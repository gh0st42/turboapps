-- A control of this project's own: the song as it plays, drawn as an old
-- oscilloscope would, a green-screen lane for each channel. Each lane shows
-- the wave of the notes the channel is playing, in the channel's colour:
-- higher notes as tighter waves, louder ones taller, drums as noise that
-- dies away, a chord as its notes added up. It is drawn from the song, not
-- from the sound, so it costs next to nothing.
--
--   scope:follow(song, at, hidden)   at = { bar =, tick = } while playing, or nil;
--                                  hidden are the channels not heard: { [2] = true }
--
-- It has no events: it is only to look at.

local gui = require "gui"
local songs = require "song"
local look = require "look"

local STEP = 3    -- the wave is drawn in steps this wide, chunky as a scope's dots
local NAME = 64   -- the channel names' column

-- A wave for each kind of sound, over a cycle from 0 to 1, from -1 to 1.
local function square(x) return x % 1 < 0.5 and 1 or -1 end
local function saw(x) return 2 * (x % 1) - 1 end
local function triangle(x) local f = x % 1 return f < 0.5 and 4 * f - 1 or 3 - 4 * f end
local function sine(x) return math.sin(2 * math.pi * x) end
local WAVES = {
  square = square, triangle = triangle, sawtooth = saw,
  ["double saw"] = function(x) return 0.6 * saw(x) + 0.4 * saw(2 * x) end,
  ["1/8 pulse"] = function(x) return x % 1 < 0.125 and 1 or -0.4 end,
  ["1/4 pulse"] = function(x) return x % 1 < 0.25 and 1 or -0.5 end,
  rounded = function(x) local v = sine(x) return v > 0 and v ^ 0.5 or -(-v) ^ 0.5 end,
}

-- waveOf is the wave an instrument is drawn with; nil for noise.
local function waveOf(inst)
  local kind = inst and inst.type
  if kind == "noise" or kind == "drumset" then return nil end
  if kind == "chip" then return WAVES[inst.wave] or square end
  if kind == "PWM" then return WAVES["1/4 pulse"] end
  if kind == "supersaw" or kind == "Picked String" then return saw end
  if kind == "harmonics" or kind == "spectrum" then
    return function(x) return 0.7 * sine(x) + 0.3 * sine(3 * x) end
  end
  return sine
end

-- noise is a steady sort of random, from -1 to 1, for a place and a frame.
local function noise(i, frame)
  local v = math.sin(i * 12.9898 + frame * 78.233) * 43758.5453
  return 2 * (v - math.floor(v)) - 1
end

gui.define {
  name = "Scope",
  build = function(parent, opts)
    local c = parent:Canvas { width = 264, height = 146 }
    -- State of its own: a field set on a Canvas draws it again.
    local s = { frame = 0 }

    function c:follow(song, at, hidden)
      s.song, s.at, s.hidden = song, at, hidden or {}
      s.frame = s.frame + 1
      self:redraw()
    end

    -- font is a VGA font when one is installed, else the fixed one.
    local function font()
      if s.font then return s.font end
      local ok, fonts = pcall(gui.fonts)
      s.font = look.fixedFont(ok and fonts or {})
      return s.font
    end

    function c:onDraw(g)
      local W, H = g:size()
      g:color(look.colors.scope)
      g:fill(0, 0, W, H)
      local song = s.song
      if not song or #song.channels == 0 then return end
      local n = #song.channels
      local laneH = H / n
      local x0 = NAME
      -- Lettering waits until the scan lines are drawn, so they leave it whole.
      local words = {}
      local function say(colour, text, x, y, w, h)
        words[#words + 1] = { colour, text, x, y, w, h }
      end
      local size = math.max(8, math.min(16, math.floor(laneH * 0.45)))
      for ci = 1, n do
        local top = math.floor((ci - 1) * laneH)
        local h = math.floor(ci * laneH) - top
        local mid = top + h / 2
        local colour = look.channelColor(song, ci)
        local quiet = s.hidden[ci]
        local notes = (s.at and not quiet) and songs.sounding(song, ci, s.at.bar, s.at.tick) or {}
        -- The lane: its name, and a faint line through the middle.
        if ci > 1 then
          g:color(look.colors.scopeGrid)
          g:fill(0, top, W, 1)
        end
        g:color(look.colors.scopeGrid)
        for x = x0, W, 6 do g:fill(x, math.floor(mid), 2, 1) end
        local label = songs.channelLabel(song, ci):upper()
        local two = h >= 2 * size
        say(quiet and look.colors.scopeDim or look.mix(colour, look.colors.scope, 0.25),
          label, 4, top, x0 - 6, two and math.floor(h / 2) or h)
        if quiet and two then
          say(look.colors.scopeDim, "MUTE", 4, top + math.floor(h / 2), x0 - 6, math.floor(h / 2))
        end
        if #notes > 0 then
          local inst = songs.instrument(song, ci)
          local wave = waveOf(inst)
          local loud = songs.volume(song, ci) / 100
          local amp = (h / 2 - 3)
          -- Each note's share: drums die away, the rest swell in a little.
          local parts = {}
          for _, nt in ipairs(notes) do
            local env = wave and math.min(1, 0.6 + nt.since * 8) or math.exp(-nt.since * 7)
            parts[#parts + 1] = { cycles = math.min(18, 1.5 * 2 ^ ((nt.pitch - 36) / 12)),
              size = nt.volume * env * loud / math.sqrt(#notes) }
          end
          local phase = s.frame * 0.04
          local points = {}
          for x = x0, W - 1, STEP do
            local f = (x - x0) / (W - x0)
            local v = 0
            for k, p in ipairs(parts) do
              local y = wave and wave(f * p.cycles + phase * k) or noise(math.floor(x / STEP), s.frame)
              v = v + y * p.size
            end
            points[#points + 1] = { x, mid - math.max(-1, math.min(1, v)) * amp }
          end
          -- A glow under it, then the trace, in steps as a scope's dots.
          for pass = 1, 2 do
            g:color(pass == 1 and look.mix(colour, look.colors.scope, 0.7) or colour)
            local w = pass == 1 and 3 or 1
            for i = 1, #points do
              local x, y = points[i][1], math.floor(points[i][2])
              g:fill(x - (w - 1) / 2, y - (w - 1) / 2, STEP + w - 1, w)
              local nx = points[i + 1]
              if nx then
                local y2 = math.floor(nx[2])
                local ya, yb = math.min(y, y2), math.max(y, y2)
                g:fill(x + STEP - 1 - (w - 1) / 2, ya - (w - 1) / 2, w, yb - ya + w)
              end
            end
          end
          -- The note under the name: a drum's, a pitch's, or a chord.
          if two then
            local what = #notes == 1 and songs.pitchName(song, ci, math.floor(notes[1].pitch + 0.5)) or "CHORD"
            say(colour, what:upper(), 4, top + math.floor(h / 2), x0 - 6, math.floor(h / 2))
          end
        end
      end
      -- Scan lines over it all, as a screen of the time had.
      g:color(look.colors.scopeLine)
      for y = 1, H, 3 do g:fill(0, y, W, 1) end
      g:font(font(), size)
      for _, w in ipairs(words) do
        g:color(w[1])
        g:text(w[2], w[3], w[4], w[5], w[6], "left")
      end
    end

    return c
  end,
}
