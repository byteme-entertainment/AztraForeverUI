-- Third-party addons (WeakAuras, DBM, Details, Masque, OmniCC, Questie, Prat, TidyPlates / Plater, ClassicCastbars, UI-pack auras ...) anchor to the client's
-- named HUD frames, read their geometry, hook their scripts or walk their children. We replace the HUD with our own frames and kill the client's, so a killed
-- frame left where it was would send those anchors to a stale spot. Every commonly used name keeps a LIVE stand-in that matches OUR visible frame.
--
-- Modes:
--   track   the client's frame stays killed (hidden holder parent, as Kill left it) but is anchored TOPLEFT / BOTTOMRIGHT to our frame (a bar or portrait:
--           to its window inside our frame) and scaled to our effective scale. Anchors follow our frame by themselves (Edit Mode move, profile switch,
--           resolution); a re-sync is needed only when someone re-anchors the stand-in or our scale / size changes (hooks, no OnUpdate).
--   ghost   track, and the frame is also SHOWN at alpha 0, mouse off, under UIParent: IsShown / IsVisible answer true for addons that test their anchor.
--           Only where the client's frame has no event, no mouse child and no protected child (CastingBarFrame). Alpha is held at 0.
--   real    the client's frame IS the visible one (we restyle and reparent it): nothing is moved here, /afui anchors only reports it.
--   native  the client's own frame, untouched, no counterpart of ours.
--   child   a child that follows its (tracked) frame; reported only.
-- Why unit frames, action bars and auras are NOT ghosts: their children are mouse-enabled buttons (aura buttons, action buttons, pet frames) that Blizzard code
-- shows again; shown at alpha 0 they would catch the mouse over our frames. IsShown there follows the client's own logic (true while its unit exists),
-- IsVisible stays false (the holder is hidden). Anchoring, size, scale, GetPoint and child iteration all work.
--
-- frame (client)                                                   -> ours                                   mode
--   PlayerFrame / TargetFrame / PetFrame / PartyMemberFrame1-4      -> AFUI_<Unit>Frame                        track
--   TargetFrameToT (2.5.3) / TargetofTargetFrame (2.4.3)            -> AFUI_TargettargetFrame                  track
--   <Unit>HealthBar / <Unit>ManaBar (all of the above)              -> the bar windows inside our frame        track
--   PlayerPortrait TargetFramePortrait PetPortrait PartyMemberNPortrait ToT portrait -> our portrait ring     track (region)
--   PartyMemberFrameNPetFrame (+ HealthBar)                         -> a strip under our party portrait        track (no counterpart: parked)
--   FocusFrame                                                      -> none (the client's own)                 native
--   CastingBarFrame                                                 -> AFUI_CastBar_player                     ghost
--   TargetFrameSpellBar                                             -> AFUI_CastBar_target                     track
--   BuffFrame, TemporaryEnchantFrame, ConsolidatedBuffs             -> AFUI_Buffs                              track
--   BuffButton1-32 / DebuffButton1-16 / TempEnchant1-3              -> our aura button of that slot            track
--   MinimapCluster                                                  -> AFUI_MinimapFrame                       track
--   MinimapBackdrop                                                 -> AFUI_MinimapRing                        track
--   Minimap MiniMapTracking MiniMapMailFrame MiniMapBattlefieldFrame GameTimeFrame (+ LFG / meeting stone) -> themselves  real
--   ChatFrame1-10, ChatFrameNEditBox, ChatFrameNTab, GeneralDockManager, ChatFrameChannelButton  -> themselves   real
--   MainMenuBar, MainMenuBarArtFrame, BonusActionBarFrame           -> AFUI_MainBar                            track
--   MultiBarBottomLeft / BottomRight / Right / Left                 -> AFUI_BottomLeftBar / BottomRightBar / RightBar / Right2Bar   track
--   ActionButton1-12, MultiBar*Button1-12                           -> AFUI_MainButtonN / BottomLeft / BottomRight / Right / Right2   track
--   PetActionBarFrame, ShapeshiftBarFrame, StanceBarFrame, PossessBarFrame -> AFUI_PetBar / StanceBar / PossessBar    track
--   PetActionButton1-10, ShapeshiftButton1-10, StanceButton1-10, PossessButton1-2  -> themselves (reparented)   real
--   micro buttons, MainMenuBarBackpackButton, CharacterBag0-3Slot, KeyRingButton  -> themselves (reparented)     real
--   MainMenuExpBar, MainMenuBarMaxLevelBar / ReputationWatchBar     -> AFUI_StatusBar / AFUI_StatusBar2        track
--   QuestWatchFrame, WatchFrame                                     -> AFUI_ObjectiveTracker (alive, alpha 0)  track
--   QuestWatchLine1-30                                              -> follow QuestWatchFrame                  child
--   DurabilityFrame, MirrorTimer1, RaidWarningFrame (Edit Mode moves the real ones), UIErrorsFrame, RaidBossEmoteFrame, ZoneTextFrame,
--   SubZoneTextFrame, WorldFrame, GameTooltip (default anchor = AFUI_HudTooltip), LootFrame, UIParent  -> themselves   real / native
--   nameplates: plate.UnitFrame, .healthBar, .castBar (per plate, NAME_PLATE_UNIT_ADDED) -> our skin, its bar, its cast box   track
--
-- /afui anchors [all]  reports each group (every frame with "all"); AFUI.AnchorFor(name) answers our visible frame; AFUI.AnchorNames() the covered names.
local AFUI = AFUI
local AC = { entries = {}, byName = {}, pending = {}, watchers = {}, hooked = {}, methods = {}, plates = {} }
AFUI.AnchorCompat = AC

local TOL = 1 -- UI units a stand-in may be off our frame before it is a mismatch
local syncing = false

local function G(n) return function() return _G[n] end end

-- Entries of a HUD piece the player switched back to the client's own (Settings > Windows) are left alone: the client's frame is the visible one.
local TAG_GROUP = { tracker = "tracker", buffs = "buffs", minimap = "minimap" }
function AC.GroupOn(e)
  local gid = TAG_GROUP[e.tag]
  return not gid or AFUI.ModuleEnabled(gid)
end

local function add(mode, group, tag, name, ours)
  local e = { mode = mode, group = group, tag = tag, name = name, ours = ours }
  AC.entries[#AC.entries + 1] = e
  AC.byName[name] = e
  return e
end

---------------------------------------------------------------- what is ours
local function unit(key) return function() local u = AFUI.Units and AFUI.Units[key]; return u and u.frame end end
-- A window (x0, y0, x1, y1; y down from the TOPLEFT) inside a unit frame: the bar interiors and the portrait ring of the current geometry.
local function unitWin(key, kind)
  return function()
    local u = AFUI.Units and AFUI.Units[key]
    local f, g = u and u.frame, u and u.geo
    if not f then return end
    if not g then return f end
    if kind == "portrait" then
      local p = g.portrait
      if not p then return f end -- portrait off: the whole frame
      return f, { p[1], -p[2], p[1] + p[3], -p[2] + p[3] }
    end
    local b = (u.rareBars or g)[kind]
    if not (b and b.win) then return f end
    return f, b.win
  end
end
local PET_STRIP = { 8, 40, 70, 52 } -- party pets have no frame of ours: a strip under the party portrait
local function partyPet(i) return function() local u = AFUI.Units and AFUI.Units["party" .. i]; if u and u.frame then return u.frame, PET_STRIP end end end

---------------------------------------------------------------- unit frames
local UNITS = {
  { key = "player", frame = { "PlayerFrame" }, hp = { "PlayerFrameHealthBar" }, mp = { "PlayerFrameManaBar" }, portrait = { "PlayerPortrait" } },
  { key = "target", frame = { "TargetFrame" }, hp = { "TargetFrameHealthBar" }, mp = { "TargetFrameManaBar" }, portrait = { "TargetFramePortrait" } },
  { key = "targettarget", frame = { "TargetFrameToT", "TargetofTargetFrame" }, hp = { "TargetFrameToTHealthBar", "TargetofTargetHealthBar" },
    mp = { "TargetFrameToTManaBar", "TargetofTargetManaBar" }, portrait = { "TargetFrameToTPortrait", "TargetofTargetPortrait" } },
  { key = "pet", frame = { "PetFrame" }, hp = { "PetFrameHealthBar" }, mp = { "PetFrameManaBar" }, portrait = { "PetPortrait" } },
}
for i = 1, 4 do
  local n = "PartyMemberFrame" .. i
  UNITS[#UNITS + 1] = { key = "party" .. i, frame = { n }, hp = { n .. "HealthBar" }, mp = { n .. "ManaBar" }, portrait = { n .. "Portrait" }, party = i }
end
for _, d in ipairs(UNITS) do
  local tag = d.party and "party" or d.key
  local label = d.party and "PartyMemberFrameN" or d.frame[1]
  for _, n in ipairs(d.frame) do add("track", label, tag, n, unit(d.key)) end
  for _, n in ipairs(d.hp) do add("track", label .. " health bar", tag, n, unitWin(d.key, "hp")) end
  for _, n in ipairs(d.mp) do add("track", label .. " mana bar", tag, n, unitWin(d.key, "mp")) end
  for _, n in ipairs(d.portrait) do add("track", label .. " portrait", tag, n, unitWin(d.key, "portrait")).region = true end
  if d.party then
    local pn = d.frame[1]
    add("track", "PartyMemberFrameNPetFrame", tag, pn .. "PetFrame", partyPet(d.party))
    add("track", "PartyMemberFrameNPetFrame", tag, pn .. "PetFrameHealthBar", partyPet(d.party))
  end
end
add("native", "FocusFrame", "native", "FocusFrame")

---------------------------------------------------------------- cast bars, buffs
add("ghost", "CastingBarFrame", "cast", "CastingBarFrame", G("AFUI_CastBar_player"))
add("track", "TargetFrameSpellBar", "cast", "TargetFrameSpellBar", G("AFUI_CastBar_target"))
for _, n in ipairs({ "BuffFrame", "TemporaryEnchantFrame", "ConsolidatedBuffs" }) do add("track", n, "buffs", n, G("AFUI_Buffs")) end

-- The aura buttons: our pool is laid out by anchors (slot n of a filter), the weapon enchants take the first slots of HELPFUL.
local function enchants()
  local p, n = AFUI.BuffPool, 0
  if p then for i = 1, #p.HELPFUL do local b = p.HELPFUL[i]; if b.enchant and b:IsShown() then n = n + 1 end end end
  return n
end
local function aura(filter, slot, plain, enchant)
  return function()
    local p = AFUI.BuffPool
    local b = p and p[filter] and p[filter][enchant and slot or slot + (plain and 0 or enchants())]
    if enchant and b and not (b.enchant and b:IsShown()) then b = nil end
    return b or _G.AFUI_Buffs
  end
end
for i = 1, 32 do add("track", "BuffButton1-32", "buffs", "BuffButton" .. i, aura("HELPFUL", i)) end
for i = 1, 16 do add("track", "DebuffButton1-16", "buffs", "DebuffButton" .. i, aura("HARMFUL", i, true)) end
for i = 1, 3 do add("track", "TempEnchant1-3", "buffs", "TempEnchant" .. i, aura("HELPFUL", i, true, true)) end
function AC.BuffSignature() -- what decides which of our buttons a stand-in follows
  local p = AFUI.BuffPool
  return p and (enchants() .. ":" .. #p.HELPFUL .. ":" .. #p.HARMFUL) or ""
end

---------------------------------------------------------------- minimap
add("track", "MinimapCluster", "minimap", "MinimapCluster", G("AFUI_MinimapFrame"))
add("track", "MinimapBackdrop", "minimap", "MinimapBackdrop", G("AFUI_MinimapRing"))
for _, n in ipairs({ "Minimap", "MiniMapTracking", "MiniMapTrackingFrame", "MiniMapMailFrame", "MiniMapBattlefieldFrame", "MiniMapMeetingStoneFrame",
  "MiniMapLFGFrame", "GameTimeFrame" }) do add("real", "Minimap and its buttons", "minimap", n) end

---------------------------------------------------------------- chat
for i = 1, 10 do
  add("real", "ChatFrame1-10", "chat", "ChatFrame" .. i)
  add("real", "ChatFrameNEditBox", "chat", "ChatFrame" .. i .. "EditBox")
  add("real", "ChatFrameNTab", "chat", "ChatFrame" .. i .. "Tab")
end
add("real", "GeneralDockManager", "chat", "GeneralDockManager")
add("real", "ChatFrameChannelButton", "chat", "ChatFrameChannelButton")

---------------------------------------------------------------- action bars
local BARS = { { "MultiBarBottomLeft", "BottomLeft" }, { "MultiBarBottomRight", "BottomRight" }, { "MultiBarRight", "Right" }, { "MultiBarLeft", "Right2" } }
for _, n in ipairs({ "MainMenuBar", "MainMenuBarArtFrame", "BonusActionBarFrame" }) do add("track", n, "bars", n, G("AFUI_MainBar")) end
for _, d in ipairs(BARS) do add("track", d[1], "bars", d[1], G("AFUI_" .. d[2] .. "Bar")) end
for i = 1, 12 do add("track", "ActionButton1-12", "bars", "ActionButton" .. i, G("AFUI_MainButton" .. i)) end
for _, d in ipairs(BARS) do
  for i = 1, 12 do add("track", d[1] .. "Button1-12", "bars", d[1] .. "Button" .. i, G("AFUI_" .. d[2] .. "Button" .. i)) end
end
add("track", "PetActionBarFrame", "bars", "PetActionBarFrame", G("AFUI_PetBar"))
add("track", "ShapeshiftBarFrame", "bars", "ShapeshiftBarFrame", G("AFUI_StanceBar"))
add("track", "StanceBarFrame", "bars", "StanceBarFrame", G("AFUI_StanceBar"))
add("track", "PossessBarFrame", "bars", "PossessBarFrame", G("AFUI_PossessBar")).optional = true -- a bar of ours only where the client has PossessButton1 (Compat.lua)
for i = 1, 10 do
  add("real", "PetActionButton1-10", "bars", "PetActionButton" .. i)
  add("real", "ShapeshiftButton1-10", "bars", "ShapeshiftButton" .. i)
  add("real", "StanceButton1-10", "bars", "StanceButton" .. i)
end
for i = 1, 2 do add("real", "PossessButton1-2", "bars", "PossessButton" .. i) end
for _, n in ipairs({ "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "QuestLogMicroButton", "SocialsMicroButton", "LFGMicroButton",
  "MainMenuMicroButton", "HelpMicroButton", "WorldMapMicroButton", "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
  "CharacterBag2Slot", "CharacterBag3Slot", "KeyRingButton" }) do add("real", "Micro menu and bag buttons", "bars", n) end

---------------------------------------------------------------- status bars, tracker
add("track", "MainMenuExpBar", "xp", "MainMenuExpBar", G("AFUI_StatusBar"))
add("track", "MainMenuBarMaxLevelBar", "xp", "MainMenuBarMaxLevelBar", G("AFUI_StatusBar"))
add("track", "ReputationWatchBar", "xp", "ReputationWatchBar", G("AFUI_StatusBar2"))
add("track", "QuestWatchFrame", "tracker", "QuestWatchFrame", G("AFUI_ObjectiveTracker"))
add("track", "WatchFrame", "tracker", "WatchFrame", G("AFUI_ObjectiveTracker"))
for i = 1, 30 do add("child", "QuestWatchLine1-30", "tracker", "QuestWatchLine" .. i) end

---------------------------------------------------------------- left to the client
for _, n in ipairs({ "DurabilityFrame", "MirrorTimer1", "RaidWarningFrame", "UIErrorsFrame", "RaidBossEmoteFrame", "ZoneTextFrame", "SubZoneTextFrame",
  "WorldFrame", "GameTooltip", "LootFrame", "UIParent" }) do add("native", "Client frames", "native", n) end

local SM = AFUI.SafeMeasure

---------------------------------------------------------------- geometry
local function isProtected(f)
  if f.IsProtected and f:IsProtected() then return true end
  local p = f.GetParent and f:GetParent()
  return (p and p.IsProtected and p:IsProtected()) and true or false
end

local function near(a, b) return math.abs((a or 0) - (b or 0)) < 0.01 end

-- The two points that lay `f` over `ours` (or over a window of it).
local function wanted(ours, win)
  if win then return { { "TOPLEFT", ours, "TOPLEFT", win[1], -win[2] }, { "BOTTOMRIGHT", ours, "TOPLEFT", win[3], -win[4] } } end
  return { { "TOPLEFT", ours, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", ours, "BOTTOMRIGHT", 0, 0 } }
end

local function pointsMatch(f, want)
  if AFUI.MeasureBlocked(f) then return true end -- cannot be read: never re-laid on a guess
  for i, w in ipairs(want) do
    local p, rel, rp, x, y = SM(f, "GetPoint", i)
    if p ~= w[1] or rel ~= w[2] or rp ~= w[3] or not near(x, w[4]) or not near(y, w[5]) then return false end
  end
  return SM(f, "GetPoint", #want + 1) == nil
end

-- Offsets are in the frame's own scale: a stand-in at our effective scale means the same numbers on both.
local function scaleOff(e, f, ours)
  if e.region or not (f.SetScale and f.GetEffectiveScale and ours.GetEffectiveScale) then return false end
  local a, b = SM(f, "GetEffectiveScale"), ours:GetEffectiveScale()
  return (a and b and a > 0 and b > 0 and math.abs(a / b - 1) > 0.001) and true or false
end

-- Left, bottom, width, height in UI units (the frame's own scale folded in), or nil while the frame has no rect.
local function rect(f)
  if not (f and f.GetLeft) then return end
  local l, b, r, t = SM(f, "GetLeft"), SM(f, "GetBottom"), SM(f, "GetRight"), SM(f, "GetTop")
  if not (l and b and r and t) then return end
  local s = (SM(f, "GetEffectiveScale") or 1) / (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1)
  return l * s, b * s, (r - l) * s, (t - b) * s
end

local function oursRect(ours, win)
  local l, b, w, h = rect(ours)
  if not l then return end
  if not win then return l, b, w, h end
  local s = (ours.GetEffectiveScale and ours:GetEffectiveScale() or 1) / (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1)
  local top = b + h
  return l + win[1] * s, top - win[4] * s, (win[3] - win[1]) * s, (win[4] - win[2]) * s
end

local function rectsMatch(a, b) -- nil: not known yet
  if not (a and b) then return nil end
  for i = 1, 4 do if math.abs(a[i] - b[i]) > TOL then return false end end
  return true
end

---------------------------------------------------------------- sync
local runner = CreateFrame("Frame")
AC.runner = runner
local function defer(fn) -- one run on the next frame, no standing OnUpdate
  if _G.C_Timer and C_Timer.After then return C_Timer.After(0, fn) end
  runner:SetScript("OnUpdate", function(self) self:SetScript("OnUpdate", nil); fn() end)
end

local scheduled = false
local function mark(e)
  AC.pending[e] = true
  if scheduled then return end
  scheduled = true
  defer(function() scheduled = false; AC.Flush() end)
end

-- Anything that re-anchors or rescales a stand-in (the client's UIParent_ManageFramePositions, an addon) marks it; our own writes do not.
local STANDIN_HOOKS = { "SetPoint", "ClearAllPoints", "SetAllPoints", "SetScale" }
local function hookStandin(e, f)
  if AC.hooked[f] then return end
  AC.hooked[f] = e
  for _, m in ipairs(STANDIN_HOOKS) do
    if f[m] then hooksecurefunc(f, m, function() if not syncing then mark(e) end end) end
  end
end

-- Our frame resized or rescaled (Edit Mode, a profile, the Frame Size slider): the stand-ins that lie on it are re-laid.
-- The bar a button sits on rescales the button too, so every ancestor's SetScale is watched as well.
local function watchFrame(p, e, methods)
  local list = AC.watchers[p]
  if not list then list = {}; AC.watchers[p] = list; AC.methods[p] = {} end
  for _, m in ipairs(methods) do
    local done = AC.methods[p]
    if p[m] and not done[m] then
      done[m] = true
      hooksecurefunc(p, m, function() for i = 1, #list do mark(list[i]) end end)
    end
  end
  for i = 1, #list do if list[i] == e then return end end
  list[#list + 1] = e
end
local function watch(ours, e)
  watchFrame(ours, e, { "SetScale", "SetWidth", "SetHeight" })
  local p, n = ours.GetParent and ours:GetParent(), 0
  while p and p ~= UIParent and n < 20 do
    watchFrame(p, e, { "SetScale" })
    p, n = p.GetParent and p:GetParent(), n + 1
  end
end

local function holdAlpha(f)
  hooksecurefunc(f, "SetAlpha", function(self, a) if a ~= 0 then self:SetAlpha(0) end end)
end

local function becomeGhost(e, f)
  e.ghosted = true
  if f.GetParent and f:GetParent() ~= UIParent then f:SetParent(UIParent) end
  if f.EnableMouse then f:EnableMouse(false) end
  f:SetAlpha(0); holdAlpha(f)
  if not f:IsShown() then f:Show() end
end

-- Lays one stand-in over our frame. Returns "ok" (already there), "fixed", "deferred" (protected, in combat: runs after it), "missing" (the client has
-- no such frame), "noours" (our frame is not built yet) or "skip" (real / native / child).
function AC.Sync(e)
  if e.mode ~= "track" and e.mode ~= "ghost" then return "skip" end
  if not AC.GroupOn(e) then return "skip" end -- the window is the client's own now: nothing is laid over anything
  local f = _G[e.name]
  if not f then return "missing" end
  local ours, win = e.ours()
  if not ours or ours == f then return "noours" end
  hookStandin(e, f); watch(ours, e)
  local want = wanted(ours, win)
  local needGhost = e.mode == "ghost" and not e.ghosted
  if not (needGhost or scaleOff(e, f, ours) or not pointsMatch(f, want)) then return "ok" end
  if InCombatLockdown() and isProtected(f) then
    AC.pending[e] = true
    AFUI.RunOutOfCombat(AC.Flush)
    return "deferred"
  end
  syncing = true
  local good, err = pcall(function()
    if needGhost then becomeGhost(e, f) end
    if scaleOff(e, f, ours) then f:SetScale(f:GetScale() * ours:GetEffectiveScale() / f:GetEffectiveScale()) end
    if not pointsMatch(f, want) then
      f:ClearAllPoints()
      for _, w in ipairs(want) do f:SetPoint(w[1], w[2], w[3], w[4], w[5]) end
    end
  end)
  syncing = false
  if not good then geterrorhandler()(err) end
  return "fixed"
end

function AC.Flush()
  local list = {}
  for e in pairs(AC.pending) do list[#list + 1] = e end
  AC.pending = {}
  local order = {}
  for i, e in ipairs(AC.entries) do order[e] = i end
  table.sort(list, function(a, b) return order[a] < order[b] end) -- parents first: a child takes its scale from its parent's
  for _, e in ipairs(list) do AC.Sync(e) end
end

-- tags: a list of group tags, or nil for everything.
function AC.Refresh(tags)
  local want
  if tags then want = {}; for _, t in ipairs(tags) do want[t] = true end end
  for _, e in ipairs(AC.entries) do
    if not want or want[e.tag] then AC.Sync(e) end
  end
end

---------------------------------------------------------------- nameplates
-- The client's plate frame is the host of our skin; plate.UnitFrame (hidden) and its bars lie over the skin's frame, health bar and cast box.
function AC.AdoptPlate(plate)
  local uf, s = plate and plate.UnitFrame, plate and plate.afuiSkin
  if not (uf and s and s.frame) then return false end
  if InCombatLockdown() and isProtected(uf) then
    AC.plates[plate] = true
    AFUI.RunOutOfCombat(AC.FlushPlates)
    return false
  end
  -- Blizzard's plate frames are never read back (see "measuring"): laid over ours blind, once per NAME_PLATE_UNIT_ADDED; a forbidden one is left alone.
  local pairs_ = { { uf, s.frame }, { uf.healthBar, s.hp }, { uf.castBar, s.castBox } }
  syncing = true
  for _, p in ipairs(pairs_) do
    local f, ours = p[1], p[2]
    if f then AFUI.NoMeasure(f) end
    if f and ours and not (f.IsForbidden and f:IsForbidden()) then
      local good, err = pcall(function()
        f:ClearAllPoints(); f:SetPoint("TOPLEFT", ours, "TOPLEFT", 0, 0); f:SetPoint("BOTTOMRIGHT", ours, "BOTTOMRIGHT", 0, 0)
      end)
      if not good then AFUI.MeasureReport.n = AFUI.MeasureReport.n + 1; AFUI.MeasureReport.first = AFUI.MeasureReport.first or tostring(err) end
    end
  end
  syncing = false
  return true
end
function AC.FlushPlates()
  local list = AC.plates
  AC.plates = {}
  for plate in pairs(list) do AC.AdoptPlate(plate) end
end
function AC.PlateAnchor(plate) return plate and plate.afuiSkin and plate.afuiSkin.frame end

---------------------------------------------------------------- report
local function pointCount(f)
  local c = f.GetNumPoints and SM(f, "GetNumPoints")
  if type(c) == "number" then return c end
  local n = 0
  while SM(f, "GetPoint", n + 1) ~= nil do n = n + 1 end
  return n
end

function AC.Check(e)
  local f = _G[e.name]
  local r = { name = e.name, mode = e.mode, group = e.group, exists = f ~= nil, ok = true }
  if not f then r.note = "absent on this client"; return r end
  if not AC.GroupOn(e) then r.note = "the client's own (switched off in Settings > Windows)"; return r end
  if AFUI.MeasureBlocked(f) then r.shown, r.alpha, r.anchors, r.note = f:IsShown() and true or false, 1, 0, "restricted by the client: not measured"; return r end
  r.shown = f:IsShown() and true or false
  r.visible = (f.IsVisible and f:IsVisible()) and true or false
  r.alpha = f.GetAlpha and f:GetAlpha() or 1
  r.anchors = pointCount(f)
  local l, b, w, h = rect(f)
  r.rect = l and { l, b, w, h } or nil
  if e.mode == "track" or e.mode == "ghost" then
    local ours, win = e.ours()
    if not ours then
      if e.optional then r.note = "no counterpart of ours on this client" else r.ok, r.note = false, "our frame is missing" end
      return r
    end
    local ol, ob, ow, oh = oursRect(ours, win)
    r.want = ol and { ol, ob, ow, oh } or nil
    r.match = rectsMatch(r.rect, r.want)
    r.placed = pointsMatch(f, wanted(ours, win)) and not scaleOff(e, f, ours)
    r.ok = r.placed and r.match ~= false
    if not r.ok then r.note = r.placed and "rect differs from ours" or "not laid over ours" end
    if e.mode == "ghost" and (r.alpha ~= 0 or not r.shown) then r.ok, r.note = false, "ghost is not shown at alpha 0" end
  end
  return r
end

-- Silent: puts back whatever Check finds out of place (deferred in combat by Sync). Returns how many it touched.
function AC.SelfCheck()
  local fixed = 0
  for _, e in ipairs(AC.entries) do
    if e.mode == "track" or e.mode == "ghost" then
      local r = AC.Check(e)
      if r.exists and not r.ok and r.note ~= "our frame is missing" then AC.Sync(e); fixed = fixed + 1 end
    end
  end
  AC.repaired = (AC.repaired or 0) + fixed
  return fixed
end

local function fmt(r)
  local rect = r.rect and string.format("%.0f,%.0f %.0fx%.0f", r.rect[1], r.rect[2], r.rect[3], r.rect[4]) or "no rect"
  local s = string.format("%s  %s  shown=%s alpha=%.1f %s anchors=%d", r.name, r.mode, r.shown and "yes" or "no", r.alpha or 1, rect, r.anchors or 0)
  if r.mode == "track" or r.mode == "ghost" then s = s .. (r.match == nil and " (rect unknown)" or "") end
  if not r.ok then s = "|cffff5555" .. s .. "  MISMATCH: " .. tostring(r.note) .. "|r" end
  return s
end

function AC.Report(all)
  local groups, order, lines = {}, {}, {}
  for _, e in ipairs(AC.entries) do
    local r = AC.Check(e)
    local g = groups[e.group]
    if not g then g = { n = 0, ok = 0, present = 0, bad = {}, mode = e.mode }; groups[e.group] = g; order[#order + 1] = e.group end
    g.n = g.n + 1
    if r.exists then g.present = g.present + 1 end
    if r.ok then g.ok = g.ok + 1 else g.bad[#g.bad + 1] = r end
    if all and r.exists then lines[#lines + 1] = "  " .. fmt(r) end
  end
  local out = { string.format("Aztra's Forever UI: %d client frames covered (%s).", #AC.entries, all and "every frame" or "/afui anchors all lists every frame") }
  if AFUI.MeasureReport.n > 0 then out[#out + 1] = string.format("  %d restricted client frame(s) are not measured (first: %s)", AFUI.MeasureReport.n, AFUI.MeasureReport.first) end
  if not all then
    for _, name in ipairs(order) do
      local g = groups[name]
      if g.present > 0 then
        out[#out + 1] = string.format("  %s  %s  %d/%d %s", name, g.mode, g.ok - (g.n - g.present), g.present, g.ok == g.n and "ok" or "|cffff5555MISMATCH|r")
        for _, r in ipairs(g.bad) do out[#out + 1] = "    " .. fmt(r) end
      end
    end
  else
    for _, l in ipairs(lines) do out[#out + 1] = l end
  end
  return out
end

---------------------------------------------------------------- public
-- Our visible frame (and the window inside it, if any) for a client frame name; for a real / native frame the client's own frame.
function AFUI.AnchorFor(name)
  local e = AC.byName[name]
  if not e then return end
  if e.mode == "track" or e.mode == "ghost" then return e.ours() end
  return _G[name]
end

function AFUI.AnchorNames()
  local out = {}
  for i, e in ipairs(AC.entries) do out[i] = e.name end
  table.sort(out)
  return out
end

AFUI.Slash.Register("anchors", function(rest)
  for _, l in ipairs(AC.Report(tostring(rest or ""):lower():find("all") ~= nil)) do AFUI.Print(l) end
end, "where the client's frames lie against ours (for addons that anchor to them)", "/afui anchors [all]")

---------------------------------------------------------------- events
local UNIT_TAGS = { "player", "target", "targettarget", "pet", "party" }
local function on(event, tags) AFUI.On(event, function() AC.Refresh(tags) end) end
on("PLAYER_ENTERING_WORLD"); on("UI_SCALE_CHANGED"); on("DISPLAY_SIZE_CHANGED")
on("PLAYER_TARGET_CHANGED", { "target", "targettarget" }); on("UNIT_CLASSIFICATION_CHANGED", { "target" }); on("PLAYER_FOCUS_CHANGED", UNIT_TAGS)
on("UNIT_PET", { "pet", "party" })
for _, e in ipairs({ "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS", "UPDATE_BONUS_ACTIONBAR", "ACTIONBAR_PAGE_CHANGED" }) do on(e, { "bars" }) end
for _, e in ipairs(AFUI.GROUP_EVENTS or {}) do on(e, { "party", "pet", "player" }) end
AFUI.On("PLAYER_REGEN_ENABLED", function() AC.Flush(); AC.FlushPlates() end)
AFUI.On("NAME_PLATE_UNIT_ADDED", function(_, u) if _G.C_NamePlate then AC.AdoptPlate(C_NamePlate.GetNamePlateForUnit(u)) end end)

local checked
AFUI.On("PLAYER_ENTERING_WORLD", function() -- the first time the rects exist: the silent self-check
  if checked then return end
  checked = true
  defer(function() AC.SelfCheck() end)
end)

AFUI.RegisterModule("AnchorCompat", { OnLogin = function()
  AC.Refresh()
  if AFUI.Layouts and not AC.layoutHooked then -- a layout / profile switch re-places and re-sizes our frames
    AC.layoutHooked = true
    for _, m in ipairs({ "Apply", "ApplySystem" }) do
      if AFUI.Layouts[m] then hooksecurefunc(AFUI.Layouts, m, function() AC.Refresh() end) end
    end
  end
  if type(AFUI.RefreshBuffs) == "function" and not AC.buffHooked then
    AC.buffHooked = true
    local last
    hooksecurefunc(AFUI, "RefreshBuffs", function() -- cheap: three counters; the stand-ins move only when the slots do
      local sig = AC.BuffSignature()
      if sig ~= last then last = sig; AC.Refresh({ "buffs" }) end
    end)
  end
end })
