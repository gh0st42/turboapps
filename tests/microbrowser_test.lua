-- tlua -p apps/microbrowser -p tests tests/microbrowser_test.lua
--
-- The requests go to servers this test runs itself, on 127.0.0.1: a Gopher
-- one, and a Gemini one with the certificates in tests/microbrowser/.

local t = require "testing"
local net = require "net"
local page = require "page"
local store = require "store"
local socket = require "socket"
local ssl = require "ssl"
local test, eq, ok = t.test, t.eq, t.ok

local root = os.tmpname()
os.remove(root)
require("lfs").mkdir(root)
store.file = root .. "/settings.lua"

---------------------------------------------------------------- servers

-- server answers requests a line each, as Gopher and Gemini ask: handler
-- gets the line and returns the answer. It runs a step at a time, as the
-- requests do, so one Lua state plays both ends.
local function server(handler, cert)
  local srv = assert(socket.bind("127.0.0.1", 0))
  srv:settimeout(0)
  local _, port = srv:getsockname()
  local s = { port = tonumber(port), lines = {}, cert = cert }
  local conns = {}
  local function serve(c)
    if s.cert then
      local n = s.cert
      c = assert(ssl.wrap(c, { mode = "server", protocol = "any",
        key = "tests/microbrowser/key" .. n .. ".pem", certificate = "tests/microbrowser/cert" .. n .. ".pem" }))
      c:settimeout(0)
      while true do
        local done, err = c:dohandshake()
        if done then break end
        if err ~= "wantread" and err ~= "wantwrite" then c:close() return end
        coroutine.yield()
      end
    end
    local got = ""
    local line
    while true do
      local data, err, partial = c:receive("*l", got)
      if data then line = data break end
      got = partial or got
      if err == "closed" then c:close() return end
      coroutine.yield()
    end
    s.lines[#s.lines + 1] = line
    local answer = handler(line)
    local i = 1
    while i <= #answer do
      local n, err, last = c:send(answer, i)
      if n then break end
      if err == "closed" then break end
      i = (last or i - 1) + 1
      coroutine.yield()
    end
    c:close()
  end
  function s.step()
    local c = srv:accept()
    if c then
      c:settimeout(0)
      conns[#conns + 1] = coroutine.create(function() serve(c) end)
    end
    for i = #conns, 1, -1 do
      local alive, err = coroutine.resume(conns[i])
      if not alive then error(err) end
      if coroutine.status(conns[i]) == "dead" then table.remove(conns, i) end
    end
  end
  return s
end

local servers = {}

-- pump runs the servers and a poll until the poll says it is done.
local function pump(poll)
  for _ = 1, 3000 do
    for _, s in ipairs(servers) do s.step() end
    if poll() then return true end
    socket.sleep(0.002)
  end
  error("it never finished")
end

local MENU = table.concat({
  "iWelcome to the test hole\tfake\t(NULL)\t0",
  "i  indented\tfake\t(NULL)\t0",
  "i\tfake\t(NULL)\t0",
  "1Things & stuff\t/things\t127.0.0.1\t%d",
  "0About this\t/about.txt\t127.0.0.1\t%d",
  "7Search here\t/search\t127.0.0.1\t%d",
  "hThe web\tURL:https://example.com/\t127.0.0.1\t%d",
  "9A file\t/file.bin\t127.0.0.1\t%d",
  "3Something failed\t\terror.host\t1",
  ".",
}, "\r\n") .. "\r\n"

local gopherSrv = server(function(line)
  local sel, words = line:match("^([^\t]*)\t?(.*)$")
  if sel == "" or sel == "/" then return (MENU:gsub("%%d", tostring(servers[1].port))) end
  if sel == "/about.txt" then return "This is a test.\r\nLine two.\r\n.\r\n" end
  if sel == "/things" then return "iThings\tfake\t(NULL)\t0\r\n.\r\n" end
  if sel == "/search" then return "iYou searched for " .. words .. "\tfake\t(NULL)\t0\r\n.\r\n" end
  if sel == "/file.bin" then return "\0\1\2binary" end
  return "3Not here\t\terror.host\t1\r\n.\r\n"
end)
servers[1] = gopherSrv

local CAPSULE = "# Test capsule\n\nHello *there* [x].\nSecond line.\n\n=> /next.gmi Next page\n=> gopher://example.org/ A hole\n=> https://example.com The web\n* one\n* two\n> quoted\n```ascii art\n  /\\_/\\\n ( o.o )\n```\n"

local geminiSrv = server(function(line)
  local path = line:match("^gemini://[^/]+(/[^?]*)") or "/"
  local query = line:match("%?(.*)$")
  if path == "/" then return "20 text/gemini\r\n" .. CAPSULE end
  if path == "/next.gmi" then return "20 text/gemini; charset=utf-8\r\n# Next\n\n=> / Back home\n" end
  if path == "/old" then return "31 /next.gmi\r\n" end
  if path == "/loop" then return "30 /loop\r\n" end
  if path == "/ask" then
    if query then return "20 text/plain\r\nYou said " .. net.unescape(query) .. "\n" end
    return "10 What is your name?\r\n"
  end
  if path == "/pic.png" then
    return "20 image/png\r\n" .. require("png").new(4, 3, "#ff0000"):encode()
  end
  if path == "/cert" then return "60 Show me yours\r\n" end
  return "51 Not found\r\n"
end, 1)
servers[2] = geminiSrv

local G = "gemini://127.0.0.1:" .. geminiSrv.port
local H = "gopher://127.0.0.1:" .. gopherSrv.port

---------------------------------------------------------------- addresses

test("addresses are read and written back", function()
  local u = net.parse("gemini://Example.org:1965/a/b.gmi?q=1#top")
  eq(u.host, "example.org"); eq(u.port, 1965); eq(u.path, "/a/b.gmi"); eq(u.query, "q=1")
  eq(u.url, "gemini://example.org/a/b.gmi?q=1")
  eq(net.parse("example.org").url, "gemini://example.org/")
  eq(net.parse("gemini://[::1]:2000/x").host, "::1")
  eq(net.parse("gemini://[::1]:2000/x").url, "gemini://[::1]:2000/x")
  local g = net.parse("gopher://example.org/0/docs/read me.txt")
  eq(g.type, "0"); eq(g.selector, "/docs/read me.txt"); eq(g.port, 70)
  eq(g.url, "gopher://example.org/0/docs/read%20me.txt")
  eq(net.parse(g.url).selector, "/docs/read me.txt")
  local s = net.parse("gopher://example.org:7070/7/find%09cats and dogs")
  eq(s.selector, "/find"); eq(s.search, "cats and dogs"); eq(s.port, 7070)
  eq(net.parse(s.url).search, "cats and dogs")
  eq(net.parse("gopher://example.org").url, "gopher://example.org/")
  eq(net.parse("gopher://example.org/").type, "1")
  eq(net.gopherURL("Host", 70, "1", "/a?b#c"), "gopher://host/1/a%3Fb%23c")
  eq(net.parse("https://example.com").scheme, "https")
  eq(select(2, net.parse("gemini:///x")), "no host in gemini:///x")
end)

test("links made whole, parents, and queries", function()
  local base = "gemini://example.org/a/b/c.gmi"
  eq(net.absolute(base, "d.gmi"), "gemini://example.org/a/b/d.gmi")
  eq(net.absolute(base, "/top"), "gemini://example.org/top")
  eq(net.absolute(base, "../up/"), "gemini://example.org/a/up/")
  eq(net.absolute(base, "//other.org/"), "gemini://other.org/")
  eq(net.absolute(base, "gopher://x/"), "gopher://x/")
  eq(net.absolute(base, "mailto:me@example.org"), "mailto:me@example.org")
  eq(net.parent(base), "gemini://example.org/a/b/")
  eq(net.parent("gemini://example.org/a/b/"), "gemini://example.org/a/")
  eq(net.parent("gemini://example.org/?q"), "gemini://example.org/")
  eq(net.parent("gemini://example.org/"), nil)
  eq(net.parent("gopher://example.org/0/docs/a.txt"), "gopher://example.org/1/docs")
  eq(net.parent("gopher://example.org/1/docs"), "gopher://example.org/")
  eq(net.parent("gopher://example.org/"), nil)
  eq(net.withQuery("gemini://example.org/ask?old", "Ann & Bob"), "gemini://example.org/ask?Ann%20%26%20Bob")
end)

---------------------------------------------------------------- pages

test("gemtext becomes Markdown, its links whole", function()
  local text, title = page.gemtext(CAPSULE, "gemini://example.org/dir/")
  eq(title, "Test capsule")
  local md = require "markdown"
  local blocks = md.parse(text)
  eq(blocks[1].type, "h1")
  -- The words are kept as they were, markup and all.
  eq(md.textOf(blocks[2]), "Hello *there* [x].\nSecond line.")
  local links = {}
  for _, r in ipairs(blocks[3].runs) do
    if r.link then links[#links + 1] = r.link end
  end
  eq(links[1], "gemini://example.org/next.gmi")
  eq(links[2], "gopher://example.org/")
  eq(links[3], "https://example.com")
  eq(md.textOf(blocks[3]), "→ Next page\n→ A hole\n⇗ The web")
  eq(blocks[4].type, "ul"); eq(blocks[5].type, "ul")
  eq(blocks[6].type, "quote"); eq(md.textOf(blocks[6]), "quoted")
  eq(blocks[7].type, "code"); eq(md.textOf(blocks[7]), "  /\\_/\\\n ( o.o )")
  -- A preformatted block left open runs to the end.
  local open = md.parse((page.gemtext("```\nleft open\n", "gemini://x/")))
  eq(md.textOf(open[1]), "left open")
end)

test("a Gopher menu becomes Markdown, each item with its kind", function()
  local menu = MENU:gsub("%%d", "70")
  local items = page.gopherItems(menu)
  eq(#items, 9, "the . ends it")
  eq(items[4].type, "1"); eq(items[4].selector, "/things"); eq(items[4].port, 70)
  eq(page.itemURL(items[4]), "gopher://127.0.0.1/1/things")
  eq(page.itemURL(items[7]), "https://example.com/")
  local text, title = page.gopher(menu)
  eq(title, "Welcome to the test hole")
  local md = require "markdown"
  local blocks = md.parse(text)
  eq(md.textOf(blocks[1]), "Welcome to the test hole\n\194\160\194\160indented")
  local runs = blocks[2].runs
  eq(runs[1].text, "DIR"); eq(runs[1].code, true)
  eq(runs[3].text, "Things & stuff\n"); eq(runs[3].link, "gopher://127.0.0.1/1/things")
  ok(text:find("`ASK` %[Search here%]"), text)
  ok(text:find("`BIN` %[A file%]"), text)
  ok(text:find("%*%*Something failed%*%*"), text)
  local plain = md.parse(page.plain("one\r\ntwo\r\n.\r\n"))
  eq(plain[1].type, "code"); eq(md.textOf(plain[1]), "one\ntwo")
end)

---------------------------------------------------------------- the look

test("a VGA font when there is one, and the EGA's colours", function()
  local look = require "look"
  eq(look.fixedFont({ "sans", "serif", "mono", "Menlo", "Perfect DOS VGA 437 Win", "Flexi IBM VGA True" }),
    "Flexi IBM VGA True", "the best first")
  eq(look.fixedFont({ "sans", "mono", "perfect dos vga 437 win" }), "perfect dos vga 437 win", "case aside")
  eq(look.fixedFont({ "sans", "serif", "mono", "Menlo" }), "mono")
  ok(look.isVGA("Flexi IBM VGA True")); ok(not look.isVGA("mono"))
  local ega = {}
  for _, c in pairs(look.EGA) do ega[c] = true end
  for key, c in pairs(look.terminal) do ok(ega[c], key .. " is one of the 16") end
  ok(ega[look.status.color] and ega[look.status.textColor])
end)

---------------------------------------------------------------- settings

test("bookmarks, certificates and tabs are kept", function()
  local s = store.load()
  eq(#s.bookmarks, 0); eq(s.textSize, 15)
  eq(store.bookmark(s, "One", "gemini://one/"), 1)
  eq(store.bookmark(s, "Two \"quoted\"\nline", "gemini://two/"), 2)
  eq(store.bookmark(s, "Uno", "gemini://one/"), 1, "the same address is renamed")
  eq(store.move(s, 1, 1), 2)
  eq(s.bookmarks[1].title, "Two \"quoted\"\nline")
  eq(store.move(s, 2, 1), 2, "nowhere to go")
  eq(store.check(s, "one:1965", "aa"), "new")
  eq(store.check(s, "one:1965", "aa"), "same")
  eq(store.check(s, "one:1965", "bb"), "changed")
  s.tabs = { "gemini://one/", "about:home" }
  ok(store.save(s))
  local again = store.load()
  eq(#again.bookmarks, 2); eq(again.bookmarks[2].title, "Uno")
  eq(again.bookmarks[1].title, "Two \"quoted\"\nline")
  eq(again.known["one:1965"], "aa"); eq(#again.tabs, 2)
  store.unbookmark(again, 1)
  eq(#again.bookmarks, 1)
  os.remove(store.file)
end)

---------------------------------------------------------------- requests

local function fetch(url, opts)
  local job = net.request(url, opts)
  pump(function() return job:poll() end)
  return job
end

test("a Gopher request, with a search's words", function()
  local job = fetch(H .. "/0/about.txt")
  eq(job.err, nil); eq(job.status, 20)
  eq(job.body, "This is a test.\r\nLine two.\r\n.\r\n")
  job = fetch(H .. "/7/search%09cats")
  ok(job.body:find("You searched for cats"), job.body)
  eq(gopherSrv.lines[#gopherSrv.lines], "/search\tcats")
end)

test("a Gemini request over TLS, and trust on first use", function()
  local seen = {}
  local trust = function(hostport, fp)
    seen[#seen + 1] = hostport
    return true
  end
  local job = fetch(G .. "/", { trust = trust })
  eq(job.err, nil); eq(job.status, 20); eq(job.meta, "text/gemini")
  eq(job.body, CAPSULE)
  eq(#job.fingerprint, 64)
  eq(seen[1], "127.0.0.1:" .. geminiSrv.port)
  eq(geminiSrv.lines[#geminiSrv.lines], G .. "/", "the request is the whole address")
  local fp = job.fingerprint
  -- A refused certificate: nothing is sent.
  local n = #geminiSrv.lines
  job = fetch(G .. "/", { trust = function() return false end })
  eq(job.untrusted, true); ok(job.err); eq(job.fingerprint, fp)
  eq(#geminiSrv.lines, n)
end)

test("what fails, fails with why", function()
  local srv = assert(socket.bind("127.0.0.1", 0))
  local _, port = srv:getsockname()
  srv:close()
  local job = fetch("gopher://127.0.0.1:" .. port .. "/")
  ok(job.err and job.err ~= "", "no one listening")
  eq(fetch("https://example.com/").err, "https: is not Gemini or Gopher")
  job = net.request(G .. "/")
  job:poll()
  job:cancel()
  eq(job.err, "stopped"); eq(job.done, true)
  pump(function() return true end)
end)

---------------------------------------------------------------- the form

local gui = require "gui"
local answers = {}
gui.msgbox = function() return table.remove(answers, 1) or "no" end
gui.inputbox = function() return table.remove(answers, 1) end
gui.openurl = function(url) opened = url return true end
local saved
gui.savefile = function(opts) saved = opts.file return root .. "/" .. opts.file end

store.file = root .. "/settings.lua"
local frm = require "forms.MicroBrowser"
local view = frm.vwPage

local function loaded()
  pump(function() return not frm.poll() end)
end

local function go(url)
  frm.open(url)
  loaded()
end

local function current()
  local tabs, i = frm.state()
  return tabs[i], tabs, i
end

test("form: starts at home, and goes to a capsule", function()
  local t = current()
  eq(t.entry.url, "about:home")
  ok(view.text:find("Bookmarks"), view.text)
  go(G .. "/")
  t = current()
  eq(t.entry.url, G .. "/"); eq(t.entry.title, "Test capsule")
  eq(frm.txtAddress.text, G .. "/")
  ok(view.text:find("Next page"), view.text)
  eq(frm.caption, "Test capsule — microbrowser")
  eq(frm.cmdBack.enabled, true)
  eq(frm.tabBar.list[1].title, "Test capsule")
end)

test("form: links, back and forward, and up", function()
  go(G .. "/")
  view:fire("onLink", G .. "/next.gmi")
  loaded()
  eq(current().entry.url, G .. "/next.gmi")
  eq(current().entry.title, "Next")
  frm.back()
  eq(current().entry.url, G .. "/")
  ok(view.text:find("Test capsule"))
  frm.forward()
  eq(current().entry.url, G .. "/next.gmi")
  frm.up()
  loaded()
  eq(current().entry.url, G .. "/")
  eq(view:fire("onLink", "#somewhere"), false, "an anchor is the view's")
  view:fire("onLink", "https://example.com")
  eq(opened, "https://example.com")
  eq(current().entry.url, G .. "/", "the web opens elsewhere")
end)

test("form: redirects, input, pictures and errors", function()
  go(G .. "/old")
  eq(current().entry.url, G .. "/next.gmi")
  go(G .. "/loop")
  eq(current().entry.title, "Too many redirects")
  answers = { "Ann" }
  go(G .. "/ask")
  eq(current().entry.url, G .. "/ask?Ann")
  ok(view.text:find("You said Ann"), view.text)
  go(G .. "/pic.png")
  eq(view.pictures["page-picture"].width, 4)
  ok(current().entry.status:find("4 × 3"), current().entry.status)
  go(G .. "/missing")
  eq(current().entry.title, "Permanent failure (51)")
  ok(view.text:find("Not found"))
  go(G .. "/cert")
  eq(current().entry.title, "A client certificate is needed")
end)

test("form: Gopher menus, searches, texts and downloads", function()
  go(H .. "/")
  eq(current().entry.title, "Welcome to the test hole")
  ok(view.text:find("Things & stuff"), view.text)
  answers = { "dogs" }
  view:fire("onLink", H .. "/7/search")
  loaded()
  eq(current().entry.url, H .. "/7/search%09dogs")
  ok(view.text:find("You searched for dogs"), view.text)
  go(H .. "/0/about.txt")
  ok(view.text:find("This is a test."), view.text)
  eq(current().entry.name, "about.txt.txt")
  go(H .. "/9/file.bin")
  eq(saved, "file.bin")
  local f = io.open(root .. "/file.bin", "rb")
  eq(f:read("*a"), "\0\1\2binary")
  f:close()
  eq(current().entry.url, H .. "/0/about.txt", "a download leaves the page as it was")
end)

test("form: tabs", function()
  local _, tabs = current()
  local n = #tabs
  frm.newTab(H .. "/1/things")
  loaded()
  local t, tabs2, i = current()
  eq(#tabs2, n + 1); eq(t.entry.url, H .. "/1/things")
  eq(frm.tabBar.active, i)
  -- A tab opened behind leaves this one shown.
  frm.newTab(G .. "/next.gmi", true)
  loaded()
  eq(current().entry.url, H .. "/1/things")
  frm.pick(i + 1)
  eq(current().entry.url, G .. "/next.gmi")
  eq(frm.txtAddress.text, G .. "/next.gmi")
  frm.closeTab(i + 1)
  eq(current().entry.url, H .. "/1/things")
  frm.closeTab(i)
  eq(#select(2, current()), n)
  -- Closing the last tab leaves a new one at home.
  while #select(2, current()) > 1 do frm.closeTab(1) end
  frm.closeTab(1)
  eq(current().entry.url, "about:home")
end)

test("form: bookmarks", function()
  go(G .. "/")
  eq(frm.cmdBookmark.visible, true)
  answers = { "My capsule" }
  frm.bookmark()
  local s = frm.settings()
  eq(s.bookmarks[1].title, "My capsule"); eq(s.bookmarks[1].url, G .. "/")
  eq(frm.cmdBookmarked.visible, true); eq(frm.cmdBookmark.visible, false)
  local menu = frm.Menu1.items
  local marks
  for _, top in ipairs(menu) do if top[1] == "&Bookmarks" then marks = top[2] end end
  eq(marks[#marks][1], "My capsule")
  frm.open("about:home")
  ok(view.text:find("My capsule"), view.text)
  -- Bookmarked again, with no name: taken out.
  frm.back()
  answers = { "" }
  frm.bookmark()
  eq(#s.bookmarks, 0)
  eq(frm.cmdBookmark.visible, true)
  eq(dofile(store.file).bookmarks[1], nil, "saved")
end)

test("form: a capsule with a new certificate is asked about", function()
  go(G .. "/")
  local s = frm.settings()
  local key = "127.0.0.1:" .. geminiSrv.port
  local first = s.known[key]
  eq(#first, 64)
  geminiSrv.cert = 2
  answers = { "no" }
  go(G .. "/next.gmi")
  eq(current().entry.title, "Certificate refused")
  eq(s.known[key], first)
  answers = { "yes" }
  frm.reload()
  loaded()
  eq(current().entry.title, "Next")
  ok(s.known[key] ~= first, "the new one is trusted")
  geminiSrv.cert = 1
end)

test("form: a fixed font and a terminal's colours", function()
  local look = require "look"
  local real = gui.fonts
  -- tlua takes only fonts that are installed, and no VGA font may be: one
  -- that is stands in for a VGA font here.
  local vga = "mono"
  for _, name in ipairs(real()) do
    if name ~= "sans" and name ~= "serif" and name ~= "mono" then vga = name break end
  end
  table.insert(look.VGA, 1, vga)
  gui.fonts = function() return { "sans", "serif", "mono", vga } end
  local s = frm.settings()
  eq(view.face, ""); eq(view.colors, nil)
  frm.toggleLook("mono")
  eq(view.face, vga)
  eq(view.textSize, 16, "a VGA font at its own size")
  frm.toggleLook("terminal")
  eq(view.colors.background, "#000000"); eq(view.colors.link, look.EGA.lightCyan)
  eq(frm.lblStatus.color, look.EGA.blue)
  local function checked(name)
    for _, top in ipairs(frm.Menu1.items) do
      for _, it in ipairs(type(top[2]) == "table" and top[2] or {}) do
        if type(it) == "table" and it.name == name then return it.checked end
      end
    end
  end
  eq(checked("mnuMono"), true); eq(checked("mnuTerminal"), true)
  local kept = dofile(store.file)
  eq(kept.mono, true); eq(kept.terminal, true)
  frm.toggleLook("mono")
  frm.toggleLook("terminal")
  eq(view.face, ""); eq(view.colors, nil); eq(view.textSize, s.textSize)
  eq(checked("mnuMono"), false)
  gui.fonts = real
  table.remove(look.VGA, 1)
end)

test("form: the tabs are kept for next time", function()
  frm.newTab(G .. "/next.gmi")
  loaded()
  frm:fire("onClose")
  local kept = dofile(store.file).tabs
  eq(kept[#kept], G .. "/next.gmi")
end)

test("form: the outline lists a page's headings, and picking one goes to it", function()
  local list = frm.lstOutline
  go("about:help")
  eq(frm.settings().outline, false)
  eq(list.visible, false, "not there to begin with")
  eq(view.left, 0)
  local full = view.width
  frm.Menu1:fire("onClick", "mnuOutline", "", nil)
  eq(frm.settings().outline, true)
  eq(list.visible, true)
  eq(list.width, 240); eq(view.left, 240); eq(view.width, full - 240, "the page gives it room")
  eq(list.items[1], "Using microbrowser")
  eq(list.items[2], "  Tabs"); eq(list.items[3], "  Moving about")
  eq(#list.items, #frm.outline(), "a line for each heading")
  ok(#list.items >= 6)
  -- Picking one goes to it, through the view.
  local went
  view.scrollTo = function(_, anchor) went = anchor return true end
  list.selected = 3
  list:fire("onChange")
  eq(went, frm.outline()[3].anchor)
  ok(went and went ~= "", "an anchor")
  list.selected = 0
  went = nil
  list:fire("onChange")
  eq(went, nil, "nothing picked, nowhere to go")
  view.scrollTo = nil
  -- Another page, another outline: with no headings, it says so.
  local tabs, i = frm.state()
  tabs[i].entry = { url = "gemini://x/", title = "x", text = "just words\n" }
  frm.pick(i)
  eq(list.items[1], "(no headings)"); eq(#list.items, 1)
  list.selected = 1
  list:fire("onChange")
  -- Headings deeper than the first are indented from the highest there is.
  tabs[i].entry = { url = "gemini://y/", title = "y", text = "## Two\n\ntext\n\n### Three\n\n## Two again\n" }
  frm.pick(i)
  eq(list.items[1], "Two"); eq(list.items[2], "  Three"); eq(list.items[3], "Two again")
  -- It keeps its width as the window changes size, and the page has the rest.
  frm.width = frm.width + 100
  frm:fire("onResize")
  eq(list.width, 240); eq(view.left, 240); eq(view.width, frm.width - 240)
  -- It is kept for next time, and puts away again.
  eq(store.load().outline, true)
  frm.Menu1:fire("onClick", "mnuOutline", "", nil)
  eq(frm.settings().outline, false)
  eq(list.visible, false); eq(view.left, 0); eq(view.width, frm.width)
  eq(store.load().outline, false)
  -- A new tab's page is listed when the sidebar comes back.
  go("about:help")
  frm.toggleOutline()
  ok(#list.items >= 6)
  frm.toggleOutline()
end)

test("history: pages seen are remembered, the newest first, and kept", function()
  local s = store.load()
  s.history = {}
  store.visit(s, "gemini://a/", "Alpha", 100)
  store.visit(s, "gemini://b/", "Beta", 200)
  store.visit(s, "gemini://a/", "Alpha again", 300)
  eq(#s.history, 2)
  local list = store.recent(s)
  eq(list[1].url, "gemini://a/"); eq(list[1].count, 2); eq(list[1].title, "Alpha again")
  eq(list[2].url, "gemini://b/")
  eq(#store.recent(s, nil, 1), 1)
  eq(#store.recent(s, "BETA"), 1, "the case aside")
  eq(store.recent(s, "gemini://b")[1].title, "Beta", "by address too")
  eq(#store.recent(s, "nothing"), 0)
  ok(store.save(s))
  local again = store.load()
  eq(#again.history, 2); eq(again.history[2].time, 300); eq(again.history[2].count, 2)
  -- Broken entries do not come through, and the oldest go past the limit.
  eq(store.forget(again, "gemini://b/"), true)
  eq(store.forget(again, "gemini://nope/"), false)
  eq(#again.history, 1)
  for i = 1, store.HISTORY_MAX + 5 do store.visit(again, "gemini://x/" .. i, "x", i) end
  eq(#again.history, store.HISTORY_MAX)
  eq(again.history[1].url, "gemini://x/6")
  store.clearHistory(again)
  eq(#again.history, 0)
  os.remove(store.file)
end)

test("form: pages are put in the history, and open from it", function()
  local historyForm = require "forms.History"
  local s = frm.settings()
  s.history = {}
  go(H .. "/")
  local title = current().entry.title
  eq(#s.history, 1); eq(s.history[1].url, H .. "/"); eq(s.history[1].title, title)
  frm.open("about:home")
  eq(#s.history, 1, "its own pages are not kept")
  go(H .. "/")
  eq(s.history[1].count, 2)
  ok(dofile(store.file).history[1], "kept in the file")
  -- The menu lists the latest.
  local menu
  for _, top in ipairs(frm.Menu1.items) do if top[1] == "&History" then menu = top[2] end end
  eq(menu[#menu][1], title)
  -- The window lists them, narrowed by what is typed.
  historyForm.prepare(s)
  eq(#historyForm.lstHistory.items, 1)
  ok(historyForm.lstHistory.items[1]:find(title, 1, true), historyForm.lstHistory.items[1])
  historyForm.txtFilter.text = "zzz"
  historyForm.txtFilter:fire("onChange")
  eq(#historyForm.lstHistory.items, 0); eq(historyForm.cmdOpen.enabled, false)
  historyForm.txtFilter.text = ""
  historyForm.txtFilter:fire("onChange")
  historyForm.cmdNewTab:fire("onClick")
  local url, inNew = historyForm.chosen()
  eq(url, H .. "/"); eq(inNew, true)
  -- Forgetting, and clearing once asked.
  historyForm.prepare(s)
  historyForm.cmdForget:fire("onClick")
  eq(#s.history, 0)
  store.visit(s, "gemini://a/", "A")
  historyForm.prepare(s)
  answers = { "no" }
  historyForm.cmdClear:fire("onClick")
  eq(#s.history, 1)
  answers = { "yes" }
  historyForm.cmdClear:fire("onClick")
  eq(#s.history, 0)
  answers = { "yes" }
  store.visit(s, "gemini://a/", "A")
  frm.Menu1:fire("onClick", "mnuClearHistory", "", nil)
  eq(#s.history, 0)
end)

test("form: the find bar finds in the page, forwards and back, and counts", function()
  frm.open("about:help")
  loaded()
  local bar = frm.pnlFind
  eq(bar.visible, false)
  local top, height = view.top, view.height
  frm.Menu1:fire("onClick", "mnuFind", "", nil)
  eq(bar.visible, true)
  eq(view.top, top + 34); eq(view.height, height - 34, "the page gives it room")
  frm.txtFind.text = "TAB"
  frm.txtFind:fire("onChange")
  local n = tonumber(frm.lblFound.caption:match("^(%d+) found"))
  ok(n and n >= 1, frm.lblFound.caption)
  frm.txtFind:fire("onKey", "Enter")
  eq(view:selectedText():lower(), "tab")
  ok(frm.lblFound.caption:find("^1 of " .. n), frm.lblFound.caption)
  frm.txtFind:fire("onKey", "Enter")
  ok(frm.lblFound.caption:find("^%d of " .. n) or n == 1, frm.lblFound.caption)
  frm.txtFind:fire("onKey", "Shift+Enter")
  ok(frm.lblFound.caption:find(" of " .. n), frm.lblFound.caption)
  frm.cmdFindNext:fire("onClick")
  frm.cmdFindPrev:fire("onClick")
  frm.txtFind.text = "no such words on this page"
  frm.txtFind:fire("onChange")
  eq(frm.lblFound.caption, "not found")
  frm.txtFind:fire("onKey", "Enter")
  ok(frm.lblStatus.caption:find("is not on this page"), frm.lblStatus.caption)
  -- Escape puts the bar away; Find Next goes on with what was looked for.
  frm.txtFind.text = "tab"
  frm.txtFind:fire("onChange")
  eq(frm.txtFind:fire("onKey", "Escape"), true)
  eq(bar.visible, false); eq(view.top, top); eq(view.height, height)
  frm.Menu1:fire("onClick", "mnuFindNext", "", nil)
  ok(frm.lblStatus.caption:find("“tab”"), frm.lblStatus.caption)
  frm.Menu1:fire("onClick", "mnuFindPrev", "", nil)
  eq(view:selectedText():lower(), "tab")
end)

t.done("microbrowser")
