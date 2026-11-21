-- Edit Mode layouts: the saved placement and settings of every system.
-- Layout = { systems = { [key] = { x, y, scale, ...settings } } }.
-- Presets (AFUI.PRESETS) are read-only; character layouts live in AztraForeverUICharDB.layouts, account-wide ones in
-- AztraForeverUIDB.layouts, and AztraForeverUICharDB.active = { scope = "preset"|"char"|"account", name } points at the one in use.
AFUI = AFUI or {}
local L = {}
AFUI.Layouts = L
local EM = AFUI.EditMode
local MODERN = "Modern"

local function deepCopy(v)
  if type(v) ~= "table" then return v end
  local c = {}
  for k, x in pairs(v) do c[k] = deepCopy(x) end
  return c
end
L.DeepCopy = deepCopy

-- SavedVariables can be missing or damaged (hand edits, old versions): rebuild what is not a table.
local function store(scope)
  if scope == "account" then
    if type(AztraForeverUIDB) ~= "table" then AztraForeverUIDB = {} end
    if type(AztraForeverUIDB.layouts) ~= "table" then AztraForeverUIDB.layouts = {} end
    return AztraForeverUIDB.layouts
  end
  if type(AztraForeverUICharDB) ~= "table" then AztraForeverUICharDB = {} end
  if type(AztraForeverUICharDB.layouts) ~= "table" then AztraForeverUICharDB.layouts = {} end
  return AztraForeverUICharDB.layouts
end

local function validScope(scope) return scope == "char" or scope == "account" end

-- Returns the stored layout (presets: the preset table itself, never hand it to callers that edit).
function L.Get(scope, name)
  local l
  if scope == "preset" then l = AFUI.PRESETS[name]
  elseif validScope(scope) then l = store(scope)[name] end
  if type(l) == "table" and type(l.systems) == "table" then return l end
end

local function setPointer(scope, name)
  if type(AztraForeverUICharDB) ~= "table" then AztraForeverUICharDB = {} end
  AztraForeverUICharDB.active = { scope = scope, name = name }
end

function L.Pointer() -- the raw saved pointer, or nil
  local a = type(AztraForeverUICharDB) == "table" and AztraForeverUICharDB.active
  return type(a) == "table" and a or nil
end

function L.GetPointer()
  local a = L.Pointer()
  if a and L.Get(a.scope, a.name) then return a.scope, a.name end
  setPointer("preset", MODERN) -- missing, damaged or pointing at a deleted layout
  return "preset", MODERN
end

-- Returns a copy of the active layout (so callers may edit it), plus its scope and name.
function L.GetActive()
  local scope, name = L.GetPointer()
  return deepCopy(L.Get(scope, name)), scope, name
end

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
L.Trim = trim

local function nameTaken(name)
  return AFUI.PRESETS[name] or store("char")[name] or store("account")[name]
end

-- Presets and layouts share one name space, as in the dropdown.
function L.Create(name, scope, fromLayout)
  name = trim(name)
  if name == "" then return false, "empty name" end
  if not validScope(scope) then return false, "bad scope" end
  if nameTaken(name) then return false, "exists" end
  local src = type(fromLayout) == "table" and fromLayout.systems and fromLayout or AFUI.PRESETS[MODERN]
  -- A copy of a preset keeps Forever's anchors (they resolve against the live frame size when placed); anything else is flattened.
  local isPreset = false
  for _, p in pairs(AFUI.PRESETS) do if p == src then isPreset = true end end
  store(scope)[name] = isPreset and deepCopy({ systems = src.systems }) or L.Flatten(src)
  return true
end

function L.Rename(scope, old, new)
  if not validScope(scope) then return false, "preset" end
  new = trim(new)
  if new == "" then return false, "empty name" end
  local layouts = store(scope)
  if type(layouts[old]) ~= "table" then return false, "missing" end
  if new == old then return true end
  if nameTaken(new) then return false, "exists" end
  layouts[new], layouts[old] = layouts[old], nil
  local a = L.Pointer()
  if a and a.scope == scope and a.name == old then a.name = new end
  return true
end

function L.Delete(scope, name)
  if not validScope(scope) then return false, "preset" end
  local layouts = store(scope)
  if layouts[name] == nil then return false, "missing" end
  layouts[name] = nil
  local a = L.Pointer()
  if a and a.scope == scope and a.name == name then setPointer("preset", MODERN) end
  return true
end

function L.SetActive(scope, name)
  if not L.Get(scope, name) then return false, "missing" end
  setPointer(scope, name)
  return true
end

function L.Save(scope, name, layout)
  if not validScope(scope) then return false, "preset" end
  if type(layout) ~= "table" or type(layout.systems) ~= "table" then return false, "bad layout" end
  local layouts = store(scope)
  if type(layouts[name]) ~= "table" then return false, "missing" end
  layouts[name] = L.Flatten(layout)
  return true
end

-- Every layout of `scope`, sorted by name.
function L.Names(scope)
  local names = {}
  for name, l in pairs(store(scope)) do if type(l) == "table" then names[#names + 1] = name end end
  table.sort(names)
  return names
end

---------------------------------------------------------------- import / export
-- A layout as one line of text: "AFUI1:" and a small JSON object. Our own format (Forever's strings are encoded by the server
-- and cannot be read here). Import keeps only plain values, so pasted text can never put anything else into the layouts.
local TAG = "AFUI1:"

local function enc(v)
  local t = type(v)
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return nil end
    return tostring(v)
  elseif t == "boolean" then return tostring(v)
  elseif t == "string" then return '"' .. v:gsub('[\\"]', "\\%0") .. '"'
  elseif t == "table" then
    local keys = {}
    for k in pairs(v) do if type(k) == "string" then keys[#keys + 1] = k end end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do
      local e = enc(v[k])
      if e then out[#out + 1] = enc(k) .. ":" .. e end
    end
    return "{" .. table.concat(out, ",") .. "}"
  end
end

-- Parses the JSON subset above (objects, arrays, strings, numbers, true / false); errors on anything else.
local function dec(s)
  local pos = 1
  local function ws() pos = s:find("[^ \t\r\n]", pos) or #s + 1 end
  local function str()
    local out = {}
    pos = pos + 1
    while true do
      local c = s:sub(pos, pos)
      if c == "" then error("end of text") end
      if c == '"' then pos = pos + 1; return table.concat(out) end
      if c == "\\" then pos = pos + 1; c = s:sub(pos, pos) end
      out[#out + 1] = c; pos = pos + 1
    end
  end
  local function value(depth)
    if depth > 6 then error("too deep") end
    ws()
    local c = s:sub(pos, pos)
    if c == "{" or c == "[" then
      local close, t = c == "{" and "}" or "]", {}
      pos = pos + 1; ws()
      if s:sub(pos, pos) == close then pos = pos + 1; return t end
      while true do
        ws()
        local k
        if close == "}" then
          if s:sub(pos, pos) ~= '"' then error("key") end
          k = str(); ws()
          if s:sub(pos, pos) ~= ":" then error("colon") end
          pos = pos + 1
        end
        local v = value(depth + 1)
        if k then t[k] = v else t[#t + 1] = v end
        ws()
        local d = s:sub(pos, pos); pos = pos + 1
        if d == close then return t end
        if d ~= "," then error("comma") end
      end
    elseif c == '"' then return str()
    elseif s:find("^true", pos) then pos = pos + 4; return true
    elseif s:find("^false", pos) then pos = pos + 5; return false
    end
    local num = s:match("^%-?[%d%.]+[eE]?[%+%-]?%d*", pos)
    if not (num and tonumber(num)) then error("value") end
    pos = pos + #num
    return tonumber(num)
  end
  local v = value(0)
  ws()
  if pos <= #s then error("trailing text") end
  return v
end

function L.Export(scope, name)
  local l = L.Get(scope, name)
  if not l then return nil, "missing" end
  return TAG .. enc({ systems = l.systems })
end

function L.Serialize(layout) -- the same text for a layout that is not stored (Profiles.lua puts one into a profile string)
  if type(layout) ~= "table" or type(layout.systems) ~= "table" then return nil end
  return TAG .. enc({ systems = layout.systems })
end

local ANCHOR_TEXT = { rel = true, stack = true } -- (point / relPoint are checked against POINTS)
local POINTS = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 1, CENTER = 1, RIGHT = 1, BOTTOMLEFT = 1, BOTTOM = 1, BOTTOMRIGHT = 1 }
local MAX_OFFSET, MIN_SCALE, MAX_SCALE, MAX_TEXT = 4000, 0.25, 2, 64

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function clamp(v, lo, hi) return math.min(math.max(v, lo), hi) end

-- One imported setting: the value to keep, or nil. Registered systems keep to their settings schema (slider range, dropdown options,
-- checkbox); every number must be finite, a scale is clamped, text is short. Nothing here may reach EM.Place unchecked.
local function setting(entry, k, v)
  local tv = type(v)
  if k == "scale" and entry then -- only a system with a size slider takes a scale
    local has = false
    for _, d in ipairs(entry.settingsSchema or {}) do if d.id == "scale" then has = true end end
    if not has then return nil end
  end
  if k == "scale" or k == "autoScale" then return finite(v) and clamp(v, MIN_SCALE, MAX_SCALE) or nil end
  if tv == "number" and not finite(v) then return nil end
  local def
  for _, s in ipairs(entry and entry.settingsSchema or {}) do if s.id == k then def = s end end
  if def then
    if def.type == "slider" then return tv == "number" and v >= def.min and v <= def.max and v or nil end
    if def.type == "checkbox" then return tv == "boolean" and v or nil end
    if def.type == "dropdown" then
      for _, o in ipairs(def.options or {}) do if o == v then return v end end
      return nil
    end
    return nil
  end
  if tv == "string" then return #v <= MAX_TEXT and v or nil end
  if tv == "number" or tv == "boolean" then return v end
end

-- Returns { systems = ... } with plain values only, or nil, "bad text".
function L.Import(text)
  if type(text) ~= "string" then return nil, "bad text" end
  text = trim(text)
  if text:sub(1, #TAG) ~= TAG then return nil, "bad text" end
  local good, raw = pcall(dec, text:sub(#TAG + 1))
  if not good or type(raw) ~= "table" or type(raw.systems) ~= "table" then return nil, "bad text" end
  local systems = {}
  for key, s in pairs(raw.systems) do
    if type(key) == "string" and type(s) == "table" then
      local c, entry = {}, EM.systems[key]
      for k, v in pairs(s) do
        local tv = type(v)
        if type(k) == "string" and k ~= "x" and k ~= "y" then
          if k == "anchor" then
            if tv == "table" and POINTS[v.point] and POINTS[v.relPoint] then
              local a = { point = v.point, relPoint = v.relPoint, x = 0, y = 0 }
              for _, ak in ipairs({ "x", "y" }) do if finite(v[ak]) then a[ak] = clamp(v[ak], -MAX_OFFSET, MAX_OFFSET) end end
              for ak in pairs(ANCHOR_TEXT) do if type(v[ak]) == "string" and #v[ak] <= MAX_TEXT then a[ak] = v[ak] end end
              c.anchor = a
            end
          elseif tv ~= "table" then
            c[k] = setting(entry, k, v)
          end
        end
      end
      if finite(s.x) and finite(s.y) then c.x, c.y = clamp(s.x, -MAX_OFFSET, MAX_OFFSET), clamp(s.y, -MAX_OFFSET, MAX_OFFSET) end -- both or neither
      systems[key] = c
    end
  end
  return { systems = systems }
end

function L.CreateFromText(name, scope, text)
  name = trim(name)
  if name == "" then return false, "empty name" end
  if not validScope(scope) then return false, "bad scope" end
  local layout = L.Import(text)
  if not layout then return false, "bad text" end
  if nameTaken(name) then return false, "exists" end
  store(scope)[name] = layout
  return true
end

---------------------------------------------------------------- applying a layout
-- A copy of `layout` with every preset anchor turned into a centre offset (EM.Resolve: live screen size, the system's
-- current frame size). Saved layouts keep centre offsets only.
function L.Flatten(layout)
  local flat = deepCopy({ systems = layout.systems })
  for key, s in pairs(flat.systems) do
    if type(s) == "table" and s.anchor then EM.Resolve(key, s) end
  end
  return flat
end

-- Makes `layout` the live state: every registered system gets its entry (missing systems and fields come from Modern),
-- and is applied now or after combat. Preset anchors stay anchors here: EM.Place resolves them when the frame is placed,
-- after its settings are applied, against the screen of that moment.
-- Two steps, so a system placed relative to others (the right bars between the minimap and the micro menu, the bottom stack) finds
-- their layout already loaded: load() fills EM.current, run() places.
local function load(layout, key)
  local base = AFUI.PRESETS[MODERN].systems[key]
  local systems = type(layout) == "table" and type(layout.systems) == "table" and layout.systems or {}
  local mine = systems[key]
  if type(mine) ~= "table" then mine = nil end
  if base or mine then
    local cur = deepCopy(base or {})
    for k, v in pairs(mine or {}) do cur[k] = deepCopy(v) end
    -- saved before the Orientation setting existed: its rows meant horizontal rows (the right bars were 12 rows of one icon)
    if mine and mine.numRows ~= nil and mine.orientation == nil then cur.orientation = "Horizontal" end
    -- a saved centre offset beats the preset anchor, unless the bar was in its automatic position when saved (then the offset is
    -- only a cache: the bar is placed again from the anchor, so a saved layout still follows which bars are shown)
    if mine and mine.x ~= nil and not (mine.auto and AFUI.AutoPlace and AFUI.AutoPlace[key] and cur.anchor) then
      cur.anchor = nil
      cur.autoScale = nil
    end
    EM.current.systems[key] = cur
    return true
  end
end
local function run(key)
  AFUI.RunOutOfCombat(EM.systems[key].run)
  if EM.RefreshOverlay then EM.RefreshOverlay(key) end -- Edit Mode open: the box follows
end
local function applyOne(layout, key) if load(layout, key) then run(key) end end

-- One system back to what the layout says (the settings window's Revert Changes).
function L.ApplySystem(layout, key) applyOne(layout, key) end

function L.Apply(layout)
  local loaded = {}
  for _, key in ipairs(EM.order) do if load(layout, key) then loaded[#loaded + 1] = key end end
  for _, key in ipairs(loaded) do run(key) end
  if AFUI.RestackBars then AFUI.RestackBars() end -- every bar has its final size now
  EM.ClearDirty()
end

-- Saved layouts keep the bar positions of the build that made them. Order 1,2,3 stacked up and 4,5 down the right side
-- (BARS_ORDER = 2) replaced a build that left bars 3 and 4 out of place: once per saved layout set, the five bars go back to the
-- Modern preset's placement and settings (orientation, rows, icons). Everything else in the layout is kept.
-- shortcut: moved bars lose their custom spot once; the old placement was the bug, bump BARS_ORDER if it changes again.
local BARS_ORDER, BAR_KEYS = 2, { "main", "bottomleft", "bottomright", "right", "right2" }
function L.MigrateBars()
  local base = AFUI.PRESETS and AFUI.PRESETS[MODERN] and AFUI.PRESETS[MODERN].systems
  if not base then return end
  for _, scope in ipairs({ "char", "account" }) do
    local holder = scope == "char" and (type(AztraForeverUICharDB) == "table" and AztraForeverUICharDB)
      or (type(AztraForeverUIDB) == "table" and AztraForeverUIDB)
    if holder and (holder.barsOrder or 0) < BARS_ORDER then
      for _, layout in pairs(store(scope)) do
        if type(layout) == "table" and type(layout.systems) == "table" then
          for _, key in ipairs(BAR_KEYS) do if base[key] then layout.systems[key] = deepCopy(base[key]) end end
        end
      end
      holder.barsOrder = BARS_ORDER
    end
  end
end

function L.ApplyActive() L.Apply((L.GetActive())) end

-- The screen changed size (resolution, UI scale): nothing may stay off it. A saved layout is re-applied, so preset
-- anchors re-resolve against the new size; unsaved edits are kept and every system is re-placed (EM.Place resolves a
-- pending anchor and clamps the offset onto the screen).
local function screenChanged()
  if not EM.dirty then return L.ApplyActive() end
  for _, key in ipairs(EM.order) do
    EM.systems[key].run()
    if EM.RefreshOverlay then EM.RefreshOverlay(key) end
  end
end
for _, e in ipairs(AFUI.SCREEN_EVENTS) do AFUI.On(e, function() AFUI.RunOutOfCombat(screenChanged) end) end

AFUI.RegisterModule("Layouts", { OnLogin = function() L.MigrateBars(); L.ApplyActive() end })
