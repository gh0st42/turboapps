-- A layout, written by gui.save: gui.load builds it.
return { kind = "Form", name = "Help", caption = "Getting Started", width = 620, height = 640,
  { kind = "MarkdownView", name = "vwHelp", left = 0, top = 0, width = 620, height = 590, grow = true },
  { kind = "Button", name = "cmdClose", caption = "Close", left = 512, top = 600, width = 96, default = true },
}
