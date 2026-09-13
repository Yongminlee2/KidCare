# iOS 3단계 구현 계획 — 지도 탭 전체

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 아이폰 지도 화면을 안드로이드와 같게 만든다 — 하루 경로선, 타임라인, 날짜 이동, '지금 위치 확인', 실시간 보기.

**Architecture:** 2단계에서 옮겨둔 `Logic/` 여덟 개가 여기서 처음 화면에 붙는다. Firestore 읽기는 `Core/`, 화면은 `Guardian/`. 한 화면이 1,343줄짜리 코틀린 Fragment 하나에 들어 있지만, Swift 쪽은 **뷰 하나에 몰지 않고 역할별로 쪼갠다** — 지도 오버레이, 상태 카드, 타임라인 패널, 명령 왕복이 각각 따로 테스트될 수 있어야 한다.

**Tech Stack:** Swift 6 / SwiftUI / 네이버 지도 iOS SDK 3.23.3 / Firebase Firestore. 새 의존성 없음.

**Spec:** `docs/superpowers/specs/2026-09-12-kidcare-ios-design.md` (§4 화면 대응표, §9 3단계)

## Global Constraints

- **정본은 안드로이드 `guardian/MapTimelineFragment.kt`(1,343줄)와 `fragment_map_timeline.xml`, `TimelineAdapter.kt`, `GradientRouteOverlay.kt` 다.** 열어서 읽고 옮긴다. 이 계획서가 코틀린과 다르면 코틀린이 맞다.
- **각 Task 는 화면에 보이는 것을 하나씩 늘린다.** Task 가 끝나면 시뮬레이터에서 눈으로 확인할 수 있어야 한다 — 이 단계는 "밤새 돌렸는데 화면이 그대로"가 되면 안 된다.
- **`ios/KidCare/Logic/` 은 Foundation 만 import 한다.** 화면 코드를 거기 두지 않는다.
- **화면 문구를 하드코딩하지 않는다.** 안드로이드에 이미 있는 키를 **먼저 찾아 쓰고**, 없을 때만 `i18n/ko.json`·`en.json` 양쪽에 새 키를 더한다. `%@` 를 `i18n` 에 쓰지 않는다 — 공유 파일이라 `%s` 로 적고 iOS 카탈로그에서만 `%@` 가 된다(2단계에서 이 지뢰를 한 번 밟았다).
- **Firestore 리스너는 화면이 사라질 때 반드시 건다/뗀다.** 무료 요금제라 리스너 누수가 곧 요금이다.
- **`Fix` 를 Firestore 에서 만들 때 `speed` 를 반드시 싣는다.** 2단계에서 이 필드가 영원히 0 이던 버그를 고쳤고, 그 수정이 의미를 가지려면 매핑이 값을 넘겨야 한다.
- **안드로이드 `app/` 아래를 수정하지 않는다.** `firestore.rules`·`gradlew` 도 마찬가지.
- Swift 6 strict concurrency. `@unchecked Sendable`·`nonisolated(unsafe)` 금지.
- 주석은 **한국어로 '왜'**. 커밋은 **한국어**, author `Yongminlee2 <dydals5678@gmail.com>`, **도구·AI 흔적 금지**.
- 실행 전 PATH: `export PATH="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:$PATH"`
- iOS 테스트: `cd ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'` (현재 128개, known issues 12)
- 안드로이드 테스트(참고용, 읽기 전용): `sh gradlew :app:testDebugUnitTest -x processDebugGoogleServices` — `sh gradlew`, `./gradlew` 아님.

## 이 단계에서 다루지 않는 것

- 관리·예약·장소·알림 탭. 4~6단계다. **탭 바 자체도 4단계에서 만든다** — 지금은 지도 화면 하나가 전부다.
- 아이 선택기(여러 자녀 중 고르기). 6단계다. 지금은 `RoleStore.childUid` 하나를 쓴다.
- 다국어 14벌. 6단계가 `i18n` 에서 생성한다. 이 단계는 키를 **추가만** 한다.

## 검증 방법 — 매 Task 끝에

에뮬레이터에 데이터를 심고 시뮬레이터로 확인한다. 운영 Firebase 에 쓰지 않는다.

```bash
# KidCareApp.init() 을 configureForEmulator(projectId: "kidcare-emulator") 로 잠시 바꾸고
cd ios && xcodebuild -project KidCare.xcodeproj -scheme KidCare \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
xcrun simctl install <udid> <경로>/KidCare.app && xcrun simctl launch <udid> com.kidcare.family
xcrun simctl io <udid> screenshot shot.png
```

**커밋 전에 반드시 `configureForApp()` 으로 되돌린다.**

---

## File Structure

```
ios/KidCare/
├─ Core/
│  ├─ TrailRepository.swift        신규. trails/{dayKey} 읽기
│  ├─ Documents.swift              수정. TrailDoc·TrailPoint·SegmentDoc 추가
│  ├─ CommandRepository.swift      신규. 명령 보내기·한 건 따라가기
│  └─ ErrorText.swift              신규. 예외 → 화면 문구 (안드로이드 ErrorText 짝)
└─ Guardian/
   ├─ MapTabView.swift             지도 탭의 뿌리. 아래 조각들을 앉힌다
   ├─ MapViewModel.swift           @Observable. 구독·로딩·명령 상태를 모두 소유
   ├─ NaverMapView.swift           수정. 경로선·정확도 원 오버레이 추가
   ├─ RouteOverlay.swift           구간별 경로선 만들기 (안드로이드 GradientRouteOverlay 짝)
   ├─ StatusCardView.swift         아이 이름·배터리·마지막 신호·버튼 둘
   ├─ TimelinePanelView.swift      접기·드래그 패널
   └─ TimelineRowView.swift        타임라인 한 줄 (안드로이드 TimelineAdapter 짝)
```

---

### Task 1: 하루 경로선이 지도에 그려진다

**이 Task 가 끝나면 아이폰 지도에 어제·오늘 다닌 길이 선으로 보인다.** 2단계의 `RoutePathRefiner`·`RouteWindows` 가 여기서 처음 쓰인다.

**Files:**
- Modify: `ios/KidCare/Core/Documents.swift` (`TrailDoc`·`TrailPoint`·`SegmentDoc` 추가)
- Create: `ios/KidCare/Core/TrailRepository.swift`
- Create: `ios/KidCare/Guardian/RouteOverlay.swift`
- Modify: `ios/KidCare/Guardian/NaverMapView.swift`
- Modify: `ios/KidCare/Guardian/ChildMapView.swift`
- Test: `ios/KidCareTests/TrailDocumentTests.swift`, `ios/KidCareTests/RouteOverlayTests.swift`

**Interfaces:**
- Consumes: `RoutePathRefiner.refine(points:) -> [Leg]`, `RouteWindows.partition(moves:)`, `Fix`
- Produces:
  - `struct TrailPoint { let lat: Double; let lng: Double; let accuracy: Double; let speed: Double; let at: Int64 }` + `var asFix: Fix`
  - `struct SegmentDoc { let type: String; let startAt: Int64; let endAt: Int64; let lat: Double; let lng: Double; let distanceMeters: Double; let pointCount: Int; let placeName: String }`
  - `struct TrailDoc { let dayKey: String; let points: [TrailPoint]; let segments: [SegmentDoc]; let updatedAt: Int64 }`
  - `TrailRepository.fetch(familyId:childUid:dayKey:) async throws -> TrailDoc?`
  - `RouteOverlay.sections(points:segments:) -> [RouteSection]` where `struct RouteSection { let segmentIndex: Int?; let coordinates: [(lat: Double, lng: Double)] }`

**정본:** `TrailDoc`·`TrailPoint`·`SegmentDoc` 은 `app/.../core/model/Documents.kt:148-189`. 읽기는 `app/.../core/TrailRepository.kt`. 구간 나누기는 `MapTimelineFragment.buildRouteSections`(:1144)와 `drawRoute`(:1055).

- [ ] **Step 1: 문서 모델 테스트를 먼저 쓴다** — 필드 이름이 코틀린과 한 글자도 달라선 안 되고, `speed` 가 실제로 실려야 한다(2단계에서 이 필드가 영원히 0 이던 버그를 고쳤다). `firestoreData` 는 만들지 않는다 — 보호자는 이 문서들을 **읽기만** 한다.
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: `Documents.swift` 에 세 타입을 더하고 `TrailRepository` 를 쓴다** — 안드로이드가 오프라인에서 캐시로 답할 때 던지는 갈래(`TrailRepository.kt:58`)도 옮긴다.
- [ ] **Step 4: 통과 확인**
- [ ] **Step 5: `RouteOverlay` 테스트를 쓴다** — 구간이 없을 때, 이동 구간 하나, 이동 구간 둘 사이에 머무름이 낀 경우. `RouteWindows.partition` 이 만든 창에 점이 배분되는지 못 박는다.
- [ ] **Step 6: `RouteOverlay` 를 구현하고 통과 확인**
- [ ] **Step 7: `NaverMapView` 에 경로선을 그린다** — `NMFPath` 를 쓰고, 지도 뷰는 여전히 `makeUIView` 에서 한 번만 만든다. 선 색은 안드로이드 `GradientRouteOverlay` 와 같은 색 자원을 쓴다.
- [ ] **Step 8: 에뮬레이터에 하루치를 심고 시뮬레이터에서 눈으로 본다** — 점 20~30개짜리 `trails/{dayKey}` 문서를 넣고, 선이 그려지는지 스크린샷으로 확인한다. **선이 안 보이면 이 Task 는 안 끝난 것이다.**
- [ ] **Step 9: 커밋**

---

### Task 2: 상태 카드 — 아이 이름·배터리·마지막 신호

**끝나면 지도 위에 `🔋 78% · 15:42 기준` 같은 카드가 뜬다.**

**Files:**
- Create: `ios/KidCare/Guardian/StatusCardView.swift`
- Create: `ios/KidCare/Core/ErrorText.swift`
- Modify: `ios/KidCare/Core/Documents.swift` (`ChildStatusDoc` 에 `lastSeenServerAt` 은 2단계에서 이미 들어갔다 — 쓰는 쪽을 만든다)
- Test: `ios/KidCareTests/StatusCardTests.swift`, `ios/KidCareTests/ErrorTextTests.swift`

**Interfaces:**
- Consumes: `ChildStatusDoc`, `FamilyRepository.serverNow`
- Produces:
  - `enum LastSignal { case never; case minutes(Int); case hours(Int); case days(Int) }`
  - `StatusCard.lastSignal(status:nowMillis:) -> LastSignal`
  - `func errorMessage(_ error: Error) -> String`

**정본:** `MapTimelineFragment.renderMapStatus`(:770), `showBatteryInfo`(:254), 그리고 **`ChildStatusDoc.lastSignal()`** — 안드로이드가 `GuardianMainActivity` 에 둔 확장 함수다. 코틀린 주석이 "읽는 쪽은 반드시 이 함수 하나만 지나가게 한다"고 못 박았으니 Swift 도 한 자리에 둔다. 오류 문구는 `app/.../core/ErrorText.kt`.

**시각 계산에 `serverNow` 를 쓴다.** 기기 시계로 빼면 부모 폰이 뒤처진 만큼 "마지막 신호 -3분 전" 같은 문구가 나온다(안드로이드 `ControlFragment` 주석).

- [ ] **Step 1: `LastSignal` 과 `errorMessage` 테스트를 쓴다** — 특히 `lastSeenServerAt`(서버 타임스탬프)이 있으면 그것을, 없으면 `lastSeenAt`(아이 폰 시계)으로 물러나는 갈래.
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현하고 통과 확인**
- [ ] **Step 4: `StatusCardView` 를 만들어 지도 위에 얹는다** — 문구 키는 안드로이드 `strings.xml` 에 이미 있는 것을 찾아 쓴다.
- [ ] **Step 5: 시뮬레이터에서 눈으로 확인하고 커밋**

---

### Task 3: 타임라인 목록

**끝나면 지도 아래에 `📍 △△초등학교 08:20~10:10 · 1시간 50분` 목록이 뜬다.** 2단계의 `SegmentSummarizer` 가 여기서 처음 쓰인다.

**Files:**
- Create: `ios/KidCare/Guardian/TimelineRowView.swift`
- Modify: `ios/KidCare/Guardian/ChildMapView.swift`
- Test: `ios/KidCareTests/TimelineRowTests.swift`

**Interfaces:**
- Consumes: `SegmentDoc`, `SegmentSummarizer.timeRange/duration/distance`, `Segment`
- Produces: `func timelineRows(from docs: [SegmentDoc], zone: TimeZone) -> [TimelineRow]`, `struct TimelineRow { let icon: TimelineIcon; let title: String; let detail: TimeRange; let duration: Duration; let distance: Distance?; let segmentIndex: Int }`

**정본:** `TimelineAdapter.kt` 와 `MapTimelineFragment.renderTimeline`(:1011). 머무름은 `placeName` 이 비면 "머무른 곳"으로 표시한다(`SegmentDoc.placeName` 주석).

- [ ] **Step 1~3: 테스트 먼저 → 구현 → 통과** — 머무름/이동 아이콘, 이름 없는 머무름, 거리 표시 유무.
- [ ] **Step 4: 화면에 붙이고 시뮬레이터에서 확인**
- [ ] **Step 5: 커밋**

---

### Task 4: 날짜 이동

**끝나면 `◀ 오늘 ▶` 로 어제·그제를 넘겨볼 수 있다.** 2단계의 `DayPicker` 가 여기서 처음 쓰인다 — 구조를 돌려주므로 화면이 `Localizable` 로 번역한다.

**Files:**
- Create: `ios/KidCare/Guardian/MapViewModel.swift` (`@Observable`. Task 1~3 이 `ChildMapView` 의 `@State` 에 쌓아 둔 로딩·상태를 여기로 옮긴다)
- Modify: `ios/KidCare/Guardian/ChildMapView.swift` (상태를 들고 있지 않고 `MapViewModel` 을 그리기만 한다)
- Test: `ios/KidCareTests/DayHeaderTextTests.swift`, `ios/KidCareTests/MapViewModelTests.swift`

> **계획서 표류 정리.** 이 계획서는 Task 1 부터 `MapViewModel` 을 전제했지만 Task 1~3 은 상태를 `ChildMapView` 의 `@State` 에 쌓았다. Task 5(명령 왕복)·7(실시간 세션)은 상태 기계라 뷰 안에 두면 UI 없이 테스트할 수 없다. 날짜 전환이 "다시 읽기"를 한 곳에 모아야 하므로 여기서 옮긴다. **커밋을 둘로 나눈다** — ① 동작 변화 없이 상태만 옮기기(기존 테스트·화면이 그대로여야 한다), ② 날짜 이동 추가.

**Interfaces:**
- Consumes: `DayPicker.todayKey/shift/isFuture/header/range`, `DayHeader`
- Produces: `func dayHeaderText(_ header: DayHeader) -> String` (화면 쪽 변환)

**정본:** `MapTimelineFragment.changeDay`(:848), `renderDayHeader`(:867).

**미래 날짜로는 못 간다**(`DayPicker.isFuture`). 날짜를 바꾸면 그 날 문서를 다시 읽고 지도와 타임라인을 함께 갈아끼운다.

- [ ] **Step 0: `MapViewModel` 로 상태를 옮긴다 (동작 변화 없음)** — `ChildMapView` 의 `상태`·`하루기록`·`오류`·`아이_이름`·`서버기준_지금` 과 `하루를_읽는다()` 를 `MapViewModel` 로 옮긴다. 뷰는 뷰모델을 그리기만 한다. 기존 테스트가 전부 초록이고 시뮬레이터 화면(경로선·상태 카드·타임라인)이 옮기기 전과 같아야 한다. **이 단계만 따로 커밋한다.**
- [ ] **Step 1~3: `dayHeaderText` 테스트 → 구현 → 통과** — 7개 요일 이름이 `schedule_day_mon`…`sun` 키를 쓰는지 확인(2단계에서 재사용하기로 한 키).
- [ ] **Step 4: 버튼을 붙이고 날짜를 넘겨 지도·타임라인이 바뀌는지 확인**
- [ ] **Step 5: 커밋**

---

### Task 5: '지금 위치 확인'

**끝나면 버튼을 눌러 아이 폰에 위치를 물어볼 수 있다.** 이 화면의 "정직한 표시" 규칙이 여기서 시작된다.

**Files:**
- Create: `ios/KidCare/Core/CommandRepository.swift`
- Modify: `ios/KidCare/Core/Documents.swift` (`CommandDoc`·`CommandType`·`CommandState`)
- Modify: `ios/KidCare/Guardian/MapViewModel.swift`, `StatusCardView.swift`
- Test: `ios/KidCareTests/CommandRepositoryTests.swift` (에뮬레이터)

**Interfaces:**
- Consumes: `AuthGateway`, `FamilyRepository.serverNow`
- Produces:
  - `CommandRepository.send(familyId:childUid:type:payload:) async throws -> String`
  - `CommandRepository.observeOne(familyId:childUid:commandId:onChange:onError:) -> ListenerRegistration`
  - `enum CommandProgress { case idle; case sending; case queued; case delivering; case done; case failed(String); case timedOut(lastSeen: LastSignal) }`

**정본:** `app/.../core/CommandRepository.kt`, `MapTimelineFragment.locateNow`(:363)와 `track`(:406).

**옮겨야 할 규칙 다섯** (상수는 `MapTimelineFragment.kt:1316-1320` 에서 그대로):
1. 보낸 뒤 그 명령 문서 하나를 따라가며 `전달 중…` → `완료` 를 보여준다.
2. **발행 자체를 `SEND_TIMEOUT_MILLIS = 15_000` 동안 기다리다 못 받으면 실패가 아니라 `.queued`** 로 `control_command_queued` 를 띄운다. 오프라인에서 Firestore 쓰기는 로컬 큐에 들어가 나중에 나가므로 "실패했다"고 말하면 거짓이다(:384-392).
3. **응답을 `COMMAND_TIMEOUT_MILLIS = 60_000` 안에 못 받으면** `control_command_timeout` 과 마지막 신호 시각을 함께 띄운다(:443-446).
4. **세대 번호(`commandGeneration`)** — 부모가 버튼을 다시 누르면 앞 명령의 늦게 온 콜백·제한시간을 무시한다(:374, :409, :444). 이게 없으면 두 번째 요청 도중에 첫 요청의 "응답 없음"이 뜬다.
5. `FAILED` 는 `childErrorText(doc.error)`(:691)로 번역한다 — 예: `ERROR_NO_FIX`("locate_no_fix"). `DONE`·`FAILED` 둘 다 `recordAnswer()`(:682)를 부른다 — **실패도 대답이다**(README "아이가 앱을 강제 종료하면" 절). 이 값이 무응답 배너(`DisconnectRule`)의 재료다.

`완료` 가 뜻하는 것은 **아이 폰이 done 이라고 적었다**는 것 하나뿐이다 — 코틀린 주석의 이 경고를 함께 옮긴다. 상태 기계는 `MapViewModel` 에 두고, 제한시간 두 개는 **주입 가능한 시계/수면 함수**로 받아 테스트가 60초를 실제로 기다리지 않게 한다.

- [ ] **Step 1: 에뮬레이터 상대 테스트를 쓴다** — 명령이 실제로 써지는지, 상태 변화를 리스너가 받는지, 60초 제한시간 갈래(주입 가능한 시계로).
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현하고 통과 확인**
- [ ] **Step 4: 버튼을 붙이고 에뮬레이터에서 손으로 상태를 바꿔가며 화면이 따라오는지 확인**
- [ ] **Step 5: 커밋**

---

### Task 6: 접기·드래그 타임라인 패널

**끝나면 타임라인을 위로 끌어올리거나 접을 수 있다.**

**Files:**
- Create: `ios/KidCare/Guardian/TimelinePanelView.swift`
- Modify: `ios/KidCare/Guardian/ChildMapView.swift`

**정본:** `MapTimelineFragment.bindTimelineDragHandle`(:908), `settleTimelineDrag`(:968), `collapsedPanelHeight`(:992), `maxTimelineContentHeight`(:1003), `renderTimelinePanel`(:876).

**네이버 지도 뷰가 제스처를 삼킨다**는 것을 1단계에서 관측했다. 드래그 핸들이 지도 위에 있으므로 **패널 제스처가 지도 팬과 싸우지 않는지 반드시 실기기·시뮬레이터에서 확인한다.** 안드로이드가 `ViewConfiguration` 으로 터치 슬롭을 재는 이유가 여기 있다.

- [ ] **Step 1: 패널을 만들고 접기/펼치기 버튼부터 붙인다** (드래그보다 쉬운 쪽 먼저)
- [ ] **Step 2: 시뮬레이터에서 접힘·펼침 확인**
- [ ] **Step 3: 드래그 제스처를 붙인다** — 안드로이드의 높이 계산(접힘 높이, 최대 높이)을 그대로 옮긴다.
- [ ] **Step 4: 지도 팬과 충돌하지 않는지 확인** — 패널을 끌 때 지도가 같이 움직이면 실패다.
- [ ] **Step 5: 네이버 로고 여백을 패널 높이에 맞춘다**(`updateNaverLogoMargin`, :1194) — 지도 SDK 이용약관상 로고가 가려지면 안 된다.
- [ ] **Step 6: 커밋**

---

### Task 7: 실시간 보기 토글

**끝나면 실시간 보기를 켜서 아이 위치가 따라 움직이는 것을 볼 수 있다.**

**Files:**
- Modify: `ios/KidCare/Guardian/MapViewModel.swift`, `StatusCardView.swift`
- Test: `ios/KidCareTests/LiveTrackingTests.swift`

**Interfaces:**
- Produces: `enum LiveTrackingState { case off; case starting; case on(until: Int64); case stopping }`

**정본:** `MapTimelineFragment.startLiveTracking`(:459), `trackLiveStart`(:508), `beginLiveStatusSubscription`(:540), `stopLiveTracking`(:593), `renderLiveTrackingState`(:642).

**이 기능은 무료 한도를 직접 먹는다.** 세션에 시간 제한이 있고(`PAYLOAD_DURATION_SECONDS`), 끝나면 반드시 구독을 뗀다. 안드로이드의 세션 ID 규약(`PAYLOAD_SESSION_ID`)도 그대로 쓴다 — 그래야 아이 폰이 옛 세션 명령을 무시한다.

- [ ] **Step 1~3: 상태 기계 테스트 → 구현 → 통과**
- [ ] **Step 4: 켜고 끄며 구독이 실제로 붙고 떨어지는지 확인** — 계측 후 제거.
- [ ] **Step 5: 커밋**

---

### Task 8: 구간별 경로 표시·숨기기

**끝나면 타임라인에서 구간을 눌러 그 구간 선만 켜고 끌 수 있다.**

**Files:**
- Modify: `ios/KidCare/Guardian/MapViewModel.swift`, `TimelineRowView.swift`, `NaverMapView.swift`

**정본:** `toggleRoute`(:1089), `toggleAllRoutes`(:1101), `renderRouteVisibilityState`(:1111), `fitWholeRoute`(:1177), `focusOn`(:1039).

- [ ] **Step 1: 구간 하나 누르면 지도가 그 구간으로 이동하고 선이 강조되게 한다**
- [ ] **Step 2: 전체 보기/숨기기 버튼**
- [ ] **Step 3: 시뮬레이터 확인 후 커밋**

---

### Task 9: 화면 전체를 실기기에서 확인

**Files:** 없음 (검증)

- [ ] **Step 1: 실기기가 연결돼 있는지 확인** — `xcrun devicectl list devices`. `unavailable` 이면 **여기서 멈추고 보고한다.** 케이블은 사람이 꽂아야 한다.
- [ ] **Step 2: 운영 Firebase 로 빌드해 실기기에 설치한다**(`configureForApp()` 그대로)
- [ ] **Step 3: `KidCareUITests` 로 화면을 눌러보고 스크린샷을 남긴다** — 경로선, 타임라인, 날짜 이동, 상태 카드.
- [ ] **Step 4: 안드로이드 폰 화면과 나란히 비교한다** — 같은 날짜, 같은 아이. 경로선 모양과 타임라인 문구가 같아야 한다. **다르면 그것이 2단계 골든 대조가 못 잡은 차이다.**
- [ ] **Step 5: 개발일지에 적고 커밋**

---

## 3단계 완료 기준

- [ ] 아이폰 지도에 하루 경로선이 그려진다
- [ ] 상태 카드에 아이 이름·배터리·마지막 신호 시각이 뜬다
- [ ] 타임라인 목록이 뜨고, 구간을 누르면 지도가 그리로 간다
- [ ] 날짜를 앞뒤로 넘길 수 있고 미래로는 못 간다
- [ ] '지금 위치 확인'이 왕복하고, 60초 무응답이 정직하게 표시된다
- [ ] 실시간 보기를 켜고 끌 수 있고, 끄면 구독이 떨어진다
- [ ] 타임라인 패널을 접고 펼치고 끌 수 있으며 지도 팬과 싸우지 않는다
- [ ] `ios/KidCare/Logic/` 이 여전히 Foundation 만 import 한다
- [ ] `git diff --stat main..HEAD -- app/src/main firestore.rules gradlew` 이 비어 있다
- [ ] 화면 문구가 전부 `Localizable.xcstrings` 를 거친다
