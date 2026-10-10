-- JSON in and out, as much of it as a workbook needs: objects, arrays,
-- strings, numbers, true, false and null. encode writes an object's keys
-- sorted, so the same workbook always gives the same bytes.

local M = {}

-- M.null stands for JSON's null inside decoded tables.
M.null = setmetatable({}, { __tostring = function() return "null" end })

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function quote(s)
  return '"' .. s:gsub('[%c"\\]', function(ch)
    return ESCAPES[ch] or ("\\u%04x"):format(ch:byte())
  end) .. '"'
end

-- isArray says t is a list: keys 1..n and nothing else. An empty table is
-- written as an array unless it is marked with M.object.
local objects = setmetatable({}, { __mode = "k" })
function M.object(t) objects[t] = true return t end

local function isArray(t)
  if objects[t] then return false end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  for i = 1, n do if t[i] == nil then return false end end
  return true
end

local function encode(v, indent, depth, out)
  local kind = type(v)
  if v == nil or v == M.null then
    out[#out + 1] = "null"
  elseif kind == "boolean" then
    out[#out + 1] = tostring(v)
  elseif kind == "number" then
    if v ~= v or v == math.huge or v == -math.huge then error("json: cannot write " .. tostring(v)) end
    if v == math.floor(v) and math.abs(v) < 1e15 then
      out[#out + 1] = ("%d"):format(v)
    else
      out[#out + 1] = ("%.17g"):format(v)
    end
  elseif kind == "string" then
    out[#out + 1] = quote(v)
  elseif kind == "table" then
    local pad = indent and ("\n" .. indent:rep(depth + 1)) or ""
    local close = indent and ("\n" .. indent:rep(depth)) or ""
    local sep = indent and ": " or ":"
    if isArray(v) then
      if #v == 0 then out[#out + 1] = "[]" return end
      out[#out + 1] = "["
      for i, x in ipairs(v) do
        out[#out + 1] = (i > 1 and "," or "") .. pad
        encode(x, indent, depth + 1, out)
      end
      out[#out + 1] = close .. "]"
    else
      local keys = {}
      for k in pairs(v) do
        if type(k) ~= "string" then error("json: object keys must be strings") end
        keys[#keys + 1] = k
      end
      if #keys == 0 then out[#out + 1] = "{}" return end
      table.sort(keys)
      out[#out + 1] = "{"
      for i, k in ipairs(keys) do
        out[#out + 1] = (i > 1 and "," or "") .. pad .. quote(k) .. sep
        encode(v[k], indent, depth + 1, out)
      end
      out[#out + 1] = close .. "}"
    end
  else
    error("json: cannot write a " .. kind)
  end
end

-- encode writes v as JSON; indent ("  ") spreads it over lines.
function M.encode(v, indent)
  local out = {}
  encode(v, indent, 0, out)
  return table.concat(out)
end

---------------------------------------------------------------- decoding

local function utf8(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
  if cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
  end
  return string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64,
    0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

local UNESCAPE = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }

-- decode reads JSON text; on bad input it returns nil and where it went wrong.
function M.decode(s)
  local i = 1
  local function fail(what) error({ json = ("json: %s at byte %d"):format(what, i) }) end
  local function skip() i = s:find("[^ \t\r\n]", i) or #s + 1 end
  local value

  local function str()
    i = i + 1
    local out = {}
    while true do
      local j = s:find('["\\]', i)
      if not j then fail("unfinished string") end
      out[#out + 1] = s:sub(i, j - 1)
      if s:sub(j, j) == '"' then i = j + 1 break end
      local e = s:sub(j + 1, j + 1)
      if e == "u" then
        local cp = tonumber(s:sub(j + 2, j + 5), 16)
        if not cp then fail("bad \\u escape") end
        i = j + 6
        if cp >= 0xD800 and cp < 0xDC00 and s:sub(i, i + 1) == "\\u" then
          local lo = tonumber(s:sub(i + 2, i + 5), 16)
          if lo and lo >= 0xDC00 and lo < 0xE000 then
            cp = 0x10000 + (cp - 0xD800) * 1024 + (lo - 0xDC00)
            i = i + 6
          end
        end
        out[#out + 1] = utf8(cp)
      elseif UNESCAPE[e] then
        out[#out + 1] = UNESCAPE[e]
        i = j + 2
      else
        fail("bad escape")
      end
    end
    return table.concat(out)
  end

  function value()
    skip()
    local ch = s:sub(i, i)
    if ch == "{" then
      i = i + 1
      local t = M.object({})
      skip()
      if s:sub(i, i) == "}" then i = i + 1 return t end
      while true do
        skip()
        if s:sub(i, i) ~= '"' then fail("expected a key") end
        local k = str()
        skip()
        if s:sub(i, i) ~= ":" then fail("expected ':'") end
        i = i + 1
        t[k] = value()
        skip()
        local c = s:sub(i, i)
        i = i + 1
        if c == "}" then return t end
        if c ~= "," then fail("expected ',' or '}'") end
      end
    elseif ch == "[" then
      i = i + 1
      local t = {}
      skip()
      if s:sub(i, i) == "]" then i = i + 1 return t end
      while true do
        t[#t + 1] = value()
        skip()
        local c = s:sub(i, i)
        i = i + 1
        if c == "]" then return t end
        if c ~= "," then fail("expected ',' or ']'") end
      end
    elseif ch == '"' then
      return str()
    elseif s:sub(i, i + 3) == "true" then i = i + 4 return true
    elseif s:sub(i, i + 4) == "false" then i = i + 5 return false
    elseif s:sub(i, i + 3) == "null" then i = i + 4 return M.null
    else
      local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
      if not num or num == "" or num == "-" then fail("unexpected " .. (ch == "" and "end" or ("'" .. ch .. "'"))) end
      i = i + #num
      return tonumber(num) or fail("bad number")
    end
  end

  local ok, result = pcall(function()
    local v = value()
    skip()
    if i <= #s then fail("text after the value") end
    return v
  end)
  if ok then return result end
  if type(result) == "table" and result.json then return nil, result.json end
  error(result, 0)
end

return M
