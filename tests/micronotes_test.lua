-- tlua -p apps/micronotes -p tests tests/micronotes_test.lua

local t = require "testing"
local notebook = require "notebook"
local png = require "png"
local zip = require "zip"
local lfs = require "lfs"
local test, eq, ok = t.test, t.eq, t.ok

local root = os.tmpname()
os.remove(root)
lfs.mkdir(root)
notebook.settingsFile = root .. "/settings.lua"

local function picture()
  local img = png.new(4, 3, "#ff0000")
  return img:encode()
end

local function names(list) return table.concat(list, ",") end

---------------------------------------------------------------- the notebook

test("a new notebook has a note to start from", function()
  local nb = notebook.new()
  eq(names(nb:notePaths()), "Ideas.md,Welcome.md")
  eq(nb.open, "Welcome.md")
  eq(names(nb:backlinks("Ideas.md")), "Welcome.md")
  eq(names(nb:backlinks("Welcome.md")), "Ideas.md")
end)

test("paths", function()
  eq(notebook.clean("a//b/./c.md"), "a/b/c.md")
  eq(notebook.clean("../x.md"), nil)
  eq(notebook.clean("a\\b.md"), "a/b.md")
  eq(notebook.title("Projects/Road map.md"), "Road map")
  eq(notebook.treePath("Projects/Road map.md"), "Projects/Road map")
  eq(notebook.treePath("attachments/a.png"), "attachments/a.png")
  ok(notebook.validName("Ideas 2"))
  eq(notebook.validName("a/b"), false)
  eq(notebook.validName("[x]"), false)
  eq(notebook.validName(".hidden"), false)
  eq(notebook.linkTarget("Page Name.md"), "Page Name")
  eq(notebook.linkTarget("Projects/Plan.md#goals"), "Projects/Plan")
  eq(notebook.linkTarget("https://example.com"), nil)
  eq(notebook.linkTarget("attachments/a.pdf"), nil)
end)

test("notes, folders and the tree", function()
  local nb = notebook.new(false)
  local a = nb:createNote("", "Alpha")
  local b = nb:createNote("Projects", "Beta", "# Beta\n\nsee [[Alpha]]\n")
  local c = nb:createNote("Projects", "Beta")
  eq(c, "Projects/Beta 1.md")
  nb:createFolder("", "Empty")
  nb.files["attachments/x.png"] = picture()
  local items = nb:items({ Projects = true })
  -- Folders first, then notes, then files.
  eq(items[1][1], "attachments")
  eq(items[2][1], "Empty")
  eq(items[3][1], "Projects")
  eq(items[3].open, true)
  eq(names(items[3][2]), "Beta,Beta 1")
  eq(items[4], "Alpha")
  eq(select(2, nb:at("Projects/Beta")), b)
  eq(nb:at("Projects"), "folder")
  eq(nb:at("attachments/x.png"), "file")
  eq(nb:at("nothing"), nil)
  -- Only some notes, in their folders, opened.
  local some = nb:items({}, { b })
  eq(#some, 1)
  eq(some[1][1], "Projects")
  eq(names(some[1][2]), "Beta")
  eq(a, "Alpha.md")
end)

test("links are found by name, the note's own folder first", function()
  local nb = notebook.new(false)
  nb:createNote("", "Plan")
  nb:createNote("Work", "Plan")
  local other = nb:createNote("Work", "Notes", "[[Plan]] and [[Home|home page]] and [x](Other.md)\n")
  eq(nb:resolve("Plan", other), "Work/Plan.md")
  eq(nb:resolve("Plan", "Top.md"), "Plan.md")
  eq(nb:resolve("Work/Plan"), "Work/Plan.md")
  eq(nb:resolve("plan#goals", other), "Work/Plan.md")
  eq(nb:resolve("Nowhere"), nil)
  eq(names(nb:backlinks("Work/Plan.md")), "Work/Notes.md")
  eq(names(nb:backlinks("Plan.md")), "")
end)

test("renaming and moving keep links working", function()
  local nb = notebook.new(false)
  local idea = nb:createNote("", "Idea")
  nb:createNote("", "Index", "See [[Idea]], [[idea|this]] and [[Idea#top]].\n")
  local moved = nb:move(idea, "Archive/Old idea")
  eq(moved, "Archive/Old idea.md")
  eq(nb.notes["Index.md"], "See [[Old idea]], [[Old idea|this]] and [[Old idea#top]].\n")
  eq(names(nb:backlinks(moved)), "Index.md")
  local _, err = nb:move("Index.md", "Archive/Old idea")
  ok(err and err:find("there already"), tostring(err))
  -- A folder moves with everything in it.
  nb:move("Archive", "Old/Archive")
  ok(nb.notes["Old/Archive/Old idea.md"])
  -- A file moves, and the notes showing it follow.
  nb.files["attachments/p.png"] = picture()
  nb:setText("Index.md", "![p](attachments/p.png)\n")
  nb:move("attachments/p.png", "attachments/q.png")
  eq(nb.notes["Index.md"], "![p](attachments/q.png)\n")
  nb:remove("Old")
  eq(names(nb:notePaths()), "Index.md")
end)

test("attachments", function()
  local nb = notebook.new(false)
  local p = nb:attach("/some/where/red dot.png", picture())
  eq(p, "attachments/red dot.png")
  eq(nb:attach("red dot.png", "x"), "attachments/red dot 1.png")
  eq(nb:picture("attachments/red%20dot.png").width, 4)
  eq(nb:pictures("Notes/a.md")["attachments/red dot.png"].height, 3)
  eq(nb:picture("nothing.png"), nil)
  nb:createNote("", "A", "![d](attachments/red dot.png)\n")
  eq(names(nb:unused()), "attachments/red dot 1.png")
end)

test("tags: written in the text or the front matter, not in code or headings", function()
  local tags = notebook.tagsOf("# Title #notatag\n\nSome words #Cooking and #home/garden, #2024 is not one, #-no.\n"
    .. "A link [x](a.md#section) and (#anchor) do not count; `#incode` neither.\n\n```\n#fenced\n```\n#last-one\n")
  eq(table.concat(tags, ","), "cooking,home/garden,last-one")
  eq(table.concat(notebook.tagsOf("---\ntags: [Alpha, beta]\n---\n\ntext #gamma\n"), ","), "alpha,beta,gamma")
  eq(table.concat(notebook.tagsOf("---\ntags: one, two\n---\n"), ","), "one,two")
  eq(table.concat(notebook.tagsOf("---\ntags:\n  - listed\n  - \"quoted\"\ntitle: x\n---\n#after\n"), ","), "after,listed,quoted")
  eq(#notebook.tagsOf("no tags here\n"), 0)
  eq(notebook.linkTags("a #tag and `#code` and #Other/Sub.\n"), "a [#tag](tag:tag) and `#code` and [#Other/Sub](tag:other/sub).\n")
  eq(notebook.linkTags("nothing\n"), "nothing\n")
  local nb = notebook.new(false)
  nb:createNote("", "One", "# One\n\n#home/garden #cook\n")
  nb:createNote("", "Two", "#home and #cook again\n")
  nb:createNote("Sub", "Three", "untagged\n")
  local list = nb:tags()
  local seen = {}
  for _, t in ipairs(list) do seen[t.tag] = t.count end
  eq(seen["home"], 2, "a tag inside counts for the one it is in")
  eq(seen["home/garden"], 1); eq(seen.cook, 2)
  eq(list[1].tag, "cook"); eq(list[1].count, 2)
end)

test("find: words, phrases, minus words and tags, the likeliest first, with a snippet", function()
  local nb = notebook.new(false)
  nb:createNote("", "Eggs", "# Eggs\n\nBoil the eggs. Eggs are good. #cook\n")
  nb:createNote("", "Shopping", "milk\n\nbuy eggs and bread\n\n#home\n")
  nb:createNote("", "Bread", "Knead the dough for bread.\n\n#cook #home\n")
  nb:createNote("", "Notes", "Nothing about food.\n")
  local function paths(q) local out = {} for i, r in ipairs(nb:find(q)) do out[i] = r.title end return table.concat(out, ",") end
  eq(paths("eggs"), "Eggs,Shopping", "the title and the heading first")
  eq(paths("EGGS bread"), "Shopping")
  eq(paths("bread"), "Bread,Shopping")
  eq(paths('"buy eggs"'), "Shopping")
  eq(paths("bread -eggs"), "Bread")
  eq(paths("#cook"), "Bread,Eggs")
  eq(paths("tag:home"), "Bread,Shopping")
  eq(paths("bread #home"), "Bread,Shopping")
  eq(paths("#cook #home"), "Bread")
  eq(paths("zebra"), "")
  eq(paths(""), "")
  eq(paths("   "), "")
  local r = nb:find("dough")[1]
  eq(r.path, "Bread.md"); eq(r.count, 1); eq(r.term, "dough")
  eq(r.snippet, "Knead the dough for bread. #cook #home")
  ok(not nb:find("eggs")[1].snippet:find("# Eggs", 1, true), "the # of a heading is left out")
  r = nb:find("eggs")[1]
  eq(r.title, "Eggs"); ok(r.score > nb:find("eggs")[2].score)
  ok(r.snippet:find("eggs", 1, true), r.snippet)
  r = nb:find("#home")[1]
  ok(r.snippet ~= "", "a tag search shows the first words")
  local long = notebook.new(false)
  long:createNote("", "Long", ("word "):rep(40) .. "needle " .. ("more "):rep(40) .. "\n")
  local sn = long:find("needle")[1].snippet
  ok(sn:find("^…") and sn:find("…$") and sn:find("needle", 1, true) and #sn < 120, sn)
end)

test("search", function()
  local nb = notebook.new(false)
  nb:createNote("", "Shopping", "milk, eggs\n")
  nb:createNote("", "Recipes", "pancakes need Eggs\n")
  nb:createNote("", "Eggs", "a note\n")
  eq(names(nb:search("eggs")), "Eggs.md,Recipes.md,Shopping.md")
  eq(names(nb:search("zebra")), "")
end)

test("a .znb is a zip of the notes, in their folders", function()
  local nb = notebook.new(false)
  nb:createNote("", "Home", "# Home\n\n[[Work/Plan]]\n")
  nb:createNote("Work", "Plan", "# Plan\n\n![dot](attachments/dot.png)\n")
  nb:createFolder("", "Empty")
  nb:attach("dot.png", picture())
  nb.open = "Work/Plan.md"
  local file = root .. "/book.znb"
  ok(nb:save(file))
  eq(nb.dirty, false)
  local z = zip.open(file)
  eq(names(z:list()), "notebook.json,Home.md,Work/Plan.md,attachments/dot.png")
  eq(z:info("Home.md").method, "deflate")
  eq(z:info("attachments/dot.png").method, "store")
  local back = assert(notebook.load(file))
  eq(back.notes["Work/Plan.md"], "# Plan\n\n![dot](attachments/dot.png)\n")
  eq(back.open, "Work/Plan.md")
  ok(back.folders.Empty)
  eq(back:picture("attachments/dot.png").width, 4)
  eq(notebook.load(root .. "/missing.znb"), nil)
  local f = io.open(root .. "/bad.znb", "wb") f:write("not a zip") f:close()
  local none, err = notebook.load(root .. "/bad.znb")
  eq(none, nil)
  ok(tostring(err):find("not a notebook"))
end)

test("folders of notes come in and go out", function()
  local nb = notebook.new(false)
  nb:createNote("Sub", "Deep", "deep\n")
  nb:attach("a.txt", "hello")
  local out = root .. "/vault"
  lfs.mkdir(out)
  ok(nb:exportFolder(out))
  local f = io.open(out .. "/Sub/Deep.md") eq(f:read("*a"), "deep\n") f:close()
  local back = assert(notebook.importFolder(out))
  eq(back.notes["Sub/Deep.md"], "deep\n")
  eq(back.files["attachments/a.txt"], "hello")
  eq(back.open, "Sub/Deep.md")
end)

---------------------------------------------------------------- the form

-- The form asks nothing while it is tested: a notebook with changes is
-- left without saving.
local gui = require "gui"
gui.msgbox = function() return "no" end

local frm = require "forms.MicroNotes"
local picker = require "forms.LinkPicker"
local pickWith -- what the picker answers, in place of asking
picker.pick = function() return pickWith end

local edit = frm.edNote

test("form: it starts reading", function()
  eq(select(3, frm.notebook()), "read")
  eq(frm.vwNote.visible, true)
  eq(frm.edNote.visible, false)
end)

local function keys(s)
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do edit:fire("onKey", ch, ch) end
end

local function fresh()
  frm.actions.mnuNewBook()
  frm.setMode("edit")
  return frm.notebook()
end

test("form: the first note shows, and typing goes into it", function()
  local nb, current, mode = fresh()
  eq(current, "Welcome.md")
  eq(mode, "edit")
  eq(frm.treNotes.path, "Welcome")
  eq(frm.lblTitle.caption, "Welcome")
  edit.ed:moveToDocument(1)
  edit:moved()
  edit:fire("onKey", "Enter", "")
  keys("More text")
  frm.flush()
  ok(nb.notes["Welcome.md"]:find("More text\n$"), nb.notes["Welcome.md"])
  ok(frm.caption:find("^•"), frm.caption)
end)

test("form: [[Name]] typed becomes a link, and [[ asks for the note", function()
  local nb = fresh()
  edit.ed:moveToDocument(1)
  edit:moved()
  edit:fire("onKey", "Enter", "")
  keys("see [[Ideas]] now")
  frm.flush()
  ok(nb.notes["Welcome.md"]:find("see %[%[Ideas%]%] now\n$"), nb.notes["Welcome.md"])
  pickWith = "Ideas"
  keys(" and [[")
  pickWith = nil
  keys(" too")
  frm.flush()
  ok(nb.notes["Welcome.md"]:find("and %[%[Ideas%]%] too\n$"), nb.notes["Welcome.md"])
  -- Cancelled, [[ stays as it was typed.
  keys(" [[")
  frm.flush()
  ok(nb.notes["Welcome.md"]:find("\\%[\\%[\n$"), nb.notes["Welcome.md"])
end)

test("form: links go to notes, made when they are not there yet", function()
  local nb = fresh()
  frm.follow("Ideas.md")
  eq(select(2, frm.notebook()), "Ideas.md")
  eq(frm.lblBacklinks.caption, "1 backlink")
  frm.follow("Later.md")
  eq(select(2, frm.notebook()), "Later.md")
  eq(nb.notes["Later.md"], "# Later\n")
  eq(frm.treNotes.path, "Later")
end)

test("form: three views of one note", function()
  local nb = fresh()
  frm.open("Ideas.md")
  frm.setMode("source")
  eq(frm.txtSource.visible, true)
  eq(frm.edNote.visible, false)
  eq(frm.txtSource.text, nb.notes["Ideas.md"])
  frm.txtSource.text = "# Ideas\n\nchanged in the source\n"
  frm.txtSource:fire("onChange")
  frm.setMode("read")
  eq(frm.vwNote.visible, true)
  eq(nb.notes["Ideas.md"], "# Ideas\n\nchanged in the source\n")
  eq(frm.vwNote.text, nb.notes["Ideas.md"])
  frm.setMode("edit")
  eq(edit:markdown(), "# Ideas\n\nchanged in the source\n")
  frm.actions.mnuToggleView()
  eq(select(3, frm.notebook()), "read")
  frm.actions.mnuToggleView()
  eq(select(3, frm.notebook()), "edit")
end)

test("form: pictures and files go in at the caret, and into the notebook", function()
  local nb = fresh()
  local pic = root .. "/photo.png"
  local f = io.open(pic, "wb") f:write(picture()) f:close()
  local doc = root .. "/notes.txt"
  f = io.open(doc, "wb") f:write("plain") f:close()
  frm.open("Ideas.md")
  edit.ed:moveToDocument(1)
  edit:moved()
  frm.attach({ pic, doc })
  frm.flush()
  ok(nb.files["attachments/photo.png"])
  eq(nb.files["attachments/notes.txt"], "plain")
  ok(nb.notes["Ideas.md"]:find("!%[photo.png%]%(attachments/photo.png%)"), nb.notes["Ideas.md"])
  ok(nb.notes["Ideas.md"]:find("%[notes.txt%]%(attachments/notes.txt%)"), nb.notes["Ideas.md"])
  eq(edit.pictures["attachments/photo.png"].width, 4)
end)

test("form: a note found by searching opens to read", function()
  local nb = fresh()
  local before = nb.notes["Ideas.md"]
  frm.txtSearch.text = "ideas"
  frm.txtSearch:fire("onChange")
  for _ = 1, 3 do frm.txtSearch:fire("onKey", "Enter") end
  local _, current, mode = frm.notebook()
  eq(current, "Ideas.md")
  eq(mode, "read")
  eq(frm.vwNote.visible, true)
  eq(nb.notes["Ideas.md"], before)
  -- Picked in the tree while searching, too.
  frm.treNotes.path = "Welcome"
  frm.treNotes:fire("onChange")
  eq(select(2, frm.notebook()), "Welcome.md")
  eq(select(3, frm.notebook()), "read")
  frm.txtSearch:fire("onKey", "Escape")
  frm.setMode("edit")
end)

test("form: searching lists the notes with what they say, and tags are links", function()
  local gui = require "gui"
  local nb = fresh()
  nb:createNote("", "Pasta", "# Pasta\n\nBoil water for the pasta. #zzcook #dinner\n")
  nb:createNote("", "Soup", "Chop onions. #zzcook\n")
  frm.showResults()
  eq(frm.lstResults.visible, false); eq(frm.treNotes.visible, true)
  frm.txtSearch.text = "#zzcook"
  frm.txtSearch:fire("onChange")
  eq(frm.lstResults.visible, true); eq(frm.treNotes.visible, false, "the list takes the tree's place")
  eq(#frm.lstResults.items, 2)
  ok(frm.lstResults.items[1]:find("^Pasta"), frm.lstResults.items[1])
  ok(frm.lstResults.items[1]:find("Boil water", 1, true), "a piece of the text")
  ok(frm.lblStatus.caption:find("2 notes"), frm.lblStatus.caption)
  -- Picking one opens it to read, at the place found.
  frm.lstResults.selected = 2
  frm.lstResults:fire("onChange")
  eq(select(2, frm.notebook()), "Soup.md"); eq(select(3, frm.notebook()), "read")
  eq(frm.vwNote:selectedText(), "#zzcook")
  ok(frm.lblStatus.caption:find("#zzcook", 1, true), "the note's tags are in the status")
  -- Words find what a note says, and a search with no match says so.
  frm.txtSearch.text = "onions"
  frm.txtSearch:fire("onChange")
  eq(#frm.lstResults.items, 1)
  eq(frm.txtSearch:fire("onKey", "Down"), true)
  frm.txtSearch.text = "qqqnothing"
  frm.txtSearch:fire("onChange")
  eq(#frm.lstResults.items, 0)
  ok(frm.lblStatus.caption:find("no note has that"), frm.lblStatus.caption)
  -- A #tag in a note being read is a link: following it searches for the tag.
  frm.txtSearch:fire("onKey", "Escape")
  eq(frm.lstResults.visible, false); eq(frm.treNotes.visible, true); eq(frm.txtSearch.text, "")
  ok(frm.vwNote.text:find("[#zzcook](tag:zzcook)", 1, true), frm.vwNote.text)
  eq(frm.vwNote:fire("onLink", "tag:zzcook"), true)
  eq(frm.txtSearch.text, "#zzcook"); eq(#frm.lstResults.items, 2)
  -- The tag menu lists them with their counts, and picking one searches.
  local menu
  local realPopup = gui.popup
  gui.popup = function(items) menu = items end
  frm.cmdTags:fire("onClick")
  local entry
  for _, it in ipairs(menu) do
    if type(it) == "table" and it[1]:find("#zzcook", 1, true) then entry = it end
  end
  ok(entry and entry[1]:find("(2)", 1, true), "the tag and how many notes have it")
  frm.txtSearch.text = ""
  frm.txtSearch:fire("onChange")
  entry[2]()
  eq(frm.txtSearch.text, "#zzcook")
  frm.txtSearch.text = ""
  frm.txtSearch:fire("onChange")
  gui.popup = realPopup
  frm.setMode("edit")
end)

test("form: notes dragged in the tree move into folders", function()
  local nb = fresh()
  local plan = nb:createNote("Work", "Plan", "# Plan\n\nsee [[Ideas]]\n")
  frm.open("Ideas.md")
  local tree = frm.treNotes
  -- Dragged from the tree, a node carries its path.
  tree.path = "Ideas"
  local carried = tree:fire("onDrag")
  eq(carried, "micronotes:Ideas")
  -- Dropped on a folder, it goes in; links to it still work.
  tree:fire("onDrop", carried, { carried }, 10, 10, "Work")
  eq(nb.notes["Work/Ideas.md"] ~= nil, true)
  eq(nb.notes["Ideas.md"], nil)
  eq(select(2, frm.notebook()), "Work/Ideas.md")
  eq(nb:resolve("Ideas", plan), "Work/Ideas.md")
  -- Dropped on a note, it goes into that note's folder: here the top.
  tree:fire("onDrop", "micronotes:Work/Ideas", {}, 10, 10, "Welcome")
  eq(nb.notes["Ideas.md"] ~= nil, true)
  -- A folder moves with what is in it, but not into itself.
  nb:createFolder("", "Archive")
  tree:fire("onDrop", "micronotes:Work", {}, 10, 10, "Archive")
  eq(nb.notes["Archive/Work/Plan.md"] ~= nil, true)
  local _, err = frm.moveInto("Archive", "Archive/Work")
  ok(err and err:find("itself"), tostring(err))
  -- Below the nodes it goes to the top.
  tree:fire("onDrop", "micronotes:Archive/Work/Plan", {}, 10, 300, nil)
  eq(nb.notes["Plan.md"] ~= nil, true)
  -- Files from elsewhere come in where they land, Markdown as notes.
  local md = root .. "/Dropped.md"
  local f = io.open(md, "wb") f:write("# Dropped\n") f:close()
  tree:fire("onDrop", md .. "\n", { md }, 10, 10, "Archive")
  eq(nb.notes["Archive/Dropped.md"], "# Dropped\n")
  eq(select(2, frm.notebook()), "Archive/Dropped.md")
end)

test("form: a note dropped on the one open is a link to it", function()
  local nb = fresh()
  frm.open("Ideas.md")
  edit.ed:moveToDocument(1)
  edit:moved()
  edit:fire("onDrop", "micronotes:Welcome", { "micronotes:Welcome" })
  frm.flush()
  ok(nb.notes["Ideas.md"]:find("%[%[Welcome%]%]"), nb.notes["Ideas.md"])
end)

test("form: a table is made in the note and changed from the Table menu", function()
  local gui = require "gui"
  gui.inputbox = function() return "2 x 2" end
  fresh()
  edit.ed:setCaret { b = #edit.ed.blocks, o = 0 }
  edit.ed:moveToDocument(1)
  frm.actions.mnuTable()
  ok(edit.ed.cell, "the caret is in the first cell")
  keys("A")
  edit:fire("onKey", "Tab", "\t")
  keys("B")
  ok(edit:markdown():find("| A | B |\n| --- | --- |\n|  |  |\n"), edit:markdown())
  frm.actions.mnuRowBelow()
  frm.actions.mnuColLeft()
  local t = edit.ed:tableAt()
  eq(#t.rows, 3) eq(#t.align, 3)
  frm.actions.mnuAlignCenter()
  ok(edit:markdown():find(":---:", 1, true), edit:markdown())
  frm.actions.mnuDelCol()
  frm.actions.mnuDelRow()
  eq(#t.rows, 2) eq(#t.align, 2)
end)

test("form: an encrypted notebook needs its password, and keeps it", function()
  local gui = require "gui"
  local realBox = gui.passwordbox
  fresh()
  local file = os.tmpname()
  gui.passwordbox = function() return "pw" end
  frm.actions.mnuPassword()
  ok(frm.caption:find("(encrypted)", 1, true), frm.caption)
  ok(frm.saveTo(file), "saved")
  local f = io.open(file, "rb") local raw = f:read("*a") f:close()
  ok(not raw:find("This is a notebook", 1, true), "no note is readable in it")
  local nb, why, locked = notebook.load(file)
  eq(nb, nil) eq(locked, "locked") ok(why:find("password"), why)
  eq(select(3, notebook.load(file, "bad")), "locked")
  local answers, asked = { "bad", "pw" }, 0
  gui.passwordbox = function() asked = asked + 1 return answers[asked] end
  fresh()
  ok(frm.openPath(file), "opened")
  eq(asked, 2)
  eq(select(2, frm.notebook()), "Welcome.md")
  -- It is saved with the password again, by the form and by the notebook.
  ok(frm.saveTo(file))
  eq(select(3, notebook.load(file)), "locked")
  ok(notebook.load(file, "pw") ~= nil)
  -- Changing it writes the file at once; Remove Password asks, and then does.
  gui.passwordbox = function() return "second" end
  frm.actions.mnuPassword()
  eq(select(3, notebook.load(file, "pw")), "locked", "the old password no longer opens it")
  ok(notebook.load(file, "second") ~= nil, "the new one does")
  ok(frm.lblStatus.caption:find("and saved", 1, true), frm.lblStatus.caption)
  local realMsg = gui.msgbox
  gui.msgbox = function() return "no" end
  frm.actions.mnuRemovePassword()
  eq(select(3, notebook.load(file)), "locked", "refused: still encrypted")
  gui.msgbox = function() return "yes" end
  frm.actions.mnuRemovePassword()
  ok(notebook.load(file) ~= nil, "readable without one")
  ok(not frm.caption:find("encrypted", 1, true), frm.caption)
  local said
  gui.msgbox = function(text) said = text return "ok" end
  frm.actions.mnuRemovePassword()
  ok(said:find("no password"), said)
  gui.msgbox = realMsg
  -- An empty password in Set Password takes it off as well.
  gui.passwordbox = function() return "again" end
  frm.actions.mnuPassword()
  eq(select(3, notebook.load(file)), "locked")
  gui.passwordbox = function() return "" end
  frm.actions.mnuPassword()
  ok(notebook.load(file) ~= nil, "readable without one")
  gui.passwordbox = realBox
  os.remove(file)
end)

test("finder: finds, counts and replaces in plain text", function()
  local finder = require "finder"
  eq(select(1, finder.find("one two one", "one", 2)), 9)
  eq(select(1, finder.find("one two one", "one", 10)), 1, "round again")
  eq(finder.find("one two one", "one", 10, { wrap = false }), nil)
  eq(select(1, finder.find("Cat cat", "cat", 1, { matchCase = true })), 5)
  eq(select(1, finder.find("category cat", "cat", 1, { whole = true })), 10)
  eq(select(1, finder.findBack("one two one", "one", 9)), 1)
  eq(select(1, finder.findBack("one two one", "one", 1)), 9, "round from the end")
  eq(finder.count("a b a b a", "a"), 3)
  eq(select(2, finder.count("a b a b a", "a", nil, 5)), 2)
  ok(finder.matches("Cat", "cat") and not finder.matches("Cat", "cat", { matchCase = true }))
  ok(not finder.matches("", "cat"))
  local text, n = finder.replaceAll("aXa Xa", "x", "yy")
  eq(text, "ayya yya"); eq(n, 2)
  eq(select(2, finder.replaceAll("aa", "a", "aa")), 2, "a replacement is not searched again")
end)

test("form: Find and Replace in the note's three views", function()
  local gui = require "gui"
  local findForm = require "forms.Find"
  local realMsg = gui.msgbox
  gui.msgbox = function() return "ok" end
  fresh()
  edit:load("The cat sat. A CAT here.\n\nOne cat more.\n")
  edit.ed:setCaret { b = 1, o = 0 }
  findForm.txtFind.text = "cat"
  findForm.txtReplace.text = "dog"
  frm.actions.mnuFindNext()
  eq(edit.ed:copyText(), "cat")
  ok(findForm.lblResult.caption:find("1 of 3"), findForm.lblResult.caption)
  findForm.cmdReplace:fire("onClick")
  ok(edit:markdown():find("The dog sat", 1, true), edit:markdown())
  findForm.cmdReplaceAll:fire("onClick")
  eq(edit:markdown(), "The dog sat. A dog here.\n\nOne dog more.\n")
  -- Read: finding, no replacing.
  frm.setMode("read")
  local view = frm.vwNote
  view.text = "alpha beta alpha\n"
  findForm.txtFind.text = "ALPHA"
  frm.actions.mnuFindNext()
  eq(view:selectedText(), "alpha")
  ok(findForm.lblResult.caption:find("1 of 2"), findForm.lblResult.caption)
  frm.actions.mnuFindPrev()
  ok(findForm.lblResult.caption:find("2 of 2"), findForm.lblResult.caption)
  findForm.cmdReplaceAll:fire("onClick")
  ok(findForm.lblResult.caption:find("Edit and Source"), findForm.lblResult.caption)
  eq(frm.vwNote.text, "alpha beta alpha\n")
  frm.setMode("edit")
  gui.msgbox = realMsg
end)

test("form: links to headings stay in the note", function()
  fresh()
  frm.open("Ideas.md")
  local before = select(2, frm.notebook())
  eq(frm.follow("#ideas"), false)
  eq(frm.edNote:fire("onLink", "#ideas"), false)
  eq(select(2, frm.notebook()), before)
end)

test("form: save, then open again", function()
  local nb = fresh()
  frm.follow("Saved.md")
  local file = root .. "/form.znb"
  ok(frm.saveTo(file))
  ok(not frm.caption:find("^•"), frm.caption)
  ok(frm.caption:find("^form %- micronotes"), frm.caption)
  fresh()
  ok(frm.openPath(file))
  local back, current = frm.notebook()
  eq(current, "Saved.md")
  ok(back.notes["Welcome.md"])
end)

t.done("micronotes")
