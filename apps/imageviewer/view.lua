-- How a picture is placed in the view, with no GUI in it: as big as fits, or
-- zoomed to a size of its own and moved about. Pure arithmetic on a view,
-- the table new makes, so all of it is tested directly.
--
--   local v = view.new()                         -- fits, the first
--   local x, y, w, h = view.place(v, iw, ih, W, H) -- where to draw an iw by ih picture in W by H
--   view.zoomBy(v, 1.25, iw, ih, W, H, mx, my)     -- bigger, the point mx, my staying put
--   view.actual(v, iw, ih, W, H)                   -- 100%
--   view.pan(v, dx, dy, iw, ih, W, H)              -- the picture moved dx, dy
--   view.fit(v)

local M = {}

M.MIN, M.MAX = 0.02, 64

local function round(n) return math.floor(n + 0.5) end

local function clamp(n, lo, hi)
  if hi < lo then return lo end
  return math.max(lo, math.min(hi, n))
end

-- new is a view that fits the picture to the window. Once zoomed it has the
-- zoom, and the point of the picture, as fractions of it, at the middle of
-- the window.
function M.new()
  return { mode = "fit", zoom = 1, cx = 0.5, cy = 0.5 }
end

function M.fit(v) v.mode = "fit" end

-- scale is how many pixels of the window one of the picture is.
function M.scale(v, iw, ih, w, h)
  if v.mode == "fit" then return math.min(w / iw, h / ih) end
  return v.zoom
end

-- rect is where the picture is, not yet rounded to pixels: in the middle
-- when it is smaller than the window across or down, else kept covering
-- the window.
local function rect(v, iw, ih, w, h)
  local s = M.scale(v, iw, ih, w, h)
  local dw, dh = iw * s, ih * s
  local x = dw <= w and (w - dw) / 2 or clamp(w / 2 - v.cx * dw, w - dw, 0)
  local y = dh <= h and (h - dh) / 2 or clamp(h / 2 - v.cy * dh, h - dh, 0)
  return x, y, dw, dh
end

-- place is the left, top, width and height to draw the picture at, in
-- whole pixels.
function M.place(v, iw, ih, w, h)
  local x, y, dw, dh = rect(v, iw, ih, w, h)
  return math.floor(x), math.floor(y), math.max(1, round(dw)), math.max(1, round(dh))
end

-- setZoom makes the scale zoom, keeping the point of the picture that is at
-- mx, my in the window (the middle if not given) where it is.
function M.setZoom(v, zoom, iw, ih, w, h, mx, my)
  mx, my = mx or w / 2, my or h / 2
  local x, y, dw, dh = rect(v, iw, ih, w, h)
  local u, t = (mx - x) / dw, (my - y) / dh
  zoom = clamp(zoom, M.MIN, M.MAX)
  v.mode, v.zoom = "zoom", zoom
  local nw, nh = iw * zoom, ih * zoom
  v.cx = (w / 2 - (mx - u * nw)) / nw
  v.cy = (h / 2 - (my - t * nh)) / nh
end

function M.zoomBy(v, factor, iw, ih, w, h, mx, my)
  M.setZoom(v, M.scale(v, iw, ih, w, h) * factor, iw, ih, w, h, mx, my)
end

function M.actual(v, iw, ih, w, h, mx, my)
  M.setZoom(v, 1, iw, ih, w, h, mx, my)
end

-- movable says whether the picture is bigger than the window, so that it
-- can be moved about.
function M.movable(v, iw, ih, w, h)
  local _, _, dw, dh = rect(v, iw, ih, w, h)
  return dw > w or dh > h
end

-- pan moves the picture dx, dy pixels, as far as its edges let it.
function M.pan(v, dx, dy, iw, ih, w, h)
  if v.mode == "fit" then return end
  local s = v.zoom
  v.cx = v.cx - dx / (iw * s)
  v.cy = v.cy - dy / (ih * s)
  -- Keep the centre where the picture still covers the window.
  local x, y, dw, dh = rect(v, iw, ih, w, h)
  if dw > w then v.cx = (w / 2 - x) / dw end
  if dh > h then v.cy = (h / 2 - y) / dh end
end

-- percent is the scale as a whole number of percent.
function M.percent(v, iw, ih, w, h)
  return round(M.scale(v, iw, ih, w, h) * 100)
end

return M
