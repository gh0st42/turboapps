# turboapps

Desktop applications written in [tlua](../tlua) with its `gui` module, each
one a project that `tlua design` opens, edits and runs. They are shipped as
`.ztl` bundles: one zip file per app, which any tlua built with the GUI runs
on any platform.

| App | What it is |
|-----|------------|
| [calculator](apps/calculator) | A standard calculator: memory, %, √, 1/x, x², a history you can recall from, copy and paste, and the keyboard. |
| [microbrowser](apps/microbrowser) | A browser for the small internet: Gemini capsules and Gopher holes, in tabs, each with its own back and forward. Gemini pages are shown with their headings, lists, quotes and preformatted text, Gopher menus with what each item is; searches and input are asked for, pictures shown, other files saved. Bookmarks are in their menu and on the start page, and a dialog sorts them. A capsule's certificate is trusted the first time it is seen and checked after. Pages load a step at a time from a timer, so the window never waits. The tabs open on closing are there next time. Pages can be drawn in a fixed font, a VGA one when one is installed (Flexi IBM VGA, Perfect DOS VGA 437), and in a terminal's 16 EGA colours. |
| [microreader](apps/microreader) | A notebook from micronotes read as a book or a help file, never changed, as Windows' help and docsets were: contents, an index of every page and heading, a search that ranks the pages, back, forward, home and the pages before and after. A number at the start of a name orders it and is not shown. `tlua microreader.ztl manual.znb "Page#heading"` opens it at a topic, as a program opens its help. |
| [microsheets](apps/microsheets) | A spreadsheet, like the terminal ones such as [vex](https://github.com/CodeOne45/vex-tui), in a window: formulas (`=SUM(B2:B9)`, 60-odd functions, references across sheets, `$` to fix them), several sheets, undo, copy and paste that moves formulas, fill, sort, filter, find, a frozen header row, column profiles, bar, line, sparkline and pie charts saved as PNG, a formula help with every function's parameters and examples, and themes. Keys work as a spreadsheet's, or as vim's (`hjkl`, `i`, `dd`, `yy`, `p`, `/`, `u`). Workbooks are `.zms` files: a zip of a CSV file of each sheet's values and a JSON file of its formulas. It opens CSV and TSV files too. |
| [micronotes](apps/micronotes) | Notes like Obsidian's: a tree of notes and folders on the left, the note on the right, read with its links followed (as it starts), edited as it looks, or edited as Markdown source, switched with Cmd+E or the buttons. Notes, files and folders are dragged in the tree into folders, and a note dragged onto the one open links to it. Notes link with `[[Note Name]]` (type `[[` to pick one; a link to a note not there yet makes it), and the notes linking back are listed. Pictures and files dropped on a note go into the notebook. A notebook is one `.znb` file: a zip of the notes as Markdown in their folders, with `attachments/`, saved by itself a moment after each change; folders of notes import and export. |
| [microword](apps/microword) | A word processor that edits Markdown as it looks: headings, bold, italic, code, links, bullet and numbered lists, quotes, code blocks, rules and pictures, with Markdown shortcuts as you type (`# `, `- `, `1. `, `> `), undo, and the clipboard. Documents are `.zmd` files: a zip of `document.md` and the pictures in `assets/`. It opens `.md` too and exports to it. |
| [pixel](apps/pixel) | A pixel art editor: pen, brush, eraser, fill, line, rectangle, ellipse and picker, with a right-click that picks up colours, transparency, undo and redo, zoom and a grid. Pictures are drawn in the 32 PICO-8 / Picotron colours or the 256 VGA ones, switched at any time, saved as PNG, and opened from PNG, GIF or JPEG. |
| [files](apps/files) | A file manager: back, forward, up and a path you can type, places, a list sorted by any column, hidden files left out unless asked for, new folder, rename, delete, a context menu on files and on the folder, and a settings dialog. Double-clicking a `.ztl` runs it with tlua; other files open in their own programs. The keyboard does everything the mouse does. |
| [editor](apps/editor) | A plain text editor: open, save and save as, find and replace, go to line, word wrap or line numbers, zoom, drag and drop, and a status line. It keeps a file's line endings as it found them. |
| [desktop](apps/desktop) | A virtual desktop and program manager for turboapps: it discovers apps from `apps/`, launches them from their bundles in `dist/` when present, offers both a flat app list and a category view, lets categories be edited and saved from inside the Desktop app, opens any app project directly in `tlua design`, and shows the designer itself as Visual Turbo Lua. |

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
on a Tree say where they landed. Microsheets saves charts as PNG with
`canvas:snapshot`. Microbrowser needs the tlua after 0.6.2, whose TLS
reads what has come without waiting, whose coroutines outlive the
chunk that made them, and whose MarkdownView draws in any installed font
and in colours of the program's. Pixel uses the `png` module and sharp scaling, and files
its context menus. The Makefile uses `../tlua/bin/tlua` when it has been built,
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
