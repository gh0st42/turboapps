-- A layout, written by gui.save: gui.load builds it.
return { kind = "Form", name = "ChartView", caption = "Chart", width = 720, height = 460,
  { kind = "ComboBox", name = "cboKind", left = 12, top = 10, width = 160, items = { "Bar", "Line", "Sparkline", "Pie" }, selected = 1 },
  { kind = "Label", name = "lblRange", caption = "", left = 184, top = 10, width = 420, textColor = "#707070" },
  { kind = "Chart", name = "chtView", left = 12, top = 46, width = 696, height = 362, grow = true },
  { kind = "Button", name = "cmdSave", caption = "Save PNG...", left = 500, top = 420, width = 106, tooltip = "Save the chart as a PNG picture, at twice the size it shows (P)" },
  { kind = "Button", name = "cmdClose", caption = "Close", left = 614, top = 420, width = 94, default = true },
}
