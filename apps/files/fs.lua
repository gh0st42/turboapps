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

---------------------------------------------------------------- settings

M.defaults = {
  showHidden = false,
  foldersFirst = true,
  sortBy = "name",
  descending = false,
  confirmDelete = true,
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
