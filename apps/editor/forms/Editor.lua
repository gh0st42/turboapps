-- The code behind Editor.form.lua: the controls are fields of the form, by
-- the names the layout gives them.
--
-- The layout has two text boxes in the same place, and one shows at a
-- time: txtText wraps long lines, and txtCode does not but numbers them.
-- A TextBox's wrapping is fixed when it is made, so View > Word Wrap
-- moves the text from one to the other.

local gui = require "gui"
local lfs = require "lfs"
local document = require "document"
local find = require "forms.Find"
local frm = gui.load "Editor" --[[@as forms.Editor]]

local DEFAULT_SIZE = frm.txtText.fontSize
local FILTER = "Text files\t*.{txt,md,lua,log,csv,json,ini,cfg,conf,xml,html,css,js}\nAll files\t*"

local doc = {
  path = nil,   -- the file being edited; nil until it is saved
  eol = "\n",   -- the line ending it is written with
  saved = "",   -- the text as it was last opened or saved
  dirty = false,
}
local wrap = true
local zoom = DEFAULT_SIZE

local function activeBox()
  return wrap and frm.txtText or frm.txtCode
end

local function updateTitle()
  frm.caption = (doc.dirty and "*" or "") .. document.basename(doc.path) .. " - Editor"
end

-- The status line follows the cursor. A TextBox says nothing when only the
-- cursor moves, so a timer looks, and works it out only when it has moved.
local statusStale, lastCursor = true, -1

local function updateStatus()
  local b = activeBox()
  local cursor = b.cursor
  if not statusStale and cursor == lastCursor then return end
  statusStale, lastCursor = false, cursor
  local text = b.text
  local line, col = document.position(text, cursor)
  local s = document.stats(text)
  frm.lblStatus.caption = ("  Ln %d, Col %d      %d lines, %d words, %d characters      %s      UTF-8")
    :format(line, col, s.lines, s.words, s.chars, doc.eol == "\r\n" and "Windows (CRLF)" or "Unix (LF)")
end

-- changed is called whenever the text changes, from the boxes and from
-- the Find dialog's Replace All.
local function changed()
  statusStale = true
  if not doc.dirty and activeBox().text ~= doc.saved then
    doc.dirty = true
    updateTitle()
  end
end

frm.txtText.onChange = changed
frm.txtCode.onChange = changed

-- What the Find dialog needs of the editor.
frm.activeBox = activeBox
frm.changed = changed
find.attach(frm)

-- setText replaces the document, as opening or starting a new one does.
local function setText(text)
  local b = activeBox()
  doc.saved, doc.dirty = text, false
  b.text = text
  b.cursor = 0
  statusStale = true
  updateTitle()
  updateStatus()
end

local function dirname(path)
  return path and path:match("^(.*)[/\\][^/\\]*$")
end

---------------------------------------------------------------- files

local function openPath(path)
  if lfs.attributes(path, "mode") ~= "file" then
    gui.msgbox(("Cannot open %s: it is not a file."):format(path), "ok", "Editor")
    return false
  end
  local text, eol = document.read(path)
  if not text then
    gui.msgbox(("Cannot open %s.\n\n%s"):format(path, tostring(eol)), "ok", "Editor")
    return false
  end
  if text:find("\0", 1, true) then
    gui.msgbox(("%s looks like a binary file, which this editor cannot show."):format(document.basename(path)), "ok", "Editor")
    return false
  end
  doc.path, doc.eol = path, eol
  setText(text)
  return true
end

local function saveTo(path)
  local text = activeBox().text
  local ok, err = document.write(path, text, doc.eol)
  if not ok then
    gui.msgbox(("Cannot save %s.\n\n%s"):format(path, tostring(err)), "ok", "Editor")
    return false
  end
  doc.path, doc.saved, doc.dirty = path, text, false
  updateTitle()
  return true
end

local function saveAs()
  local path = gui.savefile {
    title = "Save As", filter = FILTER,
    dir = dirname(doc.path), file = doc.path and document.basename(doc.path) or "Untitled.txt",
  }
  if not path then return false end
  return saveTo(path)
end

local function save()
  if doc.path then return saveTo(doc.path) end
  return saveAs()
end

-- confirmDiscard asks to save unsaved changes before they would be lost;
-- false means the user cancelled.
local function confirmDiscard()
  if not doc.dirty then return true end
  local answer = gui.msgbox(("Do you want to save the changes to %s?"):format(document.basename(doc.path)),
    "yesnocancel", "Editor")
  if answer == "yes" then return save() end
  return answer == "no"
end

local function newDocument()
  if not confirmDiscard() then return end
  doc.path, doc.eol = nil, "\n"
  setText("")
end

local function openDialog()
  if not confirmDiscard() then return end
  local path = gui.openfile { title = "Open", filter = FILTER, dir = dirname(doc.path) }
  if path then openPath(path) end
end

local function revert()
  if not doc.path then return end
  if doc.dirty and gui.msgbox("Throw away your changes and read the file again?", "okcancel", "Revert") ~= "ok" then
    return
  end
  openPath(doc.path)
end

---------------------------------------------------------------- editing

local function cut()
  local b = activeBox()
  local s = b.selectedText
  if s ~= "" then
    gui.clipboard(s)
    b:insert("")
  end
end

local function copy()
  local s = activeBox().selectedText
  if s ~= "" then gui.clipboard(s) end
end

local function paste()
  local s = gui.clipboard()
  if s and s ~= "" then activeBox():insert((s:gsub("\r\n?", "\n"))) end
end

local function goToLine()
  local b = activeBox()
  local answer = gui.inputbox("Line number:", "Go To Line", tostring(b.line))
  local n = tonumber(answer)
  if not n then return end
  b.cursor = document.lineOffset(b.text, math.floor(n))
  b:focus()
end

local function selectAll()
  local b = activeBox()
  b:select(1, #b.text)
end

---------------------------------------------------------------- view

local function setWrap(on)
  if on == wrap then return end
  local from = activeBox()
  local text, cursor = from.text, from.cursor
  wrap = on
  local to = activeBox()
  to.text = text
  to.cursor = cursor
  to.visible, from.visible = true, false
  from.text = ""
  to:focus()
  statusStale = true
end

local function setZoom(size)
  zoom = math.max(8, math.min(48, size))
  frm.txtText.fontSize = zoom
  frm.txtCode.fontSize = zoom
end

---------------------------------------------------------------- the menu

local actions = {
  mnuNew = newDocument,
  mnuOpen = openDialog,
  mnuRevert = revert,
  mnuSave = save,
  mnuSaveAs = saveAs,
  mnuExit = function() frm:close() end,
  mnuCut = cut,
  mnuCopy = copy,
  mnuPaste = paste,
  mnuFind = function() find.open(false) end,
  mnuFindNext = function() find.findNext(false) end,
  mnuFindPrev = function() find.findNext(true) end,
  mnuReplace = function() find.open(true) end,
  mnuGoTo = goToLine,
  mnuSelectAll = selectAll,
  mnuTimeDate = function() activeBox():insert(os.date("%Y-%m-%d %H:%M")) end,
  mnuZoomIn = function() setZoom(zoom + 2) end,
  mnuZoomOut = function() setZoom(zoom - 2) end,
  mnuZoomReset = function() setZoom(DEFAULT_SIZE) end,
  mnuAbout = function()
    gui.msgbox("Editor\n\nA plain text editor, made with tlua and its form designer.\n\n"
      .. "It keeps a file's line endings (Unix or Windows) as it found them.", "ok", "About Editor")
  end,
}

function frm.Menu1:onClick(name, caption, checked)
  if name == "mnuWrap" then
    setWrap(checked)
  elseif actions[name] then
    actions[name]()
  end
end

---------------------------------------------------------------- the form

-- Escape does not close the editor; the close box and File > Exit do.
function frm:onKey(key)
  return key == "Escape"
end

function frm:onClose()
  if not confirmDiscard() then return false end
  if find.visible then find:close() end
end

-- A file dropped on the editor is opened; dropped text goes in at the
-- cursor.
local function dropped(self, text, lines)
  local path = lines and #lines == 1 and lines[1]
  if path and lfs.attributes(path, "mode") == "file" then
    if confirmDiscard() then openPath(path) end
    return
  end
  activeBox():insert(text)
end

frm.txtText.onDrop = dropped
frm.txtCode.onDrop = dropped
frm.onDrop = dropped

-- The status line is looked at four times a second.
gui.every(0.25, function()
  if frm.visible then updateStatus() end
end)

-- A file named on the command line is opened, or started when it is not
-- there yet: tlua editor.ztl notes.txt
local start = arg and arg[1]
if start and start ~= "" then
  if lfs.attributes(start, "mode") == "file" then
    openPath(start)
  else
    doc.path = start
    updateTitle()
  end
else
  updateTitle()
end
updateStatus()

return frm
