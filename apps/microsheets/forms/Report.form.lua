-- A layout, written by gui.save: gui.load builds it.
return { kind = "Form", name = "Report", caption = "microsheets", width = 640, height = 480,
  { kind = "TextBox", name = "txtReport", left = 8, top = 8, width = 624, height = 424, font = "mono", fontSize = 13, grow = true, multiLine = true, readOnly = true },
  { kind = "Button", name = "cmdCopy", caption = "Copy", left = 436, top = 444, width = 94 },
  { kind = "Button", name = "cmdClose", caption = "Close", left = 538, top = 444, width = 94, default = true },
}
