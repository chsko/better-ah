-- Disenchant (#11): what an item disenchants into, and what that is worth. Pure: callers pass the
-- item's quality, class, item level and equip slot (from GetItemInfo) and a price lookup.
--
-- The table is Forever's, by item level band, quality, and armor or weapon. Source: the disenchant
-- rates TradeSkillMaster ships for Forever (its Forever table differs from Classic Era: weapons of
-- item level 21-30 give Greater Magic Essence, not Astral), written out here in our own form. Each
-- entry is a material, its chance per disenchant and how many drop; the expected amount is
-- chance * average count. Bands are by item level, not required level.
local _, ns = ...
ns = ns or {}

local Disenchant = {}

-- The base group (#12): every material a disenchant can give in Forever.
Disenchant.MATERIALS = {
  { id = 10940, name = "Strange Dust", kind = "dust" },
  { id = 11083, name = "Soul Dust", kind = "dust" },
  { id = 11137, name = "Vision Dust", kind = "dust" },
  { id = 11176, name = "Dream Dust", kind = "dust" },
  { id = 16204, name = "Illusion Dust", kind = "dust" },
  { id = 10938, name = "Lesser Magic Essence", kind = "essence" },
  { id = 10939, name = "Greater Magic Essence", kind = "essence" },
  { id = 10998, name = "Lesser Astral Essence", kind = "essence" },
  { id = 11082, name = "Greater Astral Essence", kind = "essence" },
  { id = 11134, name = "Lesser Mystic Essence", kind = "essence" },
  { id = 11135, name = "Greater Mystic Essence", kind = "essence" },
  { id = 11174, name = "Lesser Nether Essence", kind = "essence" },
  { id = 11175, name = "Greater Nether Essence", kind = "essence" },
  { id = 16202, name = "Lesser Eternal Essence", kind = "essence" },
  { id = 16203, name = "Greater Eternal Essence", kind = "essence" },
  { id = 10978, name = "Small Glimmering Shard", kind = "shard" },
  { id = 11084, name = "Large Glimmering Shard", kind = "shard" },
  { id = 11138, name = "Small Glowing Shard", kind = "shard" },
  { id = 11139, name = "Large Glowing Shard", kind = "shard" },
  { id = 11177, name = "Small Radiant Shard", kind = "shard" },
  { id = 11178, name = "Large Radiant Shard", kind = "shard" },
  { id = 14343, name = "Small Brilliant Shard", kind = "shard" },
  { id = 14344, name = "Large Brilliant Shard", kind = "shard" },
  { id = 20725, name = "Nexus Crystal", kind = "crystal" },
}
Disenchant.BY_ID = {}
for _, m in ipairs(Disenchant.MATERIALS) do Disenchant.BY_ID[m.id] = m end

local UNCOMMON, RARE, EPIC = 2, 3, 4
Disenchant.UNCOMMON, Disenchant.RARE, Disenchant.EPIC = UNCOMMON, RARE, EPIC

-- { id, chance, min, max }
local function m(id, chance, min, max) return { id = id, chance = chance, min = min, max = max or min } end

-- Uncommon bands: the dust, the essence and the shard. Armor gives mostly dust, weapons mostly
-- essence; the shard chance is the same for both.
local function green(min, max, dust, dMin, dMax, essence, eMin, eMax, shard, shardChance, weaponEssence)
  local armor = { m(dust, 0.75, dMin, dMax), m(essence, 0.20, eMin, eMax) }
  local weapon = { m(dust, 0.20, dMin, dMax), m(weaponEssence or essence, 0.75, eMin, eMax) }
  if shard then
    armor[#armor + 1] = m(shard, shardChance or 0.05, 1)
    weapon[#weapon + 1] = m(shard, shardChance or 0.05, 1)
  end
  return { quality = UNCOMMON, class = "armor", min = min, max = max, mats = armor },
    { quality = UNCOMMON, class = "weapon", min = min, max = max, mats = weapon }
end

local function rows(list, ...)
  for i = 1, select("#", ...) do list[#list + 1] = select(i, ...) end
end

local BANDS = {
  -- Item level 5-15 is 80/20 rather than 75/20, with no shard.
  { quality = UNCOMMON, class = "armor", min = 5, max = 15, mats = { m(10940, 0.80, 1, 2), m(10938, 0.20, 1, 2) } },
  { quality = UNCOMMON, class = "weapon", min = 5, max = 15, mats = { m(10940, 0.20, 1, 2), m(10938, 0.80, 1, 2) } },
}
rows(BANDS, green(16, 20, 10940, 2, 3, 10939, 1, 2, 10978))
-- 21-25: 15% essence and 10% shard on armor. Forever's weapons give Greater Magic Essence here.
rows(BANDS,
  { quality = UNCOMMON, class = "armor", min = 21, max = 25,
    mats = { m(10940, 0.75, 4, 6), m(10998, 0.15, 1, 2), m(10978, 0.10, 1) } },
  { quality = UNCOMMON, class = "weapon", min = 21, max = 25,
    mats = { m(10940, 0.15, 4, 6), m(10939, 0.75, 1, 2), m(10978, 0.10, 1) } })
rows(BANDS, green(26, 30, 11083, 1, 2, 11082, 1, 2, 11084, nil, 10939))
rows(BANDS, green(31, 35, 11083, 2, 5, 11134, 1, 2, 11138))
rows(BANDS, green(36, 40, 11137, 1, 2, 11135, 1, 2, 11139))
rows(BANDS, green(41, 45, 11137, 2, 5, 11174, 1, 2, 11177))
rows(BANDS, green(46, 50, 11176, 1, 2, 11175, 1, 2, 11178))
rows(BANDS, green(51, 55, 11176, 2, 5, 16202, 1, 2, 14343))
rows(BANDS, green(56, 60, 16204, 1, 2, 16203, 1, 2, 14344))
rows(BANDS, green(61, 99, 16204, 2, 5, 16203, 2, 3, 14344))

-- Rare (blue): low levels give dust and essence, then one shard (with a small Nexus Crystal chance
-- at the top). class nil means armor and weapons alike.
rows(BANDS,
  { quality = RARE, class = "armor", min = 5, max = 15, mats = { m(10940, 0.80, 2, 3), m(10938, 0.20, 2, 3) } },
  { quality = RARE, class = "armor", min = 16, max = 19,
    mats = { m(10940, 0.75, 3, 4), m(10939, 0.20, 2, 3), m(10978, 0.05, 1) } },
  { quality = RARE, class = "weapon", min = 16, max = 19,
    mats = { m(10940, 0.20, 3, 4), m(10939, 0.75, 2, 3), m(10978, 0.05, 1) } },
  { quality = RARE, min = 20, max = 25, mats = { m(10978, 1, 1) } },
  { quality = RARE, min = 26, max = 30, mats = { m(11084, 1, 1) } },
  { quality = RARE, min = 31, max = 35, mats = { m(11138, 1, 1) } },
  { quality = RARE, min = 36, max = 40, mats = { m(11139, 1, 1) } },
  { quality = RARE, min = 41, max = 45, mats = { m(11177, 1, 1) } },
  { quality = RARE, min = 46, max = 50, mats = { m(11178, 1, 1) } },
  { quality = RARE, min = 51, max = 55, mats = { m(14343, 1, 1) } },
  { quality = RARE, min = 56, max = 60, mats = { m(14344, 0.995, 1), m(20725, 0.005, 1) } },
  { quality = RARE, min = 61, max = 99, mats = { m(14344, 0.99, 1), m(20725, 0.01, 1) } })

-- Epic (purple), armor and weapons alike.
rows(BANDS,
  { quality = EPIC, min = 40, max = 45, mats = { m(11177, 1, 2, 4) } },
  { quality = EPIC, min = 46, max = 50, mats = { m(11178, 1, 2, 4) } },
  { quality = EPIC, min = 51, max = 55, mats = { m(14343, 1, 2, 4) } },
  { quality = EPIC, min = 56, max = 60, mats = { m(20725, 1, 1) } },
  { quality = EPIC, min = 61, max = 99, mats = { m(20725, 1, 1, 2) } })
Disenchant.BANDS = BANDS

-- Items that can't be disenchanted although they look like they could (quest and starter gear).
local EXCLUDED = {}
for _, id in ipairs({ 38, 45, 49, 53, 127, 148, 154, 2105, 2575, 2576, 2577, 2579, 2587, 3426, 3427, 3428, 4330,
  4332, 4333, 4334, 4335, 4336, 4344, 5107, 6096, 6097, 6117, 6120, 6125, 6134, 6136, 6384, 6385, 6795, 6796,
  6833, 10034, 10052, 10054, 10055, 10056, 11287, 11288, 11289, 11290, 13347, 16059, 16060, 17723, 18231, 20406,
  20407, 20408, 20897, 20901, 21766, 23345, 23473, 23476, 24143 }) do
  EXCLUDED[id] = true
end
Disenchant.EXCLUDED = EXCLUDED

-- GetItemInfo's classID: 2 is a weapon, 4 armor.
Disenchant.CLASS_IDS = { [2] = "weapon", [4] = "armor" }
local NOT_GEAR = { [""] = true, INVTYPE_NON_EQUIP = true, INVTYPE_NON_EQUIP_IGNORE = true, INVTYPE_BODY = true,
  INVTYPE_TABARD = true, INVTYPE_BAG = true, INVTYPE_AMMO = true, INVTYPE_QUIVER = true }

-- info: { id, quality, class = "armor"/"weapon" (or classID), level = item level, equip = equip slot }.
-- Returns the band's materials as { id, name, chance, min, max, expected } or nil and why not.
function Disenchant.yields(info)
  if type(info) ~= "table" then return nil, "unknown item" end
  local class = info.class or Disenchant.CLASS_IDS[info.classID]
  local quality, level = tonumber(info.quality), tonumber(info.level)
  if not (quality and level) then return nil, "item details not loaded yet" end
  if quality < UNCOMMON or quality > EPIC then return nil, "only green, blue and purple items disenchant" end
  if class ~= "armor" and class ~= "weapon" then return nil, "only armor and weapons disenchant" end
  if info.equip ~= nil and NOT_GEAR[info.equip] then return nil, "this item can't be disenchanted" end
  if info.id and EXCLUDED[info.id] then return nil, "this item can't be disenchanted" end
  for _, band in ipairs(BANDS) do
    if band.quality == quality and (band.class == nil or band.class == class)
      and level >= band.min and level <= band.max then
      local out = {}
      for _, mat in ipairs(band.mats) do
        out[#out + 1] = { id = mat.id, name = Disenchant.BY_ID[mat.id].name, chance = mat.chance, min = mat.min,
          max = mat.max, expected = mat.chance * (mat.min + mat.max) / 2 }
      end
      return out
    end
  end
  return nil, "no disenchant data for item level " .. level
end

-- The expected value of disenchanting the item, in copper. priceOf(materialID) gives a material's
-- market value or nil. Returns value (nil when no material has a price), the breakdown
-- ({ id, name, chance, min, max, expected, price, value } per material) and how many materials had
-- no price; or nil, nil, nil, why when the item doesn't disenchant.
function Disenchant.value(info, priceOf)
  local yields, why = Disenchant.yields(info)
  if not yields then return nil, nil, nil, why end
  local total, priced, missing = 0, 0, 0
  for _, y in ipairs(yields) do
    local price = priceOf and tonumber(priceOf(y.id))
    if price and price > 0 then
      y.price, y.value = price, math.floor(y.expected * price + 0.5)
      total, priced = total + y.expected * price, priced + 1
    else
      missing = missing + 1
    end
  end
  return priced > 0 and math.floor(total + 0.5) or nil, yields, missing
end

-- What selling the materials brings in after the auction house's 5% cut and the deposits, in copper.
Disenchant.AH_CUT = 0.05
function Disenchant.net(value, deposit)
  if not value then return nil end
  return math.floor(value * (1 - Disenchant.AH_CUT)) - math.floor(tonumber(deposit) or 0)
end

ns.Disenchant = Disenchant
return Disenchant
