-- Comma-separated values, as RFC 4180 has them: a field with the
-- separator, a quote or a line break in it is quoted, and a quote inside
-- one is doubled. Other separators work the same way, and detect picks
-- the one a file uses.

local M = {}

-- parse reads text into rows of fields. Lines end in "\n" or "\r\n", and a
-- last line break does not make an empty row.
function M.parse(text, sep)
  sep = sep or ","
  local rows, row, field = {}, {}, {}
  local i, n = 1, #text
  local quoted = false
  if text:sub(1, 3) == "\239\187\191" then i = 4 end -- a byte order mark
  while i <= n do
    local ch = text:sub(i, i)
    if quoted then
      if ch == '"' then
        if text:sub(i + 1, i + 1) == '"' then
          field[#field + 1] = '"'
          i = i + 1
        else
          quoted = false
        end
      else
        local j = text:find('"', i, true) or n + 1
        field[#field + 1] = text:sub(i, j - 1)
        i = j - 1
      end
    elseif ch == '"' and #field == 0 then
      quoted = true
    elseif ch == sep then
      row[#row + 1] = table.concat(field)
      field = {}
    elseif ch == "\n" or ch == "\r" then
      if ch == "\r" and text:sub(i + 1, i + 1) == "\n" then i = i + 1 end
      row[#row + 1] = table.concat(field)
      rows[#rows + 1] = row
      row, field = {}, {}
    else
      local j = text:find("[\r\n\"" .. (sep == "%" and "%%" or sep:gsub("%p", "%%%0")) .. "]", i) or n + 1
      if j == i then j = i + 1 end
      field[#field + 1] = text:sub(i, j - 1)
      i = j - 1
    end
    i = i + 1
  end
  if #field > 0 or #row > 0 then
    row[#row + 1] = table.concat(field)
    rows[#rows + 1] = row
  end
  return rows
end

-- field quotes s when it has to be.
function M.field(s, sep)
  sep = sep or ","
  if s:find('[\r\n"]') or s:find(sep, 1, true) or s:find("^%s") or s:find("%s$") then
    return '"' .. s:gsub('"', '""') .. '"'
  end
  return s
end

-- write joins rows of fields into text, a line to a row, each ending "\n".
-- Rows may be ragged; missing fields are written empty.
function M.write(rows, sep)
  sep = sep or ","
  local out = {}
  for _, row in ipairs(rows) do
    local fields = {}
    for c = 1, #row do fields[c] = M.field(row[c] or "", sep) end
    out[#out + 1] = table.concat(fields, sep) .. "\n"
  end
  return table.concat(out)
end

-- detect guesses the separator from the first lines: the one of comma,
-- semicolon, tab and bar that splits them most evenly into the most fields.
function M.detect(text)
  local lines = {}
  for line in (text:sub(1, 8192) .. "\n"):gmatch("([^\n]*)\n") do
    if line ~= "" then lines[#lines + 1] = line end
    if #lines == 10 then break end
  end
  local best, bestScore = ",", 0
  for _, sep in ipairs({ ",", "\t", ";", "|" }) do
    local counts = {}
    for k, line in ipairs(lines) do
      local _, c = line:gsub(sep == "|" and "|" or sep, "")
      counts[k] = c
    end
    if #counts > 0 and counts[1] > 0 then
      local same = 0
      for _, c in ipairs(counts) do if c == counts[1] then same = same + 1 end end
      local score = counts[1] * same / #counts
      if score > bestScore then best, bestScore = sep, score end
    end
  end
  return best
end

return M
