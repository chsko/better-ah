-- Send rules (#159): which bag items go to which of your characters when you press Send all. A rule names one
-- item, a disenchant group or an item type, a recipient and how many of each item to keep in the bags. The most
-- specific rule wins: an item, then a disenchant group (one kind before all enchanting mats), then a type.
-- Rules never move gold. Pure: the bag stacks come in from the mail adapter (Game/MailAPI.lua); the run that
-- sends the mails is Game/MailSender.lua.
local _, ns = ...
ns = ns or {}

local SendRules = {}
SendRules.__index = SendRules

SendRules.POSTAGE = 30 -- copper per item attached, as GetSendMailPrice charges it (to check in game)

SendRules.NO_ITEM = "Pick what the rule sends: alt-click an item in your bags, or pick a group or a type."
SendRules.NO_RECIPIENT = "Type who gets the items, or pick one of your characters."
SendRules.TO_SELF = "That is the character you are playing."
SendRules.BAD_KEEP = "Type how many to keep as a whole number, or leave it empty to send them all."
SendRules.DUPLICATE = "There is a rule for that already. Edit that one instead."

-- Disenchant groups, by the kind of material (Disenchant.MATERIALS). "all" is every one of them.
SendRules.GROUPS = {
  { id = "all", label = "Enchanting mats" },
  { id = "dust", label = "Dusts" },
  { id = "essence", label = "Essences" },
  { id = "shard", label = "Shards" },
}
SendRules.GROUP_BY_ID = {}
for _, g in ipairs(SendRules.GROUPS) do SendRules.GROUP_BY_ID[g.id] = g end

-- Item types: trade goods by subclass (Enum.ItemTradeGoodsSubclass), recipes, then uncommon armor and weapons by
-- the disenchant bands' item levels.
SendRules.TYPES = {
  { id = "cloth", label = "Cloth", classID = 7, subclassID = 5 },
  { id = "leather", label = "Leather", classID = 7, subclassID = 6 },
  { id = "metal", label = "Metal and stone", classID = 7, subclassID = 7 },
  { id = "meat", label = "Meat", classID = 7, subclassID = 8 },
  { id = "herb", label = "Herbs", classID = 7, subclassID = 9 },
  { id = "elemental", label = "Elemental", classID = 7, subclassID = 10 },
  { id = "recipe", label = "Recipes", classID = 9 },
}
local function range(min, max)
  if max >= 99 then return min .. "+" end
  return min .. "-" .. max
end
if ns.Disenchant then
  for _, class in ipairs({ { "armor", "Uncommon armor" }, { "weapon", "Uncommon weapons" } }) do
    for _, band in ipairs(ns.Disenchant.greenBands()) do
      SendRules.TYPES[#SendRules.TYPES + 1] = { id = class[1] .. ":" .. band.min, class = class[1],
        min = band.min, max = band.max, label = class[2] .. ", " .. range(band.min, band.max) }
    end
  end
end
SendRules.TYPE_BY_ID = {}
for _, t in ipairs(SendRules.TYPES) do SendRules.TYPE_BY_ID[t.id] = t end

local function trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function typeMatches(t, item)
  if t.class then
    if item.quality ~= 2 or not item.level or item.level < t.min or item.level > t.max then return false end
    local kind = ns.Targets and ns.Targets.typeOf(item)
    local def = kind and ns.Targets.BY_ID[kind]
    return def ~= nil and def.class == t.class
  end
  if item.classID ~= t.classID then return false end
  return t.subclassID == nil or item.subclassID == t.subclassID
end

-- How specific a rule is when it matches item (lower wins), or nil when it doesn't match.
local function rank(rule, item)
  if rule.match == "item" then
    return rule.itemID ~= nil and rule.itemID == item.itemID and 1 or nil
  elseif rule.match == "group" then
    local mat = ns.Disenchant and ns.Disenchant.BY_ID[item.itemID]
    if not mat then return nil end
    if rule.group == "all" then return 3 end
    return rule.group == mat.kind and 2 or nil
  elseif rule.match == "type" then
    local t = SendRules.TYPE_BY_ID[rule.type]
    return t and typeMatches(t, item) and 4 or nil
  end
  return nil
end

function SendRules.matches(rule, item)
  return rank(rule, item) ~= nil
end

-- The rule that sends item, and its index: the most specific, the first listed among equals.
function SendRules.ruleFor(rules, item)
  local best, bestRank, bestIndex
  for i, rule in ipairs(rules or {}) do
    local r = rank(rule, item)
    if r and (not bestRank or r < bestRank) then best, bestRank, bestIndex = rule, r, i end
  end
  return best, bestIndex
end

-- What a rule matches, as one key: two rules with the same key would fight over the same items.
function SendRules.key(rule)
  if rule.match == "item" then return "item:" .. tostring(rule.itemID) end
  if rule.match == "group" then return "group:" .. tostring(rule.group) end
  return "type:" .. tostring(rule.type)
end

function SendRules.label(rule)
  if rule.match == "item" then return rule.name or ("item " .. tostring(rule.itemID)) end
  if rule.match == "group" then
    local g = SendRules.GROUP_BY_ID[rule.group]
    return g and g.label or "?"
  end
  local t = SendRules.TYPE_BY_ID[rule.type]
  return t and t.label or "?"
end

local KIND_LABELS = { item = "item", group = "DE group", type = "type" }
function SendRules.kindLabel(rule)
  return KIND_LABELS[rule.match] or "?"
end

local function sameName(a, b)
  return a and b and trim(a):lower() == trim(b):lower()
end

-- A rule as typed in the editor, cleaned up: { match, itemID and name | group | type, to, keep }, or nil and why.
-- rules: the saved list, so a rule can't match what another one already does. opts: { me, editing (index) }.
function SendRules.check(rule, rules, opts)
  opts = opts or {}
  local out = { match = rule.match }
  if rule.match == "item" and rule.itemID then
    out.itemID, out.name = rule.itemID, rule.name
  elseif rule.match == "group" and SendRules.GROUP_BY_ID[rule.group] then
    out.group = rule.group
  elseif rule.match == "type" and SendRules.TYPE_BY_ID[rule.type] then
    out.type = rule.type
  else
    return nil, SendRules.NO_ITEM
  end
  out.to = trim(rule.to)
  if out.to == "" then return nil, SendRules.NO_RECIPIENT end
  if sameName(out.to, opts.me) then return nil, SendRules.TO_SELF end
  local keep = trim(rule.keep)
  if keep == "" then
    out.keep = nil
  elseif keep:match("^%d+$") then
    out.keep = tonumber(keep)
    if out.keep == 0 then out.keep = nil end
  else
    return nil, SendRules.BAD_KEEP
  end
  local key = SendRules.key(out)
  for i, other in ipairs(rules or {}) do
    if i ~= opts.editing and SendRules.key(other) == key then return nil, SendRules.DUPLICATE end
  end
  return out
end

-- The saved rules (BetterAHDB.mail.rules), with add, edit and delete. add and update return true, or nil and why.
function SendRules.new(saved)
  return setmetatable({ rules = saved or {} }, SendRules)
end

function SendRules:list()
  return self.rules
end

function SendRules:add(rule, opts)
  local r, why = SendRules.check(rule, self.rules, opts)
  if not r then return nil, why end
  self.rules[#self.rules + 1] = r
  return true
end

function SendRules:update(index, rule, opts)
  if not self.rules[index] then return nil, SendRules.NO_ITEM end
  local o = {}
  for k, v in pairs(opts or {}) do o[k] = v end
  o.editing = index
  local r, why = SendRules.check(rule, self.rules, o)
  if not r then return nil, why end
  self.rules[index] = r
  return true
end

function SendRules:remove(index)
  table.remove(self.rules, index)
end

-- What Send all would send now. rules: the saved list. bags: { bag, slot, itemID, count, name, classID, subclassID,
-- quality, level, equip } per stack, soulbound and locked stacks left out. opts: { me }.
-- Returns { mails = { { to, items = { stack + to }, money = 0, cod = 0 } }, byRule = { index -> { have, sends } },
-- items (count sent), attachments, recipients, postage }. Whole stacks only: a rule keeping 20 of an item sends
-- the biggest stacks that leave at least 20 behind.
function SendRules.plan(rules, bags, opts)
  opts = opts or {}
  rules = rules or {}
  local byItem, order = {}, {}
  for _, s in ipairs(bags or {}) do
    if s.itemID then
      local entry = byItem[s.itemID]
      if not entry then
        entry = { itemID = s.itemID, stacks = {}, have = 0, item = s }
        byItem[s.itemID] = entry
        order[#order + 1] = entry
      end
      entry.stacks[#entry.stacks + 1] = s
      entry.have = entry.have + (s.count or 1)
    end
  end
  local p = { mails = {}, byRule = {}, items = 0, attachments = 0, recipients = 0, postage = 0 }
  for i, rule in ipairs(rules) do p.byRule[i] = { have = 0, sends = 0, toMe = sameName(rule.to, opts.me) or nil } end
  local perTo, toOrder = {}, {}
  for _, entry in ipairs(order) do
    local rule, index = SendRules.ruleFor(rules, entry.item)
    if rule then
      local r = p.byRule[index]
      r.have = r.have + entry.have
      local to = trim(rule.to)
      if to ~= "" and not sameName(to, opts.me) then
        local budget = entry.have - (tonumber(rule.keep) or 0)
        local stacks = {}
        for _, s in ipairs(entry.stacks) do stacks[#stacks + 1] = s end
        table.sort(stacks, function(a, b)
          if (a.count or 1) ~= (b.count or 1) then return (a.count or 1) > (b.count or 1) end
          if a.bag ~= b.bag then return a.bag < b.bag end
          return a.slot < b.slot
        end)
        for _, s in ipairs(stacks) do
          local n = s.count or 1
          if n <= budget then
            budget = budget - n
            r.sends = r.sends + n
            p.items = p.items + n
            local list = perTo[to:lower()]
            if not list then
              list = { to = to, items = {}, rank = index }
              perTo[to:lower()] = list
              toOrder[#toOrder + 1] = list
            end
            if index < list.rank then list.rank = index end
            local item = {}
            for k, v in pairs(s) do item[k] = v end
            item.to = list.to
            list.items[#list.items + 1] = item
          end
        end
      end
    end
  end
  -- Recipients in the order their first rule is listed.
  table.sort(toOrder, function(a, b) return a.rank < b.rank end)
  local max = ns.MailSend and ns.MailSend.MAX_ATTACH or 12
  for _, list in ipairs(toOrder) do
    p.recipients = p.recipients + 1
    local mail
    for _, item in ipairs(list.items) do
      if not mail or #mail.items >= max then
        mail = { to = list.to, items = {}, money = 0, cod = 0 }
        p.mails[#p.mails + 1] = mail
      end
      mail.items[#mail.items + 1] = item
      p.attachments = p.attachments + 1
    end
  end
  p.postage = p.attachments * SendRules.POSTAGE
  return p
end

-- The Sends column: how many go, "to you" on the rule's own recipient, "keeps all" when the bags hold no more
-- than the keep, empty when none match.
function SendRules.sendsText(r)
  if r and r.toMe then return "to you" end
  if not r or r.have == 0 then return "" end
  if r.sends == 0 then return "keeps all" end
  return tostring(r.sends)
end

local function plural(n, one, many)
  return n == 1 and ("1 " .. one) or (n .. " " .. many)
end

-- "121 items in 11 mails to 2 characters · postage 3s 30c".
function SendRules.footer(p)
  if not p or #p.mails == 0 then return "Nothing to send." end
  return string.format("%s in %s to %s  ·  postage %s", plural(p.items, "item", "items"),
    plural(#p.mails, "mail", "mails"), plural(p.recipients, "character", "characters"), ns.Money.format(p.postage))
end

-- The line after a Send all. run: { mails (sent), items (sent), planned, to = { { name, mails } }, stopped (why) }.
-- "Sent 46 items in 3 mails: 2 to Mailbank, 1 to Dustwick."
function SendRules.report(run)
  local tail = run.stopped and (" Stopped: " .. run.stopped) or ""
  if (run.mails or 0) == 0 then return "Nothing sent." .. tail end
  local mails = run.mails == run.planned and plural(run.mails, "mail", "mails")
    or string.format("%d of %d mails", run.mails, run.planned or run.mails)
  local parts = {}
  for _, t in ipairs(run.to or {}) do parts[#parts + 1] = t.mails .. " to " .. t.name end
  local s = string.format("Sent %s in %s", plural(run.items or 0, "item", "items"), mails)
  if #parts > 0 then s = s .. ": " .. table.concat(parts, ", ") end
  return s .. "." .. tail
end

ns.SendRules = SendRules
return SendRules
