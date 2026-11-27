-- A Collect run (#156): takes the ticked mail one action at a time, like Blizzard's Open All. The first take runs
-- inside the Collect click; each later one waits DELAY seconds and until the game has no mail command pending.
-- Which take comes next is Core/MailCollect.lua. Takes go through the mail adapter's plain Take calls, which the
-- Ledger hooks, so collected sales reach the Ledger.
--
-- Needs the client to check: a real run, also with full bags; MAIL_FAILED for an item that can't be taken.
local _, ns = ...
ns = ns or {}

local MailCollector = {}
MailCollector.__index = MailCollector

MailCollector.DELAY = 0.15 -- OPEN_ALL_MAIL_MIN_DELAY in Blizzard's MailFrame.lua
MailCollector.STUCK = 5 -- takes in a row that change nothing and get no answer before the run gives up
MailCollector.REFUSED = 3 -- refused items in a row that count as full bags
MailCollector.SETTLE_TRIES = 10 -- waits for the last take's answer after Stop
MailCollector.TICK = 1 -- seconds between looks at the refresh countdown (#157)
MailCollector.REFRESH_WAIT = 15 -- seconds to wait for the inbox after asking for a refresh
MailCollector.COUNTDOWN_MAX = 90 -- seconds of countdown before asking for the refresh anyway
MailCollector.SHOWN = 50 -- the most mails the game shows at once

-- hooks: onStep(run) after each take, onDone(run) once it ends. run: { running, money, kinds, done, bagsFull,
-- itemsLeft (attachments still in mail Collect takes), waiting (seconds until the next refresh, while waiting
-- for one), more (mails the game hasn't sent yet), reason ("done", "stopped", "closed", "cancelled", "stuck",
-- "blocked": the mails shown hold nothing to take, so no refresh brings in the rest; "norefresh": the game
-- didn't send the next mails), summary }.
function MailCollector.new(env, api, hooks)
  return setmetatable({ env = env, api = api, hooks = hooks or {} }, MailCollector)
end

function MailCollector:running()
  return self.run ~= nil and self.run.running
end

function MailCollector:rows()
  local Mailbox = ns.Mailbox
  return Mailbox.rows(self.api:readInbox(), self.api.subjects)
end

-- ticks: the player's Collect ticks (kind id -> true/false).
function MailCollector:start(ticks)
  if self:running() then return end
  self.ticks = ticks or {}
  self.run = { running = true, money = 0, kinds = {}, done = 0, failed = {}, skipMoney = {}, stuck = 0,
    refused = 0, batchGone = 0 }
  -- Mail waiting beyond what is shown, with room for it: worth one refresh even before anything is taken.
  if self.api:moreWaiting() > 0 and (self.api.shown or 0) < MailCollector.SHOWN then self.run.batchGone = 1 end
  self.api:setOpeningAll(true)
  self:step()
end

-- Ends the run. A take the game is still answering is settled first, so the summary counts it; a closed
-- mailbox reads as empty, which would count it as taken, so then it is left out.
function MailCollector:stop(reason)
  local run = self.run
  if not (run and run.running) then return end
  run.running = false
  run.reason = reason or "stopped"
  self.api:setOpeningAll(false)
  if reason ~= "closed" and run.last and self.api:commandPending() and self.env.C_Timer then
    return self:finishLater(MailCollector.SETTLE_TRIES)
  end
  self:finish()
end

function MailCollector:finishLater(tries)
  local run = self.run
  self.env.C_Timer.After(MailCollector.DELAY, function()
    if self.run ~= run then return end
    if tries > 1 and self.api.open and self.api:commandPending() then return self:finishLater(tries - 1) end
    self:finish()
  end)
end

function MailCollector:finish()
  local run = self.run
  local ok, rows = false, nil
  if run.reason ~= "closed" and self.api.open then ok, rows = pcall(self.rows, self) end
  if ok then
    self:settle(rows)
    run.itemsLeft = ns.MailCollect.itemsLeft(rows, self.ticks)
  end
  run.summary = ns.MailCollect.summary(run)
  if self.hooks.onDone then self.hooks.onDone(run) end
end

-- MAIL_FAILED(itemID): the game refused that item (bags full, or a unique item already carried). It is skipped
-- for the rest of the run; a few refusals in a row read as full bags, so gold keeps coming.
function MailCollector:failed(itemID)
  local run = self.run
  if not (run and run.running) then return end
  if itemID then run.failed[itemID] = true end
  run.answered = true
  run.refused = run.refused + 1
end

function MailCollector:later()
  local timer = self.env.C_Timer
  if not timer then return self:stop("stuck") end
  local run = self.run
  timer.After(MailCollector.DELAY, function()
    if self.run == run then self:step() end
  end)
end

-- The inbox holds more than the game shows (#157): wait until it allows a refresh, ask for one, and carry on
-- once the next mails are in. The countdown is in run.waiting.
function MailCollector:waitForRefresh()
  local run, timer = self.run, self.env.C_Timer
  if not (run and run.running) then return end
  if not self.api.open then return self:stop("closed") end
  local can, seconds = self.api:canRefresh()
  run.counted = (run.counted or 0) + 1
  -- A countdown that never ends (an odd answer from the game) gets its refresh after COUNTDOWN_MAX anyway.
  if can or run.counted > MailCollector.COUNTDOWN_MAX then
    run.waiting, run.batchGone, run.counted = nil, 0, nil
    run.awaitInbox, run.refreshTimedOut = true, nil
    run.before = { shown = self.api.shown, total = self.api.total }
    if timer then
      local asked = run.before
      timer.After(MailCollector.REFRESH_WAIT, function()
        if run.before == asked then run.refreshTimedOut = true end
      end)
    end
    self.api:checkInbox()
    if self.hooks.onStep then self.hooks.onStep(run) end
    return self:later()
  end
  run.waiting = math.max(1, math.ceil(seconds))
  if self.hooks.onStep then self.hooks.onStep(run) end
  if not timer then return self:stop("stuck") end
  timer.After(MailCollector.TICK, function()
    if self.run == run then self:waitForRefresh() end
  end)
end

-- MAIL_INBOX_UPDATE (the adapter has read the inbox again): after a refresh, the next mails are in once what
-- the game shows has changed. An update from a late take changes nothing, so the wait goes on.
function MailCollector:inboxUpdated()
  local run = self.run
  if not (run and run.awaitInbox and run.before) then return end
  if self.api.shown ~= run.before.shown or self.api.total ~= run.before.total then
    run.awaitInbox, run.before = nil, nil
  end
end

local function sameMail(row, last)
  return row and row.mail.sender == last.sender and row.mail.subject == last.subject
end

local function unchanged(row, last)
  return sameMail(row, last) and (row.mail.money or 0) == last.money and (row.mail.items or 0) == last.items
end

-- After a take: where is that mail now, and did the take change it? A mail that went from the inbox (the game
-- removes auction mail once it is empty) or holds nothing more Collect takes counts as collected, under its kind.
-- When the inbox got shorter, the mail is looked for at its place and one up (a mail before it went).
function MailCollector:settle(rows)
  local run, last = self.run, self.run.last
  if not last then return end
  run.last = nil
  local now, gone = rows[last.index], false
  if #rows < last.count then
    if unchanged(rows[last.index - 1], last) then now = rows[last.index - 1]
    elseif not unchanged(now, last) then gone, now = true, nil end
  end
  local changed = gone or not unchanged(now, last)
  if changed then run.refused = 0 end
  run.stuck = (changed or run.answered) and 0 or run.stuck + 1
  run.answered = nil
  if last.take == "money" then
    if gone or (now and (now.mail.money or 0) < last.money) then
      run.money = run.money + last.money
    elseif not changed then
      -- The game kept the gold (at the gold cap, say): leave it and go on with the rest.
      run.skipMoney[ns.MailCollect.moneyKey(now and now.mail or last)] = true
    end
  end
  if gone then run.batchGone = run.batchGone + 1 end
  if gone or (now and changed and not ns.MailCollect.collects(now, self.ticks)) then
    run.kinds[last.kind] = (run.kinds[last.kind] or 0) + 1
    run.done = run.done + 1
  end
end

function MailCollector:step()
  local run = self.run
  if not (run and run.running) then return end
  if not self.api.open then return self:stop("closed") end
  if self.api:commandPending() then return self:later() end
  if run.awaitInbox then
    -- Asked for a refresh: the next mails come with MAIL_INBOX_UPDATE (inboxUpdated).
    if not run.refreshTimedOut then return self:later() end
    run.awaitInbox = nil
    -- The game didn't send the next mails: the mails shown may be all it will send now.
    return self:stop("norefresh")
  end
  local rows = self:rows()
  self:settle(rows)
  if run.stuck >= MailCollector.STUCK then return self:stop("stuck") end
  local free = self.api:freeSlots()
  if run.refused >= MailCollector.REFUSED then run.refusedFull = true end -- for the rest of the run
  run.bagsFull = (free ~= nil and free <= 0) or run.refusedFull or false
  local t = ns.MailCollect.nextTake(rows, self.ticks, run)
  if not t then -- the last take was settled above
    run.more = self.api:moreWaiting()
    if run.more == 0 then return self:stop("done") end
    -- The rest only comes in as room is made: with no mail gone from this batch, no refresh helps. With full
    -- bags that is what the end line says (items stay in the mail); else the mails shown are all to keep.
    if run.batchGone == 0 then return self:stop(run.bagsFull and "done" or "blocked") end
    return self:waitForRefresh()
  end
  local m = t.row.mail
  run.last = { index = t.row.index, kind = t.row.kind, count = #rows, money = m.money or 0, items = m.items or 0,
    take = t.take, sender = m.sender, subject = m.subject }
  if t.take == "money" then
    self.api:takeMoney(t.row.index)
  else
    self.api:takeSlot(t.row.index, t.slot)
  end
  if self.hooks.onStep then self.hooks.onStep(run) end
  self:later()
end

-- The Mailbox window (UI/MailboxWindow.lua) makes its collector with its own hooks; this only makes one for the
-- mail adapter, like the other Game/ adapters.
function MailCollector.install(env, addon)
  local api = addon.mailAPI or ns.MailAPI.install(env, addon)
  local c = MailCollector.new(env, api)
  addon.mailCollector = c
  return c
end

ns.MailCollector = MailCollector
return MailCollector
