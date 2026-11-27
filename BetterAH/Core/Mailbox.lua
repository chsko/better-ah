-- The Mailbox window's inbox model (#149, #154): which kind each mail is, what the Inbox list shows for it,
-- and the totals per kind. Pure: the mail adapter (Game/MailAPI.lua) reads the inbox and passes plain tables in.
--
-- A mail, as the adapter reads it: { index, sender, subject, money, cod, daysLeft, items (attachment count),
-- itemName (of the first attachment), count (of all attachments), hasText (nil: not read), isGM, canReply,
-- invoice ("seller", "buyer", "seller_temp_invoice" or nil) }.
local _, ns = ...
ns = ns or {}

local Mailbox = {}

-- In the order the window lists them.
Mailbox.KINDS = {
  { id = "sold", label = "Sold" },
  { id = "bought", label = "Bought" },
  { id = "outbid", label = "Outbid" },
  { id = "cancelled", label = "Cancelled" },
  { id = "expired", label = "Expired" },
  { id = "other", label = "Other" },
  { id = "letter", label = "Letter" },
  { id = "cod", label = "COD" },
}
local LABEL = {}
for _, k in ipairs(Mailbox.KINDS) do LABEL[k.id] = k.label end

-- Mail with less than this many days left is marked: expired auction mail loses its items.
Mailbox.EXPIRING_DAYS = 3

-- The subjects' format strings (the client's AUCTION_*_MAIL_SUBJECT globals), keyed by what they mean.
Mailbox.SUBJECT_GLOBALS = {
  outbid = "AUCTION_OUTBID_MAIL_SUBJECT",
  cancelled = "AUCTION_REMOVED_MAIL_SUBJECT",
  expired = "AUCTION_EXPIRED_MAIL_SUBJECT",
  sold = "AUCTION_SOLD_MAIL_SUBJECT",
  won = "AUCTION_WON_MAIL_SUBJECT",
}
local SUBJECT_KIND = { outbid = "outbid", cancelled = "cancelled", expired = "expired", sold = "sold", won = "bought" }
local SUBJECT_ORDER = { "outbid", "cancelled", "expired", "sold", "won" }

-- Does subject read as format with its %s filled in? Compared as plain text around the %s, so item names with
-- pattern characters can't break it.
local function fits(subject, format)
  if type(format) ~= "string" then return false end
  local at = format:find("%s", 1, true)
  if not at then return subject == format end
  local before, after = format:sub(1, at - 1), format:sub(at + 2)
  return #subject >= #before + #after and subject:sub(1, #before) == before
    and (after == "" or subject:sub(-#after) == after)
end

-- The mail's kind id. subjects maps outbid/cancelled/expired/sold/won to the client's subject formats.
function Mailbox.kind(mail, subjects)
  if (mail.cod or 0) > 0 then return "cod" end
  if mail.invoice == "seller" or mail.invoice == "seller_temp_invoice" then return "sold" end
  if mail.invoice == "buyer" then return "bought" end
  -- Only mail nobody can reply to (the auction house's) is read by its subject, so a player can't send a
  -- mail that passes for auction mail.
  local subject = mail.subject
  if type(subject) == "string" and subjects and not mail.canReply then
    for _, key in ipairs(SUBJECT_ORDER) do
      if fits(subject, subjects[key]) then return SUBJECT_KIND[key] end
    end
  end
  -- A Game Master's mail is always one to read, like Blizzard's Open All skipping it.
  if mail.hasText or mail.isGM then return "letter" end
  -- Text unknown (the adapter doesn't open unread mail): a mail that holds nothing can only be a letter.
  if mail.hasText == nil and (mail.items or 0) == 0 and (mail.money or 0) == 0 then return "letter" end
  return "other"
end

-- Time left as the list shows it: "29d" from 3 days up, "2d 6h" or "20h" below, "<1h" at the end.
function Mailbox.timeLeft(days)
  days = days or 0
  if days >= Mailbox.EXPIRING_DAYS then return math.floor(days) .. "d" end
  local hours = math.floor(days * 24)
  if hours < 1 then return "<1h" end
  local d, h = math.floor(hours / 24), hours % 24
  if d > 0 then return string.format("%dd %dh", d, h) end
  return h .. "h"
end

function Mailbox.isExpiring(mail)
  return mail.daysLeft ~= nil and mail.daysLeft < Mailbox.EXPIRING_DAYS
end

-- What a row names: the item for auction mail; the sender with the item, item count or subject for the rest.
local AUCTION_KINDS = { sold = true, bought = true, outbid = true, cancelled = true, expired = true }
local function what(mail, kind)
  local items = mail.items or 0
  if AUCTION_KINDS[kind] then
    return mail.itemName or mail.subject or "?"
  end
  local sender = mail.sender or "?"
  if kind == "letter" and mail.subject and mail.subject ~= "" then return sender .. ": " .. mail.subject end
  if items > 1 then return string.format("%s: %d items", sender, items) end
  if items == 1 and mail.itemName then return sender .. ": " .. mail.itemName end
  if mail.subject and mail.subject ~= "" then return sender .. ": " .. mail.subject end
  return sender
end

-- One row per mail, in inbox order: { index, kind, label, what, qty, gold, cod, left, expiring, mail }.
function Mailbox.rows(mails, subjects)
  local rows = {}
  for i, mail in ipairs(mails) do
    local kind = Mailbox.kind(mail, subjects)
    local items = mail.items or 0
    rows[#rows + 1] = {
      index = mail.index or i, kind = kind, label = LABEL[kind], what = what(mail, kind),
      qty = mail.count or (items > 0 and items or nil), gold = mail.money or 0, cod = mail.cod or 0,
      left = Mailbox.timeLeft(mail.daysLeft), expiring = Mailbox.isExpiring(mail), mail = mail,
    }
  end
  return rows
end

-- Per kind { mails, gold, items }, plus mails (all) and expiring (under 3 days left).
function Mailbox.totals(rows)
  local t = { mails = #rows, expiring = 0 }
  for _, k in ipairs(Mailbox.KINDS) do t[k.id] = { mails = 0, gold = 0, items = 0 } end
  for _, row in ipairs(rows) do
    local k = t[row.kind]
    k.mails = k.mails + 1
    k.gold = k.gold + (row.gold or 0)
    k.items = k.items + (row.mail.items or 0)
    if row.expiring then t.expiring = t.expiring + 1 end
  end
  return t
end

-- The subject formats from the client's globals (env is _G in the client).
function Mailbox.subjects(env)
  local s = {}
  for key, name in pairs(Mailbox.SUBJECT_GLOBALS) do s[key] = env[name] end
  return s
end

ns.Mailbox = Mailbox
return Mailbox
