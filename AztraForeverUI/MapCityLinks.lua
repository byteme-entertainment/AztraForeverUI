-- Clickable cities the client does not make clickable (2.5.3 world map).
-- Why: Terokkar Forest's child maps in the client are only the six Auchindoun dungeons (rect 0), so clicking Shattrath City on the Terokkar map finds no map
-- and does nothing. Each entry puts a transparent button over the city's icon on the canvas (pan / zoom / clipping stay the client's); a click opens the city's map
-- through the same navigation as the breadcrumb. x, y are fractions of the canvas, measured with /afui maphit on the real client.
AFUI = AFUI or {}
local L = {}
AFUI.MapCityLinks = L
L.LINKS = { [1952] = { { id = 1955, x = 0.29, y = 0.22, name = "Shattrath City" } } } -- Terokkar Forest -> Shattrath City
L.SIZE = 0.05 -- the button's side, as a fraction of the canvas width
local btns = {}

local function canvas()
  local wm = _G.WorldMapFrame
  local sc = wm and wm.ScrollContainer
  local ch = sc and sc.Child
  return wm, type(ch) == "table" and ch or nil -- the preview's and 2.4.3's frames have no canvas child (a method, or nothing)
end

local function new(i, parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetFrameLevel(parent:GetFrameLevel() + 8)
  b:RegisterForClicks("LeftButtonUp")
  b:SetScript("OnClick", function(self)
    local wm = canvas()
    if self.link and wm then AFUI.MapNavigate(wm, self.link.id) end
  end)
  b:SetScript("OnEnter", function(self)
    if not self.link then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.link.name, 1, 0.82, 0); GameTooltip:AddLine("Click to open the city map", 1, 1, 1); GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  btns[i] = b
  return b
end

function L.Refresh()
  local wm, ch = canvas()
  if not (wm and ch and wm.GetMapID) then return 0 end
  local list = L.LINKS[wm:GetMapID()] or {}
  local cw, chh = ch:GetWidth(), ch:GetHeight()
  for i, l in ipairs(list) do
    local b = btns[i] or new(i, ch)
    b.link = l
    b:ClearAllPoints(); b:SetWidth(L.SIZE * cw); b:SetHeight(L.SIZE * cw)
    b:SetPoint("CENTER", ch, "TOPLEFT", l.x * cw, -l.y * chh)
    b:Show()
  end
  for i = #list + 1, #btns do btns[i].link = nil; btns[i]:Hide() end
  return #list
end

local wired
function L.Setup()
  if wired then return end
  local wm = canvas()
  if not (wm and AFUI.MapChangedHooks) then return end
  wired = true
  table.insert(AFUI.MapChangedHooks, function() L.Refresh() end)
  if wm.HookScript then wm:HookScript("OnShow", function() L.Refresh() end) end
  L.Refresh()
end
