local ADDON, ns = ...

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local LSM = LibStub("LibSharedMedia-3.0")

-- Every option stores its profile path ("bar.border.size") in info.arg; ns.P is re-read on each call,
-- so profile switches need no rebuild (only a NotifyChange, see Build).
local function Resolve(path)
  local t = ns.P
  local last
  for key in path:gmatch("[^.]+") do
    if last then t = t[last] end
    last = key
  end
  return t, last
end

local function Get(info)
  local t, k = Resolve(info.arg)
  return t[k]
end

local function Set(info, v)
  local t, k = Resolve(info.arg)
  t[k] = v
  ns.RefreshAll()
end

local function GetColor(info)
  local c = Get(info)
  return c.r, c.g, c.b, c.a
end

local function SetColor(info, r, g, b, a)
  local c = Get(info)
  c.r, c.g, c.b = r, g, b
  if info.option.hasAlpha then c.a = a end
  ns.RefreshAll()
end

-- Small option constructors. Order is the argument order within a group (see Group).
local function Toggle(name, arg, desc)
  return { type = "toggle", name = name, arg = arg, desc = desc, get = Get, set = Set }
end

local function Range(name, arg, min, max, step, extra)
  local o = { type = "range", name = name, arg = arg, min = min, max = max, step = step, get = Get, set = Set }
  if extra then for k, v in pairs(extra) do o[k] = v end end
  return o
end

local function Select(name, arg, values, sorting)
  return { type = "select", name = name, arg = arg, values = values, sorting = sorting, get = Get, set = Set }
end

local function Color(name, arg, hasAlpha)
  return { type = "color", name = name, arg = arg, hasAlpha = hasAlpha, get = GetColor, set = SetColor }
end

local function Media(name, arg, mediaType)
  return {
    type = "select", dialogControl = "LSM30_" .. mediaType:gsub("^%l", string.upper), name = name, arg = arg,
    values = function() return LSM:HashTable(mediaType) end, get = Get, set = Set,
  }
end

-- Args given as an ordered list of { key, option } pairs so the tree order is the source order.
local function Group(name, list, extra)
  local g = { type = "group", name = name, args = {} }
  for i, e in ipairs(list) do
    e[2].order = i
    g.args[e[1]] = e[2]
  end
  if extra then for k, v in pairs(extra) do g[k] = v end end
  return g
end

local POINTS = {
  TOPLEFT = "Top left", TOP = "Top", TOPRIGHT = "Top right",
  LEFT = "Left", CENTER = "Center", RIGHT = "Right",
  BOTTOMLEFT = "Bottom left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom right",
}
local POINT_ORDER = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local OUTLINES = { NONE = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick outline" }
local OUTLINE_ORDER = { "NONE", "OUTLINE", "THICKOUTLINE" }
local HP_MODES = { none = "None", percent = "Percent", value = "Value", both = "Value and percent" }
local HP_ORDER = { "none", "percent", "value", "both" }
local THREAT_ROLES = { auto = "Auto", tank = "Tank", dps = "DPS & healer" }
local THREAT_ROLE_ORDER = { "auto", "tank", "dps" }

-- The one position helper: inline group with both anchor points and X/Y offsets for profile path `arg`.
local function Pos(arg, rel)
  return Group("Position", {
    { "point", Select("Anchor on element", arg .. ".point", POINTS, POINT_ORDER) },
    { "relPoint", Select("Anchor on " .. (rel or "bar"), arg .. ".relPoint", POINTS, POINT_ORDER) },
    { "x", Range("X offset", arg .. ".x", -100, 100, 1) },
    { "y", Range("Y offset", arg .. ".y", -100, 100, 1) },
  }, { inline = true })
end

local function TextGroup(name, arg, extra)
  local list = {}
  for _, e in ipairs(extra or {}) do list[#list + 1] = e end
  list[#list + 1] = { "font", Media("Font", arg .. ".font", "font") }
  list[#list + 1] = { "size", Range("Size", arg .. ".size", 6, 32, 1) }
  list[#list + 1] = { "outline", Select("Outline", arg .. ".outline", OUTLINES, OUTLINE_ORDER) }
  list[#list + 1] = { "pos", Pos(arg .. ".pos", arg == "level" and "name") }
  return Group(name, list)
end

local CATEGORIES = {
  { "enemyPlayer", "Enemy players" },
  { "friendlyPlayer", "Friendly players" },
  { "groupMember", "Party & raid members" },
  { "guildMember", "Guild members" },
  { "hostileNPC", "Hostile NPCs" },
  { "neutralNPC", "Neutral NPCs" },
  { "friendlyNPC", "Friendly NPCs" },
  { "pet", "Pets, minions & totems" },
  { "critter", "Critters" },
}

local function Visibility()
  local list = {}
  for _, c in ipairs(CATEGORIES) do
    local key = c[1]
    list[#list + 1] = { key, Group(c[2], {
      { "name", Toggle("Show name", "categories." .. key .. ".name") },
      { "bar", Toggle("Show health bar", "categories." .. key .. ".bar") },
      { "power", Toggle("Show power bar", "categories." .. key .. ".power") },
      { "cast", Toggle("Show cast bar", "categories." .. key .. ".cast") },
      { "auras", Toggle("Show auras", "categories." .. key .. ".auras") },
      { "combatOnly", Toggle("Bars only in combat", "categories." .. key .. ".combatOnly", "Hides health and power bars while you are out of combat. Names stay.") },
    }, { inline = true }) }
  end
  list[#list + 1] = { "quest", Group("Quest mobs", {
    { "override", Toggle("Always show name and bar", "quest.override", "Quest objectives ignore the category toggles.") },
    { "icon", Toggle("Show quest icon", "quest.icon") },
    { "size", Range("Icon size", "quest.size", 8, 48, 1) },
    { "pos", Pos("quest.pos") },
  }, { inline = true }) }
  return Group("Visibility", list)
end

local function CVarGroup()
  return Group("Game settings", {
    { "maxDistance", Range("Max distance", "cvars.maxDistance", 10, 100, 1) },
    { "occludedAlpha", Range("Opacity behind obstacles", "cvars.occludedAlpha", 0, 1, 0.05,
      { isPercent = true, desc = "Plates of units hidden behind walls or objects (seen from the camera). 100% = never fade." }) },
    { "minAlpha", Range("Opacity of distant plates", "cvars.minAlpha", 0, 1, 0.05,
      { isPercent = true, desc = "Plates of far-away units. 100% = never fade." }) },
  })
end

-- One "Reset this tab" button for every tab: copies the defaults of the profile keys the tab edits.
-- The key stays a table (AceDB sub-tables must exist) and the copy is deep, so defaults are never aliased.
local function ResetButton(keys)
  return {
    type = "execute", name = "Reset this tab", order = 1000,
    confirm = true, confirmText = "Reset this tab to its default settings?",
    func = function()
      for _, key in ipairs(keys) do ns.P[key] = CopyTable(ns.defaults.profile[key]) end
      ns.RefreshAll()
      AceConfigRegistry:NotifyChange("BabonyaPlates")
    end,
  }
end

local built, options

local function Build()
  if built then return options end
  built = true

  options = {
    type = "group",
    name = "BabonyaPlates",
    childGroups = "tree",
    args = {
      editor = {
        type = "execute", name = "Open layout editor", order = 0,
        hidden = function() return not ns.OpenEditor end,
        func = function() ns.OpenEditor() end,
      },
    },
  }
  local sections = {
    { "visibility", Visibility(), { "categories", "quest" } },
    { "colors", Group("Colors", {
      { "classColors", Toggle("Class colors for players", "colors.classColors") },
      { "hostile", Color("Hostile", "colors.hostile", true) },
      { "neutral", Color("Neutral", "colors.neutral", true) },
      { "friendly", Color("Friendly", "colors.friendly", true) },
      { "tapped", Color("Tapped", "colors.tapped", true) },
      { "background", Color("Bar background", "colors.background", true) },
      { "threat", Group("Threat", {
        { "enabled", Toggle("Enabled", "threat.enabled", "Colors the bars of hostile and neutral NPCs that are in combat by your threat.") },
        { "role", Select("Role", "threat.role", THREAT_ROLES, THREAT_ROLE_ORDER) },
        { "tankSecure", Color("Tank: secure", "threat.tankSecure", true) },
        { "tankInsecure", Color("Tank: insecure", "threat.tankInsecure", true) },
        { "tankLost", Color("Tank: lost", "threat.tankLost", true) },
        { "dpsLow", Color("DPS: low threat", "threat.dpsLow", true) },
        { "dpsHigh", Color("DPS: high threat", "threat.dpsHigh", true) },
        { "dpsAggro", Color("DPS: has aggro", "threat.dpsAggro", true) },
      }, { inline = true }) },
      { "execute", Group("Execute", {
        { "enabled", Toggle("Enabled", "execute.enabled", "Colors the bars of attackable units below the threshold. Tapped units keep the tapped color.") },
        { "threshold", Range("Threshold", "execute.threshold", 1, 50, 1, { desc = "Health percent below which the color applies." }) },
        { "color", Color("Color", "execute.color", true) },
      }, { inline = true }) },
    }), { "colors", "threat", "execute" } },
    { "bar", Group("Health bar", {
      { "width", Range("Width", "bar.width", 20, 400, 1) },
      { "height", Range("Height", "bar.height", 2, 60, 1) },
      { "scale", Range("Scale", "bar.scale", 0.5, 3, 0.05, { isPercent = true }) },
      { "texture", Media("Texture", "bar.texture", "statusbar") },
      { "absorbs", Group("Absorbs", {
        { "enabled", Toggle("Enabled", "absorbs.enabled", "Shows damage absorb shields on the bar.") },
        { "color", Color("Color", "absorbs.color", true) },
      }, { inline = true }) },
      { "border", Group("Border", {
        { "enabled", Toggle("Enabled", "bar.border.enabled") },
        { "texture", Media("Texture", "bar.border.texture", "border") },
        { "size", Range("Size", "bar.border.size", 1, 16, 1) },
        { "radius", Range("Corner radius", "bar.border.radius", 0, 12, 1, { desc = "0 = square corners. Rounds the bar, its background and the border (which then replaces the border texture)." }) },
        { "color", Color("Color", "bar.border.color", true) },
      }, { inline = true }) },
    }), { "bar", "absorbs" } },
    { "name", TextGroup("Name", "name"), { "name" } },
    { "hpText", TextGroup("HP text", "hpText", {
      { "mode", Select("Display", "hpText.mode", HP_MODES, HP_ORDER) },
      { "showMax", Toggle("Show max health", "hpText.showMax", "Show current / max.") },
    }), { "hpText" } },
    { "power", Group("Power bar", {
      { "height", Range("Height", "power.height", 1, 30, 1) },
      { "pos", Pos("power.pos") },
    }), { "power" } },
    { "combo", Group("Combo points", {
      { "enabled", Toggle("Enabled", "combo.enabled") },
      { "hideWhenZero", Toggle("Hide when zero", "combo.hideWhenZero") },
      { "width", Range("Width", "combo.width", 2, 40, 1) },
      { "height", Range("Height", "combo.height", 2, 40, 1) },
      { "radius", Range("Corner radius", "combo.radius", 0, 20, 1, { desc = "0 = square. Half the smaller side or more gives circles." }) },
      { "spacing", Range("Spacing", "combo.spacing", 0, 20, 1) },
      { "texture", Media("Texture", "combo.texture", "statusbar") },
      { "filled", Color("Filled color", "combo.filled", true) },
      { "empty", Color("Empty color", "combo.empty", true) },
      { "pos", Pos("combo.pos") },
    }), { "combo" } },
    { "raidMarker", Group("Raid marker", {
      { "enabled", Toggle("Enabled", "raidMarker.enabled") },
      { "size", Range("Size", "raidMarker.size", 8, 64, 1) },
      { "pos", Pos("raidMarker.pos") },
    }), { "raidMarker" } },
    { "highlight", Group("Target highlight", {
      { "scaleEnabled", Toggle("Enlarge target", "highlight.scaleEnabled") },
      { "scale", Range("Target scale", "highlight.scale", 1, 2, 0.05, { isPercent = true }) },
      { "borderEnabled", Toggle("Color target border", "highlight.borderEnabled") },
      { "borderColor", Color("Border color", "highlight.borderColor", true) },
      { "fadeEnabled", Toggle("Fade other plates", "highlight.fadeEnabled") },
      { "fadeAlpha", Range("Faded opacity", "highlight.fadeAlpha", 0, 1, 0.05, { isPercent = true }) },
    }), { "highlight" } },
    { "cvars", CVarGroup(), { "cvars" } },
  }
  for i, s in ipairs(sections) do
    s[2].order = i
    s[2].args.reset = ResetButton(s[3])
    options.args[s[1]] = s[2]
  end
  -- Tabs registered by element files via ns.RegisterOptions (Core.lua).
  local O = { Toggle = Toggle, Range = Range, Select = Select, Color = Color, Media = Media, Group = Group,
              Pos = Pos, TextGroup = TextGroup, Get = Get, Set = Set }
  for _, s in ipairs(ns.optionSections) do
    local g = s.build(O)
    g.order = s.order
    if s.reset then g.args.reset = ResetButton(s.reset) end
    options.args[s.key] = g
  end

  -- Hide each game setting whose CVar is missing on this client (names match ns.ApplyCVars in Core.lua).
  local g = options.args.cvars.args
  g.maxDistance.hidden = function() return not ns.CVarExists("nameplateMaxDistance") end
  g.occludedAlpha.hidden = function() return not ns.CVarExists("nameplateOccludedAlphaMult") end
  g.minAlpha.hidden = function() return not ns.CVarExists("nameplateMinAlpha") end

  options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(ns.db)
  options.args.profiles.order = 100

  -- Getters re-read ns.P, so a profile change only needs the dialog redrawn.
  local function Redraw() AceConfigRegistry:NotifyChange("BabonyaPlates") end
  local cb = {}
  for _, e in ipairs({ "OnProfileChanged", "OnProfileCopied", "OnProfileReset" }) do
    ns.db.RegisterCallback(cb, e, Redraw)
  end
  return options
end

-- A function table is evaluated lazily, after Core's OnInitialize has created ns.db.
AceConfig:RegisterOptionsTable("BabonyaPlates", Build)
AceConfigDialog:AddToBlizOptions("BabonyaPlates", "BabonyaPlates")

ns.OpenOptions = function() AceConfigDialog:Open("BabonyaPlates") end
