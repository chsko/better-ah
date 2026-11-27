-- A new mail (#158): who can get it, what its subject is when the player gives none, the amount typed, and
-- whether it can be sent. Pure: the mail adapter (Game/MailAPI.lua) reads the attachments and sends.
local _, ns = ...
ns = ns or {}

local MailSend = {}

MailSend.MAX_ATTACH = 12 -- ATTACHMENTS_MAX_SEND in Blizzard's MailFrame.lua
MailSend.MAX_COD = 10000 * 10000 -- MAX_COD_AMOUNT (10,000 gold), in copper

MailSend.NO_RECIPIENT = "Type who gets the mail, or pick one of your characters."
MailSend.NO_SUBJECT = "Type a subject, or add an item to name the mail after."
MailSend.BAD_AMOUNT = "Type the gold as 5g 20s, or a number of gold."
MailSend.COD_NEEDS_ITEM = "A COD mail needs at least one item: the gold is what the items cost."
MailSend.COD_OFF = "COD mail is turned off on this realm."
MailSend.COD_TOO_MUCH = "A COD can be at most 10000g."
MailSend.NOT_ENOUGH = "You don't have enough gold for this mail and its postage."

-- Your other characters on this server and faction, by name, for the To list. characters:
-- CharacterRecords:characters(), keyed "Name-serverID". server: this character's server ID; without it the list
-- is empty, as a bare name on another server would be a stranger's.
function MailSend.recipients(characters, me, faction, server)
  local out, seen = {}, {}
  if not server then return out end
  local suffix = "-" .. tostring(server)
  for _, c in ipairs(characters or {}) do
    local name, key = c.name, tostring(c.key or "")
    local here = key:sub(-#suffix) == suffix
    if here and name and name ~= "" and name ~= me and not seen[name] and (not faction or not c.faction
      or c.faction == faction) then
      seen[name] = true
      out[#out + 1] = name
    end
  end
  return out
end

-- Like Blizzard's: a mail with no subject is named after its first item, "Runecloth (20)" for a stack.
function MailSend.subjectFor(attachments)
  local a = attachments and attachments[1]
  if not (a and a.name) then return nil end
  if (a.count or 1) > 1 then return string.format("%s (%d)", a.name, a.count) end
  return a.name
end

function MailSend.reSubject(subject)
  subject = subject or ""
  if subject:sub(1, 3):lower() == "re:" then return subject end
  return "Re: " .. subject
end

-- The amount as typed: "5g 20s", "20s", or a bare number, read as gold (mail is sent in gold, not copper).
-- 0 for an empty box; nil if it can't be read.
function MailSend.amount(text)
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return 0 end
  if text:match("^%d+$") then
    local gold = tonumber(text)
    if gold * 10000 > ns.Money.MAX then return nil end
    return gold * 10000
  end
  return ns.Money.parse(text)
end

-- draft: { to, subject, body, mode = "money" | "cod", amount (text) }. attachments: what the game holds for the
-- mail. opts: { codEnabled, money (the player's), postage }. Returns the mail to send
-- { to, subject, body, money, cod } or nil and why not.
function MailSend.check(draft, attachments, opts)
  opts = opts or {}
  local to = (draft.to or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if to == "" then return nil, MailSend.NO_RECIPIENT end
  local subject = (draft.subject or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if subject == "" then subject = MailSend.subjectFor(attachments) or "" end
  if subject == "" then return nil, MailSend.NO_SUBJECT end
  local copper = MailSend.amount(draft.amount)
  if not copper then return nil, MailSend.BAD_AMOUNT end
  local mail = { to = to, subject = subject, body = draft.body or "", money = 0, cod = 0 }
  if draft.mode == "cod" and copper > 0 then
    if opts.codEnabled == false then return nil, MailSend.COD_OFF end
    if #(attachments or {}) == 0 then return nil, MailSend.COD_NEEDS_ITEM end
    if copper > MailSend.MAX_COD then return nil, MailSend.COD_TOO_MUCH end
    mail.cod = copper
  else
    mail.money = copper
  end
  if opts.money and mail.money + (opts.postage or 0) > opts.money then return nil, MailSend.NOT_ENOUGH end
  return mail
end

ns.MailSend = MailSend
return MailSend
