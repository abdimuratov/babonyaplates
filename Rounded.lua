local ADDON, ns = ...

-- Rounded corners: WoW has no corner radius, so we nine-slice white rounded-rect textures (Media/fill_R.tga,
-- Media/ring_R.tga, made by tools/gen_rounded.py). Slice margins = R keep each corner a true circle of R px
-- at any region size; only the straight middle stretches. Radii are whole pixels; callers pass the result
-- of ns.RoundedRadius, where 0 means "draw it square" (the helpers then undo any rounding they applied).
local floor, min, max = math.floor, math.min, math.max
local MEDIA = "Interface\\AddOns\\BabonyaPlates\\Media\\"
local MAX_FILL, MAX_RING = 20, 28
local CLAMP = "CLAMPTOBLACKADDITIVE"
local SLICE = Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched

-- If slicing is missing on this client (masks or textures), everything stays square.
local CAN_SLICE = UIParent:CreateMaskTexture().SetTextureSliceMargins ~= nil
  and UIParent:CreateTexture().SetTextureSliceMargins ~= nil

local function Slice(tex, m)
  tex:SetTextureSliceMargins(m, m, m, m)
  if SLICE then tex:SetTextureSliceMode(SLICE) end
end

-- Usable radius for a w x h region: whole pixels, at most half the smaller side (a circle / pill).
function ns.RoundedRadius(radius, w, h)
  if not CAN_SLICE then return 0 end
  local r = min(floor((radius or 0) + 0.5), floor(min(w, h) / 2), MAX_FILL)
  return r > 0 and r or 0
end

-- Turns tex into a white rounded fill (tint with SetVertexColor). radius 0: undoes it and returns false,
-- so the caller sets its own square texture afterwards.
function ns.RoundedFill(tex, radius)
  if radius > 0 then
    tex:SetTexture(MEDIA .. "fill_" .. radius .. ".tga")
    Slice(tex, radius)
    tex.rounded = true
    return true
  end
  if tex.rounded then
    tex.rounded = nil
    tex:SetTextureSliceMargins(0, 0, 0, 0)
    tex:SetVertexColor(1, 1, 1, 1)
  end
  return false
end

-- Clips `fill` (e.g. a StatusBar's fill texture) to the rounded shape of `host` (the frame that owns it).
function ns.RoundedMask(host, fill, radius)
  local mask = host.roundMask
  if radius > 0 then
    if not mask then
      mask = host:CreateMaskTexture()
      mask:SetAllPoints(host)
      host.roundMask = mask
    end
    mask:SetTexture(MEDIA .. "fill_" .. radius .. ".tga", CLAMP, CLAMP)
    Slice(mask, radius)
    if host.roundMasked ~= fill then
      if host.roundMasked then host.roundMasked:RemoveMaskTexture(mask) end
      fill:AddMaskTexture(mask)
      host.roundMasked = fill
    end
  elseif host.roundMasked then
    host.roundMasked:RemoveMaskTexture(mask)
    host.roundMasked = nil
  end
end

-- Rounded border of `size` px drawn outside `host`, as `size` stacked 1 px rings (ring file for each outer radius)
-- on `frame`. size 0 / radius 0 hides it. shortcut: stacked rings can show a faint seam on the arcs when
-- size > 1; per-(radius, size) textures would remove it but need ~200 files.
function ns.RoundedBorder(frame, host, radius, size, c)
  local rings = frame.rings
  if not rings then rings = {}; frame.rings = rings end
  local n = radius > 0 and min(size, MAX_RING - radius) or 0
  for i = 1, max(n, #rings) do
    local t = rings[i]
    if i > n then
      t:Hide()
    else
      if not t then
        t = frame:CreateTexture(nil, "OVERLAY")
        rings[i] = t
      end
      t:SetTexture(MEDIA .. "ring_" .. (radius + i) .. ".tga")
      Slice(t, radius + i)
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", host, "TOPLEFT", -i, i)
      t:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", i, -i)
      t:SetVertexColor(c.r, c.g, c.b, c.a)
      t:Show()
    end
  end
end
