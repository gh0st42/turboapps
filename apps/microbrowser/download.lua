-- Downloads, with no GUI in it: files that come from a capsule or a hole
-- while the browser goes on, each written to disk as it arrives. A request
-- (net.lua) is given a sink by begin; the rest is poll, from a timer.
--
--   local d = download.begin(job, download.folder(), "file.bin")
--   -- net.request's download hook returns d.sink
--   download.poll()        -- every tick; true while any is going on
--   download.list          -- all of them, oldest first
--
-- A download is { name, path, url, state, received, why, started, ... }
-- and its state is "receiving", "done", "stopped" (cancelled) or "failed".

local lfs = require "lfs"
local socket = require "socket"

local M = {}

M.list = {}
M.onChange = nil -- called with a download when its state changes

local function home()
  return ((os.getenv("HOME") or os.getenv("USERPROFILE") or "."):gsub("\\", "/"))
end

-- folder is where downloads go: the one given, else the Downloads folder
-- of the home folder (made if it is not there), else the home folder.
function M.folder(configured)
  if configured and configured ~= "" and lfs.attributes(configured, "mode") == "directory" then return configured end
  local dir = home() .. "/Downloads"
  if lfs.attributes(dir, "mode") == "directory" then return dir end
  if lfs.mkdir(dir) then return dir end
  return home()
end

-- clean makes a name from an address safe to be a file's.
local function clean(name)
  name = (name or ""):gsub("[/\\:%c]", "_"):gsub("^%.+", "")
  if name == "" then name = "download" end
  return name
end

-- uniquePath is a path in dir for name that is not taken: "a.txt", then
-- "a (2).txt", "a (3).txt".
function M.uniquePath(dir, name)
  name = clean(name)
  local function taken(n) return lfs.attributes(dir .. "/" .. n) ~= nil end
  if not taken(name) then return dir .. "/" .. name end
  local base, ext = name:match("^(.+)(%.[^.]+)$")
  base, ext = base or name, ext or ""
  local n = 2
  while taken(("%s (%d)%s"):format(base, n, ext)) do n = n + 1 end
  return dir .. "/" .. ("%s (%d)%s"):format(base, n, ext)
end

local function changed(d)
  if M.onChange then M.onChange(d) end
end

-- begin makes a download of what a request will give, into a new file in
-- dir called name (or something like it). It gives nil and why when the file
-- cannot be made. d.sink is for net.request.
function M.begin(job, dir, name)
  local path = M.uniquePath(dir, name)
  local file, err = io.open(path, "wb")
  if not file then return nil, err end
  local d = { name = path:match("[^/]+$"), path = path, url = job.url, job = job, file = file,
    state = "receiving", received = 0, started = socket.gettime() }
  d.sink = function(chunk)
    local ok, werr = file:write(chunk)
    if not ok then return nil, werr end
    d.received = d.received + #chunk
    return true
  end
  M.list[#M.list + 1] = d
  changed(d)
  return d
end

-- save makes a download of a body that is here already, written at once.
function M.save(dir, name, body)
  local path = M.uniquePath(dir, name)
  local file, err = io.open(path, "wb")
  if not file then return nil, err end
  file:write(body)
  file:close()
  local d = { name = path:match("[^/]+$"), path = path, received = #body, state = "done", started = socket.gettime() }
  d.finished = d.started
  M.list[#M.list + 1] = d
  changed(d)
  return d
end

-- finish closes the file of a download whose request is over: kept when
-- it came whole, taken away when it did not.
local function finish(d)
  if d.file then
    d.file:close()
    d.file = nil
  end
  d.finished = socket.gettime()
  local err = d.job and d.job.err
  if err == "stopped" then
    d.state = "stopped"
  elseif err then
    d.state, d.why = "failed", err
  else
    d.state = "done"
  end
  if d.state ~= "done" then os.remove(d.path) end
  d.job = nil
  changed(d)
end

-- cancel stops a download that is going on, and takes its file away.
function M.cancel(d)
  if d.state ~= "receiving" then return end
  d.job:cancel()
  finish(d)
end

-- poll moves every download on, and says whether any is still going.
function M.poll()
  local busy = false
  for _, d in ipairs(M.list) do
    if d.state == "receiving" then
      if d.job:poll() then finish(d) else busy = true end
    end
  end
  return busy
end

-- active is how many are going on.
function M.active()
  local n = 0
  for _, d in ipairs(M.list) do
    if d.state == "receiving" then n = n + 1 end
  end
  return n
end

-- remove takes a finished download out of the list (not its file).
function M.remove(d)
  if d.state == "receiving" then return false end
  for i, x in ipairs(M.list) do
    if x == d then table.remove(M.list, i) return true end
  end
  return false
end

-- clear takes all the finished ones out of the list.
function M.clear()
  local keep = {}
  for _, d in ipairs(M.list) do
    if d.state == "receiving" then keep[#keep + 1] = d end
  end
  M.list = keep
end

local function size(n)
  if n < 1024 then return n .. " B" end
  local units = { "KB", "MB", "GB" }
  local i = 0
  repeat n, i = n / 1024, i + 1 until n < 1024 or i == #units
  return (n < 10 and "%.1f %s" or "%.0f %s"):format(n, units[i])
end
M.size = size

-- describe is what a download is doing, in words.
function M.describe(d)
  if d.state == "receiving" then
    local secs = math.max(0.001, socket.gettime() - d.started)
    return ("%s so far, %s/s"):format(size(d.received), size(d.received / secs))
  elseif d.state == "done" then
    return "done, " .. size(d.received)
  elseif d.state == "stopped" then
    return "stopped"
  end
  return "failed: " .. tostring(d.why)
end

return M
