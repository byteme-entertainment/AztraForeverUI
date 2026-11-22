-- Route Blizzard's action bar key bindings to our buttons with override bindings.
local MAP = {
  { "ACTIONBUTTON", "Main" },
  { "MULTIACTIONBAR1BUTTON", "BottomLeft" },
  { "MULTIACTIONBAR2BUTTON", "BottomRight" },
  { "MULTIACTIONBAR3BUTTON", "Right" },
  { "MULTIACTIONBAR4BUTTON", "Right2" },
}
local owner = CreateFrame("Frame")
local buttons = {}
for _, m in ipairs(MAP) do
  for i = 1, 12 do
    local b = _G["AFUI_" .. m[2] .. "Button" .. i]
    b.afuiBinding = m[1] .. i
    buttons[#buttons + 1] = b
  end
end

-- The video's hotkey text: modifiers as "s-" / "c-" / "a-" ("s-1", "c-Q", "a-E"); a long name is cut to the button with "..." ("Mous...").
local MODS = { { "SHIFT-", "s-" }, { "CTRL-", "c-" }, { "ALT-", "a-" } }
function AFUI.HotkeyText(key)
  local prefix, again = "", true
  while again do
    again = false
    for _, m in ipairs(MODS) do
      if #key > #m[1] and key:sub(1, #m[1]) == m[1] then prefix = prefix .. m[2]; key = key:sub(#m[1] + 1); again = true end
    end
  end
  return prefix .. (AFUI.IS_243 and GetBindingText(key, "KEY_") or GetBindingText(key)) -- full names, as the video ("Mous...")
end

local function SetHotkey(b)
  local key = GetBindingKey(b.afuiBinding)
  if not key then return end -- unbound: Blizzard's ActionButton_UpdateHotkeys already hid it
  local hotkey = _G[b:GetName() .. "HotKey"]
  hotkey:SetWidth(36); hotkey:SetJustifyH("RIGHT")
  if hotkey.SetWordWrap then hotkey:SetWordWrap(false) end -- cut with "..." instead of wrapping
  hotkey:SetText(AFUI.HotkeyText(key))
  hotkey:Show()
end

-- Out of combat only. A button hidden by its bar's Icons setting (statehidden) gets no key: it would fire an unseen action.
local function Update()
  ClearOverrideBindings(owner)
  if not AFUI.ModuleEnabled("actionbars") then return end -- another addon owns the bars and their keys (AddonCompat.lua)
  for _, b in ipairs(buttons) do
    if not b:GetAttribute("statehidden") then
      for _, key in ipairs({ GetBindingKey(b.afuiBinding) }) do
        SetOverrideBindingClick(owner, false, key, b:GetName())
      end
      SetHotkey(b)
    end
  end
end
AFUI.UpdateBindings = Update -- ActionBars re-runs it after a relayout

-- Blizzard's own UPDATE_BINDINGS handler on our buttons resets the label; re-apply ours after it.
AFUI.HookActionButton("ActionButton_UpdateHotkeys", function(b)
  if b and b.afuiBinding then SetHotkey(b) end
end)

local function Queue() AFUI.RunOutOfCombat(Update) end
AFUI.On("PLAYER_LOGIN", Queue)
AFUI.On("UPDATE_BINDINGS", Queue)

-- J: Guild & Communities (GuildCommunities.lua). A real key binding (Bindings.xml adds the entry to Key Bindings > AddOns, where the key can be changed). The
-- default key is set once, and only while J is free or still the client's own guild / social toggle (GuildCommunities.BindPlan), so a player who unbinds it or
-- uses J for something else is never overridden. An earlier version used SHIFT-J: that binding moves to J the same way. Keys never fire while an edit box has focus.
BINDING_HEADER_AFUI = "Aztra's Forever UI"
BINDING_NAME_AFUI_GUILDCOMM = "Guild & Communities"
function AFUI_ToggleGuildCommunities()
  if AFUI.GuildCommunities and AFUI.ModuleEnabled("guild") then AFUI.GuildCommunities.Toggle()
  elseif type(_G.ToggleGuildFrame) == "function" then ToggleGuildFrame() -- Guild windows switched off: the key (still bound to us until the next login) opens the client's own
  elseif type(_G.ToggleFriendsFrame) == "function" then ToggleFriendsFrame(3) end
end

-- Guild windows switched off (Settings > Windows): J goes back to what it was before we took it (the client's own guild toggle when an earlier version took it without noting
-- the old action), and the next time the switch is on the key is taken again.
local function giveBackGuildKey(db)
  if not db.guildCommKeyDone or GetBindingAction("J") ~= "AFUI_GUILDCOMM" then return end
  local was = db.guildCommKeyWas
  if was == nil then was = "TOGGLEGUILDTAB" end
  if SetBinding("J", was ~= "" and was or nil) then
    db.guildCommKeyDone, db.guildCommKeyWas = nil, nil
    if _G.SaveBindings and _G.GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
  end
end

function AFUI.BindGuildCommKey()
  local db = _G.AztraForeverUIDB
  if type(db) ~= "table" or not _G.SetBinding or not _G.GetBindingAction then return end
  if not AFUI.ModuleEnabled("guild") then return giveBackGuildKey(db) end
  local plan = AFUI.GuildCommunities and AFUI.GuildCommunities.BindPlan(GetBindingAction("J"), db.guildCommKeyDone, GetBindingAction("SHIFT-J"),
    GetBindingKey and GetBindingKey("AFUI_GUILDCOMM") ~= nil)
  if not plan then return end
  db.guildCommKeyDone = true
  db.guildCommKeyWas = GetBindingAction("J") or ""
  if SetBinding("J", "AFUI_GUILDCOMM") then
    if plan == "migrate" then SetBinding("SHIFT-J") end -- no action: the old key is free again
    if _G.SaveBindings and _G.GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
  end
end
AFUI.On("PLAYER_LOGIN", function() AFUI.RunOutOfCombat(AFUI.BindGuildCommKey) end)


-- /afui swapkeys: the keys of the main bar (ACTIONBUTTON1-12) and of Action Bar 4 (MULTIACTIONBAR3BUTTON1-12) trade places, button by button, so the main bar
-- carries Blizzard's default 1234567890-= when that bar had been given the Shift keys; a main button left without any key gets its default key when that key is
-- free. Running it again swaps back. Out of combat only (SetBinding is protected); nothing is lost: every key stays on one of the two bars.
local DEFAULT_KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=" }
function AFUI.SwapBarKeys(cmdA, cmdB, n)
  if _G.InCombatLockdown and InCombatLockdown() then return false, "combat" end
  if not (_G.SetBinding and _G.GetBindingKey) then return false, "no bindings API" end
  for i = 1, n do
    local a, b = cmdA .. i, cmdB .. i
    local ka, kb = { GetBindingKey(a) }, { GetBindingKey(b) }
    for _, k in ipairs(ka) do SetBinding(k) end
    for _, k in ipairs(kb) do SetBinding(k) end
    for _, k in ipairs(ka) do SetBinding(k, b) end
    for _, k in ipairs(kb) do SetBinding(k, a) end
    local d = DEFAULT_KEYS[i]
    if cmdA == "ACTIONBUTTON" and d and #kb == 0 and GetBindingKey(a) == nil and (not _G.GetBindingAction or GetBindingAction(d) == "") then SetBinding(d, a) end
  end
  if _G.SaveBindings and _G.GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
  return true
end
AFUI.Slash.Register("swapkeys", function()
  local ok, why = AFUI.SwapBarKeys("ACTIONBUTTON", "MULTIACTIONBAR3BUTTON", 12)
  AFUI.Print(ok and "Keys of the main bar and Action Bar 4 swapped (run it again to swap back)." or ("Could not swap the keys: " .. tostring(why)))
end, "swap the keys of the main bar and Action Bar 4 (default 1234567890-= on the main bar)", "/afui swapkeys")
