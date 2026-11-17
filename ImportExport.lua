local ADDON, ns = ...

local AceSerializer = LibStub("AceSerializer-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local PREFIX = "BPT1:"

-- Plain deep copy of stored values only (no metatables, no functions).
local function Copy(t)
  local out = {}
  for k, v in pairs(t) do
    local tv = type(v)
    if tv == "table" then out[k] = Copy(v)
    elseif tv == "string" or tv == "number" or tv == "boolean" then out[k] = v end
  end
  return out
end

-- Trust boundary: copy only keys that exist in defaults `def` at the same path with the same type.
local function Merge(dst, src, def)
  for k, v in pairs(src) do
    local d = def[k]
    if d ~= nil and type(v) == type(d) then
      if type(d) == "table" then
        if type(dst[k]) ~= "table" then dst[k] = {} end
        Merge(dst[k], v, d)
      else
        dst[k] = v
      end
    end
  end
  return dst
end

-- Debug-only check (set ns.debug before this file loads, or call ns.ImportSelfTest()).
function ns.ImportSelfTest()
  local def = { a = 1, t = { x = "s", y = 2 }, b = true }
  local r = Merge({ a = 1, t = { x = "s", y = 2 }, b = true },
    { a = "bad", t = { x = "ok", y = 3, z = 1 }, b = false, q = 1, [1] = 5 }, def)
  assert(r.a == 1 and r.t.x == "ok" and r.t.y == 3 and r.t.z == nil and r.b == false and r.q == nil and r[1] == nil)
  assert(Merge({}, { t = 5 }, def).t == nil)
end
if ns.debug then ns.ImportSelfTest() end

local exportText, importText = "", ""

-- Styles a hidden preview plate with the new profile: well-typed but bad values (anchor names, scale 0)
-- throw here instead of on the next plate.
local probe
local function Probe()
  if not probe then
    probe = ns.CreatePlateFrames(UIParent)
    probe.isPreview = true
    probe.root:Hide()
  end
  ns.StylePlate(probe)
end

local function DoImport()
  local s = importText:gsub("^%s+", ""):gsub("%s+$", "")
  if s:sub(1, #PREFIX) ~= PREFIX then ns.addon:Print("Import failed: not a BabonyaPlates string."); return end
  local ok, success, data = pcall(AceSerializer.Deserialize, AceSerializer, s:sub(#PREFIX + 1))
  if not (ok and success and type(data) == "table") then ns.addon:Print("Import failed: the string is damaged."); return end
  local old = Copy(ns.db.profile)
  ns.db:ResetProfile()
  Merge(ns.db.profile, data, ns.defaults.profile)
  if not (pcall(Probe) and pcall(ns.RefreshAll)) then
    ns.db:ResetProfile() -- put the previous profile back
    Merge(ns.db.profile, old, ns.defaults.profile)
    ns.RefreshAll()
    ns.addon:Print("Import failed: the string has invalid settings.")
    return
  end
  importText = ""
  AceConfigRegistry:NotifyChange("BabonyaPlates")
  ns.addon:Print("Profile imported.")
end

ns.RegisterOptions{
  key = "importExport", order = 99,
  build = function(o)
    return o.Group("Import / export", {
      { "export", { type = "execute", name = "Export", func = function()
          exportText = PREFIX .. AceSerializer:Serialize(Copy(ns.db.profile))
          AceConfigRegistry:NotifyChange("BabonyaPlates")
        end } },
      { "exportBox", { type = "input", multiline = 8, width = "full", name = "Export string (select all and copy)",
          get = function() return exportText end, set = function() end } },
      { "importBox", { type = "input", multiline = 8, width = "full", name = "Paste a string to import",
          get = function() return importText end, set = function(_, v) importText = v or "" end } },
      { "import", { type = "execute", name = "Import",
          confirm = true, confirmText = "Replace the current profile with the imported settings?", func = DoImport } },
    })
  end,
}
