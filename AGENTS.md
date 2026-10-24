# Working on turboapps

Notes for coding agents (and people) picking up work on this repository:
how it is built and tested, what tlua gives and does not give, and what
has been agreed about how to work. README.md describes the apps.

## What it is

Desktop apps written in [tlua](../tlua) with its `gui` module, one
`tlua design` project to a folder under `apps/`, each bundled by the
Makefile into `dist/<app>.ztl`: calculator, editor, files, imageviewer, pixel,
microword, microsheets, micronotes, microreader and microbrowser (and
chipstudio and desktop).

tlua lives beside this repository in `../tlua`, and the Makefile uses its
`bin/tlua` when it has been built. It has an AGENTS.md of its own; read it
before changing tlua.

## Agreements

These were agreed with the owner; keep to them.

- **Never commit without asking.** Finish the work, report it, say what is
  uncommitted and offer a message, then wait. An earlier "commit it" covers
  that one commit only. This holds in `../tlua` too.
- **Commit messages follow Conventional Commits:** `type(scope): summary`,
  such as `feat(chipstudio): show a retro scope of the channels as they
  play`. The types are feat, fix, docs, style, refactor, perf, test, build
  and chore; the scope is the app or area. The summary is short, lower-case
  and imperative, with no full stop. This holds in `../tlua` too.
- **Commit only your own changes.** The owner commits their own work, and
  bumps tlua's version, themselves. Leave their uncommitted files alone and
  unstaged, even when told to "commit it all".
- **Ask before working around a tlua limit.** When tlua lacks something or
  gets something wrong, stop and offer both: a workaround in the app, or a
  fix or feature in tlua (Go or its Lua modules). Recommend one, and prefer
  tlua when more than one app would gain. Patches to tlua are welcome:
  Canvas snapshots, MarkdownEdit, drop positions and zero-timeout TLS reads
  all went there instead of into apps. Leave tlua patches uncommitted,
  with a test, for the owner.
- **Screenshots show the app's window and nothing else.** Never capture the
  whole screen: it once showed the owner's mail. A region capture
  (`screencapture -R`) takes in any window lying over the app too, so do
  not use it. Capture the window by its id: `swift tools/windows.swift
  <pid>` lists the process's windows, and `screencapture -x -o -l<id>`
  takes the one with the app's title. If that is not possible, do not
  capture; debug through the app's output.
- **Stop only what you started.** The owner runs these apps while you work
  on them. Launch an app for a check with its PID kept (`cmd & pid=$!`),
  capture and stop that PID only. Never `pkill -f`, `killall` or a
  `pgrep | head` by name: that once closed the owner's ChipStudio with a
  song not saved. Find the window to capture by that PID as well.
- **Ask when a choice is the owner's** (what a feature should do, a file
  format, an app's name); decide the rest yourself and say what you chose.

## Building and testing

```sh
make                    # every app, as dist/<app>.ztl
make test               # the apps' tests, headless: no window opens
make check              # the tests, and the layouts as the designer writes them
make layouts            # rewrite hand-edited layouts (and .d.lua stubs) the designer's way
make run-microbrowser ARGS=gemini://geminiprotocol.net/
```

Before saying a change is done, run `make check`. A change to tlua's
markdown modules or its gui must keep this repository's `make check`
passing, and tlua's own tests (see its AGENTS.md).

- Tests are `tests/<app>_test.lua`, run with the app's folder on the module
  path. `require "forms.X"` builds a form without showing it; `obj:fire`
  raises its events.
- **Nothing may wait for a person.** Stub `gui.msgbox`, `gui.inputbox`,
  `gui.savefile`, `gui.openurl` and the app's own modal forms in tests;
  a modal dialog in a headless run hangs.
- Network tests run their own servers on 127.0.0.1, stepped in the same
  loop as the requests (tests/microbrowser_test.lua); they never reach
  the internet.

## How an app is laid out

```
apps/<app>/
  main.lua               shows the first form (as the designer writes it)
  <logic>.lua            the app's logic, with no GUI in it, tested directly
  controls/<Kind>.lua    controls of the app's own, gui.define'd, loaded by tlua
  forms/<Form>.form.lua  the layout: data, as the designer writes it
  forms/<Form>.lua       the code behind it: handlers, by control name
  forms/<Form>.d.lua     declarations for the language server, written by make layouts
  images/*.svg           button images, named from the layout as ../images/x.svg
```

Settings go in `~/.config/turboapps/<app>.lua` (or `$XDG_CONFIG_HOME`), a
Lua file read back with an empty environment. Each new app gets a row in
README.md's table, and README.md's note on the tlua version it needs.

## Style

Match the code around you. Comments are plain sentences that say what a
thing is or why, often starting with its name ("bookmark adds the page
shown..."). Names are short and plain. Each module opens with a comment on
what it is and how it is used. UI text is plain English, without jargon.

## tlua and gopher-lua: what bites

- Lua 5.1: no `goto`, no bit operators, no integer division.
- A `[[...]]` long string cannot hold `[[`: use `[==[ ... ]==]` (wiki links!).
- Lua patterns have no alternation (`a|b`).
- `x and f()` keeps only f's first result; write an if.
- Large integer table keys are very slow in gopher-lua: nest tables
  (`t[row][col]`), never `t[row * 100000 + col]`.
- A field of an object can shadow a method of the same name.
- **Every field set on a Canvas redraws it**: keep a control's state in a
  local table, not on the Canvas.
- **Names objects keep for themselves**: `show`, `showModal`, `close`,
  `add`, `on`, `focus`, `redraw`, `select`, `fire`, `find`, `remove`,
  `raise`, `lower`, `edit`, `insert`, `pointAt`, `editing`, `snapshot`, the
  kinds' names, and properties such as `items`, `kind`, `text`, `caption`.
  Do not name your own fields or functions on forms or controls after them
  (`frm.select = ...` breaks; use `frm.pick`).
- `grow` stretches by the bounding box of the controls that grow. A row of
  fixed controls with one growing control goes in a Panel (see any
  toolbar here).
- Menu items are named and handled in the Menu's `onClick(name)`; an item
  may carry its own function instead (`{ "Caption", fn }`). Assign
  `items` again after changing it. In a caption, `/` makes a submenu and
  `&` marks a letter.
- A Form's `onClose` runs for the close box, Escape and `close()`.
- Networking: LuaSocket and LuaSec (`socket`, `ssl`) come with tlua 0.6.2;
  use 0.6.3 or later, whose TLS reads with a timeout of 0 work.
  A window must never wait on the network: use `settimeout(0)` and poll
  from `gui.every` (see apps/microbrowser/net.lua).
- Fonts: `"sans"`, `"serif"`, `"mono"`, or any installed font by name;
  `gui.fonts()` lists them. Check before using one: naming a missing font
  is an error.
- tlua's markdown modules are built in: `markdown` (parse/write blocks),
  MarkdownView and MarkdownEdit. Build Markdown as blocks and
  `markdown.write` them rather than pasting strings, so text is escaped.

## Where things stand

- All apps' tests pass with `make check`.
- desktop's `categories.lua` is the user's own setup, written from the
  app (pixel is under Creativity there). Tests of the built-in categories
  put them in effect themselves (`withDefaults` in tests/desktop_test.lua)
  rather than read that file; leave its contents to the user.
- microbrowser (Gemini and Gopher, tabs, bookmarks, trust on first use, a
  VGA font and EGA colours) needs tlua 0.6.3, which has the fixes made for
  it: TLS receives with a timeout of 0, coroutines resumed after the
  chunk that made them, fonts by their installed names with
  `gui.fonts()`, and MarkdownView's `face` and `colors`.
- chipstudio (a chiptune editor for BeepBox songs) needs tlua 0.7.1: the
  `beepbox` and `audio` modules, and a form's `onKeyPreview`, for Space to
  play whatever has the focus. `beepbox` is fz's synthesiser: fz's `bbx/` module
  (github.com/gh0st42/fz/bbx, tagged `bbx/v0.1.0` with fz 0.8.0), which
  tlua requires. A change to the synthesiser is made in fz, tagged there,
  and taken into tlua with `go get github.com/gh0st42/fz/bbx@<tag>`. Its tests stand in for both
  modules (fakes in tests/chipstudio_test.lua), so they make no sound.
  Never play sound at full volume while trying things: volume 0, or none.
  Done: the song grid, the piano roll with note volume and bends, the
  keyboard as a piano that records, mute and solo, the other channels
  shown faintly in the roll, named drums, a scope of the channels as
  they play (drawn from the notes, not the sound), presets, undo, WAV, and
  OGG through ffmpeg (libvorbis, else ffmpeg's own vorbis encoder).
  Later, and optional: listing an fz project's assets/bgm songs to open by
  name (file dialogs do for now), BeepBox share URLs.
- pixel has an Advanced menu (a tilemap grid with tile numbers, copy, cut,
  paste and clear of tiles, focus on one tile, a hand tool). The hand
  pans with a Scroll's `scrollX` and `scrollY`, which tlua has from 0.7.2.
- imageviewer lists a folder's folders and its PNG, JPEG, GIF and WebP
  pictures, mixed in the order of their names (what tlua's `png` module
  reads), beside a Splitter's line to drag, and draws the one picked as big
  as fits on black. Animated GIF, APNG and WebP play from `png.frames`
  (tlua 0.8.1), a timer per frame; Space stops and starts them. The whole
  window is dark through `gui.colors` (tlua 0.8.2: FLTK's global colours,
  which a ListBox's text, scrollbars and dialogs follow; a ListBox's own
  `textColor` does nothing). Zoom and panning are arithmetic in view.lua
  (tested alone) and draw only the part that shows; Enter shows the picture
  on cnvFull, a second canvas over everything, with the window's
  `fullscreen` (tlua 0.8.3), the list and the status line put away. The
  last folder and the list's width are kept in settings.lua. It has no menu; Cmd (Ctrl) O, Cmd Up and
  F1 are keys of the form's. A ListBox keeps Up and Down for
  itself and takes Home, End, Page Up, Page Down and the letters for
  nothing useful, so the form's `onKeyPreview` does those, with Enter,
  Right, Backspace and Left, itself (tested against a real window).
- files selects several rows (FileList's `selection`), cuts, copies and
  pastes them: `fs.paste` makes a job (a coroutine, stepped from a timer so
  the window never waits, stopped with `job:cancel()`), and names a copy
  that would overwrite "a copy.txt". Moving is a rename, or a copy and a
  delete across disks. Copies keep the time changed and an executable's
  permissions (by `chmod` through the shell); links are copied as links.
  Dragging files between folders is not done. A double click opens a file
  in the app of ours for it (openwith.lua: `TYPES` by extension, found in
  a bundle beside the program, else in `TURBOAPPS_ROOT`, the folder above
  the program or the current one); the Desktop opens a file the same way.
  openwith.lua is the same file in apps/files and apps/desktop (a bundle
  holds its own): change one, copy it over the other; tests/openwith_test.lua
  checks they match, and `make test` runs it.
- files lists the drives Linux automounts (from /proc/self/mounts) and
  ejects them; it is tested against a mount table of the tests' own, and
  has not run on a Linux desktop yet.
