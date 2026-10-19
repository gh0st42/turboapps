-- The code behind Viewer.form.lua: the controls are fields of the form, by
-- the names the layout gives them.
--
-- lstFiles lists the folder shown: its folders and the pictures the viewer
-- can show, mixed in the order of their names (folder.lua does the
-- listing). cnvImage draws the picture picked as big as fits, in the middle
-- of black (an animated GIF, PNG or WebP plays, round and round as it asks,
-- and Space stops and starts it), and splMain lets the user drag the line
-- between them. There is
-- no menu: all of it is done from the keyboard, the list's own keys moving
-- through it, and Enter or Right opening a folder, Backspace or Left
-- going up (see Keys below).

local gui = require "gui"
local lfs = require "lfs"
local png = require "png"
local folder = require "folder"
local frm = gui.load "Viewer" --[[@as forms.Viewer]]

local DELAY = 0.08 -- a picture is read this long after the list stops moving

local dir            -- the folder shown
local rows = {}      -- what lstFiles lists, a row each, as folder.list gives them (".." too)
local shown          -- the picture on show: { path =, image = } or { path =, why = }
local timer          -- waiting to read the picture picked
local playing        -- waiting to show the next frame of an animation

---------------------------------------------------------------- drawing

function frm.cnvImage:onDraw(g)
  local w, h = g:size()
  g:color("#000000")
  g:fill(0, 0, w, h)
  if not shown then return end
  local img = shown.image
  if img then
    -- As big as fits, whole, in the middle; smaller pictures grow to fit.
    local scale = math.min(w / img.width, h / img.height)
    local iw, ih = math.max(1, math.floor(img.width * scale + 0.5)), math.max(1, math.floor(img.height * scale + 0.5))
    g:scaling("smooth")
    g:image(img, math.floor((w - iw) / 2), math.floor((h - ih) / 2), iw, ih)
  else
    g:color("#8a8a8a")
    g:font("sans", 16)
    g:text(shown.why, 20, 0, w - 40, h, "center")
  end
end

---------------------------------------------------------------- the status

local function selectedRow()
  return rows[frm.lstFiles.selected]
end

local function updateStatus()
  local files, at = 0, 0
  local sel = frm.lstFiles.selected
  for i, e in ipairs(rows) do
    if not e.dir then
      files = files + 1
      if i == sel then at = files end
    end
  end
  local parts = { ("  %d %s"):format(files, files == 1 and "picture" or "pictures") }
  local e = selectedRow()
  if e and not e.dir then
    parts[1] = ("  %d of %d"):format(at, files)
    parts[#parts + 1] = e.name
    if shown and shown.image then
      parts[#parts + 1] = ("%d × %d"):format(shown.image.width, shown.image.height)
    end
    parts[#parts + 1] = folder.formatSize(e.size)
    local f = shown and shown.frames
    if f and #f > 1 then
      parts[#parts + 1] = ("frame %d of %d%s"):format(shown.index, #f, shown.paused and ", paused" or "")
    elseif f and f.truncated then
      parts[#parts + 1] = "too big to play: its first frame"
    end
  elseif e then
    parts[#parts + 1] = e.up and "up one folder" or (e.name .. "  (Enter opens it)")
  end
  parts[#parts + 1] = "F1: keys"
  frm.lblStatus.caption = table.concat(parts, "      ")
end

---------------------------------------------------------------- the picture

local function stopPlaying()
  if playing then playing:stop() end
  playing = nil
end

local advance

-- wait shows the next frame when the one shown has had its time.
local function wait()
  local f = shown and shown.frames
  if f and #f > 1 and not shown.paused then
    playing = gui.after(f[shown.index].delay, advance)
  end
end

-- advance shows the next frame of an animation. One that is to play only so
-- many times stops, on its last frame, when it has.
function advance()
  playing = nil
  local f = shown and shown.frames
  if not f or shown.paused then return end
  local i = shown.index + 1
  if i > #f then
    if f.loops ~= 0 and shown.plays >= f.loops then return end
    shown.plays = shown.plays + 1
    i = 1
  end
  shown.index, shown.image = i, f[i].image
  frm.cnvImage:redraw()
  updateStatus()
  wait()
end

-- showSelected reads the picture picked, or clears the view for a folder,
-- and starts an animation going.
local function showSelected()
  timer = nil
  stopPlaying()
  local e = selectedRow()
  if not e then
    shown = nil
  elseif e.dir then
    shown = { why = e.up and "Backspace or Enter goes up" or "Enter opens this folder" }
  else
    local frames, why = png.frames(e.path)
    if frames then
      shown = { path = e.path, frames = frames, index = 1, plays = 1, image = frames[1].image }
    else
      shown = { path = e.path, why = "Cannot show " .. e.name .. "\n\n" .. tostring(why) }
    end
  end
  frm.cnvImage:redraw()
  updateStatus()
  wait()
end

-- pause stops an animation where it is, or sets it going again (from the
-- first frame, if it had played its times).
local function pause()
  local f = shown and shown.frames
  if not f or #f < 2 then return false end
  shown.paused = not shown.paused or nil
  if shown.paused then
    stopPlaying()
  else
    if shown.index == #f and f.loops ~= 0 and shown.plays >= f.loops then
      shown.index, shown.image, shown.plays = 1, f[1].image, 1
      frm.cnvImage:redraw()
    end
    wait()
  end
  updateStatus()
  return true
end

-- picked is called when the row picked changes: the picture is read a
-- moment later, so that moving down a list of big pictures does not stop at
-- each of them.
local function picked()
  if timer then timer:stop() end
  stopPlaying()
  updateStatus()
  timer = gui.after(DELAY, showSelected)
end

-- flush reads the picture now, if it is waiting to be (for the tests).
local function flush()
  if timer then
    timer:stop()
    showSelected()
  end
end

function frm.lstFiles:onChange() picked() end

---------------------------------------------------------------- folders

local function caption(e)
  if e.up then return "..  (up one folder)" end
  return e.dir and (e.name .. "/") or e.name
end

-- open shows a folder. pick is the name to have picked, else the first
-- picture, else the first row. false and a message when it cannot be read.
local function open(path, pick)
  path = folder.normalize(path)
  local list, why = folder.list(path)
  if not list then
    gui.msgbox(("Cannot open %s.\n\n%s"):format(path, tostring(why)), "ok", "Image Viewer")
    return false
  end
  dir = path
  rows = {}
  if folder.parent(path) ~= path then
    rows[1] = { name = "..", path = folder.parent(path), dir = true, up = true }
  end
  for _, e in ipairs(list) do rows[#rows + 1] = e end
  local items, at, first = {}, nil, nil
  for i, e in ipairs(rows) do
    items[i] = caption(e)
    if pick and e.name == pick and not e.up then at = at or i end
    if not first and not e.dir then first = i end
  end
  frm.lstFiles.items = items
  frm.lstFiles.selected = at or first or (#rows > 0 and 1 or 0)
  frm.caption = ("%s - Image Viewer"):format(path == "/" and path or folder.basename(path))
  frm.lstFiles:focus()
  picked()
  return true
end

-- enter opens the folder picked.
local function enter()
  local e = selectedRow()
  if e and e.dir then
    return open(e.path, e.up and folder.basename(dir) or nil)
  end
  return false
end

-- up opens the folder this one is in, with this one picked.
local function up()
  local parent = folder.parent(dir)
  if parent == dir then return false end
  return open(parent, folder.basename(dir))
end

local function chooseFolder()
  local path = gui.choosedir { title = "Open Folder", dir = dir }
  if path then open(path) end
end

---------------------------------------------------------------- keys

local KEYS = [[Up, Down, Page Up, Page Down, Home, End   move through the list
Enter or Right    open the folder picked
Backspace or Left    go up one folder
a letter or digit    jump to the next name that starts with it
Space    stop or start an animation (GIF, PNG, WebP)
Cmd O (Ctrl O)    choose a folder to open
Cmd Up (Ctrl Up)    up one folder
F1    this help]]

-- pick picks row i (kept to the list), and shows its picture soon.
local function pick(i)
  i = math.max(1, math.min(#rows, i))
  if #rows == 0 or i == frm.lstFiles.selected then return end
  frm.lstFiles.selected = i
  picked()
end

-- A letter picks the next name that begins with it, wrapping round.
local function jump(c)
  local n, from = #rows, frm.lstFiles.selected
  for step = 1, n do
    local i = (from - 1 + step) % n + 1
    local e = rows[i]
    if not e.up and e.name:lower():sub(1, 1) == c then
      pick(i)
      return true
    end
  end
  return false
end

-- The list has Up and Down; the other keys are the form's, seen before the
-- list has them (it takes Home, End and the letters for nothing, or for
-- something else).
function frm:onKeyPreview(key, text)
  local sel = frm.lstFiles.selected
  local page = math.max(1, math.floor(frm.lstFiles.height / 18) - 1)
  local command = key:match("^Cmd%+(.+)$") or key:match("^Ctrl%+(.+)$")
  if command then
    if command:lower() == "o" then chooseFolder() return true end
    if command == "Up" then up() return true end
    return false
  elseif key == "F1" then
    gui.msgbox(KEYS, "ok", "Keyboard")
    return true
  elseif key == "Space" then
    return pause()
  elseif key == "Enter" or key == "Right" then
    local e = selectedRow()
    if e and e.dir then enter() return true end
  elseif key == "Backspace" or key == "Left" then
    up()
    return true
  elseif key == "Home" then pick(1) return true
  elseif key == "End" then pick(#rows) return true
  elseif key == "PageUp" then pick(sel - page) return true
  elseif key == "PageDown" then pick(sel + page) return true
  elseif #text == 1 and text:byte() > 32 and not key:find("%+") then
    return jump(text:lower())
  end
  return false
end

-- A folder, or a picture (whose folder is opened, with it picked), named on
-- the command line: tlua imageviewer.ztl ~/Pictures/cat.jpg
local start = arg and arg[1]
local mode = start and start ~= "" and lfs.attributes(start, "mode")
if mode == "file" then
  start = folder.normalize(start)
  open(folder.parent(start), folder.basename(start))
elseif mode == "directory" then
  open(start)
else
  open(folder.start())
end

function frm:onClose()
  if timer then timer:stop() end
  stopPlaying()
end

-- Exposed for the tests.
frm.open = open
frm.folder = function() return dir end
frm.entries = function() return rows end
frm.shown = function() return shown end
frm.flush = flush
frm.advance = function() if playing then playing:stop() playing = nil end advance() end
frm.pause = pause

return frm
