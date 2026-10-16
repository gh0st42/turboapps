-- A control of this project's own: the song as a grid of channels against
-- bars, each cell showing the pattern that channel plays in that bar. The
-- cell being edited is outlined, the bars that play the same pattern are lit
-- with it, the loop is marked along the top, and the bar playing is lit
-- while the song plays.
--
--   grid.song, grid.channel, grid.bar   what it shows, and the cell picked
--   grid.playBar                        the bar playing, or nil
--   grid.muted, grid.soloed             channels silenced, and played alone: { [c] = true }
--   grid:changed()                      draws it again after the song changed
--
-- The M and S beside a channel's name mute it and play it alone.
--
-- Events: onPick(channel, bar), onMenu(channel, bar, x, y), onMute(channel),
-- onSolo(channel).

local gui = require "gui"
local songs = require "song"
local look = require "look"

local LABEL = 150  -- the channel names' column, with mute and solo
local HEAD = 20    -- the bar numbers' row
local CELL = 30    -- a bar's width
local ROW = 24     -- a channel's height

gui.define {
  name = "SongGrid",
  events = { "onPick", "onMenu", "onMute", "onSolo" },
  build = function(parent, opts)
    local c = parent:Canvas { width = 800, height = HEAD + 4 * ROW }
    -- State of its own: a field set on a Canvas draws it again.
    local s = { scroll = 0 }
    c.song, c.channel, c.bar, c.playBar = nil, 1, 1, nil
    c.muted, c.soloed = {}, {}

    local MUTE_X, SOLO_X, BOX = LABEL - 44, LABEL - 22, 18

    -- silenced says whether channel ci is not heard: muted, or another is
    -- played alone.
    local function silenced(self, ci)
      if self.muted[ci] then return true end
      for _, on in pairs(self.soloed) do
        if on then return not self.soloed[ci] end
      end
      return false
    end

    function c:changed() self:redraw() end

    local function visibleBars(W) return math.max(1, math.floor((W - LABEL) / CELL)) end

    -- keepInView scrolls so the picked bar, or the one playing, is seen.
    local function keepInView(self, W)
      local n = visibleBars(W)
      local want = self.playBar or self.bar or 1
      if want ~= s.followed then
        -- Only when it moves, so the wheel can look elsewhere meanwhile.
        s.followed = want
        if want <= s.scroll then s.scroll = want - 1 end
        if want > s.scroll + n then s.scroll = want - n end
      end
      local bars = self.song and songs.bars(self.song) or 1
      s.scroll = math.max(0, math.min(s.scroll, math.max(0, bars - n)))
    end

    function c:onDraw(g)
      local W, H = g:size()
      g:color(look.colors.panel)
      g:fill(0, 0, W, H)
      local song = self.song
      if not song then return end
      keepInView(self, W)
      local bars = songs.bars(song)
      local n = visibleBars(W)
      g:font("sans", 11)
      -- The loop, along the top.
      local loopFrom, loopTo = song.introBars + 1, song.introBars + song.loopBars
      for b = s.scroll + 1, math.min(bars, s.scroll + n) do
        local x = LABEL + (b - s.scroll - 1) * CELL
        if b >= loopFrom and b <= loopTo then
          g:color(look.colors.loop)
          g:fill(x, 0, CELL, HEAD - 2)
        end
        if b == self.playBar then
          g:color(look.colors.playhead)
          g:fill(x, 0, CELL, HEAD - 2)
        end
        g:color(b == self.bar and look.colors.text or look.colors.dim)
        g:text(tostring(b), x, 0, CELL, HEAD - 2, "center")
      end
      -- The channels.
      local picked = song.channels[self.channel] and song.channels[self.channel].sequence[self.bar] or 0
      for ci, ch in ipairs(song.channels) do
        local y = HEAD + (ci - 1) * ROW
        if y > H then break end
        local colour = silenced(self, ci) and look.colors.muted or look.channelColor(song, ci)
        g:color(ci == self.channel and look.colors.selectedRow or look.colors.panel)
        g:fill(0, y, LABEL - 2, ROW - 2)
        g:color(colour)
        g:fill(4, y + 6, 10, 10)
        g:color(look.colors.text)
        g:font("sans", 12, ci == self.channel and "bold" or nil)
        g:text(songs.channelLabel(song, ci), 20, y, MUTE_X - 22, ROW - 2, "left")
        g:font("sans", 11, "bold")
        for _, b in ipairs { { MUTE_X, "M", self.muted[ci], look.colors.mute },
                             { SOLO_X, "S", self.soloed[ci], look.colors.solo } } do
          g:color(b[3] and b[4] or look.colors.cell)
          g:fill(b[1], y + 3, BOX, ROW - 8)
          g:color(b[3] and "#ffffff" or look.colors.dim)
          g:text(b[2], b[1], y + 3, BOX, ROW - 8, "center")
        end
        g:font("sans", 11)
        for b = s.scroll + 1, math.min(bars, s.scroll + n) do
          local x = LABEL + (b - s.scroll - 1) * CELL
          local pat = ch.sequence[b] or 0
          g:color(look.colors.cell)
          g:fill(x + 1, y + 1, CELL - 2, ROW - 4)
          if pat > 0 then
            local full = songs.patternHasNotes(song, ci, pat)
            g:color(full and colour or look.colors.empty)
            g:fill(x + 2, y + 2, CELL - 4, ROW - 6)
            if ci == self.channel and pat == picked and b ~= self.bar then
              -- Plays the same pattern as the cell picked: changes with it.
              g:color(look.colors.shared)
              g:fill(x + 2, y + ROW - 8, CELL - 4, 3)
            end
            g:color(full and look.colors.onColor or look.colors.dim)
            g:text(tostring(pat), x, y, CELL, ROW - 2, "center")
          end
          if b == self.playBar then
            g:color(look.colors.playhead)
            g:rect(x, y, CELL, ROW - 2)
          end
          if ci == self.channel and b == self.bar then
            g:color(look.colors.text)
            g:rect(x, y, CELL, ROW - 2)
            g:rect(x + 1, y + 1, CELL - 2, ROW - 4)
          end
        end
      end
      s.n = n
    end

    local function cellAt(self, x, y)
      if not self.song or x < LABEL or y < HEAD then
        local ci = math.floor((y - HEAD) / ROW) + 1
        if self.song and y >= HEAD and self.song.channels[ci] then return ci, nil end
        return nil
      end
      local ci = math.floor((y - HEAD) / ROW) + 1
      local b = s.scroll + math.floor((x - LABEL) / CELL) + 1
      if not self.song.channels[ci] or b > songs.bars(self.song) then return ci, nil end
      return ci, b
    end

    function c:onMouseDown(x, y, button)
      local ci, b = cellAt(self, x, y)
      if not ci then return end
      if button == 1 and x >= MUTE_X and x < MUTE_X + BOX then self:fire("onMute", ci) return end
      if button == 1 and x >= SOLO_X and x < SOLO_X + BOX then self:fire("onSolo", ci) return end
      if button == 3 then
        self:fire("onMenu", ci, b, x, y)
        return
      end
      self:fire("onPick", ci, b or self.bar)
    end

    function c:onMouseWheel(dx, dy)
      s.scroll = math.max(0, s.scroll + (dy ~= 0 and dy or dx))
      self:redraw()
    end

    -- boxOf is where channel ci's mute or solo box is, for the tests.
    function c:boxOf(ci, which)
      return (which == "solo" and SOLO_X or MUTE_X) + BOX / 2, HEAD + (ci - 1) * ROW + ROW / 2
    end

    return c
  end,
}
