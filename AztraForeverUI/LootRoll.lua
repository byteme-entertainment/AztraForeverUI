-- Forever's Group Loot roll windows (GroupLootFrame1..4): the dark box with the grey-gold rim of Dialogs.lua, the item icon in a ring of its quality colour, a flat bronze
-- timer bar, and a dark plate under each Need / Greed / Disenchant / Pass button. SKIN ONLY: the client keeps the rolling (the buttons call RollOnLoot themselves), the
-- timer, the item tooltip, the item name and its quality colour and the hiding after a roll; nothing is replaced, moved or shown from here, so it is safe in combat.
-- The roll result is the client's own: the number under a button and the chat line ("You rolled ..."); the frame hides itself when you roll.
-- Names (GroupLootFrame.xml, both clients; later clients also expose them as fields): GroupLootFrameN with Timer (+ TimerBackground), IconFrame / IconFrameIcon /
-- IconFrameBorder, Name, RollButton or NeedButton, GreedButton, DisenchantButton, PassButton; GetLootRollItemInfo(frame.rollID) -> texture, name, count, quality.
-- Setting "lootRollRestyle" (General page, default on); read once at login, so switching it off takes effect after /reload.
AFUI = AFUI or {}
local R = {}
AFUI.LootRoll = R

R.RING = { 0.3, 0.28, 0.26 } -- the ring of a common item (the loot window's, Loot.lua)
R.BAR = { 0.85, 0.62, 0.32 } -- the timer fill: Forever's bronze (WinKit K.BRONZE)
R.BUTTONS = { { "NeedButton", "RollButton" }, { "GreedButton" }, { "DisenchantButton" }, { "PassButton" } }
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function g(n) return n and _G[n] end
function R.Enabled() return AFUI.ModuleEnabled("lootroll") end -- Settings > Windows (useLootRoll; the old lootRollRestyle setting still counts)

-- A part of a roll frame: its field (clients that name it by parentKey) or its global name (GroupLootFrameN .. suffix).
local function part(f, key, suffix)
  local v = rawget(f, key)
  if v then return v end
  local n = f:GetName()
  return n and _G[n .. (suffix or key)]
end

-- The ring colour of an item quality (grey for common and unknown).
function R.RingColor(quality)
  local c = quality and quality > 1 and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
  if c then return c.r, c.g, c.b end
  return R.RING[1], R.RING[2], R.RING[3]
end

function R.Paint(f)
  if not f.afRoll or not f.rollID or not _G.GetLootRollItemInfo then return end
  local _, _, _, quality = GetLootRollItemInfo(f.rollID)
  local r, gr, b = R.RingColor(quality)
  AFUI.SetColor(f.afRoll.ring, r, gr, b, 1)
end

function R.Skin(i)
  local f = g("GroupLootFrame" .. i)
  if not f or f.afRoll then return f end
  local D = AFUI.Dialogs
  if D then D.ClearBackdrop(f); D.Rim(f) end
  local a = {}
  f.afRoll = a
  local iconFrame, icon = part(f, "IconFrame"), part(f, "Icon", "IconFrameIcon")
  local border = part(f, "Border", "IconFrameBorder")
  if border and border.SetAlpha then border:SetAlpha(0) end -- the client's quality frame: the ring replaces it
  a.ring = (iconFrame or f):CreateTexture(nil, "BACKGROUND")
  AFUI.SetColor(a.ring, R.RING[1], R.RING[2], R.RING[3], 1)
  if icon then a.ring:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2); a.ring:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  else a.ring:Hide() end
  local bar = part(f, "Timer")
  if bar and bar.SetStatusBarTexture then
    bar:SetStatusBarTexture(WHITE); bar:SetStatusBarColor(R.BAR[1], R.BAR[2], R.BAR[3])
    local bg = part(f, "Background", "TimerBackground")
    if bg and bg.GetObjectType and bg:GetObjectType() == "Texture" then AFUI.SetColor(bg, 0.02, 0.02, 0.02, 0.9) end
  end
  if D then
    for _, names in ipairs(R.BUTTONS) do
      local b
      for _, k in ipairs(names) do b = b or part(f, k) end
      if b then D.Rim(b) end
    end
  end
  if f.HookScript then f:HookScript("OnShow", R.Paint) end
  R.Paint(f)
  return f
end

local done
function R.Setup()
  if done or not R.Enabled() then return end
  done = true
  for i = 1, _G.NUM_GROUP_LOOT_FRAMES or 4 do R.Skin(i) end
end

AFUI.RegisterModule("LootRoll", { OnLogin = R.Setup })
