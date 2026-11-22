-- Forever's merchant window drawn over Blizzard's own MerchantFrame (NpcKit.lua): the metal portrait frame showing the vendor, a dark plate and a Forever
-- item slot (quality border, item level, new-item glow) for each of the 10 goods (12 on the Buyback tab) and the last sold item, the Merchant / Buyback tabs
-- under the frame, the coin box behind the money. The client's frame keeps every script: buying, buyback, the Repair / Repair All buttons, the page buttons,
-- price strings (MoneyFrames) and tooltips stay native; the Sell All Junk button (VendorTools.lua) sits on the title strip.
-- Client facts (Interface_TBC/FrameXML/MerchantFrame.xml, 2.5.3 = ButtonFrameTemplate 336 x 444): MerchantItem1..12 (153 x 44, ItemButton MerchantItemNItemButton, Name,
-- MoneyFrame, SlotTexture / NameFrame art), MerchantBuyBackItem (+ItemButton), MerchantFrameTab1/2, MerchantRepairAllButton / ItemButton, MerchantPrev/NextPageButton,
-- MerchantMoneyFrame (+Inset, Bg), BuybackBG, MerchantFrame_Update (hooked: the client redraws the items from it). 2.4.3 has the old 384 x 512 frame with the same names.
AFUI = AFUI or {}
local M = {}
AFUI.MerchantFrame = M

M.PER_PAGE, M.BUYBACK_PER_PAGE, M.CONTAINER = 10, 12, -5 -- CONTAINER: a bag id of our own for the item slots' bookkeeping (the real bags are 0..4, the bank -1 / -4)
M.SPEC = {
  frame = "MerchantFrame", title = "MerchantNameText", close = "MerchantFrameCloseButton", move = "merchant", npc = true,
  icon = "Interface\\Icons\\INV_Misc_Gem_01",
  size = { w = 336, h = 444, cut = 0 }, size243 = { w = 336, h = 512, cut = 68 }, -- 2.4.3's 512 px frame is dead art below its widgets
  hide = { "MerchantMoneyInset", "MerchantMoneyBg" },
  tabs = { "MerchantFrameTab1", "MerchantFrameTab2" },
}
M.ART = { "BuybackBG", "MerchantFrameBottomLeftBorder", "MerchantFrameBottomRightBorder", "MerchantFramePortrait" } -- shown again by MerchantFrame_Update
M.plates = {}

-- Index into the merchant's list for slot i of the current view (pure): the Buyback tab lists from 1, the Merchant tab by page.
function M.ItemIndex(tab, page, i)
  if tab == 2 then return i end
  return ((page or 1) - 1) * M.PER_PAGE + i
end

local function setShown(o, on) if on then o:Show() else o:Hide() end end

local function paint(b, slot, link)
  local quality = link and select(3, GetItemInfo(link)) or nil
  AFUI.Bags.PaintSlot(b, M.CONTAINER, slot, link, quality, link and true or false)
end

function M.Update()
  local f = _G.MerchantFrame
  if not (f and f.afNpc and AFUI.Bags and AFUI.Bags.PaintSlot) then return end
  for _, n in ipairs(M.ART) do local t = _G[n]; if t and t.Hide then t:Hide() end end
  local buy = f.selectedTab == 2
  for i = 1, M.BUYBACK_PER_PAGE do
    local item, b = _G["MerchantItem" .. i], _G["MerchantItem" .. i .. "ItemButton"]
    local shown = item and item:IsShown() and true or false
    if M.plates[i] then setShown(M.plates[i], shown) end
    if shown and b and b.afSkinned then
      local idx = M.ItemIndex(buy and 2 or 1, f.page, i)
      local get = buy and _G.GetBuybackItemLink or _G.GetMerchantItemLink
      paint(b, i, get and get(idx) or nil)
    end
  end
  local last, lb = _G.MerchantBuyBackItem, _G.MerchantBuyBackItemItemButton
  if last then
    if M.plates.last then setShown(M.plates.last, last:IsShown() and true or false) end
    if lb and lb.afSkinned and last:IsShown() and _G.GetBuybackItemLink and _G.GetNumBuybackItems then paint(lb, 13, GetBuybackItemLink(GetNumBuybackItems())) end
  end
end

local function after(f)
  local names = {}
  for i = 1, M.BUYBACK_PER_PAGE do names[#names + 1] = "MerchantItem" .. i end
  names[#names + 1] = "MerchantBuyBackItem"
  AFUI.NpcKit.Bare(names) -- the old slot art and name plate of each good
  for i = 1, M.BUYBACK_PER_PAGE do
    local item, b = _G["MerchantItem" .. i], _G["MerchantItem" .. i .. "ItemButton"]
    if item then M.plates[i] = AFUI.NpcKit.Plate(f, item, 4, 3, 3, 3) end
    if b and AFUI.Bags and AFUI.Bags.SkinSlot then b.afSkinned = true; AFUI.Bags.SkinSlot(b, 37, M.CONTAINER, i) end
  end
  local last, lb = _G.MerchantBuyBackItem, _G.MerchantBuyBackItemItemButton
  if last then M.plates.last = AFUI.NpcKit.Plate(f, last, 4, 3, 3, 3) end
  if lb and AFUI.Bags and AFUI.Bags.SkinSlot then lb.afSkinned = true; AFUI.Bags.SkinSlot(lb, 37, M.CONTAINER, 13) end
  -- the footer: the coin box behind the money (the bank's)
  local bank = AFUI.Bank
  if bank and bank.CoinBox then
    M.coin = bank.CoinBox(f); M.coin:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -9, 9)
    local money = _G.MerchantMoneyFrame
    if money then money:ClearAllPoints(); money:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12); money:SetFrameLevel(f:GetFrameLevel() + 6) end
  end
  if type(_G.MerchantFrame_Update) == "function" then hooksecurefunc("MerchantFrame_Update", M.Update) end
  f:HookScript("OnShow", M.Update)
  M.Update()
end

function M.Setup()
  if M.done or not _G.MerchantFrame or not AFUI.ModuleEnabled("merchant") then return end
  M.done = true
  AFUI.RunOutOfCombat(function() M.SPEC.after = after; AFUI.NpcKit.Skin(M.SPEC) end)
end

AFUI.RegisterModule("MerchantFrame", { OnLogin = M.Setup })
