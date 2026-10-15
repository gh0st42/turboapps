-- The code behind Bookmarks.form.lua: the controls are fields of the form,
-- by the names the layout gives them. It puts the bookmarks in order,
-- renames them, changes their addresses and deletes them, and opens one.

local gui = require "gui"
local store = require "store"
local frm = gui.load "Bookmarks" --[[@as forms.Bookmarks]]

local settings
local picked
local quiet = false -- filling the boxes, not typing in them

local function refill(sel)
  local names = {}
  for i, b in ipairs(settings.bookmarks) do names[i] = b.title end
  frm.lstMarks.items = names
  if #names > 0 then
    sel = math.max(1, math.min(sel or 1, #names))
    frm.lstMarks.selected = sel
  end
  frm.lstMarks:fire("onChange")
end

local function selected()
  local i = frm.lstMarks.selected
  if i and settings.bookmarks[i] then return i, settings.bookmarks[i] end
end

-- manage shows the bookmarks of settings and waits: it returns the address
-- of one to open, or nil. The bookmarks are changed in settings.
function frm.manage(s)
  settings = s
  picked = nil
  refill(1)
  frm.lstMarks:focus()
  frm:showModal()
  return picked
end

function frm.lstMarks:onChange()
  local _, b = selected()
  quiet = true
  frm.txtTitle.text = b and b.title or ""
  frm.txtUrl.text = b and b.url or ""
  quiet = false
  for _, c in ipairs { frm.txtTitle, frm.txtUrl, frm.cmdOpen, frm.cmdUp, frm.cmdDown, frm.cmdDelete } do
    c.enabled = b ~= nil
  end
end

function frm.lstMarks:onDoubleClick()
  frm.cmdOpen:fire("onClick")
end

function frm.txtTitle:onChange()
  local i, b = selected()
  if quiet or not b then return end
  b.title = frm.txtTitle.text
  local names = frm.lstMarks.items
  names[i] = b.title
  frm.lstMarks.items = names
  frm.lstMarks.selected = i
end

function frm.txtUrl:onChange()
  local _, b = selected()
  if quiet or not b then return end
  b.url = frm.txtUrl.text
end

function frm.cmdOpen:onClick()
  local _, b = selected()
  if not b then return end
  picked = b.url
  frm:close()
end

function frm.cmdUp:onClick()
  local i = selected()
  if i then refill(store.move(settings, i, -1)) end
end

function frm.cmdDown:onClick()
  local i = selected()
  if i then refill(store.move(settings, i, 1)) end
end

function frm.cmdDelete:onClick()
  local i = selected()
  if not i then return end
  store.unbookmark(settings, i)
  refill(i)
end

function frm.cmdClose:onClick()
  frm:close()
end

return frm
