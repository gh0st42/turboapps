# turboapps

Desktop applications written in [tlua](../tlua) with its `gui` module, each
one a project that `tlua design` opens, edits and runs. They are shipped as
`.ztl` bundles: one zip file per app, which any tlua built with the GUI runs
on any platform.

| App | What it is |
|-----|------------|
| [chipstudio](apps/chipstudio) | Chiptune music, made as easily as it can be: a grid of channels against bars to pick a bar, and a piano roll with rows only for the notes of the song's scale, so whatever goes down fits. Notes sound as they are placed; a click inside a note makes a chord. Space plays from the bar picked, round again, or that bar alone while you work on it, and an edit is heard the next time round. Sounds are BeepBox's 176 named instruments, heard as they are picked. Songs are BeepBox's own JSON, so they go back and forth with [BeepBox](https://www.beepbox.co) and fz's music editor; inside an fz project they are kept in `assets/bgm`, and Export WAV writes the sound a game plays, or Export OGG a smaller one when ffmpeg is installed. |
| [calculator](apps/calculator) | A standard calculator: memory, %, √, 1/x, x², a history you can recall from, copy and paste, and the keyboard. |
| [microbrowser](apps/microbrowser) | A browser for the small internet: Gemini capsules and Gopher holes, in tabs, each with its own back and forward. Gemini pages are shown with their headings, lists, quotes and preformatted text, Gopher menus with what each item is; searches and input are asked for, pictures shown, other files saved. Bookmarks are in their menu and on the start page, and a dialog sorts them. A capsule's certificate is trusted the first time it is seen and checked after. Pages load a step at a time from a timer, so the window never waits. Pages visited are kept in a History (Cmd+Y: searched as you type, opened here or in a new tab, forgotten or cleared; the latest are in its menu), and Cmd+F opens a find bar over the page, with next, previous and a count. An optional sidebar (View > Outline, Cmd+Shift+O) lists the page's headings, indented by level, to jump to one with the mouse or the arrows. The tabs open on closing are there next time. Pages can be drawn in a fixed font, a VGA one when one is installed (Flexi IBM VGA, Perfect DOS VGA 437), and in a terminal's 16 EGA colours. |
| [microreader](apps/microreader) | A notebook from micronotes read as a book or a help file, never changed, as Windows' help and docsets were: contents, an index of every page and heading, a search that ranks the pages, back, forward, home and the pages before and after. A number at the start of a name orders it and is not shown. `tlua microreader.ztl manual.znb "Page#heading"` opens it at a topic, as a program opens its help. A book encrypted in micronotes asks for its password. |
| [microsheets](apps/microsheets) | A spreadsheet, like the terminal ones such as [vex](https://github.com/CodeOne45/vex-tui), in a window: formulas (`=SUM(B2:B9)`, 60-odd functions, references across sheets, `$` to fix them), several sheets, undo, copy and paste that moves formulas, fill, sort, filter, find, a frozen header row, column profiles, bar, line, sparkline and pie charts saved as PNG, a formula help with every function's parameters and examples, and themes. Keys work as a spreadsheet's, or as vim's (`hjkl`, `i`, `dd`, `yy`, `p`, `/`, `u`). Workbooks are `.zms` files: a zip of a CSV file of each sheet's values and a JSON file of its formulas, optionally encrypted with a password. It opens CSV and TSV files too. |
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

The apps need tlua 0.5.3 or later, built with the GUI (`make build` in
tlua; `make static` has no GUI). Microword, micronotes and microreader need
0.6.1 or later, whose MarkdownEdit edits Markdown as it looks and goes to its
headings, whose MarkdownView takes pictures from the program, and whose drops
on a Tree say where they landed. Passwords on documents, workbooks and notebooks, and the archive window of files, need tlua 0.9.3: 0.9.2 has the zip encryption, 0.9.3 the `gui.passwordbox` that asks for the password with dots shown. Find and replace in microword and micronotes, the browser's find bar, and the image viewer's turning and flipping need the tlua after 0.9.4: the editor's `find` and `replace`, a MarkdownView's `search(text, back)` and `matches`, and a png image's `rotate` and `flip`. Editing a table's cells in microword and micronotes needs tlua 0.9.1 or later (`insertTable` and the cell editing of MarkdownEdit); reading tables, in microreader and micronotes' Read view, works with any 0.6.1 or later. Microsheets saves charts as PNG with
`canvas:snapshot`. Microbrowser needs 0.6.3 or later, whose TLS reads
what has come without waiting, whose coroutines outlive the chunk that
made them, and whose MarkdownView draws in any installed font and in
colours of the program's. ChipStudio needs 0.7.1 or later:
its `beepbox` module renders BeepBox songs with fz's synthesiser, its
`audio` module plays them, and a form's `onKeyPreview` lets Space play and
stop whatever has the focus. Pixel uses the `png` module and sharp scaling, and files
its context menus; its hand tool moves a Scroll with `scrollX` and `scrollY`, which
come with 0.7.2. The image viewer needs 0.8.2 or later: 0.8.1 has the `png.frames` that gives it
animated GIF, APNG and WebP (and `png.load` reads WebP), 0.8.2 the `gui.colors` that
makes it dark, and 0.8.3 the `fullscreen` of a Form that shows a picture on the whole screen. The Makefile uses `../tlua/bin/tlua` when it has been built,
and `tlua` on PATH otherwise. `make TLUA=/path/to/tlua` picks another.

A `.ztl` is the app's folder zipped by `tlua bundle`, with `main.lua` at the
root. `tlua fuse -o calculator apps/calculator` makes a standalone executable
from the same folder instead.

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
