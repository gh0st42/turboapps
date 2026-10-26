-- tlua -p apps/imageviewer -p tests tests/imageviewer_test.lua

local t = require "testing"
local lfs = require "lfs"
local png = require "png" -- tlua's own module
local folder = require "folder"
local viewmod = require "view"
local settings = require "settings"
local test, eq, ok = t.test, t.eq, t.ok

-- The viewer's settings are a file of the tests' own, never the user's.
local settingsFile = os.tmpname()
settings.file = settingsFile

-- A folder of the tests' own: folders a, b and Misc, pictures of two sizes
-- (one named for a JPEG, to show the extension is read in any case), a file
-- that is not a picture, a hidden one, and a "picture" that is not.
local root = os.tmpname()
os.remove(root)
root = root .. "-viewer"
local function write(path, content)
  local f = assert(io.open(path, "wb"))
  f:write(content)
  f:close()
end
assert(lfs.mkdir(root))
assert(lfs.mkdir(root .. "/a"))
assert(lfs.mkdir(root .. "/b"))
assert(lfs.mkdir(root .. "/Misc"))
assert(lfs.mkdir(root .. "/.secret"))
local function picture(path, w, h, color)
  local img = png.new(w, h, color)
  assert(img:save(path))
end
picture(root .. "/img10.png", 40, 20, "#ff0000")
picture(root .. "/img2.png", 20, 40, "#00ff00")
picture(root .. "/Photo.JPG", 10, 10, "#0000ff")
picture(root .. "/a/inside.png", 8, 8, "#ffffff")
picture(root .. "/.hidden.png", 8, 8, "#ffffff")
write(root .. "/notes.txt", "not a picture")
write(root .. "/broken.png", "this is not a PNG")

local function names(list)
  local out = {}
  for i, e in ipairs(list) do out[i] = e.name end
  return table.concat(out, ",")
end

test("isImage: the formats the viewer shows, in any case", function()
  for _, name in ipairs { "a.png", "a.PNG", "a.jpg", "a.JPEG", "a.gif", "x.y.png", "a.webp", "a.WebP" } do
    ok(folder.isImage(name), name)
  end
  for _, name in ipairs { "a.txt", "png", "a.png.txt", "a.bmp", ".png", "a" } do
    ok(not folder.isImage(name) or name == ".png", name)
  end
end)

test("list: folders and pictures mixed, in the order a person counts", function()
  local list = assert(folder.list(root))
  eq(names(list), "a,b,broken.png,img2.png,img10.png,Misc,Photo.JPG")
  ok(list[1].dir and list[2].dir and not list[3].dir and list[6].dir and not list[7].dir)
  eq(list[4].size, lfs.attributes(root .. "/img2.png", "size"))
  eq(list[1].path, root .. "/a")
  local none, why = folder.list(root .. "/nowhere")
  eq(none, nil); ok(why, "and why")
end)

test("paths", function()
  eq(folder.parent("/a/b/"), "/a"); eq(folder.parent("/a"), "/"); eq(folder.parent("/"), "/")
  eq(folder.parent("C:/a"), "C:/"); eq(folder.parent("C:\\a\\b"), "C:/a")
  eq(folder.basename("/a/b/"), "b"); eq(folder.join("/a", "b"), "/a/b"); eq(folder.join("/", "b"), "/b")
  eq(folder.formatSize(12), "12 B"); eq(folder.formatSize(1536), "1.5 KB"); eq(folder.formatSize(5 * 1024 * 1024), "5.0 MB")
end)

---------------------------------------------------------------- the view

test("view: a picture fits the window, in the middle", function()
  local v = viewmod.new()
  local x, y, w, h = viewmod.place(v, 40, 20, 200, 100)
  eq(w, 200); eq(h, 100); eq(x, 0); eq(y, 0)
  x, y, w, h = viewmod.place(v, 40, 20, 200, 200)
  eq(w, 200); eq(h, 100); eq(x, 0); eq(y, 50, "taller than wide: black above and below")
  x, y, w, h = viewmod.place(v, 20, 40, 200, 100)
  eq(h, 100); eq(w, 50); eq(x, 75); eq(y, 0)
  eq(viewmod.percent(v, 40, 20, 200, 100), 500)
  ok(not viewmod.movable(v, 40, 20, 200, 100))
end)

test("view: zoom, actual size, and moving about", function()
  local v = viewmod.new()
  viewmod.actual(v, 400, 300, 200, 100)
  eq(v.mode, "zoom"); eq(viewmod.percent(v, 400, 300, 200, 100), 100)
  local x, y, w, h = viewmod.place(v, 400, 300, 200, 100)
  eq(w, 400); eq(h, 300); eq(x, -100); eq(y, -100, "the middle of the picture in the middle of the window")
  ok(viewmod.movable(v, 400, 300, 200, 100))
  -- Moving the picture 30 right shows more of its left.
  viewmod.pan(v, 30, 0, 400, 300, 200, 100)
  x = viewmod.place(v, 400, 300, 200, 100)
  eq(x, -70)
  -- It stops where its edge meets the window's.
  viewmod.pan(v, 5000, 5000, 400, 300, 200, 100)
  x, y = viewmod.place(v, 400, 300, 200, 100)
  eq(x, 0); eq(y, 0)
  viewmod.pan(v, -5000, -5000, 400, 300, 200, 100)
  x, y = viewmod.place(v, 400, 300, 200, 100)
  eq(x, -200); eq(y, -200)
  -- Zooming keeps the point under the mouse where it is.
  v = viewmod.new()
  viewmod.actual(v, 400, 300, 200, 100)
  local before = (50 - select(1, viewmod.place(v, 400, 300, 200, 100))) / 400
  viewmod.zoomBy(v, 2, 400, 300, 200, 100, 50, 20)
  x = viewmod.place(v, 400, 300, 200, 100)
  ok(math.abs((50 - x) / 800 - before) < 0.01, "the same part of the picture is at the mouse")
  eq(viewmod.percent(v, 400, 300, 200, 100), 200)
  -- Smaller than the window, it is in the middle again, and cannot be moved.
  viewmod.setZoom(v, 0.25, 400, 300, 200, 100)
  x, y, w, h = viewmod.place(v, 400, 300, 200, 100)
  eq(w, 100); eq(h, 75); eq(x, 50); eq(y, 12)
  ok(not viewmod.movable(v, 400, 300, 200, 100))
  viewmod.setZoom(v, 1000, 400, 300, 200, 100)
  eq(v.zoom, viewmod.MAX, "not past a limit")
  viewmod.fit(v)
  eq(viewmod.percent(v, 400, 300, 200, 100), 33, "100 high of 300")
  viewmod.pan(v, 10, 10, 400, 300, 200, 100)
  eq(v.mode, "fit", "a fitted picture does not move")
end)

test("settings: kept in a file, read back with nothing in its environment", function()
  local file = os.tmpname()
  settings.file = file
  local s = settings.load()
  eq(s.last, ""); eq(s.split, 0)
  ok(settings.save { last = "/a/b \"c\"", split = 321 })
  s = settings.load()
  eq(s.last, '/a/b "c"'); eq(s.split, 321)
  local f = io.open(file, "w"); f:write("os.execute('exit 1') return { last = 5, split = 'x' }"); f:close()
  s = settings.load()
  eq(s.last, ""); eq(s.split, 0, "a file that is not what it should be is ignored")
  os.remove(file)
  settings.file = settingsFile
end)

---------------------------------------------------------------- the form

-- Built without being shown. The picture is read a moment after the row
-- changes; flush reads it now.
local frm = require "forms.Viewer"
local list, canvas = frm.lstFiles, frm.cnvImage

-- pixel is the colour at x, y of the canvas as it draws.
local function pixel(x, y)
  local img = canvas:snapshot()
  local r, g, b = img:get(x, y)
  return r, g, b
end

test("form: a folder opens with the first picture picked", function()
  ok(frm.open(root))
  local rows = frm.entries()
  eq(rows[1].name, ".."); ok(rows[1].up)
  eq(names(rows), "..,a,b,broken.png,img2.png,img10.png,Misc,Photo.JPG")
  eq(list.items[2], "a/"); eq(list.items[4], "broken.png")
  eq(list.items[1], "..  (up one folder)")
  eq(list.selected, 4, "the first picture")
  frm.flush()
  ok(frm.shown().why, "broken.png is not a picture, and says so")
  ok(frm.shown().why:find("broken.png", 1, true))
  canvas:snapshot()
  eq(frm.caption, folder.basename(root) .. " - Image Viewer")
end)

test("form: the picture fills the view and keeps its shape, on black", function()
  list.selected = 6 -- img10: 40 x 20
  frm.lstFiles:fire("onChange")
  frm.flush()
  eq(frm.shown().image.width, 40)
  ok(frm.lblStatus.caption:find("40 × 20", 1, true), frm.lblStatus.caption)
  ok(frm.lblStatus.caption:find("img10.png", 1, true))
  local w, h = canvas.width, canvas.height
  local scale = math.min(w / 40, h / 20)
  local ih = math.floor(20 * scale + 0.5)
  local top = math.floor((h - ih) / 2)
  local r, g, b = pixel(math.floor(w / 2), math.floor(h / 2))
  ok(r > 200 and g < 60 and b < 60, "red in the middle: " .. r .. "," .. g .. "," .. b)
  r, g, b = pixel(math.floor(w / 2), top - 4)
  eq(r + g + b, 0, "black above it")
  r, g, b = pixel(math.floor(w / 2), top + ih + 4)
  eq(r + g + b, 0, "and below")
  r, g, b = pixel(5, math.floor(h / 2))
  ok(r > 200 and g < 60, "it reaches the sides when it is the wider")
  -- A tall one leaves black at the sides.
  list.selected = 5 -- img2: 20 x 40
  frm.lstFiles:fire("onChange")
  frm.flush()
  r, g, b = pixel(5, math.floor(h / 2))
  eq(r + g + b, 0, "black beside a tall picture")
  r, g, b = pixel(math.floor(w / 2), 5)
  ok(g > 200 and r < 60, "green to the top and bottom")
  -- A small one grows to fit.
  list.selected = 8
  frm.lstFiles:fire("onChange")
  frm.flush()
  r, g, b = pixel(math.floor(w / 2), math.floor(h / 2))
  ok(b > 200, "blue")
  local side = math.min(w, h)
  r, g, b = pixel(math.floor(w / 2 - side / 2 + 10), math.floor(h / 2))
  ok(b > 200 and r < 60, "a 10 pixel picture is as big as the view allows")
end)

test("form: the status counts the pictures", function()
  list.selected = 5
  frm.lstFiles:fire("onChange")
  frm.flush()
  ok(frm.lblStatus.caption:find("2 of 4", 1, true), frm.lblStatus.caption)
  list.selected = 2 -- a folder
  frm.lstFiles:fire("onChange")
  frm.flush()
  ok(frm.lblStatus.caption:find("a", 1, true))
  ok(frm.lblStatus.caption:find("Enter opens it", 1, true), frm.lblStatus.caption)
  eq(frm.shown().image, nil)
  canvas:snapshot()
end)

test("form: Enter and Right open a folder, Backspace and Left go up", function()
  list.selected = 2 -- a
  eq(frm:fire("onKeyPreview", "Enter", ""), true)
  eq(frm.folder(), root .. "/a")
  eq(names(frm.entries()), "..,inside.png")
  eq(list.selected, 2, "the picture in it")
  frm.flush()
  eq(frm.shown().image.width, 8)
  eq(frm:fire("onKeyPreview", "Backspace", ""), true)
  eq(frm.folder(), root)
  eq(frm.entries()[list.selected].name, "a", "the folder we came from is picked")
  eq(frm:fire("onKeyPreview", "Right", ""), true)
  eq(frm.folder(), root .. "/a")
  list.selected = 1 -- ".."
  eq(frm:fire("onKeyPreview", "Enter", ""), true)
  eq(frm.folder(), root, "Enter on .. goes up")
  eq(frm.entries()[list.selected].name, "a")
  eq(frm:fire("onKeyPreview", "Left", ""), true)
  eq(frm.folder(), folder.parent(root))
  frm.open(root)
  -- The keys the list has for itself are left to it.
  list.selected = 5
  ok(not frm:fire("onKeyPreview", "Down", ""))
  eq(frm.folder(), root)
end)

test("form: a letter picks the next name that starts with it", function()
  frm.open(root)
  list.selected = 1
  eq(frm:fire("onKeyPreview", "i", "i"), true)
  eq(frm.entries()[list.selected].name, "img2.png")
  eq(frm:fire("onKeyPreview", "i", "i"), true)
  eq(frm.entries()[list.selected].name, "img10.png")
  eq(frm:fire("onKeyPreview", "i", "i"), true, "and round again")
  eq(frm.entries()[list.selected].name, "img2.png")
  eq(frm:fire("onKeyPreview", "P", "P"), true, "in either case")
  eq(frm.entries()[list.selected].name, "Photo.JPG")
  eq(frm:fire("onKeyPreview", "m", "m"), true, "folders are jumped to too")
  eq(frm.entries()[list.selected].name, "Misc")
  eq(frm:fire("onKeyPreview", "p", "p"), true)
  ok(not frm:fire("onKeyPreview", "q", "q"), "no name starts with q")
  ok(not frm:fire("onKeyPreview", "Cmd+i", "i"), "a shortcut is not a letter")
  ok(not frm:fire("onKeyPreview", "Space", " "))
  frm.flush()
  eq(frm.shown().image.width, 10, "and the picture follows")
end)

test("form: Home, End, Page Up and Page Down", function()
  frm.open(root)
  local last = #frm.entries()
  frm:fire("onKeyPreview", "End", "")
  eq(list.selected, last)
  frm:fire("onKeyPreview", "Home", "")
  eq(list.selected, 1)
  frm:fire("onKeyPreview", "PageDown", "")
  eq(list.selected, last, "a page is more than this folder has")
  frm:fire("onKeyPreview", "PageUp", "")
  eq(list.selected, 1)
  frm.flush()
  eq(frm.shown().image, nil, "on .., there is no picture")
  -- In an empty list the keys do nothing.
  frm.open(root .. "/b")
  frm:fire("onKeyPreview", "End", "")
  eq(list.selected, 1)
  frm.flush()
end)

test("form: the keys that were a menu's", function()
  local gui = require "gui"
  local choosedir, msgbox = gui.choosedir, gui.msgbox
  frm.open(root .. "/a")
  eq(frm:fire("onKeyPreview", "Cmd+Up", ""), true)
  eq(frm.folder(), root)
  frm.open(root .. "/a")
  eq(frm:fire("onKeyPreview", "Ctrl+Up", ""), true, "Ctrl, where there is no Cmd")
  eq(frm.folder(), root)
  gui.choosedir = function() return root .. "/b" end
  eq(frm:fire("onKeyPreview", "Cmd+o", "o"), true)
  eq(frm.folder(), root .. "/b")
  eq(#frm.entries(), 1, "an empty folder has only .. in it")
  frm.flush()
  eq(frm.shown().image, nil)
  canvas:snapshot()
  gui.choosedir = function() return nil end
  frm:fire("onKeyPreview", "Ctrl+O", "o")
  eq(frm.folder(), root .. "/b", "cancelled")
  ok(not frm:fire("onKeyPreview", "Cmd+q", "q"), "other shortcuts are left alone")
  -- F1 says the keys.
  local said
  gui.msgbox = function(text) said = text end
  eq(frm:fire("onKeyPreview", "F1", ""), true)
  ok(said and said:find("Backspace", 1, true))
  -- A folder that cannot be read is said so, and left.
  said = nil
  ok(not frm.open(root .. "/nowhere"))
  ok(said and said:find("nowhere", 1, true))
  eq(frm.folder(), root .. "/b")
  gui.choosedir, gui.msgbox = choosedir, msgbox
end)

test("form: a splitter between the list and the picture", function()
  eq(frm.lstFiles.parent, frm.splMain)
  eq(frm.cnvImage.parent, frm.splMain)
  ok(not frm.Menu1, "no menu")
  eq(frm.lstFiles.left + frm.lstFiles.width, frm.cnvImage.left, "side by side, edge to edge")
end)

---------------------------------------------------------------- zoom and the whole screen

-- pixelOf is the colour at x, y of whichever canvas is up, as it draws.
local function pixelOf(c, x, y)
  local r, g, b = c:snapshot():get(x, y)
  return r, g, b
end

test("form: zoom, actual size and fit", function()
  frm.open(root)
  list.selected = 6 -- img10: 40 x 20, red
  frm.lstFiles:fire("onChange")
  frm.flush()
  eq(frm.view().mode, "fit")
  ok(frm.lblStatus.caption:find("fit 1700%", 1, true), frm.lblStatus.caption)
  eq(frm:fire("onKeyPreview", "Cmd+1", "1"), true)
  eq(frm.view().mode, "zoom"); eq(frm.view().zoom, 1)
  ok(frm.lblStatus.caption:find("100%", 1, true) and not frm.lblStatus.caption:find("fit", 1, true), frm.lblStatus.caption)
  local w, h = canvas.width, canvas.height
  local r = pixelOf(canvas, math.floor(w / 2), math.floor(h / 2))
  ok(r > 200, "40 pixels, red, in the middle")
  r = pixelOf(canvas, math.floor(w / 2) + 60, math.floor(h / 2))
  eq(r, 0, "and black around it")
  eq(frm:fire("onKeyPreview", "Cmd+=", "="), true)
  eq(frm.view().zoom, 1.25)
  eq(frm:fire("onKeyPreview", "Ctrl+-", "-"), true)
  eq(frm.view().zoom, 1)
  eq(frm:fire("onKeyPreview", "Cmd+0", "0"), true)
  eq(frm.view().mode, "fit")
  -- Bigger than the window: only what shows is drawn, and it is the middle.
  frm:fire("onKeyPreview", "Cmd+1", "1")
  for _ = 1, 18 do frm:fire("onKeyPreview", "Cmd+=", "=") end
  ok(frm.view().zoom > 50)
  r = pixelOf(canvas, math.floor(w / 2), math.floor(h / 2))
  ok(r > 200, "still red in the middle")
  ok(frm.cnvImage.pointer == "hand", "a hand over a picture that moves")
  -- The wheel zooms, a double click goes to actual size and back.
  frm:fire("onKeyPreview", "Cmd+1", "1")
  for _ = 1, 10 do frm:fire("onKeyPreview", "Cmd+=", "=") end
  frm.cnvImage:fire("onMouseMove", 100, 100)
  local z = frm.view().zoom
  frm.cnvImage:fire("onMouseWheel", 0, -1)
  eq(frm.view().zoom, z * 1.25)
  frm.cnvImage:fire("onMouseWheel", 0, 1)
  eq(frm.view().zoom, z)
  frm.cnvImage:fire("onDoubleClick", 50, 50)
  eq(frm.view().mode, "fit")
  frm.cnvImage:fire("onDoubleClick", math.floor(w / 2), math.floor(h / 2))
  eq(frm.view().mode, "zoom"); eq(frm.view().zoom, 1)
  ok(frm.cnvImage.pointer == "default", "nothing to move at 100% of a small picture")
  -- Another picture starts fitted again.
  list.selected = 5
  frm.lstFiles:fire("onChange")
  frm.flush()
  eq(frm.view().mode, "fit")
end)

test("form: a picture bigger than the window is moved by dragging and Shift and the arrows", function()
  list.selected = 6
  frm.lstFiles:fire("onChange")
  frm.flush()
  frm:fire("onKeyPreview", "Cmd+1", "1")
  for _ = 1, 18 do frm:fire("onKeyPreview", "Cmd+=", "=") end
  local cx = frm.view().cx
  frm.cnvImage:fire("onMouseDown", 200, 200, 1, false, "")
  frm.cnvImage:fire("onMouseDrag", 150, 200)
  ok(frm.view().cx > cx, "dragging left shows more of the right")
  frm.cnvImage:fire("onMouseUp", 150, 200, 1)
  cx = frm.view().cx
  eq(frm:fire("onKeyPreview", "Shift+Right", ""), true)
  ok(frm.view().cx > cx, "Shift and Right shows more of the right")
  cx = frm.view().cx
  eq(frm:fire("onKeyPreview", "Shift+Left", ""), true)
  ok(frm.view().cx < cx)
  local cy = frm.view().cy
  frm:fire("onKeyPreview", "Shift+Down", "")
  ok(frm.view().cy > cy)
  canvas:snapshot()
  -- Without a picture bigger than the window it moves nothing, and says it used the key.
  frm:fire("onKeyPreview", "Cmd+0", "0")
  local before = frm.view().cx
  eq(frm:fire("onKeyPreview", "Shift+Left", ""), true)
  eq(frm.view().cx, before)
end)

test("form: Enter shows the picture alone, on the whole screen", function()
  frm.open(root)
  list.selected = 5 -- img2: 20 x 40, green
  frm.lstFiles:fire("onChange")
  frm.flush()
  eq(frm.fullView(), false)
  eq(frm:fire("onKeyPreview", "Enter", ""), true)
  eq(frm.fullView(), true)
  eq(frm.fullscreen, true)
  eq(frm.cnvFull.visible, true); eq(frm.splMain.visible, false); eq(frm.lblStatus.visible, false)
  eq(frm.cnvFull.width, frm.width); eq(frm.cnvFull.height, frm.height)
  local r, g = pixelOf(frm.cnvFull, math.floor(frm.cnvFull.width / 2), 5)
  ok(g > 200 and r < 60, "the picture reaches the top and bottom")
  r, g = pixelOf(frm.cnvFull, 5, math.floor(frm.cnvFull.height / 2))
  eq(r + g, 0, "and is black beside it")
  -- The arrows go to the other pictures (not the folders).
  eq(frm.entries()[list.selected].name, "img2.png")
  frm:fire("onKeyPreview", "Right", "")
  eq(frm.entries()[list.selected].name, "img10.png")
  frm:fire("onKeyPreview", "Down", "")
  eq(frm.entries()[list.selected].name, "Photo.JPG", "past the folder Misc")
  frm:fire("onKeyPreview", "Right", "")
  eq(frm.entries()[list.selected].name, "Photo.JPG", "no more pictures")
  frm:fire("onKeyPreview", "Home", "")
  eq(frm.entries()[list.selected].name, "broken.png", "the first picture, not the folders")
  frm:fire("onKeyPreview", "End", "")
  eq(frm.entries()[list.selected].name, "Photo.JPG")
  frm:fire("onKeyPreview", "PageUp", "")
  eq(frm.entries()[list.selected].name, "img10.png")
  frm.flush()
  -- Zoom works there too, and Escape comes back.
  frm:fire("onKeyPreview", "Cmd+1", "1")
  eq(frm.view().zoom, 1)
  frm.cnvFull:fire("onMouseWheel", 0, -1)
  eq(frm.view().zoom, 1.25)
  eq(frm:fire("onKeyPreview", "Escape", ""), true)
  eq(frm.fullView(), false); eq(frm.fullscreen, false)
  eq(frm.cnvFull.visible, false); eq(frm.splMain.visible, true); eq(frm.lblStatus.visible, true)
  -- F11 goes both ways, and Enter comes back too.
  frm:fire("onKeyPreview", "F11", "")
  eq(frm.fullView(), true)
  frm:fire("onKeyPreview", "F11", "")
  eq(frm.fullView(), false)
  frm:fire("onKeyPreview", "Enter", "")
  frm:fire("onKeyPreview", "Enter", "")
  eq(frm.fullView(), false)
  -- Enter on a folder still opens it.
  list.selected = 2
  frm:fire("onKeyPreview", "Enter", "")
  eq(frm.folder(), root .. "/a")
  eq(frm.fullView(), false)
  frm.open(root)
end)

test("form: the folder and the width of the list are kept", function()
  frm.open(root .. "/Misc")
  eq(settings.load().last, root .. "/Misc")
  frm:fire("onClose")
  eq(settings.load().split, frm.lstFiles.width)
  -- A new window opens where it was left, with the list as wide as it was.
  settings.save { last = root .. "/a", split = 400 }
  package.loaded["forms.Viewer"] = nil
  local again = require "forms.Viewer"
  eq(again.folder(), root .. "/a")
  eq(again.lstFiles.width, 400); eq(again.cnvImage.left, 400)
  eq(again.cnvImage.width, again.splMain.width - 400)
  -- A folder that is gone, or a width that cannot be, is not used.
  settings.save { last = root .. "/gone", split = 20 }
  package.loaded["forms.Viewer"] = nil
  again = require "forms.Viewer"
  eq(again.folder(), folder.start())
  eq(again.lstFiles.width, 280)
  package.loaded["forms.Viewer"] = frm
end)

---------------------------------------------------------------- animations

-- A folder of animated pictures, made from the files in tests/data: six
-- frames each as a GIF, a PNG and a WebP, a still WebP, and a GIF of two
-- frames that plays twice.
local movies = root .. "-movies"
assert(lfs.mkdir(movies))
local function copy(from, to)
  local f = assert(io.open("tests/data/imageviewer/" .. from, "rb"))
  write(movies .. "/" .. to, f:read("*a"))
  f:close()
end
copy("anim.gif", "anim.gif"); copy("anim.png", "anim.png"); copy("anim.webp", "anim.webp")
copy("still.webp", "still.webp"); copy("twice.gif", "twice.gif")

test("form: an animation plays, frame by frame, and goes round again", function()
  eq(names(assert(folder.list(movies))), "anim.gif,anim.png,anim.webp,still.webp,twice.gif")
  ok(frm.open(movies))
  eq(list.selected, 2, "the first picture")
  frm.flush()
  local shown = frm.shown()
  eq(#shown.frames, 6); eq(shown.index, 1)
  ok(shown.image == shown.frames[1].image)
  ok(frm.lblStatus.caption:find("frame 1 of 6", 1, true), frm.lblStatus.caption)
  local before = pixel(math.floor(canvas.width / 2), math.floor(canvas.height / 2))
  frm.advance()
  eq(frm.shown().index, 2)
  ok(frm.shown().image == shown.frames[2].image, "the next frame is on show")
  ok(frm.lblStatus.caption:find("frame 2 of 6", 1, true), frm.lblStatus.caption)
  canvas:snapshot()
  for _ = 1, 4 do frm.advance() end
  eq(frm.shown().index, 6)
  frm.advance()
  eq(frm.shown().index, 1, "and round again")
  eq(frm.shown().plays, 2)
  -- The same for the PNG and the WebP.
  for _, row in ipairs { 3, 4 } do
    list.selected = row
    frm.lstFiles:fire("onChange")
    frm.flush()
    eq(#frm.shown().frames, 6, frm.entries()[row].name)
    frm.advance()
    eq(frm.shown().index, 2)
  end
end)

test("form: Space stops and starts it", function()
  list.selected = 2
  frm.lstFiles:fire("onChange")
  frm.flush()
  eq(frm:fire("onKeyPreview", "Space", " "), true)
  ok(frm.shown().paused)
  ok(frm.lblStatus.caption:find("paused", 1, true), frm.lblStatus.caption)
  frm.advance()
  eq(frm.shown().index, 1, "a paused animation stays where it is")
  eq(frm:fire("onKeyPreview", "Space", " "), true)
  ok(not frm.shown().paused)
  ok(not frm.lblStatus.caption:find("paused", 1, true))
  frm.advance()
  eq(frm.shown().index, 2)
  -- Moving to another picture ends it.
  list.selected = 6
  frm.lstFiles:fire("onChange")
  frm.flush()
  eq(frm.shown().frames.width, 20)
  -- A picture that does not move: Space is not the animation's.
  list.selected = 5 -- still.webp
  frm.lstFiles:fire("onChange")
  frm.flush()
  eq(#frm.shown().frames, 1)
  eq(frm.shown().image.width, 160)
  ok(not frm.lblStatus.caption:find("frame", 1, true), "a still has no frames to count")
  ok(not frm:fire("onKeyPreview", "Space", " "))
end)

test("form: an animation that plays so many times stops on its last frame", function()
  list.selected = 6 -- twice.gif: two frames, to go round again once after the first time
  frm.lstFiles:fire("onChange")
  frm.flush()
  eq(frm.shown().frames.loops, 2, "a GIF's count is the times it goes round again, so it plays twice")
  frm.advance()
  eq(frm.shown().index, 2)
  frm.advance()
  eq(frm.shown().index, 1, "the second time round")
  eq(frm.shown().plays, 2)
  frm.advance()
  eq(frm.shown().index, 2)
  frm.advance()
  eq(frm.shown().index, 2, "it has played twice: it stays on its last frame")
  eq(frm.shown().plays, 2)
  -- Space plays it again.
  eq(frm:fire("onKeyPreview", "Space", " "), true)
  eq(frm:fire("onKeyPreview", "Space", " "), true)
  eq(frm.shown().index, 1)
  eq(frm.shown().plays, 1)
  frm:fire("onClose")
end)

---------------------------------------------------------------- zip files

-- A folder with a zip file of pictures in folders, an encrypted one, and
-- a comic book.
local zroot = os.tmpname()
os.remove(zroot)
zroot = zroot .. "-zips"
assert(lfs.mkdir(zroot))
local zip = require "zip"
local function makeZip(path, password)
  local w = zip.create(password and { password = password } or nil)
  w:add("red.png", png.new(40, 20, "#ff0000"):encode())
  w:add("Sub/green.png", png.new(20, 40, "#00ff00"):encode())
  w:add("Sub/deep/blue.png", png.new(10, 10, "#0000ff"):encode())
  w:add("Sub/readme.txt", "no picture")
  w:add(".hidden.png", png.new(2, 2, "#ffffff"):encode())
  local bytes = assert(w:close())
  write(path, bytes)
end
makeZip(zroot .. "/pics.zip")
makeZip(zroot .. "/secret.zip", "pw")
makeZip(zroot .. "/comic.cbz")
write(zroot .. "/plain.png.txt", "x")

test("folder: a zip file is a folder to go into, and paths inside it", function()
  eq(names(assert(folder.list(zroot))), "comic.cbz,pics.zip,secret.zip")
  local list = assert(folder.list(zroot))
  ok(list[2].dir and list[2].archive, "it is a folder")
  eq(list[2].path, zroot .. "/pics.zip!/")
  local file, inner = folder.split(zroot .. "/pics.zip!/Sub/deep")
  eq(file, zroot .. "/pics.zip"); eq(inner, "Sub/deep")
  eq(folder.split(zroot), nil)
  eq(folder.parent(zroot .. "/pics.zip!/Sub/deep"), zroot .. "/pics.zip!/Sub")
  eq(folder.parent(zroot .. "/pics.zip!/Sub"), zroot .. "/pics.zip!/")
  eq(folder.parent(zroot .. "/pics.zip!/"), zroot, "up from the top is the folder it is in")
  eq(folder.basename(zroot .. "/pics.zip!/"), "pics.zip")
  eq(folder.basename(zroot .. "/pics.zip!/Sub/deep"), "deep")
  eq(folder.normalize(zroot .. "/pics.zip!/Sub//"), zroot .. "/pics.zip!/Sub")
  eq(folder.join(zroot .. "/pics.zip!/", "Sub"), zroot .. "/pics.zip!/Sub")
  -- Its contents: folders and pictures, mixed, the way a folder's are.
  assert(folder.archive(zroot .. "/pics.zip"))
  eq(names(assert(folder.list(zroot .. "/pics.zip!/"))), "red.png,Sub")
  local sub = assert(folder.list(zroot .. "/pics.zip!/Sub"))
  eq(names(sub), "deep,green.png")
  eq(sub[2].inner, "Sub/green.png")
  eq(png.decode(assert(folder.read(sub[2]))).width, 20)
  eq(names(assert(folder.list(zroot .. "/pics.zip!/Sub/deep"))), "blue.png")
  -- An encrypted one needs its password.
  folder.closeArchives()
  local a, why, locked = folder.archive(zroot .. "/secret.zip")
  eq(a, nil); eq(locked, "locked"); ok(why:find("password"), why)
  eq(select(3, folder.archive(zroot .. "/secret.zip", "bad")), "locked")
  assert(folder.archive(zroot .. "/secret.zip", "pw"))
  eq(png.decode(assert(folder.read(assert(folder.list(zroot .. "/secret.zip!/"))[1]))).height, 20)
  folder.closeArchives()
end)

test("form: a zip file is browsed like a folder, and its pictures shown", function()
  local gui = require "gui"
  ok(frm.open(zroot))
  eq(names(frm.entries()), "..,comic.cbz,pics.zip,secret.zip")
  list.selected = 3 -- pics.zip
  eq(frm:fire("onKeyPreview", "Enter", ""), true)
  eq(frm.folder(), zroot .. "/pics.zip!/")
  eq(names(frm.entries()), "..,red.png,Sub")
  eq(frm.caption, "pics.zip - Image Viewer")
  frm.flush()
  eq(frm.shown().image.width, 40, "red.png from inside the zip file")
  list.selected = 3 -- Sub
  frm:fire("onKeyPreview", "Right", "")
  eq(frm.folder(), zroot .. "/pics.zip!/Sub")
  eq(frm.caption, "pics.zip/Sub - Image Viewer")
  eq(names(frm.entries()), "..,deep,green.png")
  list.selected = 3
  frm.flush()
  eq(frm.shown().image.height, 40)
  -- Backspace goes up, and from the top comes out of the file, onto it.
  frm:fire("onKeyPreview", "Backspace", "")
  eq(frm.folder(), zroot .. "/pics.zip!/")
  eq(frm.entries()[list.selected].name, "Sub")
  frm:fire("onKeyPreview", "Backspace", "")
  eq(frm.folder(), zroot)
  eq(frm.entries()[list.selected].name, "pics.zip")
  ok(not folder.split(require("settings").load().last), "what is kept is a real folder")
  -- The encrypted one asks for its password until it is right, once.
  local answers, asked = { "bad", "pw" }, 0
  local realBox = gui.passwordbox
  gui.passwordbox = function() asked = asked + 1 return answers[asked] end
  list.selected = 4 -- secret.zip
  frm:fire("onKeyPreview", "Enter", "")
  eq(asked, 2)
  eq(frm.folder(), zroot .. "/secret.zip!/")
  frm.flush()
  eq(frm.shown().image.width, 40)
  frm:fire("onKeyPreview", "Backspace", "")
  list.selected = 4
  frm:fire("onKeyPreview", "Enter", "")
  eq(asked, 2, "it remembers the password")
  frm.open(zroot)
  gui.passwordbox = realBox
end)

test("form: a zip file named on the command line or dropped opens", function()
  local gui = require "gui"
  local realBox = gui.passwordbox
  gui.passwordbox = function() return "pw" end
  frm:fire("onDrop", "", { zroot .. "/pics.zip" })
  eq(frm.folder(), zroot .. "/pics.zip!/")
  frm:fire("onDrop", "", { zroot .. "/secret.zip" })
  eq(frm.folder(), zroot .. "/secret.zip!/")
  frm:fire("onDrop", "", { root })
  eq(frm.folder(), root)
  frm:fire("onDrop", "", { root .. "/a/inside.png" })
  eq(frm.folder(), root .. "/a")
  -- A comic book opens as a zip file does.
  frm.open(zroot)
  frm:fire("onDrop", "", { zroot .. "/comic.cbz" })
  eq(frm.folder(), zroot .. "/comic.cbz!/")
  gui.passwordbox = realBox
end)

os.execute(("rm -rf '%s' '%s' '%s'"):format(root, movies, zroot))
t.done("imageviewer")
