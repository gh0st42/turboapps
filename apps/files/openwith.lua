-- Which of turboapps' own apps opens which kind of file, and how to start
-- it, with no GUI in it. Files uses it to open a picture in the image viewer
-- and the like, and the Desktop to open a file in the app for it. This file
-- is the same in apps/files and apps/desktop (a bundle holds its own copy,
-- and a test sees that they match).
--
--   local openwith = require "openwith"
--   openwith.appsFor("cat.png")             --> { "imageviewer", "pixel" }
--   local cmd = openwith.command("imageviewer", "cat.png", gui.interpreter)
--   --> { "/usr/bin/tlua", "/where/turboapps/dist/imageviewer.ztl", "cat.png" }, or nil
--
-- An app is found beside the program running (its bundle in the same
-- folder), else in turboapps' folder: in TURBOAPPS_ROOT, the folder the
-- program was started from, or one above the current folder. The bundle in
-- its dist/ is used when it has been made, else the app's own folder.

local lfs = require "lfs"

local M = {}

-- ctx, when set, stands in for where the program and its folders are (see
-- roots); the tests use it.
M.ctx = nil

M.TITLES = {
  imageviewer = "Image Viewer", pixel = "Pixel", microword = "MicroWord", microsheets = "MicroSheets",
  micronotes = "MicroNotes", microreader = "MicroReader", editor = "Editor", chipstudio = "ChipStudio",
}

local PICTURE = { "imageviewer", "pixel" }
local TEXT = { "editor" }

-- TYPES say which apps open a file by its extension, the one a double click
-- uses first.
M.TYPES = {
  png = PICTURE, jpg = PICTURE, jpeg = PICTURE, gif = PICTURE, webp = { "imageviewer" },
  zmd = { "microword" }, md = { "microword", "editor" }, markdown = { "microword", "editor" },
  zms = { "microsheets" }, csv = { "microsheets", "editor" }, tsv = { "microsheets", "editor" },
  znb = { "micronotes", "microreader" },
  json = { "editor", "chipstudio" },
  txt = TEXT, log = TEXT, lua = TEXT, ini = TEXT, cfg = TEXT, conf = TEXT, toml = TEXT,
  yaml = TEXT, yml = TEXT, xml = TEXT,
}

-- appsFor are the apps that open a file, by its name's end, best first.
function M.appsFor(path)
  local ext = path:match("%.([^./\\]+)$")
  local apps = ext and M.TYPES[ext:lower()] or {}
  local out = {}
  for i, a in ipairs(apps) do out[i] = a end
  return out
end

local function normalize(path)
  path = (path or ""):gsub("\\", "/"):gsub("/+", "/")
  if #path > 1 and not path:match("^%a:/$") then path = path:gsub("/$", "") end
  return path
end

local function dirname(path)
  path = normalize(path)
  local up = path:match("^(.*)/[^/]*$")
  if not up then return "." end
  return up == "" and "/" or up
end

local function exists(path) return lfs.attributes(path) ~= nil end
local function isDir(path) return lfs.attributes(path, "mode") == "directory" end

-- looksLikeRoot says whether a folder is turboapps': it has apps/ and a Makefile.
local function looksLikeRoot(path)
  return isDir(path .. "/apps") and exists(path .. "/Makefile")
end

-- roots are the folders turboapps may be in, most likely first. ctx may give
-- arg0 (the program's own path), env (the TURBOAPPS_ROOT) and cwd, each of
-- which is read from where it lives when it is not.
function M.roots(ctx)
  ctx = ctx or M.ctx or {}
  local arg0 = ctx.arg0 or (arg or {})[0] or ""
  local env = ctx.env or os.getenv("TURBOAPPS_ROOT") or ""
  local cwd = ctx.cwd or lfs.currentdir() or "."
  local out, seen = {}, {}
  local function add(path)
    path = normalize(path)
    if path ~= "" and not seen[path] and looksLikeRoot(path) then
      seen[path] = true
      out[#out + 1] = path
    end
  end
  add(env)
  -- A program started from dist/ or from apps/<name>/ is in the root above.
  local parts = {}
  for p in normalize(arg0):gmatch("[^/]+") do parts[#parts + 1] = p end
  for i = #parts, 1, -1 do
    if parts[i] == "dist" or parts[i] == "apps" then
      local lead = normalize(arg0):sub(1, 1) == "/" and "/" or ""
      add(lead .. table.concat(parts, "/", 1, i - 1))
      break
    end
  end
  local probe = normalize(cwd)
  for _ = 1, 7 do
    add(probe)
    local up = dirname(probe)
    if up == probe then break end
    probe = up
  end
  return out
end

-- locate says where an app is: the path of its bundle, or else of its
-- main.lua; nil when it is not to be found. A bundle beside the program
-- running is taken first.
function M.locate(name, ctx)
  ctx = ctx or M.ctx or {}
  local arg0 = ctx.arg0 or (arg or {})[0] or ""
  if arg0:lower():match("%.ztl$") then
    local beside = dirname(arg0) .. "/" .. name .. ".ztl"
    if exists(beside) then return beside end
  end
  for _, root in ipairs(M.roots(ctx)) do
    local bundle = root .. "/dist/" .. name .. ".ztl"
    if exists(bundle) then return bundle end
    local main = root .. "/apps/" .. name .. "/main.lua"
    if exists(main) then return main end
  end
end

-- command is what starts an app on a file: { interpreter, app, file }; nil
-- when the app is not to be found.
function M.command(name, file, interpreter, ctx)
  local target = M.locate(name, ctx)
  if not target then return nil end
  return { interpreter or "tlua", target, file }
end

-- available are the apps that open a file and can be found, best first.
function M.available(path, ctx)
  local out = {}
  for _, name in ipairs(M.appsFor(path)) do
    if M.locate(name, ctx) then out[#out + 1] = name end
  end
  return out
end

return M
