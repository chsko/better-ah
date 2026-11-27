-- Tooltip prices (#119): the lines Better AH adds to an item's tooltip. Pure: the caller passes what
-- is known about the item (market value, disenchant value, what was paid, how many are in the bags)
-- and gets lines back; Game/TooltipHook.lua puts them on the tooltip. Layout follows the mockup linked
-- from #119. Specs in spec/tooltip_prices_spec.lua.
local _, ns = ...
ns = ns or {}

local TooltipPrices = {}

TooltipPrices.AH_CUT = 0.05
TooltipPrices.TITLE = "Better AH"
TooltipPrices.NO_PRICE = "No price yet. It wasn't on the auction house in your scans."

-- The settings, kept in BetterAHDB.tooltip as what is turned off, so everything starts on.
TooltipPrices.SETTINGS = {
  { key = "show", label = "Show Better AH prices on item tooltips",
    tip = "Add market value and more to the tooltip of any item." },
  { key = "disenchant", label = "Disenchant value", sub = true,
    tip = "What disenchanting a green, blue or purple brings, from its materials' market values." },
  { key = "paid", label = "What you paid, and profit", sub = true,
    tip = "Only for items bought through Better AH (Snipe or Browse). Profit is after the 5% auction house cut." },
  { key = "shift", label = "Hold Shift for bag totals", sub = true,
    tip = "With Shift held, show the value of every one of the item in your bags." },
  { key = "lowest", label = "Min buyout", sub = true,
    tip = "The cheapest buyout in your latest scan, and how old that scan is. With Shift held, for all in your bags." },
  { key = "sales", label = "Sold, past 7 days", sub = true,
    tip = "How many you sold, of how many you posted, on all your characters in the last 7 days (from the Ledger)." },
  { key = "sellTime", label = "Best time to sell", sub = true,
    tip = "How good now is for selling the item, and its best 3 hours of the week, on the tooltip and the Post "
      .. "screen. Needs the companion app's data file (see docs/setup/companion.md)." },
}

function TooltipPrices.options(saved)
  local off = saved or {}
  local out = {}
  for _, s in ipairs(TooltipPrices.SETTINGS) do out[s.key] = off[s.key] ~= false end
  return out
end

function TooltipPrices.set(saved, key, on)
  if on == false then saved[key] = false else saved[key] = nil end
end

-- What selling brings after the auction house cut, in copper.
function TooltipPrices.afterCut(copper)
  return math.floor(copper * (1 - TooltipPrices.AH_CUT))
end

-- Money on a tooltip: from 1 gold up, rounded down to the silver, so lines don't end in copper noise.
function TooltipPrices.round(copper)
  local n = math.floor(math.abs(copper) + 0.5)
  if n >= 10000 then n = n - n % 100 end
  return copper < 0 and -n or n
end

-- item: {
--   value      market value per unit, or nil
--   disenchant disenchant value per unit, or nil (nil also when the item doesn't disenchant)
--   paid       { unit, units } from Purchases:paid, or nil
--   stackable  true when the item stacks (prices then say "each")
--   bags       how many are in the player's bags (0 for an item that isn't theirs)
--   shift      true while Shift is held
--   current    { lowest, listed, seen } from PriceDB:current, or nil (never in a scan)
--   now        the time, for how old the scan is
--   sales      { sold, posted } over the past 7 days from Ledger:soldAndPosted, or nil
--   sellTime   SellTimes.hint(...) for the item, or nil
-- }
-- opts: TooltipPrices.options(...).
-- Returns nil when nothing should be added, else { title, note, message, rows, hint }: note is dim text
-- after the title, message a dim line under it when the item has no market value, each row
-- { label, money (copper, rounded), sign = true for a profit (shown with + or -) } or
-- { label, text, dim = true for "nothing there", rating = 0-3 to colour a sell time }, and
-- hint a dim line
-- at the end. note, message and hint may be nil.
function TooltipPrices.lines(item, opts)
  opts = opts or TooltipPrices.options()
  if not opts.show then return nil end
  local value = item.value and item.value > 0 and item.value or nil
  local de = opts.disenchant and item.disenchant and item.disenchant > 0 and item.disenchant or nil
  local paid = opts.paid and item.paid or nil
  local bags = math.max(0, math.floor(tonumber(item.bags) or 0))
  local total = opts.shift and item.shift and bags > 1

  local out = { title = TooltipPrices.TITLE, rows = {} }
  local rows = out.rows
  local function money(label, copper, sign)
    rows[#rows + 1] = { label = label, money = TooltipPrices.round(copper), sign = sign }
  end

  -- count: how many it prices (the bag count while Shift is held, #210), like the other lines.
  local function lowest(count)
    -- Not without a market value: a scan that old says nothing about today, and the "no price" line says why.
    local c = opts.lowest and value and item.current
    if not c then return end
    local age = ns.Time and (" (" .. ns.Time.ago(c.seen, item.now) .. ")") or ""
    if c.listed and c.lowest and c.lowest > 0 then
      money("Min buyout" .. age, c.lowest * count)
    else
      rows[#rows + 1] = { label = "Min buyout" .. age, text = "none listed", dim = true }
    end
  end
  -- Your own sale rate: only once there is something to say.
  local function sales()
    local s = opts.sales and item.sales
    if not (s and (s.sold > 0 or s.posted > 0)) then return end
    -- Not "x of y": a sale counts when its gold is taken, so it can be of an auction posted before the week.
    rows[#rows + 1] = { label = "Sold, past 7 days", text = string.format("%d sold, %d posted", s.sold, s.posted) }
  end

  if total then
    out.note = "(" .. bags .. " in bags)"
    if value then money("Market value", value * bags) end
    lowest(bags)
    sales()
    if de then money("Disenchant value", de * bags) end
    if paid then
      local k = math.min(paid.units, bags)
      local part = k < bags and string.format(" (%d of %d)", k, bags) or ""
      money("You paid" .. part, paid.unit * k)
      local those = k < bags and string.format(" (those %d)", k) or ""
      if value then money("Profit if sold" .. those, TooltipPrices.afterCut(value * k) - paid.unit * k, true) end
      if de then
        money("Profit if disenchanted" .. those, TooltipPrices.afterCut(de * k) - paid.unit * k, true)
      end
    end
  else
    if item.stackable then out.note = "(each)" end
    if value then money("Market value", value) end
    lowest(1)
    sales()
    if de then money("Disenchant value", de) end
    if paid then
      money(paid.units > 1 and "You paid, average" or "You paid", paid.unit)
      if value then money("Profit if sold", TooltipPrices.afterCut(value) - paid.unit, true) end
      if de then money("Profit if disenchanted", TooltipPrices.afterCut(de) - paid.unit, true) end
    end
    if opts.shift and bags > 1 then out.hint = "Hold Shift for all " .. bags .. " in your bags" end
  end
  -- Best time to sell (#221): how good now is, then the best window and the advice.
  local st = opts.sellTime and item.sellTime
  if st and not st.none then
    rows[#rows + 1] = { label = "Sell now", text = st.word, rating = st.rating }
    rows[#rows + 1] = { label = "Best time", text = st.window }
    rows[#rows + 1] = { label = "", text = st.better .. " · " .. st.advice, dim = true }
  end
  if not value then
    out.message = TooltipPrices.NO_PRICE
  end
  return out
end

ns.TooltipPrices = TooltipPrices
return TooltipPrices
