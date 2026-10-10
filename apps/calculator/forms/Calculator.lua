-- The code behind Calculator.form.lua: the controls are fields of the form, by
-- the names the layout gives them. The arithmetic is in engine.lua; this
-- only wires the buttons, keys and menu to it and shows what it says.

local gui = require "gui"
local engine = require "engine"
local frm = gui.load "Calculator" --[[@as forms.Calculator]]

local calc = engine.new()

-- The form's width with and without the history beside the keypad.
local WIDE, NARROW = frm.width, frm.lstHistory.left

local function refresh()
  local text = calc:display()
  -- Long numbers and messages get a smaller font, so they fit.
  frm.lblDisplay.fontSize = #text > 18 and 15 or #text > 13 and 20 or 26
  frm.lblDisplay.caption = text
  frm.lblExpr.caption = calc:expression()
  frm.lblMemory.caption = calc.memory and "M" or ""
  frm.cmdMC.enabled = calc.memory ~= nil
  frm.cmdMR.enabled = calc.memory ~= nil
end

local function refreshHistory()
  local items = {}
  for i = #calc.history, 1, -1 do -- newest first
    local h = calc.history[i]
    items[#items + 1] = h.expr .. " " .. engine.group(h.result)
  end
  frm.lstHistory.items = items
  frm.cmdClearHistory.enabled = #items > 0
end

-- press makes a handler for a button that calls the engine and redraws.
local function press(fn)
  return function()
    local n = #calc.history
    fn()
    refresh()
    if #calc.history ~= n then refreshHistory() end
  end
end

for d = 0, 9 do
  frm["cmd" .. d].onClick = press(function() calc:digit(tostring(d)) end)
end

frm.cmdPoint.onClick = press(function() calc:point() end)
frm.cmdAdd.onClick = press(function() calc:operator("+") end)
frm.cmdSub.onClick = press(function() calc:operator("-") end)
frm.cmdMul.onClick = press(function() calc:operator("*") end)
frm.cmdDiv.onClick = press(function() calc:operator("/") end)
frm.cmdEquals.onClick = press(function() calc:equals() end)
frm.cmdPercent.onClick = press(function() calc:percent() end)
frm.cmdNegate.onClick = press(function() calc:unary("negate") end)
frm.cmdSquare.onClick = press(function() calc:unary("square") end)
frm.cmdSqrt.onClick = press(function() calc:unary("sqrt") end)
frm.cmdInverse.onClick = press(function() calc:unary("inverse") end)
frm.cmdCE.onClick = press(function() calc:clearEntry() end)
frm.cmdClear.onClick = press(function() calc:clear() end)
frm.cmdBack.onClick = press(function() calc:backspace() end)
frm.cmdMC.onClick = press(function() calc:memoryClear() end)
frm.cmdMR.onClick = press(function() calc:memoryRecall() end)
frm.cmdMPlus.onClick = press(function() calc:memoryAdd(1) end)
frm.cmdMMinus.onClick = press(function() calc:memoryAdd(-1) end)

function frm.cmdClearHistory:onClick()
  calc.history = {}
  refreshHistory()
end

-- Double-clicking a line of the history puts its result in the display.
function frm.lstHistory:onDoubleClick()
  local h = calc.history[#calc.history - self.selected + 1]
  if h then
    calc:enter(h.result)
    refresh()
  end
end

-- Keys the buttons do not use come here: digits, operators, Enter,
-- Backspace, Escape and the rest, as engine.key names them.
function frm:onKey(key, text)
  if key:find("Cmd%+") or key:find("Ctrl%+") or key:find("Alt%+") then return false end
  local n = #calc.history
  if calc:key(key, text) then
    refresh()
    if #calc.history ~= n then refreshHistory() end
    return true -- Escape clears, it does not close
  end
  return false
end

local function showHistory(on)
  frm.lblHistory.visible = on
  frm.lstHistory.visible = on
  frm.cmdClearHistory.visible = on
  frm.width = on and WIDE or NARROW
end

local help = [[Keyboard:

  0-9 and .       digits
  + - * /         operators
  Enter or =      equals
  %               percent
  Backspace       delete the last digit
  Delete          clear the entry (CE)
  Escape          clear everything (C)
  F9              change sign
  R  Q  @         1/x, x², √x
  Cmd+C, Cmd+V    copy and paste the number]]

function frm.Menu1:onClick(name, caption, checked)
  if name == "mnuCopy" then
    gui.clipboard((calc.err and "" or calc.entry))
  elseif name == "mnuPaste" then
    if not calc:enter(gui.clipboard() or "") then
      gui.msgbox("The clipboard does not hold a number.", "ok", "Paste")
    end
    refresh()
  elseif name == "mnuHistory" then
    showHistory(checked)
  elseif name == "mnuKeys" then
    gui.msgbox(help, "ok", "Keyboard Shortcuts")
  elseif name == "mnuAbout" then
    gui.msgbox("Calculator\n\nA standard calculator, made with tlua and its form designer.", "ok", "About Calculator")
  end
end

refresh()
refreshHistory()

return frm
