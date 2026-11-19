local ADDON, ns = ...

-- The player's own health (and optionally power) in a frame fixed on screen, not on a nameplate.

local issecretvalue = issecretvalue or function() return false end
local CreateFrame, InCombatLockdown, UIParent = CreateFrame, InCombatLockdown, UIParent
local UnitHealth, UnitHealthMax, UnitPower, UnitPowerMax, UnitPowerType, UnitClass =
  UnitHealth, UnitHealthMax, UnitPower, UnitPowerMax, UnitPowerType, UnitClass
local GetCursorPosition, IsMouseButtonDown, IsShiftKeyDown = GetCursorPosition, IsMouseButtonDown, IsShiftKeyDown
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local BackdropTemplate = BackdropTemplateMixin and "BackdropTemplate"

local RANGE = 800 -- same limit as the X/Y sliders below
local MANA = Enum.PowerType.Mana
local RAGE = Enum.PowerType.Rage
local TEX = "Interface\\TargetingFrame\\UI-StatusBar" -- placeholder until styled
local FALLBACK_POWER_COLOR = { r = 0.3, g = 0.5, b = 0.9 }
local isDruid = select(2, UnitClass("player")) == "DRUID"
local inCombat = InCombatLockdown() and true or false

local function nz(v, d)
  if issecretvalue(v) then return v end
  if v == nil then return d end
  return v
end

local function NewBar(parent)
  local sb = CreateFrame("StatusBar", nil, parent)
  sb:SetStatusBarTexture(TEX)
  sb:SetMinMaxValues(0, 1)
  sb:SetValue(1)
  sb.bg = sb:CreateTexture(nil, "BACKGROUND")
  sb.bg:SetAllPoints(sb)
  return sb
end

---------------------------------------------------------------------------------------------------
-- Frames (no profile or unit access)
---------------------------------------------------------------------------------------------------

local f = CreateFrame("Frame", nil, UIParent)
f:SetFrameStrata("MEDIUM")
f:SetClampedToScreen(true)
f:Hide()

local health = NewBar(f)
health:SetAllPoints(f)
local border = CreateFrame("Frame", nil, health, BackdropTemplate)
border:EnableMouse(false)

local textFrame = CreateFrame("Frame", nil, health)
textFrame:SetAllPoints(health)
textFrame:SetFrameLevel(health:GetFrameLevel() + 2)
local hpText = textFrame:CreateFontString(nil, "OVERLAY")
hpText:SetFontObject(GameFontNormalSmall)
hpText:SetPoint("CENTER")

local power = NewBar(f)
local mana = NewBar(f)

-- Shown only while unlocked.
local overlay = CreateFrame("Frame", nil, f)
overlay:SetAllPoints(f)
overlay:SetFrameLevel(health:GetFrameLevel() + 5)
overlay:EnableMouse(false)
overlay:Hide()
overlay.tex = overlay:CreateTexture(nil, "BACKGROUND")
overlay.tex:SetAllPoints(overlay)
overlay.tex:SetColorTexture(0, 0, 0, 0.6)
overlay.text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
overlay.text:SetPoint("CENTER")
overlay.text:SetWordWrap(false)
overlay.text:SetText("Personal bar \226\128\148 drag to move")

---------------------------------------------------------------------------------------------------
-- Style (profile only)
---------------------------------------------------------------------------------------------------

local function Style()
  local P = ns.P
  local p, c, bd = P.personal, P.colors, P.bar.border
  local tex = ns.Fetch("statusbar", p.texture)

  f:SetSize(p.width, p.height)
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", p.pos.x, p.pos.y)
  f:EnableMouse(not p.locked)
  overlay:SetShown(not p.locked)

  -- Same drawing as ns.StylePlate: rounded fill/mask/rings when bar.border.radius > 0, else an LSM backdrop.
  local radius = ns.RoundedRadius(bd.radius, p.width, p.height)
  health:SetStatusBarTexture(tex)
  if ns.RoundedFill(health.bg, radius) then
    health.bg:SetVertexColor(c.background.r, c.background.g, c.background.b, c.background.a)
  else
    health.bg:SetColorTexture(c.background.r, c.background.g, c.background.b, c.background.a)
  end
  ns.RoundedMask(health, health:GetStatusBarTexture(), radius)
  if bd.enabled then
    local size = bd.size
    if radius > 0 then
      border:SetBackdrop(nil)
    else
      border:SetBackdrop({ edgeFile = ns.Fetch("border", bd.texture), edgeSize = size })
      border:SetBackdropBorderColor(bd.color.r, bd.color.g, bd.color.b, bd.color.a)
    end
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", health, "TOPLEFT", -size, size)
    border:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", size, -size)
    border:Show()
  else
    border:Hide()
  end
  ns.RoundedBorder(border, health, radius, bd.enabled and bd.size or 0, bd.color)

  hpText:SetFont(ns.Fetch("font", p.font), p.size, p.outline ~= "NONE" and p.outline or "")
  hpText:SetShown(p.hpText)

  for _, bar in ipairs({ power, mana }) do
    bar:SetStatusBarTexture(tex)
    bar:SetSize(p.width, p.power.height)
    bar.bg:SetColorTexture(c.background.r, c.background.g, c.background.b, c.background.a)
  end
  power:ClearAllPoints()
  power:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -1)
  mana:ClearAllPoints()
  mana:SetPoint("TOPLEFT", power, "BOTTOMLEFT", 0, -1)
end

---------------------------------------------------------------------------------------------------
-- Data (secret-safe: unit values only go into setters)
---------------------------------------------------------------------------------------------------

local function UpdateColor()
  local p = ns.P.personal
  local col = p.color
  if p.classColor then
    local _, class = UnitClass("player")
    if class and not issecretvalue(class) and RAID_CLASS_COLORS[class] then col = RAID_CLASS_COLORS[class] end
  end
  health:GetStatusBarTexture():SetVertexColor(col.r, col.g, col.b, col.a or 1)
end

local function UpdateHealth()
  health:SetMinMaxValues(0, nz(UnitHealthMax("player"), 1))
  health:SetValue(nz(UnitHealth("player"), 0))
  if ns.P.personal.hpText then hpText:SetText(ns.HpText("player")) end
end

local function UpdatePower()
  if not ns.P.personal.power.enabled then
    power:Hide(); mana:Hide()
    return
  end
  local ptype, token = UnitPowerType("player")
  if issecretvalue(ptype) then ptype = nil end
  if issecretvalue(token) then token = nil end

  local pmax = UnitPowerMax("player", ptype)
  if not issecretvalue(pmax) and (pmax or 0) <= 0 then
    power:Hide(); mana:Hide()
    return
  end
  power:SetMinMaxValues(0, nz(pmax, 1))
  power:SetValue(nz(UnitPower("player", ptype), 0))
  local col = (token and PowerBarColor[token]) or (ptype and PowerBarColor[ptype]) or PowerBarColor.MANA or FALLBACK_POWER_COLOR
  power:GetStatusBarTexture():SetVertexColor(col.r, col.g, col.b)
  power:Show()

  -- Druid in Cat/Bear: the real mana pool under the form's power.
  if isDruid and ptype and ptype ~= MANA then
    mana:SetMinMaxValues(0, nz(UnitPowerMax("player", MANA), 1))
    mana:SetValue(nz(UnitPower("player", MANA), 0))
    local mc = PowerBarColor.MANA or FALLBACK_POWER_COLOR
    mana:GetStatusBarTexture():SetVertexColor(mc.r, mc.g, mc.b)
    mana:Show()
  else
    mana:Hide()
  end
end

-- Any secret value in the comparison -> show (fail-safe).
local function NotFull()
  local hp, hm = UnitHealth("player"), UnitHealthMax("player")
  if issecretvalue(hp) or issecretvalue(hm) or hp == nil or hm == nil then return true end
  if hp < hm then return true end
  if ns.P.personal.power.enabled then
    local ptype = UnitPowerType("player")
    local cur, pmax = UnitPower("player"), UnitPowerMax("player")
    if issecretvalue(ptype) or issecretvalue(cur) or issecretvalue(pmax) or cur == nil or pmax == nil then return true end
    if ptype == RAGE then return cur > 0 end -- rage rests at 0
    return cur < pmax
  end
  return false
end

local function UpdateVisibility()
  local p = ns.P.personal
  local show
  if not p.enabled then show = false
  elseif not p.locked then show = true -- being positioned
  elseif ns.barsHidden then show = false
  elseif p.visibility == "always" or inCombat then show = true
  elseif p.visibility == "combat" then show = false
  else show = NotFull() end
  f:SetShown(show)
end

---------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------

local function UpdateAll()
  UpdateColor()
  UpdateHealth()
  UpdatePower()
  UpdateVisibility()
end

local UNIT_EVENTS = {
  UNIT_HEALTH = function() UpdateHealth(); UpdateVisibility() end,
  UNIT_MAXHEALTH = function() UpdateHealth(); UpdateVisibility() end,
  UNIT_POWER_UPDATE = function() UpdatePower(); UpdateVisibility() end,
  UNIT_POWER_FREQUENT = function() UpdatePower(); UpdateVisibility() end,
  UNIT_MAXPOWER = function() UpdatePower(); UpdateVisibility() end,
  UNIT_DISPLAYPOWER = function() UpdatePower(); UpdateVisibility() end,
}
local PLAIN_EVENTS = { "UPDATE_SHAPESHIFT_FORM", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

f:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_REGEN_DISABLED" then inCombat = true
  elseif event == "PLAYER_REGEN_ENABLED" then inCombat = false
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- ns.RefreshAll only runs on setting/profile changes, so login and zoning style and register here.
    inCombat = InCombatLockdown() and true or false
    return ns.RefreshPersonal()
  end
  local h = UNIT_EVENTS[event]
  if h then h() else UpdateAll() end
end)
f:RegisterEvent("PLAYER_ENTERING_WORLD")

function ns.RefreshPersonal()
  if not ns.P then return end
  f:UnregisterAllEvents()
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  if not ns.P.personal.enabled then
    f:Hide()
    return
  end
  -- pcall: RegisterEvent throws on a name this client does not know.
  for event in pairs(UNIT_EVENTS) do pcall(f.RegisterUnitEvent, f, event, "player") end
  for _, event in ipairs(PLAIN_EVENTS) do pcall(f.RegisterEvent, f, event) end
  inCombat = InCombatLockdown() and true or inCombat
  Style()
  UpdateAll()
end

---------------------------------------------------------------------------------------------------
-- Moving (OnUpdate drag like Editor.lua, so Shift can lock one axis)
---------------------------------------------------------------------------------------------------

local drag

local function Clamp(v)
  return max(-RANGE, min(RANGE, floor(v + 0.5)))
end

local function DragFinish()
  drag = nil
  f:SetScript("OnUpdate", nil)
  local reg = LibStub("AceConfigRegistry-3.0", true)
  if reg then reg:NotifyChange("BabonyaPlates") end
end

local function DragUpdate()
  if not IsMouseButtonDown("LeftButton") then return DragFinish() end
  local cx, cy = GetCursorPosition()
  local s = f:GetEffectiveScale() -- offsets are in the frame's own coordinate space
  local dx, dy = (cx - drag.cx) / s, (cy - drag.cy) / s
  if IsShiftKeyDown() then
    if abs(dx) > abs(dy) then dy = 0 else dx = 0 end
  end
  local pos = ns.P.personal.pos
  pos.x, pos.y = Clamp(drag.x + dx), Clamp(drag.y + dy)
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)
end

f:SetScript("OnMouseDown", function(_, button)
  if button ~= "LeftButton" or ns.P.personal.locked then return end
  local pos = ns.P.personal.pos
  drag = { x = pos.x, y = pos.y }
  drag.cx, drag.cy = GetCursorPosition()
  f:SetScript("OnUpdate", DragUpdate)
end)
f:SetScript("OnMouseUp", function()
  if drag then DragFinish() end
end)

---------------------------------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------------------------------

ns.RegisterOptions{
  key = "personal", order = 9.5, reset = { "personal" },
  build = function(o)
    local VIS = { always = "Always", smart = "In combat or not full", combat = "In combat only" }
    local OUTLINES = { NONE = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick outline" }
    return o.Group("Personal bar", {
      { "enabled", o.Toggle("Enabled", "personal.enabled") },
      { "visibility", o.Select("Show", "personal.visibility", VIS, { "always", "smart", "combat" }) },
      { "unlock", { type = "toggle", name = "Unlock to move",
          desc = "Shows the bar with a drag overlay. Hold Shift while dragging to move along one axis.",
          get = function() return not ns.P.personal.locked end,
          set = function(_, v) ns.P.personal.locked = not v; ns.RefreshAll() end } },
      { "x", o.Range("X offset", "personal.pos.x", -RANGE, RANGE, 1) },
      { "y", o.Range("Y offset", "personal.pos.y", -RANGE, RANGE, 1) },
      { "width", o.Range("Width", "personal.width", 40, 600, 1) },
      { "height", o.Range("Height", "personal.height", 4, 60, 1) },
      { "texture", o.Media("Texture", "personal.texture", "statusbar") },
      { "classColor", o.Toggle("Class color", "personal.classColor") },
      { "color", o.Color("Color", "personal.color", true) },
      { "text", o.Group("Health text", {
        { "hpText", o.Toggle("Show", "personal.hpText", "Format follows the Health text settings of the plates.") },
        { "font", o.Media("Font", "personal.font", "font") },
        { "size", o.Range("Size", "personal.size", 6, 32, 1) },
        { "outline", o.Select("Outline", "personal.outline", OUTLINES, { "NONE", "OUTLINE", "THICKOUTLINE" }) },
      }) },
      { "power", o.Group("Power bar", {
        { "enabled", o.Toggle("Enabled", "personal.power.enabled") },
        { "height", o.Range("Height", "personal.power.height", 2, 30, 1) },
        { "note", { type = "description", name = "Druids also get a mana bar below it while in Cat or Bear form." } },
      }) },
    })
  end,
}
