-- Character tracker: reads the current character's bags, bank and auctions from the game and
-- hands plain counts to CharacterRecords. Thin on purpose; checked in game and with the fake client.
--
-- Bag indices are Forever's Enum.BagIndex (build 1.60.1.71091): the backpack is 0, bags 1-4, the
-- reagent bag 5; the bank is the tabs CharacterBankTab_1-9 (6-14). Characterbanktab (-2) holds the bank's
-- bags themselves, not what is in the bank, so it is not read.
local _, ns = ...
ns = ns or {}

local CharacterTracker = {}
CharacterTracker.__index = CharacterTracker

CharacterTracker.BAGS = { 0, 1, 2, 3, 4, 5 }
CharacterTracker.BANK = { 6, 7, 8, 9, 10, 11, 12, 13, 14 }
local ACTIVE = 0 -- Enum.AuctionStatus.Active; sold auctions are no longer the player's items

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

-- "Name-serverID" from UnitGUID ("Player-6841-0A1B2C3D"), so same-named characters on different
-- rulesets stay apart. nil while the game hasn't said who the player is or has no GUID yet, so a
-- character is never also stored under its bare name.
function CharacterTracker.characterKey(env)
  local name = try(env.UnitName, "player")
  if type(name) ~= "string" or name == "" then return nil end
  local guid = try(env.UnitGUID, "player")
  local server = type(guid) == "string" and guid:match("^Player%-(%d+)%-")
  return server and (name .. "-" .. server) or nil
end

-- Every item in the given containers as { item, count, name }, plus the number of slots read.
-- Returns nil when the client has no C_Container.
function CharacterTracker.readContainers(env, containers)
  local api = env.C_Container
  if not (api and api.GetContainerNumSlots and api.GetContainerItemInfo) then return nil end
  local items, slots = {}, 0
  for _, bag in ipairs(containers) do
    local n = try(api.GetContainerNumSlots, bag) or 0
    for slot = 1, n do
      local info = try(api.GetContainerItemInfo, bag, slot)
      if type(info) == "table" and info.itemID then
        items[#items + 1] = { item = "i:" .. info.itemID, count = info.stackCount or 1, name = info.itemName }
      end
    end
    slots = slots + n
  end
  return items, slots
end

-- The player's active auctions as { item, count }; nil when the client can't say or has only part
-- of the list so far (HasFullOwnedAuctionResults), so a partial answer never replaces the full one.
function CharacterTracker.readAuctions(env)
  local api = env.C_AuctionHouse
  if not (api and api.GetNumOwnedAuctions and api.GetOwnedAuctionInfo) then return nil end
  if api.HasFullOwnedAuctionResults and try(api.HasFullOwnedAuctionResults) == false then return nil end
  local items = {}
  for i = 1, try(api.GetNumOwnedAuctions) or 0 do
    local info = try(api.GetOwnedAuctionInfo, i)
    local id = type(info) == "table" and type(info.itemKey) == "table" and info.itemKey.itemID
    if id and info.status == ACTIVE then
      items[#items + 1] = { item = "i:" .. id, count = info.quantity or 1 }
    end
  end
  return items
end

-- addon.characters (CharacterRecords) is looked up on each update: Init creates it on ADDON_LOADED,
-- after this file has loaded.
function CharacterTracker.new(env, addon)
  return setmetatable({ env = env, addon = addon }, CharacterTracker)
end

function CharacterTracker:now()
  return try(self.env.GetServerTime) or try(self.env.time) or 0
end

-- Reads one place into the records; returns true when it was read.
function CharacterTracker:update(place)
  local key = CharacterTracker.characterKey(self.env)
  local records = self.addon.characters
  if not (key and records) then return false end
  records:setCharacter(key, {
    name = try(self.env.UnitName, "player"), faction = try(self.env.UnitFactionGroup, "player"),
  })
  local items, slots
  if place == "bags" then
    items, slots = CharacterTracker.readContainers(self.env, CharacterTracker.BAGS)
  elseif place == "bank" then
    items, slots = CharacterTracker.readContainers(self.env, CharacterTracker.BANK)
  else
    items = CharacterTracker.readAuctions(self.env)
  end
  if not items then return false end
  -- Bags and bank always have slots; none means the game isn't ready to say, not that they're empty.
  if slots == 0 then return false end
  records:setPlace(key, place, items, self:now())
  if self.onChange then self.onChange(place) end
  return true
end

function CharacterTracker:onEvent(event)
  if event == "PLAYER_ENTERING_WORLD" or event == "BAG_UPDATE_DELAYED" or event == "PLAYER_LOGOUT" then
    self:update("bags")
    -- Bank tabs are containers too: moving items in or out of the bank fires BAG_UPDATE_DELAYED.
    if self.bankOpen then self:update("bank") end
  elseif event == "BANKFRAME_OPENED" then
    self.bankOpen = true
    self:update("bank")
  elseif event == "PLAYERBANKSLOTS_CHANGED" then
    if self.bankOpen then self:update("bank") end
  elseif event == "BANKFRAME_CLOSED" then
    -- Read once more on close: items moved in the last moment only show up in BAG_UPDATE.
    if self.bankOpen then self:update("bank") end
    self.bankOpen = false
  elseif event == "AUCTION_HOUSE_SHOW" or event == "AUCTION_HOUSE_AUCTION_CREATED" or event == "AUCTION_CANCELED" then
    -- Ask for the player's auctions (again after posting or cancelling); OWNED_AUCTIONS_UPDATED brings them.
    if event == "AUCTION_HOUSE_SHOW" then self.ahOpen = true end
    local api = self.env.C_AuctionHouse
    if self.ahOpen and api and api.QueryOwnedAuctions then try(api.QueryOwnedAuctions, {}) end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    self.ahOpen = false
  elseif event == "OWNED_AUCTIONS_UPDATED" then
    -- Only while the auction house is open: away from it the client knows of no auctions.
    if self.ahOpen then self:update("auctions") end
  end
end

CharacterTracker.EVENTS = {
  "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_LOGOUT", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
  "PLAYERBANKSLOTS_CHANGED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_AUCTION_CREATED",
  "AUCTION_CANCELED", "OWNED_AUCTIONS_UPDATED",
}

function CharacterTracker.install(env, addon)
  local tracker = CharacterTracker.new(env, addon)
  local events = env.CreateFrame("Frame")
  for _, event in ipairs(CharacterTracker.EVENTS) do pcall(events.RegisterEvent, events, event) end
  events:SetScript("OnEvent", function(_, event) tracker:onEvent(event) end)
  addon.tracker = tracker
  if addon.Probes then
    local suite = addon.Probes.suite()
    suite:add("Bags", function()
      local items, slots = CharacterTracker.readContainers(env, CharacterTracker.BAGS)
      if not items then return "fail", "C_Container.GetContainerNumSlots or GetContainerItemInfo is missing" end
      if slots == 0 then return "fail", "no bag slots found (looked at bags 0-5)" end
      local count = 0
      for _, it in ipairs(items) do count = count + it.count end
      return "pass", string.format("%d slots, %d items in %d stacks", slots, count, #items)
    end)
    suite:add("Bank", function()
      local key = CharacterTracker.characterKey(env)
      local seen
      for _, c in ipairs(addon.characters and addon.characters:characters() or {}) do
        if c.key == key then seen = c.seen and c.seen.bank end
      end
      local api = env.C_Container
      local ready = api and api.GetContainerNumSlots and api.GetContainerItemInfo and "yes" or "no"
      return "info", string.format("bank functions: %s; this character's bank last read: %s", ready,
        seen and ns.Time and ns.Time.ago(seen, tracker:now()) or "never (open your bank once)")
    end)
  end
  return tracker
end

ns.CharacterTracker = CharacterTracker
if CreateFrame then CharacterTracker.install(_G, ns) end
return CharacterTracker
