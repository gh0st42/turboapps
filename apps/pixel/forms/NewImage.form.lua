-- A layout, written by gui.save: gui.load builds it.
return { kind = "Form", name = "NewImage", caption = "New Picture", width = 284, height = 200,
  { kind = "Label", name = "lblWidth", caption = "Width", left = 16, top = 16, width = 80 },
  { kind = "Spinner", name = "spnWidth", left = 104, top = 16, width = 80, max = 512, min = 1, step = 1, tabIndex = 1, value = 32 },
  { kind = "Label", name = "lblHeight", caption = "Height", left = 16, top = 52, width = 80 },
  { kind = "Spinner", name = "spnHeight", left = 104, top = 52, width = 80, max = 512, min = 1, step = 1, tabIndex = 2, value = 32 },
  { kind = "Label", name = "lblPalette", caption = "Palette", left = 16, top = 88, width = 80 },
  { kind = "ComboBox", name = "cboPalette", left = 104, top = 88, width = 164, items = { "PICO-8 / Picotron (32)", "VGA (256)" }, selected = 1, tabIndex = 3 },
  { kind = "CheckBox", name = "chkTransparent", caption = "Transparent background", left = 16, top = 122, width = 252, checked = true, tabIndex = 4 },
  { kind = "Button", name = "cmdOK", caption = "OK", left = 80, top = 156, width = 90, default = true, tabIndex = 5 },
  { kind = "Button", name = "cmdCancel", caption = "Cancel", left = 178, top = 156, width = 90, tabIndex = 6 },
}
