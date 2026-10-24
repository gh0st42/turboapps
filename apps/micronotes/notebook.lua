-- A notebook: notes in folders, with the pictures and files added to them,
-- kept in one .znb file. A .znb is a zip laid out as a folder of notes
-- would be, so unzipped it is a vault other Markdown tools open:
--
--   notebook.json            the folders (empty ones too) and the note open
--   Welcome.md               a note: Markdown, by its path
--   Projects/Roadmap.md
--   attachments/diagram.png  pictures and files the notes show or link to
--
-- Notes link to each other with [[Note Name]], found by name anywhere in
-- the notebook, and to attachments by their path from the top:
-- ![diagram](attachments/diagram.png).

local zip = require "zip"
local png = require "png"
local lfs = require "lfs"
local md = require "markdown"

local M = {}

M.EXT = "znb"
M.MANIFEST = "notebook.json"
M.ATTACHMENTS = "attachments"

local Notebook = {}
Notebook.__index = Notebook

---------------------------------------------------------------- paths

-- clean makes a path in the notebook steady: "/" between parts, none at
-- either end, no "." or "..". It is nil for one that would leave it.
function M.clean(path)
  local parts = {}
  for part in tostring(path or ""):gsub("\\", "/"):gmatch("[^/]+") do
    if part == ".." then return nil end
    if part ~= "." then parts[#parts + 1] = part end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, "/")
end

function M.dirname(path) return path:match("^(.*)/[^/]*$") or "" end
function M.basename(path) return path:match("[^/]*$") end
function M.join(dir, name)
  if not dir or dir == "" then return name end
  return dir .. "/" .. name
end

-- title is what a note is called: its file's name without .md.
function M.title(path) return (M.basename(path):gsub("%.md$", "")) end

function M.isNote(path) return path:lower():match("%.md$") ~= nil end

local IMAGES = { png = true, jpg = true, jpeg = true, gif = true, bmp = true }
function M.isPicture(path)
  return IMAGES[(path:match("%.(%w+)$") or ""):lower()] ~= nil
end

-- A name a note or folder can have: not empty, and no / \ : * ? " < > |
-- or # ^ [ ] that would break a [[link]].
function M.validName(name)
  if not name or name:match("^%s*$") then return false, "A name cannot be empty." end
  if name:match('[/\\:%*%?"<>|#%^%[%]]') then
    return false, "A name cannot have / \\ : * ? \" < > | # ^ [ or ] in it."
  end
  if name:match("^%.") then return false, "A name cannot start with a dot." end
  return true
end

---------------------------------------------------------------- the notebook

M.WELCOME = [==[
# Welcome

This is a notebook: notes in folders, kept together in one `.znb` file with
the pictures and files you add to them.

- **New note**: Cmd+N, or the + above the list. Notes are Markdown, edited
  as they look.
- **Links**: type `[[` and pick a note, or write [[Ideas]] in full. Cmd-click
  (Ctrl-click) a link to follow it; a note that is not there yet is made.
- **Pictures and files**: drag them onto a note, or Insert > Picture / File.
- **Views**: Edit, Read and Source, at the top right or Cmd+E.
- **Backlinks**: the notes that link to this one are listed at the bottom left.
]==]

-- new makes a notebook with a note to start from.
function M.new(withWelcome)
  local nb = setmetatable({ notes = {}, files = {}, folders = {}, images = {}, dirty = false }, Notebook)
  if withWelcome ~= false then
    nb.notes["Welcome.md"] = M.WELCOME
    nb.notes["Ideas.md"] = "# Ideas\n\nLinked from [[Welcome]].\n"
    nb.open = "Welcome.md"
  end
  return nb
end

-- folder paths, sorted; every note's and file's folders are folders too.
function Notebook:allFolders()
  local set = {}
  local function add(dir)
    while dir ~= "" do
      set[dir] = true
      dir = M.dirname(dir)
    end
  end
  for f in pairs(self.folders) do add(f) end
  for p in pairs(self.notes) do add(M.dirname(p)) end
  for p in pairs(self.files) do add(M.dirname(p)) end
  local list = {}
  for f in pairs(set) do list[#list + 1] = f end
  table.sort(list, function(a, b) return a:lower() < b:lower() end)
  return list, set
end

function Notebook:exists(path)
  local _, folders = self:allFolders()
  return self.notes[path] ~= nil or self.files[path] ~= nil or folders[path] == true
end

-- notePaths lists the notes, sorted by path.
function Notebook:notePaths()
  local list = {}
  for p in pairs(self.notes) do list[#list + 1] = p end
  table.sort(list, function(a, b) return a:lower() < b:lower() end)
  return list
end

-- items is the tree a Tree shows: folders first, then notes by title,
-- then files; open lists the folders shown open, by path. With only (a
-- list of note paths), just those notes show, in their folders, opened.
function Notebook:items(open, only)
  open = open or {}
  local keep
  if only then
    keep = {}
    for _, p in ipairs(only) do keep[p] = true end
  end
  local root = { children = {}, dirs = {} }
  local function dirNode(path)
    if path == "" then return root end
    local parent = dirNode(M.dirname(path))
    local name = M.basename(path)
    local node = parent.dirs[name]
    if not node then
      node = { name = name, path = path, children = {}, dirs = {} }
      parent.dirs[name] = node
    end
    return node
  end
  if not keep then
    for _, f in ipairs(self:allFolders()) do dirNode(f) end
  end
  for p in pairs(self.notes) do
    if not keep or keep[p] then
      local n = dirNode(M.dirname(p))
      n.children[#n.children + 1] = { label = M.title(p), sort = "1" .. M.title(p):lower() }
    end
  end
  for p in pairs(self.files) do
    if not keep then
      local n = dirNode(M.dirname(p))
      n.children[#n.children + 1] = { label = M.basename(p), sort = "2" .. M.basename(p):lower() }
    end
  end
  local function build(node)
    local out = {}
    local dirs = {}
    for name, d in pairs(node.dirs) do dirs[#dirs + 1] = d end
    table.sort(dirs, function(a, b) return a.name:lower() < b.name:lower() end)
    for _, d in ipairs(dirs) do
      out[#out + 1] = { d.name, build(d), open = keep ~= nil or open[d.path] or false }
    end
    table.sort(node.children, function(a, b) return a.sort < b.sort end)
    for _, c in ipairs(node.children) do out[#out + 1] = c.label end
    return out
  end
  return build(root)
end

-- at says what a tree path names: "note", "file" or "folder", and its
-- path in the notebook. A note and a folder of the same name: the note.
function Notebook:at(treePath)
  if not treePath or treePath == "" then return nil end
  if self.notes[treePath .. ".md"] then return "note", treePath .. ".md" end
  if self.files[treePath] then return "file", treePath end
  local _, folders = self:allFolders()
  if folders[treePath] then return "folder", treePath end
  return nil
end

-- treePath is how the tree names a note or file.
function M.treePath(path)
  if M.isNote(path) then return path:gsub("%.md$", "") end
  return path
end

---------------------------------------------------------------- notes

-- free makes a path no note or file has: name.md, name 1.md, ...
function Notebook:free(dir, name, ext)
  ext = ext or ".md"
  local path = M.join(dir, name .. ext)
  local n = 1
  while self:exists(path) do
    path = M.join(dir, ("%s %d%s"):format(name, n, ext))
    n = n + 1
  end
  return path
end

function Notebook:createNote(dir, name, text)
  local path = self:free(dir or "", name or "Untitled")
  self.notes[path] = text or ("# " .. M.title(path) .. "\n")
  self.dirty = true
  return path
end

function Notebook:createFolder(dir, name)
  local path = M.join(dir or "", name or "New folder")
  local n = 1
  while self:exists(path) do
    path = M.join(dir or "", ("%s %d"):format(name or "New folder", n))
    n = n + 1
  end
  self.folders[path] = true
  self.dirty = true
  return path
end

function Notebook:setText(path, text)
  if self.notes[path] ~= text then
    self.notes[path] = text
    self.dirty = true
  end
end

-- resolve finds the note a wiki link names: by its path, or by its title
-- anywhere, the one in from's folder first. nil when there is none.
function Notebook:resolve(target, from)
  target = (target or ""):gsub("#.*$", ""):gsub("%.md$", "")
  if target == "" then return nil end
  local here = from and M.dirname(from) or ""
  -- A path names its note outright; a name is the note's own folder's
  -- first, then anywhere.
  local exact = M.clean(target:find("/") and target .. ".md" or M.join(here, target .. ".md"))
  if exact and self.notes[exact] then return exact end
  local want = M.basename(target):lower()
  local best
  for _, p in ipairs(self:notePaths()) do
    if M.title(p):lower() == want then
      if M.dirname(p) == here then return p end
      best = best or p
    end
  end
  return best
end

-- linkTarget reads a link's url as a note's name, when it is one: a wiki
-- link's "Page Name.md", or a relative link to a .md file.
function M.linkTarget(url)
  if url:match("^%a[%w+.-]*:") then return nil end
  local path = url:gsub("#.*$", ""):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
  if path == "" then return nil end
  if path:lower():match("%.md$") or not path:match("%.%w+$") then return (path:gsub("%.md$", "")) end
  return nil
end

-- links lists the wiki and Markdown links of a note's text, as targets.
local function linksIn(text)
  local out = {}
  for target in text:gmatch("%[%[([^%[%]|#]+)[^%[%]]*%]%]") do out[#out + 1] = target end
  for url in text:gmatch("%]%(([^%)%s]+)") do
    local t = M.linkTarget(url)
    if t then out[#out + 1] = t end
  end
  return out
end

-- backlinks lists the notes that link to path.
function Notebook:backlinks(path)
  local out = {}
  for _, p in ipairs(self:notePaths()) do
    if p ~= path then
      for _, target in ipairs(linksIn(self.notes[p])) do
        if self:resolve(target, p) == path then
          out[#out + 1] = p
          break
        end
      end
    end
  end
  return out
end

-- search lists the notes whose title or text has text in it, the case of
-- letters aside: the titles first.
function Notebook:search(text)
  local want = text:lower()
  local byTitle, byText = {}, {}
  for _, p in ipairs(self:notePaths()) do
    if M.title(p):lower():find(want, 1, true) then byTitle[#byTitle + 1] = p
    elseif self.notes[p]:lower():find(want, 1, true) then byText[#byText + 1] = p end
  end
  for _, p in ipairs(byText) do byTitle[#byTitle + 1] = p end
  return byTitle
end

local function escapePattern(s) return (s:gsub("%p", "%%%0")) end

-- relink points the links in every note from one note's name to another's.
local function relink(self, oldTitle, newTitle)
  local pat = escapePattern(oldTitle)
  for p, text in pairs(self.notes) do
    local new = text
    -- [[Old]], [[Old|words]] and [[Old#heading]], the case of letters aside.
    new = new:gsub("%[%[(" .. pat:gsub("%a", function(c) return "[" .. c:lower() .. c:upper() .. "]" end) .. ")([|#%]])",
      function(_, after) return "[[" .. newTitle .. after end)
    if new ~= text then self.notes[p] = new end
  end
end

-- move renames or moves a note, a file or a folder to newPath, keeping
-- the links to notes working. It returns the new path, or nil and why.
function Notebook:move(old, newPath)
  newPath = M.clean(newPath)
  if not newPath then return nil, "That is not a name a note can have." end
  local kind = self.notes[old] and "note" or self.files[old] and "file" or "folder"
  if kind == "note" and not M.isNote(newPath) then newPath = newPath .. ".md" end
  if newPath == old then return old end
  if self:exists(newPath) and newPath:lower() ~= old:lower() then
    return nil, M.treePath(newPath) .. " is there already."
  end
  if kind == "note" then
    self.notes[newPath], self.notes[old] = self.notes[old], nil
    if M.title(old) ~= M.title(newPath) then relink(self, M.title(old), M.title(newPath)) end
    if self.open == old then self.open = newPath end
  elseif kind == "file" then
    self.files[newPath], self.files[old] = self.files[old], nil
    self.images[newPath], self.images[old] = self.images[old], nil
    for p, text in pairs(self.notes) do
      local new = text:gsub("%((" .. escapePattern(old) .. ")%)", "(" .. newPath:gsub("%%", "%%%%") .. ")")
      if new ~= text then self.notes[p] = new end
    end
  else
    local prefix = old .. "/"
    local function moved(p) return newPath .. "/" .. p:sub(#prefix + 1) end
    for _, set in ipairs { self.notes, self.files, self.folders } do
      local changes = {}
      for p, v in pairs(set) do
        if p == old or p:sub(1, #prefix) == prefix then changes[#changes + 1] = { p, v } end
      end
      for _, c in ipairs(changes) do set[c[1]] = nil end
      for _, c in ipairs(changes) do set[c[1] == old and newPath or moved(c[1])] = c[2] end
    end
    if self.open and self.open:sub(1, #prefix) == prefix then self.open = moved(self.open) end
    self.folders[newPath] = true
  end
  self.dirty = true
  return newPath
end

-- remove deletes a note, a file or a folder and all in it.
function Notebook:remove(path)
  if self.notes[path] then
    self.notes[path] = nil
  elseif self.files[path] then
    self.files[path] = nil
    self.images[path] = nil
  else
    local prefix = path .. "/"
    for _, set in ipairs { self.notes, self.files, self.folders } do
      for p in pairs(set) do
        if p == path or p:sub(1, #prefix) == prefix then set[p] = nil end
      end
    end
  end
  if self.open == path or (self.open and not self.notes[self.open]) then self.open = nil end
  self.dirty = true
end

---------------------------------------------------------------- attachments

-- attach keeps a file's bytes in the notebook, under attachments/, and
-- returns its path there.
function Notebook:attach(name, data)
  name = M.basename((name or "file"):gsub("\\", "/"))
  name = name:gsub('[:%*%?"<>|#%^%[%]]', "_")
  if name == "" then name = "file" end
  local stem, ext = name:match("^(.-)(%.[^.]*)$")
  if not stem or stem == "" then stem, ext = name, "" end
  local path = self:free(M.ATTACHMENTS, stem, ext)
  self.files[path] = data
  self.dirty = true
  return path
end

-- picture is the png image of a picture the notes show, by its src: a
-- path from the top of the notebook, or from the note's folder.
function Notebook:picture(src, from)
  local path = M.clean(src:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
  if path and not self.files[path] and from then path = M.clean(M.join(M.dirname(from), src)) end
  if not path or not self.files[path] then return nil end
  local img = self.images[path]
  if img == nil then
    img = png.decode(self.files[path]) or false
    self.images[path] = img
  end
  return img or nil
end

-- pictures is a table that finds pictures by src as it is read, for a
-- MarkdownEdit's or a MarkdownView's pictures; from is the note shown.
function Notebook:pictures(from)
  local nb = self
  return setmetatable({}, { __index = function(_, src) return nb:picture(src, from) end })
end

-- unused lists the attachments no note links to or shows.
function Notebook:unused()
  local all = {}
  for _, text in pairs(self.notes) do all[#all + 1] = text end
  local text = table.concat(all, "\n")
  local out = {}
  for p in pairs(self.files) do
    if not text:find(p, 1, true) then out[#out + 1] = p end
  end
  table.sort(out)
  return out
end

---------------------------------------------------------------- files

local function readFile(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local data = f:read("*a")
  f:close()
  return data
end

local function writeFile(path, data)
  local tmp = path .. ".tmp"
  local f, err = io.open(tmp, "wb")
  if not f then return nil, err end
  local ok, werr = f:write(data)
  f:close()
  if not ok then os.remove(tmp) return nil, werr end
  os.remove(path)
  local rok, rerr = os.rename(tmp, path)
  if not rok then os.remove(tmp) return nil, rerr end
  return true
end

-- Pictures and archives are compressed already, so they are stored.
local STORED = { png = true, jpg = true, jpeg = true, gif = true, zip = true, gz = true, pdf = true,
  mp3 = true, mp4 = true, mov = true, znb = true, ztl = true, zmd = true, zms = true }

-- json writes the manifest, which is small and flat enough to write here.
local function quote(s) return '"' .. s:gsub('[%c"\\]', function(c) return ("\\u%04x"):format(c:byte()) end) .. '"' end

local function manifest(self)
  local folders = {}
  for f in pairs(self.folders) do folders[#folders + 1] = quote(f) end
  table.sort(folders)
  return ('{\n  "app": "micronotes",\n  "version": 1,\n  "open": %s,\n  "folders": [%s]\n}\n'):format(
    self.open and quote(self.open) or "null", table.concat(folders, ", "))
end

-- encode gives the bytes of a .znb.
function Notebook:encode()
  local w = zip.create(self.password and { password = self.password } or nil)
  w:add(M.MANIFEST, manifest(self))
  for _, p in ipairs(self:notePaths()) do w:add(p, self.notes[p]) end
  local files = {}
  for p in pairs(self.files) do files[#files + 1] = p end
  table.sort(files)
  for _, p in ipairs(files) do
    w:add(p, self.files[p], { store = STORED[(p:match("%.(%w+)$") or ""):lower()] or nil })
  end
  return w:close()
end

function Notebook:save(path)
  local bytes, err = self:encode()
  if not bytes then return nil, err end
  local ok, werr = writeFile(path, bytes)
  if not ok then return nil, werr end
  self.dirty = false
  return true
end

local function unquote(s)
  return (s:gsub("\\u(%x%x%x%x)", function(h) return string.char(tonumber(h, 16) % 256) end):gsub('\\(["\\/])', "%1"))
end

-- locked is why the archive cannot be read with the password it has, when
-- that is the password's fault ("a password is needed", "wrong password"):
-- it is encrypted all through, so the first encrypted file shows it.
local function locked(z)
  for _, name in ipairs(z:list()) do
    local info = z:info(name)
    if info and info.encrypted then
      local _, why = z:read(name)
      if why and why:find("password", 1, true) then return why end
      return nil
    end
  end
end

-- decode reads the bytes of a .znb (or any zip of Markdown files). When it
-- is encrypted and the password is missing or wrong it gives nil, why and
-- "locked"; the notebook keeps the password to save with.
function M.decode(data, password)
  local z, err = zip.load(data, { password = password })
  if not z then return nil, "not a notebook: " .. tostring(err) end
  local why = locked(z)
  if why then return nil, why, "locked" end
  local nb = M.new(false)
  nb.password = password
  local text = z:read(M.MANIFEST) or ""
  for _, name in ipairs(z:list()) do
    local path = M.clean(name)
    if path and path ~= M.MANIFEST and not name:match("/$") and not M.basename(path):match("^%.") then
      local bytes = z:read(name) or ""
      if M.isNote(path) then nb.notes[path] = bytes else nb.files[path] = bytes end
    end
  end
  local list = text:match('"folders"%s*:%s*%[(.-)%]')
  if list then
    -- Names cannot have a " in them (validName), so none is escaped.
    for f in list:gmatch('"([^"]*)"') do
      local p = M.clean(unquote(f))
      if p then nb.folders[p] = true end
    end
  end
  local open = text:match('"open"%s*:%s*"([^"]*)"')
  open = open and M.clean(unquote(open))
  if open and nb.notes[open] then nb.open = open end
  nb.dirty = false
  return nb
end

function M.load(path, password)
  local data, err = readFile(path)
  if not data then return nil, err end
  return M.decode(data, password)
end

-- importFolder reads a folder of Markdown notes and their files, as other
-- note programs keep them, into a new notebook. Dot files are left out.
function M.importFolder(dir)
  local nb = M.new(false)
  local count = 0
  local function walk(abs, rel)
    for name in lfs.dir(abs) do
      if not name:match("^%.") then
        local full, path = abs .. "/" .. name, M.join(rel, name)
        local mode = lfs.attributes(full, "mode")
        if mode == "directory" then
          nb.folders[path] = true
          walk(full, path)
        elseif mode == "file" then
          local data = readFile(full)
          if data then
            if M.isNote(path) then nb.notes[path] = data else nb.files[path] = data end
            count = count + 1
            if count > 20000 then error("too many files in " .. dir) end
          end
        end
      end
    end
  end
  local ok, err = pcall(walk, dir, "")
  if not ok then return nil, err end
  nb.open = nb.notes["Welcome.md"] and "Welcome.md" or nb:notePaths()[1]
  nb.dirty = true
  return nb
end

-- exportFolder writes the notes and files into a folder, as a vault.
function Notebook:exportFolder(dir)
  local function mkdirs(path)
    local at = ""
    for part in path:gmatch("[^/]+") do
      at = at == "" and part or (at .. "/" .. part)
      lfs.mkdir(dir .. "/" .. at)
    end
  end
  for _, f in ipairs(self:allFolders()) do mkdirs(f) end
  for p, text in pairs(self.notes) do
    local ok, err = writeFile(dir .. "/" .. p, text)
    if not ok then return nil, err end
  end
  for p, data in pairs(self.files) do
    local ok, err = writeFile(dir .. "/" .. p, data)
    if not ok then return nil, err end
  end
  return true
end

-- headingsOf lists a note's headings, for an outline.
function Notebook:headings(path)
  return md.headings(md.parse(self.notes[path] or ""))
end

---------------------------------------------------------------- settings

M.settingsFile = nil -- the tests keep their own

function M.settingsPath()
  if M.settingsFile then return M.settingsFile end
  local base = os.getenv("XDG_CONFIG_HOME")
  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or "."
  if package.config:sub(1, 1) == "\\" then base = base or os.getenv("APPDATA") end
  return (base or (home .. "/.config")) .. "/turboapps/micronotes.lua"
end

M.defaults = { last = "", textSize = 15 }

function M.loadSettings()
  local s = {}
  for k, v in pairs(M.defaults) do s[k] = v end
  local fn = loadfile(M.settingsPath())
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

function M.saveSettings(s)
  local path = M.settingsPath()
  local dir = M.dirname(path:gsub("\\", "/"))
  lfs.mkdir(M.dirname(dir))
  lfs.mkdir(dir)
  local keys = {}
  for k in pairs(M.defaults) do keys[#keys + 1] = k end
  table.sort(keys)
  local lines = { "-- micronotes' settings, written by it.", "return {" }
  for _, k in ipairs(keys) do
    local v = s[k]
    lines[#lines + 1] = ("  %s = %s,"):format(k, type(v) == "string" and ("%q"):format(v) or tostring(v))
  end
  lines[#lines + 1] = "}\n"
  return writeFile(path, table.concat(lines, "\n"))
end

return M
