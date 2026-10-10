-- A control of this project's own: the spreadsheet grid, drawn on a
-- Canvas. A layout that uses a Grid finds it here, as controls.Grid, and
-- the designer shows it in its toolbox.
--
-- It shows a sheet of a workbook (book.lua) with its row and column
-- headers, the cursor and the selection, and edits a cell in place. The
-- keyboard works two ways: as a spreadsheet does, where typing replaces
-- the cell, or, with vim set, as vim and terminal spreadsheets do, where
-- letters are commands (h j k l, i to edit, dd, yy, p, u, / ...).
--
--   grid.book                  the workbook
--   grid:setBook(book)
--   grid:selection()           r1, c1, r2, c2 of what is selected
--   grid:moveTo(r, c [, r2, c2])
--   grid:mode()                "READY", "EDIT", "POINT" or "VISUAL"
--   grid:changed()             after the workbook was changed from outside
--
-- Events: onSelect when the cursor or the sheet changes, onChange when
-- the workbook does, onEdit(text) as the cell being edited changes,
-- onMenu(x, y) for a right click, onCommand(name) for what needs a dialog
-- ("search", "filter", "goto", "ex", "help", "fnhelp", "profile", "chart",
-- "theme").

local gui = require "gui"
local formula = require "formula"
local book = require "book"
local themes = require "themes"

local HEAD = 24     -- the column headers' height
local ROW = 22      -- a row's height
local BAR = 12      -- the scrollbars' width
local PAD = 4       -- space inside a cell
local MAX_ROWS, MAX_COLS = formula.MAX_ROWS, formula.MAX_COLS

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

-- fit cuts text to fit width w, with the measure given, at a character's start.
local function fit(measure, s, w)
  if measure(s) <= w then return s end
  local lo, hi = 0, #s
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if measure(s:sub(1, mid)) <= w then lo = mid else hi = mid - 1 end
  end
  local cut = s:sub(1, lo)
  return (cut:gsub("[\192-\255][\128-\191]*$", ""))
end

-- pointable says a formula being typed is at a place a reference can go.
local function pointable(text, caret)
  if text:sub(1, 1) ~= "=" then return false end
  local before = text:sub(1, caret):match("(%S)%s*$")
  return before ~= nil and ("=(,;+-*/^&<>:"):find(before, 1, true) ~= nil
end

gui.define {
  name = "Grid",
  events = { "onSelect", "onChange", "onEdit", "onMenu", "onCommand" },
  props = {
    vim = { type = "boolean", default = true },
    theme = { type = "string", default = "Light" },
    showFormulas = { type = "boolean", default = false },
  },
  build = function(parent, opts)
    local c = parent:Canvas { width = 600, height = 400 }
    c.book = book.new()
    c.views = {}         -- per sheet: cursor, anchor, scroll, filter
    c.entry = nil         -- the cell being edited
    c.pending = ""       -- vim keys so far: a count, "g", "d", "y", "c"
    c.search = nil       -- { text, list, i }
    c.clip = nil         -- what was copied, with its formulas
    c.fontSize = 13
    c.cache = {}         -- what drawing works out, for the mouse (assigning a field redraws)

    ---------------------------------------------------------------- the view

    function c:sheet() return self.book:current() end

    -- view is what the grid keeps for the sheet shown: the cursor (r, c),
    -- the anchor of a selection (ar, ac), the first row and column shown
    -- (top is an index into the rows shown; see rowAt), visual mode and
    -- the filter.
    function c:view()
      local s = self:sheet()
      local v = self.views[s]
      if not v then
        v = { r = 1, c = 1, top = 1, left = 1 }
        self.views[s] = v
      end
      return v
    end

    function c:setBook(b)
      self.book = b
      self.views = {}
      self.entry = nil
      self.search = nil
      self.pending = ""
      self:redraw()
      self:fire("onSelect")
    end

    -- With a filter, only some rows show; rows are counted by index into
    -- the list of those, and rowAt and indexOf go between the two.
    local function list(v) return v.filter and v.filter.rows end

    local function rowAt(v, i)
      local l = list(v)
      if l then return l[i] end
      return i
    end

    local function indexOf(v, r)
      local l = list(v)
      if not l then return r end
      local lo, hi = 1, #l
      while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if l[mid] < r then lo = mid + 1 else hi = mid end
      end
      return lo
    end

    local function lastIndex(v)
      local l = list(v)
      return l and math.max(1, #l) or MAX_ROWS
    end

    -- frozen says row 1 stays at the top.
    local function frozen(self)
      local s = self:sheet()
      return s.frozen and rowAt(self:view(), 1) == 1
    end

    local function rowHeaderWidth(self)
      local v = self:view()
      local last = rowAt(v, math.min(lastIndex(v), v.top + 60)) or 1
      return math.max(44, 16 + 8 * #tostring(last))
    end

    -- area is the part of the canvas that cells take.
    local function area(self)
      local W, H = self.width, self.height
      local x0 = rowHeaderWidth(self)
      local y0 = HEAD + (frozen(self) and ROW or 0)
      return x0, y0, W - BAR, H - BAR
    end

    -- shownRows is how many scrolling rows fit.
    local function shownRows(self)
      local _, y0, _, y1 = area(self)
      return math.max(1, math.floor((y1 - y0) / ROW))
    end

    function c:selection()
      local v = self:view()
      if not v.ar then return v.r, v.c, v.r, v.c end
      return math.min(v.r, v.ar), math.min(v.c, v.ac), math.max(v.r, v.ar), math.max(v.c, v.ac)
    end

    function c:hasRange()
      local r1, c1, r2, c2 = self:selection()
      return r1 ~= r2 or c1 ~= c2
    end

    function c:mode()
      if self.entry then return self.entry.point and "POINT" or "EDIT" end
      if self:view().visual then return "VISUAL" end
      return "READY"
    end

    -- reveal scrolls so the cursor shows.
    function c:reveal()
      local v = self:view()
      local s = self:sheet()
      local i = indexOf(v, v.r)
      local first = frozen(self) and 2 or 1
      local n = shownRows(self)
      if i >= first then
        if i < v.top then v.top = i end
        if i > v.top + n - 1 then v.top = i - n + 1 end
      end
      v.top = clamp(v.top, first, math.max(first, lastIndex(v)))
      local x0, _, x1 = area(self)
      if v.c < v.left then v.left = v.c end
      local w = 0
      for col = v.left, v.c do w = w + s:width(col) end
      while w > x1 - x0 and v.left < v.c do
        w = w - s:width(v.left)
        v.left = v.left + 1
      end
    end

    -- select moves the cursor to r, c, and with r2, c2 selects the range
    -- from there; with extend, the selection grows from where it was.
    function c:moveTo(r, col, r2, c2, extend)
      local v = self:view()
      r, col = clamp(r, 1, MAX_ROWS), clamp(col, 1, MAX_COLS)
      if r2 then
        v.ar, v.ac = r, col
        v.r, v.c = clamp(r2, 1, MAX_ROWS), clamp(c2, 1, MAX_COLS)
      else
        if extend or v.visual then
          if not v.ar then v.ar, v.ac = v.r, v.c end
        else
          v.ar, v.ac = nil, nil
        end
        v.r, v.c = r, col
      end
      if v.ar == v.r and v.ac == v.c and not v.visual then v.ar, v.ac = nil, nil end
      self:reveal()
      self:redraw()
      self:fire("onSelect")
    end

    -- move goes dr rows (counted among the rows shown) and dc columns.
    function c:move(dr, dc, extend)
      local v = self:view()
      local i = clamp(indexOf(v, v.r) + dr, 1, lastIndex(v))
      local r = rowAt(v, i) or v.r
      self:moveTo(r, v.c + dc, nil, nil, extend)
    end

    -- jump goes to the edge of the data the way Ctrl and an arrow do: to
    -- the last filled cell before an empty one, or the next filled one.
    function c:jump(dr, dc, extend)
      local s, v = self:sheet(), self:view()
      local r, col = v.r, v.c
      local function filled(rr, cc) return s:get(rr, cc) ~= nil end
      local maxR, maxC = math.max(s.rows, 1), math.max(s.cols, 1)
      local function step(rr, cc) return rr + dr, cc + dc end
      local function inside(rr, cc) return rr >= 1 and cc >= 1 and rr <= maxR and cc <= maxC end
      local nr, nc = step(r, col)
      if not inside(nr, nc) then
        if dr > 0 then r = math.max(r, maxR) elseif dr < 0 then r = 1 end
        if dc > 0 then col = math.max(col, maxC) elseif dc < 0 then col = 1 end
      elseif filled(r, col) and filled(nr, nc) then
        while inside(nr, nc) and filled(nr, nc) do r, col = nr, nc nr, nc = step(r, col) end
      else
        r, col = nr, nc
        while inside(r, col) and not filled(r, col) do
          local ar, ac = step(r, col)
          if not inside(ar, ac) then break end
          r, col = ar, ac
        end
      end
      if list(v) then r = rowAt(v, indexOf(v, r)) or v.r end
      self:moveTo(r, col, nil, nil, extend)
    end

    function c:page(dir, extend)
      local v = self:view()
      local n = shownRows(self)
      v.top = v.top + dir * n
      self:move(dir * n, 0, extend)
    end

    ---------------------------------------------------------------- changes

    -- changed is called after the workbook changes: the grid shows it
    -- again and says so.
    function c:changed()
      local v = self:view()
      if v.filter then
        local rows = self.book:filter(self:sheet(), v.filter.expr, v.filter.col)
        if rows then v.filter.rows = rows end
      end
      if self.search then self.search.list = self.book:search(self:sheet(), self.search.text) end
      self:reveal()
      self:redraw()
      self:fire("onChange")
      self:fire("onSelect")
    end

    -- run does a change to the workbook, and reports an error in it.
    local function run(self, fn)
      local ok, err = pcall(fn)
      if not ok then gui.msgbox(tostring(err), "ok", "microsheets") end
      self:changed()
    end

    -- goBack shows where an undone change was made.
    local function goBack(self, step)
      if not step then return end
      local w = step.where
      if w and w.sheet then
        local i = self.book:index(w.sheet)
        if i then self.book.active = i end
        if w.r then
          if w.r2 then self:moveTo(w.r, w.c, w.r2, w.c2) else self:moveTo(w.r, w.c) end
        end
      end
      self.book.active = math.min(self.book.active, #self.book.sheets)
    end

    function c:undo()
      if self.entry then self:cancel() return end
      local step = self.book:undo()
      goBack(self, step)
      self:changed()
      return step
    end

    function c:redo()
      local step = self.book:redo()
      goBack(self, step)
      self:changed()
      return step
    end

    function c:clearSelection()
      local r1, c1, r2, c2 = self:selection()
      run(self, function() self.book:clear(self:sheet(), r1, c1, r2, c2) end)
    end

    -- rowsOf is the rows the selection covers, or count rows from the cursor.
    local function rowsOf(self, count)
      local r1, _, r2 = self:selection()
      if r1 == r2 and count and count > 1 then r2 = r1 + count - 1 end
      return r1, r2 - r1 + 1
    end

    local function colsOf(self, count)
      local _, c1, _, c2 = self:selection()
      if c1 == c2 and count and count > 1 then c2 = c1 + count - 1 end
      return c1, c2 - c1 + 1
    end

    function c:insertRows(below, count)
      local at, n = rowsOf(self, count)
      if below then at = at + n end
      run(self, function() self.book:insertRows(self:sheet(), at, n) end)
      self:moveTo(at, self:view().c)
    end

    function c:deleteRows(count)
      local at, n = rowsOf(self, count)
      run(self, function() self.book:deleteRows(self:sheet(), at, n) end)
      self:moveTo(at, self:view().c)
    end

    function c:insertCols(right, count)
      local at, n = colsOf(self, count)
      if right then at = at + n end
      run(self, function() self.book:insertCols(self:sheet(), at, n) end)
      self:moveTo(self:view().r, at)
    end

    function c:deleteCols(count)
      local at, n = colsOf(self, count)
      run(self, function() self.book:deleteCols(self:sheet(), at, n) end)
      self:moveTo(self:view().r, at)
    end

    -- sort orders the selected rows by the cursor's column, or, with one
    -- cell selected, all the rows of the sheet below a frozen header row.
    function c:sort(descending)
      local s, v = self:sheet(), self:view()
      local r1, c1, r2, c2 = self:selection()
      if r1 == r2 then
        r1, r2, c1, c2 = s.frozen and 2 or 1, s.rows, 1, s.cols
      end
      if r2 <= r1 then return end
      run(self, function() self.book:sort(s, r1, c1, r2, c2, v.c, descending) end)
    end

    function c:fill(way)
      local r1, c1, r2, c2 = self:selection()
      if way == "down" and r1 == r2 and r1 > 1 then r1 = r1 - 1 end
      if way == "right" and c1 == c2 and c1 > 1 then c1 = c1 - 1 end
      run(self, function() self.book:fill(self:sheet(), r1, c1, r2, c2, way) end)
    end

    function c:widen(delta, count)
      local s = self:sheet()
      local _, c1, _, c2 = self:selection()
      for col = c1, c2 do
        s.widths[col] = clamp(s:width(col) + delta * (count or 1), book.MIN_WIDTH, 800)
      end
      self.book.dirty = true
      self:reveal()
      self:redraw()
      self:fire("onChange")
    end

    function c:toggleFreeze()
      local s = self:sheet()
      s.frozen = not s.frozen
      self.book.dirty = true
      self:changed()
    end

    ---------------------------------------------------------------- the clipboard

    -- copy keeps the selection, with its formulas, and puts its values on
    -- the clipboard as tab-separated text for other programs.
    function c:copy(cut)
      local s = self:sheet()
      local r1, c1, r2, c2 = self:selection()
      local text = self.book:text(s, r1, c1, r2, c2)
      self.clip = { block = self.book:copy(s, r1, c1, r2, c2), cut = cut, text = text, sheet = s,
        r1 = r1, c1 = c1, r2 = r2, c2 = c2 }
      gui.clipboard(text)
      self:redraw()
    end

    -- copyRows copies whole rows, as yy does.
    function c:copyRows(count)
      local s = self:sheet()
      local r1, n = rowsOf(self, count)
      local r2 = r1 + n - 1
      local c2 = math.max(1, s.cols)
      local text = self.book:text(s, r1, 1, r2, c2)
      self.clip = { block = self.book:copy(s, r1, 1, r2, c2), text = text, sheet = s, r1 = r1, c1 = 1, r2 = r2, c2 = c2, rows = true }
      gui.clipboard(text)
      self:redraw()
    end

    -- paste puts in what was copied here, if the clipboard still holds it,
    -- or else the clipboard's text, split at tabs and lines. Whole rows
    -- copied go in as new rows when where says "below" or "above" (vim's
    -- p and P).
    function c:paste(where)
      local s, v = self:sheet(), self:view()
      local text = gui.clipboard() or ""
      local clip = self.clip
      local r, col = self:selection()
      if clip and clip.rows and clip.text == text then
        col = 1
        if where == "below" or where == "above" then
          if where == "below" then r = r + 1 end
          run(self, function() self.book:insertBlock(s, r, clip.block) end)
          self:moveTo(r, v.c)
          return
        end
      end
      if clip and clip.text == text then
        local _, _, r2, c2 = self:selection()
        run(self, function()
          if clip.cut then
            -- A cut moves the cells: they leave where they were, and keep
            -- their formulas as they are.
            self.book:change("Move", function()
              for rr = clip.r1, clip.r2 do
                for cc = clip.c1, clip.c2 do self.book:put(clip.sheet, rr, cc, nil) end
              end
              for dr, row in ipairs(clip.block.rows) do
                for dc, raw in ipairs(row) do self.book:put(s, r + dr - 1, col + dc - 1, raw) end
              end
            end, false, { sheet = s, r = r, c = col })
            self.clip = nil
          else
            r2, c2 = self.book:paste(s, r, col, clip.block, false, r2, c2)
          end
        end)
        self:moveTo(r + clip.block.h - 1, col + clip.block.w - 1, r, col)
        return
      end
      if text == "" then return end
      text = text:gsub("\r\n", "\n"):gsub("\n$", "")
      local sep = text:find("\t") and "\t" or nil
      local rows = {}
      for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local fields = {}
        if sep then
          for f in (line .. sep):gmatch("([^\t]*)\t") do fields[#fields + 1] = f end
        else
          fields[1] = line
        end
        rows[#rows + 1] = fields
      end
      local w = 0
      for _, row in ipairs(rows) do w = math.max(w, #row) end
      local block = { rows = rows, h = #rows, w = w }
      for _, row in ipairs(rows) do for k = #row + 1, w do row[k] = "" end end
      run(self, function() self.book:paste(s, r, col, block, true) end)
      self:moveTo(r + block.h - 1, col + block.w - 1, r, col)
      v.visual = false
    end

    ---------------------------------------------------------------- search and filter

    function c:findText(text)
      local s, v = self:sheet(), self:view()
      self.search = { text = text, list = self.book:search(s, text), i = 0 }
      for i, hit in ipairs(self.search.list) do
        if hit.r > v.r or (hit.r == v.r and hit.c >= v.c) then self.search.i = i - 1 break end
      end
      return self:findNext(1)
    end

    -- findNext goes to the next match (dir 1) or the one before (-1), round
    -- again at the end, and returns which it is and how many there are.
    function c:findNext(dir)
      local sr = self.search
      if not sr or #sr.list == 0 then self:redraw() return 0, 0 end
      sr.i = (sr.i - 1 + dir) % #sr.list + 1
      local hit = sr.list[sr.i]
      local v = self:view()
      if v.filter then self:clearFilter() end
      self:moveTo(hit.r, hit.c)
      return sr.i, #sr.list
    end

    -- setFilter shows only the rows that pass expr in the cursor's column,
    -- or in any column with all set.
    function c:setFilter(expr, all)
      local v = self:view()
      local col = not all and v.c or nil
      local rows, err = self.book:filter(self:sheet(), expr, col)
      if not rows then return nil, err end
      v.filter = { expr = expr, col = col, rows = rows }
      v.top = 1
      local i = indexOf(v, v.r)
      self:moveTo(rowAt(v, i) or 1, v.c)
      return #rows
    end

    function c:clearFilter()
      local v = self:view()
      v.filter = nil
      self:reveal()
      self:redraw()
      self:fire("onSelect")
    end

    ---------------------------------------------------------------- sheets

    function c:selectSheet(i)
      if not self.book.sheets[i] then return end
      if self.entry then self:commit() end
      self.book.active = i
      self.search = nil
      self:reveal()
      self:redraw()
      self:fire("onSelect")
    end

    ---------------------------------------------------------------- editing a cell

    -- beginEdit edits the cursor's cell: with text, starting from it (typing
    -- over the cell), else from what the cell holds.
    function c:beginEdit(text)
      local s, v = self:sheet(), self:view()
      local raw = s:get(v.r, v.c) or ""
      local start = text or raw
      self.entry = { sheet = s, r = v.r, c = v.c, text = start, caret = #start, original = raw }
      self:reveal()
      self:redraw()
      self:fire("onEdit", start)
      self:fire("onSelect")
    end

    -- setEditText is the formula bar typing: the edit takes its text.
    function c:setEditText(text, caret)
      if not self.entry then self:beginEdit(text) end
      self.entry.text = text
      self.entry.caret = clamp(caret or #text, 0, #text)
      self.entry.point = nil
      self:redraw()
    end

    function c:cancel()
      if not self.entry then return end
      self.entry = nil
      self:redraw()
      self:fire("onEdit", nil)
      self:fire("onSelect")
    end

    -- commit keeps what was typed, and moves: "down", "up", "right",
    -- "left" or nowhere. With all set, the whole selection takes it.
    function c:commit(move, all)
      local e = self.entry
      if not e then return end
      self.entry = nil
      local text = e.text
      -- A formula missing its last parentheses gets them, as spreadsheets do.
      if book.isFormula(text) then
        local _, opens = text:gsub("%(", "")
        local _, closes = text:gsub("%)", "")
        if opens > closes then text = text .. (")"):rep(opens - closes) end
      end
      local r1, c1, r2, c2 = self:selection()
      if all and (r1 ~= r2 or c1 ~= c2) then
        run(self, function() self.book:fillWith(e.sheet, r1, c1, r2, c2, text) end)
      elseif text ~= e.original then
        run(self, function() self.book:set(e.sheet, e.r, e.c, text) end)
      end
      self:fire("onEdit", nil)
      if move == "down" then self:move(1, 0)
      elseif move == "up" then self:move(-1, 0)
      elseif move == "right" then self:move(0, 1)
      elseif move == "left" then self:move(0, -1)
      else self:redraw() self:fire("onSelect") end
    end

    local function editChanged(self)
      self:redraw()
      self:fire("onEdit", self.entry.text)
    end

    local function insertText(self, s)
      local e = self.entry
      e.text = e.text:sub(1, e.caret) .. s .. e.text:sub(e.caret + 1)
      e.caret = e.caret + #s
      e.point = nil
      editChanged(self)
    end

    -- typeText puts text in at the caret of the cell being edited.
    function c:typeText(text)
      if self.entry then insertText(self, text) end
    end

    -- pointTo puts a reference to r, c (to r2, c2 for a range) into the
    -- formula being typed, in place of the one put in by pointing before.
    function c:pointTo(r, col, r2, c2)
      local e = self.entry
      local ref = formula.refName(r, col)
      if r2 and (r2 ~= r or c2 ~= col) then
        ref = formula.refName(math.min(r, r2), math.min(col, c2)) .. ":" .. formula.refName(math.max(r, r2), math.max(col, c2))
      end
      local s = self:sheet()
      if s ~= e.sheet then ref = formula.sheetPrefix(s.name) .. ref end
      local p = e.point
      local start = p and p.start or e.caret
      local stop = p and p.stop or e.caret
      e.text = e.text:sub(1, start) .. ref .. e.text:sub(stop + 1)
      e.caret = start + #ref
      e.point = { start = start, stop = start + #ref, r = r, c = col, r2 = r2 or r, c2 = c2 or col }
      editChanged(self)
    end

    -- toggleAbsolute cycles the reference at the caret through A1, $A$1,
    -- A$1 and $A1, as F4 does.
    local function toggleAbsolute(self)
      local e = self.entry
      local text = e.text
      local i = 1
      while true do
        local s, f, ref = text:find("(%$?%a+%$?%d+)", i)
        if not s then return end
        if e.caret >= s - 1 and e.caret <= f then
          local r, col, ar, ac = formula.parseRef(ref)
          if not r then return end
          if not ar and not ac then ar, ac = true, true
          elseif ar and ac then ar, ac = true, false
          elseif ar then ar, ac = false, true
          else ar, ac = false, false end
          local new = (ac and "$" or "") .. formula.colName(col) .. (ar and "$" or "") .. r
          e.text = text:sub(1, s - 1) .. new .. text:sub(f + 1)
          e.caret = s - 1 + #new
          editChanged(self)
          return
        end
        i = f + 1
      end
    end

    local function prevChar(text, i)
      local j = i
      while j > 0 do
        local b = text:byte(j)
        j = j - 1
        if b < 128 or b >= 192 then break end
      end
      return j
    end

    local function nextChar(text, i)
      local j = i + 1
      while j < #text and text:byte(j + 1) >= 128 and text:byte(j + 1) < 192 do j = j + 1 end
      return math.min(j, #text)
    end

    local ARROWS = { Up = { -1, 0 }, Down = { 1, 0 }, Left = { 0, -1 }, Right = { 0, 1 } }

    local function editKey(self, key, text)
      local e = self.entry
      local base = key:gsub("^Shift%+", "")
      local shift = base ~= key
      -- Arrows point at cells while a formula wants a reference there.
      local arrow = ARROWS[base]
      if arrow and (e.point or pointable(e.text, e.caret)) and (not e.point or e.caret == e.point.stop) then
        local p = e.point
        local r, col = p and p.r2 or e.r, p and p.c2 or e.c
        local ar, ac = p and p.r or e.r, p and p.c or e.c
        r, col = clamp(r + arrow[1], 1, MAX_ROWS), clamp(col + arrow[2], 1, MAX_COLS)
        if not p and self:sheet() == e.sheet then r, col = clamp(e.r + arrow[1], 1, MAX_ROWS), clamp(e.c + arrow[2], 1, MAX_COLS) end
        if shift and p then self:pointTo(ar, ac, r, col) else self:pointTo(r, col) end
        return true
      end
      if key == "Escape" then self:cancel() return true end
      if key == "Enter" or key == "KP_Enter" then self:commit("down") return true end
      if key == "Shift+Enter" then self:commit("up") return true end
      if key == "Tab" then self:commit("right") return true end
      if key == "Shift+Tab" then self:commit("left") return true end
      if key == "Ctrl+Enter" or key == "Cmd+Enter" or key == "Alt+Enter" then self:commit(nil, true) return true end
      if key == "Up" then self:commit("up") return true end
      if key == "Down" then self:commit("down") return true end
      if key == "Left" then e.caret = prevChar(e.text, e.caret) e.point = nil editChanged(self) return true end
      if key == "Right" then e.caret = nextChar(e.text, e.caret) e.point = nil editChanged(self) return true end
      if key == "Home" or key == "Cmd+Left" then e.caret = 0 editChanged(self) return true end
      if key == "End" or key == "Cmd+Right" then e.caret = #e.text editChanged(self) return true end
      if key == "F4" then toggleAbsolute(self) return true end
      if key == "F1" then self:fire("onCommand", "fnhelp") return true end
      if key == "Backspace" then
        if e.caret > 0 then
          local j = prevChar(e.text, e.caret)
          e.text = e.text:sub(1, j) .. e.text:sub(e.caret + 1)
          e.caret = j
          e.point = nil
          editChanged(self)
        end
        return true
      end
      if key == "Delete" then
        if e.caret < #e.text then
          e.text = e.text:sub(1, e.caret) .. e.text:sub(nextChar(e.text, e.caret) + 1)
          e.point = nil
          editChanged(self)
        end
        return true
      end
      if key == "Cmd+v" or key == "Ctrl+v" then
        local clip = (gui.clipboard() or ""):match("^[^\r\n]*")
        insertText(self, clip)
        return true
      end
      if key == "Cmd+z" or key == "Ctrl+z" then
        e.text, e.caret = e.original, #e.original
        editChanged(self)
        return true
      end
      local typed = text and text ~= "" and text:byte(1) >= 32 and text:byte(1) ~= 127
      if typed and not key:find("Cmd%+") and not key:find("Ctrl%+") then
        insertText(self, text)
        return true
      end
      return not key:find("Cmd%+") -- keep keys from the menus while editing, but for Cmd's
    end

    ---------------------------------------------------------------- vim keys

    -- vimKey answers a key in vim's way; false lets the key go on.
    local function vimKey(self, key, text)
      local v = self:view()
      local digits, p = self.pending:match("^(%d*)(.*)$")
      local n = tonumber(digits) or 1
      local ch = text or ""
      if key:find("^Ctrl%+") or key:find("^Cmd%+") or key:find("^Alt%+") or ch == "" or ch:byte(1) < 32 then
        local ctrl = {
          ["Ctrl+d"] = function() self:page(1, v.visual) end,
          ["Ctrl+u"] = function() self:page(-1, v.visual) end,
          ["Ctrl+f"] = function() self:page(1, v.visual) end,
          ["Ctrl+b"] = function() self:page(-1, v.visual) end,
          ["Ctrl+r"] = function() self:redo() end,
          ["Ctrl+j"] = function() self:fill("down") end,
          ["Ctrl+l"] = function() self:fill("right") end,
          ["Ctrl+g"] = function() self:fire("onCommand", "goto") end,
        }
        if ctrl[key] then self.pending = "" ctrl[key]() return true end
        return false
      end
      if p == "" and ch:find("^%d$") and (ch ~= "0" or digits ~= "") then
        self.pending = digits .. ch
        return true
      end
      self.pending = ""
      if p == "g" then
        if ch == "g" then self:moveTo(rowAt(v, math.min(n, lastIndex(v))) or 1, v.c, nil, nil, v.visual)
        elseif ch == "t" then self:selectSheet(self.book.active % #self.book.sheets + 1)
        elseif ch == "T" then self:selectSheet((self.book.active - 2) % #self.book.sheets + 1) end
        return true
      end
      if p == "d" then
        if ch == "d" then self:deleteRows(n) elseif ch == "c" then self:deleteCols(n) end
        return true
      end
      if p == "y" then
        if ch == "y" then self:copyRows(n) elseif ch == "c" then self:copy() end
        return true
      end
      if p == "c" then
        if ch == "c" then self:beginEdit("") end
        return true
      end
      local ext = v.visual
      local keys = {
        h = function() self:move(0, -n, ext) end,
        l = function() self:move(0, n, ext) end,
        j = function() self:move(n, 0, ext) end,
        k = function() self:move(-n, 0, ext) end,
        ["0"] = function() self:moveTo(v.r, 1, nil, nil, ext) end,
        ["^"] = function() self:moveTo(v.r, 1, nil, nil, ext) end,
        ["$"] = function() self:moveTo(v.r, math.max(1, self:sheet().cols), nil, nil, ext) end,
        G = function()
          if n > 1 then self:moveTo(n, v.c, nil, nil, ext) return end
          local last = list(v) and rowAt(v, lastIndex(v)) or math.max(1, self:sheet().rows)
          self:moveTo(last, v.c, nil, nil, ext)
        end,
        w = function() self:jump(0, 1, ext) end,
        b = function() self:jump(0, -1, ext) end,
        ["}"] = function() self:jump(1, 0, ext) end,
        ["{"] = function() self:jump(-1, 0, ext) end,
        g = function() self.pending = digits .. "g" end,
        d = function()
          if v.visual then v.visual = false self:clearSelection() else self.pending = digits .. "d" end
        end,
        y = function()
          if v.visual then self:copy() v.visual = false self:moveTo(v.r, v.c) else self.pending = digits .. "y" end
        end,
        c = function()
          if v.visual then self:clearSelection() v.visual = false self:beginEdit("") else self.pending = digits .. "c" end
        end,
        Y = function() self:copyRows(n) end,
        i = function() self:beginEdit() end,
        a = function() self:beginEdit() end,
        A = function() self:beginEdit() end,
        I = function() self:beginEdit() self.entry.caret = 0 end,
        ["="] = function() self:beginEdit("=") end,
        x = function()
          if v.visual then v.visual = false end
          self:copy(true)
          self:clearSelection()
        end,
        p = function() self:paste("below") end,
        P = function() self:paste("above") end,
        o = function() self:insertRows(true, n) end,
        O = function() self:insertCols(true, n) end,
        u = function() self:undo() end,
        v = function()
          v.visual = not v.visual
          if v.visual then v.ar, v.ac = v.r, v.c else v.ar, v.ac = nil, nil end
          self:redraw()
          self:fire("onSelect")
        end,
        ["/"] = function() self:fire("onCommand", "search") end,
        n = function() self:findNext(1) self:fire("onSelect") end,
        N = function() self:findNext(-1) self:fire("onSelect") end,
        f = function() self:fire("onCommand", "filter") end,
        F = function() self:clearFilter() end,
        s = function() self:sort(false) end,
        S = function() self:sort(true) end,
        [">"] = function() self:widen(16, n) end,
        ["<"] = function() self:widen(-16, n) end,
        W = function() self:fire("onCommand", "profile") end,
        ["?"] = function() self:fire("onCommand", "help") end,
        t = function() self:fire("onCommand", "theme") end,
        [":"] = function() self:fire("onCommand", "ex") end,
      }
      keys.V = keys.v
      local fn = keys[ch]
      if fn then fn() return true end
      return false
    end

    ---------------------------------------------------------------- keys

    function c:onKey(key, text)
      if self.entry then return editKey(self, key, text) end
      local v = self:view()
      local shift = key:find("Shift%+") ~= nil
      local base = key:gsub("Shift%+", "")
      local moves = {
        Up = function() self:move(-1, 0, shift) end,
        Down = function() self:move(1, 0, shift) end,
        Left = function() self:move(0, -1, shift) end,
        Right = function() self:move(0, 1, shift) end,
        ["Ctrl+Up"] = function() self:jump(-1, 0, shift) end,
        ["Ctrl+Down"] = function() self:jump(1, 0, shift) end,
        ["Ctrl+Left"] = function() self:jump(0, -1, shift) end,
        ["Ctrl+Right"] = function() self:jump(0, 1, shift) end,
        ["Cmd+Up"] = function() self:jump(-1, 0, shift) end,
        ["Cmd+Down"] = function() self:jump(1, 0, shift) end,
        ["Cmd+Left"] = function() self:jump(0, -1, shift) end,
        ["Cmd+Right"] = function() self:jump(0, 1, shift) end,
        Home = function() self:moveTo(v.r, 1, nil, nil, shift) end,
        End = function() self:moveTo(v.r, math.max(1, self:sheet().cols), nil, nil, shift) end,
        ["Ctrl+Home"] = function() self:moveTo(rowAt(v, 1) or 1, 1, nil, nil, shift) end,
        ["Ctrl+End"] = function()
          local s = self:sheet()
          self:moveTo(math.max(1, s.rows), math.max(1, s.cols), nil, nil, shift)
        end,
        PageUp = function() self:page(-1, shift) end,
        PageDown = function() self:page(1, shift) end,
        ["Ctrl+PageDown"] = function() self:selectSheet(self.book.active % #self.book.sheets + 1) end,
        ["Ctrl+PageUp"] = function() self:selectSheet((self.book.active - 2) % #self.book.sheets + 1) end,
      }
      if moves[base] then
        self.pending = ""
        moves[base]()
        return true
      end
      if key == "Tab" then self:move(0, 1) return true end
      if key == "Shift+Tab" then self:move(0, -1) return true end
      if key == "F2" then self:beginEdit() return true end
      if key == "Delete" or key == "Backspace" then self:clearSelection() return true end
      if key == "Escape" then
        self.pending = ""
        if v.visual or v.ar then
          v.visual = false
          v.ar, v.ac = nil, nil
          self:redraw()
          self:fire("onSelect")
        elseif self.search then
          self.search = nil
          self:redraw()
        elseif v.filter then
          self:clearFilter()
        else
          self.clip = nil
          self:redraw()
        end
        return true
      end
      if self.vim then
        if key == "Enter" then self:beginEdit() return true end
        return vimKey(self, key, text)
      end
      if key == "Enter" then self:move(1, 0) return true end
      if key == "Shift+Enter" then self:move(-1, 0) return true end
      local typed = text and text ~= "" and text:byte(1) >= 32 and text:byte(1) ~= 127
      if typed and not key:find("Cmd%+") and not key:find("Ctrl%+") and not key:find("Alt%+") then
        self:beginEdit(text)
        return true
      end
      return false
    end

    ---------------------------------------------------------------- geometry

    -- columns lists the columns shown from v.left: { c, x, w } each.
    local function columns(self)
      local s, v = self:sheet(), self:view()
      local x0, _, x1 = area(self)
      local out, x, col = {}, x0, v.left
      while x < x1 and col <= MAX_COLS do
        local w = s:width(col)
        out[#out + 1] = { c = col, x = x, w = w }
        x = x + w
        col = col + 1
      end
      return out
    end

    -- rows lists the rows shown: { r, y } each, the frozen one first.
    local function rows(self)
      local v = self:view()
      local _, y0, _, y1 = area(self)
      local out = {}
      if frozen(self) then out[1] = { r = 1, y = HEAD, frozen = true } end
      local y, i = y0, math.max(v.top, frozen(self) and 2 or 1)
      local last = lastIndex(v)
      while y < y1 and i <= last do
        out[#out + 1] = { r = rowAt(v, i), y = y }
        y = y + ROW
        i = i + 1
      end
      return out
    end

    -- cellAt is the cell at x, y; x and y beyond the cells give the edge's.
    function c:cellAt(x, y)
      local cols, rws = columns(self), rows(self)
      local col, r
      for _, k in ipairs(cols) do if x >= k.x and x < k.x + k.w then col = k.c end end
      if not col then
        if x < (cols[1] and cols[1].x or 0) then col = math.max(1, self:view().left - 1) else col = cols[#cols] and cols[#cols].c or 1 end
      end
      for _, k in ipairs(rws) do if y >= k.y and y < k.y + ROW then r = k.r end end
      if not r then
        local v = self:view()
        if y < HEAD then r = rowAt(v, math.max(1, v.top - 1)) or 1
        else r = rws[#rws] and rws[#rws].r or 1 end
      end
      return r, col
    end

    ---------------------------------------------------------------- drawing

    local function selected(self, r, col)
      local r1, c1, r2, c2 = self:selection()
      return r >= r1 and r <= r2 and col >= c1 and col <= c2
    end

    local function matchSet(self)
      local set = {}
      if self.search then
        for _, hit in ipairs(self.search.list) do
          set[hit.r] = set[hit.r] or {}
          set[hit.r][hit.c] = true
        end
      end
      return set
    end

    function c:onDraw(g)
      local th = themes.get(self.theme)
      local s, v = self:sheet(), self:view()
      local W, H = g:size()
      local bk = self.book
      local x0, y0, x1, y1 = area(self)
      local cols, rws = columns(self), rows(self)
      local matches = matchSet(self)
      local r1, c1, r2, c2 = self:selection()
      local size = self.fontSize
      g:font("sans", size)
      local function measure(t) return (g:measure(t)) end

      g:color(th.bg)
      g:fill(0, 0, W, H)

      -- Cell backgrounds: the frozen row, the selection and search matches.
      for _, rw in ipairs(rws) do
        if rw.frozen then
          g:color(th.frozen)
          g:fill(x0, rw.y, x1 - x0, ROW)
        end
        for _, k in ipairs(cols) do
          local sel = selected(self, rw.r, k.c) and (r1 ~= r2 or c1 ~= c2)
          if (matches[rw.r] and matches[rw.r][k.c]) then
            g:color(th.match)
            g:fill(k.x, rw.y, k.w, ROW)
          elseif sel then
            g:color(th.selection)
            g:fill(k.x, rw.y, k.w, ROW)
          end
        end
      end

      -- Grid lines.
      g:color(th.grid)
      for _, k in ipairs(cols) do g:line(k.x + k.w - 1, HEAD, k.x + k.w - 1, y1) end
      for _, rw in ipairs(rws) do g:line(x0, rw.y + ROW - 1, x1, rw.y + ROW - 1) end
      if frozen(self) then
        g:color(th.line)
        g:fill(x0, y0 - 2, x1 - x0, 2)
      end

      -- Cell text. Text runs on into empty cells to its right.
      for _, rw in ipairs(rws) do
        local r = rw.r
        local skip = 0
        for ci, k in ipairs(cols) do
          if k.c > skip then
            local raw = s:get(r, k.c)
            if raw then
              local val = bk:value(s, r, k.c)
              local isF = book.isFormula(raw)
              local shown
              if self.showFormulas and isF then shown = raw else shown = formula.text(val) end
              local color = th.text
              local align = "left"
              if formula.isError(val) then color, align = th.error, "center"
              elseif isF then color = th.formula
              elseif type(val) == "number" then color = th.number end
              if not (self.showFormulas and isF) then
                if type(val) == "number" then align = "right"
                elseif type(val) == "boolean" then align = "center" end
              end
              local w = k.w - 2 * PAD
              if type(val) == "number" and not (self.showFormulas and isF) then
                if measure(shown) > w then
                  local digits = 9
                  while digits > 1 and measure(shown) > w do
                    shown = formula.formatNumber(val, digits)
                    digits = digits - 1
                  end
                  if measure(shown) > w then shown = ("#"):rep(math.max(1, math.floor(w / math.max(1, measure("#"))))) end
                end
              elseif align == "left" and measure(shown) > w then
                -- Run on over empty cells.
                local j = ci + 1
                local span = k.w
                while cols[j] and s:get(r, cols[j].c) == nil and measure(shown) > span - 2 * PAD do
                  local nk = cols[j]
                  if not (selected(self, r, nk.c) and (r1 ~= r2 or c1 ~= c2)) and not (matches[r] and matches[r][nk.c]) then
                    g:color(rw.frozen and th.frozen or th.bg)
                    g:fill(nk.x - 1, rw.y, nk.w, ROW - 1)
                  end
                  span = span + nk.w
                  skip = nk.c
                  j = j + 1
                end
                w = span - 2 * PAD
              end
              shown = fit(measure, (shown:gsub("[\r\n\t]", " ")), w)
              g:color(color)
              if rw.frozen then g:font("sans", size, "bold") end
              g:text(shown, k.x + PAD, rw.y, w, ROW, align)
              if rw.frozen then g:font("sans", size) end
            end
          end
        end
      end

      -- The copied range, outlined.
      local clip = self.clip
      if clip and clip.sheet == s then
        for _, k in ipairs(cols) do
          for _, rw in ipairs(rws) do
            if rw.r >= clip.r1 and rw.r <= clip.r2 and k.c >= clip.c1 and k.c <= clip.c2 then
              g:color(th.cursor)
              if rw.r == clip.r1 then for x = k.x, k.x + k.w - 1, 6 do g:line(x, rw.y, math.min(x + 3, k.x + k.w), rw.y) end end
              if rw.r == clip.r2 then for x = k.x, k.x + k.w - 1, 6 do g:line(x, rw.y + ROW - 1, math.min(x + 3, k.x + k.w), rw.y + ROW - 1) end end
              if k.c == clip.c1 then for y = rw.y, rw.y + ROW - 1, 6 do g:line(k.x, y, k.x, math.min(y + 3, rw.y + ROW)) end end
              if k.c == clip.c2 then for y = rw.y, rw.y + ROW - 1, 6 do g:line(k.x + k.w - 1, y, k.x + k.w - 1, math.min(y + 3, rw.y + ROW)) end end
            end
          end
        end
      end

      -- The selection's outline and the cursor.
      local function box(ra, ca, rb, cb, width, color)
        local xa, xb, ya, yb
        for _, k in ipairs(cols) do
          if k.c >= ca and k.c <= cb then
            xa = xa or k.x
            xb = k.x + k.w
          end
        end
        for _, rw in ipairs(rws) do
          if rw.r >= ra and rw.r <= rb then
            ya = ya and math.min(ya, rw.y) or rw.y
            yb = yb and math.max(yb, rw.y + ROW) or rw.y + ROW
          end
        end
        if xa and ya then
          g:color(color)
          for d = 0, width - 1 do g:rect(xa - 1 + d, ya - 1 + d, xb - xa + 1 - 2 * d, yb - ya + 1 - 2 * d) end
        end
      end
      if r1 ~= r2 or c1 ~= c2 then box(r1, c1, r2, c2, 1, th.cursor) end
      box(v.r, v.c, v.r, v.c, 2, th.cursor)

      -- What a formula being typed points at.
      local e = self.entry
      if e and e.point and s == self:sheet() then
        local p = e.point
        box(math.min(p.r, p.r2), math.min(p.c, p.c2), math.max(p.r, p.r2), math.max(p.c, p.c2), 2, th.formula)
      end

      -- Column headers.
      g:color(th.header)
      g:fill(0, 0, W, HEAD)
      g:fill(0, 0, x0, H)
      g:font("sans", size - 1)
      for _, k in ipairs(cols) do
        local on = k.c >= c1 and k.c <= c2
        if on then
          g:color(th.headerOn)
          g:fill(k.x, 0, k.w, HEAD)
        end
        g:color(on and th.headerOnText or th.headerText)
        g:text(formula.colName(k.c), k.x, 0, k.w, HEAD, "center")
        g:color(th.line)
        g:line(k.x + k.w - 1, 4, k.x + k.w - 1, HEAD - 4)
      end
      for _, rw in ipairs(rws) do
        local on = rw.r >= r1 and rw.r <= r2
        if on then
          g:color(th.headerOn)
          g:fill(0, rw.y, x0, ROW)
        end
        g:color(on and th.headerOnText or th.headerText)
        g:text(tostring(rw.r), 0, rw.y, x0 - 8, ROW, "right")
      end
      -- A filter shows in the corner.
      g:color(v.filter and th.cursor or th.headerText)
      g:text(v.filter and "▾" or "", 0, 0, x0, HEAD, "center")
      g:color(th.line)
      g:line(0, HEAD - 1, W, HEAD - 1)
      g:line(x0 - 1, 0, x0 - 1, H)

      -- The cell being edited, over the grid.
      if e and e.sheet == s then
        local ex, ey, ew
        for _, k in ipairs(cols) do if k.c == e.c then ex, ew = k.x, k.w end end
        for _, rw in ipairs(rws) do if rw.r == e.r then ey = rw.y end end
        if ex and ey then
          g:font("sans", size)
          local tw = measure(e.text) + 2 * PAD + 4
          ew = math.min(math.max(ew, tw), x1 - ex)
          g:color(th.edit)
          g:fill(ex, ey, ew, ROW)
          g:color(th.cursor)
          g:rect(ex - 1, ey - 1, ew + 1, ROW + 1)
          g:rect(ex - 2, ey - 2, ew + 3, ROW + 3)
          -- Long text scrolls so the caret shows.
          local before = measure(e.text:sub(1, e.caret))
          local shift = math.max(0, before - (ew - 2 * PAD - 2))
          g:color(e.text:sub(1, 1) == "=" and th.formula or th.text)
          local shown = e.text
          if shift > 0 then
            local cut = 0
            while cut < #shown and measure(shown:sub(1, cut)) < shift do cut = cut + 1 end
            shown = shown:sub(cut + 1)
            before = measure(e.text:sub(cut + 1, e.caret))
          end
          g:text(fit(measure, shown, ew - 2 * PAD), ex + PAD, ey, ew - 2 * PAD, ROW, "left")
          g:color(th.text)
          g:fill(ex + PAD + before, ey + 4, 1, ROW - 8)
        end
      end

      -- Scrollbars.
      local used = math.max(s.rows, v.r) + shownRows(self)
      local total = list(v) and math.max(1, #list(v)) or used
      g:color(th.header)
      g:fill(W - BAR, 0, BAR, H)
      g:fill(0, H - BAR, W, BAR)
      g:color(th.line)
      local th1 = math.max(20, math.floor((H - BAR - HEAD) * math.min(1, shownRows(self) / total)))
      local ty = HEAD + math.floor((H - BAR - HEAD - th1) * clamp((v.top - 1) / math.max(1, total - shownRows(self)), 0, 1))
      g:fill(W - BAR + 2, ty, BAR - 4, th1)
      local usedC = math.max(s.cols, v.c) + #cols
      local tw1 = math.max(20, math.floor((W - BAR - x0) * math.min(1, #cols / usedC)))
      local tx = x0 + math.floor((W - BAR - x0 - tw1) * clamp((v.left - 1) / math.max(1, usedC - #cols), 0, 1))
      g:fill(tx, H - BAR + 2, tw1, BAR - 4)
      self.cache.totals = { rows = total, cols = usedC }
    end

    ---------------------------------------------------------------- the mouse

    -- borderAt finds the column whose right edge is at x, in the header.
    local function borderAt(self, x)
      for _, k in ipairs(columns(self)) do
        if math.abs(x - (k.x + k.w)) <= 3 then return k end
      end
    end

    local function scrollTo(self, x, y)
      local v = self:view()
      local t = self.cache.totals or { rows = 100, cols = 26 }
      if self.dragging == "vbar" then
        local f = clamp((y - HEAD) / math.max(1, self.height - BAR - HEAD), 0, 1)
        v.top = math.max(frozen(self) and 2 or 1, math.floor(f * t.rows) + 1)
      else
        local x0 = rowHeaderWidth(self)
        local f = clamp((x - x0) / math.max(1, self.width - BAR - x0), 0, 1)
        v.left = math.max(1, math.floor(f * t.cols) + 1)
      end
      self:redraw()
    end

    function c:onMouseDown(x, y, button, double, mods)
      mods = mods or ""
      local v = self:view()
      local W, H = self.width, self.height
      self:focus()
      self.pending = ""
      if x >= W - BAR then self.dragging = "vbar" scrollTo(self, x, y) return end
      if y >= H - BAR then self.dragging = "hbar" scrollTo(self, x, y) return end
      local x0 = rowHeaderWidth(self)
      local shift = mods:find("Shift") ~= nil
      local s = self:sheet()
      if y < HEAD then
        local k = x >= x0 and borderAt(self, x)
        if k then
          if double then
            s.widths[k.c] = nil
            self.book.dirty = true
            self:redraw()
          else
            self.dragging = "width"
            self.resizing = { c = k.c, x = x, w = k.w }
          end
          return
        end
        if self.entry then self:commit() end
        if x < x0 then
          self:moveTo(math.max(1, s.rows), math.max(1, s.cols), 1, 1)
          return
        end
        local _, col = self:cellAt(x, HEAD)
        local from = shift and (v.ac or v.c) or col
        self:moveTo(math.max(1, s.rows), from, 1, col)
        self.dragging = "cols"
        self.dragFrom = from
        return
      end
      local r, col = self:cellAt(x, y)
      if x < x0 then
        if self.entry then self:commit() end
        local from = shift and (v.ar or v.r) or r
        self:moveTo(from, math.max(1, s.cols), r, 1)
        self.dragging = "rows"
        self.dragFrom = from
        return
      end
      local e = self.entry
      if e then
        if button == 1 and (e.point or pointable(e.text, e.caret)) then
          if shift and e.point then self:pointTo(e.point.r, e.point.c, r, col) else self:pointTo(r, col) end
          self.dragging = "point"
          return
        end
        if r == e.r and col == e.c and self:sheet() == e.sheet then return end
        self:commit()
      end
      if button == 3 then
        if not selected(self, r, col) then self:moveTo(r, col) end
        self:fire("onMenu", x, y)
        return
      end
      if double then
        self:moveTo(r, col)
        self:beginEdit()
        return
      end
      self:moveTo(r, col, nil, nil, shift)
      self.dragging = "cells"
    end

    function c:onMouseDrag(x, y)
      local d = self.dragging
      if not d then return end
      if d == "vbar" or d == "hbar" then scrollTo(self, x, y) return end
      if d == "width" then
        local rs = self.resizing
        local s = self:sheet()
        s.widths[rs.c] = clamp(rs.w + x - rs.x, book.MIN_WIDTH, 800)
        self.book.dirty = true
        self:redraw()
        return
      end
      local v = self:view()
      -- Dragging past an edge scrolls.
      if y > self.height - BAR then v.top = math.min(v.top + 1, lastIndex(v)) end
      if y < HEAD + (frozen(self) and ROW or 0) and d ~= "cols" then v.top = math.max(frozen(self) and 2 or 1, v.top - 1) end
      if x > self.width - BAR then v.left = v.left + 1 end
      if x < rowHeaderWidth(self) and d ~= "rows" and v.left > 1 then v.left = v.left - 1 end
      local r, col = self:cellAt(x, math.max(y, HEAD))
      local s = self:sheet()
      if d == "point" then
        local p = self.entry and self.entry.point
        if p then self:pointTo(p.r, p.c, r, col) end
      elseif d == "cols" then
        self:moveTo(math.max(1, s.rows), self.dragFrom, 1, col)
      elseif d == "rows" then
        self:moveTo(self.dragFrom, math.max(1, s.cols), r, 1)
      else
        if not v.ar then v.ar, v.ac = v.r, v.c end
        v.r, v.c = r, col
        if v.ar == v.r and v.ac == v.c then v.ar, v.ac = nil, nil end
        self:redraw()
        self:fire("onSelect")
      end
    end

    function c:onMouseUp()
      if self.dragging == "width" then self:fire("onChange") end
      self.dragging = nil
    end

    function c:onMouseWheel(dx, dy)
      local v = self:view()
      v.top = clamp(v.top + dy * 3, frozen(self) and 2 or 1, math.max(1, lastIndex(v)))
      v.left = clamp(v.left + dx, 1, MAX_COLS)
      self:redraw()
    end

    return c
  end,
}
