-- Forever's Group Finder ("Looking For Group"): the client's own LFGParentFrame (the Looking for Group tab and the Looking for More tab, plus 2.4.3's
-- start wizard) inside Forever's metal portrait frame with the eye in the ring, the red X, the two tabs as side tabs on the right edge with their icons,
-- dark stone interior, red buttons (Post / Done, Clear All, Search, Send Message, Group Invite), Forever's dark dropdowns, gold sortable column headers,
-- minimal scroll bar. Every Blizzard behaviour stays: the type / activity dropdowns, Post / Done, Clear All, auto-join, the list, invite and whisper.
-- REAL Forever captures (Warcraft Tavern, https://www.warcrafttavern.com/forever/news/no-group-finder-or-summoning-stones-in-wow-forever/, saved in
-- docs/forever-ref/screens/windows/lfg-*-warcrafttavern.jpg): "Looking For Group" title, the green eye in the portrait ring, red X, two side tabs (a helm and
-- a group), a role bar (tank / healer / damage / leader) over dark stone, category buttons (Dungeons, Quests & Zones, Battlegrounds, Custom) or the dungeon
-- list with gold names and level ranges, Back / List Self at the bottom; the browse page has a Category and a Filter by activity dropdown, a refresh button,
-- "No groups found..." over the dark stone, Send Message / Group Invite at the bottom. Forever's code: blizzard_groupfinder_vanillastyle/ (listing, browse,
-- parentframe), the Classic-style LFG tool. 2.5.3's tool is C_LFGList-based (Blizzard_LFGFrame.lua: categories, activities, up to 3 per listing, NO roles), so
-- its LFG tab is rebuilt as Forever's category cards -> checkbox list (see "Forever's pages" below; the role row of the real window is left out: it has no
-- function here) and its LFM tab keeps the client's own dropdowns / list / buttons in Forever's frame. 2.4.3 keeps the older layout dressed in the frame.
-- Art: Forever's groupfinder-* sprites (tools/lfg-art.mjs -> Media/lfg). Reference: docs/forever-ref/video2/mat-shots/forever-lfg.png.
-- Frame names (verified): 2.4.3 MOUZU/Blizzard-WoW-Interface 2.4.3/FrameXML/LFGFrame.{xml,lua} (always loaded) and Gethe/wow-ui-source tag 2.5.3
-- Interface/AddOns/Blizzard_LookingForGroupUI/Blizzard_LFGFrame.{xml,lua} (load on demand): LFGParentFrame (384x512), LFGParentFrameTab1 / Tab2,
-- LFGFrame (LFGFrameTypeDropDown1-3 + LFGFrameNameDropDown1-3 [2.4.3] / LFGFrameActivityDropDown1-3 [2.5.3], LFGComment, LFGFrameClearAllButton,
-- LFGFrameDoneButton [2.4.3] / LFGFramePostButton [2.5.3], AutoJoinCheckButton, LFGEye), LFMFrame (LFMFrameTypeDropDown, LFMFrameNameDropDown [2.4.3] /
-- LFMFrameActivityDropDown + LFMFrameInset [2.5.3], LFMFrameColumnHeader1-4, LFMFrameButton1-14 [2.4.3] / 1-16 [2.5.3], LFMListScrollFrame,
-- LFMFrameSearchButton, LFMFrameSendMessageButton, LFMFrameGroupInviteButton, AutoAddMembersCheckButton, LFMEye), LFGWizardFrame [2.4.3].
AFUI = AFUI or {}
local G = {}
AFUI.GroupFinder = G

-- Forever's groupfinder-* sprites live inside power-of-two pages (Media\LfgArt.lua, tools/lfg-art.mjs) and are drawn by atlas name with AFUI.SetAtlas. A single
-- file of any other size is drawn by the client as a solid green square (round 23), so no sprite is ever a file of its own.
G.ICON = "groupfinder-eye-frame"
G.TITLE = "Looking For Group"
G.CUT = 62 -- both clients' frames are 512 px tall and stop their widgets 62 px above the bottom
G.WIDTH = 462 -- Forever's own Group Finder is wider than the client's 384 px frame (the reference capture: 462 logical px of metal frame at 1.40625)
G.TABS = { { "LFGParentFrameTab1", "groupfinder-eye-single" }, { "LFGParentFrameTab2", "Interface\\Icons\\INV_Misc_Spyglass_03" } }

G.BUTTONS = { "LFGFrameDoneButton", "LFGFramePostButton", "LFGFrameClearAllButton", "LFMFrameSearchButton", "LFMFrameSendMessageButton", "LFMFrameGroupInviteButton",
  "LFGWizardFrameLFGButton", "LFGWizardFrameLFMButton" }
G.DROPDOWNS = { "LFGFrameTypeDropDown1", "LFGFrameTypeDropDown2", "LFGFrameTypeDropDown3", "LFGFrameNameDropDown1", "LFGFrameNameDropDown2", "LFGFrameNameDropDown3",
  "LFGFrameActivityDropDown1", "LFGFrameActivityDropDown2", "LFGFrameActivityDropDown3", "LFMFrameTypeDropDown", "LFMFrameNameDropDown", "LFMFrameActivityDropDown" }
G.HEADERS = { "LFMFrameColumnHeader1", "LFMFrameColumnHeader2", "LFMFrameColumnHeader3", "LFMFrameColumnHeader4" }
G.HIDE = { "LFMFrameInset", "AutoJoinBackground", "AddMemberBackground", "LFGParentFrameBg", "LFGSearchIcon1Shine", "LFGSearchIcon2Shine", "LFGSearchIcon3Shine" }
G.PAGES = { "LFGFrame", "LFMFrame", "LFGWizardFrame" }
G.CHECKS = { "AutoJoinCheckButton", "AutoAddMembersCheckButton" }
-- list rows: 14 on 2.4.3, 16 on 2.5.3
G.ROWS = { ["2.4.3"] = 14, ["2.5.3"] = 16 }

function G.RowNames(client) return AFUI.WinKit.Numbered("LFMFrameButton", G.ROWS[client] or 14) end

-- UIPanelWindows 2.5.3: LFGParentFrame xoffset -16, yoffset 12, width 353, height 424 (2.4.3 has none, see QuestLog.lua): the metal frame is 384 x (512 - cut)
G.PANEL = { width = AFUI.IS_243 and 384 or G.WIDTH, height = 512 - G.CUT, xoffset = 8 }

local K = AFUI.WinKit
local done

-- Forever lists Who as the third tab of this window. The client's WhoFrame is tab 2 of FriendsFrame (WhoList_Update re-selects it and opens FriendsFrame on every
-- result, row click and scroll), so the list stays in the Social window, where it also has a Who side tab: this third tab swaps this window for it
-- (ShowWhoPanel only selects tab 2 and shows the panel) and nothing here touches the client's tab logic.
G.WHO = { icon = "Interface\\Icons\\INV_Misc_GroupLooking", tip = "Who List" }
function G.OpenWho()
  local f = _G.LFGParentFrame
  if f and f:IsShown() and _G.HideUIPanel then HideUIPanel(f) end
  if type(_G.ShowWhoPanel) == "function" then ShowWhoPanel() elseif type(_G.ToggleFriendsFrame) == "function" then ToggleFriendsFrame(2) end
end
function G.WhoTab(f)
  if AFUI.IS_243 then return end -- 2.4.3 keeps its own Who tab in the Social window
  local b = CreateFrame("Button", "LFGParentFrameWhoTab", f)
  K.sideTab(b, f, #G.TABS + 1, G.WHO.icon, G.WHO.tip)
  b:SetScript("OnClick", G.OpenWho)
end

local function findClose(f) -- 2.5.3's LFGParentFrame close button is a nameless UIPanelCloseButton on the TOPRIGHT corner
  if _G.LFGParentFrameCloseButton then return _G.LFGParentFrameCloseButton end
  for _, c in ipairs({ f:GetChildren() }) do
    if c.GetObjectType and c:GetObjectType() == "Button" and not c:GetName() and (c:GetPoint()) == "TOPRIGHT" then return c end
  end
end

---------------------------------------------------------------- Forever's pages (2.5.3: the C_LFGList tool)
-- 2.5.3's tool is Blizzard_LFGFrame.lua: LFGFrame lists up to 3 activities (C_LFGList.CreateListing / UpdateListing / RemoveListing with an array of 3 activity
-- ids, 0 = empty) picked from categories (GetAvailableCategories / GetAvailableActivities); there are NO roles. Forever's page is category cards, then a list of
-- checkboxes, Back / Clear All / List Self. The page keeps its own picks (G.sel) and sends them through the same C_LFGList calls LFGFrame:CreateOrUpdateListing
-- makes; the client's dropdowns are never driven (calling UIDropDownMenu_* from here would taint the menu globals), only hidden. The comment box is the
-- client's own LFGComment (a secure edit box: its text is read by the client when the listing is made), moved onto the page.
G.MAX = 3
G.sel, G.view, G.cat = {}, "cards", nil
G.ROWS_SHOWN, G.ROW_H = 13, 23
-- Cards share the height between the page's top (y) and the button row (bottom): at most MAXCARDS, each one pitch tall (card + gap), so the last card never
-- reaches the Back / Clear All / List Self row (the client lists 6 categories: Dungeon .. Zone). banner = { w, h, cover w, cover h } of the sprites.
G.CARD = { w = 406, h = 50, x = 28, y = 68, gap = 6, bottom = 46, banner = { 290, 36, 300, 46 } }
G.MAXCARDS = 8
function G.CardPitch(n)
  local C = G.CARD
  local avail = (512 - G.CUT) - C.bottom - C.y -- the frame is 450 tall; the button row needs the last 46
  return math.min(C.h + C.gap, math.floor(avail / math.max(n, 1)))
end

-- Which banner a category gets (matched on the client's own category name; Forever's four are Dungeons, Quests & Zones, Battlegrounds, Custom).
local BANNERS = { { "dungeon", "dungeons" }, { "raid", "raids-warlords" }, { "quest", "questing" }, { "zone", "questing" }, { "battleground", "battlegrounds" },
  { "arena", "arenas" }, { "pvp", "custom-pvp" } }
function G.Banner(name)
  local n = string.lower(name or "")
  for _, b in ipairs(BANNERS) do if n:find(b[1], 1, true) then return "groupfinder-button-" .. b[2] end end
  return "groupfinder-button-custom-pve"
end

-- Every C_LFGList call goes through here: a missing function or one the client rejects (pcall) gives the default instead of an error, and a listing the client
-- will not take is kept on this page only (G.local_, labelled by the hint) so the page never errors and never shows garbage.
function G.Q(name, default, ...)
  local fn = _G.C_LFGList and C_LFGList[name]
  if type(fn) ~= "function" then return default end
  local r = { pcall(fn, ...) }
  if not r[1] or r[2] == nil then return default end
  return unpack(r, 2)
end
function G.Call(name, ...)
  local fn = _G.C_LFGList and C_LFGList[name]
  if type(fn) ~= "function" then return false end
  return (pcall(fn, ...))
end
function G.HasActive()
  if G.local_ then return true end
  return G.Q("HasActiveEntryInfo", false) and true or false
end

function G.Selected(id) for i, v in ipairs(G.sel) do if v == id then return i end end end
function G.Full() return #G.sel >= G.MAX end
-- Toggle an activity: unchecking always works, checking stops at 3 (the client's 3 slots). Returns the new state, or nil when refused.
function G.Toggle(id)
  local at = G.Selected(id)
  if at then table.remove(G.sel, at); return false end
  if G.Full() then return nil end
  G.sel[#G.sel + 1] = id
  return true
end

-- The listing the client holds now: { ids } (nonzero), from C_LFGList.GetActiveEntryInfo().activityIDs.
function G.Active()
  if G.local_ then return { unpack(G.local_) } end
  local out, info = {}, G.Q("GetActiveEntryInfo", nil)
  for _, id in ipairs(type(info) == "table" and info.activityIDs or {}) do if id and id ~= 0 then out[#out + 1] = id end end
  return out
end
function G.ReadOnly() return IsInGroup and IsInGroup(LE_PARTY_CATEGORY_HOME) and not UnitIsGroupLeader("player", LE_PARTY_CATEGORY_HOME) end
function G.Dirty()
  if G.commentDirty then return true end
  local a = G.Active()
  if #a ~= #G.sel then return true end
  for _, id in ipairs(a) do if not G.Selected(id) then return true end end
  return false
end
-- Same checks as LFGFrameMixin:UpdatePostButtonState: something changed, and the party still fits every picked activity. Returns ok, errorText.
function G.CanPost()
  if G.ReadOnly() then return false end
  if not G.Dirty() then return false end
  if #G.sel == 0 and not G.HasActive() then return false end
  if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_HOME) then
    local n = GetNumGroupMembers(LE_PARTY_CATEGORY_HOME)
    for _, id in ipairs(G.sel) do
      local max = select(8, G.Q("GetActivityInfo", nil, id))
      if max and max > 0 and n >= max then return false, string.format(_G.LFG_LIST_TOO_MANY_FOR_ACTIVITY or "Your group is too large for this activity (max %d).", max) end
    end
  end
  return true
end
-- LFGFrameMixin:CreateOrUpdateListing, with the picks of this page.
function G.Post()
  if not G.CanPost() then return end
  local ids = {}
  for i = 1, G.MAX do ids[i] = G.sel[i] or 0 end
  local ok = true
  if G.local_ then G.local_ = #G.sel > 0 and { unpack(G.sel) } or nil
  elseif G.HasActive() then
    if #G.sel > 0 then ok = G.Call("UpdateListing", ids) else ok = G.Call("RemoveListing") end
  elseif #G.sel > 0 then
    ok = G.Call("CreateListing", ids)
  end
  if not ok then G.local_ = { unpack(G.sel) } end -- the client refused or has no such call: the listing is kept on this page only (see the hint)
  G.commentDirty = false
end
-- LFGFrameClearAllButton_OnClick: a listing is taken down; with none, the page is cleared.
function G.ClearAll()
  if G.local_ then G.local_ = nil; G.sel = {}
  elseif G.HasActive() then G.Call("RemoveListing")
  else G.sel = {}; G.commentDirty = false; G.Call("ClearCreationTextFields") end
  G.Refresh()
end
function G.Open(cat) G.view, G.cat, G.offset = "list", cat, 0; G.Refresh() end
function G.Back() G.view, G.cat = "cards", nil; G.Refresh() end
function G.LoadActive() G.sel = G.Active(); G.commentDirty = false; G.view, G.cat = "cards", nil; G.Refresh() end

-- one row of the activity list: { id, name, players }
function G.Activities(cat)
  local out = {}
  for _, id in ipairs(G.Q("GetAvailableActivities", {}, cat)) do
    local name, _, _, _, _, _, _, max = G.Q("GetActivityInfo", nil, id)
    out[#out + 1] = { id = id, name = name or ("#" .. id), players = (max and max > 0) and max or nil }
  end
  return out
end

local UI = {}
G.UI = UI
function G.SetTex(t, name) AFUI.SetAtlas(t, name) end -- name = a groupfinder-* sprite (texture file + the exact texcoords of the sprite inside its page)
local function tex(parent, layer, name, w, h)
  local t = parent:CreateTexture(nil, layer)
  AFUI.SetAtlas(t, name)
  if w then t:SetWidth(w); t:SetHeight(h) end
  return t
end
local function panelEdges(f, layer)
  for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local edge = f:CreateTexture(nil, layer); AFUI.SetColor(edge, 0.45, 0.37, 0.2, 1)
    edge:SetPoint(e[1], f, e[1], 0, 0); edge:SetPoint(e[2], f, e[2], 0, 0)
    if e[3] then edge:SetHeight(1) else edge:SetWidth(1) end
  end
end
-- Forever's dark page (groupfinder-background: the silhouettes on the cliff) as a region of `page`, framed with the 1 px bronze rule, between the metal frame's edges.
local function drawPanel(page, host)
  local bg = tex(page, "BACKGROUND", "groupfinder-background")
  bg:SetPoint("TOPLEFT", host, "TOPLEFT", 8, -60); bg:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -8, 8)
  local edge = CreateFrame("Frame", nil, page)
  edge:SetPoint("TOPLEFT", host, "TOPLEFT", 8, -60); edge:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -8, 8)
  panelEdges(edge, "BORDER")
  edge:EnableMouse(false)
  return bg
end

local function makeCard(page, host, i)
  local C = G.CARD
  local b = CreateFrame("Button", "AFUI_LFGCard" .. i, page)
  b:SetWidth(C.w); b:SetHeight(C.h)
  b.host = host
  b.banner = tex(b, "BACKGROUND", "groupfinder-button-custom-pve")
  b.cover = tex(b, "ARTWORK", "groupfinder-button-cover"); b.cover:SetAllPoints(b)
  b.hl = tex(b, "HIGHLIGHT", "groupfinder-button-highlight"); b.hl:SetBlendMode("ADD"); b.hl:SetAlpha(0.55)
  b.hl:SetPoint("TOPLEFT", b.banner, "TOPLEFT"); b.hl:SetPoint("BOTTOMRIGHT", b.banner, "BOTTOMRIGHT")
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  b.label:SetPoint("LEFT", b, "LEFT", 22, 0); b.label:SetJustifyH("LEFT")
  b.count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.count:SetPoint("RIGHT", b, "RIGHT", -22, 0)
  b:SetScript("OnMouseDown", function(self) G.SetTex(self.cover, "groupfinder-button-cover-down") end)
  b:SetScript("OnMouseUp", function(self) G.SetTex(self.cover, "groupfinder-button-cover") end)
  b:SetScript("OnClick", function(self) if self.catID then G.Open(self.catID) end end)
  return b
end

-- Places card i of n at the shared pitch; the banner sits inside the cover's frame (the cover is bigger than the banner by the same ratio at any height).
local function placeCard(b, i, n)
  local C = G.CARD
  local pitch = G.CardPitch(n)
  local h = pitch - C.gap
  b:SetHeight(h)
  b:ClearAllPoints(); b:SetPoint("TOPLEFT", b.host, "TOPLEFT", C.x, -(C.y + (i - 1) * pitch))
  local dx, dy = C.w * (C.banner[3] - C.banner[1]) / 2 / C.banner[3], h * (C.banner[4] - C.banner[2]) / 2 / C.banner[4]
  b.banner:ClearAllPoints()
  b.banner:SetPoint("TOPLEFT", b, "TOPLEFT", dx, -dy); b.banner:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -dx, dy)
end

local function makeRow(page, host, i)
  local r = CreateFrame("Button", "AFUI_LFGRow" .. i, page)
  r:SetWidth(410); r:SetHeight(G.ROW_H)
  r:SetPoint("TOPLEFT", host, "TOPLEFT", 18, -(70 + (i - 1) * G.ROW_H))
  r.check = CreateFrame("CheckButton", "AFUI_LFGRowCheck" .. i, r)
  r.check:SetWidth(20); r.check:SetHeight(20); r.check:SetPoint("LEFT", r, "LEFT", 4, 0)
  K.check(r.check)
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  r.name:SetPoint("LEFT", r.check, "RIGHT", 8, 0); r.name:SetWidth(210); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
  r.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.info:SetPoint("RIGHT", r, "RIGHT", -8, 0); r.info:SetJustifyH("RIGHT")
  K.row(r)
  local function click(self)
    local row = self.row or self
    if not row.activityID or G.ReadOnly() then return end
    if G.Toggle(row.activityID) == nil then G.Refused() end
    G.Refresh()
  end
  r.check.row = r
  r:SetScript("OnClick", click); r.check:SetScript("OnClick", click)
  r:SetScript("OnEnter", function(self)
    if not self.activityID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.activityName or "", 1, 1, 1)
    if self.players then GameTooltip:AddLine(string.format("Group size: %d", self.players), 0.8, 0.8, 0.8) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return r
end

function G.Refused() if _G.UIErrorsFrame then UIErrorsFrame:AddMessage(string.format("You can list up to %d activities.", G.MAX), 1, 0.1, 0.1) end end

local function setBack(on) if UI.back then if on then UI.back:Enable() else UI.back:Disable() end end end

function G.Refresh()
  if not UI.page then return end
  local cards = G.view == "cards"
  -- categories
  local cats = G.Q("GetAvailableCategories", {})
  local shown = math.min(#cats, #UI.cards)
  for i, c in ipairs(UI.cards) do
    local id = cats[i]
    if cards and id then
      local name = G.Q("GetCategoryInfo", nil, id)
      placeCard(c, i, shown)
      c.catID = id; c.label:SetText(name or ""); G.SetTex(c.banner, G.Banner(name)); c:Show()
      local n = 0
      for _, a in ipairs(G.Activities(id)) do if G.Selected(a.id) then n = n + 1 end end
      c.count:SetText(n > 0 and (n .. " selected") or "")
    else c:Hide(); c.catID = nil end
  end
  UI.none:SetShown(cards and #cats == 0)
  UI.title:SetShown(not cards)
  UI.count:SetShown(not cards)
  UI.hint:SetShown(cards and #cats > 0)
  if _G.LFGComment then if cards then LFGComment:Hide() else LFGComment:Show() end end
  local acts = (not cards and G.cat) and G.Activities(G.cat) or {}
  if not cards then
    UI.title:SetText((G.cat and G.Q("GetCategoryInfo", nil, G.cat)) or "")
    UI.count:SetText(#G.sel .. "/" .. G.MAX)
  end
  local maxOff = math.max(#acts - G.ROWS_SHOWN, 0)
  G.offset = math.min(math.max(G.offset or 0, 0), maxOff)
  local ro = G.ReadOnly()
  for i, r in ipairs(UI.rows) do
    local a = acts[G.offset + i]
    if a then
      r.activityID, r.activityName, r.players = a.id, a.name, a.players
      r.name:SetText(a.name); r.info:SetText(a.players and (a.players .. " players") or "")
      local on = G.Selected(a.id) and true or false
      r.check:SetChecked(on)
      local lock = ro or (not on and G.Full())
      r:SetAlpha(lock and 0.5 or 1)
      r:Show()
    else r.activityID = nil; r:Hide() end
  end
  G.maxOff = cards and 0 or maxOff
  UI.bar:Refresh()
  -- buttons
  setBack(not cards)
  local ok, err = G.CanPost()
  if ok then UI.post:Enable() else UI.post:Disable() end
  UI.post.errorText = err
  UI.post:SetText(G.HasActive() and "Update" or "List Self")
  if ro or (#G.sel == 0 and not G.HasActive()) then UI.clear:Disable() else UI.clear:Enable() end
  if cards then
    local listed = #G.Active()
    local text = listed > 0 and string.format("You are listed for %d %s.", listed, listed == 1 and "activity" or "activities") or ""
    if G.local_ then text = text .. " (saved here only: the game did not take the listing)" end
    UI.hint:SetText(text)
  end
end

function G.Scroll(delta) if UI.bar then UI.bar:ScrollBy(-delta) else G.offset = (G.offset or 0) - delta; G.Refresh() end end

function G.BuildPages(f)
  local lfg = _G.LFGFrame
  if not lfg or UI.page then return end
  UI.page = lfg
  drawPanel(lfg, f)
  UI.cards = {}
  for i = 1, G.MAXCARDS do UI.cards[i] = makeCard(lfg, f, i) end
  UI.rows = {}
  for i = 1, G.ROWS_SHOWN do UI.rows[i] = makeRow(lfg, f, i) end
  UI.title = lfg:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); UI.title:SetPoint("TOPLEFT", f, "TOPLEFT", 74, -34)
  UI.count = lfg:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); UI.count:SetPoint("TOPRIGHT", f, "TOPRIGHT", -26, -36)
  UI.none = lfg:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); UI.none:SetPoint("TOP", f, "TOP", 0, -140); UI.none:SetWidth(280)
  UI.none:SetText("Looking For Group is not available right now.")
  UI.hint = lfg:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); UI.hint:SetPoint("TOP", f, "TOP", 0, -34); UI.hint:SetWidth(330)
  -- the shared bar (rows are the unit: it glides, the rows tick); the wheel over the page scrolls it, the list view only
  UI.bar = K.scrollbar(lfg, { get = function() return G.offset or 0 end, set = function(v) G.offset = v; G.Refresh() end, max = function() return G.maxOff or 0 end,
    view = function() return G.ROWS_SHOWN end, step = 2, integer = true, eps = 0.01 },
    { parent = lfg, place = function(b) b:SetPoint("TOPLEFT", f, "TOPLEFT", 438, -70); b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 438, -70 - G.ROWS_SHOWN * G.ROW_H) end })
  -- bottom buttons: Back / Clear All / List Self (Forever has Back left, List Self right)
  local function btn(name, text, point, x, w, fn)
    local b = CreateFrame("Button", name, lfg, "UIPanelButtonTemplate")
    b:SetText(text); b:SetHeight(22); b:SetPoint(point, f, point, x, 16)
    K.button(b, w, 22)
    b:SetScript("OnClick", fn)
    return b
  end
  UI.back = btn("AFUI_LFGBack", "Back", "BOTTOMLEFT", 26, 108, function() G.Back() end)
  UI.clear = btn("AFUI_LFGClear", "Clear All", "BOTTOM", 0, 104, function() PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or "igMainMenuOptionCheckBoxOn"); G.ClearAll() end)
  UI.post = btn("AFUI_LFGPost", "List Self", "BOTTOMRIGHT", -26, 108, function() PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or "igMainMenuOptionCheckBoxOn"); G.Post(); G.Refresh() end)
  UI.post:SetScript("OnEnter", function(self)
    if self.errorText then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.errorText, nil, nil, nil, nil, true); GameTooltip:Show() end
  end)
  UI.post:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- the client's own widgets this page replaces stay (they keep the client's state) but are not shown
  for i = 1, 3 do
    for _, n in ipairs({ "LFGFrameTypeDropDown", "LFGFrameActivityDropDown", "LFGLabel" }) do local w = _G[n .. i]; if w then w:Hide() end end
  end
  for _, n in ipairs({ "LFGFramePostButton", "LFGFrameClearAllButton", "LFGCommentLabel" }) do local w = _G[n]; if w then w:Hide() end end
  if _G.LFGEye then LFGEye:SetAlpha(0); LFGEye:EnableMouse(false) end
  local c = _G.LFGComment
  if c then
    c:ClearAllPoints(); c:SetPoint("TOPLEFT", f, "TOPLEFT", 26, -70 - G.ROWS_SHOWN * G.ROW_H - 10); c:SetWidth(410); c:SetHeight(18)
    c:HookScript("OnTextChanged", function(_, user) if user and G.HasActive() then G.commentDirty = true; G.Refresh() end end)
  end
  lfg:HookScript("OnShow", function() G.LoadActive() end)
  for _, fn in ipairs({ "LoadActiveEntry", "DefaultDropDownSetup", "PermissionUpdate" }) do
    if type(lfg[fn]) == "function" then hooksecurefunc(lfg, fn, function() G.Refresh() end) end
  end
  G.Refresh()
end

-- The browse page (LFMFrame): the client's own type / activity dropdowns, header, 16 rows, Refresh / Send Message / Group Invite, laid out for the 384 px frame.
G.COLS = { name = 116, zone = 124, level = 46, class = 104 }
function G.LayoutRows()
  local C = G.COLS
  for i = 1, 16 do
    local r = _G["LFMFrameButton" .. i]
    if r then
      for _, k in ipairs({ "Name", "Zone", "Level", "Class" }) do
        local fs = rawget(r, k) or _G["LFMFrameButton" .. i .. k]
        if fs then fs:SetWordWrap(false); fs:SetHeight(14) end
      end
      local n, z, l, c = _G["LFMFrameButton" .. i .. "Name"], _G["LFMFrameButton" .. i .. "Zone"], _G["LFMFrameButton" .. i .. "Level"], _G["LFMFrameButton" .. i .. "Class"]
      if n then n:ClearAllPoints(); n:SetPoint("LEFT", r, "LEFT", 8, 0); n:SetWidth(C.name - 2) end
      if z then z:ClearAllPoints(); z:SetPoint("LEFT", n, "RIGHT", 4, 0); z:SetWidth(C.zone - 4) end
      if l then l:ClearAllPoints(); l:SetPoint("LEFT", z, "RIGHT", 4, 0); l:SetWidth(C.level - 4) end
      if c then c:ClearAllPoints(); c:SetPoint("LEFT", l, "RIGHT", 4, 0); c:SetWidth(C.class - 4) end
    end
  end
end
function G.LayoutLFM(f)
  local C, lfm = G.COLS, _G.LFMFrame
  if not lfm or G.lfmDone then return end
  G.lfmDone = true
  drawPanel(lfm, f)
  local t, a = _G.LFMFrameTypeDropDown, _G.LFMFrameActivityDropDown
  if t then t:ClearAllPoints(); t:SetPoint("TOPLEFT", f, "TOPLEFT", 56, -24) end
  if a then a:ClearAllPoints(); a:SetPoint("LEFT", t, "RIGHT", -28, 0) end
  local x = 16
  for i, k in ipairs({ "name", "zone", "level", "class" }) do
    local h = _G["LFMFrameColumnHeader" .. i]
    if h then h:ClearAllPoints(); h:SetPoint("TOPLEFT", f, "TOPLEFT", x, -66); h:SetWidth(C[k]); h:SetHeight(20) end
    x = x + C[k]
  end
  for i = 1, 16 do
    local r = _G["LFMFrameButton" .. i]
    if r then
      r:SetWidth(402); r:SetHeight(19); r:ClearAllPoints()
      if i == 1 then r:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -88) else r:SetPoint("TOPLEFT", _G["LFMFrameButton" .. (i - 1)], "BOTTOMLEFT", 0, 0) end
    end
  end
  G.LayoutRows()
  local sf = _G.LFMListScrollFrame
  if sf then sf:ClearAllPoints(); sf:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -88); sf:SetWidth(402); sf:SetHeight(304) end
  local sb = _G.LFMListScrollFrameScrollBar
  if sb then sb:ClearAllPoints(); sb:SetPoint("TOPLEFT", sf, "TOPRIGHT", 8, -14); sb:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 8, 14) end
  local btns = { { "LFMFrameSearchButton", "BOTTOMLEFT", 18, 118 }, { "LFMFrameSendMessageButton", "BOTTOM", 0, 130 }, { "LFMFrameGroupInviteButton", "BOTTOMRIGHT", -18, 118 } }
  for _, b in ipairs(btns) do
    local w = _G[b[1]]
    if w then w:ClearAllPoints(); w:SetPoint(b[2], f, b[2], b[3], 16); w:SetWidth(b[4]); w:SetHeight(22) end
  end
  local empty = lfm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  empty:SetPoint("TOP", f, "TOP", 0, -140); empty:SetWidth(280)
  empty:SetText("No groups found. If you can't find what you're looking for, consider starting a group.")
  G.emptyText = empty
  local function sync() empty:SetShown((lfm.numResultsLoaded or 0) == 0) end
  if type(lfm.RefreshResults) == "function" then hooksecurefunc(lfm, "RefreshResults", function() G.LayoutRows(); sync() end) end
  if type(_G.WhoFrameColumn_SetWidth) == "function" then
    hooksecurefunc("WhoFrameColumn_SetWidth", function(h, w)
      for i, k in ipairs({ "name", "zone", "level", "class" }) do if h == _G["LFMFrameColumnHeader" .. i] and w ~= C[k] then h:SetWidth(C[k]) end end
    end)
  end
  lfm:HookScript("OnShow", function() G.LayoutRows(); sync() end)
  sync()
end

local function setup()
  if done then return end
  local f = _G.LFGParentFrame
  if not f then return end
  done = true
  local P = AFUI.Professions.Kit
  K.window(f, { icon = G.ICON, cut = G.CUT, w = AFUI.IS_243 and 384 or G.WIDTH, h = 512, hide = G.HIDE, title = "LFGParentFrameTitle", keys = { "NineSlice", "Inset", "Bg", "TopTileStreaks", "PortraitContainer", "BtnCornerLeft", "BtnCornerRight", "ButtonBottomBorder" } })
  K.picture(f.afPortrait, G.ICON, 0.02) -- the green eye, a hair inside the sprite so the ring edge stays clean
  AFUI.PanelAttrs(f, G.PANEL)
  local close = findClose(f)
  if close then P.closeButton(close, f) end
  local title = _G.LFGParentFrameTitle -- the client keeps writing "Looking For Group" / "Looking For More" into it: it is the window's title now
  if not title then
    title = f.afLabels:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -6); title:SetText(G.TITLE)
  end
  -- the old frame is 512 px tall and its pages are laid out for that (Comment 124, Post / Clear All 84, Search / Message / Invite 85 above the bottom); the
  -- metal frame stops 62 px higher, so the pages keep the old bottom and everything sits where the client put it (a page on the short frame piled Comment on the dropdowns)
  for _, n in ipairs(G.PAGES) do
    local p = _G[n]
    if p then P.hideRegions(p); p:ClearAllPoints(); p:SetPoint("TOPLEFT", f, "TOPLEFT"); p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, (_G.C_LFGList and not AFUI.IS_243) and 0 or -G.CUT) end -- the C_LFGList pages are laid out from the frame itself
  end
  for i, t in ipairs(G.TABS) do
    local b = _G[t[1]]
    if b then K.sideTab(b, f, i, t[2], b:GetText() or "") end
  end
  G.WhoTab(f)
  K.each(G.BUTTONS, K.button)
  K.each(G.DROPDOWNS, K.dropdown)
  if AFUI.EditModeWidgets then K.each(G.DROPDOWNS, AFUI.EditModeWidgets.DressDropdown) end -- Forever's field and boxed down arrow (f0089)
  K.each(G.HEADERS, K.header)
  K.each(G.RowNames(AFUI.IS_243 and "2.4.3" or "2.5.3"), K.row)
  K.each({ "LFGComment" }, K.edit)
  K.each(G.CHECKS, K.check)
  K.scroll("LFMListScrollFrameScrollBar", { x = 8 })
  if _G.C_LFGList and not AFUI.IS_243 then G.BuildPages(f); G.LayoutLFM(f) end
  f:HookScript("OnShow", function() K.refreshTabs() end)
end

function G.Setup() AFUI.RunOutOfCombat(setup) end
AFUI.On("ADDON_LOADED", function(_, name)
  if name == "Blizzard_LookingForGroupUI" then G.Setup() end -- 2.5.3 loads the tool on demand
end)
AFUI.RegisterModule("GroupFinder", { OnLogin = G.Setup })
