-- "Organized" nameplates (setting Plate stacking = Organized): in a crowd the plates sit in clean rows and columns of a screen-aligned grid, whatever the camera angle.
-- Two parts. NG.Solve is a pure function (no frames): natural plate rectangles in, grid positions out, with a little state for hysteresis. The engine below measures one
-- invisible GHOST frame of ours per plate (anchored to the plate at offset 0, so it never moves; the Blizzard plate frames are never measured: the client refuses it),
-- runs the solver a few times a second and moves OUR skin frame by an offset. Only our own frames are touched, so it works in combat.
-- Layout of a crowd (the plates of one cluster, a cluster = plates that overlap or touch at their natural spots):
--   1. rows: plates sorted by natural y are cut into rows with a dynamic programme (cost = vertical scatter inside a row + the horizontal spreading the row needs +
--      a pull toward a rectangle of aspect NG.ASPECT), so a 5 x 5 formation comes out 5 x 5 at any angle;
--   2. inside a row the plates are spread to the column pitch (plate width + gap) with weighted isotonic regression (pool adjacent violators): minimal total displacement;
--      the rows are spread to the row pitch the same way;
--   3. the result is snapped to ONE screen-wide lattice (column pitch x row pitch), so rows and columns align across rows and even across clusters, and a plate keeps
--      its cell (is "sticky") until its ideal spot is more than NG.HYST of a cell away: nothing moves under small noise or a slow camera turn;
--   4. cells shared by several plates are resolved per lattice row (isotonic again), the TARGET stays exactly where it is and the rest routes around it, no plate moves
--      more than the cap from its natural spot (over the cap it overlaps rather than detach) and none leaves the screen.
AFUI = AFUI or {}
local NG = { ops = 0 }
AFUI.NameplateGrid = NG

NG.ASPECT = 4 -- wanted width : height of a crowd's rectangle (5 x 5 plates of a 133 x 29 pitch are 4 : 1)
NG.RECT = 1 -- weight of the pull toward the wanted row length (in (column pitch)^2 per plate of difference, squared)
NG.LADDER = 2 -- rows closer than this many row pitches form one ladder of equally spaced rows
NG.HYST = 0.6 -- a plate keeps its cell until its ideal spot is this many cells away
NG.NEAR_X, NG.NEAR_Y, NG.ACTIVE_GROW = 1.2, 2, 1.25 -- two plates are one cluster when they are within 1.2 cells sideways and 2 rows up or down (the cluster range); x1.25 once arranged, so a cluster does not flicker at its edge
NG.SOLVE_DT = 0.1 -- seconds between solves
NG.APPLY_EPS = 2 -- px: an offset is applied when it changed this much (or 0.5 px when the plate's natural spot did not move)
NG.MIN_CLUSTER, NG.MIN_ACTIVE = 3, 2

local PIN = 1e4 -- weight of the pinned (target) plate
local floor, abs, huge, sqrt = math.floor, math.abs, math.huge, math.sqrt
local function round(v) return floor(v + 0.5) end

-- weighted isotonic regression, in place into out (pool adjacent violators)
local bv, bw, bn = {}, {}, {}
local function pav(p, wt, k, out)
  local nb = 0
  for i = 1, k do
    nb = nb + 1; bv[nb], bw[nb], bn[nb] = p[i], wt[i], 1
    while nb > 1 and bv[nb - 1] > bv[nb] do
      local w = bw[nb - 1] + bw[nb]
      bv[nb - 1] = (bv[nb - 1] * bw[nb - 1] + bv[nb] * bw[nb]) / w
      bw[nb - 1] = w; bn[nb - 1] = bn[nb - 1] + bn[nb]; nb = nb - 1
    end
  end
  local i = 1
  for b = 1, nb do for _ = 1, bn[b] do out[i] = bv[b]; i = i + 1 end end
end

-- Positions xs[1..k] (ascending) of items with widths ws, moved the least (sum of squares) so that neighbours are (w1 + w2) / 2 + gap apart; pinned items do not move.
local P, WT, OFF = {}, {}, {}
local function spread(xs, ws, pn, k, gap, out)
  local off = 0
  for i = 1, k do
    if i > 1 then off = off + (ws[i - 1] + ws[i]) / 2 + gap end
    P[i] = xs[i] - off; WT[i] = pn[i] and PIN or 1; OFF[i] = off
  end
  pav(P, WT, k, out)
  for i = 1, k do out[i] = out[i] + OFF[i] end
  NG.ops = NG.ops + k
end

local function cmpY(a, b) -- top first
  if a.y ~= b.y then return a.y > b.y end
  if a.x ~= b.x then return a.x < b.x end
  return a.id < b.id
end
local function cmpX(a, b)
  if a.x ~= b.x then return a.x < b.x end
  return a.id < b.id
end
local function cmpCell(a, b)
  if a.by ~= b.by then return a.by < b.by end
  if a.bx ~= b.bx then return a.bx < b.bx end
  return a.id < b.id
end

-- scratch (nothing below allocates once the tables have grown to the crowd's size)
local SX, SW, SP, SO = {}, {}, {}, {}
local SC, DP, BACK = {}, {}, {}
local RS, RE, RY, RPIN, RH, ROUT, OFFQ = {}, {}, {}, {}, {}, {}, {}
local MEM, MX, MW, MP, MO, OFFX, RSTART = {}, {}, {}, {}, {}, {}, {}
local PAR, CN, CCOUNT, LISTS, CLEN, ARR = {}, {}, {}, {}, {}, {}
local GX, GW, GP, GO, GI = {}, {}, {}, {}, {}

local function find(i) while PAR[i] ~= i do PAR[i] = PAR[PAR[i]]; i = PAR[i] end; return i end

-- the ideal (continuous) positions it.ix, it.iy of the plates L[1..m] of one cluster: rows by dynamic programme, columns and rows spread to their pitch
local function ideal(L, m, cfg)
  local gap, px, py = cfg.gap, cfg.w + cfg.gap, cfg.h + cfg.gap
  table.sort(L, cmpY)
  local cmax = math.max(2, math.min(m, floor(cfg.sw * 0.8 / px)))
  local cstar = sqrt(m * NG.ASPECT * py / px)
  local rect = NG.RECT * px * px
  for a = 1, m do
    local k, sumW, sumWY, sumWY2 = 0, 0, 0, 0
    for b = a, math.min(m, a + cmax - 1) do
      local it = L[b]
      local j = k
      while j >= 1 and SX[j] > it.x do SX[j + 1], SW[j + 1], SP[j + 1] = SX[j], SW[j], SP[j]; j = j - 1 end
      SX[j + 1], SW[j + 1], SP[j + 1] = it.x, it.w, it.isTarget and true or false
      k = k + 1
      local wy = it.isTarget and PIN or 1
      sumW = sumW + wy; sumWY = sumWY + wy * it.y; sumWY2 = sumWY2 + wy * it.y * it.y
      spread(SX, SW, SP, k, gap, SO)
      local hc = 0
      for i = 1, k do local d = SO[i] - SX[i]; hc = hc + d * d end
      local vc = sumWY2 - sumWY * sumWY / sumW
      if vc < 0 then vc = 0 end
      local dm = k - cstar
      SC[(a - 1) * cmax + (b - a + 1)] = hc + vc + rect * dm * dm
    end
  end
  DP[0] = 0
  for j = 1, m do
    local best, bl = huge, 1
    for len = 1, math.min(cmax, j) do
      local c = DP[j - len] + SC[(j - len) * cmax + len]
      if c < best then best, bl = c, len end
    end
    DP[j], BACK[j] = best, bl
  end
  local R, j = 0, m
  while j > 0 do R = R + 1; RE[R] = j; RS[R] = j - BACK[j] + 1; j = j - BACK[j] end
  -- RS/RE hold the rows bottom first: flip so row 1 is the top one
  for r = 1, floor(R / 2) do RS[r], RS[R + 1 - r] = RS[R + 1 - r], RS[r]; RE[r], RE[R + 1 - r] = RE[R + 1 - r], RE[r] end
  
  -- columns of every row
  for r = 1, R do
    local k, sumW, sumWY, pin, hmax = 0, 0, 0, false, cfg.h
    for b = RS[r], RE[r] do
      local it = L[b]
      k = k + 1; MEM[k] = it
      if it.h > hmax then hmax = it.h end
      local wy = it.isTarget and PIN or 1
      sumW = sumW + wy; sumWY = sumWY + wy * it.y
      if it.isTarget then pin = true end
    end
    for i = k + 1, #MEM do MEM[i] = nil end
    table.sort(MEM, cmpX)
    for i = 1, k do MX[i], MW[i], MP[i] = MEM[i].x, MEM[i].w, MEM[i].isTarget and true or false end
    spread(MX, MW, MP, k, gap, MO)
    -- plates less than LADDER pitches apart close up into one block without holes (fitted to where they were; on the target when it is in the block)
    local i, e0 = 1, 0
    while i <= k do
      local e = i
      while e < k and MO[e + 1] - MO[e] <= NG.LADDER * px do e = e + 1 end
      if i == 1 then e0 = e end -- the first block's last plate: it is the whole row when e0 == k
      if e > i then
        local off, sum, pinAt = 0, 0, nil
        for q = i, e do
          if q > i then off = off + (MW[q - 1] + MW[q]) / 2 + gap end
          OFFX[q] = off; sum = sum + MO[q] - off
          if MP[q] then pinAt = q end
        end
        local a = pinAt and MO[pinAt] - OFFX[pinAt] or sum / (e - i + 1)
        for q = i, e do MO[q] = a + OFFX[q] end
      end
      i = e + 1
    end
    for q = 1, k do MEM[q].ix = MO[q] end
    RY[r], RPIN[r], RH[r] = -sumWY / sumW, pin, hmax -- RY holds -y so the ladder below ascends
    RSTART[r] = (k >= 2 and not pin and e0 == k) and MO[1] or false -- a plain row of one block: its left edge
  end
  for i = R + 1, #RY do RY[i] = nil end
  -- plain rows start in one column (the rows of a crowd are as long as the crowd is wide, give or take a plate: the left edge is what the eye aligns)
  local n0, s0 = 0, 0
  for r = 1, R do if RSTART[r] then n0 = n0 + 1; s0 = s0 + RSTART[r] end end
  if n0 > 1 then
    s0 = s0 / n0
    for r = 1, R do
      if RSTART[r] and abs(RSTART[r] - s0) <= NG.LADDER * px * 0.75 then
        local d = s0 - RSTART[r]
        for b = RS[r], RE[r] do L[b].ix = L[b].ix + d end
      end
    end
  end
  spread(RY, RH, RPIN, R, gap, ROUT)
  -- rows that are close (within LADDER pitches) become one equally spaced ladder: fitted to the ideal rows, on the screen lattice (or on the target's own row when it is in it)
  local r = 1
  while r <= R do
    local e = r
    while e < R and ROUT[e + 1] - ROUT[e] <= NG.LADDER * py do e = e + 1 end
    local pinAt, sum, off = nil, 0, 0
    for q = r, e do
      if q > r then off = off + (RH[q - 1] + RH[q]) / 2 + gap end -- the target's row is a little taller
      OFFQ[q] = off
      sum = sum + ROUT[q] - off
      if RPIN[q] then pinAt = q end
    end
    local u0 = pinAt and ROUT[pinAt] - OFFQ[pinAt] or round(sum / (e - r + 1) / py) * py
    for q = r, e do
      local y = -(u0 + OFFQ[q])
      for b = RS[q], RE[q] do L[b].iy, L[b].free = y, pinAt ~= nil end
    end
    r = e + 1
  end
end

-- Solve: items[1..n] = { x, y, w, h, isTarget, id } (the plates' natural centres and sizes, screen px, id a number); cfg = { w, h (cell size), gap, cap, margin, sw, sh };
-- st = the state kept between solves ({}). Sets on every item: arr (arranged), tx, ty (the wanted centre) and dx, dy (tx - x, ty - y); not arranged = left where it is (0, 0).
function NG.Solve(items, n, cfg, st)
  st.t = st.t or {}
  st.gen = (st.gen or 0) + 1
  local gen, T = st.gen, st.t
  local gap, px, py = cfg.gap, cfg.w + cfg.gap, cfg.h + cfg.gap
  NG.ops = 0
  for i = 1, n do local it = items[i]; it.arr, it.tx, it.ty, it.dx, it.dy = false, nil, nil, 0, 0; PAR[i] = i end
  for i = 1, n - 1 do
    local a = items[i]
    for j = i + 1, n do
      local b = items[j]
      local f = (T[a.id] or T[b.id]) and NG.ACTIVE_GROW or 1
      if abs(a.x - b.x) < ((a.w + b.w) / 2 + gap) * NG.NEAR_X * f and abs(a.y - b.y) < ((a.h + b.h) / 2 + gap) * NG.NEAR_Y * f then
        local ra, rb = find(i), find(j)
        if ra ~= rb then PAR[rb] = ra end
      end
    end
  end
  local nc = 0
  for i = 1, n do CN[i] = 0 end
  for i = 1, n do
    local r = find(i)
    if CN[r] == 0 then nc = nc + 1; CN[r] = nc; CCOUNT[nc] = 0; LISTS[nc] = LISTS[nc] or {}; CLEN[nc] = CLEN[nc] or 0 end
    local c = CN[r]
    CCOUNT[c] = CCOUNT[c] + 1; LISTS[c][CCOUNT[c]] = items[i]
  end
  local ng, target = 0, nil
  for c = 1, nc do
    local L, m, active = LISTS[c], CCOUNT[c], false
    for i = m + 1, CLEN[c] do L[i] = nil end
    CLEN[c] = m
    for i = 1, m do if T[L[i].id] then active = true end end
    if m >= (active and NG.MIN_ACTIVE or NG.MIN_CLUSTER) then
      ideal(L, m, cfg)
      for i = 1, m do
        local it = L[i]
        it.arr = true
        if it.isTarget then it.bx, it.by, target = it.x, it.y, it
        else
          local s = T[it.id]
          if s and abs(it.ix - s.x) <= NG.HYST * px and abs(it.iy - s.y) <= NG.HYST * py then it.bx, it.by = s.x, s.y
          else it.bx, it.by = round(it.ix / px) * px, it.iy end -- the ladder's rows are already on the lattice (or on the target's row)
          ng = ng + 1; ARR[ng] = it
        end
      end
    end
  end
  for i = ng + 1, #ARR do ARR[i] = nil end
  -- cells shared or crowded: per lattice row, the target is an obstacle
  table.sort(ARR, cmpCell)
  local i = 1
  while i <= ng do
    local y0, k, j = ARR[i].by, 0, i
    while j <= ng and ARR[j].by - y0 < py * 0.5 do j = j + 1 end -- ARR[i..j-1] is one row
    local obstacle = target and abs(y0 - target.y) < (target.h + cfg.h) / 2 + gap - 0.5 -- (the rows next to the target's row sit exactly that far off)
    local placed = not obstacle
    for q = i, j - 1 do
      local it = ARR[q]
      if not placed and it.bx > target.x then k = k + 1; GX[k], GW[k], GP[k], GI[k] = target.x, target.w, true, false; placed = true end
      k = k + 1; GX[k], GW[k], GP[k], GI[k] = it.bx, it.w, false, it
    end
    if not placed then k = k + 1; GX[k], GW[k], GP[k], GI[k] = target.x, target.w, true, false end
    spread(GX, GW, GP, k, gap, GO)
    if not obstacle then
      local lo, hi = cfg.margin + cfg.w / 2, cfg.sw - cfg.margin - cfg.w / 2
      for q = 1, k do GO[q] = round(GO[q] / px) * px end
      while GO[k] > hi and GO[1] - px >= lo do for q = 1, k do GO[q] = GO[q] - px end end
      while GO[1] < lo and GO[k] + px <= hi do for q = 1, k do GO[q] = GO[q] + px end end
    end
    for q = 1, k do if GI[q] then GI[q].tx, GI[q].ty = GO[q], y0 end end
    i = j
  end
  -- cap, screen, state
  local lo, hi = cfg.margin + cfg.h / 2, cfg.sh - cfg.margin - cfg.h / 2
  for q = 1, ng do
    local it = ARR[q]
    local tx, ty = it.tx, it.ty
    if tx - it.x > cfg.cap then tx = it.x + cfg.cap elseif it.x - tx > cfg.cap then tx = it.x - cfg.cap end
    if ty - it.y > cfg.cap then ty = it.y + cfg.cap elseif it.y - ty > cfg.cap then ty = it.y - cfg.cap end
    local xl, xh = cfg.margin + it.w / 2, cfg.sw - cfg.margin - it.w / 2
    if tx < xl then tx = xl elseif tx > xh then tx = xh end
    if ty < lo then ty = lo elseif ty > hi then ty = hi end
    it.tx, it.ty = tx, ty
  end
  if target then target.tx, target.ty = target.x, target.y end
  for q = 1, n do
    local it = items[q]
    if it.arr then
      it.dx, it.dy = it.tx - it.x, it.ty - it.y
      local s = T[it.id]
      if not s then s = {}; T[it.id] = s end
      s.x, s.y, s.g = it.tx, it.ty, gen
    end
  end
  for id, s in pairs(T) do if s.g ~= gen then T[id] = nil end end
  return nc
end

---------------------------------------------------------------------------------------------- the engine
-- One ghost frame per plate (ours: anchored CENTER to the plate frame at offset 0, 1 x 1), measured with AFUI.SafeMeasure; the plate frame itself and everything of Blizzard's
-- stays unmeasured. The skin frame (the plate's whole art) is moved by NG.Place. If the ghost cannot be measured the engine switches itself off for good (NG.broken) and
-- every plate sits at its natural spot again; Plate stacking then falls back to the client's own stacking (Nameplates.lua WantedCVars).
local list, items, ST, CFG = {}, {}, {}, {}
local driver, acc, serial = nil, 0, 0
NG.broken = false

function NG.Mode() return not AFUI.IS_243 and AFUI.GetSetting("nameplateStacking", "organized") == "organized" end -- 2.4.3 has no plate unit API: nothing to arrange
function NG.Active() return NG.Mode() and not NG.broken end

function NG.Place(s, dx, dy)
  s.ox, s.oy = dx, dy
  s.frame:ClearAllPoints()
  s.frame:SetPoint("CENTER", s.host, "CENTER", dx, dy)
end

local function setDriver()
  if not driver then return end
  local want = NG.Active() and (#list >= NG.MIN_CLUSTER or NG.anyOffset())
  if want then driver:Show() else driver:Hide() end
end
function NG.anyOffset() for _, s in ipairs(list) do if s.ox ~= 0 or s.oy ~= 0 then return true end end return false end

function NG.Add(s)
  if not NG.Active() then return end
  if s.ghostOn then -- the same skin got a new unit
    NG.Place(s, 0, 0); s.gtx, s.gty, s.lnx = nil, nil, nil
    if ST.t then ST.t[s.gid] = nil end
    return
  end
  if not s.ghost then
    local g = CreateFrame("Frame", nil, s.host)
    g:SetWidth(1); g:SetHeight(1); g:SetPoint("CENTER", s.host, "CENTER", 0, 0)
    g:EnableMouse(false)
    s.ghost = g
    serial = serial + 1; s.gid = serial
    s.gi = { id = s.gid }
  end
  s.ghostOn, s.ox, s.oy = true, 0, 0
  list[#list + 1] = s
  NG.Place(s, 0, 0)
  if not driver then
    driver = CreateFrame("Frame")
    NG.driver = driver
    driver:Hide()
    driver:SetScript("OnUpdate", function(_, dt) NG.Step(dt) end)
  end
  setDriver()
end

function NG.Remove(s)
  if not s.ghostOn then return end
  s.ghostOn = false
  for i = #list, 1, -1 do if list[i] == s then table.remove(list, i) end end
  if ST.t then ST.t[s.gid] = nil end
  NG.Place(s, 0, 0)
  s.gtx, s.gty = nil, nil
  setDriver()
end

-- mode off / broken / settings: every plate back to its natural spot at once, state forgotten
function NG.Reset()
  for _, s in ipairs(list) do s.gtx, s.gty = nil, nil; if s.ox ~= 0 or s.oy ~= 0 then NG.Place(s, 0, 0) end end
  ST.t = nil
  acc = 0
  setDriver()
end

-- the settings changed: plates added while the mode was off get their ghost now, a mode switched off puts every plate back
function NG.Refresh()
  if NG.Active() then
    local Nm = AFUI.Nameplates
    for _, s in ipairs(Nm and Nm.Skins and Nm.Skins() or {}) do if s.unit and not s.ghostOn then NG.Add(s) end end
  else
    for _, s in ipairs(list) do s.ghostOn = false end
    NG.Reset()
    list = {}
    setDriver()
  end
  NG.Reset()
end

function NG.Break(why)
  if NG.broken then return end
  NG.broken, NG.why = true, why
  NG.Refresh()
  if AFUI.Nameplates and AFUI.Nameplates.ApplyCVars then AFUI.Nameplates.ApplyCVars() end
end

-- px in a plate's own units -> UIParent units
local function measure(s)
  local g = s.ghost
  local cx, cy = AFUI.SafeMeasure(g, "GetCenter")
  if cx == nil then
    if AFUI.MeasureBlocked(g) then NG.Break("the ghost frame cannot be measured: " .. tostring(AFUI.MeasureReport and AFUI.MeasureReport.first)) end
    return
  end
  return cx, cy
end

-- Natural spots -> solver -> wanted spots (s.gtx, s.gty in UIParent units, nil = natural)
local function solve()
  local Nm = AFUI.Nameplates
  local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
  local ues = AFUI.SafeMeasure(UIParent, "GetEffectiveScale") or 1
  local n = 0
  local cw, ch
  for _, s in ipairs(list) do
    if s.unit and s.host:IsShown() then
      local cx, cy = measure(s)
      if NG.broken then return end
      local es = cx and AFUI.SafeMeasure(s.ghost, "GetEffectiveScale")
      if cx and es then
        local f = es / ues
        s.gfac = f
        n = n + 1
        local it = s.gi
        items[n] = it
        it.x, it.y, it.w, it.h, it.isTarget = cx * f, cy * f, Nm.PLATE_W * s.k * f, Nm.CELL_H * s.k * f, s.isTarget and true or false
        it.s = s
        if not s.isTarget then cw, ch = it.w, it.h end
      else s.gtx, s.gty = nil, nil end
    else s.gtx, s.gty = nil, nil end
  end
  for i = n + 1, #items do items[i] = nil end
  if n == 0 then return end
  if not cw then cw, ch = items[1].w, items[1].h end
  CFG.w, CFG.h, CFG.gap = cw, ch, AFUI.GetSetting("nameplateGridGap", 4)
  CFG.cap, CFG.margin, CFG.sw, CFG.sh = AFUI.GetSetting("nameplateGridShift", 160), 8, uw, uh
  NG.Solve(items, n, CFG, ST)
  for i = 1, n do local it = items[i]; if it.arr then it.s.gtx, it.s.gty = it.tx, it.ty else it.s.gtx, it.s.gty = nil, nil end end
end

-- every frame: the plate's offset so that the skin sits on its wanted spot, whatever the client did with the plate since (the plate moves with its unit, the skin stays put)
local function follow()
  local snap = AFUI.Nameplates and AFUI.Nameplates.Snap or function(_, v) return v end
  for _, s in ipairs(list) do
    if s.unit and s.host:IsShown() then
      local cx, cy = measure(s)
      if NG.broken then return end
      local f = s.gfac
      if cx and f then
        local nx, ny = cx * f, cy * f
        local still = s.lnx and abs(nx - s.lnx) < 0.01 and abs(ny - s.lny) < 0.01
        s.lnx, s.lny = nx, ny
        local wx, wy = 0, 0
        if s.gtx then wx, wy = (s.gtx - nx) / f, (s.gty - ny) / f end
        wx, wy = snap(s.px, wx), snap(s.px, wy)
        local d = math.max(abs(wx - s.ox), abs(wy - s.oy))
        if d >= NG.APPLY_EPS or (d >= 0.5 and still) or (not s.gtx and d > 0) then NG.Place(s, wx, wy) end
      end
    end
  end
end

function NG.Step(dt)
  if not NG.Active() then return setDriver() end
  acc = acc + dt
  if acc >= NG.SOLVE_DT or not ST.t then
    acc = 0
    solve()
    if NG.broken then return end
    follow()
    return setDriver() -- (a crowd that has dissolved lets the OnUpdate sleep)
  end
  follow()
end

function NG.Skins() return list end
