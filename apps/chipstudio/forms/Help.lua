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

Click in the roll to put a note down, a step long; it sounds as it goes in.
Drag to make it longer, drag a note to move it, drag its end to stretch it, and click a
note to take it away (or right-click it). Clicking inside a note that is
already sounding adds another pitch to it: a chord.

The roll only has rows for the notes of the song's **scale**, so whatever
you put down fits. The rows of the key are lit.

The notes the other channels play in the bar show faintly behind, in their
colours, so a harmony or a bass is easy to write against the lead. **View >
Show Other Channels** (Cmd+G) hides them; muted channels never show.

On a drum channel the rows are its drums, kick at the bottom and crash at
the top.

## 3. Listen

**Space** plays from the bar you picked, and goes round again while
**Loop** is on. **This bar only** plays the bar you are working on over and
over; change it while it plays and you hear the change the next time round.

While it plays, the screen beside the grid shows each channel's wave, as an
old oscilloscope would: higher notes make tighter waves, louder ones taller,
and drums crackle as noise.

## 4. Choose sounds

Pick a channel, then a sound from the list on the right: it plays a note so
you can hear it. **Volume** sets how loud the channel is.

## Louder, softer, and bends

Above the roll, **Volume** and **Bend** change what a drag does. In
**Volume**, drag a note up or down to make it louder or quieter where you
grab it: at its start, its end, or anywhere between, so it can swell or
fade away. In **Bend**, drag a note to the row it should slide to. Notes are
drawn as thick as they are loud, and a bend as a line. A right click puts a
point back; **Edit > Flatten Notes in Bar** takes the shapes away.

## Playing on the keyboard

The two rows of letters are a keyboard: **Z X C V B N M , . /** play the
scale going up, and **Q W E R T Y U I O P** the same an octave higher, so
every key is in tune. **-** and **=** move the keyboard an octave.

Turn on **Record** (Cmd+R) and the keys write notes, as long as **Keys
write** says. While the song plays they go where it is playing; while it is
stopped they go one after another from the red line, on into the next bar.

## Mute and solo

The **M** beside a channel's name mutes it; the **S** plays it alone (or
with the others that have theirs on). They are for listening: the song
saved and exported has every channel.

## Repeating, and patterns

What a channel plays in a bar is a **pattern**, and its number is in the
grid. **Duplicate Bar** (Cmd+D) plays the same patterns again in the next
bar, so a change to one is heard in both, and the bars that share the
pattern you are editing are marked. **Make This Bar Unique** (Cmd+U) gives
a bar a copy of its own.

To play a pattern again later, as BeepBox does, pick the bar and step its
**Pattern** number (above the roll, or **[** and **]**) to the one you want:
bar 4 set to pattern 1 plays what bar 1 plays, and a change in either is
heard in both. One past the last number is a new, empty pattern; 0 plays
nothing. Typing 0 to 9 sets the number straight away.

## Files

Songs are BeepBox's own song files (JSON), so they open in
[BeepBox](https://www.beepbox.co) (*File > Import*) and in fz's music editor,
and a BeepBox song exported as JSON opens here. Inside an fz project, songs
are kept in `assets/bgm`, and **Export WAV** (Cmd+E) writes the sound a game
plays beside the song. **Export OGG** (Cmd+Shift+E) writes a smaller one,
through [ffmpeg](https://ffmpeg.org) when it is installed.

## Keys

| Key | Does |
|-----|------|
| Space | play or stop, wherever the focus is |
| Left, Right | the bar before or after |
| Up, Down | the channel above or below |
| 0 to 9 | the pattern this cell plays |
| [ and ] | the pattern before or after |
| Cmd+Z, Cmd+Shift+Z | undo, redo |
| Cmd+D | duplicate the bar |
| Cmd+B | play this bar only |
| Cmd+L | loop the song |
| Z to /, Q to P | play the scale (and record, with Record on) |
| - and = | the keyboard an octave down, up |
| Cmd+R | record from the keyboard |
| Cmd+1, 2, 3 | drag notes, volume, bends |
| Cmd+G | show or hide the other channels' notes |
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
