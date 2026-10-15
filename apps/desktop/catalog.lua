-- catalog finds turboapps and builds start commands for them.

local lfs = require "lfs"

local M = {}

local DEFAULT_CATEGORY_ORDER = { "Office", "Utilities", "Development", "Games", "Other" }
local DEFAULT_CATEGORY_MAP = {
  calculator = "Utilities",
  editor = "Office",
  files = "Utilities",
  microbrowser = "Utilities",
  micronotes = "Office",
  microreader = "Office",
  microsheets = "Office",
  microword = "Office",
  pixel = "Games",
  desktop = "Utilities",
  designer = "Development",
}

local categories = { order = DEFAULT_CATEGORY_ORDER, map = DEFAULT_CATEGORY_MAP }
local orderRank

local function copyList(list)
  local out = {}
  for i, v in ipairs(list or {}) do out[i] = v end
  return out
end

local function copyMap(map)
  local out = {}
  for k, v in pairs(map or {}) do out[k] = v end
  return out
end

local function categoriesPath(root)
  return root and (root .. "/apps/desktop/categories.lua") or nil
end

local function loadCategories()
  local ok, cfg = pcall(require, "categories")
  if not ok or type(cfg) ~= "table" then return end

  if type(cfg.order) == "table" then
    local order = {}
    for _, name in ipairs(cfg.order) do
      if type(name) == "string" and name ~= "" then order[#order + 1] = name end
    end
    if #order > 0 then categories.order = order end
  end

  if type(cfg.map) == "table" then
    local map = {}
    for name, category in pairs(DEFAULT_CATEGORY_MAP) do map[name] = category end
    for name, category in pairs(cfg.map) do
      if type(name) == "string" and type(category) == "string" and category ~= "" then
        map[name] = category
      end
    end
    categories.map = map
  end
end

local function rankOf(category)
  if not orderRank then
    orderRank = {}
    for i, name in ipairs(categories.order) do orderRank[name] = i end
  end
  return orderRank[category] or 999
end

loadCategories()

local function applyCategories(setup)
  setup = setup or {}

  local order = {}
  for _, name in ipairs(setup.order or {}) do
    if type(name) == "string" and name ~= "" then order[#order + 1] = name end
  end
  if #order == 0 then order = copyList(DEFAULT_CATEGORY_ORDER) end

  local map = copyMap(DEFAULT_CATEGORY_MAP)
  for name, category in pairs(setup.map or {}) do
    if type(name) == "string" and type(category) == "string" and category ~= "" then
      map[name] = category
    end
  end

  categories = { order = order, map = map }
  orderRank = nil
end

local function normalize(path)
  path = (path or ""):gsub("\\", "/")
  path = path:gsub("/+", "/")
  if #path > 1 and path:sub(-1) == "/" then path = path:sub(1, -2) end
  return path
end

local function dirname(path)
  path = normalize(path)
  if path == "" then return "." end
  local i = path:match("^.*()/")
  if not i then return "." end
  if i == 1 then return "/" end
  return path:sub(1, i - 1)
end

local function basename(path)
  path = normalize(path)
  local i = path:match("^.*()/")
  return i and path:sub(i + 1) or path
end

local function join(a, b)
  if not a or a == "" then return normalize(b) end
  if not b or b == "" then return normalize(a) end
  if b:sub(1, 1) == "/" or b:match("^%a:[/\\]") then return normalize(b) end
  return normalize(a .. "/" .. b)
end

local function exists(path)
  return lfs.attributes(path) ~= nil
end

local function isDir(path)
  return lfs.attributes(path, "mode") == "directory"
end

local function detectRootFromArg0(arg0)
  arg0 = normalize(arg0)
  if arg0 == "" then return nil end
  local parts = {}
  for p in arg0:gmatch("[^/]+") do parts[#parts + 1] = p end
  for i = #parts, 1, -1 do
    if parts[i] == "dist" or parts[i] == "apps" then
      if i == 1 then return "/" end
      return table.concat(parts, "/", 1, i - 1)
    end
  end
  return dirname(arg0)
end

local function looksLikeRoot(path)
  path = normalize(path)
  return isDir(path) and isDir(join(path, "apps")) and exists(join(path, "Makefile"))
end

function M.findRoot()
  local env = normalize(os.getenv("TURBOAPPS_ROOT") or "")
  if env ~= "" and looksLikeRoot(env) then return env end

  local fromArg = detectRootFromArg0((arg or {})[0] or "")
  if fromArg and looksLikeRoot(fromArg) then return fromArg end

  local cwd = normalize(lfs.currentdir() or ".")
  if looksLikeRoot(cwd) then return cwd end

  local probe = cwd
  for _ = 1, 6 do
    local up = dirname(probe)
    if up == probe then break end
    probe = up
    if looksLikeRoot(probe) then return probe end
  end

  return cwd
end

local function appRecord(root, name)
  local folder = join(root, "apps/" .. name)
  local bundle = join(root, "dist/" .. name .. ".ztl")
  return {
    kind = "app",
    name = name,
    category = M.categoryOf(name),
    folder = folder,
    main = join(folder, "main.lua"),
    bundle = bundle,
    hasBundle = exists(bundle),
  }
end

local function designerRecord(root)
  return {
    kind = "designer",
    name = "designer",
    title = "Visual Turbo Lua",
    category = "Development",
    folder = join(root, "apps/desktop"),
    main = nil,
    bundle = nil,
    hasBundle = false,
  }
end

function M.categoryOf(name)
  return categories.map[name] or "Other"
end

function M.categoryOrder(category)
  return rankOf(category)
end

function M.categorySetup()
  return {
    order = copyList(categories.order),
    map = copyMap(categories.map),
  }
end

function M.applyCategories(setup)
  applyCategories(setup)
end

function M.categoriesPath(root)
  return categoriesPath(root)
end

function M.readCategories(root)
  local path = categoriesPath(root)
  if not path then return M.categorySetup() end
  local fn = loadfile(path)
  if not fn then return M.categorySetup() end
  setfenv(fn, {})
  local ok, cfg = pcall(fn)
  if not ok or type(cfg) ~= "table" then return M.categorySetup() end
  return {
    order = copyList(cfg.order or {}),
    map = copyMap(cfg.map or {}),
  }
end

local function quote(s)
  return string.format("%q", s)
end

function M.writeCategories(root, setup)
  local path = categoriesPath(root)
  if not path then return nil, "no categories path" end
  setup = setup or M.categorySetup()

  local lines = {
    "-- Category setup for Turbo Desktop.",
    "--",
    "-- Edit order to change the category order in the UI.",
    "-- Edit map to assign apps to categories.",
    "",
    "return {",
    "  order = {",
  }

  for _, name in ipairs(setup.order or {}) do
    if type(name) == "string" and name ~= "" then
      lines[#lines + 1] = ("    %s,"):format(quote(name))
    end
  end

  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "  map = {"

  local keys = {}
  for name, category in pairs(setup.map or {}) do
    if type(name) == "string" and type(category) == "string" and category ~= "" then
      keys[#keys + 1] = name
    end
  end
  table.sort(keys)
  for _, name in ipairs(keys) do
    lines[#lines + 1] = ("    [%s] = %s,"):format(quote(name), quote(setup.map[name]))
  end

  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""

  local f, err = io.open(path, "wb")
  if not f then return nil, err end
  f:write(table.concat(lines, "\n"))
  f:close()

  return true
end

function M.listApps(root)
  local dir = join(root, "apps")
  local out = {}
  for name in lfs.dir(dir) do
    if name ~= "." and name ~= ".." and isDir(join(dir, name)) then
      local main = join(dir, name .. "/main.lua")
      if exists(main) then out[#out + 1] = appRecord(root, name) end
    end
  end
  out[#out + 1] = designerRecord(root)
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

function M.displayName(app)
  if app.kind == "designer" then return app.title end
  return app.hasBundle and (app.name .. " (bundle)") or app.name
end

function M.command(app, mode, interpreter)
  local exe = interpreter or (gui and gui.interpreter) or "tlua"
  if app.kind == "designer" then
    return { exe, "design", app.folder }
  end
  if mode == "design" then
    return { exe, "design", app.folder }
  end
  local target = app.hasBundle and app.bundle or app.main
  return { exe, target }
end

function M.basename(path)
  return basename(path)
end

return M
