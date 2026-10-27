-- The code behind Rules.form.lua: the controls are fields of the form, by
-- the names the layout gives them. It edits a sheet's rules of conditional
-- formatting (condfmt.lua has what they are): a list of them, and what the
-- one picked asks and how it looks. ask() shows it on a copy of the rules and
-- gives the new ones back, or nil when cancelled.

local gui = require "gui"
local condfmt = require "condfmt"
local frm = gui.load "Rules" --[[@as forms.Rules]]

local rules = {}       -- the working copy
local where            -- where a new rule is about: r1, c1, r2, c2
local answer
local quiet = false    -- loading the controls, not typing in them

local function rule() return rules[frm.lstRules.selected or 0] end

local function copy(list)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  return out
end

local function label(r)
  return ("%s   %s"):format(condfmt.rangeName(r), condfmt.describe(r))
end

local function refill(sel)
  quiet = true
  local items = {}
  for i, r in ipairs(rules) do items[i] = label(r) end
  frm.lstRules.items = items
  if #items > 0 then frm.lstRules.selected = math.max(1, math.min(sel or 1, #items)) end
  quiet = false
  frm.lstRules:fire("onChange")
end

-- relabel shows the picked rule's new words in the list.
local function relabel()
  local i = frm.lstRules.selected or 0
  if not rules[i] then return end
  quiet = true
  local items = frm.lstRules.items
  items[i] = label(rules[i])
  frm.lstRules.items = items
  frm.lstRules.selected = i
  quiet = false
end

local HINTS = {
  formula = "Write the formula for the first cell of the range, such as =B2>A2: the other cells use it moved the same way.",
  scale = "Each number gets a colour between the colours of the smallest and the biggest in the range.",
  bar = "Each number gets a bar as long as it is big, the biggest filling its cell.",
  top = "How many: the biggest numbers of the range, ties counting too.",
  bottom = "How many: the smallest numbers of the range, ties counting too.",
}

local function sample(r)
  local st = r.style or {}
  frm.lblSample.color = st.fill or "#ffffff"
  frm.lblSample.textColor = st.color or "#000000"
  frm.cmdFill.color = st.fill or "#ffffff"
  frm.cmdColor.color = st.color or "#000000"
end

-- show loads the controls with the rule picked, showing the parts that are
-- for its kind.
local function load()
  local r = rule()
  quiet = true
  local on = r ~= nil
  for _, c in ipairs { frm.txtRange, frm.cboKind, frm.cmdDelete, frm.txtA, frm.txtB, frm.cboStyle, frm.cmdFill, frm.cmdColor,
    frm.chkFill, frm.chkColor, frm.chkBold, frm.chkItalic, frm.cboScale, frm.cmdBar } do
    c.enabled = on
  end
  frm.cmdUp.enabled = on and (frm.lstRules.selected or 1) > 1
  frm.cmdDown.enabled = on and (frm.lstRules.selected or 1) < #rules
  if not r then
    frm.txtRange.text, frm.txtA.text, frm.txtB.text, frm.lblHint.caption = "", "", "", "Add a rule to colour cells by what they hold."
    quiet = false
    return
  end
  local k = condfmt.byName[r.kind]
  frm.txtRange.text = condfmt.rangeName(r)
  frm.txtRange.textColor = "#000000"
  frm.cboKind.selected = k.index
  local one = k.operands == 1 or k.operands == "n"
  local two = k.operands == 2
  frm.lblA.visible, frm.txtA.visible = one or two, one or two
  frm.lblB.visible, frm.txtB.visible = two, two
  frm.lblA.caption = k.operands == "n" and "How many:" or (r.kind == "formula" and "Formula:" or "Value:")
  frm.txtA.text = k.operands == "n" and tostring(r.n or 10) or tostring(r.a or "")
  frm.txtB.text = tostring(r.b or "")
  local isScale, isBar = r.kind == "scale", r.kind == "bar"
  local styled = not isScale and not isBar
  for _, c in ipairs { frm.lblLook, frm.cboStyle, frm.chkFill, frm.cmdFill, frm.chkColor, frm.cmdColor, frm.chkBold, frm.chkItalic, frm.lblSample } do
    c.visible = styled
  end
  for _, c in ipairs { frm.lblScale, frm.cboScale, frm.lblS1, frm.lblS2, frm.lblS3 } do c.visible = isScale end
  frm.lblBar.visible, frm.cmdBar.visible = isBar, isBar
  if styled then
    local st = r.style or {}
    frm.chkFill.checked, frm.chkColor.checked = st.fill ~= nil, st.color ~= nil
    frm.chkBold.checked, frm.chkItalic.checked = st.bold == true, st.italic == true
    -- The look that is the same as a ready-made one is shown by its name.
    local pick = #condfmt.STYLES + 1
    for i, preset in ipairs(condfmt.STYLES) do
      local p = preset[2]
      if p.fill == st.fill and p.color == st.color and (p.bold or false) == (st.bold or false) and not st.italic then pick = i break end
    end
    frm.cboStyle.selected = pick
    sample(r)
  elseif isScale then
    local pick = 0
    for i, preset in ipairs(condfmt.SCALES) do
      local same = #preset[2] == #r.scale
      for j, c in ipairs(preset[2]) do if r.scale[j] ~= c then same = false end end
      if same then pick = i break end
    end
    frm.cboScale.selected = pick
    frm.lblS1.color, frm.lblS2.color = r.scale[1], r.scale[2]
    frm.lblS3.color = r.scale[3] or r.scale[2]
    frm.lblS3.visible = #r.scale == 3
  else
    frm.cmdBar.color = r.bar
  end
  frm.lblHint.caption = HINTS[r.kind] or "Value: a number or text, or a formula such as =$F$1 to compare with a cell."
  quiet = false
end

-- prepare fills the window with a copy of rules; where is the cells a new
-- rule is about. ask does this and shows the window; the tests cannot wait
-- for one to be closed.
function frm.prepare(list, range)
  rules = condfmt.copyAll(list)
  where = range or { 1, 1, 1, 1 }
  answer = nil
  local kinds, styles, scales = {}, {}, {}
  for i, k in ipairs(condfmt.KINDS) do kinds[i] = k[2] end
  for i, st in ipairs(condfmt.STYLES) do styles[i] = st[1] end
  styles[#styles + 1] = "Custom"
  for i, sc in ipairs(condfmt.SCALES) do scales[i] = sc[1] end
  frm.cboKind.items, frm.cboStyle.items, frm.cboScale.items = kinds, styles, scales
  refill(1)
end

function frm.ask(list, range)
  frm.prepare(list, range)
  frm:showModal()
  return answer
end

-- result is what ask would give back now.
function frm.result() return answer end

function frm.lstRules:onChange()
  if quiet then return end
  load()
end

function frm.cmdAdd:onClick()
  local r = condfmt.new("greater", where[1], where[2], where[3], where[4])
  r.a = "0"
  rules[#rules + 1] = r
  refill(#rules)
  frm.txtA:focus()
end

function frm.cmdDelete:onClick()
  local i = frm.lstRules.selected or 0
  if not rules[i] then return end
  table.remove(rules, i)
  refill(i)
end

function frm.cmdUp:onClick()
  local i = frm.lstRules.selected or 0
  if i > 1 then
    rules[i], rules[i - 1] = rules[i - 1], rules[i]
    refill(i - 1)
  end
end

function frm.cmdDown:onClick()
  local i = frm.lstRules.selected or 0
  if rules[i + 1] then
    rules[i], rules[i + 1] = rules[i + 1], rules[i]
    refill(i + 1)
  end
end

function frm.txtRange:onChange()
  local r = rule()
  if quiet or not r then return end
  local r1, c1, r2, c2 = condfmt.parseRange(self.text)
  if not r1 then
    self.textColor = "#c00000"
    return
  end
  self.textColor = "#000000"
  r.r1, r.c1, r.r2, r.c2 = r1, c1, r2, c2
  relabel()
end

function frm.cboKind:onChange()
  local r = rule()
  if quiet or not r then return end
  local k = condfmt.KINDS[self.selected or 0]
  if not k or k[1] == r.kind then return end
  r.kind = k[1]
  if r.kind == "scale" and not r.scale then r.scale = copy(condfmt.SCALES[1][2]) end
  if r.kind == "bar" and not r.bar then r.bar = "#638ec6" end
  if r.kind ~= "scale" and r.kind ~= "bar" and not r.style then
    r.style = { fill = condfmt.STYLES[1][2].fill, color = condfmt.STYLES[1][2].color }
  end
  relabel()
  load()
end

function frm.txtA:onChange()
  local r = rule()
  if quiet or not r then return end
  if condfmt.byName[r.kind].operands == "n" then
    r.n = math.max(1, math.floor(tonumber(self.text) or r.n or 10))
  else
    r.a = self.text
  end
  relabel()
end

function frm.txtB:onChange()
  local r = rule()
  if quiet or not r then return end
  r.b = self.text
  relabel()
end

-- The ready-made looks fill in the colours and the bold.
function frm.cboStyle:onChange()
  local r = rule()
  local preset = condfmt.STYLES[self.selected or 0]
  if quiet or not r or not preset then return end
  r.style = {}
  for k, v in pairs(preset[2]) do r.style[k] = v end
  load()
end

function frm.cboScale:onChange()
  local r = rule()
  local preset = condfmt.SCALES[self.selected or 0]
  if quiet or not r or not preset then return end
  r.scale = copy(preset[2])
  load()
end

-- changeStyle changes one part of a rule's look, and shows it.
local function changeStyle(field, value)
  local r = rule()
  if quiet or not r then return end
  r.style = r.style or {}
  r.style[field] = value
  load()
end

local function pickColour(field, title)
  local r = rule()
  if not r then return end
  local c = gui.choosecolor { title = title, color = (r.style or {})[field] or "#ffffff" }
  if c then changeStyle(field, c) end
end

function frm.chkFill:onChange() changeStyle("fill", self.checked and ((rule().style or {}).fill or "#ffeb9c") or nil) end
function frm.chkColor:onChange() changeStyle("color", self.checked and ((rule().style or {}).color or "#9c0006") or nil) end
function frm.chkBold:onChange() changeStyle("bold", self.checked or nil) end
function frm.chkItalic:onChange() changeStyle("italic", self.checked or nil) end
function frm.cmdFill:onClick() pickColour("fill", "Fill Colour") end
function frm.cmdColor:onClick() pickColour("color", "Text Colour") end

function frm.cmdBar:onClick()
  local r = rule()
  if not r then return end
  local c = gui.choosecolor { title = "Bar Colour", color = r.bar }
  if c then
    r.bar = c
    load()
  end
end

function frm.cmdOK:onClick()
  answer = rules
  frm:close()
end

function frm.cmdCancel:onClick()
  frm:close()
end

return frm
