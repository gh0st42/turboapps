-- The code behind Desktop.form.lua: the controls are fields of the form,
-- by the names the layout gives them.

local gui = require "gui"
local catalog = require "catalog"
local openwith = require "openwith"
local frm = gui.load "Desktop" --[[@as forms.Desktop]]

local root = catalog.findRoot()
local categorySetup = catalog.readCategories(root)
catalog.applyCategories(categorySetup)
local apps = {}
local categories = {}
local refresh

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function categorySort(a, b)
  local pa = catalog.categoryOrder(a)
  local pb = catalog.categoryOrder(b)
  if pa ~= pb then return pa < pb end
  return a < b
end

local function hasCategory(name)
  for _, c in ipairs(categorySetup.order or {}) do
    if c == name then return true end
  end
  return false
end

local function addCategory(name)
  name = trim(name)
  if name == "" then return false end
  if hasCategory(name) then return false end
  categorySetup.order[#categorySetup.order + 1] = name
  return true
end

local function current()
  if (frm.tabViews.selected or 1) == 2 then
    local i = frm.lstCategoryApps.selected or 0
    local shown = frm.lstCategoryApps.tag or {}
    return shown[i]
  end
  local i = frm.lstApps.selected or 0
  local shown = frm.lstApps.tag or apps
  return shown[i]
end

local function setStatus(text)
  frm.lblStatus.caption = text and ("  " .. text) or ""
end

local function showSpawnError(title, err)
  gui.msgbox(("%s\n\n%s"):format(title, tostring(err)), "ok", "Turbo Desktop")
end

local function spawnApp(app, mode)
  if not app then
    gui.msgbox("Bitte zuerst eine App auswaehlen.", "ok", "Turbo Desktop")
    return
  end

  local cmd = catalog.command(app, mode, gui.interpreter)
  local errors = {}
  local label = mode == "design" and "Designer" or "Launch"

  local task = {
    dir = root,
    onOutput = function(line, stream)
      if stream == "stderr" then
        errors[#errors + 1] = line
        if #errors > 12 then table.remove(errors, 1) end
      end
    end,
    onExit = function(code)
      if code ~= 0 then
        local detail = table.concat(errors, "\n")
        if detail == "" then detail = "Keine weiteren Fehlermeldungen." end
        gui.msgbox(("%s fuer %s wurde mit Fehler beendet (%d).\n\n%s")
          :format(label, app.name, code, detail), "ok", "Turbo Desktop")
      end
    end,
  }
  for i, part in ipairs(cmd) do task[i] = part end

  local ok, err = pcall(gui.spawn, task)

  if not ok then
    showSpawnError(("Kann %s fuer %s nicht starten."):format(label, app.name), err)
    return
  end

  setStatus(("%s gestartet: %s"):format(label, app.name))
end

-- openFile asks for a file and opens it in the app of ours for it: a picture
-- in the image viewer, a spreadsheet in MicroSheets, and so on. The one to
-- use is the first there is; when several would do, the menu of Files'
-- Open With is the way to pick another.
local function openFile(path)
  path = path or gui.openfile { title = "Open File" }
  if not path then return end
  local name = openwith.available(path, { env = root, arg0 = (arg or {})[0] })[1]
  if not name then
    gui.msgbox(("There is no app here for %s."):format(catalog.basename(path)), "ok", "Turbo Desktop")
    return
  end
  local cmd = openwith.command(name, path, gui.interpreter, { env = root, arg0 = (arg or {})[0] })
  local errors = {}
  local task = {
    dir = root,
    onOutput = function(line, stream)
      if stream == "stderr" then
        errors[#errors + 1] = line
        if #errors > 12 then table.remove(errors, 1) end
      end
    end,
    onExit = function(code)
      if code ~= 0 then
        gui.msgbox(("%s stopped with an error (%d).\n\n%s"):format(openwith.TITLES[name] or name, code,
          table.concat(errors, "\n")), "ok", "Turbo Desktop")
      end
    end,
  }
  for i, part in ipairs(cmd) do task[i] = part end
  local ok, err = pcall(gui.spawn, task)
  if not ok then
    showSpawnError(("Cannot start %s."):format(openwith.TITLES[name] or name), err)
    return
  end
  setStatus(("Opened %s in %s"):format(catalog.basename(path), openwith.TITLES[name] or name))
end

local function showCategoryApps(name)
  local shown, names = {}, {}
  for _, app in ipairs(apps) do
    if app.category == name then
      shown[#shown + 1] = app
      names[#names + 1] = catalog.displayName(app)
    end
  end
  frm.lstCategoryApps.tag = shown
  frm.lstCategoryApps.items = names
  if #shown > 0 then
    frm.lstCategoryApps.selected = math.min(frm.lstCategoryApps.selected or 1, #shown)
  else
    frm.lstCategoryApps.selected = 0
  end
end

local function saveCategories()
  local ok, err = catalog.writeCategories(root, categorySetup)
  if not ok then
    gui.msgbox(("Kategorien konnten nicht gespeichert werden.\n\n%s"):format(tostring(err)), "ok", "Turbo Desktop")
    return false
  end
  setStatus("Kategorien gespeichert: " .. catalog.categoriesPath(root))
  return true
end

local function setCategoryForCurrent()
  local app = current()
  if not app then
    gui.msgbox("Bitte zuerst eine App auswaehlen.", "ok", "Turbo Desktop")
    return
  end
  local currentCategory = app.category or "Other"
  local name = gui.inputbox(("Kategorie fuer %s:"):format(catalog.displayName(app)), "Set Category", currentCategory)
  if not name then return end
  name = trim(name)
  if name == "" then return end

  addCategory(name)
  categorySetup.map[app.name] = name
  catalog.applyCategories(categorySetup)
  refresh()
  setStatus(("%s -> %s"):format(app.name, name))
end

local function newCategory()
  local name = gui.inputbox("Name der neuen Kategorie:", "New Category", "")
  if not name then return end
  name = trim(name)
  if name == "" then return end
  if hasCategory(name) then
    gui.msgbox("Diese Kategorie gibt es schon.", "ok", "Turbo Desktop")
    return
  end
  addCategory(name)
  catalog.applyCategories(categorySetup)
  refresh()
  for i, c in ipairs(categories) do
    if c == name then
      frm.tabViews.selected = 2
      frm.lstCategories.selected = i
      showCategoryApps(name)
      break
    end
  end
  setStatus("Kategorie angelegt: " .. name)
end

refresh = function()
  apps = catalog.listApps(root)
  local names = {}
  for i, app in ipairs(apps) do names[i] = catalog.displayName(app) end
  frm.lstApps.tag = apps
  frm.lstApps.items = names
  if #apps > 0 then frm.lstApps.selected = math.min(frm.lstApps.selected or 1, #apps) end

  categories = {}
  local seen = {}
  for _, name in ipairs(categorySetup.order or {}) do
    if type(name) == "string" and name ~= "" and not seen[name] then
      categories[#categories + 1] = name
      seen[name] = true
    end
  end
  for _, app in ipairs(apps) do
    if app.category and app.category ~= "" and not seen[app.category] then
      categories[#categories + 1] = app.category
      seen[app.category] = true
    end
  end
  table.sort(categories, categorySort)
  frm.lstCategories.items = categories
  if #categories > 0 then
    frm.lstCategories.selected = math.min(frm.lstCategories.selected or 1, #categories)
    showCategoryApps(categories[frm.lstCategories.selected])
  else
    frm.lstCategoryApps.items = {}
    frm.lstCategoryApps.tag = {}
  end

  frm.caption = ("Turbo Desktop - %s"):format(catalog.basename(root))
  setStatus(("%d Apps gefunden unter %s"):format(#apps, root))
end

frm.cmdLaunch.onClick = function() spawnApp(current(), "gui") end
frm.cmdDesign.onClick = function() spawnApp(current(), "design") end
frm.cmdRefresh.onClick = refresh
frm.cmdSetCategory.onClick = setCategoryForCurrent
frm.cmdNewCategory.onClick = newCategory
frm.cmdSaveCategories.onClick = saveCategories

frm.lstApps.onDoubleClick = function()
  spawnApp(current(), "gui")
end

frm.lstCategories.onChange = function()
  local name = categories[frm.lstCategories.selected or 0]
  if name then showCategoryApps(name) end
end

frm.lstCategoryApps.onDoubleClick = function()
  spawnApp(current(), "gui")
end

frm.Menu1.onClick = function(_, name)
  local actions = {
    mnuLaunch = function() spawnApp(current(), "gui") end,
    mnuDesign = function() spawnApp(current(), "design") end,
    mnuRefresh = refresh,
    mnuOpenFile = function() openFile() end,
    mnuSetCategory = setCategoryForCurrent,
    mnuNewCategory = newCategory,
    mnuSaveCategories = saveCategories,
    mnuExit = function() frm:close() end,
    mnuAbout = function()
      gui.msgbox(
        "Turbo Desktop\n\nProgram Manager fuer turboapps.\n" ..
        "Startet Apps normal oder im tlua Designer, und verwaltet Kategorien.",
        "ok",
        "About Turbo Desktop"
      )
    end,
  }
  local fn = actions[name]
  if fn then fn() end
end

refresh()

-- Exposed for the tests.
frm.openFile = openFile

return frm
