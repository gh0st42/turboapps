-- tlua -p apps/microreader -p tests tests/microreader_test.lua

local t = require "testing"
local bookmod = require "book"
local zip = require "zip"
local png = require "png"
local lfs = require "lfs"
local test, eq, ok = t.test, t.eq, t.ok

local root = os.tmpname()
os.remove(root)
lfs.mkdir(root)
bookmod.settingsFile = root .. "/settings.lua"

local function names(list) return table.concat(list, ",") end

-- A manual, as micronotes would keep one.
local PAGES = {
  ["index.md"] = "# The Manual\n\nStart with [[Install]], then [Usage](10 Usage/Basics.md#running).\n",
  ["01 Getting started/Install.md"] = "# Install\n\nCopy the file. See [[Basics#running]].\n\n![logo](attachments/logo.png)\n",
  ["01 Getting started/2 Setup.md"] = "# Setup\n\n## Colours\n\nPick colours.\n",
  ["01 Getting started/10 Next steps.md"] = "# Next steps\n\nRead on.\n",
  ["10 Usage/Basics.md"] = "# Basics\n\n## Running\n\nRun it. Run it again; running is easy.\n\n[the guide](attachments/guide.pdf)\n",
  ["2 Reference.md"] = "# Reference\n\nAll the colours.\n",
}

local function makeBook(file)
  local w = zip.create()
  w:add("notebook.json", '{ "app": "micronotes", "version": 1 }\n')
  for p, text in pairs(PAGES) do w:add(p, text) end
  w:add("attachments/logo.png", png.new(5, 2, "#00ff00"):encode())
  w:add("attachments/guide.pdf", "%PDF-")
  local bytes = w:close()
  local f = io.open(file, "wb")
  f:write(bytes)
  f:close()
end

local bookFile = root .. "/manual.znb"
makeBook(bookFile)

---------------------------------------------------------------- the book

test("names order pages, numbers by their value, and are shown without them", function()
  eq(bookmod.label("01 Getting started"), "Getting started")
  eq(bookmod.label("1. Intro.md"), "Intro")
  eq(bookmod.label("02-Setup.md"), "Setup")
  eq(bookmod.label("2025 Report.md"), "Report")
  eq(bookmod.label("Plain.md"), "Plain")
  ok(bookmod.before("2 Setup", "10 Next steps"))
  ok(bookmod.before("apple", "Banana"))
end)

test("pages in reading order, and the contents", function()
  local b = assert(bookmod.load(bookFile))
  eq(b.name, "manual")
  -- The home page first; numbered names next, by their numbers; then the
  -- rest, by name.
  eq(names(b:pages()), "index.md,01 Getting started/2 Setup.md,01 Getting started/10 Next steps.md,"
    .. "01 Getting started/Install.md,2 Reference.md,10 Usage/Basics.md")
  local items = b:items({ ["01 Getting started"] = true })
  eq(items[1], "The Manual") -- the home page, by its title
  eq(items[2][1], "Getting started")
  eq(items[2].open, true)
  eq(names(items[2][2]), "Setup,Next steps,Install")
  eq(items[3], "Reference")
  eq(items[4][1], "Usage")
  eq(select(2, b:at("Getting started/Setup")), "01 Getting started/2 Setup.md")
  eq(b:at("Usage"), "chapter")
  eq(b:treePath("10 Usage/Basics.md"), "Usage/Basics")
  eq(b:home(), "index.md")
  eq(b:neighbour("01 Getting started/2 Setup.md", 1), "01 Getting started/10 Next steps.md")
  eq(b:neighbour("01 Getting started/Install.md", 1), "2 Reference.md")
  eq(b:neighbour("10 Usage/Basics.md", 1), nil)
  eq(b:neighbour("index.md", -1), nil)
  eq(b:title("01 Getting started/2 Setup.md"), "Setup")
end)

test("links, pictures and files", function()
  local b = bookmod.load(bookFile)
  eq(b:resolve("Install"), "01 Getting started/Install.md")
  eq(b:resolve("Setup"), "01 Getting started/2 Setup.md") -- by its label too
  eq(b:resolve("Basics#running"), "10 Usage/Basics.md")
  eq(b:resolve("10 Usage/Basics"), "10 Usage/Basics.md")
  eq(b:resolve("Nothing"), nil)
  eq(select(2, bookmod.linkTarget("Basics.md#running")), "running")
  eq(bookmod.linkTarget("https://x.org"), nil)
  eq(b:picture("attachments/logo.png").width, 5)
  eq(b:file("attachments/guide.pdf"), "attachments/guide.pdf")
end)

test("the index and the search", function()
  local b = bookmod.load(bookFile)
  local found = b:lookup("run")
  eq(found[1].text, "Running")
  eq(found[1].anchor, "running")
  eq(found[1].page, "10 Usage/Basics.md")
  local col = b:lookup("colour")
  eq(col[1].text, "Colours")
  -- A page is in the index once, by its title.
  local setup = b:lookup("setup")
  eq(#setup, 1)
  eq(setup[1].anchor, nil)
  local hits = b:search("run")
  eq(hits[1].page, "10 Usage/Basics.md")
  eq(hits[1].hits, 4)
  eq(#b:search("colours"), 2)
  eq(#b:search("colours pick"), 1)
  eq(#b:search("zebra"), 0)
end)

test("not a book", function()
  local f = io.open(root .. "/empty.znb", "wb")
  local w = zip.create()
  w:add("notebook.json", "{}")
  f:write(w:close())
  f:close()
  local b, err = bookmod.load(root .. "/empty.znb")
  eq(b, nil)
  ok(err:find("no pages"))
end)

---------------------------------------------------------------- the form

local gui = require "gui"
gui.openurl = function(url) opened = url end -- not the real one

local frm = require "forms.MicroReader"

test("form: a book opens at its home page", function()
  ok(frm.openPath(bookFile))
  local _, page = frm.state()
  eq(page, "index.md")
  eq(frm.lblPage.caption, "The Manual")
  eq(frm.vwPage.text, PAGES["index.md"])
  eq(frm.cmdBack.enabled, false)
  eq(frm.cmdPrev.enabled, false)
  eq(frm.cmdNext.enabled, true)
end)

test("form: links, back and forward", function()
  frm.openPath(bookFile)
  frm.vwPage:fire("onLink", "Install.md")
  eq(select(2, frm.state()), "01 Getting started/Install.md")
  eq(frm.treContents.path, "Getting started/Install")
  eq(frm.vwPage.pictures["attachments/logo.png"].width, 5)
  frm.vwPage:fire("onLink", "Basics.md#running")
  eq(select(2, frm.state()), "10 Usage/Basics.md")
  frm.back()
  eq(select(2, frm.state()), "01 Getting started/Install.md")
  frm.back()
  eq(select(2, frm.state()), "index.md")
  eq(frm.cmdBack.enabled, false)
  frm.forward()
  eq(select(2, frm.state()), "01 Getting started/Install.md")
  -- Files of the book open in their own program; the web is the view's.
  frm.vwPage:fire("onLink", "attachments/guide.pdf")
  ok(opened and opened:match("guide%.pdf$"), tostring(opened))
  eq(frm.vwPage:fire("onLink", "https://example.com"), false)
end)

test("form: the contents, index and search open pages", function()
  frm.openPath(bookFile)
  frm.treContents.path = "Reference"
  frm.treContents:fire("onChange")
  eq(select(2, frm.state()), "2 Reference.md")
  frm.txtIndex.text = "colo"
  frm.txtIndex:fire("onChange")
  frm.txtIndex:fire("onKey", "Enter")
  eq(select(2, frm.state()), "01 Getting started/2 Setup.md")
  frm.txtSearch.text = "running"
  frm.txtSearch:fire("onKey", "Enter")
  eq(select(2, frm.state()), "10 Usage/Basics.md")
  ok(frm.lstResults.items[1]:find("Basics"), tostring(frm.lstResults.items[1]))
  frm.cmdPrev:fire("onClick")
  eq(select(2, frm.state()), "2 Reference.md")
  frm.cmdNext:fire("onClick")
  eq(select(2, frm.state()), "10 Usage/Basics.md")
  eq(frm.cmdNext.enabled, false)
end)

test("form: a topic opens at its page", function()
  ok(frm.openPath(bookFile, "Setup#colours"))
  eq(select(2, frm.state()), "01 Getting started/2 Setup.md")
  ok(frm.goTo("Basics"))
  eq(frm.goTo("Nowhere"), false)
end)

test("form: an encrypted book asks for its password", function()
  local gui = require "gui"
  local realBox = gui.passwordbox
  local file = root .. "/locked.znb"
  local w = zip.create { password = "pw" }
  w:add("notebook.json", '{ "app": "micronotes", "version": 1 }\n')
  for p, text in pairs(PAGES) do w:add(p, text) end
  local f = io.open(file, "wb") f:write(w:close()) f:close()
  local b, why, locked = bookmod.load(file)
  eq(b, nil) eq(locked, "locked") ok(why:find("password"), why)
  eq(select(3, bookmod.load(file, "bad")), "locked")
  ok(bookmod.load(file, "pw") ~= nil)
  local answers, asked = { "bad", "pw" }, 0
  gui.passwordbox = function() asked = asked + 1 return answers[asked] end
  ok(frm.openPath(file))
  eq(asked, 2)
  eq(select(2, frm.state()), "index.md")
  gui.passwordbox = function() return nil end
  ok(not frm.openPath(file), "cancelled")
  gui.passwordbox = realBox
end)

t.done("microreader")
