-- Writing a song out as sound, with no GUI in it: WAV by itself, and Ogg
-- Vorbis through ffmpeg when it is installed, as fz does it. ffmpeg runs
-- beside the program, through a spawn like gui.spawn's, so the window does
-- not wait for it; the tests give one of their own.
--
--   export.ogg(gui.spawn, ffmpegPath, sound, "song.ogg", function(ok, why) ... end)

local lfs = require "lfs"

local M = {}

M.windows = package.config:sub(1, 1) == "\\"

-- which finds a program on the PATH, or nil.
function M.which(name)
  local sep = M.windows and ";" or ":"
  for dir in (os.getenv("PATH") or ""):gmatch("[^" .. sep .. "]+") do
    for _, ext in ipairs(M.windows and { ".exe", "" } or { "" }) do
      local path = dir .. "/" .. name .. ext
      if lfs.attributes(path, "mode") == "file" then return path end
    end
  end
end

-- oggCommands are the ways ffmpeg is asked to make an Ogg of a WAV, best
-- first: libvorbis, which most builds have, then ffmpeg's own Vorbis
-- encoder, which some have instead and which wants to be told it may be
-- used.
function M.oggCommands(ffmpeg, wav, ogg)
  local head = { ffmpeg, "-y", "-hide_banner", "-loglevel", "error", "-i", wav }
  local function with(...)
    local cmd = {}
    for i, v in ipairs(head) do cmd[i] = v end
    for _, v in ipairs { ... } do cmd[#cmd + 1] = v end
    cmd[#cmd + 1] = ogg
    return cmd
  end
  return {
    with("-c:a", "libvorbis", "-q:a", "5"),
    with("-c:a", "vorbis", "-strict", "-2", "-ac", "2", "-q:a", "5"),
  }
end

-- ogg writes a sound as an Ogg file at path: a WAV of it first, which
-- ffmpeg turns into one, each way in turn until one works. done(true), or
-- done(false, why), is called when it has finished.
function M.ogg(spawn, ffmpeg, sound, path, done)
  local wav = os.tmpname() .. ".wav"
  local ok, err = sound:save(wav)
  if not ok then
    done(false, "cannot write " .. wav .. ": " .. tostring(err))
    return
  end
  local cmds = M.oggCommands(ffmpeg, wav, path)
  local errors = {}
  local function try(i)
    local cmd = cmds[i]
    if not cmd then
      os.remove(wav)
      done(false, #errors > 0 and table.concat(errors, "\n") or "ffmpeg could not make it")
      return
    end
    local said = {}
    local opts = {
      onOutput = function(line, stream)
        if stream == "stderr" and line ~= "" then said[#said + 1] = line end
      end,
      onExit = function(code)
        if code == 0 and lfs.attributes(path, "size") and lfs.attributes(path, "size") > 0 then
          os.remove(wav)
          done(true)
        else
          errors[#errors + 1] = table.concat(said, "\n")
          try(i + 1)
        end
      end,
    }
    for k, v in ipairs(cmd) do opts[k] = v end
    local started, why = pcall(spawn, opts)
    if not started then
      errors[#errors + 1] = tostring(why)
      try(i + 1)
    end
  end
  try(1)
end

return M
