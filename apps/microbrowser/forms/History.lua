-- The code behind History.form.lua: the controls are fields of the form, by
-- the names the layout gives them. It lists the pages seen, the newest
-- first, narrowed by what is typed in the search box, to open one (here or
-- in a tab of its own), forget one, or clear them all.

local gui = require "gui"
local store = require "store"
local frm = gui.load "History" --[[@as forms.History]]

local settings
local shown = {}      -- the entries listed
local picked, inNewTab

-- when is a time as a person reads it.
local function when(t)
  return os.date("%Y-%m-%d %H:%M", t)
end

local function refill(keep)
  shown = store.recent(settings, frm.txtFilter.text)
  local items = {}
  for i, h in ipairs(shown) do
    items[i] = ("%s    %s    %s"):format(when(h.time), h.title, h.url)
  end
  frm.lstHistory.items = items
  if #items > 0 then frm.lstHistory.selected = math.max(1, math.min(keep or 1, #items)) end
  local total = #settings.history
  frm.lblCount.caption = total == 0 and "Nothing visited yet"
    or (#shown == total and ("%d pages"):format(total) or ("%d of %d pages"):format(#shown, total))
  for _, c in ipairs { frm.cmdOpen, frm.cmdNewTab, frm.cmdForget } do c.enabled = #shown > 0 end
  frm.cmdClear.enabled = total > 0
end

local function selected()
  return shown[frm.lstHistory.selected or 0]
end

-- browse shows the history of settings and waits: it returns the address of
-- a page to open, and true when that is to be in a new tab, or nil. The
-- history is changed in settings.
function frm.browse(s)
  frm.prepare(s)
  frm:showModal()
  return picked, inNewTab
end

-- prepare fills the window, for browse, and for the tests, which cannot
-- wait for a window to be closed.
function frm.prepare(s)
  settings = s
  picked, inNewTab = nil, false
  frm.txtFilter.text = ""
  refill(1)
  frm.txtFilter:focus()
end

-- chosen is what the window would give back.
function frm.chosen()
  return picked, inNewTab
end

function frm.txtFilter:onChange()
  refill(1)
end

-- The arrows in the search box move through the list.
function frm.txtFilter:onKey(key)
  if key == "Down" or key == "Up" then
    local i = (frm.lstHistory.selected or 0) + (key == "Down" and 1 or -1)
    if i >= 1 and i <= #shown then frm.lstHistory.selected = i end
    return true
  end
  if key == "Enter" then
    frm.cmdOpen:fire("onClick")
    return true
  end
  return false
end

function frm.lstHistory:onDoubleClick()
  frm.cmdOpen:fire("onClick")
end

function frm.cmdOpen:onClick()
  local h = selected()
  if not h then return end
  picked, inNewTab = h.url, false
  frm:close()
end

function frm.cmdNewTab:onClick()
  local h = selected()
  if not h then return end
  picked, inNewTab = h.url, true
  frm:close()
end

function frm.cmdForget:onClick()
  local h = selected()
  if not h then return end
  local i = frm.lstHistory.selected
  store.forget(settings, h.url)
  refill(i)
end

function frm.cmdClear:onClick()
  if gui.msgbox("Forget every page visited?", "yesno", "Clear History") ~= "yes" then return end
  store.clearHistory(settings)
  refill(1)
end

function frm.cmdClose:onClick()
  frm:close()
end

return frm
