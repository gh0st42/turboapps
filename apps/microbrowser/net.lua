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
--   job.body         what came after the header ("" when it was streamed)
--   job.streamed     true when the body went to a sink as it came
--   job.received     how many bytes of the body have come so far
--
-- opts.download(job) is asked once the answer's kind is known (Gemini: after
-- its header, when the status is a success; Gopher: before anything is read,
-- job.parsed.type being the item's type). It may give a sink, a function
-- taking each piece of the body as it comes and returning true (or nil and
-- why to stop), so that a big file goes to disk rather than into memory;
-- a download has M.idle seconds between pieces, not M.timeout all told.
--
-- Addresses are read and written here too: parse, absolute, gopherURL.

local socket = require "socket"
local ssl = require "ssl"
local url = require "socket.url"

local M = {}

M.timeout = 20               -- seconds a request may take, all told
M.maxBody = 32 * 1024 * 1024 -- bytes; a bigger answer is cut off
M.idle = 30                  -- seconds a download may be quiet

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

-- interleave puts the addresses a name has in the order to try them: the
-- first, then one of the other family, and so on, so that an address that
-- leads nowhere (a name with an IPv6 address on a network without IPv6) is
-- not all there is. list is what socket.dns.getaddrinfo gives.
function M.interleave(list)
  local by, order = {}, {}
  for _, a in ipairs(list) do
    if not by[a.family] then by[a.family] = {} order[#order + 1] = a.family end
    local q = by[a.family]
    q[#q + 1] = a
  end
  local out, at = {}, 1
  while #out < #list do
    for _, fam in ipairs(order) do
      local a = by[fam][at]
      if a then out[#out + 1] = a end
    end
    at = at + 1
  end
  return out
end

M.stagger = 0.25 -- seconds before the next address is tried alongside

-- connect opens a connection to the host, as a browser does: the addresses
-- of the name are tried one after the other, the next while the one before
-- is still trying after a quarter of a second, and the first to answer
-- is kept.
local function connect(job, u)
  job.state = "connecting"
  local list, err = socket.dns.getaddrinfo(u.host)
  if not list or #list == 0 then return nil, err or ("cannot find " .. u.host) end
  local candidates = M.interleave(list)
  local trying, nextAt, lastErr, launched = {}, 1, nil, 0
  local function close(t)
    pcall(function() t:close() end)
  end
  local function launch()
    local a = candidates[nextAt]
    nextAt = nextAt + 1
    local tcp, cerr = (a.family == "inet6" and socket.tcp6 or socket.tcp4)()
    if not tcp then lastErr = cerr return nil end
    tcp:settimeout(0)
    local ok
    ok, cerr = tcp:connect(a.addr, u.port)
    launched = socket.gettime()
    if ok then return tcp end
    if cerr ~= "timeout" then
      lastErr = cerr
      close(tcp)
      return nil
    end
    trying[#trying + 1] = tcp
  end
  local function won(tcp)
    for _, t in ipairs(trying) do if t ~= tcp then close(t) end end
    job.sock = tcp
    return tcp
  end
  while true do
    -- The next address is tried when the one before is slow, or failed.
    if nextAt <= #candidates and (#trying == 0 or socket.gettime() - launched >= M.stagger) then
      local tcp = launch()
      if tcp then return won(tcp) end
    end
    if #trying > 0 then
      local _, writable = socket.select(nil, trying, 0)
      for _, t in ipairs(writable or {}) do
        -- A connection that failed is writable too: it has no peer.
        if t:getpeername() then return won(t) end
        close(t)
        lastErr = "connection refused"
        for i, x in ipairs(trying) do if x == t then table.remove(trying, i) break end end
      end
    end
    if #trying == 0 and nextAt > #candidates then return nil, lastErr or "connection refused" end
    if socket.gettime() > job.deadline then
      for _, t in ipairs(trying) do close(t) end
      return nil, "it took too long"
    end
    coroutine.yield()
  end
end

-- pump reads until the other end closes, starting with first (what has come
-- already). The body is collected and returned, or, with a sink, given to it
-- piece by piece and "" returned.
local function pump(job, conn, first, sink)
  job.state = "receiving"
  local parts, size = {}, 0
  local function take(got)
    if sink then
      local ok, why = sink(got)
      if not ok then return nil, why or "the file could not be written" end
      job.received = job.received + #got
      job.deadline = socket.gettime() + M.idle
    else
      parts[#parts + 1] = got
      size = size + #got
      job.received = size
    end
    return true
  end
  if first ~= "" then
    local ok, why = take(first)
    if not ok then return nil, why end
  end
  while true do
    local data, err, partial = conn:receive(65536)
    local got = data or partial
    if got and got ~= "" then
      local ok, why = take(got)
      if not ok then return nil, why end
      if not sink and size > M.maxBody then break end
    end
    if err == "closed" then break end
    if err and err ~= "timeout" and err ~= "wantread" then
      if job.received == 0 and #first == 0 then return nil, err end
      break
    end
    if not data then
      if socket.gettime() > job.deadline then return nil, "it took too long" end
      coroutine.yield()
    end
  end
  return table.concat(parts)
end

-- readHeader reads a Gemini answer's first line, and gives it and what came
-- after it in the same piece.
local function readHeader(job, conn)
  job.state = "receiving"
  local buf = ""
  while true do
    local nl = buf:find("\n", 1, true)
    if nl then return (buf:sub(1, nl - 1):gsub("\r$", "")), buf:sub(nl + 1) end
    if #buf > 4096 then return nil, "not a Gemini answer: " .. buf:sub(1, 80) end
    local data, err, partial = conn:receive(1024)
    local got = data or partial
    if got and got ~= "" then buf = buf .. got end
    local ended = err == "closed" or (err and err ~= "timeout" and err ~= "wantread")
    if ended then
      -- The other end is done: what came is all there is.
      local nl = buf:find("\n", 1, true)
      if nl then return (buf:sub(1, nl - 1):gsub("\r$", "")), buf:sub(nl + 1) end
      if buf == "" and err ~= "closed" then return nil, err end
      return (buf:gsub("\r$", "")), ""
    end
    if not data then
      if socket.gettime() > job.deadline then return nil, "it took too long" end
      coroutine.yield()
    end
  end
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
  local header, first = readHeader(job, conn)
  if not header then return nil, first end
  local status, meta = header:match("^(%d%d)%s*(.*)$")
  if not status then return nil, "not a Gemini answer: " .. header:sub(1, 80) end
  job.status, job.meta = tonumber(status), meta
  local sink
  if job.status >= 20 and job.status < 30 and opts.download then sink = opts.download(job) end
  job.streamed = sink ~= nil
  local rest
  rest, err = pump(job, conn, first, sink)
  if not rest then return nil, err end
  job.body = sink and "" or rest
  return true
end

local function gopher(job, u, opts)
  local tcp, err = connect(job, u)
  if not tcp then return nil, err end
  local line = u.selector .. (u.search and "\t" .. u.search or "") .. "\r\n"
  local ok
  ok, err = sendAll(job, tcp, line)
  if not ok then return nil, err end
  local sink = opts.download and opts.download(job)
  job.streamed = sink ~= nil
  local body
  body, err = pump(job, tcp, "", sink)
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
    return gopher(job, u, opts)
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
