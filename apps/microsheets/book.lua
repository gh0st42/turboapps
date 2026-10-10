-- A workbook: sheets of cells, the values their formulas work out to, and
-- undo. What a cell holds is kept as it was typed (its raw text); values
-- are worked out from that.
--
--   local b = book.new()
--   local s = b.sheets[1]
--   b:set(s, 1, 1, "4"); b:set(s, 2, 1, "=A1*2")
--   b:value(s, 2, 1)       --> 8
--   b:undo()
--
-- Every change goes through a method here, which keeps it for undo, marks
-- the workbook changed and works the formulas out again.

local formula = require "formula"

local M = {}
local Book = {}
Book.__index = Book
local Sheet = {}
Sheet.__index = Sheet

M.DEFAULT_WIDTH = 96
M.MIN_WIDTH = 24
-- Cells' values and the like are kept in tables of rows of columns:
-- gopher-lua is slow with big numbers as keys, so r * 32768 + c will not do.
local function get2(t, r, c)
  local row = t[r]
  return row and row[c]
end

local function set2(t, r, c, v)
  local row = t[r]
  if not row then
    row = {}
    t[r] = row
  end
  row[c] = v
end

local function isFormula(raw) return raw and raw:sub(1, 1) == "=" and #raw > 1 end
M.isFormula = isFormula

---------------------------------------------------------------- sheets

local function newSheet(name)
  return setmetatable({ name = name, cells = {}, widths = {}, frozen = false, rows = 0, cols = 0 }, Sheet)
end

function Sheet:get(r, c)
  local row = self.cells[r]
  return row and row[c]
end

-- size is how many rows and columns the sheet uses.
function Sheet:size() return self.rows, self.cols end

function Sheet:width(c) return self.widths[c] or M.DEFAULT_WIDTH end

-- measure finds the rows and columns used again, after cells went.
function Sheet:measure()
  local rows, cols = 0, 0
  for r, row in pairs(self.cells) do
    local any = false
    for c in pairs(row) do
      any = true
      if c > cols then cols = c end
    end
    if any then
      if r > rows then rows = r end
    else
      self.cells[r] = nil
    end
  end
  self.rows, self.cols = rows, cols
end

-- put changes a cell, with no undo; the Book's methods call it.
function Sheet:put(r, c, raw)
  if raw == "" then raw = nil end
  local row = self.cells[r]
  if raw == nil then
    if row and row[c] then
      row[c] = nil
      if r == self.rows or c == self.cols then self.shrink = true end
    end
    return
  end
  if not row then
    row = {}
    self.cells[r] = row
  end
  row[c] = raw
  if r > self.rows then self.rows = r end
  if c > self.cols then self.cols = c end
end

-- each calls fn(r, c, raw) for every cell with something in it, in no order.
function Sheet:each(fn)
  for r, row in pairs(self.cells) do
    for c, raw in pairs(row) do fn(r, c, raw) end
  end
end

---------------------------------------------------------------- the book

-- new makes a workbook of one empty sheet.
function M.new()
  local b = setmetatable({ sheets = {}, active = 1, undos = {}, redos = {}, dirty = false, parsed = {} }, Book)
  b.sheets[1] = newSheet("Sheet1")
  b:recalc()
  return b
end

M.newSheet = newSheet

-- find gives the sheet of that name, without regard to case, and its index.
function Book:find(name)
  if not name then return nil end
  local low = name:lower()
  for i, s in ipairs(self.sheets) do
    if s.name:lower() == low then return s, i end
  end
end

function Book:index(sheet)
  for i, s in ipairs(self.sheets) do if s == sheet then return i end end
end

function Book:current() return self.sheets[self.active] end

-- freeName makes a sheet name no sheet has yet: Sheet2, Sheet3...
function Book:freeName(base)
  base = base or "Sheet"
  local n = #self.sheets + 1
  while self:find(base .. n) do n = n + 1 end
  return base .. n
end

-- validName says whether a name can be a sheet's, and why not.
function Book:validName(name, except)
  if name == nil or name:find("^%s*$") then return false, "A sheet needs a name." end
  if name:find("[%[%]%*%?/\\:]") then return false, "A sheet name cannot have [ ] * ? / \\ or : in it." end
  if #name > 31 then return false, "A sheet name can be 31 characters at most." end
  local other = self:find(name)
  if other and other ~= except then return false, "There is a sheet called " .. other.name .. " already." end
  return true
end

---------------------------------------------------------------- values

-- tree is a formula's parse, kept for each text it is read from.
function Book:tree(raw)
  local t = self.parsed[raw]
  if t == nil then
    local tree, err = formula.parse(raw:sub(2))
    t = tree or { k = "err", v = formula.errors.PARSE, why = err }
    self.parsed[raw] = t
  end
  return t
end

-- value is what a cell works out to: a number, a string, a boolean, an
-- error (formula.isError) or nil for an empty cell.
function Book:value(sheet, r, c)
  local row = sheet.cells[r]
  local raw = row and row[c]
  if raw == nil then return nil end
  local vals = self.vals[sheet]
  local v = get2(vals, r, c)
  if v ~= nil then return v end
  if isFormula(raw) then return formula.errors.CIRC end
  v = formula.literal(raw)
  set2(vals, r, c, v)
  return v
end

-- display is a cell's value as text, as the grid shows it.
function Book:display(sheet, r, c)
  return formula.text(self:value(sheet, r, c))
end

-- context is how a formula on sheet at r, c reads other cells.
function Book:context(sheet, r, c)
  local book = self
  return {
    row = r, col = c,
    value = function(name, rr, cc)
      local s = sheet
      if name then
        s = book:find(name)
        if not s then return formula.errors.REF end
      end
      return book:value(s, rr, cc)
    end,
    size = function(name)
      local s = sheet
      if name then s = book:find(name) end
      if not s then return nil end
      return s.rows, s.cols
    end,
  }
end

-- deps lists the formula cells a formula reads, as { sheet, r, c }.
function Book:deps(sheet, r, c)
  local list = {}
  for _, ref in ipairs(formula.refs(self:tree(sheet.cells[r][c]))) do
    local s = sheet
    if ref.sheet then s = self:find(ref.sheet) end
    if s then
      local r2, c2 = math.min(ref.r2, s.rows), math.min(ref.c2, s.cols)
      for rr = ref.r1, r2 do
        local row = s.cells[rr]
        if row then
          for cc = ref.c1, c2 do
            if isFormula(row[cc]) then list[#list + 1] = { s, rr, cc } end
          end
        end
      end
    end
  end
  return list
end

-- recalc works out every formula again, each after the formulas it reads,
-- so a long chain of them needs no deep recursion. A formula that reads
-- itself, through others or not, is #CIRC!.
function Book:recalc()
  self.vals = {}
  for _, s in ipairs(self.sheets) do
    self.vals[s] = {}
    if s.shrink then s:measure() s.shrink = nil end
  end
  local state = {}
  for _, s in ipairs(self.sheets) do state[s] = {} end
  for _, s in ipairs(self.sheets) do
    for r, row in pairs(s.cells) do
      for c, raw in pairs(row) do
        if isFormula(raw) and not get2(state[s], r, c) then
          local stack = { { s, r, c } }
          while #stack > 0 do
            local top = stack[#stack]
            local ts, tr, tc = top[1], top[2], top[3]
            if not top.deps then
              set2(state[ts], tr, tc, 1)
              top.deps = self:deps(ts, tr, tc)
              top.i = 0
            end
            top.i = top.i + 1
            local d = top.deps[top.i]
            if d then
              local st = get2(state[d[1]], d[2], d[3])
              if st == nil then
                stack[#stack + 1] = { d[1], d[2], d[3] }
              elseif st == 1 then
                top.cycle = true
              end
            else
              local v
              if top.cycle then
                v = formula.errors.CIRC
              else
                v = formula.evaluate(self:tree(ts.cells[tr][tc]), self:context(ts, tr, tc))
                if v == nil then v = 0 end
              end
              set2(self.vals[ts], tr, tc, v)
              set2(state[ts], tr, tc, 2)
              stack[#stack] = nil
            end
          end
        end
      end
    end
  end
  -- The parses of formulas no longer in any cell can go.
  local n = 0
  for _ in pairs(self.parsed) do n = n + 1 end
  if n > 20000 then self.parsed = {} end
end

---------------------------------------------------------------- changes and undo

local function copySheet(s)
  local cells = {}
  for r, row in pairs(s.cells) do
    local copy = {}
    for c, raw in pairs(row) do copy[c] = raw end
    cells[r] = copy
  end
  local widths = {}
  for c, w in pairs(s.widths) do widths[c] = w end
  return { sheet = s, name = s.name, cells = cells, widths = widths, frozen = s.frozen }
end

-- snapshot keeps the whole workbook, for a change too wide to keep cell
-- by cell.
function Book:snapshot()
  local snap = { active = self.active, sheets = {} }
  for i, s in ipairs(self.sheets) do snap.sheets[i] = copySheet(s) end
  return snap
end

function Book:restore(snap)
  self.sheets = {}
  for i, k in ipairs(snap.sheets) do
    local s = k.sheet
    local copy = copySheet(k) -- keep the snapshot as it is, to restore again
    s.name, s.cells, s.widths, s.frozen = k.name, copy.cells, copy.widths, k.frozen
    s:measure()
    self.sheets[i] = s
  end
  self.active = math.min(snap.active, #self.sheets)
end

-- change runs fn, which changes the workbook through self:put and the
-- like, as one step to undo. wide says fn changes more than cells (rows,
-- columns or sheets), so the whole workbook is kept instead. where is
-- kept with it for the grid to go back to.
function Book:change(label, fn, wide, where)
  local step = { label = label, cells = {}, where = where }
  if wide then step.before = self:snapshot() end
  self.step = step
  local ok, err = pcall(fn)
  self.step = nil
  if not ok then
    if step.before then self:restore(step.before) else self:revert(step) end
    self:recalc()
    error(err, 0)
  end
  if wide then step.after = self:snapshot() end
  if #step.cells > 0 or wide then
    self.undos[#self.undos + 1] = step
    if #self.undos > 500 then table.remove(self.undos, 1) end
    self.redos = {}
    self.dirty = true
  end
  self:recalc()
  return step
end

-- put changes a cell as part of a change, keeping what it held.
function Book:put(sheet, r, c, raw)
  if raw == "" then raw = nil end
  local old = sheet:get(r, c)
  if old == raw then return end
  local step = self.step
  if step and not step.before then
    step.cells[#step.cells + 1] = { sheet, r, c, old, raw }
  end
  sheet:put(r, c, raw)
end

function Book:revert(step)
  for i = #step.cells, 1, -1 do
    local x = step.cells[i]
    x[1]:put(x[2], x[3], x[4])
  end
end

function Book:canUndo() return #self.undos > 0 end
function Book:canRedo() return #self.redos > 0 end

-- undo takes back the last change and returns it (with its where).
function Book:undo()
  local step = table.remove(self.undos)
  if not step then return nil end
  if step.before then self:restore(step.before) else self:revert(step) end
  self.redos[#self.redos + 1] = step
  self.dirty = true
  self:recalc()
  return step
end

function Book:redo()
  local step = table.remove(self.redos)
  if not step then return nil end
  if step.after then
    self:restore(step.after)
  else
    for _, x in ipairs(step.cells) do x[1]:put(x[2], x[3], x[5]) end
  end
  self.undos[#self.undos + 1] = step
  self.dirty = true
  self:recalc()
  return step
end

---------------------------------------------------------------- editing

-- set puts what was typed in a cell.
function Book:set(sheet, r, c, raw)
  if sheet:get(r, c) == ((raw ~= "" and raw) or nil) then return end
  self:change("Typing", function() self:put(sheet, r, c, raw) end, false, { sheet = sheet, r = r, c = c })
end

-- setMany puts a list of { r, c, raw } in as one change.
function Book:setMany(sheet, list, label, where)
  self:change(label or "Change", function()
    for _, x in ipairs(list) do self:put(sheet, x[1], x[2], x[3]) end
  end, false, where)
end

-- clear empties a range.
function Book:clear(sheet, r1, c1, r2, c2)
  local list = {}
  r2, c2 = math.min(r2, sheet.rows), math.min(c2, sheet.cols)
  for r = r1, r2 do
    local row = sheet.cells[r]
    if row then
      for c = c1, c2 do
        if row[c] then list[#list + 1] = { r, c, nil } end
      end
    end
  end
  if #list > 0 then self:setMany(sheet, list, "Clear", { sheet = sheet, r = r1, c = c1 }) end
end

-- copy keeps a range's cells, to paste: rows of raw text, and where they
-- came from, so formulas can be moved to where they go.
function Book:copy(sheet, r1, c1, r2, c2)
  local block = { r = r1, c = c1, rows = {}, h = r2 - r1 + 1, w = c2 - c1 + 1 }
  for r = r1, r2 do
    local row = {}
    for c = c1, c2 do row[c - c1 + 1] = sheet:get(r, c) or "" end
    block.rows[r - r1 + 1] = row
  end
  return block
end

-- text writes a range as tab-separated values, as other programs paste it.
function Book:text(sheet, r1, c1, r2, c2)
  local lines = {}
  for r = r1, r2 do
    local fields = {}
    for c = c1, c2 do
      local s = self:display(sheet, r, c)
      fields[#fields + 1] = (s:gsub("[\t\r\n]", " "))
    end
    lines[#lines + 1] = table.concat(fields, "\t")
  end
  return table.concat(lines, "\n")
end

-- paste puts a block in at r, c. Formulas in it move by the distance
-- unless asIs is set (a cut moves cells, so their formulas stay). to, when
-- given ({ r2, c2 }), is a range to fill with copies of a smaller block.
function Book:paste(sheet, r, c, block, asIs, r2, c2)
  local h, w = block.h, block.w
  local tall, wide = h, w
  if r2 and c2 then
    local th, tw = r2 - r + 1, c2 - c + 1
    if th > h and th % h == 0 then tall = th end
    if tw > w and tw % w == 0 then wide = tw end
  end
  local list = {}
  for dr = 0, tall - 1 do
    for dc = 0, wide - 1 do
      local raw = block.rows[dr % h + 1][dc % w + 1]
      if isFormula(raw) and block.r and not asIs then
        raw = formula.shift(raw, r + dr - (block.r + dr % h), c + dc - (block.c + dc % w))
      end
      list[#list + 1] = { r + dr, c + dc, raw }
    end
  end
  self:setMany(sheet, list, "Paste", { sheet = sheet, r = r, c = c, r2 = r + tall - 1, c2 = c + wide - 1 })
  return r + tall - 1, c + wide - 1
end

-- fill copies a range's first row down it ("down"), or its first column
-- across it ("right"), moving formulas as copying does.
function Book:fill(sheet, r1, c1, r2, c2, way)
  local list = {}
  for r = r1, r2 do
    for c = c1, c2 do
      local fr, fc = r, c
      if way == "down" then fr = r1 else fc = c1 end
      if fr ~= r or fc ~= c then
        local raw = sheet:get(fr, fc)
        if isFormula(raw) then raw = formula.shift(raw, r - fr, c - fc) end
        list[#list + 1] = { r, c, raw }
      end
    end
  end
  self:setMany(sheet, list, way == "down" and "Fill Down" or "Fill Right", { sheet = sheet, r = r1, c = c1, r2 = r2, c2 = c2 })
end

-- fillFrom puts one entry in every cell of a range, moving a formula as
-- copying it from r1, c1 would.
function Book:fillWith(sheet, r1, c1, r2, c2, raw)
  local list = {}
  for r = r1, r2 do
    for c = c1, c2 do
      local x = raw
      if isFormula(raw) then x = formula.shift(raw, r - r1, c - c1) end
      list[#list + 1] = { r, c, x }
    end
  end
  self:setMany(sheet, list, "Typing", { sheet = sheet, r = r1, c = c1, r2 = r2, c2 = c2 })
end

-- rewriteAll puts every formula in the workbook through fn(raw, sheet).
function Book:rewriteAll(fn)
  for _, s in ipairs(self.sheets) do
    local changes = {}
    s:each(function(r, c, raw)
      if isFormula(raw) then
        local new = fn(raw, s)
        if new ~= raw then changes[#changes + 1] = { r, c, new } end
      end
    end)
    for _, x in ipairs(changes) do s:put(x[1], x[2], x[3]) end
  end
end

-- shiftCells moves the cells of a sheet along an axis: those at `at` and
-- beyond by count (negative takes cells out, from at on).
local function shiftCells(sheet, axis, at, count)
  local cells = {}
  for r, row in pairs(sheet.cells) do
    if axis == "row" then
      if r < at then cells[r] = row
      elseif count > 0 then cells[r + count] = row
      elseif r >= at - count then cells[r + count] = row end
    else
      local new = {}
      for c, raw in pairs(row) do
        if c < at then new[c] = raw
        elseif count > 0 then new[c + count] = raw
        elseif c >= at - count then new[c + count] = raw end
      end
      cells[r] = new
    end
  end
  sheet.cells = cells
  if axis == "col" then
    local widths = {}
    for c, w in pairs(sheet.widths) do
      if c < at then widths[c] = w
      elseif count > 0 then widths[c + count] = w
      elseif c >= at - count then widths[c + count] = w end
    end
    sheet.widths = widths
  end
  sheet:measure()
end

local function structural(self, sheet, axis, at, count, label)
  self:change(label, function()
    shiftCells(sheet, axis, at, count)
    self:rewriteAll(function(raw, s)
      return "=" .. formula.adjust(raw:sub(2), s.name, sheet.name, axis, at, count)
    end)
  end, true, { sheet = sheet })
end

function Book:insertRows(sheet, at, n) structural(self, sheet, "row", at, n or 1, "Insert Rows") end

-- insertBlock puts a block of whole rows in as new rows at `at`, as one
-- change: vim's p after yy.
function Book:insertBlock(sheet, at, block)
  self:change("Paste Rows", function()
    shiftCells(sheet, "row", at, block.h)
    self:rewriteAll(function(raw, s)
      return "=" .. formula.adjust(raw:sub(2), s.name, sheet.name, "row", at, block.h)
    end)
    for dr, row in ipairs(block.rows) do
      for dc, raw in ipairs(row) do
        if isFormula(raw) and block.r then raw = formula.shift(raw, at - block.r, 0) end
        self:put(sheet, at + dr - 1, dc, raw)
      end
    end
  end, true, { sheet = sheet, r = at, c = 1 })
end
function Book:deleteRows(sheet, at, n) structural(self, sheet, "row", at, -(n or 1), "Delete Rows") end
function Book:insertCols(sheet, at, n) structural(self, sheet, "col", at, n or 1, "Insert Columns") end
function Book:deleteCols(sheet, at, n) structural(self, sheet, "col", at, -(n or 1), "Delete Columns") end

-- sort orders rows r1..r2 of columns c1..c2 by the values in column by:
-- numbers, then text, then TRUE and FALSE, and empty cells last either
-- way. Formulas that move are moved as copying them would.
function Book:sort(sheet, r1, c1, r2, c2, by, descending)
  local order = {}
  for r = r1, r2 do order[#order + 1] = { r = r, v = self:value(sheet, r, by) } end
  table.sort(order, function(a, b)
    if a.v == nil or b.v == nil then
      if a.v == nil and b.v == nil then return a.r < b.r end
      return b.v == nil
    end
    local ea, eb = formula.isError(a.v), formula.isError(b.v)
    if ea or eb then
      if ea and eb then return a.r < b.r end
      return eb
    end
    local d = formula.compare(a.v, b.v)
    if d == 0 then return a.r < b.r end
    if descending then return d > 0 end
    return d < 0
  end)
  local list = {}
  for i, o in ipairs(order) do
    local to = r1 + i - 1
    for c = c1, c2 do
      local raw = sheet:get(o.r, c)
      if isFormula(raw) then raw = formula.shift(raw, to - o.r, 0) end
      list[#list + 1] = { to, c, raw }
    end
  end
  self:setMany(sheet, list, descending and "Sort Descending" or "Sort Ascending", { sheet = sheet, r = r1, c = by })
end

---------------------------------------------------------------- sheets

function Book:addSheet(name, at)
  name = name or self:freeName()
  at = at or #self.sheets + 1
  local s = newSheet(name)
  self:change("New Sheet", function()
    table.insert(self.sheets, at, s)
    self.active = at
  end, true)
  return s
end

function Book:removeSheet(i)
  if #self.sheets <= 1 then return false end
  self:change("Delete Sheet", function()
    table.remove(self.sheets, i)
    self.active = math.max(1, math.min(self.active, #self.sheets))
  end, true)
  return true
end

-- renameSheet renames a sheet and the references to it.
function Book:renameSheet(i, name)
  local s = self.sheets[i]
  if s.name == name then return true end
  local ok, why = self:validName(name, s)
  if not ok then return nil, why end
  local old = s.name
  self:change("Rename Sheet", function()
    self:rewriteAll(function(raw) return "=" .. formula.renameSheet(raw:sub(2), old, name) end)
    s.name = name
  end, true)
  return true
end

function Book:moveSheet(i, j)
  if j < 1 or j > #self.sheets or i == j then return end
  self:change("Move Sheet", function()
    local s = table.remove(self.sheets, i)
    table.insert(self.sheets, j, s)
    self.active = j
  end, true)
end

---------------------------------------------------------------- looking at data

-- stats sums up the numbers in a range: count of cells with something in
-- them, how many are numbers, and their sum, average, least and most.
function Book:stats(sheet, r1, c1, r2, c2)
  local st = { count = 0, numbers = 0, sum = 0 }
  r2, c2 = math.min(r2, sheet.rows), math.min(c2, sheet.cols)
  for r = r1, r2 do
    if sheet.cells[r] then
      for c = c1, c2 do
        local v = self:value(sheet, r, c)
        if v ~= nil then
          st.count = st.count + 1
          if type(v) == "number" then
            st.numbers = st.numbers + 1
            st.sum = st.sum + v
            if not st.min or v < st.min then st.min = v end
            if not st.max or v > st.max then st.max = v end
          end
        end
      end
    end
  end
  if st.numbers > 0 then st.average = st.sum / st.numbers end
  return st
end

-- profile describes each column: what kind of values it has, how many,
-- how many differ, and the numbers' sum, average, least and most. With
-- header set, row 1 names the columns and is left out.
function Book:profile(sheet, header)
  local out = {}
  local first = header and 2 or 1
  for c = 1, sheet.cols do
    local col = { col = c, name = formula.colName(c), filled = 0, empty = 0, unique = 0, numbers = 0, texts = 0, sum = 0 }
    if header then
      local h = self:display(sheet, 1, c)
      if h ~= "" then col.name = col.name .. " " .. h end
    end
    local seen = {}
    for r = first, sheet.rows do
      local v = self:value(sheet, r, c)
      if v == nil then
        col.empty = col.empty + 1
      else
        col.filled = col.filled + 1
        local t = formula.text(v)
        if not seen[t] then seen[t] = true col.unique = col.unique + 1 end
        if type(v) == "number" then
          col.numbers = col.numbers + 1
          col.sum = col.sum + v
          if not col.min or v < col.min then col.min = v end
          if not col.max or v > col.max then col.max = v end
        else
          col.texts = col.texts + 1
        end
      end
    end
    if col.numbers > 0 then col.average = col.sum / col.numbers end
    if col.filled == 0 then col.kind = "empty"
    elseif col.texts == 0 then col.kind = "number"
    elseif col.numbers == 0 then col.kind = "text"
    else col.kind = "mixed" end
    out[c] = col
  end
  return out
end

-- search finds the cells whose value or formula has text in it, without
-- regard to case, row by row.
function Book:search(sheet, text)
  local found = {}
  if text == "" then return found end
  local low = text:lower()
  sheet:each(function(r, c, raw)
    if raw:lower():find(low, 1, true) or self:display(sheet, r, c):lower():find(low, 1, true) then
      found[#found + 1] = { r = r, c = c }
    end
  end)
  table.sort(found, function(a, b) return a.r < b.r or (a.r == b.r and a.c < b.c) end)
  return found
end

-- matcher reads a filter: ">1000", "<=50.5" and "<>0" compare numbers,
-- "=Canada" is the same text (without regard to case) and anything else
-- is text the value has in it.
function M.matcher(expr)
  local op, rest = expr:match("^%s*([<>]=?)%s*(.-)%s*$")
  if expr:match("^%s*<>") then op, rest = "<>", expr:match("^%s*<>%s*(.-)%s*$") end
  if op then
    local n = tonumber(rest)
    if not n then return nil, "A comparison needs a number after " .. op end
    return function(v)
      if type(v) ~= "number" then return false end
      if op == "<" then return v < n end
      if op == ">" then return v > n end
      if op == "<=" then return v <= n end
      if op == ">=" then return v >= n end
      return v ~= n
    end
  end
  local exact = expr:match("^%s*=%s*(.-)%s*$")
  if exact then
    local low = exact:lower()
    local n = tonumber(exact)
    return function(v)
      if n and type(v) == "number" then return v == n end
      return formula.text(v):lower() == low
    end
  end
  local low = expr:lower()
  return function(v) return formula.text(v):lower():find(low, 1, true) ~= nil end
end

-- filter lists the rows whose cell in column col (or in any column, when
-- col is nil) passes the filter. A frozen first row always shows.
function Book:filter(sheet, expr, col)
  local test, err = M.matcher(expr)
  if not test then return nil, err end
  local rows = {}
  for r = 1, sheet.rows do
    local keep = r == 1 and sheet.frozen
    if not keep then
      if col then
        keep = test(self:value(sheet, r, col))
      elseif sheet.cells[r] then
        for c in pairs(sheet.cells[r]) do
          if test(self:value(sheet, r, c)) then keep = true break end
        end
      end
    end
    if keep then rows[#rows + 1] = r end
  end
  return rows
end

return M
