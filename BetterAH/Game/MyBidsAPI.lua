-- My bids API (#95): the only module that asks for and reads the player's bids. Thin on purpose; the rules
-- live in Core/MyBids.lua, and bidding and buying out go through Game/BrowseAPI.lua (PlaceBid in a click).
-- Checked in game; specs use spec/fake_client.lua.
--
-- Forever's C_AuctionHouse (AuctionHouseDocumentation in BlizzardInterfaceCode): QueryBids(sorts, auctionIDs)
-- asks for the list, BIDS_UPDATED says it came, GetNumBids and GetBidInfo(i) read it (BidInfo: auctionID,
-- itemKey, itemLink, timeLeft band, minBid, bidAmount, buyoutAmount, bidder GUID). The list holds the
-- auctions you are the high bidder on, plus any you name in auctionIDs (an outbid one shows another
-- bidder): Blizzard's window passes the ids it saw earlier in the session, and marks those whose bidder
-- isn't UnitGUID("player") as outbid. BID_ADDED(bidID) follows a new bid.
local _, ns = ...
ns = ns or {}

local MyBidsAPI = {}
MyBidsAPI.__index = MyBidsAPI

MyBidsAPI.TIMEOUT = 10 -- seconds a QueryBids may take before the view stops waiting
MyBidsAPI.EVENTS = { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "BIDS_UPDATED", "BID_ADDED",
  "ITEM_KEY_ITEM_INFO_RECEIVED", "GET_ITEM_INFO_RECEIVED" }

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

local function positive(n)
  n = tonumber(n)
  return n and n > 0 and n or nil
end

-- The player's bids as Core/MyBids bids, plus whether the client has the whole list. nameOf(item) names a
-- bid whose link carries no name; ids still without one are added to missing, when given. nil when the
-- client can't say.
function MyBidsAPI.readBids(env, nameOf, missing)
  local ah = env.C_AuctionHouse
  if not (ah and ah.GetNumBids and ah.GetBidInfo) then return nil end
  local linkParts, quality = ns.MyAuctionsAPI and ns.MyAuctionsAPI.linkParts, ns.MyAuctionsAPI and
    ns.MyAuctionsAPI.QUALITY or {}
  local out = {}
  for i = 1, try(ah.GetNumBids) or 0 do
    local info = try(ah.GetBidInfo, i)
    local key = type(info) == "table" and type(info.itemKey) == "table" and info.itemKey
    if key and key.itemID and info.auctionID ~= nil then
      local item = "i:" .. key.itemID
      local name, color
      if linkParts then name, color = linkParts(info.itemLink) end
      if not name then
        local keyInfo = try(ah.GetItemKeyInfo, key)
        if type(keyInfo) == "table" then
          name = keyInfo.itemName ~= "" and keyInfo.itemName or nil
          color = color or (name and quality[keyInfo.quality])
        end
      end
      name = name or (nameOf and nameOf(item))
      if not name and missing then missing[key.itemID] = true end
      local bidder = info.bidder
      if bidder == "" or bidder == false then bidder = nil end
      out[#out + 1] = {
        id = info.auctionID, item = item, itemID = key.itemID, itemKey = key, name = name, color = color,
        link = info.itemLink, band = info.timeLeft, minBid = positive(info.minBid), bid = positive(info.bidAmount),
        buyout = positive(info.buyoutAmount), bidder = bidder,
      }
    end
  end
  local complete = not ah.HasFullBidResults or try(ah.HasFullBidResults) ~= false
  return out, complete
end

function MyBidsAPI.new(env)
  local self = setmetatable({ env = env, open = false, updates = 0, session = {} }, MyBidsAPI)
  self.events = env.CreateFrame("Frame")
  self.events:SetScript("OnEvent", function(_, event, ...) self:onEvent(event, ...) end)
  for _, e in ipairs(MyBidsAPI.EVENTS) do pcall(self.events.RegisterEvent, self.events, e) end
  return self
end

function MyBidsAPI:me()
  return try(self.env.UnitGUID, "player")
end

function MyBidsAPI:now()
  return tonumber(try(self.env.GetServerTime)) or 0
end

-- This character's store of bids (BetterAHDB.bids.characters[key], Core/MyBids.lua); a table for the
-- session when the character can't be told or nothing is saved. Kept here, not in the view, so a bid is
-- tracked whether or not My bids was opened.
function MyBidsAPI:store()
  local settings = self.addon and self.addon.bidSettings
  local tracker = ns.CharacterTracker
  local key = tracker and tracker.characterKey and tracker.characterKey(self.env) or nil
  if not (type(settings) == "table" and key) then return self.session end
  if type(settings.characters) ~= "table" then settings.characters = {} end
  local store = settings.characters[key]
  if type(store) ~= "table" then
    store = {}
    settings.characters[key] = store
  elseif not self.normalized then
    ns.MyBids.normalize(store)
  end
  self.normalized = true
  return store
end

-- A bid this character placed (from My bids or Browse), with its amount.
function MyBidsAPI:placed(id, amount)
  if id ~= nil and ns.MyBids then ns.MyBids.placed(self:store(), id, amount, self:now()) end
end

-- Asks for the bids, naming ids (auctions bid on before, so outbid ones are listed too). onChange(answered)
-- follows with BIDS_UPDATED; answered is true when that list answers this query. Returns whether it was sent.
-- With no answer in TIMEOUT seconds, onTimeout() follows and the next list no longer counts as the answer.
function MyBidsAPI:query(ids)
  local ah = self.env.C_AuctionHouse
  if not (self.open and ah and type(ah.QueryBids) == "function") then return false, "closed" end
  -- QueryBids goes through the throttled message system, like every other query.
  if type(ah.IsThrottledMessageSystemReady) == "function" and try(ah.IsThrottledMessageSystemReady) == false then
    return false, "busy"
  end
  local list = {}
  for i, id in ipairs(ids or {}) do list[i] = id end
  local ok = pcall(ah.QueryBids, {}, list)
  if not ok then return false, "failed" end
  local token = {}
  self.asked = token
  local timer = self.env.C_Timer
  if timer and timer.After then
    timer.After(MyBidsAPI.TIMEOUT, function()
      if self.asked ~= token then return end
      self.asked = nil
      self:call(self.onTimeout)
    end)
  end
  return true
end

-- readBids() for this client, asking it to load the items that have no name yet (once per visit each).
function MyBidsAPI:read(nameOf)
  local missing = {}
  local bids, complete = MyBidsAPI.readBids(self.env, nameOf, missing)
  self.waiting, self.askedItems = self.waiting or {}, self.askedItems or {}
  local items = self.env.C_Item
  for id in pairs(missing) do
    if not self.askedItems[id] then
      self.askedItems[id], self.waiting[id] = true, true
      if items and type(items.RequestLoadItemDataByID) == "function" then
        try(items.RequestLoadItemDataByID, id)
      else
        try(self.env.GetItemInfo, id)
      end
    end
  end
  return bids, complete
end

function MyBidsAPI:call(fn, ...)
  if not fn then return end
  local ok, err = pcall(fn, ...)
  if not ok and self.env.geterrorhandler then pcall(self.env.geterrorhandler(), err) end
end

function MyBidsAPI:onEvent(event, arg)
  if event == "AUCTION_HOUSE_SHOW" then
    self.open = true
  elseif event == "AUCTION_HOUSE_CLOSED" then
    self.open, self.asked, self.waiting, self.askedItems = false, nil, nil, nil
  elseif event == "BIDS_UPDATED" then
    local answered = self.asked ~= nil
    self.asked = nil
    self.updates = self.updates + 1
    if self.open then self:call(self.onChange, answered) end
  elseif event == "BID_ADDED" then
    -- Tracked even while My bids is closed, so it is named in later queries once outbid (Blizzard's window
    -- keeps its ids the same way). The amount comes from placed(), when the bid was ours to send.
    local id = tonumber(arg)
    if id and ns.MyBids then ns.MyBids.track(self:store(), id, self:now()) end
    if self.open then self:call(self.onAdded, arg) end
  elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" or event == "GET_ITEM_INFO_RECEIVED" then
    if not (self.waiting and self.waiting[arg]) then return end
    self.waiting[arg] = nil
    if self.open then self:call(self.onChange, false) end
  end
end

function MyBidsAPI.install(env, addon)
  local api = MyBidsAPI.new(env)
  addon.myBidsAPI = api
  api.addon = addon
  if addon.Probes then
    addon.Probes.suite():add("My bids", function()
      local ah = env.C_AuctionHouse or {}
      local missing = {}
      for _, name in ipairs({ "QueryBids", "GetNumBids", "GetBidInfo", "PlaceBid" }) do
        if type(ah[name]) ~= "function" then missing[#missing + 1] = "C_AuctionHouse." .. name end
      end
      if #missing > 0 then return "fail", "missing: " .. table.concat(missing, ", ") end
      local n = try(ah.GetNumBids) or 0
      local first = n > 0 and try(ah.GetBidInfo, 1)
      if type(first) ~= "table" then
        return "info", string.format("%d bids known (open My bids at the auction house to read them)", n)
      end
      return "info", string.format("%d bids; the first: minBid %s, bidAmount %s, buyoutAmount %s, timeLeft %s, "
        .. "yours %s", n, tostring(first.minBid), tostring(first.bidAmount), tostring(first.buyoutAmount),
        tostring(first.timeLeft), tostring(first.bidder ~= nil and first.bidder == try(env.UnitGUID, "player")))
    end)
  end
  return api
end

ns.MyBidsAPI = MyBidsAPI
if CreateFrame then MyBidsAPI.install(_G, ns) end
return MyBidsAPI
