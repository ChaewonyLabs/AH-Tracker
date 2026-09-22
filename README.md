# AH Tracker

[English](#ah-tracker) | [한국어](#한국어)

AH Tracker is a free ArcheRage Auction House watchlist addon by Chaewony Labs.

**⚠️ AH Tracker requires the `globals` addon to be installed. It will not work without it.**

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

AH Tracker is fully functional and free. Donations do not unlock any additional functionality.

If you would like to support continued development:

[Support Chaewony Labs on Ko-fi](https://ko-fi.com/chaewonylabs)

## License

Copyright © 2026 Chaewony Labs. All rights reserved. See [LICENSE](LICENSE).

---

# 한국어

AH Tracker는 Chaewony Labs에서 제작한 무료 ArcheRage 경매장 관심 아이템 추적 애드온입니다.

**⚠️ AH Tracker를 사용하려면 `globals` 애드온이 설치되어 있어야 합니다. `globals`가 없으면 작동하지 않습니다.**

## 주요 기능

- 관심 아이템의 현재 가격을 추적하고 목록을 저장합니다.
- 7일 / 14일 / 30일 가격 통계와 사용 가능한 Market History 데이터를 확인할 수 있습니다.
- 아이템별 목표 가격을 설정하고 가격 알림을 받을 수 있습니다.
- 경매장이 열려 있는 동안 전체 관심 목록을 AUTO Scan으로 확인할 수 있으며, 진행 상태와 완료 여부가 표시됩니다.
- 관심 목록, 시세/히스토리 데이터, 설정, 창 위치를 세션 간에 유지합니다.
- 화면 높이에 따라 페이지당 8~15개의 항목을 표시합니다.
- 영어 / 일본어 / 한국어 UI를 지원하며, 경매장 검색 언어를 별도로 설정할 수 있습니다.

## 설치 방법

1. ArcheRage를 완전히 종료합니다.
2. AH Tracker를 다운로드하고 압축을 풉니다.
3. `ahpricewatch` 폴더를 다음 위치에 넣습니다.

   `Documents\ArcheRage\Addon\`

4. 최종 경로가 다음과 같은지 확인합니다.

   `Documents\ArcheRage\Addon\ahpricewatch\toc.g`

5. 서로 다른 AH Tracker 버전의 파일을 섞어서 사용하지 마세요.

## 기본 사용 방법

1. AH Tracker를 사용하려면 경매장을 엽니다. **Update on AH Open**을 켜면 경매장이 열려 있는 동안 전체 관심 목록을 자동으로 스캔합니다.
2. **Settings**를 열고 아이템 검색 결과에서 원하는 아이템을 선택한 뒤 **Add Item**을 눌러 관심 목록에 추가합니다.
3. 관심 목록에 추가된 아이템을 선택한 뒤 Gold, Silver, Copper 단위로 목표 가격을 설정합니다. **Apply**를 누른 후 **Save settings**를 누릅니다. 기존 관심 아이템이 선택되지 않은 상태에서는 가격 입력칸과 **Apply** 버튼이 비활성화됩니다. 목표 가격을 0으로 설정하면 해당 아이템의 목표 가격 알림이 비활성화됩니다.
4. 메인 창에서 현재 가격, 통계, Signal, 스캔 상태를 확인할 수 있습니다. 모든 관심 아이템의 업데이트와 대기 중인 Market 요청이 완료되면 **Scan complete**가 표시됩니다.

## Market Data

AH Tracker는 관심 아이템의 현재 가격 관측값과 사용 가능한 Market History 데이터를 기록합니다.

표에는 7일 / 14일 / 30일 평균 및 최고 가격과 사용 가능한 거래량 정보가 표시됩니다.

`-` 표시는 해당 데이터가 아직 존재하지 않는다는 의미입니다.

통계와 알림은 각 아이템에 수집된 데이터를 기반으로 하며, 목표 가격은 별도로 설정할 수 있습니다.

## 업데이트

애드온 파일을 교체하기 전에 ArcheRage를 완전히 종료하세요.

`ahpricewatch` 애드온 폴더는 항상 하나의 완전한 버전으로 교체하고 서로 다른 버전의 파일을 섞지 마세요.

AH Tracker의 저장 데이터는 애드온 설치 폴더와 별도로 저장되므로 일반적인 업데이트에서는 UDF 데이터를 수동으로 삭제할 필요가 없습니다.

## 참고 사항

- AH Tracker는 경매장에서 구매, 입찰, 판매 등록 또는 판매 취소를 자동으로 수행하지 않습니다.
- AH Tracker의 모든 기능은 무료로 사용할 수 있습니다. 후원 여부에 따라 기능이 해금되지 않습니다.
- 이 저장소는 Proprietary 소프트웨어이며 오픈 소스가 아닙니다. 허용되는 사용 범위와 제한 사항은 [LICENSE](LICENSE)를 확인하세요.

## 후원

AH Tracker의 모든 기능은 무료로 사용할 수 있으며, 후원 여부에 따라 추가 기능이 해금되지 않습니다.

개발을 후원하고 싶다면:

[Ko-fi에서 Chaewony Labs 후원하기](https://ko-fi.com/chaewonylabs)

## 라이선스

Copyright © 2026 Chaewony Labs. All rights reserved.

자세한 내용은 [LICENSE](LICENSE)를 확인하세요.
