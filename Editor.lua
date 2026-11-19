local ADDON, ns = ...

local CreateFrame, GetCursorPosition, IsMouseButtonDown, IsShiftKeyDown = CreateFrame, GetCursorPosition, IsMouseButtonDown, IsShiftKeyDown
local floor, min, max, abs, pairs, ipairs = math.floor, math.min, math.max, math.abs, pairs, ipairs
local BackdropTemplate = BackdropTemplateMixin and "BackdropTemplate"

local FRAME_NAME = "BabonyaPlatesEditorFrame" -- global name is required by UISpecialFrames
local PREVIEW_SCALE = 2
local RANGE = 100 -- same limit as the X/Y sliders in Options.lua

-- key: profile section with .pos; region: pf field that carries it
local ELEMENTS = {
  { key = "name",       region = "name",       label = "Name" },
  { key = "hpText",     region = "hpText",     label = "Health text" },
  { key = "power",      region = "power",      label = "Power bar" },
  { key = "combo",      region = "combo",      label = "Combo points" },
  { key = "raidMarker", region = "raidMarker", label = "Raid marker" },
  { key = "quest",      region = "questIcon",  label = "Quest icon" },
  { key = "castBar",        region = "castBar",   label = "Cast bar" },
  { key = "auras",          region = "auras",     label = "Auras" },
  { key = "classification", region = "classIcon", label = "Elite icon" },
  { key = "level",          region = "levelText", label = "Level", rel = "name" },
}

local win, pf

local function Clamp(v)
  return max(-RANGE, min(RANGE, floor(v + 0.5)))
end

local function HpSample()
  local mode, showMax = ns.P.hpText.mode, ns.P.hpText.showMax
  local cur = showMax and "65K / 100K" or "65K"
  if mode == "value" then return cur end
  if mode == "both" then return cur .. " - 65%" end
  return "65%"
end

-- Sample data only, no unit API.
local function FillSample()
  local c = ns.P.colors.hostile
  pf.health:SetMinMaxValues(0, 100)
  pf.health:SetValue(65)
  pf.health:GetStatusBarTexture():SetVertexColor(c.r, c.g, c.b, c.a or 1)
  pf.name:SetText("Preview Mob")
  pf.name:SetTextColor(c.r, c.g, c.b, 1)
  pf.hpText:SetText(HpSample())
  local pc = (PowerBarColor and PowerBarColor.MANA) or { r = 0.3, g = 0.5, b = 0.9 }
  pf.power:SetMinMaxValues(0, 100)
  pf.power:SetValue(70)
  pf.power:GetStatusBarTexture():SetVertexColor(pc.r, pc.g, pc.b)
end

function ns.RefreshEditor()
  if not win or not win:IsShown() then return end
  pf.showName, pf.showBar, pf.showPower, pf.hasPower = true, true, true, true
  pf.showCast, pf.showAuras = true, true
  ns.StylePlate(pf)
  ns.ApplyVisibility(pf)
  FillSample()
  if ns.UpdateElements then ns.UpdateElements(pf) end
  for _, e in ipairs(ELEMENTS) do
    if e.handle then e.handle:SetShown(pf[e.region]:IsShown()) end
  end
end

local function Finish(e)
  e.dragging = nil
  e.handle:SetScript("OnUpdate", nil)
  e.handle:SetAlpha(e.handle:IsMouseOver() and 1 or 0)
  ns.RefreshAll()
  local reg = LibStub("AceConfigRegistry-3.0", true)
  if reg then reg:NotifyChange("BabonyaPlates") end
end

local function DragUpdate(e)
  if not IsMouseButtonDown("LeftButton") then return Finish(e) end -- released outside the handle
  local cx, cy = GetCursorPosition()
  local s = pf.root:GetEffectiveScale() -- offsets live in the root's coordinate space
  local pos = ns.P[e.key].pos
  local dx, dy = (cx - e.cx) / s, (cy - e.cy) / s
  if IsShiftKeyDown() then -- Shift: move along the main axis only
    if abs(dx) > abs(dy) then dy = 0 else dx = 0 end
  end
  pos.x = Clamp(e.sx + dx)
  pos.y = Clamp(e.sy + dy)
  ns.ApplyPos(pf[e.region], pf[e.rel or "health"], pos) -- only x/y change, anchors stay
end

local function MakeHandle(e)
  local h = CreateFrame("Button", nil, win.stage, BackdropTemplate)
  h:SetFrameLevel(pf.root:GetFrameLevel() + 20)
  h:SetAllPoints(pf[e.region])
  if h.SetBackdrop then
    h:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    h:SetBackdropBorderColor(1, 0.82, 0, 1)
  end
  h:SetAlpha(0)
  h:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
  h:SetScript("OnEnter", function(self)
    self:SetAlpha(1)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(e.label)
    GameTooltip:Show()
  end)
  h:SetScript("OnLeave", function(self)
    if not e.dragging then self:SetAlpha(0) end
    GameTooltip:Hide()
  end)
  h:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    local pos = ns.P[e.key].pos
    e.cx, e.cy = GetCursorPosition()
    e.sx, e.sy = pos.x, pos.y
    e.dragging = true
    self:SetScript("OnUpdate", function() DragUpdate(e) end)
  end)
  h:SetScript("OnMouseUp", function()
    if e.dragging then Finish(e) end
  end)
  e.handle = h
end

local function ResetPositions()
  for _, e in ipairs(ELEMENTS) do
    local src = ns.defaults.profile[e.key].pos
    local copy = {}
    for k, v in pairs(src) do copy[k] = v end
    ns.P[e.key].pos = copy
  end
  ns.RefreshAll()
  local reg = LibStub("AceConfigRegistry-3.0", true)
  if reg then reg:NotifyChange("BabonyaPlates") end
end

local function Build()
  win = CreateFrame("Frame", FRAME_NAME, UIParent, BackdropTemplate)
  win:SetSize(560, 360)
  win:SetPoint("CENTER")
  win:SetFrameStrata("DIALOG")
  win:SetClampedToScreen(true)
  win:SetMovable(true)
  win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  if win.SetBackdrop then
    win:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
  end
  table.insert(UISpecialFrames, FRAME_NAME)

  local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -18)
  title:SetText("BabonyaPlates layout editor")

  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  local hint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("BOTTOMLEFT", 20, 22)
  hint:SetText("Drag elements to move them; hold Shift to move only horizontally or vertically.\nUse the settings window for exact values and anchors.")

  local reset = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  reset:SetSize(130, 22)
  reset:SetPoint("BOTTOMRIGHT", -20, 46)
  reset:SetText("Reset positions")
  reset:SetScript("OnClick", ResetPositions)

  -- Stage scales the whole preview; the plate itself is built and styled by the real plate code.
  local stage = CreateFrame("Frame", nil, win)
  stage:SetSize(1, 1)
  stage:SetScale(PREVIEW_SCALE)
  stage:SetPoint("CENTER", win, "CENTER", 0, 5)
  win.stage = stage

  pf = ns.CreatePlateFrames(stage)
  pf.isPreview = true
  pf.root:SetPoint("CENTER", stage, "CENTER")

  -- An element that is unsupported on this client may not create its region; it gets no handle.
  for _, e in ipairs(ELEMENTS) do
    if pf[e.region] then MakeHandle(e) end
  end
  win:SetScript("OnShow", ns.RefreshEditor)
end

function ns.OpenEditor()
  if not win then Build() end
  win:Show()
  ns.RefreshEditor()
end
