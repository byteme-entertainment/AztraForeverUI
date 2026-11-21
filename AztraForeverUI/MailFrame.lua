-- Forever's mail windows over Blizzard's own MailFrame (Inbox / Send Mail tabs) and OpenMailFrame (NpcKit.lua): metal portrait frames, a title of our own that follows the tab,
-- dark plates behind the 7 inbox rows, red Open All / Send / Cancel / Reply / Delete buttons, search-box art on the To / Subject boxes, minimal scroll bars. The letter's parchment
-- (stationery behind the body of a mail you write or open) stays: its text is dark ink made for it. Attachments, money, COD, the stationery and every script stay the client's.
-- Client facts (Gethe/wow-ui-source 2.5.3 Interface/FrameXML/MailFrame.xml, ButtonFrameTemplate frames): MailFrame (children InboxFrame and SendMailFrame, each 384 x 512 with widgets down to
-- 92 px above the bottom), MailFrameTab1/2, MailItem1..7 (305 x 45), InboxPrev/NextPageButton, OpenAllMail 120 x 24, SendMailNameEditBox / SubjectEditBox, SendMailScrollFrame, SendMailMailButton /
-- CancelButton, SendMailMoneyInset / Bg, OpenMailFrame (anchored to the Inbox's right edge), OpenMailScrollFrame, OpenMailReplyButton / DeleteButton / CancelButton / ReportSpamButton.
AFUI = AFUI or {}
local M = {}
AFUI.MailFrame = M

local ICON = "Interface\\Icons\\INV_Misc_Note_01"
M.ROWS = 7
M.SPEC = {
  frame = "MailFrame", close = "MailFrameCloseButton", move = "mail", icon = ICON,
  size = { w = 384, h = 512, cut = 84 },
  hide = { "SendMailMoneyInset", "SendMailMoneyBg" },
  bare = { "InboxFrame", "SendMailFrame" },
  tabs = { "MailFrameTab1", "MailFrameTab2" },
  buttons = { "OpenAllMail", "SendMailMailButton", "SendMailCancelButton" },
  edits = { "SendMailNameEditBox", "SendMailSubjectEditBox" },
  scrolls = { "SendMailScrollFrameScrollBar" },
}
M.OPEN = {
  frame = "OpenMailFrame", title = "OpenMailTitleText", close = "OpenMailFrameCloseButton", move = "openmail", icon = ICON,
  size = { w = 384, h = 512, cut = 0 },
  buttons = { "OpenMailReplyButton", "OpenMailDeleteButton", "OpenMailCancelButton", "OpenMailReportSpamButton" },
  scrolls = { "OpenMailScrollFrameScrollBar" },
}
M.OLD_TITLES = { "InboxTitleText", "SendMailTitleText" } -- the client's own, drawn under the metal frame (they belong to the page frames)
M.PAPER_EDGES = { "SendScrollBarBackgroundTop", "OpenScrollBarBackgroundTop" } -- the old scroll bar's paper edge; the minimal bar replaces it

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

-- The attachment slot art of each inbox row comes back with every update: kept at alpha 0.
function M.UpdateRows()
  for i = 1, M.ROWS do
    local slot = _G["MailItem" .. i .. "ButtonSlot"]
    if slot and slot.SetAlpha then slot:SetAlpha(0) end
  end
end

local function skinMain(f)
  for _, n in ipairs(M.OLD_TITLES) do local t = _G[n]; if t and t.SetAlpha then t:SetAlpha(0) end end
  for _, n in ipairs(M.PAPER_EDGES) do local t = _G[n]; if t and t.Hide then t:Hide() end end
  AFUI.NpcKit.Title(f, function() return M.TitleFor(_G.SendMailFrame and SendMailFrame:IsShown()) end)
  for _, n in ipairs({ "InboxFrame", "SendMailFrame" }) do
    local p = _G[n]
    if p then p:HookScript("OnShow", f.afRetitle); p:HookScript("OnHide", f.afRetitle) end
  end
  AFUI.NpcKit.Bare(M.Rows())
  local inbox = _G.InboxFrame
  for _, n in ipairs(M.Rows()) do
    local row = _G[n]
    if row and inbox then AFUI.NpcKit.Plate(inbox, row, -1, -1, -1, -1) end
  end
  if type(_G.InboxFrame_Update) == "function" then hooksecurefunc("InboxFrame_Update", M.UpdateRows) end
  M.UpdateRows()
end

function M.Enabled() return AFUI.GetSetting("mailRestyle", false) and true or false end -- off by default: testers found the beta skin rough

function M.Setup()
  if M.done or not M.Enabled() or not _G.MailFrame then return end
  M.done = true
  AFUI.RunOutOfCombat(function()
    M.SPEC.after = skinMain
    AFUI.NpcKit.Skin(M.SPEC)
    AFUI.NpcKit.Skin(M.OPEN)
  end)
end

if AFUI.Settings and AFUI.Settings.Register then
  AFUI.Settings.Register{ category = "general", key = "mailRestyle", type = "check", default = false, label = "Forever mailbox window (beta)",
    tooltip = "Draws the mailbox in the Forever look. Still rough, so it is off by default and the client's own mailbox stays untouched. Takes effect after /reload." }
end
AFUI.RegisterModule("MailFrame", { OnLogin = M.Setup })
