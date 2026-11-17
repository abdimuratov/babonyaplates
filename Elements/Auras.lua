local ADDON, ns = ...

-- Auras via Blizzard's CustomAuraContainerTemplate (pattern: ThreatPlates Widgets/AurasWidgetMidnight.lua).
-- Addon code never touches aura buttons: they are configured only inside the group initializer, which Blizzard
-- runs in a secure call (TP :79,:437-470 "forbidden object" trap). Per plate: pf.auras holds a debuff container
-- (groups "mine" then "others") and a buff container (group "purgeable") anchored above it.

local CreateFrame, InCombatLockdown, ipairs, pairs, max = CreateFrame, InCombatLockdown, ipairs, pairs, math.max

local FD = AnchorUtil and AnchorUtil.FlowDirection
local SORT, DIR = _G.AuraContainerSortMethod, _G.AuraContainerSortDirection
-- Feature test as TP :33; the enums are needed for layout and sorting.
local HAS = (C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate")
  and FD and SORT and DIR) and true or false

if not HAS then
  ns.RegisterOptions{ key = "auras", order = 6.6, build = function(o)
    return o.Group("Auras", { { "note", { type = "description", name = "This client has no aura support." } } })
  end }
  return
end

local NP = "INCLUDE_NAME_PLATE_ONLY" -- required, or nameplate-only auras are dropped (TP :98-101)
local POOL = 40 -- containers per kind, built up front out of combat (TP :117,:685-715)
local ICON = "Interface\\Icons\\"
local DARK = { r = 0, g = 0, b = 0, a = 1 }
local BW = { mine = 2, others = 1, purgeable = 2 } -- border thickness in pixels
local GROUPS = { "mine", "others", "purgeable" }
local SAMPLE = { -- preview: group, icon
  { "mine", "Spell_Shadow_ShadowWordPain" }, { "mine", "Ability_Rogue_Rupture" },
  { "others", "Spell_Nature_Slow" }, { "others", "Spell_Fire_Immolation" },
  { "purgeable", "Spell_Holy_PowerWordShield" },
}

local pool, nextFree = { debuff = {}, buff = {} }, { debuff = 1, buff = 1 }

-- Duration text like Blizzard cooldown numbers: 12, 2m, 2h (TP :272-281). Missing API = default formatter.
local formatter
if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum.NumericRuleFormatRounding then
  local up = Enum.NumericRuleFormatRounding.Up
  formatter = C_StringUtil.CreateNumericRuleFormatter()
  formatter:SetBreakpoints({
    { threshold = 0, step = 1, rounding = up, format = "%d" },
    { threshold = 90, format = "%dm", components = { { div = 60, step = 1, rounding = up } } },
    { threshold = 5400, format = "%dh", components = { { div = 3600, step = 1, rounding = up } } },
  })
end

local function SetFont(fs, A)
  fs:SetFont(ns.Fetch("font", A.font), A.fontSize, "OUTLINE")
end

-- Group initializer, run by Blizzard once per new button (TP :297-414). Reads the profile at that moment, so
-- border colour, opacity, font, timer and stack visibility only reach buttons created after a change.
local function InitButton(button, g)
  local A = ns.P.auras
  local c = A[g]
  button:SetSize(c.size, c.size)
  if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end -- never eat plate clicks
  if g == "others" then pcall(button.SetAlpha, button, c.alpha) end

  local border = button:CreateTexture(nil, "BACKGROUND")
  local bw, col = BW[g], c.border or DARK
  border:SetPoint("TOPLEFT", -bw, bw)
  border:SetPoint("BOTTOMRIGHT", bw, -bw)
  border:SetColorTexture(col.r, col.g, col.b, col.a or 1)

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(button)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  button:SetIcon(icon)

  local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
  cd:SetAllPoints(icon)
  cd:SetReverse(true)
  cd:SetHideCountdownNumbers(true)
  cd:SetDrawEdge(false)
  cd:SetFrameLevel(button:GetFrameLevel()) -- same level as TP, so the icon does not paint over the swipe
  button:SetDurationCooldown(cd)

  -- Font must be set before the binding (TP :379-386).
  local stacks = button:CreateFontString(nil, "OVERLAY")
  SetFont(stacks, A)
  stacks:SetPoint("BOTTOMRIGHT", 2, -1)
  button:SetApplicationCount(stacks)
  if not A.showStacks then stacks:Hide() end

  local timer = button:CreateFontString(nil, "OVERLAY")
  SetFont(timer, A)
  timer:SetPoint("CENTER")
  button:SetDurationText(timer, formatter and { textFormatter = formatter } or nil)
  if not A.showTimer then timer:Hide() end
end

local function NewContainer(kind)
  local c = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
  local function Group(key, effect)
    c:AddAuraGroup(key, effect, {
      initializeFrame = function(button) InitButton(button, key) end,
      sortMethod = SORT.Default, sortDirection = DIR.Normal,
    })
  end
  if kind == "debuff" then Group("mine", "HARMFUL"); Group("others", "HARMFUL") else Group("purgeable", "HELPFUL") end
  c:SetEnabled(false)
  return c
end

-- Containers cannot be created in combat (TP :685-690); retried on PLAYER_REGEN_ENABLED.
local function MakePool()
  if InCombatLockdown() then return end
  for kind, list in pairs(pool) do
    for i = #list + 1, POOL do list[i] = NewContainer(kind) end
  end
end

local function Take(kind)
  local c = pool[kind][nextFree[kind]]
  if c then nextFree[kind] = nextFree[kind] + 1 end
  return c
end

-- Row sizes: debuff row width, its cell height, purgeable row width. A cell is the icon plus its border.
local function Metrics(A)
  local dw, dh, pw = 0, 0, 0
  for _, g in ipairs(GROUPS) do
    local c = A[g]
    if c.enabled then
      local cell = c.size + 2 * BW[g]
      local w = c.max * (cell + A.spacing)
      if g == "purgeable" then
        pw = w
      else
        dw, dh = dw + w, max(dh, cell)
      end
    end
  end
  return dw, dh, pw
end

local function Anchor(pf)
  if pf.debuffC then pf.debuffC:ClearAllPoints(); pf.debuffC:SetPoint("BOTTOMLEFT", pf.auras, "BOTTOMLEFT") end
  if pf.buffC then
    pf.buffC:ClearAllPoints()
    pf.buffC:SetPoint("BOTTOMLEFT", pf.auras, "TOPLEFT", 0, ns.P.auras.spacing + 2)
  end
end

local function Attach(pf)
  local added
  if not pf.debuffC then pf.debuffC, added = Take("debuff"), true end
  if not pf.buffC then pf.buffC, added = Take("buff"), true end
  if not added then return end
  for _, c in ipairs({ pf.debuffC or false, pf.buffC or false }) do
    if c then c:SetParent(pf.auras); c:SetEnabled(false) end
  end
  Anchor(pf)
end

-- Filter, count, sort and layout per group (TP :1074-1090); all of these are safe to call while auras are secret.
local function ConfigGroup(c, key, filter, A)
  local g = A[key]
  local gap = A.spacing + 2 * BW[key]
  c:SetAuraGroupFilterString(key, filter)
  c:SetAuraGroupCandidateFilters(key, {})
  c:SetAuraGroupMaxFrameCount(key, g.enabled and g.max or 0)
  c:SetAuraGroupSortMethod(key, SORT.Default, DIR.Normal)
  c:SetAuraGroupLayout(key, { elementWidth = g.size, elementHeight = g.size, elementSpacing = gap, lineSpacing = gap })
end

local function ConfigContainer(c, line, unit)
  c:SetFlowLayoutAnchorPoint("BOTTOMLEFT")
  c:SetFlowLayoutGrowthDirection(FD.Right, FD.Up)
  c:SetFlowLayoutMaximumLineSize(max(line, 1))
  c:SetUnit(unit)
  c:SetEnabled(true)
end

local function Off(pf)
  if pf.debuffC then pf.debuffC:SetEnabled(false) end
  if pf.buffC then pf.buffC:SetEnabled(false) end
  pf.auraKey = nil
  if pf.auras then pf.auras:Hide() end
end

local function Preview(pf)
  local A, f = ns.P.auras, pf.auras
  local s = pf.sample
  if not s then
    s = {}
    for i, d in ipairs(SAMPLE) do
      local b = CreateFrame("Frame", nil, f)
      b:EnableMouse(false)
      local bw = BW[d[1]]
      b.border = b:CreateTexture(nil, "BACKGROUND")
      b.border:SetPoint("TOPLEFT", -bw, bw)
      b.border:SetPoint("BOTTOMRIGHT", bw, -bw)
      b.icon = b:CreateTexture(nil, "ARTWORK")
      b.icon:SetAllPoints(b)
      b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      b.icon:SetTexture(ICON .. d[2])
      s[i] = b
    end
    pf.sample = s
  end
  local x, shown = { debuff = 0, buff = 0 }, {}
  for i, d in ipairs(SAMPLE) do
    local g, b = d[1], s[i]
    local c = A[g]
    shown[g] = (shown[g] or 0) + 1
    if c.enabled and shown[g] <= c.max then
      local col = c.border or DARK
      local row = g == "purgeable" and "buff" or "debuff"
      b:SetSize(c.size, c.size)
      b:SetAlpha(g == "others" and c.alpha or 1)
      b.border:SetColorTexture(col.r, col.g, col.b, col.a or 1)
      b:ClearAllPoints()
      if row == "buff" then
        b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", x[row], A.spacing + 2)
      else
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x[row], 0)
      end
      x[row] = x[row] + c.size + A.spacing + 2 * BW[g]
      b:Show()
    else
      b:Hide()
    end
  end
  f:Show()
end

local function Update(pf)
  local f = pf.auras
  if not f then return end
  if pf.isPreview then Preview(pf) return end
  if pf.sample then for _, b in ipairs(pf.sample) do b:Hide() end end
  local unit = pf.unit
  if not unit or pf.showAuras == false then
    if pf.auraKey or f:IsShown() then Off(pf) end
    return
  end
  if pf.auraKey == unit then return end -- already configured for this unit; style/remove clear the key
  if not (pf.debuffC and pf.buffC) then
    MakePool()
    Attach(pf)
  end
  if not (pf.debuffC or pf.buffC) then return end -- pool not built yet (combat), retried on regen
  local A = ns.P.auras
  local dw, _, pw = Metrics(A)
  if pf.debuffC then
    ConfigGroup(pf.debuffC, "mine", "HARMFUL|PLAYER|" .. NP, A)
    ConfigGroup(pf.debuffC, "others", "HARMFUL|!PLAYER|" .. NP, A)
    ConfigContainer(pf.debuffC, dw, unit)
  end
  if pf.buffC then
    ConfigGroup(pf.buffC, "purgeable", "HELPFUL|DISPELLABLE|" .. NP, A)
    ConfigContainer(pf.buffC, pw, unit)
  end
  pf.auraKey = unit
  f:Show()
end

ns.RegisterElement{
  create = function(pf)
    local f = CreateFrame("Frame", nil, pf.root)
    f:EnableMouse(false)
    f:SetFrameLevel(pf.root:GetFrameLevel() + 9)
    f:Hide()
    pf.auras = f
  end,
  style = function(pf)
    local A = ns.P.auras
    local dw, dh, pw = Metrics(A)
    pf.auras:SetSize(max(dw, pw, 1), max(dh, 1))
    ns.ApplyPos(pf.auras, pf.health, A.pos)
    pf.auraKey = nil
    Anchor(pf)
    Update(pf)
  end,
  update = Update,
  remove = Off,
  events = {
    PLAYER_LOGIN = MakePool,
    PLAYER_REGEN_ENABLED = function()
      MakePool()
      for _, pf in pairs(ns.plates) do
        if not (pf.debuffC and pf.buffC) then Update(pf) end
      end
    end,
  },
}

ns.RegisterOptions{
  key = "auras", order = 6.6, reset = { "auras" },
  build = function(o)
    local function Row(name, key, extra)
      local list = {
        { "enabled", o.Toggle("Enabled", "auras." .. key .. ".enabled") },
        { "size", o.Range("Icon size", "auras." .. key .. ".size", 8, 48, 1) },
        { "max", o.Range("Max icons", "auras." .. key .. ".max", 1, 12, 1) },
      }
      list[#list + 1] = extra
      return { key, o.Group(name, list, { inline = true }) }
    end
    return o.Group("Auras", {
      { "note", { type = "description", fontSize = "medium",
        name = "Which plates show auras is set per category on the Visibility tab. Size, count and spacing update at once. "
          .. "Border colour, opacity, font, timer and stacks are read when Blizzard builds an icon, so they may need /reload "
          .. "to reach icons already created." } },
      Row("My debuffs", "mine", { "border", o.Color("Border color", "auras.mine.border", true) }),
      Row("Other debuffs", "others", { "alpha", o.Range("Opacity", "auras.others.alpha", 0.1, 1, 0.05, { isPercent = true }) }),
      Row("Purgeable buffs", "purgeable", { "border", o.Color("Border color", "auras.purgeable.border", true) }),
      { "spacing", o.Range("Spacing", "auras.spacing", 0, 10, 1) },
      { "showTimer", o.Toggle("Show timer", "auras.showTimer") },
      { "showStacks", o.Toggle("Show stacks", "auras.showStacks") },
      { "font", o.Media("Font", "auras.font", "font") },
      { "fontSize", o.Range("Font size", "auras.fontSize", 6, 20, 1) },
      { "pos", o.Pos("auras.pos") },
    })
  end,
}
