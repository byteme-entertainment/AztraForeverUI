-- Vendor helpers: a "Sell All Junk Items" button on the merchant window (the client's own window and art stay; only our button is added) and the
-- optional auto sell on opening. It sells every grey (quality 0) item that has a vendor price, one UseContainerItem per 0.1 s, stops when the
-- merchant closes or a bag slot no longer holds what was planned, and prints "Sold N junk items for X". Junk only, so nothing is asked.
AFUI = AFUI or {}
local V = {}
AFUI.VendorTools = V

local MAX_BAG = 4
V.PACE = 0.1
V.open = false -- MERCHANT_SHOW / MERCHANT_CLOSED (the window may not be shown yet when the event reaches us)

local function on(key) return AFUI.QoL and AFUI.QoL.Get(key) end

-- Everything sellable that is grey, in bag order: { entries = { { bag, slot, link, count, value } }, items = pieces, total = copper }.
-- The junk rule, pure: slots = { { bag, slot, link, count, quality, price } } in bag order. Only grey (quality 0) items a vendor pays for (price > 0); a stack counts
-- price x count. White and better never, a grey with no price cannot be sold anyway.
function V.Pick(slots)
  local out = { entries = {}, items = 0, total = 0 }
  for _, s in ipairs(slots) do
    if s.quality == 0 and s.link and (s.price or 0) > 0 and not s.noSell then -- noSell: the Don't sell mark (Bags.NoSell)
      local count = s.count or 1
      out.entries[#out.entries + 1] = { bag = s.bag, slot = s.slot, link = s.link, count = count, value = s.price * count }
      out.items, out.total = out.items + count, out.total + s.price * count
    end
  end
  return out
end

function V.Scan()
  if not (_G.GetContainerNumSlots and _G.GetContainerItemInfo and _G.GetContainerItemLink and _G.GetItemInfo) then return V.Pick({}) end
  local slots = {}
  for bag = 0, MAX_BAG do
    for slot = 1, (GetContainerNumSlots(bag) or 0) do
      local _, count, _, quality = GetContainerItemInfo(bag, slot)
      if quality == 0 then
        local link = GetContainerItemLink(bag, slot)
        slots[#slots + 1] = { bag = bag, slot = slot, link = link, count = count, quality = quality, price = link and select(11, GetItemInfo(link)),
          noSell = link and AFUI.Bags and AFUI.Bags.NoSell and AFUI.Bags.NoSell.Is(link) or false }
      end
    end
  end
  return V.Pick(slots)
end

-- "12g 34s 56c" with the client's coin icons (GetCoinTextureString), plain coloured letters where the client has none
function V.Coins(copper)
  if _G.GetCoinTextureString then return GetCoinTextureString(copper) end
  return AFUI.QoL.CoinChat(copper)
end

function V.Summary(items, total)
  return string.format("Sold %d junk item%s for %s", items, items == 1 and "" or "s", V.Coins(total))
end

---------------------------------------------------------------- the run
local run
local runner = CreateFrame("Frame")

local function finish(why)
  runner:SetScript("OnUpdate", nil)
  local r = run
  run = nil
  V.last = why
  if r and r.sold > 0 then
    AFUI.Print(V.Summary(r.sold, r.total))
    if why ~= "done" then AFUI.Print("Selling stopped: " .. (why == "closed" and "the merchant window closed." or "the bags changed.")) end
  end
  V.Update()
end

function V.Step(_, dt)
  if not run then runner:SetScript("OnUpdate", nil); return end
  if not V.open then return finish("closed") end
  run.wait = run.wait - (dt or 0)
  if run.wait > 0 then return end
  local e = run.list[run.i]
  if not e then return finish("done") end
  -- the slot must still hold what we planned to sell (the player moved something, or a sale did not go through)
  if GetContainerItemLink(e.bag, e.slot) ~= e.link or (_G.CursorHasItem and CursorHasItem()) then return finish("changed") end
  if AFUI.Bags and AFUI.Bags.NoSell.Is(e.link) then run.i = run.i + 1; return end -- marked while the run was going
  UseContainerItem(e.bag, e.slot)
  run.sold, run.total = run.sold + e.count, run.total + e.value
  run.i, run.wait = run.i + 1, V.PACE
  if not run.list[run.i] then finish("done") end
end

-- Starts selling. Returns true when a run started.
function V.Start(auto)
  if run or not V.open then return false end
  if _G.CursorHasItem and CursorHasItem() then return false end
  local s = V.Scan()
  if #s.entries == 0 then
    if not auto then AFUI.Print("No junk items to sell.") end
    return false
  end
  run = { list = s.entries, i = 1, sold = 0, total = 0, wait = 0 }
  runner:SetScript("OnUpdate", V.Step)
  V.Update()
  return true
end
function V.Running() return run ~= nil end

---------------------------------------------------------------- the button
V.SIZE = 28 -- Forever's red button (WinKit.button, the 28 u height)
V.ANCHOR = { "TOPRIGHT", "MerchantFrame", "TOPRIGHT", -72, -27 } -- left of the client's close button, under the title strip

local btn
function V.Button() return btn end

function V.MakeButton(parent)
  if btn or not parent then return btn end
  btn = CreateFrame("Button", "AFUI_SellJunkButton", parent)
  btn:SetWidth(V.SIZE); btn:SetHeight(V.SIZE)
  local a = V.ANCHOR
  btn:SetPoint(a[1], _G[a[2]] or parent, a[3], a[4], a[5])
  btn:SetFrameLevel(parent:GetFrameLevel() + 8)
  local K = AFUI.WinKit
  if K and K.button then K.button(btn, V.SIZE, V.SIZE) end
  local icon = btn:CreateTexture(nil, "OVERLAY")
  AFUI.SetAtlas(icon, "bags-icon-junk"); icon:SetWidth(20); icon:SetHeight(20); icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
  btn.icon = icon
  btn:SetScript("OnClick", function() V.Start(false) end)
  btn:SetScript("OnEnter", function(self)
    local s = V.Scan()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(_G.SELL_ALL_JUNK_ITEMS or "Sell All Junk Items", 1, 1, 1)
    if #s.entries > 0 then
      GameTooltip:AddLine(s.items .. " junk item" .. (s.items == 1 and "" or "s"), 0.8, 0.8, 0.8)
      GameTooltip:AddLine("Value: " .. AFUI.QoL.CoinText(s.total), 1, 1, 1)
    else
      GameTooltip:AddLine("Nothing to sell.", 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return btn
end

-- Shown with the setting on; enabled when there is junk to sell and no run is going.
function V.Update()
  if not btn then return end
  if not on("sellJunkButton") then btn:Hide(); return end
  btn:Show()
  local can = not run and #V.Scan().entries > 0
  if can then btn:Enable() else btn:Disable() end
  if btn.icon.SetDesaturated then btn.icon:SetDesaturated(not can) end
  btn.icon:SetAlpha(can and 1 or 0.5)
end

function V.Setup()
  if _G.MerchantFrame then V.MakeButton(MerchantFrame) end
  if AFUI.QoL then AFUI.QoL.Watch("sellJunkButton", V.Update) end
  V.Update()
end

AFUI.On("MERCHANT_SHOW", function()
  if not AFUI.ModuleEnabled("vendortools") then return end -- Sell Junk switched off (Settings > Windows): no button, no automatic selling
  V.open = true
  V.Update()
  if on("autoSellJunk") then V.Start(true) end
end)
AFUI.On("MERCHANT_CLOSED", function() V.open = false; if run then finish("closed") end; V.Update() end)
AFUI.On("BAG_UPDATE", function() if V.open then V.Update() end end)

AFUI.RegisterModule("VendorTools", { OnLogin = V.Setup })
