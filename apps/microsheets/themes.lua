-- The grid's colours. Numbers take the accent colour and formulas the
-- second one, so what was typed and what was worked out can be told apart
-- at a glance.

local M = {}

M.list = {
  { name = "Light", bg = "#ffffff", grid = "#e1e3e8", text = "#1f2328", number = "#1f2328", formula = "#0b5cad",
    error = "#c62828", header = "#f3f4f6", headerText = "#57606a", headerOn = "#dde7f6", headerOnText = "#0b3d91",
    cursor = "#1a73e8", selection = "#d7e6fb", frozen = "#f7f8fa", match = "#fff2a8", edit = "#ffffff", line = "#c8ccd2" },
  { name = "GitHub Light", bg = "#ffffff", grid = "#d0d7de", text = "#24292f", number = "#0550ae", formula = "#8250df",
    error = "#cf222e", header = "#f6f8fa", headerText = "#57606a", headerOn = "#ddf4ff", headerOnText = "#0969da",
    cursor = "#0969da", selection = "#ddf4ff", frozen = "#f6f8fa", match = "#fff8c5", edit = "#ffffff", line = "#d0d7de" },
  { name = "Solarized Light", bg = "#fdf6e3", grid = "#eee8d5", text = "#586e75", number = "#268bd2", formula = "#d33682",
    error = "#dc322f", header = "#eee8d5", headerText = "#93a1a1", headerOn = "#e4dcc2", headerOnText = "#073642",
    cursor = "#b58900", selection = "#eae1c4", frozen = "#f5eedb", match = "#f0e0a0", edit = "#fdf6e3", line = "#d8d0b8" },
  { name = "Catppuccin Latte", bg = "#eff1f5", grid = "#dce0e8", text = "#4c4f69", number = "#1e66f5", formula = "#8839ef",
    error = "#d20f39", header = "#e6e9ef", headerText = "#6c6f85", headerOn = "#ccd0da", headerOnText = "#1e66f5",
    cursor = "#7287fd", selection = "#d6dbf5", frozen = "#e6e9ef", match = "#f6e3b4", edit = "#eff1f5", line = "#bcc0cc" },
  { name = "Catppuccin Mocha", bg = "#1e1e2e", grid = "#313244", text = "#cdd6f4", number = "#89b4fa", formula = "#cba6f7",
    error = "#f38ba8", header = "#181825", headerText = "#a6adc8", headerOn = "#313244", headerOnText = "#89b4fa",
    cursor = "#b4befe", selection = "#3a3d5c", frozen = "#24243a", match = "#5b4f2e", edit = "#11111b", line = "#45475a" },
  { name = "Nord", bg = "#2e3440", grid = "#3b4252", text = "#d8dee9", number = "#88c0d0", formula = "#b48ead",
    error = "#bf616a", header = "#272c36", headerText = "#81a1c1", headerOn = "#3b4252", headerOnText = "#88c0d0",
    cursor = "#88c0d0", selection = "#434c5e", frozen = "#323946", match = "#5e5536", edit = "#242933", line = "#4c566a" },
  { name = "Gruvbox", bg = "#282828", grid = "#3c3836", text = "#ebdbb2", number = "#83a598", formula = "#d3869b",
    error = "#fb4934", header = "#1d2021", headerText = "#a89984", headerOn = "#3c3836", headerOnText = "#fabd2f",
    cursor = "#fabd2f", selection = "#45403d", frozen = "#2f2b29", match = "#5a4a1e", edit = "#1d2021", line = "#504945" },
  { name = "Tokyo Night", bg = "#1a1b26", grid = "#292e42", text = "#c0caf5", number = "#7aa2f7", formula = "#bb9af7",
    error = "#f7768e", header = "#16161e", headerText = "#565f89", headerOn = "#292e42", headerOnText = "#7dcfff",
    cursor = "#7aa2f7", selection = "#2e3554", frozen = "#1f2030", match = "#4d4527", edit = "#13131c", line = "#3b4261" },
  { name = "Dracula", bg = "#282a36", grid = "#383a4a", text = "#f8f8f2", number = "#8be9fd", formula = "#ff79c6",
    error = "#ff5555", header = "#21222c", headerText = "#9aa0c0", headerOn = "#44475a", headerOnText = "#bd93f9",
    cursor = "#bd93f9", selection = "#44475a", frozen = "#2d2f3d", match = "#5c5631", edit = "#1e1f29", line = "#4d5066" },
}

M.byName = {}
for _, th in ipairs(M.list) do M.byName[th.name] = th end

function M.get(name) return M.byName[name] or M.list[1] end

-- names lists the themes in menu order.
function M.names()
  local list = {}
  for i, th in ipairs(M.list) do list[i] = th.name end
  return list
end

-- after gives the theme following name, round again at the end.
function M.after(name)
  for i, th in ipairs(M.list) do
    if th.name == name then return M.list[i % #M.list + 1].name end
  end
  return M.list[1].name
end

return M
