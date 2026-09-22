-- Parent-relative frames and bounded drawables; no native text_default overhang.
AH_PRICE_WATCH_UI = {}
local U = AH_PRICE_WATCH_UI
U.PAGER_WIDTH, U.PAGER_HEIGHT = 232, 32
-- Main-only geometry. Screen pixels / UI scale = AddAnchor/SetExtent units.
U.MIN_PAGE_SIZE, U.MAX_PAGE_SIZE = 8, 15
U.PANEL_WIDTH, U.TABLE_TOP, U.ROW_HEIGHT = 888, 72, 36
U.ROW_FOOTER_GAP, U.FOOTER_HEIGHT, U.SAFE_MARGIN = 10, 62, 12
local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
function U.EffectiveSize(parent)
    local ok, width, height, scale = pcall(function()
        return parent:GetScreenWidth(), parent:GetScreenHeight(), parent:GetUIScale()
    end)
    if not ok or not finite(width) or not finite(height) or not finite(scale) or
        width <= 0 or height <= 0 or scale <= 0 then return nil, nil end
    width, height = width / scale, height / scale
    if not finite(width) or not finite(height) then return nil, nil end
    return width, height
end
function U.MainGeometry(parent, debugEnabled)
    local width, height = U.EffectiveSize(parent)
    local chrome = U.TABLE_TOP + U.ROW_FOOTER_GAP + U.FOOTER_HEIGHT + (debugEnabled and 20 or 0)
    local count = height and math.floor((height - 2 * U.SAFE_MARGIN - chrome) / U.ROW_HEIGHT) or U.MIN_PAGE_SIZE
    count = math.max(U.MIN_PAGE_SIZE, math.min(U.MAX_PAGE_SIZE, count))
    return { pageSize = count, width = U.PANEL_WIDTH, height = chrome + count * U.ROW_HEIGHT,
        screenWidth = width, screenHeight = height,
        bottomY = U.TABLE_TOP + count * U.ROW_HEIGHT + U.ROW_FOOTER_GAP }
end
function U.ClampMainPosition(geometry, x, y)
    local function axis(value, default, screen, extent)
        value = tonumber(value)
        if not finite(value) then value = default end
        -- Invalid dimensions / a physically oversized panel: best effort at top/left.
        local maximum = screen and math.max(U.SAFE_MARGIN, screen - extent - U.SAFE_MARGIN) or U.SAFE_MARGIN
        return math.max(U.SAFE_MARGIN, math.min(value, maximum))
    end
    return axis(x, 250, geometry.screenWidth, geometry.width), axis(y, 180, geometry.screenHeight, geometry.height)
end
function U.Inside(x, width, parentWidth, margin)
    assert(x >= margin and x + width <= parentWidth - margin, "AH Tracker UI outside panel")
end
function U.Pager(parent, id, previousId, labelId, nextId)
    local region = parent:CreateChildWidget("window", id, 0, true)
    region:SetExtent(U.PAGER_WIDTH, U.PAGER_HEIGHT)
    region:Show(true)
    local buttonWidth, labelWidth, gap = 36, 112, 16
    local offset = (labelWidth + buttonWidth) / 2 + gap
    local function button(name, distance, text)
        local w = region:CreateChildWidget("button", name, 0, true)
        w:SetExtent(buttonWidth, 24)
        w:AddAnchor("CENTER", region, "CENTER", distance, 0)
        w.style:SetFontSize(12)
        w.style:SetAlign(ALIGN_CENTER)
        w.style:SetColor(235, 235, 235, 255)
        local bg = w:CreateColorDrawable(0.16, 0.19, 0.24, 1, "background")
        bg:AddAnchor("TOPLEFT", w, "TOPLEFT", 0, 0)
        bg:AddAnchor("BOTTOMRIGHT", w, "BOTTOMRIGHT", 0, 0)
        w:SetText(text)
        U.Inside(U.PAGER_WIDTH / 2 + distance - buttonWidth / 2, buttonWidth, U.PAGER_WIDTH, 8)
        return w
    end
    local previous = button(previousId, -offset, "<")
    local label = region:CreateChildWidget("label", labelId, 0, false)
    label:SetExtent(labelWidth, 24)
    label:AddAnchor("CENTER", region, "CENTER", 0, 0)
    label.style:SetFontSize(12)
    label.style:SetAlign(ALIGN_CENTER)
    label.style:SetColor(235, 235, 235, 255)
    U.Inside((U.PAGER_WIDTH - labelWidth) / 2, labelWidth, U.PAGER_WIDTH, 8)
    local next = button(nextId, offset, ">")
    return region, previous, label, next
end

-- UTF-8-safe bounded two-line item labels, independent of lookup/history identity.
function U.ItemText(text)
    local lines,line,width={},"",0
    for ch in tostring(text or ""):gmatch("[^\128-\191][\128-\191]*") do
        local units=#ch>1 and 2 or 1
        if width+units>26 then
            if #lines==1 then return lines[1].."\n"..line.."…" end
            lines[#lines+1]=line;line="";width=0
        end
        line=line..ch;width=width+units
    end
    lines[#lines+1]=line
    return table.concat(lines,"\n")
end
