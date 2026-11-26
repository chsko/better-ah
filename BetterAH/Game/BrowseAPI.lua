-- Browse API (#91, #93, #94): what the Browse view asks of the client. Browsing goes through SnipeAPI:browse, so
-- browses share its paging and the throttled message queue; item names come from
-- C_AuctionHouse.GetItemKeyInfo, which answers nil until ITEM_KEY_ITEM_INFO_RECEIVED. Thin on purpose;
-- the rules live in Core/Browse.lua. Checked in game; specs use spec/fake_client.lua.
local _, ns = ...
ns = ns or {}

local BrowseAPI = {}
BrowseAPI.__index = BrowseAPI

BrowseAPI.EVENTS = {
  "ITEM_KEY_ITEM_INFO_RECEIVED", "GET_ITEM_INFO_RECEIVED", "AUCTION_HOUSE_SHOW_ERROR",
  "AUCTION_HOUSE_SHOW_NOTIFICATION",
  "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED",
  "AUCTION_HOUSE_CLOSED", "PLAYER_MONEY", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
}
-- How long to wait for the auction house to answer a bid or a commodity quote or purchase, in seconds.
BrowseAPI.TIMEOUT = 10
-- A bid has no event of its own when it works: no error within this many seconds counts as placed.
BrowseAPI.BID_SETTLE = 4

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
  self.events:SetScript("OnEvent", function(_, event, ...) self:onEvent(event, ...) end)
  for _, e in ipairs(BrowseAPI.EVENTS) do pcall(self.events.RegisterEvent, self.events, e) end
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

function BrowseAPI:posting()
  return self.snipe and self.snipe.posting
end

-- The auctions of an item, or a commodity's listings, as the client's search returns them: for an item,
-- the raw GetItemSearchResultInfo tables (with bids, owners and time left); for a commodity,
-- PostingAPI.readListings' { unit, count, ownCount }. The list's .commodity says which.
function BrowseAPI.readAuctions(env, entry)
  if entry.commodity then
    local list, complete = ns.PostingAPI.readListings(env, entry)
    list.commodity = true
    return list, complete
  end
  local ah, list = env.C_AuctionHouse, { commodity = false }
  for i = 1, try(ah.GetNumItemSearchResults, entry.itemKey) or 0 do
    local r = try(ah.GetItemSearchResultInfo, entry.itemKey, i)
    if type(r) == "table" then list[#list + 1] = r end
  end
  return list, try(ah.HasFullItemSearchResults, entry.itemKey) ~= false
end

-- Looks up a browse row's auctions (row from Browse.rows). done(list, complete) with
-- BrowseAPI.readAuctions' list, or done(nil, why). Searches share PostingAPI's queue.
function BrowseAPI:auctions(row, done)
  local posting = self:posting()
  if not posting then return done(nil, "searching isn't ready yet") end
  posting:search({ item = "i:" .. row.itemID, itemID = row.itemID, name = row.name, itemKey = row.itemKey,
    commodity = row.commodity and true or false, unsure = row.commodity == nil, reader = BrowseAPI.readAuctions },
    done)
end

-- Why a buy or bid can't be sent now, or nil when it can.
function BrowseAPI:blocked()
  local posting = self:posting()
  if not self:open() then return "the auction house is closed" end
  if self.snipe.buying or self.bidding or self.commodity then return "still waiting for the last buy" end
  if posting.pending then return "a post is still waiting for the auction house" end
  if not posting:ready() then return "the auction house is still answering a search. Try again in a moment" end
  return nil
end

-- Buys an auction at its buyout, through SnipeAPI:buy. Must run inside a click. done(ok, why, kind), kind
-- as SnipeAPI gives it ("unknown": no answer, it may have gone through; a late success calls done(true)).
function BrowseAPI:buyout(auctionID, price, done)
  local why = self:blocked()
  if why then return done(false, why) end
  self.snipe:buy(auctionID, price, function(ok, reason, kind) done(ok, reason, kind) end, "Browse")
end

local function after(env, seconds, fn)
  local timer = env.C_Timer
  if timer and timer.After then timer.After(seconds, fn) end
end

-- Bids amount on an auction. Must run inside a click. The client fires no event when a bid works, so
-- the bid counts as placed when no error comes within BID_SETTLE seconds. done(ok, why).
function BrowseAPI:bid(auctionID, amount, done)
  local ah = self.env.C_AuctionHouse
  local why = self:blocked()
  if why then return done(false, why) end
  if not (ah and ah.PlaceBid) then return done(false, "C_AuctionHouse.PlaceBid is missing") end
  local job = { done = done }
  self.bidding = job
  local posting = self:posting()
  posting.buying = true -- an error now is the bid's, not a failed post
  after(self.env, BrowseAPI.BID_SETTLE, function() self:finishBid(job, true) end)
  -- While placing, a block the game reports is this call's (the event fires inside it).
  self.placing = job
  ah.PlaceBid(auctionID, amount)
  self.placing = nil
end

function BrowseAPI:finishBid(job, ok, why)
  if self.bidding ~= job then return end
  self.bidding = nil
  local posting = self:posting()
  if posting then posting.buying = nil end
  local fine, err = pcall(job.done, ok, why)
  if not fine and self.env.geterrorhandler then try(self.env.geterrorhandler(), err) end
end

-- Asks for a price quote on quantity of a commodity (C_AuctionHouse.StartCommoditiesPurchase, which has
-- restrictions: call it inside a click). done(unitPrice, totalPrice) with the quote, or done(nil, why).
-- confirmCommodity buys at it.
function BrowseAPI:quoteCommodity(itemID, quantity, done)
  local ah = self.env.C_AuctionHouse
  local why = self:blocked()
  if why then return done(nil, why) end
  if not (ah and ah.StartCommoditiesPurchase and ah.ConfirmCommoditiesPurchase) then
    return done(nil, "C_AuctionHouse.StartCommoditiesPurchase is missing")
  end
  local job = { itemID = itemID, quantity = quantity, quote = done, step = "quote" }
  self.commodity = job
  local posting = self:posting()
  if posting then posting.buying = true end -- an error now is the quote's, not a failed post
  after(self.env, BrowseAPI.TIMEOUT, function()
    if self.commodity == job and job.step == "quote" then
      self:endCommodity(job, nil, "no answer from the auction house")
    end
  end)
  job.placing = true
  local ok, err = pcall(ah.StartCommoditiesPurchase, itemID, quantity)
  job.placing = nil
  if not ok then self:endCommodity(job, nil, "the quote failed: " .. tostring(err)) end
end

-- Buys the quoted commodity. Must run inside a click. done(ok, why).
function BrowseAPI:confirmCommodity(done)
  local job, ah = self.commodity, self.env.C_AuctionHouse
  if not (job and job.step == "quoted") then return done(false, "the price quote ran out. Ask again") end
  job.step, job.buy = "buying", done
  local posting = self:posting()
  if posting then posting.buying = true end
  after(self.env, BrowseAPI.TIMEOUT, function()
    if self.commodity == job then self:endCommodity(job, false, "no answer from the auction house") end
  end)
  job.placing = true
  ah.ConfirmCommoditiesPurchase(job.itemID, job.quantity)
  job.placing = nil
end

-- Drops a quote without buying.
function BrowseAPI:cancelCommodity()
  local job, ah = self.commodity, self.env.C_AuctionHouse
  if not job or job.step == "buying" then return end
  if ah and ah.CancelCommoditiesPurchase then try(ah.CancelCommoditiesPurchase) end
  if job.step == "quote" then return self:endCommodity(job, nil, "cancelled") end
  self.commodity = nil
  self:releasePosting()
end

function BrowseAPI:releasePosting()
  local posting = self:posting()
  if posting then posting.buying = nil end
end

-- Ends the commodity job: the quote callback gets (a, b) while quoting, the buy callback while buying.
function BrowseAPI:endCommodity(job, a, b)
  if self.commodity ~= job then return end
  local fn = job.step == "buying" and job.buy or job.quote
  if job.step ~= "quoted" or a == nil then
    self.commodity = nil
    self:releasePosting()
    -- A purchase with no answer may still go through: a late success is still reported.
    if job.step == "buying" and a == false and b == "no answer from the auction house" then self.lateCommodity = job end
  end
  local fine, err = pcall(fn, a, b)
  if not fine and self.env.geterrorhandler then try(self.env.geterrorhandler(), err) end
end

function BrowseAPI:money()
  return try(self.env.GetMoney)
end

function BrowseAPI:me()
  return try(self.env.UnitGUID, "player")
end

function BrowseAPI:onEvent(event, a, b)
  if (event == "ITEM_KEY_ITEM_INFO_RECEIVED" or event == "GET_ITEM_INFO_RECEIVED") and self.onInfo then
    pcall(self.onInfo)
  elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    local job = self.placing or (self.commodity and self.commodity.placing and self.commodity)
    if job == self.bidding and job then
      self:finishBid(job, false, "the game blocked " .. tostring(b or "the bid"))
    elseif job and job == self.commodity then
      local why = "the game blocked " .. tostring(b or "the purchase")
      self:endCommodity(job, job.step == "buying" and false or nil, why)
    end
  elseif event == "PLAYER_MONEY" then
    if self.onMoney then pcall(self.onMoney) end
  elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
    if self.bidding then self:finishBid(self.bidding, false, "the auction house refused the bid") end
  elseif event == "AUCTION_HOUSE_SHOW_NOTIFICATION" then
    if self.bidding then self:finishBid(self.bidding, true) end
  elseif event == "COMMODITY_PRICE_UPDATED" then
    local job = self.commodity
    if job and job.step == "quote" then
      job.step = "quoted"
      self:endCommodity(job, a, b)
    elseif job and job.step == "quoted" then
      -- A new price for the same quote: the view shows it before Confirm.
      local fine, err = pcall(job.quote, a, b)
      if not fine and self.env.geterrorhandler then try(self.env.geterrorhandler(), err) end
    end
  elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
    local job = self.commodity
    if job and job.step == "quote" then
      self:endCommodity(job, nil, "that many aren't for sale at that price any more")
    end
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    local job = self.commodity
    if job and job.step == "buying" then
      self:endCommodity(job, true)
    elseif self.lateCommodity then
      local late = self.lateCommodity
      self.lateCommodity = nil
      local fine, err = pcall(late.buy, true)
      if not fine and self.env.geterrorhandler then try(self.env.geterrorhandler(), err) end
    end
  elseif event == "COMMODITY_PURCHASE_FAILED" then
    local job = self.commodity
    if job and job.step == "buying" then self:endCommodity(job, false, "the auction house refused the purchase") end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    if self.bidding then self:finishBid(self.bidding, false, "the auction house closed") end
    local job = self.commodity
    if job then
      if job.step == "quoted" then self.commodity = nil
      else self:endCommodity(job, job.step == "buying" and false or nil, "the auction house closed") end
    end
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
