-- The code behind Archive.form.lua: a zip archive's contents in a list, to
-- unpack all or some of, and to change: files added (by a button, or
-- dropped on the window), deleted, and the whole of it encrypted or not. The
-- controls are fields of the form, by the names the layout gives them.
-- look(path) shows it; it asks for the password of an encrypted archive.

local gui = require "gui"
local fs = require "fs"
local frm = gui.load "Archive" --[[@as forms.Archive]]

local archive  -- what is shown
local running  -- the job going on: { job =, timer =, tick = }
local when     -- what is done when it finishes, if anything

local function things(n) return n == 1 and "1 file" or n .. " files" end

local function setEnabled(on)
  local some = on and archive and #archive.entries > 0
  for _, c in ipairs { frm.cmdFolder, frm.cmdAll } do c.enabled = some end
  frm.cmdSelected.enabled = some
  frm.cmdDelete.enabled = some
  frm.cmdAdd.enabled, frm.cmdAddFolder.enabled, frm.cmdPassword.enabled = on, on, on
end

-- names are the files selected in the list.
local function names()
  local out = {}
  for _, row in ipairs(frm.lstEntries:selectedRows()) do out[#out + 1] = row.name end
  return out
end

-- showEntries puts the archive's files in the list.
local function showEntries()
  local a = archive
  frm.caption = fs.basename(a.path) .. " - Archive"
  frm.lblInfo.caption = ("%s, %s, %s%s"):format(fs.basename(a.path), things(#a.entries), fs.formatSize(a.total),
    a.encrypted and ", encrypted" or "")
  local rows = {}
  for i, e in ipairs(a.entries) do
    rows[i] = { name = e.name, icon = "file",
      cells = { e.name, fs.formatSize(e.size), e.modified and fs.formatTime(e.modified) or "",
        e.encrypted and "encrypted" or "" } }
  end
  frm.lstEntries.cols = { { title = "Name" }, { title = "Size", width = 80, align = "right" },
    { title = "Modified", width = 130 }, { title = "", width = 80 } }
  frm.lstEntries:setRows(rows)
  setEnabled(running == nil)
end

-- finish stops the timer and goes on to what is to be done.
local function stop()
  if running and running.timer then running.timer:stop() end
  running = nil
end

-- start runs a job a piece at a time from a timer, so the window never
-- waits; done(job) is called when it has run its course. Its errors are
-- shown.
local function start(job, verb, done)
  if running or not archive then return end
  running = { job = job }
  setEnabled(false)
  frm.prgJob.value = 0
  local function finished()
    stop()
    frm.prgJob.value = job.cancelled and frm.prgJob.value or 100
    done(job)
    if #job.errors > 0 then
      gui.msgbox(("%s\n\n%s"):format(frm.lblStatus.caption, table.concat(job.errors, "\n")), "ok", "Archive")
    end
    if when then
      local fn = when
      when = nil
      fn()
    end
  end
  local function progress()
    frm.prgJob.value = job.total > 0 and math.floor(100 * job.bytes / job.total) or 0
    frm.lblStatus.caption = ("%s %s ..."):format(verb, job.current or "")
  end
  running.tick = function()
    if job:step() then
      finished()
      return false
    end
    progress()
    return true
  end
  if job.finished then
    finished()
    return
  end
  progress()
  running.timer = gui.every(0.02, running.tick)
end

-- extract unpacks names (all when not given) into dest.
local function extract(dest, list)
  if running or not archive then return end
  local job = archive:extract(dest, list)
  start(job, "Unpacking", function(j)
    if j.cancelled then
      frm.lblStatus.caption = ("Stopped: %s unpacked"):format(things(j.count))
    else
      frm.lblStatus.caption = ("Unpacked %s into %s"):format(things(j.count), dest)
    end
    frm.extracted = { dest = dest, count = j.count, results = j.results }
    setEnabled(true)
  end)
end

-- change rewrites the archive (see fs's Archive:rewrite) and shows it as it
-- is then.
local function change(opts, said)
  if running or not archive then return end
  local pw = opts.password
  if pw == nil then pw = archive.password elseif pw == false then pw = nil end
  local job = archive:rewrite(opts)
  start(job, "Writing", function(j)
    if j.cancelled then
      frm.lblStatus.caption = "Stopped: the archive is as it was"
    elseif #j.errors > 0 then
      frm.lblStatus.caption = "The archive could not be written, and is as it was"
    else
      local a, why = fs.archive(archive.path, pw)
      if a then archive = a else frm.lblStatus.caption = tostring(why) end
      frm.lblStatus.caption = said(j)
      frm.changed = true
    end
    showEntries()
  end)
end

-- addPaths puts files and folders (as paths) in the archive.
local function addPaths(paths)
  local files = fs.collect(paths, archive.path)
  if #files == 0 then
    frm.lblStatus.caption = "There are no files to add"
    return
  end
  change({ add = files }, function(j)
    local said = ("Added %s"):format(things(j.count))
    if j.replaced > 0 then said = said .. (", replacing %d"):format(j.replaced) end
    return said
  end)
end

-- folderFor is a new folder beside the archive, named after it.
local function folderFor()
  local dir = fs.parent(archive.path)
  local stem = fs.basename(archive.path):gsub("%.[^.]*$", "")
  return fs.join(dir, fs.uniqueName(dir, stem, true))
end

-- fill reads the archive at path into the window, asking for its password
-- when it has one, and says whether it could be opened. With how = "folder"
-- it is to be unpacked at once into a folder of its own, and the window
-- goes. look does this and shows the window.
function frm.fill(path, how)
  local a, err, why = fs.archive(path)
  while not a and why == "locked" do
    local pw = gui.passwordbox((err:find("wrong", 1, true) and "Wrong password. " or "")
      .. fs.basename(path) .. " is encrypted.\nPassword:", "Open Archive")
    if not pw then return false end
    a, err, why = fs.archive(path, pw)
  end
  if not a then
    gui.msgbox(("Cannot open %s.\n\n%s"):format(path, tostring(err)), "ok", "Archive")
    return false
  end
  archive, running, when = a, nil, nil
  frm.extracted, frm.changed = nil, nil
  frm.prgJob.value = 0
  frm.lblStatus.caption = ""
  showEntries()
  if how == "folder" then
    when = function() frm:close() end
    gui.after(0, function() extract(folderFor()) end)
  end
  return true
end

function frm.look(path, how)
  if not frm.fill(path, how) then return false end
  frm:showModal()
  return true
end

function frm.cmdFolder:onClick()
  extract(folderFor())
end

local function choose(title)
  return gui.choosedir { title = title, dir = fs.parent(archive.path) }
end

function frm.cmdAll:onClick()
  local dest = choose("Extract All To")
  if dest then extract(dest) end
end

function frm.cmdSelected:onClick()
  local list = names()
  if #list == 0 then return end
  local dest = choose("Extract To")
  if dest then extract(dest, list) end
end

function frm.cmdAdd:onClick()
  local paths = gui.openfile { title = "Add Files", multiple = true, dir = fs.parent(archive.path) }
  if paths and #paths > 0 then addPaths(paths) end
end

function frm.cmdAddFolder:onClick()
  local dir = gui.choosedir { title = "Add Folder", dir = fs.parent(archive.path) }
  if dir then addPaths { dir } end
end

-- deleteSelected takes the selected files out of the archive, once asked.
local function deleteSelected()
  local list = names()
  if #list == 0 or running then return end
  local what = #list == 1 and list[1] or things(#list)
  if gui.msgbox(("Take %s out of the archive?\n\nThis cannot be undone."):format(what), "yesno", "Delete") ~= "yes" then return end
  change({ remove = list }, function(j) return ("Deleted %s"):format(things(j.removed)) end)
end

function frm.cmdDelete:onClick()
  deleteSelected()
end

function frm.cmdPassword:onClick()
  if running or not archive then return end
  local pw = gui.passwordbox("Password for the archive: all of it is encrypted.\nLeave it empty to remove the password.",
    "Password", true)
  if not pw then return end
  change({ password = pw ~= "" and pw or false }, function()
    return pw ~= "" and "The archive is encrypted" or "The archive is not encrypted any more"
  end)
end

-- Keys the list has no use for: Delete takes the files out.
function frm.lstEntries:onCommand(key)
  if key == "Delete" or key == "Backspace" then
    deleteSelected()
    return true
  end
  return false
end

-- Files and folders dropped on the window go into the archive.
function frm:onDrop(text, lines)
  if running or not archive or not lines or #lines == 0 then return end
  addPaths(lines)
end

function frm.cmdClose:onClick()
  frm:close()
end

-- Closing stops what is being done: an unpack leaves what came out, a
-- change leaves the archive as it was.
function frm:onClose()
  if running then
    running.job:cancel()
    running.job:step()
    stop()
  end
end

-- Exposed for the tests.
frm.running = function() return running end
frm.archive = function() return archive end
frm.names = names
frm.addPaths = addPaths
frm.deleteSelected = deleteSelected
frm.folderFor = function() return folderFor() end

return frm
