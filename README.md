# AH Tracker

AH Tracker is a free ArcheRage Auction House watchlist addon by Chaewony Labs.

## Features

- Track current prices for items on a persistent Auction House Watchlist.
- View 7, 14, and 30 day price statistics and Market History data when available.
- Set per-item target prices and receive price alerts.
- Run a full Watchlist AUTO Scan while the Auction House is open, with scan progress and a completion indication after every item updates successfully.
- Keep Watchlist items, market/history data, settings, and the window position between sessions.
- Show 8–15 rows per page according to available screen height.
- Use the UI in English, Japanese, or Korean, with a separate Auction House search language setting.

## Installation

1. Fully close ArcheRage.
2. Download and extract AH Tracker.
3. Place the `ahpricewatch` folder under `Documents\ArcheRage\Addon\`.
4. Confirm the resulting path is `Documents\ArcheRage\Addon\ahpricewatch\toc.g`.
5. Keep files from a single AH Tracker version together. Do not mix versions.

## Basic Usage

1. Open the Auction House to use AH Tracker. Turn on **Update on AH Open** to scan the full Watchlist automatically while the Auction House is open.
2. Open **Settings**, choose an item suggestion, and click **Add Item** to put it on the Watchlist.
3. Select that existing Watchlist row to set a target price in Gold, Silver, and Copper. Click **Apply**, then **Save settings**. The price fields and **Apply** are disabled when no existing item is selected. A zero target disables that item's target alert.
4. Check the current price, statistics, signal, and scan status in the tracker window. **Scan complete** appears after all Watchlist items update successfully and pending Market requests finish.

## Market Data

AH Tracker records current price observations and available Market History data for watched items. The table shows 7, 14, and 30 day averages and highs, plus available volume information. A dash means the corresponding data is not available yet. Statistics and alerts depend on the data collected for each item; a target price can be set independently.

## Updating

Fully close ArcheRage before replacing the `ahpricewatch` addon folder or its files. Use one complete version of the addon. AH Tracker persistence is stored separately from the addon installation folder, so a normal addon update does not require manually deleting UDF data.

## Notes

- AH Tracker does not automatically buy, bid, list, or cancel Auction House transactions.
- The addon is fully functional and free. Donations do not unlock any functionality.
- This repository is proprietary and is not open source. See [LICENSE](LICENSE) for permitted use and restrictions.

## Support

Optional support links are available through the Chaewony Labs GitHub profile.

## License

Copyright © 2026 Chaewony Labs. All rights reserved. See [LICENSE](LICENSE).
