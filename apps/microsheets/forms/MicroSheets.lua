-- The code behind MicroSheets.form.lua: the controls are fields of the
-- form, by the names the layout gives them. The grid (controls/Grid.lua)
-- does the work on the sheet; this wires it to the menus, the formula bar,
-- the sheet tabs, the status bar and files.

local gui = require "gui"
local lfs = require "lfs"
local book = require "book"
local formula = require "formula"
local workbook = require "workbook"
local themes = require "themes"
local report = require "forms.Report"
local filterForm = require "forms.Filter"
local chartForm = require "forms.ChartView"
local helpForm = require "forms.FunctionHelp"
local fnhelp = require "fnhelp"

local frm = gui.load "MicroSheets" --[[@as forms.MicroSheets]]
local grid = frm.grdSheet
local tabs = frm.tabSheets

local path = nil        -- the file shown, or nil
local csvSep = nil      -- its separator, when it is a CSV file
local password = nil    -- what the workbook is encrypted with, or nil
local settings = workbook.loadSettings()
local syncing = false   -- the formula bar is being set from here

local function sheet() return grid:sheet() end

local function plural(n, one, many) return n .. " " .. (n == 1 and one or (many or one .. "s")) end

-- number writes a number for the status bar, with thousands marked.
local function number(n)
  local s = formula.formatNumber(math.floor(n * 100 + 0.5) / 100)
  local sign, int, frac = s:match("^(-?)(%d+)(.*)$")
  if not int or #int < 5 then return s end
  return sign .. int:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") .. frac
end

---------------------------------------------------------------- the menu

-- item finds a menu item by name, in the menu's own tables.
local function item(name, items)
  items = items or frm.Menu1.items
  for _, it in ipairs(items) do
    if type(it) == "table" then
      if it.name == name then return it end
      if type(it[2]) == "table" then
        local found = item(name, it[2])
        if found then return found end
      end
    end
  end
end

local function setChecked(name, on)
  local items = frm.Menu1.items
  local it = item(name, items)
  if it and it.checked ~= on then
    it.checked = on
    frm.Menu1.items = items
  end
end

local function showChecks()
  local items = frm.Menu1.items
  item("mnuVim", items).checked = settings.vimKeys
  item("mnuFormulas", items).checked = settings.showFormulas
  item("mnuFreeze", items).checked = sheet().frozen
  for i, name in ipairs(themes.names()) do item("mnuTheme" .. i, items).checked = name == settings.theme end
  frm.Menu1.items = items
end

---------------------------------------------------------------- what shows

local function updateTitle()
  local name = path and workbook.basename(path) or "Untitled"
  frm.caption = (grid.book.dirty and "• " or "") .. name .. (password and " (encrypted)" or "") .. " - microsheets"
end

local function rangeName()
  local r1, c1, r2, c2 = grid:selection()
  local v = grid:view()
  if r1 == r2 and c1 == c2 then return formula.refName(v.r, v.c) end
  return formula.refName(r1, c1) .. ":" .. formula.refName(r2, c2)
end

-- updateStatus shows the mode, and sums up the selection, or the cursor's
-- column when one cell is selected.
local function updateStatus()
  local mode = grid:mode()
  local pending = grid.pending ~= "" and (" " .. grid.pending) or ""
  frm.lblMode.caption = mode .. pending
  local colors = { READY = "#2f6fd8", EDIT = "#2e9d57", POINT = "#c27c0e", VISUAL = "#8a4fd0" }
  frm.lblMode.color = colors[mode] or "#2f6fd8"

  -- While a formula is typed, the function it is in says how it goes.
  local entry = grid.entry
  local hint = entry and fnhelp.hint(entry.text, entry.caret)
  if hint then
    frm.lblStatus.caption = "  " .. hint
    return
  end

  local s, v = sheet(), grid:view()
  local parts = {}
  local r1, c1, r2, c2 = grid:selection()
  local st, what
  if r1 ~= r2 or c1 ~= c2 then
    st, what = grid.book:stats(s, r1, c1, r2, c2), ""
  else
    st, what = grid.book:stats(s, s.frozen and 2 or 1, v.c, math.max(1, s.rows), v.c), "column " .. formula.colName(v.c) .. ": "
  end
  if st.numbers > 0 then
    parts[#parts + 1] = ("%sSum %s   Average %s   Min %s   Max %s   Count %d"):format(what, number(st.sum),
      number(st.average), number(st.min), number(st.max), st.count)
  elseif st.count > 0 then
    parts[#parts + 1] = what .. "Count " .. st.count
  end
  if v.filter then
    parts[#parts + 1] = ("▾ %s%s (%s)"):format(v.filter.expr, v.filter.col and (" in " .. formula.colName(v.filter.col)) or "",
      plural(#v.filter.rows, "row"))
  end
  if grid.search then
    local sr = grid.search
    if #sr.list == 0 then parts[#parts + 1] = "“" .. sr.text .. "” not found"
    else parts[#parts + 1] = ("“%s” %d of %d"):format(sr.text, sr.i, #sr.list) end
  end
  frm.lblStatus.caption = "  " .. table.concat(parts, "      ")
end

-- updateBar shows the cell in the formula bar, unless it is being edited.
local function updateBar()
  syncing = true
  frm.txtCell.text = rangeName()
  if grid.entry then
    if frm.txtFormula.text ~= grid.entry.text then frm.txtFormula.text = grid.entry.text end
  else
    local v = grid:view()
    frm.txtFormula.text = sheet():get(v.r, v.c) or ""
  end
  syncing = false
end

local function refresh()
  updateTitle()
  updateBar()
  updateStatus()
  tabs.book = grid.book
  tabs:redraw()
end

function grid:onSelect()
  updateBar()
  updateStatus()
  tabs:redraw()
  setChecked("mnuFreeze", sheet().frozen)
end

function grid:onChange()
  updateTitle()
  updateStatus()
  tabs:redraw()
end

function grid:onEdit()
  updateBar()
  updateStatus()
end

---------------------------------------------------------------- the formula bar

function frm.txtFormula:onChange()
  if syncing then return end
  grid:setEditText(self.text, self.cursor)
  updateStatus()
end

function frm.txtFormula:onKey(key)
  if key == "Enter" or key == "KP_Enter" then
    if grid.entry then grid:commit("down") end
    grid:focus()
    return true
  end
  if key == "Tab" then
    if grid.entry then grid:commit("right") end
    grid:focus()
    return true
  end
  if key == "Escape" then
    grid:cancel()
    grid:focus()
    return true
  end
end

-- goTo reads where to go: "B12", "B2:D8", "Sheet2!A1", a row ("500") or
-- a row and a column ("10,5").
local function goTo(text)
  text = (text or ""):match("^%s*(.-)%s*$")
  local sheetName, rest = text:match("^'?(.-)'?!(.*)$")
  if sheetName then
    local _, i = grid.book:find(sheetName)
    if not i then gui.msgbox("There is no sheet called " .. sheetName .. ".", "ok", "Go To") return false end
    grid:selectSheet(i)
    text = rest
  end
  local a, b = text:match("^(%$?%a+%$?%d+):(%$?%a+%$?%d+)$")
  if a then
    local r1, c1 = formula.parseRef(a)
    local r2, c2 = formula.parseRef(b)
    if r1 and r2 then grid:moveTo(r2, c2, r1, c1) return true end
  end
  local r, c = formula.parseRef(text)
  if not r then
    local rr, cc = text:match("^(%d+)%s*,%s*(%d+)$")
    if rr then r, c = tonumber(rr), tonumber(cc)
    elseif text:find("^%d+$") then r, c = tonumber(text), grid:view().c end
  end
  if not r then
    gui.msgbox("Go to a cell (B12), a range (B2:D8), a row (500) or a row and a column (10,5).", "ok", "Go To")
    return false
  end
  grid:moveTo(r, c)
  return true
end

function frm.txtCell:onKey(key)
  if key == "Enter" or key == "KP_Enter" then
    if goTo(self.text) then grid:focus() end
    return true
  end
  if key == "Escape" then
    updateBar()
    grid:focus()
    return true
  end
end

---------------------------------------------------------------- files

local function setBook(b, file, sep, pw)
  path, csvSep, password = file, sep, pw
  grid:setBook(b)
  tabs.book = b
  showChecks()
  refresh()
end

local function openPath(file)
  local b, sepOrErr, why = workbook.load(file)
  local pw
  -- An encrypted workbook asks for its password until it is right.
  while not b and why == "locked" do
    pw = gui.passwordbox((sepOrErr:find("wrong", 1, true) and "Wrong password. " or "")
      .. workbook.basename(file) .. " is encrypted.\nPassword:", "Open")
    if not pw then return false end
    b, sepOrErr, why = workbook.load(file, pw)
  end
  if not b then
    gui.msgbox("Could not open " .. file .. ":\n" .. tostring(sepOrErr), "ok", "microsheets")
    return false
  end
  setBook(b, file, workbook.isCSV(file) and sepOrErr or nil, pw)
  return true
end

local function saveTo(file, asCSV)
  if grid.entry then grid:commit() end
  local ok, err
  if asCSV then
    ok, err = workbook.exportCSV(file, grid.book, sheet(), csvSep)
  else
    ok, err = workbook.save(file, grid.book, password)
  end
  if not ok then
    gui.msgbox("Could not save " .. file .. ":\n" .. tostring(err), "ok", "microsheets")
    return false
  end
  path = file
  if not asCSV then csvSep = nil end
  grid.book.dirty = false
  updateTitle()
  return true
end

local FILTER = "Workbooks\t*.zms\nCSV and text\t*.{csv,tsv,txt}\nAll files\t*"

local function saveAs()
  if grid.entry then grid:commit() end
  local start = path and (workbook.isCSV(path) and path:gsub("%.[^./\\]+$", "." .. workbook.EXT) or path) or ("Untitled." .. workbook.EXT)
  local file = gui.savefile { title = "Save Workbook", filter = "Workbooks\t*.zms", file = start }
  if not file then return false end
  if not file:lower():find("%." .. workbook.EXT .. "$") then file = file .. "." .. workbook.EXT end
  return saveTo(file)
end

-- hasMore says the workbook holds what a CSV file cannot keep.
local function hasMore()
  local b = grid.book
  if #b.sheets > 1 then return true end
  local more = false
  sheet():each(function(_, _, raw) if book.isFormula(raw) then more = true end end)
  return more
end

local function save()
  if not path then return saveAs() end
  -- A CSV file cannot be encrypted: it is saved as a workbook instead.
  if workbook.isCSV(path) and password then return saveAs() end
  if workbook.isCSV(path) then
    if hasMore() then
      local answer = gui.msgbox(workbook.basename(path) .. " can keep only the values of one sheet, not its formulas or other sheets.\n\n"
        .. "Save it as a workbook (." .. workbook.EXT .. ") instead?", "yesnocancel", "microsheets")
      if answer == "yes" then return saveAs() end
      if answer ~= "no" then return false end
    end
    return saveTo(path, true)
  end
  return saveTo(path)
end

local function confirmDiscard()
  if grid.entry then grid:commit() end
  if not grid.book.dirty then return true end
  local answer = gui.msgbox("Do you want to save the changes to " .. (path and workbook.basename(path) or "this workbook") .. "?",
    "yesnocancel", "microsheets")
  if answer == "yes" then return save() end
  return answer == "no"
end

-- setPassword encrypts the workbook, all of it, when it is next saved; an
-- empty password takes the encryption off.
local function setPassword()
  local pw = gui.passwordbox("Password for this workbook.\nLeave it empty to remove the password.", "Set Password", true)
  if not pw then return end
  password = pw ~= "" and pw or nil
  grid.book.dirty = true
  updateTitle()
end

local function newBook()
  if confirmDiscard() then setBook(book.new(), nil) end
end

local function openDialog()
  if not confirmDiscard() then return end
  local file = gui.openfile { title = "Open Workbook", filter = FILTER }
  if file then openPath(file) end
end

local function export(kind)
  if grid.entry then grid:commit() end
  local s = sheet()
  local base = path and path:gsub("%.[^./\\]+$", "") or "Untitled"
  if #grid.book.sheets > 1 then base = base .. "-" .. s.name end
  local file = gui.savefile { title = "Export " .. s.name .. " as " .. kind:upper(),
    filter = kind == "csv" and "CSV\t*.csv\nTab-separated\t*.tsv" or "JSON\t*.json", file = base .. "." .. kind }
  if not file then return end
  local ok, err
  if kind == "csv" then ok, err = workbook.exportCSV(file, grid.book, s)
  else ok, err = workbook.exportJSON(file, grid.book, s, s.frozen) end
  if not ok then gui.msgbox("Could not export " .. file .. ":\n" .. tostring(err), "ok", "microsheets") end
end

---------------------------------------------------------------- dialogs

local function findDialog()
  local text = gui.inputbox("Find (in values and formulas):", "Find", grid.search and grid.search.text or "")
  if not text or text == "" then return end
  local i, n = grid:findText(text)
  if n == 0 then gui.msgbox("“" .. text .. "” is not in this sheet.", "ok", "Find") end
  updateStatus()
end

local function gotoDialog()
  local text = gui.inputbox("Go to a cell (B12), a range (B2:D8), a row (500) or row,column (10,5):", "Go To", rangeName())
  if text then goTo(text) end
end

local function filterDialog()
  local v = grid:view()
  local current = v.filter
  local expr, all = filterForm.ask(formula.colName(v.c), current and current.expr, current and not current.col)
  if expr == "clear" then grid:clearFilter()
  elseif expr then
    local n, err = grid:setFilter(expr, all)
    if not n then gui.msgbox(err, "ok", "Filter") end
  end
  updateStatus()
  grid:focus()
end

local function renameSheet(i)
  i = i or grid.book.active
  local s = grid.book.sheets[i]
  local name = gui.inputbox("Name of the sheet:", "Rename Sheet", s.name)
  if not name or name == s.name then return end
  local ok, why = grid.book:renameSheet(i, name)
  if not ok then gui.msgbox(why, "ok", "Rename Sheet") return end
  grid:changed()
end

local function deleteSheet(i)
  i = i or grid.book.active
  local b = grid.book
  if #b.sheets <= 1 then gui.msgbox("A workbook keeps at least one sheet.", "ok", "Delete Sheet") return end
  local s = b.sheets[i]
  if s.rows > 0 and gui.msgbox("Delete the sheet " .. s.name .. " and everything on it?", "yesno", "Delete Sheet") ~= "yes" then return end
  b:removeSheet(i)
  grid:changed()
end

local function newSheet()
  local b = grid.book
  b:addSheet(nil, b.active + 1)
  grid:changed()
end

local function moveSheet(delta)
  local b = grid.book
  b:moveSheet(b.active, b.active + delta)
  grid:changed()
end

local function chart()
  local s = sheet()
  local r1, c1, r2, c2 = grid:selection()
  if r1 == r2 and c1 == c2 then
    -- One cell: chart the data around it, all of it.
    r1, c1, r2, c2 = 1, 1, math.max(1, s.rows), math.max(1, s.cols)
  end
  chartForm.view(grid.book, s, r1, c1, r2, c2, settings.theme,
    s.name .. "!" .. formula.refName(r1, c1) .. ":" .. formula.refName(r2, c2),
    (path and workbook.stem(path) .. "-" or "") .. s.name)
end

local function profile()
  local s = sheet()
  local cols = grid.book:profile(s, s.frozen)
  if #cols == 0 then gui.msgbox("This sheet is empty.", "ok", "Column Profile") return end
  local lines = {}
  local function row(...) lines[#lines + 1] = ("%-18s %-7s %7s %7s %7s %12s %12s %12s %12s"):format(...) end
  row("Column", "Kind", "Filled", "Empty", "Unique", "Sum", "Average", "Min", "Max")
  lines[#lines + 1] = ("-"):rep(18 + 8 + 8 * 3 + 13 * 4)
  for _, c in ipairs(cols) do
    local function n(x) return x and number(x) or "" end
    row(c.name:sub(1, 18), c.kind, c.filled, c.empty, c.unique, c.numbers > 0 and n(c.sum) or "", n(c.average), n(c.min), n(c.max))
  end
  local note = s.frozen and "Row 1 names the columns and is not counted." or "Every row is counted; freeze the header row to leave row 1 out."
  report.view("Column Profile - " .. s.name, table.concat(lines, "\n") .. "\n\n" .. note .. "\n")
end

local KEYS = [[
Moving                              Editing
  arrows, Tab, Enter                  typing replaces the cell (vim keys off)
  Ctrl/Cmd+arrow  edge of the data    F2, Enter  edit the cell (Enter: vim keys on)
  Home, End, Ctrl+Home, Ctrl+End      Enter / Tab  keep it and move down / right
  PageUp, PageDown                    Escape  put the cell back
  Shift with any of them selects      Ctrl+Enter  put it in every selected cell
  F5, or the cell box, to go to one   F4  cycle A1, $A$1, A$1, $A1
  Ctrl+PageDown/Up  next/last sheet   arrows or clicks after = ( + , point at cells

Vim keys (View > Vim Keys)
  h j k l      move (a count first: 5j)     i a Enter  edit      =  start a formula
  gg G 0 $     top, bottom, first, last     cc  replace the cell
  w b { }      edge of the data             x  cut    y  copy    yy Y  copy rows
  Ctrl+D/U     half a page down / up        p  paste
  v V          select a range               dd  delete rows   dc  delete columns
  gt gT        next / previous sheet        o  insert a row   O  insert a column
  u, Ctrl+R    undo, redo                   s S  sort the column up / down
  /  n  N      find, next, previous         f  filter rows    F  show them all
  > <          wider, narrower column       Ctrl+J / Ctrl+L  fill down / right
  :            go to (A100, 500, 10,5)      W  column profile   ?  this help
  t            next theme                   Escape  clears selection, search, filter

Formulas start with = and update as their cells do: =SUM(B2:B9)*2,
=IF(A1>0,"yes","no"), =Sheet2!A1, ='Q1 Sales'!B4. A $ keeps a reference
from moving when the cell is copied: =$A$1. F1 opens the formula help,
at the function being typed, with every function's parameters.
]]

-- functionHelp opens the formula help, at the function being typed if
-- there is one, and puts in the function Insert was pressed for.
local function functionHelp()
  local entry = grid.entry
  local name = entry and fnhelp.callAt(entry.text, entry.caret)
  local pick = helpForm.open(name)
  if pick then
    if grid.entry then grid:typeText(pick .. "(") else grid:beginEdit("=" .. pick .. "(") end
  end
  grid:focus()
  updateStatus()
end

---------------------------------------------------------------- settings

-- applySettings shows the settings, and with keep writes them down.
local function applySettings(keep)
  grid.vim = settings.vimKeys
  grid.theme = settings.theme
  grid.showFormulas = settings.showFormulas
  tabs.theme = settings.theme
  showChecks()
  if keep then workbook.saveSettings(settings) end
end

local function setTheme(name)
  settings.theme = name
  applySettings(true)
  updateStatus()
end

function grid:onCommand(name)
  if name == "search" then findDialog()
  elseif name == "filter" then filterDialog()
  elseif name == "goto" or name == "ex" then gotoDialog()
  elseif name == "help" then report.view("Keys", KEYS)
  elseif name == "fnhelp" then functionHelp()
  elseif name == "profile" then profile()
  elseif name == "chart" then chart()
  elseif name == "theme" then setTheme(themes.after(settings.theme)) end
end

---------------------------------------------------------------- menus

local actions = {
  mnuNew = newBook,
  mnuPassword = setPassword,
  mnuOpen = openDialog,
  mnuSave = save,
  mnuSaveAs = saveAs,
  mnuExportCSV = function() export("csv") end,
  mnuExportJSON = function() export("json") end,
  mnuExit = function() frm:close() end,
  mnuUndo = function() grid:undo() end,
  mnuRedo = function() grid:redo() end,
  mnuCut = function() if grid.entry then return end grid:copy(true) end,
  mnuCopy = function() if grid.entry then return end grid:copy() end,
  mnuPaste = function()
    if grid.entry then return end
    grid:paste()
  end,
  mnuClear = function() grid:clearSelection() end,
  mnuFillDown = function() grid:fill("down") end,
  mnuFillRight = function() grid:fill("right") end,
  mnuFind = findDialog,
  mnuFindNext = function() grid:findNext(1) updateStatus() end,
  mnuFindPrev = function() grid:findNext(-1) updateStatus() end,
  mnuGoto = gotoDialog,
  mnuSelectAll = function()
    local s = sheet()
    grid:moveTo(math.max(1, s.rows), math.max(1, s.cols), 1, 1)
  end,
  mnuVim = function(_, on) settings.vimKeys = on applySettings(true) updateStatus() end,
  mnuFormulas = function(_, on) settings.showFormulas = on applySettings(true) end,
  mnuFreeze = function() grid:toggleFreeze() end,
  mnuWider = function() grid:widen(16) end,
  mnuNarrower = function() grid:widen(-16) end,
  mnuStdWidth = function()
    local s = sheet()
    local _, c1, _, c2 = grid:selection()
    for c = c1, c2 do s.widths[c] = nil end
    grid.book.dirty = true
    grid:changed()
  end,
  mnuRowsAbove = function() grid:insertRows(false) end,
  mnuRowsBelow = function() grid:insertRows(true) end,
  mnuColsLeft = function() grid:insertCols(false) end,
  mnuColsRight = function() grid:insertCols(true) end,
  mnuNewSheet = newSheet,
  mnuDeleteRows = function() grid:deleteRows() end,
  mnuDeleteCols = function() grid:deleteCols() end,
  mnuDeleteSheet = function() deleteSheet() end,
  mnuSortAsc = function() grid:sort(false) end,
  mnuSortDesc = function() grid:sort(true) end,
  mnuFilter = filterDialog,
  mnuClearFilter = function() grid:clearFilter() end,
  mnuChart = chart,
  mnuProfile = profile,
  mnuRenameSheet = function() renameSheet() end,
  mnuSheetLeft = function() moveSheet(-1) end,
  mnuSheetRight = function() moveSheet(1) end,
  mnuNextSheet = function() grid:selectSheet(grid.book.active % #grid.book.sheets + 1) end,
  mnuPrevSheet = function() grid:selectSheet((grid.book.active - 2) % #grid.book.sheets + 1) end,
  mnuKeys = function() report.view("Keys", KEYS) end,
  mnuFunctions = functionHelp,
  mnuAbout = function()
    gui.msgbox("microsheets\n\nA spreadsheet in tlua. Workbooks are ." .. workbook.EXT ..
      " files: a zip of a CSV file for each sheet's values, beside a JSON file of its formulas.", "ok", "About microsheets")
  end,
}
for i, name in ipairs(themes.names()) do
  actions["mnuTheme" .. i] = function() setTheme(name) end
end

function frm.Menu1:onClick(name, caption, checked)
  local fn = actions[name]
  if fn then fn(caption, checked) end
  updateStatus()
end

---------------------------------------------------------------- context menus

function grid:onMenu()
  local v = grid:view()
  local value = grid.book:display(sheet(), v.r, v.c)
  local items = {
    { "Cu&t", function() grid:copy(true) end },
    { "&Copy", function() grid:copy() end },
    { "&Paste", function() grid:paste() end },
    { "Cl&ear", function() grid:clearSelection() end },
    "-",
    { "Insert Rows &Above", function() grid:insertRows(false) end },
    { "Insert Columns &Left", function() grid:insertCols(false) end },
    { "&Delete Rows", function() grid:deleteRows() end },
    { "Delete Col&umns", function() grid:deleteCols() end },
    "-",
    { "Sort &Ascending", function() grid:sort(false) end },
    { "Sort &Descending", function() grid:sort(true) end },
  }
  if value ~= "" then
    local label = #value > 24 and value:sub(1, 24) .. "…" or value
    items[#items + 1] = { "&Filter by “" .. label .. "”", function() grid:setFilter("=" .. value) end }
  end
  if v.filter then items[#items + 1] = { "&Show All Rows", function() grid:clearFilter() end } end
  items[#items + 1] = "-"
  items[#items + 1] = { "C&hart...", chart }
  gui.popup(items, frm)
  updateStatus()
end

function tabs:onPick(i)
  grid:selectSheet(i)
  showChecks()
  grid:focus()
end

function tabs:onAdd()
  newSheet()
  grid:focus()
end

function tabs:onRename(i)
  renameSheet(i)
end

function tabs:onMenu(i)
  local b = grid.book
  local items = { { "&New Sheet", newSheet } }
  if i then
    items[#items + 1] = { "&Rename...", function() renameSheet(i) end }
    items[#items + 1] = { "&Delete", function() deleteSheet(i) end, enabled = #b.sheets > 1 }
    items[#items + 1] = "-"
    items[#items + 1] = { "Move &Left", function() moveSheet(-1) end, enabled = i > 1 }
    items[#items + 1] = { "Move R&ight", function() moveSheet(1) end, enabled = i < #b.sheets }
  end
  gui.popup(items, frm)
end

---------------------------------------------------------------- the window

function frm:onClose()
  if not confirmDiscard() then return false end
end

function frm:onDrop(text, lines)
  local file = lines and lines[1]
  if not file or lfs.attributes(file, "mode") ~= "file" then return end
  if confirmDiscard() then openPath(file) end
end
grid.onDrop = function(_, text, lines) frm:fire("onDrop", text, lines) end

applySettings()

-- A workbook named on the command line is opened: tlua microsheets.ztl q1.zms
local start = arg and arg[1]
if start and start ~= "" and lfs.attributes(start, "mode") == "file" then
  openPath(start)
else
  setBook(book.new(), nil)
end
gui.after(0, function() grid:focus() end)

-- Exposed for the tests.
frm.openPath = openPath
frm.saveTo = saveTo
frm.goTo = goTo
frm.actions = actions
frm.settings = settings

return frm
