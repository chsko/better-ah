-- My bids (#95): the auctions this character has bid on, whether each bid is still the highest, and what
-- is tied up in bids. Pure: the My bids view hands in the bids the client reports and the character's
-- store of bids, and gets rows and totals back. Specs in spec/my_bids_spec.lua.
--
-- A bid, as Game/MyBidsAPI.lua reads it from C_AuctionHouse.GetBidInfo: { id = auctionID, item = "i:id",
--   itemID, itemKey, name, color, link, band = Enum.AuctionHouseTimeLeftBand, minBid = the lowest new
--   bid the auction house takes, bid = the current bid, buyout (or nil), bidder = the high bidder's GUID }.
--
-- The client only lists an auction you were outbid on when you ask for it by id (Blizzard's own window
-- keeps a list of ids for the session, Blizzard_AuctionHouseFrame.lua), and once outbid it no longer says
-- what you bid. So the store keeps, per auction id, { bid = what this character bid (or nil), at = when
-- it was last seen or bid, misses = answers in a row that left it out }. Its ids are what the next
-- query asks for; an auction that answers leave out twice (it ended, or was bought out) is forgotten.
local _, ns = ...
ns = ns or {}

local MyBids = {}

MyBids.MAX = 100 -- ids asked for at most, as Blizzard's window keeps (MaxNumActiveBidsTracked)
MyBids.MISSES = 2 -- answers in a row without an auction before it is forgotten
MyBids.MAX_AGE = 3 * 24 * 60 * 60 -- no auction lasts longer than 48 hours; a record older is stale
MyBids.ORDER = { outbid = 1, highest = 2 }
-- Enum.AuctionHouseTimeLeftBand: Short 0, Medium 1, Long 2, VeryLong 3.
MyBids.BANDS = { [0] = "under 30 min", [1] = "30 min-2 h", [2] = "2-12 h", [3] = "12-48 h" }

local function record(store, id)
  local r = store[id]
  if type(r) ~= "table" then return nil end
  return r
end

-- Drops anything in a store that isn't a record (a hand-edited or broken SavedVariables file).
function MyBids.normalize(store)
  if type(store) ~= "table" then return {} end
  for id, r in pairs(store) do
    if type(id) ~= "number" or type(r) ~= "table" then store[id] = nil
    else
      if r.bid ~= nil and type(r.bid) ~= "number" then r.bid = nil end
      if type(r.at) ~= "number" then r.at = 0 end
      if type(r.misses) ~= "number" then r.misses = 0 end
    end
  end
  return store
end

-- "highest" when this character is the high bidder, "outbid" otherwise.
function MyBids.status(bid, me)
  if me and bid.bidder ~= nil and bid.bidder == me then return "highest" end
  return "outbid"
end

-- Takes in what the client listed. answered: the list answers a query of ours (it was asked for every id
-- in the store), so an id it leaves out counts a miss. Highest bids are remembered with their amount;
-- an outbid one keeps the amount remembered before. Returns the store.
function MyBids.update(store, bids, me, now, answered)
  local seen = {}
  for _, b in ipairs(bids or {}) do
    if b.id ~= nil then
      seen[b.id] = true
      local r = record(store, b.id) or {}
      store[b.id] = r
      r.at, r.misses = now or r.at or 0, 0
      if MyBids.status(b, me) == "highest" then r.bid = b.bid end
    end
  end
  for id, r in pairs(store) do
    if not seen[id] then
      if answered then r.misses = (r.misses or 0) + 1 end
      if (r.misses or 0) >= MyBids.MISSES or (now and now - (r.at or 0) > MyBids.MAX_AGE) then store[id] = nil end
    end
  end
  -- Over the cap, the ones seen longest ago go.
  local ids = MyBids.ids(store, math.huge)
  for i = MyBids.MAX + 1, #ids do store[ids[i]] = nil end
  return store
end

-- The ids to ask the client about, the most recently seen first, at most max (default MAX).
function MyBids.ids(store, max)
  local out = {}
  for id, r in pairs(store or {}) do
    if type(r) == "table" then out[#out + 1] = id end
  end
  table.sort(out, function(a, b)
    local ta, tb = store[a].at or 0, store[b].at or 0
    if ta ~= tb then return ta > tb end
    return a < b
  end)
  max = max or MyBids.MAX
  for i = #out, max + 1, -1 do out[i] = nil end
  return out
end

-- A bid this character just placed.
function MyBids.placed(store, id, amount, now)
  local r = record(store, id) or {}
  store[id] = r
  r.bid, r.at, r.misses = amount, now or 0, 0
end

-- An auction bid on whose amount isn't known here (BID_ADDED): remembered so it is named in queries.
function MyBids.track(store, id, now)
  local r = record(store, id) or {}
  store[id] = r
  r.at, r.misses = now or r.at or 0, 0
end

-- An auction that is done with (bought out).
function MyBids.forget(store, id)
  store[id] = nil
end

-- Every bid as a row { bid, status, yours = what this character bid (or nil when not known) }: outbid
-- first, then the ones ending soonest, then by name.
function MyBids.rows(bids, store, me)
  local rows = {}
  for _, b in ipairs(bids or {}) do
    local status = MyBids.status(b, me)
    local r = store and record(store, b.id)
    local yours = status == "highest" and b.bid or (r and r.bid) or nil
    rows[#rows + 1] = { bid = b, status = status, yours = yours }
  end
  table.sort(rows, function(x, y)
    local ox, oy = MyBids.ORDER[x.status], MyBids.ORDER[y.status]
    if ox ~= oy then return ox < oy end
    local bx, by = x.bid.band or 9, y.bid.band or 9
    if bx ~= by then return bx < by end
    local nx, ny = (x.bid.name or x.bid.item or ""):lower(), (y.bid.name or y.bid.item or ""):lower()
    if nx ~= ny then return nx < ny end
    return (x.bid.id or 0) < (y.bid.id or 0)
  end)
  return rows
end

-- { count, highest, outbid, tiedUp = gold in bids that are still the highest (an outbid one is mailed back) }.
function MyBids.totals(rows)
  local t = { count = 0, highest = 0, outbid = 0, tiedUp = 0 }
  for _, r in ipairs(rows or {}) do
    t.count = t.count + 1
    if r.status == "highest" then
      t.highest = t.highest + 1
      t.tiedUp = t.tiedUp + (r.yours or 0)
    else
      t.outbid = t.outbid + 1
    end
  end
  return t
end

-- What a bid row looks like to Core/Buying's canBid and canBuyout.
function MyBids.buyRow(row)
  if not row then return nil end
  return { winning = row.status == "highest", minBid = row.bid.minBid, buyout = row.bid.buyout }
end

function MyBids.timeLeft(band)
  return band and MyBids.BANDS[band] or ""
end

ns.MyBids = MyBids
return MyBids
