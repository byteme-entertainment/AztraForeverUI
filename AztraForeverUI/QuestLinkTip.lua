-- Quest links in chat for a quest that is not in your log.
-- Why: the client shows a quest link's tooltip only for quests it knows; for any other quest (a party member's, a guildmate's) hovering or clicking the link shows nothing.
-- Questie, when installed, knows every quest: its database gives the name, levels, text and who starts it. After the client's own handlers run, if no tooltip appeared
-- we show one built from that data (or from the link alone). Post-hooks only: no Blizzard function is replaced.
AFUI = AFUI or {}
local T = {}
AFUI.QuestLinkTip = T

local function module(name)
  local L = _G.QuestieLoader
  if not (L and L.ImportModule) then return nil end
  local ok, m = pcall(L.ImportModule, L, name)
  return ok and type(m) == "table" and m or nil
end

-- Questie's functions are called both ways in its own code (dot and colon): try the dot call, then the colon call.
local function ask(DB, name, id)
  local fn = DB[name]
  if type(fn) ~= "function" then return nil end
  local ok, r = pcall(fn, id)
  if ok and type(r) == "table" then return r end
  ok, r = pcall(fn, DB, id)
  return ok and type(r) == "table" and r or nil
end

-- "quest:123:45" or the whole |Hquest:123:45|h[Name]|h link -> id, level (the level is the link's own, the quest giver's view)
function T.Parse(link)
  local id, level = tostring(link or ""):match("quest:(%d+):?(%-?%d*)")
  id = tonumber(id)
  if not id then return end
  return id, tonumber(level)
end

-- { id, name, level, minLevel, lines = { text... }, start = "NPC name" } from the link text and Questie's database when there is one.
function T.Info(id, level, text)
  local info = { id = id, level = level, name = type(text) == "string" and text:match("%[(.-)%]") or nil, lines = {} }
  local DB = module("QuestieDB")
  if not (DB and DB.GetQuest) then return info end
  local q = ask(DB, "GetQuest", id)
  if not q then return info end
  info.name = q.name or info.name
  info.level = q.level or info.level
  info.minLevel = tonumber(q.requiredLevel)
  local d = q.Description
  if type(d) == "table" then for _, l in ipairs(d) do if type(l) == "string" and l ~= "" then info.lines[#info.lines + 1] = l end end
  elseif type(d) == "string" and d ~= "" then info.lines[1] = d end
  local npc = type(q.Starts) == "table" and type(q.Starts.NPC) == "table" and q.Starts.NPC[1]
  if npc then
    local n = ask(DB, "GetNPC", npc)
    if n and n.name then info.start = n.name end
  end
  return info
end

function T.Fill(tip, info)
  tip:AddLine(info.name or ("Quest " .. info.id), 1, 0.82, 0)
  if info.level and info.level > 0 then tip:AddLine("Level " .. info.level, 1, 1, 1) end
  if info.minLevel and info.minLevel > 0 then tip:AddLine("Requires level " .. info.minLevel, 1, 1, 1) end
  for _, l in ipairs(info.lines) do tip:AddLine(l, 0.9, 0.9, 0.9, true) end
  if info.start then tip:AddLine("Starts: " .. info.start, 0.5, 0.8, 1) end
  tip:AddLine("Not in your quest log", 0.6, 0.6, 0.6)
end

-- After the client's own handler: when its tooltip did not appear, show ours. `tip` is GameTooltip (hover) or ItemRefTooltip (click); setOwner is called with `owner`.
function T.ShowIfMissing(tip, owner, anchor, link, text)
  local id, level = T.Parse(link)
  if not (id and tip) or (tip.IsShown and tip:IsShown()) then return false end
  tip:SetOwner(owner, anchor)
  T.Fill(tip, T.Info(id, level, text))
  tip:Show()
  T.shown = tip
  return true
end

local function later(fn) if _G.C_Timer and C_Timer.After then C_Timer.After(0, fn) else fn() end end

local function hookChat(chat)
  if not chat or chat.afQuestTip or not chat.HookScript then return end
  chat.afQuestTip = true
  chat:HookScript("OnHyperlinkEnter", function(self, link, text)
    if not T.Parse(link) then return end
    later(function() T.ShowIfMissing(_G.GameTooltip, self, "ANCHOR_CURSOR", link, text) end)
  end)
  chat:HookScript("OnHyperlinkLeave", function()
    if T.shown == _G.GameTooltip then GameTooltip:Hide(); T.shown = nil end
  end)
end

function T.Setup()
  for i = 1, 20 do hookChat(_G["ChatFrame" .. i]) end
  if _G.FCF_OpenTemporaryWindow then hooksecurefunc("FCF_OpenTemporaryWindow", function() for i = 1, 20 do hookChat(_G["ChatFrame" .. i]) end end) end
  if _G.SetItemRef then
    hooksecurefunc("SetItemRef", function(link, text)
      if not T.Parse(link) then return end
      later(function() T.ShowIfMissing(_G.ItemRefTooltip, _G.UIParent, "ANCHOR_PRESERVE", link, text) end)
    end)
  end
end

AFUI.RegisterModule("QuestLinkTip", { OnLogin = T.Setup })
