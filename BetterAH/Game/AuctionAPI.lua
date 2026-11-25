-- Auction API: the only module that calls Forever's auction house functions. Forever has
-- C_AuctionHouse only (ADR 0004). Scans use ReplicateItems, which returns every listing on
-- the market in one reply. Checked in game with /bah selftest; specs use spec/fake_client.lua.
local _, ns = ...
ns = ns or {}

local AuctionAPI = {}
AuctionAPI.__index = AuctionAPI

AuctionAPI.TIMEOUT = 120

-- How often the replicate list is checked directly, in case the update event never comes.
AuctionAPI.POLL = 1

-- Auction house events watched during a scan, only to report what the client did when a
-- scan fails. Unknown events are skipped (RegisterEvent errors on them).
AuctionAPI.TRACE_EVENTS = {
  "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT",
  "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
  "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED", "AUCTION_HOUSE_BROWSE_FAILURE", "UI_ERROR_MESSAGE",
}

-- Maps (uiMapID) whose only auction house is a neutral one: Tanaris (Gadgetzan),
-- Stranglethorn Vale (Booty Bay) and Winterspring (Everlook).
AuctionAPI.NEUTRAL_MAPS = { [1446] = "Gadgetzan", [1434] = "Booty Bay", [1452] = "Everlook" }

-- env is the game's global table (_G in the client, a fake in specs).
function AuctionAPI.new(env)
  local self = setmetatable({ env = env }, AuctionAPI)
  self.events = env.CreateFrame("Frame")
  self.events:SetScript("OnEvent", function(_, event, ...) self:onEvent(event, ...) end)
  self.events:RegisterEvent("AUCTION_HOUSE_SHOW")
  self.events:RegisterEvent("AUCTION_HOUSE_CLOSED")
  return self
end

local function nonEmpty(value)
  if type(value) == "string" and value ~= "" then return value end
  return nil
end

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

-- Every realm source we know of, for the self-test only (ADR 0005).
function AuctionAPI.realmSources(env)
  local guid = try(env.UnitGUID, "player")
  return {
    { "GetNormalizedRealmName", nonEmpty(try(env.GetNormalizedRealmName)) },
    { "GetRealmName", nonEmpty(try(env.GetRealmName)) },
    { "UnitGUID server id", type(guid) == "string" and guid:match("^Player%-(%d+)%-") or nil },
  }
end

-- The neutral auction house's name when the player stands at one, else nil.
function AuctionAPI.neutralHouse(env)
  local map = env.C_Map and try(env.C_Map.GetBestMapForUnit, "player")
  return map and AuctionAPI.NEUTRAL_MAPS[map]
end

-- The ruleset the character plays on (ADR 0005): "Normal", "PvP", "Roleplay", "Roleplay PvP" or
-- "Hardcore", from the game rules that are on, the way TSM reads it on Forever. GetActiveGameMode and
-- GetForeverExperiencePreset say 1 on both Normal and PvP, so they can't tell rulesets apart. A client
-- without these rules, or whose rules can't be read, falls back to GetActiveGameMode.
function AuctionAPI.ruleset(env)
  local rules, enum = env.C_GameRules, env.Enum and env.Enum.GameRule
  if rules and rules.IsGameRuleActive and enum and enum.PvPRuleset ~= nil then
    -- A rule that can't be read must not quietly count as off: that would file a PvP character
    -- under Normal. Then the whole rules path is skipped.
    local readable = true
    local function on(name)
      if enum[name] == nil then return false end
      local value = try(rules.IsGameRuleActive, enum[name])
      if type(value) ~= "boolean" then readable = false end
      return value == true
    end
    local hardcore, pvp, rp = on("HardcoreRuleset"), on("PvPRuleset"), on("RPRuleset")
    if readable then
      if hardcore then return "Hardcore" end
      if rp and pvp then return "Roleplay PvP" end
      if rp then return "Roleplay" end
      if pvp then return "PvP" end
      return "Normal"
    end
  end
  local mode = rules and try(rules.GetActiveGameMode)
  return mode ~= nil and tostring(mode) or "default"
end

-- The market the player is on now: key, parts, or nil and a reason.
-- Realm is pinned empty (ADR 0005): Forever has rulesets instead of realms and its
-- GetRealmName() is empty, so the market is ruleset plus faction. Realm sources are only
-- reported by the self-test. Neutral auction houses are their own faction, "Neutral".
function AuctionAPI.currentMarket(env)
  local faction = AuctionAPI.neutralHouse(env) and "Neutral" or nonEmpty(try(env.UnitFactionGroup, "player"))
  if not faction then return nil, "Your faction isn't known yet." end
  local parts = { realm = "", ruleset = AuctionAPI.ruleset(env), faction = faction }
  local ok, key = pcall(ns.MarketKey.build, parts)
  if not ok then return nil, tostring(key) end
  return key, parts
end

-- An item's name from the client's item cache, or nil while it isn't loaded.
function AuctionAPI:itemName(item)
  local id = type(item) == "string" and tonumber(item:match("^i:(%d+)$"))
  if not id then return nil end
  local items = self.env.C_Item
  return nonEmpty(items and try(items.GetItemNameByID, id)) or nonEmpty(try(self.env.GetItemInfo, id))
end

-- What Disenchant needs to know about an item, from GetItemInfo: { id, quality, classID, level, equip },
-- or nil while the item isn't in the client's cache.
function AuctionAPI:itemInfo(item)
  local id = type(item) == "string" and tonumber(item:match("^i:(%d+)$"))
  if not id then return nil end
  -- The global GetItemInfo, or C_Item.GetItemInfo where a client only has that one.
  local get = self.env.GetItemInfo
  if type(get) ~= "function" then get = self.env.C_Item and self.env.C_Item.GetItemInfo end
  if type(get) ~= "function" then return nil end
  local r = { pcall(get, id) }
  if not r[1] or r[2] == nil then return nil end
  -- name, link, quality, itemLevel, minLevel, type, subType, stackCount, equipLoc, texture, sellPrice, classID,
  -- subclassID
  return { id = id, quality = r[4], level = r[5], required = r[6], equip = r[10], classID = r[13],
    subclassID = r[14] }
end

-- An item's class, subclass and equip slot from GetItemInfoInstant, which answers without the item being
-- in the client's cache: { id, classID, subclassID, equip }, or nil when the client has no such call.
function AuctionAPI:itemType(item)
  local id = type(item) == "string" and tonumber(item:match("^i:(%d+)$"))
  if not id then return nil end
  local get = self.env.GetItemInfoInstant
  if type(get) ~= "function" then get = self.env.C_Item and self.env.C_Item.GetItemInfoInstant end
  if type(get) ~= "function" then return nil end
  local r = { pcall(get, id) }
  if not r[1] or r[2] == nil then return nil end
  -- itemID, type, subType, equipLoc, icon, classID, subclassID
  return { id = id, equip = r[5], classID = r[7], subclassID = r[8] }
end

function AuctionAPI:now()
  return try(self.env.GetServerTime) or try(self.env.time) or 0
end

-- Starts a full scan. onDone(listings, info) gets listings plus
-- { listings, incomplete, skipped, seconds } on success, or (nil, message) on failure.
-- Returns true when the scan started, or false and a message.
function AuctionAPI:scan(onDone)
  local C = self.env.C_AuctionHouse
  if self.pending then return false, "A scan is already running." end
  if not self.open then return false, "Open the auction house to scan." end
  if not (C and C.ReplicateItems and C.GetNumReplicateItems and C.GetReplicateItemInfo) then
    return false, "This client can't do a full scan (C_AuctionHouse.ReplicateItems is missing)."
  end
  -- The client keeps the last replicate list, so remember its size: polling only accepts a
  -- list that differs from it, never an old one left over from an earlier or throttled scan.
  local pending = { onDone = onDone, started = self:now(), seen = {}, order = {}, first = {}, unknown = {},
    before = try(C.GetNumReplicateItems) or 0, stable = 0 }
  self.pending = pending
  for _, event in ipairs(AuctionAPI.TRACE_EVENTS) do
    if not pcall(self.events.RegisterEvent, self.events, event) then pending.unknown[#pending.unknown + 1] = event end
  end
  local ok, err = pcall(C.ReplicateItems)
  if not ok then
    self:finish(nil, "The auction house refused the scan: " .. tostring(err))
    return false, "The auction house refused the scan: " .. tostring(err)
  end
  if self.env.C_Timer then
    self:poll(pending)
    self.env.C_Timer.After(AuctionAPI.TIMEOUT, function()
      if self.pending == pending then
        self:finish(nil, "No reply from the auction house after " .. AuctionAPI.TIMEOUT
          .. " seconds. Full scans may be limited to one every 15 minutes; try again later. "
          .. self:diagnosis(pending))
      end
    end)
  end
  return true
end

-- What the client did during a failed scan, for the self-test.
function AuctionAPI:diagnosis(pending)
  local events = {}
  for _, event in ipairs(pending.order) do
    local first = pending.first[event]
    events[#events + 1] = event .. " x" .. pending.seen[event] .. (first and (" (" .. first .. ")") or "")
  end
  return string.format("(replicate list: %s listings before, %s now; events: %s; not in this client: %s)",
    tostring(pending.before), tostring(try(self.env.C_AuctionHouse.GetNumReplicateItems)),
    #events > 0 and table.concat(events, ", ") or "none",
    #pending.unknown > 0 and table.concat(pending.unknown, ", ") or "none")
end

-- Fallback for clients that fill the replicate list without firing REPLICATE_ITEM_LIST_UPDATE:
-- read it once its size is non-zero, differs from the size before the scan, and has stayed the
-- same for two polls in a row.
function AuctionAPI:poll(pending)
  self.env.C_Timer.After(AuctionAPI.POLL, function()
    if self.pending ~= pending then return end
    local n = try(self.env.C_AuctionHouse.GetNumReplicateItems) or 0
    if n > 0 and n ~= pending.before and n == pending.lastCount then
      pending.stable = pending.stable + 1
      if pending.stable >= 2 then return self:complete("polling") end
    else
      pending.stable = 0
    end
    pending.lastCount = n
    self:poll(pending)
  end)
end

function AuctionAPI:finish(listings, info)
  local pending = self.pending
  self.pending = nil
  for _, event in ipairs(AuctionAPI.TRACE_EVENTS) do pcall(self.events.UnregisterEvent, self.events, event) end
  if pending and pending.onDone then pending.onDone(listings, info) end
end

function AuctionAPI:complete(via)
  local listings, info = self:readReplicate()
  info.seconds = self:now() - self.pending.started
  info.via = via
  self:finish(listings, info)
end

-- Reads the replicate list. Indices start at 0. The return order follows
-- C_AuctionHouse.GetReplicateItemInfo; the self-test shows a sample to confirm it in Forever.
function AuctionAPI:readReplicate()
  local C = self.env.C_AuctionHouse
  local listings, incomplete, skipped = {}, 0, 0
  local n = try(C.GetNumReplicateItems) or 0
  for i = 0, n - 1 do
    local ok, name, _, count, quality, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemID, hasAllInfo =
      pcall(C.GetReplicateItemInfo, i)
    if ok and itemID then
      listings[#listings + 1] = {
        item = "i:" .. tostring(itemID), name = nonEmpty(name), count = count, buyout = buyout,
        owner = nonEmpty(owner), quality = quality,
      }
      if not hasAllInfo then
        incomplete = incomplete + 1
        -- Ask the client to load the item, so the next scan or the Prices view has its name.
        local items = self.env.C_Item
        if items and items.RequestLoadItemDataByID then pcall(items.RequestLoadItemDataByID, itemID) end
      end
    else
      skipped = skipped + 1
    end
  end
  return listings, { listings = #listings, incomplete = incomplete, skipped = skipped }
end

function AuctionAPI:onEvent(event, ...)
  if event == "AUCTION_HOUSE_SHOW" then
    self.open = true
    return
  elseif event == "AUCTION_HOUSE_CLOSED" then
    self.open = false
    if self.pending then self:finish(nil, "The auction house closed before the scan finished.") end
    return
  end
  local pending = self.pending
  if not pending then return end
  if not pending.seen[event] then
    pending.order[#pending.order + 1] = event
    -- Keep the first text argument (for example a UI error message) to tell events apart.
    for i = 1, select("#", ...) do
      local arg = select(i, ...)
      if type(arg) == "string" and arg ~= "" then
        pending.first[event] = arg
        break
      end
    end
  end
  pending.seen[event] = (pending.seen[event] or 0) + 1
  if event == "REPLICATE_ITEM_LIST_UPDATE" then self:complete("event") end
end

-- Runs a scan of the current market into the price database and keeps a report for the
-- self-test. onDone(ok, message) is called when it ends.
function AuctionAPI.scanIntoPrices(addon, onDone)
  local api = addon.auctionAPI
  local key, why = AuctionAPI.currentMarket(api.env)
  if not key then return false, why end
  return api:scan(function(listings, info)
    if not listings then
      addon.lastScanReport = { ok = false, detail = info }
      return onDone(false, "Scan failed. " .. info)
    end
    -- Many listings arrive without a name (the item isn't in the client's cache yet); name what we can.
    local looked = {}
    for _, l in ipairs(listings) do
      if not l.name and l.item ~= nil then
        if looked[l.item] == nil then looked[l.item] = api:itemName(l.item) or false end
        l.name = looked[l.item] or nil
      end
    end
    local items = addon.prices:recordScan(key, api:now(), listings)
    local first = listings[1]
    addon.lastScanReport = {
      ok = true,
      detail = string.format("%d listings, %d items, %d without full info, %d unreadable, %ds via %s; first: %s",
        info.listings, items, info.incomplete, info.skipped, info.seconds, info.via or "?",
        first and string.format("%s x%s for %s", tostring(first.name or first.item), tostring(first.count),
          tostring(first.buyout)) or "none"),
    }
    onDone(true, string.format("Scanned %d listings of %d items in %d seconds.", info.listings, items,
      info.seconds))
  end)
end

function AuctionAPI.install(env, addon)
  local api = AuctionAPI.new(env)
  addon.auctionAPI = api
  if addon.Probes then
    local suite = addon.Probes.suite()
    suite:add("Realm sources", function()
      local out = {}
      for _, source in ipairs(AuctionAPI.realmSources(env)) do
        out[#out + 1] = source[1] .. "=" .. tostring(source[2] or "(empty)")
      end
      return "info", table.concat(out, ", ")
    end)
    suite:add("Neutral auction house", function()
      local map = env.C_Map and try(env.C_Map.GetBestMapForUnit, "player")
      return "info", string.format("map %s: %s", tostring(map), AuctionAPI.neutralHouse(env) or "not neutral")
    end)
    suite:add("Market key", function()
      local key, why = AuctionAPI.currentMarket(env)
      if not key then return "fail", why end
      return "pass", string.format("%q (%s)", key, ns.MarketKey.describe(key))
    end)
    suite:add("Full scan", function()
      local report = addon.lastScanReport
      if not report then return "info", "not run yet: press Scan in Prices and history, then run this again" end
      return report.ok and "pass" or "fail", report.detail
    end)
  end
  return api
end

ns.AuctionAPI = AuctionAPI
if ns.MarketKey and CreateFrame then AuctionAPI.install(_G, ns) end
return AuctionAPI
