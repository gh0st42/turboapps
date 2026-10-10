-- Workbooks on disk. A .zms file is a zip archive:
--
--   workbook.json                  the sheets, in order, and how each looks
--   sheets/Sheet1.csv              a sheet's values, as any program reads them
--   sheets/Sheet1.formulas.json    the cells whose CSV value is not what was
--                                  typed: formulas ("=SUM(A1:A3)") and text
--                                  kept as text ("'007"), by cell ("B4")
--
-- The CSV has what each formula worked out to, so a sheet unzipped is
-- still a sheet. Reading takes the CSV, then puts the formulas back.
--
-- Plain .csv, .tsv and .txt files open too, as a workbook of one sheet.

local zip = require "zip"
local lfs = require "lfs"
local book = require "book"
local csv = require "csv"
local json = require "json"
local formula = require "formula"

local M = {}

M.EXT = "zms"
M.MANIFEST = "workbook.json"

local function readFile(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local data = f:read("*a")
  f:close()
  return data
end

-- writeFile writes beside the file and renames over it, so a failed write
-- leaves the old file be.
local function writeFile(path, data)
  local tmp = path .. ".tmp"
  local f, err = io.open(tmp, "wb")
  if not f then return nil, err end
  local ok, werr = f:write(data)
  f:close()
  if not ok then os.remove(tmp) return nil, werr end
  os.remove(path)
  local rok, rerr = os.rename(tmp, path)
  if not rok then os.remove(tmp) return nil, rerr end
  return true
end
M.writeFile = writeFile

function M.basename(path) return (path:match("[^/\\]+$") or path) end
function M.extension(path) return (M.basename(path):match("%.([^.]+)$") or ""):lower() end
function M.stem(path) return (M.basename(path):gsub("%.[^.]+$", "")) end

-- isCSV says the file is read as delimited text rather than a workbook.
function M.isCSV(path)
  local ext = M.extension(path)
  return ext == "csv" or ext == "tsv" or ext == "txt"
end

---------------------------------------------------------------- a sheet as CSV

-- rows gives a sheet as rows of fields: what each cell shows for a
-- formula, what was typed for the rest, ending each row at its last cell.
local function sheetRows(b, s)
  local rows = {}
  for r = 1, s.rows do
    local row = {}
    local cells = s.cells[r]
    if cells then
      local last = 0
      for c in pairs(cells) do if c > last then last = c end end
      for c = 1, last do
        local raw = cells[c]
        if raw == nil then row[c] = ""
        elseif book.isFormula(raw) then row[c] = b:display(s, r, c)
        elseif raw:sub(1, 1) == "'" then row[c] = raw:sub(2)
        else row[c] = raw end
      end
    end
    rows[r] = row
  end
  return rows
end

-- kept lists the cells that need more than the CSV says.
local function keptCells(s)
  local out = json.object({})
  s:each(function(r, c, raw)
    if book.isFormula(raw) or raw:sub(1, 1) == "'" then out[formula.refName(r, c)] = raw end
  end)
  return out
end

local function fillSheet(s, rows)
  for r, row in ipairs(rows) do
    for c, field in ipairs(row) do
      if field ~= "" then s:put(r, c, field) end
    end
  end
end

-- csvText writes one sheet as delimited text.
function M.csvText(b, s, sep)
  return csv.write(sheetRows(b, s), sep)
end

---------------------------------------------------------------- saving

-- fileName makes a sheet's name safe as a file name in the archive.
local function fileName(name, used)
  local base = name:gsub("[^%w%-_ ]", "_"):gsub("^%s+", ""):gsub("%s+$", "")
  if base == "" then base = "sheet" end
  local candidate, n = base, 2
  while used[candidate:lower()] do
    candidate = base .. "_" .. n
    n = n + 1
  end
  used[candidate:lower()] = true
  return candidate
end

-- encode gives the bytes of a .zms file.
function M.encode(b)
  local w = zip.create()
  local manifest = { app = "microsheets", version = 1, active = b.active, sheets = {} }
  local used = {}
  local files = {}
  for i, s in ipairs(b.sheets) do
    local stem = "sheets/" .. fileName(s.name, used)
    local entry = { name = s.name, values = stem .. ".csv" }
    local kept = keptCells(s)
    if next(kept) then
      entry.formulas = stem .. ".formulas.json"
      files[#files + 1] = { entry.formulas, json.encode(kept, "  ") .. "\n" }
    end
    if s.frozen then entry.frozen = true end
    local widths = json.object({})
    for c, px in pairs(s.widths) do
      if px ~= book.DEFAULT_WIDTH then widths[formula.colName(c)] = px end
    end
    if next(widths) then entry.widths = widths end
    files[#files + 1] = { entry.values, M.csvText(b, s) }
    manifest.sheets[i] = entry
  end
  w:add(M.MANIFEST, json.encode(manifest, "  ") .. "\n")
  for _, f in ipairs(files) do w:add(f[1], f[2]) end
  return w:close()
end

function M.save(path, b)
  local bytes, err = M.encode(b)
  if not bytes then return nil, err end
  return writeFile(path, bytes)
end

---------------------------------------------------------------- loading

-- decode reads the bytes of a .zms file into a workbook.
function M.decode(data)
  local z, err = zip.load(data)
  if not z then return nil, "not a workbook: " .. tostring(err) end
  local text = z:read(M.MANIFEST)
  if not text then return nil, "not a workbook: it has no " .. M.MANIFEST end
  local manifest, jerr = json.decode(text)
  if not manifest or type(manifest.sheets) ~= "table" then return nil, "a broken " .. M.MANIFEST .. ": " .. tostring(jerr) end
  local b = book.new()
  b.sheets = {}
  for _, entry in ipairs(manifest.sheets) do
    if type(entry.name) ~= "string" then return nil, "a sheet in " .. M.MANIFEST .. " has no name" end
    local s = book.newSheet(entry.name)
    local values = type(entry.values) == "string" and z:read(entry.values)
    if values then fillSheet(s, csv.parse(values)) end
    if type(entry.formulas) == "string" then
      local ftext = z:read(entry.formulas)
      local kept = ftext and json.decode(ftext)
      if type(kept) == "table" then
        for ref, raw in pairs(kept) do
          local r, c = formula.parseRef(ref)
          if r and type(raw) == "string" then s:put(r, c, raw) end
        end
      end
    end
    s.frozen = entry.frozen == true
    if type(entry.widths) == "table" then
      for col, px in pairs(entry.widths) do
        if type(px) == "number" and col:find("^%a+$") then s.widths[formula.colIndex(col)] = math.max(book.MIN_WIDTH, px) end
      end
    end
    b.sheets[#b.sheets + 1] = s
  end
  if #b.sheets == 0 then b.sheets[1] = book.newSheet("Sheet1") end
  b.active = math.max(1, math.min(tonumber(manifest.active) or 1, #b.sheets))
  b:recalc()
  return b
end

-- importCSV reads delimited text as a workbook of one sheet named name.
function M.importCSV(text, name, sep)
  sep = sep or csv.detect(text)
  local b = book.new()
  local s = b.sheets[1]
  s.name = name or "Sheet1"
  fillSheet(s, csv.parse(text, sep))
  b:recalc()
  return b, sep
end

-- load opens a workbook, or a CSV file as one. It returns the workbook
-- and, for a CSV file, the separator it uses.
function M.load(path)
  local data, err = readFile(path)
  if not data then return nil, err end
  if M.isCSV(path) and data:sub(1, 2) ~= "PK" then
    local name = M.stem(path):gsub("[%[%]%*%?/\\:]", "_"):sub(1, 31)
    local sep = M.extension(path) == "tsv" and "\t" or nil
    return M.importCSV(data, name, sep)
  end
  return M.decode(data)
end

---------------------------------------------------------------- exporting

-- exportCSV writes one sheet as a CSV file (or TSV, by its extension).
function M.exportCSV(path, b, s, sep)
  sep = sep or (M.extension(path) == "tsv" and "\t" or ",")
  return writeFile(path, M.csvText(b, s, sep))
end

-- jsonValue is a value as JSON has it: errors become their text.
local function jsonValue(v)
  if v == nil then return json.null end
  if formula.isError(v) then return v.err end
  return v
end

-- exportJSON writes one sheet's values. With header, row 1 names the
-- fields and each row after is an object; otherwise each row is a list.
function M.jsonText(b, s, header)
  local out = {}
  if header then
    local names = {}
    for c = 1, s.cols do
      local n = b:display(s, 1, c)
      names[c] = n ~= "" and n or formula.colName(c)
    end
    for r = 2, s.rows do
      local obj = json.object({})
      for c = 1, s.cols do obj[names[c]] = jsonValue(b:value(s, r, c)) end
      out[#out + 1] = obj
    end
  else
    for r = 1, s.rows do
      local row = {}
      for c = 1, s.cols do row[c] = jsonValue(b:value(s, r, c)) end
      out[r] = row
    end
  end
  return json.encode(out, "  ") .. "\n"
end

function M.exportJSON(path, b, s, header)
  return writeFile(path, M.jsonText(b, s, header))
end

---------------------------------------------------------------- settings

M.defaults = { vimKeys = true, theme = "Light", showFormulas = false }

-- settingsFile, when set, is where the settings are kept instead; the
-- tests use it to keep away from the real ones.
M.settingsFile = nil

function M.settingsPath()
  if M.settingsFile then return M.settingsFile end
  local base = os.getenv("XDG_CONFIG_HOME")
  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or "."
  if package.config:sub(1, 1) == "\\" then base = base or os.getenv("APPDATA") end
  base = base or (home .. "/.config")
  return base .. "/turboapps/microsheets.json"
end

function M.loadSettings(path)
  local s = {}
  for k, v in pairs(M.defaults) do s[k] = v end
  local text = readFile(path or M.settingsPath())
  local t = text and json.decode(text)
  if type(t) == "table" then
    for k, v in pairs(t) do
      if M.defaults[k] ~= nil and type(v) == type(M.defaults[k]) then s[k] = v end
    end
  end
  return s
end

function M.saveSettings(s, path)
  path = path or M.settingsPath()
  local dir = path:match("^(.*)[/\\]")
  if dir then
    lfs.mkdir(dir:match("^(.*)[/\\]") or dir)
    lfs.mkdir(dir)
  end
  local t = json.object({})
  for k in pairs(M.defaults) do t[k] = s[k] end
  return writeFile(path, json.encode(t, "  ") .. "\n")
end

return M
