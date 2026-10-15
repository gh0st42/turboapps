-- How pages look, with no GUI in it: the font a page is drawn in when a
-- fixed one is asked for, a VGA one if one is installed, and the colours
-- of a terminal of old, from the 16 of the EGA.

local M = {}

-- The EGA's 16 colours, as the IBM PC showed them.
M.EGA = {
  black = "#000000", blue = "#0000aa", green = "#00aa00", cyan = "#00aaaa",
  red = "#aa0000", magenta = "#aa00aa", brown = "#aa5500", lightGray = "#aaaaaa",
  darkGray = "#555555", lightBlue = "#5555ff", lightGreen = "#55ff55", lightCyan = "#55ffff",
  lightRed = "#ff5555", lightMagenta = "#ff55ff", yellow = "#ffff55", white = "#ffffff",
}

local E = M.EGA

-- terminal is what a MarkdownView draws with in the dark: light grey on
-- black, as DOS was, every colour one of the 16.
M.terminal = {
  background = E.black, text = E.lightGray, heading = E.yellow, link = E.lightCyan,
  quote = E.green, quoteBar = E.darkGray, codeText = E.lightGreen, codeBg = E.black,
  codeLine = E.darkGray, inlineCode = E.blue, rule = E.darkGray, selection = E.blue,
  tableLine = E.darkGray, tableHead = E.blue, tableStripe = E.black,
  missing = E.darkGray, bar = E.black, thumb = E.darkGray,
}

-- The status line under the page, in the dark.
M.status = { color = E.blue, textColor = E.white }

-- VGA fonts, the best first: those drawn from the IBM VGA's own 8×16
-- characters, by the names they are installed under.
M.VGA = {
  "Flexi IBM VGA True", "Flexi IBM VGA False",
  "Perfect DOS VGA 437 Win", "Perfect DOS VGA 437",
  "PxPlus IBM VGA 8x16", "Px437 IBM VGA 8x16", "Mx437 IBM VGA 8x16",
  "Web437 IBM VGA 8x16", "PxPlus IBM VGA9", "Px437 IBM VGA9",
}

-- fixedFont is the font to draw pages in when a fixed one is wanted: the
-- first VGA font of those installed (fonts, as gui.fonts() gives them), or
-- else "mono".
function M.fixedFont(fonts)
  local have = {}
  for _, name in ipairs(fonts or {}) do have[name:lower()] = name end
  for _, name in ipairs(M.VGA) do
    if have[name:lower()] then return have[name:lower()] end
  end
  return "mono"
end

-- isVGA says whether a font is one of the VGA ones, drawn best at 16.
function M.isVGA(font)
  for _, name in ipairs(M.VGA) do
    if name:lower() == (font or ""):lower() then return true end
  end
  return false
end

return M
