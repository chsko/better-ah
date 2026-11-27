-- Disenchant targets (issue #47): which greens to buy for disenchanting, and the most to pay for each.
-- A target is a set of item types, one green item level band, a profit and whether it is sniped. Its max
-- price is what an item of its band is worth disenchanted, after the auction house cut, minus the profit.
-- Pure: worth comes in from Disenchant values, item details from the AuctionAPI adapter.
local _, ns = ...
ns = ns or {}

local Targets = {}
Targets.__index = Targets

-- Item types, in the order the editor lists them. class is the disenchant class (armor or weapon).
Targets.TYPES = {
  { id = "cloth", label = "Cloth", class = "armor" },
  { id = "leather", label = "Leather", class = "armor" },
  { id = "mail", label = "Mail", class = "armor" },
  { id = "plate", label = "Plate", class = "armor" },
  { id = "shield", label = "Shields", class = "armor" },
  { id = "jewelry", label = "Jewelry", class = "armor" },
  { id = "onehand", label = "One-hand", class = "weapon" },
  { id = "twohand", label = "Two-hand", class = "weapon" },
  { id = "ranged", label = "Ranged", class = "weapon" },
}
Targets.BY_ID = {}
for _, t in ipairs(Targets.TYPES) do Targets.BY_ID[t.id] = t end

-- The four body armor types: what a new target and the name "Armor" mean.
Targets.ARMOR = { "cloth", "leather", "mail", "plate" }

-- Item subclass IDs (Enum.ItemArmorSubclass and Enum.ItemWeaponSubclass in the client).
local ARMOR_SUBCLASS = { [0] = "jewelry", [1] = "cloth", [2] = "leather", [3] = "mail", [4] = "plate",
  [6] = "shield" }
local WEAPON_SUBCLASS = {
  [0] = "onehand", [4] = "onehand", [7] = "onehand", [13] = "onehand", [15] = "onehand", -- axe mace sword fist dagger
  [1] = "twohand", [5] = "twohand", [6] = "twohand", [8] = "twohand", [10] = "twohand", -- 2H, polearm, staff
  [2] = "ranged", [3] = "ranged", [16] = "ranged", [18] = "ranged", [19] = "ranged", -- bow gun thrown crossbow wand
}
-- Misc armor (subclass 0) only counts as jewelry in these slots: the rest (shirts, tabards, held in
-- off-hand) either don't disenchant or aren't jewelry.
local JEWELRY_SLOTS = { INVTYPE_FINGER = true, INVTYPE_NECK = true, INVTYPE_TRINKET = true }

-- The item type of an item from AuctionAPI:itemInfo ({ classID, subclassID, equip }), or nil.
function Targets.typeOf(info)
  if type(info) ~= "table" then return nil end
  if info.classID == 4 then
    local t = ARMOR_SUBCLASS[info.subclassID]
    if t == "jewelry" and not JEWELRY_SLOTS[info.equip] then return nil end
    return t
  elseif info.classID == 2 then
    return WEAPON_SUBCLASS[info.subclassID]
  end
  return nil
end

-- The disenchant classes a target covers, as a set ({ armor = true, weapon = true }).
function Targets.classes(target)
  local out = {}
  for id, on in pairs(target.types or {}) do
    if on and Targets.BY_ID[id] then out[Targets.BY_ID[id].class] = true end
  end
  return out
end

-- The profit a target asks of an item worth `worth` copper.
function Targets.profitOf(target, worth)
  local p = target.profit or {}
  local amount = tonumber(p.amount) or 0
  if p.kind == "percent" then return math.floor(worth * amount / 100 + 0.5) end
  return math.floor(amount)
end

-- The most to pay for an item worth `worth` copper (after the cut), or nil without a worth. 0 means the
-- profit takes all of it: nothing is worth buying.
function Targets.maxPrice(target, worth)
  if not worth then return nil end
  return math.max(0, worth - Targets.profitOf(target, worth))
end

-- Whether a target takes an item: sniped, green, one of its types, in its item level band.
-- band is the target's band from Disenchant.greenBands ({ min, max }).
function Targets.matches(target, band, info)
  return target.enabled == true and Targets.takes(target, band, info)
end

-- Whether an item fits a target, sniped or not: green, one of its types, in its item level band.
function Targets.takes(target, band, info)
  if not (band and type(info) == "table") then return false end
  if tonumber(info.quality) ~= 2 then return false end
  local t = Targets.typeOf(info)
  if not (t and target.types and target.types[t]) then return false end
  local level = tonumber(info.level)
  return level ~= nil and level >= band.min and level <= band.max
end

-- The best buy for a target right now (#246): of listings ({ item, price, info }, price per item in copper,
-- info from AuctionAPI:itemInfo or nil while not loaded), the one the target takes with the most profit,
-- ties to the lower price. One the sniper would buy comes before one it wouldn't, so the colour says
-- whether it buys anything (with a percent profit on armor and weapons, the most profit can be short).
-- worthOf(class) gives what an item of the target's band and that disenchant class
-- ("armor", "weapon") is worth after the cut, or nil. Sniped or not, so unticked targets show it too.
-- Returns { item, price, worth, profit, max, status } or nil: status is "buy" when the price is at or under
-- the target's max price (what the sniper buys), "short" when it makes some profit but less than the
-- target asks, "loss" otherwise.
function Targets.best(target, band, listings, worthOf)
  local best
  for _, l in ipairs(listings or {}) do
    local price = tonumber(l.price) or 0
    if price > 0 and Targets.takes(target, band, l.info) then
      local worth = worthOf(Targets.BY_ID[Targets.typeOf(l.info)].class)
      if worth then
        local profit, max = worth - price, Targets.maxPrice(target, worth)
        local buys = max > 0 and price <= max
        if not best or (buys and not best.buys) or (buys == best.buys and (profit > best.profit
          or (profit == best.profit and price < best.price))) then
          best = { item = l.item, price = price, worth = worth, profit = profit, max = max, buys = buys }
        end
      end
    end
  end
  if not best then return nil end
  if best.buys then
    best.status = "buy"
  elseif best.profit > 0 then
    best.status = "short"
  else
    best.status = "loss"
  end
  best.buys = nil
  return best
end

-- What a target asks the auction house: its band and item types, as text (#246). Two targets, or one
-- target before and after an edit, with the same signature browse for the same items.
function Targets.signature(target)
  local ids = {}
  for _, t in ipairs(Targets.TYPES) do
    if target.types and target.types[t.id] then ids[#ids + 1] = t.id end
  end
  return tostring(target.band) .. ":" .. table.concat(ids, ",")
end

-- A short name for a target's types: "Armor", "Weapons", "All gear", or up to two labels and a count.
function Targets.typesText(target)
  local chosen, armor, weapons = {}, 0, 0
  for _, t in ipairs(Targets.TYPES) do
    if target.types and target.types[t.id] then
      chosen[#chosen + 1] = t.label
      if t.class == "weapon" then weapons = weapons + 1 end
    end
  end
  for _, id in ipairs(Targets.ARMOR) do
    if target.types and target.types[id] then armor = armor + 1 end
  end
  if #chosen == 0 then return "No item types" end
  if #chosen == #Targets.TYPES then return "All gear" end
  if armor == 4 and #chosen == 4 then return "Armor" end
  if weapons == 3 and #chosen == 3 then return "Weapons" end
  if #chosen <= 2 then return table.concat(chosen, ", ") end
  return chosen[1] .. ", " .. chosen[2] .. " +" .. (#chosen - 2)
end

-- The profit as the player set it: "3s 0c" or "20%".
function Targets.profitText(target)
  local p = target.profit or {}
  if p.kind == "percent" then return tostring(p.amount or 0) .. "%" end
  return ns.Money.format(math.floor(tonumber(p.amount) or 0))
end

-- The saved list of targets (BetterAHDB.disenchant.targets).
function Targets.new(saved)
  return setmetatable({ saved = saved }, Targets)
end

function Targets:list()
  return self.saved
end

-- A new target for the four armor types, with a 10% profit. band: an item level band's min. It starts
-- unticked (not sniped), so a running sniper doesn't buy for it before it is set up (#206).
function Targets:add(band)
  local types = {}
  for _, id in ipairs(Targets.ARMOR) do types[id] = true end
  local target = { types = types, band = band, profit = { kind = "percent", amount = 10 }, enabled = false }
  self.saved[#self.saved + 1] = target
  return target, #self.saved
end

function Targets:remove(index)
  return table.remove(self.saved, index)
end

ns.Targets = Targets
return Targets
