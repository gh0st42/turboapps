-- The code behind MicroBrowser.form.lua: the controls are fields of the
-- form, by the names the layout gives them. A browser for Gemini and
-- Gopher: tabs, each with its own pages back and forward, an address bar,
-- bookmarks, and the certificate a capsule first showed trusted after.
-- net.lua fetches, a step at a time from a timer, so the window never
-- waits; page.lua turns what came into Markdown for the view.

local gui = require "gui"
local net = require "net"
local page = require "page"
local store = require "store"
local png = require "png"
local look = require "look"
local bookmarksForm = require "forms.Bookmarks"
local historyForm = require "forms.History"

local frm = gui.load "MicroBrowser" --[[@as forms.MicroBrowser]]
local view, address, bar = frm.vwPage, frm.txtAddress, frm.tabBar

local settings = store.load()

-- A tab: { entry = the page shown, history = {}, future = {}, job = a
-- request under way, target = where it is going, lazy = an address to load
-- when the tab is first picked, source = show the page's source }.
-- An entry: { url, title, text (Markdown), pictures, body (as it came),
-- name (a file name for it) }.
local tabs = {}
local current = 0
local timer
local hovered     -- the link under the mouse
local lastFind = ""

local updateMenu -- below: the menus as things are
local countFound -- below: the count in the find bar
local find       -- below: opens the find bar

local HOME = "about:home"
local HELP = "about:help"
local MAX_REDIRECTS = 5

---------------------------------------------------------------- showing

local function tab() return tabs[current] end

local function titleOf(t)
  if t.job then
    return t.target and (net.parse(t.target) or {}).host or "Loading"
  end
  local e = t.entry
  if e then return e.title or e.url end
  return t.lazy or "New Tab"
end

local function status(text) frm.lblStatus.caption = text and ("  " .. text) or "" end

local function updateTabs()
  local list = {}
  for i, t in ipairs(tabs) do list[i] = { title = titleOf(t), loading = t.job ~= nil } end
  bar.list = list
  bar.active = current
end

local function updateButtons()
  local t = tab()
  local loading = t and t.job ~= nil
  frm.cmdBack.enabled = t and #t.history > 0 or false
  frm.cmdForward.enabled = t and #t.future > 0 or false
  frm.cmdReload.visible = not loading
  frm.cmdStop.visible = loading
  local url = t and t.entry and t.entry.url
  local marked = url and store.find(settings, url) ~= nil
  frm.cmdBookmark.visible = not marked
  frm.cmdBookmarked.visible = marked and true or false
end

---------------------------------------------------------------- the outline

local OUTLINE = 240 -- how wide the sidebar is
local outline = {}  -- the headings it lists, as the view gives them

-- layoutOutline puts the sidebar beside the page, or takes it away and gives
-- the page the room. It is done again when the window changes size, so
-- that the sidebar keeps its width.
local FINDBAR = 34 -- how high the find bar is, which the page gives room to
local findOn = false

local function layoutOutline()
  local list, w = frm.lstOutline, frm.width
  list.visible = settings.outline
  if settings.outline then
    list.left, list.width = 0, OUTLINE
    list.top, list.height = view.top, view.height
    view.left, view.width = OUTLINE, w - OUTLINE
  else
    view.left, view.width = 0, w
  end
end

-- showFind puts the find bar above the page, or takes it away; the page
-- takes the room, and the outline's list goes with it.
local function showFind(on)
  if on == findOn then return end
  findOn = on
  frm.pnlFind.visible = on
  local by = on and FINDBAR or -FINDBAR
  view.top, view.height = view.top + by, view.height - by
  layoutOutline()
end

-- refreshOutline lists the headings of the page shown, indented by their
-- level (from the highest on the page, so a page of only ## headings is not
-- all indented), while the sidebar is there.
local function refreshOutline()
  if not settings.outline then return end
  outline = view:headings()
  local top = math.huge
  for _, h in ipairs(outline) do top = math.min(top, h.level) end
  local items = {}
  for i, h in ipairs(outline) do items[i] = ("  "):rep(h.level - top) .. h.text end
  if #items == 0 then items[1] = "(no headings)" end
  frm.lstOutline.items = items
  frm.lstOutline.selected = 0
end

-- Picking a heading goes to it (the arrows go from one to the next); a
-- double click goes on to the page.
function frm.lstOutline:onChange()
  local h = outline[self.selected]
  if h then view:scrollTo(h.anchor) end
end

function frm.lstOutline:onDoubleClick()
  view:focus()
end

function frm:onResize()
  layoutOutline()
end

-- render shows the current tab: its page, address and title.
local function render()
  local t = tab()
  if not t then return end
  local e = t.entry or { text = "" }
  view.pictures = e.pictures or {}
  if t.source and e.body then
    view.text = page.plain(e.body)
  else
    view.text = e.text or ""
  end
  refreshOutline()
  if countFound and findOn then countFound() end
  address.text = t.job and t.target or e.url or ""
  frm.caption = (e.title and e.title ~= "" and e.title .. " — " or "") .. "microbrowser"
  updateTabs()
  updateButtons()
  if not t.job then status(e.status) end
end

-- refresh shows a tab again if it is the one shown, or just its title.
local function refresh(t)
  if t == tab() then render() else updateTabs() end
end

-- settle puts a page in a tab: the one there goes into its history unless
-- this replaces it.
local function settle(t, entry, push)
  if push and t.entry and t.entry.url ~= entry.url then
    t.history[#t.history + 1] = t.entry
    t.future = {}
  end
  t.entry = entry
  -- A page that came is remembered, not one that could not be had.
  if entry.url and entry.body then
    store.visit(settings, entry.url, entry.title)
    store.save(settings)
    if updateMenu then updateMenu() end
  end
  refresh(t)
end

local function lastName(url, fallback)
  local name = url:gsub("[?#].*$", ""):match("([^/]+)/*$")
  if not name or name:find(":") then return fallback end
  return net.unescape(name)
end

---------------------------------------------------------------- the browser's own pages

local function ownPage(url)
  if url == HELP then
    return { url = url, title = "Using microbrowser", text = page.HELP }
  end
  return { url = HOME, title = "Home", text = page.home(settings.bookmarks) }
end

local function errorPage(url, heading, words)
  return { url = url, title = heading, text = page.message(heading, words, { { "Try again", url } }),
    status = heading }
end

---------------------------------------------------------------- fetching

local poll -- the timer's work, below

local function startTimer()
  if timer then return end
  timer = gui.every(0.02, function()
    local busy = poll()
    if not busy then timer = nil end
    return busy
  end)
end

local function trust(hostport, fingerprint)
  local verdict = store.check(settings, hostport, fingerprint)
  if verdict == "new" then store.save(settings) end
  return verdict ~= "changed"
end

local navigate

-- navigate takes a tab to an address. opts.push keeps the page it is on
-- in its history; opts.redirects counts how often it has been sent on.
navigate = function(t, url, opts)
  opts = opts or {}
  url = (url or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if url == "" then return end
  if t.job then t.job:cancel() t.job = nil end
  t.lazy = nil
  if url:find("^about:") then
    settle(t, ownPage(url), opts.push)
    return
  end
  local u, err = net.parse(url)
  if not u then
    settle(t, errorPage(url, "Not an address", err), opts.push)
    return
  end
  if u.scheme ~= "gemini" and u.scheme ~= "gopher" then
    -- The web and the rest are for their own programs.
    local ok, why = gui.openurl(url)
    status(ok and ("Opened " .. url .. " in its own program") or ("Could not open " .. url .. ": " .. tostring(why)))
    refresh(t)
    return
  end
  if u.scheme == "gopher" and u.type == "7" and not u.search then
    local words = gui.inputbox("Search for:", u.host)
    if not words or words == "" then return end
    u.search = words
    u.url = net.format(u)
  end
  t.target = u.url
  t.opts = opts
  t.job = net.request(u.url, { trust = trust })
  refresh(t)
  if t == tab() then status("Connecting to " .. u.host .. "…") end
  startTimer()
end

-- open takes the current tab somewhere, keeping where it was.
local function open(url)
  local t = tab()
  if t then navigate(t, url, { push = true }) end
end

-- arrived is what a finished request shows, or does.
local function arrived(t, job)
  local opts = t.opts or {}
  local url = job.url
  t.job, t.target = nil, nil
  if job.err == "stopped" then
    refresh(t)
    if t == tab() then status("Stopped") end
    return
  end
  if job.untrusted then
    local u = job.parsed
    local hostport = u.host .. ":" .. u.port
    refresh(t)
    local answer = gui.msgbox(("%s shows a certificate it did not show before.\n\n"
      .. "It may have made a new one, or someone may be between you and it.\n\n"
      .. "New fingerprint (SHA-256):\n%s\n\nTrust the new certificate from now on?"):format(hostport, job.fingerprint or "?"),
      "yesno", "Certificate changed")
    if answer == "yes" then
      store.trust(settings, hostport, job.fingerprint)
      store.save(settings)
      navigate(t, url, opts)
    else
      settle(t, errorPage(url, "Certificate refused", hostport
        .. " showed a certificate that is not the one it showed before, and it was not trusted."), opts.push)
    end
    return
  end
  if job.err then
    settle(t, errorPage(url, "Could not load the page", job.err), opts.push)
    return
  end
  local u = job.parsed
  local kb = ("%.1f KB"):format(#job.body / 1024)
  if u.scheme == "gopher" then
    local kind = u.type
    if kind == "1" or kind == "7" then
      local text, title = page.gopher(job.body)
      settle(t, { url = url, title = title or u.host, text = text, body = job.body,
        name = lastName(url, "menu") .. ".txt", status = "Gopher menu, " .. kb }, opts.push)
    elseif kind == "0" or kind == "h" or kind == "3" then
      settle(t, { url = url, title = lastName(url, u.host), text = page.plain(job.body), body = job.body,
        name = lastName(url, "text") .. (kind == "h" and "" or ".txt"), status = "Text, " .. kb }, opts.push)
    else
      local pic = (kind == "g" or kind == "I" or kind == "p" or kind == ":") and png.decode(job.body)
      if pic then
        settle(t, { url = url, title = lastName(url, "picture"), text = page.picture(lastName(url, "picture")),
          pictures = { ["page-picture"] = pic }, body = job.body, name = lastName(url, "picture"),
          status = ("Picture, %d × %d, %s"):format(pic.width, pic.height, kb) }, opts.push)
      else
        refresh(t)
        t.download = { url = url, body = job.body, name = lastName(url, "download") }
        if t == tab() then frm.save(t.download) end
      end
    end
    return
  end
  -- Gemini.
  local code, meta = job.status, job.meta
  local class = math.floor(code / 10)
  if class == 1 then
    refresh(t)
    local words = gui.inputbox(meta ~= "" and meta or "Input:", u.host)
    if words then navigate(t, net.withQuery(url, words), opts) end
  elseif class == 2 then
    local mime = (meta ~= "" and meta or "text/gemini"):lower()
    local kind = mime:match("^%s*([^;%s]+)")
    if kind == "text/gemini" then
      local text, title = page.gemtext(job.body, url)
      settle(t, { url = url, title = title or u.host, text = text, body = job.body,
        name = lastName(url, "index") .. (lastName(url, ""):find("%.%w+$") and "" or ".gmi"),
        status = "Gemini, " .. kb }, opts.push)
    elseif kind:find("^text/") then
      settle(t, { url = url, title = lastName(url, u.host), text = page.plain(job.body), body = job.body,
        name = lastName(url, "text.txt"), status = kind .. ", " .. kb }, opts.push)
    else
      local pic = kind:find("^image/") and png.decode(job.body)
      if pic then
        settle(t, { url = url, title = lastName(url, "picture"), text = page.picture(lastName(url, "picture")),
          pictures = { ["page-picture"] = pic }, body = job.body, name = lastName(url, "picture"),
          status = ("%s, %d × %d, %s"):format(kind, pic.width, pic.height, kb) }, opts.push)
      else
        refresh(t)
        t.download = { url = url, body = job.body, name = lastName(url, "download") }
        if t == tab() then frm.save(t.download) end
      end
    end
  elseif class == 3 then
    local n = (opts.redirects or 0) + 1
    if n > MAX_REDIRECTS then
      settle(t, errorPage(url, "Too many redirects", "The capsule sent the browser on more than "
        .. MAX_REDIRECTS .. " times."), opts.push)
    else
      navigate(t, net.absolute(url, meta), { push = opts.push, redirects = n })
    end
  elseif class == 6 then
    settle(t, errorPage(url, "A client certificate is needed", meta ~= "" and meta
      or "This capsule wants a certificate from you, which microbrowser does not have."), opts.push)
  else
    local what = ({ [4] = "Temporary failure", [5] = "Permanent failure" })[class] or "Unknown answer"
    settle(t, errorPage(url, ("%s (%d)"):format(what, code), meta), opts.push)
  end
end

-- poll moves every request on; false when none is left.
poll = function()
  local busy = false
  for _, t in ipairs(tabs) do
    local job = t.job
    if job then
      if job:poll() then
        if t.job == job then arrived(t, job) end
      else
        busy = true
        if t == tab() then
          local host = job.parsed and job.parsed.host or ""
          if job.state == "receiving" then
            status(("Receiving from %s… %.1f KB"):format(host, job.received / 1024))
          elseif job.state == "handshake" then
            status("Securing the connection to " .. host .. "…")
          else
            status("Connecting to " .. host .. "…")
          end
        end
      end
    end
    busy = busy or t.job ~= nil
  end
  return busy
end

---------------------------------------------------------------- tabs

-- select shows tab i, loading it if it has not been yet.
local function select(i)
  if not tabs[i] then return end
  current = i
  local t = tabs[i]
  if t.lazy then navigate(t, t.lazy) end
  render()
  updateMenu()
  if t.download then
    local d = t.download
    t.download = nil
    frm.save(d)
  end
end

-- newTab opens a tab after the current one, at an address or home.
local function newTab(url, behind)
  local t = { history = {}, future = {} }
  local at = math.min(current + 1, #tabs + 1)
  table.insert(tabs, at, t)
  if not behind then current = at
  elseif at <= current then current = current + 1 end
  navigate(t, url or HOME)
  if not behind then
    render()
    if not url then address:focus() end
  else
    updateTabs()
  end
  return t
end

local function closeTab(i)
  local t = tabs[i]
  if not t then return end
  if t.job then t.job:cancel() end
  table.remove(tabs, i)
  if #tabs == 0 then
    current = 0
    newTab()
    return
  end
  if i < current or current > #tabs then current = current - 1 end
  select(math.max(1, current))
end

function bar:onPick(i) select(i) end
function bar:onClose(i) closeTab(i) end
function bar:onAdd() newTab() end
function bar:onMenu(i)
  local items = { { "New Tab", function() newTab() end } }
  if i then
    items[#items + 1] = { "Duplicate Tab", function()
      local t = tabs[i]
      local url = t.target or (t.entry and t.entry.url) or t.lazy
      current = i
      newTab(url)
    end }
    items[#items + 1] = "-"
    items[#items + 1] = { "Close Tab", function() closeTab(i) end }
    items[#items + 1] = { "Close Other Tabs", function()
      local keep = tabs[i]
      for j = #tabs, 1, -1 do
        if tabs[j] ~= keep then
          if tabs[j].job then tabs[j].job:cancel() end
          table.remove(tabs, j)
        end
      end
      current = 1
      select(1)
    end }
  end
  gui.popup(items)
end

---------------------------------------------------------------- moving about

local function back()
  local t = tab()
  if not t or #t.history == 0 then return end
  if t.job then t.job:cancel() t.job = nil end
  t.future[#t.future + 1] = t.entry
  t.entry = table.remove(t.history)
  render()
end

local function forward()
  local t = tab()
  if not t or #t.future == 0 then return end
  if t.job then t.job:cancel() t.job = nil end
  t.history[#t.history + 1] = t.entry
  t.entry = table.remove(t.future)
  render()
end

local function reload()
  local t = tab()
  if not t then return end
  local url = t.target or (t.entry and t.entry.url)
  if url then navigate(t, url, { push = false }) end
end

local function stop()
  local t = tab()
  if t and t.job then
    t.job:cancel()
    arrived(t, t.job)
  end
end

local function up()
  local t = tab()
  local url = t and t.entry and t.entry.url
  local parent = url and net.parent(url)
  if parent then open(parent) end
end

---------------------------------------------------------------- bookmarks

local baseMenu = frm.Menu1.items

-- checks is whether each toggle of the menus is on.
local function checks()
  local t = tabs[current]
  return { mnuMono = settings.mono, mnuTerminal = settings.terminal, mnuSource = t and t.source or false,
    mnuOutline = settings.outline }
end

-- updateMenu lists the bookmarks in their menu, after its own items, and
-- puts the toggles as they are.
updateMenu = function()
  local on = checks()
  local items = {}
  for i, top in ipairs(baseMenu) do
    if type(top) == "table" and type(top[2]) == "table" and top[1] ~= "&Bookmarks" and top[1] ~= "&History" then
      local sub = {}
      for j, it in ipairs(top[2]) do
        if type(it) == "table" and it.name and on[it.name] ~= nil then
          local copy = {}
          for k, v in pairs(it) do copy[k] = v end
          copy.checked = on[it.name] and true or false
          sub[j] = copy
        else
          sub[j] = it
        end
      end
      items[i] = { top[1], sub }
    elseif type(top) == "table" and top[1] == "&Bookmarks" then
      local sub = {}
      for j, it in ipairs(top[2]) do sub[j] = it end
      if #settings.bookmarks > 0 then sub[#sub + 1] = "-" end
      for _, b in ipairs(settings.bookmarks) do
        -- A / would make a submenu, and & marks a letter.
        local caption = b.title:gsub("&", "&&"):gsub("/", "∕")
        local url = b.url
        sub[#sub + 1] = { caption, function() open(url) end }
      end
      items[i] = { top[1], sub }
    elseif type(top) == "table" and top[1] == "&History" then
      local sub = {}
      for j, it in ipairs(top[2]) do sub[j] = it end
      local recent = store.recent(settings, nil, 15)
      if #recent > 0 then sub[#sub + 1] = "-" end
      for _, h in ipairs(recent) do
        local caption = h.title:gsub("&", "&&"):gsub("/", "∕")
        if #caption > 50 then caption = caption:sub(1, 49):gsub("[\192-\255][\128-\191]*$", "") .. "…" end
        local url = h.url
        sub[#sub + 1] = { caption, function() open(url) end }
      end
      items[i] = { top[1], sub }
    else
      items[i] = top
    end
  end
  frm.Menu1.items = items
  updateButtons()
  -- The home page lists them too.
  for _, t in ipairs(tabs) do
    if t.entry and t.entry.url == HOME then
      t.entry = ownPage(HOME)
      refresh(t)
    end
  end
end

-- bookmark adds the page shown, or renames or removes it if it is there.
local function bookmark()
  local t = tab()
  local e = t and t.entry
  if not e or not e.url then return end
  local i = store.find(settings, e.url)
  local title = gui.inputbox(i and "Rename the bookmark, or clear the name to remove it:"
    or "Bookmark this page as:", "Bookmark", i and settings.bookmarks[i].title or e.title or e.url)
  if not title then return end
  title = title:match("^%s*(.-)%s*$")
  if title == "" then
    if i then store.unbookmark(settings, i) end
  else
    store.bookmark(settings, title, e.url)
  end
  store.save(settings)
  updateMenu()
end

-- showHistory lists the pages seen, to open one, here or in a new tab.
local function showHistory()
  local url, inNew = historyForm.browse(settings)
  store.save(settings)
  updateMenu()
  if url then
    if inNew then newTab(url) else open(url) end
  end
end

local function clearHistory()
  if gui.msgbox("Forget every page visited?", "yesno", "Clear History") ~= "yes" then return end
  store.clearHistory(settings)
  store.save(settings)
  updateMenu()
end

local function manageBookmarks()
  local url = bookmarksForm.manage(settings)
  store.save(settings)
  updateMenu()
  if url then open(url) end
end

---------------------------------------------------------------- saving and finding

-- save writes what came as a file the user names: a page, or a download.
function frm.save(d)
  if not d then
    local e = tab() and tab().entry
    if not e or not e.body then return end
    d = { url = e.url, body = e.body, name = e.name or "page.txt" }
  end
  local path = gui.savefile { title = "Save " .. d.name, file = d.name }
  if not path then
    status("Not saved")
    return
  end
  local f, err = io.open(path, "wb")
  if not f then
    gui.msgbox("Could not save it: " .. tostring(err), "ok", "Save")
    return
  end
  f:write(d.body)
  f:close()
  status(("Saved %s (%.1f KB)"):format(path, #d.body / 1024))
end

-- countFound says how many times what is in the find box is on the page.
countFound = function()
  local words = frm.txtFind.text
  if words == "" then
    frm.lblFound.caption = ""
    return
  end
  local n, which = view:matches(words)
  frm.lblFound.caption = n == 0 and "not found" or (which > 0 and ("%d of %d"):format(which, n) or ("%d found"):format(n))
end

-- findNext goes to the next match of what is in the find box (the one
-- before, with back); with the bar away, of what was last looked for.
local function findNext(back)
  local words = findOn and frm.txtFind.text or lastFind
  if words == "" then words = lastFind end
  if words == "" then
    find()
    return false
  end
  lastFind = words
  local found = view:search(words, back)
  if findOn then
    countFound()
  elseif found then
    local n, which = view:matches(words)
    status(("“%s”: %d of %d"):format(words, which, n))
  end
  if not found then status("“" .. words .. "” is not on this page") end
  return found
end

-- find opens the find bar, with what is selected in it when that is a line.
find = function()
  local sel = view:selectedText()
  showFind(true)
  if sel ~= "" and not sel:find("\n") then frm.txtFind.text = sel end
  frm.txtFind:focus()
  countFound()
end

local function closeFind()
  showFind(false)
  view:focus()
end

function frm.txtFind:onChange()
  lastFind = self.text ~= "" and self.text or lastFind
  countFound()
end

function frm.txtFind:onKey(key)
  if key == "Enter" then findNext(false) return true end
  if key == "Shift+Enter" then findNext(true) return true end
  if key == "Escape" then closeFind() return true end
  return false
end

function frm.cmdFindNext:onClick() findNext(false) end
function frm.cmdFindPrev:onClick() findNext(true) end
function frm.cmdFindClose:onClick() closeFind() end

---------------------------------------------------------------- the controls

function view:onLink(url)
  if url:find("^#") then return false end
  open(url)
  return true
end

local function linkMenu()
  local items = {}
  if hovered then
    local url = hovered
    items[#items + 1] = { "Open Link in New &Tab", function() newTab(url, true) end }
    items[#items + 1] = { "&Copy Link Address", function() gui.clipboard(url) end }
    items[#items + 1] = "-"
  end
  items[#items + 1] = { "&Back", back }
  items[#items + 1] = { "&Forward", forward }
  items[#items + 1] = { "&Reload", reload }
  items[#items + 1] = "-"
  items[#items + 1] = { "Bookmark This &Page...", bookmark }
  items[#items + 1] = { "Copy", function() view:copy() end }
  return items
end

function view:onHover(url)
  hovered = url
  if url then status(url) else
    local t = tab()
    if t and not t.job then status(t.entry and t.entry.status) end
  end
  view.contextMenu = linkMenu()
end

function address:onKey(key)
  if key == "Enter" then
    open(address.text)
    view:focus()
    return true
  end
  if key == "Escape" then
    local t = tab()
    address.text = t and (t.target or (t.entry and t.entry.url)) or ""
    view:focus()
    return true
  end
end

frm.cmdBack.onClick = function() back() end
frm.cmdForward.onClick = function() forward() end
frm.cmdReload.onClick = function() reload() end
frm.cmdStop.onClick = function() stop() end
frm.cmdHome.onClick = function() open(settings.home) end
frm.cmdBookmark.onClick = function() bookmark() end
frm.cmdBookmarked.onClick = function() bookmark() end

local applyLook -- below

local function textSize(by)
  settings.textSize = math.max(10, math.min(32, settings.textSize + by))
  applyLook()
  store.save(settings)
end

local function toggleSource()
  local t = tab()
  if not t then return end
  t.source = not t.source
  render()
  updateMenu()
end

-- applyLook draws pages in a fixed font, a VGA one if there is one, and in
-- a terminal's colours, or not, as the settings say.
local fixedFont
applyLook = function()
  local face = ""
  if settings.mono then
    fixedFont = fixedFont or look.fixedFont(gui.fonts())
    face = fixedFont
  end
  view.face = face
  -- A VGA font is drawn sharp at 16, its own size.
  local size = settings.textSize
  if look.isVGA(face) and size == 15 then size = 16 end
  view.textSize = size
  view.colors = settings.terminal and look.terminal or nil
  frm.lblStatus.color = settings.terminal and look.status.color or "#ececec"
  frm.lblStatus.textColor = settings.terminal and look.status.textColor or "#404040"
  frm.lblStatus.font = face ~= "" and face or "sans"
end

-- toggleOutline shows the sidebar of the page's headings, or puts it away.
local function toggleOutline()
  settings.outline = not settings.outline
  layoutOutline()
  refreshOutline()
  updateMenu()
  store.save(settings)
end

local function toggleLook(key)
  settings[key] = not settings[key]
  applyLook()
  updateMenu()
  store.save(settings)
end

local actions = {
  mnuNewTab = function() newTab() end,
  mnuCloseTab = function() closeTab(current) end,
  mnuAddress = function() address:focus() end,
  mnuSave = function() frm.save() end,
  mnuExit = function() frm:close() end,
  mnuCopy = function() view:copy() end,
  mnuSelectAll = function() view:selectAll() end,
  mnuFind = find,
  mnuFindNext = function() findNext(false) end,
  mnuFindPrev = function() findNext(true) end,
  mnuHistory = function() showHistory() end,
  mnuClearHistory = function() clearHistory() end,
  mnuReload = reload,
  mnuStop = stop,
  mnuSource = toggleSource,
  mnuOutline = toggleOutline,
  mnuMono = function() toggleLook("mono") end,
  mnuTerminal = function() toggleLook("terminal") end,
  mnuLarger = function() textSize(1) end,
  mnuSmaller = function() textSize(-1) end,
  mnuBack = back,
  mnuForward = forward,
  mnuUp = up,
  mnuHome = function() open(settings.home) end,
  mnuNextTab = function() select(current % #tabs + 1) end,
  mnuPrevTab = function() select((current - 2) % #tabs + 1) end,
  mnuBookmark = bookmark,
  mnuManage = manageBookmarks,
  mnuHelp = function() newTab(HELP) end,
  mnuAbout = function()
    gui.msgbox("microbrowser\n\nA browser for Gemini and Gopher, written in tlua.\n"
      .. "Pages are fetched over LuaSocket and LuaSec, as tlua carries them.", "ok", "About microbrowser")
  end,
}

function frm.Menu1:onClick(name)
  local fn = name and actions[name]
  if fn then fn() end
end

function frm:onKey(key)
  if key == "Escape" then stop() return true end
  if key == "Alt+Left" then back() return true end
  if key == "Alt+Right" then forward() return true end
end

-- What is open is kept for next time.
function frm:onClose()
  local open = {}
  for _, t in ipairs(tabs) do
    local url = t.target or (t.entry and t.entry.url) or t.lazy
    if url then open[#open + 1] = url end
  end
  settings.tabs = open
  store.save(settings)
end

---------------------------------------------------------------- starting

applyLook()
layoutOutline()
view.contextMenu = linkMenu()
updateMenu()

-- An address on the command line opens in a tab of its own, after the
-- tabs that were open last time; those load when they are picked.
local start = arg and arg[1]
for _, url in ipairs(settings.tabs) do
  tabs[#tabs + 1] = { history = {}, future = {}, lazy = url }
end
if start and start ~= "" then
  current = #tabs
  newTab(start)
elseif #tabs > 0 then
  select(1)
else
  newTab(HOME)
end
gui.after(0, function() view:focus() end)

-- Exposed for the tests.
frm.poll = poll
frm.open, frm.newTab, frm.closeTab, frm.pick = open, newTab, closeTab, select
frm.back, frm.forward, frm.reload, frm.stop, frm.up = back, forward, reload, stop, up
frm.bookmark = bookmark
frm.toggleLook = toggleLook
frm.toggleOutline = toggleOutline
frm.outline = function() return outline end
frm.settings = function() return settings end
frm.state = function() return tabs, current end

return frm
