-- A notebook (.znb, as micronotes writes it) read as a book: its notes are
-- pages, its folders chapters, never changed. This is the reading half of
-- micronotes' notebook.lua, with what a book adds: an order to read in,
-- a contents, an index of the headings, and a search that counts.
--
-- Pages are in the order of their names, numbers by their value, so that
-- "2 Setup" comes before "10 Reference"; a number at the start of a name
-- ("01 ", "1. ", "01-") orders the page and is not shown.

local zip = require "zip"
local png = require "png"
local md = require "markdown"

local M = {}

local Book = {}
Book.__index = Book

---------------------------------------------------------------- paths

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
function M.isNote(path) return path:lower():match("%.md$") ~= nil end

local IMAGES = { png = true, jpg = true, jpeg = true, gif = true, bmp = true }
function M.isPicture(path) return IMAGES[(path:match("%.(%w+)$") or ""):lower()] ~= nil end

-- label is how a page or chapter is shown: its name without .md, and
-- without a number at its start that orders it.
function M.label(name)
  name = M.basename(name):gsub("%.md$", "")
  local rest = name:match("^%d+[%.%-_%)]?%s+(.+)$") or name:match("^%d+[%-_](.+)$")
  return rest or name
end

-- before orders names as people do: numbers in them by their value.
local function key(s)
  return (s:lower():gsub("%d+", function(n) return ("%012d"):format(tonumber(n)) end))
end
function M.before(a, b) return key(a) < key(b) end

-- linkTarget reads a link's url as a page's name, when it is one.
function M.linkTarget(url)
  if url:match("^%a[%w+.-]*:") then return nil end
  local path, anchor = url:match("^([^#]*)#?(.*)$")
  path = path:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
  if path == "" then return nil, anchor end
  if path:lower():match("%.md$") or not path:match("%.%w+$") then return (path:gsub("%.md$", "")), anchor end
  return nil
end

---------------------------------------------------------------- reading

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
-- "locked".
function M.decode(data, password)
  local z, err = zip.load(data, { password = password })
  if not z then return nil, "not a notebook: " .. tostring(err) end
  local why = locked(z)
  if why then return nil, why, "locked" end
  local b = setmetatable({ notes = {}, files = {}, images = {} }, Book)
  for _, name in ipairs(z:list()) do
    local path = M.clean(name)
    if path and path ~= "notebook.json" and not name:match("/$") and not M.basename(path):match("^%.") then
      local bytes = z:read(name) or ""
      if M.isNote(path) then b.notes[path] = bytes else b.files[path] = bytes end
    end
  end
  if not next(b.notes) then return nil, "there are no pages in it" end
  return b
end

function M.load(path, password)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local data = f:read("*a")
  f:close()
  local b, derr, why = M.decode(data, password)
  if not b then return nil, derr, why end
  b.name = M.label(M.basename(path:gsub("\\", "/")):gsub("%.znb$", ""))
  return b
end

---------------------------------------------------------------- the contents

-- pages lists the pages in reading order: the home page first, then each
-- folder's pages and chapters by their names, a chapter's pages where it
-- comes.
function Book:pages()
  if self.order then return self.order end
  local home = self:home()
  local dirs = { [""] = { pages = {}, dirs = {} } }
  local function dir(path)
    if not dirs[path] then
      dirs[path] = { pages = {}, dirs = {} }
      local parent = dir(M.dirname(path))
      parent.dirs[#parent.dirs + 1] = path
    end
    return dirs[path]
  end
  for p in pairs(self.notes) do
    local d = dir(M.dirname(p))
    d.pages[#d.pages + 1] = p
  end
  local order = {}
  local function walk(path)
    local d = dirs[path]
    -- Pages and chapters in one order, by name.
    local all = {}
    for _, p in ipairs(d.pages) do
      if p ~= home then all[#all + 1] = { name = M.basename(p):gsub("%.md$", ""), page = p } end
    end
    for _, c in ipairs(d.dirs) do all[#all + 1] = { name = M.basename(c), dir = c } end
    table.sort(all, function(a, b)
      if a.name:lower() == b.name:lower() then return a.page ~= nil and b.page == nil end
      return M.before(a.name, b.name)
    end)
    for _, e in ipairs(all) do
      if e.page then order[#order + 1] = e.page else walk(e.dir) end
    end
  end
  table.insert(order, 1, home)
  walk("")
  self.order = order
  return order
end

-- items is the contents as a Tree shows it, and paths what each of its
-- tree paths means (a page's path, or a chapter's). open: the chapters
-- shown open.
function Book:items(open)
  open = open or {}
  local paths = {}
  local root = { kids = {}, byDir = {} }
  local function node(dirPath, treePath)
    if dirPath == "" then return root, "" end
    local parent, parentTree = node(M.dirname(dirPath), nil)
    local n = parent.byDir[dirPath]
    if not n then
      local label = M.label(dirPath)
      local tp = (parentTree ~= "" and parentTree .. "/" or "") .. label
      n = { kids = {}, byDir = {}, label = label, tree = tp, dir = dirPath }
      parent.byDir[dirPath] = n
      parent.kids[#parent.kids + 1] = n
      paths[tp] = dirPath
    end
    return n, n.tree
  end
  for _, p in ipairs(self:pages()) do
    local n, tp = node(M.dirname(p))
    local label = p == self:home() and self:title(p) or M.label(p)
    n.kids[#n.kids + 1] = { label = label, page = p }
    paths[(tp ~= "" and tp .. "/" or "") .. label] = p
  end
  local function build(n)
    local out = {}
    for _, k in ipairs(n.kids) do
      if k.page then out[#out + 1] = k.label
      else out[#out + 1] = { k.label, build(k), open = open[k.dir] or false } end
    end
    return out
  end
  self.treePaths = paths
  return build(root)
end

-- treePath is how the contents names a page.
function Book:treePath(page)
  if not self.treePaths then self:items() end
  for tp, p in pairs(self.treePaths) do
    if p == page then return tp end
  end
end

-- at is what a tree path of the contents means: a page's path, or a
-- chapter's, and which.
function Book:at(tp)
  if not self.treePaths then self:items() end
  local p = self.treePaths[tp or ""]
  if not p then return nil end
  return self.notes[p] and "page" or "chapter", p
end

-- home is the page a book opens at: index, README, Home or Welcome at
-- its top, or else its first page by name.
function Book:home()
  if self.homePage then return self.homePage end
  local first
  for _, name in ipairs { "index.md", "README.md", "Home.md", "Welcome.md" } do
    for p in pairs(self.notes) do
      if p:lower() == name:lower() then self.homePage = p return p end
    end
  end
  for p in pairs(self.notes) do
    if not first or M.before(p, first) then first = p end
  end
  self.homePage = first
  return first
end

-- neighbour is the page before (-1) or after (1) a page, in reading order.
function Book:neighbour(page, dir)
  local pages = self:pages()
  for i, p in ipairs(pages) do
    if p == page then return pages[i + dir] end
  end
end

-- title is a page's title: its first heading, or its label.
function Book:title(page)
  local text = self.notes[page] or ""
  local h = text:match("^#%s+([^\n]+)") or text:match("\n#%s+([^\n]+)")
  return h and h:gsub("%s+#*%s*$", "") or M.label(page)
end

---------------------------------------------------------------- links

-- resolve finds the page a link names: by its path, or by its name in
-- the page's own folder first, then anywhere.
function Book:resolve(target, from)
  target = (target or ""):gsub("#.*$", ""):gsub("%.md$", "")
  if target == "" then return nil end
  local here = from and M.dirname(from) or ""
  local exact = M.clean(target:find("/") and target .. ".md" or M.join(here, target .. ".md"))
  if exact and self.notes[exact] then return exact end
  local want = M.basename(target):lower()
  local best
  for _, p in ipairs(self:pages()) do
    local name = M.basename(p):gsub("%.md$", ""):lower()
    if name == want or M.label(p):lower() == want then
      if M.dirname(p) == here then return p end
      best = best or p
    end
  end
  return best
end

-- file is an attachment a link names: from the top, or the page's folder.
function Book:file(url, from)
  local path = M.clean((url:gsub("#.*$", ""):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)))
  if path and self.files[path] then return path end
  if from then
    path = M.clean(M.join(M.dirname(from), url))
    if path and self.files[path] then return path end
  end
end

function Book:picture(src, from)
  local path = self:file(src, from)
  if not path then return nil end
  local img = self.images[path]
  if img == nil then
    img = png.decode(self.files[path]) or false
    self.images[path] = img
  end
  return img or nil
end

function Book:pictures(from)
  local b = self
  return setmetatable({}, { __index = function(_, src) return b:picture(src, from) end })
end

---------------------------------------------------------------- index and search

-- index lists what a reader looks up: every page by its title and every
-- heading of levels 1 to 3, sorted, each with its page and anchor.
function Book:index()
  if self.indexed then return self.indexed end
  local out, seen = {}, {}
  local function add(text, page, anchor)
    local k = text:lower() .. "\0" .. page .. "\0" .. (anchor or "")
    if seen[k] then return end
    seen[k] = true
    out[#out + 1] = { text = text, page = page, anchor = anchor }
  end
  for _, p in ipairs(self:pages()) do
    local title = self:title(p)
    add(title, p, nil)
    for _, h in ipairs(md.headings(md.parse(self.notes[p]))) do
      -- A page's own title is in the index once, as the page.
      local own = h.text:lower() == title:lower() or h.text:lower() == M.label(p):lower()
      if h.level <= 3 and h.text ~= "" and not own then add(h.text, p, h.anchor) end
    end
  end
  table.sort(out, function(a, b)
    if a.text:lower() == b.text:lower() then return M.before(a.page, b.page) end
    return M.before(a.text, b.text)
  end)
  self.indexed = out
  return out
end

-- lookup is the index entries that start with text, or else have it.
function Book:lookup(text)
  local want = text:lower()
  local starts, has = {}, {}
  for _, e in ipairs(self:index()) do
    local low = e.text:lower()
    if want == "" or low:sub(1, #want) == want then starts[#starts + 1] = e
    elseif low:find(want, 1, true) then has[#has + 1] = e end
  end
  for _, e in ipairs(has) do starts[#starts + 1] = e end
  return starts
end

-- search finds the pages with every word of text in them, the case of
-- letters aside, best first: words in the title count most, then how
-- often they come up.
function Book:search(text)
  local words = {}
  for w in text:lower():gmatch("%S+") do words[#words + 1] = w end
  if #words == 0 then return {} end
  local out = {}
  for _, p in ipairs(self:pages()) do
    local body = self.notes[p]:lower()
    local title = self:title(p):lower()
    local score, hits, all = 0, 0, true
    for _, w in ipairs(words) do
      local n = 0
      local from = 1
      while true do
        local i = body:find(w, from, true)
        if not i then break end
        n = n + 1
        from = i + #w
      end
      if n == 0 then all = false break end
      hits = hits + n
      score = score + n + (title:find(w, 1, true) and 100 or 0)
    end
    if all then out[#out + 1] = { page = p, score = score, hits = hits } end
  end
  table.sort(out, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return M.before(a.page, b.page)
  end)
  return out
end

---------------------------------------------------------------- settings

M.settingsFile = nil

function M.settingsPath()
  if M.settingsFile then return M.settingsFile end
  local base = os.getenv("XDG_CONFIG_HOME")
  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or "."
  if package.config:sub(1, 1) == "\\" then base = base or os.getenv("APPDATA") end
  return (base or (home .. "/.config")) .. "/turboapps/microreader.lua"
end

M.defaults = { last = "", page = "", textSize = 15 }

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
  local lfs = require "lfs"
  local path = M.settingsPath()
  local dir = M.dirname(path:gsub("\\", "/"))
  lfs.mkdir(M.dirname(dir))
  lfs.mkdir(dir)
  local keys = {}
  for k in pairs(M.defaults) do keys[#keys + 1] = k end
  table.sort(keys)
  local lines = { "-- microreader's settings, written by it.", "return {" }
  for _, k in ipairs(keys) do
    local v = s[k]
    lines[#lines + 1] = ("  %s = %s,"):format(k, type(v) == "string" and ("%q"):format(v) or tostring(v))
  end
  lines[#lines + 1] = "}\n"
  local f = io.open(path, "w")
  if not f then return nil end
  f:write(table.concat(lines, "\n"))
  f:close()
  return true
end

return M
