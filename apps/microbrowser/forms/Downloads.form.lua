-- A layout, written by gui.save: gui.load builds it.
return { kind = "Form", name = "Downloads", caption = "Downloads", width = 660, height = 400,
  { kind = "Label", name = "lblFolder", caption = "", left = 8, top = 10, width = 524, height = 24, textColor = "#606060" },
  { kind = "Button", name = "cmdFolder", caption = "Folder...", left = 540, top = 8, width = 112, tabIndex = 1, tooltip = "where downloads are saved" },
  { kind = "ListBox", name = "lstDownloads", left = 8, top = 42, width = 524, height = 316, grow = true, tabIndex = 2 },
  { kind = "Button", name = "cmdOpen", caption = "Open", left = 540, top = 42, width = 112, default = true, tabIndex = 3 },
  { kind = "Button", name = "cmdShow", caption = "Show in Folder", left = 540, top = 76, width = 112, tabIndex = 4 },
  { kind = "Button", name = "cmdCancel", caption = "Cancel", left = 540, top = 116, width = 112, tabIndex = 5, tooltip = "stop it, and take what came of it away" },
  { kind = "Button", name = "cmdRemove", caption = "Remove", left = 540, top = 150, width = 112, tabIndex = 6, tooltip = "out of this list: the file stays" },
  { kind = "Button", name = "cmdClear", caption = "Clear Finished", left = 540, top = 184, width = 112, tabIndex = 7 },
  { kind = "Label", name = "lblCount", caption = "", left = 8, top = 366, width = 400, height = 24, textColor = "#707070" },
  { kind = "Button", name = "cmdClose", caption = "Close", left = 540, top = 362, width = 112, tabIndex = 8 },
}
