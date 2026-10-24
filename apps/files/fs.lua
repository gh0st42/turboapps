-- The file manager's dealings with the file system, with no GUI in it:
-- paths, listing a folder, sorting, the back and forward history, the
-- operations on files, and the settings file. Paths use "/" throughout,
-- which Windows takes as well as "\".

local lfs = require "lfs"

local M = {}

M.windows = package.config:sub(1, 1) == "\\"

---------------------------------------------------------------- paths

function M.normalize(path)
  path = path:gsub("\\", "/")
  if #path > 1 and not path:match("^%a:/$") then path = path:gsub("/+$", "") end
  if path == "" then path = "/" end
  return path
end

function M.join(dir, name)
  if dir:sub(-1) == "/" then return dir .. name end
  return dir .. "/" .. name
end

-- parent is the folder holding path; the root is its own parent.
function M.parent(path)
  path = M.normalize(path)
  if path == "/" or path:match("^%a:/?$") then return path end
  local up = path:match("^(.*)/[^/]*$")
  if up == "" then return "/" end
  if up:match("^%a:$") then return up .. "/" end
  return up or path
end

function M.basename(path)
  path = M.normalize(path)
  return path:match("([^/]+)$") or path
end

function M.home()
  return M.normalize(os.getenv("HOME") or os.getenv("USERPROFILE") or "/")
end

-- expand reads what was typed as a path: ~ for home, relative to dir.
function M.expand(text, dir)
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if text == "~" or text:sub(1, 2) == "~/" then text = M.home() .. text:sub(2) end
  if not (text:sub(1, 1) == "/" or text:match("^%a:[/\\]")) then text = M.join(dir, text) end
  -- Make sense of . and .. in it.
  local root, rest = text:match("^(%a:/)(.*)$")
  if not root then root, rest = "/", text:sub(2) end
  local parts = {}
  for part in rest:gmatch("[^/\\]+") do
    if part == ".." then parts[#parts] = nil
    elseif part ~= "." then parts[#parts + 1] = part end
  end
  return M.normalize(root .. table.concat(parts, "/"))
end

function M.isDir(path)
  return lfs.attributes(path, "mode") == "directory"
end

function M.exists(path)
  return lfs.attributes(path) ~= nil
end

---------------------------------------------------------------- what is what

local kinds = {
  ztl = "tlua app", lua = "Lua source", txt = "Text", md = "Markdown",
  png = "PNG image", jpg = "JPEG image", jpeg = "JPEG image", gif = "GIF image",
  svg = "SVG image", pdf = "PDF document", zip = "Zip archive", gz = "Gzip archive",
  tar = "Tar archive", json = "JSON", csv = "CSV", html = "HTML", css = "CSS",
  js = "JavaScript", go = "Go source", c = "C source", h = "C header", sh = "Shell script",
  py = "Python source", mp3 = "MP3 audio", wav = "WAV audio", mp4 = "MP4 video",
  app = "Application", exe = "Program", log = "Log",
}

function M.extension(name)
  return (name:match("%.([^.]+)$") or ""):lower()
end

function M.kindOf(name, isDir)
  local ext = M.extension(name)
  if isDir then return ext == "app" and "Application" or "Folder" end
  if kinds[ext] then return kinds[ext] end
  if ext ~= "" then return ext:upper() .. " file" end
  return "File"
end

function M.hidden(name)
  return name:sub(1, 1) == "."
end

-- size writes a byte count as people read them.
function M.formatSize(n)
  if not n then return "" end
  if n < 1024 then return n .. " B" end
  local units = { "KB", "MB", "GB", "TB" }
  local i = 0
  repeat n, i = n / 1024, i + 1 until n < 1024 or i == #units
  return (n < 10 and "%.1f %s" or "%.0f %s"):format(n, units[i])
end

function M.formatTime(t)
  if not t then return "" end
  return os.date("%Y-%m-%d %H:%M", t)
end

---------------------------------------------------------------- listing

-- list reads a folder. Each entry is { name, path, dir, size, modified,
-- kind, hidden }. It returns the entries (unsorted) and how many hidden
-- ones were left out, or nil and an error.
function M.list(dir, showHidden)
  local ok, iter, state = pcall(lfs.dir, dir)
  if not ok then return nil, tostring(iter) end
  local entries, skipped = {}, 0
  for name in iter, state do
    if name ~= "." and name ~= ".." then
      if M.hidden(name) and not showHidden then
        skipped = skipped + 1
      else
        local path = M.join(dir, name)
        local attr = lfs.attributes(path) or lfs.symlinkattributes(path) or {}
        local isDir = attr.mode == "directory"
        entries[#entries + 1] = {
          name = name, path = path, dir = isDir,
          size = (not isDir) and attr.size or nil,
          modified = attr.modification,
          kind = M.kindOf(name, isDir),
          hidden = M.hidden(name),
        }
      end
    end
  end
  return entries, skipped
end

-- sort orders entries by a column: "name", "size", "modified" or "kind",
-- folders first if asked, names breaking ties without regard to case.
function M.sort(entries, by, descending, foldersFirst)
  by = by or "name"
  table.sort(entries, function(a, b)
    if foldersFirst and a.dir ~= b.dir then return a.dir end
    local x, y
    if by == "size" then x, y = a.size or -1, b.size or -1
    elseif by == "modified" then x, y = a.modified or 0, b.modified or 0
    elseif by == "kind" then x, y = a.kind:lower(), b.kind:lower()
    else x, y = a.name:lower(), b.name:lower() end
    if x == y then
      x, y = a.name:lower(), b.name:lower()
      if x == y then x, y = a.name, b.name end
      if x == y then return false end
      return x < y
    end
    if descending then return x > y end
    return x < y
  end)
  return entries
end

-- findPrefix is the first entry from start on, going round, whose name
-- begins with prefix, ignoring case; for typing to find a file.
function M.findPrefix(entries, prefix, start)
  prefix = prefix:lower()
  local n = #entries
  if n == 0 or prefix == "" then return nil end
  start = start or 1
  for k = 0, n - 1 do
    local i = (start - 1 + k) % n + 1
    if entries[i].name:lower():sub(1, #prefix) == prefix then return i end
  end
  return nil
end

---------------------------------------------------------------- history

local History = {}
History.__index = History

function M.history()
  return setmetatable({ back = {}, forward = {} }, History)
end

-- visit goes to a new place, which forgets the way forward.
function History:visit(from, to)
  if from and from ~= to then
    self.back[#self.back + 1] = from
    self.forward = {}
  end
end

function History:goBack(current)
  local to = table.remove(self.back)
  if to then self.forward[#self.forward + 1] = current end
  return to
end

function History:goForward(current)
  local to = table.remove(self.forward)
  if to then self.back[#self.back + 1] = current end
  return to
end

---------------------------------------------------------------- changing things

local function validName(name)
  if not name or name == "" or name == "." or name == ".." then return false end
  return not name:find("[/\\%z]")
end

function M.mkdir(dir, name)
  if not validName(name) then return nil, "a name cannot be empty or have / or \\ in it" end
  local path = M.join(dir, name)
  if M.exists(path) then return nil, name .. " is there already" end
  local ok, err = lfs.mkdir(path)
  if not ok then return nil, err end
  return path
end

function M.rename(path, newName)
  if not validName(newName) then return nil, "a name cannot be empty or have / or \\ in it" end
  local to = M.join(M.parent(path), newName)
  if to == path then return to end
  if M.exists(to) then return nil, newName .. " is there already" end
  local ok, err = os.rename(path, to)
  if not ok then return nil, err end
  return to
end

-- count says how many files and folders a delete of path would remove.
function M.count(path)
  if lfs.symlinkattributes(path, "mode") ~= "directory" then return 1 end
  local n = 1
  for name in lfs.dir(path) do
    if name ~= "." and name ~= ".." then n = n + M.count(M.join(path, name)) end
  end
  return n
end

-- remove deletes a file, or a folder and all that is in it. A link to a
-- folder is removed, not followed.
function M.remove(path)
  if lfs.symlinkattributes(path, "mode") == "directory" then
    for name in lfs.dir(path) do
      if name ~= "." and name ~= ".." then
        local ok, err = M.remove(M.join(path, name))
        if not ok then return nil, err end
      end
    end
    return lfs.rmdir(path)
  end
  return os.remove(path)
end

---------------------------------------------------------------- copying and moving

-- uniqueName is a name for a copy of name in dir that is not taken: the
-- name itself when it is free, else "a copy.txt", "a copy 2.txt", and so on
-- (the end of a folder's name is not an extension).
function M.uniqueName(dir, name, isDir)
  local function taken(n)
    local path = M.join(dir, n)
    return M.exists(path) or lfs.symlinkattributes(path) ~= nil
  end
  if not taken(name) then return name end
  local base, ext = name, ""
  if not isDir then
    local b, e = name:match("^(.+)(%.[^.]+)$")
    if b then base, ext = b, e end
  end
  local n = 1
  while true do
    local candidate = base .. " copy" .. (n > 1 and (" " .. n) or "") .. ext
    if not taken(candidate) then return candidate end
    n = n + 1
  end
end

-- size is how many bytes a file, or a folder and all in it, takes; links
-- are not followed.
function M.size(path)
  local mode = lfs.symlinkattributes(path, "mode")
  if mode == "directory" then
    local n = 0
    for name in lfs.dir(path) do
      if name ~= "." and name ~= ".." then n = n + M.size(M.join(path, name)) end
    end
    return n
  end
  return mode == "file" and lfs.attributes(path, "size") or 0
end

-- within says whether path is dir or something in it.
local function within(path, dir)
  path, dir = M.normalize(path), M.normalize(dir)
  return path == dir or path:sub(1, #dir + 1) == dir:gsub("/$", "") .. "/"
end

local CHUNK = 1024 * 1024

-- quote makes text one word for the shell.
local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

-- copyMode gives a copy the permissions of what it is a copy of, which a
-- program that copies only the bytes loses (an executable stops being
-- one). Only the owner's, group's and others' bits, and only where there is
-- a shell and anything beyond the usual to give.
local function copyMode(from, to)
  if M.windows then return end
  local perms = lfs.attributes(from, "permissions")
  if not perms or not perms:find("x") then return end
  local mode = 0
  for i = 1, 9 do
    if perms:sub(i, i) ~= "-" then mode = mode + 2 ^ (9 - i) end
  end
  os.execute(("chmod %o %s"):format(mode, quote(to)))
end

local Job = {}
Job.__index = Job

-- copyFile copies a file a chunk at a time, giving the program back (the
-- job is a coroutine) when the chunks have used up what a step was given.
local function copyFile(job, from, to)
  local rf, err = io.open(from, "rb")
  if not rf then return nil, err end
  local wf, werr = io.open(to, "wb")
  if not wf then rf:close() return nil, werr end
  local function give_up(why)
    rf:close(); wf:close()
    os.remove(to)
    return nil, why
  end
  while true do
    if job.cancelled then return give_up("cancelled") end
    local chunk = rf:read(math.min(CHUNK, job.budget))
    if not chunk then break end
    local ok, e = wf:write(chunk)
    if not ok then return give_up(e) end
    job.bytes = job.bytes + #chunk
    job.spent = job.spent + #chunk
    if job.spent >= job.budget then
      job.spent = 0
      coroutine.yield()
    end
  end
  rf:close(); wf:close()
  local a = lfs.attributes(from)
  if a then lfs.touch(to, a.access, a.modification) end
  copyMode(from, to)
  return true
end

-- copyTree copies a file, a link or a folder with all in it. What cannot be
-- copied is noted in job.errors and the rest goes on; it says whether it
-- all went.
local function copyTree(job, from, to)
  local mode = lfs.symlinkattributes(from, "mode")
  job.current = M.basename(from)
  if mode == "link" then
    local ok, err = lfs.link(lfs.symlinkattributes(from, "target"), to, true)
    if not ok then job.errors[#job.errors + 1] = M.basename(from) .. ": " .. tostring(err) end
    return ok
  elseif mode == "directory" then
    local ok, err = lfs.mkdir(to)
    if not ok then
      job.errors[#job.errors + 1] = M.basename(from) .. ": " .. tostring(err)
      return false
    end
    local names = {}
    for name in lfs.dir(from) do
      if name ~= "." and name ~= ".." then names[#names + 1] = name end
    end
    table.sort(names)
    local all = true
    for _, name in ipairs(names) do
      if job.cancelled then return false end
      all = copyTree(job, M.join(from, name), M.join(to, name)) and all
    end
    return all
  end
  local ok, err = copyFile(job, from, to)
  if not ok and err ~= "cancelled" then job.errors[#job.errors + 1] = M.basename(from) .. ": " .. tostring(err) end
  return ok
end

local function runJob(job)
  for _, item in ipairs(job.items) do
    if job.cancelled then break end
    job.current = item.name
    local done = false
    -- A move on the same disk is a rename; across disks it is a copy, then
    -- the original taken away.
    if item.move and os.rename(item.from, item.to) then
      job.bytes = job.bytes + item.size
      done = true
    else
      done = copyTree(job, item.from, item.to)
      if done and item.move then
        local ok, err = M.remove(item.from)
        if not ok then
          job.errors[#job.errors + 1] = item.name .. ": copied, but not taken from where it was: " .. tostring(err)
          done = false
        end
      end
    end
    if done then
      job.count = job.count + 1
      job.results[#job.results + 1] = item.to
    end
  end
  job.finished = true
end

-- paste makes a job of copying paths into the folder dest, or of moving
-- them there when move is true. An item that is there already is given
-- a name that is not taken ("a copy.txt"); a folder cannot go into itself,
-- and a move to the folder it is in is nothing to do. The job is run with
-- job:step(), which does some of it and says whether it is all done, and
-- can be stopped with job:cancel():
--
--   job.total, job.bytes     how much there is to do, and how much is done
--   job.current              the name of what it is at
--   job.count, job.results   how many of the paths are in, and where
--   job.errors               what went wrong, as text, a line each
--   job.skipped              how many a move left alone, being there already
function M.paste(paths, dest, move)
  dest = M.normalize(dest)
  local job = setmetatable({ items = {}, total = 0, bytes = 0, count = 0, results = {}, errors = {},
    skipped = 0, spent = 0, budget = CHUNK, finished = false }, Job)
  for _, path in ipairs(paths) do
    path = M.normalize(path)
    local name = M.basename(path)
    local mode = lfs.symlinkattributes(path, "mode")
    if not mode then
      job.errors[#job.errors + 1] = name .. ": it is not there any more"
    elseif mode == "directory" and within(dest, path) then
      job.errors[#job.errors + 1] = name .. ": a folder cannot go into itself"
    elseif move and M.parent(path) == dest then
      job.skipped = job.skipped + 1
    else
      local size = M.size(path)
      job.total = job.total + size
      job.items[#job.items + 1] = {
        from = path, to = M.join(dest, M.uniqueName(dest, name, mode == "directory")),
        name = name, move = move, size = size,
      }
    end
  end
  job.co = coroutine.create(function() runJob(job) end)
  if #job.items == 0 then job.finished = true end
  return job
end

-- step does some of the job: up to budget bytes (4 MB without one). It says
-- whether the job is finished.
function Job:step(budget)
  if self.finished then return true end
  self.budget, self.spent = budget or 4 * CHUNK, 0
  local ok, err = coroutine.resume(self.co)
  if not ok then
    self.errors[#self.errors + 1] = tostring(err)
    self.finished = true
  end
  return self.finished
end

-- cancel stops it at the next chunk; what was copied already stays.
function Job:cancel()
  self.cancelled = true
end

---------------------------------------------------------------- places

-- places are the folders listed on the left: home and the usual ones in
-- it that are there, and the root of the disk.
function M.places()
  local home = M.home()
  local list = { { "Home", home } }
  for _, name in ipairs { "Desktop", "Documents", "Downloads", "Pictures", "Music" } do
    local path = M.join(home, name)
    if M.isDir(path) then list[#list + 1] = { name, path } end
  end
  if M.windows then
    for letter in ("CDEFGH"):gmatch(".") do
      if M.isDir(letter .. ":/") then list[#list + 1] = { letter .. ":", letter .. ":/" } end
    end
  else
    list[#list + 1] = { "Computer", "/" }
    if M.isDir("/Volumes") then list[#list + 1] = { "Volumes", "/Volumes" } end
  end
  return list
end

---------------------------------------------------------------- drives

-- Drives are what Linux mounts by itself when they are plugged in: USB
-- sticks, SD cards, discs. udisks puts them under /media/<user> or
-- /run/media/<user>, as the system's mount table says. The tests point
-- these elsewhere.
M.mountsFile = "/proc/self/mounts"
M.mediaRoots = { "/media/", "/run/media/" }

-- unoctal reads the mount table's escapes: \040 is a space.
local function unoctal(s)
  return (s:gsub("\\(%d%d%d)", function(o) return string.char(tonumber(o, 8)) end))
end

-- drives lists the drives mounted now, by their names: name, path, the
-- device and its file system. text is the mount table, read when not given.
function M.drives(text)
  if not text then
    local f = io.open(M.mountsFile)
    if not f then return {} end
    text = f:read("*a")
    f:close()
  end
  local list = {}
  for line in text:gmatch("[^\n]+") do
    local device, path, fstype = line:match("^(%S+)%s+(%S+)%s+(%S+)")
    if device then
      path = unoctal(path)
      for _, root in ipairs(M.mediaRoots) do
        if path:sub(1, #root) == root and #path > #root then
          list[#list + 1] = { name = M.basename(path), path = M.normalize(path),
            device = unoctal(device), fstype = fstype }
          break
        end
      end
    end
  end
  table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
  return list
end

-- driveOf is the drive a path is on, or nil.
function M.driveOf(path, drives)
  path = M.normalize(path)
  for _, d in ipairs(drives) do
    if path == d.path or path:sub(1, #d.path + 1) == d.path .. "/" then return d end
  end
end

-- diskOf is the whole disk a partition is on: /dev/sdb1 is on /dev/sdb,
-- /dev/nvme0n1p2 on /dev/nvme0n1, /dev/mmcblk0p1 on /dev/mmcblk0.
function M.diskOf(device)
  local disk = device:match("^(/dev/nvme%d+n%d+)p%d+$") or device:match("^(/dev/mmcblk%d+)p%d+$")
    or device:match("^(/dev/[hsv]d%a+)%d+$")
  return disk or device
end

-- which finds a program on the PATH, or nil.
function M.which(name)
  for dir in (os.getenv("PATH") or ""):gmatch("[^:]+") do
    local path = M.join(dir, name)
    if lfs.attributes(path, "mode") == "file" then return path end
  end
end

-- ejectSteps are the commands that take a drive out safely, run one after
-- another: with udisks, unmounting it and then switching the disk off (a
-- disk that cannot be switched off, a card reader's say, is still safe
-- to take out, so that step may fail); else gio, else umount. which says
-- whether a program is there; nil when there is none of them.
function M.ejectSteps(drive, which)
  which = which or M.which
  if which("udisksctl") then
    local steps = { { cmd = { "udisksctl", "unmount", "-b", drive.device } } }
    if drive.device:find("^/dev/") then
      steps[2] = { cmd = { "udisksctl", "power-off", "-b", M.diskOf(drive.device) }, optional = true }
    end
    return steps
  end
  if which("gio") then return { { cmd = { "gio", "mount", "-e", drive.path } } } end
  if which("umount") then return { { cmd = { "umount", drive.path } } } end
end

---------------------------------------------------------------- settings

M.defaults = {
  showHidden = false,
  foldersFirst = true,
  sortBy = "name",
  descending = false,
  confirmDelete = true,
  openWithApps = true,
}

-- settingsFile, when set, is where the settings are kept instead; the
-- tests use it to keep away from the real ones.
M.settingsFile = nil

function M.settingsPath()
  if M.settingsFile then return M.settingsFile end
  local base = os.getenv("XDG_CONFIG_HOME")
  if M.windows then base = base or os.getenv("APPDATA") end
  base = base or M.join(M.home(), ".config")
  return M.join(M.join(base, "turboapps"), "files.lua")
end

-- loadSettings reads the settings file, run with nothing in scope, and
-- fills in what it does not say from the defaults.
function M.loadSettings(path)
  local s = {}
  for k, v in pairs(M.defaults) do s[k] = v end
  local fn = loadfile(path or M.settingsPath())
  if fn then
    setfenv(fn, {})
    local ok, t = pcall(fn)
    if ok and type(t) == "table" then
      for k, v in pairs(t) do
        if M.defaults[k] ~= nil and type(v) == type(M.defaults[k]) then s[k] = v end
      end
    end
  end
  return s
end

function M.saveSettings(s, path)
  path = path or M.settingsPath()
  lfs.mkdir(M.parent(M.parent(path)))
  lfs.mkdir(M.parent(path))
  local keys = {}
  for k in pairs(M.defaults) do keys[#keys + 1] = k end
  table.sort(keys)
  local lines = { "-- The file manager's settings, written by it.", "return {" }
  for _, k in ipairs(keys) do
    lines[#lines + 1] = ("  %s = %s,"):format(k, type(s[k]) == "string" and ("%q"):format(s[k]) or tostring(s[k]))
  end
  lines[#lines + 1] = "}"
  local f, err = io.open(path, "w")
  if not f then return nil, err end
  f:write(table.concat(lines, "\n"), "\n")
  f:close()
  return true
end

---------------------------------------------------------------- opening

-- opener is the command that opens a file, or shows a folder, with what
-- the system has for it. platform is gui.platform: "darwin", "windows",
-- or anything else for the freedesktop way.
function M.opener(path, platform)
  if platform == "windows" or (not platform and M.windows) then
    return { "cmd", "/c", "start", "", (path:gsub("/", "\\")) }
  end
  if platform == "darwin" then return { "open", path } end
  return { "xdg-open", path }
end

return M
