local ADDON, ns = ...

ns.defaults = {
  profile = {
    categories = {
      enemyPlayer    = { name = true,  bar = true,  power = false, cast = true, auras = true, combatOnly = false },
      friendlyPlayer = { name = true,  bar = false, power = false, cast = false, auras = false, combatOnly = false },
      groupMember    = { name = true,  bar = false, power = false, cast = false, auras = false, combatOnly = false },
      guildMember    = { name = true,  bar = false, power = false, cast = false, auras = false, combatOnly = false },
      hostileNPC     = { name = true,  bar = true,  power = false, cast = true, auras = true, combatOnly = false },
      neutralNPC     = { name = true,  bar = true,  power = false, cast = true, auras = true, combatOnly = false },
      friendlyNPC    = { name = true,  bar = false, power = false, cast = false, auras = false, combatOnly = false },
      pet            = { name = false, bar = false, power = false, cast = false, auras = false, combatOnly = false },
      critter        = { name = false, bar = false, power = false, cast = false, auras = false, combatOnly = false },
    },
    quest = { override = true, icon = true, size = 16, pos = { point = "LEFT", relPoint = "RIGHT", x = 4, y = 0 } },
    colors = {
      classColors = true,
      hostile    = { r = 0.85, g = 0.15, b = 0.15, a = 1 },
      neutral    = { r = 0.9,  g = 0.8,  b = 0.1,  a = 1 },
      friendly   = { r = 0.2,  g = 0.8,  b = 0.2,  a = 1 },
      tapped     = { r = 0.5,  g = 0.5,  b = 0.5,  a = 1 },
      background = { r = 0,    g = 0,    b = 0,    a = 0.6 },
    },
    bar = {
      width = 120, height = 10, scale = 1, texture = "Blizzard",
      border = { enabled = true, texture = "Blizzard Tooltip", size = 1, radius = 0, color = { r = 0, g = 0, b = 0, a = 1 } },
    },
    name   = { font = "Friz Quadrata TT", size = 10, outline = "OUTLINE", pos = { point = "BOTTOM", relPoint = "TOP", x = 0, y = 2 } },
    hpText = { mode = "percent", showMax = false, font = "Friz Quadrata TT", size = 9, outline = "OUTLINE", pos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 } },
    power  = { height = 3, pos = { point = "TOP", relPoint = "BOTTOM", x = 0, y = -1 } },
    combo  = {
      enabled = true, hideWhenZero = true, width = 8, height = 8, radius = 0, spacing = 2, texture = "Blizzard",
      filled = { r = 1, g = 0.85, b = 0.1, a = 1 }, empty = { r = 0.2, g = 0.2, b = 0.2, a = 0.6 },
      pos = { point = "TOP", relPoint = "BOTTOM", x = 0, y = -3 },
    },
    raidMarker = { enabled = true, size = 18, pos = { point = "RIGHT", relPoint = "LEFT", x = -4, y = 0 } },
    highlight = {
      scaleEnabled = true, scale = 1.2, borderEnabled = true, borderColor = { r = 1, g = 1, b = 1, a = 1 },
      fadeEnabled = true, fadeAlpha = 0.6,
    },
    cvars = { maxDistance = 45 },

    -- v2 ---------------------------------------------------------------------------------------
    -- Threat colors hostile/neutral NPC bars while they are in combat. role: "auto" | "tank" | "dps".
    threat = {
      enabled = true, role = "auto",
      tankSecure   = { r = 0.2, g = 0.8, b = 0.2, a = 1 }, tankInsecure = { r = 1, g = 0.8, b = 0, a = 1 },
      tankLost     = { r = 0.9, g = 0.1, b = 0.1, a = 1 },
      dpsLow       = { r = 0.2, g = 0.8, b = 0.2, a = 1 }, dpsHigh      = { r = 1, g = 0.55, b = 0, a = 1 },
      dpsAggro     = { r = 0.9, g = 0.1, b = 0.1, a = 1 },
    },
    -- Bar color below threshold % health on attackable units (wins over threat/reaction, not over tapped).
    execute = { enabled = true, threshold = 20, color = { r = 0.7, g = 0.3, b = 1, a = 1 } },
    absorbs = { enabled = true, color = { r = 1, g = 1, b = 1, a = 0.5 } },
    -- Cast bar width follows bar.width. Shown when the category's cast toggle is on, even on name-only plates.
    castBar = {
      height = 8, texture = "Blizzard", showIcon = true, iconSize = 16, showTime = true,
      font = "Friz Quadrata TT", size = 8, outline = "OUTLINE",
      cast = { r = 1, g = 0.7, b = 0, a = 1 }, channel = { r = 0.3, g = 0.7, b = 1, a = 1 },
      shield = { r = 0.6, g = 0.6, b = 0.6, a = 1 }, interrupted = { r = 0.9, g = 0.1, b = 0.1, a = 1 },
      pos = { point = "TOP", relPoint = "BOTTOM", x = 0, y = -4 },
    },
    -- All debuffs are shown; the player's debuffs and purgeable buffs stand out (bigger, colored border).
    auras = {
      mine      = { enabled = true, size = 22, max = 6, border = { r = 1, g = 0.82, b = 0, a = 1 } },
      others    = { enabled = true, size = 16, max = 6, alpha = 0.7 },
      purgeable = { enabled = true, size = 22, max = 3, border = { r = 0.2, g = 0.6, b = 1, a = 1 } },
      spacing = 2, showTimer = true, showStacks = true, font = "Friz Quadrata TT", fontSize = 9,
      pos = { point = "BOTTOM", relPoint = "TOP", x = 0, y = 16 },
    },
    classification = { enabled = true, size = 14, pos = { point = "CENTER", relPoint = "TOPLEFT", x = 0, y = 0 } },
    level = { enabled = true, font = "Friz Quadrata TT", size = 9, outline = "OUTLINE", pos = { point = "LEFT", relPoint = "RIGHT", x = 3, y = 0 } },
  },
}
