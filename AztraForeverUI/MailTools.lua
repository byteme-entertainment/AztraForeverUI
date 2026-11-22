-- Mailbox helpers (MailFrame.lua lays the windows out; this file is what they show and do): the inbox rows' badges (money / C.O.D., item count, days left coloured and read / unread),
-- the summary line (mails, gold waiting, mailbox full), Collect All / Take Gold (one step at a time, never in combat, C.O.D. mails skipped and listed, stops on full bags), the recent
-- recipients list of the Send Mail page (15 names per account, plus your own characters), a confirmation before Return. Every call into the client's mail API happens from a click;
-- nothing here replaces a client function (hooksecurefunc / HookScript only, plus the Return button's own click script wrapped, never a protected frame).
AFUI = AFUI or {}
local M = {}
AFUI.MailTools = M

M.PER_PAGE, M.MAX_ATTACH, M.FULL, M.RECENT_MAX, M.TIMEOUT, M.GAP = 7, 16, 50, 15, 1.5, 0.15
M.SETTINGS = { -- key, label, tooltip, default
  { "mailSummary", "Summary line", "Shows how many letters wait, the gold in them, and a warning when the mailbox is full (50 letters).", true },
  { "mailRowDetails", "Letter details in the list", "Each letter shows its money or C.O.D., the number of attachments and its days left (red under 3 days); letters you read are dimmed.", true },
  { "mailCollectButtons", "Collect All / Take Gold buttons", "Two buttons under the list: Collect All takes the money and every attachment of every letter, one at a time; Take Gold takes only the money. Stops when your bags are full.", true },
  { "mailSkipCOD", "Skip C.O.D. letters when collecting", "Collect All never pays a C.O.D. for you. On: those letters are skipped and listed in chat. Off: collecting stops at the first one so you can decide.", true },
  { "mailRecents", "Recent recipients list", "A Recent button next to the To box lists the last 15 names you sent mail to and the characters of yours this addon has seen.", true },
  { "mailConfirmReturn", "Confirm before Return", "Asks before a letter with attachments or money is sent back to its sender.", true },
}
local DEFAULT = {}
for _, s in ipairs(M.SETTINGS) do DEFAULT[s[1]] = s[4] end
function M.On(key)
  local v = AFUI.GetSetting and AFUI.GetSetting(key, DEFAULT[key])
  if v == nil then return DEFAULT[key] end
  return v and true or false
end

---------------------------------------------------------------- pure helpers
-- "12g 5s 7c" with the letters in the money colours; zero parts left out; 0 = "0c".
function M.Coin(copper)
  copper = math.floor(tonumber(copper) or 0)
  if copper <= 0 then return "0|cffeda55fc|r" end
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "|cffffd700g|r" end
  if s > 0 then out[#out + 1] = s .. "|cffc7c7cfs|r" end
  if c > 0 then out[#out + 1] = c .. "|cffeda55fc|r" end
  return table.concat(out, " ")
end

-- Days left of a letter: the short text, and its colour (red under 3 days, amber under 7, soft white after).
function M.DaysText(days)
  days = tonumber(days) or 0
  if days >= 1 then return math.floor(days) .. "d" end
  local h = math.floor(days * 24)
  return h >= 1 and (h .. "h") or "<1h"
end
function M.DaysColor(days)
  days = tonumber(days) or 0
  if days < 3 then return 1, 0.25, 0.2 end
  if days < 7 then return 1, 0.82, 0 end
  return 0.85, 0.85, 0.85
end
function M.Exact(days)
  days = tonumber(days) or 0
  local d, h = math.floor(days), math.floor((days % 1) * 24)
  if d >= 1 then return d .. (d == 1 and " day " or " days ") .. h .. (h == 1 and " hour" or " hours") end
  local m = math.floor(((days * 24) % 1) * 60)
  return h .. (h == 1 and " hour " or " hours ") .. m .. (m == 1 and " minute" or " minutes")
end

-- Mail index of row i on an inbox page.
function M.Index(page, i) return ((page or 1) - 1) * M.PER_PAGE + i end

---------------------------------------------------------------- recipients (account-wide)
local function db()
  if type(_G.AztraForeverUIDB) ~= "table" then _G.AztraForeverUIDB = {} end
  local d = _G.AztraForeverUIDB
  d.mailRecent = type(d.mailRecent) == "table" and d.mailRecent or {}
  d.mailAlts = type(d.mailAlts) == "table" and d.mailAlts or {}
  return d
end
local function addUnique(list, name, cap)
  local low = name:lower()
  for i = #list, 1, -1 do if tostring(list[i]):lower() == low then table.remove(list, i) end end
  table.insert(list, 1, name)
  while #list > cap do table.remove(list) end
end
-- The name as the To box shows it: trimmed, a dangling realm separator ("Res-") dropped, and the realm dropped when it is the player's own (the client takes "Name" for the home realm and
-- "Name-Realm" for another one: a name with an empty or the home realm would only be cut). Pure apart from GetRealmName.
function M.CleanName(name)
  if type(name) ~= "string" then return "" end
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  local base, realm = name:match("^(.-)%-(.*)$")
  if not base then return name end
  if realm == "" then return base end
  local home = _G.GetRealmName and GetRealmName()
  if home and realm:gsub("%s", ""):lower() == home:gsub("%s", ""):lower() then return base end
  return name
end

-- Names are trimmed; empty names and the player's own name are not "recent".
function M.Remember(name)
  if type(name) ~= "string" then return false end
  name = M.CleanName(name)
  if name == "" then return false end
  local me = _G.UnitName and UnitName("player")
  if me and name:lower() == me:lower() then return false end
  addUnique(db().mailRecent, name, M.RECENT_MAX)
  return true
end
function M.RememberAlt()
  local me = _G.UnitName and UnitName("player")
  if not me or me == "" then return end
  local d = db()
  for _, n in ipairs(d.mailAlts) do if n == me then return end end
  d.mailAlts[#d.mailAlts + 1] = me
  while #d.mailAlts > M.RECENT_MAX do table.remove(d.mailAlts, 1) end
end
function M.Recents() return db().mailRecent end
function M.Alts()
  local me, out = _G.UnitName and UnitName("player"), {}
  for _, n in ipairs(db().mailAlts) do if n ~= me then out[#out + 1] = n end end
  return out
end

---------------------------------------------------------------- Collect All (state machine)
-- api = { count() = mails, header(i) = money, cod, hasItem, sender, item(i, n) = name or nil, free() = free bag slots }; run = M.NewRun(...).
-- NextAction(api, run) returns one of { "money", i } { "item", i, n } { "stop", reason } { "done" }; it counts every attempt (a mail can be tried twice) so a stuck
-- client cannot loop it. The driver waits for the client's MAIL_INBOX_UPDATE (or M.TIMEOUT) between steps, then asks again: nothing is queued ahead.
function M.NewRun(mode, only, skipCOD)
  return { mode = mode or "all", only = only, skipCOD = skipCOD ~= false, tries = {}, cod = {}, money = 0, items = 0, seen = {} }
end
function M.NextAction(api, run)
  local hi, lo = api.count(), 1
  if run.only then hi, lo = math.min(run.only, hi), run.only end
  for i = hi, lo, -1 do
    local money, cod, hasItem, sender = api.header(i)
    run.cur = i
    if (cod or 0) > 0 then
      if not run.seen[i] then run.seen[i] = true; run.cod[#run.cod + 1] = { sender = sender, cod = cod } end
      if not run.skipCOD then return { "stop", "cod" } end
    else
      local k = "m" .. i
      if (money or 0) > 0 and (run.tries[k] or 0) < 2 then run.tries[k] = (run.tries[k] or 0) + 1; run.pending = money; return { "money", i } end
      if run.mode == "all" and hasItem then
        for n = M.MAX_ATTACH, 1, -1 do
          local key = "i" .. i .. "_" .. n
          if api.item(i, n) and (run.tries[key] or 0) < 2 then
            if api.free() <= 0 then return { "stop", "full" } end
            run.tries[key] = (run.tries[key] or 0) + 1; return { "item", i, n }
          end
        end
      end
    end
  end
  return { "done" }
end

local function realApi()
  return {
    count = function() return (select(1, GetInboxNumItems())) or 0 end,
    header = function(i)
      local _, _, sender, _, money, cod, _, hasItem = GetInboxHeaderInfo(i)
      return money, cod, hasItem and true or false, sender
    end,
    item = function(i, n) return GetInboxItem(i, n) end,
    free = function()
      local free = 0
      for bag = 0, 4 do local f = _G.GetContainerNumFreeSlots and GetContainerNumFreeSlots(bag); if f then free = free + f end end
      return free
    end,
  }
end

local driver, run
function M.Running() return run ~= nil end
local function say(msg) if AFUI.Print then AFUI.Print("|cffffd100Mail|r: " .. msg) end end

-- The chat line that ends a run (pure).
function M.Report(r, reason)
  local parts = {}
  if r.money > 0 then parts[#parts + 1] = "took " .. M.Coin(r.money) end
  if r.items > 0 then parts[#parts + 1] = r.items .. (r.items == 1 and " item" or " items") end
  local text = #parts > 0 and table.concat(parts, ", ") or "nothing to take"
  local why = ({ full = "Bags full, stopped.", cancelled = "Cancelled.", closed = "Mailbox closed.", cod = "Stopped at a C.O.D. letter.", combat = "Stopped: combat." })[reason]
  local out = text .. (why and (" " .. why) or "")
  if #r.cod > 0 then
    local from = {}
    for _, c in ipairs(r.cod) do from[#from + 1] = (c.sender or "?") .. " (" .. M.Coin(c.cod) .. ")" end
    out = out .. " Skipped C.O.D.: " .. table.concat(from, ", ") .. "."
  end
  return out
end

local function finish(reason)
  local r = run
  run = nil
  if driver then driver:SetScript("OnUpdate", nil) end
  if r then say(M.Report(r, reason)) end
  M.Refresh()
end
M.Finish = finish

function M.Start(mode, only)
  if run or (_G.InCombatLockdown and InCombatLockdown()) then return false end
  if not (_G.MailFrame and MailFrame:IsShown()) then return false end
  run = M.NewRun(mode, only, M.On("mailSkipCOD"))
  run.api, run.wait = realApi(), 0
  driver = driver or CreateFrame("Frame")
  driver:SetScript("OnUpdate", function(_, dt) M.Step(dt) end)
  M.Refresh()
  return true
end
function M.Cancel() if run then finish("cancelled") end end

-- One driver tick (dt seconds): waits for the previous step to land, then issues the next one.
function M.Step(dt)
  if not run then return end
  if _G.InCombatLockdown and InCombatLockdown() then return finish("combat") end
  run.wait = run.wait - (dt or 0)
  if run.wait > 0 then return end
  local a = M.NextAction(run.api, run)
  if a[1] == "money" then
    run.money = run.money + (run.pending or 0); TakeInboxMoney(a[2]); run.wait = M.TIMEOUT
  elseif a[1] == "item" then
    run.items = run.items + 1; TakeInboxItem(a[2], a[3]); run.wait = M.TIMEOUT
  elseif a[1] == "stop" then return finish(a[2])
  else return finish(nil) end
  M.Refresh()
end
-- The client answered: the next step may go after a short gap.
function M.Landed() if run and run.wait > M.GAP then run.wait = M.GAP end end

---------------------------------------------------------------- what the mailbox holds
function M.Totals()
  local count, all = 0, 0
  if _G.GetInboxNumItems then count, all = GetInboxNumItems() end
  count = count or 0; all = math.max(all or count, count)
  local cod, gold = 0, 0
  for i = 1, count do
    local _, _, _, _, money, c = GetInboxHeaderInfo(i)
    if (c or 0) > 0 then cod = cod + 1 else gold = gold + (money or 0) end
  end
  return { shown = count, all = all, gold = gold, cod = cod, full = all >= M.FULL }
end

-- The two halves of the summary line (pure).
function M.SummaryText(t, running, cur)
  if running then return "Collecting... mail " .. (cur or "?") .. " of " .. t.shown, "" end
  local left = t.full and ("|cffff4040Mailbox full: " .. t.all .. " letters|r")
    or (t.all .. (t.all == 1 and " letter" or " letters") .. (t.cod > 0 and (" (" .. t.cod .. " C.O.D.)") or ""))
  return left, t.gold > 0 and ("Gold waiting: " .. M.Coin(t.gold)) or "No gold waiting"
end

---------------------------------------------------------------- rows
local function g(n) return _G[n] end

-- Where the parts of an inbox row go (row = 356 x 44, offsets from its top left): used by MailFrame.lua's layout and by the specs.
M.ROW = {
  button = { 4, 3, 37, 37 }, sender = { 48, 5, 160, 14 }, subject = { 48, 23, 180, 14 }, expire = { 262, 5, 88, 14 }, money = { 232, 23, 118, 14 },
}
local function put(f, host, r)
  if not f then return end
  f:ClearAllPoints(); f:SetPoint("TOPLEFT", host, "TOPLEFT", r[1], -r[2]); f:SetWidth(r[3]); f:SetHeight(r[4])
end
M.put = put

function M.LayoutRow(i)
  local row = g("MailItem" .. i)
  if not row then return end
  local R = M.ROW
  put(g("MailItem" .. i .. "Button"), row, R.button)
  for _, p in ipairs({ { "Sender", R.sender }, { "Subject", R.subject }, { "ExpireTime", R.expire } }) do
    local f = g("MailItem" .. i .. p[1])
    if f then
      put(f, row, p[2])
      if f.SetJustifyH then f:SetJustifyH(p[1] == "ExpireTime" and "RIGHT" or "LEFT") end
      if f.SetWordWrap then f:SetWordWrap(false) end
    end
  end
  if not row.afMoney then
    local b = g("MailItem" .. i .. "Button")
    row.afMoney = row:CreateFontString("AFUI_MailItem" .. i .. "Money", "OVERLAY", "GameFontNormalSmall")
    row.afMoney:SetJustifyH("RIGHT")
    if row.afMoney.SetWordWrap then row.afMoney:SetWordWrap(false) end
    row.afCount = (b or row):CreateFontString("AFUI_MailItem" .. i .. "Count", "OVERLAY", "NumberFontNormalSmall")
    row.afCount:SetPoint("BOTTOMRIGHT", b or row, "BOTTOMRIGHT", -2, 2)
  end
  put(row.afMoney, row, R.money)
  -- anything else the client draws on the row (its money frame) would sit on ours: ours replace it
  for _, c in ipairs({ row:GetChildren() }) do
    if c ~= g("MailItem" .. i .. "Button") and not c.afOwn and c.SetAlpha then c:SetAlpha(0) end
  end
  local cnt = g("MailItem" .. i .. "ButtonCount")
  if cnt and cnt.SetAlpha then cnt:SetAlpha(0) end
end

function M.UpdateRows()
  local details = M.On("mailRowDetails")
  local page = _G.InboxFrame and InboxFrame.pageNum or 1
  local n = _G.GetInboxNumItems and (GetInboxNumItems()) or 0
  for i = 1, M.PER_PAGE do
    local row = g("MailItem" .. i)
    if row and row.afMoney then
      local idx = M.Index(page, i)
      local slot = g("MailItem" .. i .. "ButtonSlot")
      if slot and slot.SetAlpha then slot:SetAlpha(0) end
      if details and idx <= n then
        local _, _, _, _, money, cod, days, hasItem, wasRead = GetInboxHeaderInfo(idx)
        local ex = g("MailItem" .. i .. "ExpireTime")
        if ex and ex.SetText then ex:SetText(M.DaysText(days)); ex:SetTextColor(M.DaysColor(days)) end
        row.afDays = days
        if (cod or 0) > 0 then row.afMoney:SetText("|cffff4040C.O.D.|r " .. M.Coin(cod))
        elseif (money or 0) > 0 then row.afMoney:SetText(M.Coin(money)) else row.afMoney:SetText("") end
        local count = type(hasItem) == "number" and hasItem or 0
        row.afCount:SetText(count > 1 and tostring(count) or "")
        local a = wasRead and 0.6 or 1
        for _, k in ipairs({ "Sender", "Subject" }) do local f = g("MailItem" .. i .. k); if f and f.SetAlpha then f:SetAlpha(a) end end
        local b = g("MailItem" .. i .. "Button"); if b and b.SetAlpha then b:SetAlpha(wasRead and 0.7 or 1) end
      else
        row.afDays = nil; row.afMoney:SetText(""); row.afCount:SetText("")
      end
    end
  end
end

local function hookRowTooltip(i)
  local row = g("MailItem" .. i)
  if not row or row.afTip then return end
  row.afTip = true
  row:HookScript("OnEnter", function(self)
    if not self.afDays or not M.On("mailRowDetails") then return end
    if not (GameTooltip:IsShown() and GameTooltip:IsOwned(self)) then GameTooltip:SetOwner(self, "ANCHOR_RIGHT") end
    GameTooltip:AddLine("Expires in " .. M.Exact(self.afDays), M.DaysColor(self.afDays))
    GameTooltip:Show()
  end)
end

---------------------------------------------------------------- our frames
local function button(name, parent, text, w, h, tip, onClick)
  local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
  b:SetText(text); b.afOwn = true
  if AFUI.WinKit and AFUI.WinKit.button then AFUI.WinKit.button(b, w, h) end
  b:SetWidth(w); b:SetHeight(h)
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(self.afTip or "", 1, 1, 1, 1, true); GameTooltip:Show() end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b.afTip = tip
  return b
end
M.button = button

local function label(parent, name, text, font)
  local t = parent:CreateFontString(name, "OVERLAY", font or "GameFontNormal")
  t:SetText(text); t:SetJustifyH("LEFT"); t.afOwn = true
  return t
end
M.label = label

function M.Refresh()
  local s = M.frames
  if not s then return end
  if s.summary then
    if M.On("mailSummary") then s.summary:Show() else s.summary:Hide() end
    local left, right = M.SummaryText(M.Totals(), run ~= nil, run and run.cur)
    s.summary.left:SetText(left or ""); s.summary.right:SetText(right or "")
  end
  local on = M.On("mailCollectButtons")
  for _, k in ipairs({ "collect", "gold" }) do if s[k] then if on then s[k]:Show() else s[k]:Hide() end end end
  if s.collect then
    s.collect:SetText(run and "Cancel" or "Collect All")
    if s.collect.afArt and s.collect.afArt.paint then s.collect.afArt.paint() end
    if run then s.gold:Disable() else s.gold:Enable() end
  end
  if s.take then if run then s.take:Disable() else s.take:Enable() end end
  if s.recent then if M.On("mailRecents") then s.recent:Show() else s.recent:Hide() end end
  if s.cod and s.cod.SetChecked then s.cod:SetChecked(M.On("mailSkipCOD")) end
end

-- Your own money in the footer: the bags' coin box (common-coinbox left / centre / right) with gold, silver, copper and their coins, right aligned (the bags footer, Bags.lua makeMoney).
function M.MoneyBox(parent, name)
  local box = CreateFrame("Frame", name, parent)
  box.afOwn = true; box:SetWidth(148); box:SetHeight(17)
  local function atlas(a, size) local t = box:CreateTexture(nil, "BACKGROUND"); t.afOwn = true; AFUI.SetAtlas(t, a, size); return t end
  local l = atlas("common-coinbox-left"); l:SetPoint("LEFT", box, "LEFT"); l:SetWidth(8); l:SetHeight(17)
  local r = atlas("common-coinbox-right"); r:SetPoint("RIGHT", box, "RIGHT"); r:SetWidth(8); r:SetHeight(17)
  local c = atlas("_common-coinbox-center"); c:SetPoint("TOPLEFT", l, "TOPRIGHT"); c:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
  local prev = box
  for _, k in ipairs({ { "copper", "UI-CopperIcon", 22 }, { "silver", "UI-SilverIcon", 22 }, { "gold", "UI-GoldIcon", 44 } }) do
    local ic = box:CreateTexture(nil, "ARTWORK"); ic.afOwn = true
    ic:SetTexture("Interface\\MoneyFrame\\" .. k[2]); ic:SetWidth(13); ic:SetHeight(13)
    ic:SetPoint("RIGHT", prev, prev == box and "RIGHT" or "LEFT", prev == box and -4 or -3, 0)
    local fs = box:CreateFontString(nil, "ARTWORK", "NumberFontNormal")
    fs:SetPoint("RIGHT", ic, "LEFT", -1, 0); fs:SetJustifyH("RIGHT"); fs:SetWidth(k[3]); fs:SetHeight(12); fs.afOwn = true
    box[k[1]] = fs; prev = fs
  end
  return box
end
function M.SetMyMoney()
  local box = M.frames and M.frames.money
  if not box then return end
  local copper = _G.GetMoney and GetMoney() or 0
  local g, s, c
  if AFUI.BagMoney then g, s, c = AFUI.BagMoney(copper) else copper = math.floor(copper); g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100 end
  box.gold:SetText(g); box.silver:SetText(s); box.copper:SetText(c)
end

function M.Build()
  if M.frames then return M.frames end
  local inbox, send, open = _G.InboxFrame, _G.SendMailFrame, _G.OpenMailFrame
  local s = {}
  M.frames = s
  if inbox then
    local sum = CreateFrame("Frame", "AFUI_MailSummary", inbox)
    sum.afOwn = true
    sum.left, sum.right = label(sum, nil, "", "GameFontHighlightSmall"), label(sum, nil, "", "GameFontNormalSmall")
    sum.left:SetPoint("LEFT", sum, "LEFT", 2, 0); sum.right:SetPoint("RIGHT", sum, "RIGHT", -2, 0); sum.right:SetJustifyH("RIGHT")
    s.summary = sum
    s.collect = button("AFUI_MailCollectAll", inbox, "Collect All", 120, 26, "Takes the money and every attachment of every letter, one at a time. C.O.D. letters are skipped (and listed). Click again to cancel.", function()
      if run then M.Cancel() else M.Start("all") end
    end)
    s.gold = button("AFUI_MailTakeGold", inbox, "Take Gold", 124, 26, "Takes only the money of every letter, one at a time.", function() M.Start("gold") end)
    local cod = CreateFrame("CheckButton", "AFUI_MailSkipCOD", inbox)
    cod.afOwn = true; cod:SetWidth(20); cod:SetHeight(20)
    if AFUI.WinKit and AFUI.WinKit.check then AFUI.WinKit.check(cod) end
    cod.text = label(cod, nil, "Skip C.O.D. letters when collecting", "GameFontHighlightSmall"); cod.text:SetPoint("LEFT", cod, "RIGHT", 4, 0)
    cod:SetScript("OnClick", function(self) if AFUI.SetSetting then AFUI.SetSetting("mailSkipCOD", self:GetChecked() and true or false) end; M.Refresh() end)
    cod:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("On: Collect All skips C.O.D. letters. Off: it stops at the first one.", 1, 1, 1, 1, true); GameTooltip:Show() end)
    cod:SetScript("OnLeave", function() GameTooltip:Hide() end)
    s.cod = cod
  end
  if open then
    s.take = button("AFUI_OpenMailTakeAll", open, "Take All", 96, 26, "Takes the money and every attachment of this letter (a C.O.D. letter is never paid for you).", function()
      local id = _G.InboxFrame and InboxFrame.openMailID
      if id then M.Start("all", id) end
    end)
  end
  if send then
    s.money = M.MoneyBox(send, "AFUI_MailMyMoney")
    s.recent = button("AFUI_MailRecent", send, "Recent", 62, 22, "Names you sent mail to lately and your own characters.", function() M.ToggleRecent() end)
    local pop = CreateFrame("Frame", "AFUI_MailRecentList", send)
    pop:SetFrameStrata("DIALOG"); pop:SetWidth(300); pop.afOwn = true; pop.rows = {}
    if AFUI.WinKit and AFUI.WinKit.panel then AFUI.WinKit.panel(pop) end
    pop.h1, pop.h2 = label(pop, nil, "Recent", "GameFontNormalSmall"), label(pop, nil, "My characters", "GameFontNormalSmall")
    pop:Hide()
    s.pop = pop
  end
  return s
end

-- Fills and shows (or hides) the recipients list under the To box.
local ROW_H = 18
function M.ToggleRecent()
  local pop = M.frames and M.frames.pop
  if not pop then return end
  if pop:IsShown() then pop:Hide(); return end
  local lists = { M.Recents(), M.Alts() }
  local n = math.max(#lists[1], #lists[2], 1)
  pop:ClearAllPoints(); pop:SetPoint("TOPRIGHT", M.frames.recent, "BOTTOMRIGHT", 0, -2)
  pop:SetHeight(26 + n * ROW_H)
  pop.h1:ClearAllPoints(); pop.h1:SetPoint("TOPLEFT", pop, "TOPLEFT", 8, -6)
  pop.h2:ClearAllPoints(); pop.h2:SetPoint("TOPLEFT", pop, "TOPLEFT", 156, -6)
  for c = 1, 2 do
    for i = 1, M.RECENT_MAX do
      local key = c .. "_" .. i
      local name = lists[c][i]
      local b = pop.rows[key]
      if not b and name then
        b = CreateFrame("Button", nil, pop)
        b:SetWidth(140); b:SetHeight(ROW_H); b.afOwn = true
        b.text = label(b, nil, "", "GameFontHighlightSmall"); b.text:SetPoint("LEFT", b, "LEFT", 4, 0)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        b:SetScript("OnClick", function(self)
          local box = _G.SendMailNameEditBox
          if box then -- the complete name, text visible, cursor at its end, nothing selected (an edit box of the client's own: no completion data of ours)
            local text = M.CleanName(self.name)
            box:SetText(text)
            if box.SetCursorPosition then box:SetCursorPosition(#text) end
            if box.HighlightText then box:HighlightText(0, 0) end
          end
          pop:Hide()
        end)
        pop.rows[key] = b
      end
      if b then
        if name then
          b.name = M.CleanName(name); b.text:SetText(b.name)
          b:ClearAllPoints(); b:SetPoint("TOPLEFT", pop, "TOPLEFT", c == 1 and 6 or 154, -(22 + (i - 1) * ROW_H)); b:Show()
        else b:Hide() end
      end
    end
  end
  pop:Show()
end

---------------------------------------------------------------- the client's name completion (To box)
-- The completion is entirely the client's: AutoComplete_Update / AutoCompleteBox / AutoCompleteButton1..n. This file never sets its source or flags, never wraps its functions and never hides or
-- re-texts one of its FontStrings. Skinning only: the box above the mail window (strata), tinted dark with a thin bronze rim, and never narrower than its longest row (a row cut at the box width
-- reads "Name-"), through hooksecurefunc / HookScript. /afui mailauto prints what the box and the To box look like on a real client.
M.AUTO_ROWS = 20
local function autoRows()
  local out = {}
  for i = 1, M.AUTO_ROWS do local b = _G["AutoCompleteButton" .. i]; if b then out[#out + 1] = b end end
  return out
end
function M.SkinAutoComplete()
  local function skin()
    local box = _G.AutoCompleteBox
    if not box then return end
    if box.SetFrameStrata then box:SetFrameStrata("FULLSCREEN_DIALOG") end
    if box.SetBackdropColor then pcall(box.SetBackdropColor, box, 0.04, 0.04, 0.05, 0.96) end
    if box.SetBackdropBorderColor then pcall(box.SetBackdropBorderColor, box, 0.45, 0.37, 0.2, 1) end
    local w = 0
    for _, b in ipairs(autoRows()) do
      local fs = b:IsShown() and b.GetFontString and b:GetFontString()
      if fs and fs.GetStringWidth then w = math.max(w, fs:GetStringWidth() or 0) end
    end
    if w > 0 and box.GetWidth and box:GetWidth() < w + 24 then
      box:SetWidth(w + 24)
      for _, b in ipairs(autoRows()) do if b:IsShown() and b.GetNumPoints and b:GetNumPoints() < 2 then b:SetWidth(w + 12) end end
    end
  end
  M.autoSkin = skin
  if type(_G.AutoComplete_UpdateResults) == "function" then hooksecurefunc("AutoComplete_UpdateResults", skin) end
  if _G.AutoCompleteBox and AutoCompleteBox.HookScript then AutoCompleteBox:HookScript("OnShow", skin) end
end

-- Lines for /afui mailauto: the To box (font, colour, insets, what it carries) and the completion box with its rows' texts and widths.
function M.AutoReport()
  local lines = {}
  local function add(s) lines[#lines + 1] = s end
  local e = _G.SendMailNameEditBox
  if e then
    local font, size, flags = e.GetFont and e:GetFont()
    add(string.format("To box: text \"%s\", font %s %s %s, colour %s, insets %s, regions %d, shown %s, alpha %s",
      tostring(e.GetText and e:GetText()), tostring(font), tostring(size), tostring(flags), table.concat({ e.GetTextColor and e:GetTextColor() }, "/"),
      table.concat({ e.GetTextInsets and e:GetTextInsets() }, "/"), #{ e:GetRegions() }, tostring(e:IsShown()), tostring(e:GetAlpha())))
    for _, r in ipairs({ e:GetRegions() }) do add(string.format("  region %s %s shown=%s alpha=%s", tostring(r.GetObjectType and r:GetObjectType()), tostring(r.GetName and r:GetName()), tostring(r:IsShown()), tostring(r:GetAlpha()))) end
  else add("To box: missing") end
  local box = _G.AutoCompleteBox
  if box then
    add(string.format("AutoCompleteBox: shown %s, strata %s, level %s, width %s", tostring(box:IsShown()), tostring(box:GetFrameStrata()), tostring(box:GetFrameLevel()), tostring(box:GetWidth())))
    for i, b in ipairs(autoRows()) do
      local fs = b.GetFontString and b:GetFontString()
      add(string.format("  row %d shown=%s text \"%s\" width %s / string %s", i, tostring(b:IsShown()), tostring(b.GetText and b:GetText()), tostring(b:GetWidth()), tostring(fs and fs.GetStringWidth and fs:GetStringWidth())))
    end
  else add("AutoCompleteBox: missing") end
  if AFUI.Print then for _, l in ipairs(lines) do AFUI.Print(l) end end
  return lines
end
if AFUI.Slash and AFUI.Slash.Register then
  AFUI.Slash.Register("mailauto", M.AutoReport, "the To box and the name completion box as they look now (paste it when typing a name in Send Mail looks wrong)", "/afui mailauto")
end

---------------------------------------------------------------- Return protection
M.RETURN_POPUP = "AFUI_MAIL_CONFIRM_RETURN"
local function guardReturn()
  local b = _G.OpenMailDeleteButton
  if not b or b.afGuard then return end
  local orig = b:GetScript("OnClick")
  if not orig then return end
  b.afGuard = true
  if _G.StaticPopupDialogs then
    StaticPopupDialogs[M.RETURN_POPUP] = {
      text = "Send this letter, with what it holds, back to its sender?", button1 = _G.YES or "Yes", button2 = _G.NO or "No",
      OnAccept = function(_, data) if type(data) == "function" then data() end end, timeout = 0, whileDead = true, hideOnEscape = true,
    }
  end
  b:SetScript("OnClick", function(self, ...)
    local text = self.GetText and self:GetText()
    local id = _G.InboxFrame and InboxFrame.openMailID
    if M.On("mailConfirmReturn") and id and text == (_G.RETURN_TO_SENDER or "Return") and _G.StaticPopup_Show then
      local _, _, _, _, money, _, _, hasItem = GetInboxHeaderInfo(id)
      if (money or 0) > 0 or hasItem then
        local args = { ... }
        StaticPopup_Show(M.RETURN_POPUP, nil, nil, function() orig(self, unpack(args)) end)
        return
      end
    end
    return orig(self, ...)
  end)
end

---------------------------------------------------------------- setup (called by MailFrame.lua once the windows are skinned)
function M.Setup()
  if M.done then return end
  M.done = true
  for _, s in ipairs(M.SETTINGS) do
    if AFUI.ProvideSetting then AFUI.ProvideSetting(s[1], s[4]) end
    if AFUI.Settings and AFUI.Settings.Register then AFUI.Settings.Register{ category = "tooltips", key = s[1], label = "Mailbox: " .. s[2], default = s[4], tooltip = s[3] } end
    if AFUI.OnSettingChanged then AFUI.OnSettingChanged(s[1], function() M.UpdateRows(); M.Refresh() end) end
  end
  M.Build()
  M.RememberAlt()
  for i = 1, M.PER_PAGE do hookRowTooltip(i) end
  if type(_G.InboxFrame_Update) == "function" then hooksecurefunc("InboxFrame_Update", function() M.UpdateRows(); M.Refresh() end) end
  if type(_G.SendMail) == "function" then hooksecurefunc("SendMail", function(name) if M.On("mailRecents") then M.Remember(name) end end) end
  if _G.SendMailFrame then
    SendMailFrame:HookScript("OnHide", function() if M.frames.pop then M.frames.pop:Hide() end end)
    SendMailFrame:HookScript("OnShow", M.SetMyMoney)
  end
  AFUI.On("PLAYER_MONEY", M.SetMyMoney)
  for _, ev in ipairs({ "MAIL_INBOX_UPDATE", "MAIL_SHOW" }) do AFUI.On(ev, function() M.Landed(); M.UpdateRows(); M.Refresh(); M.SetMyMoney() end) end
  M.SkinAutoComplete()
  M.SetMyMoney()
  AFUI.On("MAIL_CLOSED", function() if run then finish("closed") end end)
  AFUI.On("UI_ERROR_MESSAGE", function(_, a, b)
    local msg = type(a) == "string" and a or b
    if run and type(msg) == "string" and msg == (_G.ERR_INV_FULL or "Inventory is full.") then finish("full") end
  end)
  guardReturn()
  M.UpdateRows(); M.Refresh()
end
