-- Browse API (#91): what the Browse view asks of the client. Browsing goes through SnipeAPI:browse, so
-- browses share its paging and the throttled message queue; item names come from
-- C_AuctionHouse.GetItemKeyInfo, which answers nil until ITEM_KEY_ITEM_INFO_RECEIVED. Thin on purpose;
-- the rules live in Core/Browse.lua. Checked in game; specs use spec/fake_client.lua.
local _, ns = ...
ns = ns or {}

local BrowseAPI = {}
BrowseAPI.__index = BrowseAPI

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a = pcall(fn, ...)
  if ok then return a end
  return nil
end

-- onInfo, set by the view, is called when the client has loaded more item names.
function BrowseAPI.new(env, snipeAPI, auctionAPI)
  local self = setmetatable({ env = env, snipe = snipeAPI, auction = auctionAPI }, BrowseAPI)
  self.events = env.CreateFrame("Frame")
  self.events:SetScript("OnEvent", function(_, event) self:onEvent(event) end)
  pcall(self.events.RegisterEvent, self.events, "ITEM_KEY_ITEM_INFO_RECEIVED")
  pcall(self.events.RegisterEvent, self.events, "GET_ITEM_INFO_RECEIVED")
  return self
end

function BrowseAPI:open()
  return self.snipe ~= nil and self.snipe:open()
end

function BrowseAPI:busy()
  return self.snipe ~= nil and self.snipe.browsing ~= nil
end

-- Sends a browse query (from Browse.query). done(results, truncated) with every page read, truncated
-- when the auction house had more than were read; or done(nil, why).
function BrowseAPI:search(query, done)
  if not self.snipe then return done(nil, "browsing isn't ready yet") end
  self.snipe:browse(query, function(results, why)
    if not results then return done(nil, why) end
    local ah = self.env.C_AuctionHouse
    done(results, ah and try(ah.HasFullBrowseResults) == false)
  end)
end

-- { name, quality, isCommodity } for an item key, or nil while the client loads it.
function BrowseAPI:info(itemKey)
  local ah = self.env.C_AuctionHouse
  local info = ah and try(ah.GetItemKeyInfo, itemKey)
  if type(info) ~= "table" or not info.itemName or info.itemName == "" then return nil end
  return { name = info.itemName, quality = info.quality, isCommodity = info.isCommodity }
end

-- The required level of an item, or nil while the client loads it.
function BrowseAPI:required(itemID)
  local details = self.auction and self.auction:itemInfo("i:" .. itemID)
  return details and details.required or nil
end

-- An item's link for its tooltip, or nil.
function BrowseAPI:link(itemID)
  local get = self.env.GetItemInfo
  if type(get) ~= "function" then get = self.env.C_Item and self.env.C_Item.GetItemInfo end
  if type(get) ~= "function" then return nil end
  local ok, _, link = pcall(get, itemID)
  return ok and link or nil
end

-- The colour of an item quality, as r, g, b; white when the client doesn't know it.
function BrowseAPI:qualityColor(quality)
  local get = self.env.C_Item and self.env.C_Item.GetItemQualityColor
  if type(get) ~= "function" then get = self.env.GetItemQualityColor end
  if quality and type(get) == "function" then
    local ok, r, g, b = pcall(get, quality)
    if ok and r then return r, g, b end
  end
  return 1, 1, 1
end

function BrowseAPI:onEvent(event)
  if (event == "ITEM_KEY_ITEM_INFO_RECEIVED" or event == "GET_ITEM_INFO_RECEIVED") and self.onInfo then
    pcall(self.onInfo)
  end
end

function BrowseAPI.install(env, addon)
  local api = BrowseAPI.new(env, addon.snipeAPI, addon.auctionAPI)
  addon.browseAPI = api
  return api
end

ns.BrowseAPI = BrowseAPI
if CreateFrame then BrowseAPI.install(_G, ns) end
return BrowseAPI
