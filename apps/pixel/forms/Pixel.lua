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

local TILE_MIN, TILE_MAX = 8, 64
local TILE_COLOR, PICKED_COLOR = "#2f6fd8", "#ff9f1a"

local CHECK_LIGHT, CHECK_DARK = "#ffffff", "#d4d4d4"
local TOOL_OFF, TOOL_ON = "#e4e4e4", "#9cc4ff"

local s = session.new(picture.new(32, 32, "pico"))
local path -- the file the picture was opened from or saved to
local zoom = 12
local grid = true
local advanced = false -- the Advanced menu is there, with the tilemap grid in it
local tiles = false    -- the tilemap grid is shown, and drawing keeps to a tile
local tileSize = 16    -- a tile's side, from TILE_MIN to TILE_MAX
local focus = false    -- only the tile picked is shown, big, to draw in
local zoomBefore       -- the zoom to go back to when focus is left
local hover -- the picture pixel under the mouse, as { x, y }
local note  -- what the last tile command did, shown in the status until the mouse moves

local toolButtons = {
  pen = frm.cmdPen, brush = frm.cmdBrush, eraser = frm.cmdEraser,
  fill = frm.cmdFill, line = frm.cmdLine, rect = frm.cmdRect,
  ellipse = frm.cmdEllipse, picker = frm.cmdPicker, hand = frm.cmdHand,
}

---------------------------------------------------------------- drawing

local function colorOf(pal, c)
  return palettes.hex(pal[c] or { 0, 0, 0 })
end

-- checkerboard is an image with a square for each pixel of a w by h
-- picture, drawn under it to show where it is transparent. It is made
-- again only when the size changes (one for the picture, and one for the
-- tile in focus).
local checkers, checkerCount = {}, 0
local function checkerboard(w, h)
  local key = w .. "x" .. h
  local checker = checkers[key]
  if not checker then
    if checkerCount >= 4 then checkers, checkerCount = {}, 0 end
    checkerCount = checkerCount + 1
    checker = png.new(w, h, CHECK_LIGHT)
    for y = 0, h - 1 do
      for x = (y + 1) % 2, w - 1, 2 do checker:set(x, y, CHECK_DARK) end
    end
    checkers[key] = checker
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

-- view is the part of the picture shown: all of it, or the tile in focus.
-- It is the left and top pixel, and the width and height in pixels.
local function view()
  local k = focus and s:selectedBox()
  if k then return k[1], k[2], k[3] - k[1] + 1, k[4] - k[2] + 1 end
  return 0, 0, s.pic.w, s.pic.h
end

function frm.cnvImage:onDraw(g)
  local pic = s.pic
  local vx, vy, vw, vh = view()
  if focus then
    local k = s:selectedBox()
    drawPicture(g, { w = vw, h = vh, img = pic:cropImage(k) }, 0, 0, vw * zoom, vh * zoom)
  else
    drawPicture(g, pic, 0, 0, pic.w * zoom, pic.h * zoom)
  end
  -- The shape being dragged out, before it is drawn for real.
  local pal = palettes.get(pic.palette)
  local st = s.stroke
  if st then
    g:color(st.color == CLEAR and CHECK_DARK or colorOf(pal, st.color))
    s:shape(function(x, y)
      if pic:inside(x, y) and x >= vx and y >= vy and x < vx + vw and y < vy + vh then
        g:fill((x - vx) * zoom, (y - vy) * zoom, zoom, zoom)
      end
    end)
  end
  if grid and zoom >= 6 then
    g:color("#bdbdbd")
    local W, H = vw * zoom, vh * zoom
    for x = 1, vw - 1 do g:line(x * zoom, 0, x * zoom, H - 1) end
    for y = 1, vh - 1 do g:line(0, y * zoom, W - 1, y * zoom) end
  end
  -- A tilemap's tiles: a line between them, the tile the mouse is in, and
  -- the tile picked, which copying and the like work on.
  if tiles and not focus and zoom >= 2 then
    local W, H = pic.w * zoom, pic.h * zoom
    g:color(TILE_COLOR)
    g:width(2)
    for x = tileSize, pic.w - 1, tileSize do g:line(x * zoom, 0, x * zoom, H - 1) end
    for y = tileSize, pic.h - 1, tileSize do g:line(0, y * zoom, W - 1, y * zoom) end
    local k = hover and pic:inside(hover[1], hover[2]) and s:tileBox(hover[1], hover[2])
    if k then g:rect(k[1] * zoom, k[2] * zoom, (k[3] - k[1] + 1) * zoom, (k[4] - k[2] + 1) * zoom) end
    k = s:selectedBox()
    if k then
      g:color(PICKED_COLOR)
      g:width(3)
      g:rect(k[1] * zoom + 1, k[2] * zoom + 1, (k[3] - k[1] + 1) * zoom - 2, (k[4] - k[2] + 1) * zoom - 2)
    end
    g:width(1)
  end
  -- The pixel under the mouse.
  if s.tool ~= "hand" and hover and hover[1] >= vx and hover[2] >= vy and hover[1] < vx + vw and hover[2] < vy + vh and zoom >= 4 then
    g:color("#000000")
    g:rect((hover[1] - vx) * zoom, (hover[2] - vy) * zoom, zoom, zoom)
  end
end

-- previewBox is where the preview puts the picture in its w by h: the left
-- and top, the width and height, and how many units a pixel is. It is as
-- big as fits, in whole multiples of its size while it fits at all.
local function previewBox(w, h)
  local pic = s.pic
  local scale = math.min(w / pic.w, h / pic.h)
  if scale >= 1 then scale = math.floor(scale) end -- whole multiples, while they fit
  local pw, ph = math.max(1, math.floor(pic.w * scale)), math.max(1, math.floor(pic.h * scale))
  return math.floor((w - pw) / 2), math.floor((h - ph) / 2), pw, ph, scale
end

-- The preview also shows the tiles, and the one picked, when there are
-- tiles; a click or a drag in it picks a tile and looks at it in focus.
function frm.cnvPreview:onDraw(g)
  local w, h = g:size()
  g:color("#9a9a9a")
  g:fill(0, 0, w, h)
  local pic = s.pic
  local x, y, pw, ph, scale = previewBox(w, h)
  drawPicture(g, pic, x, y, pw, ph)
  if tiles then
    g:color(TILE_COLOR)
    for tx = tileSize, pic.w - 1, tileSize do g:line(x + math.floor(tx * scale), y, x + math.floor(tx * scale), y + ph - 1) end
    for ty = tileSize, pic.h - 1, tileSize do g:line(x, y + math.floor(ty * scale), x + pw - 1, y + math.floor(ty * scale)) end
    local k = s:selectedBox()
    if k then
      g:color(PICKED_COLOR)
      g:width(2)
      g:rect(x + math.floor(k[1] * scale), y + math.floor(k[2] * scale),
        math.floor((k[3] - k[1] + 1) * scale), math.floor((k[4] - k[2] + 1) * scale))
      g:width(1)
    end
  end
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
  if tiles then
    local col, row = s:tileCoords()
    parts[#parts + 1] = ("tiles %d × %d, tile #%d of %d (%d,%d) picked%s"):format(tileSize, tileSize,
      s:tileNumber(), s:tileCount(), col, row, focus and ", in focus" or "")
  end
  if hover and pic:inside(hover[1], hover[2]) then
    local c = pic:get(hover[1], hover[2])
    parts[#parts + 1] = ("x %d, y %d: %s"):format(hover[1], hover[2],
      c == CLEAR and "transparent" or ("%d %s"):format(c, colorOf(palettes.get(pic.palette), c)))
    if tiles then parts[#parts] = parts[#parts] .. (", in tile #%d"):format(s:tileNumber(hover[1], hover[2])) end
  end
  if note then parts[#parts + 1] = note end
  frm.lblStatus.caption = table.concat(parts, "      ")
end

local function updateTools()
  for name, b in pairs(toolButtons) do
    b.color = name == s.tool and TOOL_ON or TOOL_OFF
  end
  frm.cnvImage.pointer = s.tool == "hand" and "hand" or "default"
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
  local _, _, vw, vh = view()
  return math.max(1, math.floor(MAX_VIEW / math.max(vw, vh)))
end

local function setZoom(z)
  local _, _, vw, vh = view()
  zoom = math.max(ZOOMS[1], math.min(ZOOMS[#ZOOMS], maxZoom(), z))
  frm.cnvImage.width = vw * zoom
  frm.cnvImage.height = vh * zoom
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
  local _, _, vw, vh = view()
  for _, z in ipairs(ZOOMS) do
    if vw * z <= w and vh * z <= h then best = z end
  end
  setZoom(best)
end

---------------------------------------------------------------- the mouse

local function cell(x, y)
  local vx, vy = view()
  return vx + math.floor(x / zoom), vy + math.floor(y / zoom)
end

-- The right button picks up colours as long as it is held.
local picking = false
-- The hand: where it took hold, as the canvas's own x, y, and whether it
-- has moved since.
local grab

function frm.cnvImage:onMouseDown(x, y, button)
  if button == 2 then
    -- The middle button picks a tile without drawing in it.
    local px, py = cell(x, y)
    if s:selectTile(px, py) then frm.refresh() end
    return
  end
  local px, py = cell(x, y)
  picking = button == 3
  if s.tool == "hand" and button == 1 then
    grab = { x = x, y = y, moved = false }
    return
  end
  s:press(px, py, button)
  hover = { px, py }
  frm.refresh()
end

function frm.cnvImage:onMouseDrag(x, y)
  if grab then
    -- The canvas moves under the mouse as it scrolls, so its x, y stay
    -- where they were taken hold: what is left of them is how far to go.
    local dx, dy = x - grab.x, y - grab.y
    if dx ~= 0 or dy ~= 0 then
      grab.moved = true
      frm.scrImage.scrollX = frm.scrImage.scrollX - dx
      frm.scrImage.scrollY = frm.scrImage.scrollY - dy
    end
    return
  end
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
  if grab then
    -- A click with the hand, with no dragging, picks the tile.
    local clicked = not grab.moved
    grab = nil
    if clicked and s:selectTile(px, py) then frm.refresh() end
    return
  end
  if picking then picking = false return end
  s:release(px, py)
  frm.refresh()
end

function frm.cnvImage:onMouseMove(x, y)
  local px, py = cell(x, y)
  if hover and hover[1] == px and hover[2] == py then return end
  note = nil
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
  focus = false
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
  focus = false
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
  O  ellipse     I  picker        H  hand

The hand drags the picture around, and a click with it picks a tile
(see Advanced). The left button draws. The right button picks up the colour under
it, with any tool, as the picker does. [ and ] change the brush size.
Escape drops a line or shape while it is being dragged.

Zoom: Cmd = and Cmd -, or Cmd 0 to fit.
Undo: Cmd Z, redo: Cmd Shift Z.

Advanced: View > Advanced Features adds an Advanced menu. Its tilemap
grid draws the lines between tiles of 8 x 8 up to 64 x 64 pixels (Tile
Size...), and keeps every tool to the tile it starts in: a stroke or shape
stops at the tile's edge, and a fill goes no further.

Tiles are numbered along the rows from #0 at the top left, and the status
line says which is picked, and which the mouse is in.

The tile with the orange frame is the one picked: the one you last drew
in, a click with the hand tool, or a middle-click. Clicking in the preview
at the right picks a tile too, and looks at it in focus. Advanced > Copy, Cut, Paste and Clear Tile
(Cmd Shift C, X, V and Backspace) work on it. Focus on Tile (Cmd T) shows
only that tile, as big as fits, to draw in; the arrow keys move to the
next tile, and Escape comes back out.

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

-- The Advanced menu comes and goes with the View menu's toggle. It is the
-- layout's menus with this one before Help. The tile commands are there
-- only while the tilemap grid is shown, and Paste when a tile was copied.
local baseMenus = frm.Menu1.items

local function advancedMenu()
  return { "Ad&vanced", {
    { "Show &Tilemap Grid", checked = tiles, name = "mnuTiles" },
    { "Tile &Size...", name = "mnuTileSize" },
    "-",
    { "&Copy Tile", name = "mnuTileCopy", shortcut = "Cmd+Shift+C", enabled = tiles },
    { "Cu&t Tile", name = "mnuTileCut", shortcut = "Cmd+Shift+X", enabled = tiles },
    { "&Paste Tile", name = "mnuTilePaste", shortcut = "Cmd+Shift+V", enabled = tiles and s.tileClip ~= nil },
    { "C&lear Tile", name = "mnuTileClear", shortcut = "Cmd+Shift+Backspace", enabled = tiles },
    "-",
    { "&Focus on Tile", name = "mnuFocus", shortcut = "Cmd+T", checked = focus, enabled = tiles },
  } }
end

-- setChecked puts the tick of the menu item called name as on says.
local function setChecked(list, name, on)
  for _, it in ipairs(list) do
    if type(it) == "table" then
      if it.name == name then it.checked = on end
      if type(it[2]) == "table" then setChecked(it[2], name, on) end
    end
  end
end

local function showMenus()
  local items = {}
  for _, m in ipairs(baseMenus) do
    if m[1] == "&Help" and advanced then items[#items + 1] = advancedMenu() end
    items[#items + 1] = m
  end
  setChecked(items, "mnuGrid", grid)
  setChecked(items, "mnuAdvanced", advanced)
  frm.Menu1.items = items
end

-- setFocus shows only the tile picked, as big as fits, to draw in; or the
-- whole picture again, at the zoom it had.
local function setFocus(on)
  if on == focus then return end
  if on then
    zoomBefore = zoom
    focus = true
    zoomToFit()
  else
    focus = false
    setZoom(zoomBefore or zoom)
  end
  showMenus()
end

-- previewPick picks the tile under a point of the preview and looks at it
-- in focus; with no tiles, a click there does nothing.
local function previewPick(x, y)
  if not tiles then return end
  local ox, oy, _, _, scale = previewBox(frm.cnvPreview.width, frm.cnvPreview.height)
  local before = s:tileNumber()
  if not s:selectTile(math.floor((x - ox) / scale), math.floor((y - oy) / scale)) then return end
  if not focus then
    setFocus(true)
  elseif s:tileNumber() ~= before then
    zoomToFit()
  else
    frm.refresh()
  end
end

frm.cnvPreview.onMouseDown = function(_, x, y) previewPick(x, y) end
frm.cnvPreview.onMouseDrag = function(_, x, y) previewPick(x, y) end

-- setTiles shows the tilemap grid, and keeps drawing to a tile, or not.
local function setTiles(on)
  if not on then setFocus(false) end
  tiles = on
  s.tile = on and tileSize or nil
  showMenus()
end

-- setAdvanced shows the Advanced menu, or takes it away with what it did.
local function setAdvanced(on)
  advanced = on
  if not on then setTiles(false) end
  showMenus()
end

local function setTileSize(n)
  tileSize = math.max(TILE_MIN, math.min(TILE_MAX, math.floor(n)))
  if tiles then s.tile = tileSize end
  if focus then zoomToFit() end
end

local function askTileSize()
  local answer = gui.inputbox(("A tile's side in pixels, from %d to %d."):format(TILE_MIN, TILE_MAX),
    "Tile Size", tostring(tileSize))
  if not answer then return end
  local n = tonumber(answer:match("^%s*(%d+)%s*$") or answer:match("^%s*(%d+)%s*[xX×]%s*%d+%s*$"))
  if not n or n < TILE_MIN or n > TILE_MAX then
    gui.msgbox(("A tile's side is a number from %d to %d, as 16."):format(TILE_MIN, TILE_MAX), "ok", "Tile Size")
    return
  end
  setTileSize(n)
  if not tiles then setTiles(true) end
end

-- What the tile commands do, each with the status line saying so.
local function tileNote(what)
  local col, row = s:tileCoords()
  return ("%s tile #%d (%d,%d)"):format(what, s:tileNumber(), col, row)
end

local tileActions = {
  mnuTileCopy = function() if s:copyTile() then note = tileNote("Copied"); showMenus() end end,
  mnuTileCut = function() if s:cutTile() then note = tileNote("Cut"); showMenus() end end,
  mnuTilePaste = function() if s:pasteTile() then note = tileNote("Pasted into") end end,
  mnuTileClear = function() if s:clearTile() then note = tileNote("Cleared") end end,
}

function frm.Menu1:onClick(name, caption, checked)
  if name == "mnuGrid" then
    grid = checked
  elseif name == "mnuAdvanced" then
    setAdvanced(checked)
  elseif name == "mnuTiles" then
    setTiles(checked)
  elseif name == "mnuTileSize" then
    askTileSize()
  elseif name == "mnuFocus" then
    setFocus(checked)
  elseif tileActions[name] then
    tileActions[name]()
  elseif actions[name] then
    actions[name]()
  end
  frm.refresh()
end

local keyTools = { p = "pen", b = "brush", e = "eraser", f = "fill", l = "line", r = "rect", o = "ellipse", i = "picker", h = "hand" }

-- stepTile moves to the tile beside the one in focus.
local function stepTile(dx, dy)
  if s:moveTile(dx, dy) then zoomToFit() end
end

local arrows = { Left = { -1, 0 }, Right = { 1, 0 }, Up = { 0, -1 }, Down = { 0, 1 } }

function frm:onKey(key, text)
  if key == "Escape" then
    if s.stroke then
      s:cancel()
      frm.refresh()
    elseif focus then
      setFocus(false)
    end
    return true -- Escape does not close the window
  end
  if focus and arrows[key] then
    stepTile(arrows[key][1], arrows[key][2])
    return true
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
frm.tileSize = function() return tileSize end
frm.setTileSize = setTileSize
frm.advanced = function() return advanced, tiles end

return frm
