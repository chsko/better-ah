-- The Disenchant view (issue #45): what one green of each item level band is worth disenchanted on this
-- market, after the auction house cut, worked out live from the materials' market values. It replaces
-- the spreadsheet step of disenchant sniping; targets and the sniper (#12) build on the same numbers.
-- The rules live in Core/Disenchant.lua; this file only draws them.
local _, ns = ...
ns = ns or {}

local DisenchantView = {}
DisenchantView.__index = DisenchantView

DisenchantView.COLUMNS = {
  { "Item level", 4, 90 }, { "Required level", 100, 100, "LEFT" }, { "Armor", 205, 105 }, { "Weapon", 315, 105 },
  { "Prices", 425, 110 },
}

-- The view's settings, saved in BetterAHDB.disenchant. The Arcane Salvager is on unless turned off.
function DisenchantView.options(addon)
  local saved = addon and addon.disenchant
  return { salvager = not (saved and saved.salvager == false) }
end

-- "26-30", or "61+" for the open-ended top band (open: that band's item level max).
local function range(min, max, open)
  if (open or max) >= 99 then return min .. "+" end
  return min .. "-" .. max
end
DisenchantView.range = range

-- One row per green band: { band, armor = { value, net, breakdown, missing }, weapon = {...}, priced, mats }.
-- priceOf(materialID) gives a market value or nil. Pure, so the numbers are tested without frames.
function DisenchantView.rows(priceOf, opts)
  local out = {}
  for _, band in ipairs(ns.Disenchant.greenBands()) do
    local row = { band = band }
    local seen, mats, priced = {}, 0, 0
    for _, class in ipairs({ "armor", "weapon" }) do
      local value, breakdown, missing = ns.Disenchant.value({ quality = ns.Disenchant.UNCOMMON, class = class,
        level = band.min }, priceOf, opts)
      row[class] = { value = value, net = ns.Disenchant.net(value), breakdown = breakdown, missing = missing }
      for _, y in ipairs(breakdown or {}) do
        if not seen[y.id] then
          seen[y.id] = true
          mats = mats + 1
          if y.price then priced = priced + 1 end
        end
      end
    end
    row.priced, row.mats = priced, mats
    out[#out + 1] = row
  end
  return out
end

-- A value cell: the value after the cut, marked * when some material had no price, or - with none.
function DisenchantView.cellText(class)
  if not class.net then return "-" end
  return ns.Money.format(class.net) .. ((class.missing or 0) > 0 and " *" or "")
end

-- The detail panel text for a row.
function DisenchantView.detailText(row, opts)
  local lines = { "Armor", ns.Window.disenchantText(row.armor.value, row.armor.breakdown, row.armor.missing), "",
    "Weapons", ns.Window.disenchantText(row.weapon.value, row.weapon.breakdown, row.weapon.missing), "" }
  if opts.salvager then
    lines[#lines + 1] = "Counts the Arcane Salvager's 50% chance of one extra dust or essence."
  else
    lines[#lines + 1] = "Without an Arcane Salvager."
  end
  return table.concat(lines, "\n")
end

function DisenchantView.new(window, addon)
  return setmetatable({ window = window, env = window.env, addon = addon }, DisenchantView)
end

function DisenchantView:build(f, x, y, width, height)
  local env = self.env
  local panel = env.CreateFrame("Frame", nil, f)
  panel:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
  panel:SetSize(width, height)
  self.panel = panel

  local mats = env.CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  mats:SetSize(120, 22)
  mats:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
  mats:SetText("Scan materials")
  mats:SetScript("OnClick", function() self.window:scanMaterials() end)
  ns.Window.tooltip(env, mats, "Scan materials",
    "Look up the 24 disenchant materials only, so these values use fresh prices without a full scan.")
  self.materialsButton = mats

  local salvager = env.CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  salvager:SetSize(24, 24)
  salvager:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -112, 1)
  salvager:SetScript("OnClick", function(b) self:setSalvager(b:GetChecked() and true or false) end)
  ns.Window.tooltip(env, salvager, "Arcane Salvager",
    "Count the Arcane Salvager's 50% chance of one extra dust or essence per disenchant.")
  -- The template's own label, so clicking the words toggles it too; a plain one if the template has none.
  local label = salvager.Text
  if not label then
    label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", salvager, "RIGHT", 2, 0)
  end
  label:SetText("Arcane Salvager")
  if salvager.SetHitRectInsets then salvager:SetHitRectInsets(0, -84, 0, 0) end
  self.salvagerButton, self.salvagerLabel = salvager, label

  local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("LEFT", mats, "RIGHT", 10, 0)
  status:SetPoint("RIGHT", salvager, "LEFT", -8, 0)
  status:SetJustifyH("LEFT")
  if status.SetMaxLines then status:SetMaxLines(2) end -- clear of the column headers below
  self.status = status

  self.rows = self.window:buildRows(panel, DisenchantView.COLUMNS, function(index) self:selectRow(index) end)

  local note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -32 - (#ns.Disenchant.greenBands() + 1) * 18 - 8)
  note:SetWidth(width - 8)
  note:SetJustifyH("LEFT")
  note:SetText("What one green of each band is worth disenchanted, after the 5% auction house cut. "
    .. "Required level is usually 5 below item level. * Some of its materials have no price yet, so the "
    .. "value is too low. Scan materials to price them.")
  self.note = note
  return panel
end

function DisenchantView:setSalvager(on)
  local addon = self.addon
  addon.disenchant = addon.disenchant or {}
  addon.disenchant.salvager = on
  self:render()
end

function DisenchantView:selectRow(index)
  local row = self.list and self.list[index]
  if not row then return end
  self.selected = row.band.min
  self:render()
end

function DisenchantView:render()
  if not self.panel then return end
  local addon, w = self.addon, self.window
  local key = w:market()
  local now = addon.auctionAPI and addon.auctionAPI:now() or 0
  local opts = DisenchantView.options(addon)
  local prices = addon.prices
  local priceOf = function(id)
    return key and prices and (prices:marketValue(key, "i:" .. id, now))
  end
  self.list = DisenchantView.rows(priceOf, opts)
  self.salvagerButton:SetChecked(opts.salvager)

  local scanning = (addon.auctionAPI and addon.auctionAPI.pending) or w.materialScan
  if scanning then self.materialsButton:Disable() else self.materialsButton:Enable() end
  local text
  if w.materialStatus and w.materialMarket == key then
    text = w.materialStatus
  elseif key then
    text = "Prices from " .. ns.MarketKey.describe(key) .. "."
  else
    text = "Open the auction house to see prices."
  end
  self.status:SetText(text)

  local chosen
  for r, cells in ipairs(self.rows) do
    local row = self.list[r]
    if row then
      cells[1]:SetText(range(row.band.min, row.band.max))
      cells[2]:SetText(range(row.band.required.min, row.band.required.max, row.band.max))
      cells[3]:SetText(DisenchantView.cellText(row.armor))
      cells[4]:SetText(DisenchantView.cellText(row.weapon))
      cells[5]:SetText(row.priced == row.mats and "all priced" or string.format("%d of %d priced", row.priced,
        row.mats))
      cells.button:Show()
      if row.band.min == self.selected then chosen = row end
    else
      for _, cell in ipairs(cells) do cell:SetText("") end
      cells.button:Hide()
    end
    cells.button.selectedTexture:SetShown(row ~= nil and row.band.min == self.selected)
  end
  if chosen then
    w.detailTitle:SetText(string.format("Greens of item level %s", range(chosen.band.min, chosen.band.max)))
    w.detailBody:SetText(DisenchantView.detailText(chosen, opts))
  else
    w.detailTitle:SetText("")
    w.detailBody:SetText("Select a band to see what each material adds.")
  end
end

ns.DisenchantView = DisenchantView
return DisenchantView
