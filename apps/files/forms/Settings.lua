-- The code behind Settings.form.lua: the controls are fields of the form, by
-- the names the layout gives them. ask() shows it and says what was chosen.

local gui = require "gui"
local fs = require "fs"
local frm = gui.load "Settings" --[[@as forms.Settings]]

local SORTS = { "name", "size", "modified", "kind" }
local result

-- ask shows the dialog on a copy of the settings, and returns the new
-- settings, or nil when cancelled.
function frm.ask(settings)
  result = nil
  frm.chkHidden.checked = settings.showHidden
  frm.chkFoldersFirst.checked = settings.foldersFirst
  frm.chkDescending.checked = settings.descending
  frm.chkConfirm.checked = settings.confirmDelete
  for i, s in ipairs(SORTS) do
    if s == settings.sortBy then frm.cboSort.selected = i end
  end
  frm.lblSaved.caption = "Kept in " .. fs.settingsPath()
  frm:showModal()
  return result
end

function frm.cmdOK:onClick()
  result = {
    showHidden = frm.chkHidden.checked,
    foldersFirst = frm.chkFoldersFirst.checked,
    descending = frm.chkDescending.checked,
    confirmDelete = frm.chkConfirm.checked,
    sortBy = SORTS[frm.cboSort.selected] or "name",
  }
  frm:close()
end

function frm.cmdCancel:onClick()
  frm:close()
end

return frm
