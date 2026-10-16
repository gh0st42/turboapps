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

local play = player.new { beepbox = beepbox, audio = audio }

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
    text = text .. " · plays nothing yet: click in the roll to start"
  else
    text = text .. (" · pattern %d"):format(n)
    if #shared > 0 then
      local list = {}
      for i, b in ipairs(shared) do
        if i > 6 then list[#list + 1] = "…" break end
        list[#list + 1] = tostring(b)
      end
      text = text .. " · also plays in bar" .. (#shared > 1 and "s " or " ") .. table.concat(list, ", ")
        .. ", so a change here changes " .. (#shared > 1 and "them" or "it") .. " too"
    end
  end
  frm.lblBar.caption = text
  frm.cmdUnique.enabled = #shared > 0
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

-- show puts everything on screen as the song is.
local function show(reveal)
  bar = math.max(1, math.min(bar, songs.bars(song)))
  channel = math.max(1, math.min(channel, #song.channels))
  grid.song, grid.channel, grid.bar = song, channel, bar
  roll.song, roll.channel, roll.bar = song, channel, bar
  roll.length = LENGTHS[frm.cboLength.selected > 0 and frm.cboLength.selected or 3][2]()
  updateToolbar()
  updateInfo()
  updateInstrument()
  updateTitle()
  grid:changed()
  roll:changed()
  if reveal then roll:reveal() end
end

-- pick goes to bar b of channel c.
local function pick(c, b)
  local channelChanged = c ~= channel
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

function roll:onNote(pitch)
  if soundOK then play:note(song, channel, pitch) end
end

---------------------------------------------------------------- the grid

function grid:onPick(c, b) pick(c, b) end

local function setPatternHere(n)
  change(function(s) songs.setPattern(s, channel, bar, n) end)
  status(n == 0 and "This bar plays nothing on this channel" or ("This bar plays pattern %d"):format(n))
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

local function addChannel(kind)
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
  grid.playBar = nil
  roll.playTick = nil
  updatePlayButtons()
end

local function tick()
  local at = play:update()
  if not at then
    if play.error then status("Cannot play: " .. play.error) play.error = nil end
    stop()
    return false
  end
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

function frm.cboLength:onChange()
  if quiet then return end
  roll.length = LENGTHS[self.selected > 0 and self.selected or 3][2]()
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

---------------------------------------------------------------- menus and keys

local actions = {
  mnuNew = newSong, mnuOpen = open, mnuSave = function() saveSong() end, mnuSaveAs = function() saveAs() end,
  mnuExport = export, mnuExit = function() frm:close() end,
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


function frm:onKey(key)
  if key == "Space" or key == " " then togglePlay() return true end
  if key == "Left" then if bar > 1 then pick(channel, bar - 1) end return true end
  if key == "Right" then if bar < songs.bars(song) then pick(channel, bar + 1) end return true end
  if key == "Up" then if channel > 1 then pick(channel - 1, bar) end return true end
  if key == "Down" then if channel < #song.channels then pick(channel + 1, bar) end return true end
  local digit = key:match("^(%d)$")
  if digit then setPatternHere(tonumber(digit)) return true end
  if key == "Escape" then stop() return true end
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

-- Exposed for the tests.
frm.state = function() return song, channel, bar, dirty, path end
frm.pick, frm.change, frm.undo, frm.redo = pick, change, undo, redo
frm.load, frm.write, frm.export = load, write, export
frm.actions = actions
frm.player = play
frm.togglePlay, frm.stop = togglePlay, stop
frm.tick = tick

return frm
