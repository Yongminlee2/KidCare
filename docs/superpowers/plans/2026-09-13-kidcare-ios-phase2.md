# iOS 2단계 구현 계획 — 계산 로직 포팅과 안드로이드 대조

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 보호자 화면이 쓰는 순수 계산 로직 8개를 Swift로 옮기고, **안드로이드와 같은 답을 내는 것을 기계가 증명**한다.

**Architecture:** `ios/KidCare/Logic/` 은 Foundation만 쓴다. 옮기는 순서는 "작고 독립적인 것 → 큰 것"이고, 각 단위는 **안드로이드 테스트를 XCTest로 먼저 옮겨 빨갛게 둔 뒤** 통과시킨다. 그 위에 골든 파일 대조를 얹는다 — 테스트가 안 보는 입력에서 두 구현이 갈리는 것을 잡기 위해서다.

**Tech Stack:** Swift 6 / Swift Testing / Foundation. 새 의존성 없음.

**Spec:** `docs/superpowers/specs/2026-09-12-kidcare-ios-design.md` (§6이 이 단계다)

## Global Constraints

- **포팅 과제에서 '구현할 내용'은 코틀린 원본 파일 자체다.** 이 계획서는 옮길 코드를 베껴 적지 않는다 — 1,476줄을 두 곳에 두면 반드시 어긋나고, 어긋난 쪽을 믿는 사람이 생긴다. 대신 각 과제가 **정확한 원본 경로와 만들어야 할 Swift 시그니처**를 준다. 구현자는 원본을 열어 읽고 옮긴다.
- **포팅의 정본은 코틀린이다.** `app/src/main/java/com/kidcare/family/logic/` 의 해당 파일과 `app/src/test/java/com/kidcare/family/logic/` 의 테스트를 **열어서 읽고** 옮긴다. 이 계획서가 코틀린과 다르면 코틀린이 맞다.
- **`ios/KidCare/Logic/` 은 `import Foundation` 만 한다.** Firebase·SwiftUI·UIKit 금지. 이 경계가 깨지면 테스트가 시뮬레이터를 요구하기 시작한다.
- **안드로이드 `app/` 아래를 수정하지 않는다.** 단 하나의 예외는 Task 10의 골든 파일 생성기이며, `app/src/test/` 에만 더한다 — 앱이 싣고 다니는 코드는 그대로다.
- Swift 6 strict concurrency. `@unchecked Sendable`·`nonisolated(unsafe)` 금지.
- 시각은 전부 UTC 밀리초 `Int64`. 시간대는 `TimeZone` 을 인자로 받는다(코틀린의 `ZoneId` 자리).
- **화면 문구를 하드코딩하지 않는다.** Task 4·5의 결정을 반드시 읽을 것.
- 주석은 **한국어로 '왜'**. 커밋 메시지는 **한국어**, author `Yongminlee2 <dydals5678@gmail.com>`, **도구·AI 흔적 금지**.
- 실행 전 PATH: `export PATH="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:$PATH"`
- 테스트: `cd ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'`
- **`KidCareUITests` 스킴은 건드리지 않는다.** 실기기·운영 Firebase 전용이라 이 단계와 무관하다.

## 이 단계에서 다루지 않는 것

- 화면. 이 단계가 끝나도 iOS 화면은 1단계 그대로다. 로직을 화면에 붙이는 것은 3단계다.
- 아이 폰 전용 로직(`LocationFilter`, `SegmentBuilder`, `MovementTrailFilter`, `AdaptiveMovementDetector`, `GeofenceEvaluator`, `TrailCodec`, `LiveLocationRefiner`). 보호자 앱이 쓰지 않는다.
- `InviteCode` — 1단계에서 이미 옮겼다.

---

## 시작 전에 반드시 읽을 결정 두 개

### 결정 1: 문구를 만들어 돌려주는 함수는 **구조를 돌려주게 바꾼다**

`DayPicker.headerText` 와 `SegmentSummarizer` 의 세 함수는 코틀린에서 한국어 문장을 직접 만들어 돌려준다:

```kotlin
today -> "오늘"
today.minusDays(1) -> "어제"
else -> "${date.monthValue}월 ${date.dayOfMonth}일 (${weekdayNames[...]})"
```

**이걸 그대로 옮기면 안 된다.** iOS는 14개 언어를 싣고, 이 앱의 규칙은 "화면 문구를 하드코딩하지 않는다"이다. 그대로 옮기면 영어 사용자 화면에 "오늘"이 뜨고, 6단계에서 `i18n` 으로 다국어를 생성할 때 이 문자열들만 빠진다.

**그래서 Swift 쪽은 문장 대신 값을 돌려준다.** 예: `DayPicker.header(...)` 는 `.today` / `.yesterday` / `.date(month:day:weekday:)` 를 돌려주고, 화면이 그것을 `Localizable` 키로 바꾼다. 같은 원칙을 `SegmentSummarizer` 에도 적용한다.

> **안드로이드에도 같은 문제가 있다.** `logic/` 이 한국어를 박아 돌려주므로, 기기 언어가 영어인 안드로이드 폰에서도 날짜 머리말과 구간 요약은 한국어로 나온다. **이 단계에서 안드로이드를 고치지는 않는다**(`app/` 불가침). `docs/known-issues.md` 에 적는 것은 이 계획서 밖의 일이므로, 발견 사실만 보고서에 남긴다.

### 결정 2: 골든 파일은 **문자열이 아니라 구조**를 비교한다

결정 1 때문에 `DayPicker`·`SegmentSummarizer` 는 두 플랫폼의 반환 타입이 다르다. 이 둘의 골든 대조는 **문장이 아니라 그 문장을 만드는 재료**(어느 갈래인지, 시·분, 거리 구간)를 비교한다. 나머지 여섯은 타입이 같아 값을 그대로 비교한다.

---

## File Structure

```
ios/KidCare/Logic/
├─ InviteCode.swift            (1단계에서 완료)
├─ Fix.swift                   Fix — 좌표 한 점. RoutePathRefiner 의 입력
├─ Segment.swift               Segment · SegmentType — 하루의 한 토막
├─ ChildSelector.swift         SelectableChild · ChildSelector
├─ DisconnectRule.swift        "물어봤는데 대답이 없다" 판정
├─ DayPicker.swift             날짜 이동 + 머리말 **구조**
├─ SegmentSummarizer.swift     구간 → 시각·기간·거리 **구조**
├─ RouteWindows.swift          경로선 창 배분
├─ KoreanHolidays.swift        LunarAnchors · Holiday · KoreanHolidays
├─ RoutePathRefiner.swift      Leg · 튐 제거·공백 분리·평활
└─ ScheduleResolver.swift      ScheduleRule · Resolution · 시간대 규칙 해석

ios/KidCare/Core/
└─ HolidayCalendar.swift       Foundation 중국식 달력으로 음력 세 기준일

ios/KidCareTests/
├─ (기존 6 suite)
├─ ChildSelectorTests.swift · DisconnectRuleTests.swift · DayPickerTests.swift
├─ SegmentSummarizerTests.swift · RouteWindowsTests.swift · KoreanHolidaysTests.swift
├─ RoutePathRefinerTests.swift · ScheduleResolverTests.swift
├─ HolidayCalendarTests.swift
└─ golden/                     Kotlin 이 뽑은 입력·기대출력 JSON

app/src/test/java/com/kidcare/family/logic/
└─ GoldenFileWriterTest.kt     신규. **test/ 에만 더한다** (Task 10)
```

---

### Task 1: serverNow 의 취소 전파를 마무리한다 (1단계 이월)

1단계 최종 검토가 남긴 유일한 미해결 항목이다. 로직 포팅보다 먼저 닫는다 — 3단계 화면이 이 함수를 부르기 때문이다.

**Files:**
- Modify: `ios/KidCare/Core/FamilyRepository.swift` (`serverNow`, `measureWithTimeout`)
- Test: `ios/KidCareTests/ServerNowTests.swift` (신규)

**Interfaces:**
- Consumes: 없음
- Produces: `FamilyRepository.serverNow(familyId:uid:) async throws -> Int64` (시그니처 유지)

**문제:** `measureWithTimeout` 이 두 개의 **비구조적** `Task` 를 `withCheckedThrowingContinuation` 안에서 경주시킨다. 비구조적 Task는 부모의 취소를 물려받지 않고 `CheckedContinuation` 은 취소를 모른다. 그래서 오프셋이 아직 캐시되지 않은 **첫 호출**(= `NewFamilySession` 이 초대를 발급하는 바로 그 순간)에 취소가 떨어져도 `serverNow` 는 정상 반환하고, 뒤이어 `createInvite` 가 아무도 못 볼 초대 문서를 써버린다. TTL 10분 동안 살아 있다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
import Testing
@testable import KidCare

@Suite(.serialized)
struct ServerNowTests {

    init() async { await EmulatorHarness.start() }

    @Test("취소된 작업 안에서 serverNow 는 CancellationError 를 던진다")
    func 취소되면_던진다() async throws {
        _ = try await EmulatorHarness.freshUser()

        let 작업 = Task { () -> Int64 in
            // 아직 멤버가 아닌 uid 라 측정이 서버 왕복을 기다린다 — 그 사이에 취소된다.
            try await FamilyRepository.serverNow(familyId: "없는가족", uid: "없는사람")
        }
        작업.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await 작업.value
        }
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `cd ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/ServerNowTests`
Expected: FAIL — 취소를 무시하고 값을 돌려주므로 `CancellationError` 가 안 난다.

- [ ] **Step 3: 취소를 관측하게 고친다**

`measureWithTimeout` 의 경주를 `withTaskCancellationHandler` 로 감싸, 부모가 취소되면 continuation 을 `CancellationError` 로 **한 번만** 재개시킨다. 이미 있는 `ResumeOnce` actor 가 중복 재개를 막아주므로 그 자리를 그대로 쓴다. 측정 Task 는 계속 돌게 두고 결과만 버린다 — Firestore 쓰기는 취소가 안 되므로 기다리면 그대로 멈춘다(1단계 C1에서 확인한 사실).

핵심은 셋이다: ① 취소 시 continuation 이 반드시 재개된다, ② 두 번 재개되지 않는다, ③ 취소로 끝난 경우 오프셋을 **캐시하지 않는다**(0을 굳히면 "만들자마자 죽은 코드"가 되살아난다).

- [ ] **Step 4: 테스트가 통과하는지 확인**

Run: Step 2와 같은 명령
Expected: PASS. 이어서 전체 suite도 초록인지 확인한다(29개).

- [ ] **Step 5: 커밋**

```bash
cd /Users/com/work/KidCare && git add ios && git commit
```

커밋 메시지에 담을 것: 비구조적 Task 가 취소를 안 물려받아 첫 호출에서 고아 초대 문서가 남던 것, 취소는 캐시하지 않는 이유.

---

### Task 2: 공용 타입 넷

로직들이 주고받는 값 타입이다. 계산이 없으므로 한 번에 옮긴다.

**Files:**
- Create: `ios/KidCare/Logic/Fix.swift`, `ios/KidCare/Logic/Segment.swift`
- Test: `ios/KidCareTests/LogicTypesTests.swift`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `struct Fix { let lat: Double; let lng: Double; let accuracy: Double; let at: Int64; let speed: Double }` — `speed` 기본값 0
  - `enum SegmentType { case stay, move }`
  - `struct Segment { let type: SegmentType; let startAt: Int64; let endAt: Int64; let lat: Double; let lng: Double; let distanceMeters: Double; let pointCount: Int; let nameAnchorLat: Double?; let nameAnchorLng: Double? }`

**정본:** `Fix` 는 `app/.../logic/LocationFilter.kt:10`, `Segment`·`SegmentType` 은 `app/.../logic/SegmentBuilder.kt:3,11`. **그 파일들의 로직은 옮기지 않는다** — 아이 폰 전용이다. 타입 선언만 가져온다. `Segment` 의 뒷부분 필드는 코틀린 원본을 열어 이름과 기본값을 그대로 확인할 것.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
import Testing
@testable import KidCare

struct LogicTypesTests {

    @Test("Fix 의 speed 는 기본값 0 이다")
    func fix_기본속도() {
        // 이 필드가 없던 시절 문서를 읽으면 0 으로 들어온다 — 코틀린이 기본값을 둔 이유.
        let f = Fix(lat: 37.5, lng: 127.0, accuracy: 12, at: 1_757_000_000_000)
        #expect(f.speed == 0)
    }

    @Test("Segment 는 머무름과 이동을 구분한다")
    func segment_종류() {
        let s = Segment(type: .stay, startAt: 1, endAt: 2, lat: 37.5, lng: 127.0,
                        distanceMeters: 0, pointCount: 3)
        #expect(s.type == .stay)
        #expect(s.distanceMeters == 0)
    }
}
```

- [ ] **Step 2: 실패 확인** — Run: `-only-testing:KidCareTests/LogicTypesTests` / Expected: 컴파일 실패(`Fix` 없음)

- [ ] **Step 3: 두 파일을 쓴다** — 코틀린 원본의 주석 중 **'왜'를 설명하는 것**(예: `speed` 기본값의 이유, `Segment.lat/lng` 가 STAY 와 MOVE 에서 뜻이 다르다는 것)을 함께 옮긴다. 필드 이름은 코틀린과 한 글자도 다르면 안 된다.

- [ ] **Step 4: 통과 확인** — Expected: PASS, 2개

- [ ] **Step 5: 커밋**

---

### Task 3: ChildSelector 와 DisconnectRule

둘 다 작고 서로 독립적이라 한 번에 옮긴다. 커밋은 둘로 나눈다.

**Files:**
- Create: `ios/KidCare/Logic/ChildSelector.swift`, `ios/KidCare/Logic/DisconnectRule.swift`
- Test: `ios/KidCareTests/ChildSelectorTests.swift`, `ios/KidCareTests/DisconnectRuleTests.swift`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `struct SelectableChild { let uid: String; let displayName: String; let joinedAt: Int64 }`
  - `enum ChildSelector { static func select(children: [SelectableChild], preferredUid: String?) -> SelectableChild? }`
  - `enum DisconnectRule { static let thresholdMillis: Int64 = 30 * 60 * 1000; static func isDisconnected(lastRequestAt: Int64, lastAnswerAt: Int64, nowMillis: Int64) -> Bool }`

**정본:** `app/.../logic/ChildSelector.kt`, `app/.../logic/DisconnectRule.kt`
**옮길 테스트:** `app/src/test/.../ChildSelectorTest.kt`(39줄), `DisconnectRuleTest.kt`(60줄)

> **`ChildSelector` 는 1단계에서 `FamilyRepository.findChildUid` 안에 인라인으로 흉내내 두었다.** 이제 진짜를 옮겼으므로 그 인라인 정렬을 지우고 `ChildSelector.select` 를 부르게 바꾼다. 1단계 검토가 "2단계가 이걸 대체한다"고 주석에 적어둔 자리다.

- [ ] **Step 1: 안드로이드 테스트 두 벌을 XCTest 로 옮겨 쓴다** — 코틀린 테스트 파일을 열어 **케이스 하나하나를 같은 뜻으로** 옮긴다. `@Test("...")` 의 이름은 코틀린의 백틱 이름을 그대로 쓴다.
- [ ] **Step 2: 실패 확인** — Expected: 컴파일 실패
- [ ] **Step 3: 두 파일을 구현한다** — 정렬 기준(`joinedAt` 오름차순 → `displayName` → `uid`)과 `joinedAt == 0` 을 맨 뒤로 보내는 처리를 코틀린 그대로 지킬 것.
- [ ] **Step 4: 통과 확인**
- [ ] **Step 5: `FamilyRepository.findChildUid` 가 `ChildSelector.select` 를 쓰게 고친다** — 인라인 정렬 삭제. 1단계의 `GuardianJoinTests` 가 여전히 초록인지 확인한다.
- [ ] **Step 6: 커밋 두 번** (ChildSelector + findChildUid 교체 / DisconnectRule)

---

### Task 4: DayPicker — 머리말을 구조로 돌려준다

**결정 1을 적용하는 첫 자리다.** 시작 전에 이 계획서 위쪽의 "결정 1"을 다시 읽을 것.

**Files:**
- Create: `ios/KidCare/Logic/DayPicker.swift`
- Test: `ios/KidCareTests/DayPickerTests.swift`
- Modify: `ios/KidCare/Localizable.xcstrings`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `enum DayHeader: Equatable { case today; case yesterday; case date(month: Int, day: Int, weekday: Int) }` — `weekday` 는 월=1 … 일=7 (코틀린 `DayOfWeek.value` 와 같게)
  - `enum DayPicker { static func todayKey(zone: TimeZone, nowMillis: Int64) -> String; static func shift(dayKey: String, days: Int) -> String; static func isFuture(dayKey: String, zone: TimeZone, nowMillis: Int64) -> Bool; static func header(dayKey: String, zone: TimeZone, nowMillis: Int64) -> DayHeader; static func range(dayKey: String, zone: TimeZone) -> Range<Int64> }`

**정본:** `app/.../logic/DayPicker.kt` · **옮길 테스트:** `DayPickerTest.kt`(69줄)

- [ ] **Step 1: 테스트를 옮겨 쓴다** — 코틀린이 `"오늘"` 을 기대하는 자리는 `.today` 를, `"8월 7일 (목)"` 을 기대하는 자리는 `.date(month: 8, day: 7, weekday: 4)` 를 기대하게 바꾼다. **날짜 계산 자체를 검증하는 케이스(자정 경계, 시간대, 미래 판정, `shift`)는 뜻이 그대로다.**
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현한다** — `dayKey` 형식은 `yyyy-MM-dd`. `DateFormatter` 대신 `Calendar` + `DateComponents` 로 계산해 로케일 영향을 받지 않게 한다(코틀린이 `LocalDate` 로 하는 것과 같은 성질).
- [ ] **Step 4: 통과 확인**
- [ ] **Step 5: 문구 키 셋을 더한다** — `i18n/ko.json` 과 `i18n/en.json` 에서 안드로이드가 이미 쓰는 "오늘"/"어제" 키가 있는지 **먼저 찾아보고**, 없으면 `day_header_today`·`day_header_yesterday`·`day_header_date`(서식 `%1$d월 %2$d일 (%3$@)`)를 양쪽에 더한 뒤 `Localizable.xcstrings` 에 넣는다. 요일 이름 일곱 개도 같은 방식으로 처리한다.
- [ ] **Step 6: 커밋** — 메시지에 "왜 문자열이 아니라 구조를 돌려주는가"를 적는다.

---

### Task 5: SegmentSummarizer — 시각·기간·거리를 구조로 돌려준다

**결정 1을 적용하는 두 번째 자리다.**

**Files:**
- Create: `ios/KidCare/Logic/SegmentSummarizer.swift`
- Test: `ios/KidCareTests/SegmentSummarizerTests.swift`
- Modify: `ios/KidCare/Localizable.xcstrings`

**Interfaces:**
- Consumes: `Segment`(Task 2)
- Produces:
  - `struct TimeRange: Equatable { let startHour: Int; let startMinute: Int; let endHour: Int; let endMinute: Int }`
  - `enum Duration: Equatable { case underOneMinute; case minutes(Int); case hours(Int); case hoursMinutes(Int, Int) }`
  - `enum Distance: Equatable { case underTenMeters; case meters(Int); case kilometers(Double) }`
  - `enum SegmentSummarizer { static func timeRange(_ segment: Segment, zone: TimeZone) -> TimeRange; static func duration(millis: Int64) -> Duration; static func distance(meters: Double) -> Distance }`

**정본:** `app/.../logic/SegmentSummarizer.kt` · **옮길 테스트:** `SegmentSummarizerTest.kt`(88줄)

**반올림 규칙을 정확히 지킬 것:** 1분 미만은 `.underOneMinute`, 1km 이상은 소수 첫째 자리, 미만은 **십 단위 내림**(10 미만이면 `.underTenMeters`). 코틀린 주석이 그 이유를 적어뒀다 — 미터를 1 단위까지 보이면 GPS 오차보다 정밀해 보여 없는 정확도를 있는 척하게 된다. 그 주석도 함께 옮긴다.

- [ ] **Step 1: 테스트를 옮겨 쓴다** — `"1시간 50분"` → `.hoursMinutes(1, 50)`, `"480m"` → `.meters(480)`, `"1.2km"` → `.kilometers(1.2)` 로 바꿔 기대한다. **경계값 케이스(59초, 60초, 999m, 1000m, 9m)는 그대로 다 옮긴다** — 거기가 갈리기 쉬운 자리다.
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현한다**
- [ ] **Step 4: 통과 확인**
- [ ] **Step 5: 문구 키를 더한다** — `%02d:%02d~%02d:%02d`, `분`/`시간`/`1분 미만`/`10m 미만`/`km`/`m` 에 해당하는 키를 `i18n/ko.json`·`en.json` 에 더하고 `Localizable.xcstrings` 에 넣는다. 안드로이드에 이미 같은 뜻의 키가 있으면 그것을 쓴다.
- [ ] **Step 6: 커밋**

---

### Task 6: RouteWindows

**Files:**
- Create: `ios/KidCare/Logic/RouteWindows.swift`
- Test: `ios/KidCareTests/RouteWindowsTests.swift`

**Interfaces:**
- Consumes: 없음
- Produces: `enum RouteWindows { static func partition(moves: [Range<Int64>]) -> [Range<Int64>] }`

**정본:** `app/.../logic/RouteWindows.kt`(47줄) · **옮길 테스트:** `RouteWindowsTest.kt`(44줄)

코틀린의 `LongRange`(끝 포함)와 Swift의 `Range`(끝 제외) 차이에 주의한다. **어느 쪽을 쓸지 정하고 테스트가 그것을 못 박게 한다** — 이 경계가 어긋나면 경로선의 점 하나가 창 밖으로 새고, 그게 1단계 README의 "창 밖 점 유실" 사고였다. 코틀린이 `start until end`(끝 제외)를 쓰는 곳과 `..`(끝 포함)을 쓰는 곳을 원본에서 직접 확인할 것.

- [ ] **Step 1: 테스트를 옮겨 쓴다**
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현한다**
- [ ] **Step 4: 통과 확인**
- [ ] **Step 5: 커밋**

---

### Task 7: KoreanHolidays 와 HolidayCalendar

**Files:**
- Create: `ios/KidCare/Logic/KoreanHolidays.swift`, `ios/KidCare/Core/HolidayCalendar.swift`
- Test: `ios/KidCareTests/KoreanHolidaysTests.swift`, `ios/KidCareTests/HolidayCalendarTests.swift`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `struct LunarAnchors { let seollal: DateComponents; let chuseok: DateComponents; let buddha: DateComponents }` — 양력 연·월·일
  - `enum Holiday: CaseIterable { case newYear, seollal, independence, buddha, children, memorial, liberation, chuseok, foundation, hangul, christmas, substitute }`
  - `enum KoreanHolidays { static func of(year: Int, anchors: LunarAnchors) -> [DateComponents: Holiday] }`
  - `enum HolidayCalendar { static func anchors(year: Int) -> LunarAnchors?; static func of(year: Int) -> [DateComponents: Holiday]; static func around(date: DateComponents) -> Set<DateComponents>; static func next(from: DateComponents) -> (DateComponents, Holiday)? }`

**정본:** `app/.../logic/KoreanHolidays.kt`(124줄), `app/.../core/HolidayCalendar.kt` · **옮길 테스트:** `KoreanHolidaysTest.kt`(102줄)

**경계를 그대로 지킨다:** `KoreanHolidays` 는 음력 세 기준일을 **밖에서 받는다**(순수 계산). 음력 환산은 `HolidayCalendar` 가 한다. 안드로이드는 ICU `ChineseCalendar`, iOS는 `Calendar(identifier: .chinese)` 로 `TimeZone(identifier: "Asia/Seoul")` 을 써서 같은 답을 낸다.

> **이미 확인된 값(2026-09-12).** 2025 설날 01-29 · 부처님오신날 05-05 · 추석 10-06 / 2026 02-17 · 05-24 · 09-25 / 2027 02-06 · 05-13 · 09-15. `HolidayCalendarTests` 는 이 아홉 개를 못 박는다.

대체공휴일 규칙(관공서의 공휴일에 관한 규정 제3조, 2023년 개정)은 코틀린 파일 맨 위 주석에 정리돼 있다. **그 주석을 읽고 옮긴다** — 특히 "대체공휴일 자리는 그 다음의 첫 번째 비공휴일인데 주말도 함께 건너뛴다"는 판단(법문과 다르지만 실제 운영과 같게 맞춘 것)을 빠뜨리지 말 것.

- [ ] **Step 1: `KoreanHolidaysTests` 를 옮겨 쓴다**
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: `KoreanHolidays.swift` 를 구현한다**
- [ ] **Step 4: 통과 확인**
- [ ] **Step 5: `HolidayCalendarTests` 를 쓴다** — 위 아홉 개 값을 못 박고, ICU가 그 해를 못 다루면 `nil` 로 물러나는지도 확인한다(코틀린이 그렇게 한다 — 공휴일을 모르는 채로 도는 것이 틀린 날을 쉬는 것보다 낫다).
- [ ] **Step 6: `HolidayCalendar.swift` 를 구현하고 통과 확인**
- [ ] **Step 7: 커밋 두 번**

---

### Task 8: RoutePathRefiner

**Files:**
- Create: `ios/KidCare/Logic/RoutePathRefiner.swift`
- Test: `ios/KidCareTests/RoutePathRefinerTests.swift`

**Interfaces:**
- Consumes: `Fix`(Task 2)
- Produces:
  - `struct Leg { let points: [Fix] }`
  - `enum RoutePathRefiner { static let maxDisplayAccuracyMeters: Double = 50; static let gapBreakMillis: Int64 = 10 * 60_000; static let gapBreakDistanceMeters: Double = 150; static func refine(points: [Fix]) -> [Leg] }`

**정본:** `app/.../logic/RoutePathRefiner.kt`(153줄) · **옮길 테스트:** `RoutePathRefinerTest.kt`(77줄)

이 파일은 **문턱 숫자 하나만 어긋나도 지도 위의 선이 달라진다.** 상수를 코틀린에서 그대로 복사하고, 단일 튐 제거·시간 공백 분리·오차 가중 평활 세 단계의 순서를 바꾸지 말 것. 부동소수 비교가 들어가는 자리는 테스트에서 허용 오차를 명시한다.

- [ ] **Step 1: 테스트를 옮겨 쓴다**
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현한다** — 거리 계산은 코틀린이 쓰는 것과 같은 공식을 쓴다. 원본이 `Location.distanceBetween` 같은 안드로이드 API를 쓰지 않고 직접 계산하는지 확인하고, 직접 계산이면 그 식을 그대로 옮긴다.
- [ ] **Step 4: 통과 확인**
- [ ] **Step 5: 커밋**

---

### Task 9: ScheduleResolver

가장 크고(196줄) 테스트도 가장 많다(187줄). 자정을 넘는 규칙과 겹침 해석이 들어 있다.

**Files:**
- Create: `ios/KidCare/Logic/ScheduleResolver.swift`
- Test: `ios/KidCareTests/ScheduleResolverTests.swift`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `struct ScheduleRule { let id: String; let days: Set<Int>; let startMinute: Int; let endMinute: Int; let mode: String; let enabled: Bool; let priority: Int }` — `days` 는 월=1 … 일=7
  - `struct Resolution: Equatable { let mode: String?; let nextBoundaryMillis: Int64? }`
  - `enum ScheduleResolver { static func resolveAt(rules: [ScheduleRule], atMillis: Int64, zone: TimeZone, holidays: Set<DateComponents> = []) -> Resolution; static func overlaps(rules: [ScheduleRule], candidate: ScheduleRule) -> [ScheduleRule] }`

**정본:** `app/.../logic/ScheduleResolver.kt` · **옮길 테스트:** `ScheduleResolverTest.kt`(187줄)

**코틀린 주석이 근거를 적어둔 자리 셋을 반드시 함께 옮긴다:** ① 왜 오늘과 어제 시작한 구간만 보면 충분한가(구간 길이가 24시간을 못 넘으므로), ② 겹칠 때 우선순위 결정 방식, ③ 공휴일 집합이 어떻게 규칙을 쉬게 하는가.

- [ ] **Step 1: 테스트를 옮겨 쓴다** — 187줄이다. 케이스를 빠뜨리지 말 것. 특히 자정 넘김·경계 정확히 일치·겹침·공휴일 조합.
- [ ] **Step 2: 실패 확인**
- [ ] **Step 3: 구현한다**
- [ ] **Step 4: 통과 확인**
- [ ] **Step 5: 커밋**

---

### Task 10: 골든 파일 대조 — 두 구현이 정말 같은 답을 내는가

**여기가 이 단계의 핵심이다.** 테스트만으로는 "테스트가 안 보는 입력"에서 갈리는 것을 못 잡는다.

**Files:**
- Create: `app/src/test/java/com/kidcare/family/logic/GoldenFileWriterTest.kt` (**`app/src/test/` 에만 더한다 — `main/` 은 건드리지 않는다**)
- Create: `ios/KidCareTests/golden/*.json` (위 테스트가 생성)
- Create: `ios/KidCareTests/GoldenComparisonTests.swift`

**Interfaces:**
- Consumes: Task 4~9의 모든 타입
- Produces: 없음(검증 전용)

**대상 다섯:** `ScheduleResolver`(자정 넘김·겹침), `RoutePathRefiner`(튐 제거·평활), `KoreanHolidays`(2025~2030 대체공휴일 전부), `SegmentSummarizer`(경계값), `RouteWindows`(창 배분).

- [ ] **Step 1: 코틀린 생성기를 쓴다**

`GoldenFileWriterTest.kt` 는 JUnit 테스트 모양이지만 검증이 아니라 **출력**이 목적이다. 각 대상마다 입력을 프로그램으로 넓게 만들어(경계 주변을 촘촘히, 무작위는 고정 시드로) 입력과 기대 출력을 JSON 으로 쓴다. 저장 위치는 저장소 루트 기준 `ios/KidCareTests/golden/<이름>.json`.

`@Ignore` 를 붙이지 **않는다** — 안드로이드 CI에서 같이 돌아 파일이 최신으로 유지되는 편이 낫다. 대신 파일이 이미 있고 내용이 같으면 다시 쓰지 않아 git diff 를 더럽히지 않게 한다.

- [ ] **Step 2: 생성기를 돌려 파일을 만든다**

```bash
export PATH="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:$PATH"
export JAVA_HOME="/opt/homebrew/opt/openjdk@21"
cd /Users/com/work/KidCare && sh gradlew :app:testDebugUnitTest -x processDebugGoogleServices --tests '*GoldenFileWriterTest'
```

Expected: `ios/KidCareTests/golden/` 에 JSON 다섯 개가 생긴다.

> **`-x processDebugGoogleServices` 를 반드시 붙인다.** 이 클론에는 `app/google-services.json` 이 없고(gitignore 대상), 그게 없으면 Google Services 플러그인이 빌드를 세운다. 순수 JVM 단위 테스트는 그 파일이 필요 없으므로 그 태스크만 건너뛴다. **더미 `google-services.json` 을 만들지 않는다** — 나중에 그 파일로 APK 를 만들면 Firebase 에 연결되지 않는 앱이 조용히 나온다.
>
> **`./gradlew` 가 아니라 `sh gradlew` 로 부른다.** 저장소의 `gradlew` 는 실행 권한이 없는데(윈도우에서 만들어진 파일), 그 권한 비트를 바꾸는 것은 안드로이드 쪽 변경이라 이 작업의 범위 밖이다. `sh` 로 부르면 권한 없이 그대로 돈다.
>
> Android SDK 는 이미 설치돼 있고 `local.properties` 에 `sdk.dir` 이 적혀 있다(gitignore 대상). 그래도 안 되면 **멈추고 보고한다**.

- [ ] **Step 3: Swift 대조 테스트를 쓴다**

```swift
import Foundation
import Testing
@testable import KidCare

/// 안드로이드가 뽑아 둔 입력·기대출력을 그대로 먹고 같은 답이 나오는지 본다.
///
/// 단위 테스트와 목적이 다르다. 저 쪽은 "내가 생각한 경우"를 확인하고, 이 쪽은
/// **두 구현이 같은 함수인가**를 확인한다. 테스트가 안 보는 입력에서 갈리는 것은
/// 이 방법으로만 잡힌다.
struct GoldenComparisonTests {

    private func 읽는다(_ 이름: String) throws -> [[String: Any]] {
        let url = try #require(Bundle(for: BundleToken.self)
            .url(forResource: 이름, withExtension: "json", subdirectory: "golden"))
        let data = try Data(contentsOf: url)
        return try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    @Test("공휴일이 안드로이드와 같다 (2025~2030)")
    func 공휴일_대조() throws {
        for 사례 in try 읽는다("koreanHolidays") {
            let year = 사례["year"] as! Int
            let 기대 = 사례["holidays"] as! [String: String]
            let anchors = try #require(HolidayCalendar.anchors(year: year))
            let 실제 = KoreanHolidays.of(year: year, anchors: anchors)
            // JSON 은 "2026-02-17": "SEOLLAL" 꼴이다. DateComponents 를 같은 문자열로
            // 맞춰야 비교가 된다 — 이 변환을 테스트 안에 두는 이유는, 프로덕션 코드가
            // 골든 파일 형식을 알 이유가 없기 때문이다.
            var 실제문자열: [String: String] = [:]
            for (날짜, 공휴일) in 실제 {
                let key = String(format: "%04d-%02d-%02d", 날짜.year!, 날짜.month!, 날짜.day!)
                실제문자열[key] = String(describing: 공휴일).uppercased()
            }
            #expect(실제문자열 == 기대, "\(year)년 공휴일이 다르다")
        }
    }
}

private final class BundleToken {}
```

나머지 넷도 같은 모양으로 쓴다. 각 JSON 의 필드 이름은 Step 1에서 정한 것을 그대로 쓴다.

- [ ] **Step 4: `golden/` 이 테스트 번들에 실려 들어가는지 확인한다**

`ios/project.yml` 의 `KidCareTests` 타깃에 `golden` 폴더가 **리소스로** 들어가야 한다. Swift 소스 글롭만으로는 `.json` 이 안 실린다. `sources` 에 `buildPhase: resources` 항목을 더하고 `xcodegen generate` 후 확인한다.

- [ ] **Step 5: 대조가 통과하는지 확인**

Run: `-only-testing:KidCareTests/GoldenComparisonTests`
Expected: PASS.

**하나라도 빨간색이면 그것이 이 단계가 찾아내려던 바로 그 차이다.** 코틀린이 정본이므로 Swift 를 고친다. 어떤 입력에서 어떻게 갈렸는지를 보고서에 적을 것.

- [ ] **Step 6: 전체 suite 확인** — Expected: 초록. 누적 테스트 수를 보고서에 적는다.

- [ ] **Step 7: 커밋**

---

### Task 11: 앱 아이콘

지금 아이폰 홈 화면에 빈 아이콘으로 나온다. 원래 7단계 항목이지만 눈에 바로 보이고 소재가 이미 있어 앞으로 당긴다.

**Files:**
- Create: `ios/KidCare/Assets.xcassets/Contents.json`
- Create: `ios/KidCare/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `ios/KidCare/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
- Modify: `ios/project.yml` (에셋 카탈로그를 리소스로 싣고 `ASSETCATALOG_COMPILER_APPICON_NAME` 설정)

**Interfaces:**
- Consumes: `app/src/main/res/drawable-nodpi/ic_launcher_artwork.png` (768×768 RGBA), `app/src/main/res/values/colors.xml` 의 `mascot_bg` = `#CFEDE7`
- Produces: 홈 화면에 뜨는 앱 아이콘

**안드로이드와 같은 그림을 쓴다.** 새로 그리지 않는다 — 같은 앱이니 아이콘도 같아야 한다. 안드로이드는 적응형 아이콘이라 배경(민트 `#CFEDE7`)과 앞그림(마스코트)이 분리돼 있고, 런처가 마스크로 잘라낸다. iOS는 그런 구조가 없으므로 **둘을 하나로 합친 정사각형 PNG 한 장**을 만든다.

**iOS 아이콘의 제약 셋:**
- 정확히 **1024×1024**
- **알파 채널이 없어야 한다.** 투명도가 남아 있으면 App Store 업로드가 거부된다. 원본이 RGBA 이므로 반드시 불투명 배경 위에 합성해 알파를 없앤다.
- 모서리는 시스템이 둥글게 깎는다. 그림이 가장자리에 붙어 있으면 잘린다.

- [ ] **Step 1: 합성 스크립트를 쓴다**

`tools/make-ios-icon.swift` 를 만든다. 의존성을 더하지 않기 위해 CoreGraphics 로 직접 그린다(ImageMagick 같은 것을 새로 깔지 않는다).

하는 일: 1024×1024 불투명 비트맵을 `#CFEDE7` 로 채우고, 원본 PNG 를 가운데에 **가로세로 80%** 크기로 그린 뒤 PNG 로 쓴다. 80% 인 이유는 iOS 가 모서리를 깎고 홈 화면에서 아이콘끼리 붙어 보이지 않게 여백이 필요하기 때문이다. 안드로이드 적응형 아이콘이 108dp 중 72dp 만 보여주는 것과 같은 취지다.

- [ ] **Step 2: 아이콘을 만든다**

```bash
cd /Users/com/work/KidCare && swift tools/make-ios-icon.swift \
  app/src/main/res/drawable-nodpi/ic_launcher_artwork.png \
  ios/KidCare/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```

Expected: 1024×1024 PNG 가 생긴다.

- [ ] **Step 3: 알파가 없는지 확인한다**

```bash
file ios/KidCare/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```

Expected: `1024 x 1024, 8-bit/color RGB` — **RGBA 가 아니어야 한다.** RGBA 로 나오면 Step 1 의 비트맵 컨텍스트가 알파를 쓰고 있다는 뜻이니 고친다.

- [ ] **Step 4: 에셋 카탈로그를 만든다**

`AppIcon.appiconset/Contents.json` 은 단일 1024 항목만 둔다(iOS 17+ 는 나머지 크기를 시스템이 만든다):

```json
{
  "images" : [
    { "filename" : "AppIcon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

`Assets.xcassets/Contents.json` 은 `{ "info" : { "author" : "xcode", "version" : 1 } }` 하나면 된다.

- [ ] **Step 5: `project.yml` 에 싣는다**

`KidCare` 타깃의 `sources` 에 `Assets.xcassets` 를 더하고, `settings.base` 에 `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` 을 넣는다. 그 뒤 `xcodegen generate`.

- [ ] **Step 6: 빌드하고 실기기에 넣어 눈으로 본다**

```bash
export PATH="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:$PATH"
cd ios && xcodebuild -project KidCare.xcodeproj -scheme KidCare \
  -destination 'id=6C5120C8-779D-5250-AB4C-B152B9A648A2' \
  -derivedDataPath /tmp/kidcare-device -allowProvisioningUpdates build
xcrun devicectl device install app --device 6C5120C8-779D-5250-AB4C-B152B9A648A2 \
  /tmp/kidcare-device/Build/Products/Debug-iphoneos/KidCare.app
```

그다음 홈 화면을 확인한다. **실기기 화면은 직접 볼 수 없으므로**, `KidCareUITests` 로 앱을 띄워 스크린샷을 찍어도 홈 화면은 안 나온다 — 아이콘 확인은 사람이 해야 한다. 대신 **시뮬레이터에서는 확인할 수 있다**: 시뮬레이터에 설치한 뒤 홈 버튼(`xcrun simctl ui <udid> ...` 로는 안 되므로) 대신 `xcrun simctl get_app_container` 로 설치를 확인하고, `.app/AppIcon60x60@2x.png` 같은 생성물이 번들에 들어갔는지로 검증한다.

- [ ] **Step 7: 전체 테스트가 여전히 초록인지 확인하고 커밋**

아이콘은 테스트가 없지만, 에셋 카탈로그를 추가하면서 빌드 설정이 깨지지 않았는지는 확인해야 한다.

---

## 2단계 완료 기준

- [ ] `xcodebuild test` 가 초록이고, 안드로이드 테스트 8벌이 XCTest 로 전부 옮겨졌다
- [ ] `ios/KidCare/Logic/` 의 모든 파일이 `Foundation` 만 import 한다
- [ ] 골든 파일 대조 다섯이 통과한다
- [ ] `DayPicker`·`SegmentSummarizer` 가 문장이 아니라 구조를 돌려주고, 화면 문구는 `Localizable.xcstrings` 에만 있다
- [ ] `FamilyRepository.findChildUid` 가 `ChildSelector.select` 를 쓴다
- [ ] `serverNow` 가 취소를 전파한다 (1단계 이월 항목 종결)
- [ ] 아이폰 홈 화면에 안드로이드와 같은 앱 아이콘이 뜬다
- [ ] `git diff --stat main..HEAD -- app/src/main/` 이 비어 있다 (`app/src/test/` 의 생성기만 예외)
