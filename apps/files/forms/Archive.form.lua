-- A layout, written by gui.save: gui.load builds it.
return { kind = "Form", name = "Archive", caption = "Archive", width = 580, height = 420,
  { kind = "Label", name = "lblInfo", caption = "", left = 12, top = 10, width = 556, height = 22 },
  { kind = "ListBox", name = "lstEntries", left = 12, top = 38, width = 556, height = 290, tabIndex = 1 },
  { kind = "ProgressBar", name = "prgJob", left = 12, top = 336, width = 556, height = 18, max = 100, min = 0, value = 0 },
  { kind = "Label", name = "lblStatus", caption = "", left = 12, top = 358, width = 556, height = 22 },
  { kind = "Button", name = "cmdFolder", caption = "Extract to Folder", left = 12, top = 384, width = 140, tabIndex = 2, tooltip = "into a new folder named after the archive, beside it" },
  { kind = "Button", name = "cmdAll", caption = "Extract All To...", left = 158, top = 384, width = 130, tabIndex = 3 },
  { kind = "Button", name = "cmdSelected", caption = "Extract Selected To...", left = 294, top = 384, width = 160, tabIndex = 4 },
  { kind = "Button", name = "cmdClose", caption = "Close", left = 478, top = 384, width = 90, default = true, tabIndex = 5 },
}
