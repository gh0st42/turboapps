-- A control of this project's own: the bar being edited, as a piano roll.
-- It has a row for each pitch of the song's scale (a drum channel, one for
-- each drum), so a note can only go where it belongs, and the key's rows
-- are lit so home is easy to find.
--
--   roll.song, roll.channel, roll.bar   what it edits
--   roll.length                         how long a new note is, in ticks
--   roll.playTick                       where the bar is playing, or nil
--   roll:reveal()                       scrolls to the notes, or the channel's octave
--   roll:changed()                      draws it again after the song changed
--   roll:pointOf(pitch, tick)           where that is on it, for the tests
--
-- With the mouse: a click in an empty place puts a note there, as long as
-- roll.length, and dragging makes it longer or shorter; a click in a note
-- sounding there adds that pitch to it, a chord. Dragging a note moves it,
-- dragging its end stretches it, and a click on it takes it away, as does
-- a right click. The wheel scrolls up and down.
--
-- Events, so the form can keep undo and play what changed:
--   onEdit(continuing)  before the song is changed; continuing for the rest of a drag
--   onEdited()          after it was
--   onEditDone()        the mouse is up: the edit is finished
--   onNote(pitch)       a pitch to sound, as a note goes down or moves to it

local gui = require "gui"
local songs = require "song"
local look = require "look"

local GUTTER = 58
local ROW = 16

gui.define {
  name = "PianoRoll",
  events = { "onEdit", "onEdited", "onEditDone", "onNote" },
  build = function(parent, opts)
    local c = parent:Canvas { width = 700, height = 400 }
    local s = { top = 1, rows = {}, rowH = ROW }
    c.song, c.channel, c.bar, c.length, c.playTick = nil, 1, 1, 4, nil

    function c:changed() self:redraw() end

    local function geometry(self, W, H)
      local song = self.song
      s.rows = songs.rows(song, self.channel, self.bar)
      s.rowH = songs.isDrum(song, self.channel) and math.max(ROW, math.floor(H / #s.rows)) or ROW
      s.visible = math.max(1, math.floor(H / s.rowH))
      s.top = math.max(1, math.min(s.top, math.max(1, #s.rows - s.visible + 1)))
      s.ticks = songs.barTicks(song)
      s.colW = (W - GUTTER) / s.ticks
      s.W, s.H = W, H
    end

    -- reveal scrolls to the bar's notes, or else to the channel's octave.
    function c:reveal()
      local song = self.song
      if not song then return end
      local rows = songs.rows(song, self.channel, self.bar)
      local p = songs.patternAt(song, self.channel, self.bar)
      local hi, lo
      if p then
        for _, n in ipairs(p.notes) do
          for _, q in ipairs(n.pitches) do hi, lo = math.max(hi or q, q), math.min(lo or q, q) end
        end
      end
      local ch = song.channels[self.channel]
      local centre = hi and (hi + lo) / 2 or ((tonumber(ch and ch.octaveScrollBar) or 3) * 12 + 12)
      local best, at = math.huge, 1
      for i, q in ipairs(rows) do
        if math.abs(q - centre) < best then best, at = math.abs(q - centre), i end
      end
      local visible = math.max(1, math.floor(self.height / ROW))
      s.top = math.max(1, at - math.floor(visible / 2))
      self:redraw()
    end

    function c:onDraw(g)
      local W, H = g:size()
      g:color(look.colors.roll)
      g:fill(0, 0, W, H)
      local song = self.song
      if not song then return end
      geometry(self, W, H)
      local drum = songs.isDrum(song, self.channel)
      local colour = look.channelColor(song, self.channel)
      local rowOf = {}
      -- Rows, and the names of their pitches.
      g:font("sans", 11)
      for i = s.top, math.min(#s.rows, s.top + s.visible) do
        local q = s.rows[i]
        rowOf[q] = i
        local y = (i - s.top) * s.rowH
        local bg = (not drum and not songs.inScale(song, q)) and look.colors.offScale
          or (not drum and songs.isKey(q)) and look.colors.keyRow
          or (i % 2 == 0 and look.colors.rowAlt or look.colors.roll)
        g:color(bg)
        g:fill(GUTTER, y, W - GUTTER, s.rowH)
        g:color(look.colors.gutter)
        g:fill(0, y, GUTTER - 1, s.rowH)
        g:color((not drum and songs.isKey(q)) and look.colors.text or look.colors.dim)
        g:font("sans", 11, (not drum and songs.isKey(q)) and "bold" or nil)
        g:text(songs.pitchName(song, self.channel, q), 4, y, GUTTER - 8, s.rowH, "left")
      end
      g:font("sans", 11)
      -- Steps and beats.
      for tk = 0, s.ticks do
        local x = math.floor(GUTTER + tk * s.colW)
        g:color(tk % song.ticksPerBeat == 0 and look.colors.beat or look.colors.step)
        if tk == 0 or tk == s.ticks then g:color(look.colors.barLine) end
        g:line(x, 0, x, H)
      end
      -- Notes.
      local p = songs.patternAt(song, self.channel, self.bar)
      if p then
        for _, n in ipairs(p.notes) do
          local x1 = GUTTER + songs.noteStart(n) * s.colW
          local x2 = GUTTER + songs.noteEnd(n) * s.colW
          for _, q in ipairs(n.pitches) do
            local i = rowOf[q]
            if i then
              local y = (i - s.top) * s.rowH
              g:color(colour)
              g:fill(math.floor(x1) + 1, y + 1, math.max(3, math.floor(x2 - x1) - 1), s.rowH - 2)
              g:color(look.colors.text)
              g:rect(math.floor(x1) + 1, y + 1, math.max(3, math.floor(x2 - x1) - 1), s.rowH - 2)
              -- The end, where a drag stretches it.
              g:fill(math.floor(x2) - 3, y + 3, 2, s.rowH - 6)
            end
          end
        end
      else
        g:color(look.colors.dim)
        g:text(#s.rows > 0 and "Click to put a note here" or "", GUTTER, 0, W - GUTTER, H, "center")
      end
      if self.playTick then
        local x = math.floor(GUTTER + self.playTick * s.colW)
        g:color(look.colors.playhead)
        g:fill(x - 1, 0, 2, H)
      end
    end

    -- pointOf is the middle of a pitch's row at a tick, as last drawn; nil
    -- when the row is not in view. For the tests, which click there.
    function c:pointOf(pitch, tick)
      if not s.ticks then return nil end
      for i = s.top, math.min(#s.rows, s.top + s.visible - 1) do
        if s.rows[i] == pitch then
          return math.floor(GUTTER + (tick + 0.5) * s.colW), math.floor((i - s.top + 0.5) * s.rowH)
        end
      end
    end

    -- at is the pitch and tick under a point; nil outside the rows.
    local function at(x, y)
      if not s.ticks or x < GUTTER then return nil end
      local i = s.top + math.floor(y / s.rowH)
      local q = s.rows[i]
      if not q then return nil end
      local tick = math.max(0, math.min(s.ticks - 1, math.floor((x - GUTTER) / s.colW)))
      return q, tick, i
    end

    local function edit(self, fn)
      self:fire("onEdit", s.drag ~= nil and s.drag.began)
      if s.drag then s.drag.began = true end
      fn()
      self:fire("onEdited")
      self:redraw()
    end

    function c:onMouseDown(x, y, button)
      local song = self.song
      if not song then return end
      local q, tick = at(x, y)
      if not q then return end
      local p = songs.patternAt(song, self.channel, self.bar)
      local n = p and songs.noteAt(p, tick, q)
      if button == 3 then
        if n then
          s.drag = nil
          edit(self, function() songs.removePitch(p, n, q) end)
          self:fire("onEditDone")
        end
        return
      end
      if n then
        local nearEnd = tick >= songs.noteEnd(n) - 1 and songs.noteEnd(n) - songs.noteStart(n) > 1
        s.drag = { mode = nearEnd and "stretch" or "move", note = n, pitch = q,
          grab = tick - songs.noteStart(n), moved = false }
        return
      end
      -- A new note, or a pitch more for the one sounding there.
      s.drag = { mode = "draw", moved = false }
      edit(self, function()
        p = songs.ensurePattern(song, self.channel, self.bar)
        local made, new = songs.addNote(song, p, q, tick, self.length)
        s.drag.note, s.drag.pitch = made, q
        if made and not new then s.drag.mode = "chord" end
      end)
      if s.drag.note then self:fire("onNote", q) else s.drag = nil end
    end

    function c:onMouseDrag(x, y)
      local d = s.drag
      if not d or not d.note then return end
      local song = self.song
      local p = songs.patternAt(song, self.channel, self.bar)
      if not p then return end
      local q, tick = at(x, math.max(0, math.min(y, s.H - 1)))
      if not q then return end
      if d.mode == "draw" or d.mode == "stretch" then
        local stop = math.max(songs.noteStart(d.note) + 1, tick + 1)
        if stop ~= songs.noteEnd(d.note) then
          d.moved = true
          edit(self, function() songs.resize(song, p, d.note, stop) end)
        end
      elseif d.mode == "move" then
        local start = tick - d.grab
        local semis = q - d.pitch
        if start ~= songs.noteStart(d.note) or semis ~= 0 then
          d.moved = true
          edit(self, function()
            if songs.move(song, p, d.note, start, semis, songs.maxPitch(song, self.channel)) then
              d.pitch = d.pitch + semis
            end
          end)
          if semis ~= 0 then self:fire("onNote", d.pitch) end
        end
      end
    end

    function c:onMouseUp(x, y)
      local d = s.drag
      s.drag = nil
      if not d then return end
      if d.mode == "move" and not d.moved then
        -- A click on a note takes it away.
        local p = songs.patternAt(self.song, self.channel, self.bar)
        if p then edit(self, function() songs.removePitch(p, d.note, d.pitch) end) end
      end
      if d.began or d.mode == "move" then self:fire("onEditDone") end
    end

    function c:onMouseWheel(dx, dy)
      s.top = math.max(1, s.top + dy * 2)
      self:redraw()
    end

    return c
  end,
}
