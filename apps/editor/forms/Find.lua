-- The code behind Find.form.lua: the controls are fields of the form, by
-- the names the layout gives them. The form stays up beside the editor
-- while you go on typing; it works on whichever text box the editor gives
-- it with attach.

local gui = require "gui"
local document = require "document"
local frm = gui.load "Find" --[[@as forms.Find]]

local editor -- the editor's form, given by attach
local function box() return editor.activeBox() end

-- attach tells the dialog which editor it searches in.
function frm.attach(ed)
  editor = ed
end

local function options()
  return { matchCase = frm.chkCase.checked, wrap = frm.chkWrap.checked }
end

local function say(text)
  frm.lblResult.caption = text
end

-- selectionStart is where the selection begins, if the cursor is at its
-- end, as it is after the dialog selects a match.
local function selectionStart(b, text)
  local sel, cur = b.selectedText, b.cursor
  if sel ~= "" and cur >= #sel and text:sub(cur - #sel + 1, cur) == sel then
    return cur - #sel + 1
  end
  return cur + 1
end

-- findNext selects the next match (the one before, with back), and says
-- whether there was one. The editor's Find Next calls it with the dialog
-- closed: what was typed in it is still there to search for.
function frm.findNext(back)
  local needle = frm.txtFind.text
  if needle == "" then
    frm.open(false)
    return false
  end
  local b = box()
  local text = b.text
  local opts = options()
  local i, j
  if back then
    i, j = document.findBack(text, needle, selectionStart(b, text), opts)
  else
    local from = b.cursor + 1
    i, j = document.find(text, needle, from, opts)
    -- The selection is a match already, with the cursor before it: skip it.
    if i == from and b.selectedText ~= "" and b.selectedText == text:sub(i, j) then
      i, j = document.find(text, needle, i + 1, opts)
    end
  end
  if not i then
    say(("Cannot find \"%s\""):format(needle))
    if not frm.visible then gui.msgbox(("Cannot find \"%s\"."):format(needle), "ok", "Editor") end
    return false
  end
  b:select(i, j)
  local line = document.position(text, i)
  say(("Found on line %d"):format(line))
  return true
end

function frm.cmdFindNext:onClick()
  frm.findNext(false)
end

function frm.cmdFindPrev:onClick()
  frm.findNext(true)
end

-- Replace replaces the selection if it is a match, then finds the next.
function frm.cmdReplace:onClick()
  local b = box()
  if document.matches(b.selectedText, frm.txtFind.text, options()) then
    b:insert(frm.txtReplace.text)
  end
  frm.findNext(false)
end

function frm.cmdReplaceAll:onClick()
  local b = box()
  local needle = frm.txtFind.text
  local text, n = document.replaceAll(b.text, needle, frm.txtReplace.text, options())
  if n > 0 then
    local line = b.line
    b.text = text
    b.line = line
    editor.changed()
  end
  say(n == 1 and "Replaced 1 match" or ("Replaced %d matches"):format(n))
end

function frm.cmdClose:onClick()
  frm:close()
end

function frm.txtFind:onChange()
  local any = self.text ~= ""
  frm.cmdFindNext.enabled = any
  frm.cmdFindPrev.enabled = any
  frm.cmdReplace.enabled = any
  frm.cmdReplaceAll.enabled = any
  say("")
end

-- open shows the dialog, for finding or for replacing too, starting with
-- what is selected in the editor when that is a single line.
function frm.open(replacing)
  local sel = box().selectedText
  if sel ~= "" and not sel:find("\n") then frm.txtFind.text = sel end
  frm.caption = replacing and "Replace" or "Find"
  frm.txtFind:fire("onChange")
  frm:show()
  if replacing and frm.txtFind.text ~= "" then frm.txtReplace:focus() else frm.txtFind:focus() end
end

frm.txtFind:fire("onChange")

return frm
