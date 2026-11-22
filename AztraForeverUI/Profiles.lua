-- Profiles: the whole configuration (the settings window's options and the active Edit Mode layout) saved under a name, account wide, and chosen per character.
--   AztraForeverUIDB.profiles[name] = { settings = {key = value}, charSettings = {key = value}, layout = { preset = "Modern" } | { name, systems } }
--   AztraForeverUIDB.newCharProfile = the profile a character with no profile yet starts from (default "Default")
--   AztraForeverUICharDB.profile = the profile this character uses
-- The LIVE state stays where every module already reads it (AztraForeverUIDB.settings, AztraForeverUICharDB.settings, the layouts): the profile table is a snapshot taken
-- when you switch away, export, copy or log out, and loading one writes it back through AFUI.SetSetting / Layouts, the same paths a normal change takes.
-- shortcut: two characters on the same profile name overwrite each other's snapshot (the last to log out wins); each new character gets a profile of its own, so only a deliberate /afui profile use shares one.
-- Not in a profile: window positions, chat history, bag marks and the other per-character data that is not an option or a layout.
AFUI = AFUI or {}
local P = {}
AFUI.Profiles = P
local L, EM = AFUI.Layouts, AFUI.EditMode
local DEFAULT, MAX_NAME = "Default", 32
local MAX_TEXT, MAX_BODY, MAX_LINES, MAX_KEYS, MAX_STR = 262144, 196608, 4000, 1500, 256
local TAG, VERSION = "AFUIP", 1

local function say(msg) if AFUI.Print then AFUI.Print("|cffffd100Aztra's Forever UI|r: " .. msg) end end
local function copy(v) return L.DeepCopy(v) end
local function charDB()
  if type(AztraForeverUICharDB) ~= "table" then AztraForeverUICharDB = {} end
  return AztraForeverUICharDB
end
local function profiles(create)
  local d = AztraForeverUIDB
  if type(d) ~= "table" then if not create then return {} end; d = {}; AztraForeverUIDB = d end
  if type(d.profiles) ~= "table" then if not create then return {} end; d.profiles = {} end
  return d.profiles
end

---------------------------------------------------------------- names
local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
-- The stored name that matches `name` (case does not matter), or nil.
local function find(name)
  name = trim(name):lower()
  for k, v in pairs(profiles()) do if type(v) == "table" and type(k) == "string" and k:lower() == name then return k end end
end
local function validName(name)
  name = trim(name)
  if name == "" then return nil, "empty name" end
  if #name > MAX_NAME or name:find("[%c|]") then return nil, "bad name" end
  return name
end

function P.Names()
  local out = {}
  for k, v in pairs(profiles()) do if type(v) == "table" and type(k) == "string" then out[#out + 1] = k end end
  table.sort(out, function(a, b) return a:lower() < b:lower() end)
  return out
end
function P.Active() local n = charDB().profile; return type(n) == "string" and n or nil end
function P.Exists(name) return find(name) ~= nil end

---------------------------------------------------------------- snapshot and load
local function scalarTable(t)
  local out = {}
  if type(t) == "table" then for k, v in pairs(t) do if type(k) == "string" and v ~= nil then out[k] = copy(v) end end end
  return out
end

-- The live state as a profile table.
function P.Capture()
  local acc = type(AztraForeverUIDB) == "table" and AztraForeverUIDB.settings
  local chr = type(AztraForeverUICharDB) == "table" and AztraForeverUICharDB.settings
  local layout = { preset = "Modern" }
  local scope, name = L.GetPointer()
  if scope ~= "preset" then
    local l = L.Get(scope, name)
    if l then layout = { name = name, systems = copy(l.systems) } end
  else
    layout = { preset = name }
  end
  local filters = AFUI.AuraFilters and AFUI.AuraFilters.SnapshotText and AFUI.AuraFilters.SnapshotText() or nil -- the aura filter library travels with the profile
  return { settings = scalarTable(acc), charSettings = scalarTable(chr), layout = layout, auraFilters = filters }
end

-- Stores the live state in this character's profile.
function P.Save()
  local n = P.Active()
  if n and profiles()[n] ~= nil then profiles()[n] = P.Capture() end
end

-- A layout from a profile becomes a character layout of that name (a name that is a preset or an account layout gets " (profile)").
local function landing(name, lay)
  name = validName(name) or "Profile"
  if L.Get("char", name) then L.Save("char", name, lay); return name end
  local good = L.Create(name, "char", lay)
  if not good then
    name = name:sub(1, MAX_NAME - 10) .. " (profile)"
    if L.Get("char", name) then L.Save("char", name, lay); return name end
    good = L.Create(name, "char", lay)
  end
  return good and name or nil
end

-- Writes profile `name` into the live state. apply: also re-apply the layout and refresh the open windows (a switch at run time); false while logging in, before anything has read a setting.
function P.Load(name, apply)
  local p = profiles()[name]
  if type(p) ~= "table" then return false, "missing" end
  local acc, chr = scalarTable(p.settings), scalarTable(p.charSettings)
  local keys = {}
  for _, t in ipairs({ acc, chr, scalarTable(type(AztraForeverUIDB) == "table" and AztraForeverUIDB.settings),
    scalarTable(type(AztraForeverUICharDB) == "table" and AztraForeverUICharDB.settings) }) do
    for k in pairs(t) do keys[k] = true end
  end
  for k in pairs(keys) do -- the account value first (it drops the character's override), then this profile's override
    AFUI.SetSetting(k, acc[k], "account")
    if chr[k] ~= nil then AFUI.SetSetting(k, chr[k], "char") end
  end
  local lay, done = p.layout, false
  if type(lay) == "table" and type(lay.preset) == "string" and AFUI.PRESETS[lay.preset] then done = L.SetActive("preset", lay.preset)
  elseif type(lay) == "table" and type(lay.systems) == "table" then
    local landed = landing(lay.name or ("Profile " .. name), lay)
    done = landed and L.SetActive("char", landed)
  end
  if not done then L.SetActive("preset", "Modern") end
  if AFUI.AuraFilters and AFUI.AuraFilters.RestoreText and type(p.auraFilters) == "string" then AFUI.AuraFilters.RestoreText(p.auraFilters) end -- a profile saved before the filters keeps the current library
  charDB().profile = name
  if apply then
    L.Apply((L.GetActive()))
    local D = AFUI.EditModeDialog
    if D and D.Reload then xpcall(D.Reload, geterrorhandler()) end
    if AFUI.Settings and AFUI.Settings.Refresh then AFUI.Settings.Refresh() end
  end
  return true
end

---------------------------------------------------------------- operations (each returns true, or false and a reason)
local function changed() if P.OnChanged then P.OnChanged() end end

function P.New(name)
  local n, err = validName(name)
  if not n then return false, err end
  if find(n) then return false, "exists" end
  profiles(true)[n] = { settings = {}, charSettings = {}, layout = { preset = "Modern" } }
  changed()
  return true
end

function P.Copy(from, to)
  local src = find(from)
  if not src then return false, "missing" end
  local n, err = validName(to)
  if not n then return false, err end
  if find(n) then return false, "exists" end
  if src == P.Active() then P.Save() end
  profiles(true)[n] = copy(profiles()[src])
  changed()
  return true
end

function P.Delete(name)
  local n = find(name)
  if not n then return false, "missing" end
  if n == P.Active() then return false, "active" end
  profiles()[n] = nil
  if type(AztraForeverUIDB) == "table" and AztraForeverUIDB.newCharProfile == n then AztraForeverUIDB.newCharProfile = nil end
  changed()
  return true
end

-- Switch this character to `name`: the current state is saved into its profile, then the new one is loaded and applied, out of combat.
-- Returns true (and "queued" when it waits for the end of combat), or false and why.
function P.Use(name)
  local n = find(name)
  if not n then return false, "missing" end
  if n == P.Active() then return true end
  if EM and EM.IsOpen and EM.IsOpen() then return false, "editmode" end
  local queued = InCombatLockdown and InCombatLockdown() and true or false
  AFUI.RunOutOfCombat(function()
    P.Save()
    P.Load(n, true)
    changed()
    say("profile '" .. n .. "' is active.")
  end)
  return true, queued and "queued" or nil
end

-- The profile a character with none starts from.
function P.NewCharProfile()
  local n = type(AztraForeverUIDB) == "table" and AztraForeverUIDB.newCharProfile
  return (type(n) == "string" and profiles()[n]) and n or find(DEFAULT) or P.Names()[1]
end
function P.SetNewCharProfile(name)
  local n = find(name)
  if not n then return false, "missing" end
  profiles(true)
  AztraForeverUIDB.newCharProfile = n
  changed()
  return true
end

---------------------------------------------------------------- start-up and migration
local function hasData()
  local c = charDB()
  local a = c.active
  return (type(c.settings) == "table" and next(c.settings) ~= nil) or (type(c.layouts) == "table" and next(c.layouts) ~= nil)
    or c.wizardDone == true or (type(a) == "table" and not (a.scope == "preset" and a.name == "Modern"))
end

local function uniqueName(base)
  base = validName(base) or "Character"
  local n, i = base, 2
  while find(n) do n = base:sub(1, MAX_NAME - 4) .. " " .. i; i = i + 1 end
  return n
end

function P.Init()
  local c = charDB()
  if type(AztraForeverUIDB) ~= "table" then AztraForeverUIDB = {} end
  if type(AztraForeverUIDB.profiles) ~= "table" then -- first run of this version: what is saved now becomes "Default", nothing lost
    AztraForeverUIDB.profiles = { [DEFAULT] = P.Capture() }
    c.profile = DEFAULT
    return
  end
  local cur = c.profile
  if type(cur) == "string" and profiles()[cur] ~= nil then return end -- the live state is this profile's
  local me = uniqueName(type(UnitName) == "function" and UnitName("player") or "Character")
  if type(cur) == "string" and cur ~= "" then -- its profile was deleted from another character: keep what this one has under the same name
    profiles()[cur] = P.Capture()
  elseif hasData() then -- a character from before profiles: its own settings and layouts are its profile
    profiles()[me] = P.Capture(); c.profile = me
  else -- a new character: a copy of the chosen profile (the account's "Default" unless the account chose another)
    local src = P.NewCharProfile()
    if src and type(profiles()[src]) == "table" then
      profiles()[me] = copy(profiles()[src])
      P.Load(me, false)
    else
      profiles()[me] = P.Capture(); c.profile = me
    end
  end
end

AFUI.On("ADDON_LOADED", function(_, addon)
  if addon == "AztraForeverUI" then P.Init() end
end)
AFUI.On("PLAYER_LOGOUT", function() P.Save() end)

---------------------------------------------------------------- export / import text
-- "AFUIP1:" + 8 hex checksum + ":" + base64 of lines:  a<TAB>key<TAB>value (account setting)  c<TAB>...  (character override)  p<TAB>Preset  l<TAB>name  L<TAB>AFUI1:{layout}
-- value = b1 / b0, n<number>, s<text with \\ \n \t \r escaped>.
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64I = {}
for i = 1, 64 do B64I[B64:sub(i, i)] = i - 1 end

local function b64enc(s)
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1, c2, c3, c4 = math.floor(n / 262144) % 64, math.floor(n / 4096) % 64, math.floor(n / 64) % 64, n % 64
    out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1) .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
  end
  return table.concat(out)
end
local function b64dec(s)
  if #s % 4 ~= 0 or #s == 0 then return nil end
  local out = {}
  for i = 1, #s, 4 do
    local q = s:sub(i, i + 3)
    local v = {}
    for j = 1, 4 do
      local ch = q:sub(j, j)
      if ch == "=" then if not (i + 3 == #s and j >= 3) then return nil end; v[j] = 0
      else
        v[j] = B64I[ch]
        if not v[j] or (j > 1 and q:sub(j - 1, j - 1) == "=") then return nil end
      end
    end
    local n = v[1] * 262144 + v[2] * 4096 + v[3] * 64 + v[4]
    local chunk = string.char(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
    if q:sub(4, 4) == "=" then chunk = chunk:sub(1, q:sub(3, 3) == "=" and 1 or 2) end
    out[#out + 1] = chunk
  end
  return table.concat(out)
end
P.B64Encode, P.B64Decode = b64enc, b64dec

local function checksum(s) -- Adler-32: catches a damaged or cut-off paste; it is no protection against someone writing a string by hand
  local a, b = 1, 0
  for i = 1, #s do a = (a + s:byte(i)) % 65521; b = (b + a) % 65521 end
  return string.format("%04x%04x", b, a)
end

local ESC = { ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t", ["\r"] = "\\r" }
local UNESC = { ["\\"] = "\\", n = "\n", t = "\t", r = "\r" }
local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function encValue(v)
  local t = type(v)
  if t == "boolean" then return v and "b1" or "b0" end
  if t == "number" and finite(v) then return "n" .. string.format("%.14g", v) end
  if t == "string" and #v <= MAX_STR then return "s" .. v:gsub("[\\\n\t\r]", ESC) end
end
local function decValue(s)
  local k, rest = s:sub(1, 1), s:sub(2)
  if k == "b" then if rest == "1" then return true elseif rest == "0" then return false end return nil end
  if k == "n" then local v = rest:match("^%-?[%d%.]+[eE]?[%+%-]?%d*$") and tonumber(rest); if finite(v) then return v end return nil end
  if k == "s" and #rest <= MAX_STR * 2 then
    local bad = false
    local v = rest:gsub("\\(.?)", function(c) if UNESC[c] then return UNESC[c] end; bad = true; return "" end)
    if not bad and #v <= MAX_STR and not rest:find("[\t\r]") then return v end
  end
end

-- `p` is a stored profile table. Returns the text, or nil, why.
function P.Serialize(p)
  if type(p) ~= "table" then return nil, "missing" end
  local lines = {}
  for tag, t in pairs({ a = p.settings, c = p.charSettings }) do
    local keys = {}
    for k, v in pairs(type(t) == "table" and t or {}) do
      if type(k) == "string" and k:find("^[%w_%.%-]+$") and #k <= 64 and encValue(v) then keys[#keys + 1] = k end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do lines[#lines + 1] = tag .. "\t" .. k .. "\t" .. encValue(t[k]) end
  end
  table.sort(lines)
  local lay = p.layout
  if type(lay) == "table" and type(lay.preset) == "string" then lines[#lines + 1] = "p\t" .. lay.preset
  elseif type(lay) == "table" and type(lay.systems) == "table" then
    lines[#lines + 1] = "l\t" .. tostring(lay.name or ""):gsub("[%c]", "")
    lines[#lines + 1] = "L\t" .. L.Serialize(lay)
  end
  if type(p.auraFilters) == "string" and p.auraFilters:find("^AFUIF%d+:%x+:[%w%+/=]+$") then lines[#lines + 1] = "f\t" .. p.auraFilters end
  local body = table.concat(lines, "\n")
  return TAG .. VERSION .. ":" .. checksum(body) .. ":" .. b64enc(body)
end

-- Strict reader. Returns a profile table made of plain values only, or nil, why ("bad text", "version", "too big", "checksum", "bad data").
function P.Deserialize(text)
  if type(text) ~= "string" then return nil, "bad text" end
  text = text:gsub("%s+", "") -- a paste that was wrapped
  if #text > MAX_TEXT then return nil, "too big" end
  local ver, sum, payload = text:match("^" .. TAG .. "(%d+):(%x+):([%w%+/=]+)$")
  if not ver then return nil, "bad text" end
  if tonumber(ver) ~= VERSION then return nil, "version" end
  if #sum ~= 8 then return nil, "bad text" end
  local body = b64dec(payload)
  if not body then return nil, "bad text" end
  if #body > MAX_BODY then return nil, "too big" end
  if checksum(body) ~= sum:lower() then return nil, "checksum" end
  local p = { settings = {}, charSettings = {}, layout = { preset = "Modern" } }
  local count, lines, pendingName = 0, 0, nil
  for line in (body .. "\n"):gmatch("(.-)\n") do
    lines = lines + 1
    if lines > MAX_LINES then return nil, "too big" end
    local tag, a, b = line:match("^(%a)\t([^\t]*)\t?(.*)$")
    if not tag then return nil, "bad data" end
    if tag == "a" or tag == "c" then
      if not a:find("^[%w_%.%-]+$") or #a > 64 or b == "" then return nil, "bad data" end
      local v = decValue(b)
      if v == nil then return nil, "bad data" end
      count = count + 1
      if count > MAX_KEYS then return nil, "too big" end
      p[tag == "a" and "settings" or "charSettings"][a] = v
    elseif tag == "p" then
      if not AFUI.PRESETS[a] then return nil, "bad data" end
      p.layout = { preset = a }
    elseif tag == "f" then
      if not (AFUI.AuraFilters and AFUI.AuraFilters.Deserialize(a)) then return nil, "bad data" end -- the filter library of the profile, checked by its own reader
      p.auraFilters = a
    elseif tag == "l" then pendingName = a
    elseif tag == "L" then
      local layout = L.Import(line:sub(3))
      if not layout then return nil, "bad data" end
      p.layout = { name = pendingName ~= "" and pendingName or nil, systems = layout.systems }
    else return nil, "bad data" end
  end
  return p
end

-- The text of profile `name` (the active one is saved first).
function P.Export(name)
  local n = find(name or P.Active())
  if not n then return nil, "missing" end
  if n == P.Active() then P.Save() end
  return P.Serialize(profiles()[n])
end

-- Adds the profile in `text` under `name`; it does not switch to it.
function P.Import(name, text)
  local n, err = validName(name)
  if not n then return false, err end
  if find(n) then return false, "exists" end
  local p, why = P.Deserialize(text)
  if not p then return false, why end
  profiles(true)[n] = p
  changed()
  return true
end

local ERRORS = {
  exists = "A profile with that name already exists.", ["empty name"] = "Please enter a name.", ["bad name"] = "Use up to 32 characters, no | or control characters.",
  missing = "There is no such profile.", active = "That profile is in use: switch to another first.",
  editmode = "Close Edit Mode first.", ["bad text"] = "That is not a profile string.", version = "That profile string is from another version.",
  ["too big"] = "That text is too long to be a profile.", checksum = "The string is damaged or cut off: copy it again.", ["bad data"] = "That profile string has data this version cannot read.",
}
P.ERRORS = ERRORS

---------------------------------------------------------------- the popup (name / confirm / export / import)
local win
local function field(parent, w, h)
  local box = CreateFrame("Frame", nil, parent)
  box:SetWidth(w); box:SetHeight(h)
  local bg = box:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(box); AFUI.SetColor(bg, 0, 0, 0, 0.6)
  for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local t = box:CreateTexture(nil, "BORDER")
    t:SetPoint(e[1], box, e[1], 0, 0); t:SetPoint(e[2], box, e[2], 0, 0)
    if e[3] then t:SetHeight(1) else t:SetWidth(1) end
    AFUI.SetColor(t, 0.55, 0.5, 0.42, 1)
  end
  return box
end

local function build()
  if win then return win end
  local W, K = AFUI.EditModeWidgets, AFUI.WinKit
  if not (W and K) then return end
  local f = W.Panel("AFUI_ProfilesPopup", 420, 180, true)
  f:SetFrameStrata("TOOLTIP")
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
  f.title = W.Label(f, "GameFontHighlight", "", "TOP", f, "TOP", 0, -20)
  f.message = W.Label(f, "GameFontHighlight", "", "TOP", f, "TOP", 0, -46)
  f.message:SetWidth(360)
  f.nameLabel = W.Label(f, "GameFontNormal", "Profile Name:", "TOPLEFT", f, "TOPLEFT", 28, -48)
  f.nameBox = field(f, 364, 24)
  f.name = CreateFrame("EditBox", "AFUI_ProfilesName", f.nameBox)
  f.name:SetAutoFocus(false); f.name:SetFontObject(_G.ChatFontNormal or _G.GameFontHighlight); f.name:SetMaxLetters(MAX_NAME)
  f.name:SetPoint("TOPLEFT", f.nameBox, "TOPLEFT", 6, -2); f.name:SetPoint("BOTTOMRIGHT", f.nameBox, "BOTTOMRIGHT", -6, 2)
  f.textLabel = W.Label(f, "GameFontNormal", "", "TOPLEFT", f, "TOPLEFT", 28, -48)
  f.textBox = field(f, 364, 150)
  f.scroll = CreateFrame("ScrollFrame", "AFUI_ProfilesScroll", f.textBox)
  f.scroll:SetPoint("TOPLEFT", f.textBox, "TOPLEFT", 2, -2); f.scroll:SetPoint("BOTTOMRIGHT", f.textBox, "BOTTOMRIGHT", -2, 2)
  f.text = CreateFrame("EditBox", "AFUI_ProfilesText", f.scroll)
  f.text:SetMultiLine(true); f.text:SetAutoFocus(false); f.text:SetFontObject(_G.ChatFontNormal or _G.GameFontHighlight); f.text:SetMaxLetters(0)
  f.text:SetPoint("TOPLEFT", f.scroll, "TOPLEFT", 0, 0); f.text:SetWidth(340); f.text:SetTextInsets(4, 4, 3, 3)
  f.scroll:SetScrollChild(f.text)
  f.scroll:EnableMouseWheel(true)
  K.scrollbar(f.scroll, {
    get = function() return f.scroll:GetVerticalScroll() or 0 end,
    set = function(v) f.scroll:SetVerticalScroll(v) end,
    max = function() return f.scroll:GetVerticalScrollRange() or 0 end,
    view = function() return f.scroll:GetHeight() or 0 end,
    step = 30,
  }, { parent = f.textBox, x = 3 })
  f.error = W.Label(f, "GameFontRedSmall", "", "BOTTOM", f, "BOTTOM", 0, 58)
  local function accept()
    local o = f.opts
    if not o then return end
    local good, err = true, nil
    if o.onAccept then good, err = o.onAccept(f.name:GetText(), f.text:GetText()) end
    if good == false then f.error:SetText(ERRORS[err] or tostring(err))
    elseif f.opts == o then f.opts = nil; f:Hide() end -- onAccept may have opened the next popup (Delete asks which, then confirms)
  end
  local function cancel() f.opts = nil; f:Hide() end
  local function refresh()
    local o = f.opts
    if not (o and o.kind ~= "confirm" and o.kind ~= "export") then return end
    local named = o.kind == "export" or trim(f.name:GetText() or "") ~= ""
    local texted = o.kind ~= "import" or trim(f.text:GetText() or "") ~= ""
    if named and texted then f.ok:Enable() else f.ok:Disable() end
  end
  f.refresh = refresh
  f.name:SetScript("OnTextChanged", refresh)
  f.name:SetScript("OnEnterPressed", accept)
  f.name:SetScript("OnEscapePressed", cancel)
  f.text:SetScript("OnEscapePressed", cancel)
  f.text:SetScript("OnTextChanged", function(self, user)
    if f.opts and f.opts.kind == "export" and user and self:GetText() ~= f.opts.text then self:SetText(f.opts.text) end -- selectable, not editable
    f.scroll:UpdateScrollChildRect()
    refresh()
  end)
  f.ok = W.RedButton(f, "AFUI_ProfilesOK", "Accept", 130, 22, "BOTTOMLEFT", 25, 25, accept)
  f.cancel = W.RedButton(f, "AFUI_ProfilesCancel", "Cancel", 130, 22, "BOTTOMRIGHT", -25, 25, cancel)
  win = f
  return f
end

local function put(frame, point, x, y) frame:ClearAllPoints(); frame:SetPoint(point, win, point, x, y) end

-- kind: "name" (a name field), "confirm" (a question), "export" (text to copy), "import" (a name and a pasted text). onAccept(name, text) -> false, why keeps it open.
function P.Popup(opts)
  local f = build()
  if not f then return false end
  f.opts = opts
  f.title:SetText(opts.title or "")
  f.message:SetText(opts.message or "")
  f.error:SetText("")
  f.ok:SetText(opts.button1 or "Accept"); f.cancel:SetText(opts.button2 or "Cancel")
  f.ok:Enable()
  f.nameLabel:Hide(); f.nameBox:Hide(); f.textLabel:Hide(); f.textBox:Hide(); f.message:Hide()
  local h, y = 130, nil
  if opts.kind == "confirm" then
    f.title:ClearAllPoints(); f.title:SetPoint("TOP", f, "TOP", 0, -20)
    f.message:ClearAllPoints(); f.message:SetPoint("TOP", f, "TOP", 0, -48); f.message:Show()
    h = 150
  else
    f.title:ClearAllPoints(); f.title:SetPoint("TOP", f, "TOP", 0, -20)
    y = -48
    if opts.message and opts.kind == "name" then -- a line of help over the field (the profiles to pick from)
      f.message:ClearAllPoints(); f.message:SetPoint("TOP", f, "TOP", 0, -44); f.message:Show()
      y = -82
    end
    if opts.kind == "name" or opts.kind == "import" then
      f.nameLabel:SetText(opts.nameLabel or "Profile Name:"); put(f.nameLabel, "TOPLEFT", 28, y); f.nameLabel:Show()
      put(f.nameBox, "TOPLEFT", 28, y - 18); f.nameBox:Show()
      f.name:SetText(opts.default or "")
      y = y - 52
    end
    if opts.kind == "export" or opts.kind == "import" then
      f.textLabel:SetText(opts.textLabel or ""); put(f.textLabel, "TOPLEFT", 28, y); f.textLabel:Show()
      put(f.textBox, "TOPLEFT", 28, y - 18); f.textBox:Show()
      f.text:SetText(opts.text or "")
      y = y - 168
    end
  end
  if opts.kind ~= "confirm" then h = 70 - y + (opts.kind == "name" and -10 or 0) end
  f.Resize(420, h)
  f:Show()
  if opts.kind == "name" or opts.kind == "import" then f.name:SetFocus()
  elseif opts.kind == "export" then f.text:SetFocus(); f.text:HighlightText() end
  f.refresh()
  return true
end

---------------------------------------------------------------- UI actions (the settings page and the slash command share them)
local function result(good, err, okMsg)
  if good then if okMsg then say(okMsg) end; return true end
  say(ERRORS[err] or tostring(err))
  return false
end

function P.PromptNew()
  P.Popup({ kind = "name", title = "New Profile", button1 = "Create",
    onAccept = function(name) local g, e = P.New(name); if g then say("profile '" .. trim(name) .. "' created (defaults and the Modern layout).") end; return g, e end })
end
function P.PromptCopy(from)
  from = find(from or P.Active())
  if not from then return end
  P.Popup({ kind = "name", title = "Copy Profile", default = from .. " copy", button1 = "Copy",
    onAccept = function(name) local g, e = P.Copy(from, name); if g then say("'" .. from .. "' copied to '" .. trim(name) .. "'.") end; return g, e end })
end
function P.PromptDelete(name)
  if not name then -- which one: type its name
    P.Popup({ kind = "name", title = "Delete Profile", nameLabel = "Profile to delete:", message = "Profiles: " .. table.concat(P.Names(), ", "), button1 = "Next",
      onAccept = function(typed)
        local n = find(typed)
        if not n then return false, "missing" end
        if n == P.Active() then return false, "active" end
        P.PromptDelete(n)
        return true
      end })
    return
  end
  local n = find(name)
  if not n then say(ERRORS.missing); return end
  if n == P.Active() then say(ERRORS.active); return end
  P.Popup({ kind = "confirm", title = "Delete Profile", message = "Delete the profile \"" .. n .. "\"? It cannot be undone.", button1 = "Delete",
    onAccept = function() local g, e = P.Delete(n); if g then say("profile '" .. n .. "' deleted.") end; return g, e end })
end
function P.PromptExport(name)
  local text, err = P.Export(name)
  if not text then say(ERRORS[err] or tostring(err)); return end
  if not P.Popup({ kind = "export", title = "Export Profile", textLabel = "Profile string (Ctrl+A, Ctrl+C):", text = text, button1 = "Close", button2 = "Close",
    onAccept = function() return true end }) then say("the string: " .. text) end
end
function P.PromptImport(name, text)
  P.Popup({ kind = "import", title = "Import Profile", textLabel = "Paste the profile string:", default = name or "", text = text or "", button1 = "Import",
    onAccept = function(n, t) local g, e = P.Import(n, t); if g then say("profile '" .. trim(n) .. "' imported. Use it from the Profiles page or /afui profile use.") end; return g, e end })
end

---------------------------------------------------------------- slash command
-- Words, with "quoted names" kept whole.
local function words(s)
  local out = {}
  s = tostring(s or "")
  local pos = 1
  while true do
    pos = s:find("%S", pos)
    if not pos then break end
    local q, e = s:match('^"([^"]*)"()', pos)
    if q then out[#out + 1] = q; pos = e
    else local w = s:match("^%S+", pos); out[#out + 1] = w; pos = pos + #w end
  end
  return out
end
P.Words = words

local USAGE = "/afui profile list | new <name> | copy <from> <to> | use <name> | delete <name> | export [name] | import [name]  (use \"quotes\" around a name with spaces)"
function P.Command(rest)
  local w = words(rest)
  local cmd = tostring(w[1] or ""):lower()
  local arg = tostring(rest or ""):match("^%s*%S+%s*(.-)%s*$") or "" -- everything after the word: a name with spaces needs no quotes
  arg = arg:match('^"(.*)"$') or arg
  if cmd == "list" then
    local cur, names = P.Active(), P.Names()
    say(#names .. " profile" .. (#names == 1 and "" or "s") .. " (* = this character):")
    for _, n in ipairs(names) do AFUI.Print("  " .. (n == cur and "|cff66ff66* " or "   ") .. n .. "|r") end
  elseif cmd == "new" and arg ~= "" then
    local g, e = P.New(arg)
    result(g, e, "profile '" .. trim(arg) .. "' created (defaults and the Modern layout). /afui profile use " .. trim(arg) .. " switches to it.")
  elseif cmd == "copy" and w[2] and w[3] then
    local to = table.concat(w, " ", 3)
    local g, e = P.Copy(w[2], to)
    result(g, e, "'" .. w[2] .. "' copied to '" .. to .. "'.")
  elseif cmd == "use" and arg ~= "" then
    local g, e = P.Use(arg)
    if g and e == "queued" then say("in combat: the profile switches when combat ends.") else result(g, e) end
  elseif cmd == "delete" and arg ~= "" then
    local g, e = P.Delete(arg)
    result(g, e, "profile '" .. trim(arg) .. "' deleted.")
  elseif cmd == "export" then
    P.PromptExport(arg ~= "" and arg or nil)
  elseif cmd == "import" then
    local name, text = arg:match("^(.-)%s*(" .. TAG .. "%d+:%S+)$")
    if text and trim(name) ~= "" then
      local g, e = P.Import(name, text)
      result(g, e, "profile '" .. trim(name) .. "' imported. /afui profile use " .. trim(name) .. " switches to it.")
    else P.PromptImport(arg) end
  else
    say(USAGE)
  end
end
AFUI.Slash.Register("profile", P.Command, "save, copy, switch, export and import the whole configuration (settings and layout)", "/afui profile list|new|copy|use|delete|export|import")

---------------------------------------------------------------- the Profiles page of the settings window
local choices = { DEFAULT }
local function refreshChoices()
  for i = #choices, 1, -1 do choices[i] = nil end
  for _, n in ipairs(P.Names()) do choices[#choices + 1] = n end
  if #choices == 0 then choices[1] = DEFAULT end
end
function P.OnChanged()
  refreshChoices()
  local S = AFUI.Settings
  if S and S.IsShown and S.IsShown() then S.Refresh() end
end

local S = AFUI.Settings
if S and S.Register then
  local function always() return true end
  local function def(o) o.category = "profiles"; o.requires = always; S.Register(o) end
  local function switch(v)
    local g, e = P.Use(v)
    if not g then say(ERRORS[e] or tostring(e)) elseif e == "queued" then say("in combat: the profile switches when combat ends.") end
  end
  def { type = "text", id = "profilesInfo", lines = 2,
    text = "A profile is the whole configuration: every option in these pages and the Edit Mode layout in use. Each character has its own. Export one to share it, import one to try it." }
  def { type = "dropdown", key = "profileActive", label = "Profile", default = DEFAULT, values = choices, get = P.Active, set = switch,
    tooltip = "The profile this character uses. Switching saves the current one first, then applies the other out of combat: the Edit Mode layout, the bars, the chat and every option." }
  def { type = "dropdown", key = "profileNewChar", label = "New characters", default = DEFAULT, values = choices,
    get = P.NewCharProfile, set = function(v) P.SetNewCharProfile(v) end,
    tooltip = "The profile a character that has never used this addon starts from (it gets its own copy). The Default profile unless you pick another." }
  def { type = "button", id = "profileNew", label = "New profile", onClick = P.PromptNew,
    tooltip = "Creates a profile with every option at its default and the Modern layout. It does not switch to it." }
  def { type = "button", id = "profileCopy", label = "Copy profile", onClick = function() P.PromptCopy() end,
    tooltip = "Copies the profile this character uses, with its latest changes, under a new name." }
  def { type = "button", id = "profileDelete", label = "Delete profile", onClick = function() P.PromptDelete() end,
    tooltip = "Asks which profile to delete. The one this character uses is refused: switch to another first." }
  def { type = "button", id = "profileExport", label = "Export profile", onClick = function() P.PromptExport() end,
    tooltip = "Shows the profile in use as one line of text to copy and send. It holds your options and your layout." }
  def { type = "button", id = "profileImport", label = "Import profile", onClick = function() P.PromptImport() end,
    tooltip = "Paste a profile string and name it. It is checked before anything is saved, and added to the list without switching to it." }
end
refreshChoices()
AFUI.On("ADDON_LOADED", function(_, addon) if addon == "AztraForeverUI" then refreshChoices() end end) -- the saved profiles are not there while the files load: listed again once Init (the handler above) ran
