-- Forever's loot window (docs/forever-ref/video-notes/loot.md, frame 144): a small dark bronze-stud window (213 u wide), a darker title strip with the gold title "Items"
-- and a red X at its top-right corner, one 48 u row per item (a 37 u icon in a bronze frame, the item name, a small quality word at the right top for anything
-- that is not plain white), thin dividers. The client's LootFrame keeps all its behaviour (slots, paging, rolls, money, tooltips, the cursor placement of
-- "Open Loot Window at Mouse"); only art and the geometry of the rows change.
-- Names (Classic client LootFrame.xml, not in the Gethe tag's 2.5.3 subset - looked up defensively): LootFrame, LootButton1..LOOTFRAME_NUMBUTTONS (4), each with
-- IconTexture / Text / Count children ("LootButton1IconTexture", "LootButton1Text", "LootButton1Count"), button.slot / button.quality, LootFrameUpButton /
-- LootFrameDownButton (paging), LootFrame_Update(), LootFrame_Show(), CloseLoot(), GetLootSlotInfo(slot) -> icon, name, quantity, quality, locked.
-- ANIMATION (OnUpdate easing: 2.4.3 has no AnimationGroups, and OnUpdate steps identically in the specs). MEASURED vs ESTIMATED:
--   The only Forever capture of the loot window is ONE still (frame 144, 2 s sampling), so no loot animation could be timed directly.
--   Measured from the sibling window-open capture (video3/anim/win_open_t15, 0.1 s steps): Forever windows do not slide or scale; the shell
--   is there in one 0.1 s step, its contents one step later. => window fade-in 0.10 s (measured, +/-0.05).
--   ESTIMATES (typical Forever/Blizzard retail loot feel, not measured): row stagger 0.04 s, row fade 0.12 s, ease-out quad,
--   rare/epic shine sweep 0.50 s (26 u wide, once per row after its fade), pickup flash 0.15 s white on the icon, window height collapse 0.12 s
--   (exponential ease) when a row disappears (the client refills the rows in place, so the visible "slide up" is the content + the shrinking frame).
--   Close: instant (no captured Forever window shows a close animation; a hidden frame cannot fade without owning the hide - taint risk).
--   Bind-on-pickup / BoE lines, count placement and money rows: not visible in the still; the client's own row text is kept.
AFUI = AFUI or {}
local L = {}
AFUI.Loot = L

L.W, L.HEAD, L.ROW_H, L.PAD, L.ICON = 213, 34, 48, 6, 37

L.A = { OPEN = 0.10, STAGGER = 0.04, ROWFADE = 0.12, SHINE = 0.50, SHINE_W = 26, FLASH = 0.15, SLIDE = 0.12 }
local function clamp01(x) return x < 0 and 0 or (x > 1 and 1 or x) end
function L.Ease(x) x = clamp01(x); return 1 - (1 - x) * (1 - x) end
function L.WindowAlpha(t) return L.Ease(t / L.A.OPEN) end
function L.RowAlpha(i, t) return L.Ease((t - (i - 1) * L.A.STAGGER) / L.A.ROWFADE) end
-- Left edge of the shine of row i inside a row of width w, nil while it is not sweeping.
function L.ShineX(i, t, w)
  local p = (t - (i - 1) * L.A.STAGGER - L.A.ROWFADE) / L.A.SHINE
  if p < 0 or p > 1 then return nil end
  return p * (w - L.A.SHINE_W)
end
function L.Slide(cur, target, dt) return cur + (target - cur) * (1 - math.exp(-dt * 5 / L.A.SLIDE)) end
function L.FlashAlpha(t) if t >= L.A.FLASH then return 0 end return 0.8 * (1 - t / L.A.FLASH) end

-- Slot data: the fake preview list (/afui loot) or the client's.
function L.Info(slot)
  if L.fake then local d = L.fake[slot]; if d then return d[1], d[2], d[3], d[4], false end return end
  if GetLootSlotInfo then return GetLootSlotInfo(slot) end
end

-- Window height for n rows.
function L.Height(n) return L.HEAD + L.PAD + n * L.ROW_H + L.PAD end

-- The quality word of a row: nothing for common (white) items, the client's name for the rest (Poor, Uncommon, Rare, Epic ...).
function L.QualityWord(quality, names)
  if not quality or quality == 1 then return nil end
  return (names or _G)["ITEM_QUALITY" .. quality .. "_DESC"]
end

local f
local function g(n) return n and _G[n] end

local function edge(parent, layer, r, gr, b, a, inset)
  local t = parent:CreateTexture(nil, layer)
  AFUI.SetColor(t, r, gr, b, a)
  return t
end

local function skinRow(i)
  local b = g("LootButton" .. i)
  if not b or b.afLoot then return b end
  b.afLoot = true
  local P = AFUI.Professions.Kit
  local n = b:GetName()
  -- the item icon and the quest marker are textures of the button itself: hideRegions would blank them (the grey squares of round 21)
  for _, k in ipairs({ "IconTexture", "IconQuestTexture" }) do local t = g(n .. k); if t then t.afKeep = true end end
  P.hideRegions(b)
  local nt = b.GetNormalTexture and b:GetNormalTexture(); if nt then nt:SetAlpha(0) end
  -- video3-era capture (loot window, frame 144): every row is its own dark box with a 1 px lighter rim, 3 u apart; the icon sits in a thin dark-grey ring
  local rim = b:CreateTexture(nil, "BACKGROUND"); AFUI.SetColor(rim, 0.26, 0.25, 0.24, 1)
  rim:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -1); rim:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 2)
  local row = b:CreateTexture(nil, "BORDER"); AFUI.SetColor(row, 0.075, 0.07, 0.07, 1)
  row:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -2); row:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 3)
  b.afFrame = edge(b, "BORDER", 0.3, 0.28, 0.26, 1) -- the thin ring round the icon
  b.afFrame:SetWidth(L.ICON + 2); b.afFrame:SetHeight(L.ICON + 2); b.afFrame:SetPoint("LEFT", b, "LEFT", 6, 0)
  local icon = g(n .. "IconTexture")
  if icon then
    icon:ClearAllPoints(); icon:SetWidth(L.ICON); icon:SetHeight(L.ICON); icon:SetPoint("CENTER", b.afFrame, "CENTER", 0, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:SetDrawLayer("ARTWORK"); icon:SetAlpha(1); icon:Show() -- above our ring (BORDER, created after the client's icon)
  end
  local text = g(n .. "Text")
  if text then text:ClearAllPoints(); text:SetPoint("LEFT", b.afFrame, "RIGHT", 12, 0); text:SetPoint("RIGHT", b, "RIGHT", -8, 0); text:SetJustifyH("LEFT") end
  b.afTagBg = b:CreateTexture(nil, "ARTWORK"); AFUI.SetColor(b.afTagBg, 0.04, 0.035, 0.04, 0.9) -- the "Poor" label: a tiny white word on a dark tag at the row's top right
  b.afTagBg:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -2); b.afTagBg:SetWidth(44); b.afTagBg:SetHeight(12)
  b.afTag = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.afTag:SetPoint("CENTER", b.afTagBg, "CENTER", 0, 0)
  do local font = b.afTag:GetFont(); if font then b.afTag:SetFont(font, 8, "") end end
  AFUI.SetButtonAtlas(b, { nil, nil, "professions_recipe_hover" }, 0.5)
  -- quality gradient behind the row (green and better), the shine strip and the pickup flash
  b.afGrad = b:CreateTexture(nil, "BORDER"); AFUI.SetColor(b.afGrad, 1, 1, 1, 1)
  b.afGrad:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -2); b.afGrad:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 3); b.afGrad:Hide()
  b.afShine = b:CreateTexture(nil, "OVERLAY"); AFUI.SetColor(b.afShine, 1, 1, 1, 0.35)
  b.afShine:SetWidth(L.A.SHINE_W); b.afShine:SetHeight(L.ROW_H - 6); b.afShine:Hide()
  if b.afShine.SetBlendMode then b.afShine:SetBlendMode("ADD") end
  b.afFlash = b:CreateTexture(nil, "OVERLAY"); AFUI.SetColor(b.afFlash, 1, 1, 1, 0)
  b.afFlash:SetAllPoints(b.afFrame); b.afFlash:Hide()
  if b.HookScript then b:HookScript("OnClick", function(self) if not L.fake then self.afFlashT = 0; L.Kick() end end) end
  return b
end

-- The row's icon: GetLootSlotInfo's texture (coin rows included), else the one the client set, else the question mark; the ring takes the quality colour.
function L.PaintIcon(b)
  local icon = g(b:GetName() .. "IconTexture")
  if not icon then return end
  local tex, quality
  if b.slot then tex, quality = L.Info(b.slot), select(4, L.Info(b.slot)) end
  AFUI.SetIcon(icon, tex or (icon.GetTexture and icon:GetTexture()))
  icon:SetVertexColor(1, 1, 1); icon:Show()
  local c = quality and quality > 1 and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
  if c and b.afGrad then
    b.afGrad:Show(); AFUI.SetColor(b.afGrad, c.r, c.g, c.b, 0.22)
    if b.afGrad.SetGradientAlpha then b.afGrad:SetGradientAlpha("HORIZONTAL", c.r, c.g, c.b, 0.4, c.r, c.g, c.b, 0) end
  elseif b.afGrad then b.afGrad:Hide() end
  if quality and quality >= 3 then b.afShineOn = true else b.afShineOn = false; if b.afShine then b.afShine:Hide() end end
  if c then AFUI.SetColor(b.afFrame, c.r, c.g, c.b, 1) else AFUI.SetColor(b.afFrame, 0.3, 0.28, 0.26, 1) end
end

-- Fake preview: fill the client's own row widgets from L.fake (they are made click-proof while it shows).
local function paintFake(b, d)
  local n = b:GetName()
  local t, c = g(n .. "Text"), g(n .. "Count")
  if t then t:SetText(d[2]); local q = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[d[4]]; if q then t:SetTextColor(q.r, q.g, q.b) end end
  if c then if d[3] and d[3] > 1 then c:SetText(d[3]); c:Show() else c:Hide() end end
end

function L.Layout()
  if not f then return end
  local shown = 0
  for i = 1, _G.LOOTFRAME_NUMBUTTONS or 4 do
    local b = skinRow(i)
    if b and L.fake then
      if L.fake[i] then b.slot = i; b:Show(); b:EnableMouse(false); paintFake(b, L.fake[i]) else b:Hide() end
    end
    if b and b:IsShown() then
      shown = shown + 1
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", f, "TOPLEFT", L.PAD + 2, -(L.HEAD + L.PAD + (shown - 1) * L.ROW_H))
      b:SetWidth(L.W - 2 * (L.PAD + 2)); b:SetHeight(L.ROW_H)
      local word = b.slot and L.QualityWord(select(4, L.Info(b.slot)))
      b.afTag:SetText(word or ""); if word then b.afTagBg:Show() else b.afTagBg:Hide() end
      L.PaintIcon(b)
    end
  end
  L.H = L.Height(math.max(shown, 1))
  if not L.h or not f:IsShown() or not L.t then L.h = L.H end
  f:SetWidth(L.W); f:SetHeight(L.h)
  if f.panel then f.panel.Resize(L.W, L.h) end
  local up, down = g("LootFrameUpButton"), g("LootFrameDownButton")
  if up then up:ClearAllPoints(); up:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8) end
  if down then down:ClearAllPoints(); down:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 8) end
end

-- The animation driver: one OnUpdate on a helper frame, runs only while something moves.
local ticker
local function tick(_, dt)
  L.t = (L.t or 0) + dt
  local busy = L.t < L.A.OPEN + L.A.STAGGER * 4 + L.A.ROWFADE + L.A.SHINE
  f:SetAlpha(L.WindowAlpha(L.t))
  if L.h and math.abs(L.h - L.H) > 0.5 then
    L.h = L.Slide(L.h, L.H, dt); f:SetHeight(L.h); if f.panel then f.panel.Resize(L.W, L.h) end; busy = true
  elseif L.h ~= L.H then L.h = L.H; f:SetHeight(L.h) end
  local k = 0
  for i = 1, _G.LOOTFRAME_NUMBUTTONS or 4 do
    local b = g("LootButton" .. i)
    if b and b:IsShown() and b.afShine then
      k = k + 1
      b:SetAlpha(L.RowAlpha(k, L.t))
      local x = b.afShineOn and L.ShineX(k, L.t, b:GetWidth())
      if x then b.afShine:ClearAllPoints(); b.afShine:SetPoint("LEFT", b, "LEFT", x, 0); b.afShine:Show() else b.afShine:Hide() end
      if b.afFlashT then
        b.afFlashT = b.afFlashT + dt
        local a = L.FlashAlpha(b.afFlashT)
        if a > 0 then AFUI.SetColor(b.afFlash, 1, 1, 1, a); b.afFlash:Show(); busy = true else b.afFlash:Hide(); b.afFlashT = nil end
      end
    end
  end
  if not busy then ticker:SetScript("OnUpdate", nil) end
end
function L.Kick()
  if not f then return end
  ticker = ticker or CreateFrame("Frame")
  ticker:SetScript("OnUpdate", tick)
end
function L.Play() L.t = 0; if f then f:SetAlpha(0) end; L.Kick() end

-- /afui loot: a fake window (uncommon stack, rare, epic, money: the client has only 4 row buttons) so the animations can be watched without a kill. Rows ignore clicks.
function L.Fake()
  if not f then return end
  f:Hide() -- before L.fake is set: OnHide clears it
  L.fake = {
    { "Interface\\Icons\\INV_Misc_Herb_07", "Peacebloom", 3, 2 },
    { "Interface\\Icons\\INV_Sword_27", "Blade of the Rare", 1, 3 },
    { "Interface\\Icons\\INV_Misc_Gem_Opal_01", "Opal of the Epic", 1, 4 },
    { "Interface\\Icons\\INV_Misc_Gem_01", "12 Silver 34 Copper", 1, 1 },
  }
  f:Show()
  L.Layout()
  L.Play()
end

local function setup()
  f = _G.LootFrame
  local P, W = AFUI.Professions and AFUI.Professions.Kit, AFUI.EditModeWidgets
  if not f or f.afLootFrame or not P or not W then return end
  f.afLootFrame = true
  P.hideRegions(f)
  for _, n in ipairs({ "LootFrameCloseButton", "LootCloseButton", "LootFramePortraitOverlay" }) do
    local o = g(n); if o then o:SetAlpha(0); if o.EnableMouse then o:EnableMouse(false) end end
  end
  local panel = W.Panel(nil, L.W, L.Height(3))
  panel:SetParent(f); panel:SetFrameStrata(f:GetFrameStrata()); panel:SetFrameLevel(f:GetFrameLevel()); panel:EnableMouse(false); AFUI.SetColor(panel.bg, 0.11, 0.105, 0.105, 0.97) -- the capture's body between the rows is a mid dark grey (#1d1b1c), not near-black
  panel:ClearAllPoints(); panel:SetAllPoints(f); panel:Show()
  f.panel = panel
  local strip = f:CreateTexture(nil, "BORDER"); AFUI.SetColor(strip, 0.13, 0.09, 0.05, 1) -- the title strip is dark brown (#21180c) with a bronze foot line
  strip:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8); strip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8); strip:SetHeight(L.HEAD - 10)
  local foot = f:CreateTexture(nil, "ARTWORK"); AFUI.SetColor(foot, 0.45, 0.34, 0.17, 1); foot:SetHeight(1)
  foot:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT"); foot:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT")
  for _, r in ipairs({ f:GetRegions() }) do if r.GetObjectType and r:GetObjectType() == "FontString" then r:Hide() end end -- the client's own "Items" heading
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); title:SetPoint("CENTER", strip, "CENTER", 0, 0); title:SetText("Items")
  local close = W.CloseButton(f, function() if CloseLoot then CloseLoot() else f:Hide() end end)
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
  for _, fn in ipairs({ "LootFrame_Update", "LootFrame_Show" }) do
    if type(_G[fn]) == "function" then hooksecurefunc(fn, L.Layout) end
  end
  f:HookScript("OnShow", L.Layout)
  f:HookScript("OnShow", function() L.Play() end)
  f:HookScript("OnHide", function()
    if L.fake then L.fake = nil; for i = 1, _G.LOOTFRAME_NUMBUTTONS or 4 do local b = g("LootButton" .. i); if b then b:EnableMouse(true) end end end
    L.h = nil
  end)
  L.Layout()
end

L.Setup = setup
AFUI.RegisterModule("Loot", { OnLogin = function() AFUI.RunOutOfCombat(setup) end })

if AFUI.Slash and AFUI.Slash.Register then AFUI.Slash.Register("loot", function() L.Fake() end, "opens a fake loot window to preview its animations", "/afui loot") end
