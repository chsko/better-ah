-- Auction API: the only module that calls Forever's auction house functions. Forever has
-- C_AuctionHouse only (ADR 0004). Scans use ReplicateItems, which returns every listing on
-- the market in one reply. Checked in game with /bah selftest; specs use spec/fake_client.lua.
local _, ns = ...
ns = ns or {}

local AuctionAPI = {}
AuctionAPI.__index = AuctionAPI

AuctionAPI.TIMEOUT = 120

-- Maps (uiMapID) whose only auction house is a neutral one: Tanaris (Gadgetzan),
-- Stranglethorn Vale (Booty Bay) and Winterspring (Everlook).
AuctionAPI.NEUTRAL_MAPS = { [1446] = "Gadgetzan", [1434] = "Booty Bay", [1452] = "Everlook" }

-- env is the game's global table (_G in the client, a fake in specs).
function AuctionAPI.new(env)
  local self = setmetatable({ env = env }, AuctionAPI)
  self.events = env.CreateFrame("Frame")
  self.events:SetScript("OnEvent", function(_, event) self:onEvent(event) end)
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

-- The market the player is on now: key, parts, or nil and a reason.
-- Realm is pinned empty (ADR 0005): Forever has rulesets instead of realms and its
-- GetRealmName() is empty, so the market is ruleset plus faction. Realm sources are only
-- reported by the self-test. Neutral auction houses are their own faction, "Neutral".
function AuctionAPI.currentMarket(env)
  local rules = env.C_GameRules
  local mode = rules and try(rules.GetActiveGameMode)
  local faction = AuctionAPI.neutralHouse(env) and "Neutral" or nonEmpty(try(env.UnitFactionGroup, "player"))
  if not faction then return nil, "Your faction isn't known yet." end
  local parts = { realm = "", ruleset = mode ~= nil and tostring(mode) or "default", faction = faction }
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
  local pending = { onDone = onDone, started = self:now() }
  self.pending = pending
  self.events:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  local ok, err = pcall(C.ReplicateItems)
  if not ok then
    self:finish(nil, "The auction house refused the scan: " .. tostring(err))
    return false, "The auction house refused the scan: " .. tostring(err)
  end
  if self.env.C_Timer then
    self.env.C_Timer.After(AuctionAPI.TIMEOUT, function()
      if self.pending == pending then
        self:finish(nil, "No reply from the auction house after " .. AuctionAPI.TIMEOUT
          .. " seconds. Full scans may be limited to one every 15 minutes; try again later.")
      end
    end)
  end
  return true
end

function AuctionAPI:finish(listings, info)
  local pending = self.pending
  self.pending = nil
  self.events:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  if pending and pending.onDone then pending.onDone(listings, info) end
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

function AuctionAPI:onEvent(event)
  if event == "AUCTION_HOUSE_SHOW" then
    self.open = true
    return
  elseif event == "AUCTION_HOUSE_CLOSED" then
    self.open = false
    if self.pending then self:finish(nil, "The auction house closed before the scan finished.") end
    return
  end
  if event ~= "REPLICATE_ITEM_LIST_UPDATE" or not self.pending then return end
  local listings, info = self:readReplicate()
  info.seconds = self:now() - self.pending.started
  self:finish(listings, info)
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
    local items = addon.prices:recordScan(key, api:now(), listings)
    local first = listings[1]
    addon.lastScanReport = {
      ok = true,
      detail = string.format("%d listings, %d items, %d without full info, %d unreadable, %ds; first: %s",
        info.listings, items, info.incomplete, info.skipped, info.seconds,
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
