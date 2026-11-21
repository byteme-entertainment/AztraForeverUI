-- Quest points of the tracked quests on the map canvas (2.5.3).
-- Why this exists: Blizzard_WorldMap.lua of 2.5.3 (Gethe/wow-ui-source tag 2.5.3, Interface_TBC/AddOns/Blizzard_WorldMap) has QuestDataProviderMixin,
-- QuestBlobDataProviderMixin and StorylineQuestDataProviderMixin commented out of AddStandardDataProviders, so the client never draws a quest pin whatever the
-- tracker holds; and the shared QuestDataProvider shows every quest of the map (GetQuestsOnMap), never "the watched ones". The tick of the quest panel only
-- called Add / RemoveQuestWatch, which nothing on the map listens to. So the pins are ours: one numbered pin per tracked quest that has a point on the shown map,
-- drawn on the client's canvas child (pan / zoom / clipping stay the client's), refreshed by the tick at once and by the client's quest events.
-- Point sources (first that answers): C_QuestLog.GetQuestsOnMap(mapID) -> { questID, x, y }; QuestPOIGetIconInfo(questID) -> completed, x, y, objective.
AFUI = AFUI or {}
local P = {}
AFUI.MapQuestPins = P
P.shown, P.selected = 0, nil

local PIN, SMALL, ARROW = 24, 16, 24 -- UI px: a pin, a pin of a quest with many spots, the player arrow (Forever: ~32 px at 1440p = ~23 u)

-- Tracked quests of the log: { questID, index, title, complete, number } (number = order in the log, as the tracker numbers them).
function P.Watched(api)
  api = api or _G
  local out = {}
  -- ReadAll also sees the quests of collapsed zones (their header is expanded for the read and collapsed again)
  local Q = AFUI.QuestLog
  for _, e in ipairs(Q and Q.ReadAll and Q.ReadAll(api) or {}) do
    if not e.isHeader and e.questID and e.watched then
      out[#out + 1] = { questID = e.questID, index = e.index, title = e.title, complete = e.complete == 1 or e.complete == true, number = #out + 1 }
    end
  end
  return out
end

-- The tracked quests that have a point on map `mapID`: the watched entries plus x, y (0..1). `api` is injectable (C_QuestLog, QuestPOIGetIconInfo).
function P.Points(api, mapID, watched)
  api = api or _G
  local onMap = {}
  local cq = api.C_QuestLog
  if mapID and cq and type(cq.GetQuestsOnMap) == "function" then
    local ok, list = pcall(cq.GetQuestsOnMap, mapID)
    for _, q in ipairs(ok and type(list) == "table" and list or {}) do onMap[q.questID] = q end
  end
  local out = {}
  for _, w in ipairs(watched) do
    local x, y
    local q = onMap[w.questID]
    if q then x, y = q.x, q.y
    elseif type(api.QuestPOIGetIconInfo) == "function" then
      local ok, _, px, py = pcall(api.QuestPOIGetIconInfo, w.questID)
      if ok then x, y = px, py end
    end
    if x and y and (x ~= 0 or y ~= 0) and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
      out[#out + 1] = { questID = w.questID, index = w.index, title = w.title, complete = w.complete, number = w.number, x = x, y = y }
    end
  end
  return out
end

-- Questie present (QuestieLoader / Questie globals).
function P.Questie() return _G.Questie ~= nil or _G.QuestieLoader ~= nil end

local function questieModule(env, name)
  local L = env.QuestieLoader
  if not (L and L.ImportModule) then return nil end
  local ok, m = pcall(L.ImportModule, L, name)
  return ok and m or nil
end

-- Count of Questie's visible map icons for the quest ids (Questie's QuestieMap.questIdFrames: questId -> { frameName = true }); nil when it cannot be read.
-- With `mapID` only the world-map icons (not the minimap twins) of that map count.
function P.QuestieIcons(ids, mapID, env)
  env = env or _G
  local ok, n = pcall(function()
    local map = questieModule(env, "QuestieMap")
    local by = map and map.questIdFrames
    if not by then return nil end
    local c = 0
    for _, id in ipairs(ids) do
      for name in pairs(by[id] or {}) do
        local f = env[name]
        if f and f.IsShown and f:IsShown() and not f.miniMapIcon and (not mapID or f.UiMapID == mapID) then c = c + 1 end
      end
    end
    return c
  end)
  return ok and n or nil
end

-- Questie's objective spawns of a quest on map `mapID`: { { x, y (0..1), text } }. Questie keeps the quest object in QuestiePlayer.currentQuestlog[questId]; every
-- objective has spawnList[id] = { Name, Spawns = { [areaId] = { { x, y } } } } with x, y in percent, and ZoneDB:GetUiMapIdByAreaId turns the area into the map id.
-- Finished objectives draw nothing (as in Questie). Capped so a quest with hundreds of spawns stays readable.
local MAX_SPOTS = 30
function P.QuestieSpots(questID, mapID, env)
  env = env or _G
  local out = {}
  pcall(function()
    local player, zones = questieModule(env, "QuestiePlayer"), questieModule(env, "ZoneDB")
    local quest = player and player.currentQuestlog and player.currentQuestlog[questID]
    if not (quest and zones and zones.GetUiMapIdByAreaId and quest.Objectives) then return end
    for _, o in pairs(quest.Objectives) do
      if not o.Completed then
        for _, spawn in pairs(o.spawnList or {}) do
          for area, list in pairs(spawn.Spawns or {}) do
            if zones:GetUiMapIdByAreaId(area) == mapID then
              for _, s in pairs(list) do
                if s[1] and s[2] and #out < MAX_SPOTS then out[#out + 1] = { x = s[1] / 100, y = s[2] / 100, text = o.Description or spawn.Name } end
              end
            end
          end
        end
      end
    end
  end)
  table.sort(out, function(a, b) if a.x ~= b.x then return a.x < b.x end return a.y < b.y end) -- pairs() order is not stable between refreshes
  return out
end

-- Our pins for the watched quests on the map: the client's own points first, else Questie's spawns for quests whose Questie icons are not on this map (no duplicates).
function P.QuestiePoints(watched, mapID, env)
  local out = {}
  if not (P.Questie() and mapID) then return out end
  for _, w in ipairs(watched) do
    if (P.QuestieIcons({ w.questID }, mapID, env) or 0) == 0 then
      for _, s in ipairs(P.QuestieSpots(w.questID, mapID, env)) do
        out[#out + 1] = { questID = w.questID, index = w.index, title = w.title, complete = w.complete, number = w.number, x = s.x, y = s.y, text = s.text }
      end
    end
  end
  return out
end

local wm, scroll, canvas, win
local pool = {}

local function newPin(i)
  local b = CreateFrame("Button", nil, canvas)
  b:SetWidth(PIN); b:SetHeight(PIN)
  b.glow = b:CreateTexture(nil, "BACKGROUND"); b.glow:SetAllPoints(b); b.glow:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress"); b.glow:Hide()
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints(b)
  if AFUI.SetAtlas then AFUI.SetAtlas(b.icon, "waypoint-mappin-untracked") end
  b.num = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); b.num:SetPoint("CENTER", b, "CENTER", 0, 1)
  b:SetScript("OnClick", function(self)
    if self.q then P.Select(self.q.questID, self.q.index) end
  end)
  b:SetScript("OnEnter", function(self)
    if not self.q then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.q.title, 1, 0.82, 0)
    if self.q.text then GameTooltip:AddLine("- " .. self.q.text, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  pool[i] = b
  return b
end

local GROUP_SIZE = 11 -- the party circles (see "party members" below)
local groupPins, groupAt, groupOn = {}, 0, nil

-- Pin size and level follow the canvas: the child is scaled by the zoom, so a pin takes the inverse (and 1 / k for the map frame's own scale) to stay UI-sized;
-- its level sits above the map art and below the chrome window (WorldMap.lua's window is base + 20).
-- A pin's anchor offset is in the pin's OWN scale: with the pin scaled 1 / zoom, a point at 0..1 of the canvas needs its offset divided by that scale, and the pin is
-- anchored again whenever the scale changes (without it the pins crept towards the canvas corner as the map was zoomed in, and the party circles left the screen).
local function anchor(b, nx, ny)
  local k = b:GetScale()
  if not (type(k) == "number" and k > 0) then k = 1 end
  b:ClearAllPoints(); b:SetPoint("CENTER", canvas, "TOPLEFT", nx * canvas:GetWidth() / k, -ny * canvas:GetHeight() / k)
end

local lastScale
function P.Layout(force)
  if not canvas then return end
  local cs = scroll and scroll.GetCanvasScale and scroll:GetCanvasScale() or 1
  local ui = wm:GetEffectiveScale() / UIParent:GetEffectiveScale()
  local key = cs * 1000 + ui
  if not force and key == lastScale then return end
  lastScale = key
  P.FixArrow()
  local lvl = math.min(canvas:GetFrameLevel() + 10, wm:GetFrameLevel() + 19)
  for _, b in ipairs(groupPins) do
    b:SetScale(1 / math.max(cs, 0.01)); b:SetWidth(GROUP_SIZE / ui); b:SetHeight(GROUP_SIZE / ui); b:SetFrameLevel(lvl)
    if b.nx then anchor(b, b.nx, b.ny) end
  end
  for _, b in ipairs(pool) do
    local size = (b.small and SMALL or PIN) / ui
    b:SetScale(1 / math.max(cs, 0.01)); b:SetWidth(size); b:SetHeight(size)
    b:SetFrameLevel(lvl)
    if b.q then anchor(b, b.q.x, b.q.y) end
  end
end

function P.Refresh()
  if not canvas then return end
  local mapID = wm.GetMapID and wm:GetMapID()
  -- The client has no objective data (2.5.3): the points come from the client's calls, else from Questie's database for quests whose own icons are not on this map.
  local watched = P.Watched(_G)
  local pts = {}
  if AFUI.GetSetting("mapQuestPins", true) ~= false then -- Settings > Tracker & Map
    pts = P.Points(_G, mapID, watched)
    for _, q in ipairs(P.QuestiePoints(watched, mapID)) do pts[#pts + 1] = q end
  end
  local per = {}
  for _, q in ipairs(pts) do per[q.questID] = (per[q.questID] or 0) + 1 end
  local cw, ch = canvas:GetWidth(), canvas:GetHeight()
  for i, q in ipairs(pts) do
    local b = pool[i] or newPin(i)
    b.q, b.small = q, per[q.questID] > 3
    b.num:SetText(b.small and "" or q.complete and "?" or tostring(q.number))
    if P.selected == q.questID then b.glow:Show() else b.glow:Hide() end
    b:ClearAllPoints(); b:SetPoint("CENTER", canvas, "TOPLEFT", q.x * cw, -q.y * ch)
    b:Show()
  end
  for i = #pts + 1, #pool do pool[i].q = nil; pool[i]:Hide() end
  P.shown = #pts
  P.Layout(true)
  P.FixArrow()
  return #pts
end

---------------------------------------------------------------- party members
-- Party members on the map as class-coloured circles, the look of a raid's blips. The client draws a flat party blip for them: its group pin is told to hide those and ours
-- are drawn on the canvas from C_Map.GetPlayerMapPosition (when that call is missing the client's own blips stay, with the class-colour attempt of P.ClassCircles).
local CIRCLE = "Interface\\AddOns\\AztraForeverUI\\Media\\plain\\UI-MapPartyCircle"
function P.GroupPins() return groupPins end

local function newGroupPin(i)
  local b = CreateFrame("Button", nil, canvas)
  b:SetWidth(GROUP_SIZE); b:SetHeight(GROUP_SIZE)
  b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints(b); b.tex:SetTexture(CIRCLE)
  b:SetScript("OnEnter", function(self)
    if self.unit and UnitExists(self.unit) then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(UnitName(self.unit) or "", 1, 1, 1); GameTooltip:Show() end
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  groupPins[i] = b
  return b
end

-- the client's own party blips on or off (its group pin: SetShouldShowUnits("party", ...)); re-applied after the client's own UpdateShownUnits
local nativeHooked
local function nativeParty(show)
  local pin = P.unitPinFrame()
  if not (pin and type(pin.SetShouldShowUnits) == "function") then return end
  pcall(pin.SetShouldShowUnits, pin, "party", show)
  if not nativeHooked and type(pin.UpdateShownUnits) == "function" then
    nativeHooked = true
    hooksecurefunc(pin, "UpdateShownUnits", function() if groupOn then pcall(pin.SetShouldShowUnits, pin, "party", false) end end)
  end
end

-- Where a party member is on map `mapID`: the client's own answer first; when it has none (the member is in another zone, and this map is the continent or the zone the
-- member is in), the member's world position is converted onto the map. Returns x, y in 0..1 or nil.
function P.GroupPosition(mapID, unit)
  local x, y
  local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, unit)
  if ok and type(pos) == "table" then if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end end
  if x and y and (x ~= 0 or y ~= 0) then return x, y end
  if _G.UnitPosition and type(C_Map.GetMapPosFromWorldPos) == "function" and type(_G.CreateVector2D) == "function" then
    local wy, wx, _, inst = UnitPosition(unit)
    if wx and wy and inst then
      local ok2, _, p2 = pcall(C_Map.GetMapPosFromWorldPos, inst, CreateVector2D(wx, wy), mapID)
      if ok2 and type(p2) == "table" then
        local px, py
        if p2.GetXY then px, py = p2:GetXY() else px, py = p2.x, p2.y end
        if px and py and px >= 0 and px <= 1 and py >= 0 and py <= 1 and (px ~= 0 or py ~= 0) then return px, py end
      end
    end
  end
end

function P.UpdateGroup(force)
  if not (canvas and wm) then return 0 end
  local now = GetTime and GetTime() or 0
  if not force and now - groupAt < 0.1 then return #groupPins end
  groupAt = now
  local mapID = wm.GetMapID and wm:GetMapID()
  local want = mapID and _G.C_Map and type(C_Map.GetPlayerMapPosition) == "function" and AFUI.GetSetting("mapGroupCircles", true) ~= false
    and AFUI.RaidSize() == 0 and UnitExists("party1")
  local n = 0
  if want then
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    for i = 1, 4 do
      local unit = "party" .. i
      if UnitExists(unit) and (not UnitIsConnected or UnitIsConnected(unit)) then
        local x, y = P.GroupPosition(mapID, unit)
        if x and y then
          n = n + 1
          local b = groupPins[n] or newGroupPin(n)
          b.unit = unit
          local _, class = UnitClass(unit)
          local c = class and _G.RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
          if c then b.tex:SetVertexColor(c.r, c.g, c.b) else b.tex:SetVertexColor(1, 1, 1) end
          b:SetAlpha(UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) and 0.55 or 1)
          b.nx, b.ny = x, y
          anchor(b, x, y)
          b:Show()
        end
      end
    end
  end
  for i = n + 1, #groupPins do groupPins[i].unit = nil; groupPins[i].nx = nil; groupPins[i]:Hide() end
  local on = want and n > 0 and true or false
  if on ~= groupOn then groupOn = on; nativeParty(not on) end
  if n > 0 then P.Layout(true) end
  return n
end

-- The player arrow: the client's unit pin (a canvas child with the UnitPositionFrame methods) is sized for the client's own, larger map; ours is smaller, so
-- the arrow is set to ARROW UI units on screen whatever the pin's scale (it changes with the zoom: re-applied from the scale hook and from Refresh / Layout).
-- Party members on the map: the client draws a party blip; in a raid (and instances) every member is a circle in the class colour. The party gets the same circle and
-- colour: the pin's appearance fields for "party" (texture, useClassColor) are set now and again after each of the client's own appearance updates.
-- /afui mappin: what the map's group member pin offers (its method names with Appearance / Color / Texture / Pin / Unit in them, and whether ours applied), for
-- when the class-coloured party circles do not show.
function P.PinReport()
  local pin = P.unitPinFrame and P.unitPinFrame()
  if not pin then return "no group member pin found on the map canvas (open the map first)" end
  local names, seen = {}, {}
  local function scan(t) for k, v in pairs(t) do if type(k) == "string" and type(v) == "function" and not seen[k] and k:find("Appearance") or (type(k) == "string" and type(v) == "function" and not seen[k] and (k:find("Color") or k:find("Texture") or k:find("Pin") or k:find("Unit"))) then seen[k] = true; names[#names + 1] = k end end end
  scan(pin)
  local mt = getmetatable(pin)
  if mt and type(mt.__index) == "table" then scan(mt.__index) end
  table.sort(names)
  return "applied=" .. tostring(pin.afClassCircles) .. " methods: " .. table.concat(names, ",")
end
-- /afui mappos: each party member's position as the client gives it (on the shown map, and as world coordinates), for when the circles do not show in another zone.
AFUI.Slash.Register("mappos", function()
  local wm = _G.WorldMapFrame
  local mapID = wm and wm.GetMapID and wm:GetMapID()
  AFUI.Print("mappos: shown map " .. tostring(mapID) .. ", your zone " .. tostring(C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")))
  for i = 1, 4 do
    local u = "party" .. i
    if UnitExists(u) then
      local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, u)
      local px, py
      if ok and type(pos) == "table" then if pos.GetXY then px, py = pos:GetXY() else px, py = pos.x, pos.y end end
      local wy, wx, wz, inst = UnitPosition and UnitPosition(u)
      local gx, gy = P.GroupPosition(mapID, u)
      AFUI.Print(string.format("  %s: on map %s, world %s %s inst %s, used %s", u, px and string.format("%.3f,%.3f", px, py) or "nil", tostring(wx and math.floor(wx)), tostring(wy and math.floor(wy)), tostring(inst), gx and string.format("%.3f,%.3f", gx, gy) or "none"))
    end
  end
end, "where the client puts each party member on the shown map", "/afui mappos")
AFUI.Slash.Register("mappin", function() AFUI.Print("mappin: " .. P.PinReport()) end, "what the world map's group member pin offers (for the party circles)", "/afui mappin")

function P.ClassCircles(pin)
  if not pin or pin.afClassCircles or type(pin.SetAppearanceField) ~= "function" then return false end
  pin.afClassCircles = true
  local function apply()
    pcall(pin.SetAppearanceField, pin, "party", "texture", "WhiteCircle-RaidBlips")
    pcall(pin.SetAppearanceField, pin, "party", "useClassColor", true)
    if type(pin.SetPinTexture) == "function" then pcall(pin.SetPinTexture, pin, "party", "WhiteCircle-RaidBlips") end
  end
  apply()
  if type(pin.UpdateAppearanceData) == "function" then hooksecurefunc(pin, "UpdateAppearanceData", apply) end
  if type(pin.SetNeedsFullUpdate) == "function" then pcall(pin.SetNeedsFullUpdate, pin) end
  return true
end

local unitPin
function P.unitPinFrame() return unitPin end
function P.FixArrow()
  if not (canvas and type(canvas.GetChildren) == "function") then return false end
  if not unitPin then
    for _, ch in ipairs({ canvas:GetChildren() }) do
      if type(ch.SetPinSize) == "function" and type(ch.SetPinTexture) == "function" then unitPin = ch; break end
    end
    if not unitPin then return false end
    -- The client's GroupMembersPinMixin ignores the global pin scale (ApplyCurrentScale never runs for it) and resets each unit size to 16 / canvasScale in
    -- SynchronizePinSizes: on acquire and on every canvas size / scale change. That is why the arrow was tiny until the first zoom: re-apply after each call.
    for _, name in ipairs({ "SynchronizePinSizes", "ApplyCurrentScale" }) do
      if type(unitPin[name]) == "function" then hooksecurefunc(unitPin, name, function() P.FixArrow() end) end
    end
  end
  P.ClassCircles(unitPin)
  local k = unitPin:GetEffectiveScale() / UIParent:GetEffectiveScale()
  P.arrowSize = ARROW / math.max(k, 0.01)
  pcall(unitPin.SetPinSize, unitPin, "player", P.arrowSize)
  return true
end

-- A click on a quest title or its pin: the client's selection, and the pin lights up.
function P.Select(questID, index)
  P.selected = questID
  if index and SelectQuestLogEntry then SelectQuestLogEntry(index) end
  if _G.C_SuperTrack and type(C_SuperTrack.SetSuperTrackedQuestID) == "function" and questID then pcall(C_SuperTrack.SetSuperTrackedQuestID, questID) end
  P.Refresh()
end

-- wm = WorldMapFrame, sc = its ScrollContainer (the 2.5.3 canvas; nothing on 2.4.3, which has no canvas child to draw on).
function P.Setup(map, sc)
  if canvas or not (map and sc and type(sc.Child) == "table") then return end
  wm, scroll, canvas = map, sc, sc.Child
  -- the quest events are frequent and each refresh reads the whole log: only while the map is open (OnShow paints it when it opens)
  local function onQuestEvent() if map:IsShown() then P.Refresh() end end
  for _, ev in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_POI_UPDATE", "UNIT_QUEST_LOG_CHANGED" }) do AFUI.On(ev, onQuestEvent) end
  if map.HookScript then map:HookScript("OnShow", function() P.Refresh(); if C_Timer and C_Timer.After then C_Timer.After(0, P.FixArrow) end end) end
  if AFUI.MapChangedHooks then table.insert(AFUI.MapChangedHooks, function() P.Refresh() end) end
  AFUI.OnSettingChanged("mapQuestPins", function() P.Refresh() end)
  P.Refresh() -- P.Layout runs from WorldMap.lua's canvas OnUpdate (zoom changes the pins' scale)
end
