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
  eq(itemNames(frm.menuFor(rowNamed("beta"))), "open system - rename delete - copyPath copyName - newFolder")
  eq(itemNames(frm.menuFor(rowNamed("app.ztl"))), "run - rename delete - copyPath copyName - newFolder")
  eq(itemNames(frm.menuFor(rowNamed("Beta.lua"))), "open run - rename delete - copyPath copyName - newFolder")
  eq(itemNames(frm.menuFor(0)), "newFolder - hidden &Sort By refresh - copyFolderPath system - settings")
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
  local sortItems = items[4][2]
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

-- Tidy up.
fs.remove(root)
t.done("files")
