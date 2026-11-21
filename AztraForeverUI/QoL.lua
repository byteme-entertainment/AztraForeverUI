-- Shared bits of the quality-of-life features (item level, sell price, sell junk, new-item glow): the setting keys with their defaults, a change
-- watcher, and money text with coin icons. AFUI.GetSetting / AFUI.SetSetting belong to the Settings round (Compat.lua); this file only creates a
-- minimal compatible store when they are missing, and reads every key through Q.Get so a store without our defaults still answers.
AFUI = AFUI or {}
local Q = {}
AFUI.QoL = Q

Q.DEFAULTS = {
  bagItemLevel = true, charItemLevel = true, tooltipSellPrice = true,
  sellJunkButton = true, autoSellJunk = false, bagNewGlow = true, bagKeyring = true,
  barGlow = true,
  bagQuestMarker = true, bagUpgradeArrow = true, bagAutoOpen = true, bagGroupCategory = false, bagDontSell = true,
  bagGrayJunk = true, bagRedUnusable = true,
}

if not AFUI.GetSetting then
  function AFUI.GetSetting(key)
    local d = _G.AztraForeverUIDB
    local s = type(d) == "table" and type(d.settings) == "table" and d.settings or nil
    if s and s[key] ~= nil then return s[key] end
    return Q.DEFAULTS[key]
  end
end
if not AFUI.SetSetting then
  function AFUI.SetSetting(key, value)
    if type(_G.AztraForeverUIDB) ~= "table" then _G.AztraForeverUIDB = {} end
    local d = _G.AztraForeverUIDB
    if type(d.settings) ~= "table" then d.settings = {} end
    d.settings[key] = value
  end
end

function Q.Get(key)
  local v = AFUI.GetSetting(key)
  if v == nil then v = Q.DEFAULTS[key] end
  return v and true or false
end

local watchers = {}
function Q.Watch(key, fn)
  watchers[key] = watchers[key] or {}
  local l = watchers[key]
  l[#l + 1] = fn
end
function Q.Changed(key)
  for _, fn in ipairs(watchers[key] or {}) do fn(key) end
end

-- copper -> gold, silver, copper
function Q.Split(copper)
  copper = math.floor(tonumber(copper) or 0)
  if copper < 0 then copper = 0 end
  return math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
end

local ICON = { "Interface\\MoneyFrame\\UI-GoldIcon", "Interface\\MoneyFrame\\UI-SilverIcon", "Interface\\MoneyFrame\\UI-CopperIcon" }
-- "12|T..gold..|t 34|T..silver..|t 56|T..copper..|t": zero parts left out (retail: "Sell Price: 25 [silver] 10 [copper]"), 0 copper = "0" + copper icon
function Q.CoinText(copper)
  local parts, v = {}, { Q.Split(copper) }
  for i = 1, 3 do
    if v[i] > 0 then parts[#parts + 1] = v[i] .. "|T" .. ICON[i] .. ":0:0:2:0|t" end
  end
  if #parts == 0 then return "0|T" .. ICON[3] .. ":0:0:2:0|t" end
  return table.concat(parts, " ")
end

-- plain coloured words for chat: "12g 34s 56c" (gold / silver / copper colours of the money frame)
function Q.CoinChat(copper)
  local g, s, c = Q.Split(copper)
  local out = {}
  if g > 0 then out[#out + 1] = "|cffffd700" .. g .. "g|r" end
  if s > 0 or g > 0 then out[#out + 1] = "|cffc7c7cf" .. s .. "s|r" end
  out[#out + 1] = "|cffeda55f" .. c .. "c|r"
  return table.concat(out, " ")
end

AFUI.RegisterModule("QoL", { OnLogin = function()
  -- the settings window's change reaches the features through its SetSetting, whichever file defined it
  if type(AFUI.SetSetting) == "function" then hooksecurefunc(AFUI, "SetSetting", function(key) Q.Changed(key) end) end
end })
