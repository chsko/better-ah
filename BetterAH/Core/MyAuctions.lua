-- My auctions (#123): the player's own auctions, whether each has been undercut, and totals. Pure: the
-- My auctions view hands in the auctions the client reports and what each item's price check found, and
-- gets rows, counts and totals back. Takes over the cancel scan of #9.
--
-- An auction is { id, item = "i:id", key = check key, name, quantity, unit = buyout per unit (or nil),
--   bid = current bid (or nil), bidder = true when someone has bid, sold = true once it sold,
--   timeLeft = seconds left (or nil), band = Enum.AuctionHouseTimeLeftBand (or nil) }.
-- A check (one per check key) is { listings = { { unit, count, ownCount } }, at = time } once found,
-- { pending = true } while it runs, or { failed = reason }.
--
-- Each row has a kind, in the order the list sorts them:
--   "undercut"   someone else lists it cheaper (cheapest, by = how much cheaper per unit, cheaper = units)
--   "bid"        someone has bid on it
--   "failed"     its price check got no answer
--   "checking"   its price check is running
--   "unchecked"  not checked yet
--   "nobuyout"   it has no buyout price, so it can't be undercut
--   "lowest"     nobody else lists it cheaper (cheapest = the lowest other price, nil when nobody else)
--   "sold"       it sold and the gold is on its way by mail
local _, ns = ...
ns = ns or {}

local MyAuctions = {}

MyAuctions.CUT = 0.05 -- the auction house's cut of a sale
MyAuctions.SOON = 2 * 60 * 60 -- "ending soon" in the totals
MyAuctions.ORDER = { undercut = 1, bid = 2, failed = 3, checking = 4, unchecked = 5, nobuyout = 6, lowest = 7,
  sold = 8 }
MyAuctions.FILTERS = { "all", "undercut", "lowest", "sold" }

local function cheaperThan(listings, unit)
  local units, cheapest = 0, nil
  for _, l in ipairs(listings or {}) do
    local count = tonumber(l.count) or 0
    local others = count - math.min(count, tonumber(l.ownCount) or 0)
    local price = tonumber(l.unit)
    if others > 0 and price and price > 0 then
      if not cheapest or price < cheapest then cheapest = price end
      if unit and price < unit then units = units + others end
    end
  end
  return cheapest, units
end

-- One auction's row, given its check (or nil).
function MyAuctions.row(a, check)
  local row = { auction = a }
  if a.sold then
    row.kind = "sold"
  elseif a.bidder then
    row.kind = "bid"
  elseif not (a.unit and a.unit > 0) then
    row.kind = "nobuyout"
  elseif not check then
    row.kind = "unchecked"
  elseif check.pending then
    row.kind = "checking"
  elseif check.failed then
    row.kind, row.reason = "failed", check.failed
  else
    local cheapest, units = cheaperThan(check.listings, a.unit)
    row.cheapest = cheapest
    if cheapest and cheapest < a.unit then
      row.kind, row.by, row.cheaper = "undercut", math.ceil(a.unit - cheapest), units
    else
      row.kind = "lowest"
    end
  end
  -- An auction with a bid can be undercut too; say so in its row.
  if row.kind == "bid" and check and check.listings and a.unit then
    local cheapest = cheaperThan(check.listings, a.unit)
    row.cheapest = cheapest
    if cheapest and cheapest < a.unit then row.by = math.ceil(a.unit - cheapest) end
  end
  return row
end

-- Every auction as a row, sorted by kind, then name, then price.
function MyAuctions.rows(auctions, checks)
  local rows = {}
  for _, a in ipairs(auctions or {}) do rows[#rows + 1] = MyAuctions.row(a, checks and a.key and checks[a.key]) end
  table.sort(rows, function(x, y)
    local ox, oy = MyAuctions.ORDER[x.kind], MyAuctions.ORDER[y.kind]
    if ox ~= oy then return ox < oy end
    local nx, ny = (x.auction.name or x.auction.item or ""):lower(), (y.auction.name or y.auction.item or ""):lower()
    if nx ~= ny then return nx < ny end
    local ux, uy = x.auction.unit or 0, y.auction.unit or 0
    if ux ~= uy then return ux < uy end
    return (x.auction.id or 0) < (y.auction.id or 0)
  end)
  return rows
end

-- Which rows a filter shows: "all", "undercut", "lowest" or "sold".
function MyAuctions.shows(filter, row)
  if filter == "undercut" then return row.kind == "undercut" end
  if filter == "lowest" then return row.kind == "lowest" end
  if filter == "sold" then return row.kind == "sold" end
  return true
end

function MyAuctions.filter(rows, filter)
  local out = {}
  for _, r in ipairs(rows) do
    if MyAuctions.shows(filter, r) then out[#out + 1] = r end
  end
  return out
end

-- How many rows each filter shows: { all, undercut, lowest, sold }.
function MyAuctions.counts(rows)
  local counts = { all = 0, undercut = 0, lowest = 0, sold = 0 }
  for _, r in ipairs(rows) do
    for _, f in ipairs(MyAuctions.FILTERS) do
      if MyAuctions.shows(f, r) then counts[f] = counts[f] + 1 end
    end
  end
  return counts
end

-- What a sale brings in after the auction house cut, in whole copper.
function MyAuctions.net(copper)
  return math.floor(copper * (1 - MyAuctions.CUT) + 0.5)
end

-- Totals for the detail panel. marketValue(item) gives copper or nil; cancelCost(auction) gives copper
-- or nil. Returns { active, units, atYours, atMarket, unpriced = active auctions without a market
-- value, afterCut, soon, sold, soldGold = after the cut, undercut, undercutCost }.
function MyAuctions.totals(rows, marketValue, cancelCost)
  local t = { active = 0, units = 0, atYours = 0, atMarket = 0, unpriced = 0, afterCut = 0, soon = 0, sold = 0,
    soldGold = 0, undercut = 0, undercutCost = 0 }
  for _, r in ipairs(rows) do
    local a = r.auction
    local quantity = a.quantity or 1
    if r.kind == "sold" then
      t.sold = t.sold + 1
      local price = a.unit and a.unit * quantity or a.bid or 0
      t.soldGold = t.soldGold + MyAuctions.net(price)
    else
      t.active, t.units = t.active + 1, t.units + quantity
      local mine = (a.unit or 0) * quantity
      t.atYours = t.atYours + mine
      t.afterCut = t.afterCut + MyAuctions.net(mine)
      local value = marketValue and marketValue(a.item)
      if value then t.atMarket = t.atMarket + math.floor(value * quantity + 0.5) else t.unpriced = t.unpriced + 1 end
      if a.timeLeft and a.timeLeft <= MyAuctions.SOON or (not a.timeLeft and a.band and a.band <= 1) then
        t.soon = t.soon + 1
      end
      if r.kind == "undercut" then
        t.undercut = t.undercut + 1
        t.undercutCost = t.undercutCost + (cancelCost and cancelCost(a) or 0)
      end
    end
  end
  return t
end

-- The first undercut row, the one "Cancel next undercut" cancels, skipping ids in skip (cancels sent).
function MyAuctions.nextUndercut(rows, skip)
  for _, r in ipairs(rows) do
    if r.kind == "undercut" and not (skip and skip[r.auction.id]) then return r end
  end
  return nil
end

-- The distinct check keys of the auctions still up for sale, in list order, each with one auction to
-- build its search from.
function MyAuctions.toCheck(auctions)
  local seen, out = {}, {}
  for _, a in ipairs(auctions or {}) do
    if not a.sold and a.key and not seen[a.key] then
      seen[a.key] = true
      out[#out + 1] = a
    end
  end
  return out
end

-- Time left as a short text: from seconds when the client gives them, else from its time band.
MyAuctions.BANDS = { [0] = "< 30 min", [1] = "< 2 h", [2] = "< 12 h", [3] = "> 12 h" }
function MyAuctions.timeLeft(seconds, band)
  if seconds then
    if seconds >= 3600 then return string.format("%d h", math.floor(seconds / 3600 + 0.5)) end
    return string.format("%d min", math.max(1, math.ceil(seconds / 60)))
  end
  return band and MyAuctions.BANDS[band] or ""
end

ns.MyAuctions = MyAuctions
return MyAuctions
