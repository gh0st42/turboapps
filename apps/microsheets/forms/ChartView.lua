-- The code behind ChartView.form.lua: the controls are fields of the form,
-- by the names the layout gives them. It charts the numbers of a range.

local gui = require "gui"
local frm = gui.load "ChartView" --[[@as forms.ChartView]]
local charts = require "controls.Chart"

local KINDS = { "bar", "line", "sparkline", "pie" }

local SCALE = 2 -- a saved chart has twice the pixels shown, to stay sharp

local saveName = "chart"

-- view charts a range of sheet s, and waits until the window is closed.
-- name, when given, starts the file name a chart is saved as.
function frm.view(b, s, r1, c1, r2, c2, theme, title, name)
  saveName = name or s.name
  frm.chtView.data = charts.data(b, s, r1, c1, r2, c2)
  frm.chtView.theme = theme
  frm.lblRange.caption = title or ""
  frm:showModal()
end

function frm.cboKind:onChange()
  frm.chtView.chartType = KINDS[frm.cboKind.selected] or "bar"
end

-- save writes the chart as it shows, as a PNG file, to path, or to one
-- asked for.
function frm.save(path)
  path = path or gui.savefile { title = "Save Chart", filter = "PNG pictures\t*.png",
    file = saveName .. "-" .. frm.chtView.chartType .. ".png" }
  if not path then return false end
  if not path:lower():find("%.png$") then path = path .. ".png" end
  local ok, err = frm.chtView:snapshot(SCALE):save(path)
  if not ok then
    gui.msgbox("Could not save " .. path .. ":\n" .. tostring(err), "ok", "Save Chart")
    return false
  end
  return true
end

function frm.cmdSave:onClick()
  frm.save()
end

function frm.cmdClose:onClick()
  frm:close()
end

-- Keys 1 to 4 pick the kind, as in the terminal spreadsheets, and P saves.
function frm:onKey(key)
  if key == "p" or key == "P" then frm.save() return true end
  local i = tonumber(key)
  if i and KINDS[i] then
    frm.cboKind.selected = i
    frm.chtView.chartType = KINDS[i]
    return true
  end
end

return frm
