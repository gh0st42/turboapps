-- The code behind MicroNotes.form.lua: the controls are fields of the form,
-- by the names the layout gives them.
--
-- The notes are in treNotes on the left, the one open on the right, shown
-- one of three ways: edNote (tlua's MarkdownEdit) edits it as it looks,
-- vwNote (a MarkdownView) shows it to read, its links followed with a
-- click, and txtSource edits its Markdown. notebook.lua keeps the notes
-- and their attachments, and reads and writes the .znb.

local gui = require "gui"
local lfs = require "lfs"
local md = require "markdown"
local notebook = require "notebook"
local picker = require "forms.LinkPicker"
local find = require "forms.Find"
local finder = require "finder"

local frm = gui.load "MicroNotes" --[[@as forms.MicroNotes]]
local edit, view, source, tree = frm.edNote, frm.vwNote, frm.txtSource, frm.treNotes

local nb             -- the notebook
local path           -- its .znb, or nil before it is saved
local current        -- the note open, by its path in the notebook
local mode = "read"  -- "edit", "read" or "source": it starts reading
local openFolders = {}
local settings = notebook.loadSettings()
local editorChanged = false -- edNote has changes not yet in the notebook
local quiet = false         -- the program is changing what is shown
local saveTimer

local BOOK_FILTER = "Notebooks\t*.znb"
local ON, OFF = "#c9dcf7", "#e4e4e4"

---------------------------------------------------------------- what shows

local function bookName()
  return path and notebook.basename(path:gsub("\\", "/")):gsub("%.znb$", "") or "Untitled"
end

local function updateTitle()
  frm.caption = (nb.dirty and "• " or "") .. bookName() .. (nb.password and " (encrypted)" or "") .. " - micronotes"
end

-- currentText is the note open as it is now, the view it is in aside.
local function currentText()
  if mode == "edit" and editorChanged then return edit:markdown() end
  if mode == "source" then return source.text end
  return current and nb.notes[current] or ""
end

local function updateStatus(note)
  local parts = {}
  if current then
    if mode == "edit" then
      local words, chars = edit.ed:stats()
      parts[#parts + 1] = ("%d words, %d characters"):format(words, chars)
    end
    parts[#parts + 1] = current
    local tags = notebook.tagsOf(currentText())
    if #tags > 0 then parts[#parts + 1] = "#" .. table.concat(tags, " #") end
  end
  parts[#parts + 1] = (nb.dirty and "not saved" or (path and "saved" or "not saved yet"))
  if note then parts[#parts + 1] = note end
  frm.lblStatus.caption = "  " .. table.concat(parts, "   ·   ")
end

local results = {} -- the notes the search found, as nb:find gives them

-- showResults lists what the search box asks for over the tree (which is
-- put away while it is used), each note with a piece of its text, or lets
-- the tree back when the box is empty.
local function showResults()
  local text = frm.txtSearch.text or ""
  local searching = text:match("%S") ~= nil
  tree.visible = not searching
  frm.lstResults.visible = searching
  if not searching then
    results = {}
    return 0
  end
  results = nb:find(text)
  local items = {}
  for i, r in ipairs(results) do
    local dir = notebook.dirname(r.path)
    items[i] = ("%s%s    %s"):format(r.title, dir ~= "" and ("  (" .. dir .. ")") or "", r.snippet)
  end
  quiet = true
  frm.lstResults.items = items
  frm.lstResults.selected = 0
  quiet = false
  return #results
end

local function updateTree()
  quiet = true
  tree.items = nb:items(openFolders)
  if current then tree.path = notebook.treePath(current) end
  quiet = false
  if (frm.txtSearch.text or ""):match("%S") then showResults() end
end

local function updateBacklinks()
  local list = current and nb:backlinks(current) or {}
  local titles = {}
  for i, p in ipairs(list) do
    titles[i] = notebook.title(p) .. (notebook.dirname(p) ~= "" and ("   (" .. notebook.dirname(p) .. ")") or "")
  end
  frm.lstBacklinks.items = titles
  frm.lstBacklinks.tag = list
  frm.lblBacklinks.caption = #list == 0 and "No backlinks" or (#list == 1 and "1 backlink" or (#list .. " backlinks"))
end

local function updateButtons()
  frm.cmdEdit.color = mode == "edit" and ON or OFF
  frm.cmdRead.color = mode == "read" and ON or OFF
  frm.cmdSource.color = mode == "source" and ON or OFF
  local items = frm.Menu1.items
  for _, menu in ipairs(items) do
    for _, it in ipairs(menu[2]) do
      if type(it) == "table" then
        if it.name == "mnuViewEdit" then it.checked = mode == "edit" end
        if it.name == "mnuViewRead" then it.checked = mode == "read" end
        if it.name == "mnuViewSource" then it.checked = mode == "source" end
      end
    end
  end
  frm.Menu1.items = items
end

---------------------------------------------------------------- the note open

-- flush puts what the view open has changed into the notebook.
local function flush()
  if not current or not nb.notes[current] then return end
  if mode == "edit" and editorChanged then
    nb:setText(current, edit:markdown())
    editorChanged = false
  elseif mode == "source" then
    nb:setText(current, source.text)
  end
end

-- show puts the note open into the view of the mode.
local function show()
  quiet = true
  local text = current and nb.notes[current]
  edit.visible, view.visible, source.visible = mode == "edit", mode == "read", mode == "source"
  if mode == "edit" then
    edit:load(text or "", nb:pictures(current))
    editorChanged = false
  elseif mode == "read" then
    view.pictures = nb:pictures(current)
    view.text = text and notebook.linkTags(text) or "*No note is open: pick one on the left, or make one with Cmd+N.*\n"
  else
    source.text = text or ""
  end
  frm.lblTitle.caption = current and notebook.title(current) or ""
  quiet = false
  updateButtons()
  updateBacklinks()
  updateStatus()
end

local function focusView()
  if mode == "edit" then edit:focus() elseif mode == "read" then view:focus() else source:focus() end
end

-- open shows a note.
local function open(p)
  if p == current then focusView() return end
  flush()
  current = p
  nb.open = p
  show()
  updateTree()
  focusView()
end

local function setMode(m)
  if m == mode then return end
  flush()
  mode = m
  show()
  focusView()
end

-- openFound opens a note found by searching to read, not to edit, and
-- leaves the keyboard where it is: Enter pressed again in the search box
-- cannot type into the note.
local function openFound(p)
  if mode ~= "read" then
    flush()
    mode = "read"
    if p == current then show() end
  end
  if p ~= current then
    flush()
    current = p
    nb.open = p
    show()
    updateTree()
  end
end

---------------------------------------------------------------- saving

local function saveTo(file)
  flush()
  local ok, err = nb:save(file)
  if not ok then
    gui.msgbox("Could not save " .. file .. ":\n" .. tostring(err), "ok", "micronotes")
    return false
  end
  path = file
  settings.last = file
  notebook.saveSettings(settings)
  updateTitle()
  updateStatus()
  return true
end

local function saveAs()
  local file = gui.savefile { title = "Save Notebook", filter = BOOK_FILTER, file = bookName() .. ".znb" }
  if not file then return false end
  if not file:lower():match("%.znb$") then file = file .. ".znb" end
  return saveTo(file)
end

local function save()
  if not path then return saveAs() end
  return saveTo(path)
end

-- changed notes a change: the title says so, and a notebook that has a
-- file is saved to it a moment after the typing stops.
local function changed()
  nb.dirty = true
  updateTitle()
  updateStatus()
  if path then
    if saveTimer then saveTimer:stop() end
    saveTimer = gui.after(1.5, function()
      saveTimer = nil
      if nb.dirty and path then saveTo(path) end
    end)
  end
end

-- setPassword encrypts the notebook, all of it, from its next save; an
-- empty password takes the encryption off.
local function setPassword()
  local pw = gui.passwordbox("Password for this notebook.\nLeave it empty to remove the password.", "Set Password", true)
  if not pw then return end
  nb.password = pw ~= "" and pw or nil
  changed()
end

---------------------------------------------------------------- finding in a note

-- Each view finds in its own way: the Edit view through the editor, the
-- Read view through the view's search (the case of letters aside, and no
-- replacing), the Source view in the text of its box.
local editTarget = {
  canReplace = true,
  find = function(needle, opts, back)
    local found, wrapped = edit.ed:find(needle, opts, back)
    if found then edit:moved() end
    return found, wrapped
  end,
  replace = function(needle, with, opts)
    local replaced, found = edit.ed:replace(needle, with, opts)
    if replaced then edit:changed() end
    if found then edit:moved() end
    return replaced, found
  end,
  replaceAll = function(needle, with, opts)
    local n = edit.ed:replaceAll(needle, with, opts)
    if n > 0 then edit:changed() end
    return n
  end,
  count = function(needle, opts) return edit.ed:countMatches(needle, opts) end,
  selection = function() return edit.ed:copyText() end,
}

local readTarget = {
  canReplace = false,
  find = function(needle, _, back) return view:search(needle, back), false end,
  count = function(needle) return view:matches(needle) end,
  selection = function() return view:selectedText() end,
}

-- selStart is where the source's selection begins (the cursor, when the
-- selection is nothing, or is before it), counted from 1.
local function selStart()
  local sel, cur = source.selectedText, source.cursor
  if sel ~= "" and cur >= #sel and source.text:sub(cur - #sel + 1, cur) == sel then return cur - #sel + 1 end
  return cur + 1
end

local sourceTarget = {
  canReplace = true,
  find = function(needle, opts, back)
    local text = source.text
    local i, j, wrapped
    if back then
      local before = selStart()
      i, j = finder.findBack(text, needle, before, opts)
      wrapped = i and j >= before
    else
      local from = source.cursor + 1
      i, j = finder.find(text, needle, from, opts)
      -- The selection is a match already, with the cursor before it: skip it.
      if i == from and source.selectedText ~= "" and source.selectedText == text:sub(i, j) then
        i, j = finder.find(text, needle, i + 1, opts)
      end
      wrapped = i and i < from
    end
    if not i then return false end
    source:select(i, j)
    return true, wrapped
  end,
  replace = function(needle, with, opts)
    local replaced = false
    if finder.matches(source.selectedText, needle, opts) then
      source:insert(with)
      changed()
      replaced = true
    end
    local found = sourceTarget.find(needle, opts, false)
    return replaced, found
  end,
  replaceAll = function(needle, with, opts)
    local text, n = finder.replaceAll(source.text, needle, with, opts)
    if n > 0 then
      local line = source.line
      source.text = text
      source.line = line
      changed()
    end
    return n
  end,
  count = function(needle, opts)
    local at = source.selectedText ~= "" and selStart() or nil
    return finder.count(source.text, needle, opts, at)
  end,
  selection = function() return source.selectedText end,
}

find.attach(function()
  if mode == "edit" then return editTarget end
  if mode == "source" then return sourceTarget end
  return readTarget
end)

local function confirmDiscard()
  flush()
  if not nb.dirty then return true end
  if path then return saveTo(path) end
  local answer = gui.msgbox("Do you want to save this notebook?", "yesnocancel", "micronotes")
  if answer == "yes" then return save() end
  return answer == "no"
end

local function setNotebook(book, file)
  nb, path = book, file
  current = nil
  openFolders = {}
  for _, f in ipairs(nb:allFolders()) do openFolders[f] = true end
  local first = nb.open or nb:notePaths()[1]
  current = first
  nb.open = first
  frm.txtSearch.text = ""
  show()
  updateTree()
  updateTitle()
  if file then
    settings.last = file
    notebook.saveSettings(settings)
  end
end

local function openPath(file)
  local book, err, why = notebook.load(file)
  -- An encrypted notebook asks for its password until it is right.
  while not book and why == "locked" do
    local pw = gui.passwordbox((err:find("wrong", 1, true) and "Wrong password. " or "")
      .. notebook.basename(file) .. " is encrypted.\nPassword:", "Open")
    if not pw then return false end
    book, err, why = notebook.load(file, pw)
  end
  if not book then
    gui.msgbox("Could not open " .. file .. ":\n" .. tostring(err), "ok", "micronotes")
    return false
  end
  setNotebook(book, file)
  return true
end

---------------------------------------------------------------- notes and folders

-- here is the folder the tree's selection is in, for a new note.
local function here()
  local kind, p = nb:at(tree.path)
  if kind == "folder" then return p end
  if p then return notebook.dirname(p) end
  return current and notebook.dirname(current) or ""
end

local function newNote(dir, name)
  name = name or gui.inputbox("Name of the new note:", "New Note", "Untitled")
  if not name then return end
  local ok, why = notebook.validName(name)
  if not ok then gui.msgbox(why, "ok", "New Note") return end
  flush()
  local p = nb:createNote(dir or here(), name)
  openFolders[notebook.dirname(p)] = true
  changed()
  current = nil
  open(p)
  return p
end

local function newFolder()
  local name = gui.inputbox("Name of the new folder:", "New Folder", "New folder")
  if not name then return end
  local ok, why = notebook.validName(name)
  if not ok then gui.msgbox(why, "ok", "New Folder") return end
  local p = nb:createFolder(here(), name)
  openFolders[p] = true
  changed()
  updateTree()
end

-- rename renames or moves what the tree has selected, or the note open:
-- a path with folders in it moves it there.
local function rename(treePath)
  flush()
  local kind, p = nb:at(treePath or tree.path)
  if not kind then kind, p = current and "note", current end
  if not kind then return end
  local shown = kind == "note" and notebook.treePath(p) or p
  local answer = gui.inputbox("New name, or a path to move it to (Folder/Name):", "Rename", shown)
  if not answer or answer == shown then return end
  for part in answer:gmatch("[^/]+") do
    local ok, why = notebook.validName(part)
    if not ok then gui.msgbox(why, "ok", "Rename") return end
  end
  local newPath, err = nb:move(p, answer)
  if not newPath then gui.msgbox(err, "ok", "Rename") return end
  if current == p then current = newPath
  elseif kind == "folder" and current and current:sub(1, #p + 1) == p .. "/" then
    current = newPath .. current:sub(#p + 1)
  end
  openFolders[notebook.dirname(newPath)] = true
  changed()
  show()
  updateTree()
end

local function delete(treePath)
  flush()
  local kind, p = nb:at(treePath or tree.path)
  if not kind then kind, p = current and "note", current end
  if not kind then return end
  local what = kind == "folder" and ("the folder " .. p .. " and everything in it") or ("“" .. notebook.basename(notebook.treePath(p)) .. "”")
  if gui.msgbox("Delete " .. what .. "?", "yesno", "Delete") ~= "yes" then return end
  nb:remove(p)
  if current and not nb.notes[current] then current = nb:notePaths()[1] end
  changed()
  show()
  updateTree()
end

---------------------------------------------------------------- links and attachments

-- openAttachment opens a file of the notebook's in its own program, from a
-- copy in the temporary folder.
local function openAttachment(p)
  local data = nb.files[p]
  if not data then return false end
  local dir = os.tmpname()
  os.remove(dir)
  lfs.mkdir(dir)
  local file = dir .. "/" .. notebook.basename(p)
  local f = io.open(file, "wb")
  if not f then return false end
  f:write(data)
  f:close()
  gui.openurl(file)
  return true
end

-- follow goes where a link leads: a note (made if it is not there yet), a
-- file of the notebook's, or a web address.
local function follow(url)
  -- A #tag is a link to the notes that have it.
  local tag = url:match("^tag:(.+)$")
  if tag then
    frm.txtSearch.text = "#" .. tag
    frm.txtSearch:fire("onChange")
    return true
  end
  -- A link to a heading of the note shown is the view's to go to.
  if url:match("^#") then return false end
  local target = notebook.linkTarget(url)
  if target then
    local p = nb:resolve(target, current)
    if not p then
      local dir = notebook.dirname(target) ~= "" and notebook.dirname(target) or (current and notebook.dirname(current) or "")
      flush()
      p = nb:createNote(dir, notebook.basename(target), "# " .. notebook.basename(target) .. "\n")
      changed()
    end
    open(p)
    updateTree()
    return true
  end
  local file = notebook.clean(url:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
  if file and nb.files[file] then return openAttachment(file) end
  if url:match("^%a[%w+.-]*:") then gui.openurl(url) return true end
  updateStatus("no such note or file: " .. url)
  return true
end

function edit:onLink(url) return follow(url) end
function view:onLink(url) return follow(url) end

function edit:onHover(url) updateStatus(url and ("Cmd-click to open " .. url) or nil) end
function view:onHover(url) updateStatus(url) end

-- wikiRun is a link to a note, as the editor keeps one.
local function wikiRun(title, words)
  return { text = words or title, link = md.wikiLink(title), wiki = title }
end

-- pickNote asks which note to link to.
local function pickNote(start)
  local titles = {}
  for _, p in ipairs(nb:notePaths()) do titles[#titles + 1] = notebook.title(p) end
  table.sort(titles, function(a, b) return a:lower() < b:lower() end)
  return picker.pick(titles, start)
end

local function insertWikiLink()
  if mode == "read" then setMode("edit") end
  local title = pickNote()
  if not title then return end
  if mode == "source" then
    source:insert("[[" .. title .. "]]")
  else
    edit.ed:insertRuns({ wikiRun(title) }, "link")
    edit.ed.pending = {}
    edit:changed()
  end
end

-- typedLinks turns what was just typed into a link: [[ asks for the note,
-- and [[Name]] typed out in full becomes a link to it.
local function typedLinks()
  local ed = edit.ed
  if ed:hasSelection() then return end
  local p = ed.caret
  local b = ed.blocks[p.b]
  if not b or not md.hasText(b) or b.type == "code" then return end
  local before = md.textOf(b):sub(1, p.o)
  local style = ed:styleAt(p)
  if style.code or style.link then return end
  local target, words = before:match("%[%[([^%[%]|]+)|?([^%[%]]*)%]%]$")
  if target then
    local len = #target + #words + (words ~= "" and 1 or 0) + 4
    ed.anchor = { b = p.b, o = p.o - len }
    ed:insertRuns({ wikiRun(target, words ~= "" and words or nil) }, "link")
    ed.pending = {}
    return true
  end
  if before:match("%[%[$") and not before:match("%[%[%[$") then
    local title = pickNote()
    if title then
      ed.anchor = { b = p.b, o = p.o - 2 }
      ed:insertRuns({ wikiRun(title) }, "link")
      ed.pending = {}
      return true
    end
  end
end

-- attach adds files to the notebook and puts them in the note at the
-- caret: pictures to show, other files as links to them.
local function attach(files)
  if not current then newNote(nil, "Untitled") end
  if mode == "read" then setMode("edit") end
  local added = 0
  for _, file in ipairs(files) do
    local f = io.open(file, "rb")
    if f then
      local data = f:read("*a")
      f:close()
      local name = notebook.basename(file:gsub("\\", "/"))
      local p = nb:attach(name, data)
      local isPic = notebook.isPicture(p) and nb:picture(p)
      local src = p:gsub(" ", "%%20")
      if mode == "source" then
        source:insert((isPic and "![%s](%s)\n" or "[%s](%s)"):format(name, src))
      elseif isPic then
        edit.ed:insertImage(src, name)
      else
        edit.ed:insertRuns({ { text = name, link = src } }, "link")
        edit.ed.pending = {}
      end
      added = added + 1
    end
  end
  if added > 0 then
    if mode == "edit" then edit:changed() end
    updateTree()
    changed()
  end
end

local function insertPicture()
  local files = gui.openfile { title = "Insert Picture", filter = "Pictures\t*.{png,jpg,jpeg,gif}", multiple = true }
  if files then attach(files) end
end

local function insertFile()
  local files = gui.openfile { title = "Attach Files", multiple = true }
  if files then attach(files) end
end

---------------------------------------------------------------- the views

function edit:onChange()
  if quiet then return end
  editorChanged = true
  if typedLinks() then
    quiet = true
    edit:changed()
    quiet = false
  end
  changed()
end

function edit:onSelect()
  if not quiet then updateStatus() end
end

function edit:onMenu()
  local ed = edit.ed
  local url = ed:linkAt()
  local items = {
    { "Cu&t", function() gui.clipboard(ed:copyText()) ed:deleteSelection() edit:changed() end, enabled = ed:hasSelection() },
    { "&Copy", function() gui.clipboard(ed:copyText()) end, enabled = ed:hasSelection() },
    { "&Paste", function() ed:paste(gui.clipboard() or "") edit:changed() end },
    "-",
    { "Link to &Note...", insertWikiLink },
    { "Insert &Picture...", insertPicture },
    { "Attach &File...", insertFile },
  }
  if ed:tableAt() then
    for _, item in ipairs {
      "-",
      { "Row &Above", actions.mnuRowAbove }, { "Row &Below", actions.mnuRowBelow },
      { "Column &Left", actions.mnuColLeft }, { "Column &Right", actions.mnuColRight },
      { "Delete &Row", actions.mnuDelRow }, { "Delete &Column", actions.mnuDelCol },
    } do items[#items + 1] = item end
  end
  if url then
    items[#items + 1] = "-"
    items[#items + 1] = { "&Open Link", function()
      if url:match("^#") then edit:scrollTo(url) else follow(url) end
    end }
    items[#items + 1] = { "&Remove Link", function() ed:setLink("") edit:changed() end }
  end
  gui.popup(items, frm)
end

function source:onChange()
  if quiet then return end
  changed()
end

-- NOTE is how a node dragged out of the tree is carried: its tree path.
local NOTE = "micronotes:"

local function dropped(_, text, lines)
  -- A note dragged from the tree onto the note open is a link to it.
  local carried = text and text:sub(1, #NOTE) == NOTE and text:sub(#NOTE + 1)
  if carried then
    local kind, p = nb:at(carried)
    if not kind or kind == "folder" or not current or p == current then return end
    if mode == "read" then setMode("edit") end
    if kind == "note" then
      local title = notebook.title(p)
      if mode == "source" then source:insert("[[" .. title .. "]]")
      else edit.ed:insertRuns({ wikiRun(title) }, "link") edit.ed.pending = {} edit:changed() end
    else
      local src = p:gsub(" ", "%%20")
      if mode == "source" then source:insert(("[%s](%s)"):format(notebook.basename(p), src))
      elseif notebook.isPicture(p) then edit.ed:insertImage(src, notebook.basename(p)) edit:changed()
      else edit.ed:insertRuns({ { text = notebook.basename(p), link = src } }, "link") edit.ed.pending = {} edit:changed() end
    end
    return
  end
  local files = {}
  for _, l in ipairs(lines or {}) do
    if lfs.attributes(l, "mode") == "file" then files[#files + 1] = l end
  end
  if #files == 1 and files[1]:lower():match("%.znb$") then
    if confirmDiscard() then openPath(files[1]) end
    return
  end
  if #files > 0 then attach(files) end
end
edit.onDrop = dropped
source.onDrop = dropped
frm.onDrop = dropped

function frm.cmdEdit:onClick() setMode("edit") end
function frm.cmdRead:onClick() setMode("read") end
function frm.cmdSource:onClick() setMode("source") end

---------------------------------------------------------------- the tree

function tree:onChange()
  if quiet then return end
  local kind, p = nb:at(self.path)
  if kind == "note" and (frm.txtSearch.text or "") ~= "" then
    openFound(p)
  elseif kind == "note" then
    open(p)
  elseif kind == "file" then
    flush()
    -- An attachment shows in the reading view, a picture as itself.
    quiet = true
    current = nil
    edit.visible, view.visible, source.visible = false, true, false
    view.pictures = nb:pictures()
    local src = p:gsub(" ", "%%20")
    view.text = ("# %s\n\n%s\n\n[Open it](%s) in its own program · %d bytes\n"):format(notebook.basename(p),
      notebook.isPicture(p) and ("![%s](%s)"):format(notebook.basename(p), src) or "", src, #nb.files[p])
    frm.lblTitle.caption = notebook.basename(p)
    quiet = false
    updateBacklinks()
  end
  -- A tree's own menu is about what it has selected.
  local items = {
    { "&New Note", function() newNote() end },
    { "New &Folder", newFolder },
  }
  if kind then
    items[#items + 1] = "-"
    if kind == "file" then items[#items + 1] = { "&Open", function() openAttachment(p) end } end
    items[#items + 1] = { "&Rename or Move...", function() rename() end }
    items[#items + 1] = { "&Delete", function() delete() end }
  end
  self.contextMenu = items
end

-- A node of the tree is dragged by its path, to drop on a folder (or a
-- note, for its folder) to move it there, or on the note open to link it.
function tree:onDrag()
  local p = self.path
  if p and p ~= "" and nb:at(p) then return NOTE .. p end
end

-- moveInto moves what tree path from names into folder dir ("" for the
-- top), keeping links working; nil and why when it cannot go there.
local function moveInto(from, dir)
  local kind, p = nb:at(from)
  if not kind then return nil end
  local name = kind == "note" and notebook.title(p) or notebook.basename(p)
  if notebook.dirname(p) == dir then return nil end
  if kind == "folder" and (dir == p or dir:sub(1, #p + 1) == p .. "/") then
    return nil, "A folder cannot go inside itself."
  end
  flush()
  local newPath, err = nb:move(p, notebook.join(dir, name))
  if not newPath then return nil, err end
  if current == p then current = newPath
  elseif kind == "folder" and current and current:sub(1, #p + 1) == p .. "/" then
    current = newPath .. current:sub(#p + 1)
  end
  if dir ~= "" then openFolders[dir] = true end
  changed()
  show()
  updateTree()
  return newPath
end

-- A drop on the tree lands in the folder it is on, or the one of the note
-- it is on, or at the top below them all: nodes of the tree move there,
-- and files from elsewhere come in there, Markdown as notes.
function tree:onDrop(text, lines, x, y, at)
  local dir = ""
  if at then
    local kind, p = nb:at(at)
    if kind == "folder" then dir = p elseif p then dir = notebook.dirname(p) end
  end
  if text:sub(1, #NOTE) == NOTE then
    local _, err = moveInto(text:sub(#NOTE + 1), dir)
    if err then gui.msgbox(err, "ok", "Move") end
    return
  end
  local added
  for _, file in ipairs(lines or {}) do
    if lfs.attributes(file, "mode") == "file" then
      local f = io.open(file, "rb")
      local data = f and f:read("*a")
      if f then f:close() end
      if data then
        local name = notebook.basename(file:gsub("\\", "/"))
        if notebook.isNote(name) then
          added = nb:createNote(dir, notebook.title(name), data)
        else
          local p = nb:free(dir ~= "" and dir or notebook.ATTACHMENTS, (name:gsub("%.[^.]*$", "")), name:match("%.[^.]*$") or "")
          nb.files[p] = data
          nb.dirty = true
        end
      end
    end
  end
  if dir ~= "" then openFolders[dir] = true end
  changed()
  updateTree()
  if added then open(added) end
end

function tree:onDoubleClick()
  local kind, p = nb:at(self.path)
  if kind == "file" then openAttachment(p) end
end

function tree:onToggle(treePath, isOpen)
  openFolders[treePath] = isOpen or nil
end

function frm.txtSearch:onChange()
  local n = showResults()
  local search = self.text or ""
  if search:match("%S") then
    updateStatus(n == 0 and "no note has that" or (n == 1 and "1 note" or (n .. " notes")))
  else
    updateStatus()
  end
end

-- reveal goes to where a note was found: the first place it has what was
-- looked for, in the view the note is in.
local function reveal(term)
  if not term or term == "" then return end
  if mode == "read" then view:search(term) end
end

-- openResult opens the note the list has picked, to read, at the place the
-- search found.
local function openResult(i)
  local r = results[i]
  if not r then return end
  openFound(r.path)
  reveal(r.term)
end

function frm.txtSearch:onKey(key)
  if key == "Enter" then
    openResult(1)
    return true
  end
  if key == "Down" and #results > 0 then
    frm.lstResults:focus()
    frm.lstResults.selected = 1
    return true
  end
  if key == "Escape" then
    self.text = ""
    showResults()
    updateTree()
    focusView()
    return true
  end
end

-- The arrows in the list of what was found open each note, to see it; a
-- double click goes to the note.
function frm.lstResults:onChange()
  if quiet then return end
  openResult(self.selected)
end

function frm.lstResults:onDoubleClick()
  focusView()
end

-- Tags: a menu of them, to pick one to see its notes.
function frm.cmdTags:onClick()
  local items = {}
  for _, t in ipairs(nb:tags()) do
    local tag = t.tag
    items[#items + 1] = { ("#%s  (%d)"):format(tag:gsub("&", "&&"):gsub("/", "∕"), t.count), function()
      frm.txtSearch.text = "#" .. tag
      frm.txtSearch:fire("onChange")
      frm.txtSearch:focus()
    end }
  end
  if #items == 0 then
    items[1] = { "No tags yet: write #tag in a note", enabled = false }
  else
    items[#items + 1] = "-"
    items[#items + 1] = { "Show all notes", function()
      frm.txtSearch.text = ""
      frm.txtSearch:fire("onChange")
    end }
  end
  gui.popup(items, frm)
end

function frm.lstBacklinks:onDoubleClick()
  local list = self.tag or {}
  local p = list[self.selected or 0]
  if p then open(p) end
end

function frm.cmdNewNote:onClick() newNote() end
function frm.cmdNewFolder:onClick() newFolder() end

---------------------------------------------------------------- menus

-- inSource wraps the selection of the source view in Markdown marks.
local function wrapSource(mark)
  local sel = source.selectedText or ""
  source:insert(mark .. sel .. mark)
end

local function format(fn, mark)
  if mode == "source" then
    if mark then wrapSource(mark) else updateStatus("paragraph styles are for the Edit view") end
    return
  end
  if mode == "read" then setMode("edit") end
  fn(edit.ed)
  edit:changed()
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

-- inTable runs fn on the table the caret is in; the Table menu is for the
-- Edit view.
local function inTable(fn)
  if mode == "source" then updateStatus("a table's rows and columns are changed in the Edit view") return end
  if mode == "read" then setMode("edit") end
  if not edit.ed:tableAt() then updateStatus("put the caret in a table first") return end
  fn(edit.ed)
  edit:changed()
end

local function setStyle(t, toggle)
  format(function(ed) ed:setType(t, toggle) end)
end

local function clip(op)
  if mode == "source" then
    local sel = source.selectedText or ""
    if op == "copy" or op == "cut" then if sel ~= "" then gui.clipboard(sel) end end
    if op == "cut" then source:insert("") end
    if op == "paste" then source:insert(gui.clipboard() or "") end
    return
  end
  if mode == "read" then
    if op == "copy" then view:copy() end
    return
  end
  local ed = edit.ed
  if op == "copy" or op == "cut" then
    if ed:hasSelection() then gui.clipboard(ed:copyText()) end
    if op == "cut" then ed:deleteSelection() edit:changed() end
  else
    ed:paste(gui.clipboard() or "")
    edit:changed()
  end
end

local function editLink()
  if mode == "read" then setMode("edit") end
  local current_ = mode == "edit" and edit.ed:linkAt() or ""
  local url = gui.inputbox("Link to (a web address, or a note's name):", "Link", current_ or "")
  if not url then return end
  if mode == "source" then
    local sel = source.selectedText or ""
    source:insert(("[%s](%s)"):format(sel ~= "" and sel or url, url))
    return
  end
  edit.ed:setLink(url)
  edit:changed()
end

local KEYS = [==[
Notes
  Cmd+N            a new note, in the folder selected
  F2               rename or move the note (type Folder/Name to move it)
  Cmd+Shift+F      search the notes' names and text: words, "a phrase",
                   -leftout and #tag; Down goes to what was found
  #tag in a note   makes it tagged (the # button lists the tags)
  Cmd+F            find in the note (Cmd+G next, Cmd+Shift+G before),
                   Cmd+R replace
  Cmd+E            switch between editing and reading

Writing (the Edit view)
  # ## ### then space   headings          - or 1. then space   lists
  > then space          a quote           --- then Enter       a rule
  Cmd+B / I / Shift+C   bold, italic, code
  [[                    link to a note: pick it, or type [[Name]]
  Cmd+K                 a link to a web address
  Cmd-click a link      follow it; a note that is not there yet is made
  drop files on a note  attach them: pictures show, files are linked

The notebook is saved by itself a moment after each change, once it has a
file. A .znb is a zip of the notes as Markdown files, in their folders,
with the attachments in attachments/: unzipped, it is a folder of notes
other Markdown programs open as well.]==]

local actions = {
  mnuNewBook = function()
    if confirmDiscard() then setNotebook(notebook.new(), nil) end
  end,
  mnuOpen = function()
    if not confirmDiscard() then return end
    local file = gui.openfile { title = "Open Notebook", filter = BOOK_FILTER }
    if file then openPath(file) end
  end,
  mnuPassword = setPassword,
  mnuSave = save,
  mnuSaveAs = saveAs,
  mnuImport = function()
    if not confirmDiscard() then return end
    local dir = gui.choosedir { title = "Import a Folder of Notes" }
    if not dir then return end
    local book, err = notebook.importFolder(dir)
    if not book then gui.msgbox("Could not import " .. dir .. ":\n" .. tostring(err), "ok", "micronotes") return end
    setNotebook(book, nil)
    nb.dirty = true
    updateTitle()
  end,
  mnuExport = function()
    flush()
    local dir = gui.choosedir { title = "Export the Notes into a Folder" }
    if not dir then return end
    local ok, err = nb:exportFolder(dir)
    if not ok then gui.msgbox("Could not export:\n" .. tostring(err), "ok", "micronotes") return end
    updateStatus("exported to " .. dir)
  end,
  mnuExit = function() frm:close() end,
  mnuNewNote = function() newNote() end,
  mnuNewFolder = newFolder,
  mnuRename = function() rename() end,
  mnuDelete = function() delete() end,
  mnuFind = function() frm.txtSearch:focus() end,
  mnuTags = function() frm.cmdTags:fire("onClick") end,
  mnuFindIn = function() find.open(false) end,
  mnuFindNext = function() find.findNext(false) end,
  mnuFindPrev = function() find.findNext(true) end,
  mnuReplace = function() find.open(true) end,
  mnuUndo = function() if mode == "edit" then edit.ed:undo() edit:changed() end end,
  mnuRedo = function() if mode == "edit" then edit.ed:redo() edit:changed() end end,
  mnuCut = function() clip("cut") end,
  mnuCopy = function() clip("copy") end,
  mnuPaste = function() clip("paste") end,
  mnuSelectAll = function()
    if mode == "edit" then edit.ed:selectAll() edit:moved()
    elseif mode == "read" then view:selectAll()
    else source:select(1, #source.text) end
  end,
  mnuWikiLink = insertWikiLink,
  mnuLink = editLink,
  mnuPicture = insertPicture,
  mnuFile = insertFile,
  mnuTable = function()
    local rows, cols = askTable()
    if not rows then return end
    if mode == "source" then
      local head, line, body = {}, {}, {}
      for k = 1, cols do head[k], line[k], body[k] = "Column " .. k, "---", "" end
      local text = { "| " .. table.concat(head, " | ") .. " |", "| " .. table.concat(line, " | ") .. " |" }
      for _ = 2, rows do text[#text + 1] = "| " .. table.concat(body, " | ") .. " |" end
      source:insert(table.concat(text, "\n") .. "\n")
      return
    end
    format(function(ed) ed:insertTable(rows, cols) end)
  end,
  mnuRowAbove = function() inTable(function(ed) ed:insertRow(false) end) end,
  mnuRowBelow = function() inTable(function(ed) ed:insertRow(true) end) end,
  mnuColLeft = function() inTable(function(ed) ed:insertColumn(false) end) end,
  mnuColRight = function() inTable(function(ed) ed:insertColumn(true) end) end,
  mnuDelRow = function() inTable(function(ed)
    if not ed:deleteRow() then updateStatus("a table keeps its first row") end
  end) end,
  mnuDelCol = function() inTable(function(ed)
    if not ed:deleteColumn() then updateStatus("a table keeps one column") end
  end) end,
  mnuAlignLeft = function() inTable(function(ed) ed:setAlign("left") end) end,
  mnuAlignCenter = function() inTable(function(ed) ed:setAlign("center") end) end,
  mnuAlignRight = function() inTable(function(ed) ed:setAlign("right") end) end,
  mnuAlignNone = function() inTable(function(ed) ed:setAlign(false) end) end,
  mnuToc = function()
    if mode == "source" then source:insert("[[toc]]\n") return end
    format(function(ed) ed:paste("[[toc]]\n\n") end)
  end,
  mnuRule = function() format(function(ed) ed:insertRule() end) end,
  mnuBold = function() format(function(ed) ed:toggle("b") end, "**") end,
  mnuItalic = function() format(function(ed) ed:toggle("i") end, "*") end,
  mnuCode = function() format(function(ed) ed:toggle("code") end, "`") end,
  mnuNormal = function() setStyle("p") end,
  mnuH1 = function() setStyle("h1") end,
  mnuH2 = function() setStyle("h2") end,
  mnuH3 = function() setStyle("h3") end,
  mnuQuote = function() setStyle("quote", true) end,
  mnuCodeBlock = function() setStyle("code", true) end,
  mnuBullets = function() setStyle("ul", true) end,
  mnuNumbers = function() setStyle("ol", true) end,
  mnuViewEdit = function() setMode("edit") end,
  mnuViewRead = function() setMode("read") end,
  mnuViewSource = function() setMode("source") end,
  mnuToggleView = function() setMode(mode == "read" and "edit" or "read") end,
  mnuLarger = function()
    settings.textSize = math.min(32, settings.textSize + 1)
    edit.textSize, view.textSize = settings.textSize, settings.textSize
    notebook.saveSettings(settings)
  end,
  mnuSmaller = function()
    settings.textSize = math.max(10, settings.textSize - 1)
    edit.textSize, view.textSize = settings.textSize, settings.textSize
    notebook.saveSettings(settings)
  end,
  mnuKeys = function() gui.msgbox(KEYS, "ok", "micronotes Shortcuts") end,
  mnuAbout = function()
    gui.msgbox("micronotes\n\nNotes in Markdown, linked to each other, kept in one .znb file with their pictures and files.",
      "ok", "About micronotes")
  end,
}

function frm.Menu1:onClick(name)
  local fn = actions[name]
  if fn then fn() end
  updateButtons()
end

---------------------------------------------------------------- the window

function frm:onClose()
  if not confirmDiscard() then return false end
  if find.visible then find:close() end
end

edit.textSize, view.textSize = settings.textSize, settings.textSize

-- A notebook named on the command line is opened, or the last one.
local start = arg and arg[1]
if not (start and start ~= "" and lfs.attributes(start, "mode") == "file") then
  start = settings.last ~= "" and lfs.attributes(settings.last, "mode") == "file" and settings.last or nil
end
if not (start and openPath(start)) then setNotebook(notebook.new(), nil) end
gui.after(0, focusView)

-- Exposed for the tests.
frm.openPath = openPath
frm.saveTo = saveTo
frm.open = open
frm.setMode = setMode
frm.follow = follow
frm.openFound = openFound
frm.results = function() return results end
frm.showResults = showResults
frm.moveInto = moveInto
frm.attach = attach
frm.actions = actions
frm.notebook = function() return nb, current, mode end
frm.flush = flush

return frm
