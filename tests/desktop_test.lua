-- tlua -p apps/desktop -p tests tests/desktop_test.lua

local t = require "testing"
local lfs = require "lfs"
local catalog = require "catalog"
local test, eq, ok = t.test, t.eq, t.ok

local root = os.tmpname()
os.remove(root)
assert(lfs.mkdir(root))
assert(lfs.mkdir(root .. "/apps"))
assert(lfs.mkdir(root .. "/dist"))

local function write(path, text)
  local f = assert(io.open(path, "wb"))
  f:write(text or "")
  f:close()
end

write(root .. "/Makefile", "all:\n")

local function mkapp(name)
  assert(lfs.mkdir(root .. "/apps/" .. name))
  write(root .. "/apps/" .. name .. "/main.lua", "print('" .. name .. "')\n")
end

mkapp("alpha")
mkapp("beta")
write(root .. "/dist/beta.ztl", "x")
assert(lfs.mkdir(root .. "/apps/desktop"))

test("listApps finds app folders with main.lua", function()
  local apps = catalog.listApps(root)
  eq(#apps, 3)
  eq(apps[1].name, "alpha")
  eq(apps[2].name, "beta")
  eq(apps[3].kind, "designer")
  eq(apps[1].category, "Other")
  eq(apps[2].category, "Other")
  eq(apps[3].category, "Development")
  eq(apps[1].hasBundle, false)
  eq(apps[2].hasBundle, true)
end)

test("displayName marks bundled apps", function()
  local apps = catalog.listApps(root)
  eq(catalog.displayName(apps[1]), "alpha")
  eq(catalog.displayName(apps[2]), "beta (bundle)")
  eq(catalog.displayName(apps[3]), "Visual Turbo Lua")
end)

test("command builds launch and design calls", function()
  local apps = catalog.listApps(root)
  local app = apps[2]
  local designer = apps[3]

  local normal = catalog.command(app, "gui", "tlua")
  eq(normal[1], "tlua")
  eq(normal[2]:match("beta%.ztl$") ~= nil, true)

  local design = catalog.command(app, "design", "tlua")
  eq(design[1], "tlua")
  eq(design[2], "design")
  eq(design[3]:match("/apps/beta$") ~= nil, true)

  local designApp = catalog.command(designer, "gui", "tlua")
  eq(designApp[1], "tlua")
  eq(designApp[2], "design")
  eq(designApp[3]:match("/apps/desktop$") ~= nil, true)
end)

test("categoryOf maps known app names", function()
  eq(catalog.categoryOf("microword"), "Office")
  eq(catalog.categoryOf("pixel"), "Games")
  eq(catalog.categoryOf("files"), "Utilities")
  eq(catalog.categoryOf("designer"), "Development")
  eq(catalog.categoryOf("something-new"), "Other")
end)

test("categoryOrder follows configured order", function()
  ok(catalog.categoryOrder("Office") < catalog.categoryOrder("Utilities"), "Office before Utilities")
  ok(catalog.categoryOrder("Utilities") < catalog.categoryOrder("Development"), "Utilities before Development")
  ok(catalog.categoryOrder("Development") < catalog.categoryOrder("Games"), "Development before Games")
  ok(catalog.categoryOrder("Games") < catalog.categoryOrder("Other"), "Games before Other")
  ok(catalog.categoryOrder("NotConfigured") > catalog.categoryOrder("Other"), "unknown categories sort after configured")
end)

test("categories can be written and read from desktop config", function()
  local setup = {
    order = { "Tools", "Docs" },
    map = { alpha = "Tools", beta = "Docs" },
  }
  ok(catalog.writeCategories(root, setup), "written")
  local back = catalog.readCategories(root)
  eq(back.order[1], "Tools")
  eq(back.order[2], "Docs")
  eq(back.map.alpha, "Tools")
  eq(back.map.beta, "Docs")
end)

test("applyCategories overrides runtime mapping", function()
  local old = catalog.categorySetup()
  catalog.applyCategories {
    order = { "A", "B" },
    map = { alpha = "A" },
  }
  eq(catalog.categoryOf("alpha"), "A")
  ok(catalog.categoryOrder("A") < catalog.categoryOrder("B"), "configured order in effect")
  catalog.applyCategories(old)
end)
