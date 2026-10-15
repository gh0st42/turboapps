-- The two protocols microbrowser speaks, Gemini and Gopher, with no GUI in
-- it. A request runs a step at a time, never waiting, so a window can
-- drive it from a timer and stay awake:
--
--   local job = net.request("gemini://geminiprotocol.net/", { trust = fn })
--   while not job:poll() do socket.sleep(0.01) end
--   print(job.status, job.meta, #job.body)
--
-- What a finished job has:
--   job.err          why it failed (then nothing else is set but these):
--   job.fingerprint  the certificate's SHA-256, for a Gemini capsule
--   job.untrusted    true when trust() refused that certificate
--   job.status       Gemini's two digits, as a number (Gopher: always 20)
--   job.meta         Gemini's meta: the MIME type, a prompt, a new address
--   job.body         what came after the header
--
-- Addresses are read and written here too: parse, absolute, gopherURL.

local socket = require "socket"
local ssl = require "ssl"
local url = require "socket.url"

local M = {}

M.timeout = 20               -- seconds a request may take, all told
M.maxBody = 32 * 1024 * 1024 -- bytes; a bigger answer is cut off

local PORTS = { gemini = 1965, gopher = 70 }

---------------------------------------------------------------- addresses

-- unescape decodes %XX.
function M.unescape(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- escape encodes what an address cannot hold as it is: a selector's
-- spaces, ?, # and the like.
function M.escape(s)
  return (s:gsub("[^%w%-%._~/:@!%$&'%(%)%*%+,;=]", function(c)
    return ("%%%02X"):format(c:byte())
  end))
end

-- parse reads an address: scheme, host, port, path and query, and for
-- Gopher the item type, the selector and a search's words. A bare host
-- ("example.org") is taken for Gemini. nil and why for what is not one.
function M.parse(address)
  address = (address or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if address == "" then return nil, "no address" end
  if not address:find("^%a[%w+.-]*:") then address = "gemini://" .. address end
  local scheme, rest = address:match("^(%a[%w+.-]*)://(.*)$")
  if not scheme then
    scheme = address:match("^(%a[%w+.-]*):")
    return { scheme = scheme:lower(), url = address }
  end
  scheme = scheme:lower()
  local authority, path = rest:match("^([^/?#]*)(.*)$")
  local host, port = authority:match("^%[(.-)%]:?(%d*)$") -- [::1]:1965
  if not host then host, port = authority:match("^([^:]*):?(%d*)$") end
  if not host or host == "" then return nil, "no host in " .. address end
  local u = { scheme = scheme, host = host:lower(), port = tonumber(port) or PORTS[scheme] }
  if scheme == "gopher" then
    path = path:gsub("#.*$", "")
    local t, sel = path:match("^/(.)(.*)$")
    u.type = t or "1"
    sel = sel or ""
    local words = sel:match("%%09(.*)$") or sel:match("\t(.*)$")
    if words then sel = sel:gsub("%%09.*$", ""):gsub("\t.*$", "") end
    u.selector = M.unescape(sel)
    u.search = words and M.unescape(words)
  else
    u.path = path:match("^[^?#]*")
    u.query = path:match("%?([^#]*)")
    u.fragment = path:match("#(.*)$")
  end
  u.url = M.format(u)
  return u
end

-- format writes a parsed address back, as parse would read it.
function M.format(u)
  if not u.host then return u.url end
  local host = u.host:find(":") and "[" .. u.host .. "]" or u.host
  local s = u.scheme .. "://" .. host
  if u.port and u.port ~= PORTS[u.scheme] then s = s .. ":" .. u.port end
  if u.scheme == "gopher" then
    if (u.selector or "") == "" and u.type == "1" and not u.search then return s .. "/" end
    s = s .. "/" .. (u.type or "1") .. M.escape(u.selector or "")
    if u.search then s = s .. "%09" .. M.escape(u.search) end
    return s
  end
  s = s .. ((u.path or "") == "" and "/" or u.path)
  if u.query then s = s .. "?" .. u.query end
  return s
end

-- gopherURL is the address of a menu's item.
function M.gopherURL(host, port, itemType, selector)
  return M.format { scheme = "gopher", host = host:lower(), port = tonumber(port) or 70,
    type = itemType, selector = selector }
end

-- absolute is a link on the page at base, made whole.
function M.absolute(base, link)
  link = link:gsub("^%s+", ""):gsub("%s+$", "")
  if link:find("^%a[%w+.-]*:") then return link end
  if not base or not base:find("^%a[%w+.-]*://") then return link end
  return url.absolute(base, link)
end

-- parent is the address one level up: the folder a page is in, or the
-- menu above a selector; nil at the top.
function M.parent(address)
  local u = M.parse(address)
  if not u or not u.host then return nil end
  if u.scheme == "gopher" then
    local sel = (u.selector or ""):gsub("/+$", "")
    if sel == "" and u.type == "1" and not u.search then return nil end
    u.selector = sel:match("^(.*)/[^/]*$") or ""
    u.type, u.search = "1", nil
    return M.format(u)
  end
  local path = (u.path or "/")
  if u.query then
    u.query = nil
    return M.format(u)
  end
  if path == "/" or path == "" then return nil end
  local up = path:gsub("/+$", ""):match("^(.*/)[^/]*$") or "/"
  u.path = up
  return M.format(u)
end

-- withQuery is a Gemini address asking with what was typed.
function M.withQuery(address, text)
  local base = address:gsub("[?#].*$", "")
  return base .. "?" .. url.escape(text)
end

---------------------------------------------------------------- requests

local Job = {}
Job.__index = Job

-- wait runs fn until it stops saying it would block, giving way meanwhile.
local function wait(job, fn)
  while true do
    local a, b, c = fn()
    if a then return a, b, c end
    if b ~= "timeout" and b ~= "wantread" and b ~= "wantwrite" then return nil, b, c end
    if socket.gettime() > job.deadline then return nil, "it took too long" end
    coroutine.yield()
  end
end

local function connect(job, u)
  job.state = "connecting"
  local tcp, err = socket.tcp()
  if not tcp then return nil, err end
  job.sock = tcp
  tcp:settimeout(0)
  local ok
  ok, err = tcp:connect(u.host, u.port)
  if not ok and err ~= "timeout" then return nil, err end
  if not ok then
    while true do
      local _, writable = socket.select(nil, { tcp }, 0)
      if writable and #writable > 0 then break end
      if socket.gettime() > job.deadline then return nil, "it took too long" end
      coroutine.yield()
    end
    -- A connection that failed is writable too: it has no peer.
    if not tcp:getpeername() then return nil, "connection refused" end
  end
  return tcp
end

-- readAll reads until the other end closes.
local function readAll(job, conn)
  job.state = "receiving"
  local parts, size = {}, 0
  while true do
    local data, err, partial = conn:receive(65536)
    local got = data or partial
    if got and got ~= "" then
      parts[#parts + 1] = got
      size = size + #got
      job.received = size
      if size > M.maxBody then break end
    end
    if err == "closed" then break end
    if err and err ~= "timeout" and err ~= "wantread" then
      if size == 0 then return nil, err end
      break
    end
    if not data then
      if socket.gettime() > job.deadline then return nil, "it took too long" end
      coroutine.yield()
    end
  end
  return table.concat(parts)
end

local function sendAll(job, conn, text)
  job.state = "sending"
  local i = 1
  while i <= #text do
    local n, err, last = conn:send(text, i)
    if n then return true end
    if err ~= "timeout" and err ~= "wantwrite" then return nil, err end
    i = (last or i - 1) + 1
    if socket.gettime() > job.deadline then return nil, "it took too long" end
    coroutine.yield()
  end
  return true
end

local function gemini(job, u, opts)
  local tcp, err = connect(job, u)
  if not tcp then return nil, err end
  job.state = "handshake"
  local conn
  conn, err = ssl.wrap(tcp, { mode = "client", protocol = "any", options = "all" })
  if not conn then return nil, err end
  job.sock = conn
  conn:sni(u.host)
  conn:settimeout(0)
  local ok
  ok, err = wait(job, function() return conn:dohandshake() end)
  if not ok then return nil, "TLS: " .. tostring(err) end
  local cert = conn:getpeercertificate()
  job.fingerprint = cert and cert:digest("sha256")
  if opts.trust and not opts.trust(u.host .. ":" .. u.port, job.fingerprint, cert) then
    job.untrusted = true
    return nil, "the certificate is not the one this capsule showed before"
  end
  ok, err = sendAll(job, conn, u.url .. "\r\n")
  if not ok then return nil, err end
  local all
  all, err = readAll(job, conn)
  if not all then return nil, err end
  local header, body = all:match("^([^\n]*)\n(.*)$")
  if not header then header, body = all, "" end
  header = header:gsub("\r$", "")
  local status, meta = header:match("^(%d%d)%s*(.*)$")
  if not status then return nil, "not a Gemini answer: " .. header:sub(1, 80) end
  job.status, job.meta, job.body = tonumber(status), meta, body
  return true
end

local function gopher(job, u)
  local tcp, err = connect(job, u)
  if not tcp then return nil, err end
  local line = u.selector .. (u.search and "\t" .. u.search or "") .. "\r\n"
  local ok
  ok, err = sendAll(job, tcp, line)
  if not ok then return nil, err end
  local body
  body, err = readAll(job, tcp)
  if not body then return nil, err end
  job.status, job.meta, job.body = 20, "", body
  return true
end

-- request starts asking for an address. opts.trust(hostport, fingerprint,
-- cert) says whether a Gemini capsule's certificate is to be trusted; with
-- none, every one is.
function M.request(address, opts)
  opts = opts or {}
  local job = setmetatable({ url = address, state = "starting", received = 0, done = false }, Job)
  job.deadline = socket.gettime() + (opts.timeout or M.timeout)
  local u, err = M.parse(address)
  if u and not PORTS[u.scheme] then u, err = nil, u.scheme .. ": is not Gemini or Gopher" end
  if not u then
    job.err, job.done = err, true
    return job
  end
  job.parsed = u
  job.co = coroutine.create(function()
    if u.scheme == "gemini" then return gemini(job, u, opts) end
    return gopher(job, u)
  end)
  return job
end

-- poll takes the request as far as it goes without waiting; true once it
-- is done, failed or not.
function Job:poll()
  if self.done then return true end
  local alive, ok, err = coroutine.resume(self.co)
  if not alive then ok, err = nil, tostring(ok) end
  if coroutine.status(self.co) == "dead" then
    if not ok then self.err = err or "failed" end
    self:finish()
  end
  return self.done
end

-- cancel stops it where it is.
function Job:cancel()
  if self.done then return end
  self.err = "stopped"
  self:finish()
end

function Job:finish()
  self.done, self.state = true, "done"
  if self.sock then self.sock:close() end
  self.sock = nil
end

return M
