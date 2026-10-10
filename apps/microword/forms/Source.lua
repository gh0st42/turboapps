-- The code behind Source.form.lua: the controls are fields of the form, by
-- the names the layout gives them. It shows the document as the Markdown
-- microword keeps it in.

local gui = require "gui"
local frm = gui.load "Source" --[[@as forms.Source]]

-- view shows text, and waits until the window is closed.
function frm.view(text)
  frm.txtSource.text = text
  frm:showModal()
end

function frm.cmdCopy:onClick()
  gui.clipboard(frm.txtSource.text)
end

function frm.cmdClose:onClick()
  frm:close()
end

return frm
