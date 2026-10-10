-- tlua -p apps/microword -p tests tests/microword_test.lua

local t = require "testing"
local md = require "markdown"
local editor = require "editor"
local zmd = require "zmd"
local png = require "png"
local test, eq, ok = t.test, t.eq, t.ok

-- Reading and writing Markdown, and laying it out, are tlua's markdown
-- modules, and tested there; these are the editor's tests, the files' and
-- the form's.

---------------------------------------------------------------- editing

local function ed(text)
  return editor.new(md.parse(text or ""))
end

local function typeText(e, s)
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do e:type(ch) end
end

test("typing and Enter", function()
  local e = ed()
  typeText(e, "Hello")
  e:enter()
  typeText(e, "world")
  eq(e:markdown(), "Hello\n\nworld\n")
  eq(e.caret.b, 2); eq(e.caret.o, 5)
end)

test("markdown shortcuts at a paragraph's start", function()
  local e = ed()
  typeText(e, "## Head")
  eq(e:blockType(), "h2")
  e:enter()
  eq(e:blockType(), "p") -- after a heading comes a paragraph
  typeText(e, "- item")
  e:enter()
  typeText(e, "1. x")
  eq(e:markdown(), "## Head\n\n- item\n1. x\n")
  e:enter(); e:enter() -- Enter on an empty item ends the list
  eq(e:blockType(), "p")
  typeText(e, "---")
  e:enter()
  eq(e.blocks[#e.blocks - 1].type, "hr")
end)

test("bold while typing, and over a selection", function()
  local e = ed()
  typeText(e, "a ")
  e:toggle("b")
  typeText(e, "bold")
  e:toggle("b")
  typeText(e, " c")
  eq(e:markdown(), "a **bold** c\n")
  e.anchor, e.caret = { b = 1, o = 0 }, { b = 1, o = 1 }
  e:toggle("i")
  eq(e:markdown(), "*a* **bold** c\n")
  ok(e:isOn("i"), "on over the selection")
  e:toggle("i")
  eq(e:markdown(), "a **bold** c\n")
end)

test("Backspace and Delete across blocks", function()
  local e = ed("one\n\ntwo\n")
  e:setCaret { b = 2, o = 0 }
  e:backspace()
  eq(e:markdown(), "onetwo\n")
  eq(e.caret.o, 3)
  e:delete()
  eq(e:markdown(), "onewo\n")
  e:backspace(); e:backspace()
  eq(e:markdown(), "owo\n")
end)

test("Backspace at a heading's or item's start makes it a paragraph", function()
  local e = ed("# H\n\n    - x\n")
  e:setCaret { b = 1, o = 0 }
  e:backspace()
  eq(e:blockType(), "p")
  local f = ed("- a\n    - b\n")
  f:setCaret { b = 2, o = 0 }
  f:backspace()
  eq(f.blocks[2].level, 0)
  f:backspace()
  eq(f.blocks[2].type, "p")
end)

test("deleting a selection over several blocks", function()
  local e = ed("# Alpha\n\nbeta\n\ngamma\n")
  e.anchor, e.caret = { b = 1, o = 2 }, { b = 3, o = 3 }
  e:backspace()
  eq(e:markdown(), "# Alma\n")
end)

test("UTF-8 is moved over and deleted a character at a time", function()
  local e = ed()
  typeText(e, "héé")
  e:backspace()
  eq(e:markdown(), "hé\n")
  e:move(-1)
  eq(e.caret.o, 1)
end)

test("undo and redo", function()
  local e = ed()
  typeText(e, "abc")
  e:enter()
  typeText(e, "d")
  eq(e:markdown(), "abc\n\nd\n")
  e:undo()
  eq(e:markdown(), "abc\n"); eq(#e.blocks, 2) -- the empty paragraph is not written
  e:undo()
  eq(#e.blocks, 1)
  e:undo()
  eq(e:markdown(), "\n")
  e:redo(); e:redo()
  eq(#e.blocks, 2)
end)

test("links", function()
  local e = ed("see here now\n")
  e.anchor, e.caret = { b = 1, o = 4 }, { b = 1, o = 8 }
  e:setLink("https://x.org")
  eq(e:markdown(), "see [here](https://x.org) now\n")
  e:setCaret { b = 1, o = 6 }
  eq(e:linkAt(), "https://x.org")
  e:setLink("https://y.org") -- the link the caret is in changes
  eq(e:markdown(), "see [here](https://y.org) now\n")
  e:setLink("")
  eq(e:markdown(), "see here now\n")
end)

test("lists: kinds, toggling and indent", function()
  local e = ed("a\n\nb\n")
  e.anchor, e.caret = { b = 1, o = 0 }, { b = 2, o = 1 }
  e:setType("ul", true)
  eq(e:markdown(), "- a\n- b\n")
  e:setCaret { b = 2, o = 0 }
  ok(e:indent(1), "indented")
  eq(e:markdown(), "- a\n    - b\n")
  e.anchor, e.caret = { b = 1, o = 0 }, { b = 2, o = 1 }
  e:setType("ul", true) -- all lists already: back to paragraphs
  eq(e:markdown(), "a\n\nb\n")
end)

test("code blocks keep their text plain and their lines", function()
  local e = ed("**x** y\n")
  e:setType("code")
  eq(e:markdown(), "```\nx y\n```\n")
  e:setCaret { b = 1, o = 3 }
  e:enter()
  typeText(e, "z")
  eq(e:markdown(), "```\nx y\nz\n```\n")
  e:enter(); e:enter() -- Enter on an empty last line leaves the block
  eq(#e.blocks, 2)
  eq(e:blockType(), "p")
end)

test("pictures and rules", function()
  local e = ed("text\n")
  e:setCaret { b = 1, o = 4 }
  e:insertImage("assets/a.png", "a")
  eq(e:markdown(), "text\n\n![a](assets/a.png)\n")
  eq(e:blockType(), "p") -- the caret goes on after it
  e:setCaret { b = 2, o = 1 }
  e:backspace()
  eq(e:markdown(), "text\n")
  e:insertRule()
  ok(e:markdown():find("%-%-%-"), "a rule")
end)

test("tables, lists of contents and wiki links are kept as they were", function()
  local text = "[[toc]]\n\n# Head\n\n| a | b |\n| --- | ---: |\n| 1 | [[Page|go]] |\n\nsee [[Other Page]]\n"
  local e = ed(text)
  eq(e:markdown(), text)
  -- A table is one thing to the caret, as a picture is.
  e:setCaret { b = 3, o = 1 }
  e:backspace()
  eq(e:markdown(), "[[toc]]\n\n# Head\n\nsee [[Other Page]]\n")
  -- Typing inside a wiki link keeps it one.
  e:setCaret { b = #e.blocks, o = 5 }
  typeText(e, "X")
  eq(e:markdown(), "[[toc]]\n\n# Head\n\nsee [[Other Page|OXther Page]]\n")
end)

test("copy and paste keep the formatting", function()
  local e = ed("a **bold** word\n\nsecond\n")
  e.anchor, e.caret = { b = 1, o = 2 }, { b = 1, o = 6 }
  eq(e:copyText(), "**bold**")
  e.anchor, e.caret = { b = 1, o = 2 }, { b = 2, o = 3 }
  local text = e:copyText()
  eq(text, "**bold** word\n\nsec")
  e:setCaret { b = 2, o = 6 }
  e:paste(text)
  eq(e:markdown(), "a **bold** word\n\nsecond**bold** word\n\nsec\n")
  local f = ed("x\n")
  f:setCaret { b = 1, o = 1 }
  f:paste("- one\n- two")
  eq(f:markdown(), "xone\n\n- two\n")
end)

test("word and character counts", function()
  local w, c = ed("# Two words\n\nthree more words é\n"):stats()
  eq(w, 6); eq(c, 27)
end)

---------------------------------------------------------------- files

local root = os.tmpname()
os.remove(root)
require("lfs").mkdir(root)

local function picture()
  local img = png.new(4, 2, "#ff0000")
  return img:encode()
end

test("zmd: save and open keep the text and the pictures", function()
  local assets = { ["assets/red.png"] = zmd.asset(picture()), ["assets/unused.png"] = zmd.asset(picture()) }
  local blocks = md.parse("# Doc\n\n![red](assets/red.png)\n")
  local file = root .. "/doc.zmd"
  ok(zmd.save(file, blocks, assets), "saved")
  local f = io.open(file, "rb"); local head = f:read(2); f:close()
  eq(head, "PK")
  local back, got = zmd.load(file)
  eq(md.write(back), md.write(blocks))
  ok(got["assets/red.png"], "the picture came back")
  eq(got["assets/red.png"].image.width, 4)
  eq(got["assets/unused.png"], nil) -- pictures not in the document are not saved
end)

test("zmd: a .md opens with its pictures, and export writes them", function()
  require("lfs").mkdir(root .. "/assets")
  local f = io.open(root .. "/assets/p.png", "wb"); f:write(picture()); f:close()
  f = io.open(root .. "/plain.md", "wb"); f:write("Hi\n\n![p](assets/p.png)\n"); f:close()
  local blocks, assets = zmd.load(root .. "/plain.md")
  eq(#blocks, 2)
  ok(assets["assets/p.png"], "read from beside it")
  local out = root .. "/out"
  require("lfs").mkdir(out)
  ok(zmd.exportMarkdown(out .. "/x.md", blocks, assets), "exported")
  ok(io.open(out .. "/assets/p.png", "rb"), "the picture is beside it")
end)

test("zmd: not a document", function()
  local f = io.open(root .. "/bad.zmd", "wb"); f:write("PKnot really"); f:close()
  local blocks, err = zmd.load(root .. "/bad.zmd")
  eq(blocks, nil); ok(err:find("not a microword document"), "says why")
  eq(zmd.uniqueName({ ["assets/a.png"] = {} }, "/x/a.png"), "assets/a-2.png")
  eq(zmd.uniqueName({}, "/x/my pic.png"), "assets/my_pic.png")
end)

---------------------------------------------------------------- the form

-- Built without being shown: keys are the RichEdit's onKey fired as FLTK
-- would, and the menu its onClick.
local frm = require "forms.MicroWord"
local edit = frm.edDoc

local function key(k, text) return edit:fire("onKey", k, text or "") end
local function typeKeys(s)
  for ch in s:gmatch(".") do key(ch == " " and "Space" or ch, ch) end
end

test("form: typing, with the toolbar following", function()
  typeKeys("# Notes")
  eq(frm.cboStyle.selected, 2)
  key("Enter", "\r")
  eq(frm.cboStyle.selected, 1)
  frm.cmdBold:fire("onClick")
  typeKeys("loud")
  eq(frm.cmdBold.color, "#c9dcf7")
  eq(edit.ed:markdown(), "# Notes\n\n**loud**\n")
  eq(frm.caption, "*Untitled - microword")
  ok(frm.lblStatus.caption:find("2 words"), "counts words")
end)

test("form: keys move and select; Cmd keys go to the menu", function()
  key("Shift+Left", "")
  key("Shift+Left", "")
  eq(edit.ed:copyText(), "**ud**")
  eq(key("Cmd+b", "b"), false) -- the menu's shortcut, not typed
  frm.Menu1:fire("onClick", "mnuItalic")
  eq(edit.ed:markdown(), "# Notes\n\n**lo*****ud***\n")
  frm.Menu1:fire("onClick", "mnuUndo")
  eq(edit.ed:markdown(), "# Notes\n\n**loud**\n")
end)

test("form: the style box and list keys", function()
  frm.cboStyle.selected = 7
  frm.cboStyle:fire("onChange")
  eq(edit.ed:blockType(), "ul")
  eq(key("Tab", "\t"), true)
  eq(edit.ed.blocks[2].level, 1)
  key("Shift+Tab", "")
  key("Backspace", "\b")
  key("Backspace", "\b")
  eq(frm.cboStyle.selected, 7)
end)

test("form: save, then open again", function()
  local file = root .. "/form.zmd"
  ok(frm.saveTo(file), "saved")
  eq(frm.caption, "form.zmd - microword")
  local before = edit.ed:markdown()
  frm.Menu1:fire("onClick", "mnuSelectAll")
  key("Delete", "")
  eq(edit.ed:markdown(), "\n")
  ok(frm.openPath(file), "opened")
  eq(edit.ed:markdown(), before)
end)

test("form: a picture goes in at the caret, and is saved with the document", function()
  local pic = root .. "/assets/p.png"
  ok(frm.addPicture(pic), "added")
  ok(edit.ed:markdown():find("!%[p%]%(assets/p%.png%)"), "in the Markdown")
  local file = root .. "/withpic.zmd"
  frm.saveTo(file)
  local _, assets = zmd.load(file)
  ok(assets["assets/p.png"], "in the .zmd")
end)

-- Tidy up.
local function rmrf(p)
  local lfs = require "lfs"
  if lfs.attributes(p, "mode") == "directory" then
    for n in lfs.dir(p) do if n ~= "." and n ~= ".." then rmrf(p .. "/" .. n) end end
    lfs.rmdir(p)
  else
    os.remove(p)
  end
end
rmrf(root)
t.done("microword")
