-- The code behind LinkPicker.form.lua: the controls are fields of the
-- form, by the names the layout gives them. It asks which note a link goes
-- to, the notes listed as their name is typed; a name no note has makes a
-- link to a note made when it is first followed.

local gui = require "gui"
local frm = gui.load "LinkPicker" --[[@as forms.LinkPicker]]

local titles = {}   -- every note's title, sorted
local shown = {}    -- those the list shows
local picked

local function refill()
  local want = (frm.txtName.text or ""):lower()
  shown = {}
  for _, t in ipairs(titles) do
    if want == "" or t:lower():find(want, 1, true) then shown[#shown + 1] = t end
  end
  frm.lstNotes.items = shown
  if #shown > 0 then frm.lstNotes.selected = 1 end
end

-- pick shows the notes' titles and waits: it returns the title chosen or
-- typed, or nil when cancelled.
function frm.pick(list, start)
  titles = list
  picked = nil
  frm.txtName.text = start or ""
  refill()
  frm.txtName:focus()
  frm:showModal()
  return picked
end

-- choice is what OK means: the note selected, or else the name typed.
local function choice()
  local typed = (frm.txtName.text or ""):match("^%s*(.-)%s*$")
  local sel = shown[frm.lstNotes.selected or 0]
  if sel and (typed == "" or sel:lower():find(typed:lower(), 1, true)) then return sel end
  if typed ~= "" then return typed end
end

function frm.txtName:onChange()
  refill()
end

function frm.txtName:onKey(key)
  if key == "Down" and #shown > 0 then
    frm.lstNotes:focus()
    return true
  end
  if key == "Enter" then
    frm.cmdOK:fire("onClick")
    return true
  end
end

function frm.lstNotes:onDoubleClick()
  frm.cmdOK:fire("onClick")
end

function frm.cmdOK:onClick()
  picked = choice()
  if picked then frm:close() end
end

function frm.cmdCancel:onClick()
  frm:close()
end

-- Exposed for the tests.
frm.choice = choice

return frm
