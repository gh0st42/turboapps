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
