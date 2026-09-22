-- ArcheRage AH Price Watch v1.1.2
-- AUTO performs one watchlist scan while the player has native AH open, then
-- records native/manual searches. Settings and notifications are local only.
-- Uses the enabled nine-argument SearchAuctionArticle and GetSearchedItem* APIs.
-- Search completion is required before scan results are read. Event payload
-- layouts are not assumed. No native UI handlers or internal setup APIs are called.
-- No buy/bid/list/cancel, input simulation, memory or packet access.

if API_TYPE == nil then
    ADDON:ImportAPI(8)
    X2Chat:DispatchChatMessage(CMF_SYSTEM, "[AH Watch] globals folder not found. Install the globals dependency first.")
    return
end

ADDON:ImportObject(OBJECT_TYPE.TEXT_STYLE)
ADDON:ImportObject(OBJECT_TYPE.BUTTON)
ADDON:ImportObject(OBJECT_TYPE.DRAWABLE)
ADDON:ImportObject(OBJECT_TYPE.NINE_PART_DRAWABLE)
ADDON:ImportObject(OBJECT_TYPE.COLOR_DRAWABLE)
ADDON:ImportObject(OBJECT_TYPE.WINDOW)
ADDON:ImportObject(OBJECT_TYPE.LABEL)
ADDON:ImportAPI(API_TYPE.CHAT.id)
ADDON:ImportAPI(API_TYPE.AUCTION.id)

local CONFIG = AH_PRICE_WATCH_CONFIG or {}
local FEATURES = AH_PRICE_WATCH_FEATURES
local CATALOG, UI = AH_PRICE_WATCH_CATALOG, AH_PRICE_WATCH_UI
local MARKET = AH_PRICE_WATCH_MARKET
local market
local settingsOpen = false
local ITEMS = CONFIG.items or {}
local DEBUG = CONFIG.DEBUG == true
local ALERT_COOLDOWN = math.max(0, tonumber(CONFIG.alertCooldownSeconds) or 1800)
local VERSION = "1.1.2"
local storage = AH_PRICE_WATCH_STORAGE.New(ADDON)

-- v073 reconstructs the existing in-memory shape from bounded component keys.
local function BuildInitialState()
    local loaded = storage:Load()
    return loaded
end

local RESULT_READ_DELAY_MS = math.max(100, tonumber(CONFIG.resultReadDelayMs) or 250)
local PASSIVE_RETRY_MS = math.max(100, tonumber(CONFIG.passiveRetryMs) or 250)
local MAX_READ_ATTEMPTS = math.max(1, math.floor(tonumber(CONFIG.maxResultReadAttempts) or 8))
local MAX_LISTINGS = math.max(1, math.min(50, math.floor(tonumber(CONFIG.maxListingsPerPage) or 50)))
local MIN_STAT_SAMPLES = math.max(2, math.floor(tonumber(CONFIG.minStatSamples) or 8))
local MIN_STAT_DAYS = math.max(1, math.floor(tonumber(CONFIG.minStatDays) or 2))
local MIN_30D_STAT_SAMPLES = math.max(MIN_STAT_SAMPLES, math.floor(tonumber(CONFIG.min30dStatSamples) or 16))
local MIN_30D_STAT_DAYS = math.max(MIN_STAT_DAYS, math.floor(tonumber(CONFIG.min30dStatDays) or 4))
local SAME_PRICE_DEDUPE_SECONDS = math.max(0, math.floor(tonumber(CONFIG.samePriceDedupeSeconds) or 900))
local BUY_RATIO = tonumber(CONFIG.buyRatio) or 0.92
local GREAT_BUY_RATIO = tonumber(CONFIG.greatBuyRatio) or 0.85
local BUY_RATIO_30D = tonumber(CONFIG.buyRatio30d) or 0.92
local GREAT_BUY_RATIO_30D = tonumber(CONFIG.greatBuyRatio30d) or 0.85

-- Custom ESC-menu content. Keep this separate from native UIC_* ids.
-- v0.6.6 uses a fresh id so an old test build cannot leave the native
-- content manager in a stale open/closed state across addon reloads.
local ESC_MENU_CATEGORY = math.floor(tonumber(CONFIG.escMenuCategoryId) or 3)
local ESC_CONTENT_ID = math.floor(tonumber(CONFIG.escMenuContentId) or 1100)

local state = BuildInitialState()
MARKET.RepairLegacy(state)
MARKET.Migrate(state, MARKET.Today())
state.position = state.position or { x = 300, y = 220 }
state.last = state.last or {}
state.daily = state.daily or {}
-- Preserve recoverable saved items; missing data never seeds development items.
if type(state.watchItems) ~= "table" then state.watchItems = {} end
state.watchItems = AH_PRICE_WATCH_PACK_IDENTITY.Migrate(state.watchItems,state)
ITEMS = FEATURES.CopyItems(state.watchItems)
CATALOG.Hydrate(ITEMS)
state.watchItems = FEATURES.CopyItems(ITEMS)
state.alerts = state.alerts or {}
-- Seed notification state from the prior version's episode latch.
for name, last in pairs(state.last) do
    if last.alertSignal and not state.alerts[name] then
        state.alerts[name] = { signal = last.alertSignal, price = last.price,
            notified = { [last.alertSignal] = { price = last.price, time = tonumber(last.time) or 0 } } }
    end
end
if state.auto == nil then state.auto = false end
state.tableVisible = false
if state.language ~= "JA" and state.language ~= "KO" and state.language ~= "EN" then
    state.language = tostring(CONFIG.defaultLanguage or "EN")
    if state.language ~= "JA" and state.language ~= "KO" and state.language ~= "EN" then state.language = "EN" end
end

-- UI language and Auction search language are independent. Only documented
-- locale strings are accepted; an unavailable/unsupported locale uses a saved choice.
if state.searchLanguage ~= "EN" and state.searchLanguage ~= "KO" then state.searchLanguage = "EN" end
local clientSearchLanguage
if API_TYPE.LOCALE then
    local ok, locale = pcall(function()
        ADDON:ImportAPI(API_TYPE.LOCALE.id)
        return X2Locale:GetLocale()
    end)
    if ok then
        if locale == "en_us" or locale == "en_sg" then clientSearchLanguage = "EN"
        elseif locale == "ko" then clientSearchLanguage = "KO" end
    end
end
local function SearchLanguage()
    return clientSearchLanguage or state.searchLanguage
end

local storageFailureNotified = false
local notifyStorageFailure
local function SaveState()
    local ok = storage:Save(state)
    if not ok and notifyStorageFailure and not storageFailureNotified then
        storageFailureNotified = true
        notifyStorageFailure()
    end
    return ok
end

local I18N = {
    EN = {
        storageInitialFailed = "The first v073 save could not be completed. Existing stored data was not cleared. Please report this error before retrying.",
        storageFailed = "Data could not be saved safely. Previous saved data is retained. Reload before retrying.",
        title = "AH Tracker",
        headerItem = "Item",
        headerNow = "Now",
        tableHeaderNow = "Current",
        header7Avg = "7d Avg",
        header14Avg = "14d Avg", header14High = "14d High", headerVolume = "Volume",
        volumeHigh = "High", volumeNormal = "Normal", volumeLow = "Low", unavailable = "—",
        header7High = "7d High",
        header30Avg = "30d Avg",
        header30High = "30d High",
        headerSignal = "Signal",
        headerTime = "Time",
        lastUpdate = "Updated",
        scanComplete = "Scan complete",
        autoOn = "Update on AH Open: ON",
        autoOff = "Update on AH Open: OFF",
        lang = "LANG: EN",
        off = "OFF",
        unknown = "unknown",
        escMenuFail = "ESC menu integration failed: %s",
        eventFailed = "AUCTION_ITEM_SEARCHED registration failed: %s",
        signalREADY = "READY",
        signalCOLLECT = "COLLECTING",
        signalWAIT = "WAIT",
        signalBUY = "BUY",
        signalGREAT = "GREAT",
        signalTARGET = "TARGET",
        nativeScan = "Native AH auto scan: %s",
        nativeDone = "Native AH auto scan: %d/%d updated",
        chatPrefix = "[AH Tracker] ",
        escMenuName = "AH Tracker",
        statusOpenCheck = "AUTO OFF",
        statusAuto = "AUTO ON | Open Auction House",
        statusAutoOff = "AUTO OFF",
        statusChanged = "AUTO OFF",
        statusNoReadable = "No readable results",
        statusUntracked = "No watched items in results",
        statusCaptured = "Updated %d items",
        nativeWaiting = "Preparing search...",
        nativeFailed = "Search stopped; use normal AH search",
        hint = "Alerts: BUY / GREAT / TARGET",
        settings = "Settings",
        settingsTitle = "Watchlist / Target Price",
        watchList = "Watchlist",
        englishItem = "Item Name (choose a suggestion)",
        targetUnit = "Target per item (all zeros = disabled)",
        gold = "Gold (0-99999999)",
        silver = "Silver (0-99)",
        copper = "Copper (0-99)",
        applyItem = "Apply",
        deleteItem = "Delete Selected",
        saveSettings = "Save settings",
        cancel = "Cancel",
        draftHint = "Choose a suggestion and Add Item. Select a row to Apply its target, then Save Settings.",
        emptyName = "Enter an item name.",
        englishName = "Use an English client name (printable ASCII, max 64 characters).",
        duplicateName = "This item is already in the watchlist.",
        invalidPrice = "Use whole numbers. Gold: 0-99999999, Silver/Copper: 0-99.",
        settingsBusy = "Search in progress. Save after it finishes (your draft is kept).",
        settingsSaved = "Settings saved. Changes apply the next time AH opens.",
        settingsUnavailable = "Settings UI unavailable; check the globals dependency.",
        addItem = "Add Item",
        editSelected = "Edit Selected Item",
        newEditor = "Add an Item",
        targetPrefix = "Target:",
        searchLanguage = "AH Search Language",
        searchLanguageAuto = "Client locale",
        searchLanguageManual = "Manual selection",
        catalogAmbiguous = "Several item IDs share this name. Select a dropdown candidate.",
        catalogSelect = "Select an exact item from the suggestions.",
    },
    JA = {
        storageInitialFailed = "v073の初回保存が完了しませんでした。既存データは削除していません。このエラーを報告してください。",
        storageFailed = "安全に保存できませんでした。以前の保存データは保持されています。再ログイン後に再試行してください。",
        title = "AH Tracker",
        headerItem = "アイテム",
        headerNow = "現在価格",
        tableHeaderNow = "現在",
        header7Avg = "7日平均",
        header14Avg = "14日平均", header14High = "14日最高", headerVolume = "取引量",
        volumeHigh = "多い", volumeNormal = "普通", volumeLow = "少ない", unavailable = "—",
        header7High = "7日最高",
        header30Avg = "30日平均",
        header30High = "30日最高",
        headerSignal = "判定",
        headerTime = "時刻",
        lastUpdate = "最終更新",
        scanComplete = "スキャン完了",
        autoOn = "AH起動時更新: ON",
        autoOff = "AH起動時更新: OFF",
        lang = "言語: 日本語",
        off = "無効",
        unknown = "不明",
        escMenuFail = "ESCメニュー統合に失敗しました: %s",
        eventFailed = "AUCTION_ITEM_SEARCHEDの登録に失敗: %s",
        signalREADY = "準備",
        signalCOLLECT = "履歴収集中",
        signalWAIT = "待機",
        signalBUY = "買い",
        signalGREAT = "激安",
        signalTARGET = "目標",
        nativeScan = "通常AH自動取得: %s",
        nativeDone = "通常AH自動取得: %d/%d件更新",
        chatPrefix = "[AH Tracker] ",
        escMenuName = "AH Tracker",
        statusOpenCheck = "自動 OFF",
        statusAuto = "自動 ON | 通常AHを開いてください",
        statusAutoOff = "自動 OFF",
        statusChanged = "自動 OFF",
        statusNoReadable = "読み取れる結果がありません",
        statusUntracked = "検索結果に監視対象なし",
        statusCaptured = "%d品の価格を更新",
        nativeWaiting = "検索準備中...",
        nativeFailed = "検索停止：通常AHの検索結果は引き続き記録",
        hint = "通知: BUY / GREAT / TARGET",
        settings = "設定",
        settingsTitle = "監視アイテム / 目標価格",
        watchList = "監視リスト",
        englishItem = "アイテム名（候補から選択）",
        targetUnit = "目標単価（すべて0で無効）",
        gold = "Gold（0-99999999）",
        silver = "Silver（0-99）",
        copper = "Copper（0-99）",
        applyItem = "適用",
        deleteItem = "選択項目を削除",
        saveSettings = "設定を保存",
        cancel = "キャンセル",
        draftHint = "候補選択→アイテムを追加。リスト選択→目標価格を適用。最後に設定を保存。",
        emptyName = "アイテム名を入力してください。",
        englishName = "英語クライアントの名前を半角英数字・記号64文字以内で入力してください。",
        duplicateName = "このアイテムは登録済みです。",
        invalidPrice = "整数で入力してください。Gold: 0-99999999、Silver/Copper: 0-99。",
        settingsBusy = "価格取得中です。完了後に保存してください（編集中の内容は保持）。",
        settingsSaved = "設定を保存しました。次回AHを開いたときから反映されます。",
        settingsUnavailable = "設定UIを利用できません。globals依存関係を確認してください。",
        addItem = "アイテムを追加",
        editSelected = "選択アイテム編集",
        newEditor = "新規アイテム追加",
        targetPrefix = "目標:",
        searchLanguage = "AH Search Language",
        searchLanguageAuto = "クライアントから自動選択",
        searchLanguageManual = "手動選択",
        catalogAmbiguous = "同名のItem IDが複数あります。候補を選択してください。",
        catalogSelect = "候補から正式なアイテム名を選択してください。",
    },
    KO = {
        storageInitialFailed = "v073 최초 저장을 완료하지 못했습니다. 기존 저장 데이터는 삭제하지 않았습니다. 재시도 전에 이 오류를 보고해 주세요.",
        storageFailed = "데이터를 안전하게 저장하지 못했습니다. 이전 저장 데이터는 유지됩니다. 재접속 후 다시 시도하세요.",
        title = "AH Tracker",
        headerItem = "아이템",
        headerNow = "현재 가격",
        tableHeaderNow = "현재",
        header7Avg = "7일 평균",
        header14Avg = "14일 평균", header14High = "14일 최고", headerVolume = "거래량",
        volumeHigh = "많음", volumeNormal = "보통", volumeLow = "적음", unavailable = "—",
        header7High = "7일 최고",
        header30Avg = "30일 평균",
        header30High = "30일 최고",
        headerSignal = "판정",
        headerTime = "시간",
        lastUpdate = "최근 갱신",
        scanComplete = "스캔 완료",
        autoOn = "AH 열 때 갱신: ON",
        autoOff = "AH 열 때 갱신: OFF",
        lang = "언어: 한국어",
        off = "꺼짐",
        unknown = "알 수 없음",
        escMenuFail = "ESC 메뉴 연동에 실패했습니다: %s",
        eventFailed = "AUCTION_ITEM_SEARCHED 등록 실패: %s",
        signalREADY = "준비",
        signalCOLLECT = "데이터 수집 중",
        signalWAIT = "대기",
        signalBUY = "구매",
        signalGREAT = "특가",
        signalTARGET = "목표",
        nativeScan = "일반 AH 자동 수집: %s",
        nativeDone = "일반 AH 자동 수집: %d/%d개 갱신",
        chatPrefix = "[AH Tracker] ",
        escMenuName = "AH Tracker",
        statusOpenCheck = "자동 OFF",
        statusAuto = "자동 ON | 일반 AH를 여세요",
        statusAutoOff = "자동 OFF",
        statusChanged = "자동 OFF",
        statusNoReadable = "읽을 수 있는 결과 없음",
        statusUntracked = "검색 결과에 감시 대상 없음",
        statusCaptured = "%d개 가격 갱신",
        nativeWaiting = "검색 준비 중...",
        nativeFailed = "검색 중지: 일반 AH 검색은 계속 기록",
        hint = "알림: BUY / GREAT / TARGET",
        settings = "설정",
        settingsTitle = "감시 아이템 / 목표 가격",
        watchList = "감시 목록",
        englishItem = "아이템 이름 (후보에서 선택)",
        targetUnit = "목표 단가 (모두 0이면 비활성화)",
        gold = "Gold (0-99999999)",
        silver = "Silver (0-99)",
        copper = "Copper (0-99)",
        applyItem = "적용",
        deleteItem = "선택 항목 삭제",
        saveSettings = "설정 저장",
        cancel = "취소",
        draftHint = "후보 선택 후 아이템 추가. 목록 선택 후 목표 가격 적용. 마지막으로 설정 저장.",
        emptyName = "아이템 이름을 입력하세요.",
        englishName = "영어 클라이언트 이름을 영문/숫자/기호 최대 64자로 입력하세요.",
        duplicateName = "이미 등록된 아이템입니다.",
        invalidPrice = "정수를 입력하세요. Gold: 0-99999999, Silver/Copper: 0-99.",
        settingsBusy = "가격 수집 중입니다. 완료 후 저장하세요 (편집 내용 유지).",
        settingsSaved = "설정을 저장했습니다. 다음 AH를 열 때부터 적용됩니다.",
        settingsUnavailable = "설정 UI를 사용할 수 없습니다. globals 의존성을 확인하세요.",
        addItem = "아이템 추가",
        editSelected = "선택 아이템 편집",
        newEditor = "새 아이템 추가",
        targetPrefix = "목표:",
        searchLanguage = "AH Search Language",
        searchLanguageAuto = "클라이언트 자동 선택",
        searchLanguageManual = "수동 선택",
        catalogAmbiguous = "같은 이름의 아이템 ID가 여러 개입니다. 후보를 선택하세요.",
        catalogSelect = "후보에서 정확한 아이템을 선택하세요.",
    },
}

local function T(key)
    local lang = I18N[state.language] or I18N.EN
    return lang[key] or I18N.EN[key] or tostring(key)
end

local function SignalText(signal)
    return T("signal" .. tostring(signal or "READY"))
end

local function Chat(msg)
    X2Chat:DispatchChatMessage(CMF_SYSTEM, T("chatPrefix") .. tostring(msg))
end

notifyStorageFailure = function() Chat(T(storage.root and "storageFailed" or "storageInitialFailed")) end

local function NumberFromAny(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then
        local cleaned = string.gsub(value, "[^0-9%.%-]", "")
        return tonumber(cleaned)
    end
    return nil
end

local function CopperFromGold(gold)
    local n = tonumber(gold) or 0
    return math.floor((n * 10000) + 0.5)
end

local function MoneyText(copper)
    local n = tonumber(copper)
    if n == nil or n <= 0 then return "-" end
    n = math.floor(n + 0.5)
    local g = math.floor(n / 10000)
    local s = math.floor((n % 10000) / 100)
    local c = n % 100
    if g > 0 then return string.format("%dg %02ds %02dc", g, s, c) end
    if s > 0 then return string.format("%ds %02dc", s, c) end
    return string.format("%dc", c)
end

local function Timestamp()
    local ok, t = pcall(function() return os.time() end)
    if ok and tonumber(t) ~= nil then return tonumber(t) end
    return 0
end

local function TimeText(ts)
    local ok, t
    if tonumber(ts) ~= nil and tonumber(ts) > 0 then
        ok, t = pcall(function() return os.date("%H:%M", tonumber(ts)) end)
    else
        ok, t = pcall(function() return os.date("%H:%M") end)
    end
    if ok and t ~= nil then return tostring(t) end
    return "--:--"
end

local function DayKey(ts)
    local ok, t = pcall(function() return os.date("%Y-%m-%d", tonumber(ts) or Timestamp()) end)
    if ok and t ~= nil then return tostring(t) end
    return tostring(math.floor((tonumber(ts) or 0) / 86400))
end

local function FindWatchItemIndexByName(name, itemType)
    if type(name) ~= "string" then return nil end
    for i, item in ipairs(ITEMS) do
        if CATALOG.Matches(item, name, itemType) then return i end
    end
    return nil
end

local function ExtractListing(info)
    if type(info) ~= "table" then return nil end
    local name = type(info.name) == "string" and info.name or "?"
    local direct = NumberFromAny(info.directPriceStr)
    local stackCount = NumberFromAny(info.stackCount)
    local stack = stackCount or NumberFromAny(info.stack)
    if direct ~= nil then direct = math.floor(direct + 0.5) end
    if stack ~= nil then stack = math.floor(stack + 0.5) end
    local unit = nil
    if direct ~= nil and direct > 0 and stack ~= nil and stack > 0 then
        unit = math.floor((direct / stack) + 0.5)
    end
    return { name = name, direct = direct, stack = stack, stackCount = stackCount, unit = unit, raw = info }
end


local function CleanupDaily(itemName, now)
    local buckets = state.daily[itemName]
    if type(buckets) ~= "table" then return end
    local cutoff = (tonumber(now) or Timestamp()) - (35 * 86400)
    local kept = {}
    for _, b in ipairs(buckets) do
        if type(b) == "table" and (tonumber(b.lastTime) or 0) >= cutoff then
            kept[#kept + 1] = b
        end
    end
    state.daily[itemName] = kept
end

local function RecordDaily(itemName, price, now)
    state.daily[itemName] = state.daily[itemName] or {}
    local buckets = state.daily[itemName]
    local key = DayKey(now)
    local bucket = nil
    for _, b in ipairs(buckets) do
        if b.key == key then bucket = b break end
    end
    if bucket == nil then
        bucket = {
            key = key,
            count = 0,
            sum = 0,
            high = price,
            low = price,
            firstTime = now,
            lastTime = now,
        }
        buckets[#buckets + 1] = bucket
    end
    bucket.count = (tonumber(bucket.count) or 0) + 1
    bucket.sum = (tonumber(bucket.sum) or 0) + price
    bucket.high = math.max(tonumber(bucket.high) or price, price)
    bucket.low = math.min(tonumber(bucket.low) or price, price)
    bucket.lastTime = now
    CleanupDaily(itemName, now)
end

local function StatsFor(itemName, days, now)
    local buckets = state.daily[itemName]
    local out = { count = 0, days = 0, sum = 0, avg = nil, high = nil, low = nil }
    if type(buckets) ~= "table" then return out end
    local cutoff = (tonumber(now) or Timestamp()) - ((tonumber(days) or 0) * 86400)
    for _, b in ipairs(buckets) do
        local lastTime = tonumber(b.lastTime) or 0
        if lastTime >= cutoff then
            local c = tonumber(b.count) or 0
            local s = tonumber(b.sum) or 0
            if c > 0 then
                out.count = out.count + c
                out.days = out.days + 1
                out.sum = out.sum + s
                local hi = tonumber(b.high)
                local lo = tonumber(b.low)
                if hi ~= nil then out.high = out.high == nil and hi or math.max(out.high, hi) end
                if lo ~= nil then out.low = out.low == nil and lo or math.min(out.low, lo) end
            end
        end
    end
    if out.count > 0 then out.avg = math.floor((out.sum / out.count) + 0.5) end
    return out
end

local function MarketStatsFor(item, last)
    local record=CATALOG.ForItem(item)
    local selected=record and state.marketSelected[record.id]
    if not selected or type(last)~="table" or selected.price~=last.price then return {} end
    return MARKET.Stats(state,record.id,selected.grade,MARKET.Today())
end

local function SignalFor(index, price, now)
    local item = ITEMS[index]
    if item == nil or tonumber(price) == nil then return "READY", nil, nil, nil end
    price = tonumber(price)
    local s7 = StatsFor(item.name, 7, now)
    local s30 = StatsFor(item.name, 30, now)
    local target = CopperFromGold(item.targetGold)

    if target > 0 and price <= target then
        return "TARGET", target, s7, s30
    end

    -- Same selected item/grade/price and calendar window as the displayed 14d Avg.
    local marketAvg = MarketStatsFor(item, state.last[item.name]).avg14
    if marketAvg ~= nil then
        -- Integer percent arithmetic avoids floating-point boundary off-by-one.
        local great = math.floor(marketAvg / 100) * 85 + math.floor((marketAvg % 100) * 85 / 100)
        local buy = math.floor(marketAvg / 100) * 92 + math.floor((marketAvg % 100) * 92 / 100)
        if price <= great then return "GREAT", great, s7, s30, marketAvg end
        if price <= buy then return "BUY", buy, s7, s30, marketAvg end
        return "WAIT", nil, s7, s30, marketAvg
    end

    local ready7 = s7.avg ~= nil and s7.count >= MIN_STAT_SAMPLES and (tonumber(s7.days) or 0) >= MIN_STAT_DAYS
    local ready30 = s30.avg ~= nil and s30.count >= MIN_30D_STAT_SAMPLES and (tonumber(s30.days) or 0) >= MIN_30D_STAT_DAYS

    if ready7 and price <= math.floor(s7.avg * GREAT_BUY_RATIO) then
        return "GREAT", math.floor(s7.avg * GREAT_BUY_RATIO), s7, s30
    end
    if ready30 and price <= math.floor(s30.avg * GREAT_BUY_RATIO_30D) then
        return "GREAT", math.floor(s30.avg * GREAT_BUY_RATIO_30D), s7, s30
    end
    if ready7 and price <= math.floor(s7.avg * BUY_RATIO) then
        return "BUY", math.floor(s7.avg * BUY_RATIO), s7, s30
    end
    if ready30 and price <= math.floor(s30.avg * BUY_RATIO_30D) then
        return "BUY", math.floor(s30.avg * BUY_RATIO_30D), s7, s30
    end

    if not ready7 and not ready30 then
        return "COLLECT", nil, s7, s30
    end
    return "WAIT", nil, s7, s30
end

-- UI -------------------------------------------------------------------------
-- Ten columns in the existing width; taller rows allow bounded two-line labels.
local window = CreateEmptyWindow("ahPriceWatchWindow", "UIParent")
-- Recomputed only at initialization/UI reload; dragging never changes page size.
local mainGeometry = UI.MainGeometry(UIParent, DEBUG)
local PAGE_SIZE, tablePage = mainGeometry.pageSize, 1
local PANEL_WIDTH, TABLE_TOP, ROW_HEIGHT = UI.PANEL_WIDTH, UI.TABLE_TOP, UI.ROW_HEIGHT
local bottomY = mainGeometry.bottomY
window:SetExtent(PANEL_WIDTH, mainGeometry.height)
local savedPosition = type(state.position) == "table" and state.position or {}
local positionX, positionY = UI.ClampMainPosition(mainGeometry, savedPosition.x, savedPosition.y)
state.position = { x = positionX, y = positionY }
window:AddAnchor("TOPLEFT", "UIParent", positionX, positionY)
window:EnableDrag(false)
window:Show(state.tableVisible == true)

-- Native first Show changes hidden anchor coordinates; restore once while shown.
local startupPositionRestorePending = true
local function RestoreStartupPosition()
    if not startupPositionRestorePending or not window:IsVisible() then return end
    local saved = type(state.position) == "table" and state.position or {}
    local screenWidth, screenHeight = UI.EffectiveSize(UIParent)
    local bounds = {
        width = mainGeometry.width, height = mainGeometry.height,
        screenWidth = screenWidth or mainGeometry.screenWidth,
        screenHeight = screenHeight or mainGeometry.screenHeight
    }
    local x, y = UI.ClampMainPosition(bounds, saved.x, saved.y)
    window:RemoveAllAnchors()
    window:AddAnchor("TOPLEFT", "UIParent", x, y)
    local changed = saved.x ~= x or saved.y ~= y
    state.position = { x = x, y = y }
    startupPositionRestorePending = false
    if changed then SaveState() end
end

local background = window:CreateColorDrawable(0, 0, 0, 0.84, "background")
background:AddAnchor("TOPLEFT", window, 0, 0)
background:AddAnchor("BOTTOMRIGHT", window, 0, 0)

-- Sibling of Close; bounded above the headers. Mirrors globals/CreateTitleBar.
local titleBar = window:CreateChildWidget("window", "ahPriceWatchTitleBar", 0, true)
titleBar:SetExtent(PANEL_WIDTH - 80, 34)
titleBar:AddAnchor("TOPLEFT", window, 12, 2)
titleBar:EnableDrag(true)
titleBar:Show(true)
local titleBackground = titleBar:CreateColorDrawable(0.14, 0.18, 0.24, 0.55, "background")
titleBackground:AddAnchor("TOPLEFT", titleBar, 0, 0)
titleBackground:AddAnchor("BOTTOMRIGHT", titleBar, 0, 0)
local title = titleBar:CreateChildWidget("label", "ahPriceWatchTitle", 0, false)
title:SetExtent(PANEL_WIDTH - 80, 34)
title:AddAnchor("TOPLEFT", titleBar, 0, 0)
title:EnableDrag(true)
title.style:SetFontSize(17)
title.style:SetAlign(ALIGN_LEFT)
title.style:SetColor(255, 255, 255, 255)
title:SetText(T("title") .. " v" .. VERSION)

local statusLabel = window:CreateChildWidget("label", "ahPriceWatchStatus", 0, false)
statusLabel:SetExtent(PANEL_WIDTH - 24, 18)
statusLabel:AddAnchor("TOPLEFT", window, 12, bottomY + 58)
statusLabel.style:SetFontSize(11)
statusLabel.style:SetAlign(ALIGN_LEFT)
statusLabel.style:SetColor(190, 190, 190, 255)
statusLabel:SetText(T("statusOpenCheck"))
statusLabel:Show(DEBUG)

local closeButton = window:CreateChildWidget("button", "ahPriceWatchCloseButton", 0, true)
closeButton:SetStyle("text_default")
closeButton:SetExtent(28, 24)
closeButton:AddAnchor("TOPRIGHT", window, "TOPRIGHT", -24, 8)
UI.Inside(PANEL_WIDTH - 24 - 28, 28, PANEL_WIDTH, 12)
closeButton:SetText("X")

-- Header and cell widths share these definitions to prevent column drift.
local headers = {
    { key = "headerItem", field = "name", w = 167, align = ALIGN_LEFT },
    { key = "tableHeaderNow", field = "now", w = 72, align = ALIGN_RIGHT },
    { key = "header7Avg", field = "avg7", w = 72, align = ALIGN_RIGHT },
    { key = "header7High", field = "high7", w = 72, align = ALIGN_RIGHT },
    { key = "header14Avg", field = "avg14", w = 72, align = ALIGN_RIGHT },
    { key = "header14High", field = "high14", w = 72, align = ALIGN_RIGHT },
    { key = "header30Avg", field = "avg30", w = 72, align = ALIGN_RIGHT },
    { key = "header30High", field = "high30", w = 72, align = ALIGN_RIGHT },
    { key = "headerVolume", field = "volume", w = 60, align = ALIGN_RIGHT },
    { key = "headerSignal", field = "signal", w = 88, align = ALIGN_RIGHT },
}
local columnX=12
for _,h in ipairs(headers) do
    h.x=columnX;UI.Inside(h.x,h.w,PANEL_WIDTH,12);columnX=columnX+h.w+5
end

local headerLabels = {}
for i, h in ipairs(headers) do
    local lbl = window:CreateChildWidget("label", "ahPriceWatchHeader" .. i, 0, false)
    lbl:SetExtent(h.w, 26)
    lbl:AddAnchor("TOPLEFT", window, h.x, 40)
    lbl.style:SetFontSize(11)
    lbl.style:SetAlign(h.align)
    lbl.style:SetColor(170, 170, 170, 255)
    lbl:SetText(T(h.key))
    headerLabels[i] = lbl
end

local rows = {}
for i = 1, UI.MAX_PAGE_SIZE do
    local y = TABLE_TOP + ((i - 1) * ROW_HEIGHT)
    local row = {}

    row.name = window:CreateChildWidget("label", "ahPriceWatchName" .. i, 0, false)
    row.name:SetExtent(headers[1].w, 32)
    row.name:AddAnchor("TOPLEFT", window, headers[1].x, y)
    row.name.style:SetFontSize(12)
    row.name.style:SetAlign(ALIGN_LEFT)
    row.name.style:SetColor(255, 255, 255, 255)
    row.name:SetText(ITEMS[i] and UI.ItemText(CATALOG.ItemDisplayName(ITEMS[i], state.language)) or "")

    for column = 2, #headers do
        local f = headers[column]
        row[f.field] = window:CreateChildWidget("label", "ahPriceWatch_" .. f.field .. "_" .. i, 0, false)
        row[f.field]:SetExtent(f.w, 32)
        row[f.field]:AddAnchor("TOPLEFT", window, f.x, y)
        row[f.field].style:SetFontSize(f.field == "signal" and 11 or 10)
        row[f.field].style:SetAlign(f.align)
        row[f.field].style:SetColor(220, 220, 220, 255)
    end
    rows[i] = row
end

local scanCompleted, scanCompletionPending = false, false
local lastUpdateLabel = window:CreateChildWidget("label", "ahPriceWatchLastUpdate", 0, false)
lastUpdateLabel:SetExtent(240, 18)
lastUpdateLabel:AddAnchor("TOPLEFT", window, 12, bottomY + 34)
lastUpdateLabel.style:SetFontSize(11)
lastUpdateLabel.style:SetAlign(ALIGN_LEFT)
lastUpdateLabel.style:SetColor(170, 170, 170, 255)

local function RefreshLastUpdate()
    local latest = 0
    for _, item in ipairs(ITEMS) do
        local last = state.last[item.name]
        latest = math.max(latest, type(last) == "table" and tonumber(last.time) or 0)
    end
    lastUpdateLabel:SetText(T("lastUpdate") .. " " .. (latest > 0 and TimeText(latest) or "--:--") ..
        (scanCompleted and ("  " .. T("scanComplete")) or ""))
end

-- Display only: keep the shared price formatter and all stored values intact.
local function TableMoneyText(value)
    local n=tonumber(value)
    local text=(MoneyText(value):gsub(" ", ""):gsub("00c$", ""))
    if n and n>21474836470000 and MARKET.Integer(n) then
        text=string.format("%.0fg%02ds%02dc",math.floor(n/10000),math.floor(n/100)%100,n%100):gsub("00c$", "")
    end
    if #text>12 then
        local goldEnd=text:find("g",1,true)
        local split=goldEnd and goldEnd<=12 and goldEnd or 12
        text=text:sub(1,split).."\n"..text:sub(split+1)
    end
    return text
end

local function SetStatus(text)
    statusLabel:SetText(tostring(text or ""))
end

local function ObserveMarket(index, info, price)
    local item=ITEMS[index];local record=CATALOG.ForItem(item)
    if not record then return nil end
    state.marketSelected[record.id]=nil
    if type(info)~="table" then return nil end
    local id,grade=rawget(info,"itemType"),rawget(info,"itemGrade")
    if type(id)~="number" or type(grade)~="number" or id~=record.id or not MARKET.Integer(grade) then return nil end
    state.marketSelected[id]={grade=grade,price=price}
    return {id=id,grade=grade,name=record.en,names={[record.en]=true,[record.ko]=true,[item.name]=true}}
end

local function RefreshRow(index)
    RefreshLastUpdate() -- Also refresh when the updated item is on another page.
    local item = ITEMS[index]
    local slot = index - (tablePage - 1) * PAGE_SIZE
    if slot < 1 or slot > PAGE_SIZE then return end
    local row = rows[slot]
    if row == nil then return end
    for _, widget in pairs(row) do widget:Show(item ~= nil) end
    if item == nil then return end
    row.name:SetText(UI.ItemText(CATALOG.ItemDisplayName(item, state.language)))
    row.name.style:SetColor(255, 255, 255, 255)

    local last = state.last[item.name]
    local now = Timestamp()
    local stats = MarketStatsFor(item,last)
    local target = CopperFromGold(item.targetGold)

    for _,field in ipairs({"avg7","high7","avg14","high14","avg30","high30"}) do
        row[field]:SetText(stats[field]~=nil and (stats[field]==0 and "0c" or TableMoneyText(stats[field])) or T("unavailable"))
    end
    row.volume:SetText(stats.volume and T("volume"..stats.volume) or T("unavailable"))
    if row.target then
        row.target:SetText(target > 0 and TableMoneyText(target) or T("off"))
        row.target.style:SetColor(190, 190, 190, 255)
    end

    if type(last) == "table" and tonumber(last.price) ~= nil and tonumber(last.price) > 0 then
        local price = tonumber(last.price)
        local signal = SignalFor(index, price, now)
        row.now:SetText(TableMoneyText(price))
        row.signal:SetText(SignalText(signal))
        if signal == "BUY" or signal == "GREAT" or signal == "TARGET" then
            row.name:SetText(UI.ItemText(CATALOG.ItemDisplayName(item, state.language)))
            row.name.style:SetColor(140, 235, 150, 255)
        end
        if signal == "TARGET" or signal == "GREAT" then
            if signal == "TARGET" then
                row.signal.style:SetColor(255, 205, 90, 255)
            else
                row.signal.style:SetColor(100, 220, 255, 255)
            end
            row.now.style:SetColor(100, 235, 130, 255)
        elseif signal == "BUY" then
            row.signal.style:SetColor(140, 225, 150, 255)
            row.now.style:SetColor(140, 225, 150, 255)
        elseif signal == "COLLECT" then
            row.signal.style:SetColor(150, 195, 255, 255)
            row.now.style:SetColor(255, 255, 255, 255)
        else
            row.signal.style:SetColor(235, 205, 100, 255)
            row.now.style:SetColor(255, 255, 255, 255)
        end
    else
        row.now:SetText("-")
        row.signal:SetText(SignalText("READY"))
        row.signal.style:SetColor(180, 180, 180, 255)
        row.now.style:SetColor(255, 255, 255, 255)
    end
end

local function RefreshAllRows()
    for i = 1, PAGE_SIZE do RefreshRow((tablePage - 1) * PAGE_SIZE + i) end
    for i = PAGE_SIZE + 1, UI.MAX_PAGE_SIZE do
        for _, widget in pairs(rows[i]) do widget:Show(false) end
    end
end


local function MaybeAlert(index, price, now)
    local item = ITEMS[index]
    if item == nil then return end
    local signal, _, s7, s30, marketAvg = SignalFor(index, price, now)
    if FEATURES.Alert(state.alerts, item.name, signal, price, now, ALERT_COOLDOWN) then
        local basis = marketAvg ~= nil and (" | " .. T("header14Avg") .. " " .. MoneyText(marketAvg)) or
            (" | " .. T("header7Avg") .. " " .. MoneyText(s7 and s7.avg) ..
             " | " .. T("header30Avg") .. " " .. MoneyText(s30 and s30.avg))
        Chat(signal .. ": " .. item.name .. " | " .. T("headerNow") .. " " .. MoneyText(price) .. basis)
    end
end

-- A successful asynchronous Market merge can enable a Signal before another Current sample.
local function RefreshAfterMarket()
    RefreshAllRows()
    local pending = market and market.pending
    if not pending then return end
    local changed = false
    for index, item in ipairs(ITEMS) do
        local record = CATALOG.ForItem(item)
        local last = state.last[item.name]
        local selected = record and state.marketSelected[record.id]
        if record and record.id == pending.id and selected and selected.grade == pending.grade and
            type(last) == "table" and MarketStatsFor(item,last).avg14 ~= nil then
            MaybeAlert(index,last.price,Timestamp())
            changed = true
        end
    end
    if changed then pcall(SaveState) end -- persist the same cooldown state used by Current alerts
end

market=MARKET.Requests({state=state,day=MARKET.Today,save=SaveState,refresh=RefreshAfterMarket,
    send=function(id,grade) return X2Auction:AskMarketPrice(id,grade,true) end})
local marketReceiverOK=pcall(function()
    if not UIEVENT_TYPE.DIAGONAL_ASR or type(UIParent.SetEventHandler)~="function" then error("unavailable") end
    UIParent:SetEventHandler(UIEVENT_TYPE.DIAGONAL_ASR,function(name,grade,ui,payload)
        market:Receive(name,grade,ui,payload)
    end)
end)
market.ready=marketReceiverOK

local function RecordPrice(index, priceValue)
    local item = ITEMS[index]
    local price = tonumber(priceValue)
    if item == nil or price == nil or price <= 0 then return false end
    local now = Timestamp()
    local old = state.last[item.name] or {}

    -- Avoid weighting a 7d/30d average twice when a result is read repeatedly or
    -- AUTO receives the same native result event again. A changed price is always
    -- sampled immediately. An unchanged price becomes a new sample only after the
    -- configured interval from the last *stored sample* (not the last UI refresh).
    local oldPrice = tonumber(old.price)
    local lastSampleTime = tonumber(old.lastSampleTime) or tonumber(old.time) or 0
    local samePrice = oldPrice ~= nil and oldPrice == price
    local tooSoon = SAME_PRICE_DEDUPE_SECONDS > 0 and lastSampleTime > 0 and (now - lastSampleTime) < SAME_PRICE_DEDUPE_SECONDS
    local sampled = not (samePrice and tooSoon)

    if sampled then
        RecordDaily(item.name, price, now)
        lastSampleTime = now
    end

    local keepAlert = old.alertSignal
    state.last[item.name] = {
        price = price,
        previousPrice = oldPrice,
        time = now,
        timeText = TimeText(now),
        lastSampleTime = lastSampleTime,
        alertSignal = keepAlert,
    }
    MaybeAlert(index, price, now)
    SaveState()
    RefreshRow(index)
    return sampled
end

local function AuctionVisible()
    if UIC_AUCTION == nil then return false end
    local ok, x, y, width, height, visible = pcall(function()
        return ADDON:GetContentMainScriptPosVis(UIC_AUCTION)
    end)
    if not ok or type(visible) ~= "boolean" then return false end
    return visible == true
end

-- Passive capture engine ------------------------------------------------------
-- Passive AUTO reads the currently exposed Auction House result page.
local capture = {
    pending = false,
    source = "",
    delay = RESULT_READ_DELAY_MS,
    elapsed = 0,
    attempts = 0,
}

local function InspectCurrentResults()
    local count, total, page
    local okMeta, metaErr = pcall(function()
        count = X2Auction:GetSearchedItemCount()
        total = X2Auction:GetSearchedItemTotalCount()
        page = X2Auction:GetSearchedItemPage()
    end)
    if not okMeta then return false, "meta-error:" .. tostring(metaErr), false end

    count = tonumber(count) or 0
    total = tonumber(total) or 0
    page = tonumber(page) or 0

    -- The event can arrive slightly before native rows become readable.
    if count <= 0 then
        return false, "rows=0 total=" .. tostring(total) .. " page=" .. tostring(page), true
    end

    local probeCount = math.min(count, MAX_LISTINGS)
    local tables = 0
    local bestByIndex = {}
    local stacksByIndex = {}
    local infoByIndex = {}
    local firstName = nil

    for idx = 1, probeCount do
        local info = nil
        local okInfo = pcall(function() info = X2Auction:GetSearchedItemInfo(idx) end)
        if okInfo and type(info) == "table" then
            tables = tables + 1
            local listing = ExtractListing(info)
            if listing ~= nil then
                if firstName == nil and type(listing.name) == "string" then firstName = listing.name end
                local watchIndex = FindWatchItemIndexByName(listing.name, rawget(info, "itemType"))
                if watchIndex ~= nil and listing.unit ~= nil and listing.unit > 0 then
                    local old = bestByIndex[watchIndex]
                    if old == nil or listing.unit < old then
                        bestByIndex[watchIndex] = listing.unit
                        stacksByIndex[watchIndex] = listing.stack
                        infoByIndex[watchIndex] = info
                    end
                end
            end
        end
    end

    if tables <= 0 then
        return false, "rows=" .. tostring(count) .. " tables=0", true
    end

    local found = 0
    for _ in pairs(bestByIndex) do found = found + 1 end
    if found <= 0 then
        return true, { updated = 0, firstName = firstName, rows = count, tables = tables, page = page }, false
    end

    local updatedNames = {}
    local sampledCount = 0
    for watchIndex, price in pairs(bestByIndex) do
        ObserveMarket(watchIndex,infoByIndex[watchIndex],price)
        if RecordPrice(watchIndex, price) then sampledCount = sampledCount + 1 end
        updatedNames[#updatedNames + 1] = ITEMS[watchIndex].name .. " " .. MoneyText(price)
    end
    return true, {
        updated = found,
        sampled = sampledCount,
        names = updatedNames,
        firstName = firstName,
        rows = count,
        tables = tables,
        page = page,
        stacks = stacksByIndex,
    }, false
end

local function FinishCapture(ok, data, source)
    capture.pending = false
    capture.elapsed = 0
    capture.attempts = 0

    if ok and type(data) == "table" then
        if (tonumber(data.updated) or 0) > 0 then
            SetStatus(string.format(T("statusCaptured"), data.updated))
        else
            SetStatus(T("statusUntracked"))
        end
    else
        SetStatus(T("statusNoReadable"))
    end
end

local function TryCapture()
    if not capture.pending then return end
    capture.attempts = capture.attempts + 1
    local ok, data, retryable = InspectCurrentResults()
    if ok then
        FinishCapture(true, data, capture.source)
        return
    end
    if retryable and capture.attempts < MAX_READ_ATTEMPTS then
        capture.delay = PASSIVE_RETRY_MS
        capture.elapsed = 0
        return
    end
    FinishCapture(false, data, capture.source)
end

local function StartCapture(source)
    if not AuctionVisible() then
        capture.pending = false
        SetStatus(T("statusNoReadable"))
        return
    end
    capture.pending = true
    capture.delay = RESULT_READ_DELAY_MS
    capture.source = source or "AUTO"
    capture.elapsed = 0
    capture.attempts = 0
end

-- One-shot search engine ------------------------------------------------------
-- SearchAuctionArticle was enabled on 2025-04-29; GetSearchedItem* on 2025-05-06.
-- Native UI source: Noviern/scriptsbin, commit 945dcab, x2ui/auction/bid.lua.
-- Use nine arguments and the native default grade filter (1 = all grades).
-- The event marks completion; read listing fields from the enabled cache APIs.
-- There is no exposed request identity here: concurrent searches remain ambiguous.
-- Never initialize native AH, switch tabs or call native search button handlers.
local AUTO_OPEN_SETTLE_MS = math.max(1250, math.floor(tonumber(CONFIG.sidecarOpenSettleMs) or 1250))
local SEARCH_QUERY_SPACING_MS = math.max(1100, math.floor(tonumber(CONFIG.searchQuerySpacingMs) or 1250))
local SEARCH_QUERY_TIMEOUT_MS = math.max(1800, math.floor(tonumber(CONFIG.searchQueryTimeoutMs) or 4200))
local settingsResumeDelayMs = AUTO_OPEN_SETTLE_MS
local side = {
    ahVisible = false,
    autoShown = false,
    active = false,
    scanDoneThisOpen = false,
    settleElapsed = 0,
    index = 1,
    waiting = false,
    waitElapsed = 0,
    readElapsed = 0,
    attempts = 0,
    spacingElapsed = 0,
    eventSeen = false,
    successCount = 0,
    cacheHitCount = 0,
    queryErrorCount = 0,
    draining = false,
    drainElapsed = 0,
    drainQuietElapsed = 0,
    skipAfterDrain = false,
    lastDiag = "none",
}

local function PriceFromSearchedCache(watchIndex)
    local item = ITEMS[watchIndex]
    if item == nil then return nil, "no-item" end
    local count, total, page
    local ok = pcall(function()
        count = X2Auction:GetSearchedItemCount()
        total = X2Auction:GetSearchedItemTotalCount()
        page = X2Auction:GetSearchedItemPage()
    end)
    if not ok then return nil, "meta-error" end
    count = tonumber(count) or 0
    total = tonumber(total) or 0
    page = tonumber(page) or 0
    if page ~= 1 then return nil, "unexpected-page=" .. tostring(page) end
    if count <= 0 then return nil, "rows=0 total=" .. tostring(total) .. " page=" .. tostring(page) end

    local best, bestInfo = nil, nil
    local tables = 0
    for idx = 1, math.min(count, MAX_LISTINGS) do
        local info = nil
        local okInfo = pcall(function() info = X2Auction:GetSearchedItemInfo(idx) end)
        if okInfo and type(info) == "table" then
            tables = tables + 1
            local listing = ExtractListing(info)
            if listing ~= nil and CATALOG.Matches(item, listing.name, rawget(info, "itemType")) and tonumber(listing.unit) ~= nil and listing.unit > 0 then
                if best == nil or listing.unit < best then best, bestInfo = listing.unit, info end
            end
        end
    end
    if tables < math.min(count, MAX_LISTINGS) then return nil, "incomplete-rows" end
    if best ~= nil then return best, "rows=" .. tostring(count) .. " tables=" .. tostring(tables), bestInfo end
    return nil, "rows=" .. tostring(count) .. " tables=" .. tostring(tables)
end

local function ResetScanWait()
    side.waiting = false
    side.waitElapsed = 0
    side.readElapsed = 0
    side.attempts = 0
    side.eventSeen = false
end

local function StopSideScan()
    scanCompleted, scanCompletionPending = false, false
    RefreshLastUpdate()
    market:Cancel()
    side.skipAfterDrain = false -- A native request cannot be recalled; keep any drain guard.
    side.active = false
    ResetScanWait()
end

local function FinishNativeParityScan()
    if DEBUG then Chat("scan: " .. tostring(side.lastDiag) .. " | cache=" .. tostring(side.cacheHitCount) .. " | qerr=" .. tostring(side.queryErrorCount)) end
    side.active = false
    side.scanDoneThisOpen = true
    ResetScanWait()
    scanCompletionPending = #ITEMS > 0 and side.successCount == #ITEMS
    scanCompleted = scanCompletionPending and not market:Busy()
    scanCompletionPending = scanCompletionPending and not scanCompleted
    RefreshLastUpdate()
    if side.successCount > 0 then
        SetStatus(string.format(T("nativeDone"), side.successCount, #ITEMS))
    else
        SetStatus(T("nativeFailed"))
    end
end

local function AdvanceNativeParityScan(success, source)
    if success then
        side.successCount = side.successCount + 1
        if source == "cache" then side.cacheHitCount = side.cacheHitCount + 1 end
    end
    side.index = side.index + 1
    ResetScanWait()
    side.spacingElapsed = 0
    if side.index > #ITEMS then FinishNativeParityScan() end
end

-- Missing/rejected completion: drain old events before advancing, with a finite cap.
local function DrainFailedNativeQuery()
    market:Cancel()
    capture.pending = false
    ResetScanWait()
    side.draining, side.skipAfterDrain = true, true
    side.drainElapsed, side.drainQuietElapsed = 0, 0
end

local function IssueNativeParityQuery()
    if settingsOpen or side.draining or not side.active or side.waiting or capture.pending or not market:CanSearch() or not AuctionVisible() then return end
    local item = ITEMS[side.index]
    if item == nil then FinishNativeParityScan(); return end

    local queryName = CATALOG.QueryName(item, SearchLanguage())
    SetStatus(string.format(T("nativeScan"), item.name))
    -- Arm before the call so a synchronous completion cannot be discarded.
    ResetScanWait()
    side.waiting = true
    market:MarkSearch()
    local ok, result = pcall(function()
        return X2Auction:SearchAuctionArticle(1, 0, 0, 1, 0, false, queryName, "0", "0")
    end)
    if not ok or result == false then
        side.queryErrorCount = side.queryErrorCount + 1
        side.lastDiag = ok and "query-rejected" or "query-error"
        DrainFailedNativeQuery()
    end
end

local function StartNativeParityScan()
    if settingsOpen or side.draining or state.auto ~= true or not AuctionVisible() or #ITEMS <= 0 then return end
    if not market:BeginPass() then return end
    scanCompleted, scanCompletionPending = false, false
    RefreshLastUpdate()
    capture.pending = false
    side.active = true
    side.scanDoneThisOpen = false
    side.index = 1
    side.successCount = 0
    side.cacheHitCount = 0
    side.queryErrorCount = 0
    side.lastDiag = "none"
    side.spacingElapsed = SEARCH_QUERY_SPACING_MS
    ResetScanWait()
    SetStatus(T("nativeWaiting"))
end

local function TryNativeParityRead()
    if not side.active or not side.waiting or not AuctionVisible() then return end
    -- Timeout applies while waiting for the event too; do not read stale rows.
    if side.waitElapsed >= SEARCH_QUERY_TIMEOUT_MS then
        side.lastDiag = side.eventSeen and "result-timeout" or "no-completion-event"
        if side.eventSeen then AdvanceNativeParityScan(false, "result-timeout") else DrainFailedNativeQuery() end
        return
    end
    if not side.eventSeen then return end
    local delay = side.attempts == 0 and RESULT_READ_DELAY_MS or PASSIVE_RETRY_MS
    if side.readElapsed < delay then return end
    side.readElapsed = 0
    side.attempts = side.attempts + 1

    local price, diag, info = PriceFromSearchedCache(side.index)
    if tonumber(price) ~= nil and price > 0 then
        local candidate=ObserveMarket(side.index,info,price)
        RecordPrice(side.index, price)
        market:Offer(candidate)
        AdvanceNativeParityScan(true, "cache")
    elseif side.attempts >= MAX_READ_ATTEMPTS then
        side.lastDiag = diag
        -- Completion was received; no usable row after bounded cache reads.
        AdvanceNativeParityScan(false, "unavailable")
    end
end

local function HandleAuctionItemSearched(source, ...)
    if not AuctionVisible() then return end
    if side.draining then side.drainQuietElapsed = 0; return end
    if market:Busy() then market:Cancel() end
    if side.active then
        if side.waiting and not side.eventSeen then
            side.eventSeen = true
            side.readElapsed = 0
        end
        return -- Ignore duplicate/late events in the gap between requests.
    end
    -- Coalesce duplicate deliveries while allowing later searches in the same
    -- second. No assumption is made about the event's argument layout.
    if state.auto == true then StartCapture("AUTO") else SetStatus(T("statusChanged")) end
end

-- Register a dedicated sink first. The UIParent hook is retained as a fallback
-- because it is the receiver proven to fire on this live client in earlier tests.
local eventSink = CreateEmptyWindow("ahPriceWatchAuctionEventSink", "UIParent")
eventSink:SetExtent(1, 1)
eventSink:AddAnchor("TOPLEFT", "UIParent", -20, -20)
eventSink:Show(true)
local sinkRegistered = pcall(function()
    eventSink:SetEventHandler(UIEVENT_TYPE.AUCTION_ITEM_SEARCHED, function(...) HandleAuctionItemSearched("sink", ...) end)
end)
local rootRegistered = pcall(function()
    UIParent:SetEventHandler(UIEVENT_TYPE.AUCTION_ITEM_SEARCHED, function(...) HandleAuctionItemSearched("root", ...) end)
end)
if not sinkRegistered and not rootRegistered then
    Chat(string.format(T("eventFailed"), "no receiver accepted AUCTION_ITEM_SEARCHED"))
end

-- Buttons --------------------------------------------------------------------
local controlsBackground = window:CreateColorDrawable(0.08, 0.10, 0.14, 0.9, "background")
controlsBackground:AddAnchor("TOPLEFT", window, 8, bottomY - 6)
controlsBackground:AddAnchor("BOTTOMRIGHT", window, -8, -34 - (DEBUG and 20 or 0))
local autoButton = window:CreateChildWidget("button", "ahPriceWatchAutoButton", 0, true)
autoButton:SetStyle("text_default")
local AUTO_BUTTON_WIDTH = 240
autoButton:SetExtent(AUTO_BUTTON_WIDTH, 24)
autoButton:AddAnchor("TOPLEFT", window, 12, bottomY)

local languageButton = window:CreateChildWidget("button", "ahPriceWatchLanguageButton", 0, true)
languageButton:SetStyle("text_default")
languageButton:SetExtent(145, 24)
languageButton:AddAnchor("TOPLEFT", window, 12 + AUTO_BUTTON_WIDTH + 12, bottomY)

local settingsButton = window:CreateChildWidget("button", "ahPriceWatchSettingsButton", 0, true)
settingsButton:SetStyle("text_default")
settingsButton:SetExtent(120, 24)
settingsButton:AddAnchor("TOPLEFT", window, 12 + AUTO_BUTTON_WIDTH + 12 + 145 + 12, bottomY)
local pager, previousPage, pageLabel, nextPage = UI.Pager(window, "ahPriceWatchPager",
    "ahPriceWatchPreviousPage", "ahPriceWatchPage", "ahPriceWatchNextPage")
pager:AddAnchor("BOTTOMRIGHT", window, "BOTTOMRIGHT", -24, -34 - (DEBUG and 20 or 0))
UI.Inside(PANEL_WIDTH - 24 - UI.PAGER_WIDTH, UI.PAGER_WIDTH, PANEL_WIDTH, 12)

local function RefreshPage()
    local pages = math.max(1, math.ceil(#ITEMS / PAGE_SIZE))
    tablePage = math.max(1, math.min(tablePage, pages))
    pageLabel:SetText(tostring(tablePage) .. " / " .. tostring(pages))
    pager:Show(pages > 1)
    previousPage:Show(pages > 1)
    pageLabel:Show(pages > 1)
    nextPage:Show(pages > 1)
    RefreshAllRows()
end
previousPage:SetHandler("OnClick", function() tablePage = tablePage - 1; RefreshPage() end)
nextPage:SetHandler("OnClick", function() tablePage = tablePage + 1; RefreshPage() end)

-- Re-arm the existing scheduler/StartNativeParityScan path; never query here.
local function ArmNativeParityScan(delay)
    StopSideScan()
    side.index = 1
    side.spacingElapsed = 0
    side.settleElapsed = 0
    settingsResumeDelayMs = delay or AUTO_OPEN_SETTLE_MS
    side.scanDoneThisOpen = settingsOpen or state.auto ~= true or not AuctionVisible()
end

local function SetSettingsOpen(open)
    if settingsOpen == open then return end
    if open then
        -- A sent request cannot be recalled. On resume, allow its entire
        -- timeout plus the normal settle delay to elapse before issuing again.
        settingsResumeDelayMs = side.waiting and (SEARCH_QUERY_TIMEOUT_MS + AUTO_OPEN_SETTLE_MS) or AUTO_OPEN_SETTLE_MS
    end
    settingsOpen = open
    ArmNativeParityScan(settingsResumeDelayMs)
end

local settingsPanel
local function HideSettings()
    if settingsPanel then settingsPanel.Hide() end
end
settingsButton:SetHandler("OnClick", function()
    -- Construct optional UI lazily: failure cannot prevent the proven search
    -- engine/event receivers from starting. Never guess a replacement API.
    local ok, err = pcall(function()
        if not settingsPanel then
            settingsPanel = AH_PRICE_WATCH_CREATE_SETTINGS(window, {
                text = T, money = MoneyText,
                language = function() return state.language end,
                searchLanguage = function() return SearchLanguage(), clientSearchLanguage ~= nil end,
                visibility = SetSettingsOpen,
                items = function() return ITEMS end,
                canonicalName = function(name)
                    -- Reuse exact English spelling for known/previously removed
                    -- items, preserving their name-keyed history on re-addition.
                    for _, item in ipairs(ITEMS) do
                        if string.lower(item.name) == string.lower(name) then return item.name end
                    end
                    for oldName in pairs(state.daily) do
                        if string.lower(oldName) == string.lower(name) then return oldName end
                    end
                    for oldName in pairs(state.last) do
                        if string.lower(oldName) == string.lower(name) then return oldName end
                    end
                    for oldName in pairs(state.alerts) do
                        if string.lower(oldName) == string.lower(name) then return oldName end
                    end
                    for _, item in ipairs(CONFIG.items or {}) do
                        if string.lower(item.name) == string.lower(name) then return item.name end
                    end
                    return name
                end,
                save = function(draft, searchLanguage)
                    if side.active or capture.pending then return false, "settingsBusy" end
                    local valid, reason = FEATURES.ValidateItems(draft)
                    if not valid then return false, reason end
                    if not clientSearchLanguage then
                        state.searchLanguage = searchLanguage == "KO" and "KO" or "EN"
                    end
                    state.watchItems = FEATURES.CopyItems(draft)
                    ITEMS = FEATURES.CopyItems(state.watchItems)
                    CATALOG.Hydrate(ITEMS)
                    state.watchItems = FEATURES.CopyItems(ITEMS)
                    -- No request is made here. Closing settings schedules a
                    -- delayed scan only when AUTO and the native AH are open.
                    side.scanDoneThisOpen = true
                    if not SaveState() then return false, storage.root and "storageFailed" or "storageInitialFailed" end
                    RefreshPage()
                    SetStatus(T("settingsSaved"))
                    return true
                end,
            })
        end
        settingsPanel.Open()
    end)
    if not ok then
        SetStatus(T("settingsUnavailable"))
        if DEBUG then Chat(tostring(err)) end
    end
end)

local hint = window:CreateChildWidget("label", "ahPriceWatchHint", 0, false)
hint:SetExtent(PANEL_WIDTH - 280, 18)
hint:AddAnchor("TOPRIGHT", window, -12, bottomY + 34)
hint.style:SetFontSize(11)
hint.style:SetAlign(ALIGN_RIGHT)
hint.style:SetColor(150, 150, 150, 255)

local function RefreshAutoButton()
    autoButton:SetText(state.auto == true and T("autoOn") or T("autoOff"))
end

local function SetIdleStatus()
    if state.auto == true then
        SetStatus(T("statusAuto"))
    else
        SetStatus(T("statusOpenCheck"))
    end
end

local function ApplyLanguage()
    title:SetText(T("title") .. " v" .. VERSION)
    for i, h in ipairs(headers) do
        if headerLabels[i] ~= nil then headerLabels[i]:SetText(T(h.key)) end
    end
    languageButton:SetText(T("lang"))
    settingsButton:SetText(T("settings"))
    if settingsPanel then settingsPanel.RefreshLanguage() end
    hint:SetText(T("hint"))
    RefreshAutoButton()
    RefreshPage()
    SetIdleStatus()
end

autoButton:SetHandler("OnClick", function()
    capture.pending = false
    state.auto = not (state.auto == true)
    SaveState()
    RefreshAutoButton()
    ArmNativeParityScan(AUTO_OPEN_SETTLE_MS)
    if state.auto then
        SetStatus(T("statusAuto"))
    else
        SetStatus(T("statusAutoOff"))
    end
end)

languageButton:SetHandler("OnClick", function()
    if state.language == "JA" then
        state.language = "KO"
    elseif state.language == "KO" then
        state.language = "EN"
    else
        state.language = "JA"
    end
    SaveState()
    ApplyLanguage()
end)

closeButton:SetHandler("OnClick", function()
    HideSettings()
    capture.pending = false
    StopSideScan()
    side.scanDoneThisOpen = true
    -- Keep the native ESC content manager and our widget in the same state.
    -- Direct window:Show(false) alone can leave the native content entry marked
    -- as open, causing the next ESC-menu click to request a close again.
    pcall(function() ADDON:ShowContent(ESC_CONTENT_ID, false) end)
    state.tableVisible = false
    side.autoShown = false
    window:Show(false)
    SaveState()
end)

-- ESC menu integration --------------------------------------------------------
-- ArcheRage 9.5+ officially exposes AddEscMenuButton together with
-- RegisterContentWidget / RegisterContentTriggerFunc for addon content.
-- Category 3 corresponds to the third ESC-menu column shown by the current
-- client: Shop/Quality of Life. Content id is configurable to avoid collisions.
local escMenuRegistered = false

local function OnEscMenuContent(show)
    -- Official ShowContent normally supplies a boolean. Treat anything except
    -- explicit false as an open request so older client callback variants that
    -- omit the argument still open the table instead of silently hiding it.
    local visible = (show ~= false)
    if not visible then
        HideSettings()
        capture.pending = false
        StopSideScan()
        side.scanDoneThisOpen = true
    end
    state.tableVisible = visible
    window:Show(visible)
    RestoreStartupPosition()
    SaveState()
end

local function RegisterEscMenuIntegration()
    local ok, err = pcall(function()
        -- Register this price-table window as addon content, then let the native
        -- ESC menu show/hide it through the content trigger.
        ADDON:RegisterContentWidget(ESC_CONTENT_ID, window)
        ADDON:RegisterContentTriggerFunc(ESC_CONTENT_ID, OnEscMenuContent)
        -- Start with both native content state and widget state closed.
        -- Keep the content close integration; there is no Menu launch entry.
        ADDON:ShowContent(ESC_CONTENT_ID, false)
    end)
    escMenuRegistered = ok
    if ok then
        if DEBUG then Chat("ESC menu registered") end
    else
        Chat(string.format(T("escMenuFail"), tostring(err)))
    end
end

RegisterEscMenuIntegration()

-- Drag -----------------------------------------------------------------------
function window:OnDragStart()
    self:StartMoving()
end
titleBar:SetHandler("OnDragStart", function() window:OnDragStart() end)
title:SetHandler("OnDragStart", function() window:OnDragStart() end)

function window:OnDragStop()
    self:StopMovingOrSizing()
    local x, y = self:GetOffset()
    x, y = UI.ClampMainPosition(mainGeometry, x, y)
    self:RemoveAllAnchors()
    self:AddAnchor("TOPLEFT", "UIParent", x, y)
    state.position = { x = x, y = y }
    SaveState()
end
titleBar:SetHandler("OnDragStop", function() window:OnDragStop() end)
title:SetHandler("OnDragStop", function() window:OnDragStop() end)

-- Scheduler ------------------------------------------------------------------
local scheduler = CreateEmptyWindow("ahPriceWatchScheduler", "UIParent")
scheduler:SetExtent(1, 1)
scheduler:AddAnchor("TOPLEFT", "UIParent", -50, -50)
scheduler:Show(true)

function scheduler:OnUpdate(dt)
    local delta = tonumber(dt) or 0
    local visible = AuctionVisible()
    market:Tick(delta,visible and state.auto==true and not settingsOpen)
    if not visible then capture.pending = false end

    if capture.pending then
        capture.elapsed = capture.elapsed + delta
        if capture.elapsed >= capture.delay then
            capture.elapsed = 0
            TryCapture()
        end
    end

    if visible and not side.ahVisible then
        side.ahVisible = true
        settingsResumeDelayMs = AUTO_OPEN_SETTLE_MS
        side.scanDoneThisOpen = false
        side.settleElapsed = 0
        side.autoShown = not (state.tableVisible == true)
        StopSideScan()
        window:Show(true)
        RestoreStartupPosition()
        RefreshAllRows()
        if state.auto == true then SetStatus(T("nativeWaiting")) else SetStatus(T("statusAutoOff")) end
    elseif not visible and side.ahVisible then
        HideSettings()
        side.ahVisible = false
        side.scanDoneThisOpen = false
        StopSideScan()
        if side.autoShown and state.tableVisible ~= true then window:Show(false) end
        side.autoShown = false
        SetIdleStatus()
    end

    if side.draining then
        side.drainElapsed = side.drainElapsed + delta
        side.drainQuietElapsed = side.drainQuietElapsed + delta
        local cap = SEARCH_QUERY_TIMEOUT_MS + SEARCH_QUERY_SPACING_MS
        if side.drainElapsed >= cap or (side.drainElapsed >= SEARCH_QUERY_TIMEOUT_MS and side.drainQuietElapsed >= SEARCH_QUERY_SPACING_MS) then
            side.draining = false
            if side.active and side.skipAfterDrain then AdvanceNativeParityScan(false, "completion-timeout") end
            side.skipAfterDrain = false
        end
        return -- Never issue the next query on the drain-completion update.
    end
    if not visible or settingsOpen then return end
    if scanCompletionPending and not side.active and not market:Busy() and state.auto == true then
        scanCompletionPending, scanCompleted = false, true
        RefreshLastUpdate()
    end

    if state.auto == true and not side.active and not side.scanDoneThisOpen then
        side.settleElapsed = side.settleElapsed + delta
        if side.settleElapsed >= settingsResumeDelayMs then
            settingsResumeDelayMs = AUTO_OPEN_SETTLE_MS
            side.settleElapsed = 0
            StartNativeParityScan()
        end
    end

    if side.active then
        if not side.waiting then
            side.spacingElapsed = side.spacingElapsed + delta
            if side.spacingElapsed >= SEARCH_QUERY_SPACING_MS then
                side.spacingElapsed = 0
                IssueNativeParityQuery()
            end
        else
            side.waitElapsed = side.waitElapsed + delta
            if side.eventSeen then side.readElapsed = side.readElapsed + delta end
            TryNativeParityRead()
        end
    end
end
scheduler:SetHandler("OnUpdate", scheduler.OnUpdate)

ApplyLanguage()
state.tableVisible = false
window:Show(false)
SaveState()
if DEBUG then Chat("v" .. VERSION .. " ready") end
