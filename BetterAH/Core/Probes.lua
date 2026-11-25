-- The checks `/bah selftest` runs inside the client. They only read the game
-- environment; they never buy, post or cancel. Later modules add their own
-- checks with ns.Probes.suite():add(name, fn).
local _, ns = ...
ns = ns or {}

local Probes = {}

local LEGACY_AH = {
  "QueryAuctionItems", "GetNumAuctionItems", "GetAuctionItemInfo", "GetAuctionItemLink",
  "CanSendAuctionQuery", "PostAuction", "StartAuction", "CancelAuction", "PlaceAuctionBid",
  "GetOwnerAuctionItems", "ClickAuctionSellItemButton", "GetAuctionSellItemInfo",
  "CalculateAuctionDeposit", "GetAuctionItemTimeLeft", "SortAuctionItems",
}

local MODERN_AH = {
  "SendBrowseQuery", "GetBrowseResults", "ReplicateItems", "GetNumReplicateItems",
  "GetReplicateItemInfo", "PostItem", "PostCommodity", "CancelAuction", "PlaceBid",
  "StartCommoditiesPurchase", "QueryOwnedAuctions", "SendSearchQuery", "GetItemSearchResultInfo",
  "GetCommoditySearchResultInfo", "ConfirmCommoditiesPurchase", "CalculateItemDeposit",
  "CalculateCommodityDeposit", "GetNumOwnedAuctions", "GetOwnedAuctionInfo", "GetAvailablePostCount",
}

local function presence(container, names)
  local found, missing = {}, {}
  for _, name in ipairs(names) do
    if container and type(container[name]) == "function" then
      found[#found + 1] = name
    else
      missing[#missing + 1] = name
    end
  end
  return found, missing
end

local function describePresence(found, missing)
  return string.format("found: %s; missing: %s",
    #found > 0 and table.concat(found, ", ") or "none",
    #missing > 0 and table.concat(missing, ", ") or "none")
end

local function call(env, path, ...)
  local fn = env
  for part in path:gmatch("[^.]+") do
    if type(fn) ~= "table" then return nil end
    fn = fn[part]
  end
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if not ok then return true, "error" end
  return true, value
end

local function build()
  local suite = ns.SelfTest.new()

  suite:add("Interface version", function(env)
    local version, buildNumber, _, interface = env.GetBuildInfo()
    return "info", string.format("%s (build %s.%s)", tostring(interface), tostring(version), tostring(buildNumber))
  end)

  suite:add("Realm", function(env)
    return "info", tostring(env.GetRealmName())
  end)

  suite:add("Faction", function(env)
    return "info", tostring((env.UnitFactionGroup("player")))
  end)

  -- Forever replaces realms with rulesets; nobody knows yet which API names
  -- the ruleset, so report every candidate the client answers.
  suite:add("Ruleset hints", function(env)
    local hints = {}
    for _, path in ipairs({
      "C_GameRules.IsHardcoreActive", "C_GameRules.GetActiveGameMode", "C_Seasons.GetActiveSeason",
      "C_Seasons.HasActiveSeason", "C_Realm.GetCurrentRulesetID", "GetCurrentRegionName",
      -- GetActiveGameMode said 1 on both a PvP and a non-PvP ruleset (#5), so try what else might differ.
      "C_GameRules.GetCurrentGameModeRecordID", "C_GameRules.GetForeverExperiencePreset",
      "C_GameRules.IsSelfFoundAllowed", "C_PvP.IsWarModeFeatureEnabled", "GetRealmID", "GetNativeRealmID",
      "SelectedRealmName",
    }) do
      local ok, value = call(env, path)
      if ok then hints[#hints + 1] = path .. "=" .. tostring(value) end
    end
    return "info", #hints > 0 and table.concat(hints, ", ") or "no ruleset API found"
  end)

  suite:add("Legacy AH API", function(env)
    return "info", describePresence(presence(env, LEGACY_AH))
  end)

  suite:add("C_AuctionHouse API", function(env)
    return "info", describePresence(presence(env.C_AuctionHouse, MODERN_AH))
  end)

  suite:add("Auction house API available", function(env)
    local legacy = #presence(env, { "QueryAuctionItems" }) > 0
    local modern = #presence(env.C_AuctionHouse, { "SendBrowseQuery" }) > 0
    if legacy or modern then
      return "pass", string.format("legacy QueryAuctionItems: %s; C_AuctionHouse.SendBrowseQuery: %s",
        legacy and "yes" or "no", modern and "yes" or "no")
    end
    return "fail", "neither QueryAuctionItems nor C_AuctionHouse.SendBrowseQuery exists"
  end)

  -- Posting durations are indices 1-3 into these labels; Better AH assumes 3 is 24 hours (2/8/24 on Forever).
  suite:add("Auction durations", function(env)
    local labels = {}
    for i, name in ipairs({ "AUCTION_DURATION_ONE", "AUCTION_DURATION_TWO", "AUCTION_DURATION_THREE" }) do
      labels[i] = i .. "=" .. tostring(env[name] or "(missing)")
    end
    return "info", table.concat(labels, ", ")
  end)

  suite:add("Saved variables", function(env, addon)
    if not (addon and addon.db) then return "fail", "BetterAHDB not loaded yet" end
    if env.BetterAHDB ~= addon.db then return "fail", "BetterAHDB global is not the addon's database" end
    local keys = 0
    for _ in pairs(addon.db) do keys = keys + 1 end
    return "pass", keys == 0 and "BetterAHDB fresh (empty)" or ("BetterAHDB loaded (" .. keys .. " keys)")
  end)

  return suite
end

-- One shared suite per namespace, so other files can add checks to it.
function Probes.suite()
  ns.probeSuite = ns.probeSuite or build()
  return ns.probeSuite
end

ns.Probes = Probes
return Probes
