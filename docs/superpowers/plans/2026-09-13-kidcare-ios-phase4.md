# iOS 4단계 구현 계획 — 탭 다섯, 관리 탭, 무응답 배너

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 아이폰 보호자 앱에 안드로이드와 같은 하단 탭 다섯을 세우고, 관리 탭(인터넷 상태·소리 모드·잠금·폰찾기·한마디·알람)을 안드로이드 `ControlFragment` 와 같게 옮기고, 무응답 배너를 모든 탭 위에 띄우고, 초대 코드 입력칸의 키보드 버그를 고친다.

**Architecture:** `GuardianRootView` 가 안드로이드 `GuardianMainActivity` 자리다 — 탭 컨테이너이자 배너의 유일한 주인이며, 탭마다의 뷰모델(`MapViewModel`·`ControlViewModel`)을 **탭 전환보다 오래** 소유한다(안드로이드의 show/hide 와 같은 수명). 관리 탭의 명령 왕복은 `ControlViewModel`(@MainActor @Observable) 한 곳에 두고 Firestore 쪽은 전부 주입 가능한 클로저로 받아 UI 없이 테스트한다. 쓰기는 `CommandRepository.send`(이미 있음)와 새 `ScheduleRepository.setRingerLock` 둘뿐이다.

**Tech Stack:** Swift 6 / SwiftUI(`TabView`, `@SceneStorage`) / Firebase Firestore 12.19.1 / Swift Testing. 새 의존성 없음.

**Spec:** `docs/superpowers/specs/2026-09-12-kidcare-ios-design.md` (§4 화면·탭별 대응표·"탭을 바꿔도 지도를 다시 만들지 않는다", §8 명령의 정직한 표시·무응답 배너, §9 4단계)

## Global Constraints

브리프에서 그대로 옮긴 것(verbatim):

- Swift 6 strict concurrency, iOS 17.0, SwiftUI, XcodeGen (`ios/project.yml`; never hand-edit the xcodeproj), Swift Testing. `ios/KidCare/Logic/` imports Foundation only. No `@unchecked Sendable` or `nonisolated(unsafe)` in app code.
- Android `app/`, `firestore.rules` and `gradlew` are not modified. Android defects found go into the README dev log only.
- No push notifications and no FCM (the Firebase Spark free plan). Every Firestore listener has a removal path on disappear.
- i18n: new keys are added to **both** `i18n/ko.json` and `i18n/en.json` and are regenerated into `Localizable.xcstrings` the way earlier phases did (find the mechanism, e.g. `tools/check-i18n-keys.swift` and the existing parity tests, and state the exact command). `%@` is never used in `i18n/*.json`. A literal `%` must be `%%` in format strings. **Never borrow a string key from an unrelated screen** (this was rejected twice).
- Tests never write to production Firestore. Emulator tests use `configureForEmulator(projectId: "kidcare-emulator")` (Auth 127.0.0.1:9099, Firestore 8080), and `KidCareApp.init()` must call `configureForApp()` at commit time.
- Commits are in Korean, author `Yongminlee2 <dydals5678@gmail.com>`, with no Co-Authored-By trailer and no AI traces.
- Test command: `cd ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'`.

이 저장소에서 이어지는 규칙:

- **정본은 안드로이드다.** `guardian/GuardianMainActivity.kt`(560줄)·`activity_guardian_main.xml`·`menu/guardian_bottom_nav.xml`·`guardian/ControlFragment.kt`(1,154줄)·`fragment_control.xml`·`guardian/AlarmMemoStore.kt`·`guardian/RequestLog.kt`·`core/ScheduleRepository.kt`·`core/model/Documents.kt`·`onboarding/ChildPairingActivity.kt`·`activity_child_pairing.xml`. 이 계획서가 코틀린과 다르면 코틀린이 맞다. 상수는 인용한 줄에서 **그대로** 옮긴다.
- 색·치수는 안드로이드 리소스 값 그대로(`res/values/colors.xml`, `themes.xml`, `dimens.xml`) — 설계서 §4.
- **보이는 뒤로 가기.** 이 단계는 push 되는 화면을 새로 만들지 않는다(안드로이드 관리 탭에 화면 전환이 없다 — `GuardianMainActivity.kt:80-92` 주석이 일부러 안 만든 이유를 적었다). 기존 push 화면(`JoinFamilyView`)은 시스템 뒤로 버튼을 **가리지 않는다**(`.navigationBarBackButtonHidden` 금지). 새 화면을 push 해야 하는 일이 생기면 계획서를 멈추고 알린다.
- 주석은 **한국어로 '왜'**. 커밋 전 `KidCareApp.init()` 이 `FirebaseBootstrap.configureForApp()` 인지 `git diff ios/KidCare/KidCareApp.swift` 로 확인한다.
- 실행 전 PATH: `export PATH="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:$PATH"`
- 파일을 새로 만들었으면 테스트 전에 `cd ios && xcodegen generate` (`.xcodeproj` 는 커밋하지 않는다 — 1단계 계획서 Global Constraints).
- 에뮬레이터: `firebase emulators:start --only auth,firestore --project kidcare-emulator` (저장소 루트에서, 1단계 계획서 :143). 에뮬레이터를 쓰는 스위트는 기존처럼 `init() async { await EmulatorHarness.start() }`.

## 공통 절차 A — 문구 키를 카탈로그에 넣는 법 (조사 결과)

설계서 §7 의 `tools/ios-strings.py` 는 **아직 없다**(6단계 몫). 1~3단계는 `i18n/ko.json` 의 한국어 값을 `ios/KidCare/Localizable.xcstrings` 에 **손으로** 옮겼다(1단계 계획서 :21 "1단계 동안은 `Localizable.xcstrings` 에 한국어만 직접 넣어 둔다", 2단계 계획서 :262). 옮길 때의 변환 규칙을 기존 카탈로그와 대조해 확정했다:

| `i18n/*.json` | `Localizable.xcstrings` | 근거(기존 항목) |
|---|---|---|
| `%1$s` | `%1$@` | `control_last_seen_format` |
| `%1$d`, `%1$02d` | 그대로 | `control_last_seen_minutes`, `schedule_time_format` |
| 서식이 아닌 `%` | `%%` | `map_status_format` (`배터리 %1$d%` → `%1$d%%`) |

손으로 옮기다 틀리지 않게, 키는 `tools/add-ios-catalog-keys.py` 로 넣는다(이미 있는 키는 **건너뛴다** — 아래 "알려진 어긋남" 셋을 덮지 않기 위해서다). 파일 전체를 `json.dumps(indent=2, ensure_ascii=False) + "\n"` 로 다시 쓰며, 기존 파일과 바이트 단위로 같아 diff 에는 넣은 키만 나온다(키 정렬 포함). 서식 정규식은 `%(\d+\$)?(\d+)?(\.\d+)?([sdf])` 로 `LocalizableCatalogTests.카탈로그_값` 과 같다 — 예전 인라인 명령의 `([sd])` 는 `%1$.1f` 를 `%%1$.1f` 로 망가뜨렸다(통합 검토 M3).

```bash
cd /Users/com/work/KidCare && python3 tools/add-ios-catalog-keys.py 키1 키2 ...
```

검사 둘:

- `swift tools/check-i18n-keys.swift` — 14개 언어 키 집합 비교. **지금도 종료 코드 1 이 정상이다**(1~3단계 키가 ko/en 에만 있다, `I18nKeyParityTests` 가 `withKnownIssue` 로 기록). 이번 단계가 새로 더하는 키는 `ios_tab_not_ready_body` 하나이고, 출력의 12개 언어 목록에 그 키가 하나씩 늘어나는 것이 기대값이다. 번역을 지어내지 않는다.
- `LocalizableCatalogTests`(Task 1 이 만든다) — 카탈로그 값이 위 변환 규칙으로 `ko.json` 에서 나왔는지, 그리고 앱 코드가 쓰는 원본 키가 전부 카탈로그에 있는지를 테스트 스위트 안에서 기계로 본다.

**알려진 어긋남 셋(건드리지 않는다).** 기존 카탈로그에서 `guardian_start_join_family`("가족에 합류하기" ↔ 원본 "초대 번호로 기존 가족 참여"), `map_no_child`("아직 연결된 아이가 없어요" ↔ "아직 아이 폰이 연결되지 않았어요."), `role_guardian`("보호자" ↔ "보호자 (엄마·아빠)") 셋은 1단계에서 손으로 고친 값이 남아 있다. `PairingUITests` 가 "가족에 합류하기"·"보호자" 문구로 버튼을 찾으므로 이번 단계에서 고치면 실기기 자동화가 깨진다. 6단계가 원본에서 생성할 때 정리하도록 개발일지에 남긴다.

## 공통 절차 B — 커밋

```bash
cd /Users/com/work/KidCare
git diff --stat 31c6eb2..HEAD -- app firestore.rules gradlew   # 비어 있어야 한다
git diff ios/KidCare/KidCareApp.swift                            # 비어 있어야 한다(configureForApp)
git add <이 Task 의 파일들>
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "<한국어 메시지>"
```

## 이 단계에서 다루지 않는 것

- **아이 선택기와 그 메뉴의 '＋ 아이 추가'·'＋ 보호자 초대'.** 안드로이드에서 초대 코드 발급은 관리 탭이 아니라 자녀 선택기 팝업에 있다(`GuardianMainActivity.kt:243-286` → `GuardianPairingActivity`). 설계서 §9 는 아이 선택기를 **6단계**에 둔다. 이 단계는 `RoleStore.childUid` 하나를 쓴다. 따라서 `ControlFragment` 의 `joinedListener`(:296-310, 선택한 아이가 바뀌면 다시 구독)도 6단계로 넘긴다 — 아이가 하나로 고정된 동안 그 리스너의 `onJoined` 는 `uid == childUid` 조건(:300)에 걸려 아무 일도 하지 않는다.
- **멤버 목록, 연결 끊기·가족 나가기.** 안드로이드 앱에 그런 화면이 **없다**(`app/src/main` 전체에서 멤버 삭제·탈퇴 호출 0건). 규칙(`firestore.rules:137`)만 보호자의 멤버 삭제를 허용한다. 없는 기능을 지어내지 않는다.
- 알림·예약·장소 탭의 내용(5·6단계). 이 단계는 탭 바가 완전하도록 **자리표시 화면**만 둔다.
- 언어 고르기 버튼(`activity_guardian_main.xml:44-62`) — 6단계(14개 언어).
- 다크 모드 색(`values-night/`) — 이 앱은 아직 밝은 색표 하나다.

## 판정 기록 — 이 계획서가 내린 결정

1. **브리프 범위 vs 설계서.** 브리프는 관리 탭을 "멤버·아이 목록, 초대 코드 발급, 연결 끊기"로 적었지만, 설계서 §9(구속력 있음)는 4단계를 "관리 탭 — 소리 변경 · 폰찾기 · 메시지 · 알람 · 무응답 배너"로 적고, 안드로이드 `ControlFragment` 가 실제로 그 화면이다. 설계서와 안드로이드를 따른다. 초대는 6단계(위 절).
2. **탭을 옮겨도 리스너를 떼지 않는다 — 안드로이드와 같다.** 안드로이드는 `replace` 가 아니라 show/hide 로만 탭을 오간다(`GuardianMainActivity.kt:39-42`, `showTab` :329-353). `MapTimelineFragment` 와 `ControlFragment` 둘 다 `onHiddenChanged` 가 없고, 리스너는 `onDestroyView`(`MapTimelineFragment.kt:1299-1311`, `ControlFragment.kt:1094-1116`)에서만 뗀다. 즉 지도 탭의 명령 추적·실시간 세션 리스너와 관리 탭의 `settings/ringer` 리스너는 다른 탭을 보는 동안에도 붙어 있다. SwiftUI `TabView` 는 탭을 옮길 때마다 `onDisappear` 를 부르고 `.task` 를 취소하므로, 지금 `ChildMapView.onDisappear` 에 있는 정리를 그대로 두면 **관리 탭을 한 번 눌렀을 뿐인데 실시간 보기가 꺼지고**, `.task` 의 첫 읽기가 탭에 돌아올 때마다 다시 돌아 Firestore 읽기가 는다. 그래서 정리를 `GuardianRootView.onDisappear`(보호자 화면 자체가 사라질 때 — 안드로이드 `onDestroyView` 자리)로 옮긴다. 붙어 있는 리스너가 무한정 비용을 만들지 않는 근거: 명령 리스너는 문서 한 개이고 done/failed 뒤로는 바뀌지 않으며, 실시간 세션은 10분 만료 타이머(`MapViewModel.liveSessionTimeoutMillis`)와 아이 폰 쪽 자체 제한이 있다.
3. **문구 카탈로그 생성 방식.** 설계서 §3·§7 이 말하는 `tools/ios-strings.py` 는 없다. 앞 단계들이 쓴 손 옮기기를 명령 한 줄로 고정하고(공통 절차 A), 결과를 테스트로 검사한다.
4. **`ControlFragment` 가 예약 탭 키 `schedule_time_format` 을 쓴다.** 알람 시각 표기가 `ScheduleText.timeText`(`ScheduleAdapter.kt:186-187`)를 거치기 때문이다(`ControlFragment.kt:916,922`). "무관한 화면의 키를 빌리지 않는다" 규칙은 **iOS 가 새로** 빌리는 것을 막는 규칙이고, 이건 안드로이드가 이미 같은 문구로 정한 자리라 그대로 따른다.
5. **아이가 없을 때 소리 상태 줄.** 안드로이드는 `onViewCreated` 에서 `renderRingerState(loading = true)`(:243)를 한 뒤 아이가 없으면 `subscribe` 가 곧장 돌아가(:275-279) "확인하는 중이에요"가 영원히 남는다. iOS 는 아이가 없으면 로딩을 끄고 `control_ringer_status_unknown` 을 보인다. 안드로이드 결함은 개발일지에만 적는다.
6. **알람 시각 고르기.** 안드로이드 `MaterialTimePicker`(24시간 고정, :417-426)의 확인·취소 버튼은 시스템 문구다. iOS 는 새 키를 만들지 않도록 시스템 `DatePicker(.compact)` 를 `en_GB` 로캘(24시간)로 쓰고, 그 라벨에 같은 화면의 `control_alarm_picker_title` 을 쓴다. 고른 값이 즉시 반영되는 것(취소 없음)이 유일한 차이다.
7. **`AlarmMemoStore` 키 이름.** 안드로이드는 전용 prefs 파일(`kidcare_alarm_memo`)을 쓰지만 iOS 는 `RoleStore`·`RequestLog` 와 같은 `UserDefaults.standard` 를 쓰므로 키에 `alarm_memo_` 접두사를 붙여 충돌을 막는다.

---

## File Structure

```
ios/KidCare/
├─ RouterView.swift                    수정. ChildMapView → GuardianRootView
├─ Core/
│  ├─ Documents.swift                  수정. CommandType 확장·RingerMode·Dnd·NetworkKind·RingerSettingsDoc,
│  │                                    StatusCard.signal/elapsed
│  └─ ScheduleRepository.swift         신규. settings/ringer 구독·잠금 저장(안드로이드 ScheduleRepository 짝)
├─ Onboarding/
│  ├─ InviteCodeField.swift            신규. 코드 입력칸 키보드·길이 제한
│  └─ JoinFamilyView.swift             수정. 위를 쓴다
└─ Guardian/
   ├─ GuardianTab.swift                신규. 탭 다섯의 순서·이름·그림
   ├─ GuardianRootView.swift           신규. TabView·배너·뷰모델 수명(안드로이드 GuardianMainActivity 짝)
   ├─ KidCarePalette.swift             신규. colors.xml 값
   ├─ DisconnectBanner.swift           신규. 배너 판정 모델 + 뷰
   ├─ FirstToFinish.swift              신규. MapViewModel 에서 옮긴 "발행 15초" 경주(두 뷰모델이 함께 쓴다)
   ├─ AlarmMemoStore.swift             신규. 안드로이드 AlarmMemoStore 짝
   ├─ ControlViewModel.swift           신규. 관리 탭 상태 기계
   ├─ ControlView.swift                신규. 관리 탭 화면
   ├─ ChildMapView.swift               수정. 뷰모델을 받기만, 첫 읽기 한 번, 안전 영역
   ├─ MapViewModel.swift               수정. 처음이면_읽는다·대답이_기록되면·상태 기반 대답
   └─ RequestLog.swift                 수정. 주석만(배너가 생겼다)
ios/KidCareTests/
├─ TestDoubles.swift                   신규. 테스트 공용 문·신호·시계·가짜 리스너
├─ EmulatorHarness.swift               수정. 자녀 세션 도우미를 CommandRepositoryTests 에서 옮겨 온다
├─ CommandRepositoryTests.swift        수정. 옮긴 도우미를 부른다
├─ LocalizableCatalogTests.swift       신규
├─ GuardianTabTests.swift              신규
├─ MapTabLifecycleTests.swift          신규
├─ StatusCardTests.swift               수정. elapsed 경계
├─ DisconnectBannerTests.swift         신규
├─ MapBannerWiringTests.swift          신규
├─ ScheduleRepositoryTests.swift       신규(에뮬레이터)
├─ AlarmMemoStoreTests.swift           신규
├─ ControlViewModelTests.swift         신규
├─ ControlClockTests.swift             신규
└─ InviteCodeFieldTests.swift          신규
i18n/ko.json, i18n/en.json             수정. ios_tab_not_ready_body 하나
ios/KidCare/Localizable.xcstrings      수정. 공통 절차 A
README.md                              수정(Task 6). 개발일지·함께 고쳐야 하는 짝
```

---
### Task 1: 탭 다섯 — 지도는 그대로 살아 있고, 나머지는 자리표시

**끝나면 하단에 지도·알림·관리·예약·장소 다섯 탭이 안드로이드와 같은 순서로 뜬다.** 지도 탭은 기존 `ChildMapView` 이고, 다른 탭을 봤다 돌아와도 다시 읽지 않으며 실시간 보기도 꺼지지 않는다.

**Files:**
- Create: `ios/KidCare/Guardian/GuardianTab.swift`
- Create: `ios/KidCare/Guardian/KidCarePalette.swift`
- Create: `ios/KidCare/Guardian/GuardianRootView.swift`
- Modify: `ios/KidCare/Guardian/ChildMapView.swift` (init·첫 읽기·onDisappear·안전 영역)
- Modify: `ios/KidCare/Guardian/MapViewModel.swift` (`처음이면_읽는다()` 추가)
- Modify: `ios/KidCare/RouterView.swift:47-48`
- Modify: `i18n/ko.json`, `i18n/en.json`, `ios/KidCare/Localizable.xcstrings`
- Create: `ios/KidCareTests/TestDoubles.swift`, `ios/KidCareTests/LocalizableCatalogTests.swift`, `ios/KidCareTests/GuardianTabTests.swift`, `ios/KidCareTests/MapTabLifecycleTests.swift`

**Interfaces:**
- Consumes: `MapViewModel.init(familyId:childUid:...)`, `MapViewModel.하루를_읽는다()`, `명령_추적을_정리한다()`, `실시간_추적을_정리한다()` (3단계)
- Produces:
  - `enum GuardianTab: String, CaseIterable, Identifiable { case map, alert, control, schedule, place }` + `var titleKey: String`, `var title: String`, `var systemImage: String`
  - `enum KidCarePalette` — `static let paper, paperCard, ink, inkSoft, sky, skySoft, onAccent, grass, grassSoft, berry, onBerry, berrySoft, onBerrySoft: Color`
  - `struct GuardianRootView: View { init(familyId: String, childUid: String?) }`
  - `ChildMapView.init(viewModel: MapViewModel)` (옛 `init(familyId:childUid:)` 는 지운다)
  - `@discardableResult func MapViewModel.처음이면_읽는다() -> Task<Void, Never>`
  - 테스트 공용: `actor TestGate { func wait() async; func open() }`, `actor TestCounter { private(set) var value: Int; func next() -> Int }`, `enum TestDefaults { static func isolated(_ name: String) -> UserDefaults }`, `enum TestRepo { static func root() -> URL? }`, `@MainActor func eventually(timeoutSeconds: Double = 2, _ condition: () -> Bool) async`

**정본:** 탭 순서·이름·그림은 `res/menu/guardian_bottom_nav.xml:32-55` 와 `GuardianMainActivity.kt:93-99`. 시작 탭은 지도, 저장된 탭이 있으면 그것(`:170-175`, `onSaveInstanceState` :459-462 — iOS 에서는 `@SceneStorage`). 같은 탭을 다시 눌러도 아무 일 없음(`:162`). 하단 탭 색은 `themes.xml:186-195`(배경 `paper_card`, 선택 `sky`). 프래그먼트 자리는 하단 탭 **위**에서 끝난다(`activity_guardian_main.xml:85-89`, weight=1) — 지도가 탭 뒤로 들어가지 않는다.

**아이콘 대응.** `ic_tab_map`(접힌 지도) → `map`, `ic_tab_alert`(종 + 점, 점은 항상 그려져 있다) → `bell.badge`, `ic_tab_control`(슬라이더 셋) → `slider.horizontal.3`, `ic_tab_schedule`(시계) → `clock`, `ic_tab_place`(핀) → `mappin.and.ellipse`.

- [ ] **Step 1: 테스트 공용 도구를 만든다**

`ios/KidCareTests/TestDoubles.swift`:

```swift
import Foundation
import Testing

/// 여러 스위트가 함께 쓰는 테스트 도구. `MapViewModelTests`·`LiveTrackingTests` 안에
/// 같은 발상의 `Gate` 가 각자 중첩 타입으로 있다 — 이름이 겹쳐 가려지지 않게 모두
/// `Test` 접두사를 붙여 파일 스코프에 둔다(기존 중첩 타입은 건드리지 않는다).

/// 테스트가 열어줄 때까지 매달려 있는 문. 한 번 열리면 계속 열려 있다.
actor TestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// 몇 번 불렸는지 센다. `@Sendable` 클로저 안에서 지역 `var` 를 세면 Swift 6 가 막는다.
actor TestCounter {
    private(set) var value = 0
    @discardableResult
    func next() -> Int {
        value += 1
        return value
    }
}

/// 테스트마다 격리된 `UserDefaults`. 기본 저장소에 쓰면 시뮬레이터의 진짜 앱 상태가
/// 오염된다(3단계 리뷰 M2 가 실제로 찾아낸 흔적).
enum TestDefaults {
    static func isolated(_ name: String) -> UserDefaults {
        UserDefaults(suiteName: "\(name)-\(UUID().uuidString)")!
    }
}

/// `i18n/` 과 `ios/` 를 함께 가진 저장소 루트. `I18nKeyParityTests.repoRoot()` 와 같은
/// 발상 — 시뮬레이터 테스트 프로세스의 작업 디렉터리는 믿을 수 없어 소스 경로에서 찾는다.
enum TestRepo {
    static func root(filePath: String = #filePath) -> URL? {
        var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        while true {
            let fm = FileManager.default
            if fm.fileExists(atPath: dir.appendingPathComponent("i18n").path),
               fm.fileExists(atPath: dir.appendingPathComponent("ios").path) {
                return dir
            }
            let parent = dir.deletingLastPathComponent()
            if parent == dir { return nil }
            dir = parent
        }
    }
}

/// 조건이 참이 될 때까지 메인 액터를 양보하며 기다린다. 뷰모델은 Firestore 콜백을
/// `Task { @MainActor in }` 로 건너오므로, 콜백을 부른 직후 곧바로 상태를 보면
/// 아직 안 바뀌어 있다. 시간이 다 되면 실패를 기록한다.
@MainActor
func eventually(timeoutSeconds: Double = 2, _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    Issue.record("조건이 \(timeoutSeconds)초 안에 참이 되지 않았다")
}
```

- [ ] **Step 2: 카탈로그·탭·지도 수명 테스트를 먼저 쓴다**

`ios/KidCareTests/LocalizableCatalogTests.swift`:

```swift
import Foundation
import Testing

/// `Localizable.xcstrings` 는 6단계 전까지 `i18n/ko.json` 에서 손(계획서 공통 절차 A 의
/// 명령)으로 옮긴다. 옮긴 값이 원본과 어긋나지 않았는지, 코드가 부르는 원본 키가
/// 카탈로그에서 빠지지 않았는지를 여기서 기계로 본다 — 빠진 키는 화면에 키 이름
/// 그대로("control_find_hint") 뜨는데 빌드도 다른 테스트도 그걸 못 잡는다.
struct LocalizableCatalogTests {

    /// 1단계에서 화면에 맞춰 손으로 고친 값이 남은 키. `PairingUITests` 가 이 문구로
    /// 버튼을 찾아서 지금 고치면 실기기 자동화가 깨진다. 6단계가 원본에서 생성할 때
    /// 정리한다 — **여기에 새 키를 더하지 않는다.**
    static let 알려진_어긋남: Set<String> = ["guardian_start_join_family", "map_no_child", "role_guardian"]

    /// 안드로이드 서식 → iOS 서식. `%1$s`→`%1$@`, 숫자 서식은 그대로, 서식이 아닌 `%` 는 `%%`.
    static func 카탈로그_값(_ source: String) -> String {
        let 서식 = #/%(\d+\$)?(\d+)?([sd])/#
        var result = ""
        var rest = source[...]
        while let i = rest.firstIndex(of: "%") {
            result += rest[..<i]
            let tail = rest[i...]
            if let m = tail.prefixMatch(of: 서식) {
                let position = m.output.1.map(String.init) ?? ""
                let width = m.output.2.map(String.init) ?? ""
                result += "%" + position + width + (m.output.3 == "s" ? "@" : "d")
                rest = tail[m.range.upperBound...]
            } else if tail.hasPrefix("%%") {
                result += "%%"
                rest = tail.dropFirst(2)
            } else {
                result += "%%"
                rest = tail.dropFirst()
            }
        }
        return result + rest
    }

    private func json(_ relative: String) throws -> [String: Any] {
        let root = try #require(TestRepo.root(), "저장소 루트를 못 찾았다")
        let data = try Data(contentsOf: root.appendingPathComponent(relative))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func 카탈로그() throws -> [String: String] {
        let strings = try #require(try json("ios/KidCare/Localizable.xcstrings")["strings"] as? [String: [String: Any]])
        var out: [String: String] = [:]
        for (key, entry) in strings {
            let ko = (entry["localizations"] as? [String: Any])?["ko"] as? [String: Any]
            out[key] = (ko?["stringUnit"] as? [String: Any])?["value"] as? String
        }
        return out
    }

    @Test("서식 변환 규칙은 기존 카탈로그가 쓴 규칙과 같다")
    func 서식_변환() {
        #expect(Self.카탈로그_값("마지막 신호 %1$s") == "마지막 신호 %1$@")
        #expect(Self.카탈로그_값("%1$02d:%2$02d") == "%1$02d:%2$02d")
        #expect(Self.카탈로그_값("배터리 %1$d%\n%2$s 기준") == "배터리 %1$d%%\n%2$@ 기준")
        #expect(Self.카탈로그_값("%1$s '%2$s'") == "%1$@ '%2$@'")
    }

    @Test("카탈로그의 모든 한국어 값은 i18n/ko.json 에서 변환 규칙대로 나왔다")
    func 카탈로그는_원본에서_나온다() throws {
        let ko = try json("i18n/ko.json")
        for (key, value) in try 카탈로그() {
            let source = try #require(ko[key] as? String, "\(key) 가 i18n/ko.json 에 없다 — 카탈로그에만 있는 키는 6단계 생성 때 사라진다")
            if Self.알려진_어긋남.contains(key) { continue }
            #expect(value == Self.카탈로그_값(source), "\(key) 값이 원본과 다르다")
        }
    }

    @Test("앱 코드가 부르는 원본 키는 전부 카탈로그에 있다")
    func 코드가_부르는_키는_카탈로그에_있다() throws {
        let root = try #require(TestRepo.root())
        let ko = try json("i18n/ko.json")
        let catalog = try 카탈로그()
        let sources = try #require(FileManager.default.enumerator(at: root.appendingPathComponent("ios/KidCare"), includingPropertiesForKeys: nil))
        var missing: [String] = []
        for case let url as URL in sources where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in text.matches(of: #/"([a-z][a-z0-9_]+)"/#) {
                let key = String(match.output.1)
                if ko[key] != nil && catalog[key] == nil { missing.append("\(url.lastPathComponent): \(key)") }
            }
        }
        #expect(missing.isEmpty, "카탈로그에 없는 키: \(missing.joined(separator: ", "))")
    }

    @Test("공유 원본 i18n/*.json 에는 iOS 서식 %@ 가 없다")
    func 원본에는_iOS_서식이_없다() throws {
        for file in ["i18n/ko.json", "i18n/en.json"] {
            for (key, value) in try json(file) {
                #expect(!(value as? String ?? "").contains("@"), "\(file) 의 \(key) 에 %@ 류 서식이 있다")
            }
        }
    }
}
```

> 마지막 테스트의 `"@"` 검사가 너무 넓어 보이면: 지금 ko/en 원본에 `@` 문자가 들어간 문장이 하나도 없음을 확인했다. 앞으로 `@` 가 필요한 문장이 생기면 `%[0-9$]*@` 정규식으로 좁힌다.

`ios/KidCareTests/GuardianTabTests.swift`:

```swift
import Testing
@testable import KidCare

/// 정본은 `res/menu/guardian_bottom_nav.xml:32-55` 와 `GuardianMainActivity.kt:93-99`.
@MainActor
struct GuardianTabTests {

    @Test("탭 다섯은 안드로이드와 같은 순서·같은 문구 키다")
    func 순서와_문구() {
        #expect(GuardianTab.allCases.map(\.titleKey) == ["tab_map", "tab_alert", "tab_control", "tab_schedule", "tab_place"])
    }

    @Test("문구 키가 카탈로그에 있어 키 이름이 그대로 보이지 않는다")
    func 문구가_번역된다() {
        for tab in GuardianTab.allCases {
            #expect(tab.title != tab.titleKey, "\(tab.titleKey) 가 카탈로그에 없다")
        }
    }

    @Test("저장되는 값(rawValue)은 바뀌지 않는다 — @SceneStorage 가 이 문자열로 복원한다")
    func 저장값() {
        #expect(GuardianTab.allCases.map(\.rawValue) == ["map", "alert", "control", "schedule", "place"])
    }
}
```

`ios/KidCareTests/MapTabLifecycleTests.swift`:

```swift
import Foundation
import Testing
@testable import KidCare

/// 탭을 옮겼다 돌아와도 지도 화면이 처음 읽기를 반복하지 않는지 본다. 정본은 안드로이드
/// `GuardianMainActivity.showTab`(:329-353) — show/hide 라 `MapTimelineFragment.load` 는
/// 화면이 처음 만들어질 때 한 번뿐이다.
///
/// `하루를_읽는다()` 가 아이 이름·서버 시각을 진짜 `FamilyRepository` 로 읽으므로(주입
/// 안 됨) Firebase 가 구성돼 있어야 한다 — 에뮬레이터를 쓴다(운영에 안 닿는다).
@Suite(.serialized)
@MainActor
struct MapTabLifecycleTests {

    init() async { await EmulatorHarness.start() }

    private static func 상태(battery: Int) -> ChildStatusDoc {
        ChildStatusDoc(["lat": 37.0, "lng": 127.0, "battery": battery, "lastSeenAt": Int64(1)])!
    }

    @Test("onAppear 가 여러 번 불려도(탭을 오갈 때마다) 하루 읽기는 한 번뿐이다")
    func 처음_한_번만_읽는다() async {
        let 횟수 = TestCounter()
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: RequestLog(defaults: TestDefaults.isolated("MapTabLifecycleTests")),
            dayLoad: { _, _, _ in await 횟수.next(); return (nil, nil) }
        )
        let 첫번째 = vm.처음이면_읽는다()
        let 두번째 = vm.처음이면_읽는다()
        await 첫번째.value
        await 두번째.value
        await vm.처음이면_읽는다().value
        #expect(await 횟수.value == 1)
    }

    @Test("부른 쪽이 취소돼도(탭 전환으로 .task 가 취소되는 경우) 첫 읽기는 끝까지 간다")
    func 부른_쪽이_취소돼도_끝난다() async {
        let 문 = TestGate()
        let vm = MapViewModel(
            familyId: "family", childUid: "child",
            requestLog: RequestLog(defaults: TestDefaults.isolated("MapTabLifecycleTests")),
            dayLoad: { _, _, _ in await 문.wait(); return (Self.상태(battery: 42), nil) }
        )
        let 부른_쪽 = Task { @MainActor in await vm.처음이면_읽는다().value }
        부른_쪽.cancel()
        await 문.open()
        await vm.처음이면_읽는다().value
        #expect(vm.상태?.battery == 42)
    }
}
```

- [ ] **Step 3: 실패 확인**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/GuardianTabTests -only-testing:KidCareTests/MapTabLifecycleTests -only-testing:KidCareTests/LocalizableCatalogTests`
Expected: 컴파일 실패 — `GuardianTab`·`처음이면_읽는다` 가 없다. (`LocalizableCatalogTests` 네 개는 따로 돌리면 지금 이미 초록이어야 한다 — 기존 카탈로그 확인 결과와 같다.)

- [ ] **Step 4: 문구 키를 더한다**

`i18n/ko.json` 과 `i18n/en.json` 의 `"ios_child_unsupported_title"` 줄 **바로 아래**에, 이웃 줄과 같은 들여쓰기로 한 줄씩 더한다. 알림·예약·장소 탭 자리표시에만 쓰는 iOS 전용 키다(설계서 §4 의 `ios_` 접두사 규칙, `ios_child_unsupported_*` 와 같다). 5·6단계가 그 탭을 채우면 이 키를 지운다.

```json
  "ios_tab_not_ready_body": "이 탭은 아이폰 앱에 곧 들어와요. 그동안은 안드로이드 보호자 폰에서 쓸 수 있어요.",
```

```json
  "ios_tab_not_ready_body": "This tab is coming to the iPhone app soon. Until then, use it on an Android parent phone.",
```

그리고 공통 절차 A 를 `KEYS="tab_map tab_alert tab_control tab_schedule tab_place ios_tab_not_ready_body"` 로 돌린다.

- [ ] **Step 5: 탭 정의와 색표**

`ios/KidCare/Guardian/GuardianTab.swift`:

```swift
import Foundation

/// 보호자 하단 탭 다섯. 순서·문구·그림의 정본은 안드로이드 `res/menu/guardian_bottom_nav.xml`
/// (:32-55)과 `GuardianMainActivity.tabs`(:93-99)다. 다섯을 접지 않은 이유(칸 너비)도
/// 그 XML 주석에 있다 — 여기서 순서를 바꾸면 두 폰을 함께 쓰는 부모가 같은 자리에서
/// 다른 탭을 누르게 된다.
///
/// `rawValue` 는 `@SceneStorage` 가 저장하는 값이다. 바꾸면 저장된 선택 탭을 못 읽는다
/// (안드로이드가 탭 태그를 상수로 박아둔 이유와 같다, :74-76).
enum GuardianTab: String, CaseIterable, Identifiable {
    case map, alert, control, schedule, place

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .map: "tab_map"
        case .alert: "tab_alert"
        case .control: "tab_control"
        case .schedule: "tab_schedule"
        case .place: "tab_place"
        }
    }

    var title: String { String(localized: String.LocalizationValue(titleKey)) }

    /// 안드로이드 `ic_tab_*` 그림에 가장 가까운 SF Symbol.
    var systemImage: String {
        switch self {
        case .map: "map"
        case .alert: "bell.badge"
        case .control: "slider.horizontal.3"
        case .schedule: "clock"
        case .place: "mappin.and.ellipse"
        }
    }
}
```

`ios/KidCare/Guardian/KidCarePalette.swift`:

```swift
import SwiftUI

/// 안드로이드 `res/values/colors.xml`(:4-23)의 값 그대로. 설계서 §4 "색과 치수는 안드로이드
/// 리소스에서 그대로 가져온다 — 눈대중으로 다시 고르지 않는다".
enum KidCarePalette {
    static let paper = Color(hex: 0xFFFBF6)
    static let paperCard = Color(hex: 0xFFFEFC)
    static let ink = Color(hex: 0x342D3F)
    static let inkSoft = Color(hex: 0x776E84)
    static let sky = Color(hex: 0x826DCC)
    static let skySoft = Color(hex: 0xEEE9FF)
    static let onAccent = Color(hex: 0xFFFFFF)
    static let grass = Color(hex: 0x7E9D68)
    static let grassSoft = Color(hex: 0xEDF4E7)
    static let berry = Color(hex: 0xE878AC)
    static let onBerry = Color(hex: 0x48152D)
    /// `themes.xml:22` 의 `colorErrorContainer` — 무응답 배너 바탕.
    static let berrySoft = Color(hex: 0xFDE8F2)
    /// `themes.xml:23` 의 `colorOnErrorContainer` — 무응답 배너 글자.
    static let onBerrySoft = Color(hex: 0x5B213C)
}

private extension Color {
    /// sRGB 로 명시한다 — 앱 아이콘 작업에서 색공간을 안 적었다가 `#CFEDE7` 이
    /// `#D7F0EC` 로 나온 일이 있다(README 2단계 개발일지).
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
```

- [ ] **Step 6: `MapViewModel` 에 첫 읽기 한 번을 더한다**

`ios/KidCare/Guardian/MapViewModel.swift` 의 `func 하루를_읽는다()`(:494) **바로 위**에:

```swift
    /// 첫 읽기 작업. `nil` 이면 아직 한 번도 시작하지 않았다.
    private var 처음_읽기: Task<Void, Never>?

    /// 화면이 보일 때마다 불러도 되는 첫 읽기. 정본은 안드로이드 `MapTimelineFragment.load`
    /// 가 `onViewCreated` 에서 한 번만 도는 것 — 탭은 show/hide 라 다시 보여도 다시 읽지
    /// 않는다(`GuardianMainActivity.kt:329-353`).
    ///
    /// **`.task` 가 아니라 뷰모델이 소유한 비구조적 Task 인 이유:** `TabView` 는 탭을 옮길
    /// 때마다 `.task` 를 취소한다. 첫 읽기 도중 부모가 관리 탭을 누르면 `serverNow` 가
    /// 취소를 받아 아이 이름·서버 시각을 못 채운 채 끝나고, 한 번만 읽는다는 규칙 때문에
    /// 다시 기회가 없다. 뷰의 수명과 떼어 둔다.
    @discardableResult
    func 처음이면_읽는다() -> Task<Void, Never> {
        if let 처음_읽기 { return 처음_읽기 }
        let 작업 = Task { await self.하루를_읽는다() }
        처음_읽기 = 작업
        return 작업
    }
```

- [ ] **Step 7: `ChildMapView` 가 뷰모델을 받기만 하게 한다**

`ios/KidCare/Guardian/ChildMapView.swift`:

1. `let familyId: String`, `let childUid: String?`, `@State private var viewModel: MapViewModel` 과 `init(familyId:childUid:)`(:18-31)를 지우고 아래로 바꾼다.

```swift
    /// 뷰모델은 `GuardianRootView` 가 소유한다 — 탭을 오가도 같은 인스턴스가 살아 있어야
    /// 명령 추적·실시간 세션이 끊기지 않는다(안드로이드 show/hide 와 같은 수명).
    let viewModel: MapViewModel

    init(viewModel: MapViewModel) {
        self.viewModel = viewModel
    }
```

2. 본문의 `childUid` 두 곳(`hasChild: childUid != nil` :74, `.disabled(childUid == nil)`·`.opacity(childUid == nil ...)` :165-168)을 `viewModel.childUid` 로 바꾼다.
3. `NaverMapView(...)` 뒤의 `.ignoresSafeArea()`(:60)를 `.ignoresSafeArea(edges: .top)` 으로 바꾸고, `GeometryReader` 끝의 `.ignoresSafeArea(.container, edges: .bottom)`(:100)을 **지운다.** 이유: `TabView` 안에서 아래쪽 안전 영역은 탭 바다. 그대로 두면 타임라인 패널과 네이버 로고가 탭 바 뒤로 들어간다 — 로고가 가려지면 지도 SDK 약관 위반이고(3단계 Task 6 Step 5), 안드로이드도 프래그먼트 자리가 하단 탭 위에서 끝난다(`activity_guardian_main.xml:85-89`). 코드에 이 이유를 한 줄 주석으로 남긴다.
4. `.task { await viewModel.하루를_읽는다() }`(:104)를 `.onAppear { viewModel.처음이면_읽는다() }` 로 바꾼다. 위 주석 블록(:102-103)도 "첫 읽기는 뷰모델이 한 번만 — `처음이면_읽는다` 주석"으로 고친다.
5. `.onDisappear { ... }` 블록(:109-118)을 **통째로 지우고** 그 자리에 주석만 남긴다:

```swift
        // 명령·실시간 리스너 정리는 여기서 하지 않는다 — TabView 는 탭을 옮길 때마다
        // onDisappear 를 부르므로, 여기서 떼면 관리 탭을 한 번 눌렀을 뿐인데 실시간
        // 보기가 꺼진다. 안드로이드는 onDestroyView 에서만 뗀다(MapTimelineFragment.kt
        // :1299-1311). 정리는 GuardianRootView.onDisappear 가 한다.
```

`.task { await viewModel.시계를_돈다() }` 는 그대로 둔다 — Firestore 를 안 타는 60초 시계라 탭을 떠나면 멈추고 돌아오면 다시 도는 것이 맞다.

- [ ] **Step 8: `GuardianRootView` 와 라우터**

`ios/KidCare/Guardian/GuardianRootView.swift`:

```swift
import SwiftUI

/// 보호자 본 화면 — 하단 탭 다섯의 컨테이너. 정본은 안드로이드 `GuardianMainActivity`.
///
/// **탭마다의 뷰모델을 여기서 소유한다.** 안드로이드는 프래그먼트를 태그로 찾아 두고
/// show/hide 로만 오가서(`:39-42`, `showTab` :329-353), 다른 탭을 보는 동안에도 지도
/// 프래그먼트의 명령 추적·실시간 세션이 살아 있다. SwiftUI `TabView` 도 탭 뷰의 상태는
/// 살려 두지만 탭을 옮길 때마다 `onDisappear` 를 부르므로, 수명이 걸린 정리는 탭 뷰가
/// 아니라 이 뷰의 `onDisappear`(= 안드로이드 `onDestroyView` 자리)에 둔다.
struct GuardianRootView: View {

    @State private var mapViewModel: MapViewModel
    /// 안드로이드 `onSaveInstanceState` 의 `KEY_SELECTED_TAB`(:459-462) 자리. 처음엔 지도(:172).
    @SceneStorage("guardian.selectedTab") private var selectedTab: GuardianTab = .map

    init(familyId: String, childUid: String?) {
        _mapViewModel = State(initialValue: MapViewModel(familyId: familyId, childUid: childUid))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ChildMapView(viewModel: mapViewModel)
                .tabItem { Label(GuardianTab.map.title, systemImage: GuardianTab.map.systemImage) }
                .tag(GuardianTab.map)
            TabPlaceholderView(tab: .alert)
                .tabItem { Label(GuardianTab.alert.title, systemImage: GuardianTab.alert.systemImage) }
                .tag(GuardianTab.alert)
            TabPlaceholderView(tab: .control)
                .tabItem { Label(GuardianTab.control.title, systemImage: GuardianTab.control.systemImage) }
                .tag(GuardianTab.control)
            TabPlaceholderView(tab: .schedule)
                .tabItem { Label(GuardianTab.schedule.title, systemImage: GuardianTab.schedule.systemImage) }
                .tag(GuardianTab.schedule)
            TabPlaceholderView(tab: .place)
                .tabItem { Label(GuardianTab.place.title, systemImage: GuardianTab.place.systemImage) }
                .tag(GuardianTab.place)
        }
        // themes.xml:186-195 — 탭 띠 바탕 paper_card, 선택 항목 sky. 지도 위에서도 탭 띠가
        // 투명해지지 않게 바탕을 늘 보이게 둔다(안드로이드는 그림자 대신 선으로 띠를 뗀다).
        .tint(KidCarePalette.sky)
        .toolbarBackground(KidCarePalette.paperCard, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onDisappear {
            mapViewModel.명령_추적을_정리한다()
            mapViewModel.실시간_추적을_정리한다()
        }
    }
}

/// 아직 이 앱에 없는 탭(알림 6단계, 예약·장소 5단계)의 자리. 탭 바가 안드로이드와 같은
/// 모양이 되도록 칸만 먼저 채운다.
private struct TabPlaceholderView: View {
    let tab: GuardianTab

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 40))
                .foregroundStyle(KidCarePalette.sky)
            Text(tab.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(KidCarePalette.ink)
            Text("ios_tab_not_ready_body")
                .font(.subheadline)
                .foregroundStyle(KidCarePalette.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KidCarePalette.paper)
    }
}
```

`ios/KidCare/RouterView.swift:47-48`:

```swift
        } else if showMain, let familyId = store.familyId {
            GuardianRootView(familyId: familyId, childUid: store.childUid)
```

그리고 `RouterView` 타입 주석의 `ChildMapView` 언급(:13, :27)을 `GuardianRootView` 로 고친다.

- [ ] **Step 9: 통과 확인**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: 전체 PASS(기존 known issues 는 그대로). 새 테스트 9개 포함.

- [ ] **Step 10: 커밋** (공통 절차 B)

```bash
git add ios/KidCare/Guardian/GuardianTab.swift ios/KidCare/Guardian/KidCarePalette.swift ios/KidCare/Guardian/GuardianRootView.swift \
  ios/KidCare/Guardian/ChildMapView.swift ios/KidCare/Guardian/MapViewModel.swift ios/KidCare/RouterView.swift \
  i18n/ko.json i18n/en.json ios/KidCare/Localizable.xcstrings \
  ios/KidCareTests/TestDoubles.swift ios/KidCareTests/LocalizableCatalogTests.swift ios/KidCareTests/GuardianTabTests.swift ios/KidCareTests/MapTabLifecycleTests.swift
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "iOS 4단계 Task 1: 탭 다섯 — 지도는 탭을 오가도 살아 있고 나머지는 자리표시"
```

---

### Task 2: 무응답 배너 — 어느 탭을 보든 같은 자리에 같은 문장

**끝나면 '지금 위치 확인'에 30분 넘게 대답이 없을 때 모든 탭 맨 위에 "오후 N분 전 보낸 요청에 애기폰이 아직 대답하지 않았어요…" 배너가 뜨고, 대답이 오면 곧바로 사라진다.**

**Files:**
- Modify: `ios/KidCare/Core/Documents.swift:255-317` (`enum StatusCard` — `signal(status:)`·`elapsed(millis:)` 를 열고 `lastSignal` 이 그 둘을 지나가게)
- Create: `ios/KidCare/Guardian/DisconnectBanner.swift`
- Modify: `ios/KidCare/Guardian/MapViewModel.swift` (`대답이_기록되면`, 상태 기반 대답)
- Modify: `ios/KidCare/Guardian/RequestLog.swift:22-24` (주석)
- Modify: `ios/KidCare/Guardian/GuardianRootView.swift`
- Modify: `ios/KidCare/Localizable.xcstrings`
- Modify: `ios/KidCareTests/TestDoubles.swift` (`TestSignal`·`TestClock`·`TestListenerRegistration`·`TestCallbackBox` 추가)
- Test: `ios/KidCareTests/StatusCardTests.swift`, `ios/KidCareTests/DisconnectBannerTests.swift`, `ios/KidCareTests/MapBannerWiringTests.swift`

**Interfaces:**
- Consumes: `DisconnectRule.isDisconnected(lastRequestAt:lastAnswerAt:nowMillis:)`·`thresholdMillis`(2단계), `RequestLog`(3단계), `lastSignalText(_:)`(`StatusCardView.swift:121`), Task 1 의 `GuardianRootView`·`KidCarePalette`·`TestDefaults`·`TestGate`·`TestCounter`·`eventually`
- Produces:
  - `static func StatusCard.signal(status: ChildStatusDoc) -> (atMillis: Int64, fromServerClock: Bool)?`
  - `static func StatusCard.elapsed(millis: Int64) -> LastSignal` (음수는 0 으로)
  - `@MainActor @Observable final class DisconnectBanner` — `init(childUid:requestLog:deviceNow:sleep:)`, `private(set) var 문구: String?`, `func 다시_판정한다()`, `func 주기적으로_판정한다() async`, `nonisolated static let recheckMillis: Int64 = 60_000`
  - `struct DisconnectBannerView: View { let text: String }`
  - `var MapViewModel.대답이_기록되면: (@MainActor () -> Void)?`
  - 테스트 공용: `actor TestSignal { func wait() async; func fire() }`, `final class TestClock: Sendable { init(_ millis: Int64); var value: Int64; func advance(_ millis: Int64) }`, `final class TestListenerRegistration: NSObject, ListenerRegistration, @unchecked Sendable { var removed: Bool }`, `final class TestCallbackBox<T>: @unchecked Sendable { func set(_:); var value: T? }`

**정본:**
- 배너 자리와 판정: `GuardianMainActivity.kt:44-64`(주석), `renderBanner` :441-457, `activity_guardian_main.xml:65-83`(프래그먼트 **밖**, 탭보다 위, `colorErrorContainer`, 가로 16dp·세로 14dp 여백, `textAppearanceBodyMedium`).
- 1분마다 다시 판정: `bannerJob` :113-121, `onStart` :395-404, `onStop` :415-421, `BANNER_RECHECK_MILLIS = 60 * 1000L` :483. 화면이 안 보이는 동안(`onStop`)은 돌지 않는다 — iOS 에서는 `scenePhase != .active`.
- 대답을 받으면 즉시 다시 판정: `refreshBanner` :381-393 ← `MapTimelineFragment.recordAnswer` :682-685, `ControlFragment.recordAnswer` :747-750.
- 판정 기준 시각은 **기기 시계**(`:437-439`, `RequestLog.kt:17-23`). 경과 문구는 `LastSignalText.elapsedText` :551-556.
- 물은 뒤에 쓰인 상태 문서는 대답이다: `MapTimelineFragment.renderStatus` :750-757 — iOS 는 3단계에서 이 줄을 안 옮겼다. 안 옮기면 아이 폰의 하루 한 번 안전 업로드가 이미 올라왔는데도 배너가 옛 물음을 근거로 계속 뜬다.

- [ ] **Step 1: 테스트 공용 도구를 더한다** — `ios/KidCareTests/TestDoubles.swift` 끝에 붙인다. 파일 맨 위 import 에 `import FirebaseFirestore` 와 `import os` 를 더한다.

```swift
/// 딱 한 번 발화하는 신호 — "이 지점을 실제로 지났다"를 테스트에 알린다. `Task.yield()`
/// 횟수로 순서를 가정하지 않기 위해서다(3단계 리뷰 I2).
actor TestSignal {
    private var fired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if fired { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func fire() {
        guard !fired else { return }
        fired = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// 테스트가 움직이는 시계(UTC 밀리초). `@Sendable` 클로저에서 읽히므로 잠금으로 지킨다 —
/// `OSAllocatedUnfairLock` 이 Sendable 이라 `@unchecked` 가 필요 없다.
final class TestClock: Sendable {
    private let lock: OSAllocatedUnfairLock<Int64>
    init(_ millis: Int64) { lock = OSAllocatedUnfairLock(initialState: millis) }
    var value: Int64 { lock.withLock { $0 } }
    func advance(_ millis: Int64) { lock.withLock { $0 += millis } }
}

/// 진짜 `ListenerRegistration` 흉내. `remove()` 가 불렸는지 본다.
///
/// **`@unchecked Sendable` 은 테스트 타깃에만 있다**(`MapViewModelTests.FakeListenerRegistration`
/// 과 같은 이유) — 프로토콜이 `NSObjectProtocol` 과 동기 `remove()` 를 요구해 actor 로 못
/// 만들고, 잠금으로 직접 지킨다.
final class TestListenerRegistration: NSObject, ListenerRegistration, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)
    var removed: Bool { lock.withLock { $0 } }
    func remove() { lock.withLock { $0 = true } }
}

/// Firestore 콜백 클로저(비 Sendable)를 `@Sendable` 가짜 저장소 밖으로 꺼내 두는 상자.
/// 테스트 전용 — 위와 같은 이유로 잠금으로 지킨다.
final class TestCallbackBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?
    func set(_ value: T) { lock.withLock { stored = value } }
    var value: T? { lock.withLock { stored } }
}
```

- [ ] **Step 2: 실패하는 테스트를 쓴다**

`ios/KidCareTests/StatusCardTests.swift` 의 `struct StatusCardTests` 안 끝에 더한다:

```swift
    @Test("경과를 분·시간·일로 나누는 경계는 안드로이드 LastSignalText.elapsedText 와 같다")
    func 경과_경계() {
        #expect(StatusCard.elapsed(millis: 59_999) == .minutes(0))
        #expect(StatusCard.elapsed(millis: 60_000) == .minutes(1))
        #expect(StatusCard.elapsed(millis: 3_599_999) == .minutes(59))
        #expect(StatusCard.elapsed(millis: 3_600_000) == .hours(1))
        #expect(StatusCard.elapsed(millis: 86_399_999) == .hours(23))
        #expect(StatusCard.elapsed(millis: 86_400_000) == .days(1))
        // 음수의 뜻은 부르는 쪽이 정한다(:550) — 여기서는 0 으로 끌어올리기만 한다.
        #expect(StatusCard.elapsed(millis: -5_000) == .minutes(0))
    }

    @Test("signal 은 서버 시각을 먼저, 없으면 아이 폰 시각을, 둘 다 없으면 nil 을 준다")
    func 신호_출처() {
        let serverAt: Int64 = 1_757_000_000_000
        let 서버 = StatusCard.signal(status: status(
            lastSeenAt: serverAt - 3_600_000,
            lastSeenServerAt: Timestamp(date: Date(timeIntervalSince1970: Double(serverAt) / 1000))
        ))
        #expect(서버?.atMillis == serverAt)
        #expect(서버?.fromServerClock == true)
        let 기기 = StatusCard.signal(status: status(lastSeenAt: 42))
        #expect(기기?.atMillis == 42)
        #expect(기기?.fromServerClock == false)
        #expect(StatusCard.signal(status: status(lastSeenAt: 0)) == nil)
    }
```

`ios/KidCareTests/DisconnectBannerTests.swift`:

```swift
import Foundation
import Testing
@testable import KidCare

/// 정본은 안드로이드 `GuardianMainActivity.renderBanner`(:441-457)와 `bannerJob`(:395-404).
/// `RequestLog` 는 진짜 `Date()` 로 적으므로, "지금"만 가짜 시계로 앞으로 민다.
@MainActor
struct DisconnectBannerTests {

    private static let 분: Int64 = 60_000

    private func 기기_지금() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    @Test("한 번도 물어본 적이 없으면 뜨지 않는다")
    func 물어본_적_없으면_안_뜬다() {
        let log = RequestLog(defaults: TestDefaults.isolated("DisconnectBannerTests"))
        let banner = DisconnectBanner(childUid: "child", requestLog: log, deviceNow: { Int64(Date().timeIntervalSince1970 * 1000) + 2 * 60 * 60_000 })
        banner.다시_판정한다()
        #expect(banner.문구 == nil)
    }

    @Test("물어보고 31분 동안 대답이 없으면 뜨고, 문장에 '31분 전'이 들어간다")
    func 삼십일분_무응답이면_뜬다() {
        let log = RequestLog(defaults: TestDefaults.isolated("DisconnectBannerTests"))
        log.recordRequest("child")
        let banner = DisconnectBanner(childUid: "child", requestLog: log, deviceNow: { Int64(Date().timeIntervalSince1970 * 1000) + 31 * 60_000 })
        banner.다시_판정한다()
        let 기대 = String(format: String(localized: "guardian_disconnect_banner"), lastSignalText(.minutes(31)))
        #expect(banner.문구 == 기대)
        // 카탈로그에 키가 없으면 String(localized:) 가 키 이름을 그대로 돌려준다.
        #expect(banner.문구?.contains("guardian_disconnect_banner") == false)
    }

    @Test("29분이면 아직 뜨지 않는다 — 문턱은 DisconnectRule.thresholdMillis(30분)")
    func 이십구분이면_안_뜬다() {
        let log = RequestLog(defaults: TestDefaults.isolated("DisconnectBannerTests"))
        log.recordRequest("child")
        let banner = DisconnectBanner(childUid: "child", requestLog: log, deviceNow: { Int64(Date().timeIntervalSince1970 * 1000) + 29 * 60_000 })
        banner.다시_판정한다()
        #expect(banner.문구 == nil)
    }

    @Test("대답을 적고 다시 판정하면 곧바로 사라진다")
    func 대답이_오면_사라진다() {
        let log = RequestLog(defaults: TestDefaults.isolated("DisconnectBannerTests"))
        log.recordRequest("child")
        let clock = TestClock(기기_지금() + 31 * Self.분)
        let banner = DisconnectBanner(childUid: "child", requestLog: log, deviceNow: { clock.value })
        banner.다시_판정한다()
        #expect(banner.문구 != nil)
        log.recordAnswer("child")
        banner.다시_판정한다()
        #expect(banner.문구 == nil)
    }

    @Test("아이가 없으면 뜨지 않는다")
    func 아이가_없으면_안_뜬다() {
        let log = RequestLog(defaults: TestDefaults.isolated("DisconnectBannerTests"))
        log.recordRequest("child")
        let banner = DisconnectBanner(childUid: nil, requestLog: log, deviceNow: { Int64(Date().timeIntervalSince1970 * 1000) + 60 * 60_000 })
        banner.다시_판정한다()
        #expect(banner.문구 == nil)
    }

    @Test("아무 스냅샷이 없어도 시간이 흐르는 것만으로 다시 판정한다(안드로이드 bannerJob 주석)")
    func 시간만_흘러도_뜬다() async {
        let log = RequestLog(defaults: TestDefaults.isolated("DisconnectBannerTests"))
        log.recordRequest("child")
        let clock = TestClock(기기_지금())
        let 두번째_판정 = TestSignal()
        let 멈춤 = TestGate()
        let 횟수 = TestCounter()
        let banner = DisconnectBanner(
            childUid: "child", requestLog: log,
            deviceNow: { clock.value },
            sleep: { millis in
                #expect(millis == DisconnectBanner.recheckMillis)
                if await 횟수.next() == 1 {
                    clock.advance(31 * 60_000)
                } else {
                    await 두번째_판정.fire()
                    await 멈춤.wait()
                }
            }
        )
        let 반복 = Task { await banner.주기적으로_판정한다() }
        await 두번째_판정.wait()
        #expect(banner.문구 != nil)
        반복.cancel()
        await 멈춤.open()
        await 반복.value
    }
}
```

`ios/KidCareTests/MapBannerWiringTests.swift`:

```swift
import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 지도 탭이 대답을 적은 순간 배너가 다시 판정되는지, 그리고 물은 뒤 쓰인 상태 문서를
/// 대답으로 치는지(안드로이드 `MapTimelineFragment.kt:750-757`) 본다. `하루를_읽는다()` 가
/// 진짜 `FamilyRepository.serverNow` 를 부르므로 에뮬레이터를 쓴다.
@Suite(.serialized)
@MainActor
struct MapBannerWiringTests {

    init() async { await EmulatorHarness.start() }

    private static func 상태(lastSeenAt: Int64) -> ChildStatusDoc {
        ChildStatusDoc(["lat": 37.0, "lng": 127.0, "battery": 50, "lastSeenAt": lastSeenAt])!
    }

    @Test("명령이 failed 로 끝나면(실패도 대답이다) 대답을 적고 배너 판정을 곧바로 부른다")
    func 실패_대답이_배너를_부른다() async {
        let log = RequestLog(defaults: TestDefaults.isolated("MapBannerWiringTests"))
        let 콜백 = TestCallbackBox<(CommandDoc) -> Void>()
        let vm = MapViewModel(
            familyId: "family", childUid: "child", requestLog: log,
            commandSend: { _, _, _, _ in "cmd" },
            commandObserve: { _, _, _, onChange, _ in 콜백.set(onChange); return TestListenerRegistration() },
            commandSleep: { _ in await TestGate().wait() },
            dayLoad: { _, _, _ in (nil, nil) }
        )
        var 불린_횟수 = 0
        vm.대답이_기록되면 = { 불린_횟수 += 1 }

        await vm.지금_위치를_확인한다()
        콜백.value?(CommandDoc(id: "cmd", ["state": CommandState.failed, "error": "x"]))
        await eventually { 불린_횟수 == 1 }
        #expect(log.lastAnswerAt(childUid: "child") >= log.lastRequestAt(childUid: "child"))
    }

    @Test("물어본 뒤에 쓰인 상태 문서는 대답으로 친다")
    func 물은_뒤_상태는_대답이다() async {
        let log = RequestLog(defaults: TestDefaults.isolated("MapBannerWiringTests"))
        log.recordRequest("child")
        let 물은_시각 = log.lastRequestAt(childUid: "child")
        let vm = MapViewModel(
            familyId: "family", childUid: "child", requestLog: log,
            dayLoad: { _, _, _ in (Self.상태(lastSeenAt: 물은_시각 + 5_000), nil) }
        )
        var 불린_횟수 = 0
        vm.대답이_기록되면 = { 불린_횟수 += 1 }
        await vm.하루를_읽는다()
        #expect(log.lastAnswerAt(childUid: "child") >= 물은_시각)
        #expect(불린_횟수 >= 1)
    }

    @Test("물어보기 전에 쓰인 상태 문서는 대답이 아니다")
    func 물기_전_상태는_대답이_아니다() async {
        let log = RequestLog(defaults: TestDefaults.isolated("MapBannerWiringTests"))
        log.recordRequest("child")
        let 물은_시각 = log.lastRequestAt(childUid: "child")
        let vm = MapViewModel(
            familyId: "family", childUid: "child", requestLog: log,
            dayLoad: { _, _, _ in (Self.상태(lastSeenAt: 물은_시각 - 60_000), nil) }
        )
        var 불린_횟수 = 0
        vm.대답이_기록되면 = { 불린_횟수 += 1 }
        await vm.하루를_읽는다()
        #expect(log.lastAnswerAt(childUid: "child") == 0)
        #expect(불린_횟수 == 0)
    }
}
```

> 두 번째·세 번째 테스트의 비교는 서버 오프셋에 기댄다. 에뮬레이터 왕복은 수 ms 라 오프셋이 거의 0 이고, 비교 여유는 5초·60초다.

- [ ] **Step 3: 실패 확인**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/StatusCardTests -only-testing:KidCareTests/DisconnectBannerTests -only-testing:KidCareTests/MapBannerWiringTests`
Expected: 컴파일 실패 — `StatusCard.elapsed`·`DisconnectBanner`·`대답이_기록되면` 이 없다.

- [ ] **Step 4: `StatusCard` 를 둘로 연다**

`ios/KidCare/Core/Documents.swift` 의 `enum StatusCard { ... }`(:261-317) 전체를 아래로 바꾼다(위의 타입 주석 :255-260 은 그대로 둔다):

```swift
enum StatusCard {

    private static let minuteMillis: Int64 = 60_000
    private static let hourMillis: Int64 = 60 * minuteMillis
    private static let dayMillis: Int64 = 24 * hourMillis

    /// 마지막 신호의 **절대 시각과 그 시계의 출처**. 정본은 안드로이드
    /// `ChildStatusDoc.lastSignal()`(GuardianMainActivity.kt:505-510) — 서버 시각이 있으면
    /// 그것, 없으면 아이 폰 시계로 적은 옛 필드. `nil` 이면 쓸 만한 값이 없다.
    ///
    /// 경과(`lastSignal`)만 열어 두면 무응답 배너의 "물은 뒤에 쓰인 문서인가"
    /// (MapTimelineFragment.kt:757) 판단을 못 한다 — 그 판단은 시각 자체가 필요하다.
    static func signal(status: ChildStatusDoc) -> (atMillis: Int64, fromServerClock: Bool)? {
        if let serverAt = status.lastSeenServerAt {
            let millis = Int64(serverAt.dateValue().timeIntervalSince1970 * 1000)
            if millis > 0 { return (millis, true) }
        }
        if status.lastSeenAt > 0 { return (status.lastSeenAt, false) }
        return nil
    }

    /// `nowMillis` 는 **반드시 [FamilyRepository.serverNow] 로 잰 값**이어야 한다.
    /// 기기 시계로 빼면 부모 폰이 뒤처진 만큼 "마지막 신호 -3분 전" 같은 문구가
    /// 나온다 — 안드로이드 `ControlFragment` 주석과 같은 함정이다.
    static func lastSignal(status: ChildStatusDoc, nowMillis: Int64) -> LastSignal {
        guard let found = signal(status: status) else { return .never }
        let 경과 = nowMillis - found.atMillis
        // 음수 경과의 뜻은 시계 출처에 따라 다르다 — 코틀린 `LastSignalText.relativeText`
        // (:543-548) 와 같은 갈래. 서버 시각의 음수는 왕복 보정 오차뿐이라 "방금 전"이
        // 정직하고, 아이 폰 시각의 음수는 경과를 모른다는 뜻이라 절대 시각을 넘긴다.
        if 경과 < 0 {
            return found.fromServerClock ? .minutes(0) : .skewed(atMillis: found.atMillis)
        }
        return elapsed(millis: 경과)
    }

    /// 0 이상의 경과를 분·시간·일로 나눈다. 정본은 `LastSignalText.elapsedText`(:551-556).
    /// 음수의 뜻과 처리는 부르는 쪽이 정한다(:550) — 여기서는 0 으로 끌어올리기만 한다.
    /// 무응답 배너(`DisconnectBanner`)도 이 한 곳을 지나간다 — 관리 탭의 마지막 신호와
    /// 배너가 같은 사실을 다른 표기로 말하지 않게(:512-516).
    static func elapsed(millis: Int64) -> LastSignal {
        switch max(millis, 0) {
        case ..<minuteMillis: return .minutes(0)
        case ..<hourMillis: return .minutes(Int(millis / minuteMillis))
        case ..<dayMillis: return .hours(Int(millis / hourMillis))
        default: return .days(Int(millis / dayMillis))
        }
    }
}
```

- [ ] **Step 5: 배너 모델과 뷰**

공통 절차 A 를 `KEYS="guardian_disconnect_banner"` 로 돌린다(`%1$s` → `%1$@`, `\n` 은 JSON 이 이미 줄바꿈으로 풀어 둔다).

`ios/KidCare/Guardian/DisconnectBanner.swift`:

```swift
import Foundation
import Observation
import SwiftUI

/// "애기폰이 대답하지 않아요" 배너를 띄울지 판정한다. 정본은 안드로이드
/// `GuardianMainActivity.renderBanner`(:441-457)와 `bannerJob`(:113-121).
///
/// **탭마다 두지 않고 `GuardianRootView` 한 곳에 둔다**(:53-56) — 지도만 보는 부모도 봐야
/// 하고, 두 곳에서 판정하면 한쪽만 뜨는 어긋남이 생긴다.
///
/// **서버를 한 번도 안 건드린다.** 재료는 부모 폰 안의 `RequestLog` 뿐이고(:433-435),
/// 비교 시각도 기기 시계다 — 두 값을 적은 것도 이 폰 시계라 같은 시계끼리 빼는 쪽이
/// 정확하다(:437-439). 그래서 1분마다 다시 판정해도 통신 비용이 0 이다(:480-482).
@Observable
@MainActor
final class DisconnectBanner {

    /// 안드로이드 `BANNER_RECHECK_MILLIS = 60 * 1000L`(:483).
    nonisolated static let recheckMillis: Int64 = 60 * 1000

    /// `nil` 이면 배너를 감춘다.
    private(set) var 문구: String?

    private let childUid: String?
    private let requestLog: RequestLog
    private let deviceNow: @Sendable () -> Int64
    private let sleep: @Sendable (Int64) async -> Void

    init(
        childUid: String?,
        requestLog: RequestLog = RequestLog(),
        deviceNow: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        sleep: @escaping @Sendable (Int64) async -> Void = { millis in
            try? await Task.sleep(nanoseconds: UInt64(millis) * 1_000_000)
        }
    ) {
        self.childUid = childUid
        self.requestLog = requestLog
        self.deviceNow = deviceNow
        self.sleep = sleep
    }

    /// 지금 판정한다. 대답을 적은 직후에도 부른다 — 1분 주기만 믿으면 대답이 온 뒤에도
    /// 배너가 최대 1분 남아 부모 눈에는 고장이다(`refreshBanner` 주석 :388-389).
    func 다시_판정한다() {
        let lastRequestAt = requestLog.lastRequestAt(childUid: childUid)
        let now = deviceNow()
        let 끊겼다 = DisconnectRule.isDisconnected(
            lastRequestAt: lastRequestAt,
            lastAnswerAt: requestLog.lastAnswerAt(childUid: childUid),
            nowMillis: now
        )
        guard 끊겼다 else {
            문구 = nil
            return
        }
        문구 = String(
            format: String(localized: "guardian_disconnect_banner"),
            lastSignalText(StatusCard.elapsed(millis: now - lastRequestAt))
        )
    }

    /// 화면이 보이는 동안 1분마다 다시 판정한다. 이게 없으면 **완전히 멎어 아무 스냅샷도
    /// 안 오는 폰**에서 배너가 영영 안 뜬다(:116-119). 부르는 쪽이 앱이 활성일 때만
    /// 돌리고(`onStart`/`onStop` :395-421), 취소하면 멈춘다.
    func 주기적으로_판정한다() async {
        while !Task.isCancelled {
            다시_판정한다()
            await sleep(Self.recheckMillis)
        }
    }
}

/// 배너 한 줄. 정본은 `activity_guardian_main.xml:74-83` — 오류 컨테이너 색, 가로 16·세로 14.
struct DisconnectBannerView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(KidCarePalette.onBerrySoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            // 바탕은 상태바 뒤까지 채운다 — 안드로이드가 배너가 떠 있을 때만 상태바 높이를
            // 배너 여백에 더하는 것(applyTopInset :366-377)과 같은 모양.
            .background(KidCarePalette.berrySoft, ignoresSafeAreaEdges: .top)
    }
}
```

- [ ] **Step 6: 지도 탭이 대답을 알린다**

`ios/KidCare/Guardian/MapViewModel.swift` — 아래 줄 번호는 **3단계 끝(31c6eb2) 기준**이다. Task 1 이 `하루를_읽는다()` 위에 약 20줄을 더했으므로 줄 번호가 아니라 함께 적은 코드 문자열로 찾는다(`grep -n "상태 = 읽은_것.status\|서버_오프셋 = \|private func recordAnswer\|Phase 4" ios/KidCare/Guardian/MapViewModel.swift`).

1. `private func recordAnswer()`(:848-851)를 바꾸고 그 위에 훅을 둔다:

```swift
    /// 대답을 적은 직후 부른다. 정본은 안드로이드 `recordAnswer` 가
    /// `GuardianMainActivity.refreshBanner()` 를 함께 부르는 것(MapTimelineFragment.kt:682-685).
    /// `GuardianRootView` 가 채운다 — 비어 있어도 배너의 1분 주기 판정이 결국 따라잡는다.
    var 대답이_기록되면: (@MainActor () -> Void)?

    /// 아이 폰이 대답했다는 사실을 남기고 배너를 즉시 다시 판정하게 한다.
    private func recordAnswer() {
        guard let childUid else { return }
        requestLog.recordAnswer(childUid)
        대답이_기록되면?()
    }

    /// 서버 오프셋을 한 번이라도 쟀는가. 재기 전에는 아래 비교에 서버 시각과 기기 시각이
    /// 섞여 들어가므로 판단하지 않는다.
    private var 서버_오프셋을_쟀나 = false

    /// 부모가 마지막으로 물어본 **뒤에** 쓰인 상태 문서라면 그 자체가 "애기폰이 살아 있다"는
    /// 대답이다(늦게 살아난 폰의 안전 업로드일 수도 있다). 정본은 안드로이드
    /// `renderStatus`(MapTimelineFragment.kt:750-757) — 두 시계를 직접 비교하지 않고, 서버
    /// 기준 경과를 기기 시계로 되돌려 `RequestLog`(기기 시계)와 비교한다.
    private func 상태가_물음보다_새로우면_대답으로_친다() {
        guard 서버_오프셋을_쟀나, let childUid, let 상태, let 신호 = StatusCard.signal(status: 상태) else { return }
        let 기기시계 = Int64(Date().timeIntervalSince1970 * 1000)
        let 경과 = (기기시계 + 서버_오프셋) - 신호.atMillis
        if 기기시계 - 경과 > requestLog.lastRequestAt(childUid: childUid) {
            recordAnswer()
        }
    }
```

2. `상태와_그날_경로를_읽는다` 의 `상태 = 읽은_것.status`(:452) 바로 아래에 `상태가_물음보다_새로우면_대답으로_친다()` 한 줄.
3. `하루를_읽는다()` 의 `서버_오프셋 = 서버시각 - 이_시각의_기기시계`(:519) 바로 아래에 `서버_오프셋을_쟀나 = true`, 그리고 그 `if let 서버시각 { ... }` 블록이 끝난 뒤에 `상태가_물음보다_새로우면_대답으로_친다()` 한 줄.
4. `handleCommandTimeout` 의 `서버_오프셋 = 잰_시각 - 이_시각의_기기시계`(:727) 바로 아래에 `서버_오프셋을_쟀나 = true`.
5. `MapViewModel.swift` 안에서 "배너 UI 자체는 Phase 4 의 몫" 이라고 적은 주석 세 곳(:175-176, :703-704, :845-847)을 "배너는 `GuardianRootView` 의 `DisconnectBanner` 가 판정한다" 로 고친다.

`ios/KidCare/Guardian/RequestLog.swift:22-24` 주석을 이렇게 고친다: "`recordAnswer` 는 화면 갱신을 겸하지 않는다 — 배너를 곧바로 다시 판정하려면 부른 쪽이 `대답이_기록되면` 훅(→ `DisconnectBanner.다시_판정한다()`)도 함께 불러야 한다. 안드로이드 `recordAnswer()` 가 `refreshBanner()` 를 함께 부르는 것과 같다."

- [ ] **Step 7: `GuardianRootView` 에 배너를 얹는다**

`ios/KidCare/Guardian/GuardianRootView.swift`:

```swift
    @State private var mapViewModel: MapViewModel
    @State private var banner: DisconnectBanner
    @Environment(\.scenePhase) private var scenePhase
    @SceneStorage("guardian.selectedTab") private var selectedTab: GuardianTab = .map

    init(familyId: String, childUid: String?) {
        let map = MapViewModel(familyId: familyId, childUid: childUid)
        let banner = DisconnectBanner(childUid: childUid)
        // 둘 다 같은 init 안에서 만들어 서로를 잇는다. SwiftUI 가 init 을 여러 번 불러도
        // @State 는 첫 쌍만 붙들므로 살아남는 지도 뷰모델은 살아남는 배너를 가리킨다.
        map.대답이_기록되면 = { [weak banner] in banner?.다시_판정한다() }
        _mapViewModel = State(initialValue: map)
        _banner = State(initialValue: banner)
    }
```

`body` 는 `TabView` 를 `VStack` 으로 감싼다:

```swift
    var body: some View {
        // 배너는 탭 컨테이너 **밖**, 위에 둔다(activity_guardian_main.xml:65-73) — 어느 탭을
        // 보든 같은 자리에 같은 문장이다.
        VStack(spacing: 0) {
            if let 문구 = banner.문구 {
                DisconnectBannerView(text: 문구)
            }
            TabView(selection: $selectedTab) {
                // (Task 1 의 탭 다섯 그대로)
            }
            .tint(KidCarePalette.sky)
            .toolbarBackground(KidCarePalette.paperCard, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
        }
        // 안드로이드 onStart 에서 곧바로 한 번 판정하고 1분마다, onStop 에서 멈춘다(:395-421).
        // scenePhase 가 바뀌면 이 task 가 취소되고 새로 시작한다.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await banner.주기적으로_판정한다()
        }
        .onDisappear {
            mapViewModel.명령_추적을_정리한다()
            mapViewModel.실시간_추적을_정리한다()
        }
    }
```

- [ ] **Step 8: 통과 확인**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: 전체 PASS. 기존 `StatusCardTests` 의 모든 케이스가 리팩터 뒤에도 그대로 초록이어야 한다.

- [ ] **Step 9: 커밋** (공통 절차 B)

```bash
git add ios/KidCare/Core/Documents.swift ios/KidCare/Guardian/DisconnectBanner.swift ios/KidCare/Guardian/MapViewModel.swift \
  ios/KidCare/Guardian/RequestLog.swift ios/KidCare/Guardian/GuardianRootView.swift ios/KidCare/Localizable.xcstrings \
  ios/KidCareTests/TestDoubles.swift ios/KidCareTests/StatusCardTests.swift ios/KidCareTests/DisconnectBannerTests.swift ios/KidCareTests/MapBannerWiringTests.swift
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "iOS 4단계 Task 2: 무응답 배너 — 어느 탭을 보든 같은 자리, 대답이 오면 곧바로 사라진다"
```

---

### Task 3: 관리 탭의 두뇌 — 명령 왕복·잠금·알람 기억 (화면 없이 테스트)

**끝나면 `ControlViewModel` 하나가 안드로이드 `ControlFragment` 의 상태 기계 전부를 갖고, 가짜 Firestore 로 UI 없이 검증된다.** 화면은 Task 4 가 붙인다. 이 Task 에서 화면에 보이는 변화는 없다 — 대신 리뷰어가 상태 기계만 따로 승인하거나 반려할 수 있다.

**Files:**
- Modify: `ios/KidCare/Core/Documents.swift` (`CommandType` 확장, `RingerMode`·`Dnd`·`NetworkKind`·`RingerSettingsDoc` 추가)
- Create: `ios/KidCare/Core/ScheduleRepository.swift`
- Create: `ios/KidCare/Guardian/FirstToFinish.swift` (`MapViewModel.swift:1129-1177` 에서 옮긴다)
- Modify: `ios/KidCare/Guardian/MapViewModel.swift` (`Self.firstToFinish(` 세 곳 → `firstToFinish(`, 옮긴 코드 삭제)
- Create: `ios/KidCare/Guardian/AlarmMemoStore.swift`
- Create: `ios/KidCare/Guardian/ControlViewModel.swift`
- Modify: `ios/KidCare/Localizable.xcstrings`
- Modify: `ios/KidCareTests/EmulatorHarness.swift`, `ios/KidCareTests/CommandRepositoryTests.swift` (자녀 세션 도우미 옮기기)
- Test: `ios/KidCareTests/ScheduleRepositoryTests.swift`(에뮬레이터), `ios/KidCareTests/AlarmMemoStoreTests.swift`, `ios/KidCareTests/ControlViewModelTests.swift`

**Interfaces:**
- Consumes: `CommandRepository.send`/`observeOne`(3단계), `FamilyRepository.fetchChildStatus`/`serverNow`, `AuthGateway.currentUid()`(nonisolated), `errorMessage(_:)`, `StatusCard.signal`/`lastSignal`, `lastSignalText(_:)`, `RequestLog`, Task 2 의 `TestClock`·`TestListenerRegistration`·`TestCallbackBox`·`TestSignal`, Task 1 의 `TestGate`·`TestDefaults`·`eventually`
- Produces:
  - `CommandType.setRinger, queryRinger, findPhone, stopFind, message, payloadText, errorNotificationOff, setAlarm, cancelAlarm, payloadAtMinuteOfDay, payloadLabel, errorAlarmExactDenied`
  - `enum RingerMode { static let normal, vibrate, silent, payloadKey, errorDenied; static func isKnown(_:) -> Bool }`, `enum Dnd { static func isOn(_ value: String?) -> Bool }`, `enum NetworkKind { static let wifi, cell, none }`, `struct RingerSettingsDoc { var lockEnabled: Bool; var defaultMode: String; var holidayOff: Bool; init(_ data: [String: Any]) }`
  - `enum ScheduleRepository { static func setRingerLock(familyId:childUid:enabled:) async throws; static func observeRingerSettings(familyId:childUid:onChange:onError:) -> ListenerRegistration }`
  - `func firstToFinish<T: Sendable>(timeoutMillis: Int64, sleep: @escaping @Sendable (Int64) async -> Void, operation: @escaping @Sendable () async throws -> T) async throws -> T?`
  - `struct AlarmMemo: Equatable { let minuteOfDay: Int; let label: String; let confirmed: Bool }`, `struct AlarmMemoStore { init(defaults:now:); func memo(childUid:) -> AlarmMemo?; func recordSent(childUid:minuteOfDay:label:); func recordConfirmed(childUid:); func clear(childUid:) }`
  - `enum ControlCommandUi: Equatable { case idle, sending, done, messageUnread, messageRead, queued, failed(String); var isSpinning: Bool; var text: String? }`
  - `@MainActor @Observable final class ControlViewModel` — 전체 공개면은 Step 8 코드 블록 그대로(Task 4 가 이 이름들을 쓴다): `시작한다()`, `소리_모드를_보낸다(_:)`, `소리_상태를_묻는다()`, `폰찾기_버튼을_눌렀다()`, `소리를_끈다()`, `메시지를_보낸다()`, `알람을_맞춘다()`, `알람을_끈다()`, `잠금을_바꾼다(_:)`, `정리한다()`, 읽기 전용 상태·문구 프로퍼티, `var 메시지`, `var 알람_이름`, `var alarmMinute`, `var 대답이_기록되면`
  - `EmulatorHarness.ChildSession`, `EmulatorHarness.freshChildSession()`, `EmulatorHarness.joinAsChild(_:familyId:joinCode:)`

**정본:** `ControlFragment.kt` 전체. 줄 번호는 각 코드 주석에 적었다. 상수(:1118-1153): `COMMAND_TIMEOUT_MILLIS = 60_000L`, `SEND_TIMEOUT_MILLIS = 15_000L`, `FIND_AUTO_STOP_MILLIS = 5 * 60 * 1000L`, `DEFAULT_ALARM_MINUTE = 7 * 60`, `PAYLOAD_MODE = "mode"`, `ERROR_RINGER_DENIED = "ringer_denied"`, 모드 `"normal"/"vibrate"/"silent"`. 입력 길이: 메시지 100자(`fragment_control.xml:359,366`), 알람 이름 20자(:447). 명령 이름·페이로드 키: `Documents.kt:215-339`. 설정 문서: `Documents.kt:466-482`, `ScheduleRepository.kt:42-45, 93-96, 131-144`. 알람 기억: `AlarmMemoStore.kt` 전체. `Dnd`: `child/RingerStateStore.kt:9-19`. 네트워크 값: `child/NetworkState.kt:23-27`.

**규칙 확인(`firestore.rules`).** 이 Task 가 새로 만드는 쓰기는 둘이다.
- 명령 문서 create — `:175-177` "보호자이고 `state == 'pending'`". 기존 `CommandRepository.send` 를 그대로 쓴다(필드 7개, `state: pending`).
- `families/{f}/children/{c}/settings/ringer` 에 `{"lockEnabled": Bool}` 병합 — `:208-214` "보호자이고 `isChildMember(familyId, childUid)`", `hasOnly` 없음. 안드로이드와 똑같이 **`lockEnabled` 한 필드만** `merge: true` 로 쓴다(`ScheduleRepository.kt:88-96` — 통째로 덮으면 예약 탭의 `holidayOff`·`defaultMode` 가 기본값으로 돌아간다).

- [ ] **Step 1: 자녀 세션 도우미를 하네스로 옮긴다 (동작 변화 없음)**

`ios/KidCareTests/CommandRepositoryTests.swift` 의 `private struct ChildSession`, `private func freshChildSession()`, `private func joinAsChild(...)`(:28-81)를 지우고, 그 파일 안의 호출 `freshChildSession()` → `EmulatorHarness.freshChildSession()`, `joinAsChild(` → `EmulatorHarness.joinAsChild(` 로 바꾼다. 옮기는 이유: `ScheduleRepositoryTests` 도 "보호자 세션 + 가족에 들어온 자녀" 가 필요하다 — `freshUser()` 로 자녀로 갈아타면 익명 보호자 계정으로 돌아갈 방법이 없다.

`ios/KidCareTests/EmulatorHarness.swift` 전체:

```swift
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
@testable import KidCare

/// 테스트가 에뮬레이터를 상대하게 만들고, 테스트마다 새 익명 계정으로 갈아탄다.
///
/// 계정을 갈아타는 것이 왜 필요한가: 보안 규칙 검증은 "이 uid 가 이 문서를 만들 수
/// 있는가"를 묻는다. 테스트 전부가 한 uid 를 공유하면 앞 테스트에서 이미 멤버가 된
/// 계정으로 "아직 멤버가 아닌 사람"을 흉내 낼 수 없다.
enum EmulatorHarness {

    static let projectId = "kidcare-emulator"

    /// `FirebaseBootstrap` 이 `@MainActor` 라서 이 함수도 `@MainActor` 로 맞춘다.
    @MainActor
    static func start() {
        FirebaseBootstrap.configureForEmulator(projectId: projectId)
    }

    /// 지금 계정을 버리고 새 익명 계정으로 로그인해 그 uid 를 준다.
    @discardableResult
    static func freshUser() async throws -> String {
        try? Auth.auth().signOut()
        let result = try await Auth.auth().signInAnonymously()
        return result.user.uid
    }

    /// 자녀 폰을 흉내 내는 두 번째 세션(`CommandRepositoryTests` 에서 옮겨 왔다).
    ///
    /// 명령·설정은 보호자가 쓰고 자녀는 제 경로만 쓴다 — 방향이 반대인 두 역할을 한
    /// 프로세스에서 동시에 검증하려면 로그인 세션이 둘 있어야 한다. 기본 앱은 보호자로
    /// 두고, 자녀는 이름 붙은 두 번째 `FirebaseApp` 으로 흉내 낸다. 이 앱은 운영으로 갈
    /// 일이 없는 테스트 전용 인스턴스라 `FirebaseBootstrap` 규율과 충돌하지 않는다.
    struct ChildSession {
        let uid: String
        let db: Firestore
    }

    enum HarnessError: Error { case appMissing }

    static func freshChildSession() async throws -> ChildSession {
        // FIRApp 이름은 영문·숫자·하이픈·밑줄만 허용한다.
        let appName = "ChildSession-\(UUID().uuidString)"
        let options = FirebaseOptions(
            googleAppID: "1:000000000000:ios:0000000000000001",
            gcmSenderID: "000000000000"
        )
        options.projectID = projectId
        options.apiKey = "emulator-does-not-check-this"
        FirebaseApp.configure(name: appName, options: options)
        guard let app = FirebaseApp.app(name: appName) else { throw HarnessError.appMissing }

        let auth = Auth.auth(app: app)
        auth.useEmulator(withHost: "127.0.0.1", port: 9099)

        let firestore = Firestore.firestore(app: app)
        firestore.useEmulator(withHost: "127.0.0.1", port: 8080)
        let settings = firestore.settings
        settings.cacheSettings = MemoryCacheSettings()
        settings.isSSLEnabled = false
        firestore.settings = settings

        let result = try await auth.signInAnonymously()
        return ChildSession(uid: result.user.uid, db: firestore)
    }

    /// 자녀 세션으로 `families/{familyId}/members/{childUid}` 를 만든다 —
    /// `FamilyRepository.joinFamily` 와 같은 필드를 쓰되 자녀 세션의 `Firestore` 로 쓴다.
    static func joinAsChild(_ child: ChildSession, familyId: String, joinCode: String) async throws {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        try await child.db.collection("families").document(familyId)
            .collection("members").document(child.uid).setData([
                "role": "child",
                "displayName": "아이",
                "fcmToken": "",
                "appVersion": "",
                "updatedAt": now,
                "joinCode": joinCode,
                "joinedAt": now,
            ])
    }
}
```

Run: `cd ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/CommandRepositoryTests`
Expected: 기존 4개 PASS 그대로.

- [ ] **Step 2: 문서 상수와 설정 문서**

`ios/KidCare/Core/Documents.swift` 의 `enum CommandType` 안, `payloadSessionId`(:430) 아래에 더한다:

```swift
    /// 관리 탭이 보내는 명령(4단계). 정본은 안드로이드 `CommandType`(Documents.kt:215-339) —
    /// 값이 하나라도 다르면 자녀 폰(`child/CommandHandler`)이 이 명령을 못 알아본다.
    static let setRinger = "set_ringer"
    /// 자녀 폰의 실제 벨소리 모드만 읽어 상태 문서에 올린다. 소리는 안 낸다(:217-218).
    static let queryRinger = "query_ringer"
    static let findPhone = "find_phone"
    static let stopFind = "stop_find"
    /// 다른 명령과 달리 `delivered` 가 "전해졌지만 아직 안 읽음"이라는 **최종 상태**일 수
    /// 있다 — `done` 은 아이가 '확인했어요'를 눌렀다는 뜻이다(:247-260).
    static let message = "message"
    static let payloadText = "text"
    static let errorNotificationOff = "message_notification_off"
    /// 하루 안의 분만 보낸다. 오늘인지 내일인지는 자녀 폰이 정한다(:282-299).
    static let setAlarm = "set_alarm"
    static let cancelAlarm = "cancel_alarm"
    static let payloadAtMinuteOfDay = "atMinuteOfDay"
    static let payloadLabel = "label"
    static let errorAlarmExactDenied = "alarm_exact_denied"
```

같은 파일 끝에 더한다:

```swift
/// `set_ringer` 의 모드 값과 페이로드 키. 정본은 `ControlFragment.kt:1119-1128` — 안드로이드는
/// guardian 이 child 를 import 하지 않아 이 값을 두 곳에 적는다(`child/RingerStateStore.kt:21-27`).
/// 바꿀 일이 생기면 세 곳을 함께 고친다(README "함께 고쳐야 하는 짝").
enum RingerMode {
    static let normal = "normal"
    static let vibrate = "vibrate"
    static let silent = "silent"
    static let payloadKey = "mode"
    /// 자녀 폰이 소리 모드 변경을 거부당했을 때 적는 코드.
    static let errorDenied = "ringer_denied"

    static func isKnown(_ mode: String) -> Bool { mode == normal || mode == vibrate || mode == silent }
}

/// 자녀 폰이 올리는 방해 금지 상태. 정본은 `child/RingerStateStore.kt:9-19`. 방해 금지가
/// 켜지면 안드로이드가 벨소리 모드를 무조건 '무음'으로 보고하므로 둘을 함께 봐야 한다.
enum Dnd {
    /// 꺼짐도 모름도 아니면 켜져 있는 것이다.
    static func isOn(_ value: String?) -> Bool { value == "priority" || value == "alarms" || value == "none" }
}

/// `ChildStatusDoc.network` 값. 정본은 `child/NetworkState.kt:23-27`. 빈 값은 "모른다".
enum NetworkKind {
    static let wifi = "wifi"
    static let cell = "cell"
    static let none = "none"
}

/// children/{childUid}/settings/ringer. 정본은 `Documents.kt:466-482`. 보호자 앱은 이 문서를
/// **통째로 쓰지 않는다** — 필드 하나씩 병합한다(`ScheduleRepository.setRingerLock` 주석).
/// 그래서 `firestoreData` 가 없다.
struct RingerSettingsDoc {
    var lockEnabled = false
    var defaultMode = ""
    var holidayOff = false

    init(_ data: [String: Any]) {
        lockEnabled = data["lockEnabled"] as? Bool ?? false
        defaultMode = data["defaultMode"] as? String ?? ""
        holidayOff = data["holidayOff"] as? Bool ?? false
    }
}
```

`ios/KidCare/Core/ScheduleRepository.swift`:

```swift
import FirebaseFirestore
import Foundation

/// 벨소리 잠금 설정(settings/ringer). 정본은 안드로이드 `core/ScheduleRepository.kt`. 예약
/// 규칙(schedules/)은 5단계가 이 파일에 더한다 — 안드로이드와 같은 자리에 두려고 이름을
/// 미리 맞춘다.
enum ScheduleRepository {

    private static var db: Firestore { Firestore.firestore() }

    private static func ringerSettingsRef(familyId: String, childUid: String) -> DocumentReference {
        db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .collection("settings").document("ringer")
    }

    /// 잠금 스위치를 저장한다. **건드리는 필드만 병합한다** — 이 문서에는 관리 탭의 잠금과
    /// 예약 탭의 공휴일·기본 모드가 함께 있어서, 통째로 덮으면 한쪽이 저장할 때마다 다른
    /// 쪽 값이 기본값으로 돌아간다(ScheduleRepository.kt:88-96).
    ///
    /// 오프라인이면 이 await 는 서버 확인이 올 때까지 안 돌아온다 — 부르는 쪽이
    /// `firstToFinish` 로 15초 제한을 건다(ControlFragment.saveLock :854-860).
    static func setRingerLock(familyId: String, childUid: String, enabled: Bool) async throws {
        try await ringerSettingsRef(familyId: familyId, childUid: childUid)
            .setData(["lockEnabled": enabled], merge: true)
    }

    /// 설정 문서를 구독한다. 문서가 없으면 기본값을 준다(ScheduleRepository.kt:131-144).
    /// 돌려받은 등록은 부르는 쪽이 보호자 화면이 사라질 때 반드시 remove 한다.
    static func observeRingerSettings(
        familyId: String,
        childUid: String,
        onChange: @escaping (RingerSettingsDoc) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        ringerSettingsRef(familyId: familyId, childUid: childUid)
            .addSnapshotListener { snapshot, error in
                if let error { onError(error); return }
                onChange(RingerSettingsDoc(snapshot?.data() ?? [:]))
            }
    }
}
```

`ios/KidCareTests/ScheduleRepositoryTests.swift`:

```swift
import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 설정 문서 쓰기를 에뮬레이터로 확인한다 — 보안 규칙(firestore.rules:208-214)까지 태운다.
@Suite(.serialized)
struct ScheduleRepositoryTests {

    init() async { await EmulatorHarness.start() }

    private func 가족과_자녀() async throws -> (familyId: String, child: EmulatorHarness.ChildSession) {
        let guardianUid = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: guardianUid)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)
        let child = try await EmulatorHarness.freshChildSession()
        try await EmulatorHarness.joinAsChild(child, familyId: familyId, joinCode: invite.code)
        return (familyId, child)
    }

    private func 설정_문서(_ db: Firestore, familyId: String, childUid: String) -> DocumentReference {
        db.collection("families").document(familyId).collection("children").document(childUid)
            .collection("settings").document("ringer")
    }

    @Test("잠금 저장은 lockEnabled 하나만 병합한다 — 예약 탭의 holidayOff·defaultMode 를 지우지 않는다")
    func 잠금_저장은_다른_설정을_안_지운다() async throws {
        let (familyId, child) = try await 가족과_자녀()
        let ref = 설정_문서(Firestore.firestore(), familyId: familyId, childUid: child.uid)
        try await ref.setData(["holidayOff": true, "defaultMode": "vibrate"])

        try await ScheduleRepository.setRingerLock(familyId: familyId, childUid: child.uid, enabled: true)

        let data = try #require(try await ref.getDocument(source: .server).data())
        #expect(data["lockEnabled"] as? Bool == true)
        #expect(data["holidayOff"] as? Bool == true)
        #expect(data["defaultMode"] as? String == "vibrate")
        #expect(Set(data.keys) == ["lockEnabled", "holidayOff", "defaultMode"])
    }

    @Test("구독은 문서가 없으면 기본값(false)을, 저장하면 새 값을 준다")
    func 구독이_값을_따라온다() async throws {
        let (familyId, child) = try await 가족과_자녀()
        let 받은_값 = 값_기록()
        let listener = ScheduleRepository.observeRingerSettings(
            familyId: familyId, childUid: child.uid,
            onChange: { doc in Task { await 받은_값.기록(doc.lockEnabled) } },
            onError: { _ in }
        )
        defer { listener.remove() }
        try await 기다린다 { await 받은_값.값들.contains(false) }
        try await ScheduleRepository.setRingerLock(familyId: familyId, childUid: child.uid, enabled: true)
        try await 기다린다 { await 받은_값.값들.last == true }
    }

    @Test("아이는 잠금을 못 바꾼다 — 규칙이 보호자만 허용한다")
    func 아이는_못_쓴다() async throws {
        let (familyId, child) = try await 가족과_자녀()
        await #expect(throws: (any Error).self) {
            try await 설정_문서(child.db, familyId: familyId, childUid: child.uid)
                .setData(["lockEnabled": false], merge: true)
        }
    }

    private actor 값_기록 {
        private(set) var 값들: [Bool] = []
        func 기록(_ value: Bool) { 값들.append(value) }
    }

    private func 기다린다(timeoutSeconds: Double = 5, _ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        Issue.record("조건이 \(timeoutSeconds)초 안에 참이 되지 않았다")
    }
}
```

- [ ] **Step 3: 알람 기억**

`ios/KidCareTests/AlarmMemoStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import KidCare

/// 정본은 안드로이드 `guardian/AlarmMemoStore.kt`.
struct AlarmMemoStoreTests {

    private let 하루: Int64 = 24 * 60 * 60 * 1000

    private func 만든다(_ clock: TestClock) -> AlarmMemoStore {
        AlarmMemoStore(defaults: TestDefaults.isolated("AlarmMemoStoreTests"), now: { clock.value })
    }

    @Test("보낸 직후에는 아직 확정되지 않은 기억이다")
    func 보내면_대기() {
        let store = 만든다(TestClock(1_000))
        store.recordSent(childUid: "a", minuteOfDay: 450, label: "학원")
        #expect(store.memo(childUid: "a") == AlarmMemo(minuteOfDay: 450, label: "학원", confirmed: false))
    }

    @Test("done 이 오면 확정된다")
    func 확정() {
        let store = 만든다(TestClock(1_000))
        store.recordSent(childUid: "a", minuteOfDay: 420, label: "")
        store.recordConfirmed(childUid: "a")
        #expect(store.memo(childUid: "a")?.confirmed == true)
    }

    @Test("기록이 없으면 늦게 온 done 이 기억을 되살리지 않는다(:63-66)")
    func 없는_기억은_되살리지_않는다() {
        let store = 만든다(TestClock(1_000))
        store.recordConfirmed(childUid: "a")
        #expect(store.memo(childUid: "a") == nil)
    }

    @Test("24시간이 지나면 사라진다 — 원격 알람은 어느 시각을 골라도 24시간 안에 지난다(:25-32)")
    func 하루가_지나면_사라진다() {
        let clock = TestClock(1_000)
        let store = 만든다(clock)
        store.recordSent(childUid: "a", minuteOfDay: 420, label: "")
        clock.advance(하루 - 1)
        #expect(store.memo(childUid: "a") != nil)
        clock.advance(1)
        #expect(store.memo(childUid: "a") == nil)
    }

    @Test("지우면 사라지고, 아이마다 따로 기억한다")
    func 지우기와_아이별() {
        let store = 만든다(TestClock(1_000))
        store.recordSent(childUid: "a", minuteOfDay: 420, label: "")
        store.recordSent(childUid: "b", minuteOfDay: 480, label: "")
        store.clear(childUid: "a")
        #expect(store.memo(childUid: "a") == nil)
        #expect(store.memo(childUid: "b")?.minuteOfDay == 480)
    }
}
```

`ios/KidCare/Guardian/AlarmMemoStore.swift`:

```swift
import Foundation

struct AlarmMemo: Equatable {
    let minuteOfDay: Int
    let label: String
    /// 아이 폰이 done 이라고 적었다는 것뿐이다 — 그 뒤 아이가 앱을 강제 종료하면 알람은
    /// 사라지지만 이 값은 모른다. 그 자리는 무응답 배너가 덮는다(AlarmMemoStore.kt:17-23).
    let confirmed: Bool
}

/// "애기폰에 알람을 맞춰 뒀다"는 부모 폰의 기억. 정본은 안드로이드 `guardian/AlarmMemoStore.kt`.
///
/// 부모가 지금 알람이 걸려 있는지 볼 수 없으면 **세 개를 건다.** 알람은 아이 폰 안에만 있고
/// 물어볼 통로가 없어서(서버에 두면 알람 하나에 쓰기 하나가 붙는다 — 무료 한도) 부모 폰이
/// 자기가 보낸 것을 기억한다. `RequestLog` 와 같은 자리, 같은 이유다.
///
/// 키에 `alarm_memo_` 를 붙인다 — 안드로이드는 전용 prefs 파일을 쓰지만 여기서는
/// `RoleStore`·`RequestLog` 와 같은 `UserDefaults` 를 나눠 쓴다.
struct AlarmMemoStore {

    /// 안드로이드 `MAX_MINUTE_OF_DAY = 1439`(:89).
    static let maxMinuteOfDay = 1439
    /// 안드로이드 `EXPIRY_MILLIS = 24 * 60 * 60 * 1000L`(:90).
    static let expiryMillis: Int64 = 24 * 60 * 60 * 1000

    private let defaults: UserDefaults
    private let now: @Sendable () -> Int64

    init(
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.defaults = defaults
        self.now = now
    }

    /// 걸어 둔 알람. 없거나 24시간이 지났으면 nil(:39-49).
    func memo(childUid: String) -> AlarmMemo? {
        guard let minute = defaults.object(forKey: key("minute_of_day", childUid)) as? Int,
              (0...Self.maxMinuteOfDay).contains(minute) else { return nil }
        let sentAt = Int64(defaults.integer(forKey: key("sent_at", childUid)))
        guard now() - sentAt < Self.expiryMillis else { return nil }
        return AlarmMemo(
            minuteOfDay: minute,
            label: defaults.string(forKey: key("label", childUid)) ?? "",
            confirmed: defaults.bool(forKey: key("confirmed", childUid))
        )
    }

    /// 명령이 실제로 발행됐다. 아직 아이 폰의 대답은 못 들었다(:52-59).
    func recordSent(childUid: String, minuteOfDay: Int, label: String) {
        defaults.set(minuteOfDay, forKey: key("minute_of_day", childUid))
        defaults.set(label, forKey: key("label", childUid))
        defaults.set(Int(now()), forKey: key("sent_at", childUid))
        defaults.set(false, forKey: key("confirmed", childUid))
    }

    /// 아이 폰이 done 을 적었다. 기록이 없으면(만료됐거나 취소된 뒤 늦게 온 콜백)
    /// 되살리지 않는다 — 없는 알람을 "맞춰져 있어요"로 만들 자리다(:62-67).
    func recordConfirmed(childUid: String) {
        guard let minute = defaults.object(forKey: key("minute_of_day", childUid)) as? Int,
              (0...Self.maxMinuteOfDay).contains(minute) else { return }
        defaults.set(true, forKey: key("confirmed", childUid))
    }

    /// 알람을 껐거나, 맞추기가 실패했다(:70-77).
    func clear(childUid: String) {
        for base in ["minute_of_day", "label", "sent_at", "confirmed"] {
            defaults.removeObject(forKey: key(base, childUid))
        }
    }

    private func key(_ base: String, _ childUid: String) -> String { "alarm_memo_\(base)_\(childUid)" }
}
```

- [ ] **Step 4: 발행 15초 경주를 공용으로 옮긴다 (동작 변화 없음)**

`ios/KidCare/Guardian/MapViewModel.swift` 의 `private static func firstToFinish` 와 `private actor CommandRace`(3단계 끝 기준 :1129-1177, Task 1·2 가 줄을 더해 밀려 있다 — `grep -n "private static func firstToFinish\|private actor CommandRace" ios/KidCare/Guardian/MapViewModel.swift` 로 찾는다) 를 그 위 문서 주석과 함께 **잘라내** `ios/KidCare/Guardian/FirstToFinish.swift` 로 옮긴다. 옮기면서 바뀌는 것은 두 줄뿐이다: `private static func firstToFinish<T: Sendable>(` → `func firstToFinish<T: Sendable>(`(파일 스코프 internal), 문서 주석의 `[MapViewModel.firstToFinish]` → `[firstToFinish]`. 파일 머리에 `import Foundation` 과 한 줄 주석 "지도 탭(`MapViewModel`)과 관리 탭(`ControlViewModel`)이 함께 쓴다 — 안드로이드 `withTimeoutOrNull(SEND_TIMEOUT_MILLIS)` 두 자리(MapTimelineFragment.kt:384, ControlFragment.kt:533)와 같은 장치" 를 둔다. 그리고 `MapViewModel.swift` 의 `Self.firstToFinish(` 세 곳을 `firstToFinish(` 로 바꾼다(`grep -n "Self.firstToFinish" ios/KidCare/Guardian/MapViewModel.swift` → 3줄).

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/MapViewModelCommandGenerationTests -only-testing:KidCareTests/LiveTrackingTests -only-testing:KidCareTests/AlarmMemoStoreTests -only-testing:KidCareTests/ScheduleRepositoryTests`
Expected: 기존 지도 명령·실시간 테스트 PASS 그대로, `AlarmMemoStoreTests` 5개·`ScheduleRepositoryTests` 3개 PASS.

- [ ] **Step 5: `ControlViewModel` 테스트를 먼저 쓴다**

`ios/KidCareTests/ControlViewModelTests.swift`:

```swift
import FirebaseFirestore
import Foundation
import os
import Testing
@testable import KidCare

/// 관리 탭이 부르는 Firestore 쪽 전부의 가짜. 테스트가 명령 문서를 자녀 폰처럼 옮긴다.
///
/// **`@unchecked Sendable` 은 테스트 타깃에만 있다** — `@Sendable` 클로저 안에서 불리고
/// Firestore 콜백(비 Sendable 클로저)을 붙들어야 해서, 상태 전부를 잠금 하나로 직접 지킨다.
final class FakeControlBackend: @unchecked Sendable {

    struct Sent: Equatable {
        let type: String
        let payload: [String: String]
    }

    struct State {
        var sent: [Sent] = []
        var sendHangs = false
        var sendError: Error?
        var status: ChildStatusDoc?
        var lockHangs = false
        var lockError: Error?
        var locksSaved: [Bool] = []
        var commandCallbacks: [(CommandDoc) -> Void] = []
        var commandListeners: [TestListenerRegistration] = []
        var settingsCallback: ((RingerSettingsDoc) -> Void)?
    }

    private let lock = NSLock()
    private var state = State()
    /// 영영 안 열리는 문 — 오프라인 쓰기를 흉내 낸다.
    private let 멈춤 = TestGate()
    let settingsListener = TestListenerRegistration()

    func update(_ body: (inout State) -> Void) { lock.withLock { body(&state) } }
    var snapshot: State { lock.withLock { state } }

    func send(type: String, payload: [String: String]) async throws -> String {
        let (hangs, error, id) = lock.withLock { () -> (Bool, Error?, String) in
            state.sent.append(Sent(type: type, payload: payload))
            return (state.sendHangs, state.sendError, "cmd-\(state.sent.count)")
        }
        if hangs { await 멈춤.wait() }
        if let error { throw error }
        return id
    }

    func observe(onChange: @escaping (CommandDoc) -> Void) -> ListenerRegistration {
        let listener = TestListenerRegistration()
        lock.withLock {
            state.commandCallbacks.append(onChange)
            state.commandListeners.append(listener)
        }
        return listener
    }

    /// `index` 번째(0부터, 리스너가 붙은 순서) 명령 문서를 자녀 폰이 옮긴 것처럼 알린다.
    func 명령을_옮긴다(_ index: Int, to newState: String, error: String = "") {
        let callback = lock.withLock { state.commandCallbacks[index] }
        callback(CommandDoc(id: "cmd-\(index + 1)", ["state": newState, "error": error]))
    }

    func observeSettings(onChange: @escaping (RingerSettingsDoc) -> Void) -> ListenerRegistration {
        lock.withLock { state.settingsCallback = onChange }
        return settingsListener
    }

    func 설정이_바뀌었다(lockEnabled: Bool) {
        let callback = lock.withLock { state.settingsCallback }
        callback?(RingerSettingsDoc(["lockEnabled": lockEnabled]))
    }

    func saveLock(_ enabled: Bool) async throws {
        let (hangs, error) = lock.withLock { () -> (Bool, Error?) in
            state.locksSaved.append(enabled)
            return (state.lockHangs, state.lockError)
        }
        if hangs { await 멈춤.wait() }
        if let error { throw error }
    }
}

/// 15초·60초·5분을 실제로 기다리지 않게 하는 가짜 수면. 길이마다 문이 하나씩 있고,
/// 테스트가 열어야 그 길이의 수면이 끝난다. 문은 한 번 열리면 계속 열려 있다.
final class FakeSleep: Sendable {
    let 발행 = TestGate()
    let 응답 = TestGate()
    let 폰찾기 = TestGate()
    private let 멈춤 = TestGate()

    func sleep(_ millis: Int64) async {
        switch millis {
        case ControlViewModel.sendTimeoutMillis: await 발행.wait()
        case ControlViewModel.commandTimeoutMillis: await 응답.wait()
        case ControlViewModel.findAutoStopMillis: await 폰찾기.wait()
        default: await 멈춤.wait()
        }
    }
}

/// 정본은 안드로이드 `guardian/ControlFragment.kt`. 줄 번호는 각 테스트 이름에 적었다.
@MainActor
struct ControlViewModelTests {

    private let now: Int64 = 1_757_000_000_000
    private struct 가짜_오류: Error {}

    private func 만든다(
        childUid: String? = "child",
        backend: FakeControlBackend,
        sleep: FakeSleep = FakeSleep(),
        log: RequestLog? = nil,
        memo: AlarmMemoStore? = nil,
        clock: TestClock? = nil
    ) -> ControlViewModel {
        let clock = clock ?? TestClock(now)
        return ControlViewModel(
            familyId: "family",
            childUid: childUid,
            requestLog: log ?? RequestLog(defaults: TestDefaults.isolated("ControlViewModelTests")),
            alarmMemoStore: memo ?? AlarmMemoStore(defaults: TestDefaults.isolated("ControlViewModelTests-memo"), now: { clock.value }),
            commandSend: { _, _, type, payload in try await backend.send(type: type, payload: payload) },
            commandObserve: { _, _, _, onChange, _ in backend.observe(onChange: onChange) },
            statusFetch: { _, _ in backend.snapshot.status },
            settingsObserve: { _, _, onChange, _ in backend.observeSettings(onChange: onChange) },
            lockSave: { _, _, enabled in try await backend.saveLock(enabled) },
            serverNow: { _ in clock.value },
            deviceNow: { clock.value },
            commandSleep: { millis in await sleep.sleep(millis) }
        )
    }

    private func 상태(
        ringerMode: String = "normal", dnd: String = "", network: String = "", wifiOn: Bool? = nil, lastSeenAt: Int64
    ) -> ChildStatusDoc {
        var data: [String: Any] = [
            "lat": 37.0, "lng": 127.0, "battery": 50,
            "ringerMode": ringerMode, "dnd": dnd, "network": network, "lastSeenAt": lastSeenAt,
        ]
        if let wifiOn { data["wifiOn"] = wifiOn }
        return ChildStatusDoc(data)!
    }

    @Test("열면 상태를 한 번 읽고 소리 상태를 묻고 설정을 구독한다, 다시 열어도 반복하지 않는다(subscribe :270-311)")
    func 시작() async {
        let backend = FakeControlBackend()
        let s = 상태(ringerMode: "vibrate", network: NetworkKind.wifi, wifiOn: true, lastSeenAt: now)
        backend.update { $0.status = s }
        let vm = 만든다(backend: backend)

        await vm.시작한다().value

        #expect(backend.snapshot.sent == [.init(type: CommandType.queryRinger, payload: [:])])
        #expect(vm.ringerQueryInFlight)
        #expect(vm.소리_상태_문구 == String(localized: "control_ringer_status_loading"))
        #expect(vm.currentRingerMode == RingerMode.vibrate)
        #expect(vm.인터넷_문구 == String(localized: "control_network_wifi"))
        #expect(vm.와이파이_스위치_문구 == String(format: String(localized: "control_network_wifi_switch"), String(localized: "control_network_on")))
        #expect(backend.snapshot.settingsCallback != nil)

        await vm.시작한다().value
        #expect(backend.snapshot.sent.count == 1)
    }

    @Test("소리 모드는 mode 페이로드로 가고, done 이면 '현재 상태 · 진동'·대답 기록·배너 판정(:352-356, :622-628)")
    func 소리_모드_완료() async {
        let backend = FakeControlBackend()
        let s = 상태(lastSeenAt: now)
        backend.update { $0.status = s }
        let log = RequestLog(defaults: TestDefaults.isolated("ControlViewModelTests"))
        let vm = 만든다(backend: backend, log: log)
        var 판정 = 0
        vm.대답이_기록되면 = { 판정 += 1 }

        await vm.시작한다().value
        await vm.소리_모드를_보낸다(RingerMode.vibrate)

        #expect(backend.snapshot.sent.last == .init(type: CommandType.setRinger, payload: ["mode": "vibrate"]))
        #expect(vm.commandUi == .sending)
        #expect(vm.ringerQueryInFlight == false) // 조회 중 누른 다른 명령이 화면의 새 주인(:499-504)
        #expect(log.lastRequestAt(childUid: "child") > 0)

        backend.명령을_옮긴다(1, to: CommandState.done)
        await eventually { vm.commandUi == .done }
        #expect(vm.currentRingerMode == RingerMode.vibrate)
        #expect(vm.선택된_모드인가(RingerMode.vibrate))
        #expect(vm.소리_상태_문구 == String(format: String(localized: "control_ringer_status_applied"), String(localized: "control_mode_vibrate")))
        #expect(판정 == 1)
        #expect(log.lastAnswerAt(childUid: "child") > 0)
    }

    @Test("소리 상태 조회가 done 이면 상태를 다시 읽고 '현재 상태'로 확정한다(:629-634)")
    func 조회_완료() async {
        let backend = FakeControlBackend()
        let 처음 = 상태(ringerMode: "normal", lastSeenAt: now)
        backend.update { $0.status = 처음 }
        let vm = 만든다(backend: backend)
        await vm.시작한다().value

        let 나중 = 상태(ringerMode: "silent", lastSeenAt: now)
        backend.update { $0.status = 나중 }
        backend.명령을_옮긴다(0, to: CommandState.done)

        await eventually { vm.currentRingerMode == RingerMode.silent && !vm.상태_읽는_중 }
        #expect(vm.ringerAppliedInSession)
        #expect(vm.ringerQueryInFlight == false)
        #expect(vm.소리_상태_문구 == String(format: String(localized: "control_ringer_status_applied"), String(localized: "control_mode_silent")))
    }

    @Test("발행이 15초 안에 확인되지 않으면 실패가 아니라 queued, 폰찾기 버튼은 그대로(:533-547)")
    func 발행_큐잉() async {
        let backend = FakeControlBackend()
        backend.update { $0.sendHangs = true }
        let sleep = FakeSleep()
        let vm = 만든다(backend: backend, sleep: sleep)

        let 누름 = Task { await vm.폰찾기_버튼을_눌렀다() }
        await eventually { backend.snapshot.sent.count == 1 }
        #expect(vm.commandUi == .sending)
        await sleep.발행.open()
        await 누름.value

        #expect(vm.commandUi == .queued)
        #expect(vm.울리는_중이라고_믿는가 == false) // onSent 를 부르면 안 된다(:538-545)
        #expect(backend.snapshot.commandCallbacks.isEmpty)
    }

    @Test("폰찾기가 발행되면 5분 동안 울린다고 믿고, 그 사이 누르면 stop_find, 5분 뒤엔 되돌아간다(:369-386, :891-899, :933-940)")
    func 폰찾기() async {
        let backend = FakeControlBackend()
        let sleep = FakeSleep()
        let vm = 만든다(backend: backend, sleep: sleep)

        await vm.폰찾기_버튼을_눌렀다()
        #expect(backend.snapshot.sent.last?.type == CommandType.findPhone)
        #expect(vm.울리는_중이라고_믿는가)

        await vm.폰찾기_버튼을_눌렀다()
        #expect(backend.snapshot.sent.last?.type == CommandType.stopFind)
        #expect(vm.울리는_중이라고_믿는가 == false)

        await vm.폰찾기_버튼을_눌렀다()
        #expect(vm.울리는_중이라고_믿는가)
        await sleep.폰찾기.open()
        await eventually { vm.울리는_중이라고_믿는가 == false }
    }

    @Test("failed 는 자녀 폰의 오류 코드를 문장으로 옮기고, 실패도 대답으로 친다(:639-654, :756-767)")
    func 실패_번역() async {
        let backend = FakeControlBackend()
        let log = RequestLog(defaults: TestDefaults.isolated("ControlViewModelTests"))
        let vm = 만든다(backend: backend, log: log)
        let 사례: [(code: String, key: String.LocalizationValue)] = [
            (RingerMode.errorDenied, "control_error_ringer_denied"),
            (CommandType.errorNotificationOff, "control_error_message_notification_off"),
            (CommandType.errorAlarmExactDenied, "control_error_alarm_exact_denied"),
            ("모르는_코드", "control_error_child_failed"),
        ]
        for (index, 하나) in 사례.enumerated() {
            await vm.소리_모드를_보낸다(RingerMode.silent)
            backend.명령을_옮긴다(index, to: CommandState.failed, error: 하나.code)
            let 기대 = String(localized: 하나.key)
            await eventually { vm.commandUi == .failed(기대) }
        }
        #expect(log.lastAnswerAt(childUid: "child") > 0)
    }

    @Test("메시지: 발행되면 입력칸을 비우고, delivered 는 '아직 안 읽음'이며 60초 타이머를 끈다, done 은 '읽음'(:398-408, :635-669)")
    func 메시지() async {
        let backend = FakeControlBackend()
        let sleep = FakeSleep()
        let vm = 만든다(backend: backend, sleep: sleep)
        vm.메시지 = "  밥 먹었어?  "

        await vm.메시지를_보낸다()
        #expect(backend.snapshot.sent.last == .init(type: CommandType.message, payload: ["text": "밥 먹었어?"]))
        #expect(vm.메시지 == "")

        backend.명령을_옮긴다(0, to: CommandState.delivered)
        await eventually { vm.commandUi == .messageUnread }
        await sleep.응답.open()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(vm.commandUi == .messageUnread) // 잘 전해진 메시지 위에 '응답하지 않아요'를 덮지 않는다

        backend.명령을_옮긴다(0, to: CommandState.done)
        await eventually { vm.commandUi == .messageRead }
    }

    @Test("빈 메시지는 보내지 않고 이유를 말한다(:400-404)")
    func 빈_메시지() async {
        let backend = FakeControlBackend()
        let vm = 만든다(backend: backend)
        vm.메시지 = "   "
        await vm.메시지를_보낸다()
        #expect(backend.snapshot.sent.isEmpty)
        #expect(vm.commandUi == .failed(String(localized: "control_message_empty")))
    }

    @Test("60초 무응답은 '응답하지 않아요'와 마지막 신호를 함께 말하고, 대답으로 치지 않는다(:684-744)")
    func 무응답() async {
        let backend = FakeControlBackend()
        let s = 상태(lastSeenAt: now - 10 * 60_000)
        backend.update { $0.status = s }
        let sleep = FakeSleep()
        let log = RequestLog(defaults: TestDefaults.isolated("ControlViewModelTests"))
        let vm = 만든다(backend: backend, sleep: sleep, log: log)

        await vm.시작한다().value
        await vm.소리_모드를_보낸다(RingerMode.silent)
        await sleep.응답.open()

        let 기대 = String(
            format: String(localized: "control_command_timeout_format"),
            String(format: String(localized: "control_last_seen_format"), lastSignalText(.minutes(10)))
        )
        await eventually { vm.commandUi == .failed(기대) }
        #expect(log.lastAnswerAt(childUid: "child") == 0)
    }

    @Test("신호가 한 번도 없던 폰의 무응답은 '아직 한 번도 신호가 없었어요'(:739)")
    func 무응답_신호_없음() async {
        let backend = FakeControlBackend()
        let sleep = FakeSleep()
        let vm = 만든다(backend: backend, sleep: sleep)
        await vm.소리_모드를_보낸다(RingerMode.silent)
        await sleep.응답.open()
        let 기대 = String(format: String(localized: "control_command_timeout_format"), String(localized: "control_last_seen_never"))
        await eventually { vm.commandUi == .failed(기대) }
    }

    @Test("새 명령을 누르면 앞 리스너를 떼고, 늦게 온 앞 명령의 done 은 화면을 못 바꾼다(:98-118)")
    func 세대() async {
        let backend = FakeControlBackend()
        let vm = 만든다(backend: backend)
        await vm.소리_모드를_보낸다(RingerMode.vibrate)
        await vm.소리_모드를_보낸다(RingerMode.silent)
        #expect(backend.snapshot.commandListeners[0].removed)

        backend.명령을_옮긴다(0, to: CommandState.done)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(vm.commandUi == .sending)
        #expect(vm.currentRingerMode == nil)

        backend.명령을_옮긴다(1, to: CommandState.done)
        await eventually { vm.commandUi == .done }
        #expect(vm.currentRingerMode == RingerMode.silent)
    }

    @Test("알람: 발행되면 '보냈어요', done 이면 '맞춰져 있어요', failed 면 기억을 지운다(:444-459, :612-647, :912-931)")
    func 알람() async {
        let backend = FakeControlBackend()
        let vm = 만든다(backend: backend)
        vm.alarmMinute = 7 * 60 + 30
        vm.알람_이름 = " 학원 "

        await vm.알람을_맞춘다()
        #expect(backend.snapshot.sent.last == .init(type: CommandType.setAlarm, payload: ["atMinuteOfDay": "450", "label": "학원"]))
        let 시각 = String(format: String(localized: "schedule_time_format"), 7, 30)
        let 무엇 = String(format: String(localized: "control_alarm_state_labeled"), 시각, "학원")
        #expect(vm.알람_상태_문구 == String(format: String(localized: "control_alarm_state_pending"), 무엇))

        backend.명령을_옮긴다(0, to: CommandState.done)
        let 확정 = String(format: String(localized: "control_alarm_state_confirmed"), 무엇)
        await eventually { vm.알람_상태_문구 == 확정 }

        await vm.알람을_맞춘다()
        backend.명령을_옮긴다(1, to: CommandState.failed, error: CommandType.errorAlarmExactDenied)
        await eventually { vm.알람_상태_문구 == nil }
    }

    @Test("알람 끄기는 발행되는 순간 기억을 지운다(:461-473)")
    func 알람_끄기() async {
        let backend = FakeControlBackend()
        let clock = TestClock(now)
        let store = AlarmMemoStore(defaults: TestDefaults.isolated("ControlViewModelTests-memo"), now: { clock.value })
        store.recordSent(childUid: "child", minuteOfDay: 420, label: "")
        let vm = 만든다(backend: backend, memo: store, clock: clock)
        #expect(vm.알람_상태_문구 != nil)

        await vm.알람을_끈다()
        #expect(backend.snapshot.sent.last?.type == CommandType.cancelAlarm)
        #expect(vm.알람_상태_문구 == nil)
    }

    @Test("잠금 저장이 실패하면 스위치를 되돌리고 이유를 말한다(:862-869)")
    func 잠금_실패() async {
        let backend = FakeControlBackend()
        backend.update { $0.lockError = 가짜_오류() }
        let vm = 만든다(backend: backend)
        await vm.시작한다().value

        await vm.잠금을_바꾼다(true)
        #expect(backend.snapshot.locksSaved == [true])
        #expect(vm.lockEnabled == false)
        #expect(vm.commandUi == .failed(errorMessage(가짜_오류())))
    }

    @Test("잠금 저장이 15초 안에 확인되지 않으면 스위치는 그대로 두고 queued(:849-860)")
    func 잠금_큐잉() async {
        let backend = FakeControlBackend()
        backend.update { $0.lockHangs = true }
        let sleep = FakeSleep()
        let vm = 만든다(backend: backend, sleep: sleep)
        await vm.시작한다().value

        let 누름 = Task { await vm.잠금을_바꾼다(true) }
        await eventually { backend.snapshot.locksSaved == [true] }
        #expect(vm.lockEnabled)
        await sleep.발행.open()
        await 누름.value
        #expect(vm.commandUi == .queued)
        #expect(vm.lockEnabled)
    }

    @Test("부모가 방금 민 값과 다른 옛 스냅샷은 스위치를 되돌리지 못한다(:170-176, :820-826)")
    func 잠금_보류값() async {
        let backend = FakeControlBackend()
        backend.update { $0.lockHangs = true }
        let vm = 만든다(backend: backend)
        await vm.시작한다().value

        _ = Task { await vm.잠금을_바꾼다(true) }
        await eventually { vm.lockEnabled }

        backend.설정이_바뀌었다(lockEnabled: false) // 화면을 연 직후의 늦은 첫 읽기
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(vm.lockEnabled)

        backend.설정이_바뀌었다(lockEnabled: true)  // 우리가 쓴 값이 돌아왔다 — 보류를 푼다
        backend.설정이_바뀌었다(lockEnabled: false) // 이제부터는 서버 값을 따른다
        await eventually { vm.lockEnabled == false }
    }

    @Test("아이가 없으면 명령을 못 보내고 map_no_child, 소리 상태가 로딩에 갇히지 않는다(판정 기록 5)")
    func 아이_없음() async {
        let backend = FakeControlBackend()
        let vm = 만든다(childUid: nil, backend: backend)
        await vm.시작한다().value

        #expect(vm.아이_안내 == String(localized: "map_no_child"))
        #expect(vm.버튼_활성화 == false)
        #expect(vm.소리_상태_문구 == String(localized: "control_ringer_status_unknown"))

        await vm.소리_모드를_보낸다(RingerMode.silent)
        #expect(backend.snapshot.sent.isEmpty)
        #expect(vm.commandUi == .failed(String(localized: "map_no_child")))
    }

    @Test("방해 금지가 켜져 있으면 모드 대신 '방해금지 모드'라 말하고 안내 줄을 보인다(:999-1015), 인터넷 없음(:794-818)")
    func 방해금지와_인터넷() async {
        let backend = FakeControlBackend()
        let s = 상태(ringerMode: "silent", dnd: "priority", network: NetworkKind.none, lastSeenAt: now)
        backend.update { $0.status = s }
        let vm = 만든다(backend: backend)
        await vm.시작한다().value
        backend.명령을_옮긴다(0, to: CommandState.done)
        await eventually { !vm.상태_읽는_중 && !vm.ringerQueryInFlight }

        #expect(vm.소리_상태_문구 == String(format: String(localized: "control_ringer_status_format"), String(localized: "control_ringer_dnd")))
        #expect(vm.방해금지_안내를_보이는가)
        #expect(vm.인터넷_문구 == String(localized: "control_network_none"))
        #expect(vm.와이파이_스위치_문구 == nil) // false(꺼짐)와 nil(모름)은 다른 말이다
    }

    @Test("정리하면 설정 리스너와 명령 리스너를 뗀다(onDestroyView :1094-1116)")
    func 정리() async {
        let backend = FakeControlBackend()
        let vm = 만든다(backend: backend)
        await vm.시작한다().value
        #expect(backend.settingsListener.removed == false)

        vm.정리한다()
        #expect(backend.settingsListener.removed)
        #expect(backend.snapshot.commandListeners[0].removed)
    }
}
```

- [ ] **Step 6: 실패 확인**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/ControlViewModelTests`
Expected: 컴파일 실패 — `ControlViewModel`·`ControlCommandUi` 가 없다.

- [ ] **Step 7: 뷰모델이 쓰는 문구 키를 카탈로그에 넣는다**

모두 `i18n/ko.json` 에 이미 있는 안드로이드 키다(새 원본 키 없음). 공통 절차 A 를 이 목록으로 돌린다 — `LocalizableCatalogTests.코드가_부르는_키는_카탈로그에_있다` 가 Step 8 코드와 함께 이 목록을 검사한다.

```
KEYS="control_message_unread control_message_read control_message_empty control_ringer_status_loading control_ringer_status_format control_ringer_dnd control_ringer_status_unknown control_ringer_status_applied control_mode_normal control_mode_vibrate control_mode_silent control_network_wifi control_network_cell control_network_none control_network_unknown control_network_wifi_switch control_network_on control_network_off schedule_time_format control_alarm_state_labeled control_alarm_state_confirmed control_alarm_state_pending control_error_ringer_denied control_error_message_notification_off control_error_alarm_exact_denied"
```

(`control_command_sending`·`control_command_done`·`control_command_queued`·`control_command_timeout`·`control_command_timeout_format`·`control_last_seen_*`·`control_error_child_failed`·`map_no_child` 는 3단계가 이미 넣었다 — 명령이 건너뛴다.)

- [ ] **Step 8: `ControlViewModel` 을 구현한다**

`ios/KidCare/Guardian/ControlViewModel.swift`:

```swift
import FirebaseFirestore
import Foundation
import Observation
import os

/// 관리 탭 맨 아래 명령 상태 한 줄. 정본은 `ControlFragment.CommandUi`(:944-975)와
/// `renderCommand`(:977-991) — 스피너와 문구를 이 한 값에서만 만든다. 실패 문구 아래에서
/// 스피너가 계속 도는 화면(3단계 실기기 결함)을 구조적으로 막는다(:942-943).
enum ControlCommandUi: Equatable {
    case idle
    case sending
    case done
    /// 메시지가 아이 폰에 닿았지만 아직 '확인했어요'가 안 눌렸다. 기다리는 것이 네트워크가
    /// 아니라 **사람**이라 스피너를 안 돌린다(:949-956).
    case messageUnread
    /// 아이가 '확인했어요'를 눌렀다.
    case messageRead
    /// 이 폰의 큐에만 들어갔다. **실패가 아니다** — 연결되면 그대로 나가 아이 폰이 그때
    /// 실행한다. 그래서 오히려 말해줘야 한다(:961-972).
    case queued
    case failed(String)

    var isSpinning: Bool { self == .sending }

    var text: String? {
        switch self {
        case .idle: return nil
        case .sending: return String(localized: "control_command_sending")
        case .done: return String(localized: "control_command_done")
        case .messageUnread: return String(localized: "control_message_unread")
        case .messageRead: return String(localized: "control_message_read")
        case .queued: return String(localized: "control_command_queued")
        case .failed(let message): return message
        }
    }
}

/// 관리 탭. 부모가 버튼을 누르면 아이 폰이 바뀐다. 정본은 안드로이드 `guardian/ControlFragment.kt`.
///
/// 이 화면의 원칙은 **"정직한 표시"**다(:40-48). 명령을 보낸 뒤 그 문서 하나를 따라가며
/// `전달 중…` → `완료` 를 보여주고, 60초 안에 대답이 없으면 "애기폰이 응답하지 않아요"와
/// 마지막 신호 시각을 함께 띄운다. **"완료"가 뜻하는 것은 아이 폰이 done 이라고 적었다는
/// 것 하나뿐이다** — 실제로 실행했는지는 규칙으로 막을 수 없다(firestore.rules commands
/// update 주석). 그 이상을 뜻하는 문구를 쓰지 않는다.
///
/// 버튼은 일부러 잠그지 않는다(:478-482). 응답이 60초까지 걸리는데 그동안 버튼이 죽어
/// 있으면 고장으로 보인다. 대신 **세대 번호**로 화면의 주인을 하나로 못박는다(:98-118).
///
/// Firestore 쪽은 전부 주입받는다 — `MapViewModel` 과 같은 이유로, 세대·제한시간 순서를
/// 테스트가 결정적으로 재현하려면 진짜 왕복이 아니라 완료 시점을 정할 수 있는 자리가 필요하다.
@Observable
@MainActor
final class ControlViewModel {

    // MARK: - 상수 (ControlFragment.kt:1118-1153, fragment_control.xml)

    /// 아이 폰이 대답하기까지(:1132). 지도 탭과 같은 값이어야 한다(MapTimelineFragment.kt:1315-1316).
    nonisolated static let commandTimeoutMillis: Int64 = 60_000
    /// 이 쓰기가 서버에 닿기까지(:1134-1141). 오프라인이면 서버 확인이 영영 안 온다.
    nonisolated static let sendTimeoutMillis: Int64 = 15_000
    /// 자녀 폰 `FindPhoneController` 의 5분 자동 정지와 같은 값(:1143-1144).
    nonisolated static let findAutoStopMillis: Int64 = 5 * 60 * 1000
    /// 아침 7시 — "아침에 깨워줘"에 가장 가깝다(:1148-1149).
    nonisolated static let defaultAlarmMinute = 7 * 60
    /// `fragment_control.xml:359,366` — 넘치면 입력이 멈추고 카운터가 이유를 보여준다.
    nonisolated static let messageMaxLength = 100
    /// `fragment_control.xml:447` — 아이 폰 알림 제목 한 줄.
    nonisolated static let alarmLabelMaxLength = 20

    let familyId: String
    let childUid: String?

    // MARK: - 화면이 읽는 상태

    private(set) var commandUi: ControlCommandUi = .idle
    /// 아이 폰이 아직 안 붙었거나 설정을 못 읽을 때만 보이는 한 줄(`child_state`, xml :24-32).
    private(set) var 아이_안내: String?
    /// 마지막으로 읽은 아이 상태 문서. 화면을 열 때 한 번, 소리 조회 done 뒤 한 번 읽는다(:313-321).
    private(set) var 상태: ChildStatusDoc?
    /// `renderRingerState(loading = true)`(:243, :328) 자리. 처음엔 읽는 중이다.
    private(set) var 상태_읽는_중 = true
    /// 확인된 소리 모드. status 에서 읽었거나 이 화면에서 완료 응답을 받은 값(:131-133).
    private(set) var currentRingerMode: String?
    private(set) var ringerAppliedInSession = false
    /// 자녀 폰에 실제 소리 상태를 묻고 응답을 기다리는 동안 true(:135-136).
    private(set) var ringerQueryInFlight = false
    private(set) var lockEnabled = false
    /// 이 화면에서 폰찾기를 시작시킨 시각(부모 폰 시계). 0 이면 우리가 울린 적 없다(:178-182).
    private(set) var findStartedAt: Int64 = 0
    private(set) var 알람_기억: AlarmMemo?

    var alarmMinute = ControlViewModel.defaultAlarmMinute
    var 메시지 = ""
    var 알람_이름 = ""

    /// 대답을 적은 직후 부른다 — `GuardianRootView` 가 배너 판정으로 잇는다(:746-750).
    var 대답이_기록되면: (@MainActor () -> Void)?

    // MARK: - 주입

    private let requestLog: RequestLog
    private let alarmMemoStore: AlarmMemoStore
    private let commandSend: @Sendable (_ familyId: String, _ childUid: String, _ type: String, _ payload: [String: String]) async throws -> String
    private let commandObserve: @Sendable (
        _ familyId: String, _ childUid: String, _ commandId: String,
        _ onChange: @escaping (CommandDoc) -> Void, _ onError: @escaping (Error) -> Void
    ) -> ListenerRegistration
    private let statusFetch: @Sendable (_ familyId: String, _ childUid: String) async throws -> ChildStatusDoc?
    private let settingsObserve: @Sendable (
        _ familyId: String, _ childUid: String,
        _ onChange: @escaping (RingerSettingsDoc) -> Void, _ onError: @escaping (Error) -> Void
    ) -> ListenerRegistration
    private let lockSave: @Sendable (_ familyId: String, _ childUid: String, _ enabled: Bool) async throws -> Void
    private let serverNow: @Sendable (_ familyId: String) async throws -> Int64
    private let deviceNow: @Sendable () -> Int64
    private let commandSleep: @Sendable (_ millis: Int64) async -> Void

    // MARK: - 내부 상태

    /// 지금 화면이 따라가는 명령의 세대(:98-118). 발행 **전에** 붙잡고, 왕복 뒤·콜백 안·
    /// 제한시간 안에서 아직 최신인지 확인한다.
    private var commandGeneration = 0
    /// 따라가는 명령의 종류. `done` 하나가 명령마다 다른 일을 해야 해서 들고 있다(:120-129).
    private var trackingType: String?
    private var trackingRingerMode: String?
    /// 60초가 지나 "응답 없음"을 이미 띄웠는가. 늦은 pending/delivered 가 실패 문구를
    /// "전달 중…"으로 되돌리지 못하게 한다(:94-96).
    private var timedOut = false
    private var commandListener: ListenerRegistration?
    private var timeoutTask: Task<Void, Never>?
    private var settingsListener: ListenerRegistration?
    /// 부모가 방금 스위치로 만든 값. 아직 서버 스냅샷으로 되돌아오지 않았다(:170-176).
    private var pendingLockValue: Bool?
    private var findResetTask: Task<Void, Never>?
    /// 안드로이드 `statusJob?.cancel()`(:323)·`lockSaveJob?.cancel()`(:846) 대신 — Firestore
    /// 읽기·쓰기는 취소되지 않으므로 늦은 결과를 세대로 버린다.
    private var statusGeneration = 0
    private var lockGeneration = 0
    private var 시작_작업: Task<Void, Never>?

    /// 메시지만 `delivered` 의 뜻이 다르다(:138-156). 필드를 따로 두지 않고 종류에서 파생한다.
    private var trackingMessage: Bool { trackingType == CommandType.message }

    private static let logger = Logger(subsystem: "com.kidcare.family", category: "ControlViewModel")

    init(
        familyId: String,
        childUid: String?,
        requestLog: RequestLog = RequestLog(),
        alarmMemoStore: AlarmMemoStore = AlarmMemoStore(),
        commandSend: @escaping @Sendable (_ familyId: String, _ childUid: String, _ type: String, _ payload: [String: String]) async throws -> String = CommandRepository.send,
        commandObserve: @escaping @Sendable (
            _ familyId: String, _ childUid: String, _ commandId: String,
            _ onChange: @escaping (CommandDoc) -> Void, _ onError: @escaping (Error) -> Void
        ) -> ListenerRegistration = CommandRepository.observeOne,
        statusFetch: @escaping @Sendable (_ familyId: String, _ childUid: String) async throws -> ChildStatusDoc? = FamilyRepository.fetchChildStatus,
        settingsObserve: @escaping @Sendable (
            _ familyId: String, _ childUid: String,
            _ onChange: @escaping (RingerSettingsDoc) -> Void, _ onError: @escaping (Error) -> Void
        ) -> ListenerRegistration = ScheduleRepository.observeRingerSettings,
        lockSave: @escaping @Sendable (_ familyId: String, _ childUid: String, _ enabled: Bool) async throws -> Void = ScheduleRepository.setRingerLock,
        serverNow: @escaping @Sendable (_ familyId: String) async throws -> Int64 = { familyId in
            try await FamilyRepository.serverNow(familyId: familyId, uid: AuthGateway.currentUid())
        },
        deviceNow: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        commandSleep: @escaping @Sendable (_ millis: Int64) async -> Void = { millis in
            try? await Task.sleep(nanoseconds: UInt64(millis) * 1_000_000)
        }
    ) {
        self.familyId = familyId
        self.childUid = childUid
        self.requestLog = requestLog
        self.alarmMemoStore = alarmMemoStore
        self.commandSend = commandSend
        self.commandObserve = commandObserve
        self.statusFetch = statusFetch
        self.settingsObserve = settingsObserve
        self.lockSave = lockSave
        self.serverNow = serverNow
        self.deviceNow = deviceNow
        self.commandSleep = commandSleep
        알람_기억 = childUid.flatMap { alarmMemoStore.memo(childUid: $0) }
    }

    // MARK: - 화면이 그리는 값

    /// 아이 폰이 없으면 보낼 곳이 없다(:1074-1092). 입력칸·시각 고르기는 막지 않는다 —
    /// 미리 써 두는 것을 막을 이유가 없다. 막는 것은 보내는 버튼들뿐이다.
    var 버튼_활성화: Bool { childUid != nil }

    /// '새로 확인' 버튼(:1027, :1080).
    var 새로_확인_활성화: Bool { childUid != nil && !상태_읽는_중 && !ringerQueryInFlight }

    /// 아이 폰이 지금 울리고 있는지는 **알 방법이 없다** — 우리가 울린 지 5분이 안 됐으면
    /// 울린다고 믿는다(:875-899).
    var 울리는_중이라고_믿는가: Bool {
        findStartedAt != 0 && deviceNow() - findStartedAt < Self.findAutoStopMillis
    }

    func 선택된_모드인가(_ mode: String) -> Bool { currentRingerMode == mode }

    /// 소리 상태 줄(:994-1019). 방해 금지가 켜져 있으면 안드로이드가 모드를 무조건 '무음'으로
    /// 보고하므로, 그 값을 그대로 적지 않고 무슨 상태인지 있는 그대로 말한다.
    var 소리_상태_문구: String {
        if 상태_읽는_중 || ringerQueryInFlight { return String(localized: "control_ringer_status_loading") }
        if Dnd.isOn(상태?.dnd) {
            return String(format: String(localized: "control_ringer_status_format"), String(localized: "control_ringer_dnd"))
        }
        guard let 이름 = Self.소리_모드_이름(currentRingerMode) else {
            return String(localized: "control_ringer_status_unknown")
        }
        return ringerAppliedInSession
            ? String(format: String(localized: "control_ringer_status_applied"), 이름)
            : String(format: String(localized: "control_ringer_status_format"), 이름)
    }

    /// 안드로이드 `ic_volume_up`/`ic_vibration`/`ic_volume_off`(:1020-1026) 에 가장 가까운 그림.
    var 소리_상태_아이콘: String {
        switch currentRingerMode {
        case RingerMode.vibrate: return "iphone.radiowaves.left.and.right"
        case RingerMode.silent: return "speaker.slash.fill"
        default: return "speaker.wave.2.fill"
        }
    }

    /// 방해 금지 안내 줄(:1003).
    var 방해금지_안내를_보이는가: Bool { Dnd.isOn(상태?.dnd) && !(상태_읽는_중 || ringerQueryInFlight) }

    /// 인터넷 상태 첫 줄(:797-805). null 은 옛 문서·아직 안 올림, 빈 값은 못 읽음 — 둘 다 "모른다".
    var 인터넷_문구: String {
        switch 상태?.network {
        case NetworkKind.wifi: return String(localized: "control_network_wifi")
        case NetworkKind.cell: return String(localized: "control_network_cell")
        case NetworkKind.none: return String(localized: "control_network_none")
        default: return String(localized: "control_network_unknown")
        }
    }

    var 인터넷_아이콘: String {
        switch 상태?.network {
        case NetworkKind.cell: return "antenna.radiowaves.left.and.right"
        case NetworkKind.none: return "wifi.slash"
        default: return "wifi"
        }
    }

    /// 와이파이 스위치 줄(:807-817). `wifiOn == nil` 이면 줄을 감춘다 — false(꺼짐)와 다르다.
    var 와이파이_스위치_문구: String? {
        guard let on = 상태?.wifiOn else { return nil }
        return String(
            format: String(localized: "control_network_wifi_switch"),
            String(localized: on ? "control_network_on" : "control_network_off")
        )
    }

    /// 지금 걸려 있는 알람 한 줄(:912-931). 없으면 nil — 빈 줄로 자리를 잡지 않는다.
    var 알람_상태_문구: String? {
        guard let memo = 알람_기억 else { return nil }
        let time = Self.시각_문구(memo.minuteOfDay)
        let what = memo.label.isEmpty
            ? time
            : String(format: String(localized: "control_alarm_state_labeled"), time, memo.label)
        return String(
            format: String(localized: memo.confirmed ? "control_alarm_state_confirmed" : "control_alarm_state_pending"),
            what
        )
    }

    // MARK: - 시작과 정리

    /// 화면이 보일 때마다 불러도 된다 — 처음 한 번만 구독한다(안드로이드는 프래그먼트가
    /// 처음 만들어질 때 `subscribe` 한 번, show/hide 로는 다시 안 부른다). 뷰의 `.task` 가
    /// 아니라 뷰모델이 소유한 Task 인 이유는 `MapViewModel.처음이면_읽는다` 와 같다.
    @discardableResult
    func 시작한다() -> Task<Void, Never> {
        if let 시작_작업 { return 시작_작업 }
        let 작업 = Task { await self.구독을_시작한다() }
        시작_작업 = 작업
        return 작업
    }

    /// `subscribe`(:270-311). 안드로이드는 상태 읽기와 소리 조회를 나란히 띄우지만 여기서는
    /// 상태를 먼저 읽고 조회한다 — 문서 한 개 읽기만큼 조회가 늦어지는 대신 순서가 결정적이다.
    private func 구독을_시작한다() async {
        guard let childUid else {
            아이_안내 = String(localized: "map_no_child")
            // 안드로이드는 여기서 로딩 표시가 영영 남는다(판정 기록 5). iOS 는 끈다.
            상태_읽는_중 = false
            return
        }
        아이_안내 = nil
        settingsListener = settingsObserve(familyId, childUid, { [weak self] doc in
            Task { @MainActor in self?.잠금을_반영한다(doc.lockEnabled) }
        }, { [weak self] error in
            Task { @MainActor in self?.아이_안내 = errorMessage(error) }
        })
        await 상태를_읽는다(childUid: childUid, confirmedNow: false)
        await 소리_상태를_묻는다()
    }

    /// 보호자 화면이 통째로 사라질 때(`GuardianRootView.onDisappear`). `onDestroyView`(:1094-1116).
    /// 세대를 올려 이미 대기열에 오른 콜백까지 무해하게 만든다.
    func 정리한다() {
        settingsListener?.remove()
        settingsListener = nil
        stopTracking()
        commandGeneration += 1
        statusGeneration += 1
        lockGeneration += 1
        findResetTask?.cancel()
        findResetTask = nil
        ringerQueryInFlight = false
    }

    // MARK: - 명령

    func 소리_모드를_보낸다(_ mode: String) async {
        // 페이로드 키 "mode" 는 child/CommandHandler 가 읽는 키다(:353-355).
        await send(CommandType.setRinger, payload: [RingerMode.payloadKey: mode])
    }

    /// 서버에 남은 옛 값 대신 자녀 폰에 지금 모드를 묻는다(:358-367).
    func 소리_상태를_묻는다() async {
        guard childUid != nil, !ringerQueryInFlight else { return }
        ringerQueryInFlight = true
        await send(CommandType.queryRinger)
    }

    /// 큰 버튼(:209-211) — 울린다고 믿으면 끄고, 아니면 울린다.
    func 폰찾기_버튼을_눌렀다() async {
        if 울리는_중이라고_믿는가 { await 소리를_끈다() } else { await 폰을_찾는다() }
    }

    /// 명령이 실제로 만들어진 뒤에만 '소리 끄기'로 바꾼다 — 발행이 실패했는데 바꿔 두면
    /// 울리지도 않는 폰을 끄라고 하게 된다(:369-377).
    private func 폰을_찾는다() async {
        await send(CommandType.findPhone) { [weak self] in
            guard let self else { return }
            self.findStartedAt = self.deviceNow()
            self.폰찾기_되돌리기를_건다(after: Self.findAutoStopMillis)
        }
    }

    /// '이미 울리고 있다면 소리 끄기'도 이 함수를 쓴다(:212, :379-386). 울리지 않을 때 와도
    /// 아이 폰에서 아무 일 없이 지나간다.
    func 소리를_끈다() async {
        await send(CommandType.stopFind) { [weak self] in
            guard let self else { return }
            self.findStartedAt = 0
            self.findResetTask?.cancel()
            self.findResetTask = nil
        }
    }

    /// 입력칸은 발행이 **성공한 뒤** 비운다 — 오프라인에서 실패하면 방금 쓴 문장이 남아야
    /// 한다. 길이는 입력칸이 이미 막으므로 여기서 다시 자르지 않는다(:388-408).
    func 메시지를_보낸다() async {
        let text = 메시지.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            commandUi = .failed(String(localized: "control_message_empty"))
            return
        }
        await send(CommandType.message, payload: [CommandType.payloadText: text]) { [weak self] in
            self?.메시지 = ""
        }
    }

    /// 보내는 것은 하루 안의 분과 이름뿐이다 — 절대 시각을 여기서 계산하면 두 폰의 시간대·
    /// 시계 차이가 그대로 어긋남이 된다. 기억은 발행 성공에서 적고 done 에서 굳힌다(:435-459).
    func 알람을_맞춘다() async {
        guard let childUid else { return }
        let label = 알람_이름.trimmingCharacters(in: .whitespacesAndNewlines)
        let minute = alarmMinute
        await send(
            CommandType.setAlarm,
            payload: [CommandType.payloadAtMinuteOfDay: String(minute), CommandType.payloadLabel: label]
        ) { [weak self] in
            guard let self else { return }
            self.alarmMemoStore.recordSent(childUid: childUid, minuteOfDay: minute, label: label)
            self.알람_기억을_다시_읽는다()
        }
    }

    /// 기억은 발행이 성공한 순간 지운다 — 남겨 두면 '알람 끄기'를 누른 화면에 "맞춰져
    /// 있어요"가 남아 부모가 한 번 더 누른다(:461-473).
    func 알람을_끈다() async {
        guard let childUid else { return }
        await send(CommandType.cancelAlarm) { [weak self] in
            guard let self else { return }
            self.alarmMemoStore.clear(childUid: childUid)
            self.알람_기억을_다시_읽는다()
        }
    }

    /// 명령을 발행하고 그 문서 하나를 따라간다(:475-570).
    private func send(
        _ type: String,
        payload: [String: String] = [:],
        onSent: @escaping @MainActor () -> Void = {}
    ) async {
        guard let childUid else {
            commandUi = .failed(String(localized: "map_no_child"))
            return
        }
        // 조회 중 다른 명령을 누르면 그 명령이 화면의 새 주인이다(:499-504).
        if trackingType == CommandType.queryRinger && type != CommandType.queryRinger {
            ringerQueryInFlight = false
        }
        stopTracking()
        timedOut = false
        trackingType = type
        trackingRingerMode = type == CommandType.setRinger ? payload[RingerMode.payloadKey] : nil
        commandGeneration += 1
        let generation = commandGeneration
        // 명령 종류와 상관없이 "물어봤다"로 친다 — 강제 종료된 폰은 무엇에도 대답이 없다(:516-519).
        requestLog.recordRequest(childUid)
        commandUi = .sending

        let familyId = self.familyId
        let sendCommand = commandSend
        do {
            let commandId = try await firstToFinish(timeoutMillis: Self.sendTimeoutMillis, sleep: commandSleep) {
                try await sendCommand(familyId, childUid, type, payload)
            }
            guard let commandId else {
                // 큐에 들어간 것은 나간 것이 아니다 — onSent 를 부르면 안 된다(:537-547).
                guard generation == commandGeneration else { return }
                ringerQueryFinishedIfCurrent(type)
                commandUi = .queued
                return
            }
            // onSent 는 세대와 상관없이 부른다 — "명령이 실제로 발행됐다"는 사실이다(:548-552).
            onSent()
            guard generation == commandGeneration else { return }
            track(childUid: childUid, commandId: commandId, generation: generation)
        } catch is CancellationError {
            return
        } catch {
            guard generation == commandGeneration else { return }
            ringerQueryFinishedIfCurrent(type)
            commandUi = .failed(errorMessage(error))
        }
    }

    /// 명령 문서 하나를 따라간다(:572-606). 리스너 콜백도 제한시간도 세대가 최신일 때만
    /// 화면을 만진다 — `remove()` 는 이미 큐에 오른 콜백까지 되돌리지 않는다.
    private func track(childUid: String, commandId: String, generation: Int) {
        stopTracking()
        commandListener = commandObserve(familyId, childUid, commandId, { [weak self] doc in
            Task { @MainActor in
                guard let self, generation == self.commandGeneration else { return }
                self.명령이_바뀌었다(doc)
            }
        }, { [weak self] error in
            Task { @MainActor in
                guard let self, generation == self.commandGeneration else { return }
                self.timeoutTask?.cancel()
                self.timeoutTask = nil
                self.ringerQueryFinishedIfCurrent(self.trackingType)
                self.commandUi = .failed(errorMessage(error))
            }
        })
        let sleep = commandSleep
        let timeout = Self.commandTimeoutMillis
        timeoutTask = Task { @MainActor [weak self] in
            await sleep(timeout)
            guard !Task.isCancelled, let self, generation == self.commandGeneration else { return }
            await self.시간이_지났다(generation: generation)
        }
    }

    /// `onCommandChanged`(:608-676). 리스너는 done 뒤에도 떼지 않는다 — 안드로이드와 같다.
    /// 끝난 문서는 더 안 바뀌고, 메시지는 delivered 에서 몇 시간 뒤 done 이 될 수 있다.
    private func 명령이_바뀌었다(_ doc: CommandDoc) {
        switch doc.state {
        case CommandState.done:
            timeoutTask?.cancel()
            timeoutTask = nil
            대답을_기록한다()
            if trackingType == CommandType.setAlarm, let childUid {
                alarmMemoStore.recordConfirmed(childUid: childUid)
                알람_기억을_다시_읽는다()
            }
            if trackingType == CommandType.setRinger, let mode = trackingRingerMode, RingerMode.isKnown(mode) {
                currentRingerMode = mode
                ringerAppliedInSession = true
            }
            if trackingType == CommandType.queryRinger {
                ringerQueryInFlight = false
                if let childUid {
                    Task { await self.상태를_읽는다(childUid: childUid, confirmedNow: true) }
                }
            }
            // 메시지의 done 은 "아이가 확인했어요를 눌렀다" — '완료'라고 적으면 다른 말이 된다(:635-637).
            commandUi = trackingMessage ? .messageRead : .done
        case CommandState.failed:
            timeoutTask?.cancel()
            timeoutTask = nil
            // 알람이 안 걸렸는데 "맞춰져 있어요"가 남으면 이 기능에서 제일 나쁜 거짓말이다(:642-647).
            if trackingType == CommandType.setAlarm, let childUid {
                alarmMemoStore.clear(childUid: childUid)
                알람_기억을_다시_읽는다()
            }
            ringerQueryFinishedIfCurrent(trackingType)
            // 실패도 대답이다 — 아이 폰이 살아 있으니 error 를 적을 수 있었다(:649-652).
            대답을_기록한다()
            commandUi = .failed(아이_오류_문구(doc.error))
        case CommandState.pending, CommandState.delivered:
            if trackingMessage && doc.state == CommandState.delivered {
                // 메시지는 여기가 종착역일 수 있다 — 60초 타이머를 끄고, delivered 자체를
                // 대답으로 친다(:658-669).
                timeoutTask?.cancel()
                timeoutTask = nil
                대답을_기록한다()
                commandUi = .messageUnread
            } else if !timedOut {
                commandUi = .sending
            }
        default:
            break
        }
    }

    /// 60초 무응답(:678-708). "실패했다"가 아니라 "대답이 없다" — 리스너는 떼지 않아 늦게라도
    /// done 이 오면 "완료"로 고쳐진다. 문구를 먼저 확정하고, 서버 시각을 잰 뒤 마지막 신호를
    /// 채운다. await 뒤에는 세대를 다시 본다(:697-701).
    private func 시간이_지났다(generation: Int) async {
        timedOut = true
        ringerQueryFinishedIfCurrent(trackingType)
        commandUi = .failed(String(localized: "control_command_timeout"))

        let 신호_문구: String
        if let 상태, StatusCard.signal(status: 상태) != nil {
            // 서버 시각으로 뺀다 — 부모 폰 시계가 뒤처져 있으면 "-3분 전"이 찍힌다(:717-719).
            let now = (try? await serverNow(familyId)) ?? deviceNow()
            guard generation == commandGeneration else { return }
            신호_문구 = String(
                format: String(localized: "control_last_seen_format"),
                lastSignalText(StatusCard.lastSignal(status: 상태, nowMillis: now))
            )
        } else {
            신호_문구 = String(localized: "control_last_seen_never")
        }
        guard generation == commandGeneration else { return }
        commandUi = .failed(String(format: String(localized: "control_command_timeout_format"), 신호_문구))
    }

    // MARK: - 잠금 스위치

    /// 스위치를 민 값을 저장한다(:828-871). 오프라인에서도 Firestore 가 로컬 쓰기를 즉시
    /// 되돌려주므로 화면은 저장된 것처럼 보인다 — 서버 확인이 15초 안에 안 오면 그 사실만
    /// 말하고 스위치는 되돌리지 않는다(쓰기는 큐에 살아 있다). 진짜 실패면 되돌리고 이유를 말한다.
    func 잠금을_바꾼다(_ enabled: Bool) async {
        guard let childUid else {
            commandUi = .failed(String(localized: "map_no_child"))
            return
        }
        lockEnabled = enabled
        pendingLockValue = enabled
        lockGeneration += 1
        let generation = lockGeneration
        let familyId = self.familyId
        let save = lockSave
        do {
            let saved: Void? = try await firstToFinish(timeoutMillis: Self.sendTimeoutMillis, sleep: commandSleep) {
                try await save(familyId, childUid, enabled)
            }
            guard generation == lockGeneration else { return }
            if saved == nil { commandUi = .queued }
        } catch is CancellationError {
            return
        } catch {
            guard generation == lockGeneration else { return }
            pendingLockValue = nil
            lockEnabled = !enabled
            commandUi = .failed(errorMessage(error))
        }
    }

    /// 서버 값을 반영한다(:776-785, :820-826). 부모가 방금 만진 값이 아직 안 돌아왔으면
    /// 그대로 둔다 — 늦게 온 첫 읽기가 방금 켠 스위치를 도로 끄지 않게.
    private func 잠금을_반영한다(_ enabled: Bool) {
        if let pending = pendingLockValue, pending != enabled { return }
        pendingLockValue = nil
        lockEnabled = enabled
    }

    // MARK: - 도우미

    /// `loadStatus`(:313-348). 못 읽어도 화면 전체를 오류로 덮지 않는다 — 이 값은 무응답
    /// 문구의 보조 정보다.
    private func 상태를_읽는다(childUid: String, confirmedNow: Bool) async {
        statusGeneration += 1
        let generation = statusGeneration
        if !confirmedNow {
            currentRingerMode = nil
            ringerAppliedInSession = false
        }
        상태_읽는_중 = true
        do {
            let status = try await statusFetch(familyId, childUid)
            guard generation == statusGeneration else { return }
            상태 = status
            currentRingerMode = status.map(\.ringerMode).flatMap { RingerMode.isKnown($0) ? $0 : nil }
            ringerAppliedInSession = confirmedNow
            상태_읽는_중 = false
        } catch is CancellationError {
            return
        } catch {
            guard generation == statusGeneration else { return }
            Self.logger.error("아이 상태를 못 읽었다: \(String(describing: error), privacy: .public)")
            상태_읽는_중 = false
        }
    }

    private func 폰찾기_되돌리기를_건다(after millis: Int64) {
        findResetTask?.cancel()
        let sleep = commandSleep
        findResetTask = Task { @MainActor [weak self] in
            await sleep(max(millis, 0))
            guard !Task.isCancelled, let self else { return }
            self.findStartedAt = 0
        }
    }

    private func stopTracking() {
        commandListener?.remove()
        commandListener = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    /// 따라가던 것이 소리 조회일 때만 조회 중 표시를 끝낸다(:1053-1058).
    private func ringerQueryFinishedIfCurrent(_ type: String?) {
        guard type == CommandType.queryRinger else { return }
        ringerQueryInFlight = false
    }

    private func 대답을_기록한다() {
        guard let childUid else { return }
        requestLog.recordAnswer(childUid)
        대답이_기록되면?()
    }

    private func 알람_기억을_다시_읽는다() {
        알람_기억 = childUid.flatMap { alarmMemoStore.memo(childUid: $0) }
    }

    /// 자녀 폰이 `error` 에 남긴 코드를 문장으로(:752-767). 부모가 할 수 있는 일이 분명한
    /// 코드는 그 일까지 문장에 담는다.
    private func 아이_오류_문구(_ raw: String) -> String {
        switch raw {
        case RingerMode.errorDenied: return String(localized: "control_error_ringer_denied")
        case CommandType.errorNotificationOff: return String(localized: "control_error_message_notification_off")
        case CommandType.errorAlarmExactDenied: return String(localized: "control_error_alarm_exact_denied")
        default: return String(localized: "control_error_child_failed")
        }
    }

    private static func 소리_모드_이름(_ mode: String?) -> String? {
        switch mode {
        case RingerMode.normal: return String(localized: "control_mode_normal")
        case RingerMode.vibrate: return String(localized: "control_mode_vibrate")
        case RingerMode.silent: return String(localized: "control_mode_silent")
        default: return nil
        }
    }

    /// `ScheduleText.timeText`(ScheduleAdapter.kt:186-187) — 판정 기록 4.
    static func 시각_문구(_ minuteOfDay: Int) -> String {
        String(format: String(localized: "schedule_time_format"), minuteOfDay / 60, minuteOfDay % 60)
    }
}
```

- [ ] **Step 9: 통과 확인**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: 전체 PASS — `ControlViewModelTests` 17개, `AlarmMemoStoreTests` 5개, `ScheduleRepositoryTests` 3개 포함. `LocalizableCatalogTests` 가 초록이면 Step 7 키 목록이 뷰모델 코드와 맞다는 뜻이다.

그리고 앱 코드에 금지된 것이 없는지:

```bash
grep -rn "@unchecked Sendable\|nonisolated(unsafe)" ios/KidCare   # 비어 있어야 한다
```

- [ ] **Step 10: 커밋** (공통 절차 B)

```bash
git add ios/KidCare/Core/Documents.swift ios/KidCare/Core/ScheduleRepository.swift ios/KidCare/Guardian/FirstToFinish.swift \
  ios/KidCare/Guardian/MapViewModel.swift ios/KidCare/Guardian/AlarmMemoStore.swift ios/KidCare/Guardian/ControlViewModel.swift \
  ios/KidCare/Localizable.xcstrings ios/KidCareTests/EmulatorHarness.swift ios/KidCareTests/CommandRepositoryTests.swift \
  ios/KidCareTests/ScheduleRepositoryTests.swift ios/KidCareTests/AlarmMemoStoreTests.swift ios/KidCareTests/ControlViewModelTests.swift
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "iOS 4단계 Task 3: 관리 탭 상태 기계 — 소리·폰찾기·메시지·알람·잠금을 정직하게 따라간다"
```

---

### Task 4: 관리 탭 화면

**끝나면 '관리' 탭을 누르면 인터넷 상태 카드, 소리 상태와 벨소리·진동·무음 버튼, 잠금 스위치, 핸드폰 찾기, 한마디 보내기, 알람 맞추기, 맨 아래 명령 상태 줄이 안드로이드와 같은 순서·색으로 뜬다.**

**Files:**
- Create: `ios/KidCare/Guardian/ControlView.swift`
- Modify: `ios/KidCare/Guardian/GuardianRootView.swift`
- Modify: `ios/KidCare/Localizable.xcstrings`
- Test: `ios/KidCareTests/ControlClockTests.swift`

**Interfaces:**
- Consumes: Task 3 의 `ControlViewModel` 공개면 전부, `ControlCommandUi.isSpinning`/`text`; Task 1 의 `KidCarePalette`·`GuardianTab`; Task 2 의 `GuardianRootView.init` 안 `banner`
- Produces:
  - `struct ControlView: View { let viewModel: ControlViewModel }`
  - `enum ControlInput { static func clamp(_ text: String, max: Int) -> String; static func date(minuteOfDay: Int, calendar: Calendar = .current) -> Date; static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int }`

**정본:** `fragment_control.xml` 전체(위에서 아래 순서 그대로), `ControlFragment.onViewCreated`(:194-251), `renderRingerState`(:1029-1044 선택 버튼 색 `sky`/`sky_soft`, 글자 `on_accent`/`sky`), `renderFindButton`(:891-896), `showAlarmTimePicker`(:412-426, 24시간 고정). 치수: 좌우 `@dimen/edge` = 20dp(`dimens.xml:17`), 위 20·아래 28(xml :20-22), 카드 모서리 `ShapeAppearance.KidCare.Small` = 12dp(`themes.xml:82-85`), 구역 제목 15sp medium `ink`, 모드 버튼 높이 72·간격 6+6, 찾기 버튼 64, 보내기·맞추기 58, 구분선 위아래 20.

**화면이 하는 일은 그리기와 뷰모델 호출뿐이다.** 모든 판단(버튼이 무엇을 보낼지, 무슨 문구를 쓸지)은 Task 3 뷰모델에 있다.

- [ ] **Step 1: 입력 도우미 테스트를 먼저 쓴다**

`ios/KidCareTests/ControlClockTests.swift`:

```swift
import Foundation
import Testing
@testable import KidCare

/// 관리 탭 화면의 순수 도우미. 알람 시각은 하루 안의 분(0~1439)으로만 오간다 —
/// 절대 시각을 만들지 않는다(ControlFragment.kt:160-164).
struct ControlClockTests {

    private var 달력: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }

    @Test("하루 안의 분 → 시각 → 분 이 그대로 돌아온다")
    func 분_왕복() {
        for minute in [0, 7 * 60, 7 * 60 + 30, 23 * 60 + 59] {
            let date = ControlInput.date(minuteOfDay: minute, calendar: 달력)
            #expect(ControlInput.minuteOfDay(date, calendar: 달력) == minute)
        }
    }

    @Test("입력 길이는 안드로이드 maxLength 에서 멈춘다 — 메시지 100, 알람 이름 20")
    func 길이_제한() {
        #expect(ControlInput.clamp(String(repeating: "가", count: 101), max: ControlViewModel.messageMaxLength).count == 100)
        #expect(ControlInput.clamp(String(repeating: "a", count: 21), max: ControlViewModel.alarmLabelMaxLength).count == 20)
        #expect(ControlInput.clamp("학원", max: 20) == "학원")
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/ControlClockTests`
Expected: 컴파일 실패 — `ControlInput` 이 없다.

- [ ] **Step 3: 화면이 쓰는 문구 키를 넣는다**

모두 `i18n/ko.json` 에 있는 안드로이드 키다. 공통 절차 A:

```
KEYS="control_section_network control_network_readonly control_section_ringer control_ringer_refresh control_ringer_dnd_note control_lock_switch control_lock_hint control_find_phone control_find_stop control_find_hint control_find_stop_hint control_section_message control_message_chip_where control_message_chip_call control_message_chip_come_home control_message_chip_meal control_message_hint control_message_send control_message_hint_detail control_section_alarm control_alarm_picker_title control_alarm_label_hint control_alarm_set control_alarm_cancel control_alarm_hint_detail"
```

- [ ] **Step 4: 화면을 만든다**

`ios/KidCare/Guardian/ControlView.swift`:

```swift
import SwiftUI

/// 관리 탭 화면. 정본은 안드로이드 `fragment_control.xml` — 구역 순서(인터넷 → 소리 → 잠금 →
/// 폰찾기 → 한마디 → 알람 → 상태 줄)와 색·치수를 그대로 옮긴다. 판단은 전부 `ControlViewModel`.
///
/// 소리 모드 버튼 셋을 채운 색이 아니라 옅은 색으로 둔 이유(xml :6-9): 셋 다 진하면 "지금
/// 눌러야 할 것"이 셋으로 보이는데, 이 화면에서 진짜 강한 동작은 핸드폰 찾기 하나뿐이다.
struct ControlView: View {

    let viewModel: ControlViewModel

    /// 칩은 입력칸을 채우기만 한다 — 잘못 누른 한 줄은 아이 폰에 이미 떠서 되돌릴 수 없다(xml :300-303).
    private let 칩_문구: [String.LocalizationValue] = [
        "control_message_chip_where", "control_message_chip_call",
        "control_message_chip_come_home", "control_message_chip_meal",
    ]

    var body: some View {
        @Bindable var vm = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let 안내 = viewModel.아이_안내 {
                    Text(안내)
                        .font(.subheadline)
                        .foregroundStyle(KidCarePalette.inkSoft)
                        .padding(.bottom, 16)
                }

                구역_제목("control_section_network").padding(.top, 4)
                인터넷_카드.padding(.top, 8)

                구역_제목("control_section_ringer")
                소리_상태_카드.padding(.top, 8)
                if viewModel.방해금지_안내를_보이는가 {
                    보조_문구("control_ringer_dnd_note").padding(.top, 6)
                }
                모드_버튼들.padding(.top, 8)

                Toggle(isOn: Binding(
                    get: { viewModel.lockEnabled },
                    set: { 값 in Task { await viewModel.잠금을_바꾼다(값) } }
                )) {
                    Text("control_lock_switch").font(.body).foregroundStyle(KidCarePalette.ink)
                }
                .tint(KidCarePalette.sky)
                .frame(minHeight: 48)
                .padding(.top, 20)
                보조_문구("control_lock_hint")

                구분선

                폰찾기_구역

                구분선

                구역_제목("control_section_message")
                줄바꿈_배치(간격: 8) {
                    ForEach(칩_문구.indices, id: \.self) { i in
                        Button {
                            vm.메시지 = String(localized: 칩_문구[i])
                        } label: {
                            Text(String(localized: 칩_문구[i]))
                                .font(.subheadline)
                                .foregroundStyle(KidCarePalette.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .overlay(Capsule().stroke(KidCarePalette.inkSoft.opacity(0.4)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 10)
                TextField("control_message_hint", text: $vm.메시지, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 8)
                    .onChange(of: vm.메시지) { _, 새_값 in
                        let 잘린_값 = ControlInput.clamp(새_값, max: ControlViewModel.messageMaxLength)
                        if 잘린_값 != 새_값 { vm.메시지 = 잘린_값 }
                    }
                // counterEnabled — 100자에서 입력이 멈출 때 왜 멈췄는지 보인다(xml :349-351).
                Text("\(viewModel.메시지.count)/\(ControlViewModel.messageMaxLength)")
                    .font(.caption)
                    .foregroundStyle(KidCarePalette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                옅은_버튼("control_message_send", 그림: "paperplane.fill") {
                    await viewModel.메시지를_보낸다()
                }
                .padding(.top, 8)
                보조_문구("control_message_hint_detail").padding(.top, 8)

                구분선

                구역_제목("control_section_alarm")
                if let 알람 = viewModel.알람_상태_문구 {
                    Text(알람)
                        .font(.subheadline)
                        .foregroundStyle(KidCarePalette.inkSoft)
                        .padding(.top, 8)
                }
                // 24시간 고정(:412-426) — en_GB 로캘이 "07:30" 으로 보인다. 숫자로 입력하게
                // 하지 않는 이유는 0~1439 밖 값이 생길 수 있어서다(xml :398-399).
                DatePicker(
                    selection: Binding(
                        get: { ControlInput.date(minuteOfDay: viewModel.alarmMinute) },
                        set: { vm.alarmMinute = ControlInput.minuteOfDay($0) }
                    ),
                    displayedComponents: .hourAndMinute
                ) {
                    Label("control_alarm_picker_title", systemImage: "alarm")
                        .foregroundStyle(KidCarePalette.ink)
                }
                .environment(\.locale, Locale(identifier: "en_GB"))
                .frame(minHeight: 64)
                .padding(.horizontal, 14)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(KidCarePalette.inkSoft.opacity(0.4)))
                .padding(.top, 10)
                TextField("control_alarm_label_hint", text: $vm.알람_이름)
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 8)
                    .onChange(of: vm.알람_이름) { _, 새_값 in
                        let 잘린_값 = ControlInput.clamp(새_값, max: ControlViewModel.alarmLabelMaxLength)
                        if 잘린_값 != 새_값 { vm.알람_이름 = 잘린_값 }
                    }
                옅은_버튼("control_alarm_set", 그림: "alarm") {
                    await viewModel.알람을_맞춘다()
                }
                .padding(.top, 8)
                // 폰찾기의 '이미 울리고 있다면'과 같은 이유로 늘 살아 있다(xml :465-467).
                글자_버튼("control_alarm_cancel") { await viewModel.알람을_끈다() }
                    .padding(.top, 4)
                보조_문구("control_alarm_hint_detail").padding(.top, 8)

                명령_상태_줄.padding(.top, 16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .background(KidCarePalette.paper)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - 구역

    private var 인터넷_카드: some View {
        // 보기만 한다 — 끄고 켜기는 안드로이드가 다른 앱에 허용하지 않는다는 사실을 카드 안에 적는다(xml :43-45).
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: viewModel.인터넷_아이콘)
                .font(.system(size: 18))
                .foregroundStyle(KidCarePalette.sky)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(viewModel.인터넷_문구).font(.subheadline).foregroundStyle(KidCarePalette.ink)
                if let 스위치 = viewModel.와이파이_스위치_문구 {
                    Text(스위치).font(.caption).foregroundStyle(KidCarePalette.inkSoft).padding(.top, 1)
                }
                보조_문구("control_network_readonly").padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(KidCarePalette.skySoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var 소리_상태_카드: some View {
        HStack(spacing: 9) {
            Image(systemName: viewModel.소리_상태_아이콘)
                .font(.system(size: 18))
                .foregroundStyle(KidCarePalette.grass)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(viewModel.소리_상태_문구)
                .font(.subheadline)
                .foregroundStyle(KidCarePalette.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await viewModel.소리_상태를_묻는다() }
            } label: {
                Label("control_ringer_refresh", systemImage: "arrow.clockwise").font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(KidCarePalette.sky)
            .disabled(!viewModel.새로_확인_활성화)
            .opacity(viewModel.새로_확인_활성화 ? 1 : 0.38)
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .background(KidCarePalette.grassSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var 모드_버튼들: some View {
        HStack(spacing: 12) {
            모드_버튼(RingerMode.normal, 문구: "control_mode_normal", 그림: "speaker.wave.2.fill")
            모드_버튼(RingerMode.vibrate, 문구: "control_mode_vibrate", 그림: "iphone.radiowaves.left.and.right")
            모드_버튼(RingerMode.silent, 문구: "control_mode_silent", 그림: "speaker.slash.fill")
        }
    }

    /// 그림을 위, 이름을 아래 두 줄로 — 셋으로 갈린 폭에서 큰 글꼴이면 한 줄은 말줄임으로 잘린다(xml :185-186).
    private func 모드_버튼(_ mode: String, 문구: LocalizedStringKey, 그림: String) -> some View {
        let 선택됨 = viewModel.선택된_모드인가(mode)
        return Button {
            Task { await viewModel.소리_모드를_보낸다(mode) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: 그림).font(.system(size: 20))
                Text(문구).font(.subheadline.weight(.medium))
            }
            .foregroundStyle(선택됨 ? KidCarePalette.onAccent : KidCarePalette.sky)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(선택됨 ? KidCarePalette.sky : KidCarePalette.skySoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.버튼_활성화)
        .opacity(viewModel.버튼_활성화 ? 1 : 0.38)
    }

    private var 폰찾기_구역: some View {
        let 울리는_중 = viewModel.울리는_중이라고_믿는가
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                Task { await viewModel.폰찾기_버튼을_눌렀다() }
            } label: {
                Label(울리는_중 ? "control_find_stop" : "control_find_phone", systemImage: "bell.and.waves.left.and.right")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(KidCarePalette.onBerry)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(KidCarePalette.berry, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.버튼_활성화)
            .opacity(viewModel.버튼_활성화 ? 1 : 0.38)
            보조_문구("control_find_hint").padding(.top, 8)
            // 앱을 새로 열면 아이 폰이 울리는지 알 방법이 없다 — 언제든 끌 길을 열어 둔다.
            // 우리가 방금 울렸으면 큰 버튼이 같은 일을 하므로 숨긴다(:886-887).
            if !울리는_중 {
                글자_버튼("control_find_stop_hint") { await viewModel.소리를_끈다() }
                    .padding(.top, 4)
            }
        }
    }

    /// 명령 상태 한 줄(xml :484-506). 스피너는 `sending` 에서만 돈다.
    private var 명령_상태_줄: some View {
        HStack(spacing: 10) {
            if viewModel.commandUi.isSpinning {
                ProgressView().controlSize(.small)
            }
            if let 문구 = viewModel.commandUi.text {
                Text(문구).font(.subheadline).foregroundStyle(KidCarePalette.ink)
            }
        }
    }

    // MARK: - 조각

    private func 구역_제목(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(KidCarePalette.ink)
    }

    private func 보조_문구(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption)
            .foregroundStyle(KidCarePalette.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var 구분선: some View {
        Divider().padding(.vertical, 20)
    }

    /// `Widget.KidCare.Button.Tonal` 높이 58.
    private func 옅은_버튼(_ key: LocalizedStringKey, 그림: String, action: @escaping @MainActor () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Label(key, systemImage: 그림)
                .font(.headline)
                .foregroundStyle(KidCarePalette.sky)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(KidCarePalette.skySoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.버튼_활성화)
        .opacity(viewModel.버튼_활성화 ? 1 : 0.38)
    }

    /// `Widget.KidCare.Button.Text`.
    private func 글자_버튼(_ key: LocalizedStringKey, action: @escaping @MainActor () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(key)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(KidCarePalette.sky)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.버튼_활성화)
        .opacity(viewModel.버튼_활성화 ? 1 : 0.38)
    }
}

/// 칩 넷을 폭에 맞춰 줄바꿈한다 — 안드로이드 `ChipGroup` 기본 간격 8dp.
private struct 줄바꿈_배치: Layout {
    var 간격: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let 너비 = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, 줄높이: CGFloat = 0, 최대너비: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > 너비 {
                x = 0
                y += 줄높이 + 간격
                줄높이 = 0
            }
            x += size.width + 간격
            줄높이 = max(줄높이, size.height)
            최대너비 = max(최대너비, x - 간격)
        }
        return CGSize(width: 최대너비, height: y + 줄높이)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, 줄높이: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += 줄높이 + 간격
                줄높이 = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + 간격
            줄높이 = max(줄높이, size.height)
        }
    }
}

/// 관리 탭 화면의 순수 도우미.
enum ControlInput {

    /// 안드로이드 `android:maxLength` — 넘치는 글자는 들어오는 즉시 자른다.
    static func clamp(_ text: String, max: Int) -> String {
        String(text.prefix(max))
    }

    /// 하루 안의 분을 `DatePicker` 가 다룰 날짜로. 날짜 부분은 의미가 없다 — 명령에는 분만 간다.
    /// 2001-01-01 을 쓰는 이유: 어느 시간대에서도 서머타임 전환일이 아니라 시·분이 그대로 돌아온다.
    static func date(minuteOfDay: Int, calendar: Calendar = .current) -> Date {
        let components = DateComponents(year: 2001, month: 1, day: 1, hour: minuteOfDay / 60, minute: minuteOfDay % 60)
        return calendar.date(from: components) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
```

- [ ] **Step 5: 탭에 붙인다**

`ios/KidCare/Guardian/GuardianRootView.swift`:

1. 프로퍼티에 `@State private var controlViewModel: ControlViewModel` 를 더한다.
2. `init` 에서 배너를 만든 뒤:

```swift
        let control = ControlViewModel(familyId: familyId, childUid: childUid)
        // 관리 탭의 대답도 배너를 곧바로 다시 판정하게 한다(ControlFragment.kt:747-750).
        control.대답이_기록되면 = { [weak banner] in banner?.다시_판정한다() }
        _controlViewModel = State(initialValue: control)
```

3. `TabPlaceholderView(tab: .control)` 를 아래로 바꾼다:

```swift
            ControlView(viewModel: controlViewModel)
                // 안드로이드는 관리 탭을 처음 보여줄 때 프래그먼트를 만들고 subscribe 한다
                // (showTab 의 tx.add :339-341). 두 번째부터는 뷰모델이 무시한다.
                .onAppear { controlViewModel.시작한다() }
                .tabItem { Label(GuardianTab.control.title, systemImage: GuardianTab.control.systemImage) }
                .tag(GuardianTab.control)
```

4. `.onDisappear` 에 `controlViewModel.정리한다()` 를 더한다.

- [ ] **Step 6: 통과 확인**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: 전체 PASS — `ControlClockTests` 2개 포함, `LocalizableCatalogTests.코드가_부르는_키는_카탈로그에_있다` 가 Step 3 키 목록을 확인한다. 화면 모양은 "단계 마무리" 시뮬레이터 확인에서 본다(이 계획서는 Task 마다 눈으로 보지 않는다 — 브리프).

- [ ] **Step 7: 커밋** (공통 절차 B)

```bash
git add ios/KidCare/Guardian/ControlView.swift ios/KidCare/Guardian/GuardianRootView.swift ios/KidCare/Localizable.xcstrings ios/KidCareTests/ControlClockTests.swift
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "iOS 4단계 Task 4: 관리 탭 화면 — 안드로이드 순서·색 그대로, 판단은 뷰모델에"
```

---

### Task 5: 초대 코드 입력칸 — 한글 자판이 안 뜨게

**끝나면 '가족에 합류하기' 화면의 코드 칸을 누르면 영문 대문자 자판이 뜨고, 한글 자판으로 바꿀 수 없으며, 8자에서 입력이 멈춘다.** 알려진 버그: 기기 언어가 한국어면 기본 자판이 한글이라 `ㅁㅠㅊ234` 처럼 들어가고, `InviteCode.normalize` 는 자모를 못 고쳐 합류 버튼이 영영 안 켜진다.

**Files:**
- Create: `ios/KidCare/Onboarding/InviteCodeField.swift`
- Modify: `ios/KidCare/Onboarding/JoinFamilyView.swift:25-30`
- Test: `ios/KidCareTests/InviteCodeFieldTests.swift`

**Interfaces:**
- Consumes: `InviteCode.normalize(_:)`·`isValid(_:)` (`Logic/InviteCode.swift`, 2단계)
- Produces: `enum InviteCodeField { static let maxLength = 8; static func clamp(_ raw: String) -> String }`, `extension View { func inviteCodeKeyboard() -> some View }`

**정본:** `activity_child_pairing.xml:41-50` — `inputType="textCapCharacters"`(대문자 자판), `maxLength="8"`. `ChildPairingActivity.kt:52-55` — 글자가 바뀔 때마다 `InviteCode.isValid` 로 버튼을 켜고 끈다(iOS 는 이미 `보낼_수_있나` 로 같다).

**키보드 설정을 `InviteCode.normalize` 에 맞춘 근거.** `normalize` 는 대문자화 → 공백·하이픈 제거 → `0/O→Q`, `1/I/L→J` 교정만 한다(`InviteCode.swift:37-43`).
- `.keyboardType(.asciiCapable)` — 한글 자판을 목록에서 뺀다. 이게 버그의 실제 수정이다. 숫자·영문이 한 자판에 있어 6자리 섞인 코드를 한 번에 친다.
- `.textInputAutocapitalization(.characters)` — 안드로이드 `textCapCharacters` 와 같다. `normalize` 가 어차피 대문자로 바꾸지만, 화면에 보이는 글자가 부모 폰에 뜬 코드와 같은 모양이어야 옮겨 적다 틀린 곳이 눈에 띈다.
- `.autocorrectionDisabled()` — 자동 고침·예측 입력이 `ABC234` 를 단어로 바꾸거나 뒤에 공백을 붙이지 않게 한다(공백은 `normalize` 가 지우지만 단어 치환은 못 되돌린다).
- 길이 8 — 6자리보다 두 칸 넉넉한 안드로이드 값 그대로. `ABC-234`·`ABC 234` 처럼 끊어 적어도 `normalize` 가 지우기 전에 잘리지 않는다.

- [ ] **Step 1: 실패하는 테스트**

`ios/KidCareTests/InviteCodeFieldTests.swift`:

```swift
import Testing
@testable import KidCare

/// 정본은 안드로이드 `activity_child_pairing.xml:41-50`(maxLength=8, textCapCharacters).
struct InviteCodeFieldTests {

    @Test("최대 길이는 안드로이드와 같은 8 이다")
    func 최대_길이() {
        #expect(InviteCodeField.maxLength == 8)
    }

    @Test("8자를 넘으면 뒤를 자르고, 짧으면 그대로 둔다")
    func 자르기() {
        #expect(InviteCodeField.clamp("ABC-234-XY") == "ABC-234-")
        #expect(InviteCodeField.clamp("abc") == "abc")
        #expect(InviteCodeField.clamp("") == "")
    }

    @Test("끊어 적은 6자리는 잘린 뒤에도 유효하다 — 8 이 6 보다 넉넉한 이유")
    func 끊어_적어도_유효() {
        #expect(InviteCode.isValid(InviteCodeField.clamp("abc 234")))
        #expect(InviteCode.isValid(InviteCodeField.clamp("ABC-234")))
    }

    @Test("한글 자판으로 친 자모는 normalize 가 못 고친다 — ASCII 자판을 강제하는 이유")
    func 한글_자모는_유효하지_않다() {
        #expect(InviteCode.isValid("ㅁㅠㅊ234") == false)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/InviteCodeFieldTests`
Expected: 컴파일 실패 — `InviteCodeField` 가 없다.

- [ ] **Step 3: 구현**

`ios/KidCare/Onboarding/InviteCodeField.swift`:

```swift
import SwiftUI

/// 초대 코드 입력칸의 규칙. 정본은 안드로이드 `activity_child_pairing.xml:41-50`.
///
/// **왜 따로 두나:** 기기 언어가 한국어인 아이폰은 기본 자판이 한글이라, 코드 칸을 누르고
/// 그대로 치면 `ㅁㅠㅊ234` 가 들어간다. `InviteCode.normalize` 는 대문자화·공백 제거·
/// 헷갈리는 글자 교정만 해서 자모를 못 고치고, 합류 버튼은 영영 안 켜진다 — 부모 눈에는
/// "번호를 맞게 넣었는데 버튼이 안 눌린다"로 보인다.
enum InviteCodeField {

    /// 안드로이드 `android:maxLength="8"`. 6자리보다 두 칸 넉넉해 `ABC-234` 처럼 끊어
    /// 적어도 `normalize` 가 지우기 전에 잘리지 않는다.
    static let maxLength = 8

    static func clamp(_ raw: String) -> String {
        String(raw.prefix(maxLength))
    }
}

extension View {
    /// 초대 코드 칸의 자판. 설정마다의 근거는 계획서 Task 5 와 같다 — 요약하면 한글 자판을
    /// 빼고(`.asciiCapable`), 안드로이드 `textCapCharacters` 처럼 대문자로 보이게 하고,
    /// 자동 고침이 코드를 단어로 바꾸지 못하게 한다.
    func inviteCodeKeyboard() -> some View {
        self
            .keyboardType(.asciiCapable)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
    }
}
```

`ios/KidCare/Onboarding/JoinFamilyView.swift:25-30` 의 `TextField` 를 바꾼다:

```swift
            TextField("pairing_code_placeholder", text: $입력)
                .inviteCodeKeyboard()
                .multilineTextAlignment(.center)
                .font(.system(.largeTitle, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                // 안드로이드 maxLength=8 — 넘치는 글자는 들어오는 즉시 자른다.
                .onChange(of: 입력) { _, 새_값 in
                    let 잘린_값 = InviteCodeField.clamp(새_값)
                    if 잘린_값 != 새_값 { 입력 = 잘린_값 }
                }
```

`.navigationBarBackButtonHidden` 은 이 화면에 없고 더하지 않는다 — 시스템 뒤로 버튼이 역할 선택으로 돌아가는 유일한 길이다(Global Constraints "보이는 뒤로 가기").

- [ ] **Step 4: 통과 확인**

Run: `cd ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: 전체 PASS, `InviteCodeFieldTests` 4개 포함. 자판 모양 자체는 단위 테스트로 못 본다 — "단계 마무리" 시뮬레이터 확인 항목 6 에서 한글 자판을 켠 시뮬레이터로 본다.

- [ ] **Step 5: 커밋** (공통 절차 B)

```bash
git add ios/KidCare/Onboarding/InviteCodeField.swift ios/KidCare/Onboarding/JoinFamilyView.swift ios/KidCareTests/InviteCodeFieldTests.swift
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "iOS 4단계 Task 5: 초대 코드 칸에 한글 자판이 안 뜨게 — 영문 대문자 자판, 8자 제한"
```

---

## 단계 마무리 — 통합 리뷰 한 번, 시뮬레이터 확인 한 번

Task 1~5 는 단위 테스트만 돌리고 넘어간다(브리프). 여기서 한 번에 본다.

- [ ] **Step 1: 기계 검사**

```bash
export PATH="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:$PATH"
cd /Users/com/work/KidCare
cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'; cd ..
swift tools/check-i18n-keys.swift                                       # 종료 1 이 기대값 — 늘어난 키가 ios_tab_not_ready_body 하나뿐인지 본다
grep -rn "^import" ios/KidCare/Logic | grep -v "import Foundation$"     # 비어 있어야 한다
grep -rn "@unchecked Sendable\|nonisolated(unsafe)" ios/KidCare         # 비어 있어야 한다
git diff --stat 31c6eb2..HEAD -- app firestore.rules gradlew            # 비어 있어야 한다
grep -rn "navigationBarBackButtonHidden" ios/KidCare                    # 비어 있어야 한다
git diff 31c6eb2..HEAD -- ios/KidCare/KidCareApp.swift                  # 비어 있어야 한다
```

테스트 개수를 적어 둔다(Task 6 개발일지에 쓴다).

- [ ] **Step 2: 통합 리뷰** — superpowers:requesting-code-review 로 `31c6eb2..HEAD` 전체를 한 번 리뷰받는다. 리뷰어에게 이 계획서의 "판정 기록" 일곱 줄과 "Pre-flight conflict table" 을 함께 준다. 반려 항목은 고친 뒤 한국어 커밋(`iOS 4단계 Fix round N: …`)으로 남긴다.

- [ ] **Step 3: 시뮬레이터 확인 준비 — 에뮬레이터에만 쓴다**

1. 다른 터미널에서 `firebase emulators:start --only auth,firestore --project kidcare-emulator`.
2. `ios/KidCare/KidCareApp.swift:9` 를 **잠시** `FirebaseBootstrap.configureForEmulator(projectId: "kidcare-emulator")` 로 바꾸고 빌드·설치:

```bash
cd ios && xcodebuild -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/kidcare-dd build
xcrun simctl boot "iPhone 17" 2>/dev/null; xcrun simctl uninstall booted com.kidcare.family
xcrun simctl install booted /tmp/kidcare-dd/Build/Products/Debug-iphonesimulator/KidCare.app
xcrun simctl launch booted com.kidcare.family
```

3. 앱에서 보호자 → 새 가족 만들기 → 코드가 뜨면, 가족 ID 를 읽고 자녀를 에뮬레이터 관리자 권한(`Authorization: Bearer owner`, 규칙 우회 — 에뮬레이터 전용)으로 넣는다. 코드 화면이 자녀 합류를 감지해 본 화면으로 넘어간다(`NewFamilySession` 이 `RoleStore.childUid` 를 채운다).

```bash
EMU="http://127.0.0.1:8080/v1/projects/kidcare-emulator/databases/(default)/documents"
FAMILY=$(curl -s -H "Authorization: Bearer owner" "$EMU/families" | python3 -c 'import json,sys; print(json.load(sys.stdin)["documents"][0]["name"].split("/")[-1])')
NOW=$(python3 -c 'import time; print(int(time.time()*1000))')
curl -s -X PATCH -H "Authorization: Bearer owner" -H "Content-Type: application/json" "$EMU/families/$FAMILY/members/sim-child" \
  -d "{\"fields\":{\"role\":{\"stringValue\":\"child\"},\"displayName\":{\"stringValue\":\"민준\"},\"fcmToken\":{\"stringValue\":\"\"},\"appVersion\":{\"stringValue\":\"\"},\"joinCode\":{\"stringValue\":\"\"},\"updatedAt\":{\"integerValue\":\"$NOW\"},\"joinedAt\":{\"integerValue\":\"$NOW\"}}}"
curl -s -X PATCH -H "Authorization: Bearer owner" -H "Content-Type: application/json" "$EMU/families/$FAMILY/children/sim-child" \
  -d "{\"fields\":{\"lat\":{\"doubleValue\":37.5665},\"lng\":{\"doubleValue\":126.978},\"battery\":{\"integerValue\":\"77\"},\"ringerMode\":{\"stringValue\":\"normal\"},\"dnd\":{\"stringValue\":\"off\"},\"network\":{\"stringValue\":\"wifi\"},\"wifiOn\":{\"booleanValue\":true},\"lastSeenAt\":{\"integerValue\":\"$NOW\"}}}"
```

4. 아이 폰 흉내 — 가장 최근 `pending` 명령 하나를 `delivered` 또는 `done` 으로 옮기는 명령(규칙 우회라 순서 제약이 없다):

```bash
answer() {  # 사용: answer done   또는   answer delivered
  ID=$(curl -s -H "Authorization: Bearer owner" "$EMU/families/$FAMILY/children/sim-child/commands" \
    | python3 -c 'import json,sys; d=[x for x in json.load(sys.stdin).get("documents",[]) if x["fields"]["state"]["stringValue"] in ("pending","delivered")]; d.sort(key=lambda x:int(x["fields"]["createdAt"]["integerValue"])); print(d[-1]["name"].split("/")[-1] if d else "")')
  curl -s -X PATCH -H "Authorization: Bearer owner" -H "Content-Type: application/json" \
    "$EMU/families/$FAMILY/children/sim-child/commands/$ID?updateMask.fieldPaths=state" -d "{\"fields\":{\"state\":{\"stringValue\":\"$1\"}}}" > /dev/null
  echo "$ID → $1"
}
```

- [ ] **Step 4: 시뮬레이터에서 본다** — 항목마다 `xcrun simctl io booted screenshot /tmp/p4-<번호>.png` 로 남긴다.

1. **탭 바.** 지도·알림·관리·예약·장소 순서, 한국어 라벨, 선택 탭이 보라(`sky`). 알림·예약·장소는 자리표시 문구. 안드로이드 폰 화면과 나란히 둔다.
2. **지도 탭 수명.** 실시간 보기를 켠다 → 관리 탭 → 지도 탭으로 돌아온다. 실시간 버튼이 여전히 '끄기' 상태이고, 에뮬레이터 명령 목록에 `stop_live_tracking` 이 **새로 생기지 않았다.** 지도를 옮겨 둔 위치도 그대로다(다시 읽기·카메라 초기화 없음). 타임라인 패널과 네이버 로고가 탭 바 **위**에 보인다.
3. **관리 탭 첫 진입.** 명령 목록에 `query_ringer` 가 하나 생긴다. 탭을 오갔다 다시 와도 더 안 생긴다. `answer done` → 소리 상태가 "현재 상태 · 벨소리", 인터넷 카드가 "와이파이로 연결돼 있어요 / 와이파이 스위치 켜짐".
4. **명령 왕복.** 진동 → "전달 중…"+스피너 → `answer done` → "완료", 진동 버튼이 채운 보라. 한마디 칩 '밥 먹었어?' → 입력칸만 채워짐 → 보내기 → 입력칸 비움 → `answer delivered` → "애기폰에 도착했어요 · 아직 안 읽음"(스피너 없음), 60초 뒤에도 그대로 → `answer done` → "읽음". 무음을 누르고 60초 기다리면 "애기폰이 응답하지 않아요 / 마지막 신호 N분 전". 핸드폰 찾기 → 버튼이 '소리 끄기'로, 아래 작은 버튼이 사라짐. 알람 07:30·"학원" → "07:30 '학원' 알람을 보냈어요…" → `answer done` → "맞춰져 있어요". 잠금 스위치 → 에뮬레이터 `settings/ringer` 에 `lockEnabled` **한 필드만** 생긴다.
5. **배너.** 요청 기록을 31분 전으로 되돌리고 앱을 다시 띄운다: `xcrun simctl spawn booted defaults write com.kidcare.family last_request_at_sim-child -int $(( NOW - 31*60*1000 ))` → `xcrun simctl terminate booted com.kidcare.family && xcrun simctl launch booted com.kidcare.family`. 지도·관리·장소 탭 모두 같은 자리에 분홍 배너. 관리 탭에서 벨소리 → `answer done` → 배너가 **곧바로** 사라진다.
6. **초대 코드 자판.** 시뮬레이터 설정 → 일반 → 키보드에 '한국어'를 더하고, 하드웨어 키보드를 끈다(I/O → Keyboard → Connect Hardware Keyboard 해제). 앱을 지우고 다시 설치 → 보호자 → 가족에 합류하기 → 코드 칸을 누른다. 영문 대문자 자판이 뜨고 🌐 로 한국어가 **나오지 않는다.** `abc-234xyz` 를 치면 8자에서 멈추고 합류 버튼이 켜진다. 상단에 **시스템 뒤로 버튼이 보이고** 누르면 역할 선택으로 돌아간다.

- [ ] **Step 5: 되돌리고 확인** — `KidCareApp.swift:9` 를 `configureForApp()` 로 되돌리고 `git diff ios/KidCare/KidCareApp.swift` 가 비어 있음을 확인한다. 이 단계에서 커밋할 코드 변경이 생겼다면(시뮬레이터에서 찾은 결함) 고친 뒤 테스트를 다시 돌리고 `iOS 4단계 Fix round N: …` 로 커밋한다.

---

### Task 6: 실기기 읽기 전용 확인과 개발일지

**Files:**
- Modify: `README.md` (개발일지 절 끝 `### 아이폰 2단계 …` 다음, `## 아이가 앱을 강제 종료하면` 앞 / "함께 고쳐야 하는 짝")

**진짜 가족에 쓰는 동작은 실기기에서 하지 않는다.** 초대 코드 만들기, 명령 보내기, 잠금 저장은 전부 위 "단계 마무리"에서 **에뮬레이터로만** 확인했다. 실기기는 운영 Firebase 에 붙은 진짜 가족이므로 **보기만** 한다. 특히:
- **관리 탭을 누르지 않는다.** 여는 순간 아이 폰에 `query_ringer` 명령이 간다(안드로이드와 같은 동작, `ControlFragment.kt:287`) — 운영 Firestore 쓰기다.
- 지도 탭의 '지금 위치 확인'·'실시간 보기'를 누르지 않는다(명령 쓰기).
- 앱을 지우거나 역할을 다시 고르지 않는다 — 익명 로그인이라 그 아이폰이 가족에서 빠진다(설계서 §11). 초대 코드 자판 확인은 시뮬레이터에서 끝냈다.

- [ ] **Step 1: 실기기 연결 확인** — `xcrun devicectl list devices`. `unavailable` 이면 **여기서 멈추고 보고한다.** 케이블은 사람이 꽂아야 한다.

- [ ] **Step 2: 운영 설정으로 설치**(`configureForApp()` 그대로)

```bash
cd /Users/com/work/KidCare/ios
xcodebuild -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS,id=<UDID>' -derivedDataPath /tmp/kidcare-dd-device -allowProvisioningUpdates build
xcrun devicectl device install app --device <UDID> /tmp/kidcare-dd-device/Build/Products/Debug-iphoneos/KidCare.app
xcrun devicectl device process launch --device <UDID> com.kidcare.family
```

- [ ] **Step 3: 보기만 한다** — 스크린샷은 기기에서 사람이 찍거나 `KidCareUITests` 스킴의 첨부로 남긴다.
  1. 탭 바 다섯이 안드로이드 보호자 폰과 같은 순서·같은 라벨이다.
  2. 지도 탭이 3단계와 같은 진짜 가족의 경로·상태 카드를 보인다. 알림 탭 → 지도 탭으로 돌아왔을 때 다시 읽는 깜빡임이 없다. 타임라인 패널·네이버 로고가 탭 바에 가리지 않는다.
  3. 배너가 떠 있다면 그 문구를 기록한다(판정 재료가 폰 안에만 있어 안드로이드 보호자와 다른 시점에 뜰 수 있다 — 설계서 §8, 버그 아님).
  4. 알림·예약·장소 자리표시 화면.

- [ ] **Step 4: 개발일지를 쓴다** — `README.md` 에 절 하나를 더한다. 앞 절들과 같은 말투(부모·다음 개발자가 읽는 한국어 설명문)로, 아래 내용을 **다 담는다**:

```markdown
### 아이폰 4단계 — 탭 다섯, 관리 탭, 모든 탭 위의 배너 (2026-09-13)

하단 탭 다섯(지도·알림·관리·예약·장소)을 안드로이드와 같은 순서로 세웠습니다. 알림·예약·장소는 5·6단계가 채울 자리표시입니다. 관리 탭은 안드로이드 `ControlFragment` 를 그대로 옮겼습니다 — 인터넷 상태, 소리 모드 셋과 '새로 확인', 되돌리기 잠금, 핸드폰 찾기, 한마디 보내기, 알람 맞추기, 그리고 누른 뒤 무슨 일이 벌어졌는지 말하는 맨 아래 한 줄.

#### 탭을 옮겨도 실시간 보기가 안 꺼지게

SwiftUI 의 탭은 다른 탭으로 옮길 때마다 "화면이 사라졌다"고 알립니다. 3단계는 그 순간에 명령 추적과 실시간 세션을 정리하고 있어서, 그대로 탭을 붙였다면 **관리 탭을 한 번 눌렀을 뿐인데 실시간 보기가 꺼졌을 것**입니다. 안드로이드는 탭을 숨기기만 하고 리스너는 화면이 정말 없어질 때만 뗍니다. 그래서 정리를 탭이 아니라 보호자 화면 전체가 사라지는 자리로 옮겼고, 첫 읽기도 탭에 돌아올 때마다 반복하지 않게 했습니다.

#### 무응답 배너

(판정 재료·30분 문턱은 아래 "아이가 앱을 강제 종료하면" 절과 같다고 한 줄로 잇고) 아이폰에서도 어느 탭을 보든 같은 자리에 뜨고, 관리 탭이든 지도 탭이든 대답이 오는 순간 사라집니다. 3단계에서 빠져 있던 규칙 하나를 함께 옮겼습니다 — 부모가 물어본 **뒤에** 올라온 상태 문서는 그 자체가 대답입니다.

#### 초대 코드 칸에 한글 자판이 뜨던 버그

(증상·원인·수정 — Task 5 의 근거 문단을 부모가 읽을 수 있게 풀어서)

#### 계획과 다르게 정한 것

- 브리프는 관리 탭에 가족 목록·초대·연결 끊기를 적었지만 안드로이드 관리 탭에는 그런 것이 없고, 초대는 아이 선택기 메뉴에 있습니다. 설계서대로 6단계(아이 선택기)로 넘겼습니다. 멤버 삭제·가족 나가기 화면은 안드로이드에도 없어 만들지 않았습니다.
- 문구 카탈로그 생성 스크립트(`tools/ios-strings.py`)는 아직 없어, 한국어 값을 옮기는 명령과 그 결과를 검사하는 테스트(`LocalizableCatalogTests`)를 두었습니다. 1단계에서 손으로 고친 세 문구(`guardian_start_join_family`, `map_no_child`, `role_guardian`)가 원본과 달라 6단계에서 정리해야 합니다.

#### 안드로이드에서 찾은 것 (고치지 않았습니다)

- 아이가 아직 없는 가족에서 관리 탭을 열면 소리 상태 줄이 "확인하는 중이에요"에 영원히 머뭅니다(`ControlFragment.kt:243` 에서 켠 로딩을 `subscribe` 가 :275-279 에서 돌아가며 끄지 않음).
- `activity_guardian_main.xml:65` 주석이 배너를 "30분 넘게 아무 신호도 안 보냈을 때"라고 적지만, 실제 판정은 "물어봤는데 30분 넘게 대답이 없을 때"(`DisconnectRule`)입니다.
- `GuardianMainActivity.kt:36` 주석의 탭 단계 번호(지도 3·관리·예약 4·장소·알림 5단계)가 지금 구성과 맞지 않습니다.

#### 그래서 지금

iOS 테스트 N개(3단계 끝 M개). 실기기(운영)에서는 보기만 했고, 명령·잠금·초대처럼 가족 데이터에 쓰는 동작은 에뮬레이터에서만 확인했습니다. **안드로이드 `app/`·`firestore.rules` 는 한 줄도 안 바뀌었습니다.**
```

N 은 단계 마무리 Step 1 의 테스트 개수, M 은 Task 1 을 시작하기 전 `xcodebuild test` 한 번으로 적어 둔 개수다(3단계 계획서의 128 은 3단계 도중 값이라 쓰지 않는다). 괄호 안 지시문은 실제 문장으로 바꾼다.

"함께 고쳐야 하는 짝"(`README.md:824-831`)의 첫 줄을 이렇게 늘린다:

```markdown
- **새 명령 타입** → `core/model/Documents.kt`의 `CommandType` + `child/CommandHandler.kt`의 `when` + 보내는 화면 + **아이폰 `ios/KidCare/Core/Documents.swift`의 `CommandType`**. 넷 다. 소리 모드 값(`normal`/`vibrate`/`silent`)과 페이로드 키 `mode` 는 `guardian/ControlFragment.kt`·`child/RingerStateStore.kt`·`ios/KidCare/Core/Documents.swift`의 `RingerMode` 세 곳에 있습니다.
```

- [ ] **Step 5: 커밋**

```bash
cd /Users/com/work/KidCare
git diff --stat 31c6eb2..HEAD -- app firestore.rules gradlew   # 비어 있어야 한다
git add README.md
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "iOS 4단계 Task 6: 실기기에서 보기만 확인하고 개발일지를 쓴다"
```

---

## 4단계 완료 기준

- [ ] 하단 탭 다섯이 안드로이드와 같은 순서·라벨·그림이고, 저장된 탭으로 복원된다
- [ ] 다른 탭을 봤다 돌아와도 지도가 다시 읽지 않고 실시간 보기가 꺼지지 않는다
- [ ] 관리 탭의 소리 모드·새로 확인·잠금·폰찾기·한마디·알람이 에뮬레이터에서 왕복하고, 60초 무응답·큐잉·메시지 안 읽음이 각각 다른 문장으로 보인다
- [ ] 무응답 배너가 모든 탭 위 같은 자리에 뜨고, 대답이 오면 곧바로 사라진다
- [ ] 초대 코드 칸에 한글 자판이 안 뜨고 8자에서 멈추며, 뒤로 버튼이 보인다
- [ ] 보호자 화면이 쓰는 모든 Firestore 리스너가 `GuardianRootView.onDisappear` 경로로 떨어진다
- [ ] `ios/KidCare/Logic/` 이 Foundation 만 import 하고, 앱 코드에 `@unchecked Sendable`·`nonisolated(unsafe)` 가 없다
- [ ] `git diff --stat 31c6eb2..HEAD -- app firestore.rules gradlew` 이 비어 있다
- [ ] `LocalizableCatalogTests` 가 초록이다(코드가 쓰는 원본 키가 전부 카탈로그에 있다)

---

## 자기 검토 결과 (writing-plans self-review)

**설계서 대응.** §4 탭별 대응표의 `GuardianRootView`(탭 컨테이너·무응답 배너) → Task 1·2, `ControlView` + 뷰모델 → Task 3·4. §4 "탭을 바꿔도 지도를 다시 만들지 않는다" → Task 1(뷰모델 수명·`처음이면_읽는다`·onDisappear 이동). §4 아이 선택기 → 6단계(판정 기록 1). §8 명령의 정직한 표시(전달 중→완료, 60초 무응답+마지막 신호, "완료"의 뜻) → Task 3. §8 무응답 배너(폰 안의 재료, 다른 보호자와 다른 시점) → Task 2·Task 6 Step 3. §9 4단계 "소리 변경·폰찾기·메시지·알람·무응답 배너" → Task 2~4. §1 권한 0개 — 이 단계는 권한을 요청하지 않는다(위치·알림 API 호출 없음). §5 손 매핑·`hasOnly` → `RingerSettingsDoc` 에 `firestoreData` 없음, 잠금은 한 필드 병합.

**자리표시 검사.** "TBD/적절히/나중에" 없음. Task 6 Step 4 의 개발일지 틀에 괄호 지시문 두 곳과 N·M 이 있다 — 실행 시점에만 알 수 있는 값(테스트 개수)과, 앞 Task 에 이미 적힌 근거를 부모용 문장으로 옮기라는 지시다.

**타입·이름 일관성(고친 것 포함).**
- `ControlViewModel` 공개면: Task 3 테스트가 쓰는 이름(`시작한다`·`소리_모드를_보낸다`·`소리_상태를_묻는다`·`폰찾기_버튼을_눌렀다`·`메시지를_보낸다`·`알람을_맞춘다`·`알람을_끈다`·`잠금을_바꾼다`·`정리한다`·`상태_읽는_중`·`ringerQueryInFlight`·`currentRingerMode`·`ringerAppliedInSession`·`lockEnabled`·`울리는_중이라고_믿는가`·`선택된_모드인가`·`소리_상태_문구`·`방해금지_안내를_보이는가`·`인터넷_문구`·`와이파이_스위치_문구`·`알람_상태_문구`·`아이_안내`·`버튼_활성화`·`commandUi`·`메시지`·`알람_이름`·`alarmMinute`·`대답이_기록되면`)과 Task 3 구현·Task 4 화면이 쓰는 이름을 대조했다. Task 4 가 추가로 쓰는 `새로_확인_활성화`·`소리_상태_아이콘`·`인터넷_아이콘`·`messageMaxLength`·`alarmLabelMaxLength` 는 Task 3 구현에 있다.
- 처음 계획한 `알람_시각_문구`(+`control_alarm_time_format` 키)는 Task 4 가 `DatePicker` 로 시각을 보이게 되면서 쓰는 곳이 없어 **뺐다**. 테스트·키 목록에서도 뺐다.
- `FakeSleep` 이 `ControlViewModel.sendTimeoutMillis` 등을 비격리 문맥에서 읽으므로 상수를 `nonisolated static let` 으로 선언했다(`nonisolated(unsafe)` 아님).
- 테스트 공용 도구 이름은 기존 중첩 타입(`Gate`·`SingleSignal`·`FakeListenerRegistration`)과 겹치지 않게 `Test` 접두사로 두었고, 저장소에서 같은 이름이 없음을 grep 으로 확인했다.
- `MapViewModel.대답이_기록되면` 과 `ControlViewModel.대답이_기록되면` 은 같은 타입 `(@MainActor () -> Void)?` 다.
- 줄 번호: Task 1 이 `MapViewModel.swift` 에 약 20줄, Task 2 가 약 35줄을 더한다. Task 2·3 이 인용한 `MapViewModel.swift` 줄 번호는 **3단계 끝(31c6eb2) 기준**이며, 각 Step 에 찾을 문자열을 함께 적었다.

---

## Pre-flight conflict table

| 짝 | 함께 만지는 것 | 충돌 여부와 처리 |
|---|---|---|
| Task 1 ↔ Task 2 | `GuardianRootView.swift`(Task 1 이 만들고 Task 2 가 `init`·`body` 를 감싼다), `MapViewModel.swift`(Task 1 `처음이면_읽는다` / Task 2 `대답이_기록되면`·상태 기반 대답), `TestDoubles.swift`(Task 2 가 끝에 붙인다) | 순서 의존. Task 2 Step 7 은 Task 1 의 탭 다섯을 "그대로" 감싼다. `MapViewModel` 은 서로 다른 함수 — 줄 번호 대신 찾을 문자열로 적었다 |
| Task 1 ↔ Task 3 | `MapViewModel.swift`(Task 3 이 `firstToFinish` 를 잘라낸다), `Localizable.xcstrings`, `TestDoubles.swift`(Task 3 은 쓰기만) | `firstToFinish` 는 Task 1 이 안 만진다. 카탈로그는 명령이 키를 정렬해 넣어 순서와 무관 |
| Task 1 ↔ Task 4 | `GuardianRootView.swift`(관리 탭 자리표시를 `ControlView` 로 교체), `KidCarePalette`, `Localizable.xcstrings` | Task 4 는 Task 1 의 `TabPlaceholderView(tab: .control)` 한 줄을 바꾼다. 알림·예약·장소 자리표시는 남는다 |
| Task 1 ↔ Task 5 | `LocalizableCatalogTests` 가 `JoinFamilyView.swift` 도 훑는다 | Task 5 는 새 키를 안 쓴다(`pairing_code_placeholder` 는 이미 카탈로그에 있다) — 충돌 없음 |
| Task 2 ↔ Task 3 | `Documents.swift`(Task 2 `StatusCard` 교체 / Task 3 `CommandType` 확장·새 타입 추가), `MapViewModel.swift`, `TestDoubles.swift`, `Localizable.xcstrings` | `Documents.swift` 는 서로 다른 선언. Task 3 은 Task 2 의 `StatusCard.signal`·`TestClock`·`TestListenerRegistration`·`TestCallbackBox` 를 소비한다 — Task 2 가 먼저여야 컴파일된다 |
| Task 2 ↔ Task 4 | `GuardianRootView.swift`(Task 4 가 `banner` 를 관리 뷰모델 훅에 잇는다) | Task 4 Step 5 는 Task 2 `init` 안의 지역 `banner` 를 쓴다 — `banner` 생성 **뒤**에 넣는다고 적었다 |
| Task 3 ↔ Task 4 | `ControlViewModel` 공개면 전체, `Localizable.xcstrings` | 뷰모델 키는 Task 3, 화면 전용 키는 Task 4 가 넣어 각 Task 끝에서 `LocalizableCatalogTests` 가 초록이다. 이름 대조는 자기 검토 결과에 적었다 |
| Task 3 ↔ `CommandRepositoryTests` | 자녀 세션 도우미를 `EmulatorHarness` 로 옮김 | Task 3 Step 1 이 동작 변화 없이 옮기고 그 스위트를 먼저 다시 돌린다 |
| Task 6 ↔ 전체 | `README.md` 만 | 코드 충돌 없음 |

| Task | 테스트가 코드와 맞는가 |
|---|---|
| Task 1 | `GuardianTabTests` 는 `titleKey`/`title`/`rawValue` 를, `MapTabLifecycleTests` 는 `처음이면_읽는다()` 의 반환 `Task` 와 `dayLoad` 주입을, `LocalizableCatalogTests` 는 공통 절차 A 의 변환 규칙과 같은 규칙을 쓴다. 기존 카탈로그로 사전 확인: 어긋남 3키(예외 목록) 외 전부 일치, 코드 리터럴 누락 0 |
| Task 2 | `StatusCardTests` 새 두 케이스는 `elapsed(millis:)`·`signal(status:)` 시그니처 그대로. `DisconnectBannerTests` 는 `init(childUid:requestLog:deviceNow:sleep:)`·`문구`·`다시_판정한다`·`주기적으로_판정한다`·`recheckMillis` 를 쓴다. `MapBannerWiringTests` 는 3단계 `MapViewModel.init` 의 기존 주입점(`commandSend`·`commandObserve`·`commandSleep`·`dayLoad`)과 새 `대답이_기록되면` 만 쓴다 |
| Task 3 | `ControlViewModelTests` 의 `만든다` 가 넘기는 인자 이름·순서(`requestLog`·`alarmMemoStore`·`commandSend`·`commandObserve`·`statusFetch`·`settingsObserve`·`lockSave`·`serverNow`·`deviceNow`·`commandSleep`)가 구현 `init` 과 같다. `FakeSleep` 이 가르는 세 길이는 구현이 `commandSleep` 에 넘기는 세 상수 그대로다. `ScheduleRepositoryTests` 는 옮긴 `EmulatorHarness` 도우미를 쓴다. `AlarmMemoStoreTests` 는 `init(defaults:now:)` 를 쓴다 |
| Task 4 | `ControlClockTests` 는 `ControlInput.date(minuteOfDay:calendar:)`·`minuteOfDay(_:calendar:)`·`clamp(_:max:)` 와 뷰모델 상수를 쓴다. 화면 자체는 단위 테스트가 없고, 키 누락은 `LocalizableCatalogTests` 가, 모양은 단계 마무리 Step 4 가 본다 |
| Task 5 | `InviteCodeFieldTests` 는 `InviteCodeField.maxLength`·`clamp` 와 기존 `InviteCode.isValid` 를 쓴다. 자판 설정은 단계 마무리 Step 4-6 이 본다 |
| Task 6 | 코드 변경 없음 — 검증 절차뿐 |
