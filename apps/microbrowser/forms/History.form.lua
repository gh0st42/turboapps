-- A layout, written by gui.save: gui.load builds it.
return { kind = "Form", name = "History", caption = "History", width = 640, height = 440,
  { kind = "Label", name = "lblFilter", caption = "Search", left = 8, top = 12, width = 50, height = 24 },
  { kind = "TextBox", name = "txtFilter", left = 62, top = 10, width = 458, height = 28, tabIndex = 1, tooltip = "pages whose title or address has these words" },
  { kind = "ListBox", name = "lstHistory", left = 8, top = 46, width = 512, height = 354, grow = true, tabIndex = 2 },
  { kind = "Button", name = "cmdOpen", caption = "Open", left = 528, top = 46, width = 104, default = true, tabIndex = 3 },
  { kind = "Button", name = "cmdNewTab", caption = "Open in New Tab", left = 528, top = 80, width = 104, tabIndex = 4 },
  { kind = "Button", name = "cmdForget", caption = "Forget", left = 528, top = 120, width = 104, tabIndex = 5, tooltip = "take the page out of the history" },
  { kind = "Button", name = "cmdClear", caption = "Clear All...", left = 528, top = 154, width = 104, tabIndex = 6 },
  { kind = "Label", name = "lblCount", caption = "", left = 8, top = 408, width = 400, height = 24, textColor = "#707070" },
  { kind = "Button", name = "cmdClose", caption = "Close", left = 528, top = 404, width = 104, tabIndex = 7 },
}
