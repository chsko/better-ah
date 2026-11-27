-- Disenchant watch (#256): sees the player disenchant a green and hands the item and the mats in its loot
-- window to Snipe profit (addon.snipeProfit). Thin on purpose: DisenchantTracker pairs the steps.
--
-- Which calls Forever has here is not checked yet (no API dump for loot and spells), so every one is
-- looked up before use and each step goes to the debug log (/bah debug on): the first disenchants in game
-- show which path works. Paths to the item, best first (DisenchantTracker picks):
--   1. The loot's source: GetLootSourceInfo(1) gives the item's GUID, C_Item.GetItemLinkByGUID its link
--      (may be nil: the item is gone by then).
--   2. The bag item locked when the cast starts (UNIT_SPELLCAST_START): the target is locked for the cast.
--   3. The bag item last used or picked up (hooks on C_Container.UseContainerItem and PickupContainerItem,
--      right and left click). A hook runs after the call, when targeting has ended, so every use is kept.
-- The mats: GetNumLootItems, GetLootSlotLink(slot) and GetLootSlotInfo(slot) (count is the 3rd return), on
-- LOOT_READY (or LOOT_OPENED, whichever comes first) within DisenchantTracker.WINDOW of the cast.
local _, ns = ...
ns = ns or {}

local DisenchantWatch = {}
DisenchantWatch.__index = DisenchantWatch

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if ok then return a, b, c end
  return nil
end

local function log(text, ...)
  if ns.debugLog then ns.debugLog:add("disenchant", text, ...) end
end

function DisenchantWatch.new(env, addon)
  return setmetatable({ env = env, addon = addon, tracker = ns.DisenchantTracker.new() }, DisenchantWatch)
end

function DisenchantWatch:now()
  return try(self.env.GetTime) or 0
end

-- A bag slot was used or picked up: it may have been a Disenchant's target.
function DisenchantWatch:used(bag, slot)
  local api = self.env.C_Container
  local info = api and try(api.GetContainerItemInfo, bag, slot)
  local link = type(info) == "table" and info.hyperlink or nil
  self.tracker:used(self:now(), link)
end

DisenchantWatch.BAGS = { 0, 1, 2, 3, 4 }

-- The link of the one bag item locked right now (a cast's target is), or nil when none or several are.
function DisenchantWatch:lockedItem()
  local api = self.env.C_Container
  if not (api and api.GetContainerNumSlots and api.GetContainerItemInfo) then return nil end
  local found
  for _, bag in ipairs(DisenchantWatch.BAGS) do
    for slot = 1, try(api.GetContainerNumSlots, bag) or 0 do
      local info = try(api.GetContainerItemInfo, bag, slot)
      if type(info) == "table" and info.isLocked and info.hyperlink then
        if found then return nil end
        found = info.hyperlink
      end
    end
  end
  return found
end

-- Every loot slot as { link, count }, and the link of the item the loot came from, when the game says.
function DisenchantWatch:readLoot()
  local env, slots = self.env, {}
  for i = 1, try(env.GetNumLootItems) or 0 do
    local _, _, count = try(env.GetLootSlotInfo, i)
    slots[#slots + 1] = { link = try(env.GetLootSlotLink, i), count = count }
  end
  local source
  local guid = try(env.GetLootSourceInfo, 1)
  if type(guid) == "string" and guid:match("^Item%-") and env.C_Item then
    source = try(env.C_Item.GetItemLinkByGUID, guid)
  end
  return slots, source, guid
end

function DisenchantWatch:loot()
  local slots, source, guid = self:readLoot()
  local got, why = self.tracker:loot(self:now(), slots, source)
  if not got then
    if why ~= "no cast" then log("loot not recorded (%s): %d slots, source %s", why, #slots, tostring(guid)) end
    return nil
  end
  local parts = {}
  for id, n in pairs(got.mats) do parts[#parts + 1] = id .. " x" .. n end
  log("disenchanted %s: %s", tostring(got.link), table.concat(parts, ", "))
  local profit = self.addon.snipeProfit
  if not profit then return got end
  local paid = self.addon.purchases and self.addon.purchases:paid("i:" .. got.item, got.suffix, 1)
  local tracker = self.addon.CharacterTracker
  local char = tracker and tracker.characterKey and tracker.characterKey(self.env) or nil
  profit:disenchanted(got.item, got.suffix, char, try(self.env.GetServerTime) or 0, got.mats, paid and paid.unit)
  return got
end

function DisenchantWatch:onEvent(event, unit, guid, spellID)
  local de = tonumber(spellID) == ns.DisenchantTracker.SPELL
  if event == "UNIT_SPELLCAST_START" and unit == "player" and de then
    local locked = self:lockedItem()
    log("Disenchant cast started, locked item %s, last used %s", tostring(locked),
      tostring(self.tracker.use and self.tracker.use.link))
    self.tracker:started(self:now(), guid, spellID, locked)
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" then
    if de then log("Disenchant cast finished") end
    self.tracker:succeeded(self:now(), guid, spellID)
  elseif (event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED") and unit == "player" then
    self.tracker:failed(guid, spellID)
  elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
    self:loot()
  end
end

DisenchantWatch.EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
  "UNIT_SPELLCAST_INTERRUPTED", "LOOT_READY", "LOOT_OPENED" }

-- The calls this file may use, for /bah selftest.
DisenchantWatch.CALLS = { "GetNumLootItems", "GetLootSlotLink", "GetLootSlotInfo",
  "GetLootSourceInfo", "C_Container.UseContainerItem", "C_Container.PickupContainerItem",
  "C_Container.GetContainerItemInfo", "C_Container.GetContainerNumSlots", "C_Item.GetItemLinkByGUID" }

function DisenchantWatch.missing(env)
  local out = {}
  for _, name in ipairs(DisenchantWatch.CALLS) do
    local space, fn = name:match("^(.-)%.(.+)$")
    local v
    if space then v = type(env[space]) == "table" and env[space][fn] else v = env[name] end
    if type(v) ~= "function" then out[#out + 1] = name end
  end
  return out
end

function DisenchantWatch.install(env, addon)
  local watch = DisenchantWatch.new(env, addon)
  local events = env.CreateFrame("Frame")
  for _, event in ipairs(DisenchantWatch.EVENTS) do pcall(events.RegisterEvent, events, event) end
  events:SetScript("OnEvent", function(_, event, ...) watch:onEvent(event, ...) end)
  local api = env.C_Container
  if type(env.hooksecurefunc) == "function" and type(api) == "table" then
    for _, name in ipairs({ "UseContainerItem", "PickupContainerItem" }) do
      if type(api[name]) == "function" then
        pcall(env.hooksecurefunc, api, name, function(bag, slot) watch:used(bag, slot) end)
      end
    end
  end
  addon.disenchantWatch = watch
  if addon.Probes then
    addon.Probes.suite():add("Disenchant watch", function()
      local missing = DisenchantWatch.missing(env)
      if #missing == 0 then return "pass", "every loot and spell call it uses is there" end
      return "info", "missing: " .. table.concat(missing, ", ")
    end)
  end
  return watch
end

ns.DisenchantWatch = DisenchantWatch
if CreateFrame then DisenchantWatch.install(_G, ns) end
return DisenchantWatch
