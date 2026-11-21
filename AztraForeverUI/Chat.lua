-- Forever's chat frames (docs/forever-ref/chat.md) on Blizzard's own chat windows, tabs, buttons and edit box.
-- Forever draws chat from plain Interface\ChatFrame files. 2.5.3 ships the same files by the same paths and already uses
-- them; 2.4.3 has the 2008 art, so its regions get the TGAs from tools/chat-art.mjs (Media\chat), and regions Forever has
-- and 2.4.3 lacks are added under Blizzard's names. Docking, dragging, scrolling and the combat log stay Blizzard's.
local IS_243 = AFUI.IS_243

-- Version differences. 2.4.3: FrameXML FloatingChatFrame.xml/ChatFrame.xml (MOUZU/Blizzard-WoW-Interface 2.4.3);
-- 2.5.3: the same files at Gethe/wow-ui-source tag 2.5.3.
local V = IS_243 and {
  windows = 7,              -- ChatFrame1..7 (FloatingChatFrame.xml:688-834)
  media = "Interface\\AddOns\\AztraForeverUI\\Media\\chat\\",
  padded = true,            -- our TGAs are padded squares: texcoords from ART
  oldArt = true,            -- 2008 window border (Resize* buttons), tab, edit box: replaced
  scroll = "",              -- ChatFrame1UpButton/DownButton/BottomButton on the window (:563-648)
  tile = false,             -- no SetHorizTile/SetVertTile: tiling art is stretched (it is uniform along that axis)
  wheel = true,             -- no mouse-wheel scrolling of its own
  channelButton = true,     -- no ChatFrameChannelButton
} or {
  windows = 10,             -- ChatFrame1..10 (FloatingChatFrame.xml:746-888)
  media = "Interface\\ChatFrame\\",
  scroll = "ButtonFrame",   -- ChatFrame1ButtonFrameUpButton/... (:460-535)
  tile = true,
  newWindow = "FloatingChatFrame_OnLoad", -- temporary whisper windows are made at run time
  savedSize = true,         -- GetChatWindowSavedDimensions (FloatingChatFrame.lua:1253-1274)
}

-- Real size of each Media\chat file (the TGA is that, padded to a square power of two). Printed by tools/chat-art.mjs.
local ART = {
  ["ui-hud-actionbar-bag"] = { 256, 256 }, -- extracted here with the chat files; BarExtras uses it for the backpack
  ["UI-ChatFrame-BorderCorner"] = { 8, 8 },
  ["UI-ChatFrame-BorderLeft"] = { 16, 16 },
  ["UI-ChatFrame-BorderTop"] = { 16, 16 },
  ["ChatFrameTab-BGLeft"] = { 16, 32 },
  ["ChatFrameTab-BGMid"] = { 32, 32 },
  ["ChatFrameTab-BGRight"] = { 16, 32 },
  ["ChatFrameTab-SelectedLeft"] = { 16, 32 },
  ["ChatFrameTab-SelectedMid"] = { 32, 32 },
  ["ChatFrameTab-SelectedRight"] = { 16, 32 },
  ["ChatFrameTab-HighlightLeft"] = { 16, 32 },
  ["ChatFrameTab-HighlightMid"] = { 32, 32 },
  ["ChatFrameTab-HighlightRight"] = { 16, 32 },
  ["ChatFrameTab-NewMessage"] = { 128, 16 },
  ["UI-ChatInputBorder-Left2"] = { 32, 32 },
  ["UI-ChatInputBorder-Right2"] = { 32, 32 },
  ["UI-ChatInputBorder-Mid2"] = { 32, 32 },
  ["UI-ChatInputBorderFocus-Left"] = { 32, 32 },
  ["UI-ChatInputBorderFocus-Mid"] = { 32, 32 },
  ["UI-ChatInputBorderFocus-Right"] = { 32, 32 },
  ["UI-ChatIcon-Chat-Up"] = { 32, 32 },
  ["UI-ChatIcon-Chat-Down"] = { 32, 32 },
  ["UI-ChatIcon-Chat-Disabled"] = { 32, 32 },
  ["chatframe-button-up"] = { 27, 26 },
  ["chatframe-button-down"] = { 27, 26 },
  ["chatframe-button-highlight"] = { 27, 26 },
  ["chatframe-button-icon-voicechat"] = { 29, 29 },
}

local function Art(tex, name, flipU, flipV)
  local r, b = 1, 1
  if V.padded then
    local a, s = ART[name], 1
    while s < math.max(a[1], a[2]) do s = s * 2 end
    r, b = a[1] / s, a[2] / s
  end
  tex:SetTexture(V.media .. name)
  local l, t = 0, 0
  if flipU then l, r = r, 0 end
  if flipV then t, b = b, 0 end
  tex:SetTexCoord(l, r, t, b)
end

local TAB_COLOR = { 1, 0.5, 0.25 } -- DEFAULT_TAB_SELECTED_COLOR_TABLE (Forever floatingchatframe.lua:1452)
-- Tab alphas (Forever floatingchatframe.lua:15-20): selected or undocked / other docked tabs, without and with the mouse.
local TAB_REST, TAB_REST_OTHER, TAB_OVER, TAB_OVER_OTHER = 0.4, 0.2, 1, 0.6
-- The setting 'chatFade' (default on): off keeps the tabs at their mouse-over alphas, never dimmed.
local function Fades() return not (AFUI.GetSetting and AFUI.GetSetting("chatFade", true) == false) end
AFUI.ChatArt = { Art = Art, V = V } -- the strip and the copy windows of ChatQoL.lua draw with the same files

---------------------------------------------------------------- borders
local BORDER = { "Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
  "LeftTexture", "RightTexture", "BottomTexture", "TopTexture" }

-- FloatingBorderedFrame (Forever floatingchatframe.xml:3-75) on `frame`. Regions are named <frame><key> like Blizzard's,
-- so FCF_SetWindowColor/Alpha and the hover fades (CHAT_FRAME_TEXTURES) colour and fade them; existing ones are reused.
local function Bordered(frame)
  local n = frame:GetName()
  local function T(key, layer)
    local t = _G[n .. key]
    if not t then
      t = frame:CreateTexture(n .. key, layer)
      t:SetVertexColor(0, 0, 0); t:SetAlpha(0) -- until Blizzard applies the window's
    end
    return t
  end
  local bg = T("Background", "BACKGROUND")
  bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
  for _, p in ipairs({ { "TOPLEFT", -2, 3 }, { "TOPRIGHT", 2, 3 }, { "BOTTOMLEFT", -2, -6 }, { "BOTTOMRIGHT", 2, -6 } }) do
    bg:SetPoint(p[1], frame, p[1], p[2], p[3])
  end
  local c = {}
  for _, d in ipairs({ { "TopLeft", -4, 4 }, { "BottomLeft", -4, -4, false, true }, { "TopRight", 4, 4, true },
    { "BottomRight", 4, -4, true, true } }) do
    local t, point = T(d[1] .. "Texture", "BORDER"), d[1]:upper()
    t:SetWidth(8); t:SetHeight(8)
    t:ClearAllPoints(); t:SetPoint(point, bg, point, d[2], d[3])
    Art(t, "UI-ChatFrame-BorderCorner", d[4], d[5])
    c[d[1]] = t
  end
  for _, d in ipairs({
    { "Left", "UI-ChatFrame-BorderLeft", "TOPLEFT", "TopLeft", "BOTTOMLEFT", "BOTTOMLEFT", "BottomLeft", "TOPLEFT" },
    { "Right", "UI-ChatFrame-BorderLeft", "TOPRIGHT", "TopRight", "BOTTOMRIGHT", "BOTTOMRIGHT", "BottomRight", "TOPRIGHT", true },
    { "Bottom", "UI-ChatFrame-BorderTop", "BOTTOMLEFT", "BottomLeft", "BOTTOMRIGHT", "BOTTOMRIGHT", "BottomRight", "BOTTOMLEFT", false, true },
    { "Top", "UI-ChatFrame-BorderTop", "TOPLEFT", "TopLeft", "TOPRIGHT", "TOPRIGHT", "TopRight", "TOPLEFT" },
  }) do
    local t, vertical = T(d[1] .. "Texture", "BORDER"), d[1] == "Left" or d[1] == "Right"
    if vertical then t:SetWidth(16) else t:SetHeight(16) end
    t:ClearAllPoints()
    t:SetPoint(d[3], c[d[4]], d[5]); t:SetPoint(d[6], c[d[7]], d[8])
    Art(t, d[2], d[9], d[10])
    if V.tile then if vertical then t:SetVertTile(true) else t:SetHorizTile(true) end end
  end
end

---------------------------------------------------------------- tabs (2.4.3)
local function Selected(chat) return not chat.isDocked or chat == SELECTED_DOCK_FRAME end
local function TabAlpha(chat, tab)
  if tab.hasBeenFaded or not Fades() then return Selected(chat) and TAB_OVER or TAB_OVER_OTHER end
  return Selected(chat) and TAB_REST or TAB_REST_OTHER
end

-- ChatTabArtTemplate (Forever floatingchatframe.xml:241-320) on a 2.4.3 ChatTabTemplate tab.
local function SkinTab(chat)
  local n = chat:GetName() .. "Tab"
  local tab, L, M, R = _G[n], _G[n .. "Left"], _G[n .. "Middle"], _G[n .. "Right"]
  tab.afuiChat = chat
  Art(L, "ChatFrameTab-BGLeft"); Art(M, "ChatFrameTab-BGMid"); Art(R, "ChatFrameTab-BGRight")
  L:ClearAllPoints(); L:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", -2, 0)
  R:ClearAllPoints(); R:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 2, 0)
  M:ClearAllPoints(); M:SetPoint("LEFT", L, "RIGHT"); M:SetPoint("RIGHT", R, "LEFT") -- PanelTemplates_TabResize sizes the tab
  local function Row(kind, layer)
    local row = {}
    for i, part in ipairs({ { "Left", L }, { "Middle", M }, { "Right", R } }) do
      local t = tab:CreateTexture(n .. kind .. part[1], layer)
      Art(t, "ChatFrameTab-" .. kind .. (part[1] == "Middle" and "Mid" or part[1]))
      t:SetBlendMode("ADD"); t:SetVertexColor(TAB_COLOR[1], TAB_COLOR[2], TAB_COLOR[3])
      t:SetAllPoints(part[2])
      row[i] = t
    end
    return row
  end
  tab.afuiSelected = Row("Selected", "BORDER")
  Row("Highlight", "HIGHLIGHT")
  tab:GetHighlightTexture():SetTexture(nil) -- the 2008 highlight; the HIGHLIGHT row replaces it
  -- New-message glow on Blizzard's flash frame, so it shows (and pulses) while FCF_FlashTab flashes the tab.
  local glow = _G[n .. "Flash"]:CreateTexture(nil, "BORDER")
  Art(glow, "ChatFrameTab-NewMessage"); glow:SetBlendMode("ADD"); glow:SetHeight(16)
  glow:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 8, 0); glow:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -8, 0)
  local text = _G[n .. "Text"]
  text:ClearAllPoints(); text:SetPoint("CENTER", tab, "CENTER", 0, -5)
end

-- 2.4.3 hides tabs without the mouse; Forever keeps them at a resting alpha and shows the selected art.
local function UpdateTabs()
  for i = 1, V.windows do
    local chat, tab = _G["ChatFrame" .. i], _G["ChatFrame" .. i .. "Tab"]
    for _, t in ipairs(tab.afuiSelected) do if Selected(chat) then t:Show() else t:Hide() end end
    if chat.isDocked or chat:IsShown() then tab:Show(); tab:SetAlpha(TabAlpha(chat, tab)) end
    -- A docked window's button frame is alpha 1 (Forever FCF_DockFrame, floatingchatframe.lua:2255): its 0.25 panel is the
    -- textures' own alpha. At 0.2 on top of that the button column's panel was 5 % and the column looked missing.
    _G["ChatFrame" .. i .. "ButtonFrame"]:SetAlpha(chat.isDocked and 1 or 0.2)
  end
end

---------------------------------------------------------------- edit box (2.4.3)
local function Row3(eb, left, mid, right, file, suffix)
  for _, d in ipairs({ { left, "Left", "LEFT" }, { right, "Right", "RIGHT" } }) do
    d[1]:SetWidth(32); d[1]:SetHeight(32)
    d[1]:ClearAllPoints(); d[1]:SetPoint(d[3], eb, d[3])
    Art(d[1], file .. d[2] .. suffix)
  end
  mid:ClearAllPoints(); mid:SetHeight(32)
  mid:SetPoint("TOPLEFT", left, "TOPRIGHT"); mid:SetPoint("TOPRIGHT", right, "TOPLEFT")
  Art(mid, file .. "Mid" .. suffix)
end

-- ChatFrameEditBoxTemplate (Forever chatframeeditbox.xml:3-53) on 2.4.3's single shared ChatFrameEditBox.
local function SkinEditBox()
  local eb, left, right, mid = ChatFrameEditBox, ChatFrameEditBoxLeft, ChatFrameEditBoxRight
  for _, r in ipairs({ eb:GetRegions() }) do -- the unnamed 2008 middle (ChatFrame.xml:41-57)
    if r ~= left and r ~= right and r:GetObjectType() == "Texture" then mid = r end
  end
  Row3(eb, left, mid, right, "UI-ChatInputBorder-", "2")
  local focus = {}
  for i, k in ipairs({ "Left", "Mid", "Right" }) do
    focus[i] = eb:CreateTexture("ChatFrameEditBoxFocus" .. k, "BORDER")
    focus[i]:Hide()
  end
  Row3(eb, focus[1], focus[2], focus[3], "UI-ChatInputBorderFocus-", "")
  eb:HookScript("OnEditFocusGained", function() for _, t in ipairs(focus) do t:Show() end end)
  eb:HookScript("OnEditFocusLost", function() for _, t in ipairs(focus) do t:Hide() end end)
  ChatFrameEditBoxHeader:ClearAllPoints(); ChatFrameEditBoxHeader:SetPoint("LEFT", eb, "LEFT", 15, 0)
end

---------------------------------------------------------------- buttons
-- Forever's ScrollToBottomButton (floatingchatframe.xml:523-554): Blizzard's bottom button, whose Flash Blizzard already
-- blinks while the window is scrolled up, reskinned and moved into the window's bottom-right corner.
local RTB = "minimal-scrollbar-arrow-returntobottom"
local function BottomButton(chat) return _G[chat:GetName() .. V.scroll .. "BottomButton"] end

-- FCF_SetButtonSide (Forever floatingchatframe.lua:1556-1568); 2.4.3 moves only its bottom button there.
local function PlaceButtons(chat)
  local bf, bg = _G[chat:GetName() .. "ButtonFrame"], _G[chat:GetName() .. "Background"]
  bf:ClearAllPoints()
  if chat.buttonSide == "right" then
    bf:SetPoint("TOPLEFT", bg, "TOPRIGHT", 3, -3); bf:SetPoint("BOTTOMLEFT", bg, "BOTTOMRIGHT", 3, 6)
  else
    bf:SetPoint("TOPRIGHT", bg, "TOPLEFT", -3, -3); bf:SetPoint("BOTTOMRIGHT", bg, "BOTTOMLEFT", -3, 6)
  end
  local b = BottomButton(chat)
  b:ClearAllPoints(); b:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -2, 14) -- ResizeButton (16x16) TOPRIGHT -2,-2
end

local function SkinButtons(chat)
  local n = chat:GetName()
  -- buttonFrame (Forever floatingchatframe.xml:503-522): a bordered 29 wide column at alpha 0.2
  local bf = _G[n .. "ButtonFrame"] or CreateFrame("Frame", n .. "ButtonFrame", chat)
  bf:SetWidth(29); bf:SetAlpha(0.2)
  Bordered(bf)
  AFUI.Kill(_G[n .. V.scroll .. "UpButton"]); AFUI.Kill(_G[n .. V.scroll .. "DownButton"]) -- Forever scrolls by wheel
  local b = BottomButton(chat)
  b:SetParent(chat) -- out of the 0.2 alpha button frame (2.5.3)
  -- Blizzard's OnClick is self:GetParent():GetParent():ScrollToBottom() (button > ButtonFrame > window): reparented, that reaches UIParent and errors.
  if V.scroll == "ButtonFrame" then b:SetScript("OnClick", function() chat:ScrollToBottom() end) end
  b:SetWidth(17); b:SetHeight(15)
  AFUI.SetAtlas(b:GetNormalTexture(), RTB); AFUI.SetAtlas(b:GetPushedTexture(), RTB .. "-down")
  AFUI.SetAtlas(b:GetHighlightTexture(), RTB .. "-over")
  local flash = _G[b:GetName() .. "Flash"]
  AFUI.SetAtlas(flash, RTB); flash:SetBlendMode("ADD"); flash:ClearAllPoints(); flash:SetAllPoints(b)
  b:SetAlpha(0)
  -- Seen only while scrolled up. Driven by the scroll methods (ChatFrame.xml's buttons and the wheel call them), not by an
  -- OnUpdate on every window. Message adds never change AtBottom: a scrolled window keeps its offset.
  local function Sync()
    local a = chat:AtBottom() and 0 or 1
    if b:GetAlpha() ~= a then b:SetAlpha(a) end
  end
  for _, m in ipairs({ "ScrollUp", "ScrollDown", "ScrollToTop", "ScrollToBottom", "PageUp", "PageDown", "Clear" }) do
    if chat[m] then hooksecurefunc(chat, m, Sync) end
  end
  PlaceButtons(chat)
  if V.wheel then -- FloatingChatFrame_OnMouseScroll (Forever floatingchatframe.lua:321-327)
    chat:EnableMouseWheel(true)
    chat:SetScript("OnMouseWheel", function(self, delta) if delta > 0 then self:ScrollUp() else self:ScrollDown() end end)
  end
end

-- VoiceToggleButtonTemplate's look (2.5.3 VoiceToggleButton.xml; icon ChannelFrameButtonMixin.lua), opening 2.4.3's
-- channel pane like its TOGGLECHATTAB binding (Bindings.xml: ToggleFriendsFrame(4)).
local function MakeChannelButton()
  local b = CreateFrame("Button", "ChatFrameChannelButton", UIParent)
  b:SetWidth(27); b:SetHeight(26)
  for _, s in ipairs({ { "Normal", "chatframe-button-up" }, { "Pushed", "chatframe-button-down" }, { "Highlight", "chatframe-button-highlight" } }) do
    b["Set" .. s[1] .. "Texture"](b, V.media .. s[2])
    Art(b["Get" .. s[1] .. "Texture"](b), s[2])
  end
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetWidth(15); icon:SetHeight(15); icon:SetPoint("CENTER", b, "CENTER", 0, 0)
  Art(icon, "chatframe-button-icon-voicechat")
  local function Push(x, y, a) icon:ClearAllPoints(); icon:SetPoint("CENTER", b, "CENTER", x, y); icon:SetAlpha(a) end
  b:SetScript("OnMouseDown", function() Push(-1, -2, 0.75) end)
  b:SetScript("OnMouseUp", function() Push(0, 0, 1) end)
  b:SetScript("OnClick", function() if not IS_243 and ToggleChannelFrame then ToggleChannelFrame() else ToggleFriendsFrame(4) end end) -- 2.5.3 tab 4 is Raid; its TOGGLECHATTAB is ToggleChannelFrame
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(CHAT_CHANNELS); GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

---------------------------------------------------------------- windows
local function SkinWindow(chat)
  if chat.afuiSkinned then return end
  chat.afuiSkinned = true
  if V.oldArt then
    local n = chat:GetName()
    for _, k in ipairs({ "TopLeft", "TopRight", "BottomLeft", "BottomRight", "Top", "Bottom", "Left", "Right" }) do
      _G[n .. "Resize" .. k .. "Texture"]:SetTexture(nil) -- the 2008 border; the invisible edges still resize
    end
    Bordered(chat)
    SkinTab(chat)
  end
  SkinButtons(chat)
end

for i = 1, V.windows do SkinWindow(_G["ChatFrame" .. i]) end
-- Only now: Blizzard looks these names up on every window. 2.4.3 gets the button frame names appended so its colour and
-- fades follow the window. 2.5.3 must not: GMChatFrame_OnLoad walks the table and indexes _G[name .. value] without nil
-- checks, so it gets post-hooks on the window colour / alpha instead.
local have = {}
for _, k in ipairs(CHAT_FRAME_TEXTURES) do have[k] = true end
for _, k in ipairs(BORDER) do
  for _, key in ipairs(V.oldArt and { k, "ButtonFrame" .. k } or { k }) do
    if not have[key] then CHAT_FRAME_TEXTURES[#CHAT_FRAME_TEXTURES + 1] = key end
  end
end
if not V.oldArt then
  local function ButtonBorder(chat, fn, ...)
    for _, k in ipairs(BORDER) do
      local t = _G[chat:GetName() .. "ButtonFrame" .. k]
      if t then t[fn](t, ...) end
    end
  end
  hooksecurefunc("FCF_SetWindowColor", function(chat, r, g, b) ButtonBorder(chat, "SetVertexColor", r, g, b) end)
  hooksecurefunc("FCF_SetWindowAlpha", function(chat, alpha) ButtonBorder(chat, "SetAlpha", alpha or DEFAULT_CHATFRAME_ALPHA) end)
end
if V.newWindow then hooksecurefunc(V.newWindow, SkinWindow) end

if V.oldArt then
  SkinEditBox()
  hooksecurefunc("FCF_DockUpdate", UpdateTabs)
  hooksecurefunc("FCF_ChatTabFadeFinished", function(tab, chat)
    if chat.isDocked or chat:IsShown() then tab:Show(); tab:SetAlpha(TabAlpha(chat, tab)) end
  end)
  -- 2.4.3 fades tabs from 0 and out to 0 (FCF_OnUpdate); Forever between the resting and mouse-over alphas.
  hooksecurefunc("UIFrameFade", function(frame, info)
    local chat = frame.afuiChat
    if not chat then return end
    local sel = Selected(chat)
    if not Fades() then
      info.startAlpha = sel and TAB_OVER or TAB_OVER_OTHER; info.endAlpha = info.startAlpha; frame:SetAlpha(info.startAlpha); return
    end
    info.startAlpha = info.mode == "OUT" and (sel and TAB_OVER or TAB_OVER_OTHER) or (sel and TAB_REST or TAB_REST_OTHER)
    if info.mode == "OUT" then info.endAlpha = sel and TAB_REST or TAB_REST_OTHER
    else info.endAlpha = sel and TAB_OVER or TAB_OVER_OTHER end
    frame:SetAlpha(info.startAlpha)
  end)
else
  CHAT_TAB_SHOW_DELAY = 0.2 -- Forever floatingchatframe.lua:9
end
-- The resting tab alphas (2.5.3 reads the two constants at every fade; 2.4.3 re-runs UpdateTabs). Run again when 'chatFade' changes.
function AFUI.ChatApplyFade()
  if V.oldArt then UpdateTabs(); return end
  local f = Fades()
  CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA, CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA = f and TAB_REST or TAB_OVER, f and TAB_REST_OTHER or TAB_OVER_OTHER
end
if not V.oldArt then AFUI.ChatApplyFade() end
hooksecurefunc("FCF_SetButtonSide", PlaceButtons)

-- Forever's button column: channel button at the top, chat menu at the bottom (strata MEDIUM; Forever
-- floatingchatframevoicechat.xml:4-23, floatingchatframe.xml:723-738).
local channel = V.channelButton and MakeChannelButton() or ChatFrameChannelButton
channel:ClearAllPoints(); channel:SetPoint("TOP", ChatFrame1ButtonFrame, "TOP", 0, 0); channel:SetFrameStrata("MEDIUM")
ChatFrameMenuButton:ClearAllPoints(); ChatFrameMenuButton:SetPoint("BOTTOM", ChatFrame1ButtonFrame, "BOTTOM", 0, 0)
ChatFrameMenuButton:SetFrameStrata("MEDIUM")
for _, s in ipairs({ { "Normal", "Up" }, { "Pushed", "Down" }, { "Disabled", "Disabled" } }) do
  local t = ChatFrameMenuButton["Get" .. s[1] .. "Texture"](ChatFrameMenuButton)
  if t then Art(t, "UI-ChatIcon-Chat-" .. s[2]) end
end

-- Forever's top button is the social one: left click opens the channel pane (as it did), right click the friends window.
channel:HookScript("OnMouseUp", function(_, button) if button == "RightButton" and ToggleFriendsFrame then ToggleFriendsFrame(1) end end)
channel:HookScript("OnEnter", function() GameTooltip:AddLine("Right click: Friends", 0.7, 0.7, 0.7); GameTooltip:Show() end)

---------------------------------------------------------------- size and position
-- Forever Modern: 430x170 at BOTTOMLEFT 35,145 (mainline editmodepresetlayouts.lua:502-516, camelot
-- CHAT_FRAME_ANCHOR_OFFSET_Y); Mat's real client has it in the bottom left corner (y 28, measured). Blizzard still places ChatFrame1 for the old bars, so this re-runs after every
-- UIParent_ManageFramePositions / FCF_UpdateDockPosition. A window the player moved (user placed) or, on 2.5.3,
-- resized (saved dimensions) is left alone.
local function Place()
  local f = ChatFrame1
  if AFUI.ChatManaged or f:IsUserPlaced() then return end -- Edit Mode's "Chat Frame" system owns size and place (EditMode/Registry.lua)
  f:ClearAllPoints(); f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 35, 28)
  -- On a narrow screen (Mat's 1365 wide 2.4.3) 430 would run under the centred 562 px bars: stop 14 short of them.
  local width = math.max(250, math.min(430, math.floor((UIParent:GetWidth() - 562) / 2 - 35 - 14)))
  if not (V.savedSize and GetChatWindowSavedDimensions(1)) then f:SetWidth(width); f:SetHeight(170) end
end

-- Forever's window defaults (floatingchatframe.lua:9-31: black 0.25; CHAT_FRAME_DEFAULT_FONT_SIZE 18), applied once per
-- character so a window the player restyles afterwards stays as they left it. The client's saved values would otherwise
-- decide the panel and text size (a character that once set the panel to 0 shows no panel at all).
local function FirstRunDefaults()
  local db = AztraForeverUICharDB
  if type(db) ~= "table" or db.chatDefaults == 2 then return end
  db.chatDefaults = 2 -- 2: text 14 (video3: 23 px line pitch, 52 characters in 464 px), re-applied once over the earlier 18
  for i = 1, V.windows do
    local chat = _G["ChatFrame" .. i]
    FCF_SetWindowColor(chat, 0, 0, 0)
    FCF_SetWindowAlpha(chat, 0) -- Mat's capture: no panel at rest, 0.25 only under the mouse (video-notes/chat.md)
    if IS_243 then FCF_SetChatWindowFontSize(chat, 14) else FCF_SetChatWindowFontSize(nil, chat, 14) end
  end
end

AFUI.RegisterModule("Chat", { OnLogin = function()
  Place()
  FirstRunDefaults()
  for _, n in ipairs({ "UIParent_ManageFramePositions", "FCF_UpdateDockPosition" }) do
    if _G[n] then hooksecurefunc(n, Place) end
  end
  AFUI.ChatApplyFade()
end })

-- 2.5.3: each window's input drops the silver metal frame for Forever's bronze search border (WinKit.chatEdit); runs at login, when the kit exists,
-- and for windows made later (whispers).
local function BronzeEdit(chat)
  local K = AFUI.WinKit
  local eb = chat and _G[chat:GetName() .. "EditBox"]
  if K and K.chatEdit and eb then K.chatEdit(eb) end
end
if not V.oldArt then
  AFUI.RegisterModule("ChatEditBronze", { OnLogin = function()
    for i = 1, V.windows do BronzeEdit(_G["ChatFrame" .. i]) end
    if V.newWindow then hooksecurefunc(V.newWindow, BronzeEdit) end
  end })
end
