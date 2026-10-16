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
  -- The scope: a dark screen of the 1980s, its scan lines a shade darker.
  scope = "#0c140f", scopeGrid = "#1d2b22", scopeLine = "#080d0a", scopeDim = "#3c5244",
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

-- VGA fonts, the best first, by the names they are installed under: the
-- scope's lettering, as on a screen of the time.
M.VGA = {
  "Flexi IBM VGA True", "Flexi IBM VGA False",
  "Perfect DOS VGA 437 Win", "Perfect DOS VGA 437",
  "PxPlus IBM VGA 8x16", "Px437 IBM VGA 8x16", "Mx437 IBM VGA 8x16",
  "Web437 IBM VGA 8x16", "PxPlus IBM VGA9", "Px437 IBM VGA9",
}

-- fixedFont is the first VGA font of those installed (fonts, as
-- gui.fonts() gives them), or else "mono".
function M.fixedFont(fonts)
  local have = {}
  for _, name in ipairs(fonts or {}) do have[name:lower()] = name end
  for _, name in ipairs(M.VGA) do
    if have[name:lower()] then return have[name:lower()] end
  end
  return "mono"
end

-- mix is colour a taken part of the way to colour b: by f, from 0 (a) to 1
-- (b). Canvases draw without see-through, so faint colours are mixed.
function M.mix(a, b, f)
  local function rgb(h) return tonumber(h:sub(2, 3), 16), tonumber(h:sub(4, 5), 16), tonumber(h:sub(6, 7), 16) end
  local r1, g1, b1 = rgb(a)
  local r2, g2, b2 = rgb(b)
  local function at(x, y) return math.floor(x + (y - x) * f + 0.5) end
  return ("#%02x%02x%02x"):format(at(r1, r2), at(g1, g2), at(b1, b2))
end

return M
