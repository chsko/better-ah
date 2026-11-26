-- Feeds the debug log (#99, Core/DebugLog.lua) from the outside: it wraps the adapters' methods and
-- the window's frames after they load, so the modules it watches don't change. Loaded last.
--
-- Every hook checks that the log is on before it builds any text. Lines go to BetterAHDB.debugLog.lines,
-- which the client writes on /reload or logout. Needs the client to check; specs drive it with fakes.
local addonName, ns = ...
ns = ns or {}

local DebugHooks = {}

local function log()
  local l = ns.debugLog
  if l and l:isOn() then return l end
  return nil
end

local function add(what, text, ...)
  local l = log()
  if l then l:add(what, text, ...) end
end
DebugHooks.add = add

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if r[1] then return unpack(r, 2, table.maxn(r)) end
  return nil
end

-- The client's fine clock, for how long a query took.
local function seconds(env)
  return try(env.GetTime) or 0
end

-- How long a query took, only when it was slow: a time on every line would stop repeats folding.
DebugHooks.SLOW = 2
local function slow(env, started)
  local took = seconds(env) - started
  if took < DebugHooks.SLOW then return "" end
  return string.format(" (slow: %.1fs)", took)
end

-- Who and what the session runs on, for its first line.
function DebugHooks.header(env)
  local version, build, _, interface = try(env.GetBuildInfo)
  local name = try(env.UnitName, "player")
  local realm = try(env.GetRealmName)
  local meta = env.C_AddOns and env.C_AddOns.GetAddOnMetadata or env.GetAddOnMetadata
  local own = try(meta, addonName, "Version")
  return string.format("%s-%s, client %s (%s, interface %s), addon %s, started %s",
    tostring(name), tostring(realm), tostring(version), tostring(build), tostring(interface), tostring(own),
    tostring(try(env.date, "%Y-%m-%d %H:%M:%S")))
end

-- What a frame says on itself: its tooltip title, its text, or the texts of its font strings (a row).
local titles = setmetatable({}, { __mode = "k" })

function DebugHooks.label(frame)
  if titles[frame] then return titles[frame] end
  local text = try(frame.GetText, frame)
  if type(text) == "string" and text ~= "" then return text end
  local parts = {}
  for _, region in ipairs({ try(frame.GetRegions, frame) }) do
    local t = type(region) == "table" and try(region.GetText, region)
    if type(t) == "string" and t ~= "" then parts[#parts + 1] = t end
    if #parts == 3 then break end
  end
  if #parts > 0 then return table.concat(parts, " | ") end
  return try(frame.GetName, frame) or try(frame.GetObjectType, frame) or "frame"
end

local function viewName()
  local w = ns.window
  return w and w.model and w.model.view or "?"
end

DebugHooks.WATCHED = {
  OnClick = function(f, button)
    return string.format("click %q%s", DebugHooks.label(f), button and (" " .. tostring(button)) or "")
  end,
  OnMouseWheel = function(f, delta) return string.format("wheel %q %s", DebugHooks.label(f), tostring(delta)) end,
  OnEnterPressed = function(f) return string.format("enter %q", tostring(try(f.GetText, f))) end,
}

-- Makes a frame's SetScript wrap the handlers players use (clicks, wheel turns, Enter) so each one is
-- logged before it runs. The handler still runs in the same call, so a click stays a hardware event.
function DebugHooks.watch(frame)
  if type(frame) ~= "table" or type(frame.SetScript) ~= "function" then return frame end
  local setScript = frame.SetScript
  frame.SetScript = function(f, script, fn, ...)
    local describe = DebugHooks.WATCHED[script]
    if describe and type(fn) == "function" then
      local inner = fn
      fn = function(...)
        if log() then
          local ok, text = pcall(describe, ...)
          add("ui", "%s in %s", ok and text or script, viewName())
        end
        return inner(...)
      end
    end
    return setScript(f, script, fn, ...)
  end
  return frame
end

-- The window's env with a CreateFrame that watches every frame it makes. Reads fall through to env.
function DebugHooks.env(env)
  local create = env.CreateFrame
  return setmetatable({
    CreateFrame = function(...) return DebugHooks.watch(create(...)) end,
  }, { __index = env, __newindex = env })
end

-- Replaces class[name] with fn(original, ...).
local function around(class, name, fn)
  local original = class and class[name]
  if type(original) ~= "function" then return end
  class[name] = function(...) return fn(original, ...) end
end

local function count(t)
  return type(t) == "table" and #t or 0
end

function DebugHooks.install(env, addon)
  local Window, SnipeAPI, PostingAPI, AuctionAPI = addon.Window, addon.SnipeAPI, addon.PostingAPI, addon.AuctionAPI

  if addon.window and not addon.window.frame then addon.window.env = DebugHooks.env(addon.window.env) end
  around(Window, "tooltip", function(original, e, button, title, text)
    if type(button) == "table" and title then titles[button] = title end
    return original(e, button, title, text)
  end)
  around(Window, "select", function(original, self, id)
    if log() and id ~= self.model.view then add("view", "%s -> %s", tostring(self.model.view), tostring(id)) end
    return original(self, id)
  end)
  around(Window, "toggle", function(original, self)
    local r = original(self)
    add("view", "window mode %s", tostring(self.model.mode))
    return r
  end)

  -- Browse queries: snipe checks and the Browse view's searches.
  around(SnipeAPI, "browse", function(original, self, query, done)
    if not log() then return original(self, query, done) end
    local started = seconds(self.env)
    return original(self, query, function(results, why)
      add("browse", "%s -> %s%s", ns.DebugLog.describe(query, 3),
        results and (count(results) .. " results") or ("none: " .. tostring(why)), slow(self.env, started))
      return done(results, why)
    end)
  end)
  around(SnipeAPI, "buy", function(original, self, auctionID, price, done, source)
    if not log() then return original(self, auctionID, price, done, source) end
    add("buy", "send auction %s for %s copper (from %s)", tostring(auctionID), tostring(price), tostring(source))
    return original(self, auctionID, price, function(ok, why, kind)
      add("buy", "auction %s: %s", tostring(auctionID), ok and "bought" or (tostring(kind) .. ", " .. tostring(why)))
      return done(ok, why, kind)
    end, source)
  end)

  -- One item's listings (Post view prices, snipe lookups, material prices).
  around(PostingAPI, "search", function(original, self, entry, done)
    if not log() then return original(self, entry, done) end
    local started = seconds(self.env)
    local name = tostring(entry.name or entry.itemID or entry.item)
    return original(self, entry, function(listings, complete)
      if type(listings) == "table" then
        add("search", "%s -> %d listings%s%s", name, #listings, complete and "" or ", not all",
          slow(self.env, started))
      else
        add("search", "%s -> none: %s", name, tostring(complete))
      end
      return done(listings, complete)
    end)
  end)
  local function postResult(what, entry, plan, r, why, units)
    add("post", "%s %s x%s at %s copper, duration %s -> %s%s", what, tostring(entry and (entry.name or entry.itemID)),
      tostring(units or (plan and plan.quantity)), tostring(plan and plan.price), tostring(plan and plan.duration),
      tostring(r), why and (": " .. tostring(why)) or "")
  end
  around(PostingAPI, "post", function(original, self, entry, plan)
    local r, why, units = original(self, entry, plan)
    if log() then postResult("post", entry, plan, r, why, units) end
    return r, why, units
  end)
  around(PostingAPI, "confirm", function(original, self)
    local args = self.pending
    local r, why, units = original(self)
    if log() then
      postResult("confirm", args and args.entry, args and { price = args[6] or args[5], duration = args[3] }, r, why,
        units)
    end
    return r, why, units
  end)

  around(AuctionAPI, "scan", function(original, self, onDone)
    if not log() then return original(self, onDone) end
    add("scan", "full scan asked for")
    local ended = false
    local ok, why = original(self, function(listings, info)
      ended = true
      if listings then
        add("scan", "full scan: %d listings, %s", #listings, info)
      else
        add("scan", "full scan failed: %s", tostring(info))
      end
      return onDone(listings, info)
    end)
    if not ok and not ended then add("scan", "full scan not started: %s", tostring(why)) end
    return ok, why
  end)

  -- The snipe session log, as it is written.
  local Session = addon.Sniper and addon.Sniper.Session
  around(Session, "log", function(original, self, time, kind, find, note)
    add("snipe", "%s%s%s", tostring(kind),
      find and string.format(" %s at %s copper", tostring(find.name), tostring(find.price)) or "",
      note and (": " .. tostring(note)) or "")
    return original(self, time, kind, find, note)
  end)

  DebugHooks.events(env)
end

-- Auction house answers, errors and blocks, straight from the client.
DebugHooks.EVENTS = {
  "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_SHOW_ERROR", "AUCTION_HOUSE_POST_ERROR",
  "AUCTION_HOUSE_POST_WARNING", "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_HOUSE_PURCHASE_COMPLETED",
  "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", "AUCTION_HOUSE_BROWSE_FAILURE", "ADDON_ACTION_BLOCKED",
  "ADDON_ACTION_FORBIDDEN", "UI_ERROR_MESSAGE", "PLAYER_LOGOUT",
}

function DebugHooks.onEvent(event, ...)
  if not log() then return end
  if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    local who, what = ...
    if who ~= nil and who ~= addonName then return end
    add("blocked", "%s %s", event, tostring(what))
  elseif event == "UI_ERROR_MESSAGE" then
    local w = ns.postingAPI
    if not (w and w.open) then return end
    local _, message = ...
    add("event", "%s %s", event, tostring(message))
  else
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = ns.DebugLog.describe((select(i, ...))) end
    add("event", "%s %s", event, table.concat(parts, " "))
  end
end

function DebugHooks.events(env)
  if type(env.CreateFrame) ~= "function" then return end
  local frame = env.CreateFrame("Frame")
  for _, e in ipairs(DebugHooks.EVENTS) do pcall(frame.RegisterEvent, frame, e) end
  frame:SetScript("OnEvent", function(_, event, ...) DebugHooks.onEvent(event, ...) end)
end

-- Lua errors that name this addon, once the log is turned on. The handler before ours still runs.
function DebugHooks.hookErrors(env)
  if DebugHooks.errorsHooked then return end
  local get, set = env.geterrorhandler, env.seterrorhandler
  if type(get) ~= "function" or type(set) ~= "function" then return end
  local previous = get()
  DebugHooks.errorsHooked = true
  local handler
  handler = function(message, ...)
    if log() and tostring(message):find(addonName, 1, true) then
      local stack = try(env.debugstack, 2, 4, 0)
      add("error", "%s%s", tostring(message), stack and (" / " .. stack) or "")
    end
    if type(previous) == "function" then return previous(message, ...) end
  end
  pcall(set, handler)
  -- An error addon (BugGrabber) may keep its own handler and ignore ours: say so instead of staying quiet.
  if try(get) ~= handler then add("debug", "Lua errors can't be logged: another addon keeps the error handler") end
end

-- Turns the log on or off (Settings view and /bah debug).
function DebugHooks.setOn(env, on)
  local l = ns.debugLog
  if not l then return end
  l:setOn(on)
  if on then
    DebugHooks.hookErrors(env)
    l:add("debug", "log on")
  end
end

-- Opens the saved log once the client has loaded BetterAHDB.
function DebugHooks.load(env)
  env.BetterAHDB = env.BetterAHDB or {}
  env.BetterAHDB.debugLog = env.BetterAHDB.debugLog or {}
  local clock = function() return ns.DebugLog.stamp(env.date, seconds(env)) end
  ns.debugLog = ns.DebugLog.new(env.BetterAHDB.debugLog, clock)
  ns.debugLog:begin(DebugHooks.header(env))
  if ns.debugLog:isOn() then
    DebugHooks.hookErrors(env)
    ns.debugLog:add("debug", "log on")
  end
end

ns.DebugHooks = DebugHooks

if CreateFrame and ns.DebugLog then
  DebugHooks.install(_G, ns)
  local loader = CreateFrame("Frame")
  loader:RegisterEvent("ADDON_LOADED")
  loader:SetScript("OnEvent", function(self, _, name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    DebugHooks.load(_G)
  end)
end
return DebugHooks
