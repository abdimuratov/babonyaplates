local ADDON, ns = ...

local GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit
local UnitExists = UnitExists

-- Frame comparison instead of UnitIsUnit (secret-safe). active=false restores the plate's normal look.
local function Apply(pf, active, hasTarget)
  local P = ns.P
  local h, bd = P.highlight, P.bar.border
  local on = active and h.scaleEnabled
  pf.root:SetScale(P.bar.scale * (on and h.scale or 1))
  pf.root:SetAlpha((hasTarget and not active and h.fadeEnabled) and h.fadeAlpha or 1)
  local col = (active and h.borderEnabled) and h.borderColor or bd.color
  pf.border:SetBackdropBorderColor(col.r, col.g, col.b, col.a)
end

local function Update(pf)
  if pf.isPreview or not pf.unit then return end
  local tp = GetNamePlateForUnit("target")
  Apply(pf, tp ~= nil and tp == pf.plate, UnitExists("target") and true or false)
end

local function UpdateAll()
  for _, pf in pairs(ns.plates) do Update(pf) end
end

ns.RegisterElement{
  style = Update,
  update = Update,
  remove = function(pf) Apply(pf, false, false) end,
  events = { PLAYER_TARGET_CHANGED = UpdateAll },
}
