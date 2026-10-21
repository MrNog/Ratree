local RT = select(2, ...)

local W = {}
RT.W = W

-- Colours, as r, g, b.
W.GOLD = { 0.886, 0.722, 0.263 }
W.GREEN = { 0.373, 0.878, 0.29 }
W.GREY = { 0.29, 0.29, 0.29 }
W.EDGE = { 0.235, 0.204, 0.157 }
W.TEXT = { 0.914, 0.886, 0.816 }
W.DIM = { 0.54, 0.506, 0.44 }

function W.Solid(parent, layer, r, g, b, a)
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
    tex:SetTexture(r, g, b, a or 1)
    return tex
end

-- A 1px frame drawn from four textures; returns them so the colour can change later.
function W.Border(frame, r, g, b, a, layer)
    local edges = {}
    for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local tex = W.Solid(frame, layer or "BORDER", r, g, b, a)
        if side == "TOP" or side == "BOTTOM" then
            tex:SetHeight(1)
            tex:SetPoint(side .. "LEFT", frame, side .. "LEFT", 0, 0)
            tex:SetPoint(side .. "RIGHT", frame, side .. "RIGHT", 0, 0)
        else
            tex:SetWidth(1)
            tex:SetPoint("TOP" .. side, frame, "TOP" .. side, 0, 0)
            tex:SetPoint("BOTTOM" .. side, frame, "BOTTOM" .. side, 0, 0)
        end
        edges[i] = tex
    end
    return edges
end

-- Cut corners. 3.3.5a cannot mask a frame, so Media\UI\chamfer (a white cut-corner fill and a
-- cut-corner line, in a large and a small size) is sliced nine ways and tinted.
--   W.Chamfer(frame, big, fill, edge[, edgeHost]) -> { fill = pieces, edge = pieces }
-- fill / edge are { r, g, b[, a] }. edgeHost, when given, draws the line on that frame (anchored
-- to `frame`), so it can sit above the frame's children.
local CHAMFER = RT.MEDIA .. "UI\\chamfer"
local CH_U = { big = { 0, 24 / 128, 40 / 128, 64 / 128 }, small = { 0, 16 / 128, 48 / 128, 64 / 128 } }

local function ninePieces(host, frame, layer, ox, oy, corner, u, color)
    local pieces = {}
    local xs = { { "LEFT", 0 }, { "LEFT", corner }, { "RIGHT", -corner }, { "RIGHT", 0 } }
    local ys = { { "TOP", 0 }, { "TOP", -corner }, { "BOTTOM", corner }, { "BOTTOM", 0 } }
    for row = 1, 3 do
        for col = 1, 3 do
            local tex = host:CreateTexture(nil, layer)
            tex:SetTexture(CHAMFER)
            tex:SetTexCoord(ox + u[col], ox + u[col + 1], oy + u[row], oy + u[row + 1])
            local x1, y1, x2, y2 = xs[col], ys[row], xs[col + 1], ys[row + 1]
            tex:SetPoint("TOPLEFT", frame, y1[1] .. x1[1], x1[2], y1[2])
            tex:SetPoint("BOTTOMRIGHT", frame, y2[1] .. x2[1], x2[2], y2[2])
            tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
            pieces[#pieces + 1] = tex
        end
    end
    return pieces
end

function W.Chamfer(frame, big, fill, edge, edgeHost)
    local corner, oy, u = big and 12 or 8, big and 0 or 0.5, big and CH_U.big or CH_U.small
    return {
        fill = ninePieces(frame, frame, "BACKGROUND", 0, oy, corner, u, fill),
        edge = ninePieces(edgeHost or frame, frame, "OVERLAY", 0.5, oy, corner, u, edge),
    }
end

-- Square textures inside a cut window would poke past its cut. Content sits W.INSET in from the
-- edge, and a small triangle in the window's fill colour over each outer corner cuts it parallel
-- to the window's edge.
--   W.CoverCorners(host, region, r, g, b, corners)
local COVER = RT.MEDIA .. "UI\\cutcover"
local COVER_TC = { TOPLEFT = { 0, 1, 0, 1 }, TOPRIGHT = { 1, 0, 0, 1 },
    BOTTOMLEFT = { 0, 1, 1, 0 }, BOTTOMRIGHT = { 1, 0, 1, 0 } }
W.INSET, W.COVER = 6, 6.5

function W.CoverCorners(host, region, r, g, b, corners)
    for _, c in ipairs(corners) do
        local tex = host:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(COVER)
        tex:SetTexCoord(unpack(COVER_TC[c]))
        tex:SetSize(W.COVER, W.COVER)
        tex:SetPoint(c, region, c, 0, 0)
        tex:SetVertexColor(r, g, b, 1)
    end
end

function W.SetBorderColor(edges, r, g, b, a)
    for _, tex in ipairs(edges) do tex:SetTexture(r, g, b, a or 1) end
end

function W.Text(parent, size, r, g, b, font)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFont(font or STANDARD_TEXT_FONT, size or 12)
    text:SetShadowOffset(1, -1)
    text:SetTextColor(r or W.TEXT[1], g or W.TEXT[2], b or W.TEXT[3])
    return text
end

function W.Tip(owner, title, detail)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:AddLine(title, 1, 1, 1)
    if detail then GameTooltip:AddLine(detail, 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
end

function W.TipOnHover(widget, title, detail)
    widget:HookScript("OnEnter", function(self) W.Tip(self, title, detail) end)
    widget:HookScript("OnLeave", GameTooltip_Hide)
end

-- Button --------------------------------------------------------------------------------------------
-- Drawn to match the close button: silver octagon frame, thin black line, red body. A three-slice
-- whose caps keep the frame's corners at any width.

local PLATE = RT.MEDIA .. "UI\\redplate"
local PLATE_W, PLATE_H, CAP_W = 128, 64, 32
local PLATE_U = {
    left = { 0, CAP_W / PLATE_W },
    middle = { CAP_W / PLATE_W, (PLATE_W - CAP_W) / PLATE_W },
    right = { (PLATE_W - CAP_W) / PLATE_W, 1 },
}

-- 3.3.5a's IsEnabled returns 1 or 0, and 0 is truthy in Lua.
local function isDisabled(button)
    local enabled = button:IsEnabled()
    return not enabled or enabled == 0
end

local function threeSlice(button, layer)
    local pieces = {}
    for _, part in ipairs({ "left", "middle", "right" }) do
        local tex = button:CreateTexture(nil, layer)
        tex:SetTexture(PLATE)
        tex:SetTexCoord(PLATE_U[part][1], PLATE_U[part][2], 0, 1)
        pieces[part] = tex
    end
    pieces.left:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    pieces.left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    pieces.right:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    pieces.right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    pieces.middle:SetPoint("TOPLEFT", pieces.left, "TOPRIGHT", 0, 0)
    pieces.middle:SetPoint("BOTTOMRIGHT", pieces.right, "BOTTOMLEFT", 0, 0)
    return pieces
end

local function plateResize(button)
    local cap = CAP_W * (button:GetHeight() or PLATE_H) / PLATE_H
    for _, pieces in ipairs({ button.plate, button.glow }) do
        pieces.left:SetWidth(cap)
        pieces.right:SetWidth(cap)
    end
end

-- Pressed reads darker, disabled grey.
local function platePaint(button, pressed)
    local off = isDisabled(button)
    local shade = off and 0.6 or (pressed and 0.75 or 1)
    for _, tex in pairs(button.plate) do
        tex:SetDesaturated(off)
        tex:SetVertexColor(shade, shade, shade)
    end
end

function W.Button(name, parent, width, height, label)
    local button = CreateFrame("Button", name, parent)
    button:SetSize(width, height or 24)
    button.plate = threeSlice(button, "BACKGROUND")
    button.glow = threeSlice(button, "HIGHLIGHT")
    for _, tex in pairs(button.glow) do
        tex:SetBlendMode("ADD")
        tex:SetAlpha(0.25)
    end
    local text = button:CreateFontString(nil, "OVERLAY")
    button:SetFontString(text)
    button:SetNormalFontObject(GameFontNormal)
    button:SetHighlightFontObject(GameFontHighlight)
    button:SetDisabledFontObject(GameFontDisable)
    button:SetPushedTextOffset(1, -1)
    button:SetText(label or "")
    button:HookScript("OnEnable", function(self) platePaint(self) end)
    button:HookScript("OnDisable", function(self) platePaint(self) end)
    button:HookScript("OnMouseDown", function(self) platePaint(self, not isDisabled(self)) end)
    button:HookScript("OnMouseUp", function(self) platePaint(self) end)
    button:HookScript("OnLeave", function(self) platePaint(self) end)
    button:HookScript("OnSizeChanged", plateResize)
    plateResize(button)
    platePaint(button)
    return button
end

-- Close button: retail's red X, all four states from one sheet.
local CLOSE_SHEET = RT.MEDIA .. "UI\\redbutton2x"

function W.CloseButton(name, parent)
    local close = CreateFrame("Button", name, parent, "UIPanelCloseButton")
    close:SetSize(24, 24)
    -- 3.3.5a's close button has no disabled texture, so each state is set before it is cut.
    local function dress(state, l, r, t, b, blend)
        close["Set" .. state .. "Texture"](close, CLOSE_SHEET)
        local tex = close["Get" .. state .. "Texture"](close)
        tex:SetTexCoord(l, r, t, b)
        if blend then tex:SetBlendMode(blend) end
    end
    dress("Normal", 39 / 256, 75 / 256, 1 / 128, 39 / 128)
    dress("Pushed", 39 / 256, 75 / 256, 81 / 128, 119 / 128)
    dress("Disabled", 39 / 256, 75 / 256, 41 / 128, 79 / 128)
    dress("Highlight", 115 / 256, 151 / 256, 1 / 128, 39 / 128, "ADD")
    return close
end
