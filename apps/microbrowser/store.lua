-- What microbrowser keeps between runs, with no GUI in it: the bookmarks,
-- the certificate each Gemini capsule showed first, the tabs that were
-- open, the pages visited, the size of the text, and whether pages are in a fixed font and
-- a terminal's colours. It is a Lua file in the user's config
-- folder, read back with nothing in its environment.

local M = {}

M.file = nil -- the settings file; tests set it

function M.path()
  if M.file then return M.file end
  local base = os.getenv("XDG_CONFIG_HOME")
  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or "."
  if package.config:sub(1, 1) == "\\" then base = base or os.getenv("APPDATA") end
  return (base or (home .. "/.config")) .. "/turboapps/microbrowser.lua"
end

local DEFAULTS = { textSize = 15, home = "about:home", mono = false, terminal = false, outline = false }

-- load reads the settings, filling in what they do not have.
function M.load()
  local s = { bookmarks = {}, known = {}, tabs = {}, history = {} }
  for k, v in pairs(DEFAULTS) do s[k] = v end
  local fn = loadfile(M.path())
  if fn then
    setfenv(fn, {})
    local ok, t = pcall(fn)
    if ok and type(t) == "table" then
      for k, v in pairs(t) do
        if s[k] ~= nil and type(v) == type(s[k]) then s[k] = v end
      end
    end
  end
  -- Only well-formed entries come through.
  local marks = {}
  for _, b in ipairs(s.bookmarks) do
    if type(b) == "table" and type(b.url) == "string" then
      marks[#marks + 1] = { title = type(b.title) == "string" and b.title or b.url, url = b.url }
    end
  end
  s.bookmarks = marks
  local tabs = {}
  for _, t in ipairs(s.tabs) do if type(t) == "string" then tabs[#tabs + 1] = t end end
  s.tabs = tabs
  local seen = {}
  for _, h in ipairs(s.history) do
    if type(h) == "table" and type(h.url) == "string" then
      seen[#seen + 1] = { url = h.url, title = type(h.title) == "string" and h.title or h.url,
        time = type(h.time) == "number" and h.time or 0, count = type(h.count) == "number" and h.count or 1 }
    end
  end
  s.history = seen
  return s
end

-- write writes a value as Lua: strings, numbers, booleans and tables of them.
local function write(v, indent, out)
  local t = type(v)
  if t == "string" then out[#out + 1] = ("%q"):format(v):gsub("\\\n", "\\n")
  elseif t == "number" or t == "boolean" then out[#out + 1] = tostring(v)
  elseif t == "table" then
    out[#out + 1] = "{\n"
    local inner = indent .. "  "
    for _, x in ipairs(v) do
      out[#out + 1] = inner
      write(x, inner, out)
      out[#out + 1] = ",\n"
    end
    local keys = {}
    for k in pairs(v) do
      if type(k) == "string" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
      out[#out + 1] = inner
      out[#out + 1] = k:match("^[%a_][%w_]*$") and k or "[" .. ("%q"):format(k) .. "]"
      out[#out + 1] = " = "
      write(v[k], inner, out)
      out[#out + 1] = ",\n"
    end
    out[#out + 1] = indent .. "}"
  else
    out[#out + 1] = "nil"
  end
end

function M.save(s)
  local lfs = require "lfs"
  local path = M.path()
  local dir = path:gsub("\\", "/"):match("^(.*)/[^/]*$")
  if dir then
    lfs.mkdir(dir:match("^(.*)/[^/]*$") or dir)
    lfs.mkdir(dir)
  end
  local out = { "-- microbrowser's settings, written by it.\nreturn " }
  write({ textSize = s.textSize, home = s.home, mono = s.mono, terminal = s.terminal, outline = s.outline,
    bookmarks = s.bookmarks, known = s.known, tabs = s.tabs, history = s.history }, "", out)
  out[#out + 1] = "\n"
  local f = io.open(path, "w")
  if not f then return false end
  f:write(table.concat(out))
  f:close()
  return true
end

---------------------------------------------------------------- bookmarks

-- find is where an address is among the bookmarks, or nil.
function M.find(s, url)
  for i, b in ipairs(s.bookmarks) do
    if b.url == url then return i end
  end
end

-- bookmark adds a page, or gives it its new title; it returns where it is.
function M.bookmark(s, title, url)
  local i = M.find(s, url)
  if i then
    s.bookmarks[i].title = title
    return i
  end
  s.bookmarks[#s.bookmarks + 1] = { title = title, url = url }
  return #s.bookmarks
end

function M.unbookmark(s, i)
  table.remove(s.bookmarks, i)
end

-- move takes bookmark i up (-1) or down (1), and says where it went.
function M.move(s, i, by)
  local j = i + by
  local list = s.bookmarks
  if not list[i] or not list[j] then return i end
  list[i], list[j] = list[j], list[i]
  return j
end

---------------------------------------------------------------- history

-- HISTORY_MAX is how many pages are remembered: the oldest go first.
M.HISTORY_MAX = 1000

-- visit notes that a page was seen at time (os.time() when not given): it
-- goes to the end, the newest, with how many times it has been seen.
function M.visit(s, url, title, time)
  local count = 1
  for i, h in ipairs(s.history) do
    if h.url == url then
      count = h.count + 1
      table.remove(s.history, i)
      break
    end
  end
  s.history[#s.history + 1] = { url = url, title = title or url, time = time or os.time(), count = count }
  while #s.history > M.HISTORY_MAX do table.remove(s.history, 1) end
end

-- recent lists the pages seen, the newest first; with text, only those
-- whose title or address has it (the case of letters aside), or n at most.
function M.recent(s, text, n)
  local want = text and text ~= "" and text:lower() or nil
  local out = {}
  for i = #s.history, 1, -1 do
    local h = s.history[i]
    if not want or h.title:lower():find(want, 1, true) or h.url:lower():find(want, 1, true) then
      out[#out + 1] = h
      if n and #out >= n then break end
    end
  end
  return out
end

-- forget takes a page out of the history.
function M.forget(s, url)
  for i, h in ipairs(s.history) do
    if h.url == url then
      table.remove(s.history, i)
      return true
    end
  end
  return false
end

function M.clearHistory(s)
  s.history = {}
end

---------------------------------------------------------------- certificates

-- check says what to make of a capsule's certificate: "new" the first time
-- it is seen (and remembered), "same" after, "changed" when it is not the
-- one remembered.
function M.check(s, hostport, fingerprint)
  local known = s.known[hostport]
  if not known then
    s.known[hostport] = fingerprint
    return "new"
  end
  return known == fingerprint and "same" or "changed"
end

-- trust remembers a capsule's new certificate.
function M.trust(s, hostport, fingerprint)
  s.known[hostport] = fingerprint
end

return M
