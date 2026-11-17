local ADDON, ns = ...

local issecretvalue = issecretvalue or function() return false end
local UnitPower, UnitPowerMax, UnitClass = UnitPower, UnitPowerMax, UnitClass
local GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit
local COMBO = Enum.PowerType.ComboPoints
local PREVIEW_MAX, PREVIEW_POINTS = 5, 3

local _, class = UnitClass("player")
local isComboClass = class == "ROGUE" or class == "DRUID"

local function Layout(pf, max)
  local c = ns.P.combo
  local f = pf.combo
  pf.comboMax = max
  for i = 1, max do
    local t = f.points[i]
    if not t then
      t = f:CreateTexture(nil, "ARTWORK")
      f.points[i] = t
    end
    t:SetTexture(ns.Fetch("statusbar", c.texture))
    t:SetSize(c.size, c.size)
    t:ClearAllPoints()
    t:SetPoint("LEFT", f, "LEFT", (i - 1) * (c.size + c.spacing), 0)
    t:Show()
  end
  for i = max + 1, #f.points do f.points[i]:Hide() end
  f:SetSize(math.max(1, max * c.size + (max - 1) * c.spacing), c.size)
end

local function IsTarget(pf)
  local tp = GetNamePlateForUnit("target")
  return tp ~= nil and tp == pf.plate
end

local function Update(pf)
  local f = pf.combo
  if not f then return end
  local c = ns.P.combo
  local points, max
  if pf.isPreview then
    points, max = PREVIEW_POINTS, PREVIEW_MAX
  elseif isComboClass and c.enabled and pf.unit and pf.showBar and IsTarget(pf) then
    max, points = UnitPowerMax("player", COMBO), UnitPower("player", COMBO)
    if issecretvalue(max) or issecretvalue(points) then max, points = nil, nil end
  end
  if not max or max <= 0 or not c.enabled or (points == 0 and c.hideWhenZero) then
    f:Hide()
    return
  end
  if max ~= pf.comboMax then Layout(pf, max) end
  for i = 1, max do
    local col = i <= points and c.filled or c.empty
    f.points[i]:SetVertexColor(col.r, col.g, col.b, col.a)
  end
  f:Show()
end

local function UpdateAll()
  for _, pf in pairs(ns.plates) do Update(pf) end
end

ns.RegisterElement{
  create = function(pf)
    pf.combo = CreateFrame("Frame", nil, pf.root)
    pf.combo:EnableMouse(false)
    pf.combo.points = {}
    pf.combo:Hide()
  end,
  style = function(pf)
    local max = pf.isPreview and PREVIEW_MAX or UnitPowerMax("player", COMBO)
    if issecretvalue(max) or not max or max < 1 then max = pf.comboMax or 5 end
    Layout(pf, max)
    ns.ApplyPos(pf.combo, pf.health, ns.P.combo.pos)
    Update(pf)
  end,
  update = Update,
  remove = function(pf) pf.combo:Hide() end,
  events = {
    PLAYER_TARGET_CHANGED = UpdateAll,
    COMBO_TARGET_CHANGED = UpdateAll, -- Forever only; ThreatPlates ComboPointsWidget.lua:961
    PLAYER_ENTERING_WORLD = function() -- UnitPowerMax can be 0 while zoning (ThreatPlates :964)
      for _, pf in pairs(ns.plates) do pf.comboMax = nil end
      UpdateAll()
    end,
    UPDATE_SHAPESHIFT_FORM = UpdateAll,
    UNIT_POWER_UPDATE = function(_, unit) if unit == "player" then UpdateAll() end end,
    UNIT_DISPLAYPOWER = function(_, unit) if unit == "player" then UpdateAll() end end,
  },
}
