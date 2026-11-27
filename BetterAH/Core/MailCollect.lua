-- Collect (#156): which mail the Mailbox window's Collect takes, in what order, and the line that sums a run up.
-- Pure: works on the rows Core/Mailbox.lua makes from what the mail adapter read. The run itself (one take at a
-- time, paced) is Game/MailCollector.lua.
local _, ns = ...
ns = ns or {}

local MailCollect = {}

-- Ticked unless the player unticks them: every auction kind and other player mail. Letters are read first,
-- so they start unticked. COD is never collected: paying needs the player's own yes.
MailCollect.DEFAULTS = {
  sold = true, bought = true, outbid = true, cancelled = true, expired = true, other = true, letter = false,
}

-- ticks: the player's saved choices (kind id -> true/false), nil entries take the default.
function MailCollect.ticked(ticks, kind)
  if kind == "cod" then return false end
  local t = ticks and ticks[kind]
  if t == nil then return MailCollect.DEFAULTS[kind] or false end
  return t and true or false
end

-- Does Collect take this row's mail at all? Not a Game Master's mail (Blizzard's Open All skips it too).
function MailCollect.collects(row, ticks)
  local m = row.mail
  return MailCollect.ticked(ticks, row.kind) and not m.isGM and ((m.money or 0) > 0 or (m.items or 0) > 0)
end

-- What Collect would take now: { mails, gold, items }.
function MailCollect.preview(rows, ticks)
  local p = { mails = 0, gold = 0, items = 0 }
  for _, row in ipairs(rows) do
    if MailCollect.collects(row, ticks) then
      p.mails = p.mails + 1
      p.gold = p.gold + (row.mail.money or 0)
      p.items = p.items + (row.mail.items or 0)
    end
  end
  return p
end

-- The next single take, or nil once nothing is left to take: { take = "money" | "item", row, slot }.
-- Each mail's money before its items; items from the last slot down, like Blizzard's Open All. state:
-- { bagsFull (no item takes, money still), failed (itemID -> true, after MAIL_FAILED), skipMoney
-- (moneyKey -> true: gold the game kept) }.
function MailCollect.nextTake(rows, ticks, state)
  state = state or {}
  local failed = state.failed or {}
  for _, row in ipairs(rows) do
    if MailCollect.collects(row, ticks) then
      local m = row.mail
      if (m.money or 0) > 0 and not (state.skipMoney and state.skipMoney[MailCollect.moneyKey(m)]) then
        return { take = "money", row = row }
      end
      if not state.bagsFull then
        local slots = m.slots or {}
        for i = #slots, 1, -1 do
          local s = slots[i]
          if not (s.itemID and failed[s.itemID]) then return { take = "item", row = row, slot = s.slot } end
        end
      end
    end
  end
  return nil
end

-- Names gold the game kept, so the run doesn't ask for it again as the mail moves up the inbox.
function MailCollect.moneyKey(mail)
  return string.format("%s|%s|%d", tostring(mail.sender), tostring(mail.subject), mail.money or 0)
end

-- Attachments still in mail Collect takes: what full bags left behind.
function MailCollect.itemsLeft(rows, ticks)
  local n = 0
  for _, row in ipairs(rows) do
    if MailCollect.collects(row, ticks) then n = n + (row.mail.items or 0) end
  end
  return n
end

local PHRASES = {
  { "sold", "%d sold" }, { "bought", "%d bought" }, { "outbid", "%d outbid back" },
  { "cancelled", "%d cancelled back" }, { "expired", "%d expired back" },
  { "other", "%d other mail", "%d other mails" }, { "letter", "%d letter", "%d letters" },
}

-- "Collected 31g 4s: 12 sold, 4 expired back, 2 bought." run: { money, kinds = { kind id -> mails } }.
function MailCollect.summary(run)
  local parts, total = {}, 0
  for _, p in ipairs(PHRASES) do
    local n = run.kinds and run.kinds[p[1]] or 0
    if n > 0 then
      total = total + n
      parts[#parts + 1] = string.format((n > 1 and p[3]) or p[2], n)
    end
  end
  local money = run.money or 0
  if total == 0 and money == 0 then return "Nothing collected." end
  local head = money > 0 and ns.Money.short(money) or (total == 1 and "1 mail" or (total .. " mails"))
  if #parts == 0 then return "Collected " .. head .. "." end
  return "Collected " .. head .. ": " .. table.concat(parts, ", ") .. "."
end

ns.MailCollect = MailCollect
return MailCollect
