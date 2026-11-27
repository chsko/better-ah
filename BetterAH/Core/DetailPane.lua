local _, ns = ...

-- The right-hand detail pane's width (#236): each view keeps its own, dragged with the divider between
-- the main panel and the pane. The window's width doesn't change, so the main panel's list gets what the
-- pane gives up. Pure: no WoW API.
local DetailPane = {}
ns.DetailPane = DetailPane

DetailPane.DEFAULT, DetailPane.MIN, DetailPane.MAX = 300, 240, 420
-- The main panel's list width at the default pane width (Window's LIST_WIDTH).
DetailPane.LIST_WIDTH = 540
-- The narrowest a stretched column gets, however narrow the list.
DetailPane.MIN_COLUMN = 40

-- The views whose pane can be resized (Christian, #236): every view with a detail pane but Settings, and
-- not Disenchant snipe, whose band graphs are drawn for the default width.
DetailPane.VIEWS = { post = true, auctions = true, browse = true, bids = true, ledger = true, prices = true,
  alts = true }

function DetailPane.resizable(view)
  return DetailPane.VIEWS[view] == true
end

-- A pane width to use: a saved or dragged width rounded and kept in range, else the default.
function DetailPane.width(width)
  width = tonumber(width)
  if not width or width ~= width then return DetailPane.DEFAULT end
  width = math.floor(width + 0.5)
  return math.max(DetailPane.MIN, math.min(DetailPane.MAX, width))
end

-- The main panel's list width beside a pane this wide.
function DetailPane.listWidth(width)
  return DetailPane.LIST_WIDTH + DetailPane.DEFAULT - DetailPane.width(width)
end

-- Columns laid out for the default list width ({ header, x, width, ... }), laid out again for listWidth:
-- column flex (the first when nil) takes the difference and every column right of it moves along. A
-- column's other fields are kept. Returns new tables; the columns given are not changed.
function DetailPane.columns(columns, listWidth, flex)
  flex = flex or 1
  local base = columns[flex]
  local grow = math.max(DetailPane.MIN_COLUMN, base[3] + listWidth - DetailPane.LIST_WIDTH) - base[3]
  local out = {}
  for i, col in ipairs(columns) do
    local copy = {}
    for k, v in pairs(col) do copy[k] = v end
    if i == flex then
      copy[3] = col[3] + grow
    elseif col[2] > base[2] then
      copy[2] = col[2] + grow
    end
    out[i] = copy
  end
  return out
end

-- A view's saved width (the default when none is saved), from BetterAHDB.panes.
function DetailPane.saved(store, view)
  return DetailPane.width(type(store) == "table" and store[view] or nil)
end

-- Saves a view's width; nil forgets it, so the view goes back to the default.
function DetailPane.save(store, view, width)
  if type(store) ~= "table" then return end
  store[view] = width ~= nil and DetailPane.width(width) or nil
end
