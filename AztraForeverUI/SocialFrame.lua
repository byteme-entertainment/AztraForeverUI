-- Forever's Social window: the client's own FriendsFrame (Friends / Ignore / Muted, Who, Guild, Chat, Raid) inside Forever's metal portrait frame
-- (the one the Character / Professions windows draw): stone interior, red X, red buttons, bottom tabs, gold column headers, minimal scroll bars, dark
-- inner panels for Guild Info / member details / guild control / event log / raid info. Nothing of Blizzard's is rebuilt or replaced: old art is
-- hidden, widgets are re-skinned (hooksecurefunc / HookScript only), every click, drag, tooltip, dropdown and list update stays the client's code.
-- Forever's code (tools/ref/interface/addons/blizzard_friendsframe/camelot/friendsframe.{xml,lua}, build 1.60.1.70938): FriendsFrame 385x424 on a metal
-- portrait frame, bottom tabs (Contacts / Raid / Quick Join), Add Friend BOTTOMLEFT 4,4 and Send Message BOTTOMRIGHT -6,4 (131x21), rows 298x34 with the
-- QuestLogTitleHighlight glow, 302 px scroll lists. Guild and Who stay the old sortable-column tabs there ("the old buttons"), which is what these two
-- clients have natively. No real Forever capture of this window exists (Method / Warcraft Tavern / Wowhead / ForeverWisp / CurseForge checked: only
-- the Looking For Group window is shown): geometry follows Forever's code, the look follows the Character / Professions captures.
-- Frame names (verified): 2.4.3 MOUZU/Blizzard-WoW-Interface 2.4.3/FrameXML/{FriendsFrame,RaidFrame,ChannelFrame}.xml + AddOns/Blizzard_RaidUI and
-- Gethe/wow-ui-source tag 2.5.3 Interface_TBC/FrameXML/FriendsFrame.xml + Interface/FrameXML/RaidFrame.xml + Interface/AddOns/Blizzard_RaidUI:
--   FriendsFrame (2.4.3 384x512, 2.5.3 ButtonFrameTemplate), FriendsFrameCloseButton, FriendsFrameTitleText, FriendsFrameTab1..5 (2.4.3: Friends, Who,
--   Guild, Chat, Raid; 2.5.3: Friends, Who, Guild, Raid, Groups (hidden)), FriendsListFrame / IgnoreListFrame / MutedListFrame (2.4.3 only, each with
--   its own Friends / Ignore / Muted toggle tabs) or FriendsTabHeaderTab1/2 (2.5.3 Friends / Ignore), WhoFrame, GuildFrame (+ GuildInfoFrame,
--   GuildMemberDetailFrame, GuildControlPopupFrame, GuildEventLogFrame 2.4.3), ChannelFrame (2.4.3), RaidFrame / RaidInfoFrame, RaidParentFrame (2.5.3),
--   Blizzard_RaidUI (load on demand: RaidGroup1-8, RaidFrameReadyCheckButton).
AFUI = AFUI or {}
local S = {}
AFUI.SocialFrame = S

local ICON = "Interface\\Icons\\INV_Misc_Note_01"
local PLAIN = "Interface\\AddOns\\AztraForeverUI\\Media\\plain\\"
S.SIZE = { w = 408, h = 676 } -- 2.5.3: Forever's Friends window (video 3, f0041: 574 x 950 px at 1.40625 px per unit)
S.CUT_243 = 62 -- the 2.4.3 frame is 512 px tall; its widgets stop 62 px above the bottom, so the metal frame does too and the tabs hang under it

---------------------------------------------------------------- data (pure; specs: tests/lua/socialframe_spec.lua)
S.BUTTONS = {
  "FriendsFrameAddFriendButton", "FriendsFrameRemoveFriendButton", "FriendsFrameSendMessageButton", "FriendsFrameGroupInviteButton",
  "FriendsFrameIgnorePlayerButton", "FriendsFrameStopIgnoreButton", "FriendsFrameUnsquelchButton", "FriendsFrameMutedPlayerButton", "FriendsFrameUnmuteButton",
  "WhoFrameWhoButton", "WhoFrameAddFriendButton", "WhoFrameGroupInviteButton",
  "GuildFrameControlButton", "GuildFrameAddMemberButton", "GuildFrameGuildInformationButton", "GuildFrameImpeachButton",
  "GuildMemberRemoveButton", "GuildMemberGroupInviteButton", "GuildFramePromoteButton", "GuildFrameDemoteButton",
  "GuildInfoSaveButton", "GuildInfoCancelButton", "GuildInfoGuildEventButton", "GuildEventLogCancelButton",
  "GuildControlPopupAcceptButton", "GuildControlPopupFrameCancelButton", "GuildControlPopupFrameAddRankButton", "GuildControlPopupFrameRemoveRankButton",
  "ChannelFrameNewButton", "ChannelFrameJoinButton", "ChannelFrameDaughterFrameOkayButton", "ChannelFrameDaughterFrameCancelButton",
  "RaidFrameConvertToRaidButton", "RaidFrameRaidInfoButton", "RaidFrameReadyCheckButton", "RaidFrameAddMemberButton",
}
S.TABS = { "FriendsFrameTab1", "FriendsFrameTab2", "FriendsFrameTab3", "FriendsFrameTab4", "FriendsFrameTab5" }
S.SUBTABS = { -- the Friends / Ignore / Muted toggles of 2.4.3 (one set per list) and 2.5.3's header tabs
  "FriendsFrameToggleTab1", "FriendsFrameToggleTab2", "FriendsFrameToggleTab3", "IgnoreFrameToggleTab1", "IgnoreFrameToggleTab2", "IgnoreFrameToggleTab3",
  "MutedFrameToggleTab1", "MutedFrameToggleTab2", "MutedFrameToggleTab3", "FriendsTabHeaderTab1", "FriendsTabHeaderTab2",
}
S.SCROLLBARS = {
  "FriendsFrameFriendsScrollFrameScrollBar", "FriendsFrameIgnoreScrollFrameScrollBar", "FriendsFrameMutedScrollFrameScrollBar", "WhoListScrollFrameScrollBar",
  "GuildListScrollFrameScrollBar", "GuildInfoFrameScrollFrameScrollBar", "GuildEventLogScrollFrameScrollBar", "RaidInfoScrollFrameScrollBar", "ChannelListScrollFrameScrollBar",
  "ChannelRosterScrollFrameScrollBar",
}
S.HEADERS = { "WhoFrameColumnHeader1", "WhoFrameColumnHeader2", "WhoFrameColumnHeader3", "WhoFrameColumnHeader4",
  "GuildFrameColumnHeader1", "GuildFrameColumnHeader2", "GuildFrameColumnHeader3", "GuildFrameColumnHeader4",
  "GuildFrameGuildStatusColumnHeader1", "GuildFrameGuildStatusColumnHeader2", "GuildFrameGuildStatusColumnHeader3", "GuildFrameGuildStatusColumnHeader4" }
S.DROPDOWNS = { "WhoFrameDropDown", "GuildControlPopupFrameDropDown", "ChannelRosterDropDown" }
S.EDITS = { "WhoFrameEditBox", "GuildControlPopupFrameEditBox", "ChannelFrameDaughterFrameChannelName", "ChannelFrameDaughterFrameChannelPassword" }
-- inner panels { frame, its close button }
S.PANELS = { { "GuildInfoFrame", "GuildInfoCloseButton" }, { "GuildMemberDetailFrame", "GuildMemberDetailCloseButton" }, { "GuildControlPopupFrame" },
  { "GuildEventLogFrame", "GuildEventLogCloseButton" }, { "RaidInfoFrame", "RaidInfoCloseButton" }, { "ChannelFrameDaughterFrame", "ChannelFrameDaughterFrameDetailCloseButton" },
  { "AddFriendFrame" } }
S.PAGES = { "FriendsListFrame", "IgnoreListFrame", "MutedListFrame", "WhoFrame", "GuildFrame", "ChannelFrame", "RaidFrame", "FriendsTabHeader" }
S.INSETS = { "FriendsFrameInset", "FriendsFrameBottomInset", "WhoFrameListInset", "WhoFrameEditBoxInset", "FriendsFrameBg" }
S.KEYS = { "NineSlice", "Inset", "Bg", "TopTileStreaks", "PortraitContainer", "BtnCornerLeft", "BtnCornerRight", "ButtonBottomBorder" }
-- list rows by client: 2.4.3 numbered buttons, 2.5.3 hybrid scroll buttons for the friend and ignore lists
S.ROWS = {
  ["2.4.3"] = { { "FriendsFrameFriendButton", 10 }, { "FriendsFrameIgnoreButton", 20 }, { "FriendsFrameMutedButton", 20 }, { "WhoFrameButton", 17 }, { "GuildFrameButton", 13 },
    { "GuildFrameGuildStatusButton", 13 }, { "ChannelButton", 20 }, { "ChannelRosterButton", 20 } },
  ["2.5.3"] = { { "FriendsFrameFriendsScrollFrameButton", 14 }, { "FriendsFrameIgnoreScrollFrameButton", 22 }, { "WhoFrameButton", 17 }, { "GuildFrameButton", 13 },
    { "GuildFrameGuildStatusButton", 13 } },
}

function S.RowNames(client)
  local out = {}
  for _, r in ipairs(S.ROWS[client] or {}) do for _, n in ipairs(AFUI.WinKit.Numbered(r[1], r[2])) do out[#out + 1] = n end end
  return out
end

---------------------------------------------------------------- roomy rows (2.5.3): Forever's 298x34 friend row enlarged
-- friend 48 px: status dot, class icon, class-coloured name over a grey "Level / class / zone" line, alternate shade; ignore 28, who 22 x 12 rows.
S.ROW = { friend = 77, ignore = 28, who = 22 } -- friend: video 3's cards are 100 px (71 u) tall, 5 px apart; 77 = 7 whole rows in the list
-- The list region (2.5.3 FriendsFrame.xml): the client sizes the friends scroll frame 302 x 307 (TOPLEFT 8,-87, 10 rows made once for that height) and the ignore
-- one 298 x 309 for its 384 px window, with the scroll bar art (Top / Middle / Bottom) hanging off the frame. In Forever's 408 x 676 window the list spans
-- the inner width from the section bar down to the bottom button, in whole rows, with the minimal bar flush at its right edge.
S.LIST = { x = 11, top = 92, right = 32, bottom = 45, bar = 8 }
function S.ListWidth() return S.SIZE.w - S.LIST.x - S.LIST.right end
function S.ListHeight(rowH) return math.floor((S.SIZE.h - S.LIST.top - S.LIST.bottom) / rowH) * rowH end
local NAME_H, INFO_H = 18, 14 -- GameFontNormalLarge / GameFontHighlightSmall
function S.FriendLayout(h)
  return { status = { x = 4, size = 14 }, textX = 14, nameY = -12, infoGap = 5, nameH = NAME_H, infoH = INFO_H }
end
function S.ClassToken(localized)
  if not localized then return nil end
  for _, t in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE or {}, _G.LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
    for token, name in pairs(t) do if name == localized then return token end end
  end
end
function S.InfoLine(level, class, area)
  local who = level and ("Level " .. level .. (class and class ~= "" and (" " .. class) or "")) or nil
  if area == "" then area = nil end
  if who and area then return who .. " - " .. area end
  return who or area or "Unknown"
end
function S.Shade(i) return i % 2 == 0 and 0.06 or 0 end
-- Side tabs: Friends, Ignore, Who List (the client's own tab 2: its logic is never fought), Raid; Guild is the G key's own window.
-- Forever draws these tabs as flat gold glyphs (video 3 f0041: friends / flag / person+ / group; atlas friends-icon-tab-*, cut by tools/atlas-crop.mjs)
S.SIDE = { { key = "friends", icon = PLAIN .. "AFUI-Tab-Friends", tip = "Friends" }, { key = "ignore", icon = PLAIN .. "AFUI-Tab-Ignore", tip = "Ignore" },
  { key = "who", icon = PLAIN .. "AFUI-Tab-Who", tip = "Who List" }, { key = "raid", icon = PLAIN .. "AFUI-Tab-Raid", tip = "Raid" } }
-- Where each side tab goes: the client's own tab number (FriendsFrame: Friends 1, Who 2, Guild 3, Raid 4) and, for Friends / Ignore, its header tab (1 / 2).
S.ROUTE = { friends = { tab = 1, sub = 1 }, ignore = { tab = 1, sub = 2 }, who = { tab = 2 }, raid = { tab = 4 } }
-- Which side tab is lit, from the client's selected tab numbers (never from which page happens to be shown): tab = FriendsFrame's, sub = FriendsTabHeader's.
function S.SideOf(tab, sub)
  if tab == 4 then return "raid" elseif tab == 3 then return nil elseif tab == 2 then return "who" end
  return sub == 2 and "ignore" or "friends"
end
-- widgets the 2.5.3 Forever window has no place for: bottom tabs, header tabs, Battle.net name bar, broadcast box, Send Message (the row menu whispers)
S.GONE = { "FriendsFrameTab1", "FriendsFrameTab2", "FriendsFrameTab3", "FriendsFrameTab4", "FriendsFrameTab5", "FriendsTabHeaderTab1", "FriendsTabHeaderTab2" }
S.HIDDEN = { "FriendsFrameBattlenetFrame", "FriendsFrameBroadcastInput", "FriendsFrameSendMessageButton" }
-- which side tab shows as selected: shown = { raid, who, guild, ignore } (page visible); Guild belongs to another window, so none lights up
function S.ActiveSide(shown)
  if shown.raid then return "raid" end
  if shown.guild then return nil end
  if shown.who then return "who" end
  if shown.ignore then return "ignore" end
  return "friends"
end
-- The Guild tab: a Social panel that this very call just opened gives way to the guild window; an open one keeps its page and docks the window.
function S.GuildRoute(fresh) return fresh and "alone" or "docked" end

---------------------------------------------------------------- skin
local K = AFUI.WinKit
local done

local ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local function parts(b)
  if b.afRow then return b.afRow end
  local r = {}
  r.alt = b:CreateTexture(nil, "BACKGROUND"); AFUI.SetColor(r.alt, 1, 1, 1, 1); r.alt:SetAllPoints(b); r.alt:SetAlpha(0)
  r.line = b:CreateTexture(nil, "BORDER"); AFUI.SetColor(r.line, 0, 0, 0, 0.4); r.line:SetHeight(1); r.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT"); r.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT")
  b.afRow = r
  return r
end
local function shade(b, i) local r = parts(b); r.alt:SetAlpha(S.Shade(i)) end

-- a WoW friend's level / class / connected state (C_FriendList on 2.5.3, GetFriendInfo as the fallback)
local function friendInfo(id)
  if not id then return end
  if _G.C_FriendList and C_FriendList.GetFriendInfoByIndex then
    local i = C_FriendList.GetFriendInfoByIndex(id)
    if i then return i.level, i.className, i.area, i.connected end
  elseif _G.GetFriendInfo then
    local _, level, class, area, connected = GetFriendInfo(id)
    return level, class, area, connected
  end
end

-- Forever's friend card (video-notes/social-friends.md): near-black rounded card (#12100e), an online friend's card is tinted blue (#12304f), the hover
-- is a gold-olive card with a 1 px gold border; online names light blue, offline grey, a status dot in the card's top-left corner.
S.CARD = { idle = { 0.05, 0.05, 0.05 }, online = { 0.027, 0.11, 0.19 }, hover = { 0.227, 0.204, 0.063 }, edge = { 0.69, 0.6, 0.14 },
  rimOn = { 0.114, 0.31, 0.498 }, rimOff = { 0.14, 0.14, 0.14 } } -- video 3: online cards #051725 .. #08243a with a #1d4f7f rim, offline #0d0d0d
S.NAME = { online = { 0.416, 0.659, 1 }, offline = { 0.54, 0.54, 0.54 } }
-- What a row shows: the gold card only under the mouse (olive fill) or on the selected friend (the card's own colour inside the gold rim). The client's own glow
-- (LockHighlight on the selected row, its `highlight` / `background` textures) is gone for good, and a row without a friend (divider, invite header, stale
-- scroll button) never gets a card.
function S.RowLook(live, hover, selected)
  if not live then return "none" end
  if hover then return "hover" end
  return selected and "selected" or "idle"
end
local function paintCard(b)
  local r = b.afRow
  if not (r and r.card) then return end
  local look = S.RowLook(b.afLive, b.afHover, b.afSel)
  if look == "none" then r.card:Hide(); r.edge:Hide(); r.hov:Hide(); return end
  r.card:Show()
  local fill = look == "hover" and S.CARD.hover or (b.afOnline and S.CARD.online or S.CARD.idle)
  local rim = look == "hover" and S.CARD.edge or (b.afOnline and S.CARD.rimOn or S.CARD.rimOff)
  AFUI.SetColor(r.hov, fill[1], fill[2], fill[3], 1); AFUI.SetColor(r.edge, rim[1], rim[2], rim[3], 1)
  r.edge:Show(); r.hov:Show()
end
local function quiet(t) -- a client texture that stays invisible whatever the client does to it
  if not t or t.afQuiet or not t.SetAlpha then return end
  t.afQuiet = true; t:SetAlpha(0)
  if t.Show then hooksecurefunc(t, "Show", function(self) self:SetAlpha(0) end) end
end
-- the WoW friend's name behind a list index (C_FriendList on 2.5.3)
local function friendName(id)
  if _G.C_FriendList and C_FriendList.GetFriendInfoByIndex then local i = C_FriendList.GetFriendInfoByIndex(id); return i and i.name end
  if _G.GetFriendInfo then return (GetFriendInfo(id)) end
end
local function card(b, connected)
  local r = parts(b)
  if not r.card then
    r.card = b:CreateTexture(nil, "BACKGROUND"); r.card:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -2); r.card:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 2)
    r.edge = b:CreateTexture(nil, "BORDER"); r.edge:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -2); r.edge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 2)
    r.hov = b:CreateTexture(nil, "ARTWORK", nil, -1); r.hov:SetPoint("TOPLEFT", r.edge, "TOPLEFT", 1, -1); r.hov:SetPoint("BOTTOMRIGHT", r.edge, "BOTTOMRIGHT", -1, 1)
    AFUI.SetColor(r.edge, S.CARD.edge[1], S.CARD.edge[2], S.CARD.edge[3], 1)
    b:HookScript("OnEnter", function(self) self.afHover = true; paintCard(self) end)
    b:HookScript("OnLeave", function(self) self.afHover = false; paintCard(self) end)
    b:HookScript("OnClick", function() S.RestyleLists() end) -- the client has moved its selection by now
  end
  local c = connected and S.CARD.online or S.CARD.idle
  AFUI.SetColor(r.card, c[1], c[2], c[3], 1)
  r.alt:SetAlpha(0)
  b.afOnline = connected and true or false
  local ht = b:GetHighlightTexture(); if ht then ht:SetAlpha(0) end -- the client's / WinKit's own glow gives way to the gold card
  quiet(b.highlight); quiet(b.background)
  paintCard(b)
end
local function hideCard(b) -- a row that is not a friend
  b.afLive = false
  local r = b.afRow
  if r and r.card then paintCard(b) end
  quiet(b.highlight); quiet(b.background)
  local ht = b.GetHighlightTexture and b:GetHighlightTexture(); if ht then ht:SetAlpha(0) end
end

-- the friend row the client has selected (FriendsFrame.selectedFriend: a list index, selectedFriendType: WoW / Battle.net)
local function isSelected(b)
  local f = _G.FriendsFrame
  return f and f.selectedFriend ~= nil and f.selectedFriend == b.id and (f.selectedFriendType == nil or b.buttonType == nil or f.selectedFriendType == b.buttonType) and true or false
end

local function styleFriend(b, i)
  local t = b.buttonType
  if t ~= nil and t ~= _G.FRIENDS_BUTTON_TYPE_WOW and t ~= _G.FRIENDS_BUTTON_TYPE_BNET then hideCard(b); return end -- dividers, invites and headers keep their look
  local h = S.ROW.friend
  local l = S.FriendLayout(h)
  local r = parts(b)
  b:SetHeight(h)
  local isBnet = t ~= nil and t == _G.FRIENDS_BUTTON_TYPE_BNET
  local level, class, area, connected = friendInfo(not isBnet and b.id or nil)
  if isBnet then connected = not (b.status and tostring(b.status:GetTexture() or ""):find("Offline")) end
  local nm = b.name and b.name:GetText()
  b.afLive = nm ~= nil and nm ~= "" -- no name: a stale row beyond the list
  b.afSel = b.afLive and isSelected(b)
  if not b.afLive then hideCard(b); return end
  card(b, connected)
  if r.icon then r.icon:Hide() end
  if b.status then b.status:ClearAllPoints(); b.status:SetPoint("TOPLEFT", b, "TOPLEFT", l.status.x, l.nameY + 4); b.status:SetWidth(l.status.size); b.status:SetHeight(l.status.size) end
  local x = l.textX
  local rw = S.ListWidth()
  if b.name then
    b.name:SetFontObject(GameFontNormalLarge); b.name:SetJustifyH("LEFT"); b.name:ClearAllPoints(); b.name:SetPoint("TOPLEFT", b, "TOPLEFT", x, l.nameY); b:SetWidth(rw); b.name:SetWidth(rw - x - 60); b.name:SetHeight(l.nameH); if b.name.SetWordWrap then b.name:SetWordWrap(false) end
    local c = connected and S.NAME.online or S.NAME.offline
    b.name:SetTextColor(c[1], c[2], c[3])
  end
  if b.info then
    b.info:SetFontObject(GameFontHighlightSmall); b.info:SetJustifyH("LEFT"); b.info:ClearAllPoints(); b.info:SetPoint("TOPLEFT", b, "TOPLEFT", x, l.nameY - l.nameH - l.infoGap); b.info:SetWidth(rw - x - 60); b.info:SetHeight(l.infoH); if b.info.SetWordWrap then b.info:SetWordWrap(false) end
    local cur = b.info:GetText()
    if cur == "" or cur == nil or cur == _G.UNKNOWN then b.info:SetText(connected and S.InfoLine(level, class, area) or "Offline") end
    b.info:SetTextColor(0.54, 0.54, 0.54)
  end
  if b.gameIcon then b.gameIcon:ClearAllPoints(); b.gameIcon:SetPoint("RIGHT", b, "RIGHT", -44, 0); b.gameIcon:SetWidth(24); b.gameIcon:SetHeight(24) end
  local tp = b.travelPassButton -- the client's invite button: no card has one (no icon, no hit area)
  if tp then tp:SetAlpha(0); if tp.EnableMouse then tp:EnableMouse(false) end end
  local sm = b.summonButton
  if sm then sm:ClearAllPoints(); sm:SetPoint("RIGHT", b, "RIGHT", -44, 0) end
  paintCard(b)
end

local function styleIgnore(b, i)
  local r = parts(b)
  b:SetHeight(S.ROW.ignore)
  shade(b, i)
  local n = b.name
  b:SetWidth(S.ListWidth())
  if n then n:SetFontObject(GameFontNormal); n:SetJustifyH("LEFT"); n:ClearAllPoints(); n:SetPoint("LEFT", b, "LEFT", 32, 0); n:SetWidth(S.ListWidth() - 44) end
  if not r.x then r.x = b:CreateTexture(nil, "ARTWORK"); r.x:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up"); r.x:SetWidth(16); r.x:SetHeight(16); r.x:SetPoint("LEFT", b, "LEFT", 10, 0) end
end

local function restyleLists()
  local sf = _G.FriendsFrameFriendsScrollFrame
  if sf and sf.buttons then for i, b in ipairs(sf.buttons) do styleFriend(b, i) end end
  sf = _G.FriendsFrameIgnoreScrollFrame
  if sf and sf.buttons then for i, b in ipairs(sf.buttons) do styleIgnore(b, i) end end
end
function S.RestyleLists() restyleLists() end

-- Who page (2.5.3 FriendsFrame.xml: 17 rows of 298 x 16 under the headers at TOPLEFT 7,-57, scroll frame 296 x 287): the list fills the whole region from the
-- headers down to the search box, like the Friends list. Header columns share the list width (the client's own 83 / 105 / 32 / 92 plates, widened); rows are
-- 22 px, as many as fit (WHOS_TO_DISPLAY and the client's WhoFrameButtonN names are extended to that count); each row text starts 8 px inside its header.
S.WHO = { header = 57, list = 82, reserve = 61, gap = 2, pad = 8 } -- reserve: the search box border's top edge, counted up from the window bottom
function S.WhoRows() return math.floor((S.SIZE.h - S.WHO.list - S.WHO.reserve) / S.ROW.who) end
function S.WhoColumns(total) -- the four header widths (plates overlap by gap) and each header's left offset in the list
  local lvl, name, zone = 44, 100, 130
  local w = { name, zone, lvl, total + 3 * S.WHO.gap - name - zone - lvl }
  local x, left = 0, {}
  for i = 1, 4 do left[i] = x; x = x + w[i] - S.WHO.gap end
  return w, left
end
local WHO_FIELDS = { "Name", "Variable", "Level", "Class" }
function S.ClassColor(localized)
  local token = S.ClassToken(localized)
  local c = token and _G.RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
  if c then return c.r, c.g, c.b end
end
local function whoRow(i) -- the client makes 17 rows (FriendsFrameWhoButtonTemplate); a taller list needs more, made from the same template
  local n = "WhoFrameButton" .. i
  local b = _G[n]
  if b or not _G.WhoFrame then return b end
  b = CreateFrame("Button", n, _G.WhoFrame, "FriendsFrameWhoButtonTemplate")
  -- the client's rows carry their number and take both clicks from the XML; ours (row 18 and up, the lower ones) must too, or a right click on them does nothing
  b:SetID(i); b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  for _, k in ipairs(WHO_FIELDS) do -- a client without the template still gets its four texts
    if not _G[n .. k] then b:CreateFontString(n .. k, "ARTWORK", k == "Name" and "GameFontNormalSmall" or "GameFontHighlightSmall") end
  end
  return b
end
local function whoCount()
  local n = 0
  for i = 1, S.WhoRows() do
    local b = _G["WhoFrameButton" .. i]
    if b and b:IsShown() then n = n + 1 end
  end
  return n
end
local function whoEmpty()
  local wf = _G.WhoFrame
  if not wf then return end
  if not wf.afEmpty then
    wf.afEmpty = wf:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    wf.afEmpty:SetText("No players found.")
  end
  local none = whoCount() == 0
  wf.afEmpty:ClearAllPoints() -- the middle of the whole list area, not of its first rows
  wf.afEmpty:SetPoint("CENTER", wf, "TOPLEFT", S.LIST.x + S.ListWidth() / 2, -(S.WHO.list + S.WhoRows() * S.ROW.who / 2))
  if none then wf.afEmpty:Show() else wf.afEmpty:Hide() end
  for _, st in ipairs(wf.afStripes or {}) do if none then st:Hide() else st:Show() end end -- no stripes on an empty list: the plain dark list and the message
end
-- header plates, rows, stripes, scroll bar: one geometry for all of them (re-applied whenever the client lays the rows or a column out again)
function S.LayoutWho()
  local wf = _G.WhoFrame
  if not wf then return end
  local L, total, rows = S.LIST, S.ListWidth(), S.WhoRows()
  local widths, left = S.WhoColumns(total)
  for i = 1, 4 do
    local h = _G["WhoFrameColumnHeader" .. i]
    if h then h:ClearAllPoints(); h:SetPoint("TOPLEFT", wf, "TOPLEFT", L.x + left[i], -S.WHO.header); h:SetWidth(widths[i]) end
  end
  _G.WHOS_TO_DISPLAY = rows
  wf.afStripes = wf.afStripes or {}
  for i = 1, math.max(rows, 17) do
    local b = whoRow(i)
    if b then
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", wf, "TOPLEFT", L.x, -(S.WHO.list + (i - 1) * S.ROW.who)); b:SetWidth(total); b:SetHeight(S.ROW.who)
      if i > rows then b:Hide() end
      if b.afRow then b.afRow.alt:SetAlpha(0) end -- the stripes are drawn for the empty rows too
      for k, col in ipairs(WHO_FIELDS) do
        local fs = _G["WhoFrameButton" .. i .. col]
        if fs then
          fs:ClearAllPoints(); fs:SetPoint("LEFT", b, "LEFT", left[k] + S.WHO.pad, 0)
          fs:SetWidth(widths[k] - S.WHO.pad - 4); fs:SetHeight(14); fs:SetJustifyH("LEFT")
          if fs.SetWordWrap then fs:SetWordWrap(false) end
          if col == "Class" then
            local r, g, bl = S.ClassColor(fs:GetText())
            if r then fs:SetTextColor(r, g, bl) end
          end
        end
      end
    end
    if i <= rows then
      local st = wf.afStripes[i]
      if not st then st = wf:CreateTexture(nil, "BACKGROUND"); AFUI.SetColor(st, 1, 1, 1, 1); wf.afStripes[i] = st end
      st:ClearAllPoints(); st:SetPoint("TOPLEFT", wf, "TOPLEFT", L.x, -(S.WHO.list + (i - 1) * S.ROW.who)); st:SetWidth(total); st:SetHeight(S.ROW.who)
      st:SetAlpha(S.Shade(i))
    end
  end
  local sf = _G.WhoListScrollFrame -- spans the list; its bar sits at the right edge on the full list height, as the Friends bar does
  if sf then
    sf:ClearAllPoints(); sf:SetPoint("TOPLEFT", wf, "TOPLEFT", L.x, -S.WHO.list); sf:SetWidth(total); sf:SetHeight(rows * S.ROW.who)
    local sb = _G.WhoListScrollFrameScrollBar
    if sb then sb:ClearAllPoints(); sb:SetPoint("TOPLEFT", sf, "TOPRIGHT", L.bar, -14); sb:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", L.bar, 14); sb:SetWidth(17) end
    for _, k in ipairs({ "Top", "Middle", "Bottom" }) do local t = _G["WhoListScrollFrame" .. k]; if t then t:Hide(); t:SetAlpha(0) end end
  end
end
local function restyleWho()
  S.LayoutWho()
  for i = 1, S.WhoRows() do local b = _G["WhoFrameButton" .. i]; if b then K.row(b) end end
  whoEmpty()
end
function S.RestyleWho() restyleWho() end

-- Taller rows: the client's constants and hybrid scroll frames carry the heights, so the scroll maths follow.
local function growRows()
  if _G.FRIENDS_BUTTON_HEIGHTS then
    for _, k in ipairs({ _G.FRIENDS_BUTTON_TYPE_WOW, _G.FRIENDS_BUTTON_TYPE_BNET }) do if k then FRIENDS_BUTTON_HEIGHTS[k] = S.ROW.friend end end
  end
  _G.FRIENDS_FRAME_IGNORE_HEIGHT = S.ROW.ignore
  _G.FRIENDS_FRAME_WHO_HEIGHT = S.ROW.who
  _G.WHOS_TO_DISPLAY = S.WhoRows()
  local fr, ig = _G.FriendsFrameFriendsScrollFrame, _G.FriendsFrameIgnoreScrollFrame
  if fr then fr.buttonHeight = S.ROW.friend end
  if ig then ig.buttonHeight = S.ROW.ignore end
  if type(_G.HybridScrollFrame_Update) == "function" then
    hooksecurefunc("HybridScrollFrame_Update", function(sf) if sf == _G.FriendsFrameFriendsScrollFrame or sf == _G.FriendsFrameIgnoreScrollFrame then restyleLists() end end)
  end
  if type(_G.WhoList_Update) == "function" then hooksecurefunc("WhoList_Update", restyleWho) end
  if type(_G.WhoFrameColumn_SetWidth) == "function" then -- the client narrows the columns when its bar shows: the widths stay ours
    hooksecurefunc("WhoFrameColumn_SetWidth", function(h, w)
      local widths = S.WhoColumns(S.ListWidth())
      for i = 1, 4 do if h == _G["WhoFrameColumnHeader" .. i] and w ~= widths[i] then h:SetWidth(widths[i]) end end
    end)
  end
  restyleLists(); restyleWho()
end

---------------------------------------------------------------- Guild leaves the Social panel (2.5.3 FriendsFrame.lua)
-- Who is the panel's own tab 2 and the client's code (WhoList_Update, ShowWhoPanel, ToggleFriendsFrame(2)) runs untouched: nothing redirects it. Guild (tab 3)
-- is Forever's own window, so the panel must neither stay on that tab nor open for it. The hook below runs after the client's code, so the fix is deferred to
-- the end of the frame: put the tab back (S.tab, noted from FriendsFrame_ShowSubFrame), close a panel this call opened, refresh one that was already open.
S.FRAME_TAB = { FriendsListFrame = 1, IgnoreListFrame = 1, WhoFrame = 2, RaidFrame = 4 } -- the pages the panel really keeps -> its tab
S.tab = 1
local settling
function S.NoteSubFrame(name) if S.FRAME_TAB[name] then S.tab = S.FRAME_TAB[name] end end
-- A redirect came in. `fresh` = the panel was closed before the client's call. Returns true for the first redirect of this frame (the one that opens the window).
function S.Redirect(fresh)
  local f = _G.FriendsFrame
  if not f then return false end
  if settling then if fresh then f.afFresh = true end; return false end
  settling = true
  if fresh then f.afFresh = true; f:SetAlpha(0) end -- one invisible frame instead of an empty page
  local function settle()
    settling = false
    PanelTemplates_SetTab(f, S.tab)
    local opened = f.afFresh
    f.afFresh = nil
    if opened then
      if f:IsShown() then HideUIPanel(f) end
      f:SetAlpha(1)
    elseif f:IsShown() and _G.FriendsFrame_Update then
      FriendsFrame_Update()
    end
  end
  if _G.C_Timer and C_Timer.After then C_Timer.After(0, settle) else settle() end
  return true
end
function S.Opened() local f = _G.FriendsFrame; return f and f.afOpen end

function S.HookGuild(W)
  local f = _G.FriendsFrame
  if not f or f.afGuildHook or AFUI.IS_243 then return end
  f.afGuildHook = true
  f:HookScript("OnShow", function(self) self.afOpen = true end) -- after the client's OnShow, so during it the panel still counts as closed
  f:HookScript("OnHide", function(self) self.afOpen = false end)
  if type(_G.FriendsFrame_ShowSubFrame) == "function" then
    hooksecurefunc("FriendsFrame_ShowSubFrame", function(name)
      if name ~= "GuildFrame" then S.NoteSubFrame(name); return end
      if not IsInGuild() then return end
      local fresh = not f.afOpen
      if S.Redirect(fresh) then W.Open(S.GuildRoute(fresh)) end
    end)
  end
  -- a who result selects tab 2 but ShowUIPanel does nothing on a panel that is already open, so its page would stay Friends / Raid under a lit Who tab
  if type(_G.WhoList_Update) == "function" and type(_G.FriendsFrame_Update) == "function" then
    hooksecurefunc("WhoList_Update", function()
      local wf = _G.WhoFrame
      if f:IsShown() and PanelTemplates_GetSelectedTab(f) == 2 and wf and wf.IsShown and not wf:IsShown() then FriendsFrame_Update() end
    end)
  end
  -- ToggleFriendsFrame(3) returns early without a guild ("If not in a guild don't do anything"), so the G key needs us: the "not in a guild" window
  if type(_G.ToggleFriendsFrame) == "function" then
    hooksecurefunc("ToggleFriendsFrame", function(tab)
      if tab == 3 and not IsInGuild() then W.Open(f:IsShown() and "docked" or "alone") end
    end)
  end
end

local function skinRaidUI()
  local P = AFUI.Professions.Kit
  for i = 1, 8 do
    local grp = _G["RaidGroup" .. i]
    if grp and not grp.afGroup then
      grp.afGroup = true
      P.hideRegions(grp)
      local bg = grp:CreateTexture(nil, "BACKGROUND"); AFUI.SetColor(bg, 0.03, 0.03, 0.03, 0.55); bg:SetAllPoints(grp)
      local label = _G["RaidGroup" .. i .. "Label"]
      if label and label.SetFontObject then label:SetFontObject(GameFontNormal) end
    end
  end
  K.each({ "RaidFrameReadyCheckButton", "RaidFrameAddMemberButton" }, K.button)
end

local function away(frame) -- hidden for good: the client re-shows widgets, so Show hides again
  if not frame then return end
  frame:Hide()
  if frame.Show then hooksecurefunc(frame, "Show", function(self) self:Hide() end) end
end
-- friends (hybrid: 10 rows made for 307 px cover 7 whole rows of 77 + 1) and ignore (faux: 19 rows of 28 = 532) lists fill the region
function S.LayoutLists(f)
  local L, w = S.LIST, S.ListWidth()
  local function place(name, rowH)
    local sf = _G[name]
    if not sf then return end
    sf:ClearAllPoints(); sf:SetPoint("TOPLEFT", f, "TOPLEFT", L.x, -L.top); sf:SetWidth(w); sf:SetHeight(S.ListHeight(rowH))
    if type(sf.ScrollChild) == "table" then sf.ScrollChild:SetWidth(w) end
    local sb = _G[name .. "ScrollBar"]
    if sb then sb:ClearAllPoints(); sb:SetPoint("TOPLEFT", sf, "TOPRIGHT", L.bar, -14); sb:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", L.bar, 14); sb:SetWidth(17) end
    for _, k in ipairs({ "Top", "Middle", "Bottom" }) do away(_G[name .. k]) end -- the client's scroll bar frame art
  end
  place("FriendsFrameFriendsScrollFrame", S.ROW.friend)
  place("FriendsFrameIgnoreScrollFrame", S.ROW.ignore)
  _G.IGNORES_TO_DISPLAY = math.min(_G.IGNORES_TO_DISPLAY or 19, math.floor(S.ListHeight(S.ROW.ignore) / S.ROW.ignore))
  local first = _G.FriendsFrameIgnoreButton1
  if first then first:ClearAllPoints(); first:SetPoint("TOPLEFT", f, "TOPLEFT", L.x, -L.top) end
end
-- A side tab does what the client's tab buttons do (FriendsFrame.lua 2.5.3: PanelTemplates_SetTab on the frame / FriendsTabHeader, then FriendsFrame_Update,
-- which shows exactly one page): no script of the client's hidden buttons is pressed, so a click never depends on them being enabled or visible.
function S.Go(key)
  local f, r = _G.FriendsFrame, S.ROUTE[key]
  if not f or not r then return end
  local function set(fr, i) if type(_G.PanelTemplates_SetTab) == "function" then PanelTemplates_SetTab(fr, i) end; fr.selectedTab = i end
  set(f, r.tab)
  if r.sub and _G.FriendsTabHeader then set(_G.FriendsTabHeader, r.sub) end
  if f:IsShown() then
    if type(_G.FriendsFrame_Update) == "function" then FriendsFrame_Update() end
  elseif type(_G.ShowUIPanel) == "function" then ShowUIPanel(f) end
  S.RefreshSide()
end
local function selected(fr) if _G.PanelTemplates_GetSelectedTab then return PanelTemplates_GetSelectedTab(fr) end; return fr and fr.selectedTab end
-- Forever titles the window by its page (f0041 "Friends", f0045 "Raid"); the client keeps "Friends List" / "Who" and the title follows the lit tab.
S.TITLES = { friends = "Friends", ignore = "Ignore List", who = "Who List", raid = "Raid" }
function S.English() local l = _G.GetLocale and GetLocale() or "enUS"; return l == "enUS" or l == "enGB" end
function S.RefreshSide()
  local f = _G.FriendsFrame
  local active = S.SideOf(f and selected(f), _G.FriendsTabHeader and selected(_G.FriendsTabHeader))
  local title = _G.FriendsFrameTitleText
  if title and title.SetText and S.TITLES[active] and S.English() then title:SetText(S.TITLES[active]) end
  for i, d in ipairs(S.SIDE) do local b = _G["AFUISocialTab" .. i]; if b then b.afActive = (d.key == active) end end
  local dd = _G.FriendsFrameStatusDropDown -- the status pill belongs to the friend pages only
  if dd and dd.Show and f and f:IsShown() then if active == "friends" or active == "ignore" then dd:Show() else dd:Hide() end end
  K.refreshTabs()
end
-- The status dropdown (a 22 px wide client frame: the generic dropdown bar went negative in it) is a fixed 60 x 24 pill with the status dot inside; the whole
-- pill opens the client's menu.
S.PILL = { w = 60, h = 24 }

-- Available / Away / Busy: the player's AFK and DND chat flags (SendChatMessage with "AFK" / "DND" toggles them, as /afk and /dnd do). The client's own menu went through
-- Battle.net calls that do nothing on a server without it, so the pill opens a menu of ours (never the client's UIDropDownMenu) that sets the flags directly; the client's
-- own updater keeps the status dot in step on PLAYER_FLAGS_CHANGED.
S.STATUS = { { key = "online", text = "Available", icon = "Interface\\FriendsFrame\\StatusIcon-Online" },
  { key = "away", text = "Away", icon = "Interface\\FriendsFrame\\StatusIcon-Away" },
  { key = "busy", text = "Busy", icon = "Interface\\FriendsFrame\\StatusIcon-DnD" } }
function S.StatusCurrent()
  if _G.UnitIsAFK and UnitIsAFK("player") then return "away" end
  if _G.UnitIsDND and UnitIsDND("player") then return "busy" end
  return "online"
end
-- Returns true when something was sent. Away and Busy replace each other: the current flag is cleared first (both commands toggle).
function S.SetStatus(key)
  local cur = S.StatusCurrent()
  if cur == key or not _G.SendChatMessage then return false end
  if cur == "away" then SendChatMessage("", "AFK") elseif cur == "busy" then SendChatMessage("", "DND") end
  if key == "away" then SendChatMessage("", "AFK") elseif key == "busy" then SendChatMessage("", "DND") end
  return true
end
-- The pill's dot follows the flags: the client's updater did not repaint it after our menu changed them, so it is set here from the current status.
function S.UpdateStatusDot()
  local st = _G.FriendsFrameStatusDropDownStatus
  if not (st and st.SetTexture) then return false end
  local cur = S.StatusCurrent()
  for _, d in ipairs(S.STATUS) do if d.key == cur then st:SetTexture(d.icon); return d.key end end
end
local statusMenu
function S.CloseStatusMenu() if statusMenu then statusMenu:Hide() end end
function S.OpenStatusMenu(pill)
  if not statusMenu then
    local m = CreateFrame("Frame", "AFUI_StatusMenu", UIParent)
    m:SetFrameStrata("FULLSCREEN_DIALOG"); m:SetWidth(112); m:SetHeight(#S.STATUS * 22 + 8)
    local rim = m:CreateTexture(nil, "BACKGROUND"); AFUI.SetColor(rim, 0.45, 0.37, 0.2, 1); rim:SetAllPoints(m)
    local fill = m:CreateTexture(nil, "BORDER"); AFUI.SetColor(fill, 0.03, 0.025, 0.02, 0.97)
    fill:SetPoint("TOPLEFT", m, "TOPLEFT", 1, -1); fill:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -1, 1)
    m.rows = {}
    for i, d in ipairs(S.STATUS) do
      local b = CreateFrame("Button", nil, m)
      b:SetWidth(104); b:SetHeight(22); b:SetPoint("TOPLEFT", m, "TOPLEFT", 4, -4 - (i - 1) * 22)
      local hl = b:CreateTexture(nil, "HIGHLIGHT"); AFUI.SetColor(hl, 0.82, 0.74, 0.1, 0.18); hl:SetAllPoints(b)
      b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetWidth(12); b.icon:SetHeight(12); b.icon:SetPoint("LEFT", b, "LEFT", 6, 0); b.icon:SetTexture(d.icon)
      b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0); b.text:SetText(d.text)
      b:SetScript("OnClick", function() S.SetStatus(d.key); S.CloseStatusMenu() end)
      m.rows[i] = b
    end
    local catcher = CreateFrame("Button", nil, UIParent) -- a click anywhere else closes the menu
    catcher:SetAllPoints(UIParent); catcher:SetFrameStrata("FULLSCREEN_DIALOG"); catcher:SetFrameLevel(m:GetFrameLevel() - 1); catcher:Hide()
    catcher:SetScript("OnClick", S.CloseStatusMenu)
    m:SetScript("OnShow", function() catcher:Show() end)
    m:SetScript("OnHide", function() catcher:Hide() end)
    if _G.UISpecialFrames then table.insert(UISpecialFrames, "AFUI_StatusMenu") end
    statusMenu = m
  end
  if statusMenu:IsShown() then statusMenu:Hide(); return statusMenu end
  local cur = S.StatusCurrent()
  for i, d in ipairs(S.STATUS) do
    local r = statusMenu.rows[i]
    if d.key == cur then r.text:SetTextColor(1, 0.82, 0) else r.text:SetTextColor(1, 1, 1) end
  end
  statusMenu:ClearAllPoints(); statusMenu:SetPoint("TOPLEFT", pill, "BOTTOMLEFT", 0, -2)
  statusMenu:Show()
  return statusMenu
end
function S.StatusPill(dd)
  if dd.afPill then return end
  dd.afPill = true
  K.dropdown(dd)
  dd.afBar.l:SetAlpha(0); dd.afBar.m:SetAlpha(0); dd.afBar.r:SetAlpha(0) -- the generic bar stays out of this narrow frame
  local pill = CreateFrame("Button", nil, dd)
  pill:SetWidth(S.PILL.w); pill:SetHeight(S.PILL.h); pill:SetPoint("LEFT", dd, "LEFT", 14, 0)
  pill:SetFrameLevel(dd:GetFrameLevel() + 3)
  local W = AFUI.EditModeWidgets
  local field = (W and W.ForeverField) or K.bar
  field(pill, "BACKGROUND"):place(pill, 0, 0, 0, 0)
  pill:SetScript("OnClick", function(self) S.OpenStatusMenu(self) end)
  local st = _G.FriendsFrameStatusDropDownStatus
  if st and st.SetParent then st:SetParent(pill); st:ClearAllPoints(); st:SetPoint("LEFT", pill, "LEFT", 8, 0) end
  S.UpdateStatusDot()
  for _, e in ipairs({ "PLAYER_FLAGS_CHANGED", "PLAYER_ENTERING_WORLD" }) do AFUI.On(e, function(_, unit) if e ~= "PLAYER_FLAGS_CHANGED" or unit == nil or unit == "player" then S.UpdateStatusDot() end end) end
  pill:HookScript("OnShow", S.UpdateStatusDot)
end
function S.SideTabs(f)
  for _, n in ipairs(S.GONE) do local b = _G[n]; if b then b:SetAlpha(0); if b.EnableMouse then b:EnableMouse(false) end end end
  for _, n in ipairs(S.HIDDEN) do away(_G[n]) end
  local add = _G.FriendsFrameAddFriendButton -- Forever: one centred red button under the list
  if add then
    add:SetWidth(154); add:ClearAllPoints(); add:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)
    if S.English() and add.SetText then add:SetText("Add New Friend") end -- Forever words it so (f0041)
  end
  -- Ignore / Unignore sat on the scroll bar's down arrow (BOTTOMLEFT 4 / BOTTOMRIGHT -6): a centred pair keeps the arrow clickable
  local ig, un = _G.FriendsFrameIgnorePlayerButton, _G.FriendsFrameUnsquelchButton
  if ig then ig:SetWidth(120); ig:ClearAllPoints(); ig:SetPoint("BOTTOM", f, "BOTTOM", -64, 6) end
  if un then un:SetWidth(120); un:ClearAllPoints(); un:SetPoint("BOTTOM", f, "BOTTOM", 64, 6) end
  local dd = _G.FriendsFrameStatusDropDown
  if dd then dd:ClearAllPoints(); dd:SetPoint("TOPLEFT", f, "TOPLEFT", 52, -28); S.StatusPill(dd) end
  local ri = _G.RaidInfoFrame -- the side tabs take the strip it used to open on
  if ri then ri:ClearAllPoints(); ri:SetPoint("TOPLEFT", f, "TOPRIGHT", 64, -28) end
  for i, d in ipairs(S.SIDE) do
    local b = CreateFrame("Button", "AFUISocialTab" .. i, f)
    K.sideTab(b, f, i, d.icon, d.tip)
    b:SetScript("OnClick", function() S.Go(d.key) end)
  end
  for _, fn in ipairs({ "FriendsFrame_Update", "FriendsFrame_ShowSubFrame", "PanelTemplates_SetTab", "FriendsTabHeader_ClickTab" }) do
    if type(_G[fn]) == "function" then hooksecurefunc(fn, S.RefreshSide) end
  end
  f:HookScript("OnShow", S.RefreshSide)
  S.RefreshSide()
end

-- Row 2 of Forever's window (video 3): status pill, the player's battletag, the menu button; and the "Friends List 2/10" section bar over the list.
function S.FriendCounts()
  local on, total = 0, 0
  if _G.C_FriendList and C_FriendList.GetNumFriends then total = total + (C_FriendList.GetNumFriends() or 0); on = on + ((C_FriendList.GetNumOnlineFriends and C_FriendList.GetNumOnlineFriends()) or 0) end
  if _G.BNGetNumFriends then local t, o = BNGetNumFriends(); total = total + (t or 0); on = on + (o or 0) end
  return on, total
end
S.STRIP_PAGES = { FriendsListFrame = true, IgnoreListFrame = true } -- the pages that show the status row (plate, BattleTag, menu)
function S.StripFor(name)
  local st = S.strip
  if not st then return end
  if S.STRIP_PAGES[name] then st:Show() else st:Hide() end -- Who and Raid have nothing to show in it
end
function S.Header(f)
  local page = _G.FriendsListFrame
  local strip = CreateFrame("Frame", "AFUISocialStrip", f); strip:SetAllPoints(f); S.strip = strip
  local field = CreateFrame("Frame", "AFUISocialTag", strip)
  field:SetHeight(26); field:SetPoint("TOPLEFT", f, "TOPLEFT", 122, -28); field:SetPoint("TOPRIGHT", f, "TOPRIGHT", -52, -28)
  -- the grey-olive plate behind the status row (f0041: 38 u tall under the title bar, a dark rule under it) and the blue tag field without a bronze rim
  local band = strip:CreateTexture(nil, "BORDER"); AFUI.SetColor(band, 0.225, 0.215, 0.19, 1)
  band:SetPoint("TOPLEFT", f, "TOPLEFT", S.BAND_X, -23); band:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -23); band:SetHeight(38)
  local rule = strip:CreateTexture(nil, "BORDER"); AFUI.SetColor(rule, 0.07, 0.065, 0.055, 1)
  rule:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, 0); rule:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT", 0, 0); rule:SetHeight(2)
  local rim = field:CreateTexture(nil, "BACKGROUND"); AFUI.SetColor(rim, 0.07, 0.13, 0.21, 1); rim:SetAllPoints(field)
  local fill = field:CreateTexture(nil, "BORDER"); AFUI.SetColor(fill, 0.04, 0.11, 0.2, 1); fill:SetPoint("TOPLEFT", field, "TOPLEFT", 1, -1); fill:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", -1, 1)
  local tag = field:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); tag:SetPoint("CENTER", field, "CENTER"); tag:SetTextColor(0.5, 0.66, 0.8)
  local function paintTag()
    local name = _G.BNGetInfo and select(2, BNGetInfo())
    if name and name ~= "" then tag:SetText(name); field:Show() else field:Hide() end
  end
  -- the copy glyph after the tag (f0041, two overlapping squares): 2.5.3 has no clipboard call, so it opens a one-line box with the tag selected for Ctrl+C
  local copy = CreateFrame("Button", "AFUISocialTagCopy", field)
  copy:SetWidth(14); copy:SetHeight(14); copy:SetPoint("LEFT", tag, "RIGHT", 8, 0)
  for i, o in ipairs({ { 0, 0 }, { 3, -3 } }) do
    local box = CreateFrame("Frame", nil, copy); box:SetWidth(9); box:SetHeight(9); box:SetPoint("TOPLEFT", copy, "TOPLEFT", o[1], o[2]); box:SetFrameLevel(copy:GetFrameLevel() + i)
    local rim = box:CreateTexture(nil, "BACKGROUND"); AFUI.SetColor(rim, 0.62, 0.7, 0.8, 1); rim:SetAllPoints(box)
    local hole = box:CreateTexture(nil, "BORDER"); AFUI.SetColor(hole, 0.05, 0.11, 0.16, 1); hole:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1); hole:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1)
  end
  copy:SetScript("OnClick", function()
    local name = _G.BNGetInfo and select(2, BNGetInfo())
    if name and name ~= "" and _G.StaticPopup_Show then StaticPopup_Show("AFUI_COPY_TAG", nil, nil, name) end
  end)
  copy:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Copy BattleTag", 1, 1, 1); GameTooltip:Show() end)
  copy:SetScript("OnLeave", function() GameTooltip:Hide() end)
  if _G.StaticPopupDialogs then
    StaticPopupDialogs["AFUI_COPY_TAG"] = { text = "Press Ctrl+C to copy your BattleTag.", button1 = _G.OKAY or "OK", hasEditBox = 1, editBoxWidth = 200, timeout = 0, whileDead = 1, hideOnEscape = 1,
      OnShow = function(self, data) local eb = self.editBox or _G[self:GetName() .. "EditBox"]; if eb then eb:SetText(data or ""); eb:HighlightText(); eb:SetFocus() end end,
      EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end, EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end }
  end
  field:SetScript("OnShow", paintTag); paintTag()
  AFUI.On("BN_INFO_CHANGED", paintTag)
  local menu = CreateFrame("Button", "AFUISocialMenu", strip)
  menu:SetWidth(28); menu:SetHeight(28); menu:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -27)
  AFUI.SetButtonAtlas(menu, { "common-button-square-gray-up", "common-button-square-gray-down", "common-button-square-gray-up", "common-button-square-gray-up" })
  for i = 0, 2 do local l = menu:CreateTexture(nil, "OVERLAY"); AFUI.SetColor(l, 1, 0.82, 0, 1); l:SetWidth(14); l:SetHeight(2); l:SetPoint("CENTER", menu, "CENTER", 0, 5 - i * 5) end
  menu:SetScript("OnClick", function(self)
    local W = AFUI.EditModeWidgets
    if not (W and W.OpenMenu) then return end
    W.OpenMenu(self, {
      { text = "Friends", func = function() S.Go("friends") end },
      { text = "Ignore List", func = function() S.Go("ignore") end },
      { text = "Raid Info", func = function() S.Go("raid"); local b = _G.RaidFrameRaidInfoButton; if b and b.Click then b:Click() end end },
    }, 120)
  end)
  menu:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Menu", 1, 1, 1); GameTooltip:Show() end)
  menu:SetScript("OnLeave", function() GameTooltip:Hide() end)
  if type(_G.FriendsFrame_ShowSubFrame) == "function" then hooksecurefunc("FriendsFrame_ShowSubFrame", function(name) S.StripFor(name) end) end
  if not (page and AFUI.ListBar) then return end
  local head = CreateFrame("Button", "AFUISocialListHead", page)
  head:SetHeight(24); head:SetPoint("TOPLEFT", f, "TOPLEFT", S.LIST.x, -62); head:SetPoint("TOPRIGHT", f, "TOPRIGHT", -S.LIST.right, -62)
  head.bar = AFUI.ListBar(head); head.bar.Show()
  head.text = head:CreateFontString(nil, "OVERLAY", "GameFontNormal"); head.text:SetPoint("LEFT", head, "LEFT", 8, 0); head.text:SetTextColor(0.78, 0.76, 0.72)
  head.sign = head:CreateTexture(nil, "OVERLAY"); head.sign:SetWidth(13); head.sign:SetHeight(4); head.sign:SetPoint("RIGHT", head, "RIGHT", -6, 0)
  head:SetHighlightTexture(PLAIN .. "UI-Background-Rock", "ADD"); local ht = head:GetHighlightTexture(); if ht then ht:SetAlpha(0.08) end
  S.listHead = head
  local function paint()
    local on, total = S.FriendCounts()
    head.text:SetText("Friends List " .. on .. "/" .. total)
    AFUI.SetAtlas(head.sign, S.listCollapsed and "common-button-list-plus-c60" or "common-button-list-minus-c60")
    head.sign:SetHeight(S.listCollapsed and 13 or 4)
    local sf = _G.FriendsFrameFriendsScrollFrame
    if sf then if S.listCollapsed then sf:Hide() else sf:Show() end end
  end
  S.PaintListHead = paint
  head:SetScript("OnClick", function() S.listCollapsed = not S.listCollapsed; paint() end)
  head:SetScript("OnShow", paint)
  for _, e in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE" }) do AFUI.On(e, function() if head:IsShown() then paint() end end) end
  if type(_G.FriendsList_Update) == "function" then hooksecurefunc("FriendsList_Update", function() if S.listCollapsed then paint() end end) end
  paint()
end

-- Who header 2 (2.5.3 FriendsFrame.xml): WhoFrameDropDown hangs at TOPLEFT -15,0 of the header with the client's own Left / Middle / Right art and a 24 px arrow
-- button at the right end of ITS bar (UIDropDownMenu_SetWidth), so the bar's cap stuck out above / below the header and over the Lvl header. Forever's column
-- selector is only a small gold arrow inside the header: the dropdown now fills the header, its art is off, and the button is the arrow, 4 px from the right edge.
S.WHO_ARROW = { inset = 4, pad = 6 } -- arrow button 4 px from the header's right edge; header height minus 6 tall (never taller than the header)
function S.WhoArrowRect(hw, hh) -- the arrow button's rect inside a hw x hh header: x, y (from the header's bottom-left), w, h
  local sz = math.min(18, hh - S.WHO_ARROW.pad)
  return hw - S.WHO_ARROW.inset - sz, (hh - sz) / 2, sz, sz
end
function S.StyleWhoDropdown()
  local wd, h2 = _G.WhoFrameDropDown, _G.WhoFrameColumnHeader2
  if not wd or not h2 or wd.afWhoDrop then return end
  wd.afWhoDrop = true
  for _, k in ipairs({ "l", "m", "r" }) do if wd.afBar and wd.afBar[k] then wd.afBar[k]:SetAlpha(0) end end
  wd:ClearAllPoints(); wd:SetPoint("TOPLEFT", h2, "TOPLEFT", 0, 0); wd:SetPoint("BOTTOMRIGHT", h2, "BOTTOMRIGHT", 0, 0)
  local btn = _G.WhoFrameDropDownButton
  if btn then
    local _, _, sz = S.WhoArrowRect(h2:GetWidth() or 0, h2:GetHeight() or 24)
    btn:ClearAllPoints(); btn:SetPoint("RIGHT", h2, "RIGHT", -S.WHO_ARROW.inset, 0); btn:SetWidth(sz); btn:SetHeight(sz)
    -- the client's square plate (Normal / Pushed / Disabled) goes; Forever's gold arrow replaces it, hover and pressed light it
    for _, k in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do local t = btn[k] and btn[k](btn); if t then t:SetAlpha(0) end end
    btn:SetHighlightTexture("")
    AFUI.SetButtonAtlas(btn, { "minimal-scrollbar-arrow-bottom-c60", "minimal-scrollbar-arrow-bottom-over-c60", "minimal-scrollbar-arrow-bottom-over-c60" })
    for i, k in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
      local t = btn[k](btn)
      if t then t:SetAlpha(1); t:ClearAllPoints(); t:SetPoint("CENTER", btn, "CENTER", 0, i == 2 and -1 or 0); t:SetWidth(17); t:SetHeight(11) end
    end
  end
  local t = _G.WhoFrameDropDownText -- the "Zone" label: left in the header, ending before the arrow, cut with "..." instead of running under it
  if t then
    t:ClearAllPoints(); t:SetPoint("LEFT", h2, "LEFT", 8, 0); t:SetPoint("RIGHT", h2, "RIGHT", -(S.WHO_ARROW.inset + 18 + 2), 0)
    t:SetJustifyH("LEFT"); t:SetWordWrap(false); t:SetFontObject(GameFontNormal) -- same font as the other headers
  end
  for i = 1, 4 do -- the other headers' texts stay inside their plate and truncate
    local h = _G["WhoFrameColumnHeader" .. i]
    local fs = h and h ~= h2 and h.GetFontString and h:GetFontString()
    if fs then fs:ClearAllPoints(); fs:SetPoint("LEFT", h, "LEFT", 8, 0); fs:SetPoint("RIGHT", h, "RIGHT", -4, 0); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false) end
  end
end

-- Bottom of the Who page (2.5.3: three 85 / 120 / 120 px buttons, a 296 x 32 edit box at BOTTOM -10,20): the three buttons are one size with 4 px between, the
-- search box spans the same left and right edges 10 px above them (Forever has no placeholder text in it, so none is added).
S.WHO_BTN = { w = 105, gap = 4 }
function S.StyleWhoBottom()
  local inv, add, who, wb = _G.WhoFrameGroupInviteButton, _G.WhoFrameAddFriendButton, _G.WhoFrameWhoButton, _G.WhoFrameEditBox
  if not (inv and add and who) or inv.afWhoRow then return end
  inv.afWhoRow = true
  for _, b in ipairs({ inv, add, who }) do b:SetWidth(S.WHO_BTN.w) end
  add:ClearAllPoints(); add:SetPoint("RIGHT", inv, "LEFT", -S.WHO_BTN.gap, 0)
  who:ClearAllPoints(); who:SetPoint("RIGHT", add, "LEFT", -S.WHO_BTN.gap, 0)
  if wb then -- the search border draws 4 px outside the box and 5 above / below: box 4 px in from the button edges, 10 px above them
    wb:SetHeight(20); wb:ClearAllPoints()
    wb:SetPoint("BOTTOMLEFT", who, "TOPLEFT", 4, 10); wb:SetPoint("BOTTOMRIGHT", inv, "TOPRIGHT", -4, 10)
  end
end

-- The medallion's glyph (AFUI-Tab-Friends, 64 px: the drawn part spans x .156-.828, y .203-.844) has transparent padding and the ring opening has no floor of its
-- own, so the world showed through its upper half ("cut"). A dark disc, strips of the ring's circle (Compat's PortraitStrips) under the picture, fills the opening,
-- and the texcoords crop the padding evenly (a square centred on the glyph) so the whole glyph shows, centred, nearly as wide as the opening.
S.MEDAL = { 0.12, 0.86, 0.15, 0.89 }
-- The status plate starts right of the ring (disc edge 51.5 + the ring's rim): from x 8 it was drawn above the medallion and covered its lower third.
S.BAND_X = 58
S.DISC = { cx = 25, cy = -22, r = 26.5, step = 4, color = { 0.03, 0.05, 0.07 } }
function S.PortraitDisc(f)
  if f.afDisc then return f.afDisc end
  local d, strips = S.DISC, {}
  for i, s in ipairs(AFUI.PortraitStrips(d.r, d.step)) do
    local t = f:CreateTexture(nil, "BORDER")
    AFUI.SetColor(t, d.color[1], d.color[2], d.color[3], 1)
    t:SetWidth(2 * s[3]); t:SetHeight(s[2] - s[1]); t:SetPoint("TOPLEFT", f, "TOPLEFT", d.cx - s[3], d.cy - s[1])
    strips[i] = t
  end
  f.afDisc = strips
  return strips
end

local function setup()
  if done then return end
  local f = _G.FriendsFrame
  if not f then return end
  done = true
  local cut = AFUI.IS_243 and S.CUT_243 or 0
  if not AFUI.IS_243 then f:SetWidth(S.SIZE.w); f:SetHeight(S.SIZE.h) end -- before the chrome reads the size
  K.window(f, { icon = ICON, title = "FriendsFrameTitleText", close = "FriendsFrameCloseButton", cut = cut, keys = S.KEYS, hide = S.INSETS })
  if not AFUI.IS_243 and f.afPortrait then -- the medallion (f0041): two people in teal on black, here the gold glyph tinted
    local pt = f.afPortrait
    S.PortraitDisc(f)
    pt:SetTexture(PLAIN .. "AFUI-Tab-Friends"); pt:SetTexCoord(unpack(S.MEDAL))
    if pt.SetDesaturated then pt:SetDesaturated(true) end
    pt:SetVertexColor(0.2, 0.72, 0.9)
  end
  for _, n in ipairs(S.PAGES) do local p = _G[n]; if p then AFUI.Professions.Kit.hideRegions(p) end end
  if AFUI.IS_243 then
    K.tabs(f, S.TABS, f.afWin.h, cut)
    K.tabs(f, S.SUBTABS, f.afWin.h, cut, nil, true)
  else
    S.SideTabs(f)
    S.Header(f)
    S.LayoutLists(f)
  end
  K.each(S.BUTTONS, K.button)
  K.each(S.HEADERS, K.header)
  K.each(S.DROPDOWNS, K.dropdown)
  if not AFUI.IS_243 then S.StyleWhoDropdown() end -- 2.5.3: header 2 is the dropdown (Zone / Guild / Race)
  K.each(S.EDITS, K.edit)
  local wb = _G.WhoFrameEditBox
  if AFUI.IS_243 then
    if wb and _G.WhoFrame then wb:SetHeight(20); wb:ClearAllPoints(); wb:SetPoint("BOTTOM", _G.WhoFrame, "BOTTOM", -20, 112) end
  else
    S.StyleWhoBottom()
  end
  K.each(K.Numbered("GuildControlPopupFrameCheckbox", 16), K.check)
  K.each({ "RaidFrameAllAssistCheckButton" }, K.check) -- 2.5.3 RaidFrame.xml: "All" assist box, TOPLEFT 58,-23
  K.each(S.RowNames(AFUI.IS_243 and "2.4.3" or "2.5.3"), K.row)
  for _, n in ipairs(S.SCROLLBARS) do K.scroll(n, { x = S.LIST.bar }) end
  for _, p in ipairs(S.PANELS) do
    local pf = _G[p[1]]
    if pf then
      K.panel(pf)
      if p[2] and _G[p[2]] then AFUI.Professions.Kit.closeButton(_G[p[2]], pf) end
    end
  end
  -- 2.5.3: the raid view is its own window; same chrome
  local rp = _G.RaidParentFrame
  if rp and not rp.afWin then
    K.window(rp, { icon = ICON, title = "RaidParentFrameTitleText", close = "RaidParentFrameCloseButton", keys = S.KEYS })
    K.tabs(rp, { "RaidParentFrameTab1", "RaidParentFrameTab2" }, rp.afWin.h, 0)
  end
  if IsAddOnLoaded and IsAddOnLoaded("Blizzard_RaidUI") then skinRaidUI() end
  if not AFUI.IS_243 then growRows() end
  f:HookScript("OnShow", function() K.refreshTabs() end)
end

function S.Setup() AFUI.RunOutOfCombat(setup) end
AFUI.On("ADDON_LOADED", function(_, name)
  if name == "Blizzard_RaidUI" then AFUI.RunOutOfCombat(skinRaidUI) end
end)
AFUI.RegisterModule("SocialFrame", { OnLogin = S.Setup })
