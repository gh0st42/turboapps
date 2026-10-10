-- tlua -p apps/calculator -p tests tests/calculator_test.lua

local t = require "testing"
local engine = require "engine"
local test, eq = t.test, t.eq

-- run presses keys given as a string, one key per character, with "=" for
-- equals; names in brackets press the rest: "[sqrt]", "[neg]", "[ce]".
local function run(keys, c)
  c = c or engine.new()
  local i = 1
  while i <= #keys do
    local ch = keys:sub(i, i)
    if ch == "[" then
      local j = keys:find("]", i, true)
      local name = keys:sub(i + 1, j - 1)
      if name == "sqrt" or name == "square" or name == "inverse" then c:unary(name)
      elseif name == "neg" then c:unary("negate")
      elseif name == "ce" then c:clearEntry()
      elseif name == "c" then c:clear()
      elseif name == "bs" then c:backspace()
      elseif name == "m+" then c:memoryAdd(1)
      elseif name == "m-" then c:memoryAdd(-1)
      elseif name == "mr" then c:memoryRecall()
      elseif name == "mc" then c:memoryClear()
      else error("no key " .. name) end
      i = j + 1
    else
      assert(c:key(ch, ch), "key " .. ch)
      i = i + 1
    end
  end
  return c
end

local function shows(keys, want)
  test(keys .. " -> " .. want, function()
    eq(run(keys):display(), want, keys)
  end)
end

-- typing
shows("", "0")
shows("123", "123")
shows("0007", "7")
shows("1.5", "1.5")
shows(".5", "0.5")
shows("1..5", "1.5")
shows("1234567", "1,234,567")
shows("12345678901234567890", "1,234,567,890,123,456")
shows("123[bs]", "12")
shows("1[bs][bs]", "0")

-- arithmetic, left to right as a pocket calculator does it
shows("2+3=", "5")
shows("2+3*4=", "20")
shows("10-4/2=", "3")
shows("7/2=", "3.5")
shows("0.1+0.2=", "0.3")
shows("2+*3=", "6")          -- the second operator replaces the first
shows("5+=", "10")           -- = with no second operand uses the first
shows("2+3==", "8")          -- = again repeats + 3
shows("2*3===", "54")
shows("2+3=4", "4")          -- a digit after = starts again
shows("2+3=*2=", "10")       -- an operator after = goes on from the result
shows("1/3*3=", "1")
shows("99999999*99999999=", "9.9999998e15") -- past 15 digits: an exponent
shows("1/0=", engine.DIV_ZERO)
shows("1/0=5", "5")          -- a digit after an error starts again

-- functions
shows("9[sqrt]", "3")
shows("4[square]", "16")
shows("4[inverse]", "0.25")
shows("0[inverse]", engine.DIV_ZERO)
shows("9[neg][sqrt]", engine.INVALID)
shows("5[neg]", "-5")
shows("5[neg][neg]", "5")
shows("2+9[sqrt]=", "5")
shows("200+10%", "20")
shows("200+10%=", "220")
shows("50*10%=", "5")
shows("1000000[square][square][square]", "1e48")
shows("12+5[ce]3=", "15")
shows("12+5[c]3", "3")

-- memory
shows("5[m+]3[m+][mr]", "8")
shows("5[m+]3[m-][mr]", "2")
shows("5[m+][mc][mr]", "5")  -- MR with nothing in memory changes nothing

test("expression line", function()
  local c = run("12+")
  eq(c:expression(), "12 +")
  run("3*", c)
  eq(c:expression(), "15 ×")
  run("2=", c)
  eq(c:expression(), "15 × 2 =")
end)

test("history", function()
  local c = run("2+3=4*5=")
  eq(#c.history, 2)
  eq(c.history[1].expr, "2 + 3 =")
  eq(c.history[1].result, "5")
  eq(c.history[2].result, "20")
end)

test("enter (paste)", function()
  local c = engine.new()
  t.ok(c:enter(" 1,234.5 "), "a number is taken")
  eq(c:display(), "1,234.5")
  t.ok(not c:enter("abc"), "text is refused")
  eq(c:display(), "1,234.5")
end)

test("keyboard names", function()
  local c = engine.new()
  c:key("1", "1"); c:key("Shift+=", "+"); c:key("2", "2"); c:key("Enter", "\r")
  eq(c:display(), "3")
  c:key("Escape", "\27")
  eq(c:display(), "0")
  t.ok(not c:key("x", "x"), "x means nothing")
end)

test("format", function()
  eq(engine.format(1e21), "1e21")
  eq(engine.format(1.5e-7), "1.5e-7")
  eq(engine.format(-0), "0")
  eq(engine.format(1 / 3), "0.333333333333333")
  eq(engine.group("-1234.5678"), "-1,234.5678")
end)

test("exponents in the entry are read back", function()
  local c = engine.new()
  t.ok(c:enter("1e24"), "1e24 is a number") -- tlua before 0.4.1 read it as nil
  c:unary("square")
  eq(c:display(), "1e48")
end)

---------------------------------------------------------------- the form

-- The form is built without being shown, and its buttons pressed by
-- firing their onClick: the same code a user's clicks run.
local frm = require "forms.Calculator"

local function click(...)
  for _, name in ipairs { ... } do frm[name]:fire("onClick") end
end

test("form: buttons", function()
  click("cmdClear", "cmd1", "cmd2", "cmdAdd", "cmd3", "cmdEquals")
  eq(frm.lblDisplay.caption, "15")
  eq(frm.lblExpr.caption, "12 + 3 =")
end)

test("form: history list", function()
  click("cmdClearHistory", "cmd2", "cmdMul", "cmd4", "cmdEquals")
  eq(frm.lstHistory.items[1], "2 × 4 = 8")
  eq(frm.cmdClearHistory.enabled, true)
  click("cmdClearHistory")
  eq(#frm.lstHistory.items, 0)
end)

test("form: memory indicator", function()
  click("cmdClear", "cmd7", "cmdMPlus")
  eq(frm.lblMemory.caption, "M")
  eq(frm.cmdMR.enabled, true)
  click("cmdMC")
  eq(frm.lblMemory.caption, "")
  eq(frm.cmdMR.enabled, false)
end)

test("form: keys", function()
  click("cmdClear")
  eq(frm:fire("onKey", "9", "9"), true)
  frm:fire("onKey", "Shift+8", "*")
  frm:fire("onKey", "9", "9")
  frm:fire("onKey", "Enter", "\r")
  eq(frm.lblDisplay.caption, "81")
  eq(frm:fire("onKey", "Cmd+c", "c"), false)
end)

t.done("calculator")
