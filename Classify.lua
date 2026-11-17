local ADDON, ns = ...

local issecretvalue = issecretvalue or function() return false end

local UnitIsPlayer, UnitInParty, UnitInRaid = UnitIsPlayer, UnitInParty, UnitInRaid
local UnitIsInMyGuild, UnitCanAttack = UnitIsInMyGuild, UnitCanAttack
local UnitPlayerControlled, UnitCreatureType, UnitReaction = UnitPlayerControlled, UnitCreatureType, UnitReaction
local UnitGUID = UnitGUID
local strmatch, tonumber = string.match, tonumber

local CRITTER_TYPE_ID = 8 -- creature type ID of "Critter"; ThreatPlates reads the same 2nd return of UnitCreatureType for totems (id 11)

-- Returns category, or nil, true when an input was secret (caller keeps its previous category),
-- or nil, false when the category could not be determined (caller falls back to the fail-safe).
function ns.Classify(unit)
  local isPlayer = UnitIsPlayer(unit)
  if issecretvalue(isPlayer) then return nil, true end

  if isPlayer then
    local inParty, inRaid = UnitInParty(unit), UnitInRaid(unit)
    if issecretvalue(inParty) or issecretvalue(inRaid) then return nil, true end
    if inParty or inRaid then return "groupMember" end

    -- UnitIsInMyGuild is a Mainline API; not used by ThreatPlates, so guard its existence.
    if UnitIsInMyGuild then
      local inGuild = UnitIsInMyGuild(unit)
      if issecretvalue(inGuild) then return nil, true end
      if inGuild then return "guildMember" end
    end

    local canAttack = UnitCanAttack("player", unit)
    if issecretvalue(canAttack) then return nil, true end
    return canAttack and "enemyPlayer" or "friendlyPlayer"
  end

  -- Player-controlled non-players: pets, guardians, minions, totems (ThreatPlates Styles.lua:91-146).
  local controlled = UnitPlayerControlled(unit)
  if issecretvalue(controlled) then return nil, true end
  if controlled then return "pet" end

  local _, typeID = UnitCreatureType(unit)
  if issecretvalue(typeID) then return nil, true end
  if typeID == CRITTER_TYPE_ID then return "critter" end

  -- ThreatPlates passes the unit first: UnitReaction(unit, "player"); the other order misreports hostile NPCs as neutral.
  local reaction = UnitReaction(unit, "player")
  if issecretvalue(reaction) then return nil, true end
  if not reaction then return nil, false end
  if reaction <= 3 then return "hostileNPC" end
  if reaction == 4 then return "neutralNPC" end
  return "friendlyNPC"
end

function ns.UpdateCategory(pf)
  local category, secret = ns.Classify(pf.unit)
  if secret then return end
  pf.category = category
end

---------------------------------------------------------------------------------------------------
-- Quest mobs
---------------------------------------------------------------------------------------------------

local GetUnitTooltip = C_TooltipInfo and C_TooltipInfo.GetUnit
local QuestPlayer = Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestPlayer
local QuestObjective = Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective
local playerName = UnitName("player")

local questByGUID = {}

-- Returns true/false, or nil if the tooltip is unreadable (secret lines or no data).
-- Pattern after ThreatPlates QuestWidget.lua:221-263: lines from 3 on, an objective is open when x ~= y or % < 100.
local function ReadQuestTooltip(unit)
  local data = GetUnitTooltip and GetUnitTooltip(unit)
  if not data or not data.lines then return nil end

  local mine = true -- objectives before any QuestPlayer line are ours
  for i = 3, #data.lines do
    local line = data.lines[i]
    local text = line.leftText
    if issecretvalue(text) or issecretvalue(line.type) then return nil end
    if text then
      if line.type == QuestPlayer then
        mine = (text == playerName)
      elseif mine and line.type == QuestObjective then
        local cur, goal = strmatch(text, "(%d+)/(%d+)")
        if cur then
          if tonumber(cur) ~= tonumber(goal) then return true end
        else
          local pct = strmatch(text, "(%d+)%%")
          if pct and tonumber(pct) < 100 then return true end
        end
      end
    end
  end
  return false
end

function ns.UpdateQuest(pf)
  local unit, P = pf.unit, ns.P
  if not (P.quest.override or P.quest.icon) then
    pf.isQuest = false
    return
  end

  local isPlayer = UnitIsPlayer(unit)
  if not issecretvalue(isPlayer) and isPlayer then
    pf.isQuest = false
    return
  end

  local guid = UnitGUID(unit)
  local cacheable = not issecretvalue(guid) and guid ~= nil
  if cacheable and questByGUID[guid] ~= nil then
    pf.isQuest = questByGUID[guid]
    return
  end

  local result = ReadQuestTooltip(unit)
  if result == nil then return end -- unreadable: keep the previous value
  pf.isQuest = result
  if cacheable then questByGUID[guid] = result end
end

-- Quest log changed: drop cached results. Plate.lua re-reads every active plate afterwards.
function ns.WipeQuestCache()
  wipe(questByGUID)
end
