-- The code behind Files.form.lua: the controls are fields of the form, by
-- the names the layout gives them.
--
-- lstFiles is a FileList, a control of this project's own (controls/), which
-- does the keyboard and mouse in the list; this decides what is in it and
-- what opening a row does. fs.lua does the file system.

local gui = require "gui"
local fs = require "fs"
local settingsForm = require "forms.Settings"
local frm = gui.load "Files" --[[@as forms.Files]]

local settings = fs.loadSettings()
local history = fs.history()
local dir            -- the folder shown
local entries = {}   -- what is in it, as fs.list gives them, sorted
local hiddenCount = 0
local places = {}     -- what lstPlaces lists: { name, path [, drive] } each
local drives = {}     -- the drives mounted, as fs.drives gives them
local SORTS = { "name", "size", "modified", "kind" }

---------------------------------------------------------------- showing

local function setMenuChecked(name, on)
  local items = frm.Menu1.items
  local function walk(list)
    for _, item in ipairs(list) do
      if type(item) == "table" then
        if item.name == name then item.checked = on end
        if type(item[2]) == "table" then walk(item[2]) end
      end
    end
  end
  walk(items)
  frm.Menu1.items = items
end

local function updateStatus()
  local parts = {}
  local n = #entries
  parts[1] = ("  %d %s"):format(n, n == 1 and "item" or "items")
  if hiddenCount > 0 then parts[1] = parts[1] .. (", %d hidden"):format(hiddenCount) end
  local e = frm.lstFiles:selectedRow()
  if e then
    parts[#parts + 1] = e.entry.name .. (e.entry.size and ("  " .. fs.formatSize(e.entry.size)) or "")
    if e.entry.name:lower():match("%.ztl$") then parts[#parts + 1] = "Enter or double-click runs it" end
  end
  frm.lblStatus.caption = table.concat(parts, "      ")
end

local function rowsOf(list)
  local rows = {}
  for i, e in ipairs(list) do
    local icon = e.dir and "dir" or (fs.extension(e.name) == "ztl" and "app" or "file")
    rows[i] = {
      name = e.name, icon = icon, dim = e.hidden, entry = e,
      cells = { e.name, e.dir and "" or fs.formatSize(e.size), fs.formatTime(e.modified), e.kind },
    }
  end
  return rows
end

local function sortColumn()
  for i, s in ipairs(SORTS) do
    if s == settings.sortBy then return i end
  end
  return 1
end

-- show reads the folder again and shows it, keeping the selection on
-- selectName when it is there.
local function show(selectName)
  local list, err = fs.list(dir, settings.showHidden)
  if not list then
    gui.msgbox(("Cannot read %s.\n\n%s"):format(dir, tostring(err)), "ok", "Files")
    list, err = {}, 0
  end
  entries, hiddenCount = fs.sort(list, settings.sortBy, settings.descending, settings.foldersFirst), err
  local l = frm.lstFiles
  l.sortColumn, l.descending = sortColumn(), settings.descending
  l.emptyText = hiddenCount > 0 and ("This folder holds only hidden files (%d)."):format(hiddenCount) or nil
  l:setRows(rowsOf(entries), selectName)
  frm.txtPath.text = dir
  frm.caption = fs.basename(dir) .. " - Files"
  frm.cmdBack.enabled = #history.back > 0
  frm.cmdForward.enabled = #history.forward > 0
  frm.cmdUp.enabled = fs.parent(dir) ~= dir
  updateStatus()
end

-- go shows another folder. how is "visit" (the default), or "history" for
-- back and forward, which keep the history as it is.
local choosingPlace = false

local function go(path, how, selectName)
  path = fs.normalize(path)
  if not fs.isDir(path) then
    gui.msgbox(("%s is not a folder."):format(path), "ok", "Files")
    frm.txtPath.text = dir or ""
    return false
  end
  if how ~= "history" then history:visit(dir, path) end
  dir = path
  show(selectName)
  return true
end

local function goUp()
  local up = fs.parent(dir)
  if up ~= dir then go(up, nil, fs.basename(dir)) end
end

local function goBack()
  local to = history:goBack(dir)
  if to then go(to, "history") end
end

local function goForward()
  local to = history:goForward(dir)
  if to then go(to, "history") end
end

---------------------------------------------------------------- opening

-- run starts a tlua program, a .ztl bundle or a .lua script, with the tlua
-- this is running on, beside this one. What it says on stderr is shown if
-- it fails.
local function run(path)
  local errors = {}
  local ok, err = pcall(gui.spawn, {
    gui.interpreter, path,
    dir = fs.parent(path),
    onOutput = function(line, stream)
      if stream == "stderr" then
        errors[#errors + 1] = line
        if #errors > 12 then table.remove(errors, 1) end
      end
    end,
    onExit = function(code)
      if code ~= 0 then
        gui.msgbox(("%s stopped with an error (%d).\n\n%s"):format(fs.basename(path), code,
          table.concat(errors, "\n")), "ok", "Files")
      end
    end,
  })
  if not ok then
    gui.msgbox(("Cannot run %s.\n\n%s"):format(path, tostring(err)), "ok", "Files")
    return
  end
  frm.lblStatus.caption = "  Started " .. fs.basename(path)
end

-- openWithSystem hands a file to whatever the system opens it with.
local function openWithSystem(path)
  local cmd = fs.opener(path, gui.platform)
  local ok, err = pcall(gui.spawn, cmd)
  if not ok then gui.msgbox(("Cannot open %s.\n\n%s"):format(path, tostring(err)), "ok", "Files") end
end

local function open(e)
  if not e then return end
  if e.dir and fs.extension(e.name) ~= "app" then
    go(e.path)
  elseif fs.extension(e.name) == "ztl" then
    run(e.path)
  else
    openWithSystem(e.path)
  end
end

local function current()
  local row = frm.lstFiles:selectedRow()
  return row and row.entry
end

---------------------------------------------------------------- changing things

local function newFolder()
  local name = gui.inputbox("Name of the new folder:", "New Folder", "New Folder")
  if not name then return end
  local path, err = fs.mkdir(dir, name)
  if not path then
    gui.msgbox(("Cannot make the folder.\n\n%s"):format(tostring(err)), "ok", "New Folder")
    return
  end
  show(name)
end

local function rename()
  local e = current()
  if not e then return end
  local name = gui.inputbox(("New name for %s:"):format(e.name), "Rename", e.name)
  if not name or name == e.name then return end
  local to, err = fs.rename(e.path, name)
  if not to then
    gui.msgbox(("Cannot rename %s.\n\n%s"):format(e.name, tostring(err)), "ok", "Rename")
    return
  end
  show(name)
end

local function delete()
  local e = current()
  if not e then return end
  if settings.confirmDelete then
    local n = e.dir and fs.count(e.path) - 1 or 0
    local what = n > 0 and (" and the %d %s in it"):format(n, n == 1 and "thing" or "things") or ""
    if gui.msgbox(("Delete %s%s?\n\nThis cannot be undone."):format(e.name, what), "yesno", "Delete") ~= "yes" then
      return
    end
  end
  local at = frm.lstFiles.current
  local ok, err = fs.remove(e.path)
  if not ok then
    gui.msgbox(("Cannot delete %s.\n\n%s"):format(e.name, tostring(err)), "ok", "Delete")
  end
  show()
  frm.lstFiles:pick(math.min(at, #entries))
end

---------------------------------------------------------------- settings

local function applySettings(new)
  for k, v in pairs(new) do settings[k] = v end
  setMenuChecked("mnuHidden", settings.showHidden)
  local ok, err = fs.saveSettings(settings)
  if not ok then frm.lblStatus.caption = "  Settings not saved: " .. tostring(err) end
  show()
end

local function sortBy(by)
  if settings.sortBy == by then
    applySettings { descending = not settings.descending }
  else
    applySettings { sortBy = by, descending = false }
  end
end

---------------------------------------------------------------- drives

local ejecting -- the drive being taken out

-- placesMenu is what a right click on the places offers: to eject each
-- drive there is.
local placesMenu -- below

-- refreshPlaces lists the places again, with the drives mounted now,
-- keeping the selection where it was.
local function refreshPlaces()
  drives = fs.drives()
  local at = places[frm.lstPlaces.selected or 0]
  places = fs.places()
  for _, d in ipairs(drives) do places[#places + 1] = { d.name, d.path, drive = d } end
  local names, sel = {}, nil
  for i, p in ipairs(places) do
    names[i] = p[1]
    if at and p[2] == at[2] then sel = i end
  end
  choosingPlace = true
  frm.lstPlaces.items = names
  if sel then frm.lstPlaces.selected = sel end
  choosingPlace = false
  frm.lstPlaces.contextMenu = placesMenu()
end

-- driveToEject is the drive Eject means: the one the folder shown is on,
-- else the one picked in the places, else the only one there is.
local function driveToEject()
  local d = dir and fs.driveOf(dir, drives)
  if d then return d end
  local p = places[frm.lstPlaces.selected or 0]
  if p and p.drive then return p.drive end
  if #drives == 1 then return drives[1] end
end

-- eject takes a drive out: off its folders first, then unmounted (and,
-- with udisks, the disk switched off), a step at a time.
local function eject(d)
  d = d or driveToEject()
  if not d then
    frm.lblStatus.caption = "  There is no drive to eject"
    return
  end
  if ejecting then return end
  local steps = fs.ejectSteps(d)
  if not steps then
    gui.msgbox(("Cannot eject %s: there is no udisksctl, gio or umount."):format(d.name), "ok", "Eject")
    return
  end
  -- A drive cannot be unmounted while its folder is open.
  if fs.driveOf(dir, { d }) then go(fs.home()) end
  ejecting = d
  frm.lblStatus.caption = "  Ejecting " .. d.name .. "..."
  local errors = {}
  local function step(i)
    local st = steps[i]
    if not st then
      ejecting = nil
      refreshPlaces()
      frm.lblStatus.caption = ("  %s can be taken out now"):format(d.name)
      return
    end
    local cmd = { dir = fs.home(),
      onOutput = function(line, stream)
        if stream == "stderr" and line ~= "" then errors[#errors + 1] = line end
      end,
      onExit = function(code)
        if code == 0 or st.optional then
          step(i + 1)
        else
          ejecting = nil
          refreshPlaces()
          frm.lblStatus.caption = "  " .. d.name .. " was not ejected"
          gui.msgbox(("Cannot eject %s.\n\n%s"):format(d.name,
            #errors > 0 and table.concat(errors, "\n") or ("%s stopped with %d."):format(st.cmd[1], code)),
            "ok", "Eject")
        end
      end,
    }
    for k, v in ipairs(st.cmd) do cmd[k] = v end
    local ok, err = pcall(gui.spawn, cmd)
    if not ok then
      ejecting = nil
      gui.msgbox(("Cannot eject %s.\n\n%s"):format(d.name, tostring(err)), "ok", "Eject")
    end
  end
  step(1)
end

placesMenu = function()
  local items = {}
  for _, d in ipairs(drives) do
    local caption = d.name:gsub("&", "&&"):gsub("/", "\\/")
    items[#items + 1] = { "&Eject " .. caption, function() eject(d) end }
  end
  if #items == 0 then items[1] = { "No drives to eject", enabled = false } end
  return items
end

-- watchDrives looks at the mount table every so often, so drives show up
-- when they are plugged in and go when they are taken out.
local function watchDrives()
  local f = io.open(fs.mountsFile)
  if not f then return end -- not Linux: nothing to watch
  f:close()
  local function signature()
    local t = {}
    for i, d in ipairs(fs.drives()) do t[i] = d.path end
    return table.concat(t, "\0")
  end
  local last = signature()
  gui.every(2, function()
    local now = signature()
    if now ~= last then
      last = now
      refreshPlaces()
      -- The folder shown went with its drive.
      if dir and not fs.isDir(dir) then go(fs.home()) end
    end
    return true
  end)
end

---------------------------------------------------------------- context menus

local function checkedSort(by)
  return settings.sortBy == by
end

-- folderItems are what a context menu offers about the folder shown.
local function folderItems()
  local sorts = {}
  for _, by in ipairs(SORTS) do
    sorts[#sorts + 1] = {
      "&" .. by:sub(1, 1):upper() .. by:sub(2), name = "sort-" .. by,
      checked = checkedSort(by), function() sortBy(by) end,
    }
  end
  local items = {
    { "New &Folder...", name = "newFolder", newFolder },
    "-",
    { "Show &Hidden Files", name = "hidden", checked = settings.showHidden,
      function(_, on) applySettings { showHidden = on } end },
    { "&Sort By", sorts },
    { "&Refresh", name = "refresh", function() show() end, shortcut = "F5" },
    "-",
    { "Copy Folder &Path", name = "copyFolderPath", function() gui.clipboard(dir) end },
    { "Show in System &Viewer", name = "system", function() openWithSystem(dir) end },
    "-",
    { "Se&ttings...", name = "settings", function()
      local new = settingsForm.ask(settings)
      if new then applySettings(new) end
    end },
  }
  -- On a drive, it can be ejected from here.
  local d = fs.driveOf(dir, drives)
  if d then
    table.insert(items, #items, { "&Eject " .. d.name, name = "eject", function() eject(d) end })
    table.insert(items, #items, "-")
  end
  return items
end

-- menuFor is the context menu for row i of the list, or for the folder
-- when i is 0.
local function menuFor(i)
  local row = frm.lstFiles.entries[i]
  if not row then return folderItems() end
  local e = row.entry
  local ext = fs.extension(e.name)
  local items = {}
  local function add(item) items[#items + 1] = item end
  if e.dir and ext ~= "app" then
    add { "&Open", name = "open", function() open(e) end, shortcut = "Enter" }
    add { "Show in System &Viewer", name = "system", function() openWithSystem(e.path) end }
  elseif ext == "ztl" then
    add { "&Run", name = "run", function() run(e.path) end, shortcut = "Enter" }
  else
    add { "&Open", name = "open", function() open(e) end, shortcut = "Enter" }
    if ext == "lua" then add { "Run with &tlua", name = "run", function() run(e.path) end } end
  end
  add "-"
  add { "Re&name...", name = "rename", rename, shortcut = "F2" }
  add { "&Delete...", name = "delete", delete, shortcut = "Delete" }
  add "-"
  add { "Copy &Path", name = "copyPath", function() gui.clipboard(e.path) end }
  add { "Copy Na&me", name = "copyName", function() gui.clipboard(e.name) end }
  add "-"
  add { "New &Folder...", name = "newFolder", newFolder }
  return items
end

---------------------------------------------------------------- events

function frm.lstFiles:onMenu(i)
  gui.popup(menuFor(i), frm)
end

function frm.lstFiles:onOpen()
  open(current())
end

function frm.lstFiles:onChange()
  updateStatus()
end

function frm.lstFiles:onSort(column)
  sortBy(SORTS[column])
end

-- Keys the list has no use for of its own.
function frm.lstFiles:onCommand(key)
  if key == "Backspace" then goUp() return true end
  if key == "Delete" then delete() return true end
  return false
end

function frm.txtPath:onKey(key)
  if key == "Enter" then
    if go(fs.expand(self.text, dir)) then frm.lstFiles:focus() end
    return true
  elseif key == "Escape" then
    self.text = dir
    frm.lstFiles:focus()
    return true
  end
  return false
end


function frm.lstPlaces:onChange()
  if choosingPlace then return end
  local p = places[self.selected]
  if p then go(p[2]) end
end

function frm.cmdBack:onClick() goBack() end
function frm.cmdForward:onClick() goForward() end
function frm.cmdUp:onClick() goUp() end
function frm.cmdHome:onClick() go(fs.home()) end

-- Keys nothing else used: Backspace goes up wherever the focus is, but in
-- the path, and Escape does not close the window.
function frm:onKey(key)
  if key == "Backspace" then goUp() return true end
  if key == "Escape" then frm.lstFiles:focus() return true end
  return false
end

-- A file or folder dropped on the window is shown: a folder opened, a
-- file selected in its folder.
function frm:onDrop(text, lines)
  local path = lines and lines[1]
  if not path or path == "" then return end
  path = fs.normalize(path)
  if fs.isDir(path) then go(path)
  elseif fs.exists(path) then go(fs.parent(path), nil, fs.basename(path)) end
end

local help = [[In the list:
  Up, Down, Page Up, Page Down, Home, End    move
  Enter or double-click    open: a folder, a .ztl app (runs it
                           with tlua), or a file in its own program
  Backspace                the folder this one is in
  Delete                   delete
  F2                       rename
  Shift+F10 or right-click a menu of what can be done to it
  typing a name            goes to it

Anywhere:
  Alt+Left, Alt+Right      back, forward
  Alt+Up                   up
  Cmd+L                    type a folder to go to
  Cmd+Shift+.              show or hide hidden files
  F5                       read the folder again
  Cmd+E                    eject the drive (USB stick, SD card)
                           shown, or picked in the places
  Tab                      the list, the places, the path

Click a column's title to sort by it, again to reverse it.]]

local actions = {
  mnuOpen = function() open(current()) end,
  mnuRun = function()
    local e = current()
    if e and not e.dir and (fs.extension(e.name) == "lua" or fs.extension(e.name) == "ztl") then run(e.path) end
  end,
  mnuNewFolder = newFolder,
  mnuRename = rename,
  mnuDelete = delete,
  mnuCopyPath = function()
    local e = current()
    gui.clipboard(e and e.path or dir)
  end,
  mnuSettings = function()
    local new = settingsForm.ask(settings)
    if new then applySettings(new) end
  end,
  mnuEject = function() eject() end,
  mnuExit = function() frm:close() end,
  mnuBack = goBack,
  mnuForward = goForward,
  mnuUp = goUp,
  mnuHome = function() go(fs.home()) end,
  mnuLocation = function()
    frm.txtPath:focus()
    frm.txtPath:select(1, #frm.txtPath.text)
  end,
  mnuSortName = function() sortBy("name") end,
  mnuSortSize = function() sortBy("size") end,
  mnuSortModified = function() sortBy("modified") end,
  mnuSortKind = function() sortBy("kind") end,
  mnuRefresh = function() show() end,
  mnuKeys = function() gui.msgbox(help, "ok", "Keyboard Shortcuts") end,
  mnuAbout = function()
    gui.msgbox("Files\n\nA simple file manager, made with tlua and its form designer.", "ok", "About Files")
  end,
}

function frm.Menu1:onClick(name, caption, checked)
  if name == "mnuHidden" then
    applySettings { showHidden = checked }
  elseif actions[name] then
    actions[name]()
  end
end

---------------------------------------------------------------- starting

refreshPlaces()
watchDrives()
setMenuChecked("mnuHidden", settings.showHidden)

-- A folder named on the command line is shown first: tlua files.ztl ~/src
local start = arg and arg[1]
if start and start ~= "" then start = fs.expand(start, fs.home()) end
if not (start and fs.isDir(start)) then start = fs.home() end
go(start)
gui.after(0, function() frm.lstFiles:focus() end)

-- Exposed for the tests.
frm.menuFor = menuFor
frm.state = function()
  return { dir = dir, entries = entries, settings = settings, history = history }
end
frm.go = go
frm.applySettings = applySettings
frm.refreshPlaces, frm.eject = refreshPlaces, eject
frm.places = function() return places, drives end

return frm
