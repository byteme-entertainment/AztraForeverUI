-- Floating combat text (the damage / healing numbers over the target and the player). Nothing in this addon kills or hides it (the HitIndicator
-- regions held hidden in UnitFrames.lua are the portrait "-123", not the scrolling text), but a fresh 2.5.3 profile ships with the CVars off and
-- Blizzard_CombatText not loaded. So: set them on ONCE (db flag, later user changes are never overwritten), a Settings group, and /afui fct.
AFUI = AFUI or {}
local F = {}
AFUI.FloatingText = F

F.MASTER = "enableFloatingCombatText"
F.CVARS = { damage = "floatingCombatTextCombatDamage", healing = "floatingCombatTextCombatHealing", state = "floatingCombatTextCombatState" }
F.KEYS = { damage = "fctDamage", healing = "fctHealing", state = "fctState" }
F.ORDER = { "damage", "healing", "state" }
local EXTRA = { "enableCombatText", "floatingCombatTextFloatMode", "floatingCombatTextCombatDamageDirectionalScale",
  "floatingCombatTextCombatDamageDirectionalOffset", "floatingCombatTextLowManaHealth", "floatingCombatTextDodgeParryMiss" }

local function say(m) if AFUI.Print then AFUI.Print("|cffffd100Aztra's Forever UI|r: " .. m) end end
local function cvar(name) local ok, v = pcall(_G.GetCVar, name); if ok then return v end end
local function inCombat() return _G.InCombatLockdown and _G.InCombatLockdown() end

-- Writes one CVar when this client knows it (GetCVar answers nil for an unknown one); never raises.
function F.Set(name, value)
  if type(_G.SetCVar) ~= "function" or cvar(name) == nil then return false end
  return (pcall(_G.SetCVar, name, value and "1" or "0"))
end

function F.Loaded() return _G.IsAddOnLoaded and _G.IsAddOnLoaded("Blizzard_CombatText") and true or false end

function F.Load()
  if F.Loaded() then return true end
  local load = (_G.C_AddOns and _G.C_AddOns.LoadAddOn) or _G.LoadAddOn
  if load then pcall(load, "Blizzard_CombatText") end
  return F.Loaded()
end

-- The three groups follow the CVars (the native Interface Options may have changed them).
function F.Sync()
  for _, k in ipairs(F.ORDER) do
    local v = cvar(F.CVARS[k])
    if v ~= nil then AFUI.SetSetting(F.KEYS[k], v == "1" or v == 1) end
  end
end

-- Everything on and the addon loaded (the first run, and /afui fct on).
function F.Enable()
  F.Set(F.MASTER, true)
  for _, k in ipairs(F.ORDER) do F.Set(F.CVARS[k], true) end
  F.Load()
  F.Sync()
end

function F.Defaults()
  if inCombat() then return AFUI.RunOutOfCombat(F.Defaults) end
  local db = _G.AztraForeverUIDB
  if type(db) ~= "table" then return end
  if not db.fctDefaulted then
    db.fctDefaulted = true
    F.Enable()
  else
    if cvar(F.MASTER) == "1" then F.Load() end
    F.Sync()
  end
end

local function frameInfo(name)
  local f = _G[name]
  if not f then return name .. ": missing" end
  local p = f.GetParent and f:GetParent()
  local pn = p and p.GetName and p:GetName() or tostring(p)
  local function g(m) if f[m] then local ok, v = pcall(f[m], f); if ok then return tostring(v) end end return "?" end
  return string.format("%s: shown=%s visible=%s alpha=%s parent=%s scale=%s", name, g("IsShown"), g("IsVisible"), g("GetAlpha"), tostring(pn), g("GetScale"))
end

function F.Report()
  local out = {}
  local function add(s) out[#out + 1] = s end
  local ok, ver, build = pcall(_G.GetBuildInfo or function() return "?", "?" end)
  add("client " .. tostring(ok and ver or "?") .. " build " .. tostring(ok and build or "?") .. ", in combat: " .. tostring(inCombat() and true or false))
  add("CVar " .. F.MASTER .. " = " .. tostring(cvar(F.MASTER)))
  for _, k in ipairs(F.ORDER) do add("CVar " .. F.CVARS[k] .. " = " .. tostring(cvar(F.CVARS[k]))) end
  for _, n in ipairs(EXTRA) do add("CVar " .. n .. " = " .. tostring(cvar(n))) end
  add("Blizzard_CombatText loaded: " .. tostring(F.Loaded()) .. ", CombatText_AddMessage: " .. tostring(type(_G.CombatText_AddMessage) == "function"))
  add(frameInfo("CombatText"))
  add(frameInfo("CombatText1"))
  add(frameInfo("UIParent"))
  add(frameInfo("PlayerFrame") .. " (killed on purpose, ours replaces it)")
  add(frameInfo("PlayerHitIndicator") .. " (portrait -123, not the scrolling text)")
  local db = _G.AztraForeverUIDB
  add("AFUI defaults applied once: " .. tostring(type(db) == "table" and db.fctDefaulted or false))
  local ct = _G.CombatText
  local reg = ct and ct.IsEventRegistered and select(2, pcall(ct.IsEventRegistered, ct, "COMBAT_TEXT_UPDATE"))
  add("CombatText registered for COMBAT_TEXT_UPDATE: " .. tostring(reg))
  return out
end

AFUI.Slash.Register("fct", function(rest)
  if tostring(rest):lower() == "on" then
    if inCombat() then say("not in combat."); return end
    F.Enable()
    say("floating combat text switched on. If numbers still do not show, /reload once and paste /afui fct.")
  end
  for _, l in ipairs(F.Report()) do say(l) end
end, "floating combat text: status (paste it if damage numbers are missing); 'on' switches everything on", "/afui fct [on]")

local LABELS = { damage = { "Damage numbers", "Damage you deal and take as numbers floating over the target and your character." },
  healing = { "Healing numbers", "Healing as green numbers over the healed unit." },
  state = { "Combat state", "Entering and leaving combat, low health and similar short messages." } }
for _, k in ipairs(F.ORDER) do
  local key, name = F.KEYS[k], F.CVARS[k]
  if AFUI.Settings and AFUI.Settings.Register then
    AFUI.Settings.Register { category = "general", key = key, label = LABELS[k][1], default = true, tooltip = LABELS[k][2] .. " Switches the client's " .. name .. " option." }
  end
  AFUI.ProvideSetting(key, true) -- the panel shows an option once a module has asked for its key
  AFUI.OnSettingChanged(key, function(v)
    local on = v and true or false
    if cvar(name) == (on and "1" or "0") then return end
    AFUI.RunOutOfCombat(function() F.Set(name, on); if on then F.Set(F.MASTER, true); F.Load() end end)
  end)
end

AFUI.RegisterModule("FloatingText", { OnLogin = function() F.Defaults() end })
