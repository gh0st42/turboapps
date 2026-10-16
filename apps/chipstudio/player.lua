-- Playing a song, with no GUI in it: rendered beside the program by the
-- beepbox module and played by the audio module, which are given to new,
-- so the tests can stand in for them.
--
--   local p = player.new { beepbox = require "beepbox", audio = require "audio" }
--   p:play(song, { from = 3 })        -- the song, from bar 3, round again
--   p:play(song, { bar = 3 })         -- bar 3 alone, over and over
--   p:changed(song)                    -- after an edit: heard from the next time round
--   local at = p:update()             -- from a timer: { bar = 3, tick = 5.5 } or nil
--   p:note(song, channel, pitch)      -- one note, as it is placed
--   p.prepare = function(s) ... end   -- the song as it is to be heard: mutes
--
-- An edit made while it plays is rendered again; the new sound goes in at
-- the same place when the song is as long as before, and at the end of the
-- loop when it is not, so nothing stops while it renders.

local songs = require "song"

local M = {}
M.__index = M

function M.new(deps)
  return setmetatable({ beepbox = deps.beepbox, audio = deps.audio, loop = true,
    version = 0, job = nil, voice = nil, mode = nil }, M)
end

-- what is the song to render for what is being played: as it is to be
-- heard (prepare, when set, silences channels), all of it or the bar alone.
local function what(self, s)
  if self.prepare then s = self.prepare(s) end
  if self.mode.bar then return songs.slice(s, self.mode.bar, self.mode.bar) end
  return s
end

local function start(self, s)
  self.version = self.version + 1
  self.job = { version = self.version, job = self.beepbox.start(songs.encode(what(self, s), true)),
    bpm = s.beatsPerMinute, beats = s.beatsPerBar, ticks = s.ticksPerBeat }
end

-- play starts playing: opts.bar plays that bar alone, round and round;
-- otherwise the song from bar opts.from (1 unless given).
function M:play(s, opts)
  self:stop()
  opts = opts or {}
  self.mode = { bar = opts.bar, from = opts.from or 1 }
  self.timing = { bpm = s.beatsPerMinute, beats = s.beatsPerBar, ticks = s.ticksPerBeat }
  start(self, s)
end

function M:stop()
  if self.voice then self.voice:stop() end
  self.voice, self.job, self.mode = nil, nil, nil
end

-- playing says whether it is playing, or about to once the render is done.
function M:playing() return self.mode ~= nil end

-- changed renders the song again after an edit, if it is playing.
function M:changed(s)
  if not self.mode then return end
  start(self, s)
end

-- setLoop says whether the song goes round again at its end.
function M:setLoop(on)
  self.loop = on and true or false
end

-- update takes in a finished render and says where playing has got to: the
-- bar (from 1) and the tick in it; nil when nothing plays. errors is set to
-- why when a render failed or there is no sound.
function M:update()
  local j = self.job
  if j and j.job:done() then
    self.job = nil
    local sound, why = j.job:result()
    if not sound then
      self.error = tostring(why)
      self:stop()
      return nil
    end
    self.timing = { bpm = j.bpm, beats = j.beats, ticks = j.ticks }
    if self.voice and self.voice:playing() then
      -- The same length: the same place in it; otherwise at the loop's end.
      local same = self.length and math.abs(self.length - sound.seconds) < 1e-6
      self.voice:replace(sound, same and "now" or "loop")
    else
      local from = 0
      if not self.mode.bar then
        from = (self.mode.from - 1) * j.beats * 60 / j.bpm
        if from >= sound.seconds then from = 0 end
      end
      local v, err = self.audio.play(sound, { loop = self.loop or self.mode.bar ~= nil, from = from })
      if not v then
        self.error = tostring(err)
        self:stop()
        return nil
      end
      self.voice = v
    end
    self.length = sound.seconds
  end
  if not self.mode then return nil end
  if not self.voice then return { bar = self.mode.bar or self.mode.from, tick = 0, waiting = true } end
  if not self.voice:playing() then
    self:stop()
    return nil
  end
  local t = self.timing
  local beats = self.voice:position() * t.bpm / 60
  local barIndex = math.floor(beats / t.beats)
  local tick = (beats - barIndex * t.beats) * t.ticks
  return { bar = self.mode.bar or (barIndex + 1), tick = tick }
end

-- note sounds pitch on channel c's instrument, as the song would play it.
function M:note(s, c, pitch)
  local sound = self.beepbox.note(songs.encode(s, true), c, 1, pitch)
  if not sound then return end
  if self.preview then self.preview:stop() end
  self.preview = self.audio.play(sound, { volume = 0.9 })
end

return M
