-- A control of this project's own: a chart of a range's numbers, drawn on
-- a Canvas, as bars, lines, a sparkline or a pie.
--
--   chart.chartType      "bar", "line", "sparkline" or "pie"
--   chart.data      { labels = {...}, series = { { name =, values = {...} } } }
--   chart.theme     a theme's name (themes.lua)
--   chart:snapshot(2)        the chart as a picture, to save as PNG (tlua's)
--
-- chartData (below, as Chart.data) reads a range of a workbook into data.

local gui = require "gui"
local themes = require "themes"
local formula = require "formula"

-- PALETTE colours the series, in order.
local PALETTE = { "#4e79a7", "#f28e2b", "#e15759", "#76b7b2", "#59a14f", "#edc948", "#b07aa1", "#ff9da7", "#9c755f", "#bab0ac" }

local function nice(x)
  if x == 0 then return 0 end
  local e = 10 ^ math.floor(math.log10(math.abs(x)))
  local f = math.abs(x) / e
  local n = f <= 1 and 1 or f <= 2 and 2 or f <= 5 and 5 or 10
  return (x < 0 and -1 or 1) * n * e
end

local function short(n)
  local a = math.abs(n)
  if a >= 1e9 then return formula.formatNumber(n / 1e9, 3) .. "G" end
  if a >= 1e6 then return formula.formatNumber(n / 1e6, 3) .. "M" end
  if a >= 1e4 then return formula.formatNumber(n / 1e3, 3) .. "k" end
  return formula.formatNumber(n, 4)
end

local M = {}

local function range(series)
  local lo, hi = 0, 0
  for _, s in ipairs(series) do
    for _, v in pairs(s.values) do
      if v < lo then lo = v end
      if v > hi then hi = v end
    end
  end
  if lo == hi then hi = lo + 1 end
  return lo, hi
end

local function count(data)
  local n = #data.labels
  for _, s in ipairs(data.series) do n = math.max(n, s.n or #s.values) end
  return n
end

local function legend(g, th, series, x, y)
  for i, s in ipairs(series) do
    g:color(PALETTE[(i - 1) % #PALETTE + 1])
    g:fill(x, y + 4, 10, 10)
    g:color(th.text)
    g:text(s.name, x + 14, y, 200, 18, "left")
    y = y + 18
  end
end

local function axes(self, g, th, W, H)
  local data = self.data
  local lo, hi = range(data.series)
  local step = nice((hi - lo) / 5)
  if step == 0 then step = 1 end
  lo = math.floor(lo / step) * step
  hi = math.ceil(hi / step) * step
  g:font("sans", 11)
  local labelW = 0
  for v = lo, hi + step / 2, step do labelW = math.max(labelW, g:measure(short(v))) end
  local legendW = 0
  for _, s in ipairs(data.series) do legendW = math.max(legendW, g:measure(s.name) + 24) end
  local left, top, right, bottom = labelW + 14, 16, W - math.max(16, legendW + 16), H - 40
  for v = lo, hi + step / 2, step do
    local y = bottom - (v - lo) / (hi - lo) * (bottom - top)
    g:color(th.grid)
    g:line(left, y, right, y)
    g:color(th.headerText)
    g:text(short(v), 0, y - 8, left - 6, 16, "right")
  end
  g:color(th.line)
  local zero = bottom - (0 - lo) / (hi - lo) * (bottom - top)
  g:line(left, zero, right, zero)
  legend(g, th, data.series, right + 12, top)
  return left, top, right, bottom, lo, hi, zero
end

local function xLabels(self, g, th, left, right, bottom, n, centered)
  local labels = self.data.labels
  local slot = (right - left) / math.max(1, centered and n or n - 1)
  local every = math.max(1, math.ceil(60 / math.max(1, slot)))
  g:color(th.headerText)
  for i = 1, n, every do
    local x = centered and left + (i - 0.5) * slot or left + (i - 1) * slot
    g:text(labels[i] or tostring(i), x - slot * every / 2, bottom + 4, slot * every, 16, "center")
  end
end

local function drawBars(self, g, th, W, H)
  local n = count(self.data)
  local left, top, right, bottom, lo, hi, zero = axes(self, g, th, W, H)
  local series = self.data.series
  local slot = (right - left) / math.max(1, n)
  local bw = math.max(1, (slot * 0.8) / math.max(1, #series))
  for i = 1, n do
    for k, s in ipairs(series) do
      local v = s.values[i]
      if v then
        local y = bottom - (v - lo) / (hi - lo) * (bottom - top)
        local x = left + (i - 1) * slot + slot * 0.1 + (k - 1) * bw
        g:color(PALETTE[(k - 1) % #PALETTE + 1])
        g:fill(x, math.min(y, zero), math.max(1, bw - 1), math.max(1, math.abs(zero - y)))
      end
    end
  end
  xLabels(self, g, th, left, right, bottom, n, true)
end

local function drawLines(self, g, th, W, H)
  local n = count(self.data)
  local left, top, right, bottom, lo, hi = axes(self, g, th, W, H)
  local step = (right - left) / math.max(1, n - 1)
  g:width(2)
  for k, s in ipairs(self.data.series) do
    g:color(PALETTE[(k - 1) % #PALETTE + 1])
    local px, py
    for i = 1, n do
      local v = s.values[i]
      if v then
        local x = left + (i - 1) * step
        local y = bottom - (v - lo) / (hi - lo) * (bottom - top)
        if px then g:line(px, py, x, y) end
        g:disc(x, y, 3)
        px, py = x, y
      else
        px = nil
      end
    end
  end
  g:width(1)
  xLabels(self, g, th, left, right, bottom, n, false)
end

-- A sparkline is each series on a line of its own, with no axes.
local function drawSparks(self, g, th, W, H)
  local series = self.data.series
  local n = count(self.data)
  local rowH = math.min(60, (H - 16) / math.max(1, #series))
  g:font("sans", 12)
  local nameW = 0
  for _, s in ipairs(series) do nameW = math.max(nameW, g:measure(s.name)) end
  local left, right = nameW + 24, W - 70
  for k, s in ipairs(series) do
    local y0 = 8 + (k - 1) * rowH
    local min, max
    for _, v in pairs(s.values) do
      min = min and math.min(min, v) or v
      max = max and math.max(max, v) or v
    end
    local lo, hi = min or 0, max or 1
    if lo == hi then hi = lo + 1 end
    g:color(th.text)
    g:text(s.name, 8, y0, nameW + 8, rowH, "left")
    local color = PALETTE[(k - 1) % #PALETTE + 1]
    g:color(color)
    g:width(2)
    local step = (right - left) / math.max(1, n - 1)
    local px, py, lastV
    for i = 1, n do
      local v = s.values[i]
      if v then
        local x = left + (i - 1) * step
        local y = y0 + rowH - 6 - (v - lo) / (hi - lo) * (rowH - 12)
        if px then g:line(px, py, x, y) end
        px, py, lastV = x, y, v
      end
    end
    g:width(1)
    if px then g:disc(px, py, 3) end
    g:color(th.headerText)
    g:text(lastV and short(lastV) or "", right + 8, y0, 60, rowH, "left")
  end
end

local function drawPie(self, g, th, W, H)
  local s = self.data.series[1]
  if not s then return end
  local total = 0
  for _, v in pairs(s.values) do if v > 0 then total = total + v end end
  if total <= 0 then
    g:color(th.headerText)
    g:text("A pie needs numbers above 0.", 0, 0, W, H, "center")
    return
  end
  local d = math.min(W - 220, H - 32)
  local cx, cy = 16, (H - d) / 2
  local a = 90
  g:font("sans", 12)
  local ly = 16
  for i = 1, count(self.data) do
    local v = s.values[i]
    if v and v > 0 then
      local sweep = v / total * 360
      local color = PALETTE[(i - 1) % #PALETTE + 1]
      g:color(color)
      g:pie(cx, cy, d, d, a - sweep, a)
      a = a - sweep
      if ly < H - 18 then
        g:fill(cx + d + 24, ly + 4, 10, 10)
        g:color(th.text)
        local label = self.data.labels[i] or tostring(i)
        g:text(("%s  %s%%"):format(label, formula.formatNumber(math.floor(v / total * 1000 + 0.5) / 10)), cx + d + 40, ly, W - d - 56, 18, "left")
        ly = ly + 18
      end
    end
  end
end

-- paint draws a chart: anything with data, chartType and theme.
local function paint(self, g)
  local th = themes.get(self.theme)
  local W, H = g:size()
  g:color(th.bg)
  g:fill(0, 0, W, H)
  if #self.data.series == 0 then
    g:color(th.headerText)
    g:font("sans", 13)
    g:text("Select numbers to chart: a column or more, with labels in the first column if you like.", 0, 0, W, H, "center")
    return
  end
  g:font("sans", 11)
  if self.chartType == "line" then drawLines(self, g, th, W, H)
  elseif self.chartType == "sparkline" then drawSparks(self, g, th, W, H)
  elseif self.chartType == "pie" then drawPie(self, g, th, W, H)
  else drawBars(self, g, th, W, H) end
end


gui.define {
  name = "Chart",
  props = {
    chartType = { type = "choice", default = "bar", choices = { "bar", "line", "sparkline", "pie" } },
    theme = { type = "string", default = "Light" },
  },
  build = function(parent, opts)
    local c = parent:Canvas { width = 480, height = 300 }
    c.data = { labels = {}, series = {} }

    function c:onDraw(g) paint(self, g) end

    return c
  end,
}

-- data reads a range of a workbook for a chart. Columns of numbers are
-- series; a first column of text gives the labels, and a first row of
-- text the series' names.
function M.data(b, s, r1, c1, r2, c2)
  local function isText(v) return v ~= nil and type(v) ~= "number" end
  local header = false
  for col = c1, c2 do
    if isText(b:value(s, r1, col)) then header = true end
  end
  local numbersInFirstRow = false
  for col = c1, c2 do
    if type(b:value(s, r1, col)) == "number" then numbersInFirstRow = true end
  end
  if numbersInFirstRow and c2 > c1 and isText(b:value(s, r1, c1)) and not isText(b:value(s, r1, c1 + 1)) then header = false end
  local labelCol = false
  local first = header and r1 + 1 or r1
  for r = first, r2 do
    if isText(b:value(s, r, c1)) then labelCol = true end
  end
  if labelCol and c1 == c2 then labelCol = false end
  local data = { labels = {}, series = {} }
  for r = first, r2 do
    local i = r - first + 1
    data.labels[i] = labelCol and formula.text(b:value(s, r, c1)) or tostring(r)
  end
  for col = labelCol and c1 + 1 or c1, c2 do
    local name = header and formula.text(b:value(s, r1, col)) or formula.colName(col)
    local values, any = {}, false
    for r = first, r2 do
      local v = b:value(s, r, col)
      if type(v) == "number" then values[r - first + 1] = v any = true end
    end
    if any then data.series[#data.series + 1] = { name = name, values = values, n = r2 - first + 1 } end
  end
  return data
end

return M
