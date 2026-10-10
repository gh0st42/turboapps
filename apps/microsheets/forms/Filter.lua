-- The code behind Filter.form.lua: the controls are fields of the form, by
-- the names the layout gives them. It asks which rows to show.

local gui = require "gui"
local frm = gui.load "Filter" --[[@as forms.Filter]]

local answer, column

local function prompt()
  if frm.chkAll.checked then return "Show the rows with a value in any column that" end
  return "Show the rows whose value in column " .. column
end

-- ask asks for a filter on column `col` (its letters), starting from the
-- one in use. It returns the filter and whether every column is looked
-- in, "clear" to show every row, or nil when cancelled.
function frm.ask(col, current, all)
  answer, column = nil, col
  frm.txtExpr.text = current or ""
  frm.chkAll.checked = all and true or false
  frm.lblPrompt.caption = prompt()
  frm:showModal()
  if answer == "clear" then return "clear" end
  if answer then return answer, frm.chkAll.checked end
end

function frm.cmdOK:onClick()
  local text = frm.txtExpr.text
  if text:find("^%s*$") then answer = "clear" else answer = text end
  frm:close()
end

function frm.cmdClear:onClick()
  answer = "clear"
  frm:close()
end

function frm.cmdCancel:onClick()
  frm:close()
end

function frm.chkAll:onChange()
  frm.lblPrompt.caption = prompt()
end

return frm
