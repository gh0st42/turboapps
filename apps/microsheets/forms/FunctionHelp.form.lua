-- A layout, written by gui.save: gui.load builds it.
return { kind = "Form", name = "FunctionHelp", caption = "Formula Help", width = 780, height = 540,
  { kind = "TextBox", name = "txtSearch", left = 8, top = 8, width = 240, height = 28, tooltip = "find a function by its name or what it does" },
  { kind = "Tree", name = "treTopics", left = 8, top = 44, width = 240, height = 448 },
  { kind = "TextBox", name = "txtPage", left = 256, top = 8, width = 516, height = 484, font = "mono", fontSize = 13, grow = true, multiLine = true, readOnly = true },
  { kind = "Label", name = "lblHint", caption = "Type to search. Insert puts the function in the cell.", left = 8, top = 504, width = 440, textColor = "#707070" },
  { kind = "Button", name = "cmdInsert", caption = "Insert", left = 576, top = 500, width = 94 },
  { kind = "Button", name = "cmdClose", caption = "Close", left = 678, top = 500, width = 94, default = true },
}
