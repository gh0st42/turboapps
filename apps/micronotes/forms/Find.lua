-- The code behind Find.form.lua: the controls are fields of the form, by
-- the names the layout gives them. The form stays up beside the note while
-- you go on typing; it finds and replaces in whichever view the note is in,
-- through what the note's form gives it with attach:
--
--   find.attach(function() return target end)
--
-- A target is { find(needle, opts, back) -> found, wrapped,
-- replace(needle, with, opts) -> replaced, found, replaceAll(needle, with,
-- opts) -> how many, count(needle, opts) -> how many, which, selection() ->
-- text, canReplace = true or false }. The options are matchCase, whole and
-- wrap.

local gui = require "gui"
local frm = gui.load "Find" --[[@as forms.Find]]

local current -- the function that gives the target

-- attach tells the dialog where to find what it searches in.
function frm.attach(fn)
  current = fn
end

local function options()
  return { matchCase = frm.chkCase.checked, whole = frm.chkWhole.checked, wrap = frm.chkWrap.checked }
end

local function say(text)
  frm.lblResult.caption = text
end

local function target() return current() end

-- tally says how many matches there are, and which is selected.
local function tally(wrapped)
  local n, which = target().count(frm.txtFind.text, options())
  if n == 0 then return say("No match") end
  say(("%s of %d%s"):format(which > 0 and tostring(which) or "-", n, wrapped and ", from the top again" or ""))
end

-- findNext selects the next match (the one before, with back), and says
-- whether there was one. The note's Find Next calls it with the dialog
-- closed: what was typed in it is still there to search for.
function frm.findNext(back)
  local needle = frm.txtFind.text
  if needle == "" then
    frm.open(false)
    return false
  end
  local found, wrapped = target().find(needle, options(), back)
  if not found then
    say(("Cannot find \"%s\""):format(needle))
    if not frm.visible then gui.msgbox(("Cannot find \"%s\"."):format(needle), "ok", "micronotes") end
    return false
  end
  tally(wrapped)
  return true
end

function frm.cmdFindNext:onClick()
  frm.findNext(false)
end

function frm.cmdFindPrev:onClick()
  frm.findNext(true)
end

-- refuse says why nothing was replaced, in the view of a note that is read.
local function refuse()
  say("Replacing is for the Edit and Source views")
end

-- Replace replaces the match selected, then finds the next.
function frm.cmdReplace:onClick()
  local t = target()
  if frm.txtFind.text == "" then return end
  if not t.canReplace then return refuse() end
  local replaced, found = t.replace(frm.txtFind.text, frm.txtReplace.text, options())
  if found then
    tally(false)
  elseif replaced then
    say("Replaced; no more matches")
  else
    frm.findNext(false)
  end
end

function frm.cmdReplaceAll:onClick()
  local t = target()
  if frm.txtFind.text == "" then return end
  if not t.canReplace then return refuse() end
  local n = t.replaceAll(frm.txtFind.text, frm.txtReplace.text, options())
  say(n == 1 and "Replaced 1 match" or ("Replaced %d matches"):format(n))
end

function frm.cmdClose:onClick()
  frm:close()
end

function frm.txtFind:onChange()
  local any = self.text ~= ""
  for _, c in ipairs { frm.cmdFindNext, frm.cmdFindPrev, frm.cmdReplace, frm.cmdReplaceAll } do c.enabled = any end
  say("")
end

-- open shows the dialog, for finding or for replacing too, starting with
-- what is selected in the note when that is a line of text.
function frm.open(replacing)
  local sel = target().selection()
  if sel and sel ~= "" and not sel:find("\n") then frm.txtFind.text = sel end
  frm.caption = replacing and "Replace" or "Find"
  frm.txtFind:fire("onChange")
  frm:show()
  if replacing and frm.txtFind.text ~= "" then frm.txtReplace:focus() else frm.txtFind:focus() end
end

frm.txtFind:fire("onChange")

return frm
