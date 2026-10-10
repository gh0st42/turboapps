-- The code behind Pixel.form.lua: the controls are fields of the form, by
-- the names the layout gives them.
--
-- The picture is drawn on cnvImage, a Canvas in a Scroll, at a whole
-- number of screen pixels a picture pixel. session.lua does the drawing
-- tools and undo; this turns the mouse and keys into its calls and draws
-- what it says. The picture keeps itself as an image from tlua's png
-- module too, which g:image draws scaled up with g:scaling("nearest"), so
-- the pixels stay sharp, over a checkerboard where it is transparent.

local gui = require "gui"
local lfs = require "lfs"
local palettes = require "palettes"
local picture = require "picture"
local png = require "png"
local session = require "session"
local newImage = require "forms.NewImage"
local frm = gui.load "Pixel" --[[@as forms.Pixel]]

local CLEAR = picture.CLEAR
local ZOOMS = { 1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48 }
-- The widest the zoomed picture may be, in screen units. tlua draws it at
-- the screen's own resolution, twice this on a Retina screen, and again
-- each time it changes, so this keeps a stroke quick.
local MAX_VIEW = 2048
local OPEN_FILTER = "Pictures\t*.{png,gif,jpg,jpeg}\nAll files\t*"
local SAVE_FILTER = "PNG images\t*.png"

local CHECK_LIGHT, CHECK_DARK = "#ffffff", "#d4d4d4"
local TOOL_OFF, TOOL_ON = "#e4e4e4", "#9cc4ff"

local s = session.new(picture.new(32, 32, "pico"))
local path -- the file the picture was opened from or saved to
local zoom = 12
local grid = true
local hover -- the picture pixel under the mouse, as { x, y }

local toolButtons = {
  pen = frm.cmdPen, brush = frm.cmdBrush, eraser = frm.cmdEraser,
  fill = frm.cmdFill, line = frm.cmdLine, rect = frm.cmdRect,
  ellipse = frm.cmdEllipse, picker = frm.cmdPicker,
}

---------------------------------------------------------------- drawing

local function colorOf(pal, c)
  return palettes.hex(pal[c] or { 0, 0, 0 })
end

-- checkerboard is an image with a square for each pixel of a w by h
-- picture, drawn under it to show where it is transparent. It is made
-- again only when the size changes.
local checker
local function checkerboard(w, h)
  if not checker or checker.width ~= w or checker.height ~= h then
    checker = png.new(w, h, CHECK_LIGHT)
    for y = 0, h - 1 do
      for x = (y + 1) % 2, w - 1, 2 do checker:set(x, y, CHECK_DARK) end
    end
  end
  return checker
end

-- drawPicture draws pic at x, y, w by h screen units, sharp, with a
-- square of the checkerboard a pixel when they are big enough to see.
local function drawPicture(g, pic, x, y, w, h)
  g:scaling("nearest")
  if w >= pic.w * 4 then
    g:image(checkerboard(pic.w, pic.h), x, y, w, h)
  else
    g:color(CHECK_LIGHT)
    g:fill(x, y, w, h)
  end
  g:image(pic.img, x, y, w, h)
end

function frm.cnvImage:onDraw(g)
  local pic = s.pic
  drawPicture(g, pic, 0, 0, pic.w * zoom, pic.h * zoom)
  -- The shape being dragged out, before it is drawn for real.
  local pal = palettes.get(pic.palette)
  local st = s.stroke
  if st then
    g:color(st.color == CLEAR and CHECK_DARK or colorOf(pal, st.color))
    s:shape(function(x, y)
      if pic:inside(x, y) then g:fill(x * zoom, y * zoom, zoom, zoom) end
    end)
  end
  if grid and zoom >= 6 then
    g:color("#bdbdbd")
    local W, H = pic.w * zoom, pic.h * zoom
    for x = 1, pic.w - 1 do g:line(x * zoom, 0, x * zoom, H - 1) end
    for y = 1, pic.h - 1 do g:line(0, y * zoom, W - 1, y * zoom) end
  end
  -- The pixel under the mouse.
  if hover and pic:inside(hover[1], hover[2]) and zoom >= 4 then
    g:color("#000000")
    g:rect(hover[1] * zoom, hover[2] * zoom, zoom, zoom)
  end
end

-- The preview shows the whole picture as big as fits, in whole multiples
-- of its size while it fits at all.
function frm.cnvPreview:onDraw(g)
  local w, h = g:size()
  g:color("#9a9a9a")
  g:fill(0, 0, w, h)
  local pic = s.pic
  local scale = math.min(w / pic.w, h / pic.h)
  if scale >= 1 then scale = math.floor(scale) end -- whole multiples, while they fit
  local pw, ph = math.max(1, math.floor(pic.w * scale)), math.max(1, math.floor(pic.h * scale))
  drawPicture(g, pic, math.floor((w - pw) / 2), math.floor((h - ph) / 2), pw, ph)
end

-- The palette is a grid of swatches: 8 across for 32 colours, 16 for 256.
local function paletteGrid()
  local pal = palettes.get(s.pic.palette)
  local n = palettes.size(pal)
  local cols = n <= 32 and 8 or 16
  local cell = math.floor(192 / cols)
  return pal, n, cols, cell
end

function frm.cnvPalette:onDraw(g)
  local w, h = g:size()
  g:color("#d8d8d8")
  g:fill(0, 0, w, h)
  local pal, n, cols, cell = paletteGrid()
  for i = 0, n - 1 do
    local x, y = (i % cols) * cell, math.floor(i / cols) * cell
    g:color(colorOf(pal, i))
    g:fill(x, y, cell, cell)
  end
  -- The colour in hand, framed.
  local c = s.color
  if c ~= CLEAR then
    local x, y = (c % cols) * cell, math.floor(c / cols) * cell
    g:width(3)
    g:color("#000000"); g:rect(x, y, cell, cell)
    g:width(1)
    g:color("#ffffff"); g:rect(x + 1, y + 1, cell - 2, cell - 2)
  end
end

function frm.cnvPalette:onMouseDown(x, y)
  local _, n, cols, cell = paletteGrid()
  local col, row = math.floor(x / cell), math.floor(y / cell)
  local i = row * cols + col
  if col < cols and i < n then
    s.color = i
    frm.refresh()
  end
end

local function swatch(g, x, y, w, h, c)
  if c == CLEAR then
    g:color(CHECK_LIGHT); g:fill(x, y, w, h)
    g:color(CHECK_DARK)
    for cy = 0, h - 1, 8 do
      for cx = 0, w - 1, 8 do
        if (cx + cy) % 16 == 0 then g:fill(x + cx, y + cy, math.min(8, w - cx), math.min(8, h - cy)) end
      end
    end
  else
    g:color(colorOf(palettes.get(s.pic.palette), c)); g:fill(x, y, w, h)
  end
  g:color("#000000"); g:rect(x, y, w, h)
end

-- cnvColors: the colour in hand, with its number and how it is written,
-- and a transparent swatch, which a click takes up to draw with.
function frm.cnvColors:onDraw(g)
  local w, h = g:size()
  g:color("#d8d8d8"); g:fill(0, 0, w, h)
  local c = s.color
  swatch(g, 0, 0, 56, 34, c)
  swatch(g, 140, 0, 52, 34, CLEAR)
  g:font("sans", 11)
  g:color("#000000")
  if c == CLEAR then
    g:text("transparent", 62, 0, 74, 34, "left")
  else
    g:text(("%d\n%s"):format(c, colorOf(palettes.get(s.pic.palette), c)), 62, 0, 74, 34, "left")
  end
  g:text("transparent", 132, 34, 68, 14, "center")
end

function frm.cnvColors:onMouseDown(x)
  if x >= 136 then
    s.color = CLEAR
    frm.refresh()
  end
end

---------------------------------------------------------------- the status

local function updateTitle()
  local name = path and (path:match("([^/\\]+)$") or path) or "Untitled"
  frm.caption = (s.dirty and "*" or "") .. name .. " - Pixel"
end

local function updateStatus()
  local pic = s.pic
  local parts = {
    ("  %d × %d"):format(pic.w, pic.h),
    palettes.titles[pic.palette],
    ("zoom %d×"):format(zoom),
  }
  if hover and pic:inside(hover[1], hover[2]) then
    local c = pic:get(hover[1], hover[2])
    parts[#parts + 1] = ("x %d, y %d: %s"):format(hover[1], hover[2],
      c == CLEAR and "transparent" or ("%d %s"):format(c, colorOf(palettes.get(pic.palette), c)))
  end
  frm.lblStatus.caption = table.concat(parts, "      ")
end

local function updateTools()
  for name, b in pairs(toolButtons) do
    b.color = name == s.tool and TOOL_ON or TOOL_OFF
  end
end

local function updatePaletteChoice()
  for i, name in ipairs(palettes.names) do
    if name == s.pic.palette then frm.cboPalette.selected = i end
  end
end

-- refresh redraws everything after the picture, the tools or the colours
-- have changed.
function frm.refresh()
  frm.cnvImage:redraw()
  frm.cnvPreview:redraw()
  frm.cnvPalette:redraw()
  frm.cnvColors:redraw()
  updateTools()
  updateTitle()
  updateStatus()
end

---------------------------------------------------------------- zoom

-- maxZoom is the most the picture can be zoomed, so that the image it is
-- shown as stays a sensible size.
local function maxZoom()
  return math.max(1, math.floor(MAX_VIEW / math.max(s.pic.w, s.pic.h)))
end

local function setZoom(z)
  zoom = math.max(ZOOMS[1], math.min(ZOOMS[#ZOOMS], maxZoom(), z))
  frm.cnvImage.width = s.pic.w * zoom
  frm.cnvImage.height = s.pic.h * zoom
  frm.refresh()
end

local function stepZoom(dir)
  if dir > 0 then
    for _, z in ipairs(ZOOMS) do
      if z > zoom and z <= maxZoom() then return setZoom(z) end
    end
  else
    for i = #ZOOMS, 1, -1 do
      if ZOOMS[i] < zoom then return setZoom(ZOOMS[i]) end
    end
  end
end

-- zoomToFit picks the biggest zoom that shows the whole picture.
local function zoomToFit()
  local w, h = frm.scrImage.width - 24, frm.scrImage.height - 24
  local best = ZOOMS[1]
  for _, z in ipairs(ZOOMS) do
    if s.pic.w * z <= w and s.pic.h * z <= h then best = z end
  end
  setZoom(best)
end

---------------------------------------------------------------- the mouse

local function cell(x, y)
  return math.floor(x / zoom), math.floor(y / zoom)
end

-- The right button picks up colours as long as it is held.
local picking = false

function frm.cnvImage:onMouseDown(x, y, button)
  if button == 2 then return end
  local px, py = cell(x, y)
  picking = button == 3
  s:press(px, py, button)
  hover = { px, py }
  frm.refresh()
end

function frm.cnvImage:onMouseDrag(x, y)
  local px, py = cell(x, y)
  if picking then
    s:pick(px, py)
    hover = { px, py }
    frm.refresh()
    return
  end
  s:drag(px, py)
  hover = { px, py }
  self:redraw()
  updateStatus()
end

function frm.cnvImage:onMouseUp(x, y)
  local px, py = cell(x, y)
  if picking then picking = false return end
  s:release(px, py)
  frm.refresh()
end

function frm.cnvImage:onMouseMove(x, y)
  local px, py = cell(x, y)
  if hover and hover[1] == px and hover[2] == py then return end
  hover = { px, py }
  self:redraw()
  updateStatus()
end

function frm.cnvImage:onMouseLeave()
  hover = nil
  self:redraw()
  updateStatus()
end

---------------------------------------------------------------- files

local function openPath(file)
  local img, err = png.load(file)
  local pic, found
  if img then
    pic, found = picture.fromImage(img, s.pic.palette)
    if not pic then err = found end
  end
  if not pic then
    gui.msgbox(("Cannot open %s.\n\n%s"):format(file, tostring(err)), "ok", "Pixel")
    return false
  end
  s:setPicture(pic)
  path = file
  -- A picture in colours of its own was given the palette's nearest: it
  -- is not the file any more, so saving it asks first.
  if not found then
    s.dirty = true
    path = nil
    gui.msgbox(("%s has colours that are not in the PICO-8 or the VGA palette, so each was given "
      .. "the nearest one in %s. Save it under a new name to keep the original."):format(
        file:match("([^/\\]+)$") or file, palettes.titles[pic.palette]), "ok", "Pixel")
  end
  updatePaletteChoice()
  zoomToFit()
  return true
end

local function savePath(file)
  if not file:lower():match("%.png$") then file = file .. ".png" end
  local ok, err = s.pic:save(file)
  if not ok then
    gui.msgbox(("Cannot save %s.\n\n%s"):format(file, tostring(err)), "ok", "Pixel")
    return false
  end
  path = file
  s.dirty = false
  updateTitle()
  return true
end

local function saveAs()
  local file = gui.savefile { title = "Save As", filter = SAVE_FILTER, file = path or "untitled.png" }
  if not file then return false end
  return savePath(file)
end

local function save()
  if path then return savePath(path) end
  return saveAs()
end

-- confirmDiscard asks to save unsaved changes; false means cancelled.
local function confirmDiscard()
  if not s.dirty then return true end
  local answer = gui.msgbox("Do you want to save the changes to this picture?", "yesnocancel", "Pixel")
  if answer == "yes" then return save() end
  return answer == "no"
end

local function newPicture()
  if not confirmDiscard() then return end
  local r = newImage.ask(s.pic.w, s.pic.h, s.pic.palette)
  if not r then return end
  local background = r.transparent and CLEAR or (r.palette == "vga" and 15 or 7) -- white
  s:setPicture(picture.new(r.width, r.height, r.palette, background))
  path = nil
  updatePaletteChoice()
  zoomToFit()
end

local function openDialog()
  if not confirmDiscard() then return end
  local file = gui.openfile { title = "Open", filter = OPEN_FILTER }
  if file then openPath(file) end
end

local function resizeCanvas()
  local answer = gui.inputbox("New size, as width x height. The picture keeps its top left corner.",
    "Resize Canvas", ("%dx%d"):format(s.pic.w, s.pic.h))
  if not answer then return end
  local w, h = answer:match("^%s*(%d+)%s*[xX×*,]%s*(%d+)%s*$")
  w, h = tonumber(w), tonumber(h)
  if not w or w < 1 or h < 1 or w > picture.MAX or h > picture.MAX then
    gui.msgbox(("A size is two numbers from 1 to %d, as 64x48."):format(picture.MAX), "ok", "Resize Canvas")
    return
  end
  s:apply(function(p) p:resize(w, h) end)
  setZoom(zoom)
end

local function setPalette(name)
  s:convert(name)
  updatePaletteChoice()
  frm.refresh()
end

---------------------------------------------------------------- tools

local function setTool(name)
  s:setTool(name)
  frm.refresh()
end

for name, b in pairs(toolButtons) do
  b.onClick = function() setTool(name) end
end

function frm.chkFilled:onChange()
  s.filled = self.checked
end

function frm.spnSize:onChange()
  s.size = math.floor(self.value)
end

function frm.cmdZoomIn:onClick() stepZoom(1) end
function frm.cmdZoomOut:onClick() stepZoom(-1) end

function frm.cboPalette:onChange()
  local name = palettes.names[self.selected]
  if name and name ~= s.pic.palette then setPalette(name) end
end

---------------------------------------------------------------- menu and keys

local help = [[Tools:
  P  pen          B  brush          E  eraser
  F  fill          L  line            R  rectangle
  O  ellipse     I  picker

The left button draws. The right button picks up the colour under
it, with any tool, as the picker does. [ and ] change the brush size.
Escape drops a line or shape while it is being dragged.

Zoom: Cmd = and Cmd -, or Cmd 0 to fit.
Undo: Cmd Z, redo: Cmd Shift Z.

Pictures are saved as PNG, with transparency. Pixel opens PNG,
GIF and JPEG: one drawn in the PICO-8 or the VGA colours comes
back in that palette, and any other has each colour matched to
the nearest in the palette in use.]]

local actions = {
  mnuNew = newPicture,
  mnuOpen = openDialog,
  mnuSave = save,
  mnuSaveAs = saveAs,
  mnuExit = function() frm:close() end,
  mnuUndo = function() s:undo() end,
  mnuRedo = function() s:redo() end,
  mnuClear = function() s:apply(function(p) p:clear(CLEAR) end) end,
  mnuFlipH = function() s:apply(function(p) p:flipH() end) end,
  mnuFlipV = function() s:apply(function(p) p:flipV() end) end,
  mnuResize = resizeCanvas,
  mnuZoomIn = function() stepZoom(1) end,
  mnuZoomOut = function() stepZoom(-1) end,
  mnuZoomFit = zoomToFit,
  mnuPico = function() setPalette("pico") end,
  mnuVga = function() setPalette("vga") end,
  mnuKeys = function() gui.msgbox(help, "ok", "Keyboard Shortcuts") end,
  mnuAbout = function()
    gui.msgbox("Pixel\n\nA small pixel art editor, made with tlua and its form designer.", "ok", "About Pixel")
  end,
}

function frm.Menu1:onClick(name, caption, checked)
  if name == "mnuGrid" then
    grid = checked
  elseif actions[name] then
    actions[name]()
  end
  frm.refresh()
end

local keyTools = { p = "pen", b = "brush", e = "eraser", f = "fill", l = "line", r = "rect", o = "ellipse", i = "picker" }

function frm:onKey(key, text)
  if key == "Escape" then
    s:cancel()
    frm.refresh()
    return true -- Escape does not close the window
  end
  if key:find("%+") then return false end -- with modifiers: the menu's
  local t = text:lower()
  if keyTools[t] then
    setTool(keyTools[t])
  elseif t == "[" or t == "]" then
    local spn = frm.spnSize
    spn.value = math.max(1, math.min(16, spn.value + (t == "]" and 1 or -1)))
    s.size = math.floor(spn.value)
  else
    return false
  end
  return true
end

function frm:onClose()
  if not confirmDiscard() then return false end
end

-- A PNG dropped on the window is opened.
function frm:onDrop(text, lines)
  local file = lines and lines[1]
  if file and lfs.attributes(file, "mode") == "file" and confirmDiscard() then
    openPath(file)
  end
end

-- What the menu shortcuts and the key above reach, the form passes on.
s.size = math.floor(frm.spnSize.value)
s.filled = frm.chkFilled.checked

-- A picture named on the command line is opened: tlua pixel.ztl sprite.png
local start = arg and arg[1]
if start and start ~= "" and lfs.attributes(start, "mode") == "file" then
  openPath(start)
else
  setZoom(zoom)
end

-- Exposed for the tests.
frm.session = function() return s end
frm.zoom = function() return zoom end
frm.setZoom = setZoom
frm.openPath = openPath
frm.savePath = savePath

return frm
