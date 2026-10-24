-- The code behind Viewer.form.lua: the controls are fields of the form, by
-- the names the layout gives them.
--
-- lstFiles lists the folder shown: its folders and the pictures the viewer
-- can show, mixed in the order of their names (folder.lua does the
-- listing). cnvImage draws the picture picked as big as fits, in the middle
-- of black, or zoomed and moved about (view.lua has the arithmetic); an
-- animated GIF, PNG or WebP plays, round and round as it asks, and Space
-- stops and starts it. splMain lets the user drag the line between the list
-- and the picture.
--
-- Enter on a picture shows it alone, on the whole screen: cnvFull, a canvas
-- over everything, drawn as cnvImage is, with the list and the status line
-- put away. There is no menu: all of it is done from the keyboard (see
-- KEYS below).

local gui = require "gui"
local lfs = require "lfs"
local png = require "png"
local folder = require "folder"
local viewmod = require "view"
local settings = require "settings"
local frm = gui.load "Viewer" --[[@as forms.Viewer]]

local DELAY = 0.08 -- a picture is read this long after the list stops moving

-- The whole program is dark, so that browsing colourful pictures in a dark
-- room is not a glare: the window and its controls, the list, and the text.
gui.colors { background = "#1e1e1e", background2 = "#141414", foreground = "#c8c8c8" }

local prefs = settings.load()
local dir            -- the folder shown
local rows = {}      -- what lstFiles lists, a row each, as folder.list gives them (".." too)
local shown          -- the picture on show: { path =, image = } or { path =, why = }
local timer          -- waiting to read the picture picked
local playing        -- waiting to show the next frame of an animation
local view = viewmod.new() -- how the picture is placed: fitted, or zoomed and moved
local fullView = false -- the picture alone, on the whole screen
local mouse          -- where the mouse last was over a canvas, for zooming round it
local grab           -- where a drag of the picture took hold
local pointer = "default"

---------------------------------------------------------------- drawing

-- canvas is the one the picture is on: the full one while it is up.
local function canvas() return fullView and frm.cnvFull or frm.cnvImage end

local function round(n) return math.floor(n + 0.5) end

-- draw paints the picture on a canvas: black, and the picture placed as the
-- view says. Zoomed past the window, only the part that shows is drawn, so
-- that a big zoom is not a big picture.
local function draw(g)
  local w, h = g:size()
  g:color("#000000")
  g:fill(0, 0, w, h)
  if not shown then return end
  local img = shown.image
  if not img then
    g:color("#8a8a8a")
    g:font("sans", 16)
    g:text(shown.why, 20, 0, w - 40, h, "center")
    return
  end
  local x, y, dw, dh = viewmod.place(view, img.width, img.height, w, h)
  local s = dw / img.width
  -- Pixels stay square once they are big enough to see.
  g:scaling(s >= 2 and "nearest" or "smooth")
  if dw <= w and dh <= h then
    g:image(img, x, y, dw, dh)
    return
  end
  local c0, c1 = math.max(0, math.floor(-x / s)), math.min(img.width, math.ceil((w - x) / s))
  local r0, r1 = math.max(0, math.floor(-y / s)), math.min(img.height, math.ceil((h - y) / s))
  if c1 > c0 and r1 > r0 then
    g:image(img:crop(c0, r0, c1 - c0, r1 - r0), round(x + c0 * s), round(y + r0 * s),
      math.max(1, round((c1 - c0) * s)), math.max(1, round((r1 - r0) * s)))
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
      local img, c = shown.image, canvas()
      parts[#parts + 1] = ("%d × %d"):format(img.width, img.height)
      parts[#parts + 1] = ("%s%d%%"):format(view.mode == "fit" and "fit " or "", viewmod.percent(view, img.width, img.height, c.width, c.height))
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
  canvas():redraw()
  updateStatus()
  wait()
end

-- showSelected reads the picture picked, or clears the view for a folder,
-- and starts an animation going.
local function showSelected()
  timer = nil
  stopPlaying()
  view = viewmod.new()
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
  canvas():redraw()
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
      canvas():redraw()
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
  prefs.last = path
  settings.save(prefs)
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

---------------------------------------------------------------- zooming

-- changed draws the picture again as the view now has it, and says so.
local function changed()
  local c = canvas()
  local img = shown and shown.image
  c:redraw()
  updateStatus()
  -- A hand over a picture that can be moved. Setting the pointer draws the
  -- canvas again, so it is only set when it changes.
  local want = (img and viewmod.movable(view, img.width, img.height, c.width, c.height)) and "hand" or "default"
  if want ~= pointer then
    pointer = want
    frm.cnvImage.pointer, frm.cnvFull.pointer = want, want
  end
end

-- zoom makes the picture bigger by factor, or smaller; mx, my is the point
-- that stays where it is (the middle without one).
local function zoom(factor, mx, my)
  local img = shown and shown.image
  if not img then return false end
  local c = canvas()
  viewmod.zoomBy(view, factor, img.width, img.height, c.width, c.height, mx, my)
  changed()
  return true
end

local function actualSize(mx, my)
  local img = shown and shown.image
  if not img then return false end
  local c = canvas()
  viewmod.actual(view, img.width, img.height, c.width, c.height, mx, my)
  changed()
  return true
end

local function fitToWindow()
  if not (shown and shown.image) then return false end
  viewmod.fit(view)
  changed()
  return true
end

-- pan moves the picture by a fraction of the window, as far as it can go.
local function pan(fx, fy)
  local img = shown and shown.image
  if not img then return false end
  local c = canvas()
  viewmod.pan(view, fx * c.width, fy * c.height, img.width, img.height, c.width, c.height)
  changed()
  return true
end

---------------------------------------------------------------- the whole screen

-- setFullView shows the picture alone, on the whole screen, or puts the
-- list and the status line back.
local function setFullView(on)
  if on == fullView then return end
  fullView = on
  if on then
    frm.cnvFull.width, frm.cnvFull.height = frm.width, frm.height
    frm.splMain.visible, frm.lblStatus.visible = false, false
    frm.cnvFull.visible = true
    frm.fullscreen = true
    frm.cnvFull:focus()
  else
    frm.fullscreen = false
    frm.cnvFull.visible = false
    frm.splMain.visible, frm.lblStatus.visible = true, true
    frm.lstFiles:focus()
  end
  changed()
end

---------------------------------------------------------------- the mouse

-- Both canvases take the mouse the same way: a drag moves a picture that is
-- bigger than the window, the wheel zooms round the mouse, and a double
-- click goes between the whole picture and its actual size there.
local function wire(c)
  c.onDraw = function(_, g) draw(g) end
  c.onMouseDown = function(_, x, y) grab = { x = x, y = y } end
  c.onMouseUp = function() grab = nil end
  c.onMouseMove = function(_, x, y) mouse = { x = x, y = y } end
  c.onMouseDrag = function(_, x, y)
    local img = shown and shown.image
    if not (grab and img) then return end
    viewmod.pan(view, x - grab.x, y - grab.y, img.width, img.height, c.width, c.height)
    grab.x, grab.y = x, y
    changed()
  end
  c.onMouseWheel = function(_, _, dy)
    if dy ~= 0 then zoom(1.25 ^ (dy < 0 and 1 or -1), mouse and mouse.x, mouse and mouse.y) end
  end
  c.onDoubleClick = function(_, x, y)
    if view.mode == "fit" then actualSize(x, y) else fitToWindow() end
  end
end

wire(frm.cnvImage)
wire(frm.cnvFull)
-- A canvas that hears keys can have the focus, which the full one needs
-- once the list is put away; every key goes on to the form's.
frm.cnvFull.onKey = function() return false end

---------------------------------------------------------------- keys

local KEYS = [[Up, Down, Page Up, Page Down, Home, End   move through the list
Enter or Right    open the folder picked; Enter on a picture shows it alone,
                  on the whole screen (Enter, Esc or F11 comes back)
Backspace or Left    go up one folder
a letter or digit    jump to the next name that starts with it
Space    stop or start an animation (GIF, PNG, WebP)
Cmd = and Cmd -    zoom in and out; the wheel does too, round the mouse
Cmd 0    fit the window    Cmd 1    actual size (so does a double click)
Shift and the arrows    move a picture bigger than the window; so does dragging
F11    the whole screen    Cmd O (Ctrl O)    choose a folder to open
Cmd Up (Ctrl Up)    up one folder
F1    this help
On the whole screen the arrows, Page Up and Down, Home and End go to the
other pictures.]]

-- pick picks row i (kept to the list), and shows its picture soon.
local function pick(i)
  i = math.max(1, math.min(#rows, i))
  if #rows == 0 or i == frm.lstFiles.selected then return end
  frm.lstFiles.selected = i
  picked()
end

-- step picks the next picture, or the one before, passing the folders.
local function step(dir_)
  local i = frm.lstFiles.selected
  repeat i = i + dir_ until i < 1 or i > #rows or not rows[i].dir
  if i >= 1 and i <= #rows then pick(i) end
end

-- ends picks the first picture, or the last, passing the folders.
local function ends(from, dir_)
  local i = from
  while i >= 1 and i <= #rows and rows[i].dir do i = i + dir_ end
  if i >= 1 and i <= #rows then pick(i) end
end

-- A letter picks the next name that begins with it, wrapping round.
local function jump(c)
  local n, from = #rows, frm.lstFiles.selected
  for s = 1, n do
    local i = (from - 1 + s) % n + 1
    local e = rows[i]
    if not e.up and e.name:lower():sub(1, 1) == c then
      pick(i)
      return true
    end
  end
  return false
end

local ARROWS = { Left = { 1, 0 }, Right = { -1, 0 }, Up = { 0, 1 }, Down = { 0, -1 } }

-- The list has Up and Down; the other keys are the form's, seen before the
-- list has them (it takes Home, End and the letters for nothing, or for
-- something else).
function frm:onKeyPreview(key, text)
  local sel = frm.lstFiles.selected
  local page = math.max(1, math.floor(frm.lstFiles.height / 18) - 1)
  local command = key:match("^Cmd%+(.+)$") or key:match("^Ctrl%+(.+)$")
  local shifted = key:match("^Shift%+(%a+)$")
  if command then
    local c = command:lower()
    if c == "o" then chooseFolder() return true end
    if command == "Up" then up() return true end
    if c == "=" or c == "+" or command == "Shift+=" or command == "Shift++" then return zoom(1.25) end
    if c == "-" then return zoom(1 / 1.25) end
    if c == "0" then return fitToWindow() end
    if c == "1" then return actualSize() end
    return false
  elseif shifted and ARROWS[shifted] then
    -- Moving a picture about; the list has no use for shifted arrows.
    return pan(ARROWS[shifted][1] / 8, ARROWS[shifted][2] / 8) or true
  elseif key == "F1" then
    gui.msgbox(KEYS, "ok", "Keyboard")
    return true
  elseif key == "F11" then
    setFullView(not fullView)
    return true
  elseif key == "Space" then
    return pause()
  elseif fullView then
    -- The list is put away: the keys that moved through it go to the pictures.
    if key == "Escape" or key == "Enter" then setFullView(false)
    elseif key == "Left" or key == "Up" or key == "PageUp" then step(-1)
    elseif key == "Right" or key == "Down" or key == "PageDown" then step(1)
    elseif key == "Home" then ends(1, 1)
    elseif key == "End" then ends(#rows, -1)
    else return false end
    return true
  elseif key == "Enter" then
    local e = selectedRow()
    if e and e.dir then enter() return true end
    if e then setFullView(true) return true end
  elseif key == "Right" then
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

-- The list was as wide as it was left.
if prefs.split >= 120 and prefs.split <= frm.splMain.width - 200 then
  frm.lstFiles.width = prefs.split
  frm.cnvImage.left = prefs.split
  frm.cnvImage.width = frm.splMain.width - prefs.split
end

-- A folder, or a picture (whose folder is opened, with it picked), named on
-- the command line: tlua imageviewer.ztl ~/Pictures/cat.jpg. Else the folder
-- last shown, else the Pictures folder.
local start = arg and arg[1]
local mode = start and start ~= "" and lfs.attributes(start, "mode")
if mode == "file" then
  start = folder.normalize(start)
  open(folder.parent(start), folder.basename(start))
elseif mode == "directory" then
  open(start)
elseif prefs.last ~= "" and lfs.attributes(prefs.last, "mode") == "directory" and open(prefs.last) then
  -- opened
else
  open(folder.start())
end

function frm:onClose()
  if timer then timer:stop() end
  stopPlaying()
  if fullView then setFullView(false) end
  prefs.split = frm.lstFiles.width
  settings.save(prefs)
end

-- Exposed for the tests.
frm.open = open
frm.folder = function() return dir end
frm.entries = function() return rows end
frm.shown = function() return shown end
frm.flush = flush
frm.advance = function() if playing then playing:stop() playing = nil end advance() end
frm.pause = pause
frm.view = function() return view end
frm.fullView = function() return fullView end
frm.setFullView = setFullView

return frm
