-- A control of this project's own: a list of files, drawn on a Canvas, with
-- a header of columns, an icon on each row, and a scrollbar. A form's
-- layout that uses a FileList finds it here, as controls.FileList, and the
-- designer shows it in its toolbox.
--
-- It is drawn rather than made of a Table so that the keyboard is all its
-- own: the arrows, Page Up and Down, Home and End move the selection and
-- keep it in sight, Enter opens, and typing the start of a name goes to it.
--
--   list:setRows(rows)   rows of { name =, cells = { ... }, icon = "dir"|"app"|"file" }
--   list:pick(i)         selects row i and scrolls to it
--   list:selectedRow()   the row with the focus (the one last picked), or nil
--   list:selectedRows()  every row selected, in order; the focused one when only one is
--   list:selectNames(names)  selects the rows with these names
--   list.current         the row with the focus, 0 for none
--
-- Several rows can be selected: Shift and a click or the arrows extends the
-- selection from where it began, Cmd (Ctrl) and a click adds a row or takes
-- it out, and Cmd (Ctrl) A takes them all.
--
-- Events: onChange(i) when the selection moves, onOpen(i) on a double
-- click or Enter, onSort(column) on a click on a column's title, onMenu(i)
-- for a context menu (a right click, which selects the row under it, a
-- Ctrl-click on a Mac, or Shift+F10; i is 0 off the rows), and
-- onCommand(key, text) for keys the list has no use for, which returns
-- true when it used them.

local gui = require "gui"

local ROW, HEAD, BAR = 20, 22, 12

local function clamp(v, lo, hi)
  if hi < lo then return lo end
  return math.max(lo, math.min(hi, v))
end

-- fit shortens text with an ellipsis until it is no wider than w.
local function fit(g, text, w)
  if g:measure(text) <= w then return text end
  local lo, hi = 0, #text
  while lo < hi do
    local mid = math.ceil((lo + hi) / 2)
    if g:measure(text:sub(1, mid) .. "…") <= w then lo = mid else hi = mid - 1 end
  end
  -- Do not cut a UTF-8 character in two.
  local s = text:sub(1, lo):gsub("[\192-\255][\128-\191]*$", "")
  return s .. "…"
end

local function icon(g, kind, x, y)
  if kind == "dir" then
    g:color("#e8b931")
    g:fill(x, y + 3, 6, 3)
    g:fill(x, y + 5, 14, 9)
    g:color("#b8891a")
    g:rect(x, y + 5, 14, 9)
  elseif kind == "app" then
    g:color("#2fa84f")
    g:fill(x + 1, y + 1, 12, 12)
    g:color("#ffffff")
    g:polygon(x + 5, y + 4, x + 10, y + 7, x + 5, y + 10)
  else
    g:color("#ffffff")
    g:fill(x + 2, y, 10, 14)
    g:color("#8a8a8a")
    g:loop(x + 2, y, x + 9, y, x + 12, y + 3, x + 12, y + 14, x + 2, y + 14)
  end
end

gui.define {
  name = "FileList",
  events = { "onChange", "onOpen", "onSort", "onMenu", "onCommand" },
  build = function(parent, opts)
    local c = parent:Canvas { width = 400, height = 300 }
    c.entries = {}
    c.cols = {
      { title = "Name" },
      { title = "Size", width = 80, align = "right" },
      { title = "Modified", width = 130 },
      { title = "Kind", width = 110 },
    }
    c.current = 0
    c.selection = {}   -- the rows selected, { [i] = true }; the current one is always among them
    c.anchor = 0       -- where a Shift selection began
    c.first = 1
    c.sortColumn, c.descending = 1, false
    c.typed, c.typedTimer = "", nil

    function c:visibleRows()
      return math.max(1, math.floor((self.height - HEAD) / ROW))
    end

    -- reveal scrolls so that row i is in sight.
    function c:reveal(i)
      local vis = self:visibleRows()
      if i < self.first then self.first = i
      elseif i >= self.first + vis then self.first = i - vis + 1 end
      self.first = clamp(self.first, 1, #self.entries - vis + 1)
    end

    -- pick makes row i the one with the focus, and the only one selected;
    -- with extend, the rows from where the selection began to it are.
    function c:pick(i, quiet, extend)
      i = clamp(i, #self.entries > 0 and 1 or 0, #self.entries)
      local moved = i ~= self.current
      local before = self:selectionKey()
      self.current = i
      if extend and self.anchor > 0 and i > 0 then
        self.selection = {}
        for k = math.min(self.anchor, i), math.max(self.anchor, i) do self.selection[k] = true end
      else
        self.selection = i > 0 and { [i] = true } or {}
        self.anchor = i
      end
      if i > 0 then self:reveal(i) end
      self:redraw()
      if (moved or before ~= self:selectionKey()) and not quiet then self:fire("onChange", i) end
    end

    -- selectionKey is what is selected, as a string, to see if it changed.
    function c:selectionKey()
      local keys = {}
      for i in pairs(self.selection) do keys[#keys + 1] = i end
      table.sort(keys)
      return table.concat(keys, ",")
    end

    -- toggle adds row i to the selection, or takes it out (never the last).
    function c:toggle(i)
      if i < 1 or i > #self.entries then return end
      local count = 0
      for _ in pairs(self.selection) do count = count + 1 end
      if self.selection[i] and count > 1 then
        self.selection[i] = nil
        if self.current == i then self.current = next(self.selection) end
      else
        self.selection[i] = true
        self.current = i
      end
      self.anchor = self.current
      self:reveal(self.current)
      self:redraw()
      self:fire("onChange", self.current)
    end

    function c:selectAll()
      if #self.entries == 0 then return end
      self.selection = {}
      for i = 1, #self.entries do self.selection[i] = true end
      self.anchor = 1
      self:redraw()
      self:fire("onChange", self.current)
    end

    -- setRows shows new rows, keeping the rows of the same names selected
    -- when there are some, else the first.
    function c:setRows(rows, selectName)
      local names = {}
      for i in pairs(self.selection) do
        if self.entries[i] then names[self.entries[i].name] = true end
      end
      local was = selectName or (self.entries[self.current] or {}).name
      self.entries = rows
      self.first = 1
      self.current = 0
      local at = #rows > 0 and 1 or 0
      for i, r in ipairs(rows) do
        if r.name == was then at = i break end
      end
      self:pick(at, true)
      if not selectName then
        for i, r in ipairs(rows) do
          if names[r.name] then self.selection[i] = true end
        end
      end
      self:fire("onChange", self.current)
    end

    -- selectNames selects the rows with these names (a list), the first of
    -- them having the focus.
    function c:selectNames(list)
      local want = {}
      for _, n in ipairs(list) do want[n] = true end
      local first
      self.selection = {}
      for i, r in ipairs(self.entries) do
        if want[r.name] then
          self.selection[i] = true
          first = first or i
        end
      end
      if first then
        self.current, self.anchor = first, first
        self:reveal(first)
      end
      self:redraw()
      self:fire("onChange", self.current)
    end

    function c:selectedRow()
      return self.entries[self.current]
    end

    function c:selectedRows()
      local out = {}
      for i, r in ipairs(self.entries) do
        if self.selection[i] then out[#out + 1] = r end
      end
      if #out == 0 and self.entries[self.current] then out[1] = self.entries[self.current] end
      return out
    end

    -- The x and width of each column: the first takes what the others
    -- leave.
    local function layout(w)
      local fixed = 0
      for i = 2, #c.cols do fixed = fixed + c.cols[i].width end
      local xs, x = {}, 0
      for i, col in ipairs(c.cols) do
        local cw = i == 1 and math.max(80, w - fixed) or col.width
        xs[i] = { x, cw }
        x = x + cw
      end
      return xs
    end

    function c:onDraw(g)
      local w, h = g:size()
      local scroll = #self.entries > self:visibleRows()
      local inner = scroll and w - BAR or w
      g:color("#ffffff")
      g:fill(0, 0, w, h)
      g:font("sans", 13)

      -- The header, with the sorted column's arrow.
      local xs = layout(inner)
      g:color("#e9e9e9")
      g:fill(0, 0, w, HEAD)
      for i, col in ipairs(self.cols) do
        local x, cw = xs[i][1], xs[i][2]
        g:color("#c4c4c4")
        g:line(x + cw - 1, 2, x + cw - 1, HEAD - 3)
        g:color("#303030")
        g:text(col.title, x + 6, 0, cw - 20, HEAD, "left")
        if i == self.sortColumn then
          local ax, ay = x + cw - 14, HEAD / 2
          if self.descending then g:polygon(ax, ay - 2, ax + 8, ay - 2, ax + 4, ay + 3)
          else g:polygon(ax, ay + 3, ax + 8, ay + 3, ax + 4, ay - 2) end
        end
      end
      g:color("#c4c4c4")
      g:line(0, HEAD - 1, w, HEAD - 1)

      -- The rows in sight.
      local vis = self:visibleRows()
      for i = self.first, math.min(#self.entries, self.first + vis - 1) do
        local r = self.entries[i]
        local y = HEAD + (i - self.first) * ROW
        local sel = self.selection[i]
        if sel then g:color(i == self.current and "#2f6fd8" or "#5a8be0"); g:fill(0, y, inner, ROW)
        elseif i % 2 == 0 then g:color("#f4f6fa"); g:fill(0, y, inner, ROW) end
        icon(g, r.icon, 6, y + 3)
        g:color(sel and "#ffffff" or (r.dim and "#8a8a8a" or "#202020"))
        for k, col in ipairs(self.cols) do
          local x, cw = xs[k][1], xs[k][2]
          local pad = k == 1 and 26 or 6
          local text = tostring(r.cells[k] or "")
          g:text(fit(g, text, cw - pad - 6), x + pad, y, cw - pad - 6, ROW, col.align or "left")
        end
      end
      if #self.entries == 0 then
        g:color("#8a8a8a")
        g:text(self.emptyText or "This folder is empty.", 0, HEAD + 8, w, ROW, "center")
      end

      -- The scrollbar.
      if scroll then
        local track = h - HEAD
        local n = #self.entries
        local th = math.max(20, math.floor(track * vis / n))
        local ty = HEAD + math.floor((track - th) * (self.first - 1) / math.max(1, n - vis))
        g:color("#efefef"); g:fill(w - BAR, HEAD, BAR, track)
        g:color("#b4b4b4"); g:fill(w - BAR + 2, ty, BAR - 4, th)
      end
    end

    local function scrollTo(y)
      local n, vis = #c.entries, c:visibleRows()
      local track = c.height - HEAD
      c.first = clamp(math.floor((y - HEAD) / track * n - vis / 2) + 1, 1, n - vis + 1)
      c:redraw()
    end

    function c:onMouseDown(x, y, button, double, mods)
      self.dragging = false
      -- A context menu: about the row under the mouse, or the folder.
      if button == 3 or (button == 1 and gui.platform == "darwin" and (mods or ""):find("Ctrl")) then
        if y < HEAD then return end
        local i = self.first + math.floor((y - HEAD) / ROW)
        if i > #self.entries then i = 0 end
        -- A row in the selection keeps it, for a menu about all of it.
        if i > 0 and not self.selection[i] then self:pick(i) end
        if i > 0 then self.current = i end
        self:fire("onMenu", i)
        return
      end
      if y < HEAD then
        local xs = layout(#self.entries > self:visibleRows() and self.width - BAR or self.width)
        for i, col in ipairs(xs) do
          if x >= col[1] and x < col[1] + col[2] then self:fire("onSort", i) return end
        end
        return
      end
      if #self.entries > self:visibleRows() and x >= self.width - BAR then
        self.dragging = true
        scrollTo(y)
        return
      end
      local i = self.first + math.floor((y - HEAD) / ROW)
      if i > #self.entries then return end
      mods = mods or ""
      if mods:find("Shift") then
        self:pick(i, false, true)
      elseif mods:find("Cmd") or (gui.platform ~= "darwin" and mods:find("Ctrl")) then
        self:toggle(i)
      else
        self:pick(i)
        if double and button == 1 then self:fire("onOpen", i) end
      end
    end

    function c:onMouseDrag(x, y)
      if self.dragging then scrollTo(y) end
    end

    function c:onMouseWheel(dx, dy)
      local vis = self:visibleRows()
      self.first = clamp(self.first + dy * 3, 1, #self.entries - vis + 1)
      self:redraw()
    end

    local moves = {
      Up = function(s) return s.current - 1 end,
      Down = function(s) return s.current + 1 end,
      PageUp = function(s) return s.current - s:visibleRows() + 1 end,
      PageDown = function(s) return s.current + s:visibleRows() - 1 end,
      Home = function() return 1 end,
      End = function(s) return #s.entries end,
    }

    function c:onKey(key, text)
      if key == "Shift+F10" then
        self:fire("onMenu", self.current)
        return true
      end
      local base = key:gsub("^Shift%+", "")
      if moves[base] then
        self:pick(moves[base](self), false, key:find("^Shift%+") ~= nil)
        return true
      end
      local letter = key:match("^Cmd%+(.+)$") or key:match("^Ctrl%+(.+)$")
      if letter and letter:lower() == "a" then
        self:selectAll()
        return true
      end
      if key == "Enter" or text == "\r" then
        if self.current > 0 then self:fire("onOpen", self.current) end
        return true
      end
      -- Typing a name's first letters goes to it; a pause starts again.
      local plain = not key:find("Ctrl%+") and not key:find("Cmd%+") and not key:find("Alt%+") and not key:find("Meta%+")
      if plain and #text >= 1 and text:byte(1) > 32 and text:byte(1) ~= 127 then
        local again = self.typed == text  -- the same letter again: the next one
        self.typed = again and text or self.typed .. text
        if self.typedTimer then self.typedTimer:stop() end
        self.typedTimer = gui.after(1, function() self.typed = "" end)
        local start = self.current + ((again or #self.typed == 1) and 1 or 0)
        local prefix = self.typed:lower()
        local n = #self.entries
        for k = 0, n - 1 do
          local i = (start - 1 + k) % n + 1
          if self.entries[i].name:lower():sub(1, #prefix) == prefix then
            self:pick(i)
            break
          end
        end
        return true
      end
      return self:fire("onCommand", key, text) and true or false
    end

    return c
  end,
}
