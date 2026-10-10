-- The calculator itself, with no GUI in it: a standard calculator that
-- works the way a pocket one does. Operators apply left to right as they
-- are pressed (2 + 3 * 4 = 20), = repeats the last operation, and % is
-- relative to the first operand when adding or subtracting.
--
--   local engine = require "engine"
--   local c = engine.new()
--   c:digit("2"); c:operator("+"); c:digit("3"); c:equals()
--   c:display()   --> "5"

local M = {}

local MAX_DIGITS = 16

-- Messages shown in place of a number. Any key but C, CE or Backspace
-- starts afresh after one.
M.DIV_ZERO = "Cannot divide by zero"
M.INVALID = "Invalid input"
M.OVERFLOW = "Overflow"

-- The symbols the expression line shows for each operator.
M.symbols = { ["+"] = "+", ["-"] = "−", ["*"] = "×", ["/"] = "÷" }

-- format writes a number as the display shows it: up to 15 significant
-- digits, no trailing zeros, and an exponent only when it would not fit.
function M.format(n)
  if n ~= n then return nil, M.INVALID end
  if n == math.huge or n == -math.huge then return nil, M.OVERFLOW end
  if n == 0 then return "0" end -- also -0
  local s = ("%.15g"):format(n)
  if s:find("e") then
    -- 1e+20 reads better as 1e20, and 1.5e-07 as 1.5e-7.
    s = s:gsub("e%+", "e"):gsub("e(%-?)0+(%d)", "e%1%2")
  end
  return s
end

-- group puts thousands separators into the whole part of an entry, as
-- typed or formatted: "1234567.891" -> "1,234,567.891".
function M.group(s)
  if s:find("e") or s:find("%a") then return s end
  local sign, whole, rest = s:match("^(%-?)(%d*)(.*)$")
  whole = whole:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if whole:sub(1, 1) == "," then whole = whole:sub(2) end
  return sign .. whole .. rest
end

local function apply(a, op, b)
  if op == "+" then return a + b end
  if op == "-" then return a - b end
  if op == "*" then return a * b end
  if op == "/" then
    if b == 0 then return nil, M.DIV_ZERO end
    return a / b
  end
  error("unknown operator " .. tostring(op))
end

local Calc = {}
Calc.__index = Calc

function M.new()
  local c = setmetatable({ history = {} }, Calc)
  c:clear()
  c.memory = nil
  return c
end

-- clear is C: everything but the memory and the history.
function Calc:clear()
  self.entry = "0"   -- the number being typed or shown
  self.acc = nil     -- the left operand
  self.op = nil      -- the operator waiting for its right operand
  self.fresh = true  -- the next digit starts a new entry
  self.last = nil    -- { op, b } for = pressed again
  self.expr = ""     -- the line above the display
  self.err = nil
end

function Calc:value()
  return tonumber(self.entry) or 0
end

function Calc:display()
  return self.err or M.group(self.entry)
end

function Calc:expression()
  return self.expr
end

-- recover starts afresh after an error, before a key that is not C.
function Calc:recover()
  if self.err then self:clear() end
end

-- show puts a computed number in the entry, or the error it came to.
function Calc:show(n, err)
  local s, ferr = nil, err
  if n then s, ferr = M.format(n) end
  if not s then
    self:clear()
    self.err = ferr
    self.entry = "0"
    return false
  end
  self.entry = s
  return true
end

function Calc:digit(d)
  self:recover()
  if self.fresh then
    self.entry = d
    self.fresh = false
    if not self.op then self.last = nil; self.expr = "" end
    return
  end
  local digits = #self.entry:gsub("[^%d]", "")
  if digits >= MAX_DIGITS then return end
  if self.entry == "0" then self.entry = d
  elseif self.entry == "-0" then self.entry = "-" .. d
  else self.entry = self.entry .. d end
end

function Calc:point()
  self:recover()
  if self.fresh then
    self.entry = "0."
    self.fresh = false
    if not self.op then self.last = nil; self.expr = "" end
  elseif not self.entry:find("%.") then
    self.entry = self.entry .. "."
  end
end

function Calc:backspace()
  if self.err then self:clear() return end
  if self.fresh then return end
  self.entry = self.entry:sub(1, -2)
  if self.entry == "" or self.entry == "-" then self.entry = "0" end
end

-- clearEntry is CE: the number being typed, not the calculation.
function Calc:clearEntry()
  if self.err then self:clear() return end
  self.entry = "0"
  self.fresh = true
end

function Calc:operator(op)
  self:recover()
  if self.op and self.fresh then
    -- A second operator in a row replaces the first.
    self.op = op
  else
    local v = self:value()
    if self.op then
      local r, err = apply(self.acc, self.op, v)
      if not self:show(r, err) then return end
      self.acc = r
    else
      self.acc = v
    end
    self.op = op
  end
  self.fresh = true
  self.last = nil
  self.expr = M.format(self.acc) .. " " .. M.symbols[op]
end

function Calc:equals()
  if self.err then self:clear() return end
  local a, op, b
  if self.op then
    a, op, b = self.acc, self.op, self:value()
  elseif self.last then
    a, op, b = self:value(), self.last.op, self.last.b
  else
    return
  end
  local r, err = apply(a, op, b)
  local line = ("%s %s %s ="):format(M.format(a), M.symbols[op], M.format(b))
  if not self:show(r, err) then return end
  self.expr = line
  self.history[#self.history + 1] = { expr = line, result = self.entry }
  self.acc, self.op = nil, nil
  self.last = { op = op, b = b }
  self.fresh = true
end

-- unary applies a function to the entry: negate, square, sqrt, inverse.
function Calc:unary(fn)
  self:recover()
  local v = self:value()
  if fn == "negate" then
    -- While typing, ± only flips the sign of what is there.
    if self.entry:sub(1, 1) == "-" then self.entry = self.entry:sub(2)
    elseif self.entry ~= "0" then self.entry = "-" .. self.entry end
    return
  end
  local r, err
  if fn == "square" then r = v * v
  elseif fn == "sqrt" then
    if v < 0 then err = M.INVALID else r = math.sqrt(v) end
  elseif fn == "inverse" then
    if v == 0 then err = M.DIV_ZERO else r = 1 / v end
  else
    error("unknown function " .. tostring(fn))
  end
  self:show(r, err)
  self.fresh = true
end

-- percent turns the entry into a percentage: of the first operand when
-- adding or subtracting (200 + 10% is 220), of one otherwise (50 * 10% is 5).
function Calc:percent()
  self:recover()
  local v = self:value()
  if self.op == "+" or self.op == "-" then
    self:show(self.acc * v / 100)
  else
    self:show(v / 100)
  end
  self.fresh = true
end

-- Memory: MC, MR, M+ and M-.
function Calc:memoryClear() self.memory = nil end

function Calc:memoryRecall()
  if self.memory == nil then return end
  self:recover()
  self:show(self.memory)
  self.fresh = true
  if not self.op then self.expr = "" end
end

function Calc:memoryAdd(sign)
  if self.err then return end
  self.memory = (self.memory or 0) + sign * self:value()
  self.fresh = true
end

-- enter puts a number in the entry, as pasting does; false when the text
-- is not a number.
function Calc:enter(text)
  text = tostring(text or ""):gsub("[%s,]", "")
  local n = tonumber(text)
  if not n then return false end
  self:recover()
  self:show(n)
  self.fresh = true
  if not self.op then self.expr = "" end
  return true
end

-- key does what a key on the keyboard does, by the text it types or its
-- name; true when it meant something.
function Calc:key(name, text)
  local t = text ~= "" and text or name
  if t:match("^%d$") then self:digit(t)
  elseif t == "." or t == "," then self:point()
  elseif t == "+" or t == "-" or t == "*" or t == "/" then self:operator(t)
  elseif t == "=" or t == "\r" or t == "\n" or name == "Enter" then self:equals()
  elseif t == "%" then self:percent()
  elseif name == "Backspace" or t == "\b" then self:backspace()
  elseif name == "Delete" or t == "\127" then self:clearEntry()
  elseif name == "Escape" or t == "\27" then self:clear()
  elseif t == "r" then self:unary("inverse")
  elseif t == "@" then self:unary("sqrt")
  elseif t == "q" then self:unary("square")
  elseif name == "F9" then self:unary("negate")
  else return false end
  return true
end

return M
