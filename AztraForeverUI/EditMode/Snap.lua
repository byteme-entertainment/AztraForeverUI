-- Snapping for Edit Mode. Rects are centre-based {x, y, w, h} in UIParent units, centred on the screen centre.
-- Targets per axis (Forever's EditModeMagnetismManager, docs/forever-ref/editmode.md section 5): the screen's edges and
-- centre, grid lines (only when gridSize > 0), and the edges and centres of the other rects. Any side or centre of the
-- dragged rect may snap to any target within `threshold` (screen pixels, Forever uses 8). The first of equal distances
-- wins in the order other rects, screen, grid.
AFUI = AFUI or {}

-- Returns the snapped centre and, when something snapped, the target: { kind = "frame"|"screen"|"grid", pos, i }.
local function axis(c, size, grid, threshold, centres, sizes, screen)
  local best, bestD, bestTarget
  local mine = { c - size / 2, c, c + size / 2 }
  local function try(delta, target)
    local d = math.abs(delta)
    if d <= threshold and (not bestD or d < bestD) then best, bestD, bestTarget = delta, d, target end
  end
  for i = 1, #centres do
    local oc, os = centres[i], sizes[i]
    for _, pos in ipairs({ oc - os / 2, oc, oc + os / 2 }) do
      for _, m in ipairs(mine) do try(pos - m, { kind = "frame", pos = pos, i = i }) end
    end
  end
  if screen then
    for _, pos in ipairs({ -screen / 2, 0, screen / 2 }) do
      for _, m in ipairs(mine) do try(pos - m, { kind = "screen", pos = pos }) end
    end
  end
  if grid and grid > 0 then
    for _, m in ipairs(mine) do
      local pos = math.floor(m / grid + 0.5) * grid
      try(pos - m, { kind = "grid", pos = pos })
    end
  end
  return c + (best or 0), bestTarget
end

local function clamp(c, size, screen)
  local limit = (screen - size) / 2
  if limit <= 0 then return 0 end
  return math.min(math.max(c, -limit), limit)
end

-- Returns x, y and the preview lines of the targets snapped to: { axis = "x"|"y", kind, pos, lo, hi }. A "frame" line
-- spans both rects along the other axis (lo..hi); screen and grid lines run the full screen.
function AFUI.Snap(rect, others, gridSize, threshold)
  others = others or {}
  local xs, xw, ys, yh = {}, {}, {}, {}
  for i, o in ipairs(others) do xs[i], xw[i], ys[i], yh[i] = o.x, o.w, o.y, o.h end
  local screen = others.screen
  local t = threshold or 8
  local x, tx = axis(rect.x, rect.w, gridSize, t, xs, xw, screen and screen.w)
  local y, ty = axis(rect.y, rect.h, gridSize, t, ys, yh, screen and screen.h)
  if screen then
    x = clamp(x, rect.w, screen.w)
    y = clamp(y, rect.h, screen.h)
  end
  local lines = {}
  local function add(target, ax, cOther, sizeOther)
    if not target then return end
    local line = { axis = ax, kind = target.kind, pos = target.pos }
    if target.kind == "frame" then
      local o = others[target.i]
      local oc, os = o.y, o.h
      if ax == "y" then oc, os = o.x, o.w end
      line.lo = math.min(oc - os / 2, cOther - sizeOther / 2)
      line.hi = math.max(oc + os / 2, cOther + sizeOther / 2)
    end
    lines[#lines + 1] = line
  end
  add(tx, "x", y, rect.h)
  add(ty, "y", x, rect.w)
  return x, y, lines
end
