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

-- hold is a Gopher server that sends the start of a file and then waits, the
-- connection open, until it is let go: a download that is going on for as
-- long as a test needs it to be.
local function hold()
  local srv = assert(socket.bind("127.0.0.1", 0))
  srv:settimeout(0)
  local _, port = srv:getsockname()
  local h = { port = tonumber(port), conns = {}, released = false }
  function h.step()
    local c = srv:accept()
    if c then
      c:settimeout(0)
      h.conns[#h.conns + 1] = { sock = c, sent = false }
    end
    for i = #h.conns, 1, -1 do
      local k = h.conns[i]
      if not k.sent then
        local line = k.sock:receive("*l")
        if line then
          k.sock:send(("0123456789abcdef"):rep(100))
          k.sent = true
        end
      elseif h.released then
        k.sock:send(("0123456789abcdef"):rep(100))
        k.sock:close()
        table.remove(h.conns, i)
      end
    end
  end
  function h.release() h.released = true end
  return h
end

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
  if sel == "/big.bin" then return ("0123456789abcdef"):rep(20000) end
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
  if path == "/file.zip" then return "20 application/zip\r\nPK-not-really-a-zip" end
  if path == "/get" then return "31 /file.zip\r\n" end
  if path == "/big.dat" then return "20 application/octet-stream\r\n" .. ("0123456789abcdef"):rep(20000) end
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
  frm.settings().downloadDir = root
  go(H .. "/9/file.bin")
  local f = io.open(root .. "/file.bin", "rb")
  eq(f:read("*a"), "\0\1\2binary")
  f:close()
  eq(current().entry.url, H .. "/0/about.txt", "a download leaves the page as it was")
  os.remove(root .. "/file.bin")
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

test("net: a name's addresses are tried in turn, the families taking turns", function()
  local function order(list)
    local out = {}
    for i, a in ipairs(net.interleave(list)) do out[i] = a.addr end
    return table.concat(out, " ")
  end
  eq(order { { family = "inet6", addr = "a6" }, { family = "inet", addr = "a4" } }, "a6 a4")
  eq(order { { family = "inet6", addr = "a" }, { family = "inet6", addr = "b" }, { family = "inet", addr = "c" },
    { family = "inet", addr = "d" } }, "a c b d")
  eq(order { { family = "inet", addr = "x" } }, "x")
  eq(order {}, "")
  -- A name that leads first to an address nobody listens on (localhost is
  -- ::1 first on some systems, and the servers here are on 127.0.0.1) still
  -- gets through, by the next one.
  local job = fetch("gopher://localhost:" .. gopherSrv.port .. "/0/about.txt")
  eq(job.err, nil)
  eq(job.body, "This is a test.\r\nLine two.\r\n.\r\n")
end)

test("net: a file is given to a sink as it comes, and its answer is not kept", function()
  local got, pieces = {}, 0
  local function sink(chunk) pieces = pieces + 1 got[#got + 1] = chunk return true end
  local job = fetch(H .. "/9/big.bin", { download = function(j) eq(j.parsed.type, "9") return sink end })
  eq(job.err, nil); eq(job.streamed, true); eq(job.body, "")
  eq(#table.concat(got), 320000); eq(job.received, 320000)
  ok(pieces > 1, "in pieces")
  -- Gemini: the header is read first, and the hook sees its type.
  got, pieces = {}, 0
  local seen
  job = fetch(G .. "/big.dat", { download = function(j) seen = j.meta return sink end })
  eq(seen, "application/octet-stream"); eq(job.status, 20); eq(job.streamed, true)
  eq(#table.concat(got), 320000)
  -- A hook that gives no sink leaves the answer to be kept, as before.
  job = fetch(G .. "/file.zip", { download = function() return nil end })
  eq(job.streamed, false); eq(job.body, "PK-not-really-a-zip")
  -- It is asked only about a success, and a sink that fails stops it.
  local asked = false
  job = fetch(G .. "/nothing", { download = function() asked = true end })
  eq(asked, false); eq(job.status, 51)
  job = fetch(H .. "/9/big.bin", { download = function() return function() return nil, "disk full" end end })
  eq(job.err, "disk full")
end)

test("download: names, files that arrive, and what a stop leaves", function()
  local download = require "download"
  local dir = root .. "/dl"
  require("lfs").mkdir(dir)
  eq(download.folder(dir), dir)
  eq(download.uniquePath(dir, "a.txt"), dir .. "/a.txt")
  local f = io.open(dir .. "/a.txt", "w") f:write("x") f:close()
  eq(download.uniquePath(dir, "a.txt"), dir .. "/a (2).txt")
  ok(not download.uniquePath(dir, "../x"):find("/../", 1, true), "no way out of the folder")
  download.list = {}
  local changes = 0
  download.onChange = function() changes = changes + 1 end
  local job = net.request(H .. "/9/big.bin", { download = function(j)
    local d = assert(download.begin(j, dir, "big.bin"))
    return d.sink
  end })
  local d
  local n = 0
  pump(function()
    n = n + 1
    local busy = download.poll()
    if not job.done then job:poll() end
    d = download.list[1]
    return not busy and job.done
  end)
  eq(d.state, "done"); eq(d.received, 320000)
  eq(#io.open(d.path, "rb"):read("*a"), 320000)
  ok(changes >= 2, "told when it began and when it ended")
  ok(download.describe(d):find("done, 312 KB", 1, true), download.describe(d))
  -- Stopped: the half is taken away.
  local waiting = hold()
  servers[#servers + 1] = waiting
  local j2 = net.request("gopher://127.0.0.1:" .. waiting.port .. "/9/x", { download = function(j)
    return assert(download.begin(j, dir, "stopme.bin")).sink
  end })
  repeat for _, sv in ipairs(servers) do sv.step() end j2:poll() until download.list[2] and download.list[2].received > 0
  local d2 = download.list[2]
  eq(d2.state, "receiving"); eq(download.active(), 1)
  download.cancel(d2)
  eq(d2.state, "stopped"); eq(download.active(), 0)
  ok(not require("lfs").attributes(d2.path), "the half file is gone")
  table.remove(servers)
  -- Failed ones are taken away too; a body that is here is saved at once.
  local saved2 = download.save(dir, "here.txt", "body")
  eq(saved2.state, "done"); eq(io.open(saved2.path):read("*a"), "body")
  download.remove(d2)
  eq(#download.list, 2)
  download.clear()
  eq(#download.list, 0)
  download.onChange = nil
end)

test("form: a file goes on in the background, and the tab keeps its page", function()
  local download = require "download"
  local dl = require "forms.Downloads"
  local dir = root .. "/formdl"
  require("lfs").mkdir(dir)
  local s = frm.settings()
  s.downloadDir = dir
  s.known = {}
  download.list = {}
  go(H .. "/0/about.txt")
  local page = current().entry.url
  -- Gopher: a binary item streams to the folder, and the tab is free at once.
  frm.open(H .. "/9/big.bin")
  local t = current()
  local steps = 0
  repeat
    for _, sv in ipairs(servers) do sv.step() end
    frm.poll()
    steps = steps + 1
  until t.job == nil or steps > 3000
  eq(t.job, nil, "the tab let go of it")
  eq(t.entry.url, page, "and shows the page it had")
  eq(download.list[1].name, "big.bin")
  ok(frm.cmdStop.visible == false, "not loading")
  repeat for _, sv in ipairs(servers) do sv.step() end until not frm.poll()
  eq(download.list[1].state, "done")
  eq(#io.open(dir .. "/big.bin", "rb"):read("*a"), 320000)
  -- Gemini, by its type; a second one is not given the first's name.
  go(G .. "/file.zip")
  eq(current().entry.url, page)
  eq(io.open(dir .. "/file.zip", "rb"):read("*a"), "PK-not-really-a-zip")
  go(G .. "/file.zip")
  eq(io.open(dir .. "/file (2).zip", "rb"):read("*a"), "PK-not-really-a-zip")
  -- A link to download goes through redirects, on its own.
  ok(frm.downloadLink(G .. "/get"))
  repeat for _, sv in ipairs(servers) do sv.step() end until not frm.poll()
  eq(io.open(dir .. "/file (3).zip", "rb"):read("*a"), "PK-not-really-a-zip")
  ok(not frm.downloadLink("https://example.com/x"), "only Gemini and Gopher")
  -- Pages and pictures are still shown, not downloaded.
  go(G .. "/pic.png")
  ok(current().entry.pictures, "a picture is shown")
  eq(#download.list, 4)
  -- The window lists them, and its buttons do what they say.
  local ran
  dl.run = function(cmd) ran = cmd end
  dl.open = dl.fill -- no window is shown in a test
  frm.Menu1:fire("onClick", "mnuDownloads", "", nil)
  eq(#dl.lstDownloads.items, 4)
  ok(dl.lstDownloads.items[1]:find("big.bin    done", 1, true), dl.lstDownloads.items[1])
  ok(dl.lblFolder.caption:find(dir, 1, true), dl.lblFolder.caption)
  dl.lstDownloads.selected = 1
  dl.lstDownloads:fire("onChange")
  eq(dl.cmdOpen.enabled, true); eq(dl.cmdCancel.enabled, false); eq(dl.cmdRemove.enabled, true)
  dl.cmdOpen:fire("onClick")
  eq(ran[#ran], dir .. "/big.bin")
  dl.cmdShow:fire("onClick")
  eq(ran[#ran], dir)
  dl.cmdRemove:fire("onClick")
  eq(#download.list, 3); ok(require("lfs").attributes(dir .. "/big.bin"), "the file stays")
  -- Cancel a download that is going on.
  local waiting = hold()
  servers[#servers + 1] = waiting
  local HOLD = "gopher://127.0.0.1:" .. waiting.port .. "/9/x"
  frm.downloadLink(HOLD)
  repeat for _, sv in ipairs(servers) do sv.step() end frm.poll()
  until download.active() > 0 and download.list[#download.list].received > 0
  dl.fill()
  dl.lstDownloads.selected = #download.list
  dl.lstDownloads:fire("onChange")
  eq(dl.cmdCancel.enabled, true); eq(dl.cmdOpen.enabled, false)
  local name = download.list[#download.list].name
  dl.cmdCancel:fire("onClick")
  eq(download.list[#download.list].state, "stopped")
  ok(not require("lfs").attributes(dir .. "/" .. name), "what came is taken away")
  dl.cmdClear:fire("onClick")
  eq(#download.list, 0)
  -- The folder is kept in the settings.
  local realDir = gui.choosedir
  gui.choosedir = function() return root end
  dl.cmdFolder:fire("onClick")
  gui.choosedir = realDir
  eq(s.downloadDir, root); eq(store.load().downloadDir, root)
  -- Quitting asks when something is coming in.
  frm.downloadLink(HOLD)
  repeat for _, sv in ipairs(servers) do sv.step() end frm.poll()
  until download.active() > 0 and download.list[#download.list].received > 0
  answers = { "no" }
  eq(frm:fire("onClose"), false)
  eq(download.active(), 1)
  answers = { "yes" }
  frm:fire("onClose")
  eq(download.active(), 0)
  table.remove(servers)
  s.downloadDir = ""
end)

t.done("microbrowser")
