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
