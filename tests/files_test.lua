-- tlua -p apps/files -p tests tests/files_test.lua
--
-- Everything happens in a folder of its own under the system's temporary
-- folder, and the settings are kept there too, never in the real ones.

local t = require "testing"
local lfs = require "lfs"
local fs = require "fs"
local test, eq, ok = t.test, t.eq, t.ok

local root = os.tmpname()
os.remove(root)
assert(lfs.mkdir(root))
root = fs.normalize(root)
fs.settingsFile = root .. "/settings.lua"

-- The apps of ours that Files may open things in: a turboapps of the tests'
-- own, with the image viewer made as a bundle and the editor as a folder.
local openwith = require "openwith"
local turbo = root .. "/turbo"
lfs.mkdir(turbo); lfs.mkdir(turbo .. "/apps"); lfs.mkdir(turbo .. "/dist")
lfs.mkdir(turbo .. "/apps/editor")
do
  for _, f in ipairs { turbo .. "/Makefile", turbo .. "/dist/imageviewer.ztl", turbo .. "/apps/editor/main.lua" } do
    local h = assert(io.open(f, "wb")); h:close()
  end
end
openwith.ctx = { env = turbo, arg0 = "", cwd = "/" }

local function write(path, text)
  local f = assert(io.open(path, "wb"))
  f:write(text or "")
  f:close()
end

-- A folder to look at: two folders, three files, two of them hidden.
local box = root .. "/box"
lfs.mkdir(box)
lfs.mkdir(box .. "/beta")
lfs.mkdir(box .. "/Alpha")
lfs.mkdir(box .. "/.git")
write(box .. "/zeta.txt", ("z"):rep(3000))
write(box .. "/app.ztl", "x")
write(box .. "/.hidden", "")
write(box .. "/Beta.lua", "print(1)")

local function names(list)
  local out = {}
  for i, e in ipairs(list) do out[i] = e.name end
  return table.concat(out, " ")
end

---------------------------------------------------------------- paths

test("parent", function()
  eq(fs.parent("/a/b/c"), "/a/b")
  eq(fs.parent("/a/"), "/")
  eq(fs.parent("/"), "/")
  eq(fs.parent("C:/x"), "C:/")
  eq(fs.parent("C:/"), "C:/")
  eq(fs.parent("C:\\x\\y"), "C:/x")
end)

test("join and basename", function()
  eq(fs.join("/a", "b"), "/a/b")
  eq(fs.join("/", "b"), "/b")
  eq(fs.basename("/a/b/"), "b")
  eq(fs.basename("/"), "/")
end)

test("expand", function()
  eq(fs.expand("..", "/a/b"), "/a")
  eq(fs.expand("c/./d/../e", "/a"), "/a/c/e")
  eq(fs.expand("/x/../../y", "/a"), "/y")
  eq(fs.expand("~", "/a"), fs.home())
  eq(fs.expand("  /p  ", "/a"), "/p")
end)

test("sizes and kinds", function()
  eq(fs.formatSize(12), "12 B")
  eq(fs.formatSize(3000), "2.9 KB")
  eq(fs.formatSize(5 * 1024 * 1024), "5.0 MB")
  eq(fs.formatSize(300 * 1024 * 1024), "300 MB")
  eq(fs.kindOf("a.ztl"), "tlua app")
  eq(fs.kindOf("a.XYZ"), "XYZ file")
  eq(fs.kindOf("Makefile"), "File")
  eq(fs.kindOf("src", true), "Folder")
end)

---------------------------------------------------------------- listing

test("hidden files are left out unless asked for", function()
  local list, hidden = fs.list(box, false)
  eq(#list, 5); eq(hidden, 2)
  list, hidden = fs.list(box, true)
  eq(#list, 7); eq(hidden, 0)
end)

test("sorting", function()
  local list = fs.list(box, false)
  eq(names(fs.sort(list, "name", false, true)), "Alpha beta app.ztl Beta.lua zeta.txt")
  eq(names(fs.sort(list, "name", true, true)), "beta Alpha zeta.txt Beta.lua app.ztl")
  eq(names(fs.sort(list, "name", false, false)), "Alpha app.ztl beta Beta.lua zeta.txt")
  eq(names(fs.sort(list, "size", true, true)):match("[^ ]+ [^ ]+ ([^ ]+)"), "zeta.txt")
  eq(names(fs.sort(list, "kind", false, false)), "Alpha beta Beta.lua zeta.txt app.ztl")
end)

test("a folder that cannot be read", function()
  local list, err = fs.list(root .. "/nothing-here", false)
  eq(list, nil); ok(err, "an error")
end)

test("findPrefix", function()
  local list = fs.sort(fs.list(box, false), "name", false, true)
  eq(fs.findPrefix(list, "b", 1), 2)
  eq(fs.findPrefix(list, "b", 3), 4)
  eq(fs.findPrefix(list, "b", 5), 2) -- round again
  eq(fs.findPrefix(list, "q", 1), nil)
end)

test("history", function()
  local h = fs.history()
  h:visit("/a", "/b")
  h:visit("/b", "/c")
  eq(h:goBack("/c"), "/b")
  eq(h:goBack("/b"), "/a")
  eq(h:goBack("/a"), nil)
  eq(h:goForward("/a"), "/b")
  h:visit("/b", "/x") -- a new way forgets the old one
  eq(h:goForward("/x"), nil)
end)

---------------------------------------------------------------- changing things

test("make, rename, count and remove", function()
  local scratch = root .. "/scratch"
  lfs.mkdir(scratch)
  local made = assert(fs.mkdir(scratch, "new"))
  eq(fs.isDir(made), true)
  local _, err = fs.mkdir(scratch, "new")
  ok(err:find("there already"), "refuses a name taken")
  _, err = fs.mkdir(scratch, "a/b")
  ok(err, "refuses a slash")
  write(made .. "/f.txt", "x")
  lfs.mkdir(made .. "/sub")
  write(made .. "/sub/g.txt", "y")
  local moved = assert(fs.rename(made, "renamed"))
  eq(fs.basename(moved), "renamed")
  eq(fs.count(moved), 4)
  ok(fs.remove(moved), "removed")
  eq(fs.exists(moved), false)
  lfs.rmdir(scratch)
end)

test("settings round trip", function()
  local s = fs.loadSettings()
  eq(s.showHidden, false); eq(s.sortBy, "name")
  s.showHidden, s.sortBy = true, "size"
  ok(fs.saveSettings(s), "saved")
  local back = fs.loadSettings()
  eq(back.showHidden, true); eq(back.sortBy, "size"); eq(back.foldersFirst, true)
  write(fs.settingsFile, "return { showHidden = 'yes', os = os }")
  eq(fs.loadSettings().showHidden, false) -- a wrong type is not taken
  os.remove(fs.settingsFile)
end)

---------------------------------------------------------------- drives

-- A mount table as Linux has it, with two drives udisks mounted and the
-- usual others. The drives' folders are made under root, standing for
-- /media/<user>.
local media = root .. "/media/ann"
lfs.mkdir(root .. "/media")
lfs.mkdir(media)
lfs.mkdir(media .. "/USB STICK")
lfs.mkdir(media .. "/USB STICK/photos")
lfs.mkdir(media .. "/sd")
local MOUNTS = table.concat({
  "/dev/nvme0n1p2 / ext4 rw,relatime 0 0",
  "proc /proc proc rw,nosuid 0 0",
  "/dev/sdb1 " .. media:gsub(" ", "\\040") .. "/USB\\040STICK vfat rw,nosuid,nodev 0 0",
  "/dev/mmcblk0p1 " .. media .. "/sd exfat rw 0 0",
  "/dev/sda1 /mnt/backup ext4 rw 0 0",
}, "\n") .. "\n"
write(root .. "/mounts", MOUNTS)
fs.mountsFile = root .. "/mounts"
fs.mediaRoots = { root .. "/media/" }

test("drives are read from the mount table", function()
  local d = fs.drives()
  eq(#d, 2)
  eq(d[1].name, "sd"); eq(d[1].device, "/dev/mmcblk0p1"); eq(d[1].fstype, "exfat")
  eq(d[2].name, "USB STICK"); eq(d[2].path, media .. "/USB STICK", "\\040 is a space")
  eq(fs.driveOf(media .. "/USB STICK/photos", d).name, "USB STICK")
  eq(fs.driveOf(media .. "/USB STICKER", d), nil, "a name that only starts the same")
  eq(fs.driveOf(box, d), nil)
  eq(#fs.drives(""), 0)
  local saved = fs.mountsFile
  fs.mountsFile = root .. "/none"
  eq(#fs.drives(), 0, "no mount table: not Linux")
  fs.mountsFile = saved
end)

test("a partition's disk, and the steps that eject a drive", function()
  eq(fs.diskOf("/dev/sdb1"), "/dev/sdb")
  eq(fs.diskOf("/dev/nvme0n1p2"), "/dev/nvme0n1")
  eq(fs.diskOf("/dev/mmcblk0p1"), "/dev/mmcblk0")
  eq(fs.diskOf("/dev/sr0"), "/dev/sr0")
  local d = { name = "USB", path = "/media/ann/USB", device = "/dev/sdb1" }
  local function has(...)
    local set = {}
    for _, n in ipairs { ... } do set[n] = true end
    return function(name) return set[name] end
  end
  local steps = fs.ejectSteps(d, has("udisksctl", "gio", "umount"))
  eq(table.concat(steps[1].cmd, " "), "udisksctl unmount -b /dev/sdb1")
  eq(table.concat(steps[2].cmd, " "), "udisksctl power-off -b /dev/sdb")
  eq(steps[2].optional, true, "a card reader cannot be switched off")
  steps = fs.ejectSteps(d, has("gio", "umount"))
  eq(table.concat(steps[1].cmd, " "), "gio mount -e /media/ann/USB"); eq(#steps, 1)
  eq(table.concat(fs.ejectSteps(d, has("umount"))[1].cmd, " "), "umount /media/ann/USB")
  eq(fs.ejectSteps(d, has()), nil)
end)

---------------------------------------------------------------- the form

-- Built without being shown. The list's keys are its onKey fired, as FLTK
-- would; the form then goes where they lead.
local frm = require "forms.Files"
local list = frm.lstFiles

local function key(k, text) return list:fire("onKey", k, text or "") end
local function selectedName() return (list:selectedRow() or {}).name end

test("form: shows a folder, hidden files left out", function()
  ok(frm.go(box), "went")
  eq(frm.txtPath.text, box)
  eq(frm.caption, "box - Files")
  eq(#list.entries, 5)
  ok(frm.lblStatus.caption:find("5 items, 2 hidden"), "status says so")
end)

test("form: keys move the selection", function()
  eq(selectedName(), "Alpha")
  key("Down"); eq(selectedName(), "beta")
  key("End"); eq(selectedName(), "zeta.txt")
  key("Home"); eq(selectedName(), "Alpha")
  key("PageDown"); eq(selectedName(), "zeta.txt")
  key("Up"); eq(selectedName(), "Beta.lua")
end)

test("form: typing goes to a name", function()
  key("z", "z"); eq(selectedName(), "zeta.txt")
  list.typed = ""
  key("a", "a"); eq(selectedName(), "Alpha")
  key("p", "p"); eq(selectedName(), "app.ztl") -- "ap"
  list.typed = ""
end)

test("form: Enter opens a folder, Backspace goes back up", function()
  list:pick(2) -- beta
  key("Enter", "\r")
  eq(frm.state().dir, box .. "/beta")
  eq(frm.cmdBack.enabled, true)
  ok(list.emptyText == nil, "nothing hidden here")
  key("Backspace", "\b")
  eq(frm.state().dir, box)
  eq(selectedName(), "beta") -- the folder it came out of
end)

test("form: back and forward", function()
  frm.Menu1:fire("onClick", "mnuBack", "", nil)
  eq(frm.state().dir, box .. "/beta")
  frm.Menu1:fire("onClick", "mnuForward", "", nil)
  eq(frm.state().dir, box)
end)

test("form: the path box", function()
  frm.txtPath.text = "beta/.."
  eq(frm.txtPath:fire("onKey", "Enter", "\r"), true)
  eq(frm.state().dir, box)
  frm.txtPath.text = "Alpha"
  frm.txtPath:fire("onKey", "Enter", "\r")
  eq(frm.state().dir, box .. "/Alpha")
  frm.go(box)
end)

test("form: hidden files from the menu, kept in the settings", function()
  frm.Menu1:fire("onClick", "mnuHidden", "", true)
  eq(#list.entries, 7)
  eq(fs.loadSettings().showHidden, true)
  frm.Menu1:fire("onClick", "mnuHidden", "", false)
  eq(#list.entries, 5)
end)

test("form: a click on a column's title sorts by it", function()
  -- The Size column is the second; the first takes what the rest leave.
  local sizeX = list.width - 110 - 130 - 80 + 10
  list:fire("onMouseDown", sizeX, 5, 1, false, "")
  eq(frm.state().settings.sortBy, "size")
  list:fire("onMouseDown", sizeX, 5, 1, false, "")
  eq(frm.state().settings.descending, true)
  frm.applySettings { sortBy = "name", descending = false }
end)

test("form: a click selects, a double click opens", function()
  list:fire("onMouseDown", 40, 22 + 20 * 1 + 5, 1, false, "") -- the second row
  eq(selectedName(), "beta")
  list:fire("onMouseDown", 40, 22 + 20 * 1 + 5, 1, true, "")
  eq(frm.state().dir, box .. "/beta")
  frm.go(box)
end)

test("form: the wheel scrolls a long list", function()
  local long = root .. "/long"
  lfs.mkdir(long)
  for i = 1, 60 do write(("%s/f%02d"):format(long, i)) end
  frm.go(long)
  eq(list.first, 1)
  list:fire("onMouseWheel", 0, 2)
  eq(list.first, 7)
  key("End")
  eq(selectedName(), "f60")
  ok(list.first > 30, "the last row is in sight")
  key("Home")
  eq(list.first, 1)
  frm.go(box)
end)

-- names lists a menu's item names, "-" for its lines.
local function itemNames(items)
  local out = {}
  for _, it in ipairs(items) do out[#out + 1] = it == "-" and "-" or (it.name or it[1]) end
  return table.concat(out, " ")
end

local function rowNamed(name)
  for i, r in ipairs(list.entries) do
    if r.name == name then return i end
  end
end

test("context menu: what it offers depends on what is clicked", function()
  frm.go(box)
  eq(itemNames(frm.menuFor(rowNamed("beta"))), "open system - cut copy paste - rename delete - compress - copyPath copyName - newFolder")
  eq(itemNames(frm.menuFor(rowNamed("app.ztl"))), "run - archive extract - cut copy paste - rename delete - compress - copyPath copyName - newFolder")
  eq(itemNames(frm.menuFor(rowNamed("Beta.lua"))), "open run Open &With - cut copy paste - rename delete - compress - copyPath copyName - newFolder")
  eq(itemNames(frm.menuFor(0)), "newFolder newZip paste - hidden &Sort By refresh - copyFolderPath system - settings")
end)

test("context menu: a right click selects the row under it", function()
  local asked
  local was = list.onMenu
  list.onMenu = function(_, i) asked = i end
  list:pick(1)
  list:fire("onMouseDown", 40, 22 + 20 * 2 + 5, 3, false, "") -- the third row
  eq(asked, 3); eq(list.current, 3)
  list:fire("onMouseDown", 40, 22 + 20 * 30, 3, false, "") -- below the rows
  eq(asked, 0); eq(list.current, 3)
  key("Shift+F10", "")
  eq(asked, 3)
  list.onMenu = was
end)

test("context menu: its items do what they say", function()
  local items = frm.menuFor(0)
  local hidden
  for _, it in ipairs(items) do if it.name == "hidden" then hidden = it end end
  hidden[2]("Show Hidden Files", true)
  eq(#list.entries, 7)
  hidden[2]("Show Hidden Files", false)
  eq(#list.entries, 5)
  local sortItems = items[6][2]
  sortItems[3][2]() -- by modified
  eq(frm.state().settings.sortBy, "modified")
  frm.applySettings { sortBy = "name", descending = false }
end)

test("opener follows the platform", function()
  eq(fs.opener("/a b", "darwin")[1], "open")
  eq(fs.opener("/a b", "linux")[1], "xdg-open")
  eq(fs.opener("C:/x", "windows")[5], "C:\\x")
end)

test("form: drives are among the places, and eject", function()
  local gui = require "gui"
  local places = frm.places()
  local names = {}
  for i, p in ipairs(places) do names[i] = p[1] end
  ok(table.concat(names, ","):find("sd,USB STICK$"), table.concat(names, ","))
  eq(frm.lstPlaces.items[#places], "USB STICK")
  eq(frm.lstPlaces.contextMenu[2][1], "&Eject USB STICK")
  -- Ejecting the drive shown: home first, then each step in turn.
  frm.go(media .. "/USB STICK/photos")
  local d = select(2, frm.places())[2]
  local items = frm.menuFor(0)
  local found
  for _, it in ipairs(items) do if type(it) == "table" and it.name == "eject" then found = true end end
  ok(found, "the folder's menu offers to eject it")
  local ran, answers = {}, {}
  local realSpawn, realWhich, realMsgbox = gui.spawn, fs.which, gui.msgbox
  fs.which = function(name) return name == "udisksctl" and "/usr/bin/udisksctl" or nil end
  gui.msgbox = function(text) answers[#answers + 1] = text return "ok" end
  gui.spawn = function(cmd)
    ran[#ran + 1] = table.concat(cmd, " ")
    -- The disk switches off, so the drive is gone from the table.
    if cmd[2] == "power-off" then write(fs.mountsFile, "/dev/mmcblk0p1 " .. media .. "/sd exfat rw 0 0\n") end
    cmd.onExit(cmd[2] == "power-off" and 1 or 0)
    return {}
  end
  frm.eject(d)
  eq(frm.state().dir, fs.home(), "off the drive first")
  eq(ran[1], "udisksctl unmount -b /dev/sdb1"); eq(ran[2], "udisksctl power-off -b /dev/sdb")
  ok(frm.lblStatus.caption:find("USB STICK can be taken out now"), frm.lblStatus.caption)
  eq(#answers, 0, "a disk that cannot be switched off is fine")
  eq(#select(2, frm.places()), 1)
  -- A drive that will not unmount says why.
  ran = {}
  gui.spawn = function(cmd)
    ran[#ran + 1] = table.concat(cmd, " ")
    cmd.onOutput("Error unmounting /dev/mmcblk0p1: target is busy", "stderr")
    cmd.onExit(1)
    return {}
  end
  frm.Menu1:fire("onClick", "mnuEject", "", nil)
  eq(#ran, 1, "the disk is not switched off")
  ok(answers[1] and answers[1]:find("target is busy"), tostring(answers[1]))
  ok(frm.lblStatus.caption:find("sd was not ejected"), frm.lblStatus.caption)
  gui.spawn, fs.which, gui.msgbox = realSpawn, realWhich, realMsgbox
end)

---------------------------------------------------------------- copying and moving

local function readAll(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

-- A folder to copy from, and one to copy into.
local src, dst = root .. "/src", root .. "/dst"
local function makeSource()
  fs.remove(src); fs.remove(dst)
  lfs.mkdir(src); lfs.mkdir(dst)
  lfs.mkdir(src .. "/tree"); lfs.mkdir(src .. "/tree/inner")
  write(src .. "/a.txt", "alpha")
  write(src .. "/b.txt", "beta")
  write(src .. "/tree/one.txt", "one"); write(src .. "/tree/inner/two.txt", "two")
end

-- run does a whole job, a step at a time, with a small budget so that it takes several.
local function run(job, budget)
  local steps = 0
  repeat steps = steps + 1 until job:step(budget or 4) or steps > 10000
  return steps
end

test("a name for a copy: not one that is taken", function()
  makeSource()
  eq(fs.uniqueName(src, "new.txt"), "new.txt")
  eq(fs.uniqueName(src, "a.txt"), "a copy.txt")
  write(src .. "/a copy.txt", "")
  eq(fs.uniqueName(src, "a.txt"), "a copy 2.txt")
  eq(fs.uniqueName(src, "tree", true), "tree copy")
  write(src .. "/.bashrc", "")
  eq(fs.uniqueName(src, ".bashrc"), ".bashrc copy", "a dot is not an extension")
  write(src .. "/archive.tar.gz", "")
  eq(fs.uniqueName(src, "archive.tar.gz"), "archive.tar copy.gz")
end)

test("size of a file and of a folder", function()
  makeSource()
  eq(fs.size(src .. "/a.txt"), 5)
  eq(fs.size(src .. "/tree"), 6)
  eq(fs.size(src .. "/none"), 0)
end)

test("paste: copies files and folders, a step at a time", function()
  makeSource()
  write(src .. "/big.bin", ("x"):rep(5000))
  local a = lfs.attributes(src .. "/a.txt")
  lfs.touch(src .. "/a.txt", a.access, 1000000000)
  local job = fs.paste({ src .. "/a.txt", src .. "/tree", src .. "/big.bin" }, dst, false)
  eq(#job.items, 3); eq(job.total, 5 + 6 + 5000); eq(job.finished, false)
  ok(run(job, 1000) > 5, "the big file takes several steps")
  eq(job.finished, true); eq(job.count, 3); eq(#job.errors, 0); eq(job.bytes, job.total)
  eq(readAll(dst .. "/a.txt"), "alpha")
  eq(readAll(dst .. "/tree/inner/two.txt"), "two")
  eq(#readAll(dst .. "/big.bin"), 5000)
  eq(lfs.attributes(dst .. "/a.txt", "modification"), 1000000000, "it keeps the time it was changed")
  ok(fs.exists(src .. "/a.txt") and fs.exists(src .. "/tree/one.txt"), "a copy leaves the original")
  eq(#job.results, 3); eq(job.results[2], dst .. "/tree")
  -- Again: nothing is overwritten, the copies are named for it.
  job = fs.paste({ src .. "/a.txt", src .. "/tree" }, dst, false)
  run(job)
  eq(readAll(dst .. "/a copy.txt"), "alpha")
  eq(readAll(dst .. "/tree copy/one.txt"), "one")
  eq(job.results[1], dst .. "/a copy.txt")
  -- Into the folder they are in: a duplicate.
  job = fs.paste({ src .. "/b.txt" }, src, false)
  run(job)
  eq(readAll(src .. "/b copy.txt"), "beta")
end)

test("paste: a copy keeps an executable executable", function()
  if fs.windows then return end
  makeSource()
  write(src .. "/run.sh", "#!/bin/sh\n")
  os.execute("chmod 755 '" .. src .. "/run.sh'")
  local job = fs.paste({ src .. "/run.sh" }, dst, false)
  run(job)
  eq(lfs.attributes(dst .. "/run.sh", "permissions"), "rwxr-xr-x")
end)

test("paste: moves, and a move to where it is does nothing", function()
  makeSource()
  local job = fs.paste({ src .. "/a.txt", src .. "/tree" }, dst, true)
  run(job)
  eq(job.count, 2)
  ok(not fs.exists(src .. "/a.txt") and not fs.exists(src .. "/tree"), "gone from where they were")
  eq(readAll(dst .. "/a.txt"), "alpha"); eq(readAll(dst .. "/tree/inner/two.txt"), "two")
  job = fs.paste({ dst .. "/a.txt" }, dst, true)
  eq(job.skipped, 1); eq(#job.items, 0); eq(job.finished, true)
  -- A name that is taken: the one moved is named for it.
  write(src .. "/a.txt", "again")
  job = fs.paste({ src .. "/a.txt" }, dst, true)
  run(job)
  eq(readAll(dst .. "/a copy.txt"), "again"); eq(readAll(dst .. "/a.txt"), "alpha")
end)

test("paste: what cannot be done is said", function()
  makeSource()
  local job = fs.paste({ src .. "/tree" }, src .. "/tree/inner", false)
  eq(#job.errors, 1); ok(job.errors[1]:find("cannot go into itself"), job.errors[1]); eq(job.finished, true)
  job = fs.paste({ src .. "/gone.txt", src .. "/a.txt" }, dst, false)
  eq(#job.errors, 1); ok(job.errors[1]:find("not there any more"), job.errors[1])
  run(job)
  eq(job.count, 1, "the rest goes on")
  -- Into a folder that is not there.
  job = fs.paste({ src .. "/b.txt" }, root .. "/nowhere", false)
  run(job)
  eq(job.count, 0); eq(#job.errors, 1)
end)

test("paste: stopped, it leaves what is done and no half of a file", function()
  makeSource()
  write(src .. "/big.bin", ("x"):rep(9000))
  local job = fs.paste({ src .. "/a.txt", src .. "/big.bin", src .. "/b.txt" }, dst, false)
  job:step(1000)  -- a.txt, and the start of big.bin
  job:cancel()
  eq(job:step(1000), true)
  eq(job.cancelled, true); eq(job.count, 1)
  eq(readAll(dst .. "/a.txt"), "alpha")
  ok(not fs.exists(dst .. "/big.bin"), "the half copy is taken away")
  ok(not fs.exists(dst .. "/b.txt"), "and the rest was not started")
end)

---------------------------------------------------------------- selecting, cutting, copying, pasting

test("form: several rows are selected with Shift and Cmd", function()
  local gui = require "gui"
  makeSource()
  write(src .. "/c.txt", "c")
  frm.go(src)
  -- tree, a.txt, b.txt, c.txt (folders first)
  eq(#list.entries, 4)
  list:pick(1)
  key("Shift+Down"); key("Shift+Down")
  eq(#frm.selected(), 3); eq(list.current, 3)
  ok(frm.lblStatus.caption:find("3 selected", 1, true), frm.lblStatus.caption)
  key("Shift+Up")
  eq(#frm.selected(), 2)
  list:pick(2)
  eq(#frm.selected(), 1, "a plain move is one again")
  -- A click with Shift, and with Cmd (or Ctrl).
  list:fire("onMouseDown", 40, 22 + 20 * 3 + 5, 1, false, "Shift")
  eq(#frm.selected(), 3)
  list:fire("onMouseDown", 40, 22 + 20 * 2 + 5, 1, false, gui.platform == "darwin" and "Cmd" or "Ctrl")
  eq(#frm.selected(), 2, "taken out")
  eq(frm.selected()[1].name, "a.txt"); eq(frm.selected()[2].name, "c.txt")
  list:fire("onMouseDown", 40, 22 + 5, 1, false, gui.platform == "darwin" and "Cmd" or "Ctrl")
  eq(#frm.selected(), 3, "put in, in the order of the list")
  eq(frm.selected()[1].name, "tree")
  frm.Menu1:fire("onClick", "mnuSelectAll", "", nil)
  eq(#frm.selected(), 4)
  key("Cmd+a"); eq(#frm.selected(), 4)
  -- A right click on a row in the selection keeps the selection.
  local asked
  local was = list.onMenu
  list.onMenu = function(_, i) asked = i end
  list:fire("onMouseDown", 40, 22 + 20 * 2 + 5, 3, false, "")
  eq(asked, 3); eq(#frm.selected(), 4)
  list.onMenu = was
  -- Going to another folder leaves nothing selected there.
  frm.go(src .. "/tree")
  eq(#frm.selected(), 1)
  frm.go(src)
  eq(#frm.selected(), 1)
end)

test("form: copy, then paste into another folder", function()
  makeSource()
  frm.go(src)
  eq(frm.Menu1.items[2][2][3].enabled, false, "nothing to paste yet")
  list:selectNames { "a.txt", "tree" }
  frm.Menu1:fire("onClick", "mnuCopy", "", nil)
  ok(frm.lblStatus.caption:find("Copied 2 items", 1, true), frm.lblStatus.caption)
  eq(frm.clipboard().cut, false)
  eq(frm.Menu1.items[2][2][3].enabled, true, "now there is")
  frm.go(dst)
  frm.Menu1:fire("onClick", "mnuPaste", "", nil)
  ok(frm.pasting(), "going on")
  ok(frm.lblStatus.caption:find("Copying 1 of 2", 1, true), frm.lblStatus.caption)
  eq(frm.Menu1.items[2][2][3].enabled, false, "not while one is")
  local n = 0
  while frm.pasting() and n < 100 do frm.pasting().tick() n = n + 1 end
  eq(frm.pasting(), nil)
  eq(readAll(dst .. "/a.txt"), "alpha"); eq(readAll(dst .. "/tree/inner/two.txt"), "two")
  ok(fs.exists(src .. "/a.txt"), "a copy leaves the original")
  ok(frm.lblStatus.caption:find("Pasted 2 items", 1, true), frm.lblStatus.caption)
  eq(#frm.selected(), 2, "what was pasted is selected")
  ok(frm.clipboard(), "a copy can be pasted again")
  -- Again, here: the copies are named for what is there.
  frm.Menu1:fire("onClick", "mnuPaste", "", nil)
  while frm.pasting() do frm.pasting().tick() end
  ok(fs.exists(dst .. "/a copy.txt") and fs.exists(dst .. "/tree copy"))
end)

test("form: cut moves, and the clipboard is empty after", function()
  makeSource()
  frm.go(src)
  list:selectNames { "b.txt" }
  frm.Menu1:fire("onClick", "mnuCut", "", nil)
  ok(frm.lblStatus.caption:find("Cut 1 item", 1, true), frm.lblStatus.caption)
  ok(fs.exists(src .. "/b.txt"), "it moves when it is pasted, not before")
  frm.go(dst)
  frm.Menu1:fire("onClick", "mnuPaste", "", nil)
  while frm.pasting() do frm.pasting().tick() end
  eq(readAll(dst .. "/b.txt"), "beta")
  ok(not fs.exists(src .. "/b.txt"), "gone from where it was")
  ok(frm.lblStatus.caption:find("Moved 1 item", 1, true), frm.lblStatus.caption)
  eq(frm.clipboard(), nil)
  eq(frm.Menu1.items[2][2][3].enabled, false)
  -- Pasting in the folder it was cut from leaves it be, and says so.
  list:selectNames { "b.txt" }
  frm.Menu1:fire("onClick", "mnuCut", "", nil)
  frm.Menu1:fire("onClick", "mnuPaste", "", nil)
  ok(frm.lblStatus.caption:find("Moved 0 items, 1 was there already", 1, true), frm.lblStatus.caption)
  eq(readAll(dst .. "/b.txt"), "beta")
end)

test("form: Escape stops a paste, and what could not be pasted is said", function()
  local gui = require "gui"
  makeSource()
  write(src .. "/big.bin", ("x"):rep(9 * 1024 * 1024))
  frm.go(src)
  list:selectNames { "big.bin", "b.txt" }
  frm.Menu1:fire("onClick", "mnuCopy", "", nil)
  frm.go(dst)
  frm.Menu1:fire("onClick", "mnuPaste", "", nil)
  frm.pasting().tick() -- the first step of the big file
  ok(frm.pasting(), "still at it")
  eq(frm:fire("onKey", "Escape", ""), true)
  while frm.pasting() do frm.pasting().tick() end
  ok(frm.lblStatus.caption:find("Stopped", 1, true), frm.lblStatus.caption)
  ok(not fs.exists(dst .. "/big.bin"), "no half of a file")
  -- A folder into itself is said, in a message.
  local said
  local realMsgbox = gui.msgbox
  gui.msgbox = function(text) said = text return "ok" end
  frm.go(src)
  list:selectNames { "tree" }
  frm.Menu1:fire("onClick", "mnuCopy", "", nil)
  frm.go(src .. "/tree/inner")
  frm.Menu1:fire("onClick", "mnuPaste", "", nil)
  ok(said and said:find("cannot go into itself", 1, true), tostring(said))
  eq(frm.pasting(), nil)
  gui.msgbox = realMsgbox
end)

test("form: delete takes everything selected", function()
  local gui = require "gui"
  makeSource()
  frm.go(src)
  list:selectNames { "a.txt", "b.txt" }
  local asked
  local realMsgbox = gui.msgbox
  gui.msgbox = function(text) asked = text return "yes" end
  frm.Menu1:fire("onClick", "mnuDelete", "", nil)
  ok(asked and asked:find("Delete these 2 items", 1, true), tostring(asked))
  ok(not fs.exists(src .. "/a.txt") and not fs.exists(src .. "/b.txt"))
  ok(fs.exists(src .. "/tree"), "the rest is left")
  -- Rename is for one.
  list:selectNames { "tree" }
  eq(#frm.selected(), 1)
  makeSource()
  frm.go(src)
  list:selectNames { "a.txt", "b.txt" }
  frm.Menu1:fire("onClick", "mnuRename", "", nil)
  ok(frm.lblStatus.caption:find("one item at a time", 1, true), frm.lblStatus.caption)
  gui.msgbox = realMsgbox
end)

---------------------------------------------------------------- opening in our own apps

test("form: a picture opens in the image viewer, and Open With offers the others", function()
  local gui = require "gui"
  local system = fs.opener("x", gui.platform)[1] -- what the system opens files with: open, xdg-open, ...
  local pics = root .. "/pics"
  lfs.mkdir(pics)
  write(pics .. "/cat.png", ""); write(pics .. "/data.bin", ""); write(pics .. "/notes.txt", "")
  frm.go(pics)
  local started
  local realSpawn = gui.spawn
  gui.spawn = function(cmd) started = cmd return {} end
  local function rowOf(name)
    for i, r in ipairs(list.entries) do if r.name == name then return i end end
  end
  frm.applySettings { openWithApps = true }
  list:pick(rowOf("cat.png"))
  list:fire("onOpen", list.current)
  eq(started[2], turbo .. "/dist/imageviewer.ztl"); eq(started[3], pics .. "/cat.png")
  ok(frm.lblStatus.caption:find("Opened cat.png in Image Viewer", 1, true), frm.lblStatus.caption)
  -- A text file in the editor, which is only a folder here.
  list:pick(rowOf("notes.txt"))
  list:fire("onOpen", list.current)
  eq(started[2], turbo .. "/apps/editor/main.lua"); eq(started[3], pics .. "/notes.txt")
  -- What no app of ours opens goes to the system.
  list:pick(rowOf("data.bin"))
  list:fire("onOpen", list.current)
  eq(started[1], system); eq(started[2], pics .. "/data.bin")
  -- The menu: the apps there are for it (pixel is not made here), and the system's.
  local menu = frm.menuFor(rowOf("cat.png"))
  local with
  for _, it in ipairs(menu) do if type(it) == "table" and it[1] == "Open &With" then with = it[2] end end
  ok(with, "Open With")
  eq(itemNames(with), "with-imageviewer - with-system")
  with[1][2]()
  eq(started[2], turbo .. "/dist/imageviewer.ztl")
  with[3][2]()
  eq(started[1], system)
  -- A file nothing of ours opens has no such menu.
  for _, it in ipairs(frm.menuFor(rowOf("data.bin"))) do ok(not (type(it) == "table" and it[1] == "Open &With")) end
  -- Turned off, everything goes to the system.
  frm.applySettings { openWithApps = false }
  list:pick(rowOf("cat.png"))
  list:fire("onOpen", list.current)
  eq(started[1], system); eq(started[2], pics .. "/cat.png")
  frm.applySettings { openWithApps = true }
  -- An app that cannot be found: the system opens it.
  openwith.ctx = { env = "", arg0 = "", cwd = "/" }
  list:pick(rowOf("cat.png"))
  list:fire("onOpen", list.current)
  eq(started[1], system)
  openwith.ctx = { env = turbo, arg0 = "", cwd = "/" }
  gui.spawn = realSpawn
end)

---------------------------------------------------------------- archives

local zip = require "zip"

local function makeZip(path, password, files)
  local w = zip.create(password and { password = password } or nil)
  for _, f in ipairs(files) do w:add(f[1], f[2], { modified = f[3] }) end
  local bytes = assert(w:close())
  write(path, bytes)
end

local arcDir = root .. "/arc"
lfs.mkdir(arcDir)

test("archive: lists what is in a zip and unpacks it, a step at a time", function()
  local z = arcDir .. "/a.zip"
  makeZip(z, nil, { { "one.txt", "1", 1000000000 }, { "sub/deep/two.txt", ("x"):rep(5000) }, { "sub/three.txt", "3" } })
  local a = assert(fs.archive(z))
  eq(#a.entries, 3); eq(a.total, 5002); eq(a.encrypted, false)
  local out = arcDir .. "/out"
  local job = a:extract(out)
  ok(run(job, 1000) > 5, "the big file takes several steps")
  eq(job.count, 3); eq(#job.errors, 0); eq(job.bytes, job.total)
  eq(readAll(out .. "/one.txt"), "1")
  eq(#readAll(out .. "/sub/deep/two.txt"), 5000)
  eq(lfs.attributes(out .. "/one.txt", "modification"), 1000000000, "it keeps the time")
  -- Again: nothing is overwritten.
  job = a:extract(out, { "one.txt" })
  run(job)
  eq(readAll(out .. "/one copy.txt"), "1")
  -- A folder in a list takes all in it.
  local part = arcDir .. "/part"
  job = a:extract(part, { "sub/" })
  run(job)
  eq(job.count, 2); ok(not fs.exists(part .. "/one.txt"), "only the folder")
  eq(readAll(part .. "/sub/three.txt"), "3")
end)

test("archive: names that reach out of the folder are refused", function()
  local z = arcDir .. "/evil.zip"
  makeZip(z, nil, { { "../escape.txt", "no" }, { "/abs.txt", "no" }, { "ok.txt", "yes" } })
  local out = arcDir .. "/evilout"
  local job = assert(fs.archive(z)):extract(out)
  run(job)
  eq(job.count, 1); eq(#job.errors, 2)
  ok(not fs.exists(arcDir .. "/escape.txt"), "nothing left the folder")
  eq(readAll(out .. "/ok.txt"), "yes")
end)

test("archive: an encrypted one needs its password", function()
  local z = arcDir .. "/secret.zip"
  makeZip(z, "pw", { { "s.txt", "hidden" } })
  local a, why, locked = fs.archive(z)
  eq(a, nil); eq(locked, "locked"); ok(why:find("password"), why)
  a, why, locked = fs.archive(z, "nope")
  eq(locked, "locked"); ok(why:find("wrong"), why)
  a = assert(fs.archive(z, "pw"))
  eq(a.encrypted, true)
  local job = a:extract(arcDir .. "/secretout")
  run(job)
  eq(readAll(arcDir .. "/secretout/s.txt"), "hidden")
  local junk = arcDir .. "/junk.zip"
  write(junk, "not a zip")
  a, why, locked = fs.archive(junk)
  eq(a, nil); eq(locked, nil)
end)

test("archive: files and folders are compressed into a zip, with a password if wanted", function()
  write(arcDir .. "/one.txt", "1")
  local src2 = arcDir .. "/pack"
  lfs.mkdir(src2); lfs.mkdir(src2 .. "/inner")
  write(src2 .. "/a.txt", "alpha"); write(src2 .. "/inner/b.txt", ("b"):rep(4000)); write(src2 .. "/pic.png", "PNG")
  lfs.touch(src2 .. "/a.txt", 1000000000, 1000000000)
  local dest = arcDir .. "/packed.zip"
  local job = fs.compress({ src2, arcDir .. "/one.txt" }, dest)
  eq(job.finished, false)
  run(job, 1000)
  eq(job.count, 4); eq(#job.errors, 0); eq(job.results[1], dest)
  ok(not fs.exists(dest .. ".part"), "no half-made file is left")
  local a = assert(fs.archive(dest))
  local seen = {}
  for _, e in ipairs(a.entries) do seen[e.name] = e end
  ok(seen["pack/a.txt"] and seen["pack/inner/b.txt"] and seen["pack/pic.png"] and seen["one.txt"], "names keep the folders")
  eq(seen["pack/a.txt"].modified, 1000000000)
  eq(seen["pack/pic.png"].method, "store")
  -- With a password, and the archive being made is never put in itself.
  local sec = arcDir .. "/sec.zip"
  job = fs.compress({ arcDir .. "/pack", sec }, sec, "pw")
  run(job)
  eq(job.count, 3)
  eq(select(3, fs.archive(sec)), "locked")
  local b = assert(fs.archive(sec, "pw"))
  eq(b.encrypted, true)
  -- Stopped, it leaves nothing.
  local stop = arcDir .. "/stop.zip"
  job = fs.compress({ arcDir .. "/pack" }, stop)
  job:step(1)
  job:cancel()
  run(job)
  ok(not fs.exists(stop) and not fs.exists(stop .. ".part"), "nothing left")
end)

test("archive: files are added, removed and replaced in place, and the password changed", function()
  local z = arcDir .. "/manage.zip"
  makeZip(z, nil, { { "keep.txt", "keep", 1000000000 }, { "gone.txt", "x" }, { "dir/x.txt", "1" }, { "dir/y.txt", "2" } })
  write(arcDir .. "/new.txt", "new!")
  write(arcDir .. "/keep.txt", "replaced")
  local a = assert(fs.archive(z))
  local job = a:rewrite { remove = { "gone.txt", "dir/" }, add = fs.collect({ arcDir .. "/new.txt", arcDir .. "/keep.txt" }) }
  run(job)
  eq(job.count, 2); eq(job.removed, 3); eq(job.replaced, 1); eq(#job.errors, 0)
  a = assert(fs.archive(z))
  eq(#a.entries, 2)
  eq(a.z:read("new.txt"), "new!"); eq(a.z:read("keep.txt"), "replaced")
  -- Add a file whose name is not taken, and an encryption: all of it.
  job = a:rewrite { password = "s3" }
  run(job)
  eq(select(3, fs.archive(z)), "locked")
  a = assert(fs.archive(z, "s3"))
  eq(a.z:read("new.txt", "s3"), "new!")
  -- Changing a locked archive keeps its password, and false takes it off.
  job = a:rewrite { add = fs.collect({ arcDir .. "/one.txt" }) }
  run(job)
  eq(select(3, fs.archive(z)), "locked")
  a = assert(fs.archive(z, "s3"))
  eq(#a.entries, 3)
  run(a:rewrite { password = false })
  a = assert(fs.archive(z))
  eq(a.encrypted, false); eq(a.z:read("one.txt"), "1")
  -- The archive cannot be added to itself, and stopping leaves it whole.
  job = a:rewrite { add = fs.collect({ z }) }
  run(job)
  eq(#assert(fs.archive(z)).entries, 3)
  job = a:rewrite { remove = { "new.txt" } }
  job:step(1)
  job:cancel()
  run(job)
  eq(#assert(fs.archive(z)).entries, 3)
  ok(not fs.exists(z .. ".part"), "no half-made file")
end)

test("archive: the window lists it, asks the password, and unpacks", function()
  local gui = require "gui"
  local form = require "forms.Archive"
  local z = arcDir .. "/win.zip"
  makeZip(z, "pw", { { "a.txt", "alpha" }, { "d/b.txt", "beta" } })
  local asked = 0
  local realBox, realMsg, realDir = gui.passwordbox, gui.msgbox, gui.choosedir
  gui.passwordbox = function()
    asked = asked + 1
    return asked == 1 and "wrong" or "pw"
  end
  gui.msgbox = function() return "ok" end
  ok(form.fill(z), "opened")
  eq(asked, 2)
  eq(#form.lstEntries.entries, 2)
  ok(form.lblInfo.caption:find("encrypted"), form.lblInfo.caption)
  -- Everything, to a folder chosen.
  gui.choosedir = function() return arcDir .. "/winout" end
  form.cmdAll:fire("onClick")
  local r = form.running()
  ok(r, "it is running")
  while form.running() do r.tick() end
  eq(readAll(arcDir .. "/winout/d/b.txt"), "beta")
  eq(form.extracted.count, 2)
  -- One selected.
  form.lstEntries:pick(1)
  gui.choosedir = function() return arcDir .. "/winone" end
  form.cmdSelected:fire("onClick")
  r = form.running()
  while form.running() do r.tick() end
  eq(readAll(arcDir .. "/winone/a.txt"), "alpha"); ok(not fs.exists(arcDir .. "/winone/d"), "only the one")
  -- To a folder of its own, beside the archive.
  form.cmdFolder:fire("onClick")
  r = form.running()
  while form.running() do r.tick() end
  eq(readAll(arcDir .. "/win/a.txt"), "alpha")
  gui.passwordbox, gui.msgbox, gui.choosedir = realBox, realMsg, realDir
end)

test("archive: files are dropped on the window, deleted, and the password changed", function()
  local gui = require "gui"
  local form = require "forms.Archive"
  local z = arcDir .. "/live.zip"
  makeZip(z, nil, { { "a.txt", "alpha" }, { "b.txt", "beta" }, { "c.txt", "gamma" } })
  write(arcDir .. "/dropped.txt", "dropped")
  lfs.mkdir(arcDir .. "/dropdir"); write(arcDir .. "/dropdir/in.txt", "in")
  local realBox, realMsg, realOpen, realDir = gui.passwordbox, gui.msgbox, gui.openfile, gui.choosedir
  local said = {}
  gui.msgbox = function(text) said[#said + 1] = text return "yes" end
  ok(form.fill(z))
  local function settle() local r = form.running() while form.running() do r.tick() end end
  -- Dropped files and folders go in.
  form:fire("onDrop", "", { arcDir .. "/dropped.txt", arcDir .. "/dropdir" })
  settle()
  eq(#form.lstEntries.entries, 5)
  ok(form.lblStatus.caption:find("Added 2 files"), form.lblStatus.caption)
  eq(form.archive().z:read("dropdir/in.txt"), "in")
  ok(form.changed, "it says it changed")
  -- The button asks for files.
  gui.openfile = function() return { arcDir .. "/one.txt" } end
  form.cmdAdd:fire("onClick")
  settle()
  eq(#form.lstEntries.entries, 6)
  gui.choosedir = function() return arcDir .. "/pack" end
  form.cmdAddFolder:fire("onClick")
  settle()
  ok(form.archive().z:exists("pack/a.txt"), "a folder with what is in it")
  -- Delete what is selected, once asked.
  form.lstEntries:selectNames({ "a.txt", "b.txt" })
  eq(#form.names(), 2)
  said = {}
  form.cmdDelete:fire("onClick")
  ok(said[1]:find("2 files"), said[1])
  settle()
  ok(not form.archive().z:exists("a.txt") and form.archive().z:exists("c.txt"), "those two are gone")
  ok(form.lblStatus.caption:find("Deleted 2 files"), form.lblStatus.caption)
  gui.msgbox = function() return "no" end
  form.lstEntries:pick(1)
  form.lstEntries:fire("onCommand", "Delete")
  ok(not form.running(), "refused, nothing runs")
  gui.msgbox = function() return "yes" end
  -- A password for all of it, and the archive is read again with it.
  gui.passwordbox = function() return "pw" end
  form.cmdPassword:fire("onClick")
  settle()
  eq(select(3, fs.archive(z)), "locked")
  ok(form.lblInfo.caption:find("encrypted"), form.lblInfo.caption)
  -- A change to it keeps the password.
  form:fire("onDrop", "", { arcDir .. "/dropped.txt" })
  settle()
  eq(select(3, fs.archive(z)), "locked")
  ok(fs.archive(z, "pw"):extract(arcDir .. "/liveout") ~= nil)
  gui.passwordbox = function() return "" end
  form.cmdPassword:fire("onClick")
  settle()
  ok(fs.archive(z) ~= nil, "readable without one")
  -- Closing stops a job and leaves the archive whole.
  form:fire("onDrop", "", { arcDir .. "/pack" })
  form:fire("onClose")
  ok(not form.running(), "stopped")
  ok(fs.archive(z) ~= nil)
  gui.passwordbox, gui.msgbox, gui.openfile, gui.choosedir = realBox, realMsg, realOpen, realDir
end)

test("zip files: compress what is selected, and make an empty one", function()
  local gui = require "gui"
  local realIn, realBox = gui.inputbox, gui.passwordbox
  local work = root .. "/zipwork"
  lfs.mkdir(work); lfs.mkdir(work .. "/folder")
  write(work .. "/a.txt", "alpha"); write(work .. "/folder/b.txt", "beta")
  frm.go(work)
  local answer, pw = "squash", ""
  gui.inputbox = function() return answer end
  gui.passwordbox = function() return pw end
  local function settle()
    while frm.pasting() do frm.pasting().tick() end
  end
  list:selectNames({ "a.txt", "folder" })
  frm.compress()
  ok(frm.pasting(), "it runs a step at a time")
  settle()
  local a = assert(fs.archive(work .. "/squash.zip"))
  eq(#a.entries, 2)
  ok(a.z:exists("folder/b.txt"), "the folder's files")
  eq((list:selectedRow() or {}).name, "squash.zip")
  ok(frm.lblStatus.caption:find("Packed 2 items into squash.zip"), frm.lblStatus.caption)
  -- A name that is taken is not overwritten; a password locks it.
  pw = "pw"
  list:selectNames({ "a.txt" })
  frm.compress()
  settle()
  eq(select(3, fs.archive(work .. "/squash copy.zip")), "locked")
  ok(frm.lblStatus.caption:find("(encrypted)", 1, true), frm.lblStatus.caption)
  -- An empty one, to drop files on.
  pw, answer = "", "empty"
  frm.newZip()
  settle()
  eq(#assert(fs.archive(work .. "/empty.zip")).entries, 0)
  -- Cancelling a box makes nothing.
  answer = nil
  frm.newZip()
  ok(not frm.pasting(), "nothing runs")
  gui.inputbox, gui.passwordbox = realIn, realBox
  frm.go(box)
end)

test("archive: the menu offers it for zip files", function()
  write(box .. "/pack.zip", "x")
  frm.go(box)
  local i = rowNamed("pack.zip")
  ok(itemNames(frm.menuFor(i)):find("archive extract", 1, true), itemNames(frm.menuFor(i)))
  fs.remove(box .. "/pack.zip")
  frm.go(box)
end)

-- Tidy up.
fs.remove(root)
t.done("files")
