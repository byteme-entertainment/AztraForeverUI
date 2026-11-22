-- Auction house helpers (AuctionFrame.lua lays the window out; this file is what the lists show and what the extra buttons do). The result rows are drawn by us from the client's own
-- list API (GetAuctionItemInfo / GetAuctionItemTimeLeft, read after each of the client's own list updates: nothing here ever sends a query): name in its quality colour, level, time left
-- coloured, seller, bid and buyout (per unit when asked), own auctions marked. Extras: price per unit, hide / highlight own auctions in the results, the last 10 searches, Undercut on the
-- sell page (1 copper under the cheapest buyout of the last results), remembered duration and stack size, the value of your active auctions, the deposit warning.
-- Searching stays the client's own call, made only from a click or the Enter key, and only when CanSendAuctionQuery() allows it (the history list asks for it too). No function of the client
-- is replaced: hooksecurefunc / HookScript only.
AFUI = AFUI or {}
local A = {}
AFUI.AuctionTools = A

A.HISTORY_MAX = 10
A.SETTINGS = { -- key, label, tooltip, default
  { "ahPerUnit", "Prices per unit", "Bid and buyout columns show the price of one item (with the stack's total under it) instead of the stack's price.", true },
  { "ahHighlightOwn", "Mark my auctions", "Your own auctions in the results get a green tint and (mine) after the name.", true },
  { "ahHideOwn", "Fade my auctions", "Your own auctions in the results are faded so the other sellers stand out.", false },
  { "ahHistory", "Search history", "A small arrow next to the name box lists your last 10 searches; picking one searches again (when the client allows a new search).", true },
  { "ahUndercut", "Undercut button", "On the sell page, sets the buyout 1 copper under the cheapest buyout of that item in your last search. Search for the item first.", true },
  { "ahRemember", "Remember duration and stack size", "The sell page opens with the duration and stack size you used last (this session).", true },
  { "ahSummary", "Value of my auctions", "The Auctions page shows how many auctions you have and what they come to at their buyouts.", true },
}
local DEFAULT = {}
for _, s in ipairs(A.SETTINGS) do DEFAULT[s[1]] = s[4] end
function A.On(key)
  local v = AFUI.GetSetting and AFUI.GetSetting(key, DEFAULT[key])
  if v == nil then return DEFAULT[key] end
  return v and true or false
end

---------------------------------------------------------------- pure helpers
function A.Coin(copper)
  copper = math.floor(tonumber(copper) or 0)
  if copper <= 0 then return "0|cffeda55fc|r" end
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "|cffffd700g|r" end
  if s > 0 then out[#out + 1] = s .. "|cffc7c7cfs|r" end
  if c > 0 then out[#out + 1] = c .. "|cffeda55fc|r" end
  return table.concat(out, " ")
end

-- Price of one item of a stack (rounded down; at least 1 copper for a price above 0).
function A.UnitPrice(total, count)
  total, count = tonumber(total) or 0, tonumber(count) or 1
  if total <= 0 then return 0 end
  if count <= 1 then return total end
  return math.max(1, math.floor(total / count))
end

-- What a bid / buyout cell shows: top line, and a smaller line under it (nil = none). perUnit on: one item's price on top, the stack's total under it (stacks of 2+ only).
function A.Cell(total, count, perUnit)
  if not total or total <= 0 then return nil, nil end
  if perUnit and (count or 1) > 1 then return A.Coin(A.UnitPrice(total, count)) .. " ea", A.Coin(total) end
  return A.Coin(total), nil
end

-- The client's list entry as one table, whichever of the 2.x / 1.14 / 8.x argument orders it answers: the 7th value is the level column's header name (a string) in the
-- later layouts, and those also carry the bidder's and owner's full names after highBidder / owner.
function A.Normalize(t)
  local o = type(t[7]) == "string" and 1 or 0
  local owner = o == 1 and t[14] or t[12]
  return {
    name = t[1], texture = t[2], count = t[3] or 1, quality = t[4] or 1, canUse = t[5], level = t[6] or 0,
    minBid = t[7 + o] or 0, minIncrement = t[8 + o] or 0, buyout = t[9 + o] or 0, bid = t[10 + o] or 0, highBidder = t[11 + o], owner = owner,
    sold = (o == 1 and t[16] or t[13]) == 1,
  }
end
function A.Info(kind, idx)
  if not _G.GetAuctionItemInfo then return nil end
  local t = { GetAuctionItemInfo(kind, idx) }
  if not t[1] then return nil end
  local e = A.Normalize(t)
  e.left = _G.GetAuctionItemTimeLeft and GetAuctionItemTimeLeft(kind, idx) or 4
  return e
end

-- Time left classes of the client (1 short ... 4 very long): label and colour.
A.TIMES = { { "<30m", 1, 0.25, 0.2 }, { "<2h", 1, 0.55, 0.15 }, { "<12h", 1, 0.82, 0 }, { ">12h", 0.35, 0.85, 0.35 } }
function A.TimeLeft(c) local t = A.TIMES[c] or A.TIMES[4]; return t[1], t[2], t[3], t[4] end

-- The status of a Bids-tab entry: high bidder or outbid.
function A.BidStatus(e)
  if e.highBidder and e.highBidder ~= "" then return "High bidder", 0.35, 0.85, 0.35 end
  return "Outbid", 1, 0.3, 0.25
end

-- Cheapest buyout per unit by item name among the results of others (pure): entries = list of Normalize() tables.
function A.Lowest(entries, me)
  local low = {}
  for _, e in ipairs(entries) do
    if e.name and e.buyout and e.buyout > 0 and e.owner ~= me then
      local u = A.UnitPrice(e.buyout, e.count)
      if not low[e.name] or u < low[e.name] then low[e.name] = u end
    end
  end
  return low
end
-- The undercut for a stack: 1 copper under the cheapest unit price times the stack (never below 1).
function A.Undercut(unit, stack)
  if not unit or unit <= 0 then return nil end
  return math.max(1, math.floor(unit * math.max(1, stack or 1)) - 1)
end

-- Your active auctions: count, total of their buyouts, those without one (pure).
function A.Summary(entries)
  local n, total, none = 0, 0, 0
  for _, e in ipairs(entries) do
    n = n + 1
    if e.buyout and e.buyout > 0 then total = total + e.buyout else none = none + 1 end
  end
  return n, total, none
end
function A.SummaryText(n, total, none)
  if n == 0 then return "No active auctions" end
  local out = n .. (n == 1 and " auction" or " auctions") .. ", " .. A.Coin(total) .. " at buyout"
  if none > 0 then out = out .. " (" .. none .. " without)" end
  return out
end

---------------------------------------------------------------- search history (account-wide)
local function db()
  if type(_G.AztraForeverUIDB) ~= "table" then _G.AztraForeverUIDB = {} end
  local d = _G.AztraForeverUIDB
  d.ahSearches = type(d.ahSearches) == "table" and d.ahSearches or {}
  return d
end
function A.Remember(text)
  if type(text) ~= "string" then return false end
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return false end
  local list, low = db().ahSearches, text:lower()
  for i = #list, 1, -1 do if tostring(list[i]):lower() == low then table.remove(list, i) end end
  table.insert(list, 1, text)
  while #list > A.HISTORY_MAX do table.remove(list) end
  return true
end
function A.Searches() return db().ahSearches end

-- The client throttles queries: ours (the history list) only goes out when it says so.
function A.CanQuery()
  if _G.CanSendAuctionQuery then return (CanSendAuctionQuery()) and true or false end
  return true
end

---------------------------------------------------------------- rows
-- kind: the client's list name, the row family, how many rows, its scroll frame, and where each cell goes inside the row ({ x, w, align }).
A.KINDS = {
  browse = { list = "list", prefix = "BrowseButton", n = 8, scroll = "BrowseScrollFrame", cols = {
    name = { 44, 180, "LEFT" }, level = { 228, 32, "CENTER" }, time = { 262, 60, "CENTER" }, seller = { 326, 90, "LEFT" }, bid = { 420, 88, "RIGHT" }, buyout = { 512, 86, "RIGHT" } } },
  bid = { list = "bidder", prefix = "BidButton", n = 9, scroll = "BidScrollFrame", cols = {
    name = { 44, 236, "LEFT" }, level = { 284, 36, "CENTER" }, time = { 324, 66, "CENTER" }, buyout = { 394, 146, "RIGHT" }, status = { 544, 96, "CENTER" }, bid = { 644, 122, "RIGHT" } } },
  mine = { list = "owner", prefix = "AuctionsButton", n = 9, scroll = "AuctionsScrollFrame", cols = {
    name = { 44, 186, "LEFT" }, time = { 232, 66, "CENTER" }, seller = { 300, 116, "LEFT" }, bid = { 420, 134, "RIGHT" } } },
}
A.KIND_ORDER = { "browse", "bid", "mine" }

local function g(n) return _G[n] end

-- Builds the cells of row i of a kind once, hides what the client draws on the row besides its item button, returns the overlay.
function A.BuildRow(kind, i)
  local cfg = A.KINDS[kind]
  local row = g(cfg.prefix .. i)
  if not row then return end
  if row.afCells then return row.afCells end
  local cells = { texts = {}, subs = {} }
  row.afCells = cells
  local item = g(cfg.prefix .. i .. "Item")
  for _, c in ipairs({ row:GetChildren() }) do if c ~= item and not c.afOwn and c.SetAlpha then c:SetAlpha(0) end end
  for _, r in ipairs({ row:GetRegions() }) do
    if r.GetObjectType and r:GetObjectType() == "FontString" and not r.afOwn then r:SetAlpha(0) end
  end
  local ov = CreateFrame("Frame", "AFUI_AH" .. kind .. i, row)
  ov.afOwn = true; ov:SetAllPoints(row); if ov.EnableMouse then ov:EnableMouse(false) end
  ov:SetFrameLevel(row:GetFrameLevel() + 2)
  cells.frame = ov
  local tint = row:CreateTexture(nil, "BACKGROUND"); tint:SetAllPoints(row); tint:SetTexture("Interface\\Buttons\\WHITE8X8"); tint:SetVertexColor(0.1, 0.55, 0.2, 0.18); tint:Hide()
  tint.afOwn = true; cells.tint = tint
  for name, c in pairs(cfg.cols) do
    local fs = ov:CreateFontString("AFUI_AH" .. kind .. i .. name, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", ov, "TOPLEFT", c[1], -(name == "name" and 4 or 5)); fs:SetWidth(c[2]); fs:SetHeight(14); fs:SetJustifyH(c[3])
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    fs.afOwn = true; cells.texts[name] = fs
    if name == "name" or name == "bid" or name == "buyout" then
      local sub = ov:CreateFontString("AFUI_AH" .. kind .. i .. name .. "Sub", "OVERLAY", "GameFontDisableSmall")
      sub:SetPoint("TOPLEFT", ov, "TOPLEFT", c[1], -20); sub:SetWidth(c[2]); sub:SetHeight(12); sub:SetJustifyH(c[3])
      if sub.SetWordWrap then sub:SetWordWrap(false) end
      sub.afOwn = true; cells.subs[name] = sub
    end
  end
  return cells
end

local function qualityColor(q)
  local c = _G.ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if c then return c.r, c.g, c.b end
  return 1, 1, 1
end

-- Fills one row from a list entry (pure of the client: used by the specs with an entry table).
function A.FillRow(kind, cells, e, me, perUnit, own)
  local T, S = cells.texts, cells.subs
  local mine = e.owner and me and e.owner == me
  cells.frame:Show()
  T.name:SetText(e.name .. ((mine and own.mark) and " (mine)" or ""))
  T.name:SetTextColor(qualityColor(e.quality))
  S.name:SetText(e.count > 1 and ("Stack of " .. e.count) or "")
  if T.level then T.level:SetText(e.level > 0 and tostring(e.level) or "") end
  if T.time then local s, r, gg, b = A.TimeLeft(e.left); T.time:SetText(s); T.time:SetTextColor(r, gg, b) end
  if T.seller then T.seller:SetText((kind == "mine") and ((e.highBidder and e.highBidder ~= "") and e.highBidder or "-") or (e.owner or "")) end
  local bidNow = e.bid > 0 and e.bid or e.minBid
  if kind == "mine" then
    local top, sub = A.Cell(bidNow, e.count, false)
    T.bid:SetText(top or ""); S.bid:SetText(e.buyout > 0 and ("Buyout " .. A.Coin(e.buyout)) or "No buyout")
  else
    local top, sub = A.Cell(bidNow, e.count, perUnit)
    T.bid:SetText(top or ""); S.bid:SetText(sub or "")
    if T.buyout then
      local bt, bs = A.Cell(e.buyout, e.count, perUnit)
      T.buyout:SetText(bt or "|cff888888-|r"); S.buyout:SetText(bs or "")
    end
  end
  if T.status then local s, r, gg, b = A.BidStatus(e); T.status:SetText(s); T.status:SetTextColor(r, gg, b) end
  if cells.tint then if mine and own.mark then cells.tint:Show() else cells.tint:Hide() end end
  return mine
end

local function scrollOffset(name)
  local sf = g(name)
  if sf and _G.FauxScrollFrame_GetOffset then return FauxScrollFrame_GetOffset(sf) or 0 end
  return 0
end

function A.UpdateRows(kind)
  local cfg = A.KINDS[kind]
  if not cfg or not A.built then return end
  local num = _G.GetNumAuctionItems and (GetNumAuctionItems(cfg.list)) or 0
  local offset = scrollOffset(cfg.scroll)
  local me = _G.UnitName and UnitName("player")
  local perUnit, own = A.On("ahPerUnit"), { mark = A.On("ahHighlightOwn") }
  local hide = A.On("ahHideOwn") and kind == "browse"
  local seen = {}
  for i = 1, cfg.n do
    local cells = A.BuildRow(kind, i)
    local row = g(cfg.prefix .. i)
    if cells and row then
      local idx = offset + i
      local e = idx <= num and A.Info(cfg.list, idx) or nil
      if e then
        local mine = A.FillRow(kind, cells, e, me, perUnit, own)
        if row.SetAlpha then row:SetAlpha((hide and mine) and 0.3 or 1) end
        seen[#seen + 1] = e
      else
        cells.frame:Hide(); if cells.tint then cells.tint:Hide() end
      end
    end
  end
  if kind == "browse" then A.Collect() end
  if kind == "mine" then A.UpdateSummary() end
end

-- The results the player has (the page the client holds) as entries: for the undercut. Reads the client's list only.
function A.Collect()
  local num = _G.GetNumAuctionItems and (GetNumAuctionItems("list")) or 0
  local entries = {}
  for i = 1, num do local e = A.Info("list", i); if e then entries[#entries + 1] = e end end
  A.last = { lowest = A.Lowest(entries, _G.UnitName and UnitName("player")), count = #entries }
end

function A.UpdateSummary()
  local s = A.frames and A.frames.summary
  if not s then return end
  if not A.On("ahSummary") then s:Hide(); return end
  local entries = {}
  local num = _G.GetNumAuctionItems and (GetNumAuctionItems("owner")) or 0
  for i = 1, num do local e = A.Info("owner", i); if e then entries[#entries + 1] = e end end
  s:SetText(A.SummaryText(A.Summary(entries))); s:Show()
end

function A.UpdatePager()
  local f = A.frames
  if not (f and f.page) then return end
  local shown, total = 0, 0
  if _G.GetNumAuctionItems then shown, total = GetNumAuctionItems("list") end
  shown, total = shown or 0, total or shown or 0
  local page = (_G.AuctionFrameBrowse and AuctionFrameBrowse.page or 0) + 1
  f.page:SetText(total > 0 and ("Page " .. page .. "  (" .. shown .. " of " .. total .. ")") or "")
end

---------------------------------------------------------------- our controls
local function label(parent, name, text, font, align)
  local t = parent:CreateFontString(name, "OVERLAY", font or "GameFontNormal")
  t:SetText(text); t:SetJustifyH(align or "LEFT"); t.afOwn = true
  return t
end
A.label = label

local function button(name, parent, text, w, h, tip, onClick)
  local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
  b:SetText(text); b.afOwn = true
  if AFUI.WinKit and AFUI.WinKit.button then AFUI.WinKit.button(b, w, h) end
  b:SetWidth(w); b:SetHeight(h)
  b:SetScript("OnClick", onClick)
  b.afTip = tip
  b:SetScript("OnEnter", function(self) if self.afTip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(self.afTip, 1, 1, 1, 1, true); GameTooltip:Show() end end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end
A.button = button

local function check(name, parent, text, key, tip)
  local c = CreateFrame("CheckButton", name, parent)
  c.afOwn = true; c:SetWidth(20); c:SetHeight(20)
  if AFUI.WinKit and AFUI.WinKit.check then AFUI.WinKit.check(c) end
  c.text = label(c, nil, text, "GameFontHighlightSmall"); c.text:SetPoint("LEFT", c, "RIGHT", 4, 0)
  c.key = key
  c:SetScript("OnClick", function(self) if AFUI.SetSetting then AFUI.SetSetting(self.key, self:GetChecked() and true or false) end end)
  c:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(tip, 1, 1, 1, 1, true); GameTooltip:Show() end)
  c:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return c
end

function A.Hint(msg) if AFUI.Print then AFUI.Print("|cffffd100Auction House|r: " .. msg) end end

function A.Refresh()
  local f = A.frames
  if not f then return end
  if f.perUnit then f.perUnit:SetChecked(A.On("ahPerUnit")) end
  if f.hideOwn then f.hideOwn:SetChecked(A.On("ahHideOwn")) end
  if f.history then if A.On("ahHistory") then f.history:Show() else f.history:Hide() end end
  if f.undercut then if A.On("ahUndercut") then f.undercut:Show() else f.undercut:Hide() end end
  -- the headers say what the price columns hold
  local per = A.On("ahPerUnit")
  for _, h in ipairs({ { "BrowseCurrentBidSort", "Bid" }, { "BidBidSort", "Bid" } }) do
    local b = g(h[1]); if b and b.SetText then b:SetText(per and (h[2] .. " / unit") or h[2]) end
  end
  if f.buyoutHead then f.buyoutHead:SetText(per and "Buyout / unit" or "Buyout") end
  for _, k in ipairs(A.KIND_ORDER) do A.UpdateRows(k) end
  A.UpdatePager(); A.UpdateSummary()
end

-- Fills and shows (or hides) the search history under the name box.
function A.ToggleHistory()
  local pop = A.frames and A.frames.pop
  if not pop then return end
  if pop:IsShown() then pop:Hide(); return end
  local list = A.Searches()
  if #list == 0 then A.Hint("No searches yet."); return end
  pop:ClearAllPoints(); pop:SetPoint("TOPLEFT", _G.BrowseName or pop:GetParent(), "BOTTOMLEFT", -4, -4)
  pop:SetHeight(8 + #list * 18)
  for i = 1, A.HISTORY_MAX do
    local b = pop.rows[i]
    if not b and list[i] then
      b = CreateFrame("Button", nil, pop)
      b:SetWidth(172); b:SetHeight(18); b.afOwn = true
      b.text = label(b, nil, "", "GameFontHighlightSmall"); b.text:SetPoint("LEFT", b, "LEFT", 4, 0)
      b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
      b:SetScript("OnClick", function(self)
        pop:Hide()
        if _G.BrowseName then BrowseName:SetText(self.query) end
        if A.CanQuery() and type(_G.AuctionFrameBrowse_Search) == "function" then AuctionFrameBrowse_Search()
        else A.Hint("The auction house is busy: press Search in a moment.") end
      end)
      pop.rows[i] = b
    end
    if b then
      if list[i] then b.query = list[i]; b.text:SetText(list[i]); b:ClearAllPoints(); b:SetPoint("TOPLEFT", pop, "TOPLEFT", 4, -4 - (i - 1) * 18); b:Show() else b:Hide() end
    end
  end
  pop:Show()
end

-- Undercut: the sell boxes get 1 copper under the cheapest buyout of the item on the sell slot, from the last results.
function A.DoUndercut()
  local name = _G.GetAuctionSellItemInfo and (GetAuctionSellItemInfo())
  if not name then A.Hint("Put the item you want to sell in the slot first."); return end
  local unit = A.last and A.last.lowest and A.last.lowest[name]
  if not unit then A.Hint("No buyout of " .. name .. " in your last search. Search for it on the Browse tab first."); return end
  local stack = _G.AuctionsStackSizeEntry and AuctionsStackSizeEntry:GetNumber() or 1
  local price = A.Undercut(unit, stack)
  if _G.MoneyInputFrame_SetCopper then
    if _G.BuyoutPrice then MoneyInputFrame_SetCopper(BuyoutPrice, price) end
    if _G.StartPrice then MoneyInputFrame_SetCopper(StartPrice, price) end
  end
  A.Hint("Set to " .. A.Coin(price) .. ", 1 copper under the cheapest buyout.")
end

-- Duration and stack size of the sell page, remembered for the session.
A.session = {}
function A.ApplySession()
  if not A.On("ahRemember") or A.applying then return end
  local s = A.session
  A.applying = true
  if s.radio and type(_G.AuctionsRadioButton_OnClick) == "function" then pcall(AuctionsRadioButton_OnClick, s.radio) end
  if s.stack and _G.AuctionsStackSizeEntry then
    local max = _G.AuctionsStackSizeMaxButton and AuctionsStackSizeEntry.GetNumber and nil
    local _, _, _, _, _, _, _, stackCount, totalCount = GetAuctionSellItemInfo()
    local cap = tonumber(totalCount) or tonumber(stackCount) or s.stack
    AuctionsStackSizeEntry:SetNumber(math.max(1, math.min(s.stack, cap)))
  end
  A.applying = false
end

function A.Build()
  if A.frames then return A.frames end
  local f = {}
  A.frames = f
  local browse, bid, mine = _G.AuctionFrameBrowse, _G.AuctionFrameBid, _G.AuctionFrameAuctions
  if browse then
    f.history = button("AFUI_AHHistory", browse, "v", 22, 22, "Your last searches.", function() A.ToggleHistory() end)
    local pop = CreateFrame("Frame", "AFUI_AHHistoryList", browse)
    pop:SetFrameStrata("DIALOG"); pop:SetWidth(180); pop.afOwn = true; pop.rows = {}
    if AFUI.WinKit and AFUI.WinKit.panel then AFUI.WinKit.panel(pop) end
    pop:Hide(); f.pop = pop
    f.lvl = label(browse, "AFUI_AHLvlLabel", "Lvl", "GameFontNormalSmall"); f.dash = label(browse, "AFUI_AHDash", "-", "GameFontNormal", "CENTER")
    f.perUnit = check("AFUI_AHPerUnit", browse, "Prices per unit", "ahPerUnit", "Bid and buyout show the price of one item; the stack's total goes under it.")
    f.hideOwn = check("AFUI_AHHideOwn", browse, "Fade my auctions", "ahHideOwn", "Your own auctions in the results are faded.")
    f.page = label(browse, "AFUI_AHPage", "", "GameFontHighlightSmall", "CENTER")
    f.bidLabel = label(browse, "AFUI_AHBidLabel", "Bid:", "GameFontNormal")
    f.buyoutHead = button("AFUI_AHBuyoutHeader", browse, "Buyout", 90, 18, "The price to buy the stack at once.", function()
      if type(_G.AuctionFrame_SetSort) == "function" then pcall(AuctionFrame_SetSort, "list", "buyout") end
    end)
    if AFUI.WinKit and AFUI.WinKit.header then AFUI.WinKit.header(f.buyoutHead) end
    f.buyoutHead.afTip = "Sort by buyout."
  end
  if mine then
    f.summary = label(mine, "AFUI_AHSummary", "", "GameFontHighlightSmall")
    f.undercut = button("AFUI_AHUndercut", mine, "Undercut", 76, 26, "Sets the buyout 1 copper under the cheapest buyout of this item in your last search.", function() A.DoUndercut() end)
    f.warn = label(mine, "AFUI_AHDepositWarn", "The deposit is lost if the auction ends unsold.", "GameFontDisableSmall")
    f.depositLabel = label(mine, "AFUI_AHDepositLabel", "Deposit:", "GameFontNormalSmall")
    f.itemLabel = label(mine, "AFUI_AHItemLabel", "Item", "GameFontNormalSmall")
    f.stackLabel = label(mine, "AFUI_AHStackLabel", "Stack size", "GameFontNormalSmall")
    f.stacksLabel = label(mine, "AFUI_AHStacksLabel", "Stacks", "GameFontNormalSmall")
    f.durLabel = label(mine, "AFUI_AHDurationLabel", "Duration", "GameFontNormalSmall")
    f.startLabel = label(mine, "AFUI_AHStartLabel", "Starting price", "GameFontNormalSmall")
    f.buyoutLabel = label(mine, "AFUI_AHBuyoutLabel", "Buyout price", "GameFontNormalSmall")
  end
  return f
end

---------------------------------------------------------------- setup (called by AuctionFrame.lua once the window is skinned)
function A.Setup()
  if A.done then return end
  A.done = true
  for _, s in ipairs(A.SETTINGS) do
    if AFUI.ProvideSetting then AFUI.ProvideSetting(s[1], s[4]) end
    if AFUI.Settings and AFUI.Settings.Register then AFUI.Settings.Register{ category = "tooltips", key = s[1], label = "Auction house: " .. s[2], default = s[4], tooltip = s[3] } end
    if AFUI.OnSettingChanged then AFUI.OnSettingChanged(s[1], function() A.Refresh() end) end
  end
  A.Build()
  A.built = true
  for _, h in ipairs({ { "AuctionFrameBrowse_Update", "browse" }, { "AuctionFrameBid_Update", "bid" }, { "AuctionFrameAuctions_Update", "mine" } }) do
    if type(_G[h[1]]) == "function" then hooksecurefunc(h[1], function() A.UpdateRows(h[2]); if h[2] == "browse" then A.UpdatePager() end end) end
  end
  if type(_G.AuctionFrameBrowse_Search) == "function" then
    hooksecurefunc("AuctionFrameBrowse_Search", function() if A.On("ahHistory") and _G.BrowseName then A.Remember(BrowseName:GetText()) end end)
  end
  if type(_G.AuctionsRadioButton_OnClick) == "function" then
    hooksecurefunc("AuctionsRadioButton_OnClick", function(i) if not A.applying then A.session.radio = i end end)
  end
  if _G.AuctionsStackSizeEntry and AuctionsStackSizeEntry.HookScript then
    AuctionsStackSizeEntry:HookScript("OnTextChanged", function(self, user)
      if A.applying or not user then return end
      local n = self:GetNumber(); if n and n > 0 then A.session.stack = n end
    end)
  end
  AFUI.On("NEW_AUCTION_UPDATE", function() A.ApplySession() end)
  AFUI.On("AUCTION_ITEM_LIST_UPDATE", function() A.Refresh() end)
  AFUI.On("AUCTION_OWNED_LIST_UPDATE", function() A.UpdateRows("mine") end)
  AFUI.On("AUCTION_BIDDER_LIST_UPDATE", function() A.UpdateRows("bid") end)
  if _G.AuctionFrame and AuctionFrame.HookScript then AuctionFrame:HookScript("OnHide", function() if A.frames.pop then A.frames.pop:Hide() end end) end
  A.Refresh()
end
