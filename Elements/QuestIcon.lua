local ADDON, ns = ...

-- Blizzard atlas (Mainline); ThreatPlates ships its own tga, so fall back to the classic gossip icon.
local ATLAS = "QuestNormal"
local hasAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(ATLAS) ~= nil

local function Update(pf)
  local t = pf.questIcon
  if not t then return end
  local q = ns.P.quest
  t:SetShown(q.icon and (pf.isPreview or (pf.unit and pf.isQuest)) or false)
end

ns.RegisterElement{
  create = function(pf)
    local t = pf.root:CreateTexture(nil, "OVERLAY")
    if hasAtlas then t:SetAtlas(ATLAS) else t:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon") end
    t:Hide()
    pf.questIcon = t
  end,
  style = function(pf)
    local q = ns.P.quest
    pf.questIcon:SetSize(q.size, q.size)
    ns.ApplyPos(pf.questIcon, pf.health, q.pos)
    Update(pf)
  end,
  update = Update,
  remove = function(pf) pf.questIcon:Hide() end,
}
