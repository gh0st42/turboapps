-- A picture: a grid of palette indices, with CLEAR for a transparent pixel,
-- and the drawing it can have done to it. Nothing here knows about the
-- screen, so all of it can be tested without a window.
--
-- Beside the indices it keeps the picture in colour, as an image from
-- tlua's png module (p.img), which a Canvas draws with g:image and which is
-- saved as a PNG. set() changes both; whatever changes the indices
-- wholesale calls sync() to bring the image up to date.
--
--   local picture = require "picture"
--   local p = picture.new(32, 32, "pico")
--   p:line(0, 0, 31, 31, 8)
--   p:fill(0, 31, 12)

local png = require "png"
local palettes = require "palettes"

local M = {}

M.CLEAR = -1
M.MAX = 512 -- the largest side a picture may have

local Picture = {}
Picture.__index = Picture

function M.new(w, h, palette, background)
  local p = setmetatable({ w = w, h = h, palette = palette or "pico", px = {} }, Picture)
  local c = background or M.CLEAR
  for i = 1, w * h do p.px[i] = c end
  p:sync()
  return p
end

-- colours is how each index is written into the image, as "#rrggbbaa".
function Picture:colours()
  local cache = self.cache
  if not cache or cache.palette ~= self.palette then
    cache = { palette = self.palette, [M.CLEAR] = "#00000000" }
    local pal = palettes.get(self.palette)
    for i = 0, palettes.size(pal) - 1 do cache[i] = palettes.hex(pal[i]) .. "ff" end
    self.cache = cache
  end
  return cache
end

-- sync makes the image again from the indices.
function Picture:sync()
  local w, px, colours = self.w, self.px, self:colours()
  local img = self.img
  if not img or img.width ~= w or img.height ~= self.h then
    img = png.new(w, self.h)
    self.img = img
  end
  for y = 0, self.h - 1 do
    local row = y * w
    for x = 0, w - 1 do
      img:set(x, y, colours[px[row + x + 1]] or "#000000ff")
    end
  end
end

function Picture:inside(x, y)
  return x >= 0 and y >= 0 and x < self.w and y < self.h
end

function Picture:get(x, y)
  if not self:inside(x, y) then return nil end
  return self.px[y * self.w + x + 1]
end

function Picture:set(x, y, c)
  if not self:inside(x, y) then return end
  local i = y * self.w + x + 1
  if self.px[i] == c then return end
  self.px[i] = c
  self.img:set(x, y, self:colours()[c] or "#000000ff")
end

-- snapshot and restore copy the pixels out and back, for undo.
function Picture:snapshot()
  local copy = {}
  for i = 1, #self.px do copy[i] = self.px[i] end
  return { w = self.w, h = self.h, palette = self.palette, px = copy }
end

function Picture:restore(s)
  self.w, self.h, self.palette = s.w, s.h, s.palette
  self.px = {}
  for i = 1, #s.px do self.px[i] = s.px[i] end
  self:sync()
end

function Picture:clone()
  local p = setmetatable({}, Picture)
  p:restore(self:snapshot())
  return p
end

---------------------------------------------------------------- shapes
-- Each shape calls fn(x, y) for its pixels, so the same code draws on the
-- picture and works out the preview shown while the mouse is dragged.

-- stamp covers a brush of the given size at x, y: a square up to 2, a
-- disc from 3.
function M.stamp(x, y, size, fn)
  if size <= 1 then fn(x, y) return end
  local lo, hi = -math.floor((size - 1) / 2), math.floor(size / 2)
  local c = (lo + hi) / 2
  local r2 = (size / 2) ^ 2 - 0.5 -- keeps the corners off a 3 and a 4
  for dy = lo, hi do
    for dx = lo, hi do
      if size <= 2 or (dx - c) ^ 2 + (dy - c) ^ 2 <= r2 then fn(x + dx, y + dy) end
    end
  end
end

-- line visits the pixels from x0, y0 to x1, y1 (Bresenham's).
function M.line(x0, y0, x1, y1, fn)
  local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
  local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
  local err = dx + dy
  while true do
    fn(x0, y0)
    if x0 == x1 and y0 == y1 then return end
    local e2 = 2 * err
    if e2 >= dy then err = err + dy; x0 = x0 + sx end
    if e2 <= dx then err = err + dx; y0 = y0 + sy end
  end
end

local function order(a, b)
  if a > b then return b, a end
  return a, b
end

function M.rect(x0, y0, x1, y1, filled, fn)
  x0, x1 = order(x0, x1)
  y0, y1 = order(y0, y1)
  for y = y0, y1 do
    for x = x0, x1 do
      if filled or x == x0 or x == x1 or y == y0 or y == y1 then fn(x, y) end
    end
  end
end

-- ellipse fits an ellipse in the box from x0, y0 to x1, y1. Its pixels are
-- those whose centres are inside it, with its radii a quarter of a pixel
-- past the outer pixels' centres (half a pixel squares it off); the outline
-- is the ones of them with a neighbour outside.
function M.ellipse(x0, y0, x1, y1, filled, fn)
  x0, x1 = order(x0, x1)
  y0, y1 = order(y0, y1)
  local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
  local rx, ry = (x1 - x0) / 2 + 0.25, (y1 - y0) / 2 + 0.25
  local function inside(x, y)
    return ((x - cx) / rx) ^ 2 + ((y - cy) / ry) ^ 2 <= 1
  end
  for y = y0, y1 do
    for x = x0, x1 do
      if inside(x, y) and (filled or not (inside(x - 1, y) and inside(x + 1, y)
          and inside(x, y - 1) and inside(x, y + 1))) then
        fn(x, y)
      end
    end
  end
end

---------------------------------------------------------------- drawing

function Picture:plot(x, y, c, size)
  M.stamp(x, y, size or 1, function(px, py) self:set(px, py, c) end)
end

function Picture:stroke(x0, y0, x1, y1, c, size)
  M.line(x0, y0, x1, y1, function(x, y) self:plot(x, y, c, size) end)
end

function Picture:line(x0, y0, x1, y1, c)
  M.line(x0, y0, x1, y1, function(x, y) self:set(x, y, c) end)
end

function Picture:rect(x0, y0, x1, y1, c, filled)
  M.rect(x0, y0, x1, y1, filled, function(x, y) self:set(x, y, c) end)
end

function Picture:ellipse(x0, y0, x1, y1, c, filled)
  M.ellipse(x0, y0, x1, y1, filled, function(x, y) self:set(x, y, c) end)
end

-- fill is the paint bucket: it changes the area of one colour around
-- x, y, as far as it reaches up, down, left and right, to c. It returns
-- how many pixels it changed.
function Picture:fill(x, y, c)
  local target = self:get(x, y)
  if target == nil or target == c then return 0 end
  local w, px, n = self.w, self.px, 0
  local stack = { x, y }
  while #stack > 0 do
    local sy = table.remove(stack)
    local sx = table.remove(stack)
    -- Walk left to the start of this run, then fill it rightwards, noting
    -- the runs above and below as it goes.
    local row = sy * w
    while sx > 0 and px[row + sx] == target do sx = sx - 1 end
    local above, below = false, false
    while sx < w and px[row + sx + 1] == target do
      px[row + sx + 1] = c
      n = n + 1
      if sy > 0 then
        local t = px[row - w + sx + 1] == target
        if t and not above then stack[#stack + 1] = sx; stack[#stack + 1] = sy - 1 end
        above = t
      end
      if sy < self.h - 1 then
        local t = px[row + w + sx + 1] == target
        if t and not below then stack[#stack + 1] = sx; stack[#stack + 1] = sy + 1 end
        below = t
      end
      sx = sx + 1
    end
  end
  if n > 0 then self:sync() end
  return n
end

function Picture:clear(c)
  for i = 1, #self.px do self.px[i] = c or M.CLEAR end
  self:sync()
end

function Picture:flipH()
  for y = 0, self.h - 1 do
    local row = y * self.w
    for x = 0, math.floor(self.w / 2) - 1 do
      local a, b = row + x + 1, row + self.w - x
      self.px[a], self.px[b] = self.px[b], self.px[a]
    end
  end
  self:sync()
end

function Picture:flipV()
  for y = 0, math.floor(self.h / 2) - 1 do
    local a, b = y * self.w, (self.h - 1 - y) * self.w
    for x = 1, self.w do
      self.px[a + x], self.px[b + x] = self.px[b + x], self.px[a + x]
    end
  end
  self:sync()
end

-- resize makes the picture w by h, keeping what is in its top left corner.
function Picture:resize(w, h)
  local px = {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      px[y * w + x + 1] = self:get(x, y) or M.CLEAR
    end
  end
  self.w, self.h, self.px = w, h, px
  self:sync()
end

-- convert moves the picture to another palette, each colour to the
-- nearest the new palette has.
function Picture:convert(name)
  if name == self.palette then return end
  local from, to = palettes.get(self.palette), palettes.get(name)
  local map = {}
  for i = 0, palettes.size(from) - 1 do
    local c = from[i]
    map[i] = palettes.nearest(to, c[1], c[2], c[3])
  end
  for i = 1, #self.px do
    local c = self.px[i]
    if c ~= M.CLEAR then self.px[i] = map[c] or 0 end
  end
  self.palette = name
  self:sync()
end

---------------------------------------------------------------- files

-- save writes the picture as a PNG, with transparency.
function Picture:save(path)
  return self.img:save(path)
end

-- exact maps each colour of a palette, as "#rrggbb", to its index.
local function exact(name)
  local map, pal = {}, palettes.get(name)
  for i = palettes.size(pal) - 1, 0, -1 do map[palettes.hex(pal[i])] = i end
  return map
end

-- fromImage makes a picture of an image from the png module: a PNG, JPEG
-- or GIF. A pixel more than half transparent is transparent. The palette
-- is the first of prefer, PICO-8 and VGA that has every colour in the
-- image; when none does, each colour becomes prefer's nearest. It returns
-- the picture and whether its colours were all found as they were.
function M.fromImage(img, prefer)
  local w, h = img.width, img.height
  if w > M.MAX or h > M.MAX then
    return nil, ("the picture is %d by %d, and Pixel draws up to %d by %d"):format(w, h, M.MAX, M.MAX)
  end
  local colours, seen = {}, {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b, a = img:get(x, y)
      local key = a >= 128 and ("#%02x%02x%02x"):format(r, g, b) or false
      colours[y * w + x + 1] = key
      if key then seen[key] = { r, g, b } end
    end
  end
  local name, map, found
  for _, candidate in ipairs { prefer or "pico", "pico", "vga" } do
    map = exact(candidate)
    found = true
    for key in pairs(seen) do
      if not map[key] then found = false break end
    end
    if found then name = candidate break end
  end
  if not found then
    name = prefer or "pico"
    local pal = palettes.get(name)
    map = {}
    for key, rgb in pairs(seen) do map[key] = palettes.nearest(pal, rgb[1], rgb[2], rgb[3]) end
  end
  local p = setmetatable({ w = w, h = h, palette = name, px = {} }, Picture)
  for i = 1, w * h do
    local key = colours[i]
    p.px[i] = key and map[key] or M.CLEAR
  end
  p:sync()
  return p, found
end

return M
