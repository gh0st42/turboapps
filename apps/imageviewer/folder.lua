-- The image viewer's dealings with folders, with no GUI in it: which files
-- it can show, what a folder holds (folders and pictures together, in the
-- order a person counts them), and paths. Paths use "/" throughout,
-- which Windows takes as well as "\".
--
--   local folder = require "folder"
--   local entries = folder.list("/home/me/Pictures")
--   -- { { name = "2024", dir = true, path = ... }, { name = "a.png", path = ... } }

local lfs = require "lfs"
local zip = require "zip"

local M = {}

-- EXTENSIONS are the files shown: those tlua's png module reads (the
-- animated ones, GIF, PNG and WebP, move).
M.EXTENSIONS = { png = true, jpg = true, jpeg = true, gif = true, webp = true }

-- ARCHIVES are the files opened as folders: zip files, and comic books, which
-- are zip files of pictures.
M.ARCHIVES = { zip = true, cbz = true }

-- A place in a zip file is written as the file, then "!/", then the way
-- down inside it: "/home/me/pics.zip!/" is the top of the archive,
-- "/home/me/pics.zip!/2024/may" a folder in it.
local SEP = "!/"

function M.isArchive(name)
  local ext = name:match("%.([^./\\]+)$")
  return ext ~= nil and M.ARCHIVES[ext:lower()] == true
end

-- split gives the zip file and the way down inside it of a path in one, or
-- nil of a path that is not.
function M.split(path)
  local file, inner = path:match("^(.-)" .. SEP:gsub("%p", "%%%0") .. "(.*)$")
  if file then return file, inner end
end

-- isImage says whether a file name is one the viewer shows.
function M.isImage(name)
  local ext = name:match("%.([^./\\]+)$")
  return ext ~= nil and M.EXTENSIONS[ext:lower()] == true
end

function M.normalize(path)
  local file, inner = M.split(path)
  if file then
    inner = inner:gsub("\\", "/"):gsub("^/+", ""):gsub("/+$", "")
    return file:gsub("\\", "/") .. SEP .. inner
  end
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
  local file, inner = M.split(path)
  if file then
    -- Up from the top of an archive is the folder it is in.
    if inner == "" then return M.parent(file) end
    return file .. SEP .. (inner:match("^(.*)/[^/]*$") or "")
  end
  if path == "/" or path:match("^%a:/?$") then return path end
  local up = path:match("^(.*)/[^/]*$")
  if up == "" then return "/" end
  if up:match("^%a:$") then return up .. "/" end
  return up or path
end

function M.basename(path)
  path = M.normalize(path)
  local file, inner = M.split(path)
  if file then
    if inner == "" then return M.basename(file) end
    return inner:match("([^/]+)$")
  end
  return path:match("([^/]+)$") or path
end

function M.home()
  return M.normalize(os.getenv("HOME") or os.getenv("USERPROFILE") or "/")
end

-- start is the folder to open first: the Pictures folder when there is
-- one, else home.
function M.start()
  local pictures = M.join(M.home(), "Pictures")
  if lfs.attributes(pictures, "mode") == "directory" then return pictures end
  return M.home()
end

-- key is a name as it sorts: lower case, with each run of digits padded so
-- that "img2" comes before "img10".
local function key(name)
  return (name:lower():gsub("%d+", function(d)
    if #d >= 20 then return d end
    return ("0"):rep(20 - #d) .. d
  end))
end

---------------------------------------------------------------- archives

-- A zip file read is kept (with the password it was read with) while it is
-- looked into, so that moving about in it does not read it again.
local open = {}

-- archive opens a zip file to look into, or says it is open already. It
-- gives nil and why when it cannot be read, and "locked" as a third result
-- when it is encrypted and the password is missing or wrong.
function M.archive(file, password)
  local a = open[file]
  if a and (password == nil or a.password == password) then return a end
  local f, err = io.open(file, "rb")
  if not f then return nil, err end
  local data = f:read("*a")
  f:close()
  local z, zerr = zip.load(data, { password = password })
  if not z then return nil, zerr end
  for _, name in ipairs(z:list()) do
    local info = z:info(name)
    if info and info.encrypted then
      local _, why = z:read(name)
      if why and why:find("password", 1, true) then return nil, why, "locked" end
      break
    end
  end
  a = { z = z, password = password, file = file }
  open[file] = a
  return a
end

-- closeArchives lets go of the zip files kept.
function M.closeArchives()
  open = {}
end

-- read gives the bytes of a picture listed in an archive.
function M.read(entry)
  local a = open[entry.zip]
  if not a then return nil, "the archive is not open" end
  return a.z:read(entry.inner, a.password)
end

-- listArchive is what is in a place in an archive, as list gives a folder's.
local function listArchive(file, inner)
  local a = open[file]
  if not a then return nil, "the archive is not open" end
  local prefix = inner == "" and "" or inner .. "/"
  local all, dirs = {}, {}
  for _, name in ipairs(a.z:list()) do
    if name:sub(1, #prefix) == prefix then
      local rest = name:sub(#prefix + 1)
      local dirName, tail = rest:match("^([^/]+)/(.+)$")
      if dirName then
        if dirName:sub(1, 1) ~= "." and not dirs[dirName] then
          dirs[dirName] = true
          all[#all + 1] = { name = dirName, path = file .. SEP .. prefix .. dirName, dir = true, sort = key(dirName) }
        end
      elseif rest ~= "" and rest:sub(1, 1) ~= "." and M.isImage(rest) then
        local info = a.z:info(name)
        all[#all + 1] = { name = rest, path = file .. SEP .. name, zip = file, inner = name,
          size = info and info.size, sort = key(rest) }
      end
    end
  end
  return all
end

-- list is what is in a folder, as { name, path, dir, size } each: the
-- folders and the pictures the viewer can show, mixed, in the order of
-- their names. Names that start with a dot are left out. nil and why when
-- it cannot be read.
function M.list(dir)
  local file, inner = M.split(dir)
  local all
  if file then
    local err
    all, err = listArchive(file, inner)
    if not all then return nil, err end
    table.sort(all, function(a, b) return a.sort < b.sort or (a.sort == b.sort and a.name < b.name) end)
    return all
  end
  local ok, iter, state = pcall(lfs.dir, dir)
  if not ok then return nil, tostring(iter) end
  all = {}
  for name in iter, state do
    if name:sub(1, 1) ~= "." then
      local path = M.join(dir, name)
      local a = lfs.attributes(path)
      if a and a.mode == "directory" then
        all[#all + 1] = { name = name, path = path, dir = true, sort = key(name) }
      elseif a and a.mode == "file" and M.isArchive(name) then
        -- A zip file is a folder to go into.
        all[#all + 1] = { name = name, path = path .. SEP, dir = true, archive = true, sort = key(name) }
      elseif a and a.mode == "file" and M.isImage(name) then
        all[#all + 1] = { name = name, path = path, size = a.size, sort = key(name) }
      end
    end
  end
  local function by(a, b) return a.sort < b.sort or (a.sort == b.sort and a.name < b.name) end
  table.sort(all, by)
  return all
end

function M.formatSize(n)
  if not n then return "" end
  if n < 1024 then return n .. " B" end
  local units = { "KB", "MB", "GB", "TB" }
  local i = 0
  repeat n, i = n / 1024, i + 1 until n < 1024 or i == #units
  return (n < 10 and "%.1f %s" or "%.0f %s"):format(n, units[i])
end

return M
