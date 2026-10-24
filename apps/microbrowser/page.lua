-- What a page shows: gemtext, Gopher menus and plain text turned into the
-- Markdown a MarkdownView draws, every link made whole. No GUI in it.
--
--   local text, title = page.gemtext(body, "gemini://example.org/")
--
-- The Markdown is built as markdown's blocks and written by it, so what the
-- page says is never read as markup.

local md = require "markdown"
local net = require "net"

local M = {}

local function text(s) return { text = s } end
local function link(s, to) return { text = s, link = to } end
local function tag(s) return { text = s, code = true } end

-- Paragraph gathers lines into one paragraph, a line break between them.
local function paragraphs(blocks)
  local cur
  local p = {}
  function p.line(runs)
    if cur then cur.runs[#cur.runs + 1] = text("\n")
    else
      cur = { type = "p", runs = {} }
      blocks[#blocks + 1] = cur
    end
    for _, r in ipairs(runs) do cur.runs[#cur.runs + 1] = r end
  end
  function p.stop() cur = nil end
  return p
end

-- tidy takes out control characters a page should not have drawn; tabs
-- become spaces unless they are kept.
local function tidy(s, keepTabs)
  s = s:gsub("\r", "")
  if not keepTabs then s = s:gsub("\t", "    ") end
  return (s:gsub("[%z\1-\8\11-\31\127]", ""))
end

local function finish(blocks) return md.write(blocks) end

---------------------------------------------------------------- gemtext

-- gemtext turns a text/gemini page into Markdown, and gives its title: its
-- first heading. Links are made whole against base.
function M.gemtext(body, base)
  local blocks, title = {}, nil
  local para = paragraphs(blocks)
  local pre
  local src = tidy(body)
  if src:sub(-1) ~= "\n" then src = src .. "\n" end
  for line in src:gmatch("(.-)\n") do
    if pre then
      if line:find("^```") then
        pre.runs[1].text = table.concat(pre.lines, "\n")
        pre.lines = nil
        pre = nil
      else
        pre.lines[#pre.lines + 1] = line
      end
    elseif line:find("^```") then
      para.stop()
      pre = { type = "code", runs = { text("") }, lines = {} }
      blocks[#blocks + 1] = pre
    elseif line:find("^=>") then
      local target, label = line:match("^=>%s*(%S+)%s*(.*)$")
      if target then
        local to = net.absolute(base, target)
        if label == "" then label = target end
        local scheme = to:match("^(%a[%w+.-]*):") or ""
        local mark = (scheme == "gemini" or scheme == "gopher") and "→ " or "⇗ "
        para.line { text(mark), link(label, to) }
      end
    elseif line:find("^#") then
      para.stop()
      local hashes, words = line:match("^(#+)%s*(.*)$")
      local level = math.min(#hashes, 3)
      blocks[#blocks + 1] = { type = "h" .. level, runs = { text(words) } }
      if not title and words ~= "" then title = words end
    elseif line:find("^%* ") or line == "*" then
      para.stop()
      blocks[#blocks + 1] = { type = "ul", level = 0, runs = { text(line:sub(3)) } }
    elseif line:find("^>") then
      para.stop()
      blocks[#blocks + 1] = { type = "quote", runs = { text((line:gsub("^>%s?", ""))) } }
    elseif line:find("^%s*$") then
      para.stop()
    else
      para.line { text(line) }
    end
  end
  if pre and pre.lines then pre.runs[1].text = table.concat(pre.lines, "\n") pre.lines = nil end
  return finish(blocks), title
end

---------------------------------------------------------------- gopher

-- What each item type of a menu is, shown before it.
local KINDS = {
  ["0"] = "TXT", ["1"] = "DIR", ["7"] = "ASK", ["h"] = "WWW",
  ["g"] = "IMG", ["I"] = "IMG", ["p"] = "IMG", [":"] = "IMG",
  ["4"] = "BIN", ["5"] = "BIN", ["6"] = "BIN", ["9"] = "BIN",
  [";"] = "BIN", ["<"] = "BIN", ["s"] = "BIN", ["d"] = "DOC",
  ["8"] = "TEL", ["T"] = "TEL", ["2"] = "CSO",
}

-- gopherItems reads a menu: one item a line, type and words, then the
-- selector, host and port between tabs. A "." alone ends it.
function M.gopherItems(body)
  local items = {}
  for line in (body:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
    if line == "." then break end
    if line ~= "" then
      local t, rest = line:sub(1, 1), line:sub(2)
      local display, selector, host, port = rest:match("^([^\t]*)\t?([^\t]*)\t?([^\t]*)\t?([^\t]*)")
      items[#items + 1] = { type = t, display = display or rest, selector = selector or "",
        host = host or "", port = tonumber(port) or 70 }
    end
  end
  return items
end

-- itemURL is where an item of a menu goes: a URL: selector to the web, a
-- telnet item to telnet, the rest to Gopher.
function M.itemURL(item)
  local web = item.selector:match("^/?URL:(.+)$")
  if web then return web end
  if item.type == "8" or item.type == "T" then
    return "telnet://" .. item.host .. (item.port ~= 23 and ":" .. item.port or "")
  end
  if item.host == "" then return nil end
  return net.gopherURL(item.host, item.port, item.type, item.selector)
end

-- gopher turns a menu into Markdown: the words of info lines as they are,
-- a line each, and the items as links with their kind before them.
function M.gopher(body)
  local blocks = {}
  local para = paragraphs(blocks)
  local title
  for _, item in ipairs(M.gopherItems(tidy(body, true))) do
    local words = item.display
    if item.type == "i" or item.type == "3" or item.type == "+" then
      if words:find("^%s*$") then
        para.stop()
      else
        if not title and item.type == "i" then title = words:match("^%s*(.-)%s*$") end
        -- Leading spaces would be lost; a no-break space keeps the indent.
        words = words:gsub("^( +)", function(sp) return ("\194\160"):rep(#sp) end)
        para.line { item.type == "3" and { text = words, b = true } or text(words) }
      end
    else
      local to = M.itemURL(item)
      local kind = tag(KINDS[item.type] or "???")
      if to then
        para.line { kind, text(" "), link(words, to) }
      else
        para.line { kind, text(" " .. words) }
      end
    end
  end
  return finish(blocks), title
end

-- plain shows text as it is, in a fixed font.
function M.plain(body)
  local s = tidy(body)
  return finish { { type = "code", runs = { text((s:gsub("\n%.\n?$", "\n"):gsub("\n+$", ""))) } } }
end

---------------------------------------------------------------- the browser's own pages

-- message is a page of the browser's own: a heading, words, and links.
function M.message(heading, words, links)
  local blocks = { { type = "h1", runs = { text(heading) } } }
  if words and words ~= "" then
    for para in (words .. "\n\n"):gmatch("(.-)\n\n") do
      if para ~= "" then blocks[#blocks + 1] = { type = "p", runs = { text(para) } } end
    end
  end
  for _, l in ipairs(links or {}) do
    blocks[#blocks + 1] = { type = "p", runs = { text("→ "), link(l[1], l[2]) } }
  end
  return finish(blocks)
end

-- picture is a page that is one picture.
function M.picture(name)
  return finish { { type = "image", src = "page-picture", alt = name } }
end

-- home is the start page: the bookmarks, and places to start from.
function M.home(bookmarks)
  local blocks = { { type = "h1", runs = { text("microbrowser") } },
    { type = "p", runs = { text("Gemini and Gopher, in a window. Type an address above, or pick a bookmark.") } } }
  blocks[#blocks + 1] = { type = "h2", runs = { text("Bookmarks") } }
  if #bookmarks == 0 then
    blocks[#blocks + 1] = { type = "p", runs = { text("None yet: Cmd+D bookmarks the page you are on.") } }
  else
    local para = paragraphs(blocks)
    for _, b in ipairs(bookmarks) do para.line { text("★ "), link(b.title, b.url) } end
  end
  blocks[#blocks + 1] = { type = "h2", runs = { text("Places to start") } }
  local para = paragraphs(blocks)
  for _, p in ipairs(M.STARTS) do para.line { text("→ "), link(p[1], p[2]) } end
  return finish(blocks)
end

M.STARTS = {
  { "Project Gemini", "gemini://geminiprotocol.net/" },
  { "Kennedy, a Gemini search engine", "gemini://kennedy.gemi.dev/" },
  { "Antenna, a Gemini feed aggregator", "gemini://warmedal.se/~antenna/" },
  { "Floodgap, a Gopher server since 1999", "gopher://gopher.floodgap.com/" },
  { "Veronica-2, a Gopher search", "gopher://gopher.floodgap.com/1/v2" },
}

-- HELP is the page Help > Using microbrowser opens.
M.HELP = [==[
# Using microbrowser

microbrowser reads **Gemini** capsules (`gemini://`) and **Gopher** holes (`gopher://`). Type an address in the bar at the top and press Enter; an address with no `scheme://` is taken for Gemini. Links to the web and to other programs open in their own programs.

## Tabs

* **Cmd+T** opens a tab, **Cmd+W** closes it; the **+** after the tabs opens one too, and the **×** on a tab, or a middle click, closes it.
* **Ctrl+PageDown** and **Ctrl+PageUp** go to the next and the previous tab.
* A right click on a link opens it in a new tab behind this one. A right click on a tab duplicates it or closes the others.
* The tabs open when microbrowser closes are there again next time, each loaded when it is first picked.

## Moving about

* **Back** (Cmd+[ or Alt+Left) and **Forward** (Cmd+] or Alt+Right) go through the pages of the tab, as they were when you left them.
* **Up** (Cmd+Up) goes to the folder the page is in, or the Gopher menu above it.
* **Reload** (Cmd+R) fetches the page again; **Stop** (Cmd+. or Esc) gives up on one that is loading.
* **Home** (Cmd+Shift+H) is the start page, with your bookmarks.

## Bookmarks

* **Cmd+D**, or the star, bookmarks the page under a name you give it. On a page already bookmarked it renames the bookmark, and clearing the name removes it.
* **Bookmarks > Manage Bookmarks** (Cmd+Shift+B) puts them in order, renames them, changes their addresses and deletes them.
* The bookmarks are in the Bookmarks menu and on the start page.

## Pages

* Gemini pages (`text/gemini`) are shown with their headings, lists, quotes and preformatted text; other text as it is.
* Gopher menus show what each item is before it: `DIR` a menu, `TXT` a text, `ASK` a search, which asks for the words to search for, `IMG` a picture, `BIN` a file, `WWW` the web.
* Pictures (PNG, JPEG and GIF) are shown; other files are offered to be saved.
* **View > Outline** (Cmd+Shift+O) puts the page's headings in a sidebar, indented by level: pick one, with the mouse or the arrows, to go to it. It is there next time if it was when you closed microbrowser.
* **View > Page Source** (Cmd+U) shows the page as it came; **File > Save Page As** (Cmd+S) saves it.
* **Cmd+F** finds words on the page, and **Cmd+G** finds them again. **Cmd+=** and **Cmd+-** make the text larger and smaller.
* **View > Fixed Font** (Cmd+Shift+M) draws pages in a fixed font, as a terminal did, so the pictures Gopher holes draw in letters line up. A VGA font is used if one is installed (Flexi IBM VGA, Perfect DOS VGA 437 and the like), and the computer's fixed font if not.
* **View > Terminal Colours** (Cmd+Shift+E) puts pages in the dark: light grey on black, in the 16 colours of the EGA.
* When a capsule asks for input, microbrowser asks you, and sends what you type.

## Certificates

Gemini capsules mostly sign their own certificates, so there is no authority to check them against. microbrowser trusts a capsule's certificate the first time it sees it and expects the same one after ("trust on first use"). If a capsule shows another, you are asked whether to trust the new one: a capsule may have made a new certificate, or someone may be between you and it.

Client certificates, which a few capsules ask for, are not supported.
]==]

return M
