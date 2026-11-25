std = "lua51"
max_line_length = 120
exclude_files = { ".luarocks", "lua_modules" }

-- WoW client globals the addon writes.
globals = { "BetterAHDB", "SLASH_BETTERAH1", "SlashCmdList" }

-- WoW client globals the addon reads. Add to this list as new APIs are used.
read_globals = {
  "CreateFrame", "GetBuildInfo", "GetServerTime", "GetItemInfo", "GetMoney",
  "C_AuctionHouse", "C_Timer", "C_Item",
  "QueryAuctionItems", "GetNumAuctionItems", "GetAuctionItemInfo", "GetAuctionItemLink",
  "CanSendAuctionQuery", "PostAuction", "CancelAuction", "PlaceAuctionBid",
  "DEFAULT_CHAT_FRAME", "UIParent",
}

files["spec/"] = { std = "+busted" }
