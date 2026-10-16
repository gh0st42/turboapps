-- The code behind ChipStudio.form.lua: the controls are fields of the
-- form, by the names the layout gives them. A chiptune editor for BeepBox's
-- songs: the song grid (controls/SongGrid.lua) picks a bar of a channel,
-- the piano roll (controls/PianoRoll.lua) edits it, the panel on the right
-- picks the channel's sound, and player.lua plays it all through tlua's
-- beepbox and audio modules. song.lua is the song itself.

local gui = require "gui"
local lfs = require "lfs"
local beepbox = require "beepbox"
local audio = require "audio"
local songs = require "song"
local exporter = require "export"
local player = require "player"
local help = require "forms.Help"
local settingsStore = require "settings"

local frm = gui.load "ChipStudio" --[[@as forms.ChipStudio]]
local grid, roll = frm.grdSong, frm.rolNotes

local song = songs.new()
local path            -- where it is kept, or nil for a new song
local dirty = false
local channel, bar = 1, 1
local history = songs.history(100)
local lastKind        -- the kind of the last change, so a slider's drag is one undo
local clip            -- a bar copied: its notes
local quiet = false   -- the controls are being filled, not changed by the user
local timer
local soundOK, soundWhy = true, nil
local muted, soloed = {}, {}   -- channels silenced, and played alone
local cursor = 0               -- where the next note played on the keyboard goes, stopped
local octave = {}              -- by channel: how far the keyboard is moved, in octaves
local lastAt                   -- where playing had got to, the last time it was looked at

local play = player.new { beepbox = beepbox, audio = audio }
play.prepare = function(s) return songs.withMutes(s, muted, soloed) end

local settings = settingsStore.load()

---------------------------------------------------------------- showing

local LENGTHS = {
  { "A step", function() return 1 end },
  { "Half a beat", function() return math.max(1, math.floor(song.ticksPerBeat / 2)) end },
  { "A beat", function() return song.ticksPerBeat end },
  { "Two beats", function() return song.ticksPerBeat * 2 end },
  { "A whole bar", function() return songs.barTicks(song) end },
}

-- FRIENDLY are the scales by what most people call them.
local FRIENDLY = {
  ["easy :)"] = "Easy, happy (pentatonic major)", ["easy :("] = "Easy, sad (pentatonic minor)",
  ["island :)"] = "Island, happy (ryukyu)", ["island :("] = "Island, sad (pelog)",
  ["blues :)"] = "Blues, happy", ["blues :("] = "Blues, sad",
  ["normal :)"] = "Major", ["normal :("] = "Minor",
  ["double harmonic :)"] = "Double harmonic major", ["double harmonic :("] = "Double harmonic minor",
  ["strange"] = "Strange (whole tone)", ["expert"] = "Every note (chromatic)",
}

local function status(text) frm.lblStatus.caption = "  " .. (text or "") end

local function updateTitle()
  local name = path and path:match("([^/\\]+)$") or "New song"
  frm.caption = (dirty and "• " or "") .. name .. " — ChipStudio"
end

local function updateToolbar()
  quiet = true
  frm.spnTempo.value = song.beatsPerMinute
  frm.spnBeats.value = song.beatsPerBar
  frm.spnBars.value = songs.bars(song)
  frm.cboKey.selected = songs.keyIndex(song.key)
  frm.cboScale.selected = songs.scaleIndex(song.scale)
  quiet = false
end

local function updateInfo()
  local ch = song.channels[channel]
  local p, n = songs.patternAt(song, channel, bar)
  local text = ("Bar %d · %s"):format(bar, songs.channelLabel(song, channel))
  local shared = songs.sharedBars(song, channel, bar)
  if not p then
    text = text .. " · nothing yet: click in the roll, or pick a pattern"
  else
    if #shared > 0 then
      local list = {}
      for i, b in ipairs(shared) do
        if i > 6 then list[#list + 1] = "…" break end
        list[#list + 1] = tostring(b)
      end
      text = text .. " · also in bar" .. (#shared > 1 and "s " or " ") .. table.concat(list, ", ")
        .. ", which change with it"
    end
  end
  frm.lblBar.caption = text
  frm.cmdUnique.enabled = #shared > 0
  -- The pattern stepper: none, the patterns there are, and one more, new.
  quiet = true
  frm.spnPattern.max = #ch.patterns + 1
  frm.spnPattern.value = ch.sequence[bar] or 0
  quiet = false
  frm.lblInstrument.caption = (ch and ch.type == "drum" and "Drum sound" or "Instrument") .. " · "
    .. songs.channelLabel(song, channel)
end

local presetList = {} -- what lstPresets lists

local function fillPresets(category)
  local drum = songs.isDrum(song, channel)
  presetList = songs.presetsIn(category, drum)
  local names = {}
  for i, p in ipairs(presetList) do names[i] = p.name end
  quiet = true
  frm.lstPresets.items = names
  local current = songs.instrumentName(song, channel)
  frm.lstPresets.selected = 0
  for i, p in ipairs(presetList) do
    if p.name == current then frm.lstPresets.selected = i end
  end
  quiet = false
end

local function updateInstrument()
  local drum = songs.isDrum(song, channel)
  local cats = songs.categories(drum)
  local current = songs.instrumentName(song, channel)
  local at = 1
  for i, c in ipairs(cats) do
    for _, p in ipairs(songs.presetsIn(c, drum)) do
      if p.name == current then at = i end
    end
  end
  quiet = true
  frm.cboCategory.items = cats
  frm.cboCategory.selected = at
  frm.sldVolume.value = songs.volume(song, channel)
  quiet = false
  fillPresets(cats[at])
  frm.lblVolume.caption = ("Volume · %d%%%s"):format(songs.volume(song, channel),
    current and "" or " · a sound of its own")
end

local function updatePlayButtons()
  local on = play:playing()
  frm.cmdPlay.visible = not on
  frm.cmdStop.visible = on
end

-- keyboardBase is the lowest pitch the keyboard's bottom row plays on
-- channel c: its octave, moved as the user moved it.
local function keyboardBase(c)
  if songs.isDrum(song, c) then return 0 end
  local ch = song.channels[c]
  local base = ((tonumber(ch and ch.octaveScrollBar) or 3) + (octave[c] or 0)) * 12
  return math.max(0, math.min(base, beepbox.maxPitch - 12))
end

local function updateKeys()
  if songs.isDrum(song, channel) then
    frm.lblKeys.caption = "Keys: drums"
  else
    frm.lblKeys.caption = "Keys from " .. songs.pitchName(song, channel, keyboardBase(channel))
  end
  roll.cursorTick = (frm.chkRecord.checked and not play:playing()) and cursor or nil
end

-- unheard is the channels muted, or left out by a solo: the roll does not
-- show their notes behind the channel's own.
local function unheard()
  local any = next(soloed) ~= nil
  local out = {}
  for c = 1, #song.channels do
    if muted[c] or (any and not soloed[c]) then out[c] = true end
  end
  return out
end

-- show puts everything on screen as the song is.
local function show(reveal)
  bar = math.max(1, math.min(bar, songs.bars(song)))
  channel = math.max(1, math.min(channel, #song.channels))
  grid.song, grid.channel, grid.bar = song, channel, bar
  grid.muted, grid.soloed = muted, soloed
  roll.song, roll.channel, roll.bar = song, channel, bar
  roll.hidden = unheard()
  updateToolbar()
  updateInfo()
  updateInstrument()
  updateTitle()
  updateKeys()
  grid:changed()
  roll:changed()
  if reveal then roll:reveal() end
end

-- pick goes to bar b of channel c.
local function pick(c, b)
  local channelChanged = c ~= channel
  if c ~= channel or b ~= bar then cursor = 0 end
  channel, bar = c, b
  show(true)
  if channelChanged then lastKind = nil end
end

---------------------------------------------------------------- changing

-- change makes a change to the song that can be undone. kind names a run of
-- changes (a slider dragged) that undo takes back as one.
local function change(fn, kind)
  if not kind or kind ~= lastKind then history:save(song) end
  lastKind = kind
  fn(song)
  dirty = true
  show()
  play:changed(song)
end

local function undo()
  local prev = history:undo(song)
  if not prev then status("Nothing to undo") return end
  song, dirty, lastKind = prev, true, nil
  show(false)
  play:changed(song)
end

local function redo()
  local nxt = history:redo(song)
  if not nxt then status("Nothing to redo") return end
  song, dirty, lastKind = nxt, true, nil
  show(false)
  play:changed(song)
end

function roll:onEdit(continuing)
  if not continuing then history:save(song) end
  lastKind = nil
  dirty = true
end

function roll:onEdited()
  grid:changed()
  updateInfo()
  updateTitle()
end

function roll:onEditDone()
  play:changed(song)
end

function roll:onHint(text)
  status(text or "")
end

function roll:onNote(pitch)
  if soundOK then play:note(song, channel, pitch) end
end

---------------------------------------------------------------- the grid

function grid:onPick(c, b) pick(c, b) end

local function setPatternHere(n, kind)
  local ch = song.channels[channel]
  n = math.max(0, math.min(n, #ch.patterns + 1))
  local new = n > #ch.patterns
  change(function(s) songs.setPattern(s, channel, bar, n) end, kind)
  if n == 0 then
    status("This bar plays nothing on this channel")
  else
    local others = #songs.sharedBars(song, channel, bar)
    status(("This bar plays pattern %d%s"):format(n, new and ", a new one"
      or others > 0 and (", as %d other bar%s do%s: a change to one is a change to all"):format(others,
        others > 1 and "s" or "", others > 1 and "" or "es") or ""))
  end
end

-- stepPattern moves the bar on to the next pattern number, or back.
local function stepPattern(by)
  setPatternHere((song.channels[channel].sequence[bar] or 0) + by, "pattern" .. channel .. ":" .. bar)
end

function frm.spnPattern:onChange()
  if quiet then return end
  setPatternHere(math.floor(self.value), "pattern" .. channel .. ":" .. bar)
end

function grid:onMute(c)
  muted[c] = not muted[c] or nil
  grid:changed()
  roll.hidden = unheard()
  play:changed(song)
  status(songs.channelLabel(song, c) .. (muted[c] and " is muted" or " is heard again"))
end

function grid:onSolo(c)
  soloed[c] = not soloed[c] or nil
  grid:changed()
  roll.hidden = unheard()
  play:changed(song)
  local any = next(soloed) ~= nil
  status(soloed[c] and (songs.channelLabel(song, c) .. " plays alone" .. (#song.channels > 1 and "; S on others adds them" or ""))
    or (any and "Fewer channels play alone" or "Every channel is heard again"))
end

local barMenu -- below

function grid:onMenu(c, b)
  if b then pick(c, b) else pick(c, bar) end
  gui.popup(barMenu())
end

---------------------------------------------------------------- bars and channels

local function duplicateBar()
  change(function(s) songs.duplicateBar(s, bar) end)
  bar = bar + 1
  show()
  status("Bar " .. (bar - 1) .. " plays again in bar " .. bar)
end

local function insertBar()
  change(function(s) songs.insertBar(s, bar) end)
end

local function removeBar()
  if songs.bars(song) <= 1 then return end
  change(function(s) songs.removeBar(s, bar) end)
end

local function clearBar()
  change(function(s) songs.setPattern(s, channel, bar, 0) end)
  status("Cleared bar " .. bar .. " of " .. songs.channelLabel(song, channel))
end

local function makeUnique()
  if #songs.sharedBars(song, channel, bar) == 0 then return end
  change(function(s) songs.makeUnique(s, channel, bar) end)
  status("Bar " .. bar .. " has a pattern of its own now")
end

local function copyBar()
  local p = songs.patternAt(song, channel, bar)
  clip = p and songs.copy(p.notes) or {}
  status("Copied bar " .. bar .. " of " .. songs.channelLabel(song, channel))
end

local function pasteBar()
  if not clip then status("Copy a bar first") return end
  change(function(s)
    if #clip == 0 then
      songs.setPattern(s, channel, bar, 0)
      return
    end
    -- A pattern of its own, so the bar copied from is left as it is.
    songs.setPattern(s, channel, bar, 0)
    local p = songs.ensurePattern(s, channel, bar)
    p.notes = songs.copy(clip)
    songs.setBeats(s, s.beatsPerBar) -- what does not fit this channel's bar
  end)
  status("Pasted into bar " .. bar)
end

-- forgetMutes lets every channel be heard again: after channels came or
-- went, the numbers no longer mean the same ones.
local function forgetMutes()
  muted, soloed = {}, {}
end

local function addChannel(kind)
  forgetMutes()
  local at
  change(function(s) at = songs.addChannel(s, kind) end)
  if not at then
    status(kind == "drum" and "A song has room for five drum channels" or "A song has room for ten melody channels")
    return
  end
  pick(at, bar)
end

local function renameChannel()
  local name = gui.inputbox("A name for this channel:", "Rename Channel", songs.channelLabel(song, channel))
  if not name then return end
  change(function(s) s.channels[channel].name = name ~= "" and name or nil end)
end

local function removeChannel()
  if #song.channels <= 1 then return end
  if gui.msgbox(("Remove %s and everything it plays?"):format(songs.channelLabel(song, channel)),
    "yesno", "Remove Channel") ~= "yes" then return end
  forgetMutes()
  change(function(s) songs.removeChannel(s, channel) end)
end

barMenu = function()
  local shared = #songs.sharedBars(song, channel, bar) > 0
  local patterns = { { "None", function() setPatternHere(0) end } }
  for n = 1, #song.channels[channel].patterns + 1 do
    patterns[#patterns + 1] = { (n > #song.channels[channel].patterns and "A new pattern " or "Pattern ") .. n,
      function() setPatternHere(n) end }
  end
  return {
    { "&Duplicate Bar", duplicateBar },
    { "&Insert Empty Bar", insertBar },
    { "&Remove Bar", removeBar },
    "-",
    { "&Copy Bar", copyBar },
    { "&Paste Bar", pasteBar, enabled = clip ~= nil },
    { "C&lear Bar", clearBar },
    { "Make Bar &Unique", makeUnique, enabled = shared },
    { "&Play Pattern", patterns },
    "-",
    { "Loop &Starts Here", function() change(function(s) songs.setLoop(s, bar, s.introBars + s.loopBars) end) end },
    { "Loop &Ends Here", function() change(function(s) songs.setLoop(s, s.introBars + 1, bar) end) end },
    "-",
    { "Re&name Channel...", renameChannel },
    { "Remove C&hannel", removeChannel, enabled = #song.channels > 1 },
  }
end

---------------------------------------------------------------- playing

local function setChecked(name, on)
  local items = frm.Menu1.items
  local function walk(list)
    for _, it in ipairs(list) do
      if type(it) == "table" then
        if it.name == name then it.checked = on end
        if type(it[2]) == "table" then walk(it[2]) end
      end
    end
  end
  walk(items)
  frm.Menu1.items = items
end


local function stopTimer()
  if timer then timer:stop() timer = nil end
end

local function stop()
  play:stop()
  stopTimer()
  lastAt = nil
  grid.playBar = nil
  roll.playTick = nil
  updatePlayButtons()
  updateKeys()
end

local function tick()
  local at = play:update()
  if not at then
    if play.error then status("Cannot play: " .. play.error) play.error = nil end
    stop()
    return false
  end
  lastAt = at
  if grid.playBar ~= at.bar then grid.playBar = at.bar end
  roll.playTick = (at.bar == bar and not at.waiting) and at.tick or nil
  return true
end

local function startPlaying(from)
  if not soundOK then
    gui.msgbox("There is no sound to be had here.\n\n" .. tostring(soundWhy), "ok", "ChipStudio")
    return
  end
  play:setLoop(frm.chkLoop.checked)
  if frm.chkBarOnly.checked then
    play:play(song, { bar = bar })
  else
    play:play(song, { from = from or bar })
  end
  updatePlayButtons()
  updateKeys()
  stopTimer()
  timer = gui.every(1 / 30, tick)
end

local function togglePlay()
  if play:playing() then stop() else startPlaying() end
end

frm.cmdPlay.onClick = function() startPlaying() end
frm.cmdStop.onClick = function() stop() end

function frm.chkLoop:onChange()
  setChecked("mnuLoop", self.checked)
  play:setLoop(self.checked)
  if play:playing() then startPlaying() end
end

function frm.chkBarOnly:onChange()
  setChecked("mnuBarOnly", self.checked)
  if play:playing() then startPlaying() end
end

---------------------------------------------------------------- the toolbar

function frm.spnTempo:onChange()
  if quiet then return end
  local v = math.floor(self.value)
  change(function(s) s.beatsPerMinute = v end, "tempo")
end

function frm.spnBeats:onChange()
  if quiet then return end
  local v = math.floor(self.value)
  change(function(s) songs.setBeats(s, v) end, "beats")
end

function frm.spnBars:onChange()
  if quiet then return end
  local v = math.floor(self.value)
  change(function(s) songs.setBars(s, v) end, "bars")
end

function frm.cboKey:onChange()
  if quiet or self.selected < 1 then return end
  local k = beepbox.keys[self.selected].name
  change(function(s) s.key = k end)
end

function frm.cboScale:onChange()
  if quiet or self.selected < 1 then return end
  local sc = beepbox.scales[self.selected].name
  change(function(s) s.scale = sc end)
end

-- keyLength is how long a note the keyboard writes is, in ticks.
local function keyLength()
  return LENGTHS[frm.cboLength.selected > 0 and frm.cboLength.selected or 3][2]()
end

frm.cmdUnique.onClick = function() makeUnique() end

---------------------------------------------------------------- the instrument

-- listen plays a note of the channel's sound: the middle of its notes, or a
-- drum.
local function listen()
  if not soundOK then return end
  local drum = songs.isDrum(song, channel)
  local ch = song.channels[channel]
  local pitch = drum and 4 or ((tonumber(ch.octaveScrollBar) or 3) * 12 + 12)
  play:note(song, channel, pitch)
end

function frm.cboCategory:onChange()
  if quiet or self.selected < 1 then return end
  fillPresets(self.items[self.selected])
end

function frm.lstPresets:onChange()
  if quiet then return end
  local p = presetList[self.selected or 0]
  if not p then return end
  change(function(s) songs.setPreset(s, channel, p) end)
  status(songs.channelLabel(song, channel) .. " plays " .. p.name)
  listen()
end

frm.cmdListen.onClick = function() listen() end

function frm.sldVolume:onChange()
  if quiet then return end
  local v = self.value
  change(function(s) songs.setVolume(s, channel, v) end, "volume" .. channel)
end

---------------------------------------------------------------- what a drag does

local MODES = { notes = "optNotes", volume = "optVolume", bend = "optBend" }

local function setMode(mode)
  roll.mode = mode
  for m, name in pairs(MODES) do frm[name].checked = m == mode end
  status(({ notes = "Notes: click to put one down, drag to move and stretch",
    volume = "Volume: drag a note up or down, at its start, its end or in between",
    bend = "Bend: drag a note to the note it should slide to" })[mode])
end

for mode, name in pairs(MODES) do
  frm[name].onChange = function(self) if self.checked then setMode(mode) end end
end

local function flattenBar()
  local p = songs.patternAt(song, channel, bar)
  if not p then return end
  change(function() for _, n in ipairs(p.notes) do songs.flatten(n) end end)
  status("The notes of bar " .. bar .. " are full and straight again")
end

---------------------------------------------------------------- the keyboard

-- The two rows of letters play the scale's notes, the bottom row from the
-- keyboard's octave and the top one an octave up, so every key is in tune.
local LOWER = { "z", "x", "c", "v", "b", "n", "m", ",", ".", "/" }
local UPPER = { "q", "w", "e", "r", "t", "y", "u", "i", "o", "p" }

-- pitchOfKey is the pitch a key plays on the channel picked, or nil.
local function pitchOfKey(key)
  local k = key:lower()
  local row, from
  for i, name in ipairs(LOWER) do if name == k then row, from = i, keyboardBase(channel) end end
  for i, name in ipairs(UPPER) do
    if name == k then row, from = i, keyboardBase(channel) + (songs.isDrum(song, channel) and 2 or 12) end
  end
  if not row then return nil end
  return songs.scaleFrom(song, channel, from, #LOWER)[row]
end

local function moveOctave(by)
  if songs.isDrum(song, channel) then return end
  local was = keyboardBase(channel)
  octave[channel] = (octave[channel] or 0) + by
  if keyboardBase(channel) == was then octave[channel] = octave[channel] - by end
  updateKeys()
  status("The keyboard plays from " .. songs.pitchName(song, channel, keyboardBase(channel)))
end

-- record writes a note played on the keyboard into the song: at the
-- playhead, to the nearest note's length, while it plays; else at the
-- cursor, which then moves on by a note, to the next bar at the end of one.
local function record(pitch)
  local L = math.max(1, keyLength())
  local ticks = songs.barTicks(song)
  local b, tk
  if play:playing() and lastAt and not lastAt.waiting then
    b = lastAt.bar
    tk = math.floor(lastAt.tick / L + 0.5) * L
    if tk >= ticks then
      if b < songs.bars(song) and not frm.chkBarOnly.checked then b, tk = b + 1, 0 else tk = ticks - L end
    end
  else
    b, tk = bar, cursor
  end
  local placed
  change(function(s)
    local p = songs.ensurePattern(s, channel, b)
    placed = songs.addNote(s, p, pitch, math.max(0, tk), L)
  end)
  if not play:playing() then
    cursor = tk + L
    if cursor >= ticks then
      if bar < songs.bars(song) then
        pick(channel, bar + 1)
        cursor = 0
      else
        cursor = 0
        status("That was the end of the song; the next note goes at the start of this bar")
      end
    end
    updateKeys()
  end
  if not placed then status("No room for a note there") end
end

local function playKey(key)
  local pitch = pitchOfKey(key)
  if not pitch then return false end
  if soundOK then play:note(song, channel, pitch) end
  if frm.chkRecord.checked then record(pitch) end
  return true
end

function frm.chkRecord:onChange()
  setChecked("mnuRecord", self.checked)
  cursor = 0
  updateKeys()
  status(self.checked and "Recording: the keys write notes into " .. songs.channelLabel(song, channel)
    or "The keys only play now")
end

---------------------------------------------------------------- files

local function startDir()
  local cwd = lfs.currentdir()
  return (path and path:match("^(.*)/[^/]*$")) or songs.fzFolder(cwd) or cwd
end

-- askToKeep asks what to do with changes not saved yet: false to go on
-- without them (or after saving them), true to stay.
local saveSong -- below

local function keepChanges()
  if not dirty then return false end
  local a = gui.msgbox("Save the changes to this song first?", "yesnocancel", "ChipStudio")
  if a == "cancel" then return true end
  if a == "yes" then return not saveSong() end
  return false
end

local function load(p)
  local f, err = io.open(p, "rb")
  if not f then gui.msgbox("Cannot open " .. p .. ".\n\n" .. tostring(err), "ok", "Open") return false end
  local text = f:read("*a")
  f:close()
  local s, why = songs.decode(text)
  if not s then gui.msgbox("Cannot open " .. p .. ".\n\n" .. tostring(why), "ok", "Open") return false end
  stop()
  song, path, dirty, lastKind = s, p, false, nil
  forgetMutes()
  octave, cursor = {}, 0
  history:clear()
  channel, bar = 1, 1
  settings.last = p
  settingsStore.save(settings)
  show(true)
  status(("Opened %s: %d channels, %d bars"):format(p:match("([^/\\]+)$"), #song.channels, songs.bars(song)))
  return true
end

local function write(p)
  local f, err = io.open(p, "wb")
  if not f then gui.msgbox("Cannot save " .. p .. ".\n\n" .. tostring(err), "ok", "Save") return false end
  f:write(songs.encode(song))
  f:close()
  path, dirty = p, false
  settings.last = p
  settingsStore.save(settings)
  updateTitle()
  status("Saved " .. p)
  return true
end

local function saveAs()
  local name = path and path:match("([^/\\]+)$") or "song.json"
  local p = gui.savefile { title = "Save Song", dir = startDir(), file = name,
    filter = "BeepBox song\t*.json\nAll\t*" }
  if not p then return false end
  if not p:match("%.%w+$") then p = p .. songs.EXTENSION end
  return write(p)
end

saveSong = function()
  if path then return write(path) end
  return saveAs()
end

local function open()
  if keepChanges() then return end
  local p = gui.openfile { title = "Open Song", dir = startDir(), filter = "BeepBox song\t*.json\nAll\t*" }
  if type(p) == "table" then p = p[1] end
  if p then load(p) end
end

local function newSong()
  if keepChanges() then return end
  stop()
  song, path, dirty, lastKind = songs.new(), nil, false, nil
  forgetMutes()
  octave, cursor = {}, 0
  history:clear()
  channel, bar = 1, 1
  show(true)
  status("A new song: pick a bar and put some notes down")
end

-- export writes the song as the WAV file a game plays: beside the song, as
-- fz keeps them.
local function export()
  local name = (path and path:match("([^/\\]+)%.%w+$") or "song") .. ".wav"
  local dir = path and path:match("^(.*)/[^/]*$") or startDir()
  local p = gui.savefile { title = "Export WAV", dir = dir, file = name, filter = "WAV\t*.wav" }
  if not p then return end
  if not p:match("%.[wW][aA][vV]$") then p = p .. ".wav" end
  local sound, skipped = beepbox.render(songs.encode(song, true))
  if not sound then gui.msgbox("Cannot render the song.\n\n" .. tostring(skipped), "ok", "Export") return end
  local ok, err = sound:save(p)
  if not ok then gui.msgbox("Cannot write " .. p .. ".\n\n" .. tostring(err), "ok", "Export") return end
  status(("Exported %s: %.1f seconds%s"):format(p, sound.seconds,
    #skipped > 0 and (" (could not play: " .. table.concat(skipped, ", ") .. ")") or ""))
end

-- exportOgg writes the song as an Ogg file, the smaller sound a game can
-- play, through ffmpeg when it is installed.
local function exportOgg()
  local ffmpeg = exporter.which("ffmpeg")
  if not ffmpeg then
    gui.msgbox("Ogg files are made by ffmpeg, which is not installed here.\n\n"
      .. "Install ffmpeg, or use Export WAV, which needs nothing.", "ok", "Export OGG")
    return
  end
  local name = (path and path:match("([^/\\]+)%.%w+$") or "song") .. ".ogg"
  local dir = path and path:match("^(.*)/[^/]*$") or startDir()
  local p = gui.savefile { title = "Export OGG", dir = dir, file = name, filter = "Ogg Vorbis\t*.ogg" }
  if not p then return end
  if not p:match("%.[oO][gG][gG]$") then p = p .. ".ogg" end
  local sound, skipped = beepbox.render(songs.encode(song, true))
  if not sound then gui.msgbox("Cannot render the song.\n\n" .. tostring(skipped), "ok", "Export OGG") return end
  status("Exporting " .. p .. "...")
  exporter.ogg(gui.spawn, ffmpeg, sound, p, function(ok, why)
    if ok then
      status(("Exported %s: %.1f seconds"):format(p, sound.seconds))
    else
      status("Not exported")
      gui.msgbox("ffmpeg could not make " .. p .. ".\n\n" .. tostring(why), "ok", "Export OGG")
    end
  end)
end

---------------------------------------------------------------- menus and keys

local actions = {
  mnuNew = newSong, mnuOpen = open, mnuSave = function() saveSong() end, mnuSaveAs = function() saveAs() end,
  mnuExport = export, mnuExportOgg = exportOgg, mnuExit = function() frm:close() end,
  mnuUndo = undo, mnuRedo = redo, mnuCopy = copyBar, mnuPaste = pasteBar, mnuClear = clearBar,
  mnuUnique = makeUnique, mnuDuplicate = duplicateBar, mnuInsert = insertBar, mnuRemoveBar = removeBar,
  mnuLoopStart = function() change(function(s) songs.setLoop(s, bar, s.introBars + s.loopBars) end) end,
  mnuLoopEnd = function() change(function(s) songs.setLoop(s, s.introBars + 1, bar) end) end,
  mnuAddPitch = function() addChannel("pitch") end, mnuAddDrum = function() addChannel("drum") end,
  mnuRenameChannel = renameChannel, mnuRemoveChannel = removeChannel,
  mnuPlay = togglePlay, mnuPlayStart = function() stop() startPlaying(1) end,
  mnuLoop = function()
    frm.chkLoop.checked = not frm.chkLoop.checked
    frm.chkLoop:fire("onChange")
  end,
  mnuBarOnly = function()
    frm.chkBarOnly.checked = not frm.chkBarOnly.checked
    frm.chkBarOnly:fire("onChange")
  end,
  mnuModeNotes = function() setMode("notes") end,
  mnuModeVolume = function() setMode("volume") end,
  mnuModeBend = function() setMode("bend") end,
  mnuFlatten = flattenBar,
  mnuGhosts = function()
    roll.ghosts = not roll.ghosts
    setChecked("mnuGhosts", roll.ghosts)
    status(roll.ghosts and "The other channels' notes show behind this one's"
      or "Only this channel's notes show")
  end,
  mnuRecord = function()
    frm.chkRecord.checked = not frm.chkRecord.checked
    frm.chkRecord:fire("onChange")
  end,
  mnuOctaveUp = function() moveOctave(1) end,
  mnuOctaveDown = function() moveOctave(-1) end,
  mnuHelp = function() help.open() end,
  mnuAbout = function()
    gui.msgbox("ChipStudio\n\nChiptune music in BeepBox's own song format, played by fz's port of\n"
      .. "BeepBox's synthesiser. Made with tlua.", "ok", "About ChipStudio")
  end,
}

function frm.Menu1:onClick(name)
  local fn = name and actions[name]
  if fn then fn() end
end


-- Space plays and stops whatever has the focus: a checkbox or a button
-- would otherwise take it as a press of its own.
function frm:onKeyPreview(key)
  if key == "Space" then togglePlay() return true end
end

function frm:onKey(key)
  if key == "Space" or key == " " then togglePlay() return true end
  if key == "Left" then if bar > 1 then pick(channel, bar - 1) end return true end
  if key == "Right" then if bar < songs.bars(song) then pick(channel, bar + 1) end return true end
  if key == "Up" then if channel > 1 then pick(channel - 1, bar) end return true end
  if key == "Down" then if channel < #song.channels then pick(channel + 1, bar) end return true end
  local digit = key:match("^(%d)$")
  if digit then setPatternHere(tonumber(digit)) return true end
  if key == "Escape" then stop() return true end
  if key == "[" then stepPattern(-1) return true end
  if key == "]" then stepPattern(1) return true end
  if key == "-" then moveOctave(-1) return true end
  if key == "=" then moveOctave(1) return true end
  if playKey(key) then return true end
end

function frm:onClose()
  if keepChanges() then return false end
  stop()
end

function frm:onDrop(text, lines)
  local p = lines and lines[1]
  if p and p:match("%.json$") and not keepChanges() then load(p) end
end

---------------------------------------------------------------- starting

do
  local keys = {}
  for i, k in ipairs(beepbox.keys) do keys[i] = k.name end
  frm.cboKey.items = keys
  local scales = {}
  for i, sc in ipairs(beepbox.scales) do scales[i] = FRIENDLY[sc.name] or sc.label end
  frm.cboScale.items = scales
  local lengths = {}
  for i, l in ipairs(LENGTHS) do lengths[i] = l[1] end
  frm.cboLength.items = lengths
  frm.cboLength.selected = 3
end

-- A song named on the command line opens, else the last one, else a new one.
local start = arg and arg[1]
if not (start and lfs.attributes(start, "mode") == "file") then
  start = settings.last ~= "" and lfs.attributes(settings.last, "mode") == "file" and settings.last or nil
end
if not (start and load(start)) then show(true) status("Pick a bar in the grid, then click in the roll to put notes down. F1 shows how.") end
gui.after(0, function()
  soundOK, soundWhy = audio.available(beepbox.rate)
  if not soundOK then status("No sound here: " .. tostring(soundWhy)) end
  roll:focus()
end)

-- Without ffmpeg there is no Ogg, and the menu says why.
if not exporter.which("ffmpeg") then
  local items = frm.Menu1.items
  for _, top in ipairs(items) do
    if type(top) == "table" and type(top[2]) == "table" then
      for _, it in ipairs(top[2]) do
        if type(it) == "table" and it.name == "mnuExportOgg" then
          it[1], it.enabled = "Export &OGG... (needs ffmpeg)", false
        end
      end
    end
  end
  frm.Menu1.items = items
end

-- Exposed for the tests.
frm.state = function() return song, channel, bar, dirty, path end
frm.pick, frm.change, frm.undo, frm.redo = pick, change, undo, redo
frm.load, frm.write, frm.export, frm.exportOgg = load, write, export, exportOgg
frm.actions = actions
frm.player = play
frm.togglePlay, frm.stop = togglePlay, stop
frm.tick = tick
frm.playKey, frm.setMode = playKey, setMode
frm.stepPattern = stepPattern
frm.mutes = function() return muted, soloed end
frm.cursor = function() return cursor end

return frm
