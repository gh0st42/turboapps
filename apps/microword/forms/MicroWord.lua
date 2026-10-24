-- The code behind MicroWord.form.lua: the controls are fields of the form,
-- by the names the layout gives them.
--
-- edDoc is tlua's MarkdownEdit, which draws the document and takes the
-- keyboard and the mouse; edDoc.ed is its markdown.editor, and
-- edDoc.pictures the document's pictures. This file is the rest: the
-- menus, the toolbar, files, pictures and the clipboard.

local gui = require "gui"
local lfs = require "lfs"
local zmd = require "zmd"
local source = require "forms.Source"
local frm = gui.load "MicroWord" --[[@as forms.MicroWord]]

local edit = frm.edDoc
local path -- the .zmd the document was opened from or saved to

local DOC_FILTER = "Documents\t*.{zmd,md}\nmicroword\t*.zmd\nMarkdown\t*.md"
local SAVE_FILTER = "microword\t*.zmd"
local PICTURE_FILTER = "Pictures\t*.{png,jpg,jpeg,gif}"

local ON, OFF = "#c9dcf7", "#e4e4e4"

-- The paragraph styles, in the order the box lists them.
local STYLES = { "p", "h1", "h2", "h3", "quote", "code", "ul", "ol" }

local function ed() return edit.ed end

---------------------------------------------------------------- showing

local function updateTitle()
  local name = path and zmd.basename(path) or "Untitled"
  frm.caption = (ed().dirty and "*" or "") .. name .. " - microword"
end

local function updateStatus()
  local words, chars = ed():stats()
  local parts = { ("  %d words, %d characters"):format(words, chars) }
  local url = ed():linkAt()
  if url then parts[#parts + 1] = "link: " .. url .. "  (Cmd-click opens it)" end
  frm.lblStatus.caption = table.concat(parts, "      ")
end

-- updateToolbar shows the style at the caret: the paragraph's kind in the
-- box, and which of bold, italic and code are on.
local function updateToolbar()
  local e = ed()
  local t = e:blockType()
  for i, s in ipairs(STYLES) do
    if s == t or (t:match("^h[4-6]$") and s == "h3") then frm.cboStyle.selected = i end
  end
  frm.cmdBold.color = e:isOn("b") and ON or OFF
  frm.cmdItalic.color = e:isOn("i") and ON or OFF
  frm.cmdCode.color = e:isOn("code") and ON or OFF
  frm.cmdLink.color = e:linkAt() and ON or OFF
  frm.cmdBullets.color = t == "ul" and ON or OFF
  frm.cmdNumbers.color = t == "ol" and ON or OFF
  frm.cmdQuote.color = t == "quote" and ON or OFF
  frm.cmdUndo.enabled = e:canUndo()
  frm.cmdRedo.enabled = e:canRedo()
end

function edit:onChange()
  updateTitle()
end

function edit:onSelect()
  updateToolbar()
  updateStatus()
end

-- change runs fn on the editor, and shows what it did.
local function change(fn)
  fn(ed())
  edit:changed()
  edit:focus()
end

---------------------------------------------------------------- files

local function setDocument(blocks, assets, file)
  edit:load(blocks, assets)
  path = file
  updateTitle()
  updateToolbar()
  updateStatus()
end

local function openPath(file)
  local blocks, assets = zmd.load(file)
  if not blocks then
    gui.msgbox(("Cannot open %s.\n\n%s"):format(file, tostring(assets)), "ok", "microword")
    return false
  end
  -- A .md is opened as a new document: saving makes a .zmd of it.
  setDocument(blocks, assets, zmd.extension(file) == "zmd" and file or nil)
  if zmd.extension(file) ~= "zmd" then
    frm.caption = zmd.basename(file) .. " - microword"
  end
  return true
end

local function saveTo(file)
  if zmd.extension(file) ~= "zmd" then file = file .. ".zmd" end
  local ok, err = zmd.save(file, ed().blocks, edit.pictures)
  if not ok then
    gui.msgbox(("Cannot save %s.\n\n%s"):format(file, tostring(err)), "ok", "microword")
    return false
  end
  path = file
  ed().dirty = false
  updateTitle()
  return true
end

local function saveAs()
  local file = gui.savefile { title = "Save As", filter = SAVE_FILTER, file = path and zmd.basename(path) or "Untitled.zmd" }
  if not file then return false end
  return saveTo(file)
end

local function save()
  if path then return saveTo(path) end
  return saveAs()
end

local function confirmDiscard()
  if not ed().dirty then return true end
  local answer = gui.msgbox("Do you want to save the changes to this document?", "yesnocancel", "microword")
  if answer == "yes" then return save() end
  return answer == "no"
end

local function newDocument()
  if not confirmDiscard() then return end
  setDocument({}, {}, nil)
end

local function openDialog()
  if not confirmDiscard() then return end
  local file = gui.openfile { title = "Open", filter = DOC_FILTER }
  if file then openPath(file) end
end

local function exportMarkdown()
  local base = path and zmd.basename(path):gsub("%.zmd$", "") or "Untitled"
  local file = gui.savefile { title = "Export Markdown", filter = "Markdown\t*.md", file = base .. ".md" }
  if not file then return end
  if zmd.extension(file) ~= "md" then file = file .. ".md" end
  local ok, err = zmd.exportMarkdown(file, ed().blocks, edit.pictures)
  if not ok then
    gui.msgbox(("Cannot export %s.\n\n%s"):format(file, tostring(err)), "ok", "microword")
  else
    frm.lblStatus.caption = "  Exported " .. file .. ", with its pictures in assets/ beside it"
  end
end

---------------------------------------------------------------- pictures and links

-- addPicture puts a picture file in the document at the caret, keeping a
-- copy of it in the document's assets.
local function addPicture(file)
  local f = io.open(file, "rb")
  local data = f and f:read("*a")
  if f then f:close() end
  local asset, err
  if data then asset, err = zmd.asset(data) end
  if not asset then
    gui.msgbox(("Cannot use %s as a picture.\n\n%s"):format(file, tostring(err or "it cannot be read")), "ok", "microword")
    return false
  end
  local name = zmd.uniqueName(edit.pictures, file)
  edit.pictures[name] = asset
  local alt = zmd.basename(file):gsub("%.[^.]*$", "")
  change(function(e) e:insertImage(name, alt) end)
  return true
end

local function insertPicture()
  local file = gui.openfile { title = "Insert Picture", filter = PICTURE_FILTER }
  if file then addPicture(file) end
end

local function editLink()
  local e = ed()
  local current = e:linkAt()
  local url = gui.inputbox("Link address (empty to remove the link):", "Link", current or "https://")
  if url == nil then return end
  change(function(x) x:setLink(url) end)
end

local function openLink(url)
  if not url then return end
  local cmd
  if gui.platform == "windows" then cmd = { "cmd", "/c", "start", "", url }
  elseif gui.platform == "darwin" then cmd = { "open", url }
  else cmd = { "xdg-open", url } end
  pcall(gui.spawn, cmd)
end

-- A link to a heading of the document is the editor's to go to.
function edit:onLink(url)
  if url:match("^#") then return false end
  openLink(url)
  return true
end

---------------------------------------------------------------- the clipboard

local function copy()
  local text = ed():copyText()
  if text then gui.clipboard(text) end
end

local function cut()
  local text = ed():copyText()
  if not text then return end
  gui.clipboard(text)
  change(function(e) e:deleteSelection() end)
end

local function paste()
  local text = gui.clipboard()
  if text and text ~= "" then change(function(e) e:paste(text) end) end
end

---------------------------------------------------------------- actions

local function setStyle(t, toggle)
  change(function(e) e:setType(t, toggle) end)
end

-- askTable asks how big a table to make: "3 x 4" is three rows of four.
local function askTable()
  local answer = gui.inputbox("Rows and columns, such as 3 x 4:", "Insert Table", "3 x 3")
  if not answer then return end
  local r, c = answer:match("^%s*(%d+)%s*[xX*,]%s*(%d+)%s*$")
  r, c = tonumber(r), tonumber(c)
  if not r or r < 1 or r > 100 or c < 1 or c > 20 then
    gui.msgbox("Say how many rows and columns, such as 3 x 4 (up to 100 rows and 20 columns).", "ok", "Insert Table")
    return
  end
  return r, c
end

-- inTable runs fn on the table the caret is in, or says there is none.
local function inTable(fn)
  local e = ed()
  if not e:tableAt() then
    gui.msgbox("Put the caret in a table first.", "ok", "Table")
    return
  end
  change(fn)
end

local help = [[Typing at the start of a paragraph:
  # and a space        Heading 1 (## Heading 2, ### Heading 3)
  - and a space        a bullet list
  1. and a space       a numbered list
  > and a space        a quote
  --- and Enter        a horizontal rule
  Insert > Table...    a table: click in a cell to type, Tab to the next
                       (a new row after the last), Escape to leave it;
                       the Table menu adds and removes rows and columns

In a list, Tab and Shift+Tab move an item in and out,
and Enter on an empty item ends the list.
In a code block, Enter on an empty last line leaves it.
Shift+Enter starts a new line in the same paragraph.

Cmd+B, Cmd+I, Cmd+E    bold, italic, code
Cmd+K                  a link; Cmd-click one to open it
Insert > Table of Contents   the headings, each a link: Cmd-click one to go there
Cmd+0 to Cmd+3         normal text, headings
Cmd+U                  the Markdown the document is kept as

Documents are saved as .zmd: a zip of the Markdown, as
document.md, and the pictures in it, in assets/.]]

local actions = {
  mnuNew = newDocument,
  mnuOpen = openDialog,
  mnuSave = save,
  mnuSaveAs = saveAs,
  mnuExport = exportMarkdown,
  mnuExit = function() frm:close() end,
  mnuUndo = function() change(function(e) e:undo() end) end,
  mnuRedo = function() change(function(e) e:redo() end) end,
  mnuCut = cut,
  mnuCopy = copy,
  mnuPaste = paste,
  mnuSelectAll = function() ed():selectAll() edit:moved() end,
  mnuImage = insertPicture,
  mnuLink = editLink,
  mnuRule = function() change(function(e) e:insertRule() end) end,
  mnuTable = function()
    local rows, cols = askTable()
    if rows then change(function(e) e:insertTable(rows, cols) end) end
  end,
  mnuRowAbove = function() inTable(function(e) e:insertRow(false) end) end,
  mnuRowBelow = function() inTable(function(e) e:insertRow(true) end) end,
  mnuColLeft = function() inTable(function(e) e:insertColumn(false) end) end,
  mnuColRight = function() inTable(function(e) e:insertColumn(true) end) end,
  mnuDelRow = function() inTable(function(e)
    if not e:deleteRow() then gui.msgbox("A table keeps its first row.", "ok", "Table") end
  end) end,
  mnuDelCol = function() inTable(function(e)
    if not e:deleteColumn() then gui.msgbox("A table keeps one column.", "ok", "Table") end
  end) end,
  mnuAlignLeft = function() inTable(function(e) e:setAlign("left") end) end,
  mnuAlignCenter = function() inTable(function(e) e:setAlign("center") end) end,
  mnuAlignRight = function() inTable(function(e) e:setAlign("right") end) end,
  mnuAlignNone = function() inTable(function(e) e:setAlign(false) end) end,
  -- A table of contents lists the headings, each a link to its heading.
  mnuToc = function() change(function(e) e:insertBlock { type = "toc" } end) end,
  mnuBold = function() change(function(e) e:toggle("b") end) end,
  mnuItalic = function() change(function(e) e:toggle("i") end) end,
  mnuCode = function() change(function(e) e:toggle("code") end) end,
  mnuNormal = function() setStyle("p") end,
  mnuH1 = function() setStyle("h1") end,
  mnuH2 = function() setStyle("h2") end,
  mnuH3 = function() setStyle("h3") end,
  mnuQuote = function() setStyle("quote", true) end,
  mnuCodeBlock = function() setStyle("code", true) end,
  mnuBullets = function() setStyle("ul", true) end,
  mnuNumbers = function() setStyle("ol", true) end,
  mnuIndent = function() change(function(e) e:indent(1) end) end,
  mnuOutdent = function() change(function(e) e:indent(-1) end) end,
  mnuSource = function() source.view(ed():markdown()) end,
  mnuKeys = function() gui.msgbox(help, "ok", "Writing Shortcuts") end,
  mnuAbout = function()
    gui.msgbox("microword\n\nA small word processor that writes Markdown, made with tlua and its form designer.", "ok", "About microword")
  end,
}

function frm.Menu1:onClick(name)
  if actions[name] then actions[name]() end
end

-- The toolbar does what the menu does.
local buttons = {
  cmdUndo = "mnuUndo", cmdRedo = "mnuRedo", cmdBold = "mnuBold", cmdItalic = "mnuItalic",
  cmdCode = "mnuCode", cmdLink = "mnuLink", cmdBullets = "mnuBullets", cmdNumbers = "mnuNumbers",
  cmdQuote = "mnuQuote", cmdImage = "mnuImage", cmdRule = "mnuRule",
}
for button, action in pairs(buttons) do
  frm[button].onClick = function() actions[action]() end
end

function frm.cboStyle:onChange()
  local t = STYLES[self.selected]
  if t and t ~= ed():blockType() then setStyle(t) end
end

-- The context menu, for what is at the caret or selected.
function edit:onMenu()
  local e = ed()
  local items = {
    { "Cu&t", cut, enabled = e:hasSelection() },
    { "&Copy", copy, enabled = e:hasSelection() },
    { "&Paste", paste },
    "-",
    { "&Bold", actions.mnuBold, checked = e:isOn("b") },
    { "&Italic", actions.mnuItalic, checked = e:isOn("i") },
    { "C&ode", actions.mnuCode, checked = e:isOn("code") },
    "-",
    { "&Link...", editLink },
  }
  if e:tableAt() then
    for _, item in ipairs {
      "-",
      { "Row &Above", actions.mnuRowAbove }, { "Row &Below", actions.mnuRowBelow },
      { "Column &Left", actions.mnuColLeft }, { "Column &Right", actions.mnuColRight },
      { "Delete &Row", actions.mnuDelRow }, { "Delete &Column", actions.mnuDelCol },
    } do items[#items + 1] = item end
  end
  local url = e:linkAt()
  if url then
    items[#items + 1] = { "&Open Link", function()
      if url:match("^#") then edit:scrollTo(url) else openLink(url) end
    end }
    items[#items + 1] = { "&Remove Link", function() change(function(x) x:setLink("") end) end }
  end
  gui.popup(items, frm)
end

---------------------------------------------------------------- the form

function frm:onClose()
  if not confirmDiscard() then return false end
end

-- A document dropped on the window is opened; a picture goes in at the
-- caret.
function frm:onDrop(text, lines)
  local file = lines and lines[1]
  if not file or lfs.attributes(file, "mode") ~= "file" then return end
  local ext = zmd.extension(file)
  if ext == "zmd" or ext == "md" then
    if confirmDiscard() then openPath(file) end
  else
    addPicture(file)
  end
end
edit.onDrop = function(_, text, lines) frm:fire("onDrop", text, lines) end

-- A document named on the command line is opened: tlua microword.ztl notes.zmd
local start = arg and arg[1]
if start and start ~= "" and lfs.attributes(start, "mode") == "file" then
  openPath(start)
else
  setDocument({}, {}, nil)
end
gui.after(0, function() edit:focus() end)

-- Exposed for the tests.
frm.openPath = openPath
frm.saveTo = saveTo
frm.addPicture = addPicture
frm.actions = actions

return frm
