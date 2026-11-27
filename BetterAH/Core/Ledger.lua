-- Ledger (#137): every copper that moves through the auction house, with totals over a period. Pure:
-- Game/LedgerAPI.lua reads the game (mail invoices, posts, buys) and hands plain values in; the Ledger view
-- (UI/LedgerView.lua) asks for totals, items and days. Specs in spec/ledger_spec.lua.
--
-- Kept in BetterAHDB.ledger as
--   entries = { entry, ... } oldest first, where an entry is
--     { t = time, k = kind, char = character key, name = item name, item = itemID or nil, n = units,
--       c = copper, cut = AH cut (sales), dep = deposit returned (sales), src = where a buy came from }
--   own = { { t, char, name, c, n }, ... } buys made through Better AH that the game may also mail an
--     invoice for (a buyer invoice): the invoice is then matched against them, so a buy counts once.
--   mail = { [char] = { c = copper, n = mails, at = time } } sale gold seen in the mailbox, not taken yet.
--
-- Kinds:
--   "sale"     an auction sold and its gold was taken from the mail. c = what it sold for (before the cut),
--              cut = the auction house's cut, dep = the deposit that came back with it.
--   "buy"      a buyout or a won bid. c = what was paid for all n units.
--   "deposit"  the deposit paid when posting. c = the deposit.
--
-- A sale counts once its gold is in the bags: the mail is the one record of a sale the game keeps. A deposit
-- counts when it is paid; the one that comes back with a sale is taken off the deposits again, so "deposits
-- kept" is the deposit of auctions still up or sold with their gold still in the mail (it comes back) and
-- of cancelled and expired ones (it is lost).
local _, ns = ...
ns = ns or {}

local Ledger = {}
Ledger.__index = Ledger

Ledger.MAX_ENTRIES = 20000 -- the oldest go first
Ledger.MAX_DAYS = 400
Ledger.OWN_DAYS = 30 -- how long a Better AH buy waits for its invoice: as long as auction mail lasts
Ledger.DAY = 86400
Ledger.PERIODS = { "today", "7d", "30d", "all" }
Ledger.PERIOD_DAYS = { today = 1, ["7d"] = 7, ["30d"] = 30 }
Ledger.KINDS = { sale = true, buy = true, deposit = true }

local function int(v) return math.floor((tonumber(v) or 0) + 0.5) end
local function str(v) return type(v) == "string" and v ~= "" and v or nil end

-- An item's plain name: the name in an item link ("|cff...|Hitem:...|h[Name]|h|r"), or the text itself.
-- Better AH's views hand in links; mail invoices give plain names, and the two must match (#150).
function Ledger.bareName(v)
  v = str(v)
  if not v then return nil end
  return str(v:match("|h%[(.-)%]|h")) or v
end
local name = Ledger.bareName

-- store is the saved-variables table (BetterAHDB.ledger in the client). A broken one starts over.
function Ledger.new(store)
  store = type(store) == "table" and store or {}
  if type(store.entries) ~= "table" then store.entries = {} end
  if type(store.own) ~= "table" then store.own = {} end
  if type(store.mail) ~= "table" then store.mail = {} end
  local ledger = setmetatable({ store = store }, Ledger)
  ledger:migrate()
  return ledger
end

Ledger.VERSION = 2

-- Brings an older store up to date. Version 1 (#137) never matched a Better AH buy to its invoice (links
-- against plain names) and could book one mail more than once (#150): every buy it took from the mail
-- ("Bought · other") is dropped, and the item links it kept become plain names.
function Ledger:migrate()
  local store = self.store
  if (tonumber(store.v) or 1) >= Ledger.VERSION then return end
  local kept = {}
  for _, e in ipairs(store.entries) do
    if type(e) == "table" and not (e.k == "buy" and e.src == "mail") then
      e.name = name(e.name) or e.name
      kept[#kept + 1] = e
    end
  end
  store.entries = kept
  for _, o in ipairs(store.own) do
    if type(o) == "table" then o.name = name(o.name) or o.name end
  end
  store.v = Ledger.VERSION
end

local function push(self, e)
  local list = self.store.entries
  list[#list + 1] = e
  if #list > Ledger.MAX_ENTRIES then table.remove(list, 1) end
  return e
end

-- A sale from a seller invoice whose gold was taken. s = { t, char, name, item, n, money = copper taken
-- from the mail, cut = the AH cut, deposit = deposit returned }. What it sold for is worked out from the
-- money, as the money is what really arrived: money = sold for - cut + deposit.
function Ledger:sale(s)
  local money, cut, dep = int(s.money), math.max(0, int(s.cut)), math.max(0, int(s.deposit))
  if money <= 0 then return nil end
  return push(self, { t = int(s.t), k = "sale", char = str(s.char), name = name(s.name) or "?", item = tonumber(s.item),
    n = math.max(1, int(s.n)), c = money + cut - dep, cut = cut, dep = dep })
end

-- A buy. b = { t, char, name, item, n, c = paid for all n, src }. own = true for a buy made through
-- Better AH, which the game may also send an invoice for: it is kept for matching (buyerInvoice).
function Ledger:buy(b, own)
  local c, n = int(b.c), math.max(1, int(b.n))
  if c <= 0 then return nil end
  local e = push(self, { t = int(b.t), k = "buy", char = str(b.char), name = name(b.name) or "?",
    item = tonumber(b.item), n = n, c = c, src = str(b.src) })
  if own then
    self.store.own[#self.store.own + 1] = { t = e.t, char = e.char, name = e.name, c = c, n = n }
  end
  return e
end

-- A buyer invoice taken from the mail: i = { t, char, name, n, c = what was paid }. When it is the invoice of
-- a buy Better AH already recorded (same character and item name, within OWN_DAYS, enough gold and units of
-- it left unmatched; a buy of exactly the invoice's price and count first), it only uses that buy up and
-- returns nil; a commodity bought from several sellers comes as several invoices, which use up one buy in
-- parts. Otherwise it is a buy made somewhere else (the game's
-- own auction house, another addon, a won bid) and is recorded with src "mail".
function Ledger:buyerInvoice(i)
  local c, item, char, t = int(i.c), name(i.name), str(i.char), int(i.t)
  if c <= 0 then return nil end
  local own, n = self.store.own, math.max(1, int(i.n))
  local function fits(o, exact)
    if o.char ~= char or t - o.t > Ledger.OWN_DAYS * Ledger.DAY or t < o.t - 300 then return false end
    -- A buy whose name wasn't known yet matches only an invoice of exactly its price and count.
    if o.name == "?" then return o.c == c and o.n == n end
    if o.name ~= item then return false end
    if exact then return o.c == c and o.n == n end
    return o.c >= c and o.n >= n
  end
  -- An invoice for a whole buy first, then one part of a commodity buy from several sellers.
  for _, exact in ipairs({ true, false }) do
    for x = 1, #own do
      local o = own[x]
      if fits(o, exact) then
        o.c, o.n = o.c - c, o.n - n
        if o.c <= 0 or o.n <= 0 then table.remove(own, x) end
        return nil
      end
    end
  end
  return self:buy({ t = t, char = char, name = item, n = i.n, c = c, src = "mail" })
end

-- A deposit paid for a post: d = { t, char, name, item, n, c }.
function Ledger:deposit(d)
  local c = int(d.c)
  if c <= 0 then return nil end
  return push(self, { t = int(d.t), k = "deposit", char = str(d.char), name = name(d.name) or "?",
    item = tonumber(d.item), n = math.max(1, int(d.n)), c = c })
end

-- The sale gold waiting in one character's mailbox, as last seen there.
function Ledger:setMail(char, copper, mails, t)
  if not str(char) then return end
  self.store.mail[char] = { c = math.max(0, int(copper)), n = math.max(0, int(mails)), at = int(t) }
end

-- The sale gold waiting in the mail: one character's, or all of them (char nil).
-- Returns copper, mails, and when the oldest of those counts was seen (nil when none).
function Ledger:inMail(char)
  local c, n, at = 0, 0, nil
  for key, m in pairs(self.store.mail) do
    if (char == nil or key == char) and type(m) == "table" then
      c, n = c + int(m.c), n + int(m.n)
      if m.at and (at == nil or m.at < at) then at = m.at end
    end
  end
  return c, n, at
end

-- Drops entries older than MAX_DAYS and own buys older than OWN_DAYS, at time now.
function Ledger:prune(now)
  now = int(now)
  local cutoff, kept = now - Ledger.MAX_DAYS * Ledger.DAY, {}
  for _, e in ipairs(self.store.entries) do
    if type(e) == "table" and Ledger.KINDS[e.k] and int(e.t) >= cutoff then kept[#kept + 1] = e end
  end
  self.store.entries = kept
  local own = {}
  for _, o in ipairs(self.store.own) do
    if type(o) == "table" and int(o.t) >= now - Ledger.OWN_DAYS * Ledger.DAY then own[#own + 1] = o end
  end
  self.store.own = own
end

-- The start of the local day that t falls in. offset = local time minus UTC, in seconds.
function Ledger.dayStart(t, offset)
  offset = int(offset)
  return math.floor((int(t) + offset) / Ledger.DAY) * Ledger.DAY - offset
end

-- When a period starts, at time now: "today" from local midnight, "7d" and "30d" that many local days back
-- (today included), "all" from the start (nil).
function Ledger.periodStart(period, now, offset)
  local days = Ledger.PERIOD_DAYS[period]
  if not days then return nil end
  return Ledger.dayStart(now, offset) - (days - 1) * Ledger.DAY
end

-- The entries from time `from` (nil: all) of one character (char nil: all), newest first.
function Ledger:entries(from, char)
  local out = {}
  local list = self.store.entries
  for i = #list, 1, -1 do
    local e = list[i]
    if (from == nil or e.t >= from) and (char == nil or e.char == char) then out[#out + 1] = e end
  end
  table.sort(out, function(a, b) return a.t > b.t end)
  return out
end

-- What an entry did to the player's gold: + for gold in, - for gold out. A sale gives what came in the mail
-- less its deposit, which is counted against the deposits: sold for - cut.
function Ledger.amount(e)
  if e.k == "sale" then return e.c - (e.cut or 0) end
  return -e.c
end

-- Totals of a list of entries:
--   sales (sold for, before the cut), sold (auctions), cut, purchases, bought (units), buys (entries),
--   deposits (paid), returned (deposits that came back with sales), kept = deposits - returned,
--   moneyIn = sales, moneyOut = purchases + cut + kept, net = moneyIn - moneyOut.
function Ledger.totals(entries)
  local t = { sales = 0, sold = 0, cut = 0, purchases = 0, bought = 0, buys = 0, deposits = 0, returned = 0,
    posts = 0 }
  for _, e in ipairs(entries) do
    if e.k == "sale" then
      t.sales, t.sold, t.cut, t.returned = t.sales + e.c, t.sold + 1, t.cut + (e.cut or 0), t.returned + (e.dep or 0)
    elseif e.k == "buy" then
      t.purchases, t.bought, t.buys = t.purchases + e.c, t.bought + (e.n or 1), t.buys + 1
    elseif e.k == "deposit" then
      t.deposits, t.posts = t.deposits + e.c, t.posts + 1
    end
  end
  t.kept = t.deposits - t.returned
  t.moneyIn = t.sales
  t.moneyOut = t.purchases + t.cut + t.kept
  t.net = t.moneyIn - t.moneyOut
  return t
end

-- One row per item name: { name, item, bought = units, paid = copper, sold = units, sales = copper before the
-- cut, cost = cut + deposits kept, profit = sales - paid - cost, last = newest entry time }, avgPaid and
-- avgSold per unit (nil with none). Sorted by profit, highest first, then name.
function Ledger.byItem(entries)
  local rows, byName = {}, {}
  for _, e in ipairs(entries) do
    local r = byName[e.name]
    if not r then
      r = { name = e.name, bought = 0, paid = 0, sold = 0, sales = 0, cut = 0, deposits = 0, returned = 0, last = e.t }
      byName[e.name] = r
      rows[#rows + 1] = r
    end
    r.item = r.item or e.item
    if e.t > r.last then r.last = e.t end
    if e.k == "sale" then
      r.sold, r.sales, r.cut, r.returned = r.sold + e.n, r.sales + e.c, r.cut + (e.cut or 0), r.returned + (e.dep or 0)
    elseif e.k == "buy" then
      r.bought, r.paid = r.bought + e.n, r.paid + e.c
    elseif e.k == "deposit" then
      r.deposits = r.deposits + e.c
    end
  end
  for _, r in ipairs(rows) do
    r.cost = r.cut + r.deposits - r.returned
    r.profit = r.sales - r.paid - r.cost
    r.avgPaid = r.bought > 0 and math.floor(r.paid / r.bought + 0.5) or nil
    r.avgSold = r.sold > 0 and math.floor(r.sales / r.sold + 0.5) or nil
  end
  table.sort(rows, function(a, b)
    if a.profit ~= b.profit then return a.profit > b.profit end
    return a.name < b.name
  end)
  return rows
end

-- One row per local day from the day of `from` to the day of `now`, oldest first:
-- { day = start time, moneyIn = gold that came in (sold for - cut + deposit back), moneyOut = purchases and
-- deposits paid, net, entries = count }. With from nil, from the day of the oldest entry (at most MAX_DAYS).
function Ledger.byDay(entries, from, now, offset)
  local last = Ledger.dayStart(now, offset)
  local first = from and Ledger.dayStart(from, offset)
  if not first then
    first = last
    for _, e in ipairs(entries) do
      local d = Ledger.dayStart(e.t, offset)
      if d < first then first = d end
    end
  end
  first = math.max(first, last - (Ledger.MAX_DAYS - 1) * Ledger.DAY)
  local days, index = {}, {}
  -- One offset for the whole range, so every day is 24 hours long (a clock change shifts days by an hour).
  for d = first, last, Ledger.DAY do
    local row = { day = d, moneyIn = 0, moneyOut = 0, net = 0, entries = 0 }
    days[#days + 1] = row
    index[d] = row
  end
  for _, e in ipairs(entries) do
    local row = index[Ledger.dayStart(e.t, offset)]
    if row then
      if e.k == "sale" then
        row.moneyIn = row.moneyIn + e.c - (e.cut or 0) + (e.dep or 0)
      else
        row.moneyOut = row.moneyOut + e.c
      end
      row.entries = row.entries + 1
    end
  end
  for _, row in ipairs(days) do row.net = row.moneyIn - row.moneyOut end
  return days
end

ns.Ledger = Ledger
return Ledger
