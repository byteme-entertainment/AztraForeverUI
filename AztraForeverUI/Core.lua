AFUI = AFUI or {}

-- One failing handler, module or queued function reports through the error handler and the rest still run.
local function try(fn) xpcall(fn, geterrorhandler()) end

local handlers = {}
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if list then
    for i = 1, #list do -- pcall passes the arguments itself: no table or closure per handler per event (UNIT_HEALTH / UNIT_AURA run these in raids)
      local good, err = pcall(list[i], event, ...)
      if not good then geterrorhandler()(err) end
    end
  end
end)

function AFUI.On(event, fn)
  if not handlers[event] then
    if not pcall(frame.RegisterEvent, frame, event) then return end -- an event this client lacks
    handlers[event] = {}
  end
  local list = handlers[event]
  list[#list + 1] = fn
end

AFUI.Hidden = CreateFrame("Frame")
AFUI.Hidden:Hide()

function AFUI.Kill(f, keepParent)
  if not f then return end -- a Blizzard frame one of the two clients doesn't have
  if not f:IsProtected() then f:UnregisterAllEvents() end
  if not keepParent then f:SetParent(AFUI.Hidden) end -- keepParent: Blizzard reads the parent's fields (TargetFrame.auraRows)
  f:Hide()
end

local queue, queued = {}, {}
function AFUI.RunOutOfCombat(fn)
  if not InCombatLockdown() then return fn() end
  if queued[fn] then return end
  queued[fn] = true
  queue[#queue + 1] = fn
end
AFUI.On("PLAYER_REGEN_ENABLED", function()
  local q = queue
  queue, queued = {}, {}
  for i = 1, #q do try(q[i]) end
end)

AFUI.Modules = {}
local order = {}
function AFUI.RegisterModule(name, module)
  AFUI.Modules[name] = module
  order[#order + 1] = module
end
AFUI.On("PLAYER_LOGIN", function()
  if AFUI.RaisePopups then AFUI.RaisePopups() end
  if IsAddOnLoaded("Bartender4") then
    AFUI.Print("Aztra's Forever UI: disable Bartender4 for this character, both replace the action bars.")
  end
  for i = 1, #order do if order[i].OnLogin then try(order[i].OnLogin) end end
end)

-- The /afui command words. A module registers its own (AFUI.Slash.Register("name", fn(rest), "what it does", "usage")); a bare /afui runs "config" (Settings.lua), an
-- unknown word prints the help. Commands that live elsewhere (/editmode ...) only appear in the help through AFUI.Slash.Info.
local S = { cmds = {}, order = {}, info = {} }
AFUI.Slash = S
function S.Register(name, fn, help, usage)
  if type(name) ~= "string" or type(fn) ~= "function" then return end
  name = name:lower()
  if not S.cmds[name] then S.order[#S.order + 1] = name end
  S.cmds[name] = { fn = fn, help = help or "", usage = usage or ("/afui " .. name) }
end
function S.Info(usage, help) S.info[#S.info + 1] = { usage = usage, help = help } end
-- { { usage, help }, ... } in the order shown: the registered words, then the info lines.
function S.HelpLines()
  local out = {}
  for _, n in ipairs(S.order) do local c = S.cmds[n]; out[#out + 1] = { c.usage, c.help } end
  out[#out + 1] = { "/afui help", "this list" }
  for _, i in ipairs(S.info) do out[#out + 1] = { i.usage, i.help } end
  return out
end
function S.Help()
  AFUI.Print("|cffffd100Aztra's Forever UI|r  |cffbfbfbfslash commands|r")
  for _, l in ipairs(S.HelpLines()) do
    AFUI.Print("  |cff66ccff" .. l[1] .. "|r  |cffbfbfbf" .. l[2] .. "|r")
  end
end
function S.Run(msg)
  local word, rest = tostring(msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  word = word:lower()
  local c = S.cmds[word == "" and "config" or word]
  if c then c.fn(rest); return end
  if word ~= "" then AFUI.Print("|cffffd100Aztra's Forever UI|r: unknown command '" .. word .. "'.") end
  S.Help()
end
S.cmds.help = { fn = S.Help } -- listed last by HelpLines
SLASH_AFUI1 = "/afui"
SlashCmdList = SlashCmdList or {}
SlashCmdList["AFUI"] = S.Run

AFUI.On("ADDON_LOADED", function(_, addon)
  if addon ~= "AztraForeverUI" then return end
  if type(AztraForeverUIDB) ~= "table" then AztraForeverUIDB = { layouts = {} } end
  if type(AztraForeverUICharDB) ~= "table" then
    AztraForeverUICharDB = { active = { scope = "preset", name = "Modern" }, layouts = {} }
  end
end)

-- Taint diagnostic: Blizzard's "blocked from an action only available to the Blizzard UI" popup comes from these two events. Only our own addon is
-- reported (chat line + the last 20 in a ring buffer, `/afui taint`), with the function name, so a block can be traced to the call.
AFUI.Taint = { log = {}, MAX = 20 }
function AFUI.Taint.Record(event, addon, func)
  if addon ~= "AztraForeverUI" then return false end
  local T = AFUI.Taint
  T.log[#T.log + 1] = { event = event, func = tostring(func) }
  if #T.log > T.MAX then table.remove(T.log, 1) end
  if AFUI.Print then AFUI.Print("|cffff5555AFUI blocked:|r " .. tostring(addon) .. " tried " .. tostring(func)) end
  return true
end
AFUI.On("ADDON_ACTION_FORBIDDEN", function(event, addon, func) AFUI.Taint.Record(event, addon, func) end)
AFUI.On("ADDON_ACTION_BLOCKED", function(event, addon, func) AFUI.Taint.Record(event, addon, func) end)
S.Register("taint", function()
  local T = AFUI.Taint
  if #T.log == 0 then AFUI.Print("Aztra's Forever UI: no blocked actions recorded."); return end
  for i, e in ipairs(T.log) do AFUI.Print(i .. ". " .. e.event .. " " .. e.func) end
end, "the last actions Blizzard blocked from this addon", "/afui taint")
