-- tlua -p apps/pixel -p tests tests/pixel_test.lua

local t = require "testing"
local palettes = require "palettes"
local picture = require "picture"
local png = require "png" -- tlua's own module
local session = require "session"
local test, eq, ok = t.test, t.eq, t.ok
local CLEAR = picture.CLEAR

-- art draws a picture as text, a row a line: "." transparent, a hex digit
-- a colour.
local function art(p)
  local lines = {}
  for y = 0, p.h - 1 do
    local row = {}
    for x = 0, p.w - 1 do
      local c = p:get(x, y)
      row[#row + 1] = c == CLEAR and "." or ("%x"):format(c)
    end
    lines[#lines + 1] = table.concat(row)
  end
  return table.concat(lines, "\n")
end

local function rows(...) return table.concat({ ... }, "\n") end

---------------------------------------------------------------- palettes

test("palettes: sizes", function()
  eq(palettes.size(palettes.pico), 32)
  eq(palettes.size(palettes.vga), 256)
end)

test("palettes: colours", function()
  eq(palettes.hex(palettes.pico[8]), "#ff004d")
  eq(palettes.hex(palettes.pico[31]), "#ff9d81")
  eq(palettes.hex(palettes.vga[1]), "#0000aa")
  eq(palettes.hex(palettes.vga[31]), "#ffffff")  -- the last grey
  eq(palettes.hex(palettes.vga[32]), "#0000ff")  -- the first hue
  eq(palettes.hex(palettes.vga[40]), "#ff0000")
  eq(palettes.hex(palettes.vga[255]), "#000000")
end)

test("palettes: nearest", function()
  eq(palettes.nearest(palettes.pico, 255, 0, 77), 8)
  eq(palettes.nearest(palettes.vga, 255, 255, 255), 15)
end)

---------------------------------------------------------------- shapes

test("line", function()
  local p = picture.new(5, 3)
  p:line(0, 0, 4, 2, 1)
  eq(art(p), rows("1....", ".11..", "...11"))
end)

test("rect outline and filled", function()
  local p = picture.new(4, 4)
  p:rect(3, 3, 0, 0, 2, false)
  eq(art(p), rows("2222", "2..2", "2..2", "2222"))
  p:rect(1, 1, 2, 2, 3, true)
  eq(art(p), rows("2222", "2332", "2332", "2222"))
end)

test("ellipse", function()
  local p = picture.new(7, 5)
  p:ellipse(0, 0, 6, 4, 1, false)
  eq(art(p), rows("..111..", ".1...1.", "1.....1", ".1...1.", "..111.."))
  p:ellipse(0, 0, 6, 4, 2, true)
  eq(art(p), rows("..222..", ".22222.", "2222222", ".22222.", "..222.."))
end)

test("brush sizes", function()
  local p = picture.new(5, 5)
  p:plot(2, 2, 1, 1)
  eq(art(p), rows(".....", ".....", "..1..", ".....", "....."))
  p:clear()
  p:plot(2, 2, 1, 3)
  eq(art(p), rows(".....", "..1..", ".111.", "..1..", "....."))
  p:clear()
  p:plot(2, 2, 1, 5)
  eq(art(p), rows(".111.", "11111", "11111", "11111", ".111."))
  p:clear()
  p:plot(1, 1, 1, 4)
  eq(art(p), rows(".11..", "1111.", "1111.", ".11..", "....."))
end)

test("plotting off the edge is safe", function()
  local p = picture.new(2, 2)
  p:plot(-5, 9, 1, 3)
  p:line(-3, -3, 5, 5, 1)
  eq(art(p), rows("1.", ".1"))
end)

test("fill", function()
  local p = picture.new(5, 4)
  p:rect(0, 0, 4, 3, 1, false)
  p:set(2, 1, 1)
  eq(p:fill(1, 1, 2), 5)
  eq(art(p), rows("11111", "12121", "12221", "11111"))
  eq(p:fill(1, 1, 2), 0) -- the same colour changes nothing
  eq(p:fill(9, 9, 2), 0) -- nor does outside
end)

test("fill does not leak through corners", function()
  local p = picture.new(3, 3)
  p:line(0, 2, 2, 0, 1)
  p:fill(0, 0, 2)
  eq(art(p), rows("221", "21.", "1.."))
end)

test("fill a big area", function()
  local p = picture.new(256, 256)
  eq(p:fill(100, 100, 3), 256 * 256)
end)

test("flip", function()
  local p = picture.new(3, 2)
  p:set(0, 0, 1); p:set(2, 1, 2)
  p:flipH()
  eq(art(p), rows("..1", "2.."))
  p:flipV()
  eq(art(p), rows("2..", "..1"))
end)

test("resize keeps the top left", function()
  local p = picture.new(2, 2, "pico", 1)
  p:resize(3, 1)
  eq(art(p), "11.")
end)

test("convert to another palette", function()
  local p = picture.new(2, 1, "pico")
  p:set(0, 0, 7) -- #fff1e8, nearly white
  p:convert("vga")
  eq(p.palette, "vga")
  eq(p:get(0, 0), 15)
  eq(p:get(1, 0), CLEAR)
end)

test("the image follows the indices", function()
  local p = picture.new(3, 2, "pico")
  p:set(1, 0, 8)
  eq(select(1, p.img:get(1, 0)), 255); eq(select(4, p.img:get(1, 0)), 255)
  eq(select(4, p.img:get(0, 0)), 0) -- transparent
  p:fill(0, 1, 12)
  eq(table.concat({ p.img:get(2, 1) }, ","), "41,173,255,255")
  p:flipH()
  eq(table.concat({ p.img:get(1, 0) }, ","), "255,0,77,255")
  p:convert("vga")
  local r, g, b = p.img:get(1, 0)
  local e = palettes.vga[p:get(1, 0)]
  eq(("%d,%d,%d"):format(r, g, b), ("%d,%d,%d"):format(e[1], e[2], e[3]))
  p:resize(5, 5)
  eq(p.img.width, 5)
end)

test("undo restores the image too", function()
  local p = picture.new(2, 1, "pico")
  local snap = p:snapshot()
  p:set(0, 0, 7)
  p:restore(snap)
  eq(select(4, p.img:get(0, 0)), 0)
end)

---------------------------------------------------------------- files

local function roundTrip(p, prefer)
  local file = os.tmpname() .. ".png"
  assert(p:save(file))
  local img = assert(png.load(file))
  os.remove(file)
  return picture.fromImage(img, prefer)
end

test("save and open keeps the palette", function()
  local p = picture.new(4, 3, "vga")
  p:set(1, 1, 200); p:set(2, 2, 40)
  local q, exact = roundTrip(p, "pico")
  ok(exact, "every colour found")
  eq(q.palette, "vga")
  eq(art(q), art(p))
end)

test("a PICO-8 picture opens as PICO-8", function()
  local p = picture.new(2, 2, "pico", 8)
  local q, exact = roundTrip(p, "vga")
  ok(exact, "found")
  eq(q.palette, "pico")
  eq(q:get(1, 1), 8)
end)

test("the palette in use is tried first", function()
  local p = picture.new(1, 1, "pico", 0) -- black is in both
  eq(roundTrip(p, "vga").palette, "vga")
  eq(roundTrip(p, "pico").palette, "pico")
end)

test("other colours become the nearest", function()
  local img = png.new(2, 1)
  img:set(0, 0, 250, 2, 80, 255)  -- nearly PICO-8's 8
  img:set(1, 0, 10, 10, 10, 100)  -- mostly transparent
  local q, exact = picture.fromImage(img, "pico")
  ok(not exact, "not exact")
  eq(q:get(0, 0), 8)
  eq(q:get(1, 0), CLEAR)
end)

test("too big a picture is refused", function()
  local q, err = picture.fromImage(png.new(picture.MAX + 1, 1), "pico")
  eq(q, nil); ok(err:find("draws up to"), "says why")
end)

---------------------------------------------------------------- session

test("session: pen stroke with undo and redo", function()
  local s = session.new(picture.new(4, 2, "pico"))
  s.color = 1
  s:press(0, 0, 1); s:drag(3, 0); s:release(3, 0)
  eq(art(s.pic), rows("1111", "...."))
  ok(s.dirty, "dirty")
  ok(s:undo(), "undone")
  eq(art(s.pic), rows("....", "...."))
  ok(s:redo(), "redone")
  eq(art(s.pic), rows("1111", "...."))
  ok(not s:redo(), "nothing more to redo")
end)

test("session: the right button picks, whatever the tool", function()
  local s = session.new(picture.new(3, 1, "pico", 5))
  s:setTool("brush")
  s.color = 2
  s:press(0, 0, 3); s:release(0, 0)
  eq(s.color, 5)
  eq(art(s.pic), "555") -- nothing drawn
  eq(s.tool, "brush")
  ok(not s:canUndo(), "nothing to undo")
  s:setTool("eraser"); s.size = 1
  s:press(2, 0, 1); s:release(2, 0)
  eq(art(s.pic), "55.")
  s:press(2, 0, 3)
  eq(s.color, CLEAR) -- transparent is picked up too
end)

test("session: shapes are drawn on release", function()
  local s = session.new(picture.new(3, 3, "pico"))
  s.color = 4
  s:setTool("rect")
  s:press(0, 0, 1); s:drag(2, 2)
  eq(art(s.pic), rows("...", "...", "..."))
  local n = 0
  s:shape(function() n = n + 1 end)
  eq(n, 8)
  s:release(2, 2)
  eq(art(s.pic), rows("444", "4.4", "444"))
end)

test("session: escape drops a shape", function()
  local s = session.new(picture.new(3, 1, "pico"))
  s:setTool("line")
  s:press(0, 0, 1); s:drag(2, 0); s:cancel()
  eq(art(s.pic), "...")
  eq(s.stroke, nil)
  ok(not s:canRedo(), "the dropped shape is not redone")
end)

test("session: fill and picker", function()
  local s = session.new(picture.new(3, 1, "pico", 9))
  s:setTool("fill"); s.color = 3
  s:press(1, 0, 1)
  eq(art(s.pic), "333")
  s:setTool("picker")
  s.color = 0
  s:press(0, 0, 1)
  eq(s.color, 3)
  eq(s.tool, "fill") -- back to the tool before
end)

test("session: palette change converts the colour in hand", function()
  local s = session.new(picture.new(1, 1, "pico", 7))
  s.color = 8
  s:convert("vga")
  eq(s.pic.palette, "vga")
  eq(s.color, palettes.nearest(palettes.vga, 255, 0, 77))
  s:undo()
  eq(s.pic.palette, "pico")
end)

---------------------------------------------------------------- the form

-- Built without being shown; the mouse is its handlers fired with screen
-- coordinates, as FLTK would call them.
local frm = require "forms.Pixel"
local s = frm.session()

test("form: draws with the mouse", function()
  frm.setZoom(8)
  s.color = 12
  frm.cmdPen:fire("onClick")
  eq(s.tool, "pen")
  eq(frm.cmdPen.color, "#9cc4ff")
  frm.cnvImage:fire("onMouseDown", 8 * 2 + 3, 8 * 5 + 1, 1, false, "")
  frm.cnvImage:fire("onMouseDrag", 8 * 6, 8 * 5)
  frm.cnvImage:fire("onMouseUp", 8 * 6, 8 * 5, 1)
  for x = 2, 6 do eq(s.pic:get(x, 5), 12, "pixel " .. x) end
  eq(frm.caption, "*Untitled - Pixel")
end)

test("form: the right button picks while it is held", function()
  s.color = 1
  frm.cnvImage:fire("onMouseDown", 8 * 0 + 1, 8 * 0 + 1, 3, false, "") -- transparent
  eq(s.color, CLEAR)
  frm.cnvImage:fire("onMouseDrag", 8 * 4 + 1, 8 * 5 + 1)  -- onto the line drawn above
  eq(s.color, 12)
  frm.cnvImage:fire("onMouseUp", 8 * 4 + 1, 8 * 5 + 1, 3)
  eq(s.pic:get(0, 0), CLEAR) -- nothing was drawn
  eq(s.tool, "pen")
end)

test("form: the transparent swatch", function()
  frm.cnvColors:fire("onMouseDown", 150, 10, 1, false, "")
  eq(s.color, CLEAR)
end)

test("form: zoom sizes the canvas", function()
  frm.setZoom(4)
  eq(frm.cnvImage.width, s.pic.w * 4)
  frm.cmdZoomIn:fire("onClick")
  eq(frm.zoom(), 6)
end)

test("form: keys choose tools", function()
  frm:fire("onKey", "b", "b")
  eq(s.tool, "brush")
  eq(frm:fire("onKey", "Escape", ""), true)
end)

test("form: palette menu converts the picture", function()
  frm.Menu1:fire("onClick", "mnuVga", "", nil)
  eq(s.pic.palette, "vga")
  eq(frm.cboPalette.selected, 2)
  frm.Menu1:fire("onClick", "mnuUndo", "", nil)
  eq(s.pic.palette, "pico")
end)

test("fill and brushes keep to a box", function()
  local p = picture.new(8, 4, "pico", 0)
  eq(p:fill(1, 1, 5, { 0, 0, 3, 3 }), 16, "a box of 4 by 4")
  eq(art(p):sub(1, 9), "55550000\n", "the other half is as it was")
  eq(p:fill(6, 1, 7, { 0, 0, 3, 3 }), 0, "a start outside the box fills nothing")
  p.clip = { 4, 0, 5, 1 }
  p:rect(0, 0, 7, 3, 9, true)
  p.clip = nil
  eq(p:get(3, 0), 5); eq(p:get(4, 0), 9); eq(p:get(5, 1), 9); eq(p:get(6, 0), 0); eq(p:get(4, 2), 0)
end)

test("session: with tiles, strokes and fills stay in the tile", function()
  local s = session.new(picture.new(32, 32, "pico", 0))
  s.tile = 16
  s.color = 3
  s:setTool("fill")
  s:press(20, 5, 1)
  eq(s.pic:get(16, 0), 3); eq(s.pic:get(31, 15), 3)
  eq(s.pic:get(15, 0), 0, "not the tile beside"); eq(s.pic:get(16, 16), 0, "nor the one below")
  s:undo()
  s:setTool("pen")
  s.color = 4
  s:press(14, 8, 1)
  s:drag(20, 8)
  s:release(20, 8)
  eq(s.pic:get(15, 8), 4); eq(s.pic:get(16, 8), 0, "a stroke stops at the edge of its tile")
  s:setTool("rect")
  s.filled = true
  s.color = 6
  s:press(10, 10, 1)
  s:drag(24, 24)
  local seen = 0
  s:shape(function(x, y) if x > 15 or y > 15 then seen = seen + 1 end end)
  eq(seen, 0, "the preview is cut off too")
  s:release(24, 24)
  eq(s.pic:get(15, 15), 6); eq(s.pic:get(16, 15), 0); eq(s.pic:get(15, 16), 0)
  s.tile = nil
  s:setTool("fill")
  s.color = 8
  s:press(0, 31, 1)
  eq(s.pic:get(31, 31), 8, "without tiles it fills as far as it goes")
end)

test("session: the last tiles are as small as the picture leaves them", function()
  local s = session.new(picture.new(20, 20, "pico", 0))
  s.tile = 16
  local k = s:tileBox(18, 3)
  eq(k[1], 16); eq(k[3], 19); eq(k[2], 0); eq(k[4], 15)
end)

test("form: the Advanced menu and the tilemap grid", function()
  local function titles()
    local out = {}
    for _, m in ipairs(frm.Menu1.items) do out[#out + 1] = m[1] end
    return table.concat(out, ",")
  end
  ok(not titles():find("vanced", 1, true), "off to begin with")
  frm.Menu1:fire("onClick", "mnuAdvanced", "", true)
  ok(titles():find("Ad&vanced,&Help", 1, true), "before Help")
  local on, tiled = frm.advanced()
  ok(on and not tiled)
  eq(s.tile, nil, "tiles are off until asked for")
  frm.Menu1:fire("onClick", "mnuTiles", "", true)
  eq(s.tile, 16, "16 by 16 to begin with")
  frm.setTileSize(4); eq(frm.tileSize(), 8, "at least 8")
  frm.setTileSize(100); eq(frm.tileSize(), 64, "at most 64")
  eq(s.tile, 64, "drawing follows")
  frm.setTileSize(8)
  frm.setZoom(8)
  frm.cnvImage:snapshot() -- drawn with its tiles
  -- Asking for a size.
  local gui = require "gui"
  local inputbox, msgbox = gui.inputbox, gui.msgbox
  local reply
  gui.inputbox = function() return reply end
  gui.msgbox = function() end
  reply = "24"
  frm.Menu1:fire("onClick", "mnuTileSize", "", nil)
  eq(frm.tileSize(), 24)
  eq(s.tile, 24)
  reply = "99"
  frm.Menu1:fire("onClick", "mnuTileSize", "", nil)
  eq(frm.tileSize(), 24, "out of range: unchanged")
  reply = "16x16"
  frm.Menu1:fire("onClick", "mnuTileSize", "", nil)
  eq(frm.tileSize(), 16)
  reply = nil
  frm.Menu1:fire("onClick", "mnuTileSize", "", nil)
  eq(frm.tileSize(), 16, "cancelled")
  gui.inputbox, gui.msgbox = inputbox, msgbox
  -- Turning Advanced off takes the menu and the tiles away.
  frm.Menu1:fire("onClick", "mnuAdvanced", "", false)
  ok(not titles():find("vanced", 1, true))
  eq(s.tile, nil)
  local _, tiled2 = frm.advanced()
  ok(not tiled2)
end)

test("tiles: copy, paste and clear a box", function()
  local p = picture.new(8, 4, "pico", 0)
  p:rect(0, 0, 3, 3, 5, true)
  p:set(1, 1, CLEAR)
  local clip = p:copyBox({ 0, 0, 3, 3 })
  eq(clip.w, 4); eq(clip.h, 4); eq(clip.palette, "pico")
  p:pasteBox(4, 0, clip, { 4, 0, 7, 3 })
  eq(art(p), rows("55555555", "5.555.55", "55555555", "55555555"))
  -- Only as much as fits in the box goes down.
  local q = picture.new(8, 4, "pico", 0)
  q:pasteBox(2, 0, clip, { 4, 0, 7, 3 })
  eq(art(q), rows("00005500", "00005500", "00005500", "00005500"), "the left of it is cut off")
  p:clearBox({ 0, 0, 3, 3 })
  eq(art(p), rows("....5555", "....5.55", "....5555", "....5555"))
  -- Another palette's colours become the nearest.
  local v = picture.new(4, 4, "vga", 0)
  v:pasteBox(0, 0, clip, { 0, 0, 3, 3 })
  local e = palettes.get("pico")[5]
  local want = palettes.nearest(palettes.get("vga"), e[1], e[2], e[3])
  eq(v:get(0, 0), want); eq(v:get(1, 1), CLEAR, "transparent stays so")
  -- A part as an image of its own.
  local img = p:cropImage({ 4, 0, 7, 1 })
  eq(img.width, 4); eq(img.height, 2)
end)

test("session: tiles are picked, copied, pasted, cut and cleared", function()
  local s = session.new(picture.new(32, 32, "pico", 0))
  eq(s:selectedBox(), nil, "no tiles, no tile")
  eq(s:copyTile(), false)
  s.tile = 8
  local k = s:selectedBox()
  eq(k[1], 0); eq(k[3], 7)
  -- Drawing in a tile picks it.
  s.color = 5
  s:setTool("pen")
  s:press(18, 10, 1); s:release(18, 10)
  local col, row = s:tileCoords()
  eq(col, 2); eq(row, 1)
  eq(s:selectedBox()[1], 16)
  ok(s:selectTile(3, 30)); eq(select(2, s:tileCoords()), 3)
  ok(not s:selectTile(40, 3), "not off the picture")
  -- Moving by tiles stops at the edges.
  s:selectTile(0, 0)
  ok(not s:moveTile(-1, 0)); ok(s:moveTile(1, 0)); eq(s:tileCoords(), 1)
  ok(s:moveTile(0, 3)); ok(not s:moveTile(0, 1))
  -- Copy, paste.
  s:selectTile(16, 8)
  ok(s:copyTile())
  s:selectTile(0, 0)
  ok(s:pasteTile())
  eq(s.pic:get(2, 2), 5, "the pixel is in the tile pasted into")
  s:undo()
  eq(s.pic:get(2, 2), 0, "undone in one step")
  s:redo()
  -- Cut: gone from where it was, and still to paste.
  s:selectTile(16, 8)
  ok(s:cutTile())
  eq(s.pic:get(18, 10), CLEAR, "cut tiles are transparent")
  s:selectTile(24, 24)
  ok(s:pasteTile())
  eq(s.pic:get(26, 26), 5)
  ok(s:clearTile())
  eq(s.pic:get(26, 26), CLEAR)
  eq(s.pic:get(2, 2), 5, "other tiles are as they were")
  -- A tile at the edge is smaller, and takes what fits.
  local e = session.new(picture.new(20, 20, "pico", 0))
  e.tile = 16
  e.tileClip = picture.new(16, 16, "pico", 7):copyBox({ 0, 0, 15, 15 })
  e:selectTile(18, 3)
  ok(e:pasteTile())
  eq(e.pic:get(19, 0), 7); eq(e.pic:get(19, 15), 7); eq(e.pic:get(15, 0), 0, "not the tile beside")
  eq(e.pic:get(19, 16), 0, "nor the one below")
end)

test("form: tile commands and focus", function()
  local gui = require "gui"
  s:apply(function(p) p:clear() end)
  frm.Menu1:fire("onClick", "mnuAdvanced", "", true)
  frm.Menu1:fire("onClick", "mnuTiles", "", true)
  frm.setTileSize(8)
  frm.setZoom(4)
  local function find(name)
    local found
    local function walk(list)
      for _, it in ipairs(list) do
        if type(it) == "table" then
          if it.name == name then found = it end
          if type(it[2]) == "table" then walk(it[2]) end
        end
      end
    end
    walk(frm.Menu1.items)
    return found
  end
  ok(find("mnuTileCopy").enabled and find("mnuFocus").enabled)
  ok(not find("mnuTilePaste").enabled, "nothing copied yet")
  -- The middle button picks a tile without drawing.
  local z = frm.zoom()
  frm.cnvImage:fire("onMouseDown", 8 * z * 2 + 1, 8 * z + 1, 2, false, "")
  local col, row = s:tileCoords()
  eq(col, 2); eq(row, 1)
  eq(s.pic:get(16, 8), CLEAR, "nothing was drawn")
  -- Draw in it, copy it, paste it elsewhere.
  s.color = 5
  frm.cmdPen:fire("onClick")
  frm.cnvImage:fire("onMouseDown", z * 17 + 1, z * 9 + 1, 1, false, "")
  frm.cnvImage:fire("onMouseUp", z * 17 + 1, z * 9 + 1, 1)
  eq(s.pic:get(17, 9), 5)
  frm.Menu1:fire("onClick", "mnuTileCopy", "", nil)
  ok(find("mnuTilePaste").enabled, "Paste is there once a tile is copied")
  ok(frm.lblStatus.caption:find("Copied tile #6 (2,1)", 1, true), frm.lblStatus.caption)
  frm.cnvImage:fire("onMouseDown", 1, 1, 2, false, "")
  frm.Menu1:fire("onClick", "mnuTilePaste", "", nil)
  eq(s.pic:get(1, 1), 5)
  frm.Menu1:fire("onClick", "mnuTileClear", "", nil)
  eq(s.pic:get(1, 1), CLEAR)
  frm.Menu1:fire("onClick", "mnuUndo", "", nil)
  eq(s.pic:get(1, 1), 5, "a tile command is one step of undo")
  frm.Menu1:fire("onClick", "mnuTileCut", "", nil)
  eq(s.pic:get(1, 1), CLEAR)
  -- Focus: the tile picked, big.
  frm.cnvImage:fire("onMouseDown", 8 * z * 2 + 1, 8 * z + 1, 2, false, "")
  frm.Menu1:fire("onClick", "mnuFocus", "", true)
  local f = frm.zoom()
  ok(f > z, "bigger")
  eq(frm.cnvImage.width, 8 * f); eq(frm.cnvImage.height, 8 * f)
  frm.cnvImage:snapshot()
  s.color = 9
  frm.cnvImage:fire("onMouseDown", f * 3 + 1, f * 2 + 1, 1, false, "")
  frm.cnvImage:fire("onMouseDrag", f * 20, f * 2 + 1) -- past the tile's edge
  frm.cnvImage:fire("onMouseUp", f * 20, f * 2 + 1, 1)
  for x = 19, 23 do eq(s.pic:get(x, 10), 9, "pixel " .. x) end
  eq(s.pic:get(24, 10), CLEAR, "the stroke stops at the tile's edge")
  frm.cnvImage:snapshot()
  -- Arrows go to the next tile.
  frm:fire("onKey", "Right", "")
  eq(s:tileCoords(), 3)
  eq(frm.cnvImage.width, 8 * frm.zoom())
  frm:fire("onKey", "Left", "")
  eq(s:tileCoords(), 2)
  -- Escape comes out of focus, to the zoom it was at.
  frm:fire("onKey", "Escape", "")
  eq(frm.zoom(), z)
  eq(frm.cnvImage.width, s.pic.w * z)
  -- Turning tiles off leaves focus too.
  frm.Menu1:fire("onClick", "mnuFocus", "", true)
  frm.Menu1:fire("onClick", "mnuTiles", "", false)
  eq(frm.zoom(), z)
  frm.Menu1:fire("onClick", "mnuAdvanced", "", false)
end)

test("session: tiles are numbered along the rows", function()
  local s = session.new(picture.new(20, 20, "pico", 0))
  eq(s:tileNumber(), nil, "no tiles, no numbers"); eq(s:tileCount(), nil)
  s.tile = 8
  eq(s:tileColumns(), 3); eq(s:tileCount(), 9, "the last row and column are smaller ones")
  eq(s:tileNumber(0, 0), 0); eq(s:tileNumber(7, 7), 0); eq(s:tileNumber(8, 0), 1)
  eq(s:tileNumber(19, 3), 2); eq(s:tileNumber(0, 8), 3); eq(s:tileNumber(19, 19), 8)
  s:selectTile(10, 17)
  eq(s:tileNumber(), 7)
  local col, row = s:tileCoords()
  eq(col, 1); eq(row, 2)
  local big = session.new(picture.new(128, 128, "pico", 0))
  big.tile = 8
  eq(big:tileCount(), 256, "up to #255 in a 128 pixel square")
end)

test("session: the hand does not draw", function()
  local s = session.new(picture.new(16, 16, "pico", 0))
  s.tile = 8
  s.color = 5
  s:setTool("hand")
  s:press(10, 3, 1); s:drag(11, 3); s:release(11, 3)
  eq(s.pic:get(10, 3), 0); eq(s:canUndo(), false, "and it is nothing to undo")
  ok(s:tileNumber() == 0, "a press alone does not pick; the form picks on release")
  ok(s:selectTile(10, 3)); eq(s:tileNumber(), 1)
end)

test("form: the hand drags the picture and picks tiles", function()
  s:apply(function(p) p:clear() end)
  frm.Menu1:fire("onClick", "mnuAdvanced", "", true)
  frm.Menu1:fire("onClick", "mnuTiles", "", true)
  frm.setTileSize(8)
  frm.setZoom(4)
  local z = frm.zoom()
  local undos = #s.undoStack
  frm:fire("onKey", "h", "h")
  eq(s.tool, "hand"); eq(frm.cmdHand.color, "#9cc4ff"); eq(frm.cnvImage.pointer, "hand")
  -- A drag moves the scrollbars the other way, and draws nothing.
  frm.scrImage.scrollX, frm.scrImage.scrollY = 50, 40
  frm.cnvImage:fire("onMouseDown", 60, 60, 1, false, "")
  frm.cnvImage:fire("onMouseDrag", 45, 70)
  eq(frm.scrImage.scrollX, 65); eq(frm.scrImage.scrollY, 30)
  frm.cnvImage:fire("onMouseUp", 45, 70, 1)
  eq(#s.undoStack, undos, "nothing was drawn")
  -- A click picks the tile.
  frm.cnvImage:fire("onMouseDown", 8 * z * 3 + 1, 8 * z * 2 + 1, 1, false, "")
  frm.cnvImage:fire("onMouseUp", 8 * z * 3 + 1, 8 * z * 2 + 1, 1)
  eq(s:tileNumber(), 11, "column 3 of row 2, of 4 across")
  ok(frm.lblStatus.caption:find("tile #11 of 16 (3,2) picked", 1, true), frm.lblStatus.caption)
  frm.cnvImage:snapshot()
  frm.cmdPen:fire("onClick")
  eq(frm.cnvImage.pointer, "default")
  -- A click in the preview picks that tile, in focus.
  local pw, ph = frm.cnvPreview.width, frm.cnvPreview.height
  local scale = math.floor(math.min(pw / s.pic.w, ph / s.pic.h))
  local ox, oy = math.floor((pw - s.pic.w * scale) / 2), math.floor((ph - s.pic.h * scale) / 2)
  frm.cnvPreview:snapshot()
  frm.cnvPreview:fire("onMouseDown", ox + scale * 9, oy + scale * 2, 1, false, "")
  eq(s:tileNumber(), 1, "x 9, y 2 is in tile #1")
  ok(frm.lblStatus.caption:find("in focus", 1, true), "in focus now")
  eq(frm.cnvImage.width, 8 * frm.zoom())
  frm.cnvPreview:fire("onMouseDrag", ox + scale * 2, oy + scale * 20, 1, false, "")
  eq(s:tileNumber(), 8, "dragging goes from tile to tile")
  frm.cnvPreview:fire("onMouseUp", ox, oy, 1)
  frm:fire("onKey", "Escape", "")
  -- With no tiles, the preview does nothing.
  frm.Menu1:fire("onClick", "mnuTiles", "", false)
  frm.cnvPreview:fire("onMouseDown", ox + scale * 9, oy + scale * 2, 1, false, "")
  ok(not frm.lblStatus.caption:find("in focus", 1, true))
  frm.Menu1:fire("onClick", "mnuAdvanced", "", false)
end)

test("form: save and open again", function()
  local file = os.tmpname() .. ".png"
  local before = art(s.pic)
  ok(frm.savePath(file), "saved")
  eq(frm.caption, (file:match("[^/]+$")) .. " - Pixel")
  s:apply(function(p) p:clear() end)
  ok(frm.openPath(file), "opened")
  eq(art(frm.session().pic), before)
  eq(frm.session().dirty, false)
  os.remove(file)
end)

t.done("pixel")
