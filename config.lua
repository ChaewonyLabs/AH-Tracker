-- ArcheRage AH Price Watch v1.1.2
--
-- AUTO scans once while the player has native AH open, then captures manual
-- searches. Uses enabled SearchAuctionArticle (9 arguments, all-grade filter 1).
-- Scan prices are read through GetSearchedItem* only after a completion event.
-- Stops the scan on an error, missing completion, or unreadable result.
-- Never opens native AH or performs buy/bid/list/cancel/input simulation.
--
-- UI language affects everything except watched item names.
-- Supported: "JA", "KO", "EN".
-- targetGold = 0 disables the manual target for that item.
-- Prices are per ONE item, not per stack.

AH_PRICE_WATCH_CONFIG = {
    defaultLanguage = "EN",
    DEBUG = false,
    DEV_MARKET_PROBE = false,
    alertCooldownSeconds = 1800,

    -- ESC menu integration: Shop/Quality of Life.
    escMenuCategoryId = 3,
    escMenuContentId = 1100,

    resultReadDelayMs = 250,
    passiveRetryMs = 250,
    maxResultReadAttempts = 10,
    maxListingsPerPage = 50,

    -- Live refresh starts only when the PLAYER opens normal Auction House.
    sidecarOpenSettleMs = 1250,

    -- SearchAuctionArticle has a 1 second server cooldown.
    searchQuerySpacingMs = 1250,
    searchQueryTimeoutMs = 4200,

    -- Repeated capture of the same price within this window updates Now/Time
    -- but does not add another 7d/30d history sample.
    samePriceDedupeSeconds = 900,

    minStatSamples = 8,
    minStatDays = 2,
    min30dStatSamples = 16,
    min30dStatDays = 4,

    buyRatio = 0.92,
    greatBuyRatio = 0.85,
    buyRatio30d = 0.92,
    greatBuyRatio30d = 0.85,

    -- A missing saved Watchlist always starts empty.
    items = {}
}
