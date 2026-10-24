-- A layout, written by gui.save: gui.load builds it.
return { kind = "Form", name = "Viewer", caption = "Image Viewer", width = 960, height = 640, resizable = true,
  { kind = "Splitter", name = "splMain", left = 0, top = 0, width = 960, height = 616, grow = true,
    { kind = "ListBox", name = "lstFiles", left = 0, top = 0, width = 280, height = 616, tabIndex = 1 },
    { kind = "Canvas", name = "cnvImage", left = 280, top = 0, width = 680, height = 616 },
  },
  { kind = "Label", name = "lblStatus", caption = "", left = 0, top = 616, width = 960, height = 24, color = "#1a1a1a", textColor = "#9a9a9a" },
  { kind = "Canvas", name = "cnvFull", left = 0, top = 0, width = 960, height = 616, grow = true, visible = false },
}
