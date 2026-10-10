-- A control of this project's own: the workbook's sheets as tabs along the
-- bottom, with a + to add one. A click picks a sheet, a double click
-- renames it, and a right click asks for its menu.
--
--   tabs.book     the workbook whose sheets it shows
--
-- Events: onPick(i), onRename(i), onAdd(), onMenu(i, x, y).

local gui = require "gui"
local themes = require "themes"

local ADD = 28   -- the + button's width
local GAP = 2

gui.define {
  name = "SheetTabs",
  events = { "onPick", "onRename", "onAdd", "onMenu" },
  props = { theme = { type = "string", default = "Light" } },
  build = function(parent, opts)
    local c = parent:Canvas { width = 400, height = 26 }
    c.book = nil
    c.cache = { rects = {} }

    function c:onDraw(g)
      local th = themes.get(self.theme)
      local W, H = g:size()
      g:color(th.header)
      g:fill(0, 0, W, H)
      g:color(th.line)
      g:line(0, 0, W, 0)
      g:font("sans", 13)
      g:color(th.headerText)
      g:text("+", 0, 0, ADD, H, "center")
      local rects = {}
      local x = ADD + 4
      if self.book then
        for i, s in ipairs(self.book.sheets) do
          local w = math.floor(g:measure(s.name)) + 24
          local on = i == self.book.active
          if on then
            g:color(th.bg)
            g:fill(x, 0, w, H - 3)
            g:color(th.cursor)
            g:fill(x, H - 4, w, 3)
          end
          g:color(on and th.text or th.headerText)
          g:font("sans", 13, on and "bold" or nil)
          g:text(s.name, x, 0, w, H - 3, "center")
          g:font("sans", 13)
          g:color(th.line)
          g:line(x + w, 5, x + w, H - 7)
          rects[i] = { x, w }
          x = x + w + GAP
        end
      end
      self.cache.rects = rects
    end

    local function tabAt(self, x)
      for i, r in ipairs(self.cache.rects) do
        if x >= r[1] and x < r[1] + r[2] then return i end
      end
    end

    function c:onMouseDown(x, y, button, double)
      if x < ADD then
        if button == 1 then self:fire("onAdd") end
        return
      end
      local i = tabAt(self, x)
      if button == 3 then
        if i then self:fire("onPick", i) end
        self:fire("onMenu", i, x, y)
        return
      end
      if not i then
        if double then self:fire("onAdd") end
        return
      end
      if double then self:fire("onRename", i) else self:fire("onPick", i) end
    end

    return c
  end,
}
