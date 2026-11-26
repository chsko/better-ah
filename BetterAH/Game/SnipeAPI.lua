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
-- The auction house answers a browse a page at a time (500 results here). A check reads the first page
-- and up to this many more, so cheap listings past the first page are seen too.
SnipeAPI.MAX_PAGES = 10
SnipeAPI.EVENTS = {
  "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "AUCTION_HOUSE_BROWSE_FAILURE",
  "AUCTION_HOUSE_PURCHASE_COMPLETED",
  "AUCTION_HOUSE_SHOW_ERROR", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
  "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
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
  local job = { query = query, done = done, pages = 0 }
  self.browsing = job
  self:waitFor(job)
  if self.posting:ready() then self:sendBrowse(job) end
end

-- Each page gets its own TIMEOUT. A page that never comes ends the browse with the pages read so far.
function SnipeAPI:waitFor(job)
  local stamp = {}
  job.stamp = stamp
  after(self, function()
    if self.browsing ~= job or job.stamp ~= stamp then return end
    if job.results then return self:finishBrowse(job, job.results) end
    self:finishBrowse(job, nil, "no answer from the auction house")
  end)
end

-- After a page: ask for the next one while the auction house has more, up to MAX_PAGES.
function SnipeAPI:more(job)
  local ah = self.env.C_AuctionHouse
  local full = try(ah.HasFullBrowseResults)
  if full ~= false or type(ah.RequestMoreBrowseResults) ~= "function" or job.pages >= SnipeAPI.MAX_PAGES then
    return self:finishBrowse(job, job.results)
  end
  job.wantMore = true
  self:waitFor(job)
  if self.posting:ready() then self:requestMore(job) end
end

function SnipeAPI:requestMore(job)
  job.wantMore, job.paging = false, true
  job.pages = job.pages + 1
  local ok = pcall(self.env.C_AuctionHouse.RequestMoreBrowseResults)
  if not ok then self:finishBrowse(job, job.results) end
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
  -- Called directly, in the click's own call stack, the way Blizzard's UI and TSM do: the game only lets
  -- an addon buy inside a hardware event. An error here is a real error; the timeout ends the buy.
  ah.PlaceBid(auctionID, price)
end

function SnipeAPI:finishBuy(job, ok, why)
  if self.buying ~= job then return end
  self.buying = nil
  self.posting.buying = nil
  local fine, err = pcall(job.done, ok, why)
  if not fine and self.env.geterrorhandler then try(self.env.geterrorhandler(), err) end
end

function SnipeAPI:onEvent(event, arg, arg2)
  local ah = self.env.C_AuctionHouse
  if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    -- The game stopped a call (arg: the tainted addon, arg2: the function). Name it on the buy that was
    -- waiting, so the session log says what the game refused.
    -- The event fires inside the blocked call, so it is PlaceBid's only when it names PlaceBid.
    if self.buying and tostring(arg2 or ""):find("PlaceBid", 1, true) then
      self:finishBuy(self.buying, false, string.format("the game %s %s", event == "ADDON_ACTION_FORBIDDEN"
        and "forbids addons to call" or "blocked", tostring(arg2 or "a protected call")))
    end
  elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
    local job = self.browsing
    -- Only the first answer: a later UPDATED during paging comes from another query (an item search).
    if job and job.sent and not job.paging and not job.results then
      -- A copy: later pages are added to it.
      job.results = {}
      for _, r in ipairs(try(ah.GetBrowseResults) or {}) do job.results[#job.results + 1] = r end
      self:more(job)
    end
  elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
    local job = self.browsing
    if job and job.paging then
      job.paging = false
      for _, r in ipairs(type(arg) == "table" and arg or {}) do job.results[#job.results + 1] = r end
      self:more(job)
    end
  elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" then
    if self.browsing then self:finishBrowse(self.browsing, nil, "the auction house couldn't browse") end
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    local job = self.browsing
    if job and not job.sent then
      self:sendBrowse(job)
    elseif job and job.wantMore then
      self:requestMore(job)
    end
  elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
    -- The client dropped a query, maybe this browse: send it again once, when the system is ready.
    local job = self.browsing
    if job and job.paging and not job.reasked then
      -- Maybe the request for the next page: ask for it again once, when the system is ready.
      job.paging, job.reasked = false, true
      job.pages = job.pages - 1
      job.wantMore = true
      if self.posting:ready() then self:requestMore(job) end
    elseif job and job.sent and not job.results and not job.resent then
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
