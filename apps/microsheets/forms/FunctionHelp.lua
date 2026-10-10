-- The code behind FunctionHelp.form.lua: the controls are fields of the
-- form, by the names the layout gives them. It shows fnhelp.lua's pages:
-- about formulas, and every function, by category, with a search.

local gui = require "gui"
local fnhelp = require "fnhelp"
local frm = gui.load "FunctionHelp" --[[@as forms.FunctionHelp]]

local ABOUT = "About formulas"
local picked -- the function Insert was pressed for

-- items builds the tree: the topics, then each category's functions that
-- match the search, opened when searching.
local function items(search)
  search = (search or ""):lower()
  local list = {}
  if search == "" then
    local topics = {}
    for _, t in ipairs(fnhelp.topics) do topics[#topics + 1] = t.name end
    list[1] = { ABOUT, topics, open = true }
  end
  for _, cat in ipairs(fnhelp.categories) do
    local names = {}
    for _, f in ipairs(fnhelp.functions) do
      local doc = fnhelp.doc(f.name)
      local text = (f.name .. " " .. (doc.does or "")):lower()
      if f.cat == cat and (search == "" or text:find(search, 1, true)) then names[#names + 1] = f.name end
    end
    table.sort(names)
    if #names > 0 then list[#list + 1] = { cat, names, open = search ~= "" } end
  end
  return list
end

local function topic(name)
  for _, t in ipairs(fnhelp.topics) do
    if t.name == name then return t.text end
  end
end

-- showPage shows what a tree path names: a topic or a function.
local function showPage(path)
  local cat, name = path:match("^(.-)/(.+)$")
  local text
  if cat == ABOUT then text = topic(name)
  elseif name then text = fnhelp.page(name) end
  if not text and path ~= "" and not name then
    text = path == ABOUT and topic("Formulas") or nil
  end
  frm.txtPage.text = text or ""
  frm.cmdInsert.enabled = name ~= nil and cat ~= ABOUT
end

local function current()
  local cat, name = frm.treTopics.path:match("^(.-)/(.+)$")
  if name and cat ~= ABOUT then return name end
end

-- open shows the window at a function's help (or at the first topic), and
-- waits until it is closed. It returns the function Insert was pressed
-- for, if it was.
function frm.open(name)
  picked = nil
  frm.txtSearch.text = ""
  frm.treTopics.items = items()
  local doc = name and fnhelp.doc(name)
  if doc then
    local list = frm.treTopics.items
    for _, branch in ipairs(list) do
      if branch[1] == doc.cat then branch.open = true end
    end
    frm.treTopics.items = list
    frm.treTopics.path = doc.cat .. "/" .. doc.name
    showPage(doc.cat .. "/" .. doc.name)
  else
    frm.treTopics.path = ABOUT .. "/Formulas"
    showPage(ABOUT .. "/Formulas")
  end
  frm:showModal()
  return picked
end

function frm.treTopics:onChange()
  showPage(self.path)
end

function frm.treTopics:onDoubleClick()
  if current() then frm.cmdInsert:fire("onClick") end
end

function frm.txtSearch:onChange()
  local list = items(self.text)
  frm.treTopics.items = list
  -- Show the first match straight away.
  local first = list[1]
  if first and first[2][1] then
    local path = first[1] .. "/" .. first[2][1]
    frm.treTopics.path = path
    showPage(path)
  else
    frm.txtPage.text = "No function has “" .. self.text .. "” in its name or description."
    frm.cmdInsert.enabled = false
  end
end

function frm.txtSearch:onKey(key)
  if key == "Down" then frm.treTopics:focus() return true end
  if key == "Enter" and current() then frm.cmdInsert:fire("onClick") return true end
end

function frm.cmdInsert:onClick()
  picked = current()
  if picked then frm:close() end
end

function frm.cmdClose:onClick()
  frm:close()
end

-- Exposed for the tests.
frm.treeItems = items
frm.showTopic = showPage

return frm
