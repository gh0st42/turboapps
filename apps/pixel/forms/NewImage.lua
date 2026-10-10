-- The code behind NewImage.form.lua: the controls are fields of the form, by
-- the names the layout gives them. ask() shows it and says what was chosen.

local gui = require "gui"
local palettes = require "palettes"
local frm = gui.load "NewImage" --[[@as forms.NewImage]]

local result

-- ask shows the dialog, starting from the size and palette given, and
-- returns { width, height, palette, transparent }, or nil when cancelled.
function frm.ask(width, height, palette)
  result = nil
  frm.spnWidth.value = width or 32
  frm.spnHeight.value = height or 32
  for i, name in ipairs(palettes.names) do
    if name == palette then frm.cboPalette.selected = i end
  end
  frm:showModal()
  return result
end

function frm.cmdOK:onClick()
  result = {
    width = math.floor(frm.spnWidth.value),
    height = math.floor(frm.spnHeight.value),
    palette = palettes.names[frm.cboPalette.selected] or "pico",
    transparent = frm.chkTransparent.checked,
  }
  frm:close()
end

function frm.cmdCancel:onClick()
  frm:close()
end

return frm
