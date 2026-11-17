local ADDON, ns = ...

local issecretvalue = issecretvalue or function() return false end
local GetRaidTargetIndex, SetRaidTargetIconTexture = GetRaidTargetIndex, SetRaidTargetIconTexture

local function Update(pf)
  local t = pf.raidMarker
  if not t then return end
  local idx
  if pf.isPreview then
    idx = 8
  elseif pf.unit then
    idx = GetRaidTargetIndex(pf.unit)
    if issecretvalue(idx) then return end -- keep what is shown
  end
  if ns.P.raidMarker.enabled and idx and idx >= 1 and idx <= 8 then
    SetRaidTargetIconTexture(t, idx)
    t:Show()
  else
    t:Hide()
  end
end

ns.RegisterElement{
  create = function(pf)
    pf.raidMarker = pf.root:CreateTexture(nil, "OVERLAY")
    pf.raidMarker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    pf.raidMarker:Hide()
  end,
  style = function(pf)
    local r = ns.P.raidMarker
    pf.raidMarker:SetSize(r.size, r.size)
    ns.ApplyPos(pf.raidMarker, pf.health, r.pos)
    Update(pf)
  end,
  update = Update,
  remove = function(pf) pf.raidMarker:Hide() end,
  events = {
    RAID_TARGET_UPDATE = function()
      for _, pf in pairs(ns.plates) do Update(pf) end
    end,
  },
}
