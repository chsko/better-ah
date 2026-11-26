-- Buying (#93, #94): the rules behind buying from the Browse view, without the WoW API. An item's
-- auctions as table rows (buy out or bid), and a commodity's price ladder: what a quantity costs, cheapest
-- first. Specs in spec/buying_spec.lua.
local _, ns = ...
ns = ns or {}

local Buying = {}

-- Enum.AuctionHouseTimeLeftBand: how long an auction has left, as the client tells it.
Buying.TIME_LEFT = { [0] = "< 30 min", [1] = "30 min - 2 h", [2] = "2 - 12 h", [3] = "12 - 48 h" }

function Buying.timeLeftText(band)
  return Buying.TIME_LEFT[band] or "-"
end

-- An item's auctions as rows, from the client's item search results (GetItemSearchResultInfo):
-- { auctionID, buyoutAmount, bidAmount, minBid, bidder, timeLeft, owners, containsOwnerItem,
-- containsAccountItem, quantity, itemLink }. me is the player's GUID, for the auctions they are the
-- highest bidder on; value the item's market value or nil. Rows:
-- { auctionID, buyout, bid, minBid, timeLeft, seller, own, winning, quantity, percent, link }.
function Buying.itemRows(results, me, value)
  local rows = {}
  for _, r in ipairs(results or {}) do
    if r.auctionID then
      local owners = r.owners or {}
      -- Blizzard's own test (AuctionHouseUtil.IsOwnedAuction): the only owner is you or your account.
      local own = (#owners == 1 and (r.containsOwnerItem or r.containsAccountItem))
        or (#owners == 2 and r.containsOwnerItem and r.containsAccountItem) or false
      local buyout = (r.buyoutAmount or 0) > 0 and r.buyoutAmount or nil
      local bid = (r.bidAmount or 0) > 0 and r.bidAmount or nil
      rows[#rows + 1] = { auctionID = r.auctionID, buyout = buyout, bid = bid, minBid = r.minBid,
        timeLeft = r.timeLeft, seller = owners[1], own = own and true or false,
        winning = me ~= nil and r.bidder ~= nil and r.bidder == me, quantity = math.max(1, r.quantity or 1),
        percent = ns.Browse and ns.Browse.percent(buyout, value) or nil, link = r.itemLink }
    end
  end
  -- Cheapest buyout first, auctions without one after them by their bid.
  table.sort(rows, function(a, b)
    if (a.buyout ~= nil) ~= (b.buyout ~= nil) then return a.buyout ~= nil end
    local x, y = a.buyout or a.minBid or 0, b.buyout or b.minBid or 0
    if x ~= y then return x < y end
    return a.auctionID < b.auctionID
  end)
  return rows
end

-- Whether the player can buy out a row now, or nil and why not. money is their gold in copper.
function Buying.canBuyout(row, money)
  if not row then return nil, "Select an auction." end
  if row.own then return nil, "That's your own auction." end
  if not row.buyout then return nil, "This auction has no buyout. You can bid on it." end
  if money and row.buyout > money then return nil, "You don't have enough gold." end
  return true
end

-- Whether a bid of amount on a row is allowed, or nil and why not.
function Buying.canBid(row, amount, money)
  if not row then return nil, "Select an auction." end
  if row.own then return nil, "That's your own auction." end
  if row.winning then return nil, "You're already the highest bidder." end
  if not amount or amount <= 0 then return nil, "Type how much to bid." end
  if row.minBid and amount < row.minBid then
    return nil, "The lowest you can bid is " .. ns.Money.format(row.minBid) .. "."
  end
  if row.buyout and amount >= row.buyout then return nil, "That's the buyout or more: buy it out instead." end
  if money and amount > money then return nil, "You don't have enough gold." end
  return true
end

-- Copper from the gold, silver and copper boxes (strings or numbers; blank is 0). nil when a box holds
-- something that isn't a whole number, or silver or copper is 100 or more.
function Buying.money(gold, silver, copper)
  local parts = {}
  for i, v in ipairs({ gold or "", silver or "", copper or "" }) do
    v = tostring(v):gsub("^%s+", ""):gsub("%s+$", "")
    local n = v == "" and 0 or tonumber(v)
    if not n or n < 0 or n ~= math.floor(n) or (i > 1 and n >= 100) then return nil end
    parts[i] = n
  end
  return parts[1] * 10000 + parts[2] * 100 + parts[3]
end

-- Gold, silver and copper of an amount in copper, for filling the boxes.
function Buying.split(copper)
  copper = math.max(0, math.floor(copper or 0))
  return math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
end

-- A commodity's price ladder for a quantity. listings are { unit, count, ownCount } (PostingAPI
-- readListings), cheapest first or not. Own units can't be bought, so they are left out. Returns
-- { rows = { { unit, count, running, runningTotal, take } }, available, quantity, total, average },
-- where take is how many of that row the quantity buys and quantity is clipped to what is available.
function Buying.ladder(listings, quantity, value)
  local sorted = {}
  for _, l in ipairs(listings or {}) do
    local count = (l.count or 0) - math.min(l.count or 0, l.ownCount or 0)
    if count > 0 and (l.unit or 0) > 0 then sorted[#sorted + 1] = { unit = l.unit, count = count } end
  end
  table.sort(sorted, function(a, b) return a.unit < b.unit end)
  local want = math.max(0, math.floor(tonumber(quantity) or 0))
  local running, runningTotal, total, bought = 0, 0, 0, 0
  for _, r in ipairs(sorted) do
    running = running + r.count
    runningTotal = runningTotal + r.unit * r.count
    r.running, r.runningTotal = running, runningTotal
    r.take = math.max(0, math.min(r.count, want - bought))
    bought = bought + r.take
    total = total + r.take * r.unit
    r.percent = ns.Browse and ns.Browse.percent(r.unit, value) or nil
  end
  return { rows = sorted, available = running, quantity = bought, total = total,
    average = bought > 0 and math.floor(total / bought + 0.5) or nil }
end

-- The most of a commodity money buys from a ladder's rows, cheapest first (all of it if money is nil).
function Buying.affordable(rows, money)
  local n, left = 0, money
  for _, r in ipairs(rows or {}) do
    if left == nil then
      n = n + r.count
    else
      local k = math.min(r.count, math.floor(left / r.unit))
      n, left = n + k, left - k * r.unit
      if k < r.count then break end
    end
  end
  return n
end

-- How a commodity quote compares to the price shown before it: "same" (or cheaper), "up", or
-- "unavailable" when the client has no quote.
function Buying.quote(shownTotal, quotedTotal)
  if not quotedTotal then return "unavailable" end
  if shownTotal and quotedTotal <= shownTotal then return "same" end
  return "up"
end

ns.Buying = Buying
return Buying
