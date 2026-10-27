-- Conditional formatting, with no GUI in it: rules that colour cells by what
-- they hold, kept on a sheet (sheet.rules, in the order they count: the
-- first rule to say something about a cell wins what it says).
--
-- A rule is { kind =, r1, c1, r2, c2 = the cells it is about, a =, b =
-- what it compares with (as typed: a number, text, or a formula that
-- starts with =), n = how many for top and bottom, style = { fill =,
-- color =, bold =, italic = } for the kinds that colour a cell, and
-- scale = { colours } for a colour scale, bar = a colour for a data bar }.
--
--   local rule = condfmt.new("greater", 1, 1, 20, 1); rule.a = "10"
--   local look = condfmt.evaluator(book, sheet)
--   look(3, 1)     --> { fill = "#ffc7ce", color = "#9c0006" } or nil
--
-- What a cell gets is { fill, color, bold, italic, bar = { fraction, colour } }.

local formula = require "formula"

local M = {}

-- KINDS are what a rule can ask, in the order a menu lists them: its name,
-- what it is called, and how many things it compares with (a, b).
M.KINDS = {
  { "greater", "Greater than", 1 }, { "greaterEq", "Greater than or equal to", 1 },
  { "less", "Less than", 1 }, { "lessEq", "Less than or equal to", 1 },
  { "equal", "Equal to", 1 }, { "notEqual", "Not equal to", 1 },
  { "between", "Between", 2 }, { "notBetween", "Not between", 2 },
  { "contains", "Text contains", 1 }, { "notContains", "Text does not contain", 1 },
  { "beginsWith", "Text begins with", 1 }, { "endsWith", "Text ends with", 1 },
  { "empty", "Is empty", 0 }, { "notEmpty", "Is not empty", 0 }, { "error", "Is an error", 0 },
  { "duplicate", "Is a duplicate", 0 }, { "unique", "Is unique", 0 },
  { "top", "In the top", "n" }, { "bottom", "In the bottom", "n" },
  { "aboveAvg", "Above average", 0 }, { "belowAvg", "Below average", 0 },
  { "formula", "Formula is true", 1 },
  { "scale", "Colour scale", 0 }, { "bar", "Data bar", 0 },
}

M.byName = {}
for i, k in ipairs(M.KINDS) do M.byName[k[1]] = { name = k[1], label = k[2], operands = k[3], index = i } end

-- STYLES are ready-made looks for the rules that colour a cell.
M.STYLES = {
  { "Light red fill with dark red text", { fill = "#ffc7ce", color = "#9c0006" } },
  { "Yellow fill with dark yellow text", { fill = "#ffeb9c", color = "#9c5700" } },
  { "Green fill with dark green text", { fill = "#c6efce", color = "#006100" } },
  { "Light blue fill with dark blue text", { fill = "#bdd7ee", color = "#1f3864" } },
  { "Red text", { color = "#c00000" } },
  { "Green text", { color = "#00802b" } },
  { "Bold", { bold = true } },
  { "Red fill", { fill = "#e06666", color = "#ffffff" } },
}

M.SCALES = {
  { "Green, yellow, red", { "#63be7b", "#ffeb84", "#f8696b" } },
  { "Red, yellow, green", { "#f8696b", "#ffeb84", "#63be7b" } },
  { "White to green", { "#ffffff", "#63be7b" } },
  { "White to red", { "#ffffff", "#f8696b" } },
  { "White to blue", { "#ffffff", "#5a8ac6" } },
}

---------------------------------------------------------------- ranges

-- rangeName writes the cells of a rule as A1:B20 (A1 for one).
function M.rangeName(rule)
  local a, b = formula.refName(rule.r1, rule.c1), formula.refName(rule.r2, rule.c2)
  return a == b and a or (a .. ":" .. b)
end

-- parseRange reads A1 or A1:B20 (with $ if you like), putting the corners in
-- order: r1, c1, r2, c2, or nil.
function M.parseRange(text)
  text = (text or ""):gsub("%s+", "")
  local a, b = text:match("^([^:]+):([^:]+)$")
  if not a then a = text:match("^([^:]+)$") b = a end
  if not a then return nil end
  local r1, c1 = formula.parseRef(a)
  local r2, c2 = formula.parseRef(b)
  if not (r1 and r2) then return nil end
  return math.min(r1, r2), math.min(c1, c2), math.max(r1, r2), math.max(c1, c2)
end

---------------------------------------------------------------- rules

-- new makes a rule of a kind, about the cells r1, c1 to r2, c2, with a look
-- to begin with.
function M.new(kind, r1, c1, r2, c2)
  local rule = { kind = kind, r1 = r1, c1 = c1, r2 = r2, c2 = c2, a = "", b = "", n = 10 }
  if kind == "scale" then
    rule.scale = { M.SCALES[1][2][1], M.SCALES[1][2][2], M.SCALES[1][2][3] }
  elseif kind == "bar" then
    rule.bar = "#638ec6"
  else
    rule.style = { fill = M.STYLES[1][2].fill, color = M.STYLES[1][2].color }
  end
  return rule
end

local function copyList(t)
  local out = {}
  for i, v in ipairs(t) do out[i] = v end
  return out
end

function M.copy(rule)
  local c = {}
  for k, v in pairs(rule) do c[k] = v end
  if rule.style then
    c.style = {}
    for k, v in pairs(rule.style) do c.style[k] = v end
  end
  if rule.scale then c.scale = copyList(rule.scale) end
  return c
end

function M.copyAll(rules)
  local out = {}
  for i, r in ipairs(rules or {}) do out[i] = M.copy(r) end
  return out
end

-- describe says what a rule asks, in words.
function M.describe(rule)
  local k = M.byName[rule.kind]
  if not k then return tostring(rule.kind) end
  local s = k.label
  if rule.kind == "top" or rule.kind == "bottom" then
    s = ("%s %d"):format(s, rule.n or 10)
  elseif k.operands == 1 then
    s = s .. " " .. tostring(rule.a or "")
  elseif k.operands == 2 then
    s = ("%s %s and %s"):format(s, tostring(rule.a or ""), tostring(rule.b or ""))
  end
  return s
end

local function colour(v)
  return type(v) == "string" and v:match("^#%x%x%x%x%x%x$") and v or nil
end

-- clean makes a rule of what a file had, or nil when it is not one.
function M.clean(t)
  if type(t) ~= "table" or not M.byName[t.kind] then return nil end
  local r1, c1, r2, c2 = tonumber(t.r1), tonumber(t.c1), tonumber(t.r2), tonumber(t.c2)
  if not (r1 and c1 and r2 and c2) or r1 < 1 or c1 < 1 then return nil end
  local rule = { kind = t.kind, r1 = math.min(r1, r2), c1 = math.min(c1, c2), r2 = math.max(r1, r2), c2 = math.max(c1, c2),
    a = type(t.a) == "string" and t.a or (type(t.a) == "number" and tostring(t.a) or ""),
    b = type(t.b) == "string" and t.b or (type(t.b) == "number" and tostring(t.b) or ""),
    n = math.max(1, math.floor(tonumber(t.n) or 10)) }
  if t.kind == "scale" then
    rule.scale = {}
    for _, c in ipairs(type(t.scale) == "table" and t.scale or {}) do
      if colour(c) then rule.scale[#rule.scale + 1] = c end
    end
    if #rule.scale < 2 or #rule.scale > 3 then rule.scale = copyList(M.SCALES[1][2]) end
  elseif t.kind == "bar" then
    rule.bar = colour(t.bar) or "#638ec6"
  else
    rule.style = {}
    local st = type(t.style) == "table" and t.style or {}
    rule.style.fill, rule.style.color = colour(st.fill), colour(st.color)
    rule.style.bold, rule.style.italic = st.bold == true or nil, st.italic == true or nil
  end
  return rule
end

---------------------------------------------------------------- looking

local function rgb(c)
  return tonumber(c:sub(2, 3), 16), tonumber(c:sub(4, 5), 16), tonumber(c:sub(6, 7), 16)
end

-- mix is the colour a fraction of the way from one colour to another.
local function mix(a, b, f)
  local r1, g1, b1 = rgb(a)
  local r2, g2, b2 = rgb(b)
  local function part(x, y) return math.floor(x + (y - x) * f + 0.5) end
  return ("#%02x%02x%02x"):format(part(r1, r2), part(g1, g2), part(b1, b2))
end
M.mix = mix

-- scaleColour is the colour of v between lo and hi on a scale of 2 or 3.
local function scaleColour(colors, v, lo, hi)
  if hi <= lo then return colors[1] end
  local f = (v - lo) / (hi - lo)
  if #colors == 2 then return mix(colors[1], colors[2], f) end
  if f <= 0.5 then return mix(colors[1], colors[2], f * 2) end
  return mix(colors[2], colors[3], (f - 0.5) * 2)
end

-- Cells of a rule's range that hold something, as { r, c, v }; and the
-- numbers among them.
local function gather(book, sheet, rule)
  local cells, nums = {}, {}
  for r = rule.r1, math.min(rule.r2, math.max(sheet.rows, rule.r1)) do
    local row = sheet.cells[r]
    if row then
      for c = rule.c1, math.min(rule.c2, math.max(sheet.cols, rule.c1)) do
        if row[c] ~= nil then
          local v = book:value(sheet, r, c)
          cells[#cells + 1] = { r, c, v }
          if type(v) == "number" then nums[#nums + 1] = v end
        end
      end
    end
  end
  return cells, nums
end

local function truthy(v)
  if type(v) == "boolean" then return v end
  if type(v) == "number" then return v ~= 0 end
  return false
end

-- operand is what a rule compares with: a number, or text, or the value of a
-- formula (worked out at the rule's first cell).
local function operand(book, sheet, rule, text)
  text = (text or ""):match("^%s*(.-)%s*$")
  if text:sub(1, 1) == "=" and #text > 1 then
    local v = formula.evaluate(book:tree(text), book:context(sheet, rule.r1, rule.c1))
    return v
  end
  return tonumber(text) or text
end

-- prepare works out what a rule needs of its whole range: the numbers, the
-- ends, the average, which values come twice. It gives the test of one cell.
local function prepare(book, sheet, rule)
  local kind = rule.kind
  local k = M.byName[kind]
  local a, b
  if k.operands == 1 or k.operands == 2 then
    a = operand(book, sheet, rule, rule.a)
    b = k.operands == 2 and operand(book, sheet, rule, rule.b) or nil
  end
  local function num(v) return type(v) == "number" and v or nil end
  local function textOf(v) return formula.text(v):lower() end
  local needle = type(a) == "string" and a:lower() or tostring(a or ""):lower()

  if kind == "greater" then return function(v) return num(v) and num(a) and v > a end
  elseif kind == "greaterEq" then return function(v) return num(v) and num(a) and v >= a end
  elseif kind == "less" then return function(v) return num(v) and num(a) and v < a end
  elseif kind == "lessEq" then return function(v) return num(v) and num(a) and v <= a end
  elseif kind == "equal" or kind == "notEqual" then
    local want = kind == "equal"
    return function(v)
      if v == nil then return false end
      local same
      if num(v) and num(a) then same = v == a else same = textOf(v) == needle end
      return same == want
    end
  elseif kind == "between" or kind == "notBetween" then
    local lo, hi = num(a), num(b)
    if lo and hi and lo > hi then lo, hi = hi, lo end
    local inside = kind == "between"
    return function(v)
      if not (num(v) and lo and hi) then return false end
      return (v >= lo and v <= hi) == inside
    end
  elseif kind == "contains" then return function(v) return v ~= nil and textOf(v):find(needle, 1, true) ~= nil end
  elseif kind == "notContains" then return function(v) return v ~= nil and textOf(v):find(needle, 1, true) == nil end
  elseif kind == "beginsWith" then return function(v) return v ~= nil and textOf(v):sub(1, #needle) == needle end
  elseif kind == "endsWith" then return function(v) return v ~= nil and needle ~= "" and textOf(v):sub(-#needle) == needle end
  elseif kind == "empty" then return function(v) return v == nil or v == "" end
  elseif kind == "notEmpty" then return function(v) return v ~= nil and v ~= "" end
  elseif kind == "error" then return function(v) return formula.isError(v) end
  end

  local cells, nums = gather(book, sheet, rule)
  if kind == "duplicate" or kind == "unique" then
    local counts = {}
    for _, x in ipairs(cells) do
      if x[3] ~= "" then
        local t = textOf(x[3])
        counts[t] = (counts[t] or 0) + 1
      end
    end
    local wantMany = kind == "duplicate"
    return function(v)
      if v == nil or v == "" then return false end
      return ((counts[textOf(v)] or 0) > 1) == wantMany
    end
  elseif kind == "top" or kind == "bottom" then
    table.sort(nums)
    local n = math.min(rule.n or 10, #nums)
    if n == 0 then return function() return false end end
    if kind == "top" then
      local limit = nums[#nums - n + 1]
      return function(v) return num(v) ~= nil and v >= limit end
    end
    local limit = nums[n]
    return function(v) return num(v) ~= nil and v <= limit end
  elseif kind == "aboveAvg" or kind == "belowAvg" then
    local sum = 0
    for _, v in ipairs(nums) do sum = sum + v end
    local avg = #nums > 0 and sum / #nums or 0
    if kind == "aboveAvg" then return function(v) return num(v) ~= nil and v > avg end end
    return function(v) return num(v) ~= nil and v < avg end
  elseif kind == "formula" then
    local raw = (rule.a or ""):match("^%s*(.-)%s*$")
    if raw:sub(1, 1) ~= "=" then raw = "=" .. raw end
    return nil, function(r, c)
      local shifted = raw
      if r ~= rule.r1 or c ~= rule.c1 then shifted = formula.shift(raw, r - rule.r1, c - rule.c1) end
      return truthy(formula.evaluate(book:tree(shifted), book:context(sheet, r, c)))
    end
  elseif kind == "scale" or kind == "bar" then
    local lo, hi
    for _, v in ipairs(nums) do
      lo = lo and math.min(lo, v) or v
      hi = hi and math.max(hi, v) or v
    end
    return nil, nil, { lo = lo, hi = hi }
  end
  return function() return false end
end

-- evaluator gives what to do with a cell of sheet: a function of r, c that
-- says how rules colour it, or nil. What the rules need of their ranges is
-- worked out the first time it is asked for, so it is made again for each
-- change of the workbook.
function M.evaluator(book, sheet)
  local rules = sheet.rules or {}
  if #rules == 0 then return function() end end
  local prepared = {}
  local function prep(i)
    local p = prepared[i]
    if p == nil then
      local test, perCell, range = prepare(book, sheet, rules[i])
      p = { test = test, perCell = perCell, range = range }
      prepared[i] = p
    end
    return p
  end
  return function(r, c)
    local out
    for i, rule in ipairs(rules) do
      if r >= rule.r1 and r <= rule.r2 and c >= rule.c1 and c <= rule.c2 then
        local v = book:value(sheet, r, c)
        local p = prep(i)
        local hit, effect = false, nil
        if rule.kind == "scale" then
          if type(v) == "number" and p.range.lo then
            effect = { fill = scaleColour(rule.scale, v, p.range.lo, p.range.hi) }
          end
        elseif rule.kind == "bar" then
          if type(v) == "number" and p.range.lo then
            local lo, hi = math.min(0, p.range.lo), math.max(0, p.range.hi)
            local f = hi > lo and math.max(0, (v - lo) / (hi - lo)) or 0
            if v > 0 or f > 0 then effect = { bar = { f, rule.bar } } end
          end
        else
          if p.test then hit = p.test(v) and true or false else hit = p.perCell(r, c) end
          if hit then
            effect = {}
            for k, x in pairs(rule.style or {}) do effect[k] = x end
          end
        end
        if effect then
          out = out or {}
          for k, x in pairs(effect) do
            if out[k] == nil then out[k] = x end
          end
        end
      end
    end
    return out
  end
end

---------------------------------------------------------------- changing

-- shift moves a rule's cells when rows or columns are put in or taken out of
-- a sheet: axis "row" or "col", at where, count how many (negative: taken
-- out, from at on). It gives false when nothing of the rule is left.
function M.shift(rule, axis, at, count)
  local lo, hi = axis == "row" and "r1" or "c1", axis == "row" and "r2" or "c2"
  if count > 0 then
    if rule[lo] >= at then rule[lo] = rule[lo] + count end
    if rule[hi] >= at then rule[hi] = rule[hi] + count end
    return true
  end
  local n = -count
  if rule[lo] >= at + n then rule[lo] = rule[lo] - n elseif rule[lo] >= at then rule[lo] = at end
  if rule[hi] >= at + n then rule[hi] = rule[hi] - n elseif rule[hi] >= at then rule[hi] = at - 1 end
  return rule[hi] >= rule[lo]
end

return M
