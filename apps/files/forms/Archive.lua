-- The code behind Archive.form.lua: a zip archive's contents in a list, and
-- the buttons that extract it all, or what is selected, into a folder. The
-- controls are fields of the form, by the names the layout gives them.
-- look(path) shows it; it asks for the password of an encrypted archive.

local gui = require "gui"
local fs = require "fs"
local frm = gui.load "Archive" --[[@as forms.Archive]]

local archive  -- what is shown
local running  -- the extraction going on: { job =, timer =, tick = }
local when     -- what is done when it finishes, if anything

local function things(n) return n == 1 and "1 file" or n .. " files" end

local function setEnabled(on)
  for _, c in ipairs { frm.cmdFolder, frm.cmdAll, frm.cmdSelected } do c.enabled = on end
end

-- finish says how an extraction went, and offers its errors.
local function finish(job, dest)
  if running and running.timer then running.timer:stop() end
  running = nil
  setEnabled(true)
  frm.prgJob.value = job.cancelled and frm.prgJob.value or 100
  local said
  if job.cancelled then
    said = ("Stopped: %s of %s unpacked"):format(things(job.count), things(#job.items))
  else
    said = ("Unpacked %s into %s"):format(things(job.count), dest)
  end
  frm.lblStatus.caption = said
  frm.extracted = { dest = dest, count = job.count, results = job.results }
  if #job.errors > 0 then
    gui.msgbox(("%s\n\n%s"):format(said, table.concat(job.errors, "\n")), "ok", "Extract")
  end
  if when then
    local fn = when
    when = nil
    fn()
  end
end

-- extract unpacks names (all when not given) into dest, a piece at a time
-- from a timer, so the window never waits.
local function extract(dest, names)
  if running or not archive then return end
  local job = archive:extract(dest, names)
  running = { job = job }
  setEnabled(false)
  frm.prgJob.value = 0
  local function progress()
    frm.prgJob.value = job.total > 0 and math.floor(100 * job.bytes / job.total) or 0
    frm.lblStatus.caption = ("Unpacking %s ..."):format(job.current or "")
  end
  running.tick = function()
    if job:step() then
      finish(job, dest)
      return false
    end
    progress()
    return true
  end
  if job.finished then
    finish(job, dest)
    return
  end
  progress()
  running.timer = gui.every(0.02, running.tick)
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
  frm.extracted = nil
  frm.caption = fs.basename(path) .. " - Archive"
  frm.lblInfo.caption = ("%s, %s, %s%s"):format(fs.basename(path), things(#a.entries), fs.formatSize(a.total),
    a.encrypted and ", encrypted" or "")
  local items = {}
  for i, e in ipairs(a.entries) do items[i] = ("%s    %s"):format(e.name, fs.formatSize(e.size)) end
  frm.lstEntries.items = items
  frm.prgJob.value = 0
  frm.lblStatus.caption = ""
  setEnabled(#a.entries > 0)
  frm.cmdSelected.enabled = false
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

function frm.lstEntries:onChange()
  frm.cmdSelected.enabled = running == nil and frm.lstEntries.selected > 0
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
  local i = frm.lstEntries.selected
  local e = archive and archive.entries[i]
  if not e then return end
  local dest = choose("Extract To")
  if dest then extract(dest, { e.name }) end
end

function frm.cmdClose:onClick()
  frm:close()
end

-- Closing stops what is being unpacked; what was unpacked stays.
function frm:onClose()
  if running then
    running.job:cancel()
    running.job:step()
    if running then
      if running.timer then running.timer:stop() end
      running = nil
    end
  end
end

-- Exposed for the tests.
frm.pick = extract
frm.running = function() return running end
frm.folderFor = function() return folderFor() end

return frm
