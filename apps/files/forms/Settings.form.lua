-- A layout, written by gui.save: gui.load builds it.
return { kind = "Form", name = "Settings", caption = "Settings", width = 320, height = 262,
  { kind = "CheckBox", name = "chkHidden", caption = "Show hidden files and folders", left = 16, top = 16, width = 288, tabIndex = 1 },
  { kind = "CheckBox", name = "chkFoldersFirst", caption = "List folders before files", left = 16, top = 44, width = 288, tabIndex = 2 },
  { kind = "Label", name = "lblSort", caption = "Sort by", left = 16, top = 80, width = 60 },
  { kind = "ComboBox", name = "cboSort", left = 80, top = 78, width = 120, items = { "Name", "Size", "Modified", "Kind" }, selected = 1, tabIndex = 3 },
  { kind = "CheckBox", name = "chkDescending", caption = "Descending", left = 210, top = 78, width = 100, tabIndex = 4 },
  { kind = "CheckBox", name = "chkConfirm", caption = "Ask before deleting", left = 16, top = 112, width = 288, tabIndex = 5 },
  { kind = "CheckBox", name = "chkApps", caption = "Open files in turboapps' own apps", left = 16, top = 140, width = 288, tabIndex = 6, tooltip = "pictures in the image viewer, documents in MicroWord, and so on; off, the system's programs open them" },
  { kind = "Label", name = "lblSaved", caption = "", left = 16, top = 172, width = 288, height = 36, fontSize = 11, textColor = "#707070" },
  { kind = "Button", name = "cmdOK", caption = "OK", left = 118, top = 220, width = 90, default = true, tabIndex = 7 },
  { kind = "Button", name = "cmdCancel", caption = "Cancel", left = 214, top = 220, width = 90, tabIndex = 8 },
}
