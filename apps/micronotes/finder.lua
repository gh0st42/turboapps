-- Finding and replacing in plain text, with no GUI in it: what the Find
-- dialog does in the Source view, where a note is a text box. A match is
-- text found, by the options matchCase, whole (a whole word) and wrap
-- (round the end, on unless false); positions are bytes counted from 1, and
-- a match is its first and last byte.
--
--   local finder = require "finder"
--   finder.find("one two one", "one", 2)          --> 9  11

local M = {}

local function fold(s, matchCase) return matchCase and s or s:lower() end

local function isWord(c)
  return c ~= nil and (c >= 128 or string.char(c):match("[%w_]") ~= nil)
end

-- scan finds the first match at or after from: its first and last byte.
local function scan(text, needle, from, opts)
  local hay, pat = fold(text, opts.matchCase), fold(needle, opts.matchCase)
  while true do
    local i, j = hay:find(pat, from, true)
    if not i then return nil end
    if not opts.whole or (not isWord(text:byte(i - 1)) and not isWord(text:byte(j + 1))) then return i, j end
    from = i + 1
  end
end

-- find is the first match from byte from on, going round to the start when
-- there is none after (unless wrap is false).
function M.find(text, needle, from, opts)
  opts = opts or {}
  if needle == "" then return nil end
  from = math.max(1, from or 1)
  local i, j = scan(text, needle, from, opts)
  if not i and opts.wrap ~= false and from > 1 then i, j = scan(text, needle, 1, opts) end
  return i, j
end

-- findBack is the last match that ends before byte before, round again from
-- the end when there is none.
function M.findBack(text, needle, before, opts)
  opts = opts or {}
  if needle == "" then return nil end
  local function last(limit)
    local fi, fj, at = nil, nil, 1
    while true do
      local i, j = scan(text, needle, at, opts)
      if not i or j >= limit then break end
      fi, fj, at = i, j, i + 1
    end
    return fi, fj
  end
  local i, j = last(before or #text + 1)
  if not i and opts.wrap ~= false then i, j = last(#text + 1) end
  return i, j
end

-- count is how many matches there are, and which of them starts at byte at.
function M.count(text, needle, opts, at)
  opts = opts or {}
  if needle == "" then return 0, 0 end
  local n, which, from = 0, 0, 1
  while true do
    local i, j = scan(text, needle, from, opts)
    if not i then break end
    n = n + 1
    if i == at then which = n end
    from = i + 1
  end
  return n, which
end

-- matches says whether a selection is a match of needle as it stands.
function M.matches(selection, needle, opts)
  opts = opts or {}
  if needle == "" or selection == "" then return false end
  local i, j = scan(selection, needle, 1, opts)
  return i == 1 and j == #selection
end

-- replaceAll gives the text with every match replaced, and how many were.
function M.replaceAll(text, needle, replacement, opts)
  opts = opts or {}
  if needle == "" then return text, 0 end
  local parts, at, n = {}, 1, 0
  while true do
    local i, j = scan(text, needle, at, opts)
    if not i then break end
    parts[#parts + 1] = text:sub(at, i - 1)
    parts[#parts + 1] = replacement
    at, n = j + 1, n + 1
  end
  parts[#parts + 1] = text:sub(at)
  return table.concat(parts), n
end

return M
