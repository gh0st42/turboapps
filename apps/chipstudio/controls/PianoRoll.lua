-- A control of this project's own: the bar being edited, as a piano roll.
-- It has a row for each pitch of the song's scale (a drum channel, one for
-- each drum), so a note can only go where it belongs, and the key's rows
-- are lit so home is easy to find.
--
--   roll.song, roll.channel, roll.bar   what it edits
--   roll.playTick                       where the bar is playing, or nil
--   roll.mode                           "notes", "volume" or "bend": what a drag does
--   roll.cursorTick                     where a note played on the keyboard goes, or nil
--   roll.ghosts                         whether the other channels' notes show, faintly
--   roll.hidden                         channels whose notes do not show: { [3] = true }
--   roll:reveal()                       scrolls to the notes, or the channel's octave
--   roll:changed()                      draws it again after the song changed
--   roll:pointOf(pitch, tick)           where that is on it, for the tests
--
-- With the mouse: a click in an empty place puts a note of one step there,
-- and dragging makes it longer or shorter; a click in a note
-- sounding there adds that pitch to it, a chord. Dragging a note moves it,
-- dragging its end stretches it, and a click on it takes it away, as does
-- a right click. The wheel scrolls up and down.
--
-- On a melody channel, the notes the other melody channels play in the bar
-- show faintly behind its own, in their colours, so a harmony or a bass can
-- be written against the lead. They are only to see by: clicks go to the
-- channel's own notes.
--
-- In volume mode, dragging a note up or down makes it louder or quieter
-- where it was grabbed: at its start or end, or at a new point in between,
-- so it can swell and fade. In bend mode the same drag bends it to the row
-- the mouse is on, as a slide. Notes are drawn as thick as they are loud,
-- with a bend as a line. A right click puts a point back as it was.
--
-- Events, so the form can keep undo and play what changed:
--   onEdit(continuing)  before the song is changed; continuing for the rest of a drag
--   onEdited()          after it was
--   onEditDone()        the mouse is up: the edit is finished
--   onNote(pitch)       a pitch to sound, as a note goes down or moves to it
--   onHint(text)        what a drag is setting ("Volume 60%"), or nil when done

local gui = require "gui"
local songs = require "song"
local look = require "look"

local GUTTER = 72
local ROW = 16

gui.define {
  name = "PianoRoll",
  events = { "onEdit", "onEdited", "onEditDone", "onNote", "onHint" },
  build = function(parent, opts)
    local c = parent:Canvas { width = 700, height = 400 }
    local s = { top = 1, rows = {}, rowH = ROW }
    c.song, c.channel, c.bar, c.playTick = nil, 1, 1, nil
    c.mode, c.cursorTick = "notes", nil
    c.ghosts, c.hidden = true, {}

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
      -- yOf is the height a pitch is at, between the rows when it is not
      -- one of them (a bend can end off the scale); nil out of range.
      s.yOf = function(pitch)
        local rows = s.rows
        for j = 1, #rows do
          if rows[j] == pitch then return (j - s.top + 0.5) * s.rowH end
          if rows[j + 1] and rows[j] > pitch and rows[j + 1] < pitch then
            local f = (rows[j] - pitch) / (rows[j] - rows[j + 1])
            return (j + f - s.top + 0.5) * s.rowH
          end
        end
      end
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
      -- The other melody channels' notes, faint and thin, bends and all.
      if self.ghosts and not drum then
        for oc = 1, #song.channels do
          local op = oc ~= self.channel and not songs.isDrum(song, oc) and not (self.hidden or {})[oc]
            and songs.patternAt(song, oc, self.bar)
          if op then
            g:color(look.mix(look.channelColor(song, oc), look.colors.roll, 0.55))
            local h = math.max(2, math.floor(s.rowH / 4))
            for _, n in ipairs(op.notes) do
              for _, q in ipairs(n.pitches) do
                for tk = songs.noteStart(n), songs.noteEnd(n) - 1 do
                  local _, bend = songs.shapeAt(n, tk + 0.5)
                  local y = s.yOf(q + bend)
                  if y then
                    local xa = math.floor(GUTTER + tk * s.colW) + (tk == songs.noteStart(n) and 2 or 0)
                    local xb = math.floor(GUTTER + (tk + 1) * s.colW) - (tk == songs.noteEnd(n) - 1 and 1 or 0)
                    g:fill(xa, math.floor(y - h / 2), math.max(1, xb - xa), h)
                  end
                end
              end
            end
          end
        end
      end
      -- Notes: as thick as they are loud, with their bends drawn over them.
      local mode = self.mode or "notes"
      local p = songs.patternAt(song, self.channel, self.bar)
      if p then
        for _, n in ipairs(p.notes) do
          local st, en = songs.noteStart(n), songs.noteEnd(n)
          local x1 = math.floor(GUTTER + st * s.colW) + 1
          local x2 = math.floor(GUTTER + en * s.colW)
          for _, q in ipairs(n.pitches) do
            local i = rowOf[q]
            if i then
              local y = (i - s.top) * s.rowH
              g:color(look.colors.noteBox)
              g:rect(x1, y + 1, math.max(3, x2 - x1), s.rowH - 2)
              g:color(colour)
              for tk = st, en - 1 do
                local vol = songs.shapeAt(n, tk + 0.5)
                local h = math.max(2, math.floor((s.rowH - 2) * (0.25 + 0.75 * vol / 100)))
                -- One piece a step, joined, so a note reads as one.
                local xa = math.floor(GUTTER + tk * s.colW) + (tk == st and 1 or 0)
                local xb = math.floor(GUTTER + (tk + 1) * s.colW)
                g:fill(xa, y + math.floor((s.rowH - h) / 2), math.max(1, xb - xa), h)
              end
              if mode == "notes" then
                -- The end, where a drag stretches it.
                g:color(look.colors.text)
                g:fill(x2 - 3, y + 3, 2, s.rowH - 6)
              end
            end
            -- A bend: a line from point to point, at the pitch it reaches.
            if songs.hasShape(n) or mode == "bend" then
              g:color(look.colors.bend)
              g:width(2)
              for k = 2, #n.points do
                local a, b = n.points[k - 1], n.points[k]
                local ya, yb = s.yOf(q + (a.pitchBend or 0)), s.yOf(q + (b.pitchBend or 0))
                if ya and yb and ((a.pitchBend or 0) ~= 0 or (b.pitchBend or 0) ~= 0 or mode == "bend") then
                  g:line(GUTTER + a.tick * s.colW, ya, GUTTER + b.tick * s.colW, yb)
                end
              end
              g:width(1)
            end
            -- Its points, to drag, in the modes that shape it.
            if mode ~= "notes" and rowOf[q] then
              for _, pt in ipairs(n.points) do
                local px = math.floor(GUTTER + pt.tick * s.colW)
                local py = mode == "bend" and s.yOf(q + (pt.pitchBend or 0)) or ((rowOf[q] - s.top + 0.5) * s.rowH)
                if py then
                  g:color(look.colors.text)
                  g:fill(px - 3, math.floor(py) - 3, 7, 7)
                  g:color(look.colors.roll)
                  g:fill(px - 2, math.floor(py) - 2, 5, 5)
                end
              end
            end
          end
        end
      else
        g:color(look.colors.dim)
        g:text(#s.rows > 0 and "Click to put a note here" or "", GUTTER, 0, W - GUTTER, H, "center")
      end
      if self.cursorTick then
        -- Where the next note played on the keyboard goes.
        local x = math.floor(GUTTER + self.cursorTick * s.colW)
        g:color(look.colors.record)
        for yy = 0, H, 8 do g:fill(x - 1, yy, 2, 4) end
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
      local mode = self.mode or "notes"
      if mode ~= "notes" then
        -- Shaping a note: the note sounding there, on any of its rows.
        local n = p and (songs.noteAt(p, tick, q) or songs.noteAt(p, tick))
        if not n then return end
        if button == 3 then
          s.drag = nil
          local i = songs.pointFor(n, tick)
          edit(self, function() songs.resetPoint(n, i) end)
          self:fire("onEditDone")
          return
        end
        local base = q
        local has = false
        for _, pq in ipairs(n.pitches) do if pq == q then has = true end end
        if not has then base = n.pitches[1] end
        s.drag = { mode = mode, note = n, y0 = y, base = base, moved = false }
        edit(self, function() s.drag.point = songs.pointFor(n, tick) end)
        local pt = n.points[s.drag.point]
        s.drag.v0, s.drag.b0 = pt.volume or 100, pt.pitchBend or 0
        self:fire("onHint", mode == "volume" and ("Volume %d%%"):format(s.drag.v0)
          or ("Bend %+d"):format(s.drag.b0))
        return
      end
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
        -- One step: dragging makes it longer.
        local made, new = songs.addNote(song, p, q, tick, 1)
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
      if d.mode == "volume" then
        local v = math.max(0, math.min(100, d.v0 + (d.y0 - y) * 100 / (5 * s.rowH)))
        if math.floor(v + 0.5) ~= d.note.points[d.point].volume then
          d.moved = true
          edit(self, function() songs.setPointVolume(d.note, d.point, v) end)
          self:fire("onHint", ("Volume %d%%"):format(d.note.points[d.point].volume))
        end
        return
      elseif d.mode == "bend" then
        local semis = q - d.base
        if semis ~= d.note.points[d.point].pitchBend then
          d.moved = true
          edit(self, function() songs.setPointBend(d.note, d.point, semis, songs.maxPitch(song, self.channel)) end)
          self:fire("onHint", ("Bend %+d"):format(d.note.points[d.point].pitchBend))
          self:fire("onNote", d.base + d.note.points[d.point].pitchBend)
        end
        return
      end
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
      if d.mode == "volume" or d.mode == "bend" then self:fire("onHint", nil) end
    end

    function c:onMouseWheel(dx, dy)
      s.top = math.max(1, s.top + dy * 2)
      self:redraw()
    end

    return c
  end,
}
