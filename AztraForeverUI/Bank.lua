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
B.PURCHASE_H, B.FOOTER = 72, 33
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
  function m.item(i) return B.PAD_X + ((i - 1) % cols) * (B.ITEM + B.GAP), B.GRID_TOP + math.floor((i - 1) / cols) * (B.ITEM + B.GAP) end
  function m.bag(j) return B.PAD_X + B.BAG_LABEL_W + (j - 1) * (B.BAG + B.BAG_GAP), m.bagY end
  return m
end

-- "Combine bank bags" (the default): the window the combined bags use (10 columns, 1 px gaps, search box and Clean Up button under the title): the 28 bank slots first,
-- then every slot of the bought bank bags, then the divider, the "Bag Slots" row and the purchase row. Same return shape as Metrics (item(i) is the i-th slot of B.List()).
B.COLS, B.CGAP, B.CTOP = 10, 1, 60
function B.CombinedMetrics(total, hasPurchase)
  local L = AFUI.BagLayout
  local cols = B.COLS
  local m = { cols = cols, rows = L.Rows(total, cols), combined = true }
  m.w = cols * B.ITEM + (cols - 1) * B.CGAP + 15
  local gridH = m.rows * B.ITEM + (m.rows - 1) * B.CGAP
  m.divider = B.CTOP + gridH + 8
  m.bagY = m.divider + 12
  m.purchaseY = m.bagY + B.BAG + 6
  m.h = m.purchaseY + (hasPurchase and B.PURCHASE_H or 0) + 6 + B.FOOTER
  m.scale = L.FitScale(m.h, _G.UIParent and UIParent:GetHeight() or 768)
  function m.item(i) local c, r = L.Cell(i - 1, total, cols); return m.w - 7 - (cols * B.ITEM + (cols - 1) * B.CGAP) + c * (B.ITEM + B.CGAP), B.CTOP + r * (B.ITEM + B.CGAP) end
  function m.bag(j) return B.PAD_X + B.BAG_LABEL_W + (j - 1) * (B.BAG + B.BAG_GAP), m.bagY end
  return m
end

-- The coin box behind a window's money (Forever's footer: common-coinbox left / centre / right), 168 x 17; the caller anchors it. The merchant window uses it too.
function B.CoinBox(host)
  local coin = CreateFrame("Frame", nil, host); coin:SetWidth(168); coin:SetHeight(17); coin:SetFrameLevel(host:GetFrameLevel() + 2)
  for _, def in ipairs({ { "common-coinbox-left", "LEFT" }, { "common-coinbox-right", "RIGHT" } }) do
    local t = coin:CreateTexture(nil, "BACKGROUND"); AFUI.SetAtlas(t, def[1], true); t:SetPoint(def[2], coin, def[2])
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

local function sizeSig()
  local _, nb = counts()
  local t = {}
  for id = BAG0 + 1, BAG0 + nb do t[#t + 1] = GetContainerNumSlots(id) or 0 end
  return table.concat(t, ",")
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
        local x, y = m.item(i); place(b, x, y, B.ITEM)
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
  setShown(B.search, combined); setShown(B.sort, combined)
  B.search:ClearAllPoints(); B.search:SetPoint("TOPLEFT", f, "TOPLEFT", 62, -33); B.search:SetWidth(m.w - 62 - 40)
  if B.search:GetText() ~= AFUI.Bags.searchText then B.search:SetText(AFUI.Bags.searchText) end
  local p = _G.BankFramePurchaseInfo
  if p then p:ClearAllPoints(); p:SetPoint("TOP", f, "TOP", -4, -m.purchaseY + 2) end
  local money = _G.BankFrameMoneyFrame
  if money then money:ClearAllPoints(); money:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12) end
  B.coin:ClearAllPoints(); B.coin:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -9, 9)
  if AFUI.PanelAttrs and AFUI.WinKit and AFUI.WinKit.ORIGIN then
    AFUI.PanelAttrs(f, { width = m.w * scale, height = m.h * scale, xoffset = AFUI.WinKit.ORIGIN.x, yoffset = AFUI.WinKit.ORIGIN.y })
  end
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
  local sb = CreateFrame("Button", nil, f)
  sb:SetWidth(24); sb:SetHeight(24); sb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -9, -30); sb:SetFrameLevel(f:GetFrameLevel() + 30)
  AFUI.SetButtonAtlas(sb, { "bags-button-autosort-up", "bags-button-autosort-down", "bags-button-autosort-up" }, 0.4)
  sb:SetScript("OnClick", function() AFUI.Bags.CleanUp(B.SortSlots(), B.Shown) end)
  sb:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText("Clean Up Bank", 1, 1, 1)
    GameTooltip:AddLine(AFUI.Bags.Sort.Running("bank") and "Click again to stop." or "Merges partial stacks, then sorts by type, quality and name.", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  sb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  B.sort = sb
  B.sorting = tf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  B.sorting:SetText("Sorting..."); B.sorting:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12); B.sorting:Hide()
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
  end
  -- Settings.lua loads after this file: the option is registered at login
  if AFUI.Settings and AFUI.Settings.Register then
    AFUI.Settings.Register{ category = "tooltips", key = "bankCombine", label = "Combine bank bags", default = true,
      tooltip = "The bank shows one window with the bank slots and every bank bag in a single grid, with a search box and Clean Up button. Off: Blizzard's own window for each bank bag." }
  end
  if AFUI.ProvideSetting then AFUI.ProvideSetting("bankCombine", true) end
  -- a bank bag swapped or bought changes the grid: lay it out again (one frame after a burst of events, out of combat)
  local pend = CreateFrame("Frame")
  local function sizeChanged()
    if pend.queued or not (B.Shown() and B.Combined()) or sizeSig() == B.sig then return end
    pend.queued = true
    pend:SetScript("OnUpdate", function(self) self:SetScript("OnUpdate", nil); self.queued = nil; if B.Shown() then B.Apply() end end)
  end
  AFUI.On("BAG_UPDATE", sizeChanged); AFUI.On("PLAYERBANKBAGSLOTS_CHANGED", sizeChanged)
  if f:IsShown() then B.Apply() end
end

AFUI.Bags = AFUI.Bags or {}
AFUI.Bags.Bank = B -- Bags.UpdateAll calls Bank.Update after every scan
AFUI.RegisterModule("Bank", { OnLogin = B.Setup })
