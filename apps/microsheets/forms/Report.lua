-- The code behind Report.form.lua: the controls are fields of the form, by
-- the names the layout gives them. It shows a page of text: the keys, the
-- functions, a profile of the columns.

local gui = require "gui"
local frm = gui.load "Report" --[[@as forms.Report]]

-- view shows text under a title, and waits until the window is closed.
function frm.view(title, text)
  frm.caption = title
  frm.txtReport.text = text
  frm:showModal()
end

function frm.cmdCopy:onClick()
  gui.clipboard(frm.txtReport.text)
end

function frm.cmdClose:onClick()
  frm:close()
end

return frm
