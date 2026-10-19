-- The image viewer's dealings with folders, with no GUI in it: which files
-- it can show, what a folder holds (folders and pictures together, in the
-- order a person counts them), and paths. Paths use "/" throughout,
-- which Windows takes as well as "\".
--
--   local folder = require "folder"
--   local entries = folder.list("/home/me/Pictures")
--   -- { { name = "2024", dir = true, path = ... }, { name = "a.png", path = ... } }

local lfs = require "lfs"

local M = {}

-- EXTENSIONS are the files shown: those tlua's png module reads (the
-- animated ones, GIF, PNG and WebP, move).
M.EXTENSIONS = { png = true, jpg = true, jpeg = true, gif = true, webp = true }

-- isImage says whether a file name is one the viewer shows.
function M.isImage(name)
  local ext = name:match("%.([^./\\]+)$")
  return ext ~= nil and M.EXTENSIONS[ext:lower()] == true
end

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

-- list is what is in a folder, as { name, path, dir, size } each: the
-- folders and the pictures the viewer can show, mixed, in the order of
-- their names. Names that start with a dot are left out. nil and why when
-- it cannot be read.
function M.list(dir)
  local ok, iter, state = pcall(lfs.dir, dir)
  if not ok then return nil, tostring(iter) end
  local all = {}
  for name in iter, state do
    if name:sub(1, 1) ~= "." then
      local path = M.join(dir, name)
      local a = lfs.attributes(path)
      if a and a.mode == "directory" then
        all[#all + 1] = { name = name, path = path, dir = true, sort = key(name) }
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
