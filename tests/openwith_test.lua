-- tlua -p apps/files -p tests tests/openwith_test.lua
--
-- openwith.lua, which Files and the Desktop both carry a copy of.

local t = require "testing"
local lfs = require "lfs"
local openwith = require "openwith"
local test, eq, ok = t.test, t.eq, t.ok

local base = os.tmpname()
os.remove(base)
assert(lfs.mkdir(base))

local function write(path, text)
  local f = assert(io.open(path, "wb"))
  f:write(text or "")
  f:close()
end

-- A turboapps of its own: the viewer made as a bundle, the editor only as a
-- folder, and no pixel at all.
local root = base .. "/turbo"
assert(lfs.mkdir(root)); assert(lfs.mkdir(root .. "/apps")); assert(lfs.mkdir(root .. "/dist"))
write(root .. "/Makefile", "all:\n")
for _, name in ipairs { "imageviewer", "editor", "microword" } do
  assert(lfs.mkdir(root .. "/apps/" .. name))
  write(root .. "/apps/" .. name .. "/main.lua", "")
end
write(root .. "/dist/imageviewer.ztl", "x")
local nowhere = { env = "", arg0 = "", cwd = "/" }
local here = { env = root, arg0 = "", cwd = "/" }

test("the apps for a file, by its extension, in any case", function()
  eq(table.concat(openwith.appsFor("/a/cat.png"), ","), "imageviewer,pixel")
  eq(table.concat(openwith.appsFor("CAT.JPEG"), ","), "imageviewer,pixel")
  eq(table.concat(openwith.appsFor("a.webp"), ","), "imageviewer")
  eq(table.concat(openwith.appsFor("book.zmd"), ","), "microword")
  eq(table.concat(openwith.appsFor("notes.md"), ","), "microword,editor")
  eq(table.concat(openwith.appsFor("sheet.csv"), ","), "microsheets,editor")
  eq(table.concat(openwith.appsFor("a.znb"), ","), "micronotes,microreader")
  eq(table.concat(openwith.appsFor("song.json"), ","), "editor,chipstudio")
  eq(table.concat(openwith.appsFor("readme.txt"), ","), "editor")
  eq(#openwith.appsFor("a.exe"), 0); eq(#openwith.appsFor("noextension"), 0); eq(#openwith.appsFor("dir.d/file"), 0)
  -- What is given back is a copy.
  openwith.appsFor("a.png")[1] = "x"
  eq(openwith.appsFor("a.png")[1], "imageviewer")
  for _, apps in pairs(openwith.TYPES) do
    for _, app in ipairs(apps) do ok(openwith.TITLES[app], app .. " has a title") end
  end
end)

test("locate: a bundle first, else the app's own folder, else nothing", function()
  eq(openwith.locate("imageviewer", here), root .. "/dist/imageviewer.ztl")
  eq(openwith.locate("editor", here), root .. "/apps/editor/main.lua")
  eq(openwith.locate("pixel", here), nil)
  eq(openwith.locate("imageviewer", nowhere), nil)
end)

test("locate: where the program was started from, or the folder above", function()
  eq(openwith.locate("editor", { env = "", arg0 = root .. "/dist/files.ztl", cwd = "/" }), root .. "/apps/editor/main.lua")
  eq(openwith.locate("editor", { env = "", arg0 = root .. "/apps/files/main.lua", cwd = "/" }), root .. "/apps/editor/main.lua")
  eq(openwith.locate("editor", { env = "", arg0 = "x.lua", cwd = root .. "/apps/files" }), root .. "/apps/editor/main.lua")
  eq(openwith.locate("editor", { env = "", arg0 = "x.lua", cwd = root }), root .. "/apps/editor/main.lua")
  eq(openwith.locate("editor", { env = "/not/a/root", arg0 = "", cwd = "/" }), nil)
end)

test("locate: a bundle beside the program running wins", function()
  local elsewhere = base .. "/installed"
  assert(lfs.mkdir(elsewhere))
  write(elsewhere .. "/files.ztl", "x"); write(elsewhere .. "/editor.ztl", "x")
  local ctx = { env = root, arg0 = elsewhere .. "/files.ztl", cwd = "/" }
  eq(openwith.locate("editor", ctx), elsewhere .. "/editor.ztl")
  eq(openwith.locate("imageviewer", ctx), root .. "/dist/imageviewer.ztl", "else the root has it")
end)

test("command and available", function()
  local cmd = openwith.command("imageviewer", "/pics/cat.png", "/usr/bin/tlua", here)
  eq(cmd[1], "/usr/bin/tlua"); eq(cmd[2], root .. "/dist/imageviewer.ztl"); eq(cmd[3], "/pics/cat.png"); eq(#cmd, 3)
  eq(openwith.command("pixel", "/pics/cat.png", "tlua", here), nil)
  eq(openwith.command("editor", "a.txt", nil, here)[1], "tlua", "the one on the path without another")
  -- Of those that open a png, the viewer is here and pixel is not.
  eq(table.concat(openwith.available("cat.png", here), ","), "imageviewer")
  eq(table.concat(openwith.available("a.md", here), ","), "microword,editor")
  eq(#openwith.available("cat.png", nowhere), 0)
  -- The override tests use is what is looked in when nothing is given.
  openwith.ctx = here
  eq(openwith.locate("editor"), root .. "/apps/editor/main.lua")
  openwith.ctx = nil
end)

test("the copies in Files and in the Desktop are the same", function()
  local function read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
  end
  eq(read("apps/files/openwith.lua"), read("apps/desktop/openwith.lua"), "keep them the same: copy one over the other")
end)

os.execute(("rm -rf '%s'"):format(base))
t.done("openwith")
