-- Third-party addons that hang their own frames on the client's CharacterFrame / PaperDollFrame (Outfitter, ...). Our Character window IS the client's
-- CharacterFrame (631 x 484, 398 collapsed), so a frame anchored to it follows the window; but those addons placed their frames for the old 384 x 512 art,
-- and the places they chose are now our right pane header, our mode tabs. One adapter per known addon re-seats its frames; /afui compat prints the state.
-- Adapters move the addon's own frames (anchor, scale, strata, level) and hook its show / open calls to redo that; nothing is hidden or killed, so the addon keeps working.
local AFUI = AFUI
local AC = {}
AFUI.AddonCompat = AC

AC.adapters = {}
function AC.Register(name, adapter) adapter.name = name; AC.adapters[#AC.adapters + 1] = adapter end

local function isLoaded(name) return IsAddOnLoaded and IsAddOnLoaded(name) and true or false end
local function g(n) return _G[n] end

---------------------------------------------------------------- Outfitter
-- The TBC-era Outfitter the tester runs (title bar "Outfitter 2.0.4") could not be found to read; cdmichaelb/Outfitter 3.0.4 (Outfitter.xml:578-1062, Outfitter.lua:1198-1201,
-- 6208, OutfitterMinimapButton.lua) is the nearest source, and a tester screenshot shows the same layout: OutfitterFrame is a child of OutfitterButtonFrame (child of
-- PaperDollFrame), TOPLEFT at the paper doll's TOPRIGHT (-34 in 3.0.4, about +3 in the screenshot) / -48, and its OnShow sets its frame level to PaperDollFrame's - 1,
-- so it is drawn UNDER our mode tabs (level base + 6) and our window. We anchor it past the tabs, lift it with its whole tree above everything of ours, and redo both
-- after every OnShow / open call of Outfitter and every size change of our window. Every name is tried, whatever exists is used.
local OUTFITTER_PANEL_X, OUTFITTER_PANEL_Y = 2, -48 -- past the mode tabs, Outfitter's own y
local OUTFITTER_BUTTON = { "TOPRIGHT", "BOTTOMRIGHT", -20, 2 } -- hangs from the window's bottom edge: free in the full and the collapsed window
local LIFT = 60 -- levels above our window: our own highest is +30 (the close button)
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local PANELS = { "OutfitterFrame" }
local BUTTONS = { "OutfitterButton" }
local ROOTS = { "OutfitterFrameTab1", "OutfitterFrameTab2", "OutfitterFrameTab3" } -- tabs that are not under the panel are lifted on their own
local OPENERS = { { "Outfitter", { "OpenUI", "ToggleUI", "ToggleOutfitterFrame", "ShowPanel" } },
  { false, { "Outfitter_Toggle", "Outfitter_Open", "Outfitter_OpenUI", "Outfitter_ToggleOutfitterFrame", "Outfitter_ShowPanel" } } }
local offsets = setmetatable({}, { __mode = "k" }) -- child level minus parent level, remembered the first time so a re-lift is idempotent

local function first(names) for _, n in ipairs(names) do local f = g(n); if f and f.SetPoint then return f end end end

-- f is at least at `level` (top) or exactly there (a child); its children keep their own distance above it.
local function lift(f, level, top)
  if not (f and f.GetFrameLevel and f.SetFrameLevel) then return end
  if not top or f:GetFrameLevel() < level then f:SetFrameLevel(level) end
  if f.GetChildren then
    for _, k in ipairs({ f:GetChildren() }) do
      if type(k) == "table" and k.GetFrameLevel then
        local off = offsets[k]
        if not off then off = math.max(1, k:GetFrameLevel() - f:GetFrameLevel()); offsets[k] = off end
        lift(k, f:GetFrameLevel() + off)
      end
    end
  end
end

local function raise(f, cf)
  local want, have = cf:GetFrameStrata(), f.GetFrameStrata and f:GetFrameStrata()
  if have and (STRATA[have] or 0) < (STRATA[want] or 0) then f:SetFrameStrata(want) end
  lift(f, cf:GetFrameLevel() + LIFT, true)
end

local function moveOutfitter()
  local cf = _G.CharacterFrame
  if not cf then return end
  local panel, button = first(PANELS), first(BUTTONS)
  if panel then
    local tabW = AFUI.CharacterFrame and AFUI.CharacterFrame.TAB_W or 55
    panel:ClearAllPoints(); panel:SetPoint("TOPLEFT", cf, "TOPRIGHT", tabW + OUTFITTER_PANEL_X, OUTFITTER_PANEL_Y)
    local pe, ce = panel.GetEffectiveScale and panel:GetEffectiveScale(), cf.GetEffectiveScale and cf:GetEffectiveScale()
    if pe and ce and pe > 0 and math.abs(pe / ce - 1) > 0.01 then panel:SetScale(panel:GetScale() * ce / pe) end -- a panel outside the window's scale chain keeps its size next to it
    raise(panel, cf)
  end
  if button then
    button:ClearAllPoints(); button:SetPoint(OUTFITTER_BUTTON[1], cf, OUTFITTER_BUTTON[2], OUTFITTER_BUTTON[3], OUTFITTER_BUTTON[4])
    raise(button, cf)
  end
  for _, n in ipairs(ROOTS) do local t = g(n); if t and not (panel and t.GetParent and t:GetParent() == panel) then raise(t, cf) end end
  if AFUI.RaiseMinimapAddons then AFUI.RaiseMinimapAddons() end -- OutfitterMinimapButton hangs off MinimapBackdrop: Minimap.lua lifts it by name
end

-- Outfitter re-anchors / re-levels the panel in its own OnShow and open functions: ours runs after them (HookScript / hooksecurefunc), hooked once per frame / function.
local hooked = {}
local function reapply() AFUI.RunOutOfCombat(moveOutfitter) end
local function hookOutfitter()
  for _, f in ipairs({ first(PANELS) or false, first(BUTTONS) or false }) do
    if f and f.HookScript and not hooked[f] then hooked[f] = true; f:HookScript("OnShow", reapply) end
  end
  for _, set in ipairs(OPENERS) do
    local t = set[1] and g(set[1]) or _G
    if type(t) == "table" and hooksecurefunc then
      for _, fn in ipairs(set[2]) do
        local key = tostring(t) .. fn
        if type(t[fn]) == "function" and not hooked[key] then hooked[key] = true; pcall(hooksecurefunc, t, fn, reapply) end
      end
    end
  end
end

AC.Register("Outfitter", {
  present = function() return isLoaded("Outfitter") or g("OutfitterFrame") ~= nil end,
  apply = function() hookOutfitter(); moveOutfitter() end,
  frames = { "OutfitterButtonFrame", "OutfitterButton", "OutfitterFrame", "OutfitterMainFrame", "OutfitterFrameTab1", "OutfitterFrameTab2", "OutfitterFrameTab3", "OutfitterSlotEnables", "OutfitterMinimapButton" },
})

-- Loaded-only entries: no frames of ours to re-seat, listed so /afui compat shows what is around.
for _, n in ipairs({ "ItemRack", "Questie", "Bagnon", "ElvUI", "Pawn", "Bartender4" }) do
  AC.Register(n, { present = function() return isLoaded(n) end })
end

---------------------------------------------------------------- state of a frame, for the report
local function nameOf(f) return f and f.GetName and f:GetName() or (f and "?") or "nil" end
local function num(v) return type(v) == "number" and (math.floor(v * 10 + 0.5) / 10) or v end

function AC.Describe(f)
  if not f then return { exists = false } end
  local d = { exists = true, shown = f:IsShown() and true or false, parent = f.GetParent and nameOf(f:GetParent()) or "?", anchors = {} }
  if f.IsVisible then d.visible = f:IsVisible() and true or false end
  d.strata, d.level, d.alpha, d.scale = f.GetFrameStrata and f:GetFrameStrata(), f.GetFrameLevel and f:GetFrameLevel(), f.GetAlpha and num(f:GetAlpha()), f.GetEffectiveScale and num(f:GetEffectiveScale())
  local n = f.GetNumPoints and f:GetNumPoints() or (f.points and #f.points) or 0
  for i = 1, n do
    local p, rel, rp, x, y = f:GetPoint(i)
    d.anchors[#d.anchors + 1] = tostring(p) .. "->" .. nameOf(rel) .. ":" .. tostring(rp) .. " " .. tostring(num(x)) .. "," .. tostring(num(y))
  end
  d.left, d.bottom, d.w, d.h = f.GetLeft and num(f:GetLeft()), f.GetBottom and num(f:GetBottom()), f.GetWidth and num(f:GetWidth()), f.GetHeight and num(f:GetHeight())
  return d
end

local function line(label, d)
  if not d.exists then return label .. ": does not exist" end
  return label .. ": shown=" .. tostring(d.shown) .. " visible=" .. tostring(d.visible) .. " parent=" .. tostring(d.parent) .. " " .. tostring(d.strata) .. "/" .. tostring(d.level)
    .. " alpha=" .. tostring(d.alpha) .. " scale=" .. tostring(d.scale) .. " left=" .. tostring(d.left) .. " bottom=" .. tostring(d.bottom) .. " " .. tostring(d.w) .. "x" .. tostring(d.h)
    .. " [" .. table.concat(d.anchors, " | ") .. "]"
end

-- Returns { lines } and prints them. For each known addon: loaded or not; for adapters with frames, the frames' state plus the window and mode tabs they sit next to (strata/level).
function AC.Report(print_)
  local out = {}
  local function add(s) out[#out + 1] = s end
  add("AFUI compat")
  local any = false
  for _, a in ipairs(AC.adapters) do
    local here = a.present and a.present() and true or false
    if here then any = true end
    add(a.name .. ": " .. (here and "LOADED" or "not loaded"))
    if here and a.frames then
      add("  " .. line("CharacterFrame", AC.Describe(_G.CharacterFrame)))
      add("  " .. line("PaperDollFrame", AC.Describe(_G.PaperDollFrame)))
      add("  " .. line("AFUI_CharacterWindow", AC.Describe(_G.AFUI_CharacterWindow)))
      add("  " .. line("AFUI_CharacterModeTab1", AC.Describe(_G.AFUI_CharacterModeTab1)))
      for _, n in ipairs(a.frames) do add("  " .. line(n, AC.Describe(_G[n]))) end
    end
  end
  if not any then add("no known third-party addons loaded") end
  if print_ ~= false then for _, s in ipairs(out) do AFUI.Print(s) end end
  return out
end

function AC.Apply()
  for _, a in ipairs(AC.adapters) do
    if a.apply and a.present and a.present() then AFUI.RunOutOfCombat(a.apply) end
  end
end

AFUI.RegisterModule("AddonCompat", {
  OnLogin = function()
    AC.Apply()
    if _G.CharacterFrame and CharacterFrame.HookScript then
      CharacterFrame:HookScript("OnShow", AC.Apply)
      CharacterFrame:HookScript("OnSizeChanged", AC.Apply) -- collapse / expand
    end
  end,
})
AFUI.On("ADDON_LOADED", function() if AC.loggedIn then AC.Apply() end end)
AFUI.On("PLAYER_LOGIN", function() AC.loggedIn = true end)
AFUI.On("UI_SCALE_CHANGED", function() if AC.loggedIn then AC.Apply() end end)
AFUI.On("DISPLAY_SIZE_CHANGED", function() if AC.loggedIn then AC.Apply() end end)

if AFUI.Slash and AFUI.Slash.Register then
  AFUI.Slash.Register("compat", function() AC.Report() end, "which third-party addons are loaded and where Outfitter's frames are, with strata / level next to our window and tabs (paste it in a bug report)", "/afui compat")
end
