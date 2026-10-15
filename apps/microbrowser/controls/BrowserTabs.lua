-- A control of this project's own: the browser's tabs along the top, each
-- with its title and an × to close it, and a + after them for a new one.
-- A click picks a tab, a middle click or the × closes it, and a right
-- click asks for its menu.
--
--   tabs.list     the tabs: { title = "...", loading = true|nil } each
--   tabs.active   the one picked
--   tabs:changed()  draws them again after list or active changed
--
-- Events: onPick(i), onClose(i), onAdd(), onMenu(i, x, y).

local gui = require "gui"

local ADD = 30     -- the + button's width
local CLOSE = 18   -- the ×'s width, at a tab's right
local WIDEST = 220
local NARROWEST = 70

gui.define {
  name = "BrowserTabs",
  events = { "onPick", "onClose", "onAdd", "onMenu" },
  build = function(parent, opts)
    local c = parent:Canvas { width = 600, height = 30 }
    -- State lives in a table of its own: a field set on a Canvas draws it.
    local s = { rects = {}, add = nil, hover = nil }
    c.list, c.active = {}, 1

    function c:changed() self:redraw() end

    -- Fit shortens text to a width, with … at its end.
    local function fit(g, text, w)
      if g:measure(text) <= w then return text end
      local chars = {}
      for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
      local n = #chars
      while n > 0 and g:measure(table.concat(chars, "", 1, n) .. "…") > w do n = n - 1 end
      return table.concat(chars, "", 1, n) .. "…"
    end

    function c:onDraw(g)
      local W, H = g:size()
      local list = self.list or {}
      g:color("#dcdcdf")
      g:fill(0, 0, W, H)
      g:color("#b8b8bc")
      g:line(0, H - 1, W, H - 1)
      local n = math.max(1, #list)
      local w = math.max(NARROWEST, math.min(WIDEST, math.floor((W - ADD - 8) / n) - 2))
      local x = 4
      local rects = {}
      g:font("sans", 13)
      for i, t in ipairs(list) do
        local on = i == self.active
        if on then
          g:color("#ffffff")
          g:fill(x, 3, w, H - 3)
          g:color("#b8b8bc")
          g:line(x, 3, x, H - 1)
          g:line(x + w, 3, x + w, H - 1)
          g:line(x, 3, x + w, 3)
        elseif s.hover == i then
          g:color("#e9e9ec")
          g:fill(x, 4, w, H - 6)
        end
        g:color(on and "#1d1d1f" or "#4a4a4f")
        local title = (t.loading and "◌ " or "") .. ((t.title or "") ~= "" and t.title or "New Tab")
        g:text(fit(g, title, w - CLOSE - 14), x + 8, 3, w - CLOSE - 10, H - 4, "left")
        g:color("#77777c")
        g:text("×", x + w - CLOSE - 2, 3, CLOSE, H - 4, "center")
        if not on and list[i + 1] and (i + 1) ~= self.active then
          g:color("#b8b8bc")
          g:line(x + w, 9, x + w, H - 9)
        end
        rects[i] = { x, w }
        x = x + w + 1
      end
      g:color("#4a4a4f")
      g:font("sans", 17)
      g:text("+", x + 2, 2, ADD - 4, H - 4, "center")
      s.add = { x + 2, ADD - 4 }
      s.rects = rects
    end

    local function tabAt(x)
      for i, r in ipairs(s.rects) do
        if x >= r[1] and x < r[1] + r[2] then
          return i, x >= r[1] + r[2] - CLOSE - 4
        end
      end
    end

    function c:onMouseDown(x, y, button, double)
      if s.add and x >= s.add[1] and x < s.add[1] + s.add[2] then
        if button == 1 then self:fire("onAdd") end
        return
      end
      local i, onClose = tabAt(x)
      if button == 3 then
        self:fire("onMenu", i, x, y)
      elseif button == 2 then
        if i then self:fire("onClose", i) end
      elseif not i then
        if double then self:fire("onAdd") end
      elseif onClose then
        self:fire("onClose", i)
      else
        self:fire("onPick", i)
      end
    end

    function c:onMouseMove(x, y)
      local i = tabAt(x)
      if i ~= s.hover then
        s.hover = i
        self:redraw()
      end
    end

    function c:onMouseLeave()
      if s.hover then
        s.hover = nil
        self:redraw()
      end
    end

    return c
  end,
}
