-- A layout, written by gui.save: gui.load builds it.
return { kind = "Form", name = "Source", caption = "Markdown Source", width = 640, height = 480,
  { kind = "TextBox", name = "txtSource", left = 8, top = 8, width = 624, height = 424, font = "mono", fontSize = 13, grow = true, multiLine = true, readOnly = true },
  { kind = "Label", name = "lblNote", caption = "This is what document.md holds inside the .zmd.", left = 8, top = 444, width = 400, textColor = "#707070" },
  { kind = "Button", name = "cmdCopy", caption = "Copy", left = 436, top = 444, width = 94 },
  { kind = "Button", name = "cmdClose", caption = "Close", left = 538, top = 444, width = 94, default = true },
}
