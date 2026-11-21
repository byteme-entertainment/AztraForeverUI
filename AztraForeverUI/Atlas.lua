-- Runtime helper for the generated Forever atlas table (Media\Atlas.lua).
local warned = {}

function AFUI.SetAtlas(texture, name, useAtlasSize)
  local e = AFUI_ATLAS and AFUI_ATLAS[string.lower(name)]
  if not e then
    texture:SetTexture(nil)
    if not warned[name] then
      warned[name] = true
      AFUI.Print("AztraForeverUI: unknown atlas '" .. tostring(name) .. "'")
    end
    return
  end
  texture:SetTexture(e[1])
  texture:SetTexCoord(e[4], e[5], e[6], e[7])
  texture.afuiAtlas = string.lower(name) -- which sprite it shows (the preview's bar alignment check reads it)
  if useAtlasSize then
    texture:SetWidth(e[2])
    texture:SetHeight(e[3])
  end
end

-- Button state art from atlas names { normal, pushed, highlight, disabled }; the highlight is additive, at hlAlpha when given.
function AFUI.SetButtonAtlas(btn, art, hlAlpha)
  local function state(name, setter, getter, add)
    local e = name and AFUI_ATLAS and AFUI_ATLAS[string.lower(name)]
    if not e then return end
    if add then btn[setter](btn, e[1], "ADD") else btn[setter](btn, e[1]) end
    local t = btn[getter](btn)
    if t then
      t:SetTexCoord(e[4], e[5], e[6], e[7])
      if add and hlAlpha then t:SetAlpha(hlAlpha) end
    end
  end
  state(art[1], "SetNormalTexture", "GetNormalTexture")
  state(art[2], "SetPushedTexture", "GetPushedTexture")
  state(art[3], "SetHighlightTexture", "GetHighlightTexture", true)
  state(art[4], "SetDisabledTexture", "GetDisabledTexture")
end
