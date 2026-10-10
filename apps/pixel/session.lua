-- What the user is doing to a picture: the tool and colours in hand, the
-- stroke being drawn, and undo and redo. The form turns the mouse into
-- press, drag and release at picture coordinates, and draws what this says;
-- everything in between is here, and works without a window.

local picture = require "picture"
local palettes = require "palettes"

local M = {}

M.tools = { "pen", "brush", "eraser", "fill", "line", "rect", "ellipse", "picker" }
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
  if not self.pic:inside(x, y) and tool == "fill" then return end
  if tool == "fill" then
    if self.pic:get(x, y) == c then return end
    self:checkpoint()
    self.pic:fill(x, y, c)
    return
  end
  self:checkpoint()
  self.stroke = { x0 = x, y0 = y, x = x, y = y, color = c }
  if tool == "pen" then self.pic:plot(x, y, c, 1)
  elseif tool == "brush" then self.pic:plot(x, y, c, self.size)
  elseif tool == "eraser" then self.pic:plot(x, y, picture.CLEAR, self.size)
  end
end

function Session:drag(x, y)
  local st = self.stroke
  if not st or (x == st.x and y == st.y) then return end
  local tool = self.tool
  if tool == "pen" then self.pic:stroke(st.x, st.y, x, y, st.color, 1)
  elseif tool == "brush" then self.pic:stroke(st.x, st.y, x, y, st.color, self.size)
  elseif tool == "eraser" then self.pic:stroke(st.x, st.y, x, y, picture.CLEAR, self.size)
  end
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
-- dragged out, so the form can show it before the button is let go.
function Session:shape(fn)
  local st = self.stroke
  if not st or not shapes[self.tool] then return false end
  if self.tool == "line" then picture.line(st.x0, st.y0, st.x, st.y, fn)
  elseif self.tool == "rect" then picture.rect(st.x0, st.y0, st.x, st.y, self.filled, fn)
  else picture.ellipse(st.x0, st.y0, st.x, st.y, self.filled, fn) end
  return true
end

return M
