-- tlua -p apps/chipstudio -p tests tests/chipstudio_test.lua
--
-- The song model against BeepBox's JSON, the player with stand-ins for the
-- synthesiser and the speakers, and the form, headless.

local t = require "testing"
local json = require "json"
local songs = require "song"
local beepbox = require "beepbox"
local lfs = require "lfs"
local test, eq, ok = t.test, t.eq, t.ok

local root = os.tmpname()
os.remove(root)
lfs.mkdir(root)

local function bar(s, c, b) return (songs.patternAt(s, c, b)) end

---------------------------------------------------------------- JSON

test("JSON keeps empty arrays and objects apart, and its order", function()
  local v = json.decode('{"b":[],"a":{},"c":[1,2.5,"x",true,null]}')
  eq(json.encode(v), '{"a":{},"b":[],"c":[1,2.5,"x",true,null]}')
  eq(json.encode(json.copy(v)), json.encode(v), "a copy too")
  eq(json.encode(json.object { z = 1, a = 2 }, nil, { z = 1 }), '{"z":1,"a":2}')
  eq(json.encode(0.1), "0.1")
end)

---------------------------------------------------------------- a song

test("a new song is ready to play", function()
  local s = songs.new()
  eq(s.format, "BeepBox"); eq(songs.bars(s), 8); eq(#s.channels, 4)
  eq(songs.channelLabel(s, 1), "Lead"); eq(songs.channelLabel(s, 4), "Drums")
  ok(songs.isDrum(s, 4) and not songs.isDrum(s, 1))
  eq(songs.instrumentName(s, 1), "square lead")
  eq(songs.instrumentName(s, 4), "standard drumset")
  eq(songs.barTicks(s), 16)
  -- What it writes, BeepBox reads: the synthesiser takes it.
  local again = assert(songs.decode(songs.encode(s)))
  eq(songs.encode(again), songs.encode(s), "written the same way twice")
  local sound = assert(beepbox.render(songs.encode(songs.slice(s, 1, 1), true)))
  ok(sound.seconds > 1.9 and sound.seconds < 2.1, "a bar of silence: " .. sound.seconds)
end)

test("a song from elsewhere keeps what it does not know", function()
  local text = [[{"format":"BeepBox","version":9,"scale":"easy :)","key":"D","introBars":0,"loopBars":2,
    "beatsPerBar":8,"ticksPerBeat":4,"beatsPerMinute":150,"layeredInstruments":false,
    "patternInstruments":false,"reverb":3,"channels":[{"type":"pitch","instruments":[{"type":"chip",
    "volume":80,"eqFilter":[],"effects":["vibrato"],"vibrato":"light","wave":"square"}],
    "patterns":[{"notes":[{"pitches":[12],"points":[{"tick":0,"pitchBend":0,"volume":100},
    {"tick":2,"pitchBend":-1,"volume":60},{"tick":4,"pitchBend":0,"volume":100}]}]}],
    "sequence":[1,1,0],"octaveScrollBar":3}]}]]
  local s = assert(songs.decode(text))
  eq(s.reverb, 3); eq(songs.bars(s), 3)
  local back = json.decode(songs.encode(s))
  eq(back.reverb, 3)
  eq(back.channels[1].instruments[1].vibrato, "light")
  eq(json.encode(back.channels[1].instruments[1].eqFilter), "[]")
  eq(back.channels[1].patterns[1].notes[1].points[2].pitchBend, -1)
  eq(songs.decode('{"format":"Other"}'), nil)
  eq(select(2, songs.decode("{")) ~= nil, true)
end)

---------------------------------------------------------------- patterns and notes

test("a note goes into a bar, a chord into a note", function()
  local s = songs.new()
  eq(bar(s, 1, 1), nil, "nothing plays there yet")
  local p = songs.ensurePattern(s, 1, 1)
  eq(s.channels[1].sequence[1], 1)
  local n, new = songs.addNote(s, p, 48, 0, 4)
  ok(new); eq(songs.noteStart(n), 0); eq(songs.noteEnd(n), 4)
  -- Inside a note that is sounding: one more pitch of it.
  local same, new2 = songs.addNote(s, p, 52, 2, 4)
  eq(same, n); eq(new2, false); eq(table.concat(n.pitches, ","), "48,52")
  for q = 53, 60 do songs.addNote(s, p, q, 1, 4) end
  eq(#n.pitches, 4, "four pitches at most")
  -- Before the next note: only as long as there is room.
  local later = songs.addNote(s, p, 50, 8, 4)
  local before = songs.addNote(s, p, 50, 6, 8)
  eq(songs.noteEnd(before), 8, "stops where the next begins")
  eq(songs.addNote(s, p, 50, 16, 4), nil, "past the bar")
  local last = songs.addNote(s, p, 40, 14, 8)
  eq(songs.noteEnd(last), 16, "ends with the bar")
  eq(#p.notes, 4)
  -- Taking pitches out, then the note.
  songs.removePitch(p, n, 48)
  eq(#n.pitches, 3)
  songs.removePitch(p, later, 50)
  eq(#p.notes, 3)
end)

test("notes move and stretch without running into others", function()
  local s = songs.new()
  local p = songs.ensurePattern(s, 1, 1)
  local a = songs.addNote(s, p, 48, 0, 4)
  local b = songs.addNote(s, p, 50, 8, 4)
  songs.resize(s, p, a, 12)
  eq(songs.noteEnd(a), 8, "up to the next note")
  songs.resize(s, p, a, 0)
  eq(songs.noteEnd(a), 1, "a tick at least")
  songs.resize(s, p, a, 4)
  ok(songs.move(s, p, a, 2, 3, beepbox.maxPitch))
  eq(songs.noteStart(a), 2); eq(a.pitches[1], 51)
  songs.move(s, p, a, 7, 0, beepbox.maxPitch)
  eq(songs.noteStart(a), 4, "stops beside the next note")
  songs.move(s, p, a, -5, 100, beepbox.maxPitch)
  eq(songs.noteStart(a), 0); eq(a.pitches[1], beepbox.maxPitch, "in the range of pitches")
  -- A note with a shape keeps it when it is stretched.
  local c = songs.addNote(s, p, 40, 12, 4)
  table.insert(c.points, 2, json.object { tick = 14, pitchBend = 0, volume = 50 })
  songs.resize(s, p, c, 16)
  eq(c.points[2].tick, 14); eq(c.points[2].volume, 50)
  eq(songs.noteEnd(b), 12)
end)

test("bars that share a pattern, and one made unique", function()
  local s = songs.new()
  local p = songs.ensurePattern(s, 1, 1)
  songs.addNote(s, p, 48, 0, 4)
  ok(songs.duplicateBar(s, 1))
  eq(songs.bars(s), 9); eq(s.channels[1].sequence[2], 1)
  local shared = songs.sharedBars(s, 1, 1)
  eq(#shared, 1); eq(shared[1], 2)
  ok(songs.makeUnique(s, 1, 2))
  eq(s.channels[1].sequence[2], 2); eq(#songs.sharedBars(s, 1, 1), 0)
  eq(#bar(s, 1, 2).notes, 1, "a copy of its notes")
  songs.addNote(s, bar(s, 1, 2), 60, 8, 2)
  eq(#bar(s, 1, 1).notes, 1, "the first bar is as it was")
  songs.clearBar(s, 2)
  eq(s.channels[1].sequence[2], 0)
  ok(songs.removeBar(s, 2)); eq(songs.bars(s), 8)
  songs.setBars(s, 3)
  eq(songs.bars(s), 3); eq(s.loopBars, 3)
  ok(songs.insertBar(s, 1)); eq(s.channels[1].sequence[2], 1, "the old first bar moved along")
end)

test("channels: pitch ones before drum ones", function()
  local s = songs.new()
  local c = songs.addChannel(s, "pitch")
  eq(c, 4, "after the last pitch channel")
  eq(s.channels[5].type, "drum")
  eq(#s.channels[4].sequence, 8)
  eq(songs.addChannel(s, "drum"), 6)
  ok(songs.removeChannel(s, 6))
  eq(#s.channels, 5)
end)

test("rows are the scale's, and names follow the key", function()
  local s = songs.new() -- C major
  local rows = songs.rows(s, 1, 1)
  eq(rows[1], beepbox.maxPitch)
  for _, q in ipairs(rows) do ok(songs.inScale(s, q), "in the scale: " .. q) end
  eq(#rows, 7 * 7 + 1)
  -- A note off the scale has its row too.
  songs.addNote(s, songs.ensurePattern(s, 1, 1), 49, 0, 2)
  local found = false
  for _, q in ipairs(songs.rows(s, 1, 1)) do if q == 49 then found = true end end
  ok(found, "the note's row is there")
  eq(songs.pitchName(s, 1, 48), "C4")
  s.key = "D"
  eq(songs.pitchName(s, 1, 48), "D4")
  eq(#songs.rows(s, 4, 1), beepbox.drums)
  eq(songs.pitchName(s, 4, 0), "Drum 1")
end)

test("presets and instruments", function()
  local s = songs.new()
  ok(#songs.categories(false) > 10); eq(songs.categories(true)[1], "Retro")
  local piano = songs.preset("grand piano", false)
  songs.setPreset(s, 1, piano)
  eq(songs.instrumentName(s, 1), "grand piano")
  songs.setVolume(s, 1, 40)
  eq(songs.volume(s, 1), 40)
  eq(songs.instrumentName(s, 1), nil, "changed: one of its own")
  eq(#songs.presetsIn("Drum", true), 1)
end)

test("undo and redo keep whole songs", function()
  local s = songs.new()
  local h = songs.history(2)
  ok(not h:canUndo())
  h:save(s); s.beatsPerMinute = 90
  h:save(s); s.beatsPerMinute = 80
  h:save(s); s.beatsPerMinute = 70
  local back = h:undo(s); eq(back.beatsPerMinute, 80)
  back = h:undo(back); eq(back.beatsPerMinute, 90)
  eq(h:undo(back), nil, "two kept")
  local fwd = h:redo(back); eq(fwd.beatsPerMinute, 80)
end)

test("a bar alone, for playing over and over", function()
  local s = songs.new()
  songs.addNote(s, songs.ensurePattern(s, 2, 3), 36, 0, 4)
  local one = songs.slice(s, 3, 3)
  eq(songs.bars(one), 1); eq(one.loopBars, 1)
  eq(#bar(one, 2, 1).notes, 1)
  local quiet = songs.slice(s, 5, 5)
  eq(songs.lastBar(quiet), 1, "an empty bar still plays for its length")
end)

---------------------------------------------------------------- the player

-- Stand-ins for the synthesiser and the speakers: a render is done when the
-- test says so, and a voice is where the test puts it.
local function fakes()
  local f = { jobs = {}, voices = {}, notes = {} }
  f.beepbox = {
    start = function(text)
      local j = { text = text, finished = false }
      function j:done() return self.finished end
      function j:result() return { seconds = 2 * #json.decode(text).channels[1].sequence } end
      f.jobs[#f.jobs + 1] = j
      return j
    end,
    note = function(text, c, inst, pitch)
      f.notes[#f.notes + 1] = { c = c, pitch = pitch }
      return { seconds = 0.35 }
    end,
  }
  f.audio = {
    play = function(sound, opts)
      local v = { sound = sound, opts = opts or {}, at = 0, on = true }
      function v:position() return self.at end
      function v:playing() return self.on end
      function v:stop() self.on = false end
      function v:replace(s2, when) self.replaced, self.when = s2, when end
      f.voices[#f.voices + 1] = v
      return v
    end,
  }
  return f
end

local player = require "player"

test("the player renders, plays and says where it is", function()
  local f = fakes()
  local p = player.new(f)
  local s = songs.new() -- 8 bars of 4 beats at 120: two seconds a bar
  p:play(s, { from = 3 })
  ok(p:playing())
  local at = p:update()
  ok(at.waiting, "while it renders"); eq(#f.voices, 0)
  f.jobs[1].finished = true
  at = p:update()
  eq(#f.voices, 1)
  eq(f.voices[1].opts.from, 4, "from the start of bar 3")
  eq(f.voices[1].opts.loop, true)
  f.voices[1].at = 4.5 -- seconds: bar 3, a beat in
  at = p:update()
  eq(at.bar, 3); eq(at.tick, 4)
  -- An edit: rendered again, and the same length goes in where it is.
  p:changed(s)
  f.jobs[2].finished = true
  p:update()
  eq(f.voices[1].when, "now")
  -- The end of a song not looping stops it.
  f.voices[1].on = false
  eq(p:update(), nil); ok(not p:playing())
end)

test("the player plays a bar alone, and sounds a note", function()
  local f = fakes()
  local p = player.new(f)
  p:setLoop(false)
  local s = songs.new()
  p:play(s, { bar = 5 })
  eq(#json.decode(f.jobs[1].text).channels[1].sequence, 1, "the bar alone")
  f.jobs[1].finished = true
  p:update()
  eq(f.voices[1].opts.loop, true, "a bar alone goes round whatever the loop says")
  f.voices[1].at = 1.5
  local at = p:update()
  eq(at.bar, 5); eq(at.tick, 12)
  p:note(s, 2, 36)
  eq(f.notes[1].c, 2); eq(f.notes[1].pitch, 36)
  p:stop()
  ok(not p:playing())
end)

---------------------------------------------------------------- the form

local gui = require "gui"
local settings = require "settings"
settings.file = root .. "/settings.lua"
local answers = {}
gui.msgbox = function() return table.remove(answers, 1) or "no" end
gui.inputbox = function() return table.remove(answers, 1) end
local saveAs
gui.savefile = function() return saveAs end
gui.openfile = function() return nil end

local frm = require "forms.ChipStudio"
local roll, grid = frm.rolNotes, frm.grdSong
local f = fakes()
frm.player.beepbox, frm.player.audio = f.beepbox, f.audio

local function state()
  local s, c, b, dirty, path = frm.state()
  return { song = s, channel = c, bar = b, dirty = dirty, path = path }
end

test("form: starts with a song to play", function()
  local st = state()
  eq(#st.song.channels, 4); eq(st.channel, 1); eq(st.bar, 1)
  ok(frm.lblBar.caption:find("plays nothing yet"), frm.lblBar.caption)
  eq(frm.cboScale.items[frm.cboScale.selected], "Major"); eq(frm.cboKey.items[frm.cboKey.selected], "C")
  eq(frm.lstPresets.items[frm.lstPresets.selected], "square lead")
  eq(frm.cboCategory.items[frm.cboCategory.selected], "Retro")
end)

-- click presses the roll at a pitch and tick, as the mouse would.
local function rowY(pitch)
  local rows = songs.rows(state().song, state().channel, state().bar)
  for i, q in ipairs(rows) do if q == pitch then return i end end
end

test("form: notes go down with the mouse, and undo takes them back", function()
  frm.pick(1, 2)
  roll:reveal()
  -- Put the roll at a known place: the top row is the highest pitch.
  local s = state().song
  local rows = songs.rows(s, 1, 2)
  -- Draw directly through the model the roll uses, as the roll would.
  roll:fire("onEdit", false)
  local p = songs.ensurePattern(s, 1, 2)
  songs.addNote(s, p, 48, 0, 4)
  roll:fire("onEdited")
  roll:fire("onEditDone")
  ok(state().dirty)
  ok(frm.lblBar.caption:find("pattern 1"), frm.lblBar.caption)
  roll:fire("onNote", 48)
  eq(f.notes[#f.notes].pitch, 48)
  frm.undo()
  eq(songs.patternAt(state().song, 1, 2), nil, "undone")
  frm.redo()
  eq(#songs.patternAt(state().song, 1, 2).notes, 1, "and done again")
  ok(#rows > 40)
end)

test("form: the roll's mouse puts a note down and takes it away", function()
  frm.pick(2, 4)
  local s = state().song
  roll:reveal()
  roll:snapshot() -- the roll lays itself out as it draws
  local pitch = 36 -- C, in the scale
  local x, y = roll:pointOf(pitch, 0)
  ok(x, "the row is in view")
  local heard = #f.notes
  roll:fire("onMouseDown", x, y, 1, false)
  local x2 = roll:pointOf(pitch, 5)
  roll:fire("onMouseDrag", x2, y)
  roll:fire("onMouseUp", x2, y)
  local p = songs.patternAt(state().song, 2, 4)
  eq(#p.notes, 1); eq(songs.noteEnd(p.notes[1]), 6, "dragged out to six ticks")
  eq(#f.notes, heard + 1, "it sounded")
  -- A click inside it on another row: a chord.
  local cx, cy = roll:pointOf(43, 2)
  roll:fire("onMouseDown", cx, cy, 1, false)
  roll:fire("onMouseUp", cx, cy)
  eq(table.concat(p.notes[1].pitches, " "), "36 43")
  -- Dragging it along moves it.
  local mx, my = roll:pointOf(pitch, 1)
  roll:fire("onMouseDown", mx, my, 1, false)
  local tx = roll:pointOf(pitch, 4)
  roll:fire("onMouseDrag", tx, my)
  roll:fire("onMouseUp", tx, my)
  eq(songs.noteStart(p.notes[1]), 3)
  -- A click on it takes that pitch away; a right click, the other.
  local dx, dy = roll:pointOf(43, 4)
  roll:fire("onMouseDown", dx, dy, 1, false)
  roll:fire("onMouseUp", dx, dy)
  eq(#p.notes[1].pitches, 1)
  local rx, ry = roll:pointOf(pitch, 4)
  roll:fire("onMouseDown", rx, ry, 3, false)
  eq(#p.notes, 0)
  -- Each was one undo.
  frm.undo()
  eq(#songs.patternAt(state().song, 2, 4).notes, 1)
end)

test("form: bars, patterns and the toolbar", function()
  frm.pick(1, 2)
  frm.actions.mnuDuplicate()
  local st = state()
  eq(st.bar, 3); eq(songs.bars(st.song), 9)
  eq(st.song.channels[1].sequence[3], st.song.channels[1].sequence[2])
  ok(frm.lblBar.caption:find("also plays in bar 2"), frm.lblBar.caption)
  eq(frm.cmdUnique.enabled, true)
  frm.cmdUnique:fire("onClick")
  eq(frm.cmdUnique.enabled, false)
  ok(state().song.channels[1].sequence[3] ~= state().song.channels[1].sequence[2])
  -- Numbers set the pattern of the cell.
  frm:fire("onKey", "0")
  eq(state().song.channels[1].sequence[3], 0)
  frm:fire("onKey", "Left")
  eq(state().bar, 2)
  frm:fire("onKey", "Down")
  eq(state().channel, 2)
  -- The tempo: a run of changes is one undo.
  frm.spnTempo.value = 130; frm.spnTempo:fire("onChange")
  frm.spnTempo.value = 140; frm.spnTempo:fire("onChange")
  eq(state().song.beatsPerMinute, 140)
  frm.undo()
  eq(state().song.beatsPerMinute, 120)
  frm.cboScale.selected = 1; frm.cboScale:fire("onChange")
  eq(state().song.scale, "easy :)")
  frm.cboKey.selected = 3; frm.cboKey:fire("onChange")
  eq(state().song.key, "D")
end)

test("form: a sound for the channel, and its volume", function()
  frm.pick(1, 1)
  local before = #f.notes
  for i, c in ipairs(frm.cboCategory.items) do if c == "Keyboard" then frm.cboCategory.selected = i end end
  frm.cboCategory:fire("onChange")
  frm.lstPresets.selected = 1; frm.lstPresets:fire("onChange")
  eq(songs.instrumentName(state().song, 1), "grand piano")
  eq(#f.notes, before + 1, "it plays a note to hear it")
  frm.sldVolume.value = 50; frm.sldVolume:fire("onChange")
  frm.sldVolume.value = 40; frm.sldVolume:fire("onChange")
  eq(songs.volume(state().song, 1), 40)
  frm.undo()
  eq(songs.volume(state().song, 1), 100, "one undo for the drag")
  ok(frm.lblInstrument.caption:find("Lead"))
end)

test("form: playing, with the bar only", function()
  frm.pick(1, 2)
  frm.chkBarOnly.checked = true
  frm.togglePlay()
  ok(frm.player:playing()); eq(frm.cmdStop.visible, true)
  f.jobs[#f.jobs].finished = true
  frm.tick()
  f.voices[#f.voices].at = 1
  frm.tick()
  eq(grid.playBar, 2); ok(roll.playTick ~= nil)
  frm.togglePlay()
  ok(not frm.player:playing()); eq(grid.playBar, nil); eq(frm.cmdPlay.visible, true)
  frm.chkBarOnly.checked = false
end)

test("form: save, open and export", function()
  saveAs = root .. "/tune"
  frm.actions.mnuSave()
  local st = state()
  eq(st.path, root .. "/tune.json"); ok(not st.dirty)
  ok(frm.caption:find("^tune.json"), frm.caption)
  local text = io.open(root .. "/tune.json"):read("*a")
  local back = assert(songs.decode(text))
  eq(#back.channels, 4); eq(back.key, "D")
  eq(dofile(settings.file).last, root .. "/tune.json")
  -- New, then open what was saved.
  frm.actions.mnuNew()
  eq(state().path, nil)
  ok(frm.load(root .. "/tune.json"))
  eq(state().song.key, "D")
  -- Export writes the WAV a game plays.
  saveAs = root .. "/tune.wav"
  frm.export()
  local wav = io.open(root .. "/tune.wav", "rb"):read("*a")
  eq(wav:sub(1, 4), "RIFF")
  ok(frm.lblStatus.caption:find("Exported"), frm.lblStatus.caption)
  -- Not a song: it says so, and keeps the one open.
  local bad = io.open(root .. "/bad.json", "w") bad:write('{"format":"x"}') bad:close()
  eq(frm.load(root .. "/bad.json"), false)
  eq(state().path, root .. "/tune.json")
end)

test("form: changes not saved are asked about", function()
  frm.change(function(s) s.beatsPerMinute = 99 end)
  answers = { "cancel" }
  eq(frm:fire("onClose"), false, "stays open")
  answers = { "no" }
  frm.actions.mnuNew()
  eq(state().song.beatsPerMinute, 120, "a new song, the change let go")
end)

t.done("chipstudio")
