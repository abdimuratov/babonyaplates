local ADDON, ns = ...

ns.defaults = {
  profile = {
    categories = {
      enemyPlayer    = { name = true,  bar = true,  power = false },
      friendlyPlayer = { name = true,  bar = false, power = false },
      groupMember    = { name = true,  bar = false, power = false },
      guildMember    = { name = true,  bar = false, power = false },
      hostileNPC     = { name = true,  bar = true,  power = false },
      neutralNPC     = { name = true,  bar = true,  power = false },
      friendlyNPC    = { name = true,  bar = false, power = false },
      pet            = { name = false, bar = false, power = false },
      critter        = { name = false, bar = false, power = false },
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
  },
}
