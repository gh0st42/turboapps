# turboapps

Desktop applications written in [tlua](../tlua) with its `gui` module, each
one a project that `tlua design` opens, edits and runs. They are shipped as
`.ztl` bundles: one zip file per app, which any tlua built with the GUI runs
on any platform.

| App | What it is |
|-----|------------|
| [chipstudio](apps/chipstudio) | Chiptune music, made as easily as it can be: a grid of channels against bars to pick a bar, and a piano roll with rows only for the notes of the song's scale, so whatever goes down fits. Notes sound as they are placed; a click inside a note makes a chord. Space plays from the bar picked, round again, or that bar alone while you work on it, and an edit is heard the next time round. Sounds are BeepBox's 176 named instruments, heard as they are picked. Songs are BeepBox's own JSON, so they go back and forth with [BeepBox](https://www.beepbox.co) and fz's music editor; inside an fz project they are kept in `assets/bgm`, and Export WAV writes the sound a game plays, or Export OGG a smaller one when ffmpeg is installed. |
| [calculator](apps/calculator) | A standard calculator: memory, %, √, 1/x, x², a history you can recall from, copy and paste, and the keyboard. |
| [microbrowser](apps/microbrowser) | A browser for the small internet: Gemini capsules and Gopher holes, in tabs, each with its own back and forward. Gemini pages are shown with their headings, lists, quotes and preformatted text, Gopher menus with what each item is; searches and input are asked for, pictures shown, other files saved. Bookmarks are in their menu and on the start page, and a dialog sorts them. A capsule's certificate is trusted the first time it is seen and checked after. Pages load a step at a time from a timer, so the window never waits. Files that are not pages (a Gopher file, a Gemini type that is not text or a picture, or Download Link on a link's menu) are saved to the Downloads folder in the background as they come, a tab keeping the page it had; View > Downloads (Cmd+J) lists them with how each is going, to stop one, open it or its folder, and choose the folder. Pages visited are kept in a History (Cmd+Y: searched as you type, opened here or in a new tab, forgotten or cleared; the latest are in its menu), and Cmd+F opens a find bar over the page, with next, previous and a count. An optional sidebar (View > Outline, Cmd+Shift+O) lists the page's headings, indented by level, to jump to one with the mouse or the arrows. The tabs open on closing are there next time. Pages can be drawn in a fixed font, a VGA one when one is installed (Flexi IBM VGA, Perfect DOS VGA 437), and in a terminal's 16 EGA colours. |
| [microreader](apps/microreader) | A notebook from micronotes read as a book or a help file, never changed, as Windows' help and docsets were: contents, an index of every page and heading, a search that ranks the pages, back, forward, home and the pages before and after. A number at the start of a name orders it and is not shown. `tlua microreader.ztl manual.znb "Page#heading"` opens it at a topic, as a program opens its help. A book encrypted in micronotes asks for its password. |
| [microsheets](apps/microsheets) | A spreadsheet, like the terminal ones such as [vex](https://github.com/CodeOne45/vex-tui), in a window: formulas (`=SUM(B2:B9)`, 60-odd functions, references across sheets, `$` to fix them), several sheets, undo, copy and paste that moves formulas, fill, sort, filter, find, a frozen header row, column profiles, bar, line, sparkline and pie charts saved as PNG, conditional formatting (Data > Conditional Formatting: cells compared with a number, text or another cell, between, empty, errors, duplicates, top and bottom, above and below average, a formula, colour scales and data bars, each with a look of its own and in an order that says which wins, kept in the workbook and with undo), a formula help with every function's parameters and examples, and themes. Keys work as a spreadsheet's, or as vim's (`hjkl`, `i`, `dd`, `yy`, `p`, `/`, `u`). Workbooks are `.zms` files: a zip of a CSV file of each sheet's values and a JSON file of its formulas, optionally encrypted with a password. It opens CSV and TSV files too. |
| [micronotes](apps/micronotes) | Notes like Obsidian's: a tree of notes and folders on the left, the note on the right, read with its links followed (as it starts), edited as it looks, or edited as Markdown source, switched with Cmd+E or the buttons. Notes, files and folders are dragged in the tree into folders, and a note dragged onto the one open links to it. Notes link with `[[Note Name]]` (type `[[` to pick one; a link to a note not there yet makes it), and the notes linking back are listed. Pictures and files dropped on a note go into the notebook. Tables are edited in their cells, as in microword, and Cmd+F finds and Cmd+R replaces in the note in any of its three views. The search box looks through every note's name and text (words, "a phrase", -leftout) and lists what it finds, the likeliest first, each with a piece of its text, to open at the place found; notes are tagged by writing #tag in them (or `tags:` in front matter), a # button lists the tags, and a tag in a note being read is a link to the notes that have it. A notebook is one `.znb` file: a zip of the notes as Markdown in their folders, with `attachments/`, saved by itself a moment after each change, optionally encrypted with a password; folders of notes import and export. |
| [microword](apps/microword) | A word processor that edits Markdown as it looks: headings, bold, italic, code, links, bullet and numbered lists, quotes, code blocks, rules and pictures, with find and replace (Cmd+F, Cmd+G, Cmd+R: match case, whole words, one at a time or all, as one step of undo), tables edited in their cells (click in one, Tab to the next, a Tab past the last adds a row, and a Table menu for rows, columns and alignment), Markdown shortcuts as you type (`# `, `- `, `1. `, `> `), undo, and the clipboard. Documents are `.zmd` files: a zip of `document.md` and the pictures in `assets/`, optionally encrypted all through with a password (File > Set Password, AES-256, which 7-Zip opens). It opens `.md` too and exports to it. |
| [pixel](apps/pixel) | A pixel art editor: pen, brush, eraser, fill, line, rectangle, ellipse and picker, with a right-click that picks up colours, transparency, undo and redo, zoom and a grid, and an optional tilemap grid (8 to 64 pixels) that keeps drawing and fills to one tile, with numbered tiles you can copy, cut, paste and clear, a hand tool, and a focus mode that shows one tile big. Pictures are drawn in the 32 PICO-8 / Picotron colours or the 256 VGA ones, switched at any time, saved as PNG, and opened from PNG, GIF or JPEG. |
| [imageviewer](apps/imageviewer) | A simple image viewer, all from the keyboard: the folders and the PNG, JPEG, GIF and WebP pictures in a folder on the left, mixed in the order of their names, and the picture on the right as big as fits on black, with a line between them to drag. Animated GIF, PNG and WebP pictures play, and Space stops and starts them. Cmd and = or -, the wheel, or a double click zoom, a picture bigger than the window is dragged or moved with Shift and the arrows, Cmd R turns it, Cmd Shift R turns it back, and Cmd Shift H and V flip it (as shown: the file is not changed), and Enter shows it alone on the whole screen, where the arrows go from picture to picture. Zip files and comic books (`.cbz`) are folders in it: Enter goes into one (an encrypted one asks for its password), Cmd Shift O opens one, and dropping one on the window does too. It remembers the folder and how wide the list was, is dark all through, to be easy on the eyes in a dark room, and has no menu. Up and Down move through the list, Enter or Right opens a folder, Backspace or Left goes up, and a letter jumps to the next name that starts with it. |
| [files](apps/files) | A file manager: back, forward, up and a path you can type, places, a list sorted by any column, hidden files left out unless asked for, several files selected (Shift, Cmd and Cmd+A) to cut, copy, paste and delete, folders too, with a paste that goes on in the background and stops with Escape, new folder, rename, a context menu on files and on the folder, and a settings dialog. A double click opens a picture in the image viewer, a spreadsheet in MicroSheets and so on, in the apps of this folder, or in the system's program (Open With picks, and a setting turns it off). On Linux, drives mounted by themselves when plugged in (USB sticks, SD cards) appear among the places as they come and go, and eject from the File menu, the folder's menu or the places' (udisks, else gio, else umount). Zip files: Compress to Zip (and New Zip File on the folder's menu) packs what is selected, with a password if wanted; a double click on a `.zip` shows what is in it (asking for the password of an encrypted one), to unpack all of it into a folder of its own or elsewhere, or the files selected, to add files by dropping them on that window or with a button, to delete files from it, and to encrypt it or take the encryption off. The menu does the same for `.zmd`, `.znb`, `.zms` and `.ztl`. Unpacking never overwrites a file. Double-clicking a `.ztl` runs it with tlua; other files open in their own programs. The keyboard does everything the mouse does. |
| [editor](apps/editor) | A plain text editor: open, save and save as, find and replace, go to line, word wrap or line numbers, zoom, drag and drop, and a status line. It keeps a file's line endings as it found them. |
| [desktop](apps/desktop) | A virtual desktop and program manager for turboapps: it discovers apps from `apps/`, launches them from their bundles in `dist/` when present, offers both a flat app list and a category view, lets categories be edited and saved from inside the Desktop app, opens a file in the app for it (Open File with App), opens any app project directly in `tlua design`, and shows the designer itself as Visual Turbo Lua. |

## Building and running

```sh
make                    # every app, as dist/<app>.ztl
make calculator         # one app
make run-editor         # bundle it and run it
make run-editor ARGS=notes.txt
tlua dist/editor.ztl notes.txt
```

The apps are built, tested and released with **tlua 0.9.6**, the release named
in `.tlua-version`, and that is the one to use. It must be built with the GUI
(`make build` in tlua; the static builds have no GUI). The Makefile uses
`../tlua/bin/tlua` when it has been built, and `tlua` on PATH otherwise;
`make TLUA=/path/to/tlua` picks another.

Older releases run some of the apps. The oldest each needs, and why:

| App | tlua | What it needs |
|-----|------|---------------|
| calculator, editor, desktop | 0.5.3 | the `gui` module |
| microreader | 0.9.3 | encrypted books (`zip` passwords, `gui.passwordbox`) |
| microsheets | 0.9.3 | encrypted workbooks |
| files | 0.9.3 | zip files, with passwords |
| microword, micronotes | 0.9.5 | find and replace, and tables edited in place (0.9.1), in MarkdownEdit; encrypted files (0.9.3) |
| microbrowser | 0.9.5 | MarkdownView's `search` and `matches` for the find bar; TLS reads that do not wait (0.6.3) |
| imageviewer | 0.9.5 | turning and flipping (`rotate`, `flip`); animated pictures (0.8.1), `gui.colors` (0.8.2), `Form.fullscreen` (0.8.3) |
| pixel | 0.7.2 | `scrollX` and `scrollY` for the hand tool |
| chipstudio | 0.7.1 | `beepbox` and `audio`, and `onKeyPreview` |

A `.ztl` is the app's folder zipped by `tlua bundle`, with `main.lua` at the
root. `tlua fuse -o calculator apps/calculator` makes a standalone executable
from the same folder instead.

## Releases

Pushing a tag such as `v0.2.0` makes a GitHub release (`.github/workflows/release.yml`):
the source, every app as a `.ztl` (and all of them in a zip), and every app as a
native program, one archive each for Linux amd64 and arm64, macOS arm64 and
Windows amd64, each program fused onto that platform's tlua (`tlua fuse --base`).
The macOS programs are not signed (`xattr -dr com.apple.quarantine .` if one is
refused), and Windows ones open a console window beside the app. The tlua they are
built on is the release named in `.tlua-version`: change it, and nothing else, to
move to a newer one. `scripts/package.sh VERSION` does the same by hand into
`release/`; `.github/workflows/ci.yml` tests every push on Linux and macOS and
tries the packing.

## Working on an app

```sh
make design-calculator  # open it in tlua's form designer
make test               # the apps' tests, headless: no window opens
make check              # the tests, and the layouts checked as the designer writes them
make layouts            # rewrite hand-edited layouts the way the designer would
```

Each app is laid out as `tlua design` lays out a project:

```
apps/editor/
  main.lua                 shows the first form (as the designer writes it)
  document.lua             the app's logic, with no GUI in it
  forms/Editor.form.lua    the layout: the designer's, rewritten on every save
  forms/Editor.lua         the code behind it: handlers, by control name
  forms/Editor.d.lua       the controls, for the language server: written on save
  forms/Find.form.lua ...  more forms, the same way
```

- **Layouts** are data. Change them in the designer, or by hand and then run
  `make layouts` so they come out as the designer writes them. `make check`
  fails when one does not, so a hand edit never leaves the designer
  rewriting the whole file on its next save.
- **Code** goes in `forms/<Form>.lua`. The designer only adds empty handlers
  to it.
- **Images** for buttons are in the app's `images/`, named from a layout
  relative to `forms/` (`../images/pen.svg`), as the designer names them.
  They are SVG, which FLTK draws at the screen's resolution.
- **Logic** that is not about the screen goes in a plain module beside
  `main.lua` (`engine.lua`, `document.lua`), so it can be tested without a
  window.

Desktop's categories are configured in `apps/desktop/categories.lua`.
You can edit and save them in the Desktop app itself, or edit `order` and
`map` in that file by hand.

### Adding an app

1. `tlua design apps/myapp`, and accept the offer to start a project there.
2. Draw the forms, write their code, and F5 to run it.
3. `make myapp` bundles it as `dist/myapp.ztl`. Any folder in `apps/` with a
   `main.lua` is picked up.
4. Tests go in `tests/myapp_test.lua`, which `make test` runs with
   `apps/myapp` on the module path. `require "forms.X"` builds a form without
   showing it, and `frm.cmdOK:fire("onClick")` presses its buttons: see
   [tests/calculator_test.lua](tests/calculator_test.lua).
