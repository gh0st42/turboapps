-- The editor's text handling, with no GUI in it: reading and writing files
-- with their line endings kept, finding and replacing, and saying where a
-- position is. Positions are byte offsets, as a TextBox's cursor counts
-- them and string.find returns them.

local M = {}

-- read loads a file as the editor shows it: with "\n" line endings. It
-- returns the text and the ending the file used ("\n" or "\r\n"), or nil
-- and an error.
function M.read(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local data, rerr = f:read("*a")
  f:close()
  if not data then return nil, rerr or "cannot read the file" end
  return M.decode(data)
end

-- decode turns a file's bytes into the editor's text and its line ending.
-- A file is taken as CRLF when most of its lines end that way.
function M.decode(data)
  if data:sub(1, 3) == "\239\187\191" then data = data:sub(4) end -- UTF-8 BOM
  local _, crlf = data:gsub("\r\n", "")
  local _, lf = data:gsub("\n", "")
  local eol = (crlf > 0 and crlf * 2 >= lf) and "\r\n" or "\n"
  data = data:gsub("\r\n", "\n"):gsub("\r", "\n")
  return data, eol
end

-- encode turns the editor's text back into a file's bytes.
function M.encode(text, eol)
  if eol == "\r\n" then return (text:gsub("\n", "\r\n")) end
  return text
end

-- write saves text to path with the given line ending. It writes to a
-- temporary file first and moves it into place, so a failed save does not
-- leave half a file behind.
function M.write(path, text, eol)
  local tmp = path .. ".tmp~"
  local f, err = io.open(tmp, "wb")
  if not f then
    -- The directory may not let us make files: write in place instead.
    f, err = io.open(path, "wb")
    if not f then return nil, err end
    f:write(M.encode(text, eol))
    f:close()
    return true
  end
  local ok, werr = f:write(M.encode(text, eol))
  f:close()
  if not ok then os.remove(tmp) return nil, werr end
  os.remove(path) -- rename does not replace on Windows
  local moved, merr = os.rename(tmp, path)
  if not moved then return nil, merr end
  return true
end

-- basename is a path's last part, for the title bar.
function M.basename(path)
  if not path then return "Untitled" end
  return path:match("([^/\\]+)$") or path
end

-- position says which line and column a byte offset is at, both from 1.
-- Columns count characters, not bytes, so UTF-8 text counts as it reads.
function M.position(text, offset)
  offset = math.max(0, math.min(offset or 0, #text))
  local before = text:sub(1, offset)
  local _, newlines = before:gsub("\n", "")
  local lineStart = (before:match(".*()\n") or 0) + 1
  local col = before:sub(lineStart):gsub("[\128-\191]", "")
  return newlines + 1, #col + 1
end

-- stats counts lines, words and characters.
function M.stats(text)
  local _, newlines = text:gsub("\n", "")
  local _, words = text:gsub("%S+", "")
  local chars = #text:gsub("[\128-\191]", "")
  return { lines = text == "" and 1 or newlines + 1, words = words, chars = chars }
end

local function fold(s, matchCase)
  if matchCase then return s end
  return s:lower()
end

-- find looks for needle in text, from byte from (1-based) onwards. With
-- wrap, it goes round to the start when nothing is found after from. It
-- returns the first and last byte of the match, or nil.
function M.find(text, needle, from, opts)
  opts = opts or {}
  if needle == "" then return nil end
  local hay, pat = fold(text, opts.matchCase), fold(needle, opts.matchCase)
  from = math.max(1, from or 1)
  local i, j = hay:find(pat, from, true)
  if not i and opts.wrap and from > 1 then
    i, j = hay:find(pat, 1, true)
  end
  return i, j
end

-- findBack looks for the last match that ends before byte before.
function M.findBack(text, needle, before, opts)
  opts = opts or {}
  if needle == "" then return nil end
  local hay, pat = fold(text, opts.matchCase), fold(needle, opts.matchCase)
  local function last(limit)
    local found, at = nil, 1
    while true do
      local i, j = hay:find(pat, at, true)
      if not i or j >= limit then break end
      found, at = i, i + 1
    end
    return found
  end
  local i = last(before or #text + 1)
  if not i and opts.wrap then i = last(#text + 1) end
  if i then return i, i + #needle - 1 end
end

-- replaceAll replaces every match of needle and returns the new text and
-- how many were replaced.
function M.replaceAll(text, needle, replacement, opts)
  opts = opts or {}
  if needle == "" then return text, 0 end
  local hay, pat = fold(text, opts.matchCase), fold(needle, opts.matchCase)
  local parts, at, n = {}, 1, 0
  while true do
    local i, j = hay:find(pat, at, true)
    if not i then break end
    parts[#parts + 1] = text:sub(at, i - 1)
    parts[#parts + 1] = replacement
    at, n = j + 1, n + 1
  end
  parts[#parts + 1] = text:sub(at)
  return table.concat(parts), n
end

-- matches says whether a selection is the needle, as find would match it.
function M.matches(selection, needle, opts)
  opts = opts or {}
  return needle ~= "" and fold(selection, opts.matchCase) == fold(needle, opts.matchCase)
end

-- lineOffset is the byte offset of the start of line n (from 1), for
-- going to a line; the end of the text when there are fewer lines.
function M.lineOffset(text, n)
  if n <= 1 then return 0 end
  local line = 1
  for pos in text:gmatch("()\n") do
    line = line + 1
    if line == n then return pos end
  end
  return #text
end

return M
