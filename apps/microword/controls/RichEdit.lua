-- A control of this project's own: the WYSIWYG editor, drawn on a Canvas.
-- A form's layout that uses a RichEdit finds it here, as controls.RichEdit,
-- and the designer shows it in its toolbox.
--
-- It draws editor.lua's document as a page, laid out by tlua's
-- markdown.layout and drawn by markdown.render, the same that draw a
-- MarkdownView, with the caret and the selection, and turns the keyboard
-- and the mouse into the editor's calls. What the menus and the toolbar do
-- goes through edit.ed and edit:changed().
--
--   edit.ed            the editor (editor.lua)
--   edit.assets        the pictures, by the name the Markdown gives them
--   edit:load(blocks, assets)
--   edit:changed()     after the document was changed from outside
--   edit:moved()       after the caret was moved from outside
--
-- Events: onChange when the document changes, onSelect when the caret or
-- the selection moves, onMenu(x, y) for a right click, onLink(url) for a
-- Cmd- or Ctrl-click on a link.

local gui = require "gui"
local editor = require "editor"
local layout = require "markdown.layout"
local render = require "markdown.render"

local BAR = 12           -- the scrollbar's width
local MARGIN = 56        -- white page around the text
local TOP = 40           -- above the first block and below the last
local MAX_WIDTH = 700    -- the widest the text column gets

-- The page's own colours; the text's are markdown.render's.
local COLORS = {
  desk = "#e7e8ec", page = "#ffffff", selection = render.colors.selection, caret = "#000000",
}

gui.define {
  name = "RichEdit",
  events = { "onChange", "onSelect", "onMenu", "onLink" },
  build = function(parent, opts)
    local c = parent:Canvas { width = 400, height = 300 }
    c.ed = editor.new()
    c.assets = {}
    c.scrollY = 0
    c.needsLayout = true
    c.revealCaret = true
    c.measurer = render.measurer()
    c.lineCache = {} -- each paragraph's lines, kept between layouts

    local function imageSize(src)
      local a = c.assets[src]
      if a and a.image then return a.image.width, a.image.height end
      return nil
    end

    -- Where the page's text column starts on the Canvas.
    function c:origin()
      local columnW = math.max(160, math.min(MAX_WIDTH, self.width - BAR - 2 * MARGIN))
      local x = math.floor((self.width - BAR - columnW) / 2)
      return x, TOP - self.scrollY, columnW
    end

    function c:load(blocks, assets)
      self.ed:load(blocks)
      self.assets = assets or {}
      self.scrollY = 0
      self.needsLayout = true
      self.revealCaret = true
      self:redraw()
      self:fire("onSelect")
    end

    function c:changed()
      self.needsLayout = true
      self.revealCaret = true
      self:redraw()
      self:fire("onChange")
      self:fire("onSelect")
    end

    function c:moved()
      self.revealCaret = true
      self:redraw()
      self:fire("onSelect")
    end

    ---------------------------------------------------------------- drawing

    local function relayout(self, columnW)
      if self.needsLayout or not self.lay or self.lay.width ~= columnW then
        self.lay = layout.build(self.ed.blocks, columnW, self.measurer.measure, imageSize, self.lineCache)
        self.needsLayout = false
      end
      return self.lay
    end

    local function drawBlock(self, g, L, x0, y0, columnW)
      render.block(g, L, x0, y0, columnW, {
        measure = self.measurer.measure,
        image = function(src)
          local a = self.assets[src]
          return a and a.image
        end,
      })
    end

    function c:onDraw(g)
      local W, H = g:size()
      local x0, _, columnW = self:origin()
      self.measurer.g = g
      local lay = relayout(self, columnW)
      local ed = self.ed
      local total = lay.height + 2 * TOP
      if self.revealCaret then
        local _, cy, ch = lay:caret(ed.caret)
        if cy + TOP - self.scrollY < 8 then self.scrollY = cy + TOP - 8 end
        if cy + ch + TOP - self.scrollY > H - 8 then self.scrollY = cy + ch + TOP - H + 8 end
        self.revealCaret = false
      end
      self.scrollY = math.max(0, math.min(self.scrollY, math.max(0, total - H)))
      local y0 = TOP - self.scrollY

      g:color(COLORS.desk); g:fill(0, 0, W, H)
      g:color(COLORS.page)
      g:fill(x0 - MARGIN, y0 - TOP + 12, columnW + 2 * MARGIN, lay.height + 2 * TOP - 24)
      g:color("#d6d7db")
      g:rect(x0 - MARGIN, y0 - TOP + 12, columnW + 2 * MARGIN, lay.height + 2 * TOP - 24)

      -- The selection, under the text.
      if ed:hasSelection() then
        local s, e = ed:range()
        g:color(COLORS.selection)
        for _, r in ipairs(lay:rects(s, e)) do
          if y0 + r[2] + r[4] >= 0 and y0 + r[2] <= H then g:fill(x0 + r[1], y0 + r[2], r[3], r[4]) end
        end
      end

      for _, L in ipairs(lay.blocks) do
        if y0 + L.y + L.h >= 0 and y0 + L.y <= H then drawBlock(self, g, L, x0, y0, columnW) end
      end

      -- A picture or a rule that is selected gets a frame.
      if ed:hasSelection() then
        local s, e = ed:range()
        for i = s.b, e.b do
          local L = lay.blocks[i]
          if L and not editor.hasText(L.block) and (i > s.b or s.o == 0) and (i < e.b or e.o == 1) then
            g:color("#2f6fd8"); g:width(2)
            g:rect(x0 + L.x - 2, y0 + L.y - 2, L.lines[1].w + 4, L.lines[1].h + 4)
            g:width(1)
          end
        end
      end

      -- The caret.
      local cx, cy, ch = lay:caret(ed.caret)
      g:color(COLORS.caret)
      g:fill(x0 + cx, y0 + cy + 2, 2, ch - 4)

      -- The scrollbar.
      if total > H then
        local th = math.max(24, math.floor(H * H / total))
        local ty = math.floor((H - th) * self.scrollY / (total - H))
        g:color("#dcdde1"); g:fill(W - BAR, 0, BAR, H)
        g:color("#a9abb2"); g:fill(W - BAR + 2, ty, BAR - 4, th)
      end
      self.measurer.g = nil
    end

    ---------------------------------------------------------------- the mouse

    local function scrollTo(self, y)
      local total = self.lay.height + 2 * TOP
      self.scrollY = (y / self.height) * total - self.height / 2
      self:redraw()
    end

    local function hitAt(self, x, y)
      if not self.lay then return self.ed.caret end
      local x0, y0 = self:origin()
      return self.lay:hit(x - x0, y - y0)
    end

    function c:onMouseDown(x, y, button, double, mods)
      mods = mods or ""
      local total = self.lay and self.lay.height + 2 * TOP or 0
      if x >= self.width - BAR and total > self.height then
        self.scrolling = true
        scrollTo(self, y)
        return
      end
      self.scrolling = false
      local p = hitAt(self, x, y)
      local ed = self.ed
      if button == 3 then
        -- A right click outside the selection moves the caret there first.
        local s, e = ed:range()
        local inside = ed:hasSelection() and not editor.before(p, s) and not editor.before(e, p)
        if not inside then ed:setCaret(p) end
        self:redraw()
        self:fire("onSelect")
        self:fire("onMenu", x, y)
        return
      end
      if (mods:find("Cmd") or mods:find("Ctrl")) and ed:linkAt(p) then
        self:fire("onLink", (ed:linkAt(p)))
        return
      end
      if double then
        ed:selectWord(p)
      else
        ed:setCaret(p, mods:find("Shift") ~= nil)
      end
      self.goal = nil
      ed.goalX = nil
      self.dragging = true
      self:redraw()
      self:fire("onSelect")
    end

    function c:onMouseDrag(x, y)
      if self.scrolling then scrollTo(self, y) return end
      if not self.dragging then return end
      -- Dragging past the top or bottom scrolls.
      if y < 0 then self.scrollY = self.scrollY - 20
      elseif y > self.height then self.scrollY = self.scrollY + 20 end
      self.ed:setCaret(hitAt(self, x, y), true)
      self:redraw()
      self:fire("onSelect")
    end

    function c:onMouseUp()
      self.dragging = false
      self.scrolling = false
    end

    function c:onMouseWheel(dx, dy)
      self.scrollY = self.scrollY + dy * 40
      self:redraw()
    end

    ---------------------------------------------------------------- keys

    -- edits are keys that change the document; the rest only move.
    function c:onKey(key, text)
      local ed, lay = self.ed, self.lay
      local shift = key:find("Shift%+") ~= nil
      local base = key:gsub("Shift%+", "")
      local page = math.max(40, self.height - 80)
      local moves = {
        Left = function() ed:move(-1, shift) end,
        Right = function() ed:move(1, shift) end,
        ["Alt+Left"] = function() ed:move(-1, shift, true) end,
        ["Alt+Right"] = function() ed:move(1, shift, true) end,
        ["Ctrl+Left"] = function() ed:move(-1, shift, true) end,
        ["Ctrl+Right"] = function() ed:move(1, shift, true) end,
        Up = function() if lay then ed:moveLine(lay, -1, shift) end end,
        Down = function() if lay then ed:moveLine(lay, 1, shift) end end,
        Home = function() if lay then ed:moveLineEdge(lay, -1, shift) end end,
        End = function() if lay then ed:moveLineEdge(lay, 1, shift) end end,
        ["Cmd+Left"] = function() if lay then ed:moveLineEdge(lay, -1, shift) end end,
        ["Cmd+Right"] = function() if lay then ed:moveLineEdge(lay, 1, shift) end end,
        ["Cmd+Up"] = function() ed:moveToDocument(-1, shift) end,
        ["Cmd+Down"] = function() ed:moveToDocument(1, shift) end,
        ["Ctrl+Home"] = function() ed:moveToDocument(-1, shift) end,
        ["Ctrl+End"] = function() ed:moveToDocument(1, shift) end,
        PageUp = function() if lay then ed:movePage(lay, -1, shift, page) end end,
        PageDown = function() if lay then ed:movePage(lay, 1, shift, page) end end,
      }
      local keepGoal = base == "Up" or base == "Down" or base == "PageUp" or base == "PageDown"
      if moves[base] then
        local goal = ed.goalX
        moves[base]()
        if keepGoal then ed.goalX = ed.goalX or goal else ed.goalX = nil end
        if base == "PageUp" then self.scrollY = self.scrollY - page end
        if base == "PageDown" then self.scrollY = self.scrollY + page end
        self:moved()
        return true
      end
      ed.goalX = nil
      local edits = {
        Backspace = function() ed:backspace() end,
        ["Alt+Backspace"] = function() ed:deleteWord() end,
        ["Ctrl+Backspace"] = function() ed:deleteWord() end,
        Delete = function() ed:delete() end,
        Enter = function() ed:enter() end,
        ["Shift+Enter"] = function() ed:lineBreak() end,
      }
      local edit = edits[key]
      if key == "Tab" or key == "Shift+Tab" then
        local delta = key == "Tab" and 1 or -1
        if ed:indent(delta) then self:changed() return true end
        if key == "Tab" and ed:blockType() == "code" then ed:type("    ") self:changed() return true end
        return false -- Tab goes on to the next control
      end
      if edit then
        edit()
        self:changed()
        return true
      end
      local typed = text ~= "" and text:byte(1) >= 32 and text:byte(1) ~= 127
      if typed and not key:find("Cmd%+") and not key:find("Ctrl%+") and not key:find("Meta%+") then
        ed:type(text)
        self:changed()
        return true
      end
      return false
    end

    return c
  end,
}
