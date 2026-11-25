-- Snipe API (issue #12): the only module that browses the auction house for targets and buys auctions.
-- Thin on purpose; the rules live in Core/Sniper.lua. Checked in game; specs use spec/fake_client.lua.
--
-- Browsing uses C_AuctionHouse.SendBrowseQuery, which answers with AUCTION_HOUSE_BROWSE_RESULTS_UPDATED
-- (GetBrowseResults; the cheapest come first) or AUCTION_HOUSE_BROWSE_FAILURE. A browse waits for the
-- throttled message system like a search. One item's auctions come from PostingAPI:search, so searches
-- share one queue. Buying uses PlaceBid with the buyout, which needs a hardware event (a click or a
-- mouse wheel turn) and answers with AUCTION_HOUSE_PURCHASE_COMPLETED or AUCTION_HOUSE_SHOW_ERROR.
local _, ns = ...
ns = ns or {}

local SnipeAPI = {}
SnipeAPI.__index = SnipeAPI

SnipeAPI.TIMEOUT = 10
SnipeAPI.EVENTS = {
  "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_FAILURE", "AUCTION_HOUSE_PURCHASE_COMPLETED",
  "AUCTION_HOUSE_SHOW_ERROR", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
  "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
}

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a = pcall(fn, ...)
  if ok then return a end
  return nil
end

function SnipeAPI.new(env, postingAPI)
  local self = setmetatable({ env = env, posting = postingAPI, late = {} }, SnipeAPI)
  self.events = env.CreateFrame("Frame")
  self.events:SetScript("OnEvent", function(_, event, ...) self:onEvent(event, ...) end)
  for _, e in ipairs(SnipeAPI.EVENTS) do pcall(self.events.RegisterEvent, self.events, e) end
  return self
end

function SnipeAPI:open()
  return self.posting ~= nil and self.posting.open == true
end

local function after(self, fn)
  local timer = self.env.C_Timer
  if timer and timer.After then timer.After(SnipeAPI.TIMEOUT, fn) end
end

-- Sends a browse query (from Sniper.browseQuery). done(results) with the client's browse results, or
-- done(nil, why). One browse at a time.
function SnipeAPI:browse(query, done)
  local ah = self.env.C_AuctionHouse
  if not self:open() then return done(nil, "the auction house is closed") end
  if self.browsing then return done(nil, "a browse is already running") end
  if not (ah and ah.SendBrowseQuery and ah.GetBrowseResults) then
    return done(nil, "C_AuctionHouse.SendBrowseQuery is missing")
  end
  local job = { query = query, done = done }
  self.browsing = job
  after(self, function()
    if self.browsing == job then self:finishBrowse(job, nil, "no answer from the auction house") end
  end)
  if self.posting:ready() then self:sendBrowse(job) end
end

function SnipeAPI:sendBrowse(job)
  job.sent = true
  local ok, err = pcall(self.env.C_AuctionHouse.SendBrowseQuery, job.query)
  if not ok then self:finishBrowse(job, nil, "browse failed: " .. tostring(err)) end
end

function SnipeAPI:finishBrowse(job, results, why)
  if self.browsing ~= job then return end
  self.browsing = nil
  local ok, err = pcall(job.done, results, why)
  if not ok and self.env.geterrorhandler then try(self.env.geterrorhandler(), err) end
end

-- One item's auctions, as PostingAPI.readListings gives them (with auctionID and link).
function SnipeAPI:auctions(itemKey, done)
  self.posting:search({ item = "i:" .. itemKey.itemID, itemID = itemKey.itemID, itemKey = itemKey }, done)
end

-- Buys an auction at its buyout. Must run inside a click or a mouse wheel turn. done(true) once the
-- auction house confirms, done(false, why) otherwise. One buy at a time. A confirmation that comes after
-- the timeout calls done(true) again, so the spend still counts.
function SnipeAPI:buy(auctionID, price, done)
  local ah = self.env.C_AuctionHouse
  if not self:open() then return done(false, "the auction house is closed") end
  if self.buying then return done(false, "still waiting for the last buy") end
  if self.posting.pending then return done(false, "a post is still waiting for the auction house") end
  if not (ah and ah.PlaceBid) then return done(false, "C_AuctionHouse.PlaceBid is missing") end
  local job = { auctionID = auctionID, done = done }
  self.buying = job
  self.posting.buying = true -- its error event is ours, not a failed post
  after(self, function()
    if self.buying == job then
      self.late[auctionID] = job
      self:finishBuy(job, false, "no answer from the auction house")
    end
  end)
  local ok, err = pcall(ah.PlaceBid, auctionID, price)
  if not ok then self:finishBuy(job, false, "the auction house refused: " .. tostring(err)) end
end

function SnipeAPI:finishBuy(job, ok, why)
  if self.buying ~= job then return end
  self.buying = nil
  self.posting.buying = nil
  local fine, err = pcall(job.done, ok, why)
  if not fine and self.env.geterrorhandler then try(self.env.geterrorhandler(), err) end
end

function SnipeAPI:onEvent(event, arg)
  local ah = self.env.C_AuctionHouse
  if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
    local job = self.browsing
    if job and job.sent then self:finishBrowse(job, try(ah.GetBrowseResults) or {}) end
  elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" then
    if self.browsing then self:finishBrowse(self.browsing, nil, "the auction house couldn't browse") end
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    local job = self.browsing
    if job and not job.sent then self:sendBrowse(job) end
  elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
    -- The client dropped a query, maybe this browse: send it again once, when the system is ready.
    local job = self.browsing
    if job and job.sent and not job.resent then
      job.sent, job.resent = false, true
      if self.posting:ready() then self:sendBrowse(job) end
    end
  elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
    local job = self.buying
    if job and (arg == nil or arg == job.auctionID) then
      self:finishBuy(job, true)
    elseif arg ~= nil and self.late[arg] then
      local late = self.late[arg]
      self.late[arg] = nil
      local fine, err = pcall(late.done, true)
      if not fine and self.env.geterrorhandler then try(self.env.geterrorhandler(), err) end
    end
  elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
    if self.buying then self:finishBuy(self.buying, false, "sold to someone else, or the auction house refused") end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    if self.browsing then self:finishBrowse(self.browsing, nil, "the auction house closed") end
    if self.buying then self:finishBuy(self.buying, false, "the auction house closed") end
  end
end

function SnipeAPI:money()
  return try(self.env.GetMoney)
end

-- A sound for a new find, if the client has one.
function SnipeAPI:alert()
  local kit = self.env.SOUNDKIT
  local id = kit and (kit.AUCTION_WINDOW_OPEN or kit.UI_BNET_TOAST)
  if id then try(self.env.PlaySound, id) end
end

SnipeAPI.NEEDED = { "SendBrowseQuery", "GetBrowseResults", "PlaceBid" }

function SnipeAPI.install(env, addon)
  local api = SnipeAPI.new(env, addon.postingAPI)
  addon.snipeAPI = api
  if addon.Probes then
    addon.Probes.suite():add("Snipe API", function()
      local ah = env.C_AuctionHouse or {}
      local missing = {}
      for _, name in ipairs(SnipeAPI.NEEDED) do
        if type(ah[name]) ~= "function" then missing[#missing + 1] = "C_AuctionHouse." .. name end
      end
      if #missing > 0 then return "fail", "missing: " .. table.concat(missing, ", ") end
      return "pass", "browse and buy are available"
    end)
  end
  return api
end

ns.SnipeAPI = SnipeAPI
if CreateFrame then SnipeAPI.install(_G, ns) end
return SnipeAPI
