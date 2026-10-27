-- The code behind Downloads.form.lua: the controls are fields of the form,
-- by the names the layout gives them. It lists what is being downloaded and
-- what was, as download.lua keeps them: how each is going, to stop one, open
-- one or its folder, clear the list, and choose the folder they go in. The
-- window stays up while the browser goes on.

local gui = require "gui"
local lfs = require "lfs"
local download = require "download"
local store = require "store"
local frm = gui.load "Downloads" --[[@as forms.Downloads]]

local settings
local shown = {}   -- what the list has, a download each
local ticks = 0

-- run starts a program for a file; the tests put their own in its place.
function frm.run(cmd)
  local ok, err = pcall(gui.spawn, cmd)
  if not ok then gui.msgbox("Cannot open it.\n\n" .. tostring(err), "ok", "Downloads") end
end

-- opener is the command that opens a file or a folder in the system's own
-- program.
local function opener(path)
  if gui.platform == "windows" then return { "cmd", "/c", "start", "", (path:gsub("/", "\\")) } end
  if gui.platform == "darwin" then return { "open", path } end
  return { "xdg-open", path }
end

local function selected()
  return shown[frm.lstDownloads.selected or 0]
end

local function refill()
  local keep = frm.lstDownloads.selected or 0
  shown = {}
  local items = {}
  for _, d in ipairs(download.list) do
    shown[#shown + 1] = d
    items[#items + 1] = ("%s    %s"):format(d.name, download.describe(d))
  end
  frm.lstDownloads.items = items
  if #items > 0 then frm.lstDownloads.selected = math.max(1, math.min(keep, #items)) end
  frm.lblFolder.caption = "Saved in " .. download.folder(settings and settings.downloadDir)
  local n = download.active()
  frm.lblCount.caption = #items == 0 and "Nothing downloaded yet"
    or (n > 0 and ("%d going on, %d in all"):format(n, #items) or ("%d in all"):format(#items))
  frm.lstDownloads:fire("onChange")
end

-- Each button is for what is picked, when that can be done to it.
function frm.lstDownloads:onChange()
  local d = selected()
  frm.cmdOpen.enabled = d ~= nil and d.state == "done"
  frm.cmdShow.enabled = d ~= nil and d.state ~= "failed" and d.state ~= "stopped"
  frm.cmdCancel.enabled = d ~= nil and d.state == "receiving"
  frm.cmdRemove.enabled = d ~= nil and d.state ~= "receiving"
  frm.cmdClear.enabled = #shown > 0
end

-- attach tells the window which settings hold the folder, as the browser
-- keeps them.
function frm.attach(s)
  settings = s
end

-- fill puts what there is in the list; open does that and shows the window
-- (a test cannot show one).
function frm.fill()
  refill()
end

function frm.open()
  refill()
  frm:show()
end

-- tick is what the browser's timer calls: while the window is up and
-- something is coming in, the list is made again a few times a second.
function frm.tick()
  if not frm.visible then return end
  ticks = ticks + 1
  if ticks % 12 == 0 and download.active() > 0 then refill() end
end

-- A download that starts or ends changes the list at once.
download.onChange = function()
  if frm.visible and settings then refill() end
end

function frm.cmdOpen:onClick()
  local d = selected()
  if d and d.state == "done" then frm.run(opener(d.path)) end
end

function frm.cmdShow:onClick()
  local d = selected()
  if d then frm.run(opener(d.path:match("^(.*)/[^/]*$") or ".")) end
end

function frm.cmdCancel:onClick()
  local d = selected()
  if d then
    download.cancel(d)
    refill()
  end
end

function frm.cmdRemove:onClick()
  local d = selected()
  if d then
    download.remove(d)
    refill()
  end
end

function frm.cmdClear:onClick()
  download.clear()
  refill()
end

function frm.cmdFolder:onClick()
  local dir = gui.choosedir { title = "Save Downloads In", dir = download.folder(settings.downloadDir) }
  if not dir then return end
  settings.downloadDir = dir
  store.save(settings)
  refill()
end

function frm.cmdClose:onClick()
  frm:close()
end

return frm
