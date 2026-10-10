-- Formulas: what follows the "=" in a cell, read into a tree and worked
-- out, and rewritten when cells move. They are written as a spreadsheet
-- writes them:
--
--   =A1+B2*2        numbers, "text", TRUE and FALSE; + - * / ^ % & and
--                   the comparisons = <> < > <= >=
--   =SUM(A1:B10)    a range; =SUM(B:B) is a whole column
--   =Sheet2!A1      a cell on another sheet; ='Q1 Sales'!B4 when the name
--                   has spaces in it
--   =$A$1           a reference that stays put when the cell is copied
--
-- A value is a number, a string, a boolean, nil for an empty cell, or one
-- of the errors in M.errors.

local M = {}

M.MAX_ROWS = 1048576
M.MAX_COLS = 16384

---------------------------------------------------------------- errors

local function newError(text) return setmetatable({ err = text }, { __tostring = function() return text end }) end

M.errors = {
  DIV0 = newError("#DIV/0!"), VALUE = newError("#VALUE!"), REF = newError("#REF!"),
  NAME = newError("#NAME?"), NUM = newError("#NUM!"), NA = newError("#N/A"),
  CIRC = newError("#CIRC!"), PARSE = newError("#ERROR!"),
}
local E = M.errors
local byText = {}
for _, e in pairs(E) do byText[e.err] = e end

function M.isError(v) return type(v) == "table" and v.err ~= nil end

---------------------------------------------------------------- references

-- colName gives a column's letters: 1 is A, 27 is AA.
function M.colName(c)
  local s = ""
  while c > 0 do
    local d = (c - 1) % 26
    s = string.char(65 + d) .. s
    c = math.floor((c - 1) / 26)
  end
  return s
end

-- colIndex reads column letters, in either case.
function M.colIndex(s)
  local c = 0
  for i = 1, #s do c = c * 26 + (s:upper():byte(i) - 64) end
  return c
end

function M.refName(r, c) return M.colName(c) .. r end

-- parseRef reads "B12" or "$B$12" into row, column and whether each is
-- fixed; nil if it is not one.
function M.parseRef(s)
  local ac, letters, ar, digits = s:match("^(%$?)(%a+)(%$?)(%d+)$")
  if not letters or #letters > 3 then return nil end
  local r, c = tonumber(digits), M.colIndex(letters)
  if r < 1 or r > M.MAX_ROWS or c > M.MAX_COLS then return nil end
  return r, c, ar == "$", ac == "$"
end

-- sheetPrefix writes a sheet's name for a reference, quoted if it must be.
function M.sheetPrefix(name)
  if name:find("^[%a_][%w_%.]*$") and not M.parseRef(name) then return name .. "!" end
  return "'" .. name:gsub("'", "''") .. "'!"
end

---------------------------------------------------------------- tokens

-- tokenize splits formula text (without its "=") into tokens, each with
-- its kind (t), what it says (v) and where it is in the text (s, e).
function M.tokenize(text)
  local toks, i, n = {}, 1, #text
  local function add(t, v, s, e) toks[#toks + 1] = { t = t, v = v, s = s, e = e } end
  while i <= n do
    local ch = text:sub(i, i)
    if ch:find("%s") then
      i = i + 1
    elseif ch:find("%d") or (ch == "." and text:sub(i + 1, i + 1):find("%d")) then
      local num = text:match("^%d*%.?%d*", i)
      local exp = text:match("^[eE][-+]?%d+", i + #num)
      if exp then num = num .. exp end
      add("num", tonumber(num), i, i + #num - 1)
      i = i + #num
    elseif ch == '"' then
      local j, parts = i + 1, {}
      while true do
        local q = text:find('"', j, true)
        if not q then return nil, "a string is not finished" end
        parts[#parts + 1] = text:sub(j, q - 1)
        if text:sub(q + 1, q + 1) == '"' then
          parts[#parts + 1] = '"'
          j = q + 2
        else
          add("str", table.concat(parts), i, q)
          i = q + 1
          break
        end
      end
    elseif ch == "'" then
      local j, parts = i + 1, {}
      while true do
        local q = text:find("'", j, true)
        if not q then return nil, "a sheet name is not finished" end
        parts[#parts + 1] = text:sub(j, q - 1)
        if text:sub(q + 1, q + 1) == "'" then
          parts[#parts + 1] = "'"
          j = q + 2
        else
          if text:sub(q + 1, q + 1) ~= "!" then return nil, "a quoted name must be a sheet's" end
          add("sheet", table.concat(parts), i, q + 1)
          i = q + 2
          break
        end
      end
    elseif ch == "#" then
      local e = text:match("^#[%w/]+[!?]?", i)
      if not e or not byText[e:upper()] then return nil, "unknown error " .. (e or "#") end
      add("err", byText[e:upper()], i, i + #e - 1)
      i = i + #e
    elseif ch:find("[%a_%$]") then
      local word = text:match("^[%w_%.%$]+", i)
      local after = i + #word
      local follow = text:match("^%s*(.)", after)
      if text:sub(after, after) == "!" and not word:find("%$") then
        add("sheet", word, i, after)
        i = after + 1
      else
        local up = word:upper()
        if follow == "(" and not word:find("%$") then
          add("func", up, i, after - 1)
        elseif M.parseRef(word) then
          add("ref", up, i, after - 1)
        elseif up == "TRUE" or up == "FALSE" then
          add("bool", up == "TRUE", i, after - 1)
        elseif word:find("^%$?%a%a?%a?$") then
          add("col", up, i, after - 1)
        else
          add("name", word, i, after - 1)
        end
        i = after
      end
    else
      local two = text:sub(i, i + 1)
      if two == "<=" or two == ">=" or two == "<>" then
        add("op", two, i, i + 1)
        i = i + 2
      elseif ch:find("[%+%-%*/%^&%%=<>]") then
        add("op", ch, i, i)
        i = i + 1
      elseif ch == "(" or ch == ")" or ch == ":" then
        add(ch, ch, i, i)
        i = i + 1
      elseif ch == "," or ch == ";" then
        add(",", ch, i, i)
        i = i + 1
      else
        return nil, "unexpected '" .. ch .. "'"
      end
    end
  end
  return toks
end

---------------------------------------------------------------- parsing

-- parse reads formula text (without its "=") into a tree, or returns nil
-- and why not.
function M.parse(text)
  local toks, err = M.tokenize(text)
  if not toks then return nil, err end
  local pos = 1
  local function peek(k) return toks[pos + (k or 0)] end
  local function fail(msg) error({ formula = msg }) end
  local function take(t, v)
    local tok = toks[pos]
    if tok and tok.t == t and (v == nil or tok.v == v) then pos = pos + 1 return tok end
  end
  local expr

  local function cellOf(tok)
    local r, c, ar, ac = M.parseRef(tok.v)
    return r, c, ar, ac
  end

  -- reference reads a cell, a range or a column range, with its sheet.
  local function reference(sheet)
    local tok = take("ref") or take("col")
    if not tok then fail("a sheet name must be followed by a cell") end
    if tok.t == "col" then
      if not take(":") then fail("unknown name " .. tok.v) end
      local other = take("col")
      if not other then fail("expected a column after ':'") end
      local c1, c2 = M.colIndex(tok.v:gsub("%$", "")), M.colIndex(other.v:gsub("%$", ""))
      if c1 > M.MAX_COLS or c2 > M.MAX_COLS then fail("no such column") end
      return { k = "range", sheet = sheet, r1 = 1, c1 = math.min(c1, c2), r2 = M.MAX_ROWS, c2 = math.max(c1, c2), cols = true }
    end
    local r1, c1 = cellOf(tok)
    if peek() and peek().t == ":" and peek(1) and peek(1).t == "ref" then
      pos = pos + 1
      local r2, c2 = cellOf(take("ref"))
      return { k = "range", sheet = sheet, r1 = math.min(r1, r2), c1 = math.min(c1, c2), r2 = math.max(r1, r2), c2 = math.max(c1, c2) }
    end
    return { k = "ref", sheet = sheet, r = r1, c = c1 }
  end

  local function primary()
    local tok = peek()
    if not tok then fail("the formula ends too soon") end
    if tok.t == "num" then pos = pos + 1 return { k = "num", v = tok.v } end
    if tok.t == "str" then pos = pos + 1 return { k = "str", v = tok.v } end
    if tok.t == "bool" then pos = pos + 1 return { k = "bool", v = tok.v } end
    if tok.t == "err" then pos = pos + 1 return { k = "err", v = tok.v } end
    if tok.t == "sheet" then pos = pos + 1 return reference(tok.v) end
    if tok.t == "ref" or tok.t == "col" then return reference(nil) end
    if tok.t == "func" then
      pos = pos + 1
      take("(")
      local args = {}
      if not take(")") then
        while true do
          if peek() and (peek().t == "," or peek().t == ")") then
            args[#args + 1] = { k = "missing" }
          else
            args[#args + 1] = expr()
          end
          if take(")") then break end
          if not take(",") then fail("expected ',' or ')' in " .. tok.v) end
        end
      end
      return { k = "call", name = tok.v, args = args }
    end
    if tok.t == "(" then
      pos = pos + 1
      local e = expr()
      if not take(")") then fail("expected ')'") end
      return e
    end
    if tok.t == "name" then fail("unknown name " .. tok.v) end
    fail("unexpected " .. tostring(tok.v))
  end

  local function postfix()
    local e = primary()
    while take("op", "%") do e = { k = "pct", a = e } end
    return e
  end

  local function unary()
    if take("op", "-") then return { k = "neg", a = unary() } end
    if take("op", "+") then return unary() end
    return postfix()
  end

  local function binary(next, ops)
    return function()
      local e = next()
      while true do
        local tok = peek()
        if not (tok and tok.t == "op" and ops[tok.v]) then return e end
        pos = pos + 1
        e = { k = "bin", op = tok.v, a = e, b = next() }
      end
    end
  end

  local power = binary(unary, { ["^"] = true })
  local term = binary(power, { ["*"] = true, ["/"] = true })
  local additive = binary(term, { ["+"] = true, ["-"] = true })
  local concat = binary(additive, { ["&"] = true })
  expr = binary(concat, { ["="] = true, ["<>"] = true, ["<"] = true, [">"] = true, ["<="] = true, [">="] = true })

  local ok, result = pcall(function()
    local e = expr()
    if pos <= #toks then fail("unexpected " .. tostring(toks[pos].v)) end
    return e
  end)
  if ok then return result end
  if type(result) == "table" and result.formula then return nil, result.formula end
  error(result, 0)
end

-- refs lists the references in a tree: { sheet, r1, c1, r2, c2 } each.
function M.refs(node, out)
  out = out or {}
  if node.k == "ref" then
    out[#out + 1] = { sheet = node.sheet, r1 = node.r, c1 = node.c, r2 = node.r, c2 = node.c }
  elseif node.k == "range" then
    out[#out + 1] = { sheet = node.sheet, r1 = node.r1, c1 = node.c1, r2 = node.r2, c2 = node.c2 }
  end
  if node.a then M.refs(node.a, out) end
  if node.b then M.refs(node.b, out) end
  if node.args then for _, a in ipairs(node.args) do M.refs(a, out) end end
  return out
end

---------------------------------------------------------------- values

-- formatNumber writes a number as a cell shows it in general: whole
-- numbers in full, others to ten significant digits.
function M.formatNumber(n, digits)
  if n ~= n then return E.NUM.err end
  if n == math.floor(n) and math.abs(n) < 1e15 then return ("%d"):format(n) end
  local s = ("%." .. (digits or 10) .. "g"):format(n)
  if s:find("e") then
    s = s:gsub("%.?0+e", "e"):gsub("e%+?(%-?)0*(%d)", "e%1%2")
  end
  return s
end

-- text is how a value is shown and joined into text.
function M.text(v)
  if v == nil then return "" end
  local kind = type(v)
  if kind == "number" then return M.formatNumber(v) end
  if kind == "boolean" then return v and "TRUE" or "FALSE" end
  if kind == "table" and v.err then return v.err end
  return tostring(v)
end

-- toNumber turns a value into a number, or an error.
local function toNumber(v)
  local kind = type(v)
  if kind == "number" then return v end
  if v == nil then return 0 end
  if kind == "boolean" then return v and 1 or 0 end
  if kind == "string" then
    local s = v:match("^%s*(.-)%s*$")
    local pct = s:match("^(.-)%%$")
    local n = tonumber(pct or s)
    if n and pct then n = n / 100 end
    return n or E.VALUE
  end
  return v -- an error
end
M.toNumber = toNumber

local function toBool(v)
  local kind = type(v)
  if kind == "boolean" then return v end
  if v == nil then return false end
  if kind == "number" then return v ~= 0 end
  if kind == "string" then
    local up = v:upper()
    if up == "TRUE" then return true end
    if up == "FALSE" then return false end
    return E.VALUE
  end
  return v
end

-- compare orders two values as a spreadsheet does: numbers before text
-- before booleans, text without regard to case. An empty cell is 0 to a
-- number, "" to text and FALSE to a boolean.
local RANK = { number = 1, string = 2, boolean = 3 }
function M.compare(a, b)
  if a == nil and b == nil then return 0 end
  if a == nil then a = type(b) == "string" and "" or type(b) == "boolean" and false or 0 end
  if b == nil then b = type(a) == "string" and "" or type(a) == "boolean" and false or 0 end
  local ta, tb = type(a), type(b)
  if ta ~= tb then return RANK[ta] < RANK[tb] and -1 or 1 end
  if ta == "string" then a, b = a:lower(), b:lower() end
  if ta == "boolean" then a, b = a and 1 or 0, b and 1 or 0 end
  if a < b then return -1 end
  if a > b then return 1 end
  return 0
end

-- literal reads what was typed in a cell that is not a formula: a number,
-- a percentage, TRUE or FALSE, or text. A leading ' keeps it text.
function M.literal(raw)
  if raw == nil or raw == "" then return nil end
  if raw:sub(1, 1) == "'" then return raw:sub(2) end
  local s = raw:match("^%s*(.-)%s*$")
  local n = tonumber(s)
  if n and not s:find("^0[xX]") and n == n and n ~= math.huge and n ~= -math.huge then return n end
  local pct = s:match("^([-+]?[%d%.]+)%%$")
  if pct and tonumber(pct) then return tonumber(pct) / 100 end
  local up = s:upper()
  if up == "TRUE" then return true end
  if up == "FALSE" then return false end
  return raw
end

---------------------------------------------------------------- evaluation

-- A range, worked out, is a table that says where it is; functions read
-- its cells through each and at.
local function isRange(v) return type(v) == "table" and v.range end

local function clip(ctx, v)
  local rows, cols = ctx.size(v.sheet)
  return v.r1, v.c1, math.min(v.r2, math.max(rows, v.r1 - 1)), math.min(v.c2, math.max(cols, v.c1 - 1))
end

-- each calls fn(value, r, c) for each cell of a range that has something
-- in it, or for every cell when all is set. fn returning true stops it.
local function each(ctx, v, fn, all)
  local r1, c1, r2, c2 = clip(ctx, v)
  for r = r1, r2 do
    for c = c1, c2 do
      local x = ctx.value(v.sheet, r, c)
      if (x ~= nil or all) and fn(x, r, c) then return end
    end
  end
end

-- scalar is a value a function takes one of: a one-cell range is its cell.
local function scalar(ctx, v)
  if isRange(v) then
    if v.r1 == v.r2 and v.c1 == v.c2 then return ctx.value(v.sheet, v.r1, v.c1) end
    return E.VALUE
  end
  return v
end

local eval

local function arith(op, a, b)
  a, b = toNumber(a), toNumber(b)
  if M.isError(a) then return a end
  if M.isError(b) then return b end
  if op == "+" then return a + b end
  if op == "-" then return a - b end
  if op == "*" then return a * b end
  if op == "/" then
    if b == 0 then return E.DIV0 end
    return a / b
  end
  local r = a ^ b
  if r ~= r or r == math.huge or r == -math.huge then return E.NUM end
  return r
end

local F, LAZY = {}, {}
M.functions = F

function eval(node, ctx)
  local k = node.k
  if k == "num" or k == "str" or k == "bool" or k == "err" then return node.v end
  if k == "ref" then
    local v = ctx.value(node.sheet, node.r, node.c)
    return v
  end
  if k == "range" then
    if node.sheet and not ctx.size(node.sheet) then return E.REF end
    return { range = true, sheet = node.sheet, r1 = node.r1, c1 = node.c1, r2 = node.r2, c2 = node.c2 }
  end
  if k == "missing" then return nil end
  if k == "neg" then
    local a = toNumber(scalar(ctx, eval(node.a, ctx)))
    if M.isError(a) then return a end
    return -a
  end
  if k == "pct" then
    local a = toNumber(scalar(ctx, eval(node.a, ctx)))
    if M.isError(a) then return a end
    return a / 100
  end
  if k == "bin" then
    local a = scalar(ctx, eval(node.a, ctx))
    local b = scalar(ctx, eval(node.b, ctx))
    local op = node.op
    if M.isError(a) then return a end
    if M.isError(b) then return b end
    if op == "&" then return M.text(a) .. M.text(b) end
    if op == "=" then return M.compare(a, b) == 0 end
    if op == "<>" then return M.compare(a, b) ~= 0 end
    if op == "<" then return M.compare(a, b) < 0 end
    if op == ">" then return M.compare(a, b) > 0 end
    if op == "<=" then return M.compare(a, b) <= 0 end
    if op == ">=" then return M.compare(a, b) >= 0 end
    return arith(op, a, b)
  end
  if k == "call" then
    local lazy = LAZY[node.name]
    if lazy then return lazy(ctx, node.args) end
    local fn = F[node.name]
    if not fn then return E.NAME end
    local args = {}
    for i, a in ipairs(node.args) do args[i] = eval(a, ctx) end
    return fn(ctx, args, #node.args)
  end
  return E.PARSE
end

-- evaluate works out a parsed formula. ctx gives the cells:
--   ctx.value(sheet, r, c)   a cell's value; sheet nil for the formula's own
--   ctx.size(sheet)          how many rows and columns the sheet uses, or
--                            nil when there is no such sheet
-- A range left over at the end is its one cell, or #VALUE!.
function M.evaluate(tree, ctx)
  local v = scalar(ctx, eval(tree, ctx))
  if type(v) == "number" and (v ~= v or v == math.huge or v == -math.huge) then return E.NUM end
  return v
end

---------------------------------------------------------------- functions

-- numbers calls fn(n) for the numbers among args as SUM takes them: in a
-- range only numbers count; given directly, text that reads as a number
-- does too. It returns an error if one came up.
local function numbers(ctx, args, fn)
  local bad
  for _, a in ipairs(args) do
    if isRange(a) then
      each(ctx, a, function(v)
        if M.isError(v) then bad = v return true end
        if type(v) == "number" then fn(v) end
      end)
    elseif a ~= nil then
      local n = toNumber(a)
      if M.isError(n) then bad = n end
      if type(n) == "number" then fn(n) end
    end
    if bad then return bad end
  end
end

-- num takes one argument as a number, or the error it gives.
local function num(ctx, v, default)
  if v == nil and default ~= nil then return default end
  return toNumber(scalar(ctx, v))
end

local function str(ctx, v)
  v = scalar(ctx, v)
  if M.isError(v) then return nil, v end
  return M.text(v)
end

-- math1 makes a function of one number.
local function math1(f)
  return function(ctx, args)
    local x = num(ctx, args[1])
    if M.isError(x) then return x end
    return f(x)
  end
end

local function roundTo(x, d, how)
  local m = 10 ^ d
  local y = math.abs(x) * m
  y = y * (1 + 2 ^ -50) -- 1.005 is 1.00499999...; nudge it up
  if how == "up" then y = math.ceil(y - y * 2 ^ -48)
  elseif how == "down" then y = math.floor(y)
  else y = math.floor(y + 0.5) end
  local r = y / m
  return x < 0 and -r or r
end

local function rounder(how)
  return function(ctx, args)
    local x, d = num(ctx, args[1]), num(ctx, args[2], 0)
    if M.isError(x) then return x end
    if M.isError(d) then return d end
    return roundTo(x, math.floor(d), how)
  end
end

F.SUM = function(ctx, args)
  local s = 0
  return numbers(ctx, args, function(n) s = s + n end) or s
end

F.PRODUCT = function(ctx, args)
  local p, any = 1, false
  return numbers(ctx, args, function(n) p, any = p * n, true end) or (any and p or 0)
end

F.AVERAGE = function(ctx, args)
  local s, n = 0, 0
  local bad = numbers(ctx, args, function(x) s, n = s + x, n + 1 end)
  if bad then return bad end
  if n == 0 then return E.DIV0 end
  return s / n
end
F.AVG = F.AVERAGE

F.MAX = function(ctx, args)
  local m
  return numbers(ctx, args, function(n) if not m or n > m then m = n end end) or m or 0
end

F.MIN = function(ctx, args)
  local m
  return numbers(ctx, args, function(n) if not m or n < m then m = n end end) or m or 0
end

F.MEDIAN = function(ctx, args)
  local list = {}
  local bad = numbers(ctx, args, function(n) list[#list + 1] = n end)
  if bad then return bad end
  if #list == 0 then return E.NUM end
  table.sort(list)
  local mid = math.floor((#list + 1) / 2)
  if #list % 2 == 1 then return list[mid] end
  return (list[mid] + list[mid + 1]) / 2
end

local function variance(ctx, args, sample)
  local list, s = {}, 0
  local bad = numbers(ctx, args, function(n) list[#list + 1] = n s = s + n end)
  if bad then return bad end
  local n = #list
  if n < (sample and 2 or 1) then return E.DIV0 end
  local mean, ss = s / n, 0
  for _, x in ipairs(list) do ss = ss + (x - mean) ^ 2 end
  return ss / (sample and n - 1 or n)
end
F.STDEV = function(ctx, args)
  local v = variance(ctx, args, true)
  return M.isError(v) and v or math.sqrt(v)
end
F.VAR = function(ctx, args) return variance(ctx, args, true) end

F.COUNT = function(ctx, args)
  local n = 0
  for _, a in ipairs(args) do
    if isRange(a) then
      each(ctx, a, function(v) if type(v) == "number" then n = n + 1 end end)
    elseif type(toNumber(a)) == "number" and a ~= nil then
      n = n + 1
    end
  end
  return n
end

F.COUNTA = function(ctx, args, given)
  local n = 0
  for i = 1, given do
    local a = args[i]
    if isRange(a) then each(ctx, a, function() n = n + 1 end)
    elseif a ~= nil then n = n + 1 end
  end
  return n
end

F.COUNTBLANK = function(ctx, args)
  local a = args[1]
  if not isRange(a) then return E.VALUE end
  local n = 0
  each(ctx, a, function(v) if v == nil or v == "" then n = n + 1 end end, true)
  return n
end

F.ROUND = rounder("near")
F.ROUNDUP = rounder("up")
F.ROUNDDOWN = rounder("down")
F.TRUNC = rounder("down")
F.INT = math1(math.floor)
F.ABS = math1(math.abs)
F.SIGN = math1(function(x) return x > 0 and 1 or x < 0 and -1 or 0 end)
F.EXP = math1(math.exp)
F.SQRT = math1(function(x) if x < 0 then return E.NUM end return math.sqrt(x) end)
F.LN = math1(function(x) if x <= 0 then return E.NUM end return math.log(x) end)
F.LOG10 = math1(function(x) if x <= 0 then return E.NUM end return math.log10(x) end)
F.PI = function() return math.pi end

F.LOG = function(ctx, args)
  local x, b = num(ctx, args[1]), num(ctx, args[2], 10)
  if M.isError(x) then return x end
  if M.isError(b) then return b end
  if x <= 0 or b <= 0 or b == 1 then return E.NUM end
  return math.log(x) / math.log(b)
end

F.POWER = function(ctx, args) return arith("^", num(ctx, args[1]), num(ctx, args[2])) end

F.MOD = function(ctx, args)
  local a, b = num(ctx, args[1]), num(ctx, args[2])
  if M.isError(a) then return a end
  if M.isError(b) then return b end
  if b == 0 then return E.DIV0 end
  return a - b * math.floor(a / b)
end

local function toMultiple(how)
  return function(ctx, args)
    local x, s = num(ctx, args[1]), num(ctx, args[2], 1)
    if M.isError(x) then return x end
    if M.isError(s) then return s end
    if s == 0 then return 0 end
    local q = x / s
    return (how == "up" and math.ceil(q - 1e-12) or math.floor(q + 1e-12)) * s
  end
end
F.CEILING = toMultiple("up")
F.FLOOR = toMultiple("down")

F.SUMPRODUCT = function(ctx, args)
  local first = args[1]
  if not isRange(first) then return E.VALUE end
  local h, w = first.r2 - first.r1, first.c2 - first.c1
  for _, a in ipairs(args) do
    if not isRange(a) or a.r2 - a.r1 ~= h or a.c2 - a.c1 ~= w then return E.VALUE end
  end
  if first.r2 == M.MAX_ROWS then
    local rows = ctx.size(first.sheet) or 0
    h = math.max(0, rows - first.r1)
  end
  local total = 0
  for dr = 0, h do
    for dc = 0, w do
      local p = 1
      for _, a in ipairs(args) do
        local v = ctx.value(a.sheet, a.r1 + dr, a.c1 + dc)
        if M.isError(v) then return v end
        p = p * (type(v) == "number" and v or 0)
      end
      total = total + p
    end
  end
  return total
end

---------------------------------------------------------------- logic

LAZY.IF = function(ctx, nodes)
  if #nodes < 2 then return E.VALUE end
  local c = toBool(scalar(ctx, eval(nodes[1], ctx)))
  if M.isError(c) then return c end
  if c then return scalar(ctx, eval(nodes[2], ctx)) end
  if nodes[3] then return scalar(ctx, eval(nodes[3], ctx)) end
  return false
end

LAZY.IFERROR = function(ctx, nodes)
  local v = scalar(ctx, eval(nodes[1], ctx))
  if M.isError(v) then return nodes[2] and scalar(ctx, eval(nodes[2], ctx)) or nil end
  return v
end

LAZY.IFNA = function(ctx, nodes)
  local v = scalar(ctx, eval(nodes[1], ctx))
  if v == E.NA then return nodes[2] and scalar(ctx, eval(nodes[2], ctx)) or nil end
  return v
end

-- bools calls fn(b) for each truth value among args.
local function bools(ctx, args, fn)
  for _, a in ipairs(args) do
    if isRange(a) then
      local bad
      each(ctx, a, function(v)
        if M.isError(v) then bad = v return true end
        if type(v) == "boolean" or type(v) == "number" then fn(toBool(v)) end
      end)
      if bad then return bad end
    else
      local b = toBool(a)
      if M.isError(b) then return b end
      fn(b)
    end
  end
end

F.AND = function(ctx, args)
  local all = true
  return bools(ctx, args, function(b) all = all and b end) or all
end
F.OR = function(ctx, args)
  local any = false
  return bools(ctx, args, function(b) any = any or b end) or any
end
F.XOR = function(ctx, args)
  local odd = false
  return bools(ctx, args, function(b) if b then odd = not odd end end) or odd
end
F.NOT = function(ctx, args)
  local b = toBool(scalar(ctx, args[1]))
  if M.isError(b) then return b end
  return not b
end
F.TRUE = function() return true end
F.FALSE = function() return false end

F.ISBLANK = function(ctx, args) return scalar(ctx, args[1]) == nil end
F.ISNUMBER = function(ctx, args) return type(scalar(ctx, args[1])) == "number" end
F.ISTEXT = function(ctx, args) return type(scalar(ctx, args[1])) == "string" end
F.ISERROR = function(ctx, args) return M.isError(scalar(ctx, args[1])) end
F.ISNA = function(ctx, args) return scalar(ctx, args[1]) == E.NA end
F.NA = function() return E.NA end

F.CHOOSE = function(ctx, args)
  local i = num(ctx, args[1])
  if M.isError(i) then return i end
  i = math.floor(i)
  if i < 1 or i >= #args then return E.VALUE end
  return scalar(ctx, args[i + 1])
end

---------------------------------------------------------------- text

-- textArgs makes a function of text arguments; spec says which are
-- numbers ("n") and which text ("s"), with defaults.
local function textFn(spec, f)
  return function(ctx, args)
    local vals = {}
    for i, kind in ipairs(spec) do
      local a = args[i]
      if a == nil and kind.default ~= nil then
        vals[i] = kind.default
      elseif kind[1] == "n" then
        local n = num(ctx, a)
        if M.isError(n) then return n end
        vals[i] = n
      else
        local s, bad = str(ctx, a)
        if bad then return bad end
        vals[i] = s
      end
    end
    return f(unpack(vals, 1, #spec))
  end
end

F.CONCAT = function(ctx, args, given)
  local out = {}
  for i = 1, given do
    local a = args[i]
    if isRange(a) then
      local bad
      each(ctx, a, function(v)
        if M.isError(v) then bad = v return true end
        out[#out + 1] = M.text(v)
      end)
      if bad then return bad end
    else
      if M.isError(a) then return a end
      out[#out + 1] = M.text(a)
    end
  end
  return table.concat(out)
end
F.CONCATENATE = F.CONCAT

F.TEXTJOIN = function(ctx, args, given)
  local sep, bad = str(ctx, args[1])
  if bad then return bad end
  local skipEmpty = toBool(scalar(ctx, args[2]))
  if M.isError(skipEmpty) then return skipEmpty end
  local out = {}
  for i = 3, given do
    local a = args[i]
    local list = {}
    if isRange(a) then
      each(ctx, a, function(v) list[#list + 1] = v end, true)
    else
      list[1] = a
    end
    for _, v in ipairs(list) do
      if M.isError(v) then return v end
      local s = M.text(v)
      if s ~= "" or not skipEmpty then out[#out + 1] = s end
    end
  end
  return table.concat(out, sep)
end

local S, N = { "s" }, { "n" }
F.UPPER = textFn({ S }, string.upper)
F.LOWER = textFn({ S }, string.lower)
F.PROPER = textFn({ S }, function(s)
  return (s:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end)
F.LEN = textFn({ S }, function(s) return #s end)
F.TRIM = textFn({ S }, function(s) return (s:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")) end)
F.LEFT = textFn({ S, { "n", default = 1 } }, function(s, n)
  if n < 0 then return E.VALUE end
  return s:sub(1, math.floor(n))
end)
F.RIGHT = textFn({ S, { "n", default = 1 } }, function(s, n)
  if n < 0 then return E.VALUE end
  n = math.floor(n)
  if n == 0 then return "" end
  return s:sub(-n)
end)
F.MID = textFn({ S, N, N }, function(s, i, n)
  if i < 1 or n < 0 then return E.VALUE end
  return s:sub(math.floor(i), math.floor(i) + math.floor(n) - 1)
end)
F.REPT = textFn({ S, N }, function(s, n)
  if n < 0 then return E.VALUE end
  return s:rep(math.floor(n))
end)
F.SUBSTITUTE = textFn({ S, S, S }, function(s, old, new)
  if old == "" then return s end
  return (s:gsub(old:gsub("%p", "%%%0"), (new:gsub("%%", "%%%%"))))
end)
F.FIND = textFn({ S, S, { "n", default = 1 } }, function(needle, s, from)
  local i = s:find(needle, math.floor(from), true)
  return i or E.VALUE
end)
F.SEARCH = textFn({ S, S, { "n", default = 1 } }, function(needle, s, from)
  local i = s:lower():find(needle:lower(), math.floor(from), true)
  return i or E.VALUE
end)
F.VALUE = function(ctx, args)
  local v = scalar(ctx, args[1])
  if type(v) == "number" then return v end
  return toNumber(M.text(v))
end
F.EXACT = textFn({ S, S }, function(a, b) return a == b end)

-- FIXED writes a number with so many decimals, and commas unless told not to.
F.FIXED = function(ctx, args)
  local x, d = num(ctx, args[1]), num(ctx, args[2], 2)
  if M.isError(x) then return x end
  if M.isError(d) then return d end
  local plain = toBool(scalar(ctx, args[3]))
  d = math.max(0, math.floor(d))
  local s = ("%." .. d .. "f"):format(roundTo(x, d))
  if plain ~= true then
    local sign, int, frac = s:match("^(-?)(%d+)(.*)$")
    int = int:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    s = sign .. int .. frac
  end
  return s
end

---------------------------------------------------------------- conditions

-- criterion turns SUMIF's condition into a test: ">5", "<>x", "=a*",
-- "apple" (the same, without regard to case; * and ? as wildcards), or a
-- number.
local function criterion(c)
  if type(c) ~= "string" then
    return function(v) return v ~= nil and M.compare(v, c) == 0 end
  end
  local op, rest = c:match("^([<>=]=?)(.*)$")
  if c:sub(1, 2) == "<>" then op, rest = "<>", c:sub(3) end
  op = op or "="
  local target = M.literal(rest or c)
  if type(target) == "string" and (op == "=" or op == "<>") then
    local pat = "^" .. target:lower():gsub("[%^%$%(%)%%%.%[%]%+%-]", "%%%0"):gsub("%*", ".*"):gsub("%?", ".") .. "$"
    local function same(v) return v ~= nil and M.text(v):lower():find(pat) ~= nil end
    if op == "=" then return same end
    return function(v) return not same(v) end
  end
  if target == nil then
    if op == "=" then return function(v) return v == nil or v == "" end end
    if op == "<>" then return function(v) return v ~= nil and v ~= "" end end
  end
  return function(v)
    if v == nil or type(v) ~= type(target) then return op == "<>" end
    local d = M.compare(v, target)
    if op == "=" then return d == 0 end
    if op == "<>" then return d ~= 0 end
    if op == "<" then return d < 0 end
    if op == ">" then return d > 0 end
    if op == "<=" then return d <= 0 end
    return d >= 0
  end
end

-- matching calls fn(r, c) for the cells of a range that meet a condition.
local function conditional(ctx, args, fn)
  local range = args[1]
  if not isRange(range) then return E.VALUE end
  local cv = scalar(ctx, args[2])
  if M.isError(cv) then return cv end
  local test = criterion(cv)
  local other = args[3]
  if other ~= nil and not isRange(other) then return E.VALUE end
  each(ctx, range, function(v, r, c)
    if test(v) then
      local value = v
      if other then value = ctx.value(other.sheet, other.r1 + r - range.r1, other.c1 + c - range.c1) end
      fn(value)
    end
  end, true)
end

F.COUNTIF = function(ctx, args)
  local n = 0
  return conditional(ctx, { args[1], args[2] }, function() n = n + 1 end) or n
end
F.SUMIF = function(ctx, args)
  local s = 0
  return conditional(ctx, args, function(v) if type(v) == "number" then s = s + v end end) or s
end
F.AVERAGEIF = function(ctx, args)
  local s, n = 0, 0
  local bad = conditional(ctx, args, function(v) if type(v) == "number" then s, n = s + v, n + 1 end end)
  if bad then return bad end
  if n == 0 then return E.DIV0 end
  return s / n
end

---------------------------------------------------------------- lookups

-- position finds a value in a row or column of cells (got(i) gives the
-- i'th), exactly or, with sorted, the last that is not more.
local function position(want, count, got, sorted)
  local found
  for i = 1, count do
    local v = got(i)
    if sorted then
      if v ~= nil and type(v) == type(want) then
        if M.compare(v, want) <= 0 then found = i else break end
      end
    elseif v ~= nil and M.compare(v, want) == 0 then
      return i
    end
  end
  return found
end

local function lookup(ctx, args, vertical)
  local want, t = scalar(ctx, args[1]), args[2]
  if M.isError(want) then return want end
  if not isRange(t) then return E.VALUE end
  local idx = num(ctx, args[3])
  if M.isError(idx) then return idx end
  idx = math.floor(idx)
  local sorted = args[4] == nil or toBool(scalar(ctx, args[4])) == true
  local r1, c1, r2, c2 = clip(ctx, t)
  if vertical then
    if idx < 1 or idx > t.c2 - t.c1 + 1 then return E.REF end
    local i = position(want, r2 - r1 + 1, function(i) return ctx.value(t.sheet, r1 + i - 1, c1) end, sorted)
    if not i then return E.NA end
    return ctx.value(t.sheet, r1 + i - 1, c1 + idx - 1)
  end
  if idx < 1 or idx > t.r2 - t.r1 + 1 then return E.REF end
  local i = position(want, c2 - c1 + 1, function(i) return ctx.value(t.sheet, r1, c1 + i - 1) end, sorted)
  if not i then return E.NA end
  return ctx.value(t.sheet, r1 + idx - 1, c1 + i - 1)
end

F.VLOOKUP = function(ctx, args) return lookup(ctx, args, true) end
F.HLOOKUP = function(ctx, args) return lookup(ctx, args, false) end

F.INDEX = function(ctx, args)
  local t = args[1]
  if not isRange(t) then return E.VALUE end
  local r, c = num(ctx, args[2], 1), num(ctx, args[3], 1)
  if M.isError(r) then return r end
  if M.isError(c) then return c end
  r, c = math.floor(r), math.floor(c)
  -- A single row takes its one index as the column.
  if t.r1 == t.r2 and args[3] == nil then r, c = 1, r end
  if r < 1 or c < 1 or r > t.r2 - t.r1 + 1 or c > t.c2 - t.c1 + 1 then return E.REF end
  return ctx.value(t.sheet, t.r1 + r - 1, t.c1 + c - 1)
end

F.MATCH = function(ctx, args)
  local want, t = scalar(ctx, args[1]), args[2]
  if M.isError(want) then return want end
  if not isRange(t) then return E.NA end
  local kind = num(ctx, args[3], 1)
  if M.isError(kind) then return kind end
  local r1, c1, r2, c2 = clip(ctx, t)
  local vertical = t.c1 == t.c2
  local count = vertical and (r2 - r1 + 1) or (c2 - c1 + 1)
  local function got(i)
    if vertical then return ctx.value(t.sheet, r1 + i - 1, c1) end
    return ctx.value(t.sheet, r1, c1 + i - 1)
  end
  local i
  if kind == 0 then
    if type(want) == "string" then
      local test = criterion("=" .. want)
      for k = 1, count do if test(got(k)) then i = k break end end
    else
      i = position(want, count, got, false)
    end
  elseif kind > 0 then
    i = position(want, count, got, true)
  else
    for k = 1, count do
      local v = got(k)
      if v ~= nil and type(v) == type(want) and M.compare(v, want) >= 0 then i = k else break end
    end
  end
  return i or E.NA
end

-- ROW and COLUMN read the reference they are given, not its value.
LAZY.ROW = function(ctx, nodes)
  local n = nodes[1]
  if not n then return ctx.row end
  if n.k == "ref" then return n.r end
  if n.k == "range" then return n.r1 end
  return E.VALUE
end
LAZY.COLUMN = function(ctx, nodes)
  local n = nodes[1]
  if not n then return ctx.col end
  if n.k == "ref" then return n.c end
  if n.k == "range" then return n.c1 end
  return E.VALUE
end
LAZY.ROWS = function(ctx, nodes)
  local n = nodes[1]
  if n and n.k == "range" then return n.r2 - n.r1 + 1 end
  if n and n.k == "ref" then return 1 end
  return E.VALUE
end
LAZY.COLUMNS = function(ctx, nodes)
  local n = nodes[1]
  if n and n.k == "range" then return n.c2 - n.c1 + 1 end
  if n and n.k == "ref" then return 1 end
  return E.VALUE
end

-- names lists every function, for the help.
function M.names()
  local list = {}
  for name in pairs(F) do list[#list + 1] = name end
  for name in pairs(LAZY) do list[#list + 1] = name end
  table.sort(list)
  return list
end

---------------------------------------------------------------- rewriting

-- rewrite calls fn for each reference in formula text and puts what it
-- returns in its place. fn gets { sheet, r1, c1, r2, c2, ar1, ac1, ar2,
-- ac2, cols } (the a's say which parts have a $) and returns the new
-- text, or nil to keep it. Text that does not read is kept as it is.
function M.rewrite(text, fn)
  local toks = M.tokenize(text)
  if not toks then return text end
  local out, last = {}, 0
  local i = 1
  while i <= #toks do
    local tok = toks[i]
    local start, sheet = tok.s, nil
    local j = i
    if tok.t == "sheet" then sheet = tok.v j = i + 1 end
    local a = toks[j]
    local ref
    if a and a.t == "ref" then
      local r1, c1, ar1, ac1 = M.parseRef(a.v)
      ref = { sheet = sheet, r1 = r1, c1 = c1, r2 = r1, c2 = c1, ar1 = ar1, ac1 = ac1, ar2 = ar1, ac2 = ac1 }
      local colon, b = toks[j + 1], toks[j + 2]
      if colon and colon.t == ":" and b and b.t == "ref" then
        local r2, c2, ar2, ac2 = M.parseRef(b.v)
        ref.r2, ref.c2, ref.ar2, ref.ac2 = r2, c2, ar2, ac2
        ref.range = true
        j = j + 2
      end
    elseif a and a.t == "col" and toks[j + 1] and toks[j + 1].t == ":" and toks[j + 2] and toks[j + 2].t == "col" then
      local b = toks[j + 2]
      ref = { sheet = sheet, r1 = 1, r2 = M.MAX_ROWS, cols = true, range = true,
        c1 = M.colIndex((a.v:gsub("%$", ""))), c2 = M.colIndex((b.v:gsub("%$", ""))),
        ac1 = a.v:sub(1, 1) == "$", ac2 = b.v:sub(1, 1) == "$" }
      j = j + 2
    end
    if ref then
      local new = fn(ref)
      if new then
        out[#out + 1] = text:sub(last + 1, start - 1)
        out[#out + 1] = new
        last = toks[j].e
      end
      i = j + 1
    else
      i = i + 1
    end
  end
  out[#out + 1] = text:sub(last + 1)
  return table.concat(out)
end

-- refText writes a reference back out.
function M.refText(ref)
  local prefix = ref.sheet and M.sheetPrefix(ref.sheet) or ""
  local function cell(r, c, ar, ac)
    return (ac and "$" or "") .. M.colName(c) .. (ar and "$" or "") .. r
  end
  if ref.cols then
    return prefix .. (ref.ac1 and "$" or "") .. M.colName(ref.c1) .. ":" .. (ref.ac2 and "$" or "") .. M.colName(ref.c2)
  end
  local s = prefix .. cell(ref.r1, ref.c1, ref.ar1, ref.ac1)
  if ref.range then s = s .. ":" .. cell(ref.r2, ref.c2, ref.ar2, ref.ac2) end
  return s
end

local function inBounds(r, c) return r >= 1 and c >= 1 and r <= M.MAX_ROWS and c <= M.MAX_COLS end

-- shift moves the references a formula has, without $, by dr rows and dc
-- columns, as copying it from one cell to another does. One pushed off
-- the sheet becomes #REF!.
function M.shift(text, dr, dc)
  if dr == 0 and dc == 0 then return text end
  return M.rewrite(text, function(ref)
    if not ref.cols then
      if not ref.ar1 then ref.r1 = ref.r1 + dr end
      if not ref.ar2 then ref.r2 = ref.r2 + dr end
    end
    if not ref.ac1 then ref.c1 = ref.c1 + dc end
    if not ref.ac2 then ref.c2 = ref.c2 + dc end
    if not inBounds(ref.r1, ref.c1) or not inBounds(ref.r2, ref.c2) then return "#REF!" end
    return M.refText(ref)
  end)
end

local function sameSheet(a, b) return a and b and a:lower() == b:lower() end

-- adjust keeps a formula on sheet `own` pointing at the same cells after
-- `count` rows (axis "row") or columns ("col") are put in at `at` on sheet
-- `target`, or taken out from there when count is negative. A reference
-- to cells taken out becomes #REF!; a range loses what was taken out.
function M.adjust(text, own, target, axis, at, count)
  return M.rewrite(text, function(ref)
    local sheet = ref.sheet or own
    if not sameSheet(sheet, target) then return nil end
    if axis == "row" and ref.cols then return nil end
    local k1, k2 = axis == "row" and "r1" or "c1", axis == "row" and "r2" or "c2"
    local a, b = ref[k1], ref[k2]
    if count > 0 then
      if a >= at then a = a + count end
      if b >= at then b = b + count end
    else
      local first, last = at, at - count - 1
      local function moved(x)
        if x > last then return x + count end
        return x
      end
      if a >= first and b <= last then return "#REF!" end
      if a >= first and a <= last then a = first else a = moved(a) end
      if b >= first and b <= last then b = first - 1 else b = moved(b) end
    end
    if a == ref[k1] and b == ref[k2] then return nil end
    ref[k1], ref[k2] = a, b
    if not ref.range and (a ~= b) then return "#REF!" end
    return M.refText(ref)
  end)
end

-- renameSheet points references to sheet `old` at `new` instead.
function M.renameSheet(text, old, new)
  return M.rewrite(text, function(ref)
    if not sameSheet(ref.sheet, old) then return nil end
    ref.sheet = new
    return M.refText(ref)
  end)
end

return M
