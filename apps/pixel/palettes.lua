-- The palettes a picture can be drawn in, as lists of { r, g, b } from
-- index 0. They are the ones tlua's console comes with: the 32 colours of
-- PICO-8 and its extended palette, which Picotron starts with, and the 256
-- a VGA card came up in.

local M = {}

local function list(hexes)
  local out = {}
  for i, h in ipairs(hexes) do
    out[i - 1] = { math.floor(h / 65536), math.floor(h / 256) % 256, h % 256 }
  end
  return out
end

M.pico = list {
  -- 0-15: PICO-8.
  0x000000, 0x1d2b53, 0x7e2553, 0x008751,
  0xab5236, 0x5f574f, 0xc2c3c7, 0xfff1e8,
  0xff004d, 0xffa300, 0xffec27, 0x00e436,
  0x29adff, 0x83769c, 0xff77a8, 0xffccaa,
  -- 16-31: the extended palette, the darker companions of the first 16.
  0x291814, 0x111d35, 0x422136, 0x125359,
  0x742f29, 0x49333b, 0xa28879, 0xf3ef7d,
  0xbe1250, 0xff6c24, 0xa8e72e, 0x00b543,
  0x065ab5, 0x754665, 0xff6e59, 0xff9d81,
}

-- Integer division as Go does it, towards zero, which the VGA table below
-- was written with.
local function quot(a, b)
  local q = a / b
  return q < 0 and math.ceil(q) or math.floor(q)
end

-- wheel is one of 24 hues between the brightest and dimmest a channel may
-- be, walking the edges of the colour cube from blue, four steps an edge.
local corners = {
  { 0, 0, 1 }, { 1, 0, 1 }, { 1, 0, 0 }, { 1, 1, 0 },
  { 0, 1, 0 }, { 0, 1, 1 }, { 0, 0, 1 },
}

local function wheel(hue, value, floor)
  local segment, step = math.floor(hue / 4), hue % 4
  local from, to = corners[segment + 1], corners[segment + 2]
  local rgb = {}
  for i = 1, 3 do
    local s = from[i] == 1 and value or floor
    local e = to[i] == 1 and value or floor
    local v = s + quot((e - s) * step, 4)
    rgb[i] = math.floor(v * 255 / 63)
  end
  return rgb
end

-- vga is the IBM VGA's default 256: the 16 EGA colours, 16 greys, nine
-- runs of 24 hues at three brightnesses and three saturations, and 8 black.
M.vga = (function()
  local out = list {
    0x000000, 0x0000aa, 0x00aa00, 0x00aaaa,
    0xaa0000, 0xaa00aa, 0xaa5500, 0xaaaaaa,
    0x555555, 0x5555ff, 0x55ff55, 0x55ffff,
    0xff5555, 0xff55ff, 0xffff55, 0xffffff,
  }
  local n = 16
  for _, v in ipairs { 0, 5, 8, 11, 14, 17, 20, 24, 28, 32, 36, 40, 45, 50, 56, 63 } do
    local g = math.floor(v * 255 / 63)
    out[n], n = { g, g, g }, n + 1
  end
  for _, value in ipairs { 63, 45, 28 } do
    for _, floor in ipairs { 0, quot(value, 2), quot(value * 3, 4) } do
      for hue = 0, 23 do
        out[n], n = wheel(hue, value, floor), n + 1
      end
    end
  end
  while n < 256 do
    out[n], n = { 0, 0, 0 }, n + 1
  end
  return out
end)()

-- The palettes by name, in the order the app offers them.
M.names = { "pico", "vga" }
M.titles = { pico = "PICO-8 / Picotron (32)", vga = "VGA (256)" }

function M.get(name)
  return M[name] or M.pico
end

function M.size(pal)
  return #pal + 1 -- index 0 is not counted by #
end

function M.hex(c)
  return ("#%02x%02x%02x"):format(c[1], c[2], c[3])
end

-- nearest is the entry of pal closest to an RGB colour, weighted towards
-- green as tlua's console weights it, so pictures move between palettes
-- the way its images are reduced to one.
function M.nearest(pal, r, g, b)
  local best, bestDist = 0, math.huge
  for i = 0, M.size(pal) - 1 do
    local e = pal[i]
    local dr, dg, db = r - e[1], g - e[2], b - e[3]
    local d = 2 * dr * dr + 4 * dg * dg + 3 * db * db
    if d < bestDist then best, bestDist = i, d end
  end
  return best
end

return M
