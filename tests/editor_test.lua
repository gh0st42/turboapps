-- tlua -p apps/editor -p tests tests/editor_test.lua

local t = require "testing"
local document = require "document"
local test, eq, ok = t.test, t.eq, t.ok

test("decode: LF", function()
  local text, eol = document.decode("a\nb\n")
  eq(text, "a\nb\n"); eq(eol, "\n")
end)

test("decode: CRLF round trip", function()
  local text, eol = document.decode("a\r\nb\r\n")
  eq(text, "a\nb\n"); eq(eol, "\r\n")
  eq(document.encode(text, eol), "a\r\nb\r\n")
end)

test("decode: old Mac CR and the BOM", function()
  local text = document.decode("\239\187\191a\rb")
  eq(text, "a\nb")
end)

test("write and read", function()
  local path = os.tmpname()
  ok(document.write(path, "one\ntwo\n", "\r\n"), "written")
  local f = io.open(path, "rb"); local raw = f:read("*a"); f:close()
  eq(raw, "one\r\ntwo\r\n")
  local text, eol = document.read(path)
  eq(text, "one\ntwo\n"); eq(eol, "\r\n")
  os.remove(path)
end)

test("read: missing file", function()
  local text, err = document.read("/no/such/file.txt")
  eq(text, nil); ok(err, "an error")
end)

test("basename", function()
  eq(document.basename(nil), "Untitled")
  eq(document.basename("/a/b/notes.txt"), "notes.txt")
  eq(document.basename("C:\\docs\\x.md"), "x.md")
end)

test("position", function()
  local text = "ab\ncdé\nf"
  local l, c = document.position(text, 0); eq(l, 1); eq(c, 1)
  l, c = document.position(text, 2); eq(l, 1); eq(c, 3)
  l, c = document.position(text, 3); eq(l, 2); eq(c, 1)
  l, c = document.position(text, 7); eq(l, 2); eq(c, 4)    -- after é, two bytes
  l, c = document.position(text, #text); eq(l, 3); eq(c, 2)
end)

test("stats", function()
  local s = document.stats("hello world\nhéllo\n")
  eq(s.lines, 3); eq(s.words, 3); eq(s.chars, 18)
  eq(document.stats("").lines, 1)
end)

test("find", function()
  local text = "One two one TWO"
  local i, j = document.find(text, "one", 1, {})
  eq(i, 1); eq(j, 3)                                   -- ignores case by default
  i = document.find(text, "one", 1, { matchCase = true }); eq(i, 9)
  i = document.find(text, "two", 6, {}); eq(i, 13)
  i = document.find(text, "two", 14, {}); eq(i, nil)
  i = document.find(text, "two", 14, { wrap = true }); eq(i, 5)
  i = document.find(text, "", 1, {}); eq(i, nil)
  i = document.find("a.b", ".", 1, {}); eq(i, 2)        -- plain text, not a pattern
end)

test("findBack", function()
  local text = "ab ab ab"
  local i, j = document.findBack(text, "ab", 7, {}); eq(i, 4); eq(j, 5)
  i = document.findBack(text, "ab", 3, {}); eq(i, 1)
  i = document.findBack(text, "ab", 2, {}); eq(i, nil)
  i = document.findBack(text, "ab", 2, { wrap = true }); eq(i, 7)
end)

test("replaceAll", function()
  local text, n = document.replaceAll("Cat cat CAT", "cat", "dog", {})
  eq(text, "dog dog dog"); eq(n, 3)
  text, n = document.replaceAll("Cat cat CAT", "cat", "dog", { matchCase = true })
  eq(text, "Cat dog CAT"); eq(n, 1)
  text, n = document.replaceAll("100%", "%", "%%", {})
  eq(text, "100%%"); eq(n, 1)
  text, n = document.replaceAll("aaa", "a", "aa", {})
  eq(text, "aaaaaa"); eq(n, 3)
end)

test("lineOffset", function()
  local text = "ab\ncd\nef"
  eq(document.lineOffset(text, 1), 0)
  eq(document.lineOffset(text, 2), 3)
  eq(document.lineOffset(text, 3), 6)
  eq(document.lineOffset(text, 99), #text)
end)

---------------------------------------------------------------- the forms

-- Built without being shown. Text boxes keep their text, but cursors and
-- selections are FLTK's and only there once a window is up, so what is
-- tried here is what does not need them.
local frm = require "forms.Editor"
local find = require "forms.Find"

local function menu(name, checked)
  frm.Menu1:fire("onClick", name, "", checked)
end

test("forms load and are titled", function()
  eq(frm.caption, "Untitled - Editor")
  eq(frm.txtText.visible, true)
  eq(frm.txtCode.visible, false)
end)

test("typing marks the document changed", function()
  frm.txtText.text = "hello"
  frm.txtText:fire("onChange")
  eq(frm.caption, "*Untitled - Editor")
end)

test("word wrap moves the text", function()
  frm.txtText.text = "some text"
  menu("mnuWrap", false)
  eq(frm.txtCode.visible, true)
  eq(frm.txtText.visible, false)
  eq(frm.txtCode.text, "some text")
  eq(frm.activeBox(), frm.txtCode)
  menu("mnuWrap", true)
  eq(frm.txtText.text, "some text")
  eq(frm.activeBox(), frm.txtText)
end)

test("zoom", function()
  local size = frm.txtText.fontSize
  menu("mnuZoomIn")
  eq(frm.txtText.fontSize, size + 2)
  eq(frm.txtCode.fontSize, size + 2)
  menu("mnuZoomReset")
  eq(frm.txtText.fontSize, size)
end)

test("replace all from the dialog", function()
  frm.txtText.text = "red green red"
  find.txtFind.text = "red"
  find.txtReplace.text = "blue"
  find.cmdReplaceAll:fire("onClick")
  eq(frm.txtText.text, "blue green blue")
  eq(find.lblResult.caption, "Replaced 2 matches")
end)

test("find buttons follow the search text", function()
  find.txtFind.text = ""
  find.txtFind:fire("onChange")
  eq(find.cmdFindNext.enabled, false)
  find.txtFind.text = "x"
  find.txtFind:fire("onChange")
  eq(find.cmdFindNext.enabled, true)
end)

t.done("editor")
