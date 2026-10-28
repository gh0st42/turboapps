-- Makes native programs of the apps in this folder, if you want them: each
-- .ztl is fused onto a copy of tlua, which gives one file that runs by itself
-- (no tlua to install; the Linux ones still need the X11 or Wayland libraries
-- tlua does). It does nothing until you run it:
--
--   tlua fuse-all.lua                 asks, then makes all of them
--   tlua fuse-all.lua -y              makes all of them without asking
--   tlua fuse-all.lua calculator pixel      only those
--   tlua fuse-all.lua -o programs     where to put them (default: programs)
--   tlua fuse-all.lua --list          the apps here
--   tlua fuse-all.lua --base PATH     fuse onto another tlua, such as one for
--                                     another platform (a tlua.exe makes .exe)
--
-- The tlua that runs this script is the one they are made of, so they are
-- for the platform it is for. Each is about as big as tlua (20 MB or so).

local lfs = require "lfs"

local windows = package.config:sub(1, 1) == "\\"

local function usage()
  print([[usage: tlua fuse-all.lua [-y] [-o folder] [--base tlua] [--list] [app ...]

Makes a native program of each .ztl beside this script (or of the apps named),
by fusing it onto tlua. See the top of the script.]])
end

-- Where this script is, to find the .ztl files beside it.
local here = (arg and arg[0] or ""):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."

local function quote(s)
  if windows then return '"' .. s .. '"' end
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- run runs a command and says whether it went well.
local function run(cmd)
  if windows then cmd = '"' .. cmd .. '"' end
  local r = os.execute(cmd)
  return r == true or r == 0
end

local function human(n)
  if n < 1024 * 1024 then return ("%.0f KB"):format(n / 1024) end
  return ("%.1f MB"):format(n / 1024 / 1024)
end

---------------------------------------------------------------- options

local yes, list = false, false
local out, base = "programs", nil
local wanted = {}
do
  local i = 1
  local a = arg or {}
  while a[i] do
    local x = a[i]
    if x == "-y" or x == "--yes" then yes = true
    elseif x == "--list" then list = true
    elseif x == "-o" then i = i + 1 out = a[i]
    elseif x == "--base" then i = i + 1 base = a[i]
    elseif x == "-h" or x == "--help" then usage() return
    elseif x:sub(1, 1) == "-" then
      io.stderr:write("unknown option " .. x .. "\n")
      usage()
      os.exit(2)
    else wanted[#wanted + 1] = x:gsub("%.ztl$", "") end
    i = i + 1
  end
  if not out then
    usage()
    os.exit(2)
  end
end

-- The tlua to build on: the one running this, unless given another.
local tlua = base
if not tlua then
  local ok, gui = pcall(require, "gui")
  tlua = (ok and gui.interpreter ~= "" and gui.interpreter) or (arg and arg[-1]) or "tlua"
end

---------------------------------------------------------------- the apps

local apps = {}
for name in lfs.dir(here) do
  local app = name:match("^(.+)%.ztl$")
  if app then apps[#apps + 1] = app end
end
table.sort(apps)

if list then
  for _, app in ipairs(apps) do print(app) end
  return
end

if #apps == 0 then
  io.stderr:write("there are no .ztl files beside " .. arg[0] .. "\n")
  os.exit(1)
end

local chosen = apps
if #wanted > 0 then
  chosen = {}
  local have = {}
  for _, app in ipairs(apps) do have[app] = true end
  for _, app in ipairs(wanted) do
    if not have[app] then
      io.stderr:write("no app called " .. app .. " here (--list shows them)\n")
      os.exit(1)
    end
    chosen[#chosen + 1] = app
  end
end

-- The programs of a Windows tlua are .exe files.
local exe = ""
if (base and base:lower():match("%.exe$")) or (not base and windows) then exe = ".exe" end

local size = lfs.attributes(tlua, "size") or 20 * 1024 * 1024
if not yes then
  io.write(("Make %d program%s in %s/, each about %s (%s in all)? [y/N] "):format(
    #chosen, #chosen == 1 and "" or "s", out, human(size), human(size * #chosen)))
  local answer = io.read("*l")
  if not (answer and answer:lower():match("^y")) then
    print("Nothing made.")
    return
  end
end

---------------------------------------------------------------- fusing

lfs.mkdir(out)
local made, failed = 0, {}
for _, app in ipairs(chosen) do
  local target = out .. "/" .. app .. exe
  local cmd = ("%s fuse -o %s %s%s > %s"):format(quote(tlua), quote(target),
    base and ("--base " .. quote(base) .. " ") or "", quote(here .. "/" .. app .. ".ztl"), windows and "NUL" or "/dev/null")
  io.write(("%-14s "):format(app))
  io.flush()
  if run(cmd) and lfs.attributes(target, "mode") == "file" then
    made = made + 1
    print(human(lfs.attributes(target, "size")))
  else
    failed[#failed + 1] = app
    print("failed")
  end
end

print(("\nMade %d program%s in %s/."):format(made, made == 1 and "" or "s", out))
if #failed > 0 then
  io.stderr:write("Not made: " .. table.concat(failed, ", ") .. "\n")
  os.exit(1)
end
