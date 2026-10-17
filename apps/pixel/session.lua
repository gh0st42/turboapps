-- What the user is doing to a picture: the tool and colours in hand, the
-- stroke being drawn, and undo and redo. The form turns the mouse into
-- press, drag and release at picture coordinates, and draws what this says;
-- everything in between is here, and works without a window.

local picture = require "picture"
local palettes = require "palettes"

local M = {}

M.tools = { "pen", "brush", "eraser", "fill", "line", "rect", "ellipse", "picker", "hand" }
M.UNDO_LIMIT = 100

local Session = {}
Session.__index = Session

function M.new(pic)
  local s = setmetatable({
    tool = "pen",
    lastTool = "pen",
    size = 3,         -- the brush's and the eraser's
    filled = false,   -- rectangles and ellipses
    color = 0,        -- what the tools draw with; CLEAR is transparent
    tile = nil,       -- a tilemap's tile size, or nil: strokes and fills stay in one tile
    selected = { 0, 0 }, -- a pixel of the tile picked, for copying and the like
    tileClip = nil,   -- the tile copied, to paste
  }, Session)
  s:setPicture(pic or picture.new(32, 32, "pico"))
  return s
end

-- setPicture starts on another picture, with a fresh history.
function Session:setPicture(pic)
  self.pic = pic
  self.undoStack, self.redoStack = {}, {}
  self.dirty = false
  self.stroke = nil
  local size = palettes.size(palettes.get(pic.palette))
  if self.color ~= picture.CLEAR and self.color >= size then self.color = 0 end
end

function Session:setTool(tool)
  if tool ~= "picker" then self.lastTool = tool end
  self.tool = tool
  self.stroke = nil
end

---------------------------------------------------------------- history

-- checkpoint keeps the picture as it is, for undo, before it changes.
function Session:checkpoint()
  local u = self.undoStack
  u[#u + 1] = self.pic:snapshot()
  if #u > M.UNDO_LIMIT then table.remove(u, 1) end
  self.redoStack = {}
  self.dirty = true
end

function Session:canUndo() return #self.undoStack > 0 end
function Session:canRedo() return #self.redoStack > 0 end

function Session:undo()
  local s = table.remove(self.undoStack)
  if not s then return false end
  self.redoStack[#self.redoStack + 1] = self.pic:snapshot()
  self.pic:restore(s)
  self.dirty = true
  return true
end

function Session:redo()
  local s = table.remove(self.redoStack)
  if not s then return false end
  self.undoStack[#self.undoStack + 1] = self.pic:snapshot()
  self.pic:restore(s)
  self.dirty = true
  return true
end

-- apply does a change to the whole picture as one step of undo.
function Session:apply(fn, ...)
  self:checkpoint()
  fn(self.pic, ...)
end

-- convert moves the picture, and the colour in hand, to another palette.
function Session:convert(name)
  if name == self.pic.palette then return end
  local from, to = palettes.get(self.pic.palette), palettes.get(name)
  self:apply(function(p) p:convert(name) end)
  if self.color ~= picture.CLEAR then
    local e = from[self.color] or { 0, 0, 0 }
    self.color = palettes.nearest(to, e[1], e[2], e[3])
  end
end

---------------------------------------------------------------- tiles

-- tileBox is the tile of the picture around x, y as a box { x0, y0, x1, y1 },
-- or nil when there are no tiles.
function Session:tileBox(x, y)
  local n = self.tile
  if not n then return nil end
  local x0, y0 = math.floor(x / n) * n, math.floor(y / n) * n
  return { x0, y0, math.min(x0 + n, self.pic.w) - 1, math.min(y0 + n, self.pic.h) - 1 }
end

-- selectedBox is the tile picked, as a box; nil without tiles.
function Session:selectedBox()
  local x, y = self.selected[1], self.selected[2]
  if not self.pic:inside(x, y) then x, y = 0, 0 end
  return self:tileBox(x, y)
end

-- selectTile picks the tile around x, y; false when it is not on the picture.
function Session:selectTile(x, y)
  if not self.tile or not self.pic:inside(x, y) then return false end
  self.selected = { x, y }
  return true
end

-- tileCoords says which tile is picked: its column and row, from 0.
function Session:tileCoords()
  local k = self:selectedBox()
  if not k then return nil end
  return k[1] / self.tile, k[2] / self.tile
end

-- tileColumns and tileCount are how many tiles go across the picture, and
-- how many there are; the last of them is a smaller one when the tile
-- size does not divide the picture.
function Session:tileColumns() return self.tile and math.ceil(self.pic.w / self.tile) end

function Session:tileCount()
  if not self.tile then return nil end
  return self:tileColumns() * math.ceil(self.pic.h / self.tile)
end

-- tileNumber is the number of the tile around x, y, counted along the
-- rows from 0 at the top left; with no x, y, of the tile picked.
function Session:tileNumber(x, y)
  if not self.tile then return nil end
  local k = self:selectedBox()
  if x then k = self:tileBox(x, y) end
  return (k[2] / self.tile) * self:tileColumns() + k[1] / self.tile
end

-- moveTile picks the tile dx columns and dy rows away, if there is one.
function Session:moveTile(dx, dy)
  local k = self:selectedBox()
  if not k then return false end
  local x, y = k[1] + dx * self.tile, k[2] + dy * self.tile
  return self:selectTile(x, y)
end

-- copyTile keeps the tile picked, to paste.
function Session:copyTile()
  local k = self:selectedBox()
  if not k then return false end
  self.tileClip = self.pic:copyBox(k)
  return true
end

-- cutTile keeps the tile picked and clears it, as one step of undo.
function Session:cutTile()
  if not self:copyTile() then return false end
  self:clearTile()
  return true
end

-- pasteTile puts the tile kept into the one picked, as much as fits.
function Session:pasteTile()
  local k = self:selectedBox()
  if not k or not self.tileClip then return false end
  self:apply(function(p) p:pasteBox(k[1], k[2], self.tileClip, k) end)
  return true
end

-- clearTile makes the tile picked transparent.
function Session:clearTile()
  local k = self:selectedBox()
  if not k then return false end
  self:apply(function(p) p:clearBox(k) end)
  return true
end

-- inBox draws with the picture kept to a box, or to nothing special.
local function inBox(pic, box, fn)
  pic.clip = box
  fn()
  pic.clip = nil
end

---------------------------------------------------------------- the mouse

local shapes = { line = true, rect = true, ellipse = true }

-- pick takes the colour at x, y as the one to draw with; the picker tool
-- does it, and so does the right button with any tool.
function Session:pick(x, y)
  local got = self.pic:get(x, y)
  if got then self.color = got end
  return got
end

-- press starts a stroke at x, y with a mouse button: 1, the left, draws
-- with the tool in hand, and 3, the right, picks a colour.
function Session:press(x, y, button)
  if button == 3 then
    self:pick(x, y)
    return
  end
  local c = self.color
  local tool = self.tool
  if tool == "picker" then
    self:pick(x, y)
    self:setTool(self.lastTool)
    return
  end
  if tool == "hand" then return end -- the form pans, or picks a tile on release
  if not self.pic:inside(x, y) and tool == "fill" then return end
  if tool == "fill" then
    self:selectTile(x, y)
    if self.pic:get(x, y) == c then return end
    self:checkpoint()
    self.pic:fill(x, y, c, self:tileBox(x, y))
    return
  end
  self:checkpoint()
  self:selectTile(x, y) -- drawing in a tile picks it
  -- With tiles, a stroke stays in the tile it began in.
  self.stroke = { x0 = x, y0 = y, x = x, y = y, color = c, box = self:tileBox(x, y) }
  inBox(self.pic, self.stroke.box, function()
    if tool == "pen" then self.pic:plot(x, y, c, 1)
    elseif tool == "brush" then self.pic:plot(x, y, c, self.size)
    elseif tool == "eraser" then self.pic:plot(x, y, picture.CLEAR, self.size)
    end
  end)
end

function Session:drag(x, y)
  local st = self.stroke
  if not st or (x == st.x and y == st.y) then return end
  local tool = self.tool
  inBox(self.pic, st.box, function()
    if tool == "pen" then self.pic:stroke(st.x, st.y, x, y, st.color, 1)
    elseif tool == "brush" then self.pic:stroke(st.x, st.y, x, y, st.color, self.size)
    elseif tool == "eraser" then self.pic:stroke(st.x, st.y, x, y, picture.CLEAR, self.size)
    end
  end)
  st.x, st.y = x, y
end

function Session:release(x, y)
  local st = self.stroke
  if not st then return end
  self:drag(x, y)
  if shapes[self.tool] then
    self:shape(function(px, py) self.pic:set(px, py, st.color) end)
  end
  self.stroke = nil
end

-- cancel drops a shape being dragged out, as Escape does.
function Session:cancel()
  if self.stroke and shapes[self.tool] then
    self.stroke = nil
    self:undo()
    self.redoStack = {}
  end
end

-- shape calls fn for each pixel of the line, rectangle or ellipse being
-- dragged out, so the form can show it before the button is let go. With
-- tiles it calls fn only for the pixels in the tile the shape began in.
function Session:shape(fn)
  local st = self.stroke
  if not st or not shapes[self.tool] then return false end
  local k = st.box
  local inner = fn
  if k then
    inner = function(x, y)
      if x >= k[1] and y >= k[2] and x <= k[3] and y <= k[4] then fn(x, y) end
    end
  end
  if self.tool == "line" then picture.line(st.x0, st.y0, st.x, st.y, inner)
  elseif self.tool == "rect" then picture.rect(st.x0, st.y0, st.x, st.y, self.filled, inner)
  else picture.ellipse(st.x0, st.y0, st.x, st.y, self.filled, inner) end
  return true
end

return M
