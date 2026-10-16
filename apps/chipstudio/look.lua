-- How ChipStudio looks: its colours, and each channel's, as BeepBox colours
-- its channels, pitch ones bright and drum ones grey.

local M = {}

M.colors = {
  panel = "#f4f4f6", cell = "#e6e7eb", empty = "#cfd1d8", text = "#1d1d1f", dim = "#7a7c85",
  selectedRow = "#e1e7f5", loop = "#d6ecd6", playhead = "#ff9f1a", shared = "#1d1d1f",
  onColor = "#1d1d1f",
  roll = "#fbfbfc", rowAlt = "#f2f3f6", keyRow = "#e4ecfb", offScale = "#fbe3e3",
  noteBox = "#9da2ad", bend = "#b2303a", record = "#d63a3a",
  muted = "#b9bbc2", mute = "#d63a3a", solo = "#e3a21a",
  beat = "#c9ccd4", step = "#e7e8ec", barLine = "#8d909a", gutter = "#eceef2",
}

local PITCH = { "#45a3ff", "#ffc23d", "#5fd068", "#ff6fae", "#b18cff", "#3fd6cf", "#ff8a4d",
  "#9bd53a", "#e57bff", "#ffd96a" }
local DRUM = { "#a8aab3", "#c3a98f", "#8fb3c3", "#b3a8c9", "#a9c39a" }

-- channelColor is channel c's colour: by its place among the channels of
-- its kind.
function M.channelColor(song, c)
  local ch = song.channels[c]
  if not ch then return "#999999" end
  local n = 0
  for i = 1, c do if song.channels[i].type == ch.type then n = n + 1 end end
  local list = ch.type == "drum" and DRUM or PITCH
  return list[(n - 1) % #list + 1]
end

return M
