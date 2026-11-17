local ADDON, ns = ...

local issecretvalue = issecretvalue or function() return false end
local UnitClassification, UnitEffectiveLevel, UnitCanAttack = UnitClassification, UnitEffectiveLevel, UnitCanAttack
local GetAtlasInfo = C_Texture and C_Texture.GetAtlasInfo

-- Blizzard atlas when it exists on this client, else a classic texture path.
local ICONS = {
  gold = { atlas = "nameplates-icon-elite-gold", tex = "Interface\\Tooltips\\EliteNameplateIcon" },
  silver = { atlas = "nameplates-icon-elite-silver", tex = "Interface\\Tooltips\\RareEliteNameplateIcon" },
  skull = { tex = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" },
}
local ELITE = { elite = true, rareelite = true }
local WHITE = { r = 1, g = 1, b = 1 }

local function SetIcon(t, kind)
  local i = ICONS[kind]
  if i.atlas and GetAtlasInfo and GetAtlasInfo(i.atlas) then
    t:SetAtlas(i.atlas)
  else
    t:SetTexCoord(0, 1, 0, 1)
    t:SetTexture(i.tex)
  end
end

-- Forever's own nameplate thresholds (ThreatPlates Nameplate.lua:293-302); retail helper otherwise.
local function LevelColor(level)
  local c
  if NameplateLevelFrameMixin and NameplateLevelFrameMixin.GetDifficultyColor then
    local ok, v = pcall(NameplateLevelFrameMixin.GetDifficultyColor, NameplateLevelFrameMixin, level - UnitEffectiveLevel("player"))
    if ok then c = v end
  elseif GetCreatureDifficultyColor then
    c = GetCreatureDifficultyColor(level)
  end
  return type(c) == "table" and c.r and c or WHITE
end

local function Update(pf)
  local icon, text = pf.classIcon, pf.levelText
  if not icon then return end
  local P = ns.P
  local kind, str, color
  if pf.isPreview then
    kind, str, color = "gold", "60+", WHITE
  elseif pf.unit then
    local cls, lvl = UnitClassification(pf.unit), UnitEffectiveLevel(pf.unit)
    if issecretvalue(cls) or issecretvalue(lvl) then return end -- keep what is shown
    if cls == "worldboss" or lvl == -1 then
      kind = "skull"
    elseif cls == "elite" or cls == "rareelite" then
      kind = "gold"
    elseif cls == "rare" then
      kind = "silver"
    end
    if cls == "rareelite" then kind = "silver" end
    if lvl and lvl > 0 then
      str = lvl .. (ELITE[cls] and "+" or "")
      local can = UnitCanAttack("player", pf.unit)
      if issecretvalue(can) then color = text.lastColor or WHITE else color = can and LevelColor(lvl) or WHITE end
    end
  end
  if kind and P.classification.enabled and pf.showBar then
    SetIcon(icon, kind)
    icon:Show()
  else
    icon:Hide()
  end
  if str and P.level.enabled and pf.showName then
    text.lastColor = color
    text:SetText(str)
    text:SetTextColor(color.r, color.g, color.b)
    text:Show()
  else
    text:Hide()
  end
end

local function UpdateUnit(_, unit)
  local pf = unit and ns.plates[unit]
  if pf then Update(pf) end
end

ns.RegisterElement{
  create = function(pf)
    pf.classIcon = pf.root:CreateTexture(nil, "OVERLAY")
    pf.classIcon:Hide()
    pf.levelText = pf.root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pf.levelText:Hide()
  end,
  style = function(pf)
    local c, l = ns.P.classification, ns.P.level
    pf.classIcon:SetSize(c.size, c.size)
    ns.ApplyPos(pf.classIcon, pf.health, c.pos)
    pf.levelText:SetFont(ns.Fetch("font", l.font), l.size, l.outline ~= "NONE" and l.outline or "")
    ns.ApplyPos(pf.levelText, pf.name, l.pos)
    Update(pf)
  end,
  update = Update,
  remove = function(pf) pf.classIcon:Hide(); pf.levelText:Hide() end,
  events = {
    UNIT_LEVEL = UpdateUnit,
    UNIT_CLASSIFICATION_CHANGED = UpdateUnit,
    PLAYER_LEVEL_UP = function()
      for _, pf in pairs(ns.plates) do Update(pf) end
    end,
  },
}

ns.RegisterOptions{
  key = "classification", order = 8.5, reset = { "classification", "level" },
  build = function(o)
    return o.Group("Elite & level", {
      { "icon", o.Group("Elite icon", {
        { "enabled", o.Toggle("Enabled", "classification.enabled") },
        { "size", o.Range("Size", "classification.size", 8, 64, 1) },
        { "pos", o.Pos("classification.pos") },
      }) },
      { "level", o.TextGroup("Level text", "level", { { "enabled", o.Toggle("Enabled", "level.enabled") } }) },
    })
  end,
}
