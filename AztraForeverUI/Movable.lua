-- Makes the windows that other files build movable with the one shared helper (WinKit.makeMovable): Friends / Social (Raid, Who, Ignore are its tabs),
-- Group Finder, Guild and Guild & Communities. Their own files stay untouched: the frames are looked up by name and wired as soon as they exist.
AFUI = AFUI or {}

-- { frame name, key, own whole-frame drag (the guild windows already dragged by any free spot) }
local WINDOWS = {
  { "FriendsFrame", "social" }, { "LFGParentFrame", "lfg" }, { "AFUIGuildFrame", "guild", true }, { "AFUIGuildCommFrame", "guildcomm", true },
}

local function attach()
  local K = AFUI.WinKit
  if not K then return end
  for _, w in ipairs(WINDOWS) do
    local f = _G[w[1]]
    if f and not f.afMoveKey then K.makeMovable(f, w[3] and f or nil, w[2]) end
  end
end
AFUI.Movable = { Attach = attach }

AFUI.RegisterModule("Movable", { OnLogin = attach })
AFUI.On("ADDON_LOADED", attach) -- load on demand frames (Blizzard_*, the Group Finder's)
AFUI.On("PLAYER_ENTERING_WORLD", attach)
if type(_G.ToggleFriendsFrame) == "function" then hooksecurefunc("ToggleFriendsFrame", attach) end
if type(_G.ToggleLFGParentFrame) == "function" then hooksecurefunc("ToggleLFGParentFrame", attach) end
