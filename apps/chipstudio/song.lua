-- A song, with no GUI in it: BeepBox's song JSON (what BeepBox exports and
-- fz keeps in assets/bgm), read into tables, changed, and written back with
-- everything it does not touch kept as it was.
--
-- A song has channels (pitch ones, then drum ones), each with instruments,
-- patterns and a sequence: which pattern it plays in each bar, 0 for none.
-- A pattern is a list of notes; a note is a span of ticks with up to four
-- pitches (a chord), its points giving where it starts and ends. Pitches
-- count from the song's key; a drum channel's are its twelve drums.
--
-- Channels, bars and pitches count from 1 here, as Lua does, except a
-- note's pitch and tick, which are what the file says.

local json = require "json"
local beepbox = require "beepbox"

local M = {}

-- ORDER is how the keys of a song are written: as BeepBox writes them.
M.ORDER = {}
for i, k in ipairs { "format", "version", "name", "scale", "key", "introBars", "loopBars",
  "beatsPerBar", "ticksPerBeat", "beatsPerMinute", "layeredInstruments", "patternInstruments",
  "channels", "type", "name", "instruments", "patterns", "sequence", "octaveScrollBar",
  "notes", "pitches", "points", "tick", "pitchBend", "volume", "continuesLastPattern" } do
  M.ORDER[k] = M.ORDER[k] or i
end

M.MAX_NOTES_IN_CHORD = 4
M.MAX_BARS = 128
M.NOTE_NAMES = { "C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B" }

local obj = json.object

local function point(tick)
  return obj { tick = tick, pitchBend = 0, volume = 100 }
end

---------------------------------------------------------------- presets

local presetCache

-- presets are BeepBox's named instruments, those for drum channels apart.
function M.presets()
  if not presetCache then
    presetCache = beepbox.presets()
    for _, p in ipairs(presetCache) do p.settings = json.decode(p.settings) end
  end
  return presetCache
end

function M.preset(name, drum)
  for _, p in ipairs(M.presets()) do
    if p.name == name and p.noise == (drum and true or false) then return p end
  end
end

-- categories are the groups that have presets for a kind of channel.
function M.categories(drum)
  local out, seen = {}, {}
  for _, p in ipairs(M.presets()) do
    if p.noise == (drum and true or false) and not seen[p.category] then
      seen[p.category] = true
      out[#out + 1] = p.category
    end
  end
  return out
end

function M.presetsIn(category, drum)
  local out = {}
  for _, p in ipairs(M.presets()) do
    if p.category == category and p.noise == (drum and true or false) then out[#out + 1] = p end
  end
  return out
end

---------------------------------------------------------------- a song

-- What a new song starts with: something that sounds as soon as a note is
-- put down, on every channel.
M.STARTERS = {
  { kind = "pitch", name = "Lead", preset = "square lead", octave = 4 },
  { kind = "pitch", name = "Harmony", preset = "triangle wave", octave = 3 },
  { kind = "pitch", name = "Bass", preset = "FM bass", octave = 2 },
  { kind = "drum", name = "Drums", preset = "standard drumset", octave = 0 },
}

local function newChannel(kind, preset, bars, octave)
  local p = preset and M.preset(preset, kind == "drum")
  local inst = p and json.copy(p.settings) or obj { type = kind == "drum" and "noise" or "chip", volume = 100 }
  local seq = {}
  for i = 1, bars do seq[i] = 0 end
  return obj { type = kind, instruments = { inst }, patterns = {}, sequence = seq,
    octaveScrollBar = octave or 3 }
end

-- new is a song of eight bars of four beats at 120, in C major, with a lead,
-- a harmony, a bass and drums.
function M.new()
  local s = obj { format = "BeepBox", version = 9, scale = "normal :)", key = "C",
    introBars = 0, loopBars = 8, beatsPerBar = 4, ticksPerBeat = 4, beatsPerMinute = 120,
    layeredInstruments = false, patternInstruments = false, channels = {} }
  for i, st in ipairs(M.STARTERS) do
    local ch = newChannel(st.kind, st.preset, 8, st.octave)
    ch.name = st.name
    s.channels[i] = ch
  end
  return s
end

-- normalize fills in what a song read from elsewhere may leave out, and
-- makes every channel's sequence as long as the song.
function M.normalize(s)
  s.version = s.version or 9
  s.scale = s.scale or "normal :)"
  s.key = s.key or "C"
  s.beatsPerBar = tonumber(s.beatsPerBar) or 4
  s.ticksPerBeat = tonumber(s.ticksPerBeat) or 4
  s.beatsPerMinute = tonumber(s.beatsPerMinute) or 120
  s.introBars = tonumber(s.introBars) or 0
  s.channels = s.channels or {}
  local bars = 1
  for _, ch in ipairs(s.channels) do
    ch.type = ch.type or "pitch"
    ch.instruments = ch.instruments or {}
    if #ch.instruments == 0 then
      ch.instruments[1] = obj { type = ch.type == "drum" and "noise" or "chip", volume = 100 }
    end
    ch.patterns = ch.patterns or {}
    ch.sequence = ch.sequence or {}
    bars = math.max(bars, #ch.sequence)
    for _, p in ipairs(ch.patterns) do p.notes = p.notes or {} end
  end
  for _, ch in ipairs(s.channels) do
    for b = #ch.sequence + 1, bars do ch.sequence[b] = 0 end
  end
  s.loopBars = tonumber(s.loopBars) or bars
  return s
end

-- decode reads a song; nil and why for what is not a BeepBox song.
function M.decode(text)
  local s, err = json.decode(text)
  if not s then return nil, err end
  if type(s) ~= "table" or type(s.format) ~= "string" or s.format:lower() ~= "beepbox" then
    return nil, "this is not a BeepBox song"
  end
  return M.normalize(s)
end

-- encode writes a song as BeepBox's JSON: spread out to be read, or in one
-- line for the synthesiser.
function M.encode(s, compact)
  return json.encode(s, not compact and "  " or nil, M.ORDER) .. (compact and "" or "\n")
end

function M.copy(s) return json.copy(s) end

---------------------------------------------------------------- bars, beats, ticks

function M.bars(s)
  local n = 1
  for _, ch in ipairs(s.channels) do n = math.max(n, #ch.sequence) end
  return n
end

-- barTicks is how many ticks a bar has: its beats times the beat's steps.
function M.barTicks(s) return s.beatsPerBar * s.ticksPerBeat end

function M.secondsPerBar(s) return s.beatsPerBar * 60 / s.beatsPerMinute end

function M.isDrum(s, c) return s.channels[c] and s.channels[c].type == "drum" end

-- channelLabel is what a channel is called: its own name, or its kind and
-- number.
function M.channelLabel(s, c)
  local ch = s.channels[c]
  if not ch then return "" end
  if type(ch.name) == "string" and ch.name ~= "" then return ch.name end
  local n = 0
  for i = 1, c do if s.channels[i].type == ch.type then n = n + 1 end end
  return (ch.type == "drum" and "Drums " or "Channel ") .. n
end

---------------------------------------------------------------- patterns

-- patternAt is the pattern channel c plays in bar b, and its number; nil
-- when it plays none.
function M.patternAt(s, c, b)
  local ch = s.channels[c]
  local n = ch and ch.sequence[b] or 0
  if n and n > 0 then
    while #ch.patterns < n do ch.patterns[#ch.patterns + 1] = obj { notes = {} } end
    return ch.patterns[n], n
  end
end

-- newPattern adds an empty pattern to channel c, and is its number.
local function newPattern(s, c)
  local ch = s.channels[c]
  local p = obj { notes = {} }
  if s.patternInstruments then p.instruments = { 1 } end
  ch.patterns[#ch.patterns + 1] = p
  return #ch.patterns
end

-- ensurePattern is the pattern of channel c in bar b, made when there is
-- none, so a note can be put there.
function M.ensurePattern(s, c, b)
  local p, n = M.patternAt(s, c, b)
  if p then return p, n end
  n = newPattern(s, c)
  s.channels[c].sequence[b] = n
  return s.channels[c].patterns[n], n
end

-- sharedBars are the other bars channel c plays the same pattern in as in
-- bar b: what an edit there changes too.
function M.sharedBars(s, c, b)
  local ch = s.channels[c]
  local n = ch and ch.sequence[b] or 0
  local out = {}
  if n == 0 then return out end
  for i, m in ipairs(ch.sequence) do
    if i ~= b and m == n then out[#out + 1] = i end
  end
  return out
end

-- makeUnique gives bar b of channel c a copy of its pattern of its own.
function M.makeUnique(s, c, b)
  local p = M.patternAt(s, c, b)
  if not p or #M.sharedBars(s, c, b) == 0 then return false end
  local ch = s.channels[c]
  ch.patterns[#ch.patterns + 1] = json.copy(p)
  ch.sequence[b] = #ch.patterns
  return true
end

-- setPattern makes channel c play pattern n (0 for none) in bar b.
function M.setPattern(s, c, b, n)
  local ch = s.channels[c]
  if not ch then return end
  n = math.max(0, math.floor(n))
  while #ch.patterns < n do ch.patterns[#ch.patterns + 1] = obj { notes = {} } end
  ch.sequence[b] = n
end

-- usedPatterns says how many patterns of channel c have notes.
function M.patternHasNotes(s, c, n)
  local p = s.channels[c] and s.channels[c].patterns[n]
  return p ~= nil and #p.notes > 0
end

---------------------------------------------------------------- notes

function M.noteStart(n) return n.points[1].tick end
function M.noteEnd(n) return n.points[#n.points].tick end

local function sortNotes(p)
  table.sort(p.notes, function(a, b) return M.noteStart(a) < M.noteStart(b) end)
end

local function hasPitch(n, pitch)
  for i, q in ipairs(n.pitches) do if q == pitch then return i end end
end

-- noteAt is the note of a pattern sounding at tick, and with pitch when one
-- is given: the one a click there means.
function M.noteAt(p, tick, pitch)
  for i, n in ipairs(p.notes) do
    if tick >= M.noteStart(n) and tick < M.noteEnd(n) and (pitch == nil or hasPitch(n, pitch)) then
      return n, i
    end
  end
end

-- retime moves a note's points to a new start and end, keeping the shape of
-- its volume and bends between them.
local function retime(n, start, stop)
  local s0, e0 = M.noteStart(n), M.noteEnd(n)
  local len0 = math.max(1, e0 - s0)
  local last = nil
  for i, pt in ipairs(n.points) do
    local t
    if i == 1 then t = start
    elseif i == #n.points then t = stop
    else t = start + math.floor((pt.tick - s0) * (stop - start) / len0 + 0.5) end
    if last and t <= last then t = last + 1 end
    pt.tick = t
    last = t
  end
  -- Points squeezed past the end are dropped, keeping the last.
  while #n.points > 2 and n.points[#n.points - 1].tick >= stop do table.remove(n.points, #n.points - 1) end
  n.points[#n.points].tick = math.max(stop, n.points[#n.points - 1].tick + 1)
end

-- room is how far a note from start may run before the next one, or the
-- end of the bar.
local function room(s, p, start, except)
  local limit = M.barTicks(s)
  for _, n in ipairs(p.notes) do
    if n ~= except and M.noteStart(n) >= start and M.noteStart(n) < limit then limit = M.noteStart(n) end
  end
  return limit
end

-- addNote puts pitch down at tick, length ticks long: in a note already
-- sounding there, as one more pitch of its chord, or else as a note of its
-- own, as long as there is room for before the next note. It is the note,
-- and whether it is new; nil when there is no room.
function M.addNote(s, p, pitch, tick, length)
  local barTicks = M.barTicks(s)
  if tick < 0 or tick >= barTicks then return nil end
  local n = M.noteAt(p, tick)
  if n then
    if hasPitch(n, pitch) then return n, false end
    if #n.pitches >= M.MAX_NOTES_IN_CHORD then return nil end
    n.pitches[#n.pitches + 1] = pitch
    table.sort(n.pitches)
    return n, false
  end
  local stop = math.min(tick + math.max(1, length), room(s, p, tick))
  if stop <= tick then return nil end
  n = obj { pitches = { pitch }, points = { point(tick), point(stop) } }
  p.notes[#p.notes + 1] = n
  sortNotes(p)
  return n, true
end

-- removePitch takes a pitch out of a note, and the note out of the pattern
-- when it was its last.
function M.removePitch(p, n, pitch)
  local i = hasPitch(n, pitch)
  if i and #n.pitches > 1 then
    table.remove(n.pitches, i)
    return
  end
  for j, m in ipairs(p.notes) do
    if m == n then table.remove(p.notes, j) return end
  end
end

-- resize makes a note end at stop, as far as there is room.
function M.resize(s, p, n, stop)
  local start = M.noteStart(n)
  stop = math.max(start + 1, math.min(stop, room(s, p, start + 1, n)))
  retime(n, start, stop)
end

-- move takes a note to start at tick, its pitches by semitones, as far as
-- the bar, the notes beside it and the range of pitches allow.
function M.move(s, p, n, tick, semitones, maxPitch)
  local len = M.noteEnd(n) - M.noteStart(n)
  local barTicks = M.barTicks(s)
  tick = math.max(0, math.min(tick, barTicks - len))
  -- Not over another note: stop beside it.
  for _, m in ipairs(p.notes) do
    if m ~= n then
      local ms, me = M.noteStart(m), M.noteEnd(m)
      if tick < me and tick + len > ms then
        if tick + len / 2 < (ms + me) / 2 then tick = ms - len else tick = me end
      end
    end
  end
  tick = math.max(0, math.min(tick, barTicks - len))
  for _, m in ipairs(p.notes) do
    if m ~= n and tick < M.noteEnd(m) and tick + len > M.noteStart(m) then return false end
  end
  local lo, hi = math.huge, -math.huge
  for _, q in ipairs(n.pitches) do lo, hi = math.min(lo, q), math.max(hi, q) end
  semitones = math.max(-lo, math.min(semitones, maxPitch - hi))
  for i, q in ipairs(n.pitches) do n.pitches[i] = q + semitones end
  retime(n, tick, tick + len)
  sortNotes(p)
  return true
end

---------------------------------------------------------------- a note's shape

-- A note's points say how loud it is (volume, 0 to 100) and how far it is
-- bent (pitchBend, in semitones) along it, from its start to its end; in
-- between, the synthesiser goes straight from one point to the next.

local function lerp(a, b, f) return a + (b - a) * f end

-- shapeAt is a note's volume and bend at a tick, between its points.
function M.shapeAt(n, tick)
  local pts = n.points
  if tick <= pts[1].tick then return pts[1].volume or 100, pts[1].pitchBend or 0 end
  for i = 2, #pts do
    local a, b = pts[i - 1], pts[i]
    if tick <= b.tick then
      local f = (b.tick > a.tick) and (tick - a.tick) / (b.tick - a.tick) or 0
      return lerp(a.volume or 100, b.volume or 100, f), lerp(a.pitchBend or 0, b.pitchBend or 0, f)
    end
  end
  local last = pts[#pts]
  return last.volume or 100, last.pitchBend or 0
end

-- pointFor is the point of a note an edit at tick means: the one there, or
-- its start or end when tick is next to them, or else a new point there,
-- put in where the shape already is so nothing changes until it is moved.
function M.pointFor(n, tick)
  local pts = n.points
  local start, stop = pts[1].tick, pts[#pts].tick
  if tick <= start then return 1 end
  if tick >= stop - 1 then return #pts end
  for i, pt in ipairs(pts) do
    if pt.tick == tick then return i end
  end
  local vol, bend = M.shapeAt(n, tick)
  for i = 2, #pts do
    if tick < pts[i].tick then
      table.insert(pts, i, obj { tick = tick, pitchBend = math.floor(bend + 0.5), volume = math.floor(vol + 0.5) })
      return i
    end
  end
  return #pts
end

function M.setPointVolume(n, i, v)
  n.points[i].volume = math.max(0, math.min(100, math.floor(v + 0.5)))
end

-- setPointBend bends point i of a note by semitones, as far as the range of
-- pitches allows for every pitch of it.
function M.setPointBend(n, i, semis, maxPitch)
  local lo, hi = math.huge, -math.huge
  for _, q in ipairs(n.pitches) do lo, hi = math.min(lo, q), math.max(hi, q) end
  n.points[i].pitchBend = math.max(-lo, math.min(math.floor(semis + 0.5), maxPitch - hi))
end

-- resetPoint puts a point back: full volume and no bend at a note's ends,
-- and a point between them taken out.
function M.resetPoint(n, i)
  if i > 1 and i < #n.points then
    table.remove(n.points, i)
  else
    n.points[i].volume, n.points[i].pitchBend = 100, 0
  end
end

-- flatten takes a note's shape away: two points, full volume, no bend.
function M.flatten(n)
  local start, stop = M.noteStart(n), M.noteEnd(n)
  n.points = { point(start), point(stop) }
end

-- hasShape says whether a note is anything but full and straight.
function M.hasShape(n)
  if #n.points > 2 then return true end
  for _, pt in ipairs(n.points) do
    if (pt.volume or 100) ~= 100 or (pt.pitchBend or 0) ~= 0 then return true end
  end
  return false
end

---------------------------------------------------------------- rows, names

function M.scaleIndex(name)
  for i, sc in ipairs(beepbox.scales) do if sc.name == name then return i end end
  return #beepbox.scales -- "expert": every semitone
end

function M.keyIndex(name)
  for i, k in ipairs(beepbox.keys) do if k.name == name then return i end end
  return 1
end

function M.maxPitch(s, c) return M.isDrum(s, c) and beepbox.drums - 1 or beepbox.maxPitch end

-- inScale says whether a pitch is one of the song's scale's.
function M.inScale(s, pitch)
  local notes = beepbox.scales[M.scaleIndex(s.scale)].notes
  return notes[pitch % 12 + 1]
end

-- rows are the pitches the roll shows for channel c in bar b, top first:
-- those in the scale, and any a note there already has, which would
-- otherwise be out of reach. A drum channel shows all its drums.
function M.rows(s, c, b)
  local out = {}
  local top = M.maxPitch(s, c)
  if M.isDrum(s, c) then
    for q = top, 0, -1 do out[#out + 1] = q end
    return out
  end
  local used = {}
  local p = M.patternAt(s, c, b)
  if p then
    for _, n in ipairs(p.notes) do for _, q in ipairs(n.pitches) do used[q] = true end end
  end
  for q = top, 0, -1 do
    if M.inScale(s, q) or used[q] then out[#out + 1] = q end
  end
  return out
end

-- pitchName is what a row is called: "C4", or "Drum 3" on a drum channel.
function M.pitchName(s, c, pitch)
  if M.isDrum(s, c) then return "Drum " .. (pitch + 1) end
  local key = M.keyIndex(s.key) - 1
  local abs = pitch + key
  return M.NOTE_NAMES[abs % 12 + 1] .. math.floor(abs / 12)
end

-- isKey says whether a pitch is the song's key, in any octave.
function M.isKey(pitch) return pitch % 12 == 0 end

-- scaleFrom is the pitches a keyboard row plays: count of them, the
-- scale's notes going up from the first at or above from, so every key is
-- in tune. A drum channel's are its drums.
function M.scaleFrom(s, c, from, count)
  local out = {}
  local top = M.maxPitch(s, c)
  local q = math.max(0, from)
  while #out < count and q <= top do
    if M.isDrum(s, c) or M.inScale(s, q) then out[#out + 1] = q end
    q = q + 1
  end
  return out
end

---------------------------------------------------------------- instruments

function M.instrument(s, c)
  local ch = s.channels[c]
  return ch and ch.instruments[1]
end

-- instrumentName is the preset a channel's instrument is, or nil for one of
-- its own.
function M.instrumentName(s, c)
  local inst = M.instrument(s, c)
  if not inst then return nil end
  return beepbox.match(json.encode(inst))
end

-- setPreset gives channel c a preset's instrument, keeping its volume.
function M.setPreset(s, c, preset)
  local ch = s.channels[c]
  local old = ch.instruments[1]
  local inst = json.copy(preset.settings)
  if old and old.volume ~= nil and preset.settings.volume == old.volume then inst.volume = old.volume end
  ch.instruments[1] = inst
end

function M.volume(s, c)
  local inst = M.instrument(s, c)
  return inst and tonumber(inst.volume) or 100
end

function M.setVolume(s, c, v)
  local inst = M.instrument(s, c)
  if inst then inst.volume = math.max(0, math.min(100, math.floor(v + 0.5))) end
end

---------------------------------------------------------------- the song's shape

-- setBars makes the song n bars long, adding empty bars or taking them off
-- the end, and keeps the loop inside it.
function M.setBars(s, n)
  n = math.max(1, math.min(M.MAX_BARS, math.floor(n)))
  for _, ch in ipairs(s.channels) do
    for b = #ch.sequence + 1, n do ch.sequence[b] = 0 end
    for b = #ch.sequence, n + 1, -1 do ch.sequence[b] = nil end
  end
  s.introBars = math.min(s.introBars, n - 1)
  s.loopBars = math.max(1, math.min(s.loopBars, n - s.introBars))
end

-- insertBar puts an empty bar in before bar at.
function M.insertBar(s, at)
  if M.bars(s) >= M.MAX_BARS then return false end
  for _, ch in ipairs(s.channels) do table.insert(ch.sequence, at, 0) end
  if at <= s.introBars + s.loopBars then s.loopBars = s.loopBars + 1 end
  return true
end

-- duplicateBar plays bar b again after it: the same patterns, so a change to
-- either is heard in both.
function M.duplicateBar(s, b)
  if not M.insertBar(s, b + 1) then return false end
  for _, ch in ipairs(s.channels) do ch.sequence[b + 1] = ch.sequence[b] end
  return true
end

function M.removeBar(s, b)
  if M.bars(s) <= 1 then return false end
  for _, ch in ipairs(s.channels) do table.remove(ch.sequence, b) end
  if b <= s.introBars then s.introBars = s.introBars - 1
  elseif b <= s.introBars + s.loopBars then s.loopBars = math.max(1, s.loopBars - 1) end
  M.setBars(s, M.bars(s))
  return true
end

-- clearBar makes every channel play nothing in bar b.
function M.clearBar(s, b)
  for _, ch in ipairs(s.channels) do ch.sequence[b] = 0 end
end

-- addChannel adds a channel of a kind, with a preset: a pitch channel after
-- the last pitch channel, a drum channel at the end, as BeepBox keeps them.
-- It is the new channel's number, or nil when there are as many as there
-- can be.
function M.addChannel(s, kind, preset)
  local count, lastPitch = 0, 0
  for i, ch in ipairs(s.channels) do
    if ch.type == kind then count = count + 1 end
    if ch.type == "pitch" then lastPitch = i end
  end
  local max = kind == "drum" and beepbox.noiseChannels or beepbox.pitchChannels
  if count >= max then return nil end
  local ch = newChannel(kind, preset or (kind == "drum" and "standard drumset" or "square wave"), M.bars(s), 3)
  local at = kind == "drum" and #s.channels + 1 or lastPitch + 1
  table.insert(s.channels, at, ch)
  return at
end

function M.removeChannel(s, c)
  if #s.channels <= 1 or not s.channels[c] then return false end
  table.remove(s.channels, c)
  return true
end

-- setBeats makes a bar n beats long. Notes that would be past its end are
-- cut short, or taken out when they start there: the synthesiser would
-- still play them, and nothing could reach them to edit.
function M.setBeats(s, n)
  s.beatsPerBar = math.max(1, math.min(16, math.floor(n)))
  local limit = M.barTicks(s)
  for _, ch in ipairs(s.channels) do
    for _, p in ipairs(ch.patterns) do
      for i = #p.notes, 1, -1 do
        local note = p.notes[i]
        if M.noteStart(note) >= limit then
          table.remove(p.notes, i)
        elseif M.noteEnd(note) > limit then
          retime(note, M.noteStart(note), limit)
        end
      end
    end
  end
end

-- setLoop makes the loop bars from to to: those before are played once.
function M.setLoop(s, from, to)
  local bars = M.bars(s)
  from = math.max(1, math.min(from, bars))
  to = math.max(from, math.min(to, bars))
  s.introBars, s.loopBars = from - 1, to - from + 1
end

---------------------------------------------------------------- playing

-- lastBar is the last bar anything plays in: where a song played through
-- ends.
function M.lastBar(s)
  local last = 0
  for _, ch in ipairs(s.channels) do
    for b, n in ipairs(ch.sequence) do if n > 0 and b > last then last = b end end
  end
  return last
end

-- slice is a song of bars from to to of s, for playing a part of it over
-- and over; with nothing playing in them, the first bar plays nothing for
-- as long as a bar takes.
function M.slice(s, from, to)
  local t = json.copy(s)
  for _, ch in ipairs(t.channels) do
    local seq = {}
    for b = from, to do seq[#seq + 1] = ch.sequence[b] or 0 end
    ch.sequence = seq
  end
  t.introBars, t.loopBars = 0, to - from + 1
  if M.lastBar(t) < to - from + 1 then
    -- The synthesiser stops after the last bar with a pattern, so give the
    -- last bar one, empty if need be.
    local ch = t.channels[1]
    local last = #ch.sequence
    if ch.sequence[last] == 0 then
      ch.patterns[#ch.patterns + 1] = obj { notes = {} }
      ch.sequence[last] = #ch.patterns
    end
  end
  return t
end

-- withMutes is the song as it is heard with some channels silenced: muted
-- ones, or all but the soloed ones when any are. A silenced channel plays
-- an empty pattern where it played one, so the song is as long as before.
function M.withMutes(s, muted, soloed)
  local anySolo = false
  for c in pairs(soloed or {}) do if soloed[c] then anySolo = true end end
  local quiet = {}
  for c = 1, #s.channels do
    quiet[c] = (muted and muted[c]) or (anySolo and not soloed[c])
  end
  local any = false
  for c = 1, #s.channels do if quiet[c] then any = true end end
  if not any then return s end
  local t = json.copy(s)
  for c, ch in ipairs(t.channels) do
    if quiet[c] then
      ch.patterns[#ch.patterns + 1] = obj { notes = {} }
      local empty = #ch.patterns
      for b, n in ipairs(ch.sequence) do if n > 0 then ch.sequence[b] = empty end end
    end
  end
  return t
end

---------------------------------------------------------------- undo

-- history keeps whole songs, as fz's editor does: a song is a few
-- kilobytes, and a copy cannot drift from the song as an undone edit can.
function M.history(limit)
  local h = { past = {}, future = {}, limit = limit or 100 }
  -- save keeps the song as it is before a change.
  function h:save(s)
    self.past[#self.past + 1] = json.copy(s)
    if #self.past > self.limit then table.remove(self.past, 1) end
    self.future = {}
  end
  function h:undo(s)
    local prev = table.remove(self.past)
    if not prev then return nil end
    self.future[#self.future + 1] = json.copy(s)
    return prev
  end
  function h:redo(s)
    local nxt = table.remove(self.future)
    if not nxt then return nil end
    self.past[#self.past + 1] = json.copy(s)
    return nxt
  end
  function h:canUndo() return #self.past > 0 end
  function h:canRedo() return #self.future > 0 end
  function h:clear() self.past, self.future = {}, {} end
  return h
end

---------------------------------------------------------------- files

M.EXTENSION = ".json"

-- fzSongs is the assets/bgm folder of the fz project a path is in, if it is
-- in one.
function M.fzFolder(path)
  local lfs = require "lfs"
  local dir = path
  for _ = 1, 8 do
    if lfs.attributes(dir .. "/assets/bgm", "mode") == "directory" then return dir .. "/assets/bgm" end
    local up = dir:match("^(.*)/[^/]+$")
    if not up or up == "" or up == dir then break end
    dir = up
  end
end

return M
