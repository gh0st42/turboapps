-- What ChipStudio keeps between runs: the song last open. A Lua file in the
-- user's config folder, read back with nothing in its environment.

local lfs = require "lfs"

local M = {}

M.file = nil -- the settings file; the tests set it

function M.path()
  if M.file then return M.file end
  local base = os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or os.getenv("USERPROFILE") or ".") .. "/.config")
  return base .. "/turboapps/chipstudio.lua"
end

function M.load()
  local s = { last = "" }
  local fn = loadfile(M.path())
  if fn then
    setfenv(fn, {})
    local ok, t = pcall(fn)
    if ok and type(t) == "table" and type(t.last) == "string" then s.last = t.last end
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
  f:write(("-- ChipStudio's settings, written by it.\nreturn { last = %q }\n"):format(s.last or ""))
  f:close()
  return true
end

return M
