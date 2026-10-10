-- A layout, written by gui.save: gui.load builds it.
return { kind = "Form", name = "Filter", caption = "Filter Rows", width = 420, height = 200,
  { kind = "Label", name = "lblPrompt", caption = "Show the rows whose value in column A", left = 16, top = 12, width = 388 },
  { kind = "TextBox", name = "txtExpr", left = 16, top = 42, width = 388, height = 28, font = "mono" },
  { kind = "CheckBox", name = "chkAll", caption = "Look in every column instead", left = 16, top = 76, width = 388 },
  { kind = "Label", name = "lblHint", caption = "apple has the text   =Oslo is it   >1000  <=50.5  <>0 compare", left = 16, top = 108, width = 388, fontSize = 12, textColor = "#707070" },
  { kind = "Button", name = "cmdClear", caption = "Show All", left = 16, top = 156, width = 100 },
  { kind = "Button", name = "cmdCancel", caption = "Cancel", left = 200, top = 156, width = 100 },
  { kind = "Button", name = "cmdOK", caption = "Filter", left = 304, top = 156, width = 100, default = true },
}
