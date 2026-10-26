-- The code behind Find.form.lua: the controls are fields of the form, by
-- the names the layout gives them. The form stays up beside the document
-- while you go on typing; it finds and replaces in the editor the document
-- form gives it with attach:
--
--   find.attach { ed = function() return the markdown editor end,
--                 changed = function() ... end, moved = function() ... end }
--
-- changed is called after text is replaced, moved after a match is selected.

local gui = require "gui"
local frm = gui.load "Find" --[[@as forms.Find]]

local host

-- attach tells the dialog which document it searches in.
function frm.attach(h)
  host = h
end

local function options()
  return { matchCase = frm.chkCase.checked, whole = frm.chkWhole.checked, wrap = frm.chkWrap.checked }
end

local function say(text)
  frm.lblResult.caption = text
end

-- tally says how many matches there are, and which is selected.
local function tally(wrapped)
  local n, which = host.ed():countMatches(frm.txtFind.text, options())
  if n == 0 then return say("No match") end
  say(("%s of %d%s"):format(which > 0 and tostring(which) or "-", n, wrapped and ", from the top again" or ""))
end

-- findNext selects the next match (the one before, with back), and says
-- whether there was one. The document's Find Next calls it with the dialog
-- closed: what was typed in it is still there to search for.
function frm.findNext(back)
  local needle = frm.txtFind.text
  if needle == "" then
    frm.open(false)
    return false
  end
  local found, wrapped = host.ed():find(needle, options(), back)
  if not found then
    say(("Cannot find \"%s\""):format(needle))
    if not frm.visible then gui.msgbox(("Cannot find \"%s\"."):format(needle), "ok", "microword") end
    return false
  end
  host.moved()
  tally(wrapped)
  return true
end

function frm.cmdFindNext:onClick()
  frm.findNext(false)
end

function frm.cmdFindPrev:onClick()
  frm.findNext(true)
end

-- Replace replaces the match selected, then finds the next.
function frm.cmdReplace:onClick()
  local e = host.ed()
  if frm.txtFind.text == "" then return end
  local replaced, found = e:replace(frm.txtFind.text, frm.txtReplace.text, options())
  if replaced then host.changed() end
  if found then
    host.moved()
    tally(false)
  elseif replaced then
    say("Replaced; no more matches")
  else
    frm.findNext(false)
  end
end

function frm.cmdReplaceAll:onClick()
  if frm.txtFind.text == "" then return end
  local n = host.ed():replaceAll(frm.txtFind.text, frm.txtReplace.text, options())
  if n > 0 then host.changed() end
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
-- what is selected in the document when that is a line of text.
function frm.open(replacing)
  local sel = host.ed():copyText()
  if sel and sel ~= "" and not sel:find("\n") then frm.txtFind.text = sel end
  frm.caption = replacing and "Replace" or "Find"
  frm.txtFind:fire("onChange")
  frm:show()
  if replacing and frm.txtFind.text ~= "" then frm.txtReplace:focus() else frm.txtFind:focus() end
end

frm.txtFind:fire("onChange")

return frm
