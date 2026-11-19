local ADDON, ns = ...

local issecretvalue = issecretvalue or function() return false end

local CreateFrame, InCombatLockdown, C_Timer = CreateFrame, InCombatLockdown, C_Timer
local GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit
local UnitHealth, UnitHealthMax, UnitHealthPercent = UnitHealth, UnitHealthMax, UnitHealthPercent
local UnitPower, UnitPowerMax, UnitPowerType = UnitPower, UnitPowerMax, UnitPowerType
local UnitName, UnitIsPlayer, UnitClass, UnitReaction = UnitName, UnitIsPlayer, UnitClass, UnitReaction
local UnitIsTapDenied, UnitSelectionColor, UnitIsUnit = UnitIsTapDenied, UnitSelectionColor, UnitIsUnit
local AbbreviateNumbers = AbbreviateNumbers
local ScaleTo100 = CurveConstants and CurveConstants.ScaleTo100
local BackdropTemplate = BackdropTemplateMixin and "BackdropTemplate"
local UnitThreatSituation, UnitAffectingCombat = UnitThreatSituation, UnitAffectingCombat
local floor, pairs, type = math.floor, pairs, type

local pfByPlate = setmetatable({}, { __mode = "k" })  -- plate -> pf (lives as long as the plate)
local pfByFrame = setmetatable({}, { __mode = "k" })  -- Blizzard UnitFrame -> pf currently covering it
local origParent = setmetatable({}, { __mode = "k" }) -- UnitFrame -> parent, only while reparented away
local hooked = setmetatable({}, { __mode = "k" })
local elements = {}
local elementHandlers = {}   -- event -> list of element handlers
local coreHandlers = {}      -- event -> function(...)
local styleVersion = 1
local autoTank               -- cached auto role (nil = recompute on next use)
local curveCache = {}        -- base colour key -> execute colour curve; wiped when settings change
local THREAT_CATS = { hostileNPC = true, neutralNPC = true }
local EXECUTE_CATS = { enemyPlayer = true, hostileNPC = true, neutralNPC = true }
-- Absorb overlay needs the heal-prediction calculator (ThreatPlates Init.lua:139, Healthbar.lua:473-480).
local HAS_ABSORBS = type(UnitGetTotalAbsorbs) == "function" and type(CreateUnitHealPredictionCalculator) == "function"
  and type(UnitGetDetailedHealPrediction) == "function" and Enum.UnitDamageAbsorbClampMode ~= nil
ns.inCombat = InCombatLockdown() and true or false

-- Surnames: on WoW Forever UnitName's 2nd return is a surname when regional unique names are on
-- (ThreatPlates Init.lua:110-131); on other clients it is a realm, which we do not show.
local SURNAMES = _G.RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() or false
local SURNAME_SEP = Constants and Constants.CharacterNameSeparatorConsts
  and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "

-- Western abbreviations (45.2K, 1.3M); same options-table pattern as ThreatPlates Localization.lua:133-151.
local ABBREVIATE = {
  breakpointData = {
    { breakpoint = 1e9, abbreviation = "B", significandDivisor = 1e8, fractionDivisor = 10, abbreviationIsGlobal = false },
    { breakpoint = 1e6, abbreviation = "M", significandDivisor = 1e5, fractionDivisor = 10, abbreviationIsGlobal = false },
    { breakpoint = 1e3, abbreviation = "K", significandDivisor = 1e2, fractionDivisor = 10, abbreviationIsGlobal = false },
  },
}

-- v or d, but never boolean-tests a secret value.
local function nz(v, d)
  if issecretvalue(v) then return v end
  if v == nil then return d end
  return v
end

local function IsTrue(v)
  return not issecretvalue(v) and v
end

---------------------------------------------------------------------------------------------------
-- Elements
---------------------------------------------------------------------------------------------------

-- element = { create(pf), style(pf), update(pf), remove(pf), events = { EVENT = function(event, ...) end } }
-- All fields optional. update runs after every data update and visibility change; remove when a plate is released.
-- pf.showName / pf.showBar / pf.showPower tell elements what is visible (bar group respects ns.barsHidden).
function ns.RegisterElement(element)
  elements[#elements + 1] = element
  if element.events then
    for event, fn in pairs(element.events) do
      local list = elementHandlers[event]
      if not list then
        list = {}
        elementHandlers[event] = list
        -- RegisterEvent throws on an event name this client does not know; guard only this call
        -- so one unsupported event cannot stop the addon from loading.
        pcall(ns.eventFrame.RegisterEvent, ns.eventFrame, event)
      end
      list[#list + 1] = fn
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Frames and styling (no unit API calls)
---------------------------------------------------------------------------------------------------

function ns.CreatePlateFrames(parent)
  local pf = { showName = true, showBar = true, showPower = false, hasPower = true }

  local root = CreateFrame("Frame", nil, parent)
  root:EnableMouse(false)
  root:SetIgnoreParentAlpha(true) -- Blizzard's own plate fading must not leak into ours (ThreatPlates Nameplate.lua:1180)
  pf.root = root

  local health = CreateFrame("StatusBar", nil, root)
  health:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar") -- needed before SetVertexColor; restyled later
  health:SetMinMaxValues(0, 1)
  health:SetValue(1)
  pf.health = health

  pf.bg = health:CreateTexture(nil, "BACKGROUND")
  pf.bg:SetAllPoints(health)

  pf.border = CreateFrame("Frame", nil, health, BackdropTemplate)
  pf.border:EnableMouse(false)

  -- HP text sits on its own frame above the absorb overlay (health +1) so the shield never covers it.
  local textFrame = CreateFrame("Frame", nil, health)
  textFrame:SetAllPoints(health)
  textFrame:SetFrameLevel(health:GetFrameLevel() + 2)
  pf.hpText = textFrame:CreateFontString(nil, "OVERLAY")
  pf.hpText:SetFontObject(GameFontNormalSmall)

  -- Absorb shield overlay: starts at the right edge of the health fill (anchored in StylePlate).
  local absorb = CreateFrame("StatusBar", nil, health)
  absorb:SetFrameLevel(health:GetFrameLevel() + 1)
  absorb:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  absorb:SetMinMaxValues(0, 1)
  absorb:SetValue(0)
  absorb:Hide()
  pf.absorb = absorb

  -- On root, not health: names stay visible when the bar group is hidden.
  pf.name = root:CreateFontString(nil, "OVERLAY")
  pf.name:SetFontObject(GameFontNormal)
  pf.name:SetWordWrap(false)

  local power = CreateFrame("StatusBar", nil, root)
  power:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  power:SetMinMaxValues(0, 1)
  power:SetValue(1)
  pf.power = power
  pf.powerBg = power:CreateTexture(nil, "BACKGROUND")
  pf.powerBg:SetAllPoints(power)

  for i = 1, #elements do
    local create = elements[i].create
    if create then create(pf) end
  end
  return pf
end

local function SetFont(fs, spec)
  local flags = spec.outline
  if flags == nil or flags == "NONE" then flags = "" end
  fs:SetFont(ns.Fetch("font", spec.font), spec.size, flags)
end

function ns.StylePlate(pf)
  local P = ns.P
  local b, c = P.bar, P.colors

  pf.root:SetScale(b.scale)
  pf.root:SetSize(b.width, b.height)

  local bd = b.border
  local radius = ns.RoundedRadius(bd.radius, b.width, b.height) -- 0 = square, the original drawing below

  pf.health:SetAllPoints(pf.root)
  pf.health:SetStatusBarTexture(ns.Fetch("statusbar", b.texture))
  if ns.RoundedFill(pf.bg, radius) then
    pf.bg:SetVertexColor(c.background.r, c.background.g, c.background.b, c.background.a)
  else
    pf.bg:SetColorTexture(c.background.r, c.background.g, c.background.b, c.background.a)
  end
  ns.RoundedMask(pf.health, pf.health:GetStatusBarTexture(), radius)

  if bd.enabled then
    local size = bd.size
    if radius > 0 then
      pf.border:SetBackdrop(nil) -- the rounded rings replace the LSM border
    else
      -- A fresh table every time: SetBackdrop ignores the table it already has applied.
      pf.border:SetBackdrop({ edgeFile = ns.Fetch("border", bd.texture), edgeSize = size })
      pf.border:SetBackdropBorderColor(bd.color.r, bd.color.g, bd.color.b, bd.color.a)
    end
    pf.border:ClearAllPoints()
    pf.border:SetPoint("TOPLEFT", pf.health, "TOPLEFT", -size, size)
    pf.border:SetPoint("BOTTOMRIGHT", pf.health, "BOTTOMRIGHT", size, -size)
    pf.border:Show()
  else
    pf.border:Hide()
  end
  ns.RoundedBorder(pf.border, pf.health, radius, bd.enabled and bd.size or 0, bd.color)

  SetFont(pf.name, P.name)
  ns.ApplyPos(pf.name, pf.health, P.name.pos)

  SetFont(pf.hpText, P.hpText)
  ns.ApplyPos(pf.hpText, pf.health, P.hpText.pos)
  pf.hpText:SetShown(P.hpText.mode ~= "none")

  local ab, hfill = P.absorbs, pf.health:GetStatusBarTexture()
  pf.absorb:SetStatusBarTexture(ns.Fetch("statusbar", b.texture))
  pf.absorb:GetStatusBarTexture():SetVertexColor(ab.color.r, ab.color.g, ab.color.b, ab.color.a)
  pf.absorb:SetWidth(b.width)
  pf.absorb:ClearAllPoints()
  pf.absorb:SetPoint("TOPLEFT", hfill, "TOPRIGHT")
  pf.absorb:SetPoint("BOTTOMLEFT", hfill, "BOTTOMRIGHT")

  pf.power:SetStatusBarTexture(ns.Fetch("statusbar", b.texture))
  pf.power:SetSize(b.width, P.power.height)
  ns.ApplyPos(pf.power, pf.health, P.power.pos)
  pf.powerBg:SetColorTexture(c.background.r, c.background.g, c.background.b, c.background.a)

  if pf.hit then pf.hit:SetSize(b.width * b.scale, b.height * b.scale + 20) end

  pf.styleVersion = styleVersion
  for i = 1, #elements do
    local style = elements[i].style
    if style then style(pf) end
  end
end

-- Clickable area follows our bar, or is removed when nothing is drawn (ThreatPlates ApplyPlateHitTest, Nameplate.lua:1140).
function ns.ApplyHitTest(pf)
  local plate = pf.plate
  if not (plate and pf.hit and plate.CanChangeHitTestPoints and plate:CanChangeHitTestPoints()) then return end
  if pf.showName or pf.showBar then
    plate:SetAllHitTestPoints(pf.hit)
  else
    plate:ClearAllHitTestPoints()
  end
end

-- Damage absorb overlay; the values go from the calculator straight into the StatusBar (ThreatPlates Healthbar.lua:201-221).
local function UpdateAbsorbs(pf)
  local sb = pf.absorb
  if not (HAS_ABSORBS and pf.unit and pf.showBar and ns.P.absorbs.enabled) then
    pf.absorbWanted = false -- also covers the editor preview, which has no unit
    sb:Hide()
    return
  end
  local calc = pf.absorbCalc
  if not calc then
    calc = CreateUnitHealPredictionCalculator()
    calc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealthWithoutIncomingHeals)
    pf.absorbCalc = calc
  end
  UnitGetDetailedHealPrediction(pf.unit, nil, calc)
  sb:SetMinMaxValues(0, calc:GetMaximumHealth())
  sb:SetValue((calc:GetDamageAbsorbs()))
  pf.absorbWanted = true
  -- A freshly shown bar renders full width for one frame (Healthbar.lua:84-96): show it a frame later.
  if not sb:IsShown() and not pf.absorbPending then
    pf.absorbPending = true
    C_Timer.After(0, function()
      pf.absorbPending = false
      if pf.absorbWanted then sb:Show() end
    end)
  end
end

-- Shows/hides our regions from pf.showName / showBar / showPower. The editor sets those flags itself.
function ns.ApplyVisibility(pf)
  pf.health:SetShown(pf.showBar)
  pf.name:SetShown(pf.showName)
  pf.power:SetShown(pf.showPower and pf.hasPower)
  UpdateAbsorbs(pf)
  ns.ApplyHitTest(pf)
end

---------------------------------------------------------------------------------------------------
-- Data (reads the unit, secret-safe)
---------------------------------------------------------------------------------------------------

local function UpdateName(pf)
  local name, second = UnitName(pf.unit)
  local hasName = issecretvalue(name) or name ~= nil
  -- Concatenating a secret name is allowed (result stays secret); comparing it is not.
  if hasName and SURNAMES and not issecretvalue(second) and second ~= nil and second ~= "" then
    name = name .. SURNAME_SEP .. second
  end
  if hasName then pf.name:SetText(name) else pf.name:SetText("") end
end

local function PercentText(unit)
  if UnitHealthPercent and ScaleTo100 then
    -- Same call and format as ThreatPlates StatusText.lua:189; works with secret results.
    return ("%.f%%"):format(UnitHealthPercent(unit, true, ScaleTo100))
  end
  local cur, max = UnitHealth(unit), UnitHealthMax(unit)
  if not issecretvalue(cur) and not issecretvalue(max) and cur and max and max > 0 then
    return floor(100 * cur / max + 0.5) .. "%"
  end
  return ""
end

-- "" for mode none. Also used by PersonalBar.lua.
function ns.HpText(unit)
  local mode = ns.P.hpText.mode
  if mode == "none" then return "" end

  -- Value modes need AbbreviateNumbers (the only secret-safe formatter); percent is the fallback.
  if mode ~= "percent" and AbbreviateNumbers then
    local text = AbbreviateNumbers(UnitHealth(unit), ABBREVIATE)
    if ns.P.hpText.showMax then
      text = text .. " / " .. AbbreviateNumbers(UnitHealthMax(unit), ABBREVIATE)
    end
    if mode == "both" then
      text = text .. " - " .. PercentText(unit)
    end
    return text
  end
  return PercentText(unit)
end

local function UpdateHpText(pf)
  if ns.P.hpText.mode == "none" then return end
  pf.hpText:SetText(ns.HpText(pf.unit))
end

local function UpdateHealth(pf)
  local unit = pf.unit
  -- Secret health goes straight into the StatusBar setters (ThreatPlates Healthbar.lua:496-497).
  pf.health:SetMinMaxValues(0, nz(UnitHealthMax(unit), 1))
  pf.health:SetValue(nz(UnitHealth(unit), 0))
  UpdateHpText(pf)
end

local FALLBACK_POWER_COLOR = { r = 0.3, g = 0.5, b = 0.9 }

local function UpdatePower(pf)
  local unit = pf.unit
  local ptype, token = UnitPowerType(unit)
  if issecretvalue(ptype) then ptype = nil end
  if issecretvalue(token) then token = nil end

  local max = UnitPowerMax(unit, ptype)
  if not issecretvalue(max) and (max or 0) <= 0 then
    pf.hasPower = false
    return
  end
  pf.hasPower = true
  pf.power:SetMinMaxValues(0, nz(max, 1))
  pf.power:SetValue(nz(UnitPower(unit, ptype), 0))

  local col = (token and PowerBarColor[token]) or (ptype and PowerBarColor[ptype]) or PowerBarColor.MANA or FALLBACK_POWER_COLOR
  pf.power:GetStatusBarTexture():SetVertexColor(col.r, col.g, col.b)
end

-- Returns r, g, b, a, tapped. Possibly-secret values only travel from the Unit* API into color setters.
local function UnitColor(pf)
  local unit, C = pf.unit, ns.P.colors
  local c

  if IsTrue(UnitIsTapDenied(unit)) then
    return C.tapped.r, C.tapped.g, C.tapped.b, C.tapped.a or 1, true
  end
  local isPlayer = IsTrue(UnitIsPlayer(unit))
  if isPlayer and C.classColors then
    local _, class = UnitClass(unit)
    if not issecretvalue(class) and class then c = RAID_CLASS_COLORS[class] end
  end
  if not c then
    local reaction = UnitReaction(unit, "player")
    if not issecretvalue(reaction) and reaction then
      -- Enemy players turn neutral e.g. when mounted: still hostile (ThreatPlates Nameplate.lua:505-508).
      if reaction <= 3 or (isPlayer and reaction == 4) then c = C.hostile
      elseif reaction == 4 then c = C.neutral
      else c = C.friendly end
    else
      local r, g, b = UnitSelectionColor(unit)
      if type(r) == "number" then return r, g, b, 1 end
      c = C.hostile
    end
  end
  return c.r, c.g, c.b, c.a or 1
end

-- Tank = tank aura, else Warrior Defensive Stance / Druid Bear (ThreatPlates Nameplate.lua:2354-2420). Cached.
local function IsTankAuto()
  if autoTank == nil then
    local tank = false
    if UnitHasEffectivelyTankAura then
      local v = UnitHasEffectivelyTankAura("player")
      tank = not issecretvalue(v) and v == true
    end
    if not tank and GetShapeshiftFormID then
      local _, class = UnitClass("player")
      local form = GetShapeshiftFormID()
      if not issecretvalue(form) and form then
        if class == "WARRIOR" then tank = form == 18
        elseif class == "DRUID" then tank = form == 5 or form == 8 end
      end
    end
    autoTank = tank
  end
  return autoTank
end

-- r, g, b, a for hostile/neutral NPCs in combat, or nothing (secret, no threat table, out of combat).
local function ThreatColor(pf)
  local T = ns.P.threat
  if not (T.enabled and THREAT_CATS[pf.category]) then return end
  local unit = pf.unit
  local fighting = UnitAffectingCombat(unit)
  if issecretvalue(fighting) or not fighting then return end
  local status = UnitThreatSituation("player", unit)
  if issecretvalue(status) or type(status) ~= "number" then return end
  local role = T.role
  if role == "auto" then role = IsTankAuto() and "tank" or "dps" end
  local c
  if role == "tank" then
    c = (status >= 3 and T.tankSecure) or (status == 2 and T.tankInsecure) or T.tankLost
  else
    c = (status >= 2 and T.dpsAggro) or (status == 1 and T.dpsHigh) or T.dpsLow
  end
  return c.r, c.g, c.b, c.a or 1
end

-- Colour object for the health fill below the execute threshold, else nothing. Step curve on the health percent
-- (ThreatPlates Modules/Color.lua:70,212; StatusText.lua:50-54); a secret base colour cannot go into a curve.
local function ExecuteColor(pf, r, g, b, a)
  local E = ns.P.execute
  if not (E.enabled and EXECUTE_CATS[pf.category] and UnitHealthPercent
    and C_CurveUtil and C_CurveUtil.CreateColorCurve and Enum.LuaCurveType) then return end
  if issecretvalue(r) or issecretvalue(g) or issecretvalue(b) then return end
  local key = r .. ":" .. g .. ":" .. b .. ":" .. a
  local curve = curveCache[key]
  if not curve then
    curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    local e = E.color
    curve:AddPoint(0, CreateColor(e.r, e.g, e.b, e.a or 1))
    curve:AddPoint(E.threshold / 100, CreateColor(r, g, b, a))
    curveCache[key] = curve
  end
  return UnitHealthPercent(pf.unit, true, curve)
end

local function UpdateColor(pf)
  local r, g, b, a, tapped = UnitColor(pf)
  local exec
  if not tapped then
    local tr, tg, tb, ta = ThreatColor(pf)
    if tr then r, g, b, a = tr, tg, tb, ta end
    exec = ExecuteColor(pf, r, g, b, a)
  end
  -- Texture vertex color instead of SetStatusBarColor: ThreatPlates Healthbar.lua:344-348 on Midnight-API clients.
  local tex = pf.health:GetStatusBarTexture()
  if exec then tex:SetVertexColor(exec.r, exec.g, exec.b, exec.a) else tex:SetVertexColor(r, g, b, a) end
  pf.name:SetTextColor(r, g, b, 1) -- the name never takes the execute colour
end

local function UpdateFlags(pf)
  local P = ns.P
  local cat = pf.category and P.categories[pf.category]
  local name, bar, power
  if cat then
    name, bar, power = cat.name, cat.bar, cat.power
    pf.showCast, pf.showAuras = cat.cast ~= false, cat.auras ~= false
  else
    name, bar, power = true, true, false -- fail-safe: category unknown, show name and bar
    pf.showCast, pf.showAuras = true, true
  end
  if pf.isQuest and P.quest.override then name, bar = true, true end
  -- Out of combat only the bars go; names, casts and auras stay. Wins over the quest override.
  if cat and cat.combatOnly and not ns.inCombat then bar, power = false, false end
  pf.showName = name
  pf.showBar = bar and not ns.barsHidden
  pf.showPower = power and not ns.barsHidden
end

-- Runs every element's update hook (the editor calls it on its preview plate).
function ns.UpdateElements(pf)
  for i = 1, #elements do
    local update = elements[i].update
    if update then update(pf) end
  end
end

function ns.UpdatePlateData(pf)
  if not pf.unit then return end
  UpdateFlags(pf)
  UpdateName(pf)
  UpdateHealth(pf)
  UpdatePower(pf)
  UpdateColor(pf)
  ns.ApplyVisibility(pf)
  ns.UpdateElements(pf)
end

---------------------------------------------------------------------------------------------------
-- Blizzard plate handling (ThreatPlates Nameplate.lua:879-925, 1023-1056)
---------------------------------------------------------------------------------------------------

-- Hides Blizzard's whole UnitFrame (health bar, name, auras, ...). Returns true if it had to be reparented.
local function HideBlizzard(uf)
  if uf:IsForbidden() then return false end
  if uf:IsProtected() then
    -- Secure code can revert Hide()/SetAlpha on protected frames, so move it away instead.
    if not origParent[uf] then origParent[uf] = uf:GetParent() end
    uf:ClearAllPoints()
    uf:SetParent(nil)
    return true
  end
  uf:Hide()
  return false
end

-- The one place root and hit frame are anchored.
function ns.PlaceRoot(pf)
  local uf, plate = pf.ufr, pf.plate
  if not uf then return end
  -- A reparented UnitFrame has no points left, so a frame anchored to it would vanish.
  local anchor = origParent[uf] and plate or uf
  pf.root:ClearAllPoints()
  pf.root:SetPoint("CENTER", anchor, "CENTER")
  pf.hit:ClearAllPoints()
  pf.hit:SetPoint("CENTER", anchor, "CENTER")
  ns.ApplyHitTest(pf)
end

-- Blizzard re-shows its frame on its own (pooling, fades): hide it again while one of our plates covers it.
local function OnBlizzardShow(uf)
  local pf = pfByFrame[uf]
  if pf and pf.unit and HideBlizzard(uf) then ns.PlaceRoot(pf) end
end

-- plate.UnitFrame can be nil or stale right after NAME_PLATE_UNIT_ADDED, so this runs again from AcquireUnitFrame.
local function Attach(pf)
  local uf = pf.plate.UnitFrame
  if not uf or uf:IsForbidden() then return false end
  if pf.ufr and pf.ufr ~= uf then pfByFrame[pf.ufr] = nil end
  pf.ufr = uf
  pfByFrame[uf] = pf
  if not hooked[uf] then
    hooked[uf] = true
    uf:HookScript("OnShow", OnBlizzardShow)
    hooksecurefunc(uf, "Show", OnBlizzardShow)
  end
  HideBlizzard(uf)
  ns.PlaceRoot(pf)
  return true
end

local function IgnoreUnit(unit)
  -- Own plate, widget-only plates and game objects stay Blizzard's (ThreatPlates Nameplate.lua:1000-1002).
  return IsTrue(UnitIsUnit(unit, "player"))
    or (UnitNameplateShowsWidgetsOnly and IsTrue(UnitNameplateShowsWidgetsOnly(unit)))
    or (UnitIsGameObject and IsTrue(UnitIsGameObject(unit)))
    or false
end

local function RemovePlate(unit)
  local pf = ns.plates[unit]
  if not pf then return end
  for i = 1, #elements do
    local remove = elements[i].remove
    if remove then remove(pf) end
  end
  ns.plates[unit] = nil
  pf.unit, pf.category, pf.isQuest = nil, nil, false
  pf.absorbWanted = false
  pf.absorb:Hide()
  pf.root:Hide()

  local uf, plate = pf.ufr, pf.plate
  if uf then
    pfByFrame[uf] = nil
    pf.ufr = nil
    local orig = origParent[uf]
    if orig then
      origParent[uf] = nil
      uf:SetParent(orig)
      uf:SetAllPoints(orig)
    end
  end
  if plate.CanChangeHitTestPoints and plate:CanChangeHitTestPoints() then
    plate:ClearAllHitTestPoints()
  end
end

local function AddPlate(unit)
  if ns.plates[unit] then RemovePlate(unit) end
  -- Forbidden plates stay Blizzard default and are never touched.
  local plate = GetNamePlateForUnit(unit)
  if not plate or plate:IsForbidden() or IgnoreUnit(unit) then return end

  local pf = pfByPlate[plate]
  if not pf then
    pf = ns.CreatePlateFrames(plate)
    pf.plate = plate
    pf.hit = CreateFrame("Frame", nil, plate)
    pfByPlate[plate] = pf
  end
  if pf.styleVersion ~= styleVersion then ns.StylePlate(pf) end

  pf.unit, pf.category, pf.isQuest = unit, nil, false
  ns.plates[unit] = pf
  pf.root:Show()

  ns.UpdateCategory(pf)
  ns.UpdateQuest(pf)
  ns.UpdatePlateData(pf)

  if not Attach(pf) then
    C_Timer.After(0, function()
      if ns.plates[unit] == pf then Attach(pf) end
    end)
  end
end

---------------------------------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------------------------------

function ns.RefreshPlates()
  wipe(curveCache)
  autoTank = nil
  styleVersion = styleVersion + 1 -- pooled plates without a unit restyle when they are next used
  for _, pf in pairs(ns.plates) do
    ns.StylePlate(pf)
    ns.UpdateQuest(pf)
    ns.UpdatePlateData(pf)
  end
end

-- Cheap path for the bar toggle: no styling, no CVars.
function ns.RefreshVisibility()
  for _, pf in pairs(ns.plates) do
    UpdateFlags(pf)
    ns.ApplyVisibility(pf)
    for i = 1, #elements do
      local update = elements[i].update
      if update then update(pf) end
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------

local function ForUnit(fn)
  return function(unit, ...)
    local pf = ns.plates[unit]
    if pf then fn(pf, ...) end
  end
end

local function RecomputeAll()
  for _, pf in pairs(ns.plates) do
    ns.UpdateCategory(pf)
    ns.UpdatePlateData(pf)
  end
end

local questPending, questQueued = false, false

local function RefreshQuests()
  ns.WipeQuestCache()
  for _, pf in pairs(ns.plates) do
    ns.UpdateQuest(pf)
    ns.UpdatePlateData(pf)
  end
end

-- Debounced; deferred while in combat (tooltip data is unreliable there).
local function QueueQuestRefresh()
  if InCombatLockdown() then
    questPending = true
  elseif not questQueued then
    questQueued = true
    C_Timer.After(0.3, function()
      questQueued = false
      if InCombatLockdown() then questPending = true else RefreshQuests() end
    end)
  end
end

coreHandlers.NAME_PLATE_UNIT_ADDED = AddPlate
coreHandlers.NAME_PLATE_UNIT_REMOVED = RemovePlate
coreHandlers.UNIT_HEALTH = ForUnit(function(pf)
  UpdateHealth(pf)
  if ns.P.execute.enabled then UpdateColor(pf) end
  UpdateAbsorbs(pf)
end)
coreHandlers.UNIT_MAXHEALTH = coreHandlers.UNIT_HEALTH
coreHandlers.UNIT_ABSORB_AMOUNT_CHANGED = ForUnit(UpdateAbsorbs)
coreHandlers.UNIT_THREAT_SITUATION_UPDATE = ForUnit(UpdateColor)
coreHandlers.UNIT_THREAT_LIST_UPDATE = coreHandlers.UNIT_THREAT_SITUATION_UPDATE
coreHandlers.UNIT_FLAGS = ForUnit(function(pf) -- combat state of the unit
  if ns.P.threat.enabled then UpdateColor(pf) end
end)
coreHandlers.UNIT_NAME_UPDATE = ForUnit(UpdateName)
coreHandlers.UNIT_FACTION = ForUnit(function(pf)
  ns.UpdateCategory(pf)
  ns.UpdatePlateData(pf)
end)
coreHandlers.UNIT_POWER_UPDATE = ForUnit(function(pf)
  if pf.showPower then
    UpdatePower(pf)
    ns.ApplyVisibility(pf)
  end
end)
coreHandlers.UNIT_MAXPOWER = coreHandlers.UNIT_POWER_UPDATE
coreHandlers.UNIT_DISPLAYPOWER = coreHandlers.UNIT_POWER_UPDATE
coreHandlers.GROUP_ROSTER_UPDATE = RecomputeAll
coreHandlers.PLAYER_GUILD_UPDATE = RecomputeAll
coreHandlers.QUEST_LOG_UPDATE = QueueQuestRefresh
coreHandlers.UNIT_QUEST_LOG_CHANGED = function(unit)
  if unit == "player" then QueueQuestRefresh() end
end

local function SetPlayerCombat(state)
  ns.inCombat = state
  autoTank = nil
  ns.RefreshVisibility()
  for _, pf in pairs(ns.plates) do UpdateColor(pf) end
end
coreHandlers.PLAYER_REGEN_DISABLED = function() SetPlayerCombat(true) end
coreHandlers.UPDATE_SHAPESHIFT_FORM = function()
  autoTank = nil
  for _, pf in pairs(ns.plates) do UpdateColor(pf) end
end
coreHandlers.PLAYER_REGEN_ENABLED = function()
  SetPlayerCombat(false)
  if questPending then
    questPending = false
    QueueQuestRefresh()
  end
end

local ev = CreateFrame("Frame")
ns.eventFrame = ev
ev:SetScript("OnEvent", function(_, event, ...)
  local core = coreHandlers[event]
  if core then core(...) end
  local list = elementHandlers[event]
  if list then
    for i = 1, #list do list[i](event, ...) end
  end
end)

-- Called once from Core's OnEnable (PLAYER_LOGIN), when Blizzard's nameplate driver exists.
function ns.EnablePlates()
  ns.inCombat = InCombatLockdown() and true or false
  for event in pairs(coreHandlers) do
    -- RegisterEvent throws on event names this client lacks (PLAYER_GUILD_UPDATE is not confirmed on Forever).
    pcall(ev.RegisterEvent, ev, event)
  end
  if NamePlateDriverFrame and NamePlateDriverFrame.AcquireUnitFrame then
    hooksecurefunc(NamePlateDriverFrame, "AcquireUnitFrame", function(_, plate)
      local pf = pfByPlate[plate]
      if plate.UnitFrame then origParent[plate.UnitFrame] = nil end -- Blizzard just re-parented it
      if pf and pf.unit then Attach(pf) end
    end)
  end
end
