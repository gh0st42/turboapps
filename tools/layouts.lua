-- Does to each app what tlua design does when it saves a form: writes the
-- layout (forms/Name.form.lua) through gui.save, and the language server's
-- stub (forms/Name.d.lua) beside it. A layout edited by hand comes out as
-- the designer would have written it.
--
--   tlua tools/layouts.lua apps/calculator apps/editor          rewrite them
--   tlua tools/layouts.lua --check apps/calculator apps/editor  only compare
--
-- With --check nothing is written, and the exit status says whether every
-- file is already as the designer writes it.

local gui = require "gui"
local lfs = require "lfs"

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function writeFile(path, text)
  local f = assert(io.open(path, "wb"))
  f:write(text)
  f:close()
end

-- readLayout runs a layout file with nothing in scope, as gui.load does.
local function readLayout(path)
  local fn, err = loadfile(path)
  if not fn then return nil, err end
  setfenv(fn, {})
  local ok, doc = pcall(fn)
  if not ok then return nil, doc end
  if type(doc) ~= "table" or doc.kind ~= "Form" then
    return nil, path .. " does not return a form's layout"
  end
  return doc
end

-- layoutText is what gui.save writes for a layout.
local tmp = os.tmpname()
local function layoutText(doc)
  gui.save(doc, tmp)
  return readFile(tmp)
end

local kinds = gui.kinds()

local function classOf(kind)
  local info = kinds[kind]
  if info and (not info.defined or info.builtin) then return "gui." .. kind end
  return "gui.Object"
end

local function walk(node, fn)
  for _, child in ipairs(node) do
    fn(child)
    walk(child, fn)
  end
end

-- stubText is what the designer writes as Name.d.lua.
local function stubText(name, doc)
  local lines = {
    "---@meta",
    "-- What " .. name .. ".form.lua has in it, for a language server. Written by tlua",
    "-- design each time the form is saved; changing it here changes nothing.",
    "",
    "---@class forms." .. name .. ": gui.Form",
  }
  local fields = {}
  walk(doc, function(node)
    if node.name then fields[#fields + 1] = ("---@field %s %s"):format(node.name, classOf(node.kind)) end
  end)
  table.sort(fields)
  for _, f in ipairs(fields) do lines[#lines + 1] = f end
  return table.concat(lines, "\n") .. "\n"
end

local check, dirs = false, {}
for _, a in ipairs(arg) do
  if a == "--check" then check = true else dirs[#dirs + 1] = a end
end
if #dirs == 0 then
  io.stderr:write("usage: tlua tools/layouts.lua [--check] appdir...\n")
  os.exit(2)
end

local problems, files = 0, 0

-- settle writes want to path, or with --check says whether it is there.
local function settle(path, want)
  files = files + 1
  if readFile(path) == want then return end
  if check then
    problems = problems + 1
    print(path .. ": not as tlua design writes it (run make layouts)")
  else
    writeFile(path, want)
    print("wrote " .. path)
  end
end

local basePath = package.path

for _, dir in ipairs(dirs) do
  -- A layout's own controls are the modules controls.<Kind> of its app.
  package.path = dir .. "/?.lua;" .. basePath
  local formsDir = dir .. "/forms"
  if lfs.attributes(formsDir, "mode") == "directory" then
    local names = {}
    for file in lfs.dir(formsDir) do
      local name = file:match("^(.+)%.form%.lua$")
      if name then names[#names + 1] = name end
    end
    table.sort(names)
    for _, name in ipairs(names) do
      local path = formsDir .. "/" .. name .. ".form.lua"
      local doc, err = readLayout(path)
      if not doc then
        problems = problems + 1
        print(err)
      else
        -- gui.load builds it, so a property the gui module refuses is
        -- caught here and not when the app is run.
        local ok, lerr = pcall(gui.load, doc)
        if not ok then
          problems = problems + 1
          print(path .. ": " .. tostring(lerr))
        else
          if doc.name ~= name then
            problems = problems + 1
            print(("%s: the form is named %q, not %q"):format(path, tostring(doc.name), name))
          end
          settle(path, layoutText(doc))
          settle(formsDir .. "/" .. name .. ".d.lua", stubText(name, doc))
        end
      end
    end
  end
end

os.remove(tmp)
if check then
  print(("%d files checked, %d problems"):format(files, problems))
end
os.exit(problems == 0 and 0 or 1)
