std = "lua51"
max_line_length = 120
exclude_files = { ".luarocks", "lua_modules" }

-- WoW client globals the addon writes.
globals = { "BetterAHDB", "SLASH_BETTERAH1", "SlashCmdList" }

-- WoW client globals the addon reads. Add to this list as new APIs are used.
read_globals = {
  "CreateFrame", "GetBuildInfo", "UnitName", "C_Container", "GetRealmName", "GetNormalizedRealmName", "UnitGUID", "UnitFactionGroup",
  "GetCurrentRegionName",
  "C_GameRules", "C_Seasons", "C_Realm", "GetServerTime", "GetItemInfo", "GetMoney",
  "C_AuctionHouse", "C_Timer", "C_Item", "C_Map",
  "QueryAuctionItems", "GetNumAuctionItems", "GetAuctionItemInfo", "GetAuctionItemLink",
  "CanSendAuctionQuery", "PostAuction", "StartAuction", "CancelAuction", "PlaceAuctionBid",
  "ClickAuctionSellItemButton", "GetAuctionSellItemInfo", "CalculateAuctionDeposit", "GetOwnerAuctionItems",
  "DEFAULT_CHAT_FRAME", "UIParent", "UISpecialFrames",
  "AuctionFrame", "AuctionHouseFrame", "CloseAuctionHouse",
}

files["spec/"] = { std = "+busted" }
files["spec/fake_client.lua"] = { self = false } -- stub methods ignore self
