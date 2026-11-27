-- Send all (#159): sends what the send rules (Core/SendRules.lua) pick from the bags, one mail at a time. The
-- Send all click attaches the first mail's items; every SendMail, the first included, runs from a timer
-- ATTACH_WAIT later. Each next mail waits for the game's MAIL_SEND_SUCCESS, then NEXT_WAIT seconds, and is
-- worked out again from the bags as they are then (stacks on a mail read as locked and are left out).
-- MAIL_FAILED, no answer, or an item the game won't attach ends the run.
-- Mail goes through the mail adapter (Game/MailAPI.lua).
--
-- Needs the client to check: a real Send all to an alt, also with more than 12 stacks; that SendMail outside a
-- click is allowed (Blizzard's SendMail is not restricted); the postage per item; a recipient whose mailbox is
-- full.
local _, ns = ...
ns = ns or {}

local MailSender = {}
MailSender.__index = MailSender

MailSender.ATTACH_WAIT = 0.3 -- seconds between attaching a mail's items and sending it
MailSender.NEXT_WAIT = 0.5 -- seconds after a mail went before the next one
MailSender.TIMEOUT = 30 -- seconds without an answer before the run gives up

MailSender.NOT_ATTACHED = "the game wouldn't attach %s."
MailSender.NOTHING_ATTACHED = "the game attached nothing to the mail."
MailSender.NO_POSTAGE = "not enough gold for the postage."
MailSender.REFUSED = "the game refused the mail to %s."
MailSender.NO_ANSWER = "no answer from the game. Its items are still on the new mail: send or take them off " ..
  "there."
MailSender.CLOSED = "the mailbox closed."
MailSender.STOPPED = "you pressed Stop."

-- hooks: onStep(run) as it goes, onDone(run) once it ends. run: { running, planned (mails), mails and items
-- (sent so far), to = { { name, mails } }, stopped (why it ended early), summary }.
function MailSender.new(env, api, hooks)
  return setmetatable({ env = env, api = api, hooks = hooks or {} }, MailSender)
end

function MailSender:running()
  return self.run ~= nil and self.run.running
end

-- Waiting for the game's answer to a mail it was handed.
function MailSender:waiting()
  return self:running() and self.run.waiting ~= nil
end

local function call(self, hook)
  local fn = self.hooks[hook]
  if fn then fn(self.run) end
end

function MailSender:plan()
  return ns.SendRules.plan(self.rules, self.api:bagStacks(), self.opts)
end

-- rules: the saved send rules. opts: { me }. Returns the run, or nil when there is nothing to send.
function MailSender:start(rules, opts)
  if self:running() then return nil end
  -- A copy: a rule changed while the run goes doesn't change where its mails go.
  self.rules, self.opts = {}, opts or {}
  for i, r in ipairs(rules or {}) do
    local copy = {}
    for k, v in pairs(r) do copy[k] = v end
    self.rules[i] = copy
  end
  local plan = self:plan()
  if #plan.mails == 0 then return nil end
  self.run = { running = true, planned = #plan.mails, mails = 0, items = 0, to = {}, toIndex = {} }
  self:mail(plan.mails[1])
  return self.run
end

-- Attach one planned mail's stacks, then send it after ATTACH_WAIT.
function MailSender:mail(planned)
  local run, api = self.run, self.api
  run.current = planned
  for _, item in ipairs(planned.items) do
    if not api:attachFromBag(item.bag, item.slot) then
      api:clearSend()
      return self:finish(string.format(MailSender.NOT_ATTACHED, item.name or "an item"))
    end
  end
  call(self, "onStep")
  local timer = self.env.C_Timer
  if timer then
    timer.After(MailSender.ATTACH_WAIT, function()
      if self.run == run and run.running then self:send() end
    end)
  else
    self:send()
  end
end

function MailSender:send()
  local run, api = self.run, self.api
  if run.stopping then
    api:clearSend()
    return self:finish(MailSender.STOPPED)
  end
  local attached = api:sendItems()
  if #attached == 0 then return self:finish(MailSender.NOTHING_ATTACHED) end
  local have = api:playerMoney()
  if have and api:postage() > have then
    api:clearSend()
    return self:finish(MailSender.NO_POSTAGE)
  end
  local sent = 0
  for _, a in ipairs(attached) do sent = sent + (a.count or 1) end
  local waiting = { to = run.current.to, items = sent }
  run.waiting, run.lastError = waiting, nil
  self.api:releaseSendFocus()
  local timer = self.env.C_Timer
  if timer then
    timer.After(MailSender.TIMEOUT, function()
      if self.run == run and run.waiting == waiting then
        run.waiting = nil
        self:finish(MailSender.NO_ANSWER)
      end
    end)
  end
  api:send({ to = run.current.to, subject = ns.MailSend.subjectFor(attached) or "Items", body = "", money = 0,
    cod = 0 })
end

-- MAIL_SEND_SUCCESS: true when it answered this run's mail.
function MailSender:sent()
  local run = self.run
  if not (self:running() and run.waiting) then return false end
  local w = run.waiting
  run.waiting = nil
  self.api:releaseSendFocus()
  run.mails = run.mails + 1
  run.items = run.items + w.items
  local key = w.to:lower()
  local t = run.toIndex[key]
  if not t then
    t = { name = w.to, mails = 0 }
    run.toIndex[key] = t
    run.to[#run.to + 1] = t
  end
  t.mails = t.mails + 1
  if run.stopping then
    self:finish(MailSender.STOPPED)
    return true
  end
  -- Never more mails than the run set out with, whatever the bags read as by now.
  if run.mails >= run.planned then
    self:finish()
    return true
  end
  call(self, "onStep")
  local timer = self.env.C_Timer
  local function nextMail()
    if self.run ~= run or not run.running then return end
    if run.stopping then return self:finish(MailSender.STOPPED) end
    local plan = self:plan()
    if #plan.mails == 0 then
      run.planned = run.mails -- the bags hold less than first read: all of it went
      return self:finish()
    end
    self:mail(plan.mails[1])
  end
  if timer then timer.After(MailSender.NEXT_WAIT, nextMail) else nextMail() end
  return true
end

function MailSender:onError(message)
  if self:waiting() and type(message) == "string" then self.run.lastError = message end
end

-- MAIL_FAILED: true when it was this run's mail that failed. Its items go back to the bags.
function MailSender:failed()
  local run = self.run
  if not (self:running() and run.waiting) then return false end
  local to = run.waiting.to
  run.waiting = nil
  self.api:clearSend()
  self:finish(run.lastError and (run.lastError:gsub("%.$", "") .. ".") or string.format(MailSender.REFUSED, to))
  return true
end

-- Stop: a mail already handed to the game gets its answer first, so the report counts it.
function MailSender:stop()
  if not self:running() then return end
  if self.run.waiting then
    self.run.stopping = true
    call(self, "onStep")
    return
  end
  self.run.stopping = true
end

-- The mailbox closed: whatever was attached is the game's to put back.
function MailSender:closed()
  if not self:running() then return end
  self.run.waiting = nil
  self:finish(MailSender.CLOSED)
end

function MailSender:finish(stopped)
  local run = self.run
  if not (run and run.running) then return end
  run.running = false
  run.stopped = stopped
  run.current = nil
  run.summary = ns.SendRules.report(run)
  call(self, "onDone")
end

function MailSender.install(env, addon)
  local s = MailSender.new(env, addon.mailAPI or ns.MailAPI.install(env, addon))
  addon.mailSender = s
  return s
end

ns.MailSender = MailSender
return MailSender
