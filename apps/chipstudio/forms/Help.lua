-- The code behind Help.form.lua: ChipStudio's getting-started page.

local gui = require "gui"
local frm = gui.load "Help" --[[@as forms.Help]]

frm.TEXT = [==[
# Getting started

ChipStudio makes chiptune music: tunes played on the sounds of old consoles
and home computers. A song is a few **channels** (a lead, a harmony, a bass
and drums to start with), and each plays a **bar** at a time.

## 1. Pick a bar

The grid at the top is the song: a row for each channel, a column for each
bar. Click a cell to edit what that channel plays in that bar. The piano roll
below shows it.

## 2. Put notes down

Click in the roll to put a note down; it sounds as it goes in. Drag to make
it longer, drag a note to move it, drag its end to stretch it, and click a
note to take it away (or right-click it). Clicking inside a note that is
already sounding adds another pitch to it: a chord.

The roll only has rows for the notes of the song's **scale**, so whatever
you put down fits. The rows of the key are lit. **New notes** sets how long
a note is when it goes down.

## 3. Listen

**Space** plays from the bar you picked, and goes round again while
**Loop** is on. **This bar only** plays the bar you are working on over and
over; change it while it plays and you hear the change the next time round.

## 4. Choose sounds

Pick a channel, then a sound from the list on the right: it plays a note so
you can hear it. **Volume** sets how loud the channel is.

## Repeating, and patterns

What a channel plays in a bar is a **pattern**, and its number is in the
grid. **Duplicate Bar** (Cmd+D) plays the same patterns again in the next
bar, so a change to one is heard in both, and the bars that share the
pattern you are editing are marked. **Make This Bar Unique** (Cmd+U) gives
a bar a copy of its own. Typing a number with the grid picked plays that
pattern there, and 0 plays nothing.

## Files

Songs are BeepBox's own song files (JSON), so they open in
[BeepBox](https://www.beepbox.co) (*File > Import*) and in fz's music editor,
and a BeepBox song exported as JSON opens here. Inside an fz project, songs
are kept in `assets/bgm`, and **Export WAV** (Cmd+E) writes the sound a game
plays beside the song.

## Keys

| Key | Does |
|-----|------|
| Space | play or stop |
| Left, Right | the bar before or after |
| Up, Down | the channel above or below |
| 0 to 9 | the pattern this cell plays |
| Cmd+Z, Cmd+Shift+Z | undo, redo |
| Cmd+D | duplicate the bar |
| Cmd+B | play this bar only |
| Cmd+L | loop the song |
]==]

frm.vwHelp.text = frm.TEXT
frm.vwHelp.textSize = 14

function frm.vwHelp:onLink(url)
  if url:match("^https?:") then gui.openurl(url) return true end
end

function frm.cmdClose:onClick() frm:close() end

function frm.open()
  frm:showModal()
end

return frm
