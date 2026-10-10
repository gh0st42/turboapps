-- The code behind MicroReader.form.lua: the controls are fields of the
-- form, by the names the layout gives them.
--
-- A notebook (.znb) read as a book, the way help files were: the contents
-- on the left with an index and a search beside it, the page on the right
-- (a MarkdownView), and back, forward, home and the pages before and after.
-- Nothing is ever changed. book.lua reads the notebook.
--
-- A program can open its help at a topic: tlua microreader.ztl manual.znb
-- "Settings#colours" opens that page at that heading.

local gui = require "gui"
local lfs = require "lfs"
local bookmod = require "book"

local frm = gui.load "MicroReader" --[[@as forms.MicroReader]]
local view, contents = frm.vwPage, frm.treContents

local book          -- the book open
local bookPath      -- its file
local page          -- the page shown, by its path in the book
local history, future = {}, {}
local openChapters = {}
local settings = bookmod.loadSettings()
local quiet = false
local lastFind = ""

local BOOK_FILTER = "Notebooks\t*.znb"

---------------------------------------------------------------- what shows

local function updateStatus(note)
  if not book then
    frm.lblStatus.caption = "  Open a notebook (.znb) to read it: File > Open Book."
    return
  end
  local pages = book:pages()
  local n = 0
  for i, p in ipairs(pages) do if p == page then n = i end end
  local parts = { ("page %d of %d"):format(n, #pages) }
  if note then parts[#parts + 1] = note end
  frm.lblStatus.caption = "  " .. table.concat(parts, "   ·   ")
end

local function updateButtons()
  frm.cmdBack.enabled = #history > 0
  frm.cmdForward.enabled = #future > 0
  frm.cmdPrev.enabled = book ~= nil and page ~= nil and book:neighbour(page, -1) ~= nil
  frm.cmdNext.enabled = book ~= nil and page ~= nil and book:neighbour(page, 1) ~= nil
  frm.cmdHome.enabled = book ~= nil
end

-- showContents shows the contents with the page's chapters open and the
-- page selected.
local function showContents()
  if not book then return end
  quiet = true
  local dir = page and bookmod.dirname(page) or ""
  while dir ~= "" do
    openChapters[dir] = true
    dir = bookmod.dirname(dir)
  end
  contents.items = book:items(openChapters)
  if page then contents.path = book:treePath(page) or "" end
  quiet = false
end

-- show shows a page, at a heading if anchor names one, and keeps where it
-- was to go back to unless back says this is going back.
local function show(p, anchor, how)
  if not book or not book.notes[p] then return false end
  if how ~= "history" and page and (p ~= page or anchor) then
    history[#history + 1] = { page = page }
    future = {}
  end
  page = p
  view.pictures = book:pictures(p)
  view.text = book.notes[p]
  if anchor and anchor ~= "" then view:scrollTo(anchor) end
  frm.lblPage.caption = book:title(p)
  frm.caption = book:title(p) .. " - " .. book.name .. " - microreader"
  showContents()
  updateButtons()
  updateStatus()
  settings.page = p
  bookmod.saveSettings(settings)
  return true
end

local function back()
  local h = table.remove(history)
  if not h then return end
  future[#future + 1] = { page = page }
  show(h.page, nil, "history")
end

local function forward()
  local h = table.remove(future)
  if not h then return end
  history[#history + 1] = { page = page }
  show(h.page, nil, "history")
end

local function neighbour(dir)
  if not page then return end
  local p = book:neighbour(page, dir)
  if p then show(p) end
end

-- goTo opens a topic as a link or the command line names it: "Page",
-- "Folder/Page.md", "Page#heading" or "#heading" on the page shown.
local function goTo(topic)
  if not book then return false end
  local target, anchor = bookmod.linkTarget(topic)
  if not target then
    if anchor and anchor ~= "" and page then return view:scrollTo(anchor) end
    return false
  end
  local p = book:resolve(target, page)
  if not p then return false end
  return show(p, anchor)
end

---------------------------------------------------------------- books

local function setBook(b, file, at)
  book, bookPath = b, file
  history, future, openChapters = {}, {}, {}
  page = nil
  frm.txtIndex.text = ""
  frm.txtSearch.text = ""
  frm.lstResults.items = {}
  frm.lstIndex.tag = book:index()
  local names = {}
  for i, e in ipairs(frm.lstIndex.tag) do names[i] = e.text end
  frm.lstIndex.items = names
  if not (at and goTo(at)) then show(book:home()) end
  history = {}
  updateButtons()
  settings.last = file
  bookmod.saveSettings(settings)
end

local function openPath(file, at)
  local b, err = bookmod.load(file)
  if not b then
    gui.msgbox("Could not open " .. file .. ":\n" .. tostring(err), "ok", "microreader")
    return false
  end
  setBook(b, file, at)
  return true
end

---------------------------------------------------------------- links

-- openAttachment opens a file of the book's in its own program, from a
-- copy in the temporary folder.
local function openAttachment(p)
  local dir = os.tmpname()
  os.remove(dir)
  lfs.mkdir(dir)
  local file = dir .. "/" .. bookmod.basename(p)
  local f = io.open(file, "wb")
  if not f then return end
  f:write(book.files[p])
  f:close()
  gui.openurl(file)
end

-- Links are the reader's to follow: to pages and headings of the book, to
-- its files, and out to the web, which the view opens itself.
function view:onLink(url)
  if not book then return false end
  if url:match("^%a[%w+.-]*:") then return false end
  if url:match("^#") then
    view:scrollTo(url)
    return true
  end
  local target = bookmod.linkTarget(url)
  if target then
    if not goTo(url) then updateStatus("this book has no page " .. target) end
    return true
  end
  local file = book:file(url, page)
  if file then openAttachment(file) else updateStatus("this book has no file " .. url) end
  return true
end

function view:onHover(url)
  updateStatus(url)
end

---------------------------------------------------------------- contents, index and search

function contents:onChange()
  if quiet or not book then return end
  local kind, p = book:at(self.path)
  if kind == "page" then show(p) end
end

function contents:onToggle(path, isOpen)
  local kind, p = book:at(path)
  if kind == "chapter" then openChapters[p] = isOpen or nil end
end

-- The index lists what starts with what is typed first, then what has it.
function frm.txtIndex:onChange()
  if not book then return end
  local found = book:lookup(self.text or "")
  frm.lstIndex.tag = found
  local names = {}
  for i, e in ipairs(found) do
    names[i] = e.text .. (e.anchor and ("   — " .. bookmod.label(e.page)) or "")
  end
  frm.lstIndex.items = names
  if #found > 0 then frm.lstIndex.selected = 1 end
end

local function openIndexEntry()
  local e = (frm.lstIndex.tag or {})[frm.lstIndex.selected or 0]
  if e then
    show(e.page, e.anchor)
    if e.anchor then view:scrollTo(e.anchor) end
  end
end

function frm.txtIndex:onKey(key)
  if key == "Enter" then openIndexEntry() return true end
  if key == "Down" then frm.lstIndex:focus() return true end
end

function frm.lstIndex:onChange() openIndexEntry() end
function frm.lstIndex:onDoubleClick() openIndexEntry() end

-- search lists the pages with every word, best first, with how often.
local function search()
  if not book then return end
  local text = frm.txtSearch.text or ""
  local found = book:search(text)
  frm.lstResults.tag = found
  local names = {}
  for i, r in ipairs(found) do names[i] = ("%s   (%d)"):format(book:title(r.page), r.hits) end
  frm.lstResults.items = names
  updateStatus(#found == 0 and ("no page has “" .. text .. "”") or (#found == 1 and "1 page" or (#found .. " pages")))
  if #found > 0 then frm.lstResults.selected = 1 end
  lastFind = text:match("^%s*(%S+)") or ""
end

local function openResult()
  local r = (frm.lstResults.tag or {})[frm.lstResults.selected or 0]
  if not r then return end
  show(r.page)
  -- The first word found is selected on the page.
  if lastFind ~= "" then view:search(lastFind) end
end

function frm.txtSearch:onKey(key)
  if key == "Enter" then search() openResult() return true end
  if key == "Down" then frm.lstResults:focus() return true end
end

function frm.lstResults:onChange() openResult() end
function frm.lstResults:onDoubleClick() openResult() end

---------------------------------------------------------------- buttons and menus

function frm.cmdBack:onClick() back() end
function frm.cmdForward:onClick() forward() end
function frm.cmdHome:onClick() if book then show(book:home()) end end
function frm.cmdPrev:onClick() neighbour(-1) end
function frm.cmdNext:onClick() neighbour(1) end

local HELP = [[
Reading
  Click a link to follow it: to another page, a heading, a file of the
  book's (it opens in its own program), or a web page.
  Back and Forward (Cmd+[ and Cmd+]) go through the pages seen; Home
  goes to the first; the page buttons (Ctrl+PageUp and Ctrl+PageDown)
  read on in the book's order.

Finding
  Contents (Cmd+1): the book's chapters and pages.
  Index (Cmd+2): every page and heading, as you type.
  Search (Cmd+3): the pages with all the words, best first.
  Cmd+F finds on the page shown, Cmd+G again.

A book is a notebook from micronotes, a .znb. Pages are in the order of
their names; a number at the start of one ("01 Intro") orders it and is
not shown. A program opens its help at a topic with:
  tlua microreader.ztl manual.znb "Page#heading"]]

local function findInPage(again)
  if not again or lastFind == "" then
    local text = gui.inputbox("Find on this page:", "Find", lastFind)
    if not text or text == "" then return end
    lastFind = text
  end
  if not view:search(lastFind) then updateStatus("“" .. lastFind .. "” is not on this page") end
end

local actions = {
  mnuOpen = function()
    local file = gui.openfile { title = "Open Book", filter = BOOK_FILTER }
    if file then openPath(file) end
  end,
  mnuExit = function() frm:close() end,
  mnuCopy = function() view:copy() end,
  mnuSelectAll = function() view:selectAll() end,
  mnuFind = function() findInPage(false) end,
  mnuFindNext = function() findInPage(true) end,
  mnuBack = back,
  mnuForward = forward,
  mnuHome = function() if book then show(book:home()) end end,
  mnuPrev = function() neighbour(-1) end,
  mnuNext = function() neighbour(1) end,
  mnuContents = function() frm.tabNav.selected = 1 contents:focus() end,
  mnuIndex = function() frm.tabNav.selected = 2 frm.txtIndex:focus() end,
  mnuSearch = function() frm.tabNav.selected = 3 frm.txtSearch:focus() end,
  mnuLarger = function()
    settings.textSize = math.min(32, settings.textSize + 1)
    view.textSize = settings.textSize
    bookmod.saveSettings(settings)
  end,
  mnuSmaller = function()
    settings.textSize = math.max(10, settings.textSize - 1)
    view.textSize = settings.textSize
    bookmod.saveSettings(settings)
  end,
  mnuHelp = function() gui.msgbox(HELP, "ok", "Using microreader") end,
  mnuAbout = function()
    gui.msgbox("microreader\n\nReads a micronotes notebook as a book: contents, index, search, and links, never changed.",
      "ok", "About microreader")
  end,
}

function frm.Menu1:onClick(name)
  local fn = actions[name]
  if fn then fn() end
end

function frm:onKey(key)
  if key == "Alt+Left" then back() return true end
  if key == "Alt+Right" then forward() return true end
end

function frm:onDrop(text, lines)
  local file = lines and lines[1]
  if file and lfs.attributes(file, "mode") == "file" then openPath(file) end
end
view.onDrop = function(_, text, lines) frm:fire("onDrop", text, lines) end

---------------------------------------------------------------- starting

view.textSize = settings.textSize

-- A book named on the command line opens, at the topic after it if one
-- is; else the last book, at the last page read.
local start, topic = arg and arg[1], arg and arg[2]
if not (start and start ~= "" and lfs.attributes(start, "mode") == "file") then
  start, topic = nil, nil
  if settings.last ~= "" and lfs.attributes(settings.last, "mode") == "file" then
    start, topic = settings.last, settings.page ~= "" and settings.page or nil
  end
end
if not (start and openPath(start, topic)) then
  view.text = "# microreader\n\nOpen a notebook to read it: **File > Open Book** (Cmd+O), or drop a `.znb` here.\n"
  updateButtons()
  updateStatus()
end
gui.after(0, function() view:focus() end)

-- Exposed for the tests.
frm.openPath = openPath
frm.goTo = goTo
frm.back, frm.forward = back, forward
frm.state = function() return book, page, #history, #future end

return frm
