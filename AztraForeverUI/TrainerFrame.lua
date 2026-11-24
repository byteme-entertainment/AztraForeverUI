-- Forever's class / profession trainer window over Blizzard's own ClassTrainerFrame (NpcKit.lua): metal portrait frame showing the trainer, dark plates behind the skill
-- list and the skill details, red Train / Cancel buttons, the filter dropdown, minimal scroll bars and Forever's row glow on the skill rows. Every script stays the client's
-- (selecting a skill, expanding a header, Train, the cost and requirement texts, the money). Blizzard_TrainerUI is load on demand: skinned on its ADDON_LOADED.
-- LAYOUT IS OURS, NOT THE CLIENT'S (a real 2.5.3 screenshot: the skill rows' texts drew outside the shrunk window, the cost and the player's money overlapped): everything the window
-- shows is placed from ONE table (T.Layout, in terms of OUR window size and the client's real row count / row height, never remembered native geometry): greeting, the expand + filter header,
-- the list plate with its scroll frame, bar and the skill rows INSIDE it (each row's text / sub text / +- icon / glow anchored to the row itself), the detail plate with its scroll frame and
-- the cost money (one anchor, the client's own width and coin sub-anchors), the footer with the player's money and Train / Cancel. The client re-anchors rows and resets their widths on every
-- update, so the layout is applied again after ClassTrainer_Update / ClassTrainer_SetSelection / FauxScrollFrame_Update(list) / OnShow, then measured (T.Validate): anything that still lies
-- outside the window or its plate is re-anchored into it and recorded for /afui trainerreport. Names: ClassTrainerFrame, ClassTrainerSkill1..N (CLASS_TRAINER_SKILLS_DISPLAYED, row
-- height CLASS_TRAINER_SKILL_HEIGHT), ClassTrainerListScrollFrame, ClassTrainerDetailScrollFrame (+ child), ClassTrainerSkillHighlightFrame, ClassTrainerDetailMoneyFrame / ClassTrainerMoneyFrame,
-- ClassTrainerTrainButton / CancelButton. Nothing unknown is hidden here (an unknown control stays, only moved into the window when it is found outside it).
AFUI = AFUI or {}
local T = {}
AFUI.TrainerFrame = T

T.SKILLS = 11 -- CLASS_TRAINER_SKILLS_DISPLAYED when the client does not say
T.errors, T.problems = {}, {}
T.plates = {}

-- The one layout table (pure): our window width, the real row count and row height. y = offsets from the top of the window, x from its left; every rect { x, y, w, h }.
function T.Layout(n, rowH, w)
  n = math.max(1, math.floor(tonumber(n) or T.SKILLS))
  rowH = (type(rowH) == "number" and rowH >= 10 and rowH <= 40) and rowH or 16
  w = w or 384
  local L = { w = w, n = n, rowH = rowH, pad = 10, inset = 4, bar = 17, gap = 2 }
  L.greet = { x = 66, y = 34, w = w - 76, h = 16 }
  L.head = { y = 56, h = 24 }
  L.list = { x = L.pad, y = 84, w = w - 2 * L.pad, h = n * rowH + 2 * L.inset }
  L.rowW = L.list.w - 2 * L.inset - L.bar - L.gap
  L.detail = { x = L.pad, y = L.list.y + L.list.h + 8, w = L.list.w, h = 144 }
  L.detailW = L.list.w - 2 * L.inset - L.bar - L.gap -- the scroll frame's inner width (the child frame gets it)
  L.foot = { y = L.detail.y + L.detail.h + 8, h = 40 }
  L.h = L.foot.y + L.foot.h
  return L
end

T.SPEC = {
  frame = "ClassTrainerFrame", title = "ClassTrainerNameText", close = "ClassTrainerFrameCloseButton", move = "trainer", npc = true,
  icon = "Interface\\Icons\\INV_Misc_Book_09",
  size = { w = 384, h = T.Layout(T.SKILLS).h, cut = 0 }, -- the metal frame is as tall as OUR layout; nothing of the client's frame height is assumed
  bare = { "ClassTrainerExpandButtonFrame" },
  buttons = { "ClassTrainerTrainButton", "ClassTrainerCancelButton" },
  dropdowns = { "ClassTrainerFrameFilterDropDown" },
  scrolls = { { "ClassTrainerListScrollFrameScrollBar", 2 }, { "ClassTrainerDetailScrollFrameScrollBar", 2 } },
  rows = {}, -- ClassTrainerSkill1..N, filled by T.Prepare
}
function T.Prepare(n, rowH)
  T.L = T.Layout(n, rowH)
  T.SPEC.size = { w = T.L.w, h = T.L.h, cut = 0 }
  T.SPEC.rows = {}
  for i = 1, T.L.n do T.SPEC.rows[i] = "ClassTrainerSkill" .. i end
  return T.L
end
T.Prepare(T.SKILLS)

---------------------------------------------------------------- measuring
local function g(n) return n and _G[n] end
local function rect(o) -- l, t, r, b in UI units (y up), or nil while the client has not laid it out
  if not (o and o.GetLeft) then return end
  local l, t, r, b = o:GetLeft(), o:GetTop(), o:GetRight(), o:GetBottom()
  if type(l) == "number" and type(t) == "number" and type(r) == "number" and type(b) == "number" then return l, t, r, b end
end
local function inside(o, host, tol)
  local l, t, r, b = rect(o); local hl, ht, hr, hb = rect(host)
  if not (l and hl) then return true end -- unplaced: says nothing
  tol = tol or 1
  return l >= hl - tol and r <= hr + tol and t <= ht + tol and b >= hb - tol
end
local function shown(o) return o and (not o.IsShown or o:IsShown()) end
local function under(o, a) -- is `o` a descendant of `a`?
  local p = o and o.GetParent and o:GetParent()
  local d = 0
  while p and d < 12 do if p == a then return true end; p = p.GetParent and p:GetParent(); d = d + 1 end
  return false
end
local function pos(o, rel, point, relPoint, x, y, w, h)
  o:ClearAllPoints(); o:SetPoint(point, rel, relPoint, x, y)
  if w then o:SetWidth(w) end
  if h then o:SetHeight(h) end
end

---------------------------------------------------------------- placing
local function plate(f, key, name)
  local p = T.plates[key]
  if not p then
    p = CreateFrame("Frame", name, f)
    p:SetFrameLevel(f:GetFrameLevel()); p.afOwn = true
    if AFUI.WinKit and AFUI.WinKit.panel then AFUI.WinKit.panel(p) end
    T.plates[key] = p
  end
  return p
end

-- The player's money and the cost: found by name, then by place (a money frame inside the detail scroll frame is the cost whatever it is called).
function T.Money()
  local detail = _G.ClassTrainerDetailScrollFrame
  local cost, mine = _G.ClassTrainerDetailMoneyFrame, _G.ClassTrainerMoneyFrame
  if not cost and mine and under(mine, detail) then cost, mine = mine, nil end
  if cost and mine and (mine == cost or under(mine, detail)) then mine = nil end
  return cost, mine
end
local function costLabel(child)
  local l = g("ClassTrainerCostLabel")
  if l and l.ClearAllPoints then return l end
  local want = AFUI.NpcKit.Norm(type(_G.COSTS_LABEL) == "string" and _G.COSTS_LABEL or "Cost")
  local function scan(f, d)
    for _, r in ipairs({ f:GetRegions() }) do
      if r.GetObjectType and r:GetObjectType() == "FontString" and AFUI.NpcKit.Norm(r:GetText()) == want then return r end
    end
    if d < 2 then for _, c in ipairs({ f:GetChildren() }) do local r = scan(c, d + 1); if r then return r end end end
  end
  return child and scan(child, 0)
end

local steps = {}
function steps.head(f, L)
  local gr = _G.ClassTrainerGreetingText
  if gr and gr.ClearAllPoints then pos(gr, f, "TOPLEFT", "TOPLEFT", L.greet.x, -L.greet.y, L.greet.w); if gr.SetJustifyH then gr:SetJustifyH("CENTER") end end
  local ex, dd, cy = _G.ClassTrainerExpandButtonFrame, _G.ClassTrainerFrameFilterDropDown, -(L.head.y + L.head.h / 2)
  if ex then pos(ex, f, "LEFT", "TOPLEFT", L.pad, cy) end
  if dd then pos(dd, f, "RIGHT", "TOPRIGHT", -L.pad + 16, cy) end -- the dropdown's bar sits 16 px inside its frame
end

local function fixRow(row, i, L, host)
  local name = row.GetName and row:GetName() or ("ClassTrainerSkill" .. i)
  pos(row, host, "TOPLEFT", "TOPLEFT", L.inset, -(L.inset + (i - 1) * L.rowH), L.rowW, L.rowH)
  local nt = row.GetNormalTexture and row:GetNormalTexture() -- the + / - of a header
  if nt then pos(nt, row, "LEFT", "LEFT", 4, 0, 16, 16) end
  local ht = row.GetHighlightTexture and row:GetHighlightTexture()
  if ht then ht:ClearAllPoints(); ht:SetAllPoints(row) end
  local sub = g(name .. "SubText")
  local fs = (row.GetFontString and row:GetFontString()) or g(name .. "Text")
  if sub == fs then sub = nil end
  if sub and sub.ClearAllPoints then pos(sub, row, "RIGHT", "RIGHT", -6, 0); if sub.SetJustifyH then sub:SetJustifyH("RIGHT") end end
  if fs and fs.ClearAllPoints then
    fs:ClearAllPoints(); fs:SetPoint("LEFT", row, "LEFT", 24, 0); fs:SetPoint("RIGHT", sub or row, sub and "LEFT" or "RIGHT", -6, 0)
    if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
  end
end

function steps.list(f, L)
  local host = plate(f, "list", "AFUI_TrainerListPlate")
  pos(host, f, "TOPLEFT", "TOPLEFT", L.list.x, -L.list.y, L.list.w, L.list.h)
  local sf = _G.ClassTrainerListScrollFrame
  if sf then sf:ClearAllPoints(); sf:SetPoint("TOPLEFT", host, "TOPLEFT", L.inset, -L.inset); sf:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -(L.inset + L.bar + L.gap), L.inset) end
  for i = 1, L.n do local row = g("ClassTrainerSkill" .. i); if row and row.ClearAllPoints then fixRow(row, i, L, host) end end
  local k = L.n + 1 -- rows past the client's own count are not ours to show
  while g("ClassTrainerSkill" .. k) do local x = g("ClassTrainerSkill" .. k); if x.Hide then x:Hide() end; k = k + 1 end
  local hl = _G.ClassTrainerSkillHighlightFrame -- the selection bar: the client anchors it to the selected row and sizes it for its own rows
  if hl and hl.SetWidth then hl:SetWidth(L.rowW); hl:SetHeight(L.rowH) end
end

function steps.detail(f, L)
  local host = plate(f, "detail", "AFUI_TrainerDetailPlate")
  pos(host, f, "TOPLEFT", "TOPLEFT", L.detail.x, -L.detail.y, L.detail.w, L.detail.h)
  local sf = _G.ClassTrainerDetailScrollFrame
  if sf then
    sf:ClearAllPoints(); sf:SetPoint("TOPLEFT", host, "TOPLEFT", L.inset, -L.inset); sf:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -(L.inset + L.bar + L.gap), L.inset)
    local child = (sf.GetScrollChild and sf:GetScrollChild()) or _G.ClassTrainerDetailScrollChildFrame
    if child and child.SetWidth then child:SetWidth(L.detailW) end
  end
  local cost = T.Money()
  if cost then -- ONE anchor, right of the label: the frame's own width and the coin buttons' sub-anchors are the client's (never stretched)
    local child = sf and ((sf.GetScrollChild and sf:GetScrollChild()) or _G.ClassTrainerDetailScrollChildFrame)
    local label = costLabel(child)
    if label then cost:ClearAllPoints(); cost:SetPoint("LEFT", label, "RIGHT", 6, 0) end
  end
end

function steps.foot(f, L)
  local train, cancel = _G.ClassTrainerTrainButton, _G.ClassTrainerCancelButton
  if cancel then cancel:ClearAllPoints(); cancel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -L.pad, 8) end
  if train then train:ClearAllPoints(); train:SetPoint("RIGHT", cancel or f, cancel and "LEFT" or "BOTTOMRIGHT", cancel and -6 or -L.pad, cancel and 0 or 22) end
  local _, mine = T.Money()
  if mine then
    local bank = AFUI.Bank
    if bank and bank.CoinBox and not T.coin then T.coin = bank.CoinBox(f); T.coin.afOwn = true end
    if T.coin then T.coin:ClearAllPoints(); T.coin:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", L.pad, 14) end
    mine:ClearAllPoints()
    if T.coin then mine:SetPoint("RIGHT", T.coin, "RIGHT", -6, 0) else mine:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", L.pad + 8, 14) end
    if mine.SetFrameLevel then mine:SetFrameLevel(f:GetFrameLevel() + 6) end
  end
end

local ORDER = { "head", "list", "detail", "foot" }
function T.Apply()
  local f, L = _G.ClassTrainerFrame, T.L
  if not (f and f.afNpc and L) or T.busy then return end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then T.pending = true; return end
  T.busy = true
  for _, tag in ipairs(ORDER) do
    local ok, err = pcall(steps[tag], f, L)
    if not ok and not T.errors[tag] then
      T.errors[tag] = tostring(err)
      if AFUI.Print then AFUI.Print("|cffff5555Trainer skin|r: step '" .. tag .. "' failed (" .. tostring(err) .. "); /afui trainerreport has the details") end
    end
  end
  local ok, err = pcall(T.Validate, f)
  if not ok then T.errors.validate = tostring(err) end
  T.busy = false
end

---------------------------------------------------------------- elements, validation, report
-- Every key element: { name, object, group ("list" | "detail" | "foot" | "head"), home = function that puts it back }.
function T.Elements()
  local L, out = T.L, {}
  local function add(name, o, group, tol) if o then out[#out + 1] = { name = name, o = o, group = group, tol = tol } end end
  local sf = _G.ClassTrainerListScrollFrame
  add("ClassTrainerListScrollFrame", sf, "list")
  add("ClassTrainerListScrollFrameScrollBar (ours)", sf and _G.ClassTrainerListScrollFrameScrollBar and _G.ClassTrainerListScrollFrameScrollBar.afBar, "list")
  for i = 1, L.n do
    local row = g("ClassTrainerSkill" .. i)
    if row then
      add("ClassTrainerSkill" .. i, row, "list")
      for _, r in ipairs({ row:GetRegions() }) do
        local k = r.GetObjectType and r:GetObjectType()
        if k == "FontString" or k == "Texture" then
          local rn = (r.GetName and r:GetName()) or ("(unnamed " .. k .. ")")
          add("  " .. rn, r, "row:" .. i)
        end
      end
    end
  end
  add("ClassTrainerSkillHighlightFrame", _G.ClassTrainerSkillHighlightFrame, "list")
  add("ClassTrainerDetailScrollFrame", _G.ClassTrainerDetailScrollFrame, "detail")
  add("ClassTrainerSkillIcon", _G.ClassTrainerSkillIcon, "detail")
  local cost, mine = T.Money()
  add("cost money (" .. ((cost and cost.GetName and cost:GetName()) or "?") .. ")", cost, "detail")
  add("player money (" .. ((mine and mine.GetName and mine:GetName()) or "?") .. ")", mine, "foot")
  add("ClassTrainerTrainButton", _G.ClassTrainerTrainButton, "foot")
  add("ClassTrainerCancelButton", _G.ClassTrainerCancelButton, "foot")
  add("ClassTrainerFrameFilterDropDown", _G.ClassTrainerFrameFilterDropDown, "head", 20) -- the dropdown frame reaches 16 px past its bar
  add("ClassTrainerExpandButtonFrame", _G.ClassTrainerExpandButtonFrame, "head")
  add("ClassTrainerGreetingText", _G.ClassTrainerGreetingText, "head")
  return out
end

-- Measures the key elements; whatever lies outside the window (or outside its plate / its row) is put back inside, once, and recorded. Never errors.
function T.Validate(f)
  f = f or _G.ClassTrainerFrame
  local L = T.L
  if not (f and L and rect(f)) then return end
  local plates = { list = T.plates.list, detail = T.plates.detail }
  local bad = {}
  local function put(el, why)
    bad[#bad + 1] = el.name
    T.problems[el.name] = why
    if not T.logged then
      T.logged = true
      if AFUI.Print then AFUI.Print("|cffff5555Trainer skin|r: '" .. el.name:gsub("^%s+", "") .. "' was " .. why .. "; it was moved back into the window. /afui trainerreport has the details") end
    end
  end
  for _, el in ipairs(T.Elements()) do
    local o = el.o
    local rowNo = tonumber(el.group:match("^row:(%d+)"))
    if rowNo then -- a region of a skill row: inside its row
      local row = g("ClassTrainerSkill" .. rowNo)
      if shown(o) and not inside(o, row, 2) then
        put(el, "outside its row") -- back onto its row: a text spans it, a texture fills it
        o:ClearAllPoints()
        if o:GetObjectType() == "FontString" then o:SetPoint("LEFT", row, "LEFT", 24, 0); o:SetPoint("RIGHT", row, "RIGHT", -6, 0) else o:SetAllPoints(row) end
      end
    elseif shown(o) then
      local host = plates[el.group]
      local inWin = inside(o, f, el.tol or 1)
      if not inWin or (host and not inside(o, host, 1.5)) then
        put(el, inWin and "outside its plate" or "outside the window")
        if o == _G.ClassTrainerSkillHighlightFrame then
          o:SetWidth(L.rowW); o:SetHeight(L.rowH); if not inside(o, plates.list, 1.5) then o:Hide() end
        elseif not (o == _G.ClassTrainerListScrollFrame or o == _G.ClassTrainerDetailScrollFrame or o.afScrollbar) then
          o:ClearAllPoints() -- last resort: inside its plate (or the footer), keeping the client's own size
          if host then o:SetPoint("TOPLEFT", host, "TOPLEFT", L.inset, -L.inset) else o:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", L.pad, 10) end
        end
      end
    end
  end
  -- a loose text of the client's frame (a label whose place was measured from the old frame's bottom) over a plate or outside the window is decoration that drifted: it goes
  local function overlaps(o, host)
    local l, t, r, b = rect(o); local hl, ht, hr, hb = rect(host)
    return l and hl and l < hr and hl < r and b < ht and hb < t
  end
  for _, r in ipairs({ f:GetRegions() }) do
    if r.GetObjectType and r:GetObjectType() == "FontString" and shown(r) and not (r.afOwn or r.afLabel or r == _G.ClassTrainerGreetingText) then
      if not inside(r, f, 1) or overlaps(r, plates.list) or overlaps(r, plates.detail) then
        put({ name = "(loose text) " .. tostring(r:GetText() or "") }, "drawn over a plate or outside the window")
        r:SetAlpha(0); r:Hide()
      end
    end
  end
  return bad
end

local function anchors(o)
  local out = {}
  for i = 1, (o.GetNumPoints and o:GetNumPoints() or 0) do
    local p, rel, rp, x, y = o:GetPoint(i)
    local rn = rel and ((rel.GetName and rel:GetName()) or "(unnamed)") or "nil"
    out[#out + 1] = string.format("%s>%s:%s %+.0f,%+.0f", tostring(p), rn, tostring(rp), tonumber(x) or 0, tonumber(y) or 0)
  end
  return table.concat(out, "; ")
end
-- /afui trainerreport: for each key element its parent, anchors, rect and whether it is inside the window (and its plate), then the problems found and the errors.
function T.Report()
  local f, lines = _G.ClassTrainerFrame, {}
  if not (f and f.afNpc and T.L) then lines[1] = "trainer window: not skinned (Blizzard_TrainerUI not loaded yet, or the module is off)"
  else
    local wl, wt, wr, wb = rect(f)
    lines[1] = string.format("trainer window %s: layout %dx%d, %d rows of %d px, window rect %s", "ClassTrainerFrame", T.L.w, T.L.h, T.L.n, T.L.rowH, wl and string.format("%.0f,%.0f,%.0f,%.0f", wl, wt, wr, wb) or "unplaced")
    local plates = { list = T.plates.list, detail = T.plates.detail }
    for _, el in ipairs(T.Elements()) do
      local o = el.o
      local p = o.GetParent and o:GetParent()
      local l, t, r, b = rect(o)
      local where = l and string.format("%.0f,%.0f,%.0f,%.0f", l, t, r, b) or "unplaced"
      local host = plates[el.group]
      lines[#lines + 1] = string.format("%-44s parent %-30s %s | %s | window %s%s | %s", el.name, (p and p.GetName and p:GetName()) or "(unnamed)", where, anchors(o),
        inside(o, f, 1) and "in" or "OUT", host and (inside(o, host, 1.5) and ", plate in" or ", plate OUT") or "", shown(o) and "shown" or "hidden")
    end
  end
  for k, why in pairs(T.problems) do lines[#lines + 1] = "problem: " .. k .. " was " .. why end
  for tag, err in pairs(T.errors) do lines[#lines + 1] = "error in step " .. tag .. ": " .. err end
  if AFUI.Print then for _, l in ipairs(lines) do AFUI.Print(l) end end
  return lines
end
if AFUI.Slash and AFUI.Slash.Register then
  AFUI.Slash.Register("trainerreport", T.Report, "where the trainer window's list, rows, money and buttons are (paste it when the trainer looks wrong)", "/afui trainerreport")
end

---------------------------------------------------------------- setup
function T.Count()
  local n = tonumber(_G.CLASS_TRAINER_SKILLS_DISPLAYED)
  if not n then n = 0; while _G["ClassTrainerSkill" .. (n + 1)] do n = n + 1 end end
  return n > 0 and math.floor(n) or T.SKILLS
end

T.SPEC.after = function(f)
  if f.HookScript then f:HookScript("OnShow", T.Apply) end
  for _, fn in ipairs({ "ClassTrainer_Update", "ClassTrainerFrame_Update", "ClassTrainer_SetSelection" }) do
    if type(_G[fn]) == "function" then hooksecurefunc(fn, T.Apply) end
  end
  if type(_G.FauxScrollFrame_Update) == "function" then
    hooksecurefunc("FauxScrollFrame_Update", function(frame) if frame and frame == _G.ClassTrainerListScrollFrame then T.Apply() end end)
  end
  T.Apply()
end

function T.Setup()
  if T.done or not _G.ClassTrainerFrame or not AFUI.ModuleEnabled("trainer") then return end -- Blizzard_TrainerUI loads on demand: switched off, the client's own window stays
  T.done = true
  local row1 = _G.ClassTrainerSkill1
  T.Prepare(T.Count(), (row1 and row1.GetHeight and row1:GetHeight()) or tonumber(_G.CLASS_TRAINER_SKILL_HEIGHT))
  AFUI.RunOutOfCombat(function() AFUI.NpcKit.Skin(T.SPEC) end)
end

AFUI.On("ADDON_LOADED", function(_, name) if name == "Blizzard_TrainerUI" then T.Setup() end end)
AFUI.On("PLAYER_REGEN_ENABLED", function() if T.pending then T.pending = false; T.Apply() end end)
AFUI.RegisterModule("TrainerFrame", { OnLogin = T.Setup })
