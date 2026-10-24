-- What the image viewer keeps between runs: the folder last shown and how
-- wide its list was. A Lua file in the user's config folder, read back with
-- nothing in its environment.

local lfs = require "lfs"

local M = {}

M.file = nil -- the settings file; the tests set it

function M.path()
  if M.file then return M.file end
  local base = os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or os.getenv("USERPROFILE") or ".") .. "/.config")
  return base .. "/turboapps/imageviewer.lua"
end

function M.load()
  local s = { last = "", split = 0 }
  local fn = loadfile(M.path())
  if fn then
    setfenv(fn, {})
    local ok, t = pcall(fn)
    if ok and type(t) == "table" then
      if type(t.last) == "string" then s.last = t.last end
      if type(t.split) == "number" then s.split = math.floor(t.split) end
    end
  end
  return s
end

function M.save(s)
  local p = M.path()
  local dir = p:match("^(.*)/[^/]*$")
  if dir then
    lfs.mkdir(dir:match("^(.*)/[^/]*$") or dir)
    lfs.mkdir(dir)
  end
  local f = io.open(p, "w")
  if not f then return false end
  f:write(("-- Image Viewer's settings, written by it.\nreturn { last = %q, split = %d }\n"):format(s.last or "", s.split or 0))
  f:close()
  return true
end

return M
