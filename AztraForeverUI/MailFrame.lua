-- Forever's mail windows over Blizzard's own MailFrame (Inbox / Send Mail tabs) and OpenMailFrame (NpcKit.lua): metal portrait frames, a title of our own that follows the tab, and a layout
-- of our own for every page, 384 x 470 each, in sections that never overlap (M.LAYOUT is the one table: the code places from it, the specs check it):
--   Inbox     summary line | list plate with the 7 rows (icon, sender, subject, money / C.O.D., days left, count) | page buttons | Open All, Collect All, Take Gold | C.O.D. check
--   Send Mail To box + Recent | Subject | body in a dark plate (light ink; the stationery art is hidden) | the real number of attachment slots (one row up to 8) + postage | Send Money / C.O.D. radios, "Amount to send", thin Gold/Silver/Copper boxes | footer: You have <money>, Send / Cancel
--   Letter    From + Report Spam | Subject | body plate | 16 attachment slots | money / C.O.D. | Reply, Delete / Return, Take All, Close
-- Blizzard's frames, buttons and scripts stay: they are re-anchored and re-skinned, never rebuilt; MailTools.lua adds the helper buttons and what the rows show.
-- Client facts (Gethe/wow-ui-source 2.5.3 Interface/FrameXML/MailFrame.xml, ButtonFrameTemplate frames): MailFrame (children InboxFrame and SendMailFrame), MailFrameTab1/2, MailItem1..7,
-- InboxPrev/NextPageButton, OpenAllMail, SendMailNameEditBox / SubjectEditBox, SendMailScrollFrame, SendMailAttachment1..12, SendMailMoney (+ SendMailSendMoneyButton / CODButton),
-- SendMailMailButton / CancelButton, OpenMailFrame (anchored to the Inbox's right edge), OpenMailScrollFrame, OpenMailAttachmentButton1..16, Reply / Delete / Cancel / ReportSpam.
AFUI = AFUI or {}
local M = {}
AFUI.MailFrame = M

local ICON = "Interface\\Icons\\INV_Misc_Note_01"
M.ROWS = 7
M.W, M.H = 384, 470
M.SPEC = {
  frame = "MailFrame", close = "MailFrameCloseButton", move = "mail", icon = ICON,
  size = { w = M.W, h = M.H, cut = 0 },
  hide = { "SendMailMoneyInset", "SendMailMoneyBg" },
  bare = { "InboxFrame", "SendMailFrame" },
  tabs = { "MailFrameTab1", "MailFrameTab2" },
  buttons = { "OpenAllMail", "SendMailMailButton", "SendMailCancelButton" },
  edits = { "SendMailNameEditBox", "SendMailSubjectEditBox", "SendMailMoneyGold", "SendMailMoneySilver", "SendMailMoneyCopper" }, -- one thin box art (NpcKit.Edit)
  checks = { "SendMailSendMoneyButton", "SendMailCODButton" },
  scrolls = { { "SendMailScrollFrameScrollBar", 4 } },
}
M.OPEN = {
  frame = "OpenMailFrame", title = "OpenMailTitleText", close = "OpenMailFrameCloseButton", move = "openmail", icon = ICON,
  size = { w = M.W, h = M.H, cut = 0 },
  buttons = { "OpenMailReplyButton", "OpenMailDeleteButton", "OpenMailCancelButton", "OpenMailReportSpamButton" },
  scrolls = { { "OpenMailScrollFrameScrollBar", 4 } },
}
M.OLD_TITLES = { "InboxTitleText", "SendMailTitleText" } -- the client's own, drawn under the metal frame (they belong to the page frames)
-- paper of the client's stationery and its scroll bar: hidden, the body sits in a dark plate of ours
M.PAPER = { "SendScrollBarBackgroundTop", "SendScrollBarBackgroundBottom", "OpenScrollBarBackgroundTop", "OpenScrollBarBackgroundBottom",
  "SendStationeryBackgroundLeft", "SendStationeryBackgroundRight", "OpenStationeryBackgroundLeft", "OpenStationeryBackgroundRight", "SendMailHorizontalBarLeft", "SendMailHorizontalBarRight",
  "OpenMailHorizontalBarLeft", "OpenMailHorizontalBarRight", "InboxFrameBg", "SendMailFrameBg" }

-- The window title for the page showing (pure): the Send Mail page (or none showing = Inbox).
function M.TitleFor(sendShown)
  if sendShown then return _G.SENDMAIL or "Send Mail" end
  return _G.INBOX or "Inbox"
end

function M.Rows()
  local out = {}
  for i = 1, M.ROWS do out[i] = "MailItem" .. i end
  return out
end

---------------------------------------------------------------- layout
-- { name, x, y, w, h }: offsets (y down) from the top left of the page frame. A name starting with "plate:" is a dark panel of ours; "~" = the client sizes it (anchor only).
local function grid(prefix, n, cols, x0, y0, pitch, size, pitchY)
  local out = {}
  for i = 1, n do out[i] = { prefix .. i, x0 + ((i - 1) % cols) * pitch, y0 + math.floor((i - 1) / cols) * (pitchY or pitch), size, size } end
  return out
end
local function cat(...)
  local out = {}
  for _, l in ipairs({ ... }) do for _, v in ipairs(l) do out[#out + 1] = v end end
  return out
end
local function rows()
  local out = {}
  for i = 1, M.ROWS do out[i] = { "MailItem" .. i, 14, 60 + (i - 1) * 44, 356, 44 } end
  return out
end
-- The Send page is computed from ONE table (M.SEND, rows top to bottom, y = offsets from the top of the page) and the REAL number of attachment slots of the client (ATTACHMENTS_MAX_SEND, read when
-- the layout is built: 7 on the 2.5.3 client, 12 on others): n <= 8 slots sit in ONE row, more in two rows, left aligned under "Attachments". The money block (radios, "Amount to send", the three
-- thin boxes with their coins) has no plate of its own (the empty framed box of the old layout was the plate of the money block: the client's controls did not show on it); the footer strip carries
-- "You have <your money>" on the left and Send / Cancel on the right, on one baseline.
M.SEND = {
  boxH = 18, toY = 36, subjectY = 66, bodyY = 94, labelH = 14, slot = 37, slotGap = 7, slotRowMax = 8, x0 = 10,
  moneyY = 352, -- top of the radio row; "Amount to send" and the boxes sit below it
  footY = 428, footH = 38, btnY = 434,
}
function M.SlotCount()
  local n = tonumber(_G.ATTACHMENTS_MAX_SEND)
  if not n then n = 0; while _G["SendMailAttachment" .. (n + 1)] do n = n + 1 end end
  return math.max(1, math.min(16, math.floor(n > 0 and n or 12)))
end
function M.SlotGrid(n) local cols = n <= M.SEND.slotRowMax and n or math.ceil(n / 2); return cols, math.ceil(n / cols) end -- columns, rows
function M.BuildSend(n)
  local S = M.SEND
  local cols, rows = M.SlotGrid(n)
  local pitch = S.slot + S.slotGap
  local slotsTop = S.moneyY - 10 - (rows * S.slot + (rows - 1) * S.slotGap)
  local labelY = slotsTop - S.labelH - 4
  local bodyH = labelY - 6 - S.bodyY
  local mY = S.moneyY
  return cat({
    { "AFUI_MailToLabel", 62, S.toY + 1, 44, 16 }, { "SendMailNameEditBox", 112, S.toY, 192, S.boxH }, { "AFUI_MailRecent", 310, S.toY - 2, 64, 22 },
    { "AFUI_MailSubjectLabel", 62, S.subjectY + 1, 48, 16 }, { "SendMailSubjectEditBox", 112, S.subjectY, 258, S.boxH },
    { "plate:AFUI_MailBodyPlate", 10, S.bodyY, 364, bodyH }, { "SendMailScrollFrame", 16, S.bodyY + 5, 322, bodyH - 10 },
    { "AFUI_MailAttachLabel", S.x0, labelY, 150, S.labelH }, -- the label row: Attachments left, Postage right (never over the slots)
  }, grid("SendMailAttachment", n, cols, S.x0, slotsTop, pitch, S.slot, pitch), {
    { "AFUI_MailPostageLabel", 180, labelY, 80, S.labelH, "RIGHT" }, { "~SendMailCostMoneyFrame", 266, labelY, 98, S.labelH },
    { "SendMailSendMoneyButton", 12, mY, 20, 20 }, { "SendMailCODButton", 152, mY, 20, 20 },
    { "AFUI_MailAmountLabel", S.x0 + 2, mY + 26, 200, S.labelH },
    { "SendMailMoneyGold", 14, mY + 44, 58, S.boxH }, { "SendMailMoneySilver", 90, mY + 44, 36, S.boxH }, { "SendMailMoneyCopper", 144, mY + 44, 36, S.boxH },
    { "plate:AFUI_MailFooter", 4, S.footY, 376, S.footH },
    { "AFUI_MailYouHave", 14, S.btnY + 6, 46, S.labelH }, { "AFUI_MailMyMoney", 62, S.btnY + 4, 148, 17 },
    { "SendMailMailButton", 214, S.btnY, 80, 26 }, { "SendMailCancelButton", 298, S.btnY, 76, 26 },
  })
end
M.slots = M.SlotCount()
M.LAYOUT = {
  inbox = cat({
    { "AFUI_MailSummary", 66, 34, 308, 18 },
    { "plate:AFUI_MailListPlate", 10, 56, 364, 316 },
  }, rows(), {
    { "InboxPrevPageButton", 10, 378, 28, 28 }, { "InboxCurrentPage", 44, 382, 296, 20 }, { "InboxNextPageButton", 346, 378, 28, 28 },
    { "OpenAllMail", 10, 412, 112, 26 }, { "AFUI_MailCollectAll", 126, 412, 120, 26 }, { "AFUI_MailTakeGold", 250, 412, 124, 26 },
    { "AFUI_MailSkipCOD", 10, 444, 20, 20 },
  }),
  send = M.BuildSend(M.SlotCount()),
  open = cat({
    { "OpenMailSenderLabel", 62, 38, 44, 16 }, { "~OpenMailSender", 112, 36, 150, 18 }, { "OpenMailReportSpamButton", 268, 34, 106, 22 },
    { "OpenMailSubjectLabel", 62, 62, 48, 16 }, { "OpenMailSubject", 112, 62, 262, 18 },
    { "plate:AFUI_OpenBodyPlate", 10, 88, 364, 170 }, { "OpenMailScrollFrame", 16, 93, 322, 160 },
    { "OpenMailAttachmentText", 10, 264, 150, 14 },
  }, grid("OpenMailAttachmentButton", 16, 8, 10, 282, 41, 37), {
    { "~OpenMailMoneyButton", 10, 368, 160, 30 }, { "~OpenMailMoney", 200, 368, 174, 30 },
    { "OpenMailReplyButton", 10, 434, 84, 26 }, { "OpenMailDeleteButton", 98, 434, 84, 26 }, { "AFUI_OpenMailTakeAll", 186, 434, 96, 26 }, { "OpenMailCancelButton", 290, 434, 84, 26 },
  }),
}
-- the invoice of an auction letter takes the body's place (same rectangle, shown instead of the text)
M.INVOICE = { "OpenMailInvoiceFrame", 16, 93, 342, 160 }

local function place(f, host, r, keepSize)
  f:ClearAllPoints(); f:SetPoint("TOPLEFT", host, "TOPLEFT", r[2], -r[3])
  if not keepSize then f:SetWidth(r[4]); f:SetHeight(r[5]) end
  if r[6] and f.SetJustifyH then f:SetJustifyH(r[6]) end
end
M.labels = {} -- layout name -> the FontString that carries it: the client's own (reused) or ours

local plates = {}
local function plate(host, name, r)
  local p = plates[name]
  if not p then
    p = CreateFrame("Frame", name, host)
    p:SetFrameLevel(host:GetFrameLevel()); p.afOwn = true
    if name == "AFUI_MailFooter" then -- the grey strip under the content (the bank's footer): flat, no rim
      local t = p:CreateTexture(nil, "BACKGROUND"); t.afOwn = true; t:SetAllPoints(p); AFUI.SetColor(t, 0.1, 0.1, 0.11, 0.55)
    elseif AFUI.WinKit and AFUI.WinKit.panel then AFUI.WinKit.panel(p) end
    plates[name] = p
  end
  place(p, host, r)
  return p
end

-- The money input frame of the client wraps the three boxes: it sits behind them (kept, never swept), the boxes carry their own coins to their right.
local COIN_W = 13
local function moneyBlock(host)
  local gold, wrap = _G.SendMailMoneyGold, _G.SendMailMoney
  if not gold then return end
  local left, top
  for _, r in ipairs(M.LAYOUT.send) do if r[1] == "SendMailMoneyGold" then left, top = r[2], r[3] end end
  if wrap and wrap.SetPoint and left then wrap:ClearAllPoints(); wrap:SetPoint("TOPLEFT", host, "TOPLEFT", left, -top); wrap:SetWidth(166); wrap:SetHeight(M.SEND.boxH) end
  for _, k in ipairs({ "Gold", "Silver", "Copper" }) do -- the coin of a box (a Money texture of the box): right of it, one line
    local box = _G["SendMailMoney" .. k]
    for _, r in ipairs(box and { box:GetRegions() } or {}) do
      local p = r.GetObjectType and r:GetObjectType() == "Texture" and not r.afOwn and r.GetTexture and r:GetTexture()
      if type(p) == "string" and p:lower():find("money") then
        r:ClearAllPoints(); r:SetPoint("LEFT", box, "RIGHT", 4, 0); r:SetWidth(COIN_W); r:SetHeight(COIN_W); r:SetAlpha(1); r:Show()
      end
    end
  end
end

-- Places every entry of one page's layout.
function M.Apply(page, host)
  host = host or (page == "inbox" and _G.InboxFrame) or (page == "send" and _G.SendMailFrame) or _G.OpenMailFrame
  if not host then return end
  if page == "send" then -- the client's slot count decides the grid
    local n = M.SlotCount()
    if n ~= M.slots then M.slots = n; M.LAYOUT.send = M.BuildSend(n) end
  end
  for _, r in ipairs(M.LAYOUT[page]) do
    local name = r[1]
    if name:sub(1, 6) == "plate:" then plate(host, name:sub(7), r)
    else
      local keep = name:sub(1, 1) == "~"
      local f = M.labels[name] or _G[keep and name:sub(2) or name]
      if f then place(f, host, r, keep) end
    end
  end
  if page == "send" then
    moneyBlock(host)
    local N = AFUI.NpcKit
    for i = 1, M.slots do local b = _G["SendMailAttachment" .. i]; if b and N then N.Slot(b); N.SlotUpdate(b) end end
  elseif page == "open" then
    local N = AFUI.NpcKit
    for i = 1, 16 do local b = _G["OpenMailAttachmentButton" .. i]; if b and N then N.Slot(b); N.SlotUpdate(b) end end
  end
end

-- The attachment grids come back to the client's own positions with every update of the letter: ours again.
function M.ApplyOpen()
  if not _G.OpenMailFrame then return end
  M.Apply("open", OpenMailFrame)
  local inv = _G[M.INVOICE[1]]
  if inv then place(inv, OpenMailFrame, M.INVOICE) end
end

-- Light ink on the dark plates (the client's body text is black for its paper).
local function lightInk(t)
  if not t then return end
  if t.SetTextColor and not pcall(t.SetTextColor, t, 0.9, 0.9, 0.85) then pcall(t.SetTextColor, t, "P", 0.9, 0.9, 0.85) end
end

-- Every FontString the client draws straight on a page (static labels in places that no longer exist) goes; `keep` lists the names that stay.
-- (now structural: M.Sweep below hides every region and child frame of a page that is not on its allow-list, whatever the client calls it)

-- The names a page's layout places (allow-list of the sweep).
local function names(page)
  local out = {}
  for _, r in ipairs(M.LAYOUT[page]) do local n = r[1]:gsub("^plate:", ""):gsub("^~", ""); out[n] = true end
  return out
end

-- Hides what is not ours on one page ("inbox" / "send" / "open"): FontStrings and textures of the page frame, child frames that are not controls we place, stray sliders (a scroll frame's
-- own bar is restyled by WinKit.scroll). Returns the report rows (see /afui mailreport).
function M.Sweep(page)
  local N = AFUI.NpcKit
  if not (N and N.Sweep) then return end
  if page == "inbox" then
    local keep = names("inbox"); keep.InboxTooMuchMail = true
    return N.Sweep(_G.InboxFrame, { keep = keep, keepText = { InboxCurrentPage = true, InboxTooMuchMail = true }, textures = true })
  elseif page == "send" then
    local keep = names("send"); keep.SendMailMoney = true -- the client's money input frame: the three boxes (placed by name) live in it
    local words = M.LabelWords() -- an edit box keeps every FontString but the duplicate labels (the box's own text is no region, and nothing else of it is ours to hide)
    local o = N.Sweep(_G.SendMailFrame, { keep = keep, textures = true, scrollX = 4, scrolls = { SendMailScrollFrame = true },
      fontsIn = { SendMailNameEditBox = words, SendMailSubjectEditBox = words, SendMailScrollFrame = true, SendMailMoney = true } })
    M.Dedupe(_G.SendMailFrame)
    return o
  end -- the letter's window frame carries our chrome: only its labels and its scroll frame are swept
  return N.Sweep(_G.OpenMailFrame, { keepText = names("open"), children = false, scrollX = 4, scrolls = { OpenMailScrollFrame = true } })
end

-- The labels of the Send page: the client's own FontStrings are reused (found by their text, the localized globals, or by sitting on the box they label) and re-anchored; ours are only
-- created for what the client does not have. Never both.
local function norm(s) return (tostring(s or ""):lower():gsub("[%s:]+$", "")) end
M.LABELS = {
  { "AFUI_MailToLabel", "To:", { "TO", "SEND_MAIL_TO" }, "SendMailNameEditBox" },
  { "AFUI_MailSubjectLabel", "Subject:", { "SUBJECT", "SUBJECT_COLON", "SEND_MAIL_SUBJECT" }, "SendMailSubjectEditBox" },
  { "AFUI_MailPostageLabel", "Postage:", { "POSTAGE", "SEND_MAIL_COST", "SENDMAIL_COST" }, "SendMailCostMoneyFrame" },
}
local function wanted(l)
  local set = { [norm(l[2])] = true }
  for _, g in ipairs(l[3]) do if type(_G[g]) == "string" then set[norm(_G[g])] = true end end
  return set
end
-- The texts of the three labels (normalized), as one set.
function M.LabelWords()
  local out = {}
  for _, l in ipairs(M.LABELS) do for k in pairs(wanted(l)) do out[k] = true end end
  return out
end
-- A second copy of a label anywhere under the page (the real client draws "Postage:" a second time inside the postage money frame, a few px off): every FontString with a label's text
-- that is not the one in use goes, whatever frame it lives in (down to 3 levels). Texts that are not one of the three labels are never touched.
function M.Dedupe(page)
  if not page then return end
  local words = M.LabelWords()
  local function walk(f, depth)
    for _, r in ipairs(f.GetRegions and { f:GetRegions() } or {}) do
      if r.GetObjectType and r:GetObjectType() == "FontString" and not (r.afOwn or r.afLabel) and words[norm(r.GetText and r:GetText())] then
        if r.SetAlpha then r:SetAlpha(0) end; if r.Hide then r:Hide() end
      end
    end
    if depth < 3 then for _, c in ipairs(f.GetChildren and { f:GetChildren() } or {}) do if not c.afOwn then walk(c, depth + 1) end end end
  end
  walk(page, 0)
end
function M.Labels(send)
  local cands = {}
  local function collect(f)
    if not (f and f.GetRegions) then return end
    for _, r in ipairs({ f:GetRegions() }) do
      if r.GetObjectType and r:GetObjectType() == "FontString" and not r.afOwn then cands[#cands + 1] = r end
    end
  end
  collect(send)
  for _, n in ipairs({ "SendMailNameEditBox", "SendMailSubjectEditBox", "SendMailScrollFrame" }) do collect(_G[n]) end
  for _, l in ipairs(M.LABELS) do
    local name = l[1]
    if not M.labels[name] then
      local set, found = wanted(l), nil
      for _, r in ipairs(cands) do
        if not r.afLabel and set[norm(r.GetText and r:GetText())] then found = r; break end
      end
      if not found then -- no text match: the FontString anchored to the control it labels (and not another label's text)
        local box = _G[l[4]]
        for _, r in ipairs(cands) do
          local _, rel = r.GetPoint and r:GetPoint(1)
          local t = norm(r.GetText and r:GetText())
          if not r.afLabel and box and rel == box and t ~= "" and not (wanted(M.LABELS[1])[t] or wanted(M.LABELS[2])[t] or wanted(M.LABELS[3])[t]) then found = r; break end
        end
      end
      if found then found.afLabel = true; M.labels[name] = found
      elseif AFUI.MailTools and not _G[name] then
        M.labels[name] = AFUI.MailTools.label(send, name, l[2], name == "AFUI_MailAttachLabel" and "GameFontNormalSmall" or "GameFontNormal")
      end
    end
  end
  if AFUI.MailTools then
    for _, l in ipairs({ { "AFUI_MailAttachLabel", "Attachments" }, { "AFUI_MailAmountLabel", "Amount to send" }, { "AFUI_MailYouHave", "You have" } }) do
      if not _G[l[1]] then AFUI.MailTools.label(send, l[1], l[2], "GameFontNormalSmall") end
    end
  end
  M.UpdateAmount()
end

-- "Amount to send" (money) or "C.O.D. amount" (the C.O.D. radio is on).
function M.UpdateAmount()
  local t, cod = _G.AFUI_MailAmountLabel, _G.SendMailCODButton
  if t and t.SetText then t:SetText((cod and cod.GetChecked and cod:GetChecked()) and "C.O.D. amount" or "Amount to send") end
end

local function hideNames(list)
  for _, n in ipairs(list) do local t = _G[n]; if t and t.SetAlpha then t:SetAlpha(0); if t.Hide then t:Hide() end end end
end

local function skinInbox()
  local inbox = _G.InboxFrame
  if not inbox then return end
  M.Sweep("inbox")
  if _G.InboxTooMuchMail then InboxTooMuchMail:SetAlpha(0) end
  AFUI.NpcKit.Bare(M.Rows())
  for i, n in ipairs(M.Rows()) do
    AFUI.NpcKit.Strip(n)
    if AFUI.MailTools then AFUI.MailTools.LayoutRow(i) end
  end
  for _, n in ipairs({ "InboxPrevPageButton", "InboxNextPageButton" }) do local b = _G[n]; if b and AFUI.WinKit and AFUI.WinKit.row then AFUI.WinKit.row(b) end end
  if _G.InboxCurrentPage and InboxCurrentPage.SetJustifyH then InboxCurrentPage:SetJustifyH("CENTER") end
  M.Apply("inbox", inbox)
end

local function skinSend()
  local send = _G.SendMailFrame
  if not send then return end
  M.Labels(send)
  M.Apply("send", send) -- the layout first: a bar the sweep restyles reads the final size of its list
  M.Sweep("send")
  local scroll = _G.SendMailScrollFrame
  if scroll then
    if _G.SendMailScrollChildFrame then SendMailScrollChildFrame:SetWidth(322) end
    if _G.SendMailBodyEditBox then SendMailBodyEditBox:SetWidth(316); lightInk(SendMailBodyEditBox) end
  end
  for _, n in ipairs({ "SendMailSendMoneyButton", "SendMailCODButton" }) do -- the radio dots are the client's, its labels read on the dark plate
    local t = _G[n .. "Text"]; if t and t.SetFontObject then t:SetFontObject(GameFontHighlightSmall) end
  end
end

-- The client re-anchors and re-shows pieces of its pages when attachments change, the tab flips or the window opens: the sweep and the layout go back on after those calls.
function M.Relayout()
  if not M.done then return end
  if _G.SendMailFrame then M.Labels(SendMailFrame); M.Apply("send", SendMailFrame); M.Sweep("send") end
  if _G.InboxFrame and InboxFrame:IsShown() then M.Apply("inbox", InboxFrame); M.Sweep("inbox") end
end
local function hookClient()
  if M.hooked then return end
  M.hooked = true
  for _, fn in ipairs({ "SendMailFrame_Update", "SendMailAttachment_OnClick", "SendMailRadioButton_OnClick", "MailFrameTab_OnClick", "MailFrame_Show" }) do
    if type(_G[fn]) == "function" then hooksecurefunc(fn, M.Relayout) end
  end
  for _, n in ipairs({ "InboxFrame", "SendMailFrame" }) do local p = _G[n]; if p then p:HookScript("OnShow", M.Relayout) end end
end

local function skinOpen()
  local open = _G.OpenMailFrame
  if not open then return end
  M.ApplyOpen()
  M.Sweep("open")
  for _, n in ipairs({ "OpenMailSenderLabel", "OpenMailSubjectLabel", "OpenMailAttachmentText", "OpenMailSubject" }) do local t = _G[n]; if t and t.SetJustifyH then t:SetJustifyH("LEFT") end end
  lightInk(_G.OpenMailBodyText)
  if _G.OpenMailScrollChildFrame then OpenMailScrollChildFrame:SetWidth(322) end
  if _G.OpenMailBodyText and OpenMailBodyText.SetWidth then OpenMailBodyText:SetWidth(310) end
  if type(_G.OpenMailFrame_UpdateButtonPositions) == "function" then hooksecurefunc("OpenMailFrame_UpdateButtonPositions", M.ApplyOpen) end
  if type(_G.OpenMail_Update) == "function" then hooksecurefunc("OpenMail_Update", M.ApplyOpen) end
  open:HookScript("OnShow", function() M.ApplyOpen(); M.Sweep("open") end)
end

local function skinMain(f)
  for _, n in ipairs(M.OLD_TITLES) do local t = _G[n]; if t and t.SetAlpha then t:SetAlpha(0) end end
  hideNames(M.PAPER)
  AFUI.NpcKit.Title(f, function() return M.TitleFor(_G.SendMailFrame and SendMailFrame:IsShown()) end)
  for _, n in ipairs({ "InboxFrame", "SendMailFrame" }) do
    local p = _G[n]
    if p then p:HookScript("OnShow", f.afRetitle); p:HookScript("OnHide", f.afRetitle) end
  end
  if AFUI.MailTools then AFUI.MailTools.Setup() end
  skinInbox(); skinSend()
  hookClient()
end

function M.Enabled() return AFUI.ModuleEnabled("mail") end -- Settings > Windows (useMail; the old mailRestyle setting still counts)

function M.Setup()
  if M.done or not M.Enabled() or not _G.MailFrame then return end
  M.done = true
  AFUI.RunOutOfCombat(function()
    M.SPEC.before = skinMain
    M.SPEC.after = function() M.Apply("inbox"); M.Apply("send") end -- WinKit.button sets its own height: the sizes of our layout go back on
    AFUI.NpcKit.Skin(M.SPEC)
    M.OPEN.before = function() hideNames(M.PAPER); skinOpen() end
    M.OPEN.after = M.ApplyOpen
    AFUI.NpcKit.Skin(M.OPEN)
  end)
end

-- /afui mailreport: what the sweep hid / kept / reused on each mail page, one line per thing (paste it when a mail window looks wrong on a real client).
function M.Report()
  local lines = AFUI.NpcKit.ReportLines({ "InboxFrame", "SendMailFrame", "OpenMailFrame" })
  for n, l in pairs(M.labels) do lines[#lines + 1] = "label " .. n .. ": " .. ((l.afOwn and "created by us") or "the client's own, reused") end
  if AFUI.Print then for _, l in ipairs(lines) do AFUI.Print(l) end end
  return lines
end
if AFUI.Slash and AFUI.Slash.Register then
  AFUI.Slash.Register("mailreport", M.Report, "what the mail skin hid, kept or reused (paste it when a mail window looks wrong)", "/afui mailreport")
end

AFUI.RegisterModule("MailFrame", { OnLogin = M.Setup })
