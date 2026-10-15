-- A layout, written by gui.save: gui.load builds it.
return { kind = "Form", name = "Bookmarks", caption = "Bookmarks", width = 520, height = 420,
  { kind = "ListBox", name = "lstMarks", left = 8, top = 8, width = 400, height = 300, grow = true },
  { kind = "Button", name = "cmdOpen", caption = "Open", left = 416, top = 8, width = 96 },
  { kind = "Button", name = "cmdUp", caption = "Move Up", left = 416, top = 44, width = 96 },
  { kind = "Button", name = "cmdDown", caption = "Move Down", left = 416, top = 76, width = 96 },
  { kind = "Button", name = "cmdDelete", caption = "Delete", left = 416, top = 112, width = 96 },
  { kind = "Label", name = "lblTitle", caption = "Title", left = 8, top = 318, width = 60, height = 28 },
  { kind = "TextBox", name = "txtTitle", left = 72, top = 318, width = 336, height = 28 },
  { kind = "Label", name = "lblUrl", caption = "Address", left = 8, top = 350, width = 60, height = 28 },
  { kind = "TextBox", name = "txtUrl", left = 72, top = 350, width = 336, height = 28 },
  { kind = "Button", name = "cmdClose", caption = "Close", left = 416, top = 384, width = 96, default = true },
}
