-- Forever minimap (docs/forever-ref/minimap.md): 198 px map under the 253 px copper ring, header bar (zone + clock) with the
-- tracking button, mail, day/night badge and hover zoom buttons at Forever's anchors. MinimapCluster stays alive (other addons
-- anchor to it); only its art is hidden.
AFUI = AFUI or {}

local P = "ui-hud-minimap-"
local SIZE = 198 -- Forever's Minimap widget; the 256 mask stretched over it leaves a disc that runs under the ring's feathered edge
local RING = 253
local CLUSTER_W, CLUSTER_H = 273, 283 -- ring + 20 padding wide; header top to ring bottom high
local CENTER_Y = -156.5 -- map centre below the cluster top
local HS = 1 -- the video measures Forever's own 144 x 18.5 header: no enlargement
local HEADER_W, HEADER_H, ZONE_SIZE = 144, 18.5, 10

-- Addons (LibDBIcon, minimap button bags) place their buttons from Minimap:GetWidth() and GetMinimapShape(); our map is round.
if not GetMinimapShape then function GetMinimapShape() return "ROUND" end end

-- Font size that fits a string of width `width` into `maxW`, never under 8 (the zone name beside the clock).
function AFUI.ZoneFontSize(width, maxW, size)
  if width <= maxW then return size end
  return math.max(8, math.floor(size * maxW / width))
end

function AFUI.ClockText(hour, minute) return string.format("%02d:%02d", hour, minute) end

-- Daylight is 06:00 to 18:00 server time (the day/night badge).
function AFUI.IsDay(hour, minute)
  local m = hour * 60 + minute
  return m >= 360 and m < 1080
end

-- One zoom step for the wheel and the zoom buttons, clamped to the client's levels.
function AFUI.MinimapZoom(delta)
  local zoom = Minimap:GetZoom() + (delta > 0 and 1 or -1)
  if zoom >= 0 and zoom < Minimap:GetZoomLevels() then Minimap:SetZoom(zoom) end
end

local ZONE_COLORS = {
  sanctuary = { 0.41, 0.8, 0.94 }, arena = { 1, 0.1, 0.1 }, friendly = { 0.1, 1, 0.1 },
  hostile = { 1, 0.1, 0.1 }, contested = { 1, 0.7, 0 },
}
function AFUI.ZoneColor(pvpType)
  local c = ZONE_COLORS[pvpType] or { 1, 0.82, 0 } -- NORMAL_FONT_COLOR
  return c[1], c[2], c[3]
end

-- Textures can only be hidden; frames are reparented to the hidden holder so a stray Show() cannot bring them back.
local function banish(name)
  local f = _G[name]
  if not f then return end
  if f.IsObjectType and f:IsObjectType("Texture") then f:Hide(); f:SetAlpha(0) else AFUI.Kill(f) end -- alpha 0 too: Minimap_UpdateRotationSetting calls MinimapNorthTag:Show() on every rotation CVAR update
end

-- Verified in 2.4.3 and 2.5.3 Minimap.xml: the tracking button owns these textures directly (no child button);
-- the ButtonX names are listed too in case a client nests them. banish tolerates missing names.
AFUI.TRACKING_ART = { "MiniMapTrackingBorder", "MiniMapTrackingBackground", "MiniMapTrackingShine",
  "MiniMapTrackingButtonBorder", "MiniMapTrackingButtonBackground", "MiniMapTrackingButtonShine" }

-- Names of what the character tracks now (GetTrackingInfo: name, texture, active); a client without the list has the one active texture.
function AFUI.TrackingActive()
  local out = {}
  for i = 1, _G.GetNumTrackingTypes and GetNumTrackingTypes() or 0 do
    local name, _, active = GetTrackingInfo(i)
    if name and active then out[#out + 1] = name end
  end
  return out
end

function AFUI.BagSlotsText(free, total) return free .. "/" .. total end

-- A small "free/total" bag slots counter above the bag bar's right end (option minimapBagSlots, off by default). The single-icon bag bar already
-- carries its own count. Re-read on BAG_UPDATE: five containers at most, no table is kept.
function AFUI.SetupBagSlots()
  if not (AFUI.BagBar and _G.GetContainerNumSlots) then return end
  local host = CreateFrame("Frame", "AFUI_BagSlots", UIParent)
  host:SetWidth(60); host:SetHeight(14)
  host:SetPoint("BOTTOMRIGHT", AFUI.BagBar, "TOPRIGHT", 0, 3)
  local fs = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("RIGHT", host, "RIGHT", 0, 0)
  AFUI.BagSlots, host.text = host, fs
  local function update()
    local mode = AFUI.BagBarMode and AFUI.BagBarMode() or "full"
    if AFUI.GetSetting("minimapBagSlots", false) ~= true or mode == "single" then host:Hide(); return end
    local free, total = 0, 0
    for bag = 0, 4 do
      local n = GetContainerNumSlots(bag) or 0
      if n > 0 then free, total = free + (GetContainerNumFreeSlots(bag) or 0), total + n end
    end
    fs:SetText(AFUI.BagSlotsText(free, total))
    if free <= 3 then fs:SetTextColor(1, 0.2, 0.2) else fs:SetTextColor(1, 1, 1) end
    host:Show()
  end
  AFUI.UpdateBagSlots = update
  AFUI.On("BAG_UPDATE", update)
  AFUI.On("PLAYER_ENTERING_WORLD", update)
  AFUI.OnSettingChanged("minimapBagSlots", update)
  update()
end

function AFUI.SetupMinimap()
  local mf = CreateFrame("Frame", "AFUI_MinimapFrame", UIParent)
  mf:SetWidth(CLUSTER_W); mf:SetHeight(CLUSTER_H)
  mf:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
  AFUI.MinimapFrame = mf

  -- MiniMapCompassRing / MinimapCompassTexture / MinimapNorthTag: Forever bakes the north triangle into the ring art.
  for _, n in ipairs({ "MinimapBorder", "MinimapBorderTop", "MinimapZoneTextButton", "MinimapToggleButton",
    "MinimapZoomIn", "MinimapZoomOut", "MiniMapWorldMapButton", "MiniMapCompassRing", "MinimapCompassTexture",
    "MinimapNorthTag", "TimeManagerClockButton" }) do banish(n) end
  -- Blizzard_TimeManager can load after us; its ring clock would sit under our header clock.
  AFUI.On("ADDON_LOADED", function(_, addon) if addon == "Blizzard_TimeManager" then banish("TimeManagerClockButton") end end)

  Minimap:SetParent(mf)
  Minimap:ClearAllPoints(); Minimap:SetPoint("CENTER", mf, "TOP", 10, CENTER_Y)
  Minimap:SetWidth(SIZE); Minimap:SetHeight(SIZE)
  local mask = AFUI_ATLAS and AFUI_ATLAS[P .. "frame-generic-mask-c60"]
  if mask then Minimap:SetMaskTexture(mask[1]) end -- whole-sheet 256x256 white disc, stretched over the 198 map
  Minimap:EnableMouseWheel(true)
  Minimap:SetScript("OnMouseWheel", function(_, delta) AFUI.MinimapZoom(delta) end)
  local mapLevel = Minimap:GetFrameLevel()

  -- Minimap is a child frame, so the ring needs its own frame above it to draw over the map edge (no backdrop disc in Forever).
  local ringFrame = CreateFrame("Frame", "AFUI_MinimapRing", mf)
  ringFrame:SetWidth(RING); ringFrame:SetHeight(RING)
  ringFrame:SetPoint("CENTER", Minimap, "CENTER", 0, 0); ringFrame:SetFrameLevel(mapLevel + 3)
  AFUI.MinimapRing = ringFrame

  -- Blizzard's MinimapCluster is strata LOW at UIParent's level: buttons addons parent to it (or to the Minimap with a low level)
  -- would sit behind the ring. It moves under our cluster, above the ring; whatever is still at or under the ring is lifted.
  if MinimapCluster then
    MinimapCluster:SetParent(mf)
    MinimapCluster:ClearAllPoints(); MinimapCluster:SetPoint("TOPRIGHT", mf, "TOPRIGHT", 0, 0)
    MinimapCluster:SetFrameStrata(mf:GetFrameStrata())
    MinimapCluster:SetFrameLevel(ringFrame:GetFrameLevel() + 2)
    MinimapCluster:EnableMouse(false)
  end
  local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
  -- Root cause of the buttons under the ring: Blizzard's own buttons (tracking, mail, eyes, day/night) keep the cluster's LOW strata
  -- when reparented to our MEDIUM cluster (SetParent never changes strata), so the MEDIUM ring covers them at any level; the old lift
  -- only walked the children of Minimap/MinimapCluster, which these no longer are. lift() fixes strata and level of one frame.
  local function lift(f)
    if f and f.IsForbidden and f:IsForbidden() then return end -- forbidden frames error on any call from addon code
    if not (f and f ~= ringFrame and f ~= mf and f.GetFrameStrata and f.SetFrameStrata) then return end
    local rs = ringFrame:GetFrameStrata()
    if (STRATA[f:GetFrameStrata()] or 3) < (STRATA[rs] or 3) then f:SetFrameStrata(rs) end
    if f:GetFrameStrata() == rs and f:GetFrameLevel() <= ringFrame:GetFrameLevel() then f:SetFrameLevel(ringFrame:GetFrameLevel() + 1) end
  end
  local function onMap(f)
    if f.IsForbidden and f:IsForbidden() then return false end
    local n = f.GetName and f:GetName()
    if n and (n:find("^LibDBIcon10_") or n:find("^Minimap") or n:find("^MiniMap")) then return true end
    if not f.GetPoint then return false end
    local _, rel = f:GetPoint(1)
    return rel == Minimap
  end
  local function raise()
    for _, n in ipairs({ "MiniMapTracking", "MiniMapTrackingFrame", "MiniMapMailFrame", "MiniMapBattlefieldFrame", "MiniMapMeetingStoneFrame",
      "MiniMapLFGFrame", "GameTimeFrame", "OutfitterMinimapButton", "AFUI_MinimapHeader", "AFUI_MinimapClock", "AFUI_MinimapZoomIn", "AFUI_MinimapZoomOut" }) do
      lift(_G[n])
    end
    for _, host in ipairs({ Minimap, MinimapCluster, mf }) do
      for _, c in ipairs(host and host.GetChildren and { host:GetChildren() } or {}) do lift(c) end
    end
    -- addon buttons parented to UIParent with their own strata
    for _, c in ipairs({ UIParent:GetChildren() }) do if onMap(c) then lift(c) end end
  end
  -- children can be secure addon buttons: SetFrameLevel on them is blocked in combat, so wait for it to end
  function AFUI.RaiseMinimapAddons() AFUI.RunOutOfCombat(raise) end
  AFUI.RaiseMinimapAddons()
  AFUI.On("PLAYER_ENTERING_WORLD", AFUI.RaiseMinimapAddons)
  AFUI.On("ADDON_LOADED", AFUI.RaiseMinimapAddons)
  -- Addons add their buttons after their own ADDON_LOADED / login (LibDBIcon registers when its addon's PLAYER_LOGIN or a later
  -- event runs), so a lift at load time misses them: LibDBIcon announces every new button, and a slow timer catches the rest (2.5.3 only;
  -- 2.4.3 has no C_Timer and relies on the events).
  if _G.C_Timer and C_Timer.After then
    local ticks = 0 -- two minutes after login: later buttons arrive through ADDON_LOADED / LibDBIcon_IconCreated, and each pass lists every UIParent child
    local function tick() ticks = ticks + 1; AFUI.RaiseMinimapAddons(); AFUI.RunOutOfCombat(AFUI.KeepTrackerClear); if ticks < 24 then C_Timer.After(5, tick) end end
    C_Timer.After(5, tick)
  end
  AFUI.On("ADDON_LOADED", function()
    local lib = _G.LibStub and LibStub("LibDBIcon-1.0", true)
    if lib and lib.RegisterCallback and not AFUI.dbiconHooked then
      AFUI.dbiconHooked = true
      lib.RegisterCallback(AFUI, "LibDBIcon_IconCreated", function() AFUI.RaiseMinimapAddons() end)
    end
  end)
  -- Blizzard's quest tracker hangs under MinimapCluster, which is no longer our cluster's size: when it reaches into our cluster
  -- (or a right action bar) it is moved under the cluster, left of the right bars (Forever's objective tracker sits there).
  local function overlap(a, b)
    local al, ar, at, ab, bl, br, bt, bb = a:GetLeft(), a:GetRight(), a:GetTop(), a:GetBottom(), b:GetLeft(), b:GetRight(), b:GetTop(), b:GetBottom()
    return al and ar and at and ab and bl and br and bt and bb and al < br and ar > bl and ab < bt and at > bb
  end
  function AFUI.KeepTrackerClear()
    if AFUI.Tracker then return end -- Forever's tracker (Tracker.lua) is an Edit Mode system with its own place; Blizzard's list is invisible
    local t = _G.WatchFrame or _G.QuestWatchFrame
    if not (t and t.GetLeft and t:IsShown()) then return end
    local bars = AFUI.Bars
    local hit, left = overlap(t, mf), nil
    for _, k in ipairs({ "right", "right2" }) do
      local b = bars and bars[k] and bars[k].frame
      if b and b:IsShown() and b:GetLeft() then
        left = math.min(left or b:GetLeft(), b:GetLeft())
        if overlap(t, b) then hit = true end
      end
    end
    if not hit then return end
    local x = left and (mf:GetRight() - left + 8) or 10 -- the tracker's right edge stops left of the first right bar
    t:ClearAllPoints()
    t:SetPoint("TOPRIGHT", mf, "BOTTOMRIGHT", -x, -4)
  end
  local function keepClear() AFUI.RunOutOfCombat(AFUI.KeepTrackerClear) end
  AFUI.On("PLAYER_ENTERING_WORLD", keepClear)
  if _G.UIParent_ManageFramePositions then hooksecurefunc("UIParent_ManageFramePositions", keepClear) end
  local ring = ringFrame:CreateTexture(nil, "OVERLAY")
  AFUI.SetAtlas(ring, P .. "frame-c60", true); ring:SetPoint("CENTER", ringFrame, "CENTER", 0, 0)

  -- Header bar: click = world map, mouse-over lightens the bar.
  local header = CreateFrame("Button", "AFUI_MinimapHeader", mf)
  header:SetWidth(HEADER_W); header:SetHeight(HEADER_H)
  header:SetPoint("TOP", mf, "TOP", 9.5, -2) -- Forever's +10; the cluster is odd wide, so a whole +10 would straddle a pixel
  header:SetFrameLevel(mapLevel + 8)
  local bar = header:CreateTexture(nil, "BACKGROUND")
  AFUI.SetAtlas(bar, P .. "header-button-c60"); bar:SetAllPoints(header)
  AFUI.SetButtonAtlas(header, { nil, nil, P .. "header-button-c60" }, 0.1)
  header:SetScript("OnClick", function() ToggleWorldMap() end)
  -- No fixed width, so a long zone name never wraps onto a second line; fitZone shrinks it to end before the clock instead.
  local zone = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  zone:SetJustifyH("LEFT"); zone:SetPoint("LEFT", header, "LEFT", 6, 0)
  AFUI.MinimapZone = zone

  -- Clock: Forever keeps Blizzard's button on the bar; ours is a 40x16 button with the same ticker font, opening the time manager.
  local clockButton = CreateFrame("Button", "AFUI_MinimapClock", mf)
  clockButton:SetWidth(40); clockButton:SetHeight(18)
  clockButton:SetPoint("RIGHT", header, "RIGHT", -2, 0); clockButton:SetFrameLevel(mapLevel + 9)
  clockButton:SetScript("OnClick", function() if TimeManager_Toggle then TimeManager_Toggle() end end)
  local clock = clockButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  clock:SetPoint("RIGHT", clockButton, "RIGHT", -4, 0) -- right-aligned: "16:10" sits where Forever's does, "7:42 PM" grows left
  AFUI.MinimapClock, AFUI.MinimapClockButton = clock, clockButton

  -- GameTimeFrame is the day/night indicator on both clients (no calendar yet): Forever's DielFrame badge, 42x42 on the ring's upper right.
  local badge = { frame = GameTimeFrame }
  if GameTimeFrame then
    GameTimeFrame:SetParent(mf); GameTimeFrame:SetFrameLevel(mapLevel + 5)
    GameTimeFrame:SetWidth(42); GameTimeFrame:SetHeight(42)
    GameTimeFrame:SetHitRectInsets(0, 0, 0, 0)
    GameTimeFrame:ClearAllPoints(); GameTimeFrame:SetPoint("CENTER", Minimap, "CENTER", 55.5, 86.5) -- Forever's (55, 86) on the map's half-pixel centre
    banish("GameTimeTexture")
    badge.icon = GameTimeFrame:CreateTexture(nil, "BACKGROUND")
    badge.icon:SetPoint("CENTER", GameTimeFrame, "CENTER", 0, 0)
    local border = GameTimeFrame:CreateTexture(nil, "OVERLAY")
    AFUI.SetAtlas(border, P .. "frame-cycle-c60", true); border:SetPoint("CENTER", GameTimeFrame, "CENTER", 0, 0)
  end

  -- 10 left of the zone, 8 right of the clock, 5 between them.
  local zoneFont, _, zoneFlags = GameFontHighlightSmall and GameFontHighlightSmall:GetFont()
  local function fitZone()
    if not zoneFont then return end
    clock:SetFont(zoneFont, ZONE_SIZE, zoneFlags)
    zone:SetFont(zoneFont, ZONE_SIZE, zoneFlags)
    local size = AFUI.ZoneFontSize(zone:GetStringWidth() or 0, HEADER_W - 16 - (clock:GetStringWidth() or 0), ZONE_SIZE)
    if size ~= ZONE_SIZE then zone:SetFont(zoneFont, size, zoneFlags) end
  end
  local function updateZone()
    zone:SetText(GetMinimapZoneText())
    zone:SetTextColor(AFUI.ZoneColor((GetZonePVPInfo())))
    fitZone()
  end
  -- A clock needs a heartbeat: one throttled OnUpdate that only writes when the minute changed.
  local elapsed = 5
  local function updateClock(_, dt)
    elapsed = elapsed + dt
    if elapsed < 5 then return end
    elapsed = 0
    -- The player's own clock settings (local/realm, 12/24 h) via Blizzard's GameTime_GetTime when the client has it.
    local text = GameTime_GetTime and GameTime_GetTime(true) or AFUI.ClockText(GetGameTime())
    if text ~= clock.shown then clock.shown = text; clock:SetText(text); fitZone() end
    if badge.icon then
      local day = AFUI.IsDay(GetGameTime())
      if day ~= badge.day then badge.day = day; AFUI.SetAtlas(badge.icon, P .. (day and "daycycle-c60" or "nightcycle-c60"), true) end
    end
  end
  header:SetScript("OnUpdate", updateClock)
  for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
    AFUI.On(e, updateZone)
  end
  updateZone(); updateClock(header, 5)

  -- Mail hangs under the bar's left end, tracking overlaps its left end by 3 px; the eyes sit on the ring's lower left.
  if MiniMapMailFrame then
    MiniMapMailFrame:SetParent(mf); MiniMapMailFrame:SetFrameLevel(header:GetFrameLevel())
    MiniMapMailFrame:SetWidth(32 * HS); MiniMapMailFrame:SetHeight(24 * HS)
    MiniMapMailFrame:ClearAllPoints(); MiniMapMailFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    if MiniMapMailIcon then
      AFUI.SetAtlas(MiniMapMailIcon, P .. "mail-icon-c60"); MiniMapMailIcon:SetWidth(32 * HS); MiniMapMailIcon:SetHeight(24 * HS)
      MiniMapMailIcon:ClearAllPoints(); MiniMapMailIcon:SetPoint("TOPLEFT", MiniMapMailFrame, "TOPLEFT", 0, 0)
    end
    banish("MiniMapMailBorder")
  end
  local tracking = MiniMapTracking or MiniMapTrackingFrame
  if tracking then
    tracking:SetParent(mf); tracking:SetFrameLevel(header:GetFrameLevel())
    tracking:SetWidth(20); tracking:SetHeight(20)
    tracking:ClearAllPoints(); tracking:SetPoint("RIGHT", header, "LEFT", -2, 0)
    local tname = tracking:GetName()
    for _, n in ipairs(AFUI.TRACKING_ART) do banish(n) end
    local art = tracking:CreateTexture(nil, "BACKGROUND")
    AFUI.SetAtlas(art, P .. "tracking-button-c60"); art:SetAllPoints(tracking)
    local icon = _G[tname .. "Icon"]
    if icon then icon:SetWidth(18); icon:SetHeight(18); icon:ClearAllPoints(); icon:SetPoint("CENTER", tracking, "CENTER", 0, 0) end
    -- the stock tooltip says only "Tracking": what is tracked now goes under it
    tracking:HookScript("OnEnter", function()
      local on = AFUI.TrackingActive()
      if not (GameTooltip and GameTooltip:IsShown()) then return end
      GameTooltip:AddLine(#on > 0 and table.concat(on, ", ") or "Nothing tracked", 0.1, 1, 0.1)
      GameTooltip:AddLine("Click: choose what to track", 0.5, 0.5, 0.5)
      GameTooltip:Show()
    end)
  end
  AFUI.SetupBagSlots()
  -- Battleground and looking-for-group (2.4.3 meeting stone, 2.5.3 LFG) eyes: the client's own icon, without its old ring.
  -- Forever has one group finder eye (QueueStatusButton CENTER, Minimap, -68, -68); the TBC clients have two buttons, so the
  -- battleground eye keeps that spot and the LFG one sits 30 degrees further round the ring (radius 96, at least one eye apart).
  local EYE = { MiniMapBattlefieldFrame = { -68, -68 }, MiniMapMeetingStoneFrame = { -93, -25 }, MiniMapLFGFrame = { -93, -25 } }
  for n, at in pairs(EYE) do
    local eye = _G[n]
    if eye then
      eye:SetParent(mf); eye:SetFrameLevel(header:GetFrameLevel())
      eye:ClearAllPoints(); eye:SetPoint("CENTER", Minimap, "CENTER", at[1], at[2])
      banish(n:gsub("Frame$", "Border"))
    end
  end

  -- Coordinates under the ring (video: white 12 px outlined text centred below it, no box). The client answers 0, 0 where there is no map.
  local coords = mf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  coords:SetPoint("CENTER", Minimap, "CENTER", 0, -113)
  local ce = 1
  CreateFrame("Frame", nil, UIParent):SetScript("OnUpdate", function(_, dt)
    ce = ce + dt
    if ce < 0.5 then return end
    ce = 0
    local x, y = 0, 0
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then -- 2.5.3: the retail map API (the legacy call may answer 0, 0 there)
      local id = C_Map.GetBestMapForUnit("player")
      local pos = id and C_Map.GetPlayerMapPosition(id, "player")
      if pos then x, y = pos:GetXY() end
    elseif GetPlayerMapPosition then x, y = GetPlayerMapPosition("player") end
    if x and y and (x > 0 or y > 0) then coords:SetText(string.format("%.1f, %.1f", x * 100, y * 100)) else coords:SetText("") end
  end)
  AFUI.MinimapCoords = coords

  -- Zoom buttons (not Blizzard's): hidden until the cursor is on the map.
  local function zoomButton(name, w, h, x, y, delta, art)
    local b = CreateFrame("Button", name, mf)
    b:SetWidth(w); b:SetHeight(h); b:SetPoint("CENTER", Minimap, "CENTER", x, y)
    b:SetFrameLevel(mapLevel + 6)
    AFUI.SetButtonAtlas(b, { P .. art, P .. art .. "-down", P .. art .. "-mouseover" })
    b:SetScript("OnClick", function() AFUI.MinimapZoom(delta) end)
    b:Hide()
    return b
  end
  local zin = zoomButton("AFUI_MinimapZoomIn", 17, 17, 88, -68, 1, "zoom-in")
  local zout = zoomButton("AFUI_MinimapZoomOut", 17, 9, 72, -84, -1, "zoom-out")
  AFUI.MinimapZoomIn, AFUI.MinimapZoomOut = zin, zout
  -- Shown while the cursor is on the map or on either button (Forever: ZoomHitArea, mainline/minimap.lua:253-268). Leaving the
  -- map for a button fires OnLeave first, so hiding waits until the cursor is on none of the three.
  local function sync()
    if MouseIsOver(Minimap) or MouseIsOver(zin) or MouseIsOver(zout) then zin:Show(); zout:Show() else zin:Hide(); zout:Hide() end
  end
  local function enter() zin:Show(); zout:Show() end
  for _, f in ipairs({ Minimap, zin, zout }) do
    f:HookScript("OnEnter", enter)
    f:HookScript("OnLeave", sync)
  end
  AFUI.RaiseMinimapAddons() -- everything above is built and reparented now
end

AFUI.RegisterModule("Minimap", { OnLogin = AFUI.SetupMinimap })
