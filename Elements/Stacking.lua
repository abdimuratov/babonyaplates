local ADDON, ns = ...

-- Own plate stacker (the engine's stacking bitfield cannot tell name-only plates from bar plates, so Core turns it off).
-- Every INTERVAL: measure each participating plate's visible rect at offset 0, sort bottom to top, push each plate
-- up until it clears the overlapping plates below it, and ease the applied offset (pf.stackOff) toward that target.
-- Units: "screen units" = region coordinates * effective scale, so plates with different scales compare consistently.
-- Only our root and hit frame move (ns.PlaceRoot); Blizzard's plate never does.
local issecretvalue = issecretvalue or function() return false end
local pairs, next, huge, min, max, abs = pairs, next, math.huge, math.min, math.max, math.abs
local sort = table.sort

local INTERVAL, EASE, GAP = 0.03, 0.4, 2
local list, listN = {}, 0   -- reused every tick, no per-tick allocations
local uL, uB, uR, uT        -- union rect accumulator (root coordinate space)

local function Num(v) return v ~= nil and not issecretvalue(v) end

-- Adds a GetRect() result to the union; false when it is missing or secret.
local function AddRect(l, b, w, h)
  if not (Num(l) and Num(b) and Num(w) and Num(h)) then return false end
  uL, uB, uR, uT = min(uL, l), min(uB, b), max(uR, l + w), max(uT, b + h)
  return true
end

-- Visible rect at offset 0 into pf.sL/sR/sB/sT (screen units); false when nothing measurable.
local function Measure(pf)
  uL, uB, uR, uT = huge, huge, -huge, -huge
  local any = false
  if pf.showBar then any = AddRect(pf.health:GetRect()) or any end
  if pf.showPower and pf.hasPower then any = AddRect(pf.power:GetRect()) or any end
  if pf.showName then
    if AddRect(pf.name:GetRect()) then
      any = true
    else -- name geometry can be secret: assume a text line above the bar
      local l, b, w, h = pf.health:GetRect()
      if Num(l) and Num(b) and Num(w) and Num(h) then
        local P = ns.P
        any = AddRect(l, b + h + P.name.pos.y, w, P.name.size + 2) or any
      end
    end
  end
  if pf.combo:IsShown() then AddRect(pf.combo:GetRect()) end
  if not any then return false end
  local rs, off = pf.root:GetEffectiveScale(), pf.stackOff or 0
  pf.sL, pf.sR = uL * rs, uR * rs
  pf.sB, pf.sT = uB * rs - off, uT * rs - off -- the applied offset is still in the measured rect
  pf.sMid = (pf.sB + pf.sT) / 2
  return true
end

local function Participates(pf)
  local S = ns.P.stacking
  if pf.showBar or pf.showPower then return S.withBars end
  return pf.showName and S.nameOnly
end

local function ByHeight(a, b) return a.sMid < b.sMid end

local function Ease(pf)
  if pf.hitDirty then ns.ApplyHitTest(pf) end -- hit area could not follow in combat
  local tgt, off = pf.stackTarget or 0, pf.stackOff or 0
  if tgt == off and (off == 0 or pf.stackRS == pf.root:GetEffectiveScale()) then return end
  off = off + (tgt - off) * EASE
  if abs(tgt - off) < 0.5 then off = tgt end
  pf.stackOff = off
  ns.PlaceRoot(pf)
end

local function Tick()
  if next(ns.plates) == nil then return end
  local n = 0
  for _, pf in pairs(ns.plates) do
    if Participates(pf) and pf.root:IsVisible() and Measure(pf) then
      n = n + 1
      list[n] = pf
    end
    pf.stackTarget = 0
  end
  for i = n + 1, listN do list[i] = nil end
  listN = n
  if n >= 2 then
    sort(list, ByHeight)
    for i = 2, n do
      local pf, tgt = list[i], 0
      for j = 1, i - 1 do
        local q = list[j]
        if q.sL < pf.sR and pf.sL < q.sR then -- horizontal overlap: clear the placed top of q
          tgt = max(tgt, q.sT + q.stackTarget + GAP - pf.sB)
        end
      end
      pf.stackTarget = tgt
    end
  end
  for _, pf in pairs(ns.plates) do Ease(pf) end
end

local acc = 0
CreateFrame("Frame"):SetScript("OnUpdate", function(_, dt)
  acc = acc + dt
  if acc < INTERVAL then return end
  acc = 0
  Tick()
end)

ns.RegisterElement{
  remove = function(pf) pf.stackOff, pf.stackTarget = 0, 0 end, -- the next ns.PlaceRoot starts from zero
}
