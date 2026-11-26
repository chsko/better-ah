-- The debug log (#99): what the player and the addon did, kept in BetterAHDB.debugLog so a bug report
-- can be read from the saved file instead of from memory. Pure: the caller hands in a clock. The client
-- writes saved variables on /reload and logout, not on a crash.
--
-- saved = { on = bool, session = n, lines = { "#n HH:MM:SS.mmm [what] text", ... } }, oldest first.
local _, ns = ...
ns = ns or {}

local DebugLog = {}
DebugLog.__index = DebugLog

DebugLog.MAX = 4000 -- lines kept
DebugLog.SLACK = 500 -- lines allowed past MAX before the oldest are dropped, so trimming is rare

-- clock() returns the local time as "HH:MM:SS.mmm"; it is only called while the log is on.
function DebugLog.new(saved, clock)
  saved = saved or {}
  saved.lines = saved.lines or {}
  saved.session = saved.session or 0
  return setmetatable({ saved = saved, clock = clock or function() return "?" end }, DebugLog)
end

function DebugLog:isOn()
  return self.saved.on == true
end

function DebugLog:setOn(on)
  self.saved.on = on and true or false
end

-- Starts a new session: the number goes on every line until the next /reload or login. header becomes
-- the session's first line, written just before its first other line (so a session with the log off
-- leaves nothing behind).
function DebugLog:begin(header)
  self.saved.session = self.saved.session + 1
  self.last, self.repeats = nil, 0
  self.header, self.headed = header or "", false
end

-- A short, one-line description of a value, for logging arguments: tables show their fields sorted,
-- levels deep (1 unless given).
function DebugLog.describe(value, levels, depth)
  if type(value) == "string" then return value end
  if type(value) ~= "table" then return tostring(value) end
  if (depth or 0) >= (levels or 1) then return "{...}" end
  local keys = {}
  for k in pairs(value) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for i, k in ipairs(keys) do
    if i > 8 then
      parts[#parts + 1] = "..."
      break
    end
    parts[#parts + 1] = tostring(k) .. "=" .. DebugLog.describe(value[k], levels, (depth or 0) + 1)
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

-- Formats like string.format, but a bad pattern or argument never throws: the log must not break
-- the action it records.
local function render(text, ...)
  if select("#", ...) == 0 then return tostring(text) end
  local args = { n = select("#", ...), ... }
  for i = 1, args.n do
    local v = args[i]
    if type(v) ~= "number" and type(v) ~= "string" then args[i] = DebugLog.describe(v) end
  end
  local ok, out = pcall(string.format, text, unpack(args, 1, args.n))
  if ok then return out end
  local parts = { tostring(text) }
  for i = 1, args.n do parts[#parts + 1] = tostring(args[i]) end
  return table.concat(parts, " ")
end

function DebugLog:write(what, text, force)
  if not (force or self:isOn()) then return end
  if self.header and not self.headed then
    self.headed = true
    self:write("session", self.header, true)
  end
  local lines = self.saved.lines
  local body = "[" .. tostring(what) .. "] " .. text:gsub("[\r\n]+", " / ")
  -- The same line again (a check that found the same thing) adds to the last line's count instead.
  if body == self.last and #lines > 0 then
    self.repeats = self.repeats + 1
    lines[#lines] = self.lastLine .. string.format(" (x%d, last %s)", self.repeats + 1, self.clock())
    return
  end
  local line = string.format("#%d %s %s", self.saved.session, self.clock(), body)
  lines[#lines + 1] = line
  self.last, self.lastLine, self.repeats = body, line, 0
  if #lines > DebugLog.MAX + DebugLog.SLACK then
    local keep, from = {}, #lines - DebugLog.MAX + 1
    for i = from, #lines do keep[#keep + 1] = lines[i] end
    self.saved.lines = keep
  end
end

-- Adds a line while the log is on. text and its arguments work like string.format; arguments are only
-- formatted when the line is kept, so a call costs almost nothing while the log is off.
function DebugLog:add(what, text, ...)
  if not self:isOn() then return end
  self:write(what, render(text, ...))
end

-- A note from the player (/bah mark). Written even while the log is off.
function DebugLog:mark(text)
  self:write("MARK", text ~= nil and text ~= "" and text or "(no text)", true)
end

function DebugLog:count()
  return #self.saved.lines
end

function DebugLog:clear()
  self.saved.lines = {}
  self.last, self.repeats, self.headed = nil, 0, false
end

-- "HH:MM:SS.mmm" from a date function (os.date / the client's date), seconds and a fraction of a
-- second from a fine clock (GetTime). The milliseconds tell lines in the same second apart.
function DebugLog.stamp(dateFn, fine)
  local ms = math.floor(((fine or 0) % 1) * 1000)
  local ok, clock = pcall(dateFn, "%H:%M:%S")
  return string.format("%s.%03d", ok and tostring(clock) or "??:??:??", ms)
end

ns.DebugLog = DebugLog
return DebugLog
