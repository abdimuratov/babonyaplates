local ADDON, ns = ...

local LSM = LibStub("LibSharedMedia-3.0")
local InCombatLockdown = InCombatLockdown

ns.addon = LibStub("AceAddon-3.0"):NewAddon(ADDON, "AceEvent-3.0", "AceConsole-3.0")
local addon = ns.addon

ns.plates = {}        -- unit token -> pf (filled by Plate.lua)
ns.barsHidden = false -- runtime only, never saved

-- Option tabs added by element files: { key, order, reset = { profile keys }, build = function(o) return group end }.
-- Options.lua builds them lazily and passes its constructors as o (see Build there).
ns.optionSections = {}
function ns.RegisterOptions(section) ns.optionSections[#ns.optionSections + 1] = section end

-- Globals required by Bindings.xml.
BINDING_HEADER_BABONYAPLATES = "BabonyaPlates"
BINDING_NAME_BABONYAPLATES_TOGGLE = "Toggle health bars"

---------------------------------------------------------------------------------------------------
-- Media
---------------------------------------------------------------------------------------------------

-- Missing media names fall back to the LSM default of that type.
function ns.Fetch(mediaType, name)
  return LSM:Fetch(mediaType, name, true) or LSM:Fetch(mediaType, LSM:GetDefault(mediaType))
end

-- Anchor a region to rel using a { point, relPoint, x, y } table (spec: positions are relative to pf.health).
function ns.ApplyPos(region, rel, pos)
  region:ClearAllPoints()
  region:SetPoint(pos.point, rel, pos.relPoint, pos.x, pos.y)
end

---------------------------------------------------------------------------------------------------
-- CVars
---------------------------------------------------------------------------------------------------

-- C_CVar.GetCVarInfo is what ThreatPlates' Options.lua uses (CVarIsUnavailable) to hide missing CVars.
function ns.CVarExists(name)
  return C_CVar.GetCVarInfo(name) ~= nil
end

local function SetCVar(name, value)
  if not ns.CVarExists(name) then return end
  value = tostring(value)
  if C_CVar.GetCVar(name) ~= value then
    C_CVar.SetCVar(name, value)
  end
end

local function AnyOn(P, key)
  local c = P.categories[key]
  return c.name or c.bar or c.power or c.cast or c.auras
end

-- Floating engine names are replaced by ours. Own/guild/title CVars are left alone.
local NAME_CVARS = {
  "UnitNameFriendlyPlayerName", "UnitNameFriendlyPetName", "UnitNameFriendlyGuardianName",
  "UnitNameFriendlyTotemName", "UnitNameFriendlyMinionName",
  "UnitNameEnemyPlayerName", "UnitNameEnemyPetName", "UnitNameEnemyGuardianName",
  "UnitNameEnemyTotemName", "UnitNameEnemyMinionName",
  "UnitNameNPC", "UnitNameHostleNPC", "UnitNameInteractiveNPC", "UnitNameNonCombatCreatureName",
}

local PET_CVARS = {
  "nameplateShowEnemyGuardians", "nameplateShowEnemyMinions", "nameplateShowEnemyPets", "nameplateShowEnemyTotems",
  "nameplateShowFriendlyPlayerGuardians", "nameplateShowFriendlyPlayerMinions",
  "nameplateShowFriendlyPlayerPets", "nameplateShowFriendlyPlayerTotems",
}

local pendingCVars = false

function ns.ApplyCVars()
  if InCombatLockdown() then
    pendingCVars = true
    return
  end
  pendingCVars = false

  local P = ns.P
  local qo = P.quest.override
  local enemies = AnyOn(P, "enemyPlayer") or AnyOn(P, "hostileNPC") or AnyOn(P, "neutralNPC") or AnyOn(P, "critter") or qo
  local friendlyPlayers = AnyOn(P, "friendlyPlayer") or AnyOn(P, "groupMember") or AnyOn(P, "guildMember")
  local friendlyNpcs = AnyOn(P, "friendlyNPC") or AnyOn(P, "critter") or qo
  local pets = AnyOn(P, "pet")

  -- Only ever switch plate types on, never off: other plates the user wants stay theirs.
  if enemies then
    SetCVar("nameplateShowEnemies", 1)
    SetCVar("nameplateShowEnemyMinus", 1)
  end
  if friendlyPlayers then SetCVar("nameplateShowFriendlyPlayers", 1) end
  if friendlyNpcs then SetCVar("nameplateShowFriendlyNpcs", 1) end
  if pets then
    for _, name in ipairs(PET_CVARS) do SetCVar(name, 1) end
  end
  if enemies or friendlyPlayers or friendlyNpcs or pets then SetCVar("nameplateShowAll", 1) end

  for _, name in ipairs(NAME_CVARS) do SetCVar(name, 0) end

  SetCVar("nameplateMaxDistance", P.cvars.maxDistance)
  -- The engine fades the plate frame our root sits on (units behind obstacles, far units); other nameplate
  -- addons leave these CVars changed, which made plates seem to appear only from some camera angles.
  SetCVar("nameplateOccludedAlphaMult", P.cvars.occludedAlpha)
  SetCVar("nameplateMinAlpha", P.cvars.minAlpha)
  SetCVar("nameplateMaxAlpha", 1)
  SetCVar("nameplateSelectedAlpha", 1)

  -- nameplateStackingTypes is a bitfield indexed by Enum.NamePlateStackType (replaces nameplateMotion);
  -- bitfield CVars are only accessible via C_CVar.Get/SetCVarBitfield (see ThreatPlates Options.lua:671-681).
  -- All flags stay off: no nameplate stacking at all.
  if Enum.NamePlateStackType and ns.CVarExists("nameplateStackingTypes") then
    for _, index in pairs(Enum.NamePlateStackType) do
      if C_CVar.GetCVarBitfield("nameplateStackingTypes", index) then
        C_CVar.SetCVarBitfield("nameplateStackingTypes", index, false)
      end
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Refresh and bar toggle
---------------------------------------------------------------------------------------------------

-- ns.RefreshPlates (Plate.lua) and ns.RefreshEditor (Editor.lua, optional) are looked up at call time.
function ns.RefreshAll()
  ns.ApplyCVars()
  if ns.RefreshPlates then ns.RefreshPlates() end
  if ns.RefreshEditor then ns.RefreshEditor() end
end

-- Only touches our own regions, so it is safe in combat.
function ns.ToggleBars()
  ns.barsHidden = not ns.barsHidden
  if ns.RefreshVisibility then ns.RefreshVisibility() end
  addon:Print(ns.barsHidden and "Health bars hidden." or "Health bars shown.")
end

function BabonyaPlates_ToggleBars()
  ns.ToggleBars()
end

---------------------------------------------------------------------------------------------------
-- Addon lifecycle
---------------------------------------------------------------------------------------------------

local CONFLICTS = { "TidyPlates_ThreatPlates", "Plater", "Kui_Nameplates", "Platynator" }

-- Old saved keys: combo.size became width + height; the stacking settings are gone.
local function Migrate()
  local c, cv = ns.P.combo, ns.P.cvars
  if c.size ~= nil then
    c.width, c.height, c.size = c.size, c.size, nil
  end
  ns.P.stacking, cv.stacking, cv.stackEnemy, cv.stackFriendly = nil, nil, nil, nil
end

local function OnProfileChanged()
  ns.P = ns.db.profile
  Migrate()
  ns.RefreshAll()
end

function addon:OnInitialize()
  -- true = one shared "Default" profile for all characters.
  ns.db = LibStub("AceDB-3.0"):New("BabonyaPlatesDB", ns.defaults, true)
  ns.P = ns.db.profile
  Migrate()
  ns.db.RegisterCallback(ns, "OnProfileChanged", OnProfileChanged)
  ns.db.RegisterCallback(ns, "OnProfileCopied", OnProfileChanged)
  ns.db.RegisterCallback(ns, "OnProfileReset", OnProfileChanged)

  self:RegisterChatCommand("babonyaplates", "OnSlash")
  self:RegisterChatCommand("bpt", "OnSlash")
end

function addon:OnEnable()
  for _, name in ipairs(CONFLICTS) do
    if C_AddOns.IsAddOnLoaded(name) then
      self:Print("|cffff5555Warning:|r " .. name .. " is also loaded and will conflict with BabonyaPlates. Disable one of them.")
    end
  end

  self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if pendingCVars then ns.ApplyCVars() end
  end)

  ns.ApplyCVars()
  if ns.EnablePlates then ns.EnablePlates() end
end

function addon:OnSlash(input)
  local cmd = strlower(strtrim(input or ""))
  if cmd == "toggle" then
    ns.ToggleBars()
  elseif cmd == "edit" then
    if ns.OpenEditor then ns.OpenEditor() else self:Print("Editor is not available.") end
  elseif cmd == "" then
    if ns.OpenOptions then ns.OpenOptions() else self:Print("Options are not available. Commands: toggle, edit.") end
  else
    self:Print("Commands: /bpt (options), /bpt toggle, /bpt edit")
  end
end
