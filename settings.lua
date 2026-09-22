-- Settings use the documented X2Editbox implementation of Editbox.
-- No Auction APIs are called here. Edits remain a draft until Save succeeds.
function AH_PRICE_WATCH_CREATE_SETTINGS(parent, context)
    local F, T = AH_PRICE_WATCH_FEATURES, context.text
    local C, U = AH_PRICE_WATCH_CATALOG, AH_PRICE_WATCH_UI
    local isOpen, chosenId = false, nil
    local refreshSuggestions
    assert(OBJECT_TYPE.EDITBOX and OBJECT_TYPE.X2_EDITBOX, "X2Editbox dependency missing")
    ADDON:ImportObject(OBJECT_TYPE.EDITBOX)
    ADDON:ImportObject(OBJECT_TYPE.X2_EDITBOX)
    local panel = CreateEmptyWindow("ahPriceWatchSettingsWindow", "UIParent")
    panel:SetExtent(864, 380)
    panel:AddAnchor("TOPLEFT", parent, 0, 28)
    panel:Show(false)
    local bg = panel:CreateColorDrawable(0.05, 0.05, 0.07, 1, "background")
    bg:AddAnchor("TOPLEFT", panel, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", panel, 0, 0)
    local LIST_X, LIST_WIDTH = 12, 418
    local labels = {}
    local function label(id, key, x, y, width)
        local w = panel:CreateChildWidget("label", "ahPriceWatchSettings" .. id, 0, false)
        w:SetExtent(width, 22)
        w:AddAnchor("TOPLEFT", panel, x, y)
        w.style:SetFontSize(12)
        w.style:SetAlign(ALIGN_LEFT)
        w.style:SetColor(235, 235, 235, 255)
        if key then labels[#labels + 1] = { widget = w, key = key } end
        return w
    end
    local function button(id, key, x, y, width, anchor)
        local w = panel:CreateChildWidget("button", "ahPriceWatchSettings" .. id, 0, true)
        w:SetStyle("text_default")
        w:SetExtent(width, 26)
        w:AddAnchor(anchor or "TOPLEFT", panel, anchor or "TOPLEFT", x, y)
        if key then labels[#labels + 1] = { widget = w, key = key } end
        return w
    end
    local function edit(id, x, y, width)
        local w = panel:CreateChildWidget("x2editbox", "ahPriceWatchSettings" .. id, 0, true)
        w:SetExtent(width, 26)
        w:AddAnchor("TOPLEFT", panel, x, y)
        w:SetInset(5, 3, 5, 3)
        w:EnableFocus(true)
        w.style:SetAlign(ALIGN_LEFT)
        w.style:SetColor(255, 255, 255, 255)
        local fill = w:CreateColorDrawable(0.18, 0.18, 0.22, 1, "background")
        fill:AddAnchor("TOPLEFT", w, 0, 0)
        fill:AddAnchor("BOTTOMRIGHT", w, 0, 0)
        w:SetText("")
        return w
    end
    label("Title", "settingsTitle", 12, 5, 750)
    local close = button("Close", nil, -24, 8, 30, "TOPRIGHT")
    U.Inside(864 - 24 - 30, 30, 864, 12)
    close:SetText("X")
    label("ListTitle", "watchList", LIST_X, 34, LIST_WIDTH)
    local editorTitle = label("EditorTitle", nil, 450, 34, 402)
    label("NameLabel", "englishItem", 450, 60, 402)
    local nameEdit = edit("Name", 450, 86, 402)
    nameEdit:SetMaxTextLength(256)
    label("TargetLabel", "targetUnit", 450, 118, 402)
    label("GoldLabel", "gold", 450, 144, 150)
    label("SilverLabel", "silver", 608, 144, 110)
    label("CopperLabel", "copper", 736, 144, 116)
    local gold, silver, copper = edit("Gold", 450, 168, 150), edit("Silver", 608, 168, 110), edit("Copper", 736, 168, 116)
    local add = button("Add", "addItem", 450, 202, 126)
    local apply = button("Apply", "applyItem", 588, 202, 126)
    local delete = button("Delete", "deleteItem", 726, 202, 126)
    local watchlist = panel:CreateChildWidget("window", "ahPriceWatchSettingsWatchlist", 0, true)
    watchlist:SetExtent(LIST_WIDTH, 32)
    watchlist:AddAnchor("TOPLEFT", panel, "TOPLEFT", LIST_X, 244)
    watchlist:Show(true)
    local pager, previous, pageLabel, nextPage = U.Pager(watchlist, "ahPriceWatchSettingsPager",
        "ahPriceWatchSettingsPrevious", "ahPriceWatchSettingsPage", "ahPriceWatchSettingsNext")
    pager:AddAnchor("CENTER", watchlist, "CENTER", 0, 0)
    U.Inside((LIST_WIDTH - U.PAGER_WIDTH) / 2, U.PAGER_WIDTH, LIST_WIDTH, 12)
    local message = label("Message", nil, 12, 314, 840)
    local save = button("Save", "saveSettings", 450, 346, 196)
    local cancel = button("Cancel", "cancel", 656, 346, 196)
    label("SearchLanguageLabel", "searchLanguage", 450, 238, 402)
    local searchLanguageButton = button("SearchLanguage", nil, 450, 266, 196)
    local searchLanguageSource = label("SearchLanguageSource", nil, 656, 268, 196)
    local draftSearchLanguage, automaticSearchLanguage = "EN", false
    local listButtons = {}
    local draft, selected, page = {}, nil, 1
    local refresh
    local function addCandidate()
        local record = C.ById(chosenId)
        if not record or nameEdit:GetText() ~= C.Display(record, context.language()) then return nil end
        for _, item in ipairs(draft) do
            if item.id == record.id or string.lower(item.name) == string.lower(record.en) then return nil end
        end
        return record
    end
    local function refreshActions()
        add:Enable(addCandidate() ~= nil)
        gold:Enable(selected ~= nil)
        silver:Enable(selected ~= nil)
        copper:Enable(selected ~= nil)
        apply:Enable(selected ~= nil)
        delete:Enable(selected ~= nil)
    end
    local function clearEditor()
        selected, chosenId = nil, nil
        nameEdit:SetText("")
        gold:SetText("0"); silver:SetText("0"); copper:SetText("0")
    end
    local function selectItem(index)
        selected = index
        local item = draft[index]
        local record = C.ForItem(item)
        chosenId = record and record.id or nil
        nameEdit:SetText(C.ItemDisplayName(item, context.language()))
        local amount = math.floor((tonumber(item.targetGold) or 0) * 10000 + 0.5)
        gold:SetText(tostring(math.floor(amount / 10000)))
        silver:SetText(tostring(math.floor(amount / 100) % 100))
        copper:SetText(tostring(amount % 100))
        message:SetText(T("draftHint"))
        refresh()
    end
    for slot = 1, 6 do
        local rowSlot = slot
        local w = button("Item" .. slot, nil, LIST_X, 60 + (slot - 1) * 29, LIST_WIDTH)
        w:SetHandler("OnClick", function()
            local index = (page - 1) * 6 + rowSlot
            if draft[index] then selectItem(index) end
        end)
        listButtons[slot] = w
    end
    refresh = function()
        for _, entry in ipairs(labels) do entry.widget:SetText(T(entry.key)) end
        editorTitle:SetText(T(selected and "editSelected" or "newEditor"))
        searchLanguageButton:SetText(draftSearchLanguage == "KO" and "한국어" or "English")
        searchLanguageButton:Enable(not automaticSearchLanguage)
        searchLanguageSource:SetText(T(automaticSearchLanguage and "searchLanguageAuto" or "searchLanguageManual"))
        if refreshSuggestions then refreshSuggestions(false, true) end
        refreshActions()
        local pages = math.max(1, math.ceil(#draft / 6))
        page = math.max(1, math.min(page, pages))
        pageLabel:SetText(tostring(page) .. " / " .. tostring(pages))
        for slot, w in ipairs(listButtons) do
            local index = (page - 1) * 6 + slot
            local item = draft[index]
            w:Show(item ~= nil)
            if item then
                local target = math.floor((item.targetGold or 0) * 10000 + 0.5)
                local targetText = target > 0 and (context.money(target):gsub(" ", ""):gsub("00c$", "")) or "-"
                w:SetText((selected == index and "> " or "  ") .. C.ItemDisplayName(item, context.language()) .. " | " ..
                    T("targetPrefix") .. " " .. targetText)
            end
        end
    end
    local function applyTarget()
        if not selected or not draft[selected] then return false end
        local amount, err = F.TargetCopper(gold:GetText(), silver:GetText(), copper:GetText())
        if amount == nil then message:SetText(T(err)); return false end
        -- Apply only changes the selected target, never its name or identity.
        draft[selected].targetGold = amount / 10000
        message:SetText(T("draftHint"))
        refresh()
        return true
    end
    local function addItem()
        local record = addCandidate()
        if not record then return end
        draft[#draft + 1] = { id = record.id, name = context.canonicalName(record.en), targetGold = 0 }
        page = math.floor((#draft - 1) / 6) + 1
        clearEditor()
        message:SetText(T("draftHint"))
        refresh()
    end
    -- Created last so the dropdown is above the editor fields it covers.
    local dropdown = panel:CreateChildWidget("window", "ahPriceWatchSuggestions", 0, true)
    dropdown:SetExtent(402, 180)
    dropdown:AddAnchor("TOPLEFT", nameEdit, "BOTTOMLEFT", 0, 4)
    local fill = dropdown:CreateColorDrawable(0.07, 0.09, 0.12, 1, "background")
    fill:AddAnchor("TOPLEFT", dropdown, "TOPLEFT", 0, 0)
    fill:AddAnchor("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", 0, 0)
    local candidates, suggestionButtons = {}, {}
    local lastInput, lastLanguage, inputElapsed = "", context.language(), 0
    for slot = 1, 6 do
        local index = slot
        local w = dropdown:CreateChildWidget("button", "ahPriceWatchSuggestion" .. slot, 0, true)
        w:SetStyle("text_default")
        w:SetExtent(378, 24)
        w:AddAnchor("TOPLEFT", dropdown, "TOPLEFT", 12, 6 + (slot - 1) * 28)
        w:SetHandler("OnClick", function()
            local item = candidates[index]
            if not item then return end
            selected, chosenId = nil, item.id
            gold:SetText("0"); silver:SetText("0"); copper:SetText("0")
            lastInput = C.Display(item, context.language())
            nameEdit:SetText(lastInput)
            dropdown:Show(false)
            refresh()
        end)
        suggestionButtons[slot] = w
    end
    refreshSuggestions = function(force, languageRefresh)
        local language = context.language()
        local text = tostring(nameEdit:GetText() or "")
        if language ~= lastLanguage and chosenId then
            local item = C.ById(chosenId)
            if item and text == C.Display(item, lastLanguage) then
                text = C.Display(item, language); nameEdit:SetText(text)
            end
        end
        if chosenId then
            local item = C.ById(chosenId)
            if not item or text ~= C.Display(item, language) then chosenId = nil end
        end
        refreshActions()
        if not force and text == lastInput and language == lastLanguage then return end
        local changedLanguage = language ~= lastLanguage
        lastInput, lastLanguage = text, language
        if languageRefresh and not changedLanguage then dropdown:Show(false); return end
        candidates = C.Search(text, language, 6, draft)
        for slot, w in ipairs(suggestionButtons) do
            local item = candidates[slot]
            w:Show(item ~= nil)
            if item then w:SetText(C.Display(item, language) .. " [#" .. tostring(item.id) .. "]") end
        end
        dropdown:Show(isOpen and #candidates > 0)
    end
    dropdown:Show(false)
    -- Existing OnUpdate/GetText APIs only; no native autocomplete/internal API.
    panel:SetHandler("OnUpdate", function(_, dt)
        if not isOpen then return end
        inputElapsed = inputElapsed + (tonumber(dt) or 0)
        if inputElapsed >= 100 then inputElapsed = 0; refreshSuggestions(false, false) end
    end)
    local function hide()
        if not isOpen then return end
        isOpen = false
        dropdown:Show(false)
        panel:Show(false)
        context.visibility(false)
    end
    searchLanguageButton:SetHandler("OnClick", function()
        if automaticSearchLanguage then return end
        draftSearchLanguage = draftSearchLanguage == "EN" and "KO" or "EN"
        refresh()
    end)
    apply:SetHandler("OnClick", applyTarget)
    add:SetHandler("OnClick", addItem)
    delete:SetHandler("OnClick", function()
        if selected then table.remove(draft, selected); clearEditor(); refresh(); message:SetText(T("draftHint")) end
    end)
    previous:SetHandler("OnClick", function() page = page - 1; refresh() end)
    nextPage:SetHandler("OnClick", function() page = page + 1; refresh() end)
    save:SetHandler("OnClick", function()
        -- Preserve auto-apply for the selected target. New candidates require
        -- an explicit Add Item click and are never silently added by Save.
        if selected and not applyTarget() then return end
        local ok, err = context.save(draft, draftSearchLanguage)
        if not ok then message:SetText(T(err)); return end
        hide()
    end)
    close:SetHandler("OnClick", hide)
    cancel:SetHandler("OnClick", hide)
    return {
        Hide = hide,
        RefreshLanguage = refresh,
        Open = function()
            if isOpen then
                -- Show alone does not restore native stacking order. Use the
                -- Show/Raise pattern used by ChoreTracker's sibling windows.
                panel:Show(true)
                panel:Raise()
                return
            end
            context.visibility(true)
            isOpen = true
            dropdown:Show(false)
            draft, page = F.CopyItems(context.items()), 1
            draftSearchLanguage, automaticSearchLanguage = context.searchLanguage()
            clearEditor()
            refresh()
            message:SetText(T("draftHint"))
            panel:Show(true)
            panel:Raise()
        end,
    }
end
