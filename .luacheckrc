std = "lua51"
max_line_length = 120
exclude_files = { ".luarocks", "lua_modules" }

-- WoW client globals the addon writes.
globals = { "BetterAHDB", "SLASH_BETTERAH1", "SlashCmdList" }

-- WoW client globals the addon reads. Add to this list as new APIs are used.
read_globals = {
  "CreateFrame", "GetBuildInfo", "UnitName", "C_Container", "GetRealmName", "GetNormalizedRealmName", "UnitGUID", "UnitFactionGroup",
  "GetCurrentRegionName",
  "C_GameRules", "Enum", "C_Seasons", "C_Realm", "GetServerTime", "GetItemInfo", "GetItemInfoInstant", "GetMoney", "ItemLocation", "AUCTION_DURATION_ONE", "AUCTION_DURATION_TWO", "AUCTION_DURATION_THREE",
  "C_AuctionHouse", "C_Timer", "C_Item", "C_Map",
  "QueryAuctionItems", "GetNumAuctionItems", "GetAuctionItemInfo", "GetAuctionItemLink",
  "CanSendAuctionQuery", "PostAuction", "StartAuction", "CancelAuction", "PlaceAuctionBid",
  "ClickAuctionSellItemButton", "GetAuctionSellItemInfo", "CalculateAuctionDeposit", "GetOwnerAuctionItems",
  "DEFAULT_CHAT_FRAME", "UIParent", "UISpecialFrames", "GetCursorPosition", "IsMouseButtonDown", "GameTooltip",
  "AuctionFrame", "AuctionHouseFrame", "CloseAuctionHouse", "hooksecurefunc", "ChatEdit_InsertLink",
  "GetItemQualityColor", "TooltipDataProcessor", "ItemRefTooltip", "GetCoinTextureString", "GetItemCount",
  "IsShiftKeyDown",
}

files["spec/"] = { std = "+busted" }
files["spec/fake_client.lua"] = { self = false } -- stub methods ignore self
