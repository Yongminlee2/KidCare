# iOS 아이 역할 3단계 구현 계획 — 아이 화면과 권한, 그리고 아이 역할 켜기

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 아이폰이 **실제로 아이 폰이 된다.** 역할 선택 화면의 막이를 걷어 아이로 페어링하고, 앱이 뜨는 순간 저장된 역할이 child 이면 **화면과 무관하게** 수집기·시계·장소 감시·업로더를 조립한다(2단계 통합 검토 I1, 1단계 M6). 아이는 지금 무엇이 공유되고 있는지, 무엇이 꺼져 있어 안 되고 있는지, 그리고 **앱을 완전히 닫으면 아무것도 안 된다는 것**을 한 화면에서 본다. 권한이 꺼진 순간은 안드로이드 `child/ConditionWatcher.kt` 와 **같은 `permission_off` 이벤트**로 부모에게 간다 — 부모 화면은 한 줄도 안 바뀐 채로 그것을 읽는다.

**Architecture:** 배선의 주인이 **뷰가 아니다.** `Child/ChildSession.swift`(`@MainActor`, 앱당 하나)가 `LocationCollector`·`TrackingTicker`·`TrackingCoordinator`·`PlaceWatcher`·`ConditionWatcher` 를 소유하고, `KidCareApp.init()` 이 `FirebaseBootstrap.configureForApp()` 바로 뒤에서 `ChildSession.shared.startIfChild()` 를 부른다. `ChildRootView`/`ChildHomeView` 는 그 세션을 **읽기만** 한다 — 지역 전환이나 중요 위치 변경으로 앱이 백그라운드에서 되살아났을 때 `WindowGroup` 의 body 가 평가된다는 보장이 없기 때문이다(판정 기록 1). 권한 판단은 `Child/ChildPermissions.swift` 한 곳에 모으고(`onboarding/PermissionStep.kt` 자리), 화면이 무엇을 말할지는 `Child/ChildHomeModel.swift` 가 정하며(`ChildHomeActivity.kt:70-82`), 그림은 `ChildHomeView` 가 그린다. `ConditionWatcher` 는 `TrackingCoordinator.onCondition`(1번 단계, 1단계가 이미 비워 둔 훅)에 걸린다.

**Tech Stack:** Swift 6 strict concurrency / iOS 17 / SwiftUI / CoreLocation / UIKit(`UIApplication.backgroundRefreshStatus`, `ProcessInfo.isLowPowerModeEnabled`) / Firebase Firestore / Swift Testing / XcodeGen. 새 의존성 없음. **`app/` 을 한 줄도 안 만진다** — 이 단계는 골든 파일을 더하지 않으므로 `GoldenFileWriterTest.kt` 예외조차 쓰지 않는다.

**Spec:** `docs/superpowers/specs/2026-09-22-kidcare-ios-child-design.md`. 이 단계가 기대는 곳:
- §14 3단계 — 범위 그대로("`Child/`: ChildPermissions·ConditionWatcher·DeviceState·ChildHomeModel·ChildHomeView·ChildRootView / 역할 선택 화면의 막이 제거, `JoinFamilyView(expectedRole: .child)`, `RouterView` 의 child 갈래, `RoleStore` 저장 / 새 i18n 키 + `INFOPLIST_KEYS` 확장 + `ios_child_unsupported_*` 셋 제거")
- §8 전부 — 8.1 두 걸음, 8.2 정확한 위치, 8.3 저전력 모드, 8.4 백그라운드 앱 새로고침, 8.5 문구, 8.6 아이폰에 없는 권한 둘
- §4.10 `LOW_PERCENT`(15)·`REARM_PERCENT`(20), §4.9 `CONDITION_CHECK_INTERVAL_MILLIS`(60초)
- §5.3 되살아나는 길 둘과 **강제 종료**, §15-2("가장 큰 차이다")
- §17 열린 질문 4(백그라운드 새로고침은 고장으로 취급)·7(`ios_child_unsupported_*` 를 지운다)·9(‘다시 연결’ 버튼을 둔다)
- §12.1 `ChildHomeModelTests`, §12.4 "시뮬레이터로 되는 것"

**이월 받는 것(반드시 닫는다):**
- 2단계 통합 검토 **I1** — 출시 빌드에 수집기를 만드는 자리가 없다. `-childSim`(`#if DEBUG`) 밖에 없어서 지역 전환이 아무에게도 안 배달된다. → Task 3.
- 1단계 **M6** — 중요 위치 변경으로 되살아난 프로세스가 수집을 다시 시작하지 않는다. → Task 3(같은 자리).
- 1단계 수정 파동의 경고 — **`TrackingCoordinator(ticker:)` 를 안 넘기면 I1(멈춘 폰이 `.moving` 에 갇힘)이 그대로 되살아난다.** → 판정 기록 2(컴파일이 막게 한다) + Task 3 테스트.
- 2단계 통합 검토 **M3** — 장소 스냅샷마다 지역 스무 개를 통째로 지웠다 다시 건다. 앱이 뜨자마자 캐시본·서버본으로 두 번 돈다. → Task 3 에서 닫는다(판정 기록 17).

---

## 선행 조건

2단계(`docs/superpowers/plans/2026-09-22-kidcare-ios-child-phase2.md`)가 **전부 커밋된 뒤** 시작한다. 기준 커밋은 `d26e28f`(2단계 마무리) 이상이다.

```bash
cd /Users/com/work/KidCare
git status --short                                                       # 비어 있어야 한다
git log --oneline -1                                                     # d26e28f 이거나 그 뒤
ls docs/superpowers/plans/2026-09-22-kidcare-ios-child-phase2.md          # 있어야 한다

# 1·2단계가 만든 이름 — 하나라도 다르면 Pre-flight conflict table 의 해당 행을 먼저 처리한다
grep -n "final class TrackingCoordinator\|var onCondition\|ticker: Ticking" ios/KidCare/Child/TrackingCoordinator.swift   # 세 줄
grep -n "protocol Ticking\|final class TrackingTicker\|static var periodMillis" ios/KidCare/Child/TrackingTicker.swift    # 세 줄
grep -n "final class LocationCollector\|func requestAuthorization\|var onAuthorizationChange\|func start()" ios/KidCare/Child/LocationCollector.swift  # 네 줄
grep -n "final class PlaceWatcher\|func apply(placeDocs\|func isInsideKnownPlace\|func onFix(" ios/KidCare/Child/PlaceWatcher.swift                    # 네 줄
grep -n "final class DeviceState\|struct Snapshot\|batteryPercent" ios/KidCare/Child/DeviceState.swift                    # 세 줄
grep -n "static func add(familyId" ios/KidCare/Core/EventRepository.swift                                                 # 한 줄
grep -n "static let permissionOff\|static let lowBattery" ios/KidCare/Core/Documents.swift                                # 두 줄
grep -n "static func fetchMember\|static func joinFamily" ios/KidCare/Core/FamilyRepository.swift                         # 두 줄
grep -n "enum ChildSimHarness" ios/KidCare/Child/ChildSimHarness.swift                                                    # 한 줄(이 단계가 지운다)
grep -n "ChildSimHarness.launch" ios/KidCare/RouterView.swift                                                             # 한 줄(이 단계가 지운다)
grep -n "ios_child_unsupported" i18n/ko.json i18n/en.json ios/KidCare/Onboarding/RoleSelectView.swift                      # 여덟 줄(이 단계가 지운다)
grep -n "NSLocationAlwaysAndWhenInUseUsageDescription\|UIBackgroundModes" ios/project.yml                                  # 두 줄(1단계가 이미 넣었다)
grep -n "ios_perm_location_always" tools/ios-strings.py                                                                    # 한 줄(1단계가 이미 매핑했다)

# 안드로이드 정본 — 이 단계가 인용하는 줄이 실제로 그 줄인지 확인한다
sed -n '70,82p' app/src/main/java/com/kidcare/family/child/ChildHomeActivity.kt      # onResume 의 세 갈래
sed -n '173,184p' app/src/main/java/com/kidcare/family/child/ConditionWatcher.kt     # LOW_PERCENT / REARM_PERCENT / WATCHED
sed -n '422,433p' app/src/main/java/com/kidcare/family/core/FamilyRepository.kt      # isStillMember
sed -n '913p'     app/src/main/java/com/kidcare/family/child/TrackingService.kt      # CONDITION_CHECK_INTERVAL_MILLIS

# 기준 테스트 개수 M — 2단계 마무리 기준 708 이다. 실제로 돌려 확인하고 적어 둔다
cd ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5
```

## Global Constraints

설계서 §16 과 1·2단계 계획서의 목록을 이 단계의 말로 옮긴 것이다.

- **Swift 6 strict concurrency, iOS 17.0, SwiftUI, XcodeGen**(`ios/project.yml`; xcodeproj 를 손으로 고치지 않는다), **Swift Testing**.
- `ios/KidCare/Logic/` 은 **Foundation 만** import 한다. CoreLocation 도 Firebase 도 UIKit 도 안 된다. **이 단계는 `Logic/` 에 파일을 하나도 더하지 않는다**(판정 기록 6).
- 앱 코드에 **`@unchecked Sendable` 과 `nonisolated(unsafe)` 를 쓰지 않는다.**
- **푸시 알림과 FCM 을 쓰지 않는다**(Spark 무료 요금제). 아이 폰은 **로컬 알림도 하나도 안 띄운다**(설계서 §8.6). 새 Firestore 리스너에는 떼는 길이 있다.
- `app/src/main`, `firestore.rules`, `gradlew` 를 **한 줄도** 고치지 않는다. **이 단계는 `app/` 전체를 안 만진다** — 골든 파일을 더하지 않으므로 `GoldenFileWriterTest.kt` 예외도 안 쓴다.
- **정본은 안드로이드다.** 이 계획서가 코틀린과 다르면 코틀린이 맞다. 상수는 인용한 `파일:줄` 에서 그대로 옮긴다.
- 새 문구는 `i18n/ko.json`·`i18n/en.json` **둘에만** 넣고 `python3 tools/ios-strings.py` 로 생성한다. **번역을 지어내지 않는다** — 나머지 12개 언어는 영어로 채워지고 `tools/i18n-untranslated.json` 에 남는다.
- 테스트는 **운영 Firestore 에 절대 쓰지 않는다.** 에뮬레이터 테스트는 `configureForEmulator(projectId: "kidcare-emulator")`(Auth 127.0.0.1:9099, Firestore 8080)를 쓰고, **커밋 시점의 `KidCareApp.init()` 은 반드시 `configureForApp()` 을 부른다.** 에뮬레이터는 이미 떠 있는 것을 그대로 쓰고 그 데이터도 지우지 않는다.
- **실기기를 아이로 페어링하지 않는다**(설계서 §13, 4단계 몫). 이 단계의 확인은 전부 시뮬레이터다.
- **시뮬레이터를 끄거나 지우지 않는다.** 테스트 전에 앱을 **지우지 않는다**(위에 덮어 설치한다).
- **명령(`commands/`)을 만들지 않는다.** 아이폰 아이는 구독하지 않는다(설계서 §1).
- **지역 감시는 `CLLocationManager.startMonitoring(for:)` 그대로다**(주인 판정, §17 열린 질문 2). `CLMonitor` 로 옮기지 않는다.
- 커밋은 한국어, 작성자 `Yongminlee2 <dydals5678@gmail.com>`. **AI 흔적을 남기지 않는다**(Co-Authored-By 금지).
- 테스트 명령: `cd ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'`.
- 주석은 한국어로 **"왜"** 를 적는다. 실행 전 PATH 는 `export PATH="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:$PATH"` 다. 파일을 새로 만들거나 지웠으면 테스트 전에 `cd ios && xcodegen generate` 를 돌린다.
- Swift 의 `CancellationError` 를 일반 `catch` 로 삼키지 않는다(설계서 §16 마지막 줄).

## 공통 절차 A — 문구 키를 카탈로그에 넣는 법

6단계 계획서 공통 절차 A 그대로다. 카탈로그(`ios/KidCare/Localizable.xcstrings`)를 **손으로 고치지 않는다.**

1. 새 문구가 필요하면 `i18n/ko.json` 과 `i18n/en.json` **둘 다**에 키를 넣는다(코드 포인트 순 정렬, 파일 끝 줄바꿈 하나). 나머지 12개 언어 파일에는 넣지 않는다.
2. 키를 일부러 더하거나 뺐으면 `python3 tools/ios-strings.py --write-gaps` 로 빈 칸 기록(`tools/i18n-untranslated.json`)까지 새로 쓴다. diff 의 빈 칸 변화가 의도한 것인지 눈으로 본다.
3. 평소에는 `python3 tools/ios-strings.py` 를 돌린다. 빈 칸이 기록과 다르면 쓰지 않고 멈춘다.
4. 검사: `python3 tools/ios-strings.py --check`(종료 코드 0), `I18nKeyParityTests`·`LocalizableCatalogTests`·`LocalizationBundleTests`.

**이 단계는 1~3 을 전부 쓴다** — 새 키 아홉을 더하고 옛 키 셋을 지운다(판정 기록 14). 그래서 `--write-gaps` 를 **반드시** 한 번 돈다.

## 공통 절차 B — 커밋

```bash
cd /Users/com/work/KidCare
git diff --stat d26e28f..HEAD -- app firestore.rules gradlew           # 비어 있어야 한다 (app 전체)
git diff ios/KidCare/KidCareApp.swift | grep -n "configureForEmulator"  # 비어 있어야 한다
grep -rn "@unchecked Sendable\|nonisolated(unsafe)" ios/KidCare         # 주석 말고는 비어 있어야 한다
grep -rn "import CoreLocation\|import Firebase\|import UIKit" ios/KidCare/Logic   # 비어 있어야 한다
python3 tools/ios-strings.py --check                                    # 종료 코드 0
git add <이 Task 의 파일들>
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "<한국어 메시지>"
```

## 이 단계에서 다루지 않는 것

- **보호자 화면 잠금(`Guardian/ChildPlatform`, 세 화면의 `.disabled`)** — 4단계다(설계서 §14·§10.2). 그래서 `ios_child_no_remote_control`·`ios_child_schedule_not_applied` 두 키도 **여기서 안 만든다.** 재료인 `platform: "ios"` 는 1단계가 상태 문서에 이미 심었다.
- **실기기 확인 열 항목**(설계서 §12.4). 4단계에서 주인의 허락을 받고 한다. 특히 강제 종료 뒤 되살아나는지(§17 열린 질문 3)와 백그라운드 새로고침을 끄면 정말 배달이 멎는지(§17 열린 질문 4)는 **여기서 확인할 수 없다** — 이 단계는 "고장으로 취급"한 채로 간다.
- **CoreMotion / 활동 인식**(§17 열린 질문 5). v1 에서 안 쓴다.
- **`CLMonitor`**(§17 열린 질문 2). 4단계 실기기 확인 뒤에 다시 본다.
- **2단계 I2**(도착 5분 안의 이탈이 조용히 사라진다). **정본과 글자까지 같은 동작이라 고치지 않는다** — 4단계 개발일지에 한 줄 남긴다.
- **2단계 M1·M2·M4·M5**(이름 예산 두 배, `decode` 숫자 해석, `SKIP_TOO_CLOSE` 업로드의 한 점 뒤처짐, 규칙이 보호자의 자작 이벤트를 안 막음). 전부 4단계 전수 검토 몫이다. 이 단계가 받는 2단계 미결은 **M3 하나뿐**이다(판정 기록 17).
- **골든 파일** — 이 단계는 `Logic/` 에 순수 함수를 안 더하므로 대조할 코틀린 함수가 없다(판정 기록 6).
- **`child_play_services_*` 세 키 제거** — 안드로이드가 쓴다(`ChildHomeActivity.kt:129-134`). 아이폰에 대응이 없을 뿐이다(판정 기록 11).

---

## 판정 기록 — 이 계획서가 내린 결정

1. **배선의 주인은 뷰가 아니라 `ChildSession` 이고, `KidCareApp.init()` 이 만든다.**
   2단계 통합 검토 I1 이 정확히 이 자리다 — 지금 수집기를 만드는 유일한 코드가 `ChildSimView` 의 `.task` 안이라 출시 빌드에서는 지역 전환이 아무에게도 안 배달된다. 설계서 §14 는 `ChildRootView` 라고만 적었는데, **뷰의 `.task` 에 두면 같은 사고가 그대로 남는다**: iOS 가 지역 경계나 중요 위치 변경으로 앱을 **백그라운드에** 되살릴 때 `WindowGroup` 의 body 가 평가된다는 보장이 없다(화면이 없으므로 그릴 이유가 없다). 그래서 소유자는 `@MainActor final class ChildSession`(`static let shared`)이고, 시작은 `KidCareApp.init()` 이 `FirebaseBootstrap.configureForApp()` **바로 뒤**에서 부른다. `ChildRootView` 는 그 세션을 읽어 그리기만 한다. 1단계 M6 도 같은 한 줄로 닫힌다 — 중요 위치 변경으로 되살아난 실행에도 이제 다시 시작할 것이 있다.
   `KidCareApp.init()` 은 테스트 프로세스에서도 돌므로 `RouterView` 가 이미 쓰는 것과 **같은 기준**(`XCTestConfigurationFilePath`)으로 문을 닫는다(`RouterView.swift:37` 의 이유가 그대로 걸린다 — 테스트가 아이 파이프라인을 띄우면 에뮬레이터에 쓰레기 문서가 쌓인다).

2. **`TrackingCoordinator.init` 의 `ticker: Ticking? = nil` 에서 기본값을 지운다.**
   1단계 수정 파동 보고서가 "3단계가 `ChildRootView` 를 만들 때 **반드시** `ticker:` 를 넘겨야 한다 — 안 넘기면 I1(멈춘 폰이 `.moving` 에 갇혀 하루 종일 조용해진다)이 그대로 되살아난다"고 경고했고, 그 경고가 지금은 **주석 한 줄**뿐이다. 주석은 잊힌다. 기본값을 지우면 모든 호출부가 `ticker:` 를 **글자로 적어야** 하고, 빠뜨리면 컴파일이 안 된다. 테스트는 `ticker: nil` 또는 `ticker: 가짜_시계()` 를 명시한다 — 지금 테스트가 인자를 생략하고 있으면 그 줄들을 고친다(Pre-flight 표 참고). 그 위에 실행 시 확인을 하나 더 얹는다: `ChildSessionTests.세션은_시계를_단다` 가 세션이 만든 코디네이터에 **좌표 없이 tick 만 주고** 모드가 내려가는지 본다.

3. **`-childSim` 문을 지운다.** 1단계 판정 기록 9 가 "3단계가 `ChildRootView` 를 만들면 이 파일과 `ChildSimHarness` 를 지운다"고 예고했고, 이제 진짜 길이 생겼다. 지우는 것 넷: `ios/KidCare/Child/ChildSimHarness.swift`, `ios/KidCare/Child/ChildSimView.swift`, `ios/KidCareTests/ChildSimHarnessTests.swift`, `RouterView.swift:48-55` 의 `#if DEBUG` 갈래. 남기면 **파이프라인을 조립하는 코드가 두 벌**이 되고, 둘 중 하나만 고치는 사고가 이 저장소에서 이미 여러 번 났다.
   **딱 하나만 좁게 남긴다** — `-childBattery <0~100>`. 시뮬레이터는 배터리를 안 주므로(`DeviceState.swift:62-65`) 이 인자가 없으면 상태 문서가 늘 `battery: -1` 이고 `ConditionWatcher` 의 15% 갈래를 **시뮬레이터에서 확인할 방법이 사라진다**(`ConditionWatcher.kt:98` 이 `percent !in 1..100` 을 그냥 돌려보내기 때문이다). 이것은 파이프라인을 따로 만들지 않고 값 하나를 주입할 뿐이라 "두 벌"이 되지 않는다. `#if DEBUG` 안에 두고 출시 빌드에 문자열조차 안 남는 것을 Task 4 가 `strings` 로 확인한다(1단계가 같은 확인을 했다).

4. **감시하는 권한은 넷이고, 순서가 곧 고치는 순서다.** 설계서 §8.6 이 정했다. `PermissionStep.firstMissing`(`PermissionStep.kt:88-89`)과 같은 모양의 `ChildPermissions.firstMissing()` 하나로 화면과 `ConditionWatcher` 가 **같은 목록**을 본다.

   | # | 아이폰 권한 | 읽는 곳 | 안드로이드 대응 |
   |---|---|---|---|
   | 1 | 위치 권한 자체(`.notDetermined`/`.denied`/`.restricted`) | `CLLocationManager.authorizationStatus` | `PermissionStep.LOCATION_FINE` |
   | 2 | 항상 허용(`.authorizedWhenInUse` 면 빠진 것) | 같음 | `PermissionStep.LOCATION_BACKGROUND` |
   | 3 | 정확한 위치(`.reducedAccuracy` 면 빠진 것) | `CLLocationManager.accuracyAuthorization` | **없다**(설계서 §15-8) |
   | 4 | 백그라운드 앱 새로고침 | `UIApplication.shared.backgroundRefreshStatus` | **없다**(설계서 §8.4) |

   순서를 이렇게 두는 이유는 안드로이드와 같다 — 1이 없으면 2를 물을 수 없고(iOS 는 '항상'을 곧바로 못 묻는다, §8.1), 2가 없으면 3·4를 고쳐도 화면을 벗어나는 순간 하루가 조용해진다.

5. **저전력 모드는 권한이 아니다 — 화면 한 줄이고, 이벤트를 만들지 않는다.** 설계서 §8.3 이 정했고 근거가 안드로이드에 있다: `ConditionWatcher.kt:43-46` 이 `BATTERY_UNRESTRICTED` 를 감시 목록에서 뺀 이유와 **같은 판단**이다("아이가 언제든 껐다 켰다 하는 설정이라 알리기 시작하면 소음이 된다"). 그래서 `ChildPermissions` 에 넣지 않고 `ChildHomeModel` 이 **덧붙이는 한 줄**로만 둔다 — 다른 문제와 **함께** 보일 수 있는 유일한 문장이다(판정 기록 10 의 "한 번에 하나"에 대한 유일한 예외이고, 이유는 이것이 고장이 아니라 주의사항이라서다).

6. **`Logic/` 에 파일을 하나도 더하지 않는다.** 설계서 §3.1 의 여덟은 1·2단계가 전부 옮겼다. 이 단계가 만드는 것은 `CLLocationManager`·`UIApplication`·`Firestore` 를 아는 것들뿐이라 `Child/` 에 산다. **그래서 골든 파일이 없다** — 대조할 코틀린 순수 함수가 없다. 대신 `ChildPermissions` 의 "어느 상태가 어느 항목을 빠진 것으로 치나"와 `ChildHomeModel` 의 "그때 어떤 문장 하나를 보여주나"는 순수 판정이라 `CLAuthorizationStatus` 같은 값을 **인자로 받는 정적 함수**로 갈라 두고, 그 함수만 단위 테스트한다(설계서 §12.1 의 "순수한 부분을 따로 뽑아 테스트한다"와 같은 방식).

7. **`permission_off` 하나로 아이폰의 권한 고장 넷을 전부 알린다. 새 `EventType` 을 만들지 않는다.**
   정본이 그렇게 한다 — `ConditionWatcher.kt:123-142` 는 꺼진 것들의 **이름 집합**을 통째로 기억하고, 집합이 늘어난 순간에 `PERMISSION_OFF` **문서 하나**를 쓴다(여럿이 한꺼번에 꺼져도 하나다, `:119-121`). 부모 화면은 `alert_permission_off`(`ko.json:10`)와 `event_detail_permission`(`:124`)을 **이미** 갖고 있고 한 줄도 안 바뀐다. 아이폰 전용 이름 넷(`ios_child_perm_*_title` 과 기존 `perm_location_title`)이 `detail` 의 `%1$s` 자리에 들어갈 뿐이다.
   `EventType.SIGNAL_LOST`(`Documents.kt:454`)를 쓰고 싶어질 자리가 하나 있는데(아래 8번), **쓰지 않는다** — 안드로이드 아이도 그 값을 안 쓰고(부모 쪽 `DisconnectRule` 자리다), 한쪽만 쓰기 시작하면 두 플랫폼의 알림 목록이 갈린다.

8. **1단계 이월의 "4시간 유휴 업로드가 스트림이 죽어도 `lastSeenAt` 을 갱신한다"에 대한 답은 `ConditionWatcher` 다.**
   1단계 수정 파동이 `tick` 에 유휴 업로드(설계서 §6.4 규칙 2, 4시간)를 넣으면서 **정직하게** 적어 뒀다: 올라가는 `at` 은 마지막으로 **실제로 받은** 점의 진짜 시각이라 위치를 "방금"으로 속이지 않는다. 그런데 서버 쪽 `updatedAt` 은 새로 찍히므로 부모 화면의 "마지막 신호"는 살아난다 — **좌표 스트림이 죽어 있어도** 그렇다. 이것은 버그가 아니라 설계다(§6.4 규칙 2 가 원하는 바로 그 동작이다). 빠진 것은 **"왜 조용한지"를 말하는 입**이었다.
   그 입이 `ConditionWatcher` 다. 스트림이 죽는 원인 넷은 전부 판정 기록 4 의 감시 목록 안에 있고(권한 없음 / 앱 사용 중만 / 정확한 위치 꺼짐 / 백그라운드 새로고침 꺼짐), 꺼지는 **순간** `permission_off` 가 나간다. 그리고 이 검사는 좌표에만 묶여 있으면 안 된다 — 좌표가 안 오는 것이 바로 증상이기 때문이다. 그래서 `onCondition` 은 `handle()`(좌표) **과** `tick()`(60초 시계) **둘 다**에서 불린다. 1단계가 그 자리를 이미 그렇게 만들어 뒀다(`TrackingCoordinator.swift:117` 과 `:250`) — 이 단계는 훅을 잇기만 한다. 60초 주기는 `TrackingService.kt:913` `CONDITION_CHECK_INTERVAL_MILLIS` 와 같은 값이고, `TrackingTicker.periodMillis` 가 이미 그 값이다.
   **나머지 원인 둘(강제 종료, 앱이 통째로 죽음)은 `ConditionWatcher` 가 말할 수 없다** — 말할 프로세스가 없기 때문이다. 그 자리는 부모 화면의 무응답 배너와 아이 화면의 강제 종료 문장(판정 기록 9)이 나눠 덮는다. 이것을 계획서에 적어 두는 이유는, 적지 않으면 다음 사람이 "감시가 다 덮는다"고 읽기 때문이다.

9. **강제 종료를 화면에 적는다. 그리고 로그에도 적는다.** 설계서 §5.3·§15-2 가 "아이폰이 안드로이드를 못 따라가는 가장 큰 자리"라고 못 박았고, 1단계 `LocationCollector.swift:77-78` 이 이미 코드 주석으로는 정직하다. **아이에게 말하는 일은 3단계 몫**이라고 그 주석이 적어 뒀다. 문구는 아래 그대로 쓴다(새 키 `ios_child_force_quit_notice`).

   > **ko:** 앱을 완전히 닫으면(앱 전환기에서 위로 밀기) 위치가 멈춰요. 다시 열 때까지 엄마 아빠가 볼 수 없어요.
   > **en:** If you close the app all the way (swipe it away in the app switcher), your location stops. Your parents cannot see you until you open it again.

   이 줄은 **고장 문구가 아니라 상시 안내**다 — 공유가 정상일 때도 아이 화면 아래에 늘 있다. 고장일 때만 보여주면 정작 강제 종료한 아이는 그 화면을 못 본다(앱이 없으니까).
   개발 로그(번역 대상이 아니다. `ChildSession` 이 뜰 때 한 번, `Logger(category: "ChildSession").notice`):

   > 강제 종료(앱 전환기에서 위로 밀기) 뒤에는 iOS 가 이 앱을 되살리지 않는다 — 중요 위치 변경도, 지역 감시도 오지 않는다. 아이가 앱을 다시 열거나 폰을 껐다 켤 때까지 기록이 통째로 없다(설계서 §5.3·§15-2). 되살리기가 도는 것은 메모리 압박으로 OS 가 종료했을 때와 재부팅 뒤뿐이다.

10. **화면은 한 번에 하나만 말한다. 순서는 "이걸 고쳐야 다음이 의미 있는가"다.** `ChildHomeActivity.kt:49-51` 그대로다. 아이폰의 순서: **가족에서 빠짐 → 권한 넷(판정 기록 4 의 순서) → 공유 중.** 안드로이드의 Play 서비스 갈래 자리에 아이폰은 아무것도 안 넣는다(판정 기록 11). 저전력 모드 한 줄과 강제 종료 한 줄은 이 셋 **어느 것과도 함께** 보인다(각각 판정 기록 5·9).

11. **Play 서비스 갈래를 안 옮긴다. 그 문구 키도 안 지운다.** `ChildHomeActivity.kt:125-136` 은 `GoogleApiAvailability` 가 재료인데 아이폰에 대응이 없다. 그 자리에 아이폰이 놓는 "조용한 고장"은 **정확한 위치 끄기**(설계서 §8.2 — "이 앱에서 가장 조용한 고장이다")이고 그것은 이미 판정 기록 4 의 3번이다. `child_play_services_fixable`/`_unfixable`/`child_play_services_fix` 세 키는 **안드로이드가 쓰고 있으므로 그대로 둔다** — `ios_child_unsupported_*` 를 지우는 근거(아무도 안 쓴다)가 여기에는 없다.

12. **가족에서 빠졌는지 묻는 함수를 iOS 에 더한다 — 모르면 아무 말도 바꾸지 않는다.**
    `FamilyRepository.isStillMember(familyId:uid:) async -> Bool?` 를 안드로이드(`FamilyRepository.kt:422-433`)에서 그대로 옮긴다. 세 갈래가 핵심이다: 캐시에서 온 "없음"은 **모름(`nil`)**, `PERMISSION_DENIED` 는 **빠짐(`false`)**, 그 밖의 실패는 **모름**. `nil` 이면 화면은 아무 말도 바꾸지 않는다(`ChildHomeActivity.kt:146-147`: "확실하지 않은 것으로 화면을 겁주지 않는다"). 기존 `fetchMember` 를 쓰지 않는 이유: 그것은 던지거나 `nil` 을 주는데 **"없다"와 "못 읽었다"가 같은 값**이라 정확히 이 구분을 못 한다.
    읽기 하나가 더 든다. 아이 화면은 아이가 어쩌다 한 번 여는 곳이라 하루 몇 번 수준이다(`:142-144` 의 같은 계산).

13. **‘다시 연결’ 버튼을 둔다.** §17 열린 질문 9 의 추천대로이고 조건도 안드로이드와 같다 — **서버가 "이 기기는 이 가족의 멤버가 아니다"라고 확답했을 때에만** 뜬다(`ChildHomeActivity.kt:168-173`). 그 시점에는 이미 풀 감시가 남아 있지 않다. 누르면 `RoleStore.shared.clear()` + `ChildSession.shared.stop()` 이고 역할 선택으로 돌아간다.

14. **새 i18n 키 아홉, 지우는 키 셋. `INFOPLIST_KEYS` 는 이미 확장돼 있다.**
    설계서 §8.5 가 적은 새 키 목록에서 `ios_child_no_remote_control`·`ios_child_schedule_not_applied` 둘은 **4단계 몫**이라 빼고(보호자 화면 문구다), 판정 기록 9 의 `ios_child_force_quit_notice` 하나를 더한다. `ios_perm_location_when_in_use`·`ios_perm_location_always` 와 `tools/ios-strings.py:31-35` 의 `INFOPLIST_KEYS` 확장은 **1단계가 이미 했다**(선행 조건 grep 으로 확인) — 설계서 §8.5 의 그 줄은 이 단계에서 할 일이 없다.
    지우는 셋(`ios_child_unsupported_title`/`_body`/`_confirm`)은 §17 열린 질문 7 의 판정대로 지운다. `ko.json`·`en.json` 에만 있고 안드로이드가 안 쓴다.

15. **'항상 허용'은 두 걸음이고, 그 두 걸음을 화면이 직접 이끈다.** 1단계 `LocationCollector.requestAuthorization()`(`:89-97`)이 이미 `.notDetermined → requestWhenInUseAuthorization()`, `.authorizedWhenInUse → requestAlwaysAuthorization()` 으로 갈라 뒀다("두 번째 걸음과 화면 안내는 3단계가 정한다"고 적혀 있다). 아이 화면의 버튼은 **같은 함수 하나**를 부른다 — 두 걸음을 화면이 다시 적지 않는다. 다만 `.denied`/`.restricted` 와 정확한 위치·백그라운드 새로고침은 **대화상자로 못 고친다** → 그때 버튼은 `UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)` 이다(새 키 `ios_child_open_settings`).

16. **`requestTemporaryFullAccuracyAuthorization` 을 쓰지 않는다.** 설계서 §8.2 가 정했다 — 한 세션만 살아서 다음에 또 같은 침묵이 온다. 아이가 설정에서 켜는 것이 유일한 진짜 해결이다.

17. **2단계 M3 을 여기서 닫는다 — 목록이 실제로 바뀐 때만 지역을 다시 건다.**
    지금 `PlaceWatcher.apply(placeDocs:)` 는 스냅샷마다 `replaceMonitoredRegions` 를 부르고, `observePlaces` 가 `includeMetadataChanges: true`(`PlaceRepository.swift:42`)라 앱이 뜨자마자 캐시본·서버본으로 **두 번** 돈다. 이 단계가 배선을 진짜 시작 경로로 옮기면 그 두 번이 **모든 실행에서** 일어난다 — 그때마다 스무 개를 지웠다 다시 거는 것은 iOS 의 초기 상태 판정을 매번 처음부터 시키는 일이다. 고치는 방법은 한 줄이다: 고른 결과(`GeofenceRegionSelection.chooseWithReport` 의 `places`)가 **직전과 같으면 `replaceMonitoredRegions` 를 건너뛴다.** 비교는 `Place` 의 `id`·`lat`·`lng`·`radiusMeters` 넷으로 한다 — 이름이나 알림 스위치가 바뀌어도 OS 에 건 원은 그대로이므로 다시 걸 이유가 없다(판정은 `places` 를 보고 하고, 그 목록은 어차피 갱신된다).
    **`places` 자체는 항상 갱신한다** — 건너뛰는 것은 OS 등록뿐이다. 이 구분을 놓치면 지운 장소의 판정이 살아남는다.

18. **에뮬레이터 테스트를 새로 만들지 않는다.** 이 단계가 쓰는 유일한 Firestore 쓰기는 `EventRepository.add` 로 나가는 `permission_off` 이고, 그 경로(`childUid`·`read == false`·`at` 밀리초·거부 다섯)는 **2단계 `ChildEventWriteTests` 일곱이 이미 에뮬레이터로 태웠다**. 같은 함수·같은 문서 모양이라 두 벌이 된다. 대신 `ConditionWatcherTests` 가 **어떤 `EventDoc` 을 만드는지**를 가짜 `addEvent` 로 고정하고(2단계 판정 기록 13 과 같은 갈라치기), 실제 쓰기는 Task 4 의 시뮬레이터 확인이 눈으로 본다.

---

## File Structure

```
i18n/
├─ ko.json                              수정. 새 키 아홉 + `ios_child_unsupported_*` 셋 삭제
└─ en.json                              수정. 같음
tools/
└─ i18n-untranslated.json               재생성(--write-gaps)
ios/KidCare/
├─ KidCareApp.swift                     수정. init() 이 ChildSession.shared.startIfChild() 를 부른다
├─ RouterView.swift                     수정. #if DEBUG -childSim 갈래 삭제 + child 갈래 추가
├─ Onboarding/
│  └─ RoleSelectView.swift              수정. 아이 버튼이 JoinFamilyView(expectedRole: .child) 로 간다
├─ Core/
│  └─ FamilyRepository.swift            수정. isStillMember(familyId:uid:) 추가 (FamilyRepository.kt:422)
└─ Child/
   ├─ ChildPermissions.swift            신규. 감시 권한 넷의 상태·이름·고치는 방법 (onboarding/PermissionStep.kt)
   ├─ ConditionWatcher.swift            신규. 배터리·권한이 나빠진 순간 한 번만 (child/ConditionWatcher.kt)
   ├─ ChildSession.swift                신규. 앱 시작 시 파이프라인 조립. 앱당 하나
   ├─ ChildHomeModel.swift              신규. 화면이 무엇을 말할지 정한다 (ChildHomeActivity.kt:70-82)
   ├─ ChildHomeView.swift               신규. 그 문장을 그린다. 버튼 하나 (activity_child_home.xml)
   ├─ ChildRootView.swift               신규. 역할이 child 일 때의 뿌리. 탭이 없다
   ├─ PlaceWatcher.swift                수정. 목록이 바뀐 때만 지역 재등록 (2단계 M3)
   ├─ TrackingCoordinator.swift         수정. init 의 ticker 기본값 제거
   ├─ ChildSimHarness.swift             **삭제**
   └─ ChildSimView.swift                **삭제**
ios/KidCareTests/
├─ ChildPermissionsTests.swift          신규. 상태 조합 → 빠진 첫 항목
├─ ConditionWatcherTests.swift          신규. 배터리 15/20, 권한 집합 전환, 한 번만
├─ ChildHomeModelTests.swift            신규. 상태 조합 → 문장 하나 (설계서 §12.1)
├─ ChildSessionTests.swift              신규. 시계가 달렸나, 역할이 아니면 안 뜨나
├─ TrackingCoordinatorTests.swift       수정. ticker: 를 명시 (기본값 제거)
├─ PlaceWatcherTests.swift              수정. 같은 목록이면 다시 안 건다
└─ ChildSimHarnessTests.swift           **삭제**
ios/dev/
└─ child-permissions.md                 신규(선택). 시뮬레이터에서 권한을 끄는 절차 메모
```

---

## Task 1: 권한 넷과 조건 감시 — 꺼진 순간 부모에게 한 번

**끝나면 `ChildPermissions.firstMissing` 이 아이폰의 권한 넷을 안드로이드와 같은 순서로 돌려주고, `ConditionWatcher` 가 배터리 15%·권한 전환에 `events/` 문서를 딱 하나 만든다(같은 상태가 이어지면 Firestore 를 한 번도 안 건드린다).**

**Files:**
- Create: `ios/KidCare/Child/ChildPermissions.swift`, `ios/KidCare/Child/ConditionWatcher.swift`
- Create: `ios/KidCareTests/ChildPermissionsTests.swift`, `ios/KidCareTests/ConditionWatcherTests.swift`
- Modify: `i18n/ko.json`, `i18n/en.json`, `tools/i18n-untranslated.json`

- [ ] **Step 1: 문구 키를 넣는다 (공통 절차 A)**

`i18n/ko.json` 과 `i18n/en.json` **둘 다**에 아래 아홉을 코드 포인트 순 자리에 넣는다. **12개 언어 파일은 건드리지 않는다.** 같은 커밋에서 `ios_child_unsupported_title`/`_body`/`_confirm` 셋을 지운다 — 쓰는 곳(`RoleSelectView.swift:89-97`)은 Task 3 이 없앤다. **키를 먼저 지우고 쓰는 곳을 나중에 없애면 그 사이 커밋이 빌드는 되지만 화면에 키 이름이 그대로 뜬다.** 그래서 이 Step 은 **더하기만 하고**, 셋을 지우는 것은 Task 3 Step 1 이다.

| 키 | ko | en |
|---|---|---|
| `ios_child_perm_always_title` | 위치 '항상 허용' | Location 'Always' |
| `ios_child_perm_always_reason` | '앱을 사용하는 동안'으로 되어 있어요. 화면을 벗어나면 위치가 멈춰요. 설정에서 '항상'으로 바꿔주세요. | It is set to 'While Using the App'. Your location stops as soon as you leave the screen. Change it to 'Always' in Settings. |
| `ios_child_perm_precise_title` | 정확한 위치 | Precise Location |
| `ios_child_perm_precise_reason` | 정확한 위치가 꺼져 있어요. 이러면 위치가 너무 흐릿해서 아무것도 전달되지 않아요. 설정에서 켜주세요. | Precise Location is off. Your location is too fuzzy to send anything at all. Turn it on in Settings. |
| `ios_child_perm_refresh_title` | 백그라운드 앱 새로고침 | Background App Refresh |
| `ios_child_perm_refresh_reason` | 이게 꺼져 있으면 앱을 보고 있을 때만 위치가 전달돼요. 설정에서 켜주세요. | With this off, your location is only sent while you are looking at the app. Turn it on in Settings. |
| `ios_child_low_power_notice` | 저전력 모드가 켜져 있어 위치가 드문드문 올 수 있어요. | Low Power Mode is on, so your location may arrive less often. |
| `ios_child_open_settings` | 설정 열기 | Open Settings |
| `ios_child_force_quit_notice` | 앱을 완전히 닫으면(앱 전환기에서 위로 밀기) 위치가 멈춰요. 다시 열 때까지 엄마 아빠가 볼 수 없어요. | If you close the app all the way (swipe it away in the app switcher), your location stops. Your parents cannot see you until you open it again. |

1번 권한(위치 권한 자체)은 **이미 있는 키를 쓴다** — `perm_location_title`(`ko.json`) / `perm_location_reason`. 14개 언어에 다 있다(설계서 §8.5 "그대로 쓰는 키"의 규율).

```bash
cd /Users/com/work/KidCare
python3 tools/ios-strings.py --write-gaps
git diff --stat tools/i18n-untranslated.json   # 새 키 아홉 × 12개 언어만큼 빈 칸이 는다 — 눈으로 본다
python3 tools/ios-strings.py --check           # 0
```

- [ ] **Step 2: 테스트를 먼저 쓴다 (빨강)**

`ios/KidCareTests/ChildPermissionsTests.swift`:

```swift
import CoreLocation
import Testing
import UIKit
@testable import KidCare

/// 감시하는 권한 넷과 **그 순서**를 고정한다. 순서는 "이걸 고쳐야 다음이 의미 있는가"이고
/// 정본은 `onboarding/PermissionStep.kt:18-89` 다(그쪽 여섯 중 넷, 설계서 §8.6).
struct ChildPermissionsTests {

    /// 전부 정상인 조합 하나 — 여기서 nil 이 안 나오면 아래 갈래들이 전부 의미가 없다.
    private let 정상 = ChildPermissions.Snapshot(
        authorization: .authorizedAlways, accuracy: .fullAccuracy, backgroundRefresh: .available)

    @Test("다 켜져 있으면 빠진 것이 없다")
    func 정상이면_없다() {
        #expect(ChildPermissions.firstMissing(정상) == nil)
    }

    @Test("위치 권한 자체가 먼저다 — 없으면 나머지를 물을 수조차 없다 (§8.1)")
    func 위치가_먼저() {
        for status in [CLAuthorizationStatus.notDetermined, .denied, .restricted] {
            var s = 정상
            s.authorization = status
            // 정확한 위치도 새로고침도 같이 꺼 둔다. 그래도 **위치 권한이 이긴다**.
            s.accuracy = .reducedAccuracy
            s.backgroundRefresh = .denied
            #expect(ChildPermissions.firstMissing(s) == .location, "\(status)")
        }
    }

    @Test("'앱 사용 중만'은 항상 허용이 빠진 것이다 — 화면을 벗어나면 하루가 조용해진다 (§8.1)")
    func 앱_사용_중만() {
        var s = 정상
        s.authorization = .authorizedWhenInUse
        #expect(ChildPermissions.firstMissing(s) == .always)
    }

    @Test("정확한 위치가 꺼지면 점이 하나도 안 쌓인다 — 가장 조용한 고장 (§8.2)")
    func 정확한_위치() {
        var s = 정상
        s.accuracy = .reducedAccuracy
        #expect(ChildPermissions.firstMissing(s) == .precise)
    }

    @Test("백그라운드 앱 새로고침이 꺼지면 앱을 볼 때만 점이 온다 (§8.4·§17-4)")
    func 새로고침() {
        var s = 정상
        s.backgroundRefresh = .denied
        #expect(ChildPermissions.firstMissing(s) == .backgroundRefresh)
        s.backgroundRefresh = .restricted
        #expect(ChildPermissions.firstMissing(s) == .backgroundRefresh)
    }

    @Test("여럿이 꺼져 있으면 고치는 순서대로 앞의 것 하나만 준다")
    func 순서() {
        var s = 정상
        s.authorization = .authorizedWhenInUse
        s.accuracy = .reducedAccuracy
        s.backgroundRefresh = .denied
        #expect(ChildPermissions.firstMissing(s) == .always)
    }

    @Test("꺼진 것 전부의 이름 집합 — ConditionWatcher 가 이 집합의 증가를 전환으로 읽는다")
    func 꺼진_전부() {
        var s = 정상
        s.authorization = .authorizedWhenInUse
        s.backgroundRefresh = .denied
        #expect(ChildPermissions.allMissing(s) == [.always, .backgroundRefresh])
        #expect(ChildPermissions.allMissing(정상).isEmpty)
    }

    @Test("항목마다 제목·이유 키가 있고, 위치 권한만 기존 14개 언어 키를 쓴다 (§8.5)")
    func 문구_키() {
        #expect(ChildPermissions.Item.location.titleKey == "perm_location_title")
        #expect(ChildPermissions.Item.location.reasonKey == "perm_location_reason")
        #expect(ChildPermissions.Item.always.titleKey == "ios_child_perm_always_title")
        #expect(ChildPermissions.Item.precise.titleKey == "ios_child_perm_precise_title")
        #expect(ChildPermissions.Item.backgroundRefresh.titleKey == "ios_child_perm_refresh_title")
        for item in ChildPermissions.Item.allCases {
            #expect(!item.reasonKey.isEmpty)
        }
    }

    @Test("대화상자로 고칠 수 있는 것과 설정으로 보내야 하는 것이 갈린다 (판정 기록 15)")
    func 고치는_방법() {
        var s = 정상
        s.authorization = .notDetermined
        #expect(ChildPermissions.fix(for: .location, in: s) == .ask)
        s.authorization = .authorizedWhenInUse
        #expect(ChildPermissions.fix(for: .always, in: s) == .ask)
        s.authorization = .denied
        #expect(ChildPermissions.fix(for: .location, in: s) == .settings)
        // 정확한 위치와 새로고침은 물을 API 자체가 없다(§8.2 — 임시 정확도는 안 쓴다).
        #expect(ChildPermissions.fix(for: .precise, in: 정상) == .settings)
        #expect(ChildPermissions.fix(for: .backgroundRefresh, in: 정상) == .settings)
    }
}
```

`ios/KidCareTests/ConditionWatcherTests.swift`:

```swift
import CoreLocation
import Foundation
import Testing
import UIKit
@testable import KidCare

/// 정본 `child/ConditionWatcher.kt`. 문턱 둘(:173 15 / :176 20)과 "한 번만"(:100-107·:123-142),
/// 그리고 **아무것도 안 달라졌으면 Firestore 를 한 번도 안 건드린다**(:71-74)를 고정한다.
@MainActor
struct ConditionWatcherTests {

    private func 새_저장소() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "조건감시-\(UUID().uuidString)")!
        return defaults
    }

    /// 쓴 이벤트를 모으는 가짜. 2단계 `PlaceWatcherTests` 의 가짜와 같은 모양이다.
    private final class 기록 {
        var docs: [EventDoc] = []
        func add(_ familyId: String, _ doc: EventDoc) async throws { docs.append(doc) }
    }

    private let 정상 = ChildPermissions.Snapshot(
        authorization: .authorizedAlways, accuracy: .fullAccuracy, backgroundRefresh: .available)

    @Test("배터리 15% 아래로 처음 내려가면 한 번 (:173)")
    func 배터리_한_번() async throws {
        let 기록부 = 기록()
        let watcher = ConditionWatcher(defaults: 새_저장소(), addEvent: 기록부.add)
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 14, permissions: 정상, now: 1_000)
        #expect(기록부.docs.count == 1)
        #expect(기록부.docs[0].type == EventType.lowBattery)
        #expect(기록부.docs[0].at == 1_000)
        #expect(기록부.docs[0].childUid == "C")
        // 같은 상태가 이어지면 아무것도 안 나간다 — 쓰기도 읽기도 0.
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 12, permissions: 정상, now: 2_000)
        #expect(기록부.docs.count == 1)
    }

    @Test("20% 위로 충전되면 다시 한 번 알릴 수 있게 풀린다 (:176, 히스테리시스)")
    func 배터리_풀림() async throws {
        let 기록부 = 기록()
        let defaults = 새_저장소()
        let watcher = ConditionWatcher(defaults: defaults, addEvent: 기록부.add)
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 14, permissions: 정상, now: 1)
        // 19% 는 아직 안 풀린다 — 14↔15 를 오가는 폰이 경고를 계속 올리는 것을 막는 그 간격이다.
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 19, permissions: 정상, now: 2)
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 14, permissions: 정상, now: 3)
        #expect(기록부.docs.count == 1)
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 20, permissions: 정상, now: 4)
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 14, permissions: 정상, now: 5)
        #expect(기록부.docs.count == 2)
    }

    @Test("배터리를 못 읽으면(-1) 아무 판단도 안 한다 (:96-98)")
    func 배터리_모름() async throws {
        let 기록부 = 기록()
        let watcher = ConditionWatcher(defaults: 새_저장소(), addEvent: 기록부.add)
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: -1, permissions: 정상, now: 1)
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 0, permissions: 정상, now: 2)
        #expect(기록부.docs.isEmpty)
    }

    @Test("권한이 꺼지면 permission_off 하나. 새 EventType 을 만들지 않는다 (판정 기록 7)")
    func 권한_한_번() async throws {
        let 기록부 = 기록()
        let watcher = ConditionWatcher(defaults: 새_저장소(), addEvent: 기록부.add)
        var 꺼짐 = 정상
        꺼짐.authorization = .authorizedWhenInUse
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 80, permissions: 꺼짐, now: 10)
        #expect(기록부.docs.count == 1)
        #expect(기록부.docs[0].type == EventType.permissionOff)
        // detail 은 `event_detail_permission`(%1$s 에 권한 이름)이다 — 부모 화면이 이미 읽는 키다.
        #expect(기록부.docs[0].detail.contains(String(localized: "ios_child_perm_always_title")))
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 80, permissions: 꺼짐, now: 20)
        #expect(기록부.docs.count == 1)
    }

    @Test("여럿이 한꺼번에 꺼져도 문서는 하나다 (:119-121)")
    func 여럿이_하나() async throws {
        let 기록부 = 기록()
        let watcher = ConditionWatcher(defaults: 새_저장소(), addEvent: 기록부.add)
        var 꺼짐 = 정상
        꺼짐.authorization = .denied
        꺼짐.accuracy = .reducedAccuracy
        꺼짐.backgroundRefresh = .denied
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 80, permissions: 꺼짐, now: 10)
        #expect(기록부.docs.count == 1)
    }

    @Test("다시 켠 것은 기억만 갱신하고 알리지 않는다 — 소음이 아니라 정상 복귀다 (:115-117)")
    func 다시_켜면_조용() async throws {
        let 기록부 = 기록()
        let watcher = ConditionWatcher(defaults: 새_저장소(), addEvent: 기록부.add)
        var 꺼짐 = 정상
        꺼짐.backgroundRefresh = .denied
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 80, permissions: 꺼짐, now: 10)
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 80, permissions: 정상, now: 20)
        #expect(기록부.docs.count == 1)
        // 다시 꺼지면 그때는 또 알린다(집합이 다시 늘어난 순간이다).
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 80, permissions: 꺼짐, now: 30)
        #expect(기록부.docs.count == 2)
    }

    @Test("프로세스가 죽어도 '이미 알렸다'가 남는다 — 같은 저장소로 새로 만들어 본다 (:50-56)")
    func 프로세스_밖() async throws {
        let defaults = 새_저장소()
        let 첫번째 = 기록()
        try await ConditionWatcher(defaults: defaults, addEvent: 첫번째.add)
            .check(familyId: "F", childUid: "C", batteryPercent: 14, permissions: 정상, now: 1)
        #expect(첫번째.docs.count == 1)
        let 두번째 = 기록()
        try await ConditionWatcher(defaults: defaults, addEvent: 두번째.add)
            .check(familyId: "F", childUid: "C", batteryPercent: 14, permissions: 정상, now: 2)
        #expect(두번째.docs.isEmpty, "재시작할 때마다 같은 경고가 새로 올라가면 안 된다")
    }

    @Test("표시를 쓰기보다 먼저 한다 — 쓰기가 실패해도 같은 경고가 큐에 쌓이지 않는다 (:58-62)")
    func 쓰기_실패() async throws {
        struct 터짐: Error {}
        let defaults = 새_저장소()
        var 시도 = 0
        let watcher = ConditionWatcher(defaults: defaults, addEvent: { _, _ in 시도 += 1; throw 터짐() })
        await #expect(throws: (any Error).self) {
            try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 14, permissions: 정상, now: 1)
        }
        // 두 번째 검사는 이미 "알렸다"로 기억돼 있어 쓰기를 다시 시도하지 않는다.
        try? await watcher.check(familyId: "F", childUid: "C", batteryPercent: 14, permissions: 정상, now: 2)
        #expect(시도 == 1)
    }

    @Test("저전력 모드는 이벤트를 만들지 않는다 (§8.3 — BATTERY_UNRESTRICTED 를 뺀 것과 같은 판단)")
    func 저전력은_조용() async throws {
        let 기록부 = 기록()
        let watcher = ConditionWatcher(defaults: 새_저장소(), addEvent: 기록부.add)
        // 감시 목록에 아예 없다는 것을 타입으로 고정한다.
        #expect(!ChildPermissions.Item.allCases.map(\.rawValue).contains("lowPower"))
        try await watcher.check(familyId: "F", childUid: "C", batteryPercent: 80, permissions: 정상, now: 1)
        #expect(기록부.docs.isEmpty)
    }
}
```

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/ChildPermissionsTests -only-testing:KidCareTests/ConditionWatcherTests`
Expected: **컴파일 실패**(타입이 아직 없다). 그것이 이 Step 의 빨강이다.

- [ ] **Step 3: `ChildPermissions` 를 만든다**

`ios/KidCare/Child/ChildPermissions.swift`:

```swift
import CoreLocation
import Foundation
import UIKit

/// 아이폰이 요구하는 권한 넷의 상태와 이름. 정본은 `onboarding/PermissionStep.kt` 이고,
/// 그 여섯 중 넷만 옮긴다 — 나머지 둘(`DND_ACCESS`·`NOTIFICATION`)은 아이폰에 **대응이 없다**
/// (설계서 §8.6: 소리 모드를 바꿀 API 가 없고, 아이 폰은 알림을 하나도 안 띄운다).
/// 대신 아이폰에만 있는 둘이 들어온다 — 정확한 위치(§8.2)와 백그라운드 앱 새로고침(§8.4).
///
/// **읽기를 스냅샷으로 갈라 두는 이유.** `CLLocationManager` 와 `UIApplication` 은 테스트에서
/// 만들 수 없다. 판정(어느 상태가 어느 항목을 빠진 것으로 치나)은 순수 함수라 값만 받으면
/// 되고, 그래야 `ChildPermissionsTests` 가 CoreLocation 없이 돈다(설계서 §12.1 의 규율).
enum ChildPermissions {

    /// **순서가 곧 고치는 순서다**(`PermissionStep.kt:13-16` 과 같은 규율). 위치 권한이 없으면
    /// '항상'을 물을 수조차 없고(§8.1 두 걸음), '항상'이 없으면 나머지를 고쳐도 화면을 벗어나는
    /// 순간 하루가 조용해진다.
    enum Item: String, CaseIterable {
        case location
        case always
        case precise
        case backgroundRefresh

        /// 1번은 **이미 14개 언어에 있는 키**를 쓴다(설계서 §8.5 "그대로 쓰는 키").
        var titleKey: String.LocalizationValue {
            switch self {
            case .location: "perm_location_title"
            case .always: "ios_child_perm_always_title"
            case .precise: "ios_child_perm_precise_title"
            case .backgroundRefresh: "ios_child_perm_refresh_title"
            }
        }

        var reasonKey: String.LocalizationValue {
            switch self {
            case .location: "perm_location_reason"
            case .always: "ios_child_perm_always_reason"
            case .precise: "ios_child_perm_precise_reason"
            case .backgroundRefresh: "ios_child_perm_refresh_reason"
            }
        }

        var 이름: String { String(localized: titleKey) }
    }

    /// 지금 이 폰의 값 셋. 화면과 `ConditionWatcher` 가 **같은 스냅샷**을 본다 — 두 곳이
    /// 따로 읽으면 한쪽만 옛 값으로 판단하는 순간이 생긴다.
    struct Snapshot: Equatable {
        var authorization: CLAuthorizationStatus
        var accuracy: CLAccuracyAuthorization
        var backgroundRefresh: UIBackgroundRefreshStatus
    }

    /// 고치는 방법. `.ask` 는 그 자리에서 대화상자를 띄울 수 있다는 뜻이고,
    /// `.settings` 는 **물을 API 가 없어** 설정 앱으로 보내야 한다는 뜻이다.
    enum Fix { case ask, settings }

    /// 아직 안 된 첫 번째. 전부 됐으면 nil. `PermissionStep.firstMissing`(:88-89) 그대로다.
    static func firstMissing(_ s: Snapshot) -> Item? { allMissing(s).first }

    /// 지금 꺼져 있는 것 **전부**. `ConditionWatcher` 가 이 집합의 **증가**를 전환으로 읽는다
    /// (`ConditionWatcher.kt:113-117`: 집합이 늘어난 순간이 곧 전환이다).
    static func allMissing(_ s: Snapshot) -> [Item] {
        Item.allCases.filter { !isGranted($0, s) }
    }

    static func isGranted(_ item: Item, _ s: Snapshot) -> Bool {
        switch item {
        case .location:
            return s.authorization == .authorizedAlways || s.authorization == .authorizedWhenInUse
        case .always:
            // '앱 사용 중만'이 안드로이드 `LOCATION_BACKGROUND` 와 정확히 같은 자리다 —
            // 화면상으로는 위치 권한이 여전히 허용이라 아무도 모른다(`ConditionWatcher.kt:32-34`).
            return s.authorization == .authorizedAlways
        case .precise:
            // 오차 1~3km 로 들어와 완화 문턱(100m)도 못 넘는다. 점이 하나도 안 쌓이는데
            // 앱은 멀쩡히 돌고 파란 표시도 켜져 있다(§8.2).
            return s.accuracy == .fullAccuracy
        case .backgroundRefresh:
            // 애플 문서가 얇은 자리다. 확인 전까지 **고장으로 취급**한다(§17 열린 질문 4) —
            // 침묵을 침묵으로 두는 것보다 한 번 더 말하는 쪽이 이 앱의 규율이다.
            return s.backgroundRefresh == .available
        }
    }

    /// 앞의 것이 아직 안 됐으면 뒤의 것은 **판단하지 않는다**. `.location` 이 `.notDetermined`
    /// 인 동안 `.always` 를 "빠졌다"고 부르는 것은 맞지만 고칠 방법이 아직 없기 때문에,
    /// 화면은 늘 `firstMissing` 하나만 말한다(판정 기록 10).
    static func fix(for item: Item, in s: Snapshot) -> Fix {
        switch item {
        case .location:
            // 한 번 거부되면 앱이 다시 못 묻는다 — 설정으로 보낸다.
            return s.authorization == .notDetermined ? .ask : .settings
        case .always:
            // 두 걸음의 두 번째(§8.1). iOS 가 대화상자를 바로 안 띄울 수 있지만, 부르는 것이
            // 맞다 — 그 뒤 앱이 백그라운드에서 위치를 쓰면 iOS 가 스스로 묻는다.
            return s.authorization == .authorizedWhenInUse ? .ask : .settings
        case .precise:
            // `requestTemporaryFullAccuracyAuthorization` 을 **쓰지 않는다**(§8.2) —
            // 한 세션만 살아서 다음에 또 같은 침묵이 온다.
            return .settings
        case .backgroundRefresh:
            // 물을 API 가 아예 없다.
            return .settings
        }
    }

    /// 진짜 값을 읽는 자리. `@MainActor` 인 이유는 `UIApplication.shared` 다.
    @MainActor
    static func snapshot(manager: CLLocationManager) -> Snapshot {
        Snapshot(authorization: manager.authorizationStatus,
                 accuracy: manager.accuracyAuthorization,
                 backgroundRefresh: UIApplication.shared.backgroundRefreshStatus)
    }
}
```

- [ ] **Step 4: `ConditionWatcher` 를 만든다**

`ios/KidCare/Child/ConditionWatcher.swift`. 정본 `child/ConditionWatcher.kt` 의 구조를 그대로 옮긴다 — 클래스 주석의 "왜"도 함께 옮기되 아이폰에 맞게 고쳐 적는다.

```swift
import Foundation
import os

/// 아이 폰이 **자기 상태**를 감시해 부모에게 알린다. 정본은 `child/ConditionWatcher.kt` 다.
///
/// 장소 사건(`PlaceWatcher`)이 "아이가 어디 갔다"라면 여기는 "이 폰이 지금 제구실을 못 하고
/// 있다"이다. 쓰는 길은 완전히 같다 — `EventRepository.add` 로 `events/` 에 문서 하나.
/// 규칙과의 계약(`childUid`·`read == false`·`at` 은 밀리초 정수)도 그대로다.
///
/// ## 권한이 꺼진 것이 이 앱에서 제일 중요한 경고다
///
/// 배터리가 없으면 폰이 꺼지고, 폰이 꺼지면 부모 화면의 연결 끊김 배너가 결국 뜬다 — 늦어도
/// 알기는 안다. 그런데 **권한만 꺼지면 앱은 멀쩡히 켜져 있다.** 파란 위치 표시도 그대로 뜨고,
/// 4시간 유휴 업로드(설계서 §6.4 규칙 2)가 상태 문서를 계속 새로 찍어 부모 화면의 "마지막
/// 신호"까지 살아 있다. 그저 그날 하루가 조용할 뿐이다. 부모는 그것을 "오늘은 별일 없었구나"로
/// 읽는다. **이 감시가 그 침묵에 이유를 붙이는 유일한 입이다**(3단계 판정 기록 8).
///
/// ## 아이폰이 말할 수 없는 것
///
/// 앱이 강제 종료되거나 통째로 죽으면 이 감시도 함께 죽는다 — 말할 프로세스가 없다.
/// 그 자리는 부모 화면의 무응답 배너와 아이 화면의 강제 종료 안내가 나눠 덮는다(§5.3·§15-2).
///
/// ## 한 번만 알린다 — 프로세스가 죽어도
///
/// "이미 알렸다"를 메모리에 두면 앱이 다시 뜰 때마다 잊어버려, 12% 에 앉아 있는 폰이 재시작할
/// 때마다 같은 경고를 새로 올린다. 그래서 `UserDefaults` 에 적는다(코틀린의 SharedPreferences
/// `commit()` 자리, `:50-56`). `synchronize()` 는 **부르지 않는다** — 애플이 deprecated 로
/// 표시했고, `UserDefaults.set` 은 그 자리에서 메모리에 반영되며 디스크 플러시는 프로세스가
/// 죽어도 이어진다(2단계 `PlaceStateStore` 와 같은 판단).
///
/// **표시를 Firestore 쓰기보다 먼저 한다**(`:58-62`). 반대 순서면 오프라인일 때 쓰기가 매달린
/// 채로 검사가 다시 돌아 같은 경고가 여러 번 큐에 쌓이고, 연결이 돌아오는 순간 한꺼번에
/// 올라간다. 대가는 "쓰기가 진짜로 거부되면 그 경고 하나를 잃는다"뿐이다.
@MainActor
final class ConditionWatcher {

    /// 이 아래로 내려가면 알린다. `ConditionWatcher.kt:173`.
    static let lowPercent = 15
    /// 여기까지 충전되면 다음 한 번을 다시 알릴 수 있다. `:176`. 문턱을 벌린 것이
    /// `GeofenceEvaluator` 의 이탈 여유 50m 와 같은 히스테리시스다(`:88-93`).
    static let rearmPercent = 20

    private static let batteryKey = "kidcare_conditions.battery_reported"
    private static let permissionsKey = "kidcare_conditions.permissions_off"

    private let defaults: UserDefaults
    private let addEvent: (String, EventDoc) async throws -> Void
    private let logger = Logger(subsystem: "com.kidcare.family", category: "ConditionWatcher")

    init(defaults: UserDefaults = .standard,
         addEvent: @escaping (String, EventDoc) async throws -> Void = { familyId, doc in
             _ = try await EventRepository.add(familyId: familyId, doc: doc)
         }) {
        self.defaults = defaults
        self.addEvent = addEvent
    }

    /// 한 번 훑고, **달라진 것이 있을 때만** `events/` 에 적는다. 아무것도 안 달라졌으면
    /// Firestore 를 한 번도 안 건드린다 — 읽기도 쓰기도 0 이다(`:71-74`).
    ///
    /// `batteryPercent` 와 `permissions` 를 여기서 읽지 않고 받는 이유는 코틀린과 같다(`:76-77`):
    /// `DeviceState` 와 화면이 이미 같은 값을 읽는다. 두 번 적으면 언젠가 한쪽만 고친다.
    func check(familyId: String, childUid: String, batteryPercent: Int,
               permissions: ChildPermissions.Snapshot, now: Int64) async throws {
        try await checkBattery(familyId: familyId, childUid: childUid, percent: batteryPercent, now: now)
        try await checkPermissions(familyId: familyId, childUid: childUid, permissions: permissions, now: now)
    }

    private func checkBattery(familyId: String, childUid: String, percent: Int, now: Int64) async throws {
        // 못 읽으면(-1) 아무 판단도 하지 않는다. 그대로 흘려보내면 "0% 미만"이 되어 폰마다
        // 켜자마자 거짓 경고가 하나 나간다(`:96-98`). 시뮬레이터가 늘 이 상태다.
        guard (1...100).contains(percent) else { return }

        if defaults.bool(forKey: Self.batteryKey) {
            if percent >= Self.rearmPercent { defaults.set(false, forKey: Self.batteryKey) }
            return
        }
        guard percent < Self.lowPercent else { return }

        defaults.set(true, forKey: Self.batteryKey)
        try await add(familyId: familyId, childUid: childUid, type: EventType.lowBattery,
                      detail: String(localized: "event_detail_battery \(percent)"), now: now)
    }

    /// 지금 꺼져 있는 것들의 **이름 집합**을 통째로 기억한다. 이렇게 두면 "언제 꺼졌는가"를 따로
    /// 적을 필요 없이, 집합이 늘어난 순간이 곧 전환이다(`:113-117`). 다시 켠 것(집합이 줄어든
    /// 것)은 기억만 갱신하고 알리지 않는다 — 부모가 원하던 상태로 돌아간 것이라 소음이다.
    ///
    /// 여럿이 한꺼번에 꺼져도 문서는 하나다(`:119-121`). 위치를 통째로 끄면 '위치 권한'과
    /// '항상 허용'이 같이 꺼지는데, 그때 줄이 둘 뜨면 부모는 사고가 두 개 난 줄로 읽는다.
    private func checkPermissions(familyId: String, childUid: String,
                                  permissions: ChildPermissions.Snapshot, now: Int64) async throws {
        let offNow = ChildPermissions.allMissing(permissions)
        let names = Set(offNow.map(\.rawValue))
        let reported = Set(defaults.stringArray(forKey: Self.permissionsKey) ?? [])
        guard names != reported else { return }

        defaults.set(names.sorted(), forKey: Self.permissionsKey)

        let fresh = offNow.filter { !reported.contains($0.rawValue) }
        guard !fresh.isEmpty else { return }
        let 이름들 = fresh.map(\.이름).joined(separator: ", ")
        try await add(familyId: familyId, childUid: childUid, type: EventType.permissionOff,
                      detail: String(localized: "event_detail_permission \(이름들)"), now: now)
    }

    /// `at` 은 폰 시계다(`PlaceWatcher.onFix` 와 같은 판단, `:145-147`) — 규칙이 서버 시각과
    /// 대조해 과거 7일~미래 1시간 밖이면 거부하지만, 여기서 "지금"으로 바꿔치기하면 일어난
    /// 시각을 지어내는 셈이다.
    ///
    /// 실패는 삼키지 않고 위로 던진다(`:149-150`). 부르는 쪽(`ChildSession`)이 로그로 남긴다 —
    /// 이벤트 하나를 못 쓴 것 때문에 위치 수집이 멈추면 안 된다.
    private func add(familyId: String, childUid: String, type: String, detail: String, now: Int64) async throws {
        try await addEvent(familyId, EventDoc(type: type, at: now, childUid: childUid, detail: detail))
    }
}
```

`String(localized: "event_detail_battery \(percent)")` 의 모양은 **이 저장소의 기존 자리에 맞춘다** — 보호자 쪽에서 `%1$d`/`%1$s` 가 든 키를 쓰는 코드를 `grep -n "event_detail_\|String(localized:" ios/KidCare/Guardian/AlertText.swift` 로 먼저 보고 **그 모양 그대로** 적는다. 추측해서 쓰지 않는다.

`EventDoc` 의 초기화 인자 이름도 2단계가 쓰는 모양(`EventDoc(type:at:childUid:detail:)` 인지 `placeName:` 이 필수인지)을 `grep -n "struct EventDoc" -A 20 ios/KidCare/Core/Documents.swift` 로 확인하고 맞춘다.

- [ ] **Step 5: 초록을 확인한다**

Run: Step 2 와 같은 명령 → 그다음 전체.
Expected: PASS. 순증 약 18개(`ChildPermissionsTests` 8 + `ConditionWatcherTests` 9~10).

- [ ] **Step 6: 커밋**

```bash
cd /Users/com/work/KidCare
python3 tools/ios-strings.py --check
git add i18n/ko.json i18n/en.json tools/i18n-untranslated.json ios/KidCare/Localizable.xcstrings \
        ios/KidCare/Child/ChildPermissions.swift ios/KidCare/Child/ConditionWatcher.swift \
        ios/KidCareTests/ChildPermissionsTests.swift ios/KidCareTests/ConditionWatcherTests.swift ios/project.yml
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" \
    commit -m "iOS 아이 3단계 Task 1: 아이폰이 요구하는 권한 넷과, 꺼진 순간 부모에게 한 번 알리는 감시"
```

---

## Task 2: 아이 화면 — 한 번에 하나만, 그리고 못 하는 것을 말한다

**끝나면 `ChildHomeModel` 이 상태 조합마다 문장 하나와 버튼 하나를 정하고, `ChildHomeView` 가 그것을 그린다. 공유가 정상일 때도 강제 종료 안내가 화면에 남아 있다.**

**Files:**
- Create: `ios/KidCare/Child/ChildHomeModel.swift`, `ios/KidCare/Child/ChildHomeView.swift`
- Create: `ios/KidCareTests/ChildHomeModelTests.swift`
- Modify: `ios/KidCare/Core/FamilyRepository.swift`(`isStillMember` 추가)

- [ ] **Step 1: 테스트를 먼저 쓴다 (빨강)**

`ios/KidCareTests/ChildHomeModelTests.swift`. 설계서 §12.1 이 이름까지 정해 둔 테스트다 — "권한 상태 조합 → 어떤 문장 하나를 보여주나. 안드로이드가 '한 번에 하나만, 고쳐야 다음이 의미 있는 순서'로 정한 것(`ChildHomeActivity.kt:49-51`)을 그대로 고정한다."

```swift
import CoreLocation
import Testing
import UIKit
@testable import KidCare

@MainActor
struct ChildHomeModelTests {

    private let 정상 = ChildPermissions.Snapshot(
        authorization: .authorizedAlways, accuracy: .fullAccuracy, backgroundRefresh: .available)

    private func 모델(_ p: ChildPermissions.Snapshot, 멤버: Bool? = true, 저전력: Bool = false) -> ChildHomeModel {
        let m = ChildHomeModel()
        m.apply(permissions: p, stillMember: 멤버, lowPower: 저전력)
        return m
    }

    @Test("다 정상이면 공유 중이라고 말하고 버튼이 없다 (child_sharing_on, ChildHomeActivity.kt:92-97)")
    func 공유중() {
        let m = 모델(정상)
        #expect(m.state == .sharing)
        #expect(m.titleKey == "child_home_title")
        #expect(m.bodyKey == "child_sharing_on")
        #expect(m.action == nil)
    }

    @Test("권한이 빠지면 그 이름과 이유, 그리고 고치는 버튼 (child_permission_missing)")
    func 권한_빠짐() {
        var s = 정상
        s.authorization = .authorizedWhenInUse
        let m = 모델(s)
        #expect(m.state == .permissionMissing(.always))
        #expect(m.bodyKey == "child_permission_missing")
        // `%1$s` 자리에 들어갈 이름
        #expect(m.bodyArgument == String(localized: "ios_child_perm_always_title"))
        #expect(m.reasonKey == "ios_child_perm_always_reason")
        // 두 걸음의 두 번째는 앱이 직접 물을 수 있다(판정 기록 15)
        #expect(m.action == .init(titleKey: "child_go_to_permission", kind: .ask))
    }

    @Test("정확한 위치·백그라운드 새로고침은 설정으로 보낸다 — 물을 API 가 없다")
    func 설정으로() {
        var s = 정상
        s.accuracy = .reducedAccuracy
        #expect(모델(s).action == .init(titleKey: "ios_child_open_settings", kind: .settings))
        s = 정상
        s.backgroundRefresh = .denied
        #expect(모델(s).action == .init(titleKey: "ios_child_open_settings", kind: .settings))
    }

    @Test("가족에서 빠진 것이 권한보다 먼저다 — 권한을 다 켜도 아무 데도 안 간다 (:49-51)")
    func 가족이_먼저() {
        var s = 정상
        s.authorization = .denied
        let m = 모델(s, 멤버: false)
        #expect(m.state == .familyGone)
        #expect(m.titleKey == "child_home_title_gone")
        #expect(m.bodyKey == "child_family_gone")
        #expect(m.action == .init(titleKey: "child_repair", kind: .repair))
    }

    @Test("모르면(nil) 아무 말도 바꾸지 않는다 — 확실하지 않은 것으로 겁주지 않는다 (:146-147)")
    func 모르면_그대로() {
        #expect(모델(정상, 멤버: nil).state == .sharing)
        var s = 정상
        s.authorization = .denied
        #expect(모델(s, 멤버: nil).state == .permissionMissing(.location))
    }

    @Test("저전력 모드는 다른 문장과 **함께** 보인다. 고장이 아니라 주의사항이다 (§8.3)")
    func 저전력_한_줄() {
        #expect(모델(정상, 저전력: false).lowPowerNoticeKey == nil)
        #expect(모델(정상, 저전력: true).lowPowerNoticeKey == "ios_child_low_power_notice")
        var s = 정상
        s.accuracy = .reducedAccuracy
        let m = 모델(s, 저전력: true)
        #expect(m.state == .permissionMissing(.precise))
        #expect(m.lowPowerNoticeKey == "ios_child_low_power_notice", "고장과 함께 보여야 한다")
    }

    @Test("강제 종료 안내는 **늘** 있다 — 정상일 때도. 고장일 때만 두면 정작 그 아이는 못 본다 (§5.3·판정 기록 9)")
    func 강제_종료_안내() {
        #expect(모델(정상).forceQuitNoticeKey == "ios_child_force_quit_notice")
        var s = 정상
        s.authorization = .denied
        #expect(모델(s).forceQuitNoticeKey == "ios_child_force_quit_notice")
        #expect(모델(정상, 멤버: false).forceQuitNoticeKey == "ios_child_force_quit_notice")
    }

    @Test("권한 넷의 순서가 화면에서도 그대로다")
    func 순서() {
        var s = ChildPermissions.Snapshot(
            authorization: .notDetermined, accuracy: .reducedAccuracy, backgroundRefresh: .denied)
        #expect(모델(s).state == .permissionMissing(.location))
        s.authorization = .authorizedWhenInUse
        #expect(모델(s).state == .permissionMissing(.always))
        s.authorization = .authorizedAlways
        #expect(모델(s).state == .permissionMissing(.precise))
        s.accuracy = .fullAccuracy
        #expect(모델(s).state == .permissionMissing(.backgroundRefresh))
        s.backgroundRefresh = .available
        #expect(모델(s).state == .sharing)
    }
}
```

- [ ] **Step 2: `FamilyRepository.isStillMember` 를 더한다**

정본 `core/FamilyRepository.kt:422-433` 을 그대로 옮긴다. **세 갈래가 핵심**이고, 그중 캐시 갈래를 빠뜨리면 오프라인일 때 화면이 "가족에서 빠졌다"고 거짓말한다.

```swift
/// 서버가 아직 이 기기를 이 가족의 멤버로 아는가. 정본 `core/FamilyRepository.kt:422-433`.
///
/// **모르면 `nil` 이다.** 캐시에서 온 "없음"은 아직 서버에 못 물어본 것이고, 그것을 `false` 로
/// 뭉개면 오프라인인 아이 화면이 "가족에서 빠졌어요"라고 거짓말한다. `PERMISSION_DENIED` 만
/// `false` 인 이유: 규칙이 `read: memberOf(familyId)`(`firestore.rules:99`)라 멤버가 아니면
/// 거부가 곧 답이다.
///
/// 기존 `fetchMember` 를 안 쓰는 이유는 그쪽이 "없다"와 "못 읽었다"를 같은 값으로 돌려주기
/// 때문이다 — 이 화면이 필요한 구분이 정확히 그것이다.
static func isStillMember(familyId: String, uid: String) async -> Bool? {
    do {
        let snap = try await db.collection("families").document(familyId)
            .collection("members").document(uid).getDocument()
        if snap.metadata.isFromCache && !snap.exists { return nil }
        return snap.exists
    } catch let error as NSError where error.domain == FirestoreErrorDomain
        && error.code == FirestoreErrorCode.permissionDenied.rawValue {
        return false
    } catch {
        // 화면은 아무 말도 하지 않는다.
        logger.warning("가족 멤버 확인 실패: \(String(describing: error), privacy: .public)")
        return nil
    }
}
```

`logger` 이름과 `db` 접근자, `FirestoreErrorCode` 를 쓰는 기존 모양을 `grep -n "FirestoreErrorCode\|private static let logger\|private static var db" ios/KidCare/Core/*.swift` 로 확인하고 그대로 맞춘다. `CancellationError` 를 일반 `catch` 로 삼키지 않는지도 이 자리에서 본다 — 삼키면 안 되므로, 이 저장소가 쓰는 방식(`catch is CancellationError { throw ... }` 또는 `try Task.checkCancellation()`)에 맞춘다.

- [ ] **Step 3: `ChildHomeModel` 을 만든다**

```swift
import CoreLocation
import Foundation
import Observation
import UIKit

/// 아이 화면이 **무엇을 말할지** 정한다. 그림은 `ChildHomeView` 가 그린다.
/// 정본 `child/ChildHomeActivity.kt:70-82`(`onResume` 의 세 갈래)와 `:49-51`(순서의 근거).
///
/// **한 번에 하나만 말한다.** 순서는 "이걸 고쳐야 다음이 의미가 있는가"다 — 가족에서 빠졌으면
/// 권한을 다 켜도 아무 데도 안 가고, 위치 권한이 없으면 '항상 허용'을 물을 수조차 없다.
///
/// 안드로이드의 Play 서비스 갈래(`:125-136`)는 **안 옮긴다.** 아이폰에 대응하는 재료가 없고,
/// 그 자리의 "조용한 고장"은 아이폰에서는 정확한 위치 끄기다(설계서 §8.2) — 이미 권한 넷 안에 있다.
@MainActor
@Observable
final class ChildHomeModel {

    enum State: Equatable {
        case sharing
        case permissionMissing(ChildPermissions.Item)
        case familyGone
    }

    struct Action: Equatable {
        enum Kind { case ask, settings, repair }
        let titleKey: String.LocalizationValue
        let kind: Kind
    }

    private(set) var state: State = .sharing
    /// 저전력 모드 한 줄. **다른 문장과 함께** 보인다 — 고장이 아니라 주의사항이라서다(§8.3).
    private(set) var lowPowerNoticeKey: String.LocalizationValue?

    /// 강제 종료 안내는 **늘** 있다. 고장일 때만 보여주면 정작 강제 종료한 아이는 그 화면을
    /// 못 본다 — 앱이 없으니까(3단계 판정 기록 9).
    let forceQuitNoticeKey: String.LocalizationValue = "ios_child_force_quit_notice"

    var titleKey: String.LocalizationValue {
        state == .familyGone ? "child_home_title_gone" : "child_home_title"
    }

    var bodyKey: String.LocalizationValue {
        switch state {
        case .sharing: "child_sharing_on"
        case .permissionMissing: "child_permission_missing"
        case .familyGone: "child_family_gone"
        }
    }

    /// `child_permission_missing` 의 `%1$s` 자리(`ko.json:35`).
    var bodyArgument: String? {
        if case .permissionMissing(let item) = state { return item.이름 }
        return nil
    }

    var reasonKey: String.LocalizationValue? {
        if case .permissionMissing(let item) = state { return item.reasonKey }
        return nil
    }

    private(set) var action: Action?

    /// `stillMember` 가 `nil` 이면 **아무 말도 바꾸지 않는다**(`:146-147`).
    func apply(permissions: ChildPermissions.Snapshot, stillMember: Bool?, lowPower: Bool) {
        lowPowerNoticeKey = lowPower ? "ios_child_low_power_notice" : nil

        if stillMember == false {
            state = .familyGone
            action = Action(titleKey: "child_repair", kind: .repair)
            return
        }
        guard let missing = ChildPermissions.firstMissing(permissions) else {
            state = .sharing
            action = nil
            return
        }
        state = .permissionMissing(missing)
        action = switch ChildPermissions.fix(for: missing, in: permissions) {
        case .ask: Action(titleKey: "child_go_to_permission", kind: .ask)
        case .settings: Action(titleKey: "ios_child_open_settings", kind: .settings)
        }
    }
}
```

- [ ] **Step 4: `ChildHomeView` 를 만든다**

레이아웃은 `app/src/main/res/layout/activity_child_home.xml` 을 먼저 열어 그 배치(마스코트 · 제목 · 본문 · 버튼 하나 · 언어 버튼)를 확인한 뒤 맞춘다. `RoleSelectView` 가 이미 쓰는 `KidCarePalette`·`KidCareFilledButtonStyle` 을 그대로 쓴다. 뷰는 **모델이 정한 것만 그린다** — 여기서 권한을 다시 판단하지 않는다.

지켜야 할 것 넷:
1. 버튼은 **하나**다. `action == nil` 이면 아예 안 그린다.
2. `.ask` 는 `ChildSession.shared.requestAuthorization()`(= `LocationCollector.requestAuthorization()`, 판정 기록 15), `.settings` 는 `UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)`, `.repair` 는 `RoleStore.shared.clear()` + `ChildSession.shared.stop()`.
3. 저전력 줄과 강제 종료 줄은 본문 **아래**에 작은 글씨로 둘 다 자리를 잡는다. 강제 종료 줄은 늘 있다.
4. `scenePhase` 가 `.active` 로 돌아올 때마다 다시 읽는다 — 안드로이드가 `onResume` 에서 매번 다시 판단하는 자리(`:70-82`)다. 아이가 설정 앱에 다녀오면 그때 값이 바뀌어 있다.

- [ ] **Step 5: 초록을 확인한다**

Run: `-only-testing:KidCareTests/ChildHomeModelTests` → 그다음 전체.
Expected: PASS. 순증 약 8개.

- [ ] **Step 6: 커밋**

```bash
git add ios/KidCare/Child/ChildHomeModel.swift ios/KidCare/Child/ChildHomeView.swift \
        ios/KidCare/Core/FamilyRepository.swift ios/KidCareTests/ChildHomeModelTests.swift ios/project.yml
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" \
    commit -m "iOS 아이 3단계 Task 2: 아이 화면은 한 번에 하나만 말하고, 앱을 닫으면 멈춘다는 것을 숨기지 않는다"
```

---

## Task 3: 진짜 시작 경로 — 앱이 뜨면 역할이 정한다

**끝나면 `-childSim` 없이, 아이로 페어링한 아이폰이 앱을 여는 것만으로 수집기·시계·장소 감시·업로더·조건 감시가 붙는다. `ticker:` 를 빠뜨리면 컴파일이 안 된다. 역할 선택 화면의 아이 버튼이 실제로 아이 페어링으로 간다.**

**Files:**
- Create: `ios/KidCare/Child/ChildSession.swift`, `ios/KidCare/Child/ChildRootView.swift`, `ios/KidCareTests/ChildSessionTests.swift`
- Modify: `ios/KidCare/KidCareApp.swift`, `ios/KidCare/RouterView.swift`, `ios/KidCare/Onboarding/RoleSelectView.swift`, `ios/KidCare/Child/TrackingCoordinator.swift`, `ios/KidCare/Child/PlaceWatcher.swift`, `ios/KidCareTests/TrackingCoordinatorTests.swift`, `ios/KidCareTests/PlaceWatcherTests.swift`, `i18n/ko.json`, `i18n/en.json`, `tools/i18n-untranslated.json`
- Delete: `ios/KidCare/Child/ChildSimHarness.swift`, `ios/KidCare/Child/ChildSimView.swift`, `ios/KidCareTests/ChildSimHarnessTests.swift`

- [ ] **Step 1: 막이를 걷는다**

`RoleSelectView.swift`:
- `아이는_안된다고_알린다` 상태와 `.alert("ios_child_unsupported_title", …)` 블록(`:89-97`)을 지운다.
- 아이 버튼(`:62-65`)의 액션을 `아이로_간다 = true` 로 바꾸고, 보호자 합류와 같은 모양의 `.navigationDestination(isPresented: $아이로_간다) { JoinFamilyView(expectedRole: .child, onJoined: onChildReady) }` 를 더한다.
- 머리 주석(`:5-6`)을 고친다. 지금은 "아이 버튼을 지우지 않고 안내로 두는 이유"를 적고 있는데 그 안내가 사라진다.

`JoinFamilyView` 는 **한 줄도 안 고친다** — `expectedRole` 을 이미 받고, `RoleStore.shared.role = result.role`(:137)로 child 를 그대로 저장한다. `findChildUid` 를 아이 자신에게도 부르는데, 아이 폰은 그 값을 안 쓴다(보호자 선택기용이다) — 해롭지 않으므로 그대로 둔다.

`i18n/ko.json`·`en.json` 에서 `ios_child_unsupported_title`/`_body`/`_confirm` 셋을 지우고 `python3 tools/ios-strings.py --write-gaps` 를 돈다(공통 절차 A).

```bash
grep -rn "ios_child_unsupported" ios/ i18n/ tools/   # 비어 있어야 한다
```

- [ ] **Step 2: `ticker:` 를 필수로 만든다 (컴파일이 막는다)**

`TrackingCoordinator.swift` 의 `ticker: Ticking? = nil` 에서 `= nil` 을 지운다. 주석을 고쳐 **왜 기본값이 없는지**를 적는다:

```swift
    /// **기본값이 없다.** 1단계 통합 검토 I1 이 "이 인자를 안 넘기면 좌표가 끊긴 폰이 `.moving`
    /// 에 갇혀 하루 종일 조용해진다"였고, 그 경고를 주석으로만 두면 잊힌다 — 실제로 2단계까지
    /// 진짜 파이프라인이 `#if DEBUG` 화면 하나뿐이었다. 기본값을 지우면 새 호출부가 `ticker:`
    /// 를 **글자로** 적어야 하고, 빠뜨리면 컴파일이 안 된다. 테스트는 `ticker: nil` 이나
    /// 가짜 시계를 **명시한다**(벽시계를 기다리는 테스트를 만들지 않기 위해서다).
    ticker: Ticking?
```

그다음 컴파일러가 가리키는 호출부를 전부 고친다.

```bash
cd /Users/com/work/KidCare
grep -rn "TrackingCoordinator(" ios/KidCare ios/KidCareTests
# 테스트에서 인자를 생략하고 있던 줄에 `ticker: nil` 을 명시한다. 값을 바꾸지 않는다.
```

- [ ] **Step 3: `ChildSession` 을 만든다**

`ios/KidCare/Child/ChildSession.swift`. **2단계까지 `ChildSimView.start()` 안에 있던 배선을 그대로 옮긴다** — 순서를 바꾸지 않는다. 옮기면서 바뀌는 것은 소유자(뷰 → 세션), 배터리 주입(`#if DEBUG` 한 인자), 그리고 `onCondition` 을 잇는 것 셋뿐이다.

```swift
import FirebaseFirestore
import Foundation
import os
import SwiftUI
import UIKit

/// 아이 역할의 파이프라인을 **앱이 사는 동안** 소유한다. 앱당 하나다.
///
/// ## 왜 뷰가 아닌가 (2단계 통합 검토 I1, 1단계 M6)
///
/// 2단계까지 수집기를 만드는 유일한 코드가 `ChildSimView` 의 `.task` 안이었다 — `#if DEBUG`
/// 안이라 **출시 빌드에는 그 자리가 아예 없었다.** 지역 경계를 넘어 iOS 가 앱을 되살려도 배달할
/// 곳이 없었다는 뜻이다. 그런데 화면으로 옮기는 것만으로는 부족하다: iOS 가 앱을 **백그라운드에**
/// 되살릴 때(지역 전환·중요 위치 변경) `WindowGroup` 의 body 가 평가된다는 보장이 없다 —
/// 그릴 화면이 없으니 그릴 이유도 없다. 그래서 시작은 `KidCareApp.init()` 이 부르고,
/// `ChildRootView` 는 이 세션을 **읽기만** 한다.
///
/// ## 되살아나는 길과, 되살아나지 않는 길
///
/// 중요 위치 변경(`LocationCollector.start()`)과 지역 감시(`PlaceWatcher`)가 앱을 다시 띄운다.
/// **강제 종료(앱 전환기에서 위로 밀기) 뒤에는 둘 다 오지 않는다** — 아래 `logNoRevivalAfterForceQuit`
/// 가 그것을 로그에 적고, 아이 화면이 `ios_child_force_quit_notice` 로 아이에게 말한다.
@MainActor
@Observable
final class ChildSession {

    static let shared = ChildSession()

    private(set) var running = false
    private(set) var childUid = ""
    let home = ChildHomeModel()

    private var collector: LocationCollector?
    private var coordinator: TrackingCoordinator?
    private var placeWatcher: PlaceWatcher?
    private var conditionWatcher: ConditionWatcher?
    private var placesListener: ListenerRegistration?
    private var device: DeviceState?
    private let logger = Logger(subsystem: "com.kidcare.family", category: "ChildSession")

    /// 테스트 프로세스에서는 절대 안 뜬다. `RouterView.swift:37` 과 **같은 기준**이다 —
    /// 테스트가 아이 파이프라인을 띄우면 에뮬레이터에 쓰레기 문서가 쌓이고, 아직 구성되지 않은
    /// `FirebaseApp` 을 건드려 프로세스가 통째로 죽는다.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// `KidCareApp.init()` 이 부른다. **저장된 역할이 child 일 때만** 뜬다.
    func startIfChild(store: RoleStore = .shared) {
        guard !Self.isRunningTests else { return }
        guard store.role == .child, let familyId = store.familyId else { return }
        start(familyId: familyId)
    }

    func start(familyId: String, battery: Int? = ChildSession.injectedBattery) {
        guard !running else { return }
        running = true
        logNoRevivalAfterForceQuit()
        Task { await build(familyId: familyId, battery: battery) }
    }

    /// **강제 종료 뒤에는 되살아나지 않는다**(설계서 §5.3·§15-2). 코드 주석과 아이 화면 문구만으로는
    /// 현장에서 이 사실이 안 보인다 — 로그가 그 셋째 자리다(3단계 판정 기록 9).
    private func logNoRevivalAfterForceQuit() {
        logger.notice("""
            강제 종료(앱 전환기에서 위로 밀기) 뒤에는 iOS 가 이 앱을 되살리지 않는다 — \
            중요 위치 변경도, 지역 감시도 오지 않는다. 아이가 앱을 다시 열거나 폰을 껐다 켤 때까지 \
            기록이 통째로 없다(설계서 §5.3·§15-2). 되살리기가 도는 것은 메모리 압박으로 OS 가 \
            종료했을 때와 재부팅 뒤뿐이다.
            """)
    }

    private func build(familyId: String, battery: Int?) async { /* 아래 배선 그대로 */ }

    func stop() { … }

    func requestAuthorization() { collector?.requestAuthorization() }
}
```

`build(familyId:battery:)` 의 배선은 **`ChildSimView.start()`(`:39-123`)의 순서를 글자 그대로 옮긴다.** 달라지는 곳만 여기 적는다.

1. `uid = try await AuthGateway.uid()` — 실패하면 `running = false` 로 되돌리고 로그. 화면은 아무 말도 바꾸지 않는다(모르는 것으로 겁주지 않는다).
2. `DeviceState` — `battery` 가 있으면 주입, 없으면 기본. `self.device` 에 **보관한다**(`ConditionWatcher` 가 같은 값을 읽어야 한다, `ConditionWatcher.kt:76-77`).
3. **`ticker:` 를 넘긴다.** `let ticker = TrackingTicker()` → `TrackingCoordinator(familyId:uploader:source:ticker:)`.
4. `coordinator.restore()`.
5. **`onCondition` 을 잇는다 — 이 단계가 새로 더하는 유일한 훅이다.**

```swift
        let conditionWatcher = ConditionWatcher()
        self.conditionWatcher = conditionWatcher
        let childUid = uid
        // 1번 단계. 좌표가 들어올 때(`handle`)와 60초 시계(`tick`) **둘 다**에서 불린다 —
        // 좌표가 안 오는 것이 바로 증상이므로 좌표에만 묶으면 아무 말도 못 한다(판정 기록 8).
        // `TrackingCoordinator` 가 1분에 한 번으로 이미 솎는다(`TrackingService.kt:399-401`).
        coordinator.onCondition = { [weak self] now in
            guard let self, let collector = self.collector else { return }
            let permissions = ChildPermissions.snapshot(manager: collector.manager)
            let battery = self.device?.snapshot().batteryPercent ?? -1
            Task { @MainActor in
                do {
                    try await conditionWatcher.check(
                        familyId: familyId, childUid: childUid,
                        batteryPercent: battery, permissions: permissions, now: now)
                } catch is CancellationError {
                    // 취소는 실패가 아니다(1단계 `uploadNow` 와 같은 규율).
                } catch {
                    // 이벤트 하나를 못 쓴 것 때문에 위치 수집이 멈추면 안 된다(`ConditionWatcher.kt:149-150`).
                    self.logger.warning("상태 이벤트 쓰기 실패: \(String(describing: error), privacy: .public)")
                }
                self.refreshHome()
            }
        }
```

`collector.manager` 가 `private` 이면 **매니저를 밖으로 열지 말고** `LocationCollector` 에 `var permissions: ChildPermissions.Snapshot { ChildPermissions.snapshot(manager: manager) }` 를 더한다 — 매니저는 앱이 사는 동안 하나여야 한다는 규율(설계서 §5.2)을 깨지 않는 쪽이다.

6. `collector.onAuthorizationChange` 를 잇는다 — 설계서 §8.1 의 "권한 상태를 한 번 받고 끝내지 않고 계속 본다". 바뀔 때마다 `refreshHome()` 과 `conditionWatcher` 를 다시 돌린다(같은 `check` 를 지금 시각으로 한 번 더 부른다).
7. 장소 배선(`placeWatcher`, `updateKnownPlace`, `onPlaceFix`, `observePlaces`)은 `ChildSimView.swift:76-114` **그대로**다. `collector.onFix` 는 `ChildSimView` 가 화면 갱신을 위해 덮어쓰던 것인데, 세션에서는 `TrackingCoordinator.init` 이 이미 건 것을 **그대로 두고** 화면 갱신은 `ChildRootView` 의 `.task`/`scenePhase` 가 주기적으로 한다 — 좌표마다 뷰를 다시 그릴 이유가 없다.
8. `collector.requestAuthorization()` → `collector.start()`.
9. `refreshHome()` — `ChildPermissions.snapshot` + `ProcessInfo.processInfo.isLowPowerModeEnabled` + `FamilyRepository.isStillMember` 를 모아 `home.apply(...)`. 멤버 확인은 **읽기가 하나 드는 일**이라 화면이 앞으로 나올 때(`scenePhase == .active`)와 세션이 뜰 때만 한다(`ChildHomeActivity.checkStillInFamily` 가 `onResume` 에서만 도는 것과 같다).
10. **저전력 모드 변화**는 `NSProcessInfoPowerStateDidChange` 를 구독해 `refreshHome()` 만 부른다(설계서 §8.3 — 이벤트를 안 만든다). 구독은 `stop()` 에서 뗀다.

`stop()` 은 `placesListener?.remove()`, `collector?.stop()`, 티커 정지, 알림 구독 해제, `running = false` 를 한다. 부르는 곳은 '다시 연결' 버튼 하나다.

`ChildSession.injectedBattery` 는 **`#if DEBUG` 안의 계산 프로퍼티 하나**다(판정 기록 3).

```swift
#if DEBUG
extension ChildSession {
    /// 시뮬레이터는 배터리를 안 준다(`DeviceState.swift:62-65`) — 값을 안 넣으면 상태 문서가 늘
    /// `battery: -1` 이고 `ConditionWatcher` 의 15% 갈래를 **시뮬레이터에서 확인할 길이 없다**
    /// (`ConditionWatcher.kt:98` 이 1..100 밖을 그냥 돌려보낸다). 파이프라인을 따로 만들지 않고
    /// 값 하나를 주입할 뿐이라 "조립하는 코드가 두 벌"이 되지 않는다(3단계 판정 기록 3).
    /// `-childBattery <0~100>`.
    static var injectedBattery: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-childBattery"), i + 1 < args.count,
              let value = Int(args[i + 1]), (0...100).contains(value) else { return nil }
        return value
    }
}
#else
extension ChildSession {
    static var injectedBattery: Int? { nil }
}
#endif
```

- [ ] **Step 4: `ChildRootView` 와 `RouterView`·`KidCareApp` 을 잇는다**

`ChildRootView.swift` — 탭이 없다. `ChildSession.shared` 를 읽어 `ChildHomeView(model: session.home)` 하나를 그리고, `scenePhase` 가 `.active` 가 될 때 `session.refreshHome()` 을 부른다.

`RouterView.swift`:
- `#if DEBUG` `-childSim` 갈래(`:48-55`)를 **통째로 지운다.** 1단계 판정 기록 9 가 "3단계가 `ChildRootView` 를 만들면 이 세 줄을 지운다"고 예고한 그 자리다.
- `init` 의 `showMain` 판단(`:41`)에 child 갈래를 더한다. 지금은 `store.role == .guardian && store.familyId != nil` 이라 아이는 영영 역할 선택으로 간다.
- 본 화면 분기에 child 를 더한다:

```swift
            } else if store.role == .child, store.familyId != nil {
                // 아이는 **아이 화면만** 본다 — 보호자 탭이 하나도 안 보인다(설계서 §2-2).
                // 수집 파이프라인은 여기서 만들지 않는다. `KidCareApp.init()` 이 이미 만들었다 —
                // 백그라운드로 되살아난 실행에는 이 body 가 안 돌 수 있기 때문이다(판정 기록 1).
                ChildRootView()
            } else if showMain, let familyId = store.familyId {
```

`isRunningTests` 갈래는 **그대로 위에 둔다**(테스트 프로세스는 아무 화면도 안 그린다).

`KidCareApp.swift` 의 `init()` 끝에 한 줄:

```swift
        // 저장된 역할이 child 면 **화면과 무관하게** 수집을 시작한다. 지역 전환이나 중요 위치
        // 변경으로 앱이 백그라운드에서 되살아나면 `WindowGroup` 의 body 가 안 돌 수 있다 —
        // 그때도 이 줄은 돈다(2단계 통합 검토 I1, 1단계 M6).
        ChildSession.shared.startIfChild()
```

`ChildSession.shared` 가 `@MainActor` 이고 `KidCareApp.init()` 도 `@MainActor`(SwiftUI `App`)이므로 건너뛸 것이 없다. 컴파일러가 반대하면 `MainActor.assumeIsolated` 를 **쓰지 말고** 왜 반대하는지 확인한다.

- [ ] **Step 5: 2단계 M3 를 닫는다 — 목록이 바뀐 때만 지역을 다시 건다**

`PlaceWatcher.apply(placeDocs:)` 에 한 겹을 더한다(판정 기록 17).

```swift
    /// OS 등록은 **고른 결과가 실제로 달라졌을 때만** 다시 건다. `observePlaces` 가
    /// `includeMetadataChanges: true`(`PlaceRepository.swift:42`)라 앱이 뜨자마자 캐시본·서버본으로
    /// 두 번 도는데, 그때마다 스무 개를 지웠다 다시 걸면 iOS 의 초기 상태 판정이 매번 처음부터
    /// 시작한다(2단계 통합 검토 M3). 비교는 OS 에 실제로 가는 넷 — id·lat·lng·반경 — 으로만 한다.
    /// 이름이나 알림 스위치가 바뀌어도 원은 그대로다.
    ///
    /// **`places` 는 언제나 갱신한다.** 건너뛰는 것은 OS 등록뿐이다 — 이 구분을 놓치면 부모가
    /// 지운 장소의 판정이 살아남는다.
```

`PlaceWatcherTests` 에 두 개를 더한다: `같은_목록이면_다시_안_건다`(두 번 `apply` 해도 `replaceMonitoredRegions` 호출이 한 번), `반경이_바뀌면_다시_건다`.

- [ ] **Step 6: `-childSim` 을 지운다**

```bash
cd /Users/com/work/KidCare
git rm ios/KidCare/Child/ChildSimHarness.swift ios/KidCare/Child/ChildSimView.swift \
       ios/KidCareTests/ChildSimHarnessTests.swift
grep -rn "ChildSim" ios/   # 비어 있어야 한다
cd ios && xcodegen generate
```

- [ ] **Step 7: 세션 테스트 (빨강 → 초록)**

`ios/KidCareTests/ChildSessionTests.swift`. **세션은 실제로 Firestore 와 CoreLocation 을 건드리므로 통째로 띄우지 않는다** — 띄우면 에뮬레이터에 쓰레기가 쌓인다(`ChildSimHarnessTests.테스트에서는_꺼져있다` 가 지키던 그 규율이다). 대신 셋만 본다.

```swift
@MainActor
struct ChildSessionTests {

    @Test("테스트 프로세스에서는 절대 안 뜬다 — 뜨면 에뮬레이터에 쓰레기 문서가 쌓인다")
    func 테스트에서는_꺼져있다() {
        let defaults = UserDefaults(suiteName: "세션-\(UUID().uuidString)")!
        let store = RoleStore(defaults: defaults)
        store.role = .child
        store.familyId = "FAM1"
        ChildSession.shared.startIfChild(store: store)
        #expect(ChildSession.shared.running == false)
    }

    @Test("역할이 child 가 아니거나 가족이 없으면 아무것도 안 만든다")
    func 역할이_아니면() { … }

    /// **이 테스트가 1단계 I1 의 재발을 막는 자리다.** 컴파일러가 `ticker:` 를 강제하지만
    /// "넘기되 `nil` 을 넘긴다"는 여전히 가능하다 — 그러면 좌표가 끊긴 폰이 `.moving` 에 갇힌다.
    @Test("세션이 만드는 코디네이터는 좌표 없이도 모드를 내린다 (시계가 달려 있다)")
    func 세션은_시계를_단다() {
        // 세션이 파이프라인을 만드는 함수를 그대로 부르되 진짜 매니저 대신 가짜 `LocationSource`
        // 와 가짜 시계를 넣는다(`TrackingCoordinatorTests.가짜_시계` 재사용). `.moving` 까지
        // 올린 뒤 좌표를 끊고 tick 만 60초·5분 흘리면 `.slowProbe` → `.still` 로 내려가야 한다.
        …
    }
}
```

세 번째 테스트가 가능하려면 `ChildSession` 의 조립을 **주입 가능한 한 함수**로 갈라 둔다 — 예: `static func makeCoordinator(familyId:uploader:source:ticker:) -> TrackingCoordinator` 하나. 그 함수 안에 `ticker:` 를 넘기는 줄이 있고, 테스트가 그 함수를 부른다. **`ChildSession.build` 전체를 테스트하려 들지 않는다**(Firestore 가 붙어 있다).

- [ ] **Step 8: 초록을 확인한다**

```bash
cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: PASS. `ChildSimHarnessTests` 4개가 빠지고 `ChildSessionTests` 3개와 `PlaceWatcherTests` 2개가 는다.

- [ ] **Step 9: 커밋**

```bash
cd /Users/com/work/KidCare
python3 tools/ios-strings.py --check
git add -A ios/KidCare ios/KidCareTests i18n tools/i18n-untranslated.json ios/project.yml
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" \
    commit -m "iOS 아이 3단계 Task 3: 앱이 뜨면 역할이 수집을 시작한다 — 시뮬레이터 전용 문을 지우고 시계를 필수로"
```

---

## Task 4: 단계 마무리 — 전수 대조, 일부러 깨 보기, 시뮬레이터 통과

**끝나면 설계서 §8 의 네 권한이 코드와 한 줄씩 맞고, 배선을 일부러 끊으면 테스트가 실제로 빨개지며, 시뮬레이터에서 아이로 페어링해 권한을 하나씩 꺼 보면 화면 문장이 바뀌고 부모 알림 탭에 "애기폰에서 권한이 꺼졌어요"가 뜬다.**

**Files:**
- Create: `ios/dev/child-permissions.md`(시뮬레이터 절차 메모)
- Modify: 이 단계에서 찾은 결함이 있으면 그 파일들

- [ ] **Step 1: 상수와 문구를 한 줄씩 대조한다**

```bash
cd /Users/com/work/KidCare
# 설계서 §4.10 — ConditionWatcher 문턱 둘
grep -n "LOW_PERCENT\|REARM_PERCENT" app/src/main/java/com/kidcare/family/child/ConditionWatcher.kt
grep -n "lowPercent\|rearmPercent" ios/KidCare/Child/ConditionWatcher.swift
# 설계서 §4.9 — 조건 검사 주기 60초. iOS 는 TrackingTicker 가 그 값이다
grep -n "CONDITION_CHECK_INTERVAL_MILLIS" app/src/main/java/com/kidcare/family/child/TrackingService.kt
grep -n "periodMillis" ios/KidCare/Child/TrackingTicker.swift
# 감시 목록 — 안드로이드 넷 중 둘은 아이폰에 대응이 없다(§8.6)
sed -n '179,184p' app/src/main/java/com/kidcare/family/child/ConditionWatcher.kt
grep -n "case location\|case always\|case precise\|case backgroundRefresh" ios/KidCare/Child/ChildPermissions.swift
# 이벤트 타입 — 새로 만든 것이 없어야 한다
grep -n "EventType\." ios/KidCare/Child/ConditionWatcher.swift
grep -n "const val" app/src/main/java/com/kidcare/family/core/model/Documents.kt | sed -n '/EventType/,$p'
# 문구 — 부모 쪽 키를 그대로 쓰는지
grep -rn "event_detail_permission\|event_detail_battery\|alert_permission_off" ios/KidCare i18n/ko.json
```

표를 만들어 **값과 인용 줄이 둘 다 맞는지** 눈으로 본다. 하나라도 어긋나면 **안드로이드가 맞다.**

- [ ] **Step 2: 배선을 일부러 끊어 본다 (여섯)**

1·2단계에서 이 확인이 가장 중요했다. **여섯을 차례로 깨고, 각각이 빨개지는 것을 보고, 되돌린다.**

| # | 깨는 것 | 빨개져야 하는 테스트 |
|---|---|---|
| 1 | `ChildSession` 조립에서 `ticker:` 자리에 `nil` 을 넣는다 | `ChildSessionTests.세션은_시계를_단다` |
| 2 | `ConditionWatcher.lowPercent` 를 `10` 으로 | `ConditionWatcherTests.배터리_한_번` |
| 3 | `ConditionWatcher.rearmPercent` 를 `15` 로(문턱을 붙인다) | `ConditionWatcherTests.배터리_풀림` |
| 4 | `ChildPermissions.Item` 에서 `.precise` 를 뺀다 | `ChildPermissionsTests.정확한_위치`·`순서`, `ChildHomeModelTests.순서` |
| 5 | `ChildHomeModel.apply` 에서 `stillMember == false` 갈래를 권한 판정 **뒤로** 옮긴다 | `ChildHomeModelTests.가족이_먼저` |
| 6 | `ChildHomeModel.forceQuitNoticeKey` 를 고장일 때만 주게 바꾼다 | `ChildHomeModelTests.강제_종료_안내` |

```bash
cd ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:KidCareTests/ChildPermissionsTests -only-testing:KidCareTests/ConditionWatcherTests \
  -only-testing:KidCareTests/ChildHomeModelTests -only-testing:KidCareTests/ChildSessionTests
cd /Users/com/work/KidCare && git checkout ios/KidCare/Child   # 되돌리기
git status --short   # 비어 있어야 한다
```

**여섯 중 하나라도 초록이면 그 검사가 무의미하다는 뜻이다 — 검사를 고치고 다시 한다.**

- [ ] **Step 3: 출시 빌드에 시뮬레이터 문이 없는지 본다**

1단계가 같은 확인을 했다(`childSim` 문자열 0개).

```bash
cd ios
xcodebuild build -project KidCare.xcodeproj -scheme KidCare -configuration Release \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -3
BIN=$(find ~/Library/Developer/Xcode/DerivedData -name KidCare -type f -path "*Release-iphonesimulator*" | head -1)
strings "$BIN" | grep -c "childBattery"      # 0 이어야 한다
strings "$BIN" | grep -c "childSim"          # 0 이어야 한다
```

- [ ] **Step 4: 전체 테스트**

```bash
cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: PASS. 개수는 선행 조건의 M(708)에서 `ChildSimHarnessTests` 4개를 빼고 Task 1~3 의 순증(약 31)을 더한 값이다.

- [ ] **Step 5: 시뮬레이터에서 아이로 페어링하고 권한을 하나씩 꺼 본다**

설계서 §14 3단계의 완료 기준이다: "에뮬레이터를 상대로 아이로 페어링해 아이 화면까지 가고, 권한을 하나씩 꺼 보면 화면 문장이 바뀌고 `permission_off` 이벤트가 부모 쪽에 뜬다."

1. 에뮬레이터가 떠 있는지 본다(`curl -s http://127.0.0.1:8080` 로 8080 확인). **데이터를 지우지 않는다.**
2. `KidCareApp.swift` 를 잠깐 `configureForEmulator(projectId: "kidcare-emulator")` 로 바꾼다. **Step 7 에서 반드시 되돌린다.**
3. 보호자 시뮬레이터(`iPhone 17`)에서 가족을 만들고 **아이용 초대 코드**를 뽑는다. 아이 시뮬레이터(`iPhone 17 Pro`)에서 앱을 **지우지 않고** 덮어 설치한 뒤 띄워 역할 선택 → **아이** → 그 코드로 합류한다. 배터리 갈래를 보려면 `-childBattery 12` 로 띄운다.
4. **아이 화면까지 갔는지** 본다. 보호자 탭이 하나도 안 보여야 한다.
5. 권한을 하나씩 꺼 본다. 시뮬레이터의 **설정 앱 ▸ 개인정보 보호 및 보안 ▸ 위치 서비스 ▸ KidCare** 와 **설정 ▸ 일반 ▸ 백그라운드 앱 새로고침**에서 바꾼다. 절차와 항목 이름을 `ios/dev/child-permissions.md` 에 적어 둔다(다음 사람이 찾느라 시간을 안 쓰게).

   | 끄는 것 | 아이 화면이 말해야 하는 것 | 버튼 | `events/` |
   |---|---|---|---|
   | (전부 켬) | `child_sharing_on` + 강제 종료 줄 | 없음 | — |
   | 위치를 '앱을 사용하는 동안'으로 | `ios_child_perm_always_title` 이름이 든 `child_permission_missing` | `child_go_to_permission` | `permission_off` 하나 |
   | 정확한 위치 끄기 | `ios_child_perm_precise_title` | `ios_child_open_settings` | 하나 더 |
   | 백그라운드 앱 새로고침 끄기 | `ios_child_perm_refresh_title` | `ios_child_open_settings` | 하나 더 |
   | 위치 '안 함' | `perm_location_title` | `ios_child_open_settings` | 하나 더 |
   | 다시 전부 켜기 | `child_sharing_on` | 없음 | **새 문서가 안 생긴다**(판정 기록 7) |
   | 저전력 모드 켜기(설정 ▸ 배터리) | 위 문장 + `ios_child_low_power_notice` 한 줄 | 그대로 | **안 생긴다**(§8.3) |

   ```bash
   EMU="http://127.0.0.1:8080/v1/projects/kidcare-emulator/databases/(default)/documents"
   curl -s -H "Authorization: Bearer owner" "$EMU/families/<가족ID>/events" | python3 -m json.tool | head -60
   ```
   `type` 이 `permission_off`, `read` 가 `false`, `at` 이 밀리초 정수, `detail` 이 그 권한 이름인지 본다. 필드가 **일곱뿐**인지도 본다(2단계 확인과 같은 목록).

6. **배터리 경고**: `-childBattery 12` 로 띄우면 `low_battery` 문서 하나가 생기고, 다시 띄워도 **또 안 생긴다**(프로세스 밖 기억). `-childBattery 25` 로 한 번 띄웠다가 `12` 로 다시 띄우면 그때는 또 생긴다.
7. **보호자 앱의 알림 탭**에 "애기폰에서 권한이 꺼졌어요"와 "애기폰 배터리가 얼마 안 남았어요"가 뜨는지 본다. **보호자 쪽은 한 줄도 안 바뀌었다**(`git diff --stat d26e28f..HEAD -- ios/KidCare/Guardian` 가 비어야 한다).
8. **되살리기**: 아이 시뮬레이터에서 앱을 **홈으로 내린 뒤** `xcrun simctl location booted set …` 으로 좌표를 크게 옮겨 지역 경계를 넘긴다. 앱이 백그라운드에서 사건을 쓰는지 본다 — **이것이 2단계 I1 이 막혀 있던 자리다.** (시뮬레이터가 진짜 앱 종료 후 되살리기를 재현하지 못하는 것은 4단계 몫이다. 여기서 보는 것은 "배선이 화면 밖에 있다"까지다.)
9. 항목마다 `xcrun simctl io booted screenshot /tmp/child-p3-<번호>.png` 로 남긴다.
10. **앱을 지우지 않고** 시뮬레이터도 끄지 않는다.

- [ ] **Step 6: 정직함을 한 번 더 확인한다**

```bash
cd /Users/com/work/KidCare
grep -rn "commands" ios/KidCare/Child                     # 비어 있어야 한다(설계서 §1)
grep -rn "UNUserNotificationCenter\|FirebaseMessaging" ios/KidCare  # 비어 있어야 한다(§8.6·FCM 금지)
grep -rn "requestTemporaryFullAccuracy" ios/KidCare       # 비어 있어야 한다(§8.2)
grep -rn "force" ios/KidCare/Child/ChildSession.swift     # 강제 종료를 없는 일로 적은 자리가 없는지 눈으로
```
그리고 **화면이 거짓말하지 않는지**를 사람 눈으로 읽는다: "공유 중"이라고 말하는 모든 조합에서 실제로 점이 올라가는가. 특히 `.authorizedAlways` + `.fullAccuracy` + 새로고침 켜짐인데 **좌표가 안 오는** 경우가 있으면 그것은 새 결함이다.

- [ ] **Step 7: 되돌리고 확인**

```bash
cd /Users/com/work/KidCare
git checkout ios/KidCare/KidCareApp.swift
git diff ios/KidCare/KidCareApp.swift          # 비어 있어야 한다(configureForApp)
git status --short                              # 새 dev 문서 말고는 비어 있어야 한다
git diff --stat d26e28f..HEAD -- app firestore.rules gradlew   # 비어 있어야 한다
```

여기서 찾은 결함은 고친 뒤 테스트를 다시 돌리고 `iOS 아이 3단계 Fix round N: …` 으로 커밋한다.

- [ ] **Step 8: 커밋**

```bash
git add ios/dev/child-permissions.md
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" \
    commit -m "iOS 아이 3단계 단계 마무리: 권한 전수 대조와 시뮬레이터 아이 페어링 확인"
```

---

## 3단계 완료 기준

- [ ] 역할 선택 화면에서 **아이**를 고르면 초대 코드 화면으로 가고, 합류하면 `RoleStore.role == .child` 가 저장된다.
- [ ] 아이로 페어링한 폰이 앱을 여는 것만으로 수집이 시작된다 — **`-childSim` 없이.** `ChildSim*` 이 저장소에 하나도 없다.
- [ ] 수집기를 만드는 코드가 **뷰 밖**에 있다(`KidCareApp.init()` → `ChildSession`). 2단계 I1 과 1단계 M6 이 닫혔다.
- [ ] `TrackingCoordinator(ticker:)` 를 빠뜨리면 **컴파일이 안 되고**, `nil` 을 넘기면 `ChildSessionTests.세션은_시계를_단다` 가 빨개진다.
- [ ] 아이 화면이 한 번에 하나만 말하고, 순서가 가족 → 위치 → 항상 → 정확한 위치 → 새로고침 → 공유 중이다.
- [ ] 저전력 모드 줄은 **다른 문장과 함께** 뜨고 이벤트를 만들지 않는다.
- [ ] 강제 종료 안내가 **정상일 때도** 화면에 있고, 같은 사실이 `ChildSession` 의 로그에도 남는다.
- [ ] 권한이 꺼지면 `permission_off` 문서 **하나**가 나가고, 같은 상태가 이어지면 Firestore 를 한 번도 안 건드리며, 프로세스가 다시 떠도 다시 안 나간다.
- [ ] 배터리 15/20 히스테리시스가 정본과 같고, 못 읽으면(-1) 아무 판단도 안 한다.
- [ ] 조건 검사가 **좌표와 60초 시계 둘 다**에서 돈다 — 좌표가 죽어도 부모가 이유를 받는다(판정 기록 8).
- [ ] 새 `EventType` 이 **하나도 없다.** 부모 화면이 한 줄도 안 바뀐 채로 읽는다.
- [ ] 가족에서 빠졌는지 모를 때(`nil`) 화면이 아무 말도 바꾸지 않는다.
- [ ] `ios_child_unsupported_*` 셋이 `ios/`·`i18n/`·`tools/` 어디에도 없다. 새 키 아홉이 ko·en 에만 있고 `--check` 가 0 이다.
- [ ] 같은 장소 목록으로 `apply` 를 두 번 해도 OS 지역을 다시 걸지 않는다(2단계 M3).
- [ ] 출시 빌드 바이너리에 `childBattery`·`childSim` 문자열이 0개다.
- [ ] 앱 코드에 `@unchecked Sendable`·`nonisolated(unsafe)` 가 없고, 새 리스너(저전력 알림)에 떼는 길이 있다.
- [ ] `git diff --stat d26e28f..HEAD -- app firestore.rules gradlew` 가 **비어 있다**(이 단계는 `app/` 을 아예 안 만진다).
- [ ] 커밋이 전부 한국어이고 작성자가 `Yongminlee2 <dydals5678@gmail.com>` 이며 `Co-Authored-By` 가 하나도 없다.

---

## 자기 검토 결과 (writing-plans self-review)

**설계서 대응.** §14 3단계가 적은 세 줄을 하나씩 짚는다.

- "`Child/`: ChildPermissions, ConditionWatcher, DeviceState, ChildHomeModel, ChildHomeView, ChildRootView" → Task 1(앞의 둘)·Task 2(ChildHomeModel·View)·Task 3(ChildRootView). **`DeviceState` 는 1단계가 이미 만들었다**(그 파일 주석 `:30-33` 이 "설계서는 3단계에 적었지만 1단계로 당겼다 — 권한·저전력 감시는 안 당긴다"고 적어 뒀다). 이 단계는 그 파일을 **안 고치고 읽기만** 한다.
- "역할 선택 화면의 막이 제거, `JoinFamilyView(expectedRole: .child)`, `RouterView` 의 child 갈래, `RoleStore` 저장" → Task 3 Step 1·4. `JoinFamilyView` 와 `RoleStore` 는 **한 줄도 안 고친다** — 이미 `expectedRole` 을 받고 `result.role` 을 저장한다(선행 조건 grep 으로 확인).
- "새 i18n 키(§8.5) + `tools/ios-strings.py` 의 `INFOPLIST_KEYS` 확장 + `ios_child_unsupported_*` 셋 제거" → Task 1 Step 1(더하기)·Task 3 Step 1(지우기). **`INFOPLIST_KEYS` 확장은 1단계가 이미 했다** — 판정 기록 14 에 적었다.
- §8.1~8.4 네 권한 → `ChildPermissions` 넷 + `ChildPermissionsTests` 여덟. §8.1 의 "계속 본다"는 `onAuthorizationChange` 구독(Task 3 Step 3-6).
- §8.5 문구 → Task 1 Step 1 의 표. §8.6(아이폰에 없는 권한 둘) → 판정 기록 4 의 표에서 빠진 이유를 적었다.
- §5.3·§15-2 강제 종료 → 판정 기록 9 에 **문구를 그대로 써 뒀다**(화면 한 줄 + 로그 한 문단).
- §12.1 `ChildHomeModelTests` → Task 2 Step 1, 이름도 설계서 그대로.
- §12.4 "시뮬레이터로 되는 것" → Task 4 Step 5. 실기기 열 항목은 손대지 않는다.
- §17 열린 질문 4(새로고침을 고장으로 취급)·7(키 셋 삭제)·9(‘다시 연결’ 버튼) → 각각 `ChildPermissions.isGranted` 의 주석·Task 3 Step 1·판정 기록 13.
- §16 제약 → Global Constraints.

**작업 지시의 여덟 항목 대응.** ①진짜 시작 경로 → 판정 기록 1·2, Task 3. ②역할 켜기 → Task 3 Step 1. ③아이 화면 → Task 2. ④권한 넷과 "정직하게 안 하는 것" → Task 1·판정 기록 4·5·16. ⑤`ConditionWatcher` 와 4시간 유휴 업로드 이월 → Task 1·판정 기록 7·8. ⑥강제 종료 정직함 → 판정 기록 9(문구 두 벌을 글자로 적었다). ⑦`-childSim` 제거 → 판정 기록 3(배터리 인자 하나만 남기는 이유까지). ⑧이월 닫기 → M6(판정 기록 1), 2단계 M3(판정 기록 17). **2단계 I2 와 M1·M2·M4·M5 는 여기 안 맞는 이유를 "다루지 않는 것"에 적었다.**

**설계서에서 구체화하지 못한 것 셋.** 셋 다 본문에 그렇게 적었다.
- **설계서가 `ChildRootView` 에 수집기를 두라고 읽히는데, 그러면 2단계 I1 이 안 닫힌다.** 백그라운드 되살리기에서 SwiftUI body 가 도는지 보장이 없기 때문이다. 판정 기록 1 에서 `ChildSession` + `KidCareApp.init()` 으로 바꿨다 — **설계서의 글자에서 벗어난 유일한 자리**이고, 목적(§5.3 되살리기)은 그대로 지킨다. **주인 확인이 필요하다.**
- **백그라운드 앱 새로고침이 정말 배달을 멎게 하는지**(§17 열린 질문 4). 시뮬레이터로 못 본다. "고장으로 취급"한 채로 가고, 4단계에서 안 멎는 것이 확인되면 그 항목과 문구를 **지운다**(거짓 경고를 남겨두지 않는다).
- **강제 종료 뒤 되살아나는가**(§17 열린 질문 3). 못 본다. 이 계획서는 "안 되살아난다"를 가정하고 그것을 **화면에 적는** 쪽을 골랐다 — 반대로 가정했다가 틀리면 아이가 모르는 채로 하루가 조용해진다.

**자리표시 검사.** "TBD/적절히/나중에"는 없다. 실행해야 알 수 있는 값 다섯만 비워 뒀다: 선행 조건의 M, Task 4 Step 4 의 최종 개수, Task 4 Step 5 의 가족ID·아이UID, `ChildSession.build` 의 본문(2단계 `ChildSimView.start()` 를 **옮기는 것**이라 그 파일을 열어 그대로 옮기라고 적었다 — 추측해 쓰지 말라고 못 박았다), `ChildHomeView` 의 정확한 여백(`activity_child_home.xml` 을 열어 맞추라고 적었다). `String(localized:)` 의 서식 인자 모양과 `EventDoc` 초기화 인자 이름도 **grep 으로 확인한 뒤 채운다**고 적었다.

**타입·이름 일관성.**
- 테스트와 구현 대조: `ChildPermissions.Snapshot(authorization:accuracy:backgroundRefresh:)`·`Item`·`firstMissing`·`allMissing`·`isGranted`·`fix(for:in:)`·`titleKey`·`reasonKey`·`이름`, `ConditionWatcher(defaults:addEvent:)`·`check(familyId:childUid:batteryPercent:permissions:now:)`·`lowPercent`·`rearmPercent`, `ChildHomeModel.apply(permissions:stillMember:lowPower:)`·`state`·`titleKey`·`bodyKey`·`bodyArgument`·`reasonKey`·`action`·`lowPowerNoticeKey`·`forceQuitNoticeKey`, `ChildSession.shared`·`startIfChild(store:)`·`start(familyId:battery:)`·`stop()`·`requestAuthorization()`·`running`·`home` 이 전부 구현 Step 에 있다.
- 초안에서 고친 것 넷.
  - `ConditionWatcher` 를 `ChildPermissions` 를 **직접 읽는** 모양으로 두려다 **스냅샷을 받는** 모양으로 바꿨다. 직접 읽으면 `CLLocationManager` 가 필요해져 테스트가 시뮬레이터 권한 상태에 매달리고, 화면과 감시가 **서로 다른 순간의 값**으로 판단하는 창이 생긴다.
  - `ChildHomeModel` 을 화면이 매번 새로 만드는 값 타입으로 두려다 `@Observable` 클래스로 바꿔 `ChildSession` 이 소유하게 했다. 세션이 권한 변화를 먼저 받으므로(델리게이트) 그쪽이 갱신의 주인이다.
  - 저전력 모드를 `ChildPermissions.Item` 에 넣으려다 뺐다 — 넣으면 `firstMissing` 이 그것을 고장으로 돌려주고 `ConditionWatcher` 가 `permission_off` 를 쏜다. 설계서 §8.3 이 정확히 그것을 금지한다.
  - `ChildSession` 을 `actor` 로 두려다 `@MainActor final class` 로 바꿨다. 소유하는 것들(`LocationCollector`·`TrackingCoordinator`·`PlaceWatcher`·`ChildHomeModel`)이 전부 `@MainActor` 다 — `actor` 로 두면 경계마다 `await` 가 붙고 델리게이트 콜백에서 건너오는 길이 하나 더 는다.
- **실행 전에 확인이 필요한 가정 다섯.** 전부 Pre-flight conflict table 에 행이 있고, 다르면 멈추고 보고하게 적었다: `LocationCollector.manager` 의 접근 수준, `EventDoc` 초기화 인자, `String(localized:)` 서식 인자를 쓰는 기존 모양, `FirestoreErrorCode` 를 쓰는 기존 모양, `TrackingCoordinator(` 호출부 목록.

---

## Pre-flight conflict table

| 짝 | 함께 만지는 것 | 충돌 여부와 처리 |
|---|---|---|
| **1단계 ↔ 3단계 Task 3** | `Child/TrackingCoordinator.swift` 의 `init(ticker:)` 기본값과 `onCondition` 훅(`:63`) | 1단계가 훅을 "지금 자리에 둬야 순서가 안 틀어진다"(판정 기록 7)며 1번 단계에 비워 뒀다. Task 3 은 **그 자리에 잇기만** 한다 — 순서를 옮기지 않는다. 기본값 제거는 호출부를 전부 건드리므로 `grep -rn "TrackingCoordinator("` 결과를 **한 줄씩** 고친다. 값은 하나도 안 바꾼다 |
| **1단계 ↔ 3단계 Task 3** | `Child/TrackingTicker.swift` — `periodMillis == stopConfirmMillis == 60초` | 이 단계는 **안 고친다.** `CONDITION_CHECK_INTERVAL_MILLIS`(`TrackingService.kt:913`)가 같은 60초라 조건 검사 주기가 저절로 정본과 같아진다(1단계 수정 파동 보고서의 세 자리 한 값). 다르면 1단계가 깨진 것이다 |
| **1단계 ↔ 3단계 Task 1** | `Child/DeviceState.swift` | **안 고친다.** 1단계가 3단계에서 당겨 왔고(그 파일 `:30-33`), `ConditionWatcher` 는 `snapshot().batteryPercent` 를 **받기만** 한다(`ConditionWatcher.kt:76-77` 의 "두 번 적으면 언젠가 한쪽만 고친다") |
| **1단계 ↔ 3단계 Task 3** | `Child/LocationCollector.swift` — `requestAuthorization()`(:89-97)·`onAuthorizationChange`(:28)·`manager` | 1단계가 "두 번째 걸음과 화면 안내는 3단계가 정한다"고 적어 뒀다. Task 3 은 **그 함수를 부르기만** 한다 — 두 걸음을 화면에 다시 적지 않는다. `manager` 가 `private` 이면 밖으로 열지 말고 `var permissions: ChildPermissions.Snapshot` 를 더한다(매니저는 앱이 사는 동안 하나여야 한다, 설계서 §5.2) |
| **1단계 ↔ 3단계 Task 3** | `Child/ChildSimHarness.swift`·`ChildSimView.swift`·`RouterView.swift:48-55` | 1단계 판정 기록 9 가 "3단계가 `ChildRootView` 를 만들면 지운다"고 **예고했다.** 지우는 것이 계약 이행이지 남의 일을 없애는 것이 아니다. 배터리 주입만 좁게 남긴다(판정 기록 3). `ChildSimHarnessTests` 4개가 사라지므로 Task 4 의 개수 계산에 반영한다 |
| **1단계 ↔ 3단계 Task 3** | `KidCareApp.swift` | 1단계가 `configureForApp()` 을 `init()` 첫 줄로 두었고 그것이 커밋 시점의 계약이다. Task 3 은 **그 뒤에 한 줄을 더할 뿐**이다. 시뮬레이터 확인 중에 `configureForEmulator` 로 바꾸면 **Task 4 Step 7 에서 반드시 되돌린다** |
| **2단계 ↔ 3단계 Task 3** | `Child/PlaceWatcher.swift` 의 `apply(placeDocs:)` | 2단계 M3 을 여기서 닫는다(판정 기록 17). `places` 갱신과 OS 등록을 가르는 것이지 판정 로직을 바꾸는 것이 아니다. `PlaceWatcherTests` 의 기존 테스트가 "apply 하면 건다"를 보고 있으면 **그 테스트는 그대로 통과해야 한다**(첫 apply 는 언제나 건다) |
| **2단계 ↔ 3단계 Task 1** | `Core/EventRepository.add` 와 `EventDoc.firestoreData` | 2단계가 만들었고 **안 고친다.** 판정 기록 14(항상 `read: false`)가 이미 그 안에 있다. `ConditionWatcher` 는 그 함수를 주입받아 부르기만 한다 |
| **2단계 ↔ 3단계 Task 1** | 에뮬레이터 테스트(`ChildEventWriteTests`) | **새로 만들지 않는다**(판정 기록 18). 같은 함수·같은 문서 모양이라 두 벌이 된다. 다만 Task 4 Step 5 가 실제 쓰기를 눈으로 본다 |
| **2단계 ↔ 3단계 Task 3** | `Core/PlaceRepository.observePlaces` 구독을 `ChildSimView` 에서 `ChildSession` 으로 옮기는 것 | 리스너를 **떼는 길**이 함께 옮겨 가야 한다(Global Constraints). `stop()` 에 `placesListener?.remove()` 가 없으면 화면을 나갈 때 리스너가 샌다 |
| **3단계 Task 1 ↔ Task 2** | `ChildPermissions` | 순서 의존. `ChildHomeModel` 이 `firstMissing`·`fix` 를 그대로 쓴다 |
| **3단계 Task 1 ↔ Task 3** | `i18n/*.json` — Task 1 이 아홉을 더하고 Task 3 이 셋을 지운다 | **같은 파일을 두 커밋이 만진다.** Task 1 이 지우기까지 하면 그 사이 커밋에서 `RoleSelectView` 가 없는 키를 가리켜 화면에 키 이름이 뜬다. 그래서 더하기(Task 1)와 지우기(Task 3)를 **쓰는 곳의 제거와 같은 커밋**에 맞췄다. 둘 다 `--write-gaps` 를 돈다 |
| **3단계 Task 2 ↔ Task 3** | `Core/FamilyRepository.swift` | Task 2 가 `isStillMember` 를 더하고 Task 3 이 그것을 부른다. 순서 의존 |
| **3단계 Task 2 ↔ Task 3** | `ChildHomeModel` 의 소유자 | Task 2 는 모델과 뷰만 만들고 아무도 안 소유한다(테스트가 직접 만든다). Task 3 에서 `ChildSession.home` 이 주인이 된다 — Task 2 를 단독으로 돌리면 화면이 앱에 안 붙어 있는 것이 **정상**이다 |
| **3단계 ↔ 4단계** | `Guardian/ChildPlatform` 과 세 화면 잠금, `ios_child_no_remote_control`·`ios_child_schedule_not_applied` | 겹치지 않는다. 이 단계는 그 두 키를 **안 만든다**(판정 기록 14). `platform: "ios"` 는 1단계가 상태 문서에 이미 심었다 |
| **3단계 ↔ 보호자 앱(안 고침)** | `Guardian/AlertText`·`AlertViewModel` 이 `permission_off`·`low_battery` 를 이미 그린다 | **보호자 쪽은 한 줄도 안 바뀐다.** 새 `EventType` 을 안 만드는 것이 그 계약이다(판정 기록 7). Task 4 Step 5-7 이 `git diff --stat -- ios/KidCare/Guardian` 으로 확인한다 |
| **3단계 ↔ 안드로이드(안 고침)** | `ConditionWatcher.kt:145-147` 주석이 `at` 창을 "과거 24시간"으로 적었다 | 규칙은 7일이다(`firestore.rules:306-310`). 2단계 판정 기록 12 가 같은 것을 기록했다. **코틀린 주석을 고치지 않는다**(`app/src/main` 금지) — 4단계 개발일지에 한 줄 남긴다 |
| **작업 트리 상태 ↔ 3단계 시작** | 선행 조건의 `git status --short` 가 비어 있어야 한다 | 2단계가 `d26e28f` 로 끝났고 이 계획서 파일 자체도 같은 폴더에 들어간다. 시작 전에 2단계 커밋이 전부 끝났는지 확인한다 |
