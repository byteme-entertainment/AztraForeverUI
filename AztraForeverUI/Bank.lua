-- Forever's bank window drawn over Blizzard's own BankFrame: the client's frame, item buttons, bag buttons, purchase button and money frame keep every
-- script (clicks, drags, tooltips, buying a slot); only art and positions change (hooks and anchors, nothing replaced). Look = docs/forever-ref/screens/bags/
-- bank-window.jpg: the bag windows' metal frame and Rock fill (Bags.Chrome), the wing slots with quality borders / new-item glow / item level
-- (Bags.SkinSlot), the item grid, a divider, "Bag Slots:" with the bag buttons, the purchase row and the grey footer with the money.
-- Client facts (vanilla/TBC bankframe.xml + .lua): BankFrameItem1..NUM_BANKGENERIC_SLOTS (container -1, button id = slot), BankFrameBag1..NUM_BANKBAGSLOTS
-- (BankButtonIDToInvSlotID(id, 1)), BankFramePurchaseInfo (label, BankFrameSlotCost, BankFramePurchaseButton, BankFrameDetailMoneyFrame), BankFrameMoneyFrame,
-- BankFrameTitleText, BankCloseButton, an unnamed UI-BankFrame texture and two unnamed labels ("Item Slots", "Bag Slots").
-- "Combine bank bags" (default on): the same frame also holds every slot of the bought bank bags (container ids 5..11, the Bags.lua item buttons) in ONE grid after the
-- 28 bank slots, with the search box and Clean Up button; Blizzard's separate bank bag windows are never opened (Bags.lua overrides ToggleBag / OpenBag / CloseBag /
-- IsBagOpen for those ids via B.Owns and hides a ContainerFrame that shows one anyway). Off: the old look and the client's own bag windows.
AFUI = AFUI or {}
local B = {}
AFUI.Bank = B

B.ITEM, B.GAP, B.PAD_X, B.GRID_TOP = 37, 10, 20, 40
B.BAG, B.BAG_GAP, B.BAG_LABEL_W = 28, 4, 74
B.PURCHASE_H = 72
B.FOOTER = AFUI.BagLayout.FOOT.border + AFUI.BagLayout.FooterHeight("bank") -- the footer strip and the frame border under it (Bags.lua: BagLayout.Footer)
local BANK_CONTAINER = -1

-- Pure geometry. Returns { w, h, cols, rows, item(i) = x, y, bag(j) = x, y, divider, bagY, purchaseY } (y from the window's top, positive down).
function B.Metrics(nItems, nBags, hasPurchase)
  local cols = nItems % 7 == 0 and 7 or (nItems % 6 == 0 and 6 or 7)
  local rows = math.ceil(nItems / cols)
  local m = { cols = cols, rows = rows }
  m.w = 2 * B.PAD_X + cols * B.ITEM + (cols - 1) * B.GAP
  local gridH = rows * B.ITEM + (rows - 1) * B.GAP
  m.divider = B.GRID_TOP + gridH + 12
  m.bagY = m.divider + 14
  m.purchaseY = m.bagY + B.BAG + 6
  m.h = m.purchaseY + (hasPurchase and B.PURCHASE_H or 0) + 6 + B.FOOTER
  m.footer = AFUI.BagLayout.Footer("bank", m.w, m.h); m.coinY = m.footer.money[2]
  function m.item(i) return B.PAD_X + ((i - 1) % cols) * (B.ITEM + B.GAP), B.GRID_TOP + math.floor((i - 1) / cols) * (B.ITEM + B.GAP) end
  function m.bag(j) return B.PAD_X + B.BAG_LABEL_W + (j - 1) * (B.BAG + B.BAG_GAP), m.bagY end
  return m
end

-- "Combine bank bags" (the default): the window the combined bags use (10 columns, 1 px gaps, search box and Clean Up button under the title): the 28 bank slots first,
-- then every slot of the bought bank bags, then the divider, the "Bag Slots" row and the purchase row. Same return shape as Metrics (item(i) is the i-th slot of B.List()).
-- The size is computed from the player's layout (columns: Auto or 4..20, slot size, spacing: BagLayout.Prefs("bank")) and the screen (BagLayout.Plan: Auto columns grow first
-- to cut the rows, only then the window scales down), top to bottom: title, search + toolbar row (Clean Up, Layout gear), grid, divider, "Bag Slots" row, purchase row, footer
-- (money). m.rects lists every control's rectangle { x, y, w, h } inside the window (y down) for the specs: nothing leaves the window and nothing overlaps.
-- o (tests) = { prefs, screenW, screenH }.
B.COLS, B.CGAP, B.CTOP, B.MIN_W, B.PURCHASE_W, B.TOOL = 10, 1, 60, 340, 300, 24
function B.CombinedMetrics(total, hasPurchase, o)
  o = o or {}
  local L = AFUI.BagLayout
  local pf = o.prefs or L.Prefs("bank")
  local item, g = pf.item, pf.gap
  local function dims(c) -- window width, divider y, bag row y, purchase row y, height for c columns
    local rows = L.Rows(total, c)
    local gridW, gridH = c * item + (c - 1) * g, rows * item + (rows - 1) * g
    local divider = B.CTOP + gridH + 8
    local bagY = divider + 12
    local purchaseY = bagY + B.BAG + 6
    return math.max(gridW + 15, B.MIN_W), purchaseY + (hasPurchase and B.PURCHASE_H or 0) + 6 + B.FOOTER, divider, bagY, purchaseY
  end
  local plan = L.Plan({ cols = pf.cols, total = total, screenW = o.screenW or (_G.UIParent and UIParent:GetWidth() or 1024), screenH = o.screenH or (_G.UIParent and UIParent:GetHeight() or 768),
    size = function(c) local w, h = dims(c); return w, h end })
  local cols = plan.cols
  local m = { cols = cols, rows = L.Rows(total, cols), combined = true, item_size = item, gap = g, scale = plan.scale, fits = plan.fits, auto = plan.auto }
  m.w, m.h, m.divider, m.bagY, m.purchaseY = dims(cols)
  local gridW, gridH = cols * item + (cols - 1) * g, m.rows * item + (m.rows - 1) * g
  m.gridX = L.GridX(m.w, gridW)
  function m.item(i) local c, r = L.Cell(i - 1, total, cols); return m.gridX + c * (item + g), B.CTOP + r * (item + g) end
  function m.bag(j) return B.PAD_X + B.BAG_LABEL_W + (j - 1) * (B.BAG + B.BAG_GAP), m.bagY end
  local T = B.TOOL
  m.sortX, m.gearX = m.w - 9 - T, m.w - 9 - T - 6 - T -- the toolbar row: search box, Layout gear, Clean Up (right to left)
  m.searchX, m.searchW = 62, m.gearX - 6 - 62
  m.footer = AFUI.BagLayout.Footer("bank", m.w, m.h); m.coinY = m.footer.money[2]
  m.rects = {
    title = { m.w / 2 - 70, 6, 140, 14 }, close = { m.w - 28, 0, 28, 25 },
    search = { m.searchX - 4, 30, m.searchW + 8, 24 }, gear = { m.gearX, 30, T, T }, sort = { m.sortX, 30, T, T },
    grid = { m.gridX, B.CTOP, gridW, gridH }, divider = { B.PAD_X, m.divider, m.w - 2 * B.PAD_X, 1 },
    bagLabel = { B.PAD_X, m.bagY, 66, B.BAG },
    footer = m.footer.strip, coin = m.footer.money, sorting = { AFUI.BagLayout.FOOT.inset, m.coinY + 2.5, 60, 12 }, -- "Sorting..." sits on the strip's left, centred like the money
  }
  for j = 1, 7 do local x, y = m.bag(j); m.rects["bag" .. j] = { x, y, B.BAG, B.BAG } end
  if hasPurchase then m.rects.purchase = { m.w / 2 - 4 - B.PURCHASE_W / 2, m.purchaseY - 2, B.PURCHASE_W, B.PURCHASE_H } end
  return m
end

-- The coin box behind a window's money (Forever's footer: common-coinbox left / centre / right), 168 x 17; the caller anchors it. The merchant window uses it too.
function B.CoinBox(host)
  local coin = CreateFrame("Frame", nil, host); coin:SetWidth(168); coin:SetHeight(17); coin:SetFrameLevel(host:GetFrameLevel() + 2)
  for _, def in ipairs({ { "common-coinbox-left", "LEFT" }, { "common-coinbox-right", "RIGHT" } }) do
    local t = coin:CreateTexture(nil, "BACKGROUND"); AFUI.SetAtlas(t, def[1]); t:SetWidth(8); t:SetHeight(17); t:SetPoint(def[2], coin, def[2]) -- the art is 2x: its bracket is drawn at half size so it fits the 17 px box
  end
  local mid = coin:CreateTexture(nil, "BACKGROUND"); AFUI.SetAtlas(mid, "_common-coinbox-center")
  mid:SetPoint("TOPLEFT", coin, "TOPLEFT", 8, 0); mid:SetPoint("BOTTOMRIGHT", coin, "BOTTOMRIGHT", -8, 0)
  return coin
end

local function counts() return _G.NUM_BANKGENERIC_SLOTS or 28, _G.NUM_BANKBAGSLOTS or 7 end
local function setShown(o, on) if on then o:Show() else o:Hide() end end
local BAG0 = _G.NUM_BAG_SLOTS or 4 -- the bank bags are container ids BAG0 + 1 .. BAG0 + 7 (5..11)

function B.Combined() return B.done and AFUI.QoL and AFUI.QoL.Get("bankCombine") and true or false end
function B.Shown() local f = _G.BankFrame; return f and f.IsShown and f:IsShown() and true or false end
-- Is this container id one of the bank bags this window shows itself (Bags.lua then keeps Blizzard's own windows for it closed)?
function B.Owns(id)
  local _, nb = counts()
  return type(id) == "number" and id > BAG0 and id <= BAG0 + nb and B.Combined()
end

-- Every slot of the combined window in order: { { container, slot } }, the bank slots then each bank bag.
function B.List()
  local n, nb = counts()
  local out = {}
  for i = 1, n do out[#out + 1] = { BANK_CONTAINER, i } end
  for id = BAG0 + 1, BAG0 + nb do
    for s = 1, GetContainerNumSlots(id) or 0 do out[#out + 1] = { id, s } end
  end
  return out
end

-- The same slots for Clean Up: { container, slot, family of the bag }.
function B.SortSlots()
  local out, fam = {}, {}
  for _, e in ipairs(B.List()) do
    if fam[e[1]] == nil then fam[e[1]] = AFUI.Bags.BagType(e[1]) end
    out[#out + 1] = { e[1], e[2], fam[e[1]] }
  end
  return out
end

-- Everything the window's size depends on: the bank bags' slot counts, the player's layout and the screen.
local function sizeSig()
  local _, nb = counts()
  local t = {}
  for id = BAG0 + 1, BAG0 + nb do t[#t + 1] = GetContainerNumSlots(id) or 0 end
  local pf = AFUI.BagLayout.Prefs("bank")
  t[#t + 1] = pf.cols .. ":" .. pf.pct .. ":" .. pf.gap
  t[#t + 1] = _G.UIParent and (math.floor(UIParent:GetWidth()) .. "x" .. math.floor(UIParent:GetHeight())) or ""
  return table.concat(t, ",")
end

-- A bought bank bag whose slot count the client has not reported yet (0): its slots are missing from the grid until it does.
function B.PendingData()
  if not _G.GetNumBankSlots then return false end
  local bought = GetNumBankSlots() or 0
  for id = BAG0 + 1, BAG0 + math.min(bought, select(2, counts())) do
    if (GetContainerNumSlots(id) or 0) == 0 then return true end
  end
  return false
end

local function bagButton(i)
  local f = _G["BankFrameBag" .. i]
  if f then return f end
  local sf = _G.BankSlotsFrame
  return sf and rawget(sf, "Bag" .. i) or (_G.BankFrame and rawget(_G.BankFrame, "Bag" .. i))
end
local function itemButton(i) return _G["BankFrameItem" .. i] end

local function purchaseShown() local p = _G.BankFramePurchaseInfo; return p and p.IsShown and p:IsShown() and true or false end

---------------------------------------------------------------- painting
function B.UpdateButton(b)
  if not b or not b.afSkinned then return end
  local id = b:GetID()
  if b.isBag then
    local inv = _G.BankButtonIDToInvSlotID and BankButtonIDToInvSlotID(id, 1)
    local link = inv and GetInventoryItemLink and GetInventoryItemLink("player", inv)
    local q = link and _G.GetInventoryItemQuality and GetInventoryItemQuality("player", inv) or nil
    b.afDim = _G.GetNumBankSlots and id > (GetNumBankSlots() or 0) or false -- a bank bag slot not bought yet: the same wing art, darker
    AFUI.Bags.PaintSlot(b, BANK_CONTAINER - 3, id, link, q, link and true or false)
    return
  end
  local tex, _, _, quality = GetContainerItemInfo(BANK_CONTAINER, id)
  local link = tex and GetContainerItemLink(BANK_CONTAINER, id)
  AFUI.Bags.PaintSlot(b, BANK_CONTAINER, id, link, quality, tex and true or false)
  local text = AFUI.Bags.searchText -- the search box: non-matches dim (the bank bag slots do the same in Bags.UpdateButton)
  b:SetAlpha(AFUI.BagSearch.Matches(link and GetItemInfo(link), text, text ~= "" and link and AFUI.Bags.SearchExtra(link) or nil) and 1 or 0.25)
end

function B.Update()
  if not B.done then return end
  local n, nb = counts()
  for i = 1, n do B.UpdateButton(itemButton(i)) end
  for i = 1, nb do B.UpdateButton(bagButton(i)) end
  setShown(B.sorting, B.Combined() and AFUI.Bags.Sort.Running("bank"))
end

---------------------------------------------------------------- layout
local function place(f, x, y, w, h)
  f:ClearAllPoints(); f:SetPoint("TOPLEFT", BankFrame, "TOPLEFT", x, -y)
  if w then f:SetWidth(w); f:SetHeight(h or w) end
end

function B.Layout()
  local f = _G.BankFrame
  if not (f and B.done) then return end
  local n, nb = counts()
  local combined = B.Combined()
  local list = combined and B.List() or nil
  local m = combined and B.CombinedMetrics(#list, purchaseShown()) or B.Metrics(n, nb, purchaseShown())
  B.metrics, B.sig = m, sizeSig()
  local scale = m.scale or 1
  f:SetScale(scale); f:SetWidth(m.w); f:SetHeight(m.h)
  for _, tb in ipairs({ B.sort, B.layoutBtn }) do if tb.FitIcon then tb:FitIcon() end end -- the glyphs are sized in whole pixels of the new scale
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end -- never off the screen, whatever spot the player dragged it to
  if f.SetHitRectInsets then f:SetHitRectInsets(0, 0, 0, 0) end
  AFUI.Bags.Chrome(f, m.w, m.h, true)
  -- the bank bags' own slots (Bags buttons with the bank bag container ids) live in this window while it is combined, else they are put away
  for id = BAG0 + 1, BAG0 + nb do
    local hd = AFUI.Bags.Holder(id)
    hd:SetParent(f); hd:ClearAllPoints(); hd:SetAllPoints(f); hd:SetFrameLevel(f:GetFrameLevel() + 2)
    local have = combined and GetContainerNumSlots(id) or 0
    for slot, b in pairs(AFUI.Bags.BagButtons(id)) do if slot > have then b:Hide() end end
  end
  if combined then
    for i, e in ipairs(list) do
      local b = e[1] == BANK_CONTAINER and itemButton(e[2]) or AFUI.Bags.Button(e[1], e[2])
      if b then
        local x, y = m.item(i); place(b, x, y, m.item_size)
        if e[1] ~= BANK_CONTAINER then b:Show(); AFUI.Bags.UpdateButton(b) end
      end
    end
  else
    for i = 1, n do local b = itemButton(i); if b then local x, y = m.item(i); place(b, x, y, B.ITEM) end end
  end
  for j = 1, nb do local b = bagButton(j); if b then local x, y = m.bag(j); place(b, x, y, B.BAG) end end
  B.divider:ClearAllPoints()
  B.divider:SetPoint("TOPLEFT", f, "TOPLEFT", B.PAD_X, -m.divider); B.divider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -B.PAD_X, -m.divider)
  B.bagLabel:ClearAllPoints(); B.bagLabel:SetPoint("LEFT", f, "TOPLEFT", B.PAD_X, -(m.bagY + B.BAG / 2))
  setShown(B.search, combined); setShown(B.sort, combined); setShown(B.layoutBtn, combined)
  if combined then
    B.search:ClearAllPoints(); B.search:SetPoint("TOPLEFT", f, "TOPLEFT", m.searchX, -33); B.search:SetWidth(m.searchW)
    B.sort:ClearAllPoints(); B.sort:SetPoint("TOPLEFT", f, "TOPLEFT", m.sortX, -30)
    B.layoutBtn:ClearAllPoints(); B.layoutBtn:SetPoint("TOPLEFT", f, "TOPLEFT", m.gearX, -30)
  end
  if B.search:GetText() ~= AFUI.Bags.searchText then B.search:SetText(AFUI.Bags.searchText) end
  local p = _G.BankFramePurchaseInfo
  if p then
    p:ClearAllPoints(); p:SetPoint("TOP", f, "TOP", -4, -m.purchaseY + 2)
    if combined and p.SetWidth then p:SetWidth(B.PURCHASE_W) end -- the client's frame is sized for its own window: here it stays inside ours
  end
  -- the footer is anchored from the TOP with the computed height, not from the bottom: it cannot end up inside the grid whatever the client does to the frame's own size
  local money = _G.BankFrameMoneyFrame
  local F = AFUI.BagLayout.FOOT
  if money then money:ClearAllPoints(); money:SetPoint("RIGHT", f, "TOPRIGHT", -(F.inset + 4), -(m.coinY + F.box / 2)) end -- centred on the coin box whatever height the client gives its frame
  B.coin:ClearAllPoints(); B.coin:SetPoint("TOPRIGHT", f, "TOPRIGHT", -F.inset, -m.coinY)
  B.sorting:ClearAllPoints(); B.sorting:SetPoint("LEFT", f, "TOPLEFT", F.inset, -(m.coinY + F.box / 2))
  if AFUI.PanelAttrs and AFUI.WinKit and AFUI.WinKit.ORIGIN then
    -- the panel opens at ORIGIN; a window too tall for that spot moves up (never above the top margin) so its bottom stays above the chat / bottom bars
    local L, O = AFUI.BagLayout, AFUI.WinKit.ORIGIN
    local top = O.y
    if combined and _G.UIParent then top = -math.max(L.TOP_MARGIN, math.min(-O.y, UIParent:GetHeight() - L.BOTTOM_MARGIN - m.h * scale)) end
    AFUI.PanelAttrs(f, { width = m.w * scale, height = m.h * scale, xoffset = O.x, yoffset = top, bottomClampOverride = combined and L.BOTTOM_MARGIN or nil })
  end
  -- the frame's real size after all this (a UIPanel manager or another addon may have resized it): put it right again
  if f.GetHeight and math.abs((f:GetHeight() or m.h) - m.h) > 0.5 then f:SetHeight(m.h) end
  if f.GetWidth and math.abs((f:GetWidth() or m.w) - m.w) > 0.5 then f:SetWidth(m.w) end
end

-- Blizzard's own windows for the bank bags (ContainerFrame5..): never shown while the bank combines them.
function B.HideBlizzardBags()
  if InCombatLockdown() then return end
  for i = 1, 13 do
    local c = _G["ContainerFrame" .. i]
    if c and c.IsShown and c:IsShown() and B.Owns(c:GetID()) then c:Hide() end
  end
end

function B.Apply()
  if InCombatLockdown() then AFUI.RunOutOfCombat(B.Apply); return end
  B.Layout()
  B.HideBlizzardBags()
  B.Update()
  AFUI.PortraitUnit(B.portrait, "npc")
end

---------------------------------------------------------------- setup
function B.Setup()
  local f = _G.BankFrame
  if not f or B.done or not AFUI.Bags or not AFUI.Bags.Chrome then return end
  B.done = true
  local P = AFUI.Professions and AFUI.Professions.Kit
  if P then P.hideRegions(f); if _G.BankSlotsFrame then P.hideRegions(_G.BankSlotsFrame) end end
  for _, r in ipairs({ f:GetRegions() }) do -- the unnamed "Item Slots" / "Bag Slots" labels sit on the old art
    if r.GetObjectType and r:GetObjectType() == "FontString" and r ~= _G.BankFrameTitleText then r:Hide() end
  end
  -- title and close button above the metal pieces
  local tf = CreateFrame("Frame", nil, f); tf:SetAllPoints(f); tf:SetFrameLevel(f:GetFrameLevel() + 25)
  B.titleFrame = tf
  local title = _G.BankFrameTitleText
  if title then title:SetParent(tf); title:ClearAllPoints(); title:SetPoint("TOP", f, "TOP", 0, -6); title:SetFontObject(GameFontNormal) end
  local close = _G.BankCloseButton
  if close then
    close:ClearAllPoints(); close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 3); close:SetWidth(28); close:SetHeight(28); close:SetFrameLevel(f:GetFrameLevel() + 30)
    AFUI.SetButtonAtlas(close, { "redbutton-exit", "redbutton-exit-pressed", "redbutton-highlight", "redbutton-exit-disabled" })
  end
  -- the portrait ring shows the banker (the client's own BankPortraitTexture is hidden with the old art)
  B.portrait = f:CreateTexture(nil, "ARTWORK")
  AFUI.WindowPortrait(f, B.portrait)
  -- own pieces: divider under the grid, "Bag Slots:", the coin box behind the money
  B.divider = f:CreateTexture(nil, "ARTWORK"); AFUI.SetColor(B.divider, 0.42, 0.34, 0.2, 0.9); B.divider:SetHeight(1)
  B.bagLabel = tf:CreateFontString(nil, "OVERLAY", "GameFontNormal"); B.bagLabel:SetText((_G.BAGSLOTTEXT and BAGSLOTTEXT:gsub(":?%s*$", "") or "Bag Slots") .. ":")
  B.coin = B.CoinBox(f)
  -- search box (the combined bags window's own, shared text) and the Clean Up button beside it, "Sorting..." in the footer while a run is going
  B.search = AFUI.Bags.MakeSearch(f, "Bank")
  local sb = AFUI.Bags.IconButton(f, "broom"); sb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -9, -30)
  sb:SetScript("OnClick", function() AFUI.Bags.CleanUp(B.SortSlots(), B.Shown) end)
  sb:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText("Clean Up Bank", 1, 1, 1)
    GameTooltip:AddLine(AFUI.Bags.Sort.Running("bank") and "Click again to stop." or "Merges partial stacks, then sorts by type, quality and name.", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  sb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  B.sort = sb
  B.sorting = tf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  B.sorting:SetText("Sorting..."); B.sorting:Hide() -- Layout anchors it in the footer
  B.layoutBtn = AFUI.Bags.MakeLayoutButton(f, "bank") -- the gear left of Clean Up: columns, slot size and spacing
  local money = _G.BankFrameMoneyFrame
  if money then money:SetFrameLevel(f:GetFrameLevel() + 6) end
  -- the slots
  local n, nb = counts()
  for i = 1, n do local b = itemButton(i); if b then b.afSkinned = true; AFUI.Bags.SkinSlot(b, B.ITEM, BANK_CONTAINER, i) end end
  for j = 1, nb do local b = bagButton(j); if b then b.afSkinned = true; AFUI.Bags.SkinSlot(b, B.BAG, BANK_CONTAINER - 3, j) end end
  -- the purchase button wears Forever's red button
  local buy = _G.BankFramePurchaseButton
  if buy and AFUI.WinKit and AFUI.WinKit.button then AFUI.WinKit.button(buy, 124, 28) end
  -- the window moves like the others (the spot is remembered per character)
  if AFUI.WinKit and AFUI.WinKit.makeMovable then AFUI.WinKit.makeMovable(f, nil, "bank") end
  -- hooks: the client's own button updates, show, and the purchase row coming or going (the height follows it)
  if type(_G.BankFrameItemButton_Update) == "function" then hooksecurefunc("BankFrameItemButton_Update", B.UpdateButton) end
  f:HookScript("OnShow", B.Apply)
  local p = _G.BankFramePurchaseInfo
  if p and p.HookScript then
    p:HookScript("OnShow", function() if f:IsShown() then B.Apply() end end)
    p:HookScript("OnHide", function() if f:IsShown() then B.Apply() end end)
  end
  if AFUI.QoL then
    AFUI.QoL.Watch("bagItemLevel", B.Update); AFUI.QoL.Watch("bagNewGlow", B.Update)
    AFUI.QoL.Watch("bankCombine", function() if f:IsShown() then B.Apply() end end)
    for _, k in pairs(AFUI.BagLayout.KEYS.bank) do -- the player's layout: re-laid out at once out of combat, else when it ends (B.Apply waits)
      AFUI.QoL.Watch(k, function() if f:IsShown() then B.Apply() end; AFUI.Bags.RefreshLayoutPopup() end)
    end
  end
  -- Settings.lua loads after this file: the option is registered at login
  if AFUI.Settings and AFUI.Settings.Register then
    AFUI.Settings.Register{ category = "tooltips", key = "bankCombine", label = "Combine bank bags", default = true,
      tooltip = "The bank shows one window with the bank slots and every bank bag in a single grid, with a search box and Clean Up button. Off: Blizzard's own window for each bank bag." }
  end
  if AFUI.ProvideSetting then AFUI.ProvideSetting("bankCombine", true) end
  -- a bank bag swapped or bought changes the grid: lay it out again (one frame after a burst of events, out of combat)
  -- Root cause guard: the frame size comes from the slot counts the client reports AT LAYOUT TIME, and the bank bags' sizes can arrive after the window opened (a first
  -- layout with 0 slots in a bought bag gives a window too short for the grid). So BANKFRAME_OPENED always gets a second pass on the next frame, every event that can change a
  -- count (BAG_UPDATE, PLAYERBANKBAGSLOTS_CHANGED, PLAYERBANKSLOTS_CHANGED), and a screen change (resolution / UI scale), re-lay out when the signature differs; while a bought
  -- bank bag still reports 0 slots the pass repeats (at most 5 frames).
  local pend = CreateFrame("Frame")
  local function queue(force)
    if pend.queued or not B.Shown() or not (force or B.Combined() and sizeSig() ~= B.sig) then return end
    pend.queued = true
    pend:SetScript("OnUpdate", function(self)
      self:SetScript("OnUpdate", nil); self.queued = nil
      if not B.Shown() then return end
      B.Apply()
      if B.Combined() and B.PendingData() and (self.tries or 0) < 5 then self.tries = (self.tries or 0) + 1; queue(true) else self.tries = nil end
    end)
  end
  B.Queue = queue
  local function sizeChanged() queue(false) end
  AFUI.On("BAG_UPDATE", sizeChanged); AFUI.On("PLAYERBANKBAGSLOTS_CHANGED", sizeChanged); AFUI.On("PLAYERBANKSLOTS_CHANGED", sizeChanged)
  AFUI.On("DISPLAY_SIZE_CHANGED", sizeChanged); AFUI.On("UI_SCALE_CHANGED", sizeChanged)
  AFUI.On("BANKFRAME_OPENED", function() queue(true) end)
  if f:IsShown() then B.Apply() end
end

AFUI.Bags = AFUI.Bags or {}
AFUI.Bags.Bank = B -- Bags.UpdateAll calls Bank.Update after every scan
AFUI.RegisterModule("Bank", { OnLogin = B.Setup })
