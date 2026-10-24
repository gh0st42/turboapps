-- Files: microword keeps a document as a .zmd, a zip holding the Markdown
-- as document.md and the pictures it shows in assets/, which the Markdown
-- names as assets/<name>. Any zip tool opens one, and any Markdown viewer
-- shows what is inside.
--
-- It also opens plain .md files, with their pictures read from beside
-- them, and exports a document as a .md with an assets folder beside it.

local zip = require "zip"
local png = require "png"
local lfs = require "lfs"
local md = require "markdown"

local M = {}

M.MAIN = "document.md"

local function readFile(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local data = f:read("*a")
  f:close()
  if not data then return nil, "cannot read " .. path end
  return data
end

local function writeFile(path, data)
  local tmp = path .. ".tmp~"
  local f, err = io.open(tmp, "wb")
  if not f then return nil, err end
  f:write(data)
  f:close()
  os.remove(path)
  local ok, rerr = os.rename(tmp, path)
  if not ok then os.remove(tmp) return nil, rerr end
  return true
end

local function dirname(path)
  return path:match("^(.*)[/\\][^/\\]*$") or "."
end

function M.basename(path)
  return path:match("([^/\\]+)$") or path
end

function M.extension(path)
  return (path:match("%.([^./\\]+)$") or ""):lower()
end

-- Assets are kept as { [name] = { data = bytes, image = png image } },
-- by the name the Markdown uses.

-- asset makes an asset of a picture's bytes, or says why it is not one.
function M.asset(data)
  local image, err = png.decode(data)
  if not image then return nil, err end
  return { data = data, image = image }
end

-- uniqueName is a name for a new picture in assets/ that is not taken.
function M.uniqueName(assets, file)
  local name = M.basename(file):gsub("[^%w%._%-]", "_")
  local base, ext = name:match("^(.-)(%.[^.]*)$")
  if not base or base == "" then base, ext = name, "" end
  local candidate, n = "assets/" .. name, 1
  while assets[candidate] do
    n = n + 1
    candidate = ("assets/%s-%d%s"):format(base, n, ext)
  end
  return candidate
end

-- used lists the assets the blocks name, so that pictures taken out of the
-- document are not saved with it.
function M.used(blocks)
  local set = {}
  for _, b in ipairs(blocks) do
    if b.type == "image" and b.src then set[b.src] = true end
  end
  return set
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

-- load reads a .zmd, or a .md and the pictures beside it. It returns the
-- blocks and the assets, or nil and why: and, as a third result, "locked"
-- when the document is encrypted and the password is missing or wrong.
function M.load(path, password)
  local data, err = readFile(path)
  if not data then return nil, err end
  local assets = {}
  if M.extension(path) == "zmd" or data:sub(1, 2) == "PK" then
    local arc, zerr = zip.load(data, { password = password })
    if not arc then return nil, "not a microword document: " .. tostring(zerr) end
    local why = locked(arc)
    if why then return nil, why, "locked" end
    local text = arc:read(M.MAIN)
    if not text then return nil, "not a microword document: it has no " .. M.MAIN end
    for _, name in ipairs(arc:list()) do
      if name ~= M.MAIN then
        local bytes = arc:read(name)
        local a = bytes and M.asset(bytes)
        if a then assets[name] = a end
      end
    end
    arc:close()
    return md.parse(text), assets
  end
  -- A plain Markdown file: its pictures are files beside it.
  local blocks = md.parse(data)
  local dir = dirname(path)
  for _, b in ipairs(blocks) do
    if b.type == "image" and b.src and not b.src:match("^%a[%w+.-]*://") and not assets[b.src] then
      local file = b.src:sub(1, 1) == "/" and b.src or (dir .. "/" .. b.src)
      local bytes = readFile(file)
      local a = bytes and M.asset(bytes)
      if a then assets[b.src] = a end
    end
  end
  return blocks, assets
end

-- save writes a .zmd: the Markdown, and the pictures it uses, all
-- encrypted with the password when there is one.
function M.save(path, blocks, assets, password)
  local w = zip.create(password and { password = password } or nil)
  w:add(M.MAIN, md.write(blocks))
  local names = {}
  for name in pairs(M.used(blocks)) do
    if assets[name] then names[#names + 1] = name end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    -- A picture is compressed already.
    w:add(name, assets[name].data, { store = true })
  end
  local bytes, err = w:close()
  if not bytes then return nil, err end
  return writeFile(path, bytes)
end

-- exportMarkdown writes the Markdown to path and the pictures beside it,
-- in the folders their names say (assets/), for other Markdown tools.
function M.exportMarkdown(path, blocks, assets)
  local ok, err = writeFile(path, md.write(blocks))
  if not ok then return nil, err end
  local dir = dirname(path)
  for name in pairs(M.used(blocks)) do
    local a = assets[name]
    if a and not name:find("%.%.") then
      local sub = dirname(name)
      if sub ~= "." then lfs.mkdir(dir .. "/" .. sub) end
      local wok, werr = writeFile(dir .. "/" .. name, a.data)
      if not wok then return nil, werr end
    end
  end
  return true
end

return M
