-- A layout, written by gui.save: gui.load builds it.
return { kind = "Form", name = "LinkPicker", caption = "Link to Note", width = 380, height = 400,
  { kind = "TextBox", name = "txtName", left = 8, top = 8, width = 364, height = 28, tooltip = "a note's name; one that is not there yet is made when the link is followed" },
  { kind = "ListBox", name = "lstNotes", left = 8, top = 42, width = 364, height = 310, grow = true },
  { kind = "Button", name = "cmdCancel", caption = "Cancel", left = 176, top = 362, width = 94 },
  { kind = "Button", name = "cmdOK", caption = "Link", left = 278, top = 362, width = 94, default = true },
}
