local ADDON, ns = ...

local issecretvalue = issecretvalue or function() return false end
local CreateFrame, C_Timer, format = CreateFrame, C_Timer, string.format
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
local UnitCastingDuration, UnitChannelDuration = UnitCastingDuration, UnitChannelDuration
local EvalColor = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
local INTERP = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
local DIR_ELAPSED = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime
local DIR_REMAINING = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
local HOLD = 0.6
local PREVIEW_ICON = "Interface\\Icons\\Spell_Fire_FlameBolt"
local SHIELD_ATLAS = "nameplates-InterruptShield"
local SHIELD_FILE = "Interface\\CastingBar\\UI-CastingBar-Arena-Shield"

-- pf.castState: nil (idle) | "cast" | "hold" (showing "Interrupted"). pf.castToken invalidates pending hold timers.

-- Event ids may be nil or secret; then we cannot tell them apart, so treat them as the same cast.
local function Same(a, b)
  if a == nil or b == nil or issecretvalue(a) or issecretvalue(b) then return true end
  return a == b
end

local function Tint(f, c, ni)
  local tex = f.bar:GetStatusBarTexture()
  if issecretvalue(ni) and EvalColor then
    -- Never branch on the secret flag: pick each channel inside the API (ThreatPlates Compatibility.lua:229-234).
    local s = ns.P.castBar.shield
    tex:SetVertexColor(EvalColor(ni, s.r, c.r), EvalColor(ni, s.g, c.g), EvalColor(ni, s.b, c.b), EvalColor(ni, s.a, c.a))
  else
    if not issecretvalue(ni) and ni then c = ns.P.castBar.shield end
    tex:SetVertexColor(c.r, c.g, c.b, c.a)
  end
  if issecretvalue(ni) and f.shield.SetAlphaFromBoolean then
    f.shield:SetAlphaFromBoolean(ni, 1, 0)
  else
    f.shield:SetAlpha((not issecretvalue(ni) and ni) and 1 or 0)
  end
end

local function OnUpdate(f)
  local d = f.duration
  if d and ns.P.castBar.showTime then f.time:SetText(format("%.1f", d:GetRemainingDuration())) end
end

local function End(pf)
  local f = pf.castBar
  pf.castToken = (pf.castToken or 0) + 1
  pf.castState, pf.castId = nil, nil
  f.duration = nil
  f:SetScript("OnUpdate", nil)
  f:Hide()
end

-- Reads the unit's current cast/channel and (re)starts the bar. barid: castBarID from the event, if any.
local function Begin(pf, channel, barid)
  local f, unit = pf.castBar, pf.unit
  local name, text, tex, trade, ni, id, _
  if channel then
    name, text, tex, _, _, trade, ni, _, _, _, id = UnitChannelInfo(unit)
  else
    name, text, tex, _, _, trade, _, ni, _, id = UnitCastingInfo(unit)
  end
  local d
  if channel then
    d = UnitChannelDuration and UnitChannelDuration(unit)
  else
    d = UnitCastingDuration and UnitCastingDuration(unit)
  end
  local isCast = issecretvalue(name) or name ~= nil
  if not isCast or (not issecretvalue(trade) and trade) or not d or not f.bar.SetTimerDuration or not INTERP then
    if pf.castState == "cast" then End(pf) end -- no cast (or none we can draw) anymore
    return
  end

  pf.castToken = (pf.castToken or 0) + 1 -- cancels a pending "Interrupted" hold
  pf.castState, pf.castChannel, pf.castId = "cast", channel, barid or id
  f.duration = d
  f.bar:SetTimerDuration(d, INTERP, channel and DIR_REMAINING or DIR_ELAPSED)
  f.text:SetText(text)
  f.icon:SetTexture(tex)
  Tint(f, channel and ns.P.castBar.channel or ns.P.castBar.cast, ni)
  f.time:SetText("")
  f:SetScript("OnUpdate", OnUpdate)
  f:Show()
end

local function Interrupted(pf)
  local f = pf.castBar
  local token = (pf.castToken or 0) + 1
  pf.castToken, pf.castState, pf.castId, f.duration = token, "hold", nil, nil
  f:SetScript("OnUpdate", nil)
  f.bar:SetMinMaxValues(0, 1)
  f.bar:SetValue(1)
  Tint(f, ns.P.castBar.interrupted, false)
  f.text:SetText(INTERRUPTED or "Interrupted")
  f.time:SetText("")
  f:Show()
  C_Timer.After(HOLD, function()
    if pf.castToken == token then End(pf) end
  end)
end

local function Preview(pf)
  local f = pf.castBar
  f.bar:SetMinMaxValues(0, 1)
  f.bar:SetValue(0.6)
  f.text:SetText("Fireball")
  f.time:SetText("1.2")
  f.icon:SetTexture(PREVIEW_ICON)
  Tint(f, ns.P.castBar.cast, false)
  f:Show()
end

local function Sync(pf)
  if pf.isPreview then return Preview(pf) end
  if not pf.unit then return end
  if pf.showCast == false then
    if pf.castState then End(pf) end
  elseif pf.castState ~= "hold" then
    Begin(pf, false)
    if pf.castState ~= "cast" then Begin(pf, true) end
  end
end

local function Layout(pf)
  local P = ns.P
  local c, f = P.castBar, pf.castBar
  local w, h = P.bar.width, c.height
  f:SetSize(w, h)
  ns.ApplyPos(f, pf.health, c.pos)
  f.bar:SetStatusBarTexture(ns.Fetch("statusbar", c.texture))

  local r = ns.RoundedRadius(P.bar.border.radius, w, h)
  local bg = P.colors.background
  if ns.RoundedFill(f.bg, r) then
    f.bg:SetVertexColor(bg.r, bg.g, bg.b, bg.a)
  else
    f.bg:SetColorTexture(bg.r, bg.g, bg.b, bg.a)
  end
  ns.RoundedMask(f.bar, f.bar:GetStatusBarTexture(), r)

  local flags = c.outline
  if flags == nil or flags == "NONE" then flags = "" end
  local font = ns.Fetch("font", c.font)
  f.text:SetFont(font, c.size, flags)
  f.time:SetFont(font, c.size, flags)
  f.time:SetShown(c.showTime)
  f.text:ClearAllPoints()
  f.text:SetPoint("LEFT", f, "LEFT", 3, 0)
  if c.showTime then f.text:SetPoint("RIGHT", f.time, "LEFT", -2, 0) else f.text:SetPoint("RIGHT", f, "RIGHT", -3, 0) end

  f.icon:SetSize(c.iconSize, c.iconSize)
  f.icon:SetShown(c.showIcon)
  f.shield:SetSize(h * 1.6, h * 1.6)
end

ns.RegisterElement{
  create = function(pf)
    local f = CreateFrame("Frame", nil, pf.root)
    f:EnableMouse(false)
    f:Hide()
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar") -- needed before GetStatusBarTexture; restyled later
    bar:SetAllPoints(f)
    bar:SetMinMaxValues(0, 1)
    f.bar = bar
    f.bg = bar:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(bar)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("RIGHT", f, "LEFT", -2, 0)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.text = bar:CreateFontString(nil, "OVERLAY")
    f.text:SetFontObject(GameFontNormalSmall)
    f.text:SetJustifyH("LEFT")
    f.text:SetWordWrap(false)
    f.time = bar:CreateFontString(nil, "OVERLAY")
    f.time:SetFontObject(GameFontNormalSmall)
    f.time:SetPoint("RIGHT", f, "RIGHT", -3, 0)
    f.shield = f:CreateTexture(nil, "OVERLAY")
    f.shield:SetPoint("CENTER", f, "LEFT", 0, 0)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(SHIELD_ATLAS) then
      f.shield:SetAtlas(SHIELD_ATLAS)
    else
      f.shield:SetTexture(SHIELD_FILE)
    end
    f.shield:SetAlpha(0)
    pf.castBar = f
  end,
  style = function(pf)
    Layout(pf)
    if pf.isPreview then Preview(pf) end
  end,
  update = Sync,
  remove = End,
  events = (function()
    local function ForCast(fn)
      return function(_, unit, ...)
        local pf = ns.plates[unit]
        if pf and pf.castBar and pf.showCast ~= false then fn(pf, ...) end
      end
    end
    -- STOP-type events only end the cast they belong to (STOP also follows INTERRUPTED).
    local stop = ForCast(function(pf, _, _, id)
      if pf.castState == "cast" and Same(pf.castId, id) then End(pf) end
    end)
    return {
      UNIT_SPELLCAST_START = ForCast(function(pf, _, _, id) Begin(pf, false, id) end),
      UNIT_SPELLCAST_CHANNEL_START = ForCast(function(pf, _, _, id) Begin(pf, true, id) end),
      UNIT_SPELLCAST_CHANNEL_UPDATE = ForCast(function(pf) if pf.castState == "cast" then Begin(pf, true, pf.castId) end end),
      UNIT_SPELLCAST_DELAYED = ForCast(function(pf) if pf.castState == "cast" then Begin(pf, false, pf.castId) end end),
      UNIT_SPELLCAST_INTERRUPTIBLE = ForCast(function(pf) if pf.castState == "cast" then Begin(pf, pf.castChannel, pf.castId) end end),
      UNIT_SPELLCAST_NOT_INTERRUPTIBLE = ForCast(function(pf) if pf.castState == "cast" then Begin(pf, pf.castChannel, pf.castId) end end),
      UNIT_SPELLCAST_STOP = stop,
      UNIT_SPELLCAST_FAILED = stop,
      UNIT_SPELLCAST_INTERRUPTED = ForCast(function(pf, _, _, _, id)
        if pf.castState == "cast" and Same(pf.castId, id) then Interrupted(pf) end
      end),
      UNIT_SPELLCAST_CHANNEL_STOP = ForCast(function(pf, _, _, by, id)
        if pf.castState ~= "cast" or not Same(pf.castId, id) then return end
        if issecretvalue(by) or by ~= nil then Interrupted(pf) else End(pf) end
      end),
    }
  end)(),
}

ns.RegisterOptions{
  key = "castBar", order = 6.5, reset = { "castBar" },
  build = function(o)
    return o.Group("Cast bar", {
      { "info", { type = "description", name = "Which plates show cast bars is set per category on the Visibility tab. The bar width follows the health bar; the corner radius follows the health bar border." } },
      { "height", o.Range("Height", "castBar.height", 2, 40, 1) },
      { "texture", o.Media("Texture", "castBar.texture", "statusbar") },
      { "showIcon", o.Toggle("Show spell icon", "castBar.showIcon") },
      { "iconSize", o.Range("Icon size", "castBar.iconSize", 8, 48, 1) },
      { "showTime", o.Toggle("Show remaining time", "castBar.showTime") },
      { "cast", o.Color("Cast color", "castBar.cast", true) },
      { "channel", o.Color("Channel color", "castBar.channel", true) },
      { "shield", o.Color("Not interruptible color", "castBar.shield", true) },
      { "interrupted", o.Color("Interrupted color", "castBar.interrupted", true) },
      { "text", o.TextGroup("Text and position", "castBar") },
    })
  end,
}
