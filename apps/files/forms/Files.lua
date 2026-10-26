-- The code behind Files.form.lua: the controls are fields of the form, by
-- the names the layout gives them.
--
-- lstFiles is a FileList, a control of this project's own (controls/), which
-- does the keyboard and mouse in the list; this decides what is in it and
-- what opening a row does. fs.lua does the file system.

local gui = require "gui"
local fs = require "fs"
local openwith = require "openwith"
local settingsForm = require "forms.Settings"
local archiveForm = require "forms.Archive"
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

-- setMenuItem sets a field (checked, enabled) of the menu item called name.
local function setMenuItem(name, field, on)
  local items = frm.Menu1.items
  local function walk(list)
    for _, item in ipairs(list) do
      if type(item) == "table" then
        if item.name == name then item[field] = on end
        if type(item[2]) == "table" then walk(item[2]) end
      end
    end
  end
  walk(items)
  frm.Menu1.items = items
end

local function setMenuChecked(name, on) setMenuItem(name, "checked", on) end

local clip      -- what was cut or copied: { paths = {...}, cut = true or false }
local pasting   -- the job being done: { job =, timer = }

local function updateStatus()
  local parts = {}
  local n = #entries
  parts[1] = ("  %d %s"):format(n, n == 1 and "item" or "items")
  if hiddenCount > 0 then parts[1] = parts[1] .. (", %d hidden"):format(hiddenCount) end
  local rows = frm.lstFiles:selectedRows()
  local e = frm.lstFiles:selectedRow()
  if #rows > 1 then
    local size = 0
    for _, r in ipairs(rows) do size = size + (r.entry.size or 0) end
    parts[#parts + 1] = ("%d selected"):format(#rows) .. (size > 0 and ("  " .. fs.formatSize(size)) or "")
  elseif e then
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
local updateEdit -- below

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
  updateEdit()
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
  frm.lstFiles.selection = {} -- what was selected there is not selected here
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
local function run(path, file)
  local errors = {}
  local ok, err = pcall(gui.spawn, {
    gui.interpreter, path, file,
    dir = fs.parent(file or path),
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

-- openWithApp opens a file in one of turboapps' own apps; false when the
-- app cannot be found.
local function openWithApp(name, path)
  local cmd = openwith.command(name, path, gui.interpreter)
  if not cmd then return false end
  run(cmd[2], path)
  frm.lblStatus.caption = ("  Opened %s in %s"):format(fs.basename(path), openwith.TITLES[name] or name)
  return true
end

-- lookInto shows a zip archive's contents, to unpack all or some of them;
-- how = "folder" unpacks it at once into a folder of its own. The folder
-- shown is read again after, with what came out in it.
local function lookInto(path, how)
  archiveForm.look(path, how)
  show()
  local ex = archiveForm.extracted
  if ex then frm.lblStatus.caption = ("  Unpacked %d into %s"):format(ex.count, ex.dest) end
end

-- open opens what is picked: a folder is gone into, a .ztl is run, and a file
-- is opened in the app of ours for it when there is one (and that is not
-- turned off in the settings), else in the system's own program.
local function open(e)
  if not e then return end
  if e.dir and fs.extension(e.name) ~= "app" then
    go(e.path)
  elseif fs.extension(e.name) == "ztl" then
    run(e.path)
  elseif fs.extension(e.name) == "zip" then
    lookInto(e.path)
  else
    local app = settings.openWithApps and openwith.available(e.path)[1]
    if not (app and openWithApp(app, e.path)) then openWithSystem(e.path) end
  end
end

local function current()
  local row = frm.lstFiles:selectedRow()
  return row and row.entry
end

-- selected is every entry selected, in the order of the list.
local function selected()
  local out = {}
  for _, row in ipairs(frm.lstFiles:selectedRows()) do out[#out + 1] = row.entry end
  return out
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
  if #selected() > 1 then
    frm.lblStatus.caption = "  Rename works on one item at a time"
    return
  end
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
  local list = selected()
  if #list == 0 then return end
  if settings.confirmDelete then
    local question
    if #list == 1 then
      local e = list[1]
      local n = e.dir and fs.count(e.path) - 1 or 0
      local what = n > 0 and (" and the %d %s in it"):format(n, n == 1 and "thing" or "things") or ""
      question = ("Delete %s%s?"):format(e.name, what)
    else
      local n = 0
      for _, e in ipairs(list) do n = n + fs.count(e.path) end
      question = ("Delete these %d items, with the %d %s in all?"):format(#list, n, n == 1 and "thing" or "things")
    end
    if gui.msgbox(question .. "\n\nThis cannot be undone.", "yesno", "Delete") ~= "yes" then
      return
    end
  end
  local at = frm.lstFiles.current
  local errors = {}
  for _, e in ipairs(list) do
    local ok, err = fs.remove(e.path)
    if not ok then errors[#errors + 1] = ("%s: %s"):format(e.name, tostring(err)) end
  end
  if #errors > 0 then
    gui.msgbox(("Cannot delete everything.\n\n%s"):format(table.concat(errors, "\n")), "ok", "Delete")
  end
  show()
  frm.lstFiles:pick(math.min(at, #entries))
end

---------------------------------------------------------------- cut, copy and paste

local function things(n) return n == 1 and "1 item" or n .. " items" end

-- updateEdit enables what the Edit menu can do now: cut and copy when
-- something is selected, paste when something was cut or copied.
function updateEdit()
  local any = #entries > 0
  setMenuItem("mnuCut", "enabled", any)
  setMenuItem("mnuCopy", "enabled", any)
  setMenuItem("mnuPaste", "enabled", clip ~= nil and pasting == nil)
end

-- setClip keeps what is selected to paste: cut, which moves it, or copied.
local function setClip(cut)
  local list = selected()
  if #list == 0 then return end
  clip = { paths = {}, cut = cut }
  for _, e in ipairs(list) do clip.paths[#clip.paths + 1] = e.path end
  frm.lblStatus.caption = ("  %s %s%s"):format(cut and "Cut" or "Copied", things(#list),
    cut and ": Paste moves " .. (#list == 1 and "it" or "them") .. " into a folder" or "")
  updateEdit()
end

-- finishPaste is what is done when a paste has run its course: the folder is
-- read again with what was pasted selected, and what happened is said.
local function finishPaste(job, where)
  local at = pasting
  pasting = nil
  if at and at.timer then at.timer:stop() end
  if where == dir then
    show()
    local names = {}
    for _, path in ipairs(job.results) do names[#names + 1] = fs.basename(path) end
    if #names > 0 then frm.lstFiles:selectNames(names) end
  end
  local said
  if job.cancelled then
    said = ("Stopped: %s %s of %s"):format(job.move and "moved" or "copied", things(job.count), things(#job.items))
  else
    said = ("%s %s"):format(job.move and "Moved" or "Pasted", things(job.count))
    if job.skipped > 0 then
      said = said .. (", %d %s there already"):format(job.skipped, job.skipped == 1 and "was" or "were")
    end
  end
  frm.lblStatus.caption = "  " .. said
  if job.move and #job.errors == 0 and not job.cancelled then clip = nil end
  updateEdit()
  if #job.errors > 0 then
    gui.msgbox(("%s\n\n%s"):format(said, table.concat(job.errors, "\n")), "ok", "Paste")
  end
end

-- paste copies or moves what was cut or copied into the folder shown, a
-- piece at a time from a timer, so the window never waits and Escape can
-- stop it.
local function paste()
  if not clip or pasting then return end
  local where = dir
  local job = fs.paste(clip.paths, where, clip.cut)
  job.move = clip.cut
  if job.finished then
    finishPaste(job, where)
    return
  end
  pasting = { job = job }
  updateEdit()
  local function progress()
    local pct = job.total > 0 and math.floor(100 * job.bytes / job.total) or 100
    frm.lblStatus.caption = ("  %s %d of %d: %s (%d%%)  Escape stops it"):format(job.move and "Moving" or "Copying",
      math.min(job.count + 1, #job.items), #job.items, job.current or "", pct)
  end
  progress()
  -- tick is what the timer calls (and the tests): a step of the job.
  pasting.tick = function()
    if job:step() then
      finishPaste(job, where)
      return false
    end
    progress()
    return true
  end
  pasting.timer = gui.every(0.02, pasting.tick)
end

-- stopPaste stops a paste that is going on, what is done staying done.
local function stopPaste()
  if not pasting then return false end
  pasting.job:cancel()
  return true
end

---------------------------------------------------------------- zip files

-- startJob runs an archive job from a timer as paste does, in the place
-- paste has (so Escape stops it and nothing is pasted meanwhile); done(job)
-- says what came of it.
local function startJob(job, verb, done)
  if pasting then return end
  pasting = { job = job }
  updateEdit()
  local function finished()
    if pasting and pasting.timer then pasting.timer:stop() end
    pasting = nil
    updateEdit()
    done(job)
    if #job.errors > 0 then
      gui.msgbox(("%s\n\n%s"):format(frm.lblStatus.caption, table.concat(job.errors, "\n")), "ok", "Zip")
    end
  end
  local function progress()
    local pct = job.total > 0 and math.floor(100 * job.bytes / job.total) or 100
    frm.lblStatus.caption = ("  %s %s (%d%%)  Escape stops it"):format(verb, job.current or "", pct)
  end
  pasting.tick = function()
    if job:step() then
      finished()
      return false
    end
    progress()
    return true
  end
  progress()
  pasting.timer = gui.every(0.02, pasting.tick)
end

-- askZip asks what to call a new zip file and what to lock it with: its
-- path, which is not one already there, and a password or nil.
local function askZip(title, suggestion)
  local name = gui.inputbox("Name of the zip file:", title, suggestion)
  if not name then return end
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" or name:find("[/\\]") then return end
  if not name:lower():find("%.zip$") then name = name .. ".zip" end
  local pw = gui.passwordbox("Password for the zip file (all of it is encrypted).\nLeave it empty for none.", title, true)
  if not pw then return end
  return fs.join(dir, fs.uniqueName(dir, name, false)), pw ~= "" and pw or nil
end

-- makeZip writes a zip file of paths (none: an empty one), and shows it.
local function makeZip(title, suggestion, paths)
  local dest, pw = askZip(title, suggestion)
  if not dest then return end
  local where = dir
  local job = fs.compress(paths, dest, pw)
  startJob(job, "Packing", function(j)
    if where == dir then
      show()
      frm.lstFiles:selectNames { fs.basename(dest) }
    end
    if j.cancelled then
      frm.lblStatus.caption = "  Stopped: no zip file was made"
    elseif #j.errors > 0 and not j.results[1] then
      frm.lblStatus.caption = "  The zip file could not be written"
    else
      frm.lblStatus.caption = ("  Packed %s into %s%s"):format(things(j.count), fs.basename(dest), pw and " (encrypted)" or "")
    end
  end)
end

-- compress packs what is selected, folders with all in them, into a zip file.
local function compress()
  local list = selected()
  if #list == 0 then return end
  local paths = {}
  for i, e in ipairs(list) do paths[i] = e.path end
  local base = #list == 1 and list[1].name:gsub("%.[^.]*$", "") or fs.basename(dir)
  makeZip("Compress", base .. ".zip", paths)
end

-- newZip makes an empty zip file, to add to by dropping files on it.
local function newZip()
  makeZip("New Zip File", "New archive.zip", {})
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
    { "New &Zip File...", name = "newZip", newZip, enabled = pasting == nil },
    { "&Paste", name = "paste", paste, enabled = clip ~= nil and pasting == nil },
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
    -- The apps of ours that open it, and the system's program.
    local with = {}
    for _, name in ipairs(openwith.available(e.path)) do
      with[#with + 1] = { "&" .. (openwith.TITLES[name] or name), name = "with-" .. name,
        function() openWithApp(name, e.path) end }
    end
    if #with > 0 then
      with[#with + 1] = "-"
      with[#with + 1] = { "&System Default", name = "with-system", function() openWithSystem(e.path) end }
      add { "Open &With", with }
    end
  end
  if fs.isArchive(e.name) and not e.dir then
    add "-"
    add { "Open as &Archive...", name = "archive", function() lookInto(e.path) end }
    add { "E&xtract to Folder", name = "extract", function() lookInto(e.path, "folder") end }
  end
  add "-"
  add { "Cu&t", name = "cut", function() setClip(true) end }
  add { "&Copy", name = "copy", function() setClip(false) end }
  add { "&Paste", name = "paste", paste, enabled = clip ~= nil and pasting == nil and e.dir == true and ext ~= "app" }
  add "-"
  add { "Re&name...", name = "rename", rename, shortcut = "F2", enabled = #selected() == 1 }
  add { "&Delete...", name = "delete", delete, shortcut = "Delete" }
  add "-"
  add { "Compress to &Zip...", name = "compress", compress, enabled = pasting == nil }
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
  if key == "Escape" and stopPaste() then return true end
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
  if key == "Escape" then
    if not stopPaste() then frm.lstFiles:focus() end
    return true
  end
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
                           with tlua), or a file in one of turboapps'
                           apps (a picture in the image viewer) or the
                           system's program; Open With in the menu picks
  Backspace                the folder this one is in
  Delete                   delete
  F2                       rename
  Shift+Up, Shift+Down, Shift+click   select several; Cmd+click adds
                           or takes one out; Cmd+A selects all
  Cmd+X, Cmd+C, Cmd+V      cut, copy and paste files and folders
                           (a cut one is moved); Escape stops a paste
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
  mnuCut = function() setClip(true) end,
  mnuCopy = function() setClip(false) end,
  mnuPaste = paste,
  mnuSelectAll = function() frm.lstFiles:selectAll() end,
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
frm.selected = selected
frm.paste, frm.setClip, frm.stopPaste = paste, setClip, stopPaste
frm.clipboard = function() return clip end
frm.pasting = function() return pasting end
frm.lookInto = lookInto
frm.compress = compress
frm.newZip = newZip
frm.state = function()
  return { dir = dir, entries = entries, settings = settings, history = history }
end
frm.go = go
frm.applySettings = applySettings
frm.refreshPlaces, frm.eject = refreshPlaces, eject
frm.places = function() return places, drives end

return frm
