-- Makes the windows that other files build movable with the one shared helper (WinKit.makeMovable): Friends / Social (Raid, Who, Ignore are its tabs),
-- Group Finder, Guild and Guild & Communities. Their own files stay untouched: the frames are looked up by name and wired as soon as they exist.
AFUI = AFUI or {}

-- A window whose switch is off (Settings > Windows) is the client's own and is not touched: no drag handle, no hook on its Toggle function.
-- { frame name, key, own whole-frame drag (the guild windows already dragged by any free spot), the window switch (AddonCompat.lua) }
local WINDOWS = {
  { "FriendsFrame", "social", false, "social" }, { "LFGParentFrame", "lfg", false, "lfg" },
  { "AFUIGuildFrame", "guild", true, "guild" }, { "AFUIGuildCommFrame", "guildcomm", true, "guild" },
}

local function attach()
  local K = AFUI.WinKit
  if not K then return end
  for _, w in ipairs(WINDOWS) do
    local f = _G[w[1]]
    if f and not f.afMoveKey and AFUI.ModuleEnabled(w[4]) then K.makeMovable(f, w[3] and f or nil, w[2]) end
  end
end
AFUI.Movable = { Attach = attach }

-- The Toggle hooks catch a window built on demand; they go on at login and only for a window that is ours (the switches are read from the saved settings then).
local function hookToggles()
  if type(_G.ToggleFriendsFrame) == "function" and AFUI.ModuleEnabled("social") then hooksecurefunc("ToggleFriendsFrame", attach) end
  if type(_G.ToggleLFGParentFrame) == "function" and AFUI.ModuleEnabled("lfg") then hooksecurefunc("ToggleLFGParentFrame", attach) end
end

AFUI.RegisterModule("Movable", { OnLogin = function() hookToggles(); attach() end })
AFUI.On("ADDON_LOADED", attach) -- load on demand frames (Blizzard_*, the Group Finder's)
AFUI.On("PLAYER_ENTERING_WORLD", attach)
