# turboapps

Desktop applications written in [tlua](../tlua) with its `gui` module, each
one a project that `tlua design` opens, edits and runs. They are shipped as
`.ztl` bundles: one zip file per app, which any tlua built with the GUI runs
on any platform.

| App | What it is |
|-----|------------|
| [calculator](apps/calculator) | A standard calculator: memory, %, √, 1/x, x², a history you can recall from, copy and paste, and the keyboard. |
| [microsheets](apps/microsheets) | A spreadsheet, like the terminal ones such as [vex](https://github.com/CodeOne45/vex-tui), in a window: formulas (`=SUM(B2:B9)`, 60-odd functions, references across sheets, `$` to fix them), several sheets, undo, copy and paste that moves formulas, fill, sort, filter, find, a frozen header row, column profiles, bar, line, sparkline and pie charts saved as PNG, a formula help with every function's parameters and examples, and themes. Keys work as a spreadsheet's, or as vim's (`hjkl`, `i`, `dd`, `yy`, `p`, `/`, `u`). Workbooks are `.zms` files: a zip of a CSV file of each sheet's values and a JSON file of its formulas. It opens CSV and TSV files too. |
| [microword](apps/microword) | A word processor that edits Markdown as it looks: headings, bold, italic, code, links, bullet and numbered lists, quotes, code blocks, rules and pictures, with Markdown shortcuts as you type (`# `, `- `, `1. `, `> `), undo, and the clipboard. Documents are `.zmd` files: a zip of `document.md` and the pictures in `assets/`. It opens `.md` too and exports to it. |
| [pixel](apps/pixel) | A pixel art editor: pen, brush, eraser, fill, line, rectangle, ellipse and picker, with a right-click that picks up colours, transparency, undo and redo, zoom and a grid. Pictures are drawn in the 32 PICO-8 / Picotron colours or the 256 VGA ones, switched at any time, saved as PNG, and opened from PNG, GIF or JPEG. |
| [files](apps/files) | A file manager: back, forward, up and a path you can type, places, a list sorted by any column, hidden files left out unless asked for, new folder, rename, delete, a context menu on files and on the folder, and a settings dialog. Double-clicking a `.ztl` runs it with tlua; other files open in their own programs. The keyboard does everything the mouse does. |
| [editor](apps/editor) | A plain text editor: open, save and save as, find and replace, go to line, word wrap or line numbers, zoom, drag and drop, and a status line. It keeps a file's line endings as it found them. |

## Building and running

```sh
make                    # every app, as dist/<app>.ztl
make calculator         # one app
make run-editor         # bundle it and run it
make run-editor ARGS=notes.txt
tlua dist/editor.ztl notes.txt
```

The apps need tlua 0.5.0 or later built with the GUI, and microword a tlua
with the `markdown` modules (the one after 0.5.2), which read, lay out and
draw its documents as tlua's MarkdownView does; microsheets needs a Canvas
that draws bold and italic (`g:font(name, size, "bold italic")`), and also
saves charts with `canvas:snapshot` (`make build` in tlua;
`make static` has no GUI). Pixel uses its `png` module and sharp scaling,
files its context menus. The Makefile uses `../tlua/bin/tlua` when it has been built,
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

### Adding an app

1. `tlua design apps/myapp`, and accept the offer to start a project there.
2. Draw the forms, write their code, and F5 to run it.
3. `make myapp` bundles it as `dist/myapp.ztl`. Any folder in `apps/` with a
   `main.lua` is picked up.
4. Tests go in `tests/myapp_test.lua`, which `make test` runs with
   `apps/myapp` on the module path. `require "forms.X"` builds a form without
   showing it, and `frm.cmdOK:fire("onClick")` presses its buttons: see
   [tests/calculator_test.lua](tests/calculator_test.lua).
