-- tlua -p apps/imageviewer -p tests tests/imageviewer_test.lua

local t = require "testing"
local lfs = require "lfs"
local png = require "png" -- tlua's own module
local folder = require "folder"
local test, eq, ok = t.test, t.eq, t.ok

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
  ok(not frm:fire("onKeyPreview", "Enter", ""), "Enter on a picture does nothing")
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

os.execute(("rm -rf '%s' '%s'"):format(root, movies))
t.done("imageviewer")
