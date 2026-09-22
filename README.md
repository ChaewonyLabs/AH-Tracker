# AH Tracker

[English](#english) | [한국어](#한국어)

## English

AH Tracker is a free ArcheRage Auction House watchlist addon by Chaewony Labs.

**⚠️ AH Tracker requires the `globals` addon to be installed. It will not work without it.**

### Features

- Keep a persistent Watchlist and check current prices.
- View 7, 14, and 30 day price statistics, plus Market History and volume information when available.
- Set optional target prices and use Signal for a general indication based on market data.
- Run a full Watchlist AUTO Scan with progress and completion status while the Auction House is open.
- Keep the Watchlist, price history, settings, and window position between sessions.
- Show 8–15 rows per page, depending on screen height.
- Use the UI in English, Japanese, or Korean, with a separate Auction House search-language setting.

### Installation

1. Make sure the `globals` addon is installed.
2. Extract the `ahpricewatch` folder into `Documents\ArcheRage\Addon\`.
3. Launch ArcheRage and open the Auction House.

### Basic Usage

1. Open the Auction House, then open `Settings` in AH Tracker.
2. Choose an item from the suggestions and select `Add Item` to add it to the Watchlist.
3. To set an optional target, select a Watchlist item and enter the amount in Gold, Silver, and Copper. Select `Apply`, then `Save settings`. A value of 0 means no target is set.
4. Current price, market statistics, and Signal work normally without a target. Signal is a general indication based on available market data, so you do not need to set a target for every item.
5. Turn `Update on AH Open` ON to update the full Watchlist automatically when you open the Auction House. `Scan Complete` appears after a successful full Watchlist scan.

If you want to search the Auction House manually, turn `Update on AH Open` OFF before opening it. This prevents AH Tracker from starting an automatic Watchlist update during your manual search.

### Market Data

AH Tracker records current price observations and available Market History data. The table can show 7, 14, and 30 day statistics and available volume information. A dash means the corresponding data is not yet available.

### Updating

Fully close ArcheRage, then replace the existing `ahpricewatch` folder with the complete folder from the new version. Saved Watchlist, history, and settings data is stored separately and remains available after a normal update.

### Notes

- AH Tracker does not buy, bid, list, or cancel Auction House transactions.

### Support

AH Tracker is free. Donations do not unlock any functionality.

[Support Chaewony Labs on Ko-fi](https://ko-fi.com/chaewonylabs)

### License

Copyright © 2026 Chaewony Labs. All rights reserved. AH Tracker is proprietary software and is not open source. See [LICENSE](LICENSE) for permitted use and restrictions.

## 한국어

AH Tracker는 Chaewony Labs에서 만든 무료 ArcheRage 경매장 Watchlist 애드온입니다.

**⚠️ AH Tracker를 사용하려면 `globals` 애드온이 설치되어 있어야 합니다. `globals`가 없으면 작동하지 않습니다.**

### 주요 기능

- Watchlist를 저장하고 아이템의 현재 가격을 확인합니다.
- 7일, 14일, 30일 가격 통계와 이용 가능한 Market History 및 거래량 정보를 표시합니다.
- 필요할 때만 목표 가격을 설정하고, 시장 데이터를 바탕으로 한 대략적인 판단을 Signal에서 확인합니다.
- 경매장이 열려 있는 동안 진행 상황과 완료 상태를 보여 주는 전체 Watchlist AUTO Scan을 실행합니다.
- Watchlist, 가격 기록, 설정, 창 위치를 다음 접속 때도 유지합니다.
- 화면 높이에 따라 페이지당 8~15개 행을 표시합니다.
- UI 언어는 영어, 일본어, 한국어를 지원하며 경매장 검색 언어는 별도로 설정할 수 있습니다.

### 설치

1. `globals` 애드온이 설치되어 있는지 확인합니다.
2. `ahpricewatch` 폴더를 `Documents\ArcheRage\Addon\`에 압축 해제합니다.
3. ArcheRage를 실행하고 경매장을 엽니다.

### 기본 사용법

1. 경매장을 연 다음 AH Tracker에서 `Settings`를 엽니다.
2. 추천 목록에서 아이템을 고르고 `Add Item`을 눌러 Watchlist에 추가합니다.
3. 선택 사항인 목표 금액을 지정하려면 Watchlist에서 아이템을 선택하고 Gold, Silver, Copper 값을 입력합니다. `Apply`를 누른 뒤 `Save settings`를 누릅니다. 값이 0이면 목표가 설정되지 않은 상태입니다.
4. 값을 지정하지 않아도 현재 가격, 시장 통계, Signal은 정상적으로 작동합니다. Signal은 이용 가능한 시장 데이터를 바탕으로 한 대략적인 판단이므로 모든 아이템에 목표를 설정할 필요는 없습니다.
5. 경매장을 열 때 전체 Watchlist를 자동으로 갱신하려면 `Update on AH Open`을 ON으로 설정합니다. 전체 Watchlist 스캔이 성공하면 `Scan Complete`가 표시됩니다.

경매장에서 직접 검색하려면 열기 전에 `Update on AH Open`을 OFF로 설정하는 것을 권장합니다. 수동 검색 중 AH Tracker가 Watchlist 자동 갱신을 시작하지 않도록 할 수 있습니다.

### 시장 데이터

AH Tracker는 현재 가격 관측값과 이용 가능한 Market History 데이터를 기록합니다. 표에는 7일, 14일, 30일 통계와 제공되는 거래량 정보가 표시됩니다. 대시(—)는 해당 데이터가 아직 없다는 뜻입니다.

### 업데이트

ArcheRage를 완전히 종료한 뒤 기존 `ahpricewatch` 폴더를 새 버전의 전체 폴더로 교체합니다. 저장된 Watchlist, 가격 기록, 설정 데이터는 별도 위치에 보관되므로 일반적인 업데이트 후에도 유지됩니다.

### 참고

- AH Tracker는 경매장 아이템을 자동으로 구매, 입찰, 등록 또는 취소하지 않습니다.

### 후원

AH Tracker는 무료이며 후원 여부에 따라 추가 기능이 해금되지 않습니다.

[Ko-fi에서 Chaewony Labs 후원하기](https://ko-fi.com/chaewonylabs)

### 라이선스

Copyright © 2026 Chaewony Labs. All rights reserved. AH Tracker는 Proprietary 소프트웨어이며 오픈 소스가 아닙니다. 허용되는 사용 범위와 제한 사항은 [LICENSE](LICENSE)를 확인하세요.
