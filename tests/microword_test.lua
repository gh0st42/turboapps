-- tlua -p apps/microword -p tests tests/microword_test.lua

local t = require "testing"
local md = require "markdown"
local zmd = require "zmd"
local png = require "png"
local test, eq, ok = t.test, t.eq, t.ok

-- Reading, writing, laying out and editing Markdown are tlua's markdown
-- modules and its MarkdownEdit, and tested there; these are the files'
-- tests and the form's.

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

test("form: a table of contents goes in, and its links go to the headings", function()
  edit:load("# One\n\nsome text\n\n## Two\n\nmore\n")
  frm.actions.mnuToc()
  eq(edit:markdown(), "[[toc]]\n\n# One\n\nsome text\n\n## Two\n\nmore\n")
  -- A link to a heading is the editor's, not the system's to open.
  eq(edit:fire("onLink", "#two"), false)
  ok(edit:scrollTo("#two"))
  eq(edit.ed.caret.b, 4)
end)

test("form: a table is made, filled in cell by cell, and changed from the Table menu", function()
  local gui = require "gui"
  local ask, said = "2 x 2", nil
  gui.inputbox = function() return ask end
  gui.msgbox = function(text) said = text end
  edit:load("intro\n")
  edit.ed:moveToDocument(1)
  frm.actions.mnuTable()
  ok(edit.ed.cell, "the caret is in the first cell")
  typeKeys("A")
  key("Tab", "\t")
  typeKeys("B")
  key("Tab", "\t") typeKeys("1")
  key("Tab", "\t") typeKeys("2")
  eq(edit:markdown(), "intro\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n")
  key("Tab", "\t") -- past the last cell: a new row
  eq(#edit.ed.blocks[2].rows, 3)
  frm.actions.mnuColRight()
  eq(#edit.ed.blocks[2].align, 3)
  frm.actions.mnuAlignRight()
  ok(edit:markdown():find("| --- | ---: | --- |", 1, true) or edit:markdown():find("---: |", 1, true), edit:markdown())
  frm.actions.mnuDelRow()
  eq(#edit.ed.blocks[2].rows, 2)
  frm.actions.mnuDelCol()
  eq(#edit.ed.blocks[2].align, 2)
  -- Out of the table, the Table menu has nothing to change.
  key("Escape", "")
  edit.ed:setCaret { b = 1, o = 0 }
  frm.actions.mnuRowBelow()
  eq(said, "Put the caret in a table first.")
  ask = "many"
  said = nil
  frm.actions.mnuTable()
  ok(said, "a size that is not one is said so")
  eq(#edit.ed.blocks, 3)
end)

test("form: a password encrypts the whole document, and opening it asks", function()
  local gui = require "gui"
  local realBox = gui.passwordbox
  edit:load("# Secret plans\n")
  local file = root .. "/locked.zmd"
  gui.passwordbox = function() return "hunter2" end
  frm.actions.mnuPassword()
  ok(frm.caption:find("(encrypted)", 1, true), frm.caption)
  ok(frm.saveTo(file), "saved")
  -- Nothing readable is left in the file, and the module says it is locked.
  local f = io.open(file, "rb") local raw = f:read("*a") f:close()
  ok(not raw:find("Secret plans", 1, true), "the text is not in the file")
  local blocks, why, locked = zmd.load(file)
  eq(blocks, nil) eq(locked, "locked") ok(why:find("password"), why)
  blocks, why, locked = zmd.load(file, "nope")
  eq(locked, "locked") ok(why:find("wrong"), why)
  -- The form asks until the password is right, and keeps it for saving.
  local answers, asked = { "nope", "hunter2" }, 0
  gui.passwordbox = function() asked = asked + 1 return answers[asked] end
  edit:load("")
  ok(frm.openPath(file), "opened")
  eq(asked, 2)
  eq(edit:markdown(), "# Secret plans\n")
  ok(frm.caption:find("(encrypted)", 1, true), frm.caption)
  edit.ed:moveToDocument(1)
  typeKeys("!")
  ok(frm.saveTo(file), "saved again")
  eq(zmd.load(file, "hunter2") ~= nil, true)
  -- Cancelling the box does not open it; an empty password takes it off.
  gui.passwordbox = function() return nil end
  ok(not frm.openPath(file), "cancelled")
  gui.passwordbox = function() return "" end
  frm.actions.mnuPassword()
  ok(not frm.caption:find("encrypted", 1, true), frm.caption)
  ok(frm.saveTo(file))
  ok(zmd.load(file) ~= nil, "open without a password")
  gui.passwordbox = realBox
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
