# iOS 아이 역할 1단계 구현 계획 — 위치와 경로

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 아이폰이 **아이 폰**으로서 위치를 모아 안드로이드와 **글자까지 같은 모양**의 `children/{childUid}/trails/{dayKey}` 문서와 `children/{childUid}` 상태 문서를 쓰게 한다. 시뮬레이터에 GPX 경로를 먹이면 에뮬레이터에 그 두 문서가 올라가고, 지금 있는 아이폰 보호자 앱이 그 경로를 지도에 그린다. 순수 로직 다섯을 `Logic/` 으로 옮기고 전부 코틀린이 뽑은 골든 파일로 대조한다.

**Architecture:** 층이 셋이다. **`Logic/`** 은 Foundation 만 import 하는 순수 포팅이다(`LocationFilter`, `AdaptiveMovementDetector`, `MovementTrailFilter`, `SegmentBuilder`, `TrailCodec` + 기존 `Fix`·`Segment` 확장). 코틀린이 정본이고 골든 파일이 그 계약을 기계로 잡는다. **`Child/`** 는 CoreLocation·UIKit·파일을 아는 자리다 — `LocationCollector` 가 연속 스트림을 받아 `CollectionMode` 표의 소프트웨어 간격으로 솎고, `TrackingCoordinator`(`@MainActor`) 가 안드로이드 `TrackingService.handle()`(:532-699)의 순서를 **글자 그대로** 돌리며 `TrailBuffer`(메모리)·`TrailStore`(파일)·업로드 판정을 소유한다. **`Core/`** 는 Firestore 를 아는 자리다 — `TrailRepository.save`, 새 `ChildStatusReporter`, `Documents.swift` 의 쓰기 모양(`firestoreData`). 아이 역할 화면(`ChildRootView`)과 역할 선택 막이 제거는 **3단계 몫이라**, 1단계는 DEBUG 전용 실행 인자로 뜨는 `ChildSimHarness` 하나로 파이프라인을 시뮬레이터에서 돌린다(판정 기록 9).

**Tech Stack:** Swift 6 엄격 동시성 / iOS 17 / SwiftUI / CoreLocation / Firebase Firestore 12.19.1 / Swift Testing / XcodeGen. 새 의존성 없음. 코틀린 쪽은 기존 `GoldenFileWriterTest.kt` 한 파일에 `@Test` 다섯을 더하는 것이 전부다.

**Spec:** `docs/superpowers/specs/2026-09-22-kidcare-ios-child-design.md`. 이 단계가 기대는 곳은 다음과 같다.

- §3.1 `Logic/` 새 파일 표 중 다섯(장소·이름 관련 셋은 2단계), §3.2 `Fix.speedAccuracy`·`Segment.nameLat/nameLng`
- §3.3 `Core/ChildStatusReporter`(신규), `TrailRepository.save`, `ChildStatusDoc.platform`
- §3.4 `Child/` 중 여섯: `LocationCollector`, `CollectionMode`, `TrackingCoordinator`, `TrailBuffer`, `TrailStore`, `TrailUploader`(+ 브리프가 상태 문서의 배터리를 요구하므로 `DeviceState`, 판정 기록 8)
- §4 상수 대조표 전체(§4.6~4.7 은 2단계)
- §5 아이폰에서의 위치 수집(5.1 연속 스트림 + 소프트웨어 간격, 5.2 `Info.plist`·매니저 설정, 5.3 되살아나는 길)
- §6 데이터 흐름 전부(6.1 점 하나가 지나는 길, 6.2 버퍼와 파일, 6.3 하루 문서, 6.4 업로드 시점, 6.5 오프라인)
- §11.1 쓰기가 규칙을 통과하는가, §12.1·12.2·12.3 테스트, §14 "1단계 — 위치와 경로"
- §15-1 "시간 간격으로 위치를 요청할 수 없다", §15-3 `STILL_ESCALATE_MILLIS`, §15-7 "위치 권한 0개라는 성질을 잃는다"

**선행 조건.** 시작 전에 아래가 전부 맞는지 확인한다. 하나라도 다르면 맨 아래 Pre-flight conflict table 의 해당 행을 먼저 처리한다.

```bash
cd /Users/com/work/KidCare
git status --short                                                   # 비어 있어야 한다
git log --oneline -1                                                 # 4bda965 설계서: 아이폰 아이 역할 …
git rev-parse --abbrev-ref HEAD                                      # ios-guardian-app
grep -n "private static let earthRadiusMeters\|private static let maxSpeedMps\|private static func distanceMeters" ios/KidCare/Logic/RoutePathRefiner.swift   # 세 줄 (Task 1 이 지운다)
grep -rn "Fix(" ios/KidCare ios/KidCareTests | wc -l                 # 호출부 개수. speedAccuracy 는 마지막 기본값이라 0곳이 바뀐다
grep -n "Segment(" ios/KidCare/Logic/SegmentSummarizer.swift ios/KidCare/Logic/TimelinePanel.swift | wc -l   # 1 이상이면 Task 2 의 명시적 init 이 그 호출부를 살려야 한다
grep -n 'info\["UIBackgroundModes"\] == nil' ios/KidCareTests/ReleaseConfigTests.swift   # 한 줄 (Task 3 이 고친다)
grep -n 'hasSuffix("UsageDescription")' ios/KidCareTests/ReleaseConfigTests.swift        # 한 줄 (Task 3 이 고친다)
grep -n "INFOPLIST_KEYS = " tools/ios-strings.py                     # 한 줄, 지금은 CFBundleDisplayName 하나뿐
python3 tools/ios-strings.py --check; echo $?                        # 0
curl -s http://127.0.0.1:8080/ >/dev/null && echo "에뮬레이터 살아 있다"   # 살아 있어야 한다 (Auth 9099 / Firestore 8080, kidcare-emulator)
cd ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5
```

마지막 명령이 보고한 **테스트 개수를 M 으로 적어 둔다.** 각 Task 의 "통과 확인"과 단계 마무리가 그 수와 비교한다.

## Global Constraints

5·6단계 계획서의 Global Constraints 를 그대로 옮긴 것(verbatim):

- Swift 6 strict concurrency, iOS 17.0, SwiftUI, XcodeGen (`ios/project.yml`; never hand-edit the xcodeproj), Swift Testing. `ios/KidCare/Logic/` imports Foundation only. No `@unchecked Sendable` or `nonisolated(unsafe)` in app code.
- No push notifications and no FCM (the Firebase Spark free plan). Every Firestore listener has a removal path on disappear.
- i18n: 새 키는 `i18n/ko.json` 과 `i18n/en.json` **둘 다**에 넣고 `python3 tools/ios-strings.py` 로 `Localizable.xcstrings` 를 다시 만든다. **번역을 지어내지 않는다** — 나머지 12개 언어는 영어로 채워지고 `tools/i18n-untranslated.json` 에 기록된다(6단계 공통 절차 A). `%@` 는 `i18n/*.json` 에 절대 쓰지 않는다. 리터럴 `%` 는 `%%` 다. **무관한 화면의 문구 키를 빌려 쓰지 않는다**(두 번 거절당했다).
- Tests never write to production Firestore. Emulator tests use `configureForEmulator(projectId: "kidcare-emulator")` (Auth 127.0.0.1:9099, Firestore 8080), and `KidCareApp.init()` must call `configureForApp()` at commit time.
- Commits are in Korean, author `Yongminlee2 <dydals5678@gmail.com>`, with no Co-Authored-By trailer and no AI traces.
- Test command: `cd ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'`.
- **정본은 안드로이드다.** 이 계획서가 코틀린과 다르면 코틀린이 맞다. 상수는 인용한 줄에서 그대로 옮긴다.
- 주석은 한국어로 '왜'를 적는다. 실행 전 PATH 는 `export PATH="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:$PATH"` 이다. 파일을 새로 만들었으면 테스트 전에 `cd ios && xcodegen generate` 를 돌린다.
- `CancellationError` 를 일반 `catch` 로 삼키지 않는다 — 안드로이드에서 같은 사고를 아홉 번 고쳤다.

이 단계의 브리프가 더한 것(전부 구속력이 있다):

- **안드로이드는 딱 한 파일만 건드린다.** `app/src/test/java/com/kidcare/family/logic/GoldenFileWriterTest.kt` 다(2단계와 같은 예외, 설계서 §12.2·§17 열린 질문 1). `app/src/main` · `firestore.rules` · `gradlew` 는 한 줄도 안 바뀐다. 매 커밋 전에 `git diff --stat 4bda965..HEAD -- app firestore.rules gradlew` 가 **그 한 파일만** 보여야 한다.
- **옮긴 로직 전부에 골든 대조가 붙는다.** 다섯 로직 각각에 골든 파일 하나, 그리고 각각을 **일부러 망가뜨려 골든이 정말 무는지** 확인한다(2단계에서 이 확인이 가장 중요했다, 설계서 §14 4단계).
- **밀도는 안드로이드와 같다.** 아이폰에는 간격 요청이 없으므로 연속 스트림 + 소프트웨어 솎기다(§5.1). `STILL_ESCALATE_MILLIS`(5분)를 포함한 다섯 모드의 문턱을 `CollectionMode` 표 하나에 못박고 단위 테스트로 고정한다.
- **강제 종료를 없는 일로 하지 않는다.** iOS 는 강제 종료 뒤 앱을 되살리지 않는다(§5.3). 1단계는 **실제로 있는** 되살리기 길(중요 위치 변경)만 걸고, 부모에게 그것을 어떻게 말할지는 3단계가 정한다.
- **이 단계에는 명령이 하나도 없다.** `locate_now`·실시간 보기·`commands/` 읽기가 전부 범위 밖이다. `CommandRepository` 를 부르는 코드를 새로 쓰지 않는다.
- **에뮬레이터만 쓴다.** 모든 테스트는 이미 떠 있는 Firebase 에뮬레이터(Auth 9099 / Firestore 8080, 프로젝트 `kidcare-emulator`)나 가짜를 상대한다. 운영 Firebase 를 건드리지 않고, **실기기를 아이로 페어링하지 않는다**(설계서 §13).
- **업로드 주기는 15분 / 4시간이다**(§6.4). 이 단계에서 이 값을 조정하지 않는다.
- **시뮬레이터를 끄거나 지우지 않는다.** `xcrun simctl shutdown`·`erase` 를 쓰지 않는다. 테스트 전에 앱을 **지우지 않는다** — 덮어 설치한다. 남은 상태 때문에 테스트가 **실제로 실패했을 때만** 지운다(그리고 그 사실을 적는다).
- **에뮬레이터를 다시 띄우지 않는다.** 이미 떠 있는 것과 거기 들어 있는 데이터를 그대로 쓴다.

## 공통 절차 A — 문구 키를 카탈로그에 넣는 법

6단계 계획서 공통 절차 A 그대로다. 요약하면 셋이다.

1. 새 문구는 `i18n/ko.json` 과 `i18n/en.json` **둘 다**에 넣는다. 두 파일은 코드 포인트 순으로 정렬돼 있고 파일 끝에 줄바꿈이 하나 있다(`json.dumps(d, indent=2, ensure_ascii=False) + "\n"` 와 바이트까지 같다). 나머지 12개 언어 파일에는 **넣지 않는다.**
2. 키를 더하거나 뺐으면 `python3 tools/ios-strings.py --write-gaps` 로 빈 칸 기록(`tools/i18n-untranslated.json`)까지 다시 쓴다. diff 에 나온 빈 칸 변화가 의도한 것인지 눈으로 본다.
3. 평소에는 `python3 tools/ios-strings.py` 를 돌린다. 빈 칸이 기록과 다르면 쓰지 않고 멈춘다(종료 코드 1).

검사는 `python3 tools/ios-strings.py --check`(0 이어야 한다), `swift tools/check-i18n-keys.swift`(사람이 읽는 보고서, 빈 칸이 있는 한 1 이 정상), 그리고 `LocalizableCatalogTests`·`I18nKeyParityTests`·`LocalizationBundleTests`·`ReleaseConfigTests.앱_이름` 이다.

이 단계가 더하는 키는 **둘뿐이다**(Task 3): `ios_perm_location_when_in_use`, `ios_perm_location_always`. 둘 다 `Info.plist` 용이라 `tools/ios-strings.py` 의 `INFOPLIST_KEYS` 에 매핑을 더해야 `Localizable.xcstrings` 의 InfoPlist 항목으로 실린다(설계서 §8.5 끝).

## 공통 절차 B — 커밋

```bash
cd /Users/com/work/KidCare
git diff --stat 4bda965..HEAD -- app firestore.rules gradlew
#   → GoldenFileWriterTest.kt 한 줄만 나와야 한다. 다른 파일이 보이면 멈추고 되돌린다.
git diff ios/KidCare/KidCareApp.swift                            # 비어 있어야 한다(configureForApp)
grep -rn "@unchecked Sendable\|nonisolated(unsafe)\|navigationBarBackButtonHidden" ios/KidCare   # 비어 있어야 한다
grep -rn "CommandRepository\|locate_now\|startLiveTracking" ios/KidCare/Child                    # 비어 있어야 한다(명령 없음)
grep -rn "import CoreLocation\|import FirebaseFirestore\|import SwiftUI\|import UIKit" ios/KidCare/Logic   # 비어 있어야 한다
python3 tools/ios-strings.py --check                             # 0
git add <이 Task 의 파일들>
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "<한국어 메시지>"
```

## 공통 절차 C — 골든 파일 한 벌을 만드는 법

옮긴 로직마다 **똑같이 세 걸음**이다. Task 1·2 가 이 절차를 다섯 번 돈다.

1. **코틀린 쪽.** `app/src/test/java/com/kidcare/family/logic/GoldenFileWriterTest.kt` 에 `@Test` 하나와 `generate*()` 하나를 더한다. 그 파일이 이미 갖춘 규율을 그대로 쓴다.
   - 손으로 짠 `toJson` 을 쓴다(의존성을 더하지 않는다).
   - `@Test` 는 **`generate*()` 를 먼저 지역 변수로 평가한 뒤** `writeGoldenIfPresent(name, toJson(payload))` 를 부른다. `ios/` 가 없어도 생성·자체 검증은 돌아야 한다(그 함수 주석 :62-72).
   - 페이로드는 항상 `linkedMapOf("constants" to …, "cases" to …)` 모양이다. `constants` 는 **그 로직의 상수 전부를 코틀린이 실제로 들고 있는 값으로** 적는다 — `Float` 상수는 `.toDouble()` 로 넓혀서 적는다(아래 2번이 이 값을 쓴다).
   - **생성기 자체 점검.** `generate*()` 끝에 `check(...)` 를 넣어 **경계 바로 아래·위 케이스가 서로 다른 답을 내지 않으면 생성기가 죽게** 한다. 2단계에서 "경계값이라 이름 붙인 케이스가 실제로는 경계 근처에 가지도 못한" 사고가 있었다.
   - **`Float` ↔ `Double` 경계.** 생성기는 정확도·속도 값을 `Float` 로 **정확히 표현되는 값**으로만 만든다(설계서 §4.1). 그리고 속도 근거처럼 `Float` 산술과 `Double` 산술이 갈릴 수 있는 판정은, 생성기가 **같은 식을 `Double` 로도 계산해 두 답이 같은지 `check`** 한다(판정 기록 3).
2. **스위프트 쪽.** `ios/KidCareTests/GoldenComparisonTests.swift` 에 테스트 **둘**을 더한다.
   - `…_상수가_같다` — 골든의 `constants` 맵과 Swift 상수를 **비트까지** 비교한다. 이것이 §4 상수 대조표를 사람이 아니라 기계가 지키게 만드는 장치다.
   - `…_대조` — `cases` 를 먹여 답이 같은지 본다.
   - `골든_리소스가_번들에_있다` 에 그 파일의 `cases` 개수 하한 한 줄을 더한다. `[]` 로 비워도 통과하던 사고를 다시 열지 않는다.
3. **일부러 망가뜨려 확인한다.** Swift 포팅에서 값 하나를 바꾸고 골든 테스트만 돌려 **빨개지는 것을 본 뒤 되돌린다.** 각 Task 가 어디를 어떻게 바꿀지 적어 두었다. 빨개지지 않으면 그 골든은 스윕이 아니라 장식이다 — 멈추고 보고한다.

코틀린 생성기를 돌리는 명령은 하나다.

```bash
cd /Users/com/work/KidCare
export PATH="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:$PATH"
./gradlew :app:testDebugUnitTest --tests 'com.kidcare.family.logic.GoldenFileWriterTest'
git status --short ios/KidCareTests/golden/            # 새 파일과 바뀐 파일만
```

## 이 단계에서 다루지 않는 것

- **명령 전부.** `locate_now`, 실시간 보기, `commands/` 구독·쓰기. 브리프가 못박았고 설계서 §1 이 "아이폰 아이는 `commands/` 를 구독하지 않는다"로 이미 닫았다.
- **장소(지오펜스)와 머무름 이름.** `GeofenceEvaluator`·`PlaceNameCache`·`GeofenceRegionSelection`·`PlaceWatcher`·`PlaceStateStore`·`PlaceNamer`·`EventRepository.add` 는 **2단계**다(설계서 §14). 그래서 1단계의 `SegmentDoc.placeName` 은 **전부 빈 문자열**이고, 보호자 타임라인은 그 구간을 "머무른 곳"으로 표시한다(`SegmentDoc.placeName` 주석의 이미 정해진 동작). `TrackingCoordinator` 에는 그 자리에 **호출되지 않는 훅 하나**만 남긴다(판정 기록 7).
- **아이 화면·권한 안내·역할 선택 막이 제거.** `ChildHomeModel`·`ChildHomeView`·`ChildRootView`·`ChildPermissions`·`ConditionWatcher`, `RoleSelectView` 의 막이 제거, `ios_child_unsupported_*` 세 키 삭제는 **3단계**다. 1단계는 DEBUG 전용 `ChildSimHarness` 로만 아이 파이프라인을 띄운다(판정 기록 9).
- **보호자 화면 잠금과 `Guardian/ChildPlatform`.** **4단계**다. 1단계는 상태 문서에 `platform: "ios"` 를 **심기만** 한다(설계서 §10.1 이 요구하는 재료).
- **실기기.** 설계서 §12.4 의 열 항목은 4단계다. 이 단계는 시뮬레이터와 에뮬레이터만 쓴다.
- **배터리 실측.** 설계서 §9.1 이 "아직 아무도 안 쟀다"고 적었고 숫자를 지어내지 않는다.
- **`CoreMotion` 활동 인식.** 설계서 §17 열린 질문 5 가 v1 에서 안 쓰기로 했다. 그 자리를 `STILL_ESCALATE_MILLIS` 가 대신한다.

## 판정 기록 — 이 계획서가 내린 결정

1. **`Logic/` 다섯의 이름과 모양은 코틀린을 그대로 따른다.** `object` → `enum`(케이스 없는 네임스페이스), `class AdaptiveMovementDetector` → `final class`, `data class` → `struct`. 상수 이름만 Swift 관례(lowerCamelCase)로 바꾸고 **값과 줄 번호를 주석에 그대로 적는다**. 이름을 "더 나은 것"으로 바꾸지 않는 이유는 두 언어를 나란히 놓고 읽는 사람이 이 앱의 주 독자이기 때문이다.

2. **`accuracy`·`speed`·`speedAccuracy` 는 `Double` 로 넓힌다. 다만 `Float` 상수는 그 `Float` 이 실제로 담고 있는 `Double` 값을 적는다.** 설계서 §4.1 은 "`Float` → `Double` 로 넓히는 것이 유일한 차이"라고 했는데, 상수를 십진 리터럴 그대로 옮기면 그 말이 거짓이 된다. 코틀린 `0.7f` 는 `0.699999988079071` 이고 `0.35f` 는 `0.3499999940395355` 다 — Swift 에 `0.7`·`0.35` 라고 적으면 **문턱이 코틀린보다 미세하게 높아져** 경계에서 두 폰이 갈린다. 그래서 다음 둘만 확장값을 적고 나머지(50·100·15·3·25·40·55.6·1.0·1.5·0.6)는 십진 그대로 옮긴다.

   | 코틀린 | 리터럴 | Swift `Double` |
   |---|---|---|
   | `MovementTrailFilter.MOVING_SPEED_MPS` (:58) | `0.7f` | `0.699999988079071` |
   | `MovementTrailFilter.MIN_CONFIDENT_SPEED_MPS` (:82) · `AdaptiveMovementDetector.MIN_CONFIDENT_SPEED_MPS` (:181) | `0.35f` | `0.3499999940395355` |

   **사람이 지키게 두지 않는다.** 골든 파일의 `constants` 맵이 코틀린 값을 그대로 싣고, `GoldenComparisonTests` 가 Swift 상수와 비트까지 비교한다(공통 절차 C-2). 누가 "0.35 로 고치는 게 깔끔하다"고 정리하면 그 자리에서 빨개진다.

3. **`Float` 산술과 `Double` 산술이 갈릴 수 있는 곳은 생성기가 막는다.** `speed - speedAccuracy >= MIN_CONFIDENT_SPEED_MPS` 는 코틀린에서 `Float` 뺄셈이고 Swift 에서 `Double` 뺄셈이다. 값에 따라 문턱 양쪽으로 갈릴 수 있다. 두 언어의 산술을 억지로 맞추지 않는다(Swift 에서 `Float` 로 계산하면 `Fix` 를 `Double` 로 넓힌 결정이 무의미해진다). 대신 **생성기가 같은 식을 `Double` 로도 계산해 두 답이 같은 케이스만 골든에 싣고**, 다르면 `check()` 로 죽는다. 실제로 갈리는 입력이 있다면 그 사실이 생성 단계에서 드러나고, 그때는 사람이 보고 판정한다.

4. **`RoutePathRefiner` 의 사본 셋을 지우고 `LocationFilter` 를 쓴다.** 지금 `RoutePathRefiner.swift` 는 `distanceMeters`·`earthRadiusMeters`(:39-48)·`maxSpeedMps`(:35)를 자기 안에 복사해 두고 있고, 그 파일 머리 주석(:6-11)이 "`LocationFilter` 타입 자체는 안 옮기므로 이 파일이 쓰는 두 값만 복사한다"고 이유를 적어 뒀다. **이 단계가 그 전제를 없앤다** — `LocationFilter` 가 생긴다. 코틀린 `RoutePathRefiner.kt:82-103` 도 `LocationFilter.distanceMeters`·`MAX_SPEED_MPS` 를 부른다. 사본을 남기면 한쪽만 바뀌는 날이 온다. 머리 주석도 함께 고친다. 기존 `routePathRefiner.json` 골든이 초록으로 남는 것이 이 변경의 검사다(허용치 1e-9, `GoldenComparisonTests.swift:182`).

5. **하버사인의 라디안 변환은 지금 Swift 코드의 모양(`x * .pi / 180`)을 쓴다.** 자바 `Math.toRadians` 는 `x / 180.0 * PI` 라 마지막 비트가 다를 수 있다. 그래도 바꾸지 않는 이유는 둘이다. (1) 이미 `routePathRefiner` 골든 30여 케이스가 그 모양으로 1e-9 안에서 통과한다 — 두 식의 차이는 적도에서 0.1mm 아래다. (2) 대신 **골든 생성기가 거리 문턱을 정확히 맞춘 케이스를 만들지 않는다** — 25.0m·50.0m 같은 값은 `offsetLatLng` 로 만든 근사치라 애초에 정확히 문턱에 앉지 않고, `check()` 가 경계 위·아래가 실제로 갈리는지 확인한다. 골든 대조의 거리 비교도 1e-9 허용치를 쓴다.

6. **`Decision` 은 코틀린 enum 이름을 `rawValue` 로 갖는다.** 골든 JSON 이 `"UPLOAD_STALE_FALLBACK"` 같은 코틀린 이름을 그대로 싣고, Swift 가 `Decision(rawValue:)` 로 되돌려 비교한다. 6단계가 `Holiday` 에서 이름 매핑 표를 손으로 만들어야 했던 것(`GoldenComparisonTests.swift:82-92`)과 같은 사고 — `String(describing:).uppercased()` 가 `uploadStaleFallback` 을 `UPLOADSTALEFALLBACK` 으로 만든다 — 를 `rawValue` 로 아예 없앤다. `AdaptiveMovementState` 도 같다(`FAST_PROBE`·`SLOW_PROBE`·`MOVING`).

7. **`TrackingCoordinator` 는 10단계 순서를 지금 다 쓰고, 2단계 몫은 빈 훅으로 남긴다.** 설계서 §6.1 의 순서가 곧 계약이라 나중에 중간에 끼워 넣으면 순서가 틀어진다. 그래서 3번(등록 장소 안/밖 갱신)과 8번(`PlaceWatcher.onFix`)을 **주입된 옵셔널 클로저**로 지금 자리에 둔다. 1단계에서는 둘 다 `nil` 이고, `TrackingCoordinatorTests` 가 **가짜 훅으로 호출 순서와 인자를 이미 고정한다** — 특히 "8번이 7번의 결과에 안 묶인다"(`SKIP_TOO_CLOSE` 도 넘어간다, `TrackingService.kt:631-639`)를 1단계에서 테스트로 박아 둔다. 1번(`ConditionWatcher`)도 같은 모양의 훅이다(3단계가 잇는다). **훅이 아니라 빈 클래스를 지금 만들지 않는다** — 안 쓰는 클래스는 2단계가 어차피 다시 쓴다.

8. **`DeviceState`(배터리)는 설계서가 3단계에 적어 뒀지만 1단계로 당긴다.** 브리프가 "`status` 문서에 위치와 배터리"를 1단계 산출물로 요구한다. 상태 문서를 쓰면서 배터리만 나중에 채우면 그 사이에 올라간 문서가 `battery: -1` 로 남아 부모 화면이 "모름"을 띄운다. 다만 **권한·저전력 모드 감시(`ConditionWatcher`)는 당기지 않는다** — 그건 이벤트를 쓰는 일이라 2·3단계 몫이다. `DeviceState` 는 **읽기만** 한다(`NetworkState.kt` 와 같은 자리).
   **시뮬레이터는 배터리를 안 준다.** `UIDevice.batteryLevel` 이 -1, `batteryState` 가 `.unknown` 이다(`simctl status_bar override` 는 화면 위 막대만 바꾼다). 그래서 `DeviceState` 는 배터리 읽기를 **주입받고**, 기본값이 진짜 `UIDevice` 다. 매핑은 `DeviceStateTests` 가 가짜로 고정하고, 시뮬레이터 확인에서는 `ChildSimHarness` 가 `-childSimBattery 77` 로 값을 주입해 상태 문서에 실제 숫자가 실리는 것을 눈으로 본다. 실기기 실측은 4단계다.

9. **아이 파이프라인은 DEBUG 전용 실행 인자로 띄운다(`ChildSimHarness`).** 역할 선택 막이 제거와 `ChildRootView` 는 3단계다(설계서 §14). 그런데 1단계의 완료 기준은 "시뮬레이터에 GPX 를 먹이면 보호자가 그 경로를 그린다"이라 띄울 방법이 필요하다. `Guardian/ReadOnlyCheck.swift` 가 이미 같은 모양(DEBUG 빌드 + `-readOnlyCheck` 인자)의 선례다. 그대로 따른다.
   - `-childSim <familyId>` 가 있으면 `RouterView` 가 다른 화면 대신 `ChildSimView` 를 그린다. 출시 빌드에서는 `#if DEBUG` 밖이라 **존재 자체가 없다.**
   - 그 화면은 익명 로그인한 **자기 uid 를 크게 보여준다**(시뮬레이터 확인에서 그 uid 로 멤버 문서를 심는다). 사람에게 보여주는 글이지만 **문구 키를 만들지 않는다** — 출시 빌드에 없는 화면에 14개 언어 칸을 더하면 번역 빈 칸 기록만 늘어난다.
   - '지금 올리기' 버튼 하나를 둔다. `TrackingCoordinator` 의 업로드 판정을 **건너뛰고** 직접 업로드를 부른다. 15분을 기다리지 않고 경로를 보기 위한 것이고, 판정 코드는 건드리지 않는다.
   - 3단계가 `ChildRootView` 를 만들면 이 화면은 **지운다.** 그 일을 3단계 계획서가 받도록 파일 머리 주석에 적는다.

10. **상태 문서의 `ringerMode`·`dnd` 는 빈 문자열을 **명시적으로** 쓴다.** 아이폰은 소리 모드를 읽을 API 자체가 없다(설계서 §1). 필드를 **빼면** 코틀린 `ChildStatusDoc.ringerMode` 의 기본값 `"normal"`(`Documents.kt:95`)과 Swift 의 같은 기본값이 살아나 부모 화면이 "벨소리"라고 **거짓말**한다. `""` 를 쓰면 `RingerMode.isKnown("")` 이 false 라 아이폰 보호자는 "모름"으로 접고(`ControlViewModel.swift:631`), 안드로이드 보호자는 이 작업의 범위 밖이다(설계서 §17 열린 질문 8). 침묵보다 "모른다"가 낫다는 이 앱의 규율 그대로다.
    같은 이유로 `wifiOn` 은 **필드 자체를 안 쓴다** — 아이폰은 와이파이 스위치를 못 읽고, `false`(꺼짐)와 없음(모름)은 다른 말이다(`Documents.kt:108-110`). `network` 는 `NWPathMonitor` 로 실제로 읽어 `wifi`/`cell`/`none` 을 쓴다(`NetworkState.kt:23-26` 의 값 그대로).

11. **`accuracy`·`speed` 의 마지막 비트는 안드로이드와 다르다. 필드 이름·타입·개수는 같다.** 안드로이드는 `Float` 를 Firestore 에 넣으므로 서버에 `Double(Float(12.3)) = 12.300000190734863` 이 저장된다. 아이폰은 `Double` 그대로 `12.3` 을 저장한다. **둘 다 Firestore 의 `double` 이고 보호자 코드는 `double(_:)` 하나로 읽는다** — 지도·타임라인·경로 다듬기 어디서도 이 차이가 보이지 않는다(허용치 1e-9 보다 작다). "안드로이드와 같은 모양"은 필드 집합과 타입을 말하고, 그것은 `DocumentsTests` 가 코틀린 `data class` 의 필드 목록과 대조해 지킨다.

12. **`Info.plist` 에 `UIBackgroundModes: [location]` 과 위치 사용 설명 둘이 생긴다 — `ReleaseConfigTests` 를 고쳐야 한다.** 지금 그 테스트는 "권한 문구 0개, 배경 모드 없음"을 **단언**한다(`ReleaseConfigTests.swift:87-90`, 7단계 판정 기록 10). 설계서 §15-7 이 이 성질을 잃는 것을 이 설계의 대가로 이미 적었다. 그래서 단언을 **지우지 않고 뒤집는다** — "위치 사용 설명은 정확히 둘이고 배경 모드는 정확히 `location` 하나다"로 바꾸고, 왜 늘었는지(아이 역할)와 왜 더 늘면 안 되는지(가이드라인 2.5.4 는 배경 모드를 **실제로 쓰는 것만** 허용한다)를 주석에 적는다. 셋째 문구나 둘째 배경 모드가 생기면 그 자리에서 빨개진다.
    **개인정보 매니페스트(`PrivacyInfo.xcprivacy`)는 안 고친다.** `NSPrivacyCollectedDataTypePreciseLocation` 이 이미 들어 있다(보호자 앱이 아이 위치를 다루기 때문). 이유 필요 API 도 늘지 않는다 — 다만 `TrailStore` 를 쓸 때 **파일 시각 API(`modificationDate`·`attributesOfItem`)와 부팅 시각 API(`systemUptime`·`mach_absolute_time`)를 쓰지 않는다.** 안드로이드가 `SystemClock.elapsedRealtime()` 을 쓰는 자리(`TrackingService.kt:400`)는 3단계 몫이고, 그때도 `Date` 로 간다. `ReleaseConfigTests.이유_필요_API` 가 소스를 훑어 이 규율을 지킨다.

13. **`TrailStore` 는 `FileHandle.seekToEnd` 로 덧붙이고, 실패를 삼킨다.** 코틀린 `TrailStore.kt:23-25` 의 판단 그대로다 — 이 파일은 메모리 버퍼의 사본이지 원본이 아니다. 위치는 `.applicationSupportDirectory` 아래 `trail_today.csv` 이고(설계서 §6.2: `.documentDirectory` 는 파일 앱에 노출될 수 있다), `isExcludedFromBackup = true` 를 건다. **Application Support 디렉터리는 없을 수 있어 `createDirectory(withIntermediateDirectories: true)` 를 먼저 부른다** — iOS 에서 이 폴더는 앱이 만들기 전까지 존재하지 않는다(안드로이드 `filesDir` 은 항상 있어서 코틀린에 대응 코드가 없다).

14. **업로드 규칙 셋 중 1·2 를 지금 다 쓰고, 3(사건 직후)도 **판정만** 지금 넣는다.** 사건을 쓰는 코드는 2단계다. 그런데 규칙 3 은 1·2 를 **무시하고** 올리는 갈래라 나중에 끼워 넣으면 판정 함수의 모양이 바뀐다. `shouldUpload(now:fix:eventJustWritten:)` 의 인자로 지금 두고, 1단계에서는 언제나 `false` 로 불린다. `UPLOAD_EVENT_MIN_GAP_MILLIS`(1분)까지 테스트로 고정해 두면 2단계는 부르는 쪽만 잇는다.

15. **`lastUploadAt`·`lastUploadedFix` 는 메모리에만 둔다.** 코틀린 `TrackingService.kt:81-89` 와 같은 판단이다 — 프로세스가 다시 뜨면 0/`nil` 이 되어 업로드가 한 번 더 나가는데, 그게 손해가 아니라 이득이다(되살아난 직후 부모가 최신을 한 번 받는다). 설계서 §6.4 가 명시적으로 같은 말을 한다. 그리고 이 성질이 설계서 §10.1 의 "페어링 뒤 첫 좌표에서 업로드를 한 번 강제"를 **공짜로** 만든다: `lastUploadAt == 0` 이라 첫 규칙이 곧바로 참이고, 그 한 번이 `platform: "ios"` 를 심는다.

16. **되살리는 길은 중요 위치 변경 하나만 1단계에 건다.** 설계서 §5.3 은 둘(중요 위치 변경 + 지역 감시)을 다 걸라고 했는데, 지역 감시는 장소 목록이 있어야 걸 수 있고 그건 2단계다. 1단계는 `startMonitoringSignificantLocationChanges()` 만 켜고, **되살아난 뒤의 복구**(`TrailUploader.restore()` 자리)를 지금 다 쓴다 — 오늘 파일을 읽어 버퍼를 되찾고, 마지막 점을 필터 기준점으로 돌려주고, **그 복구된 점으로는 절대 상태 문서를 쓰지 않는다**(`TrackingService.kt:713-717`). 복구는 시뮬레이터에서 앱을 껐다 켜서 확인할 수 있는 것이라 1단계에 둘 값어치가 있다.

17. **강제 종료를 '되살아난다'고 적지 않는다.** 코드에도 주석에도 "앱이 죽어도 계속 기록한다"고 쓰지 않는다. 사실은 "메모리 압박·재부팅으로 죽으면 중요 위치 변경이 되살리고, **앱 전환기에서 위로 밀면 아무도 되살리지 않는다**"이다(설계서 §5.3·§15-2). 부모에게 이것을 어떻게 말할지는 3단계가 정한다 — 1단계는 그 자리에 문구를 만들지 않는다.

18. **`didUpdateLocations` 묶음은 시간순으로 전부 처리한다.** `LocationCollector.kt:127-130` 과 같은 이유다 — `lastLocation` 하나만 쓰면 모퉁이가 사라져 경로가 건물을 가로지르는 직선이 된다. 실기기에서 실제로 묶음이 오는지는 4단계 확인 항목(설계서 §12.4-9)이지만, **코드는 온다고 가정하고 쓴다** — 안 오면 반복문이 한 번 도는 것뿐이고, 온다고 가정 안 했다가 오면 경로가 조용히 망가진다.

19. **CoreLocation 의 "못 믿음" 표기를 안드로이드 모양으로 옮긴다.** 두 API 가 무효값을 다르게 말한다. 이 표가 `LocationCollector.fix(from:)` 의 전부다.

    | CoreLocation | 값 | `Fix` | 근거 |
    |---|---|---|---|
    | `horizontalAccuracy` | 음수 = 무효 | `.infinity` | 코틀린은 `loc.accuracy` 가 항상 유효. `.infinity` 면 모든 정확도 게이트가 거절한다 — 지어내지 않는다 |
    | `speed` | 음수 = 무효 | `0` | 코틀린 `loc.speed` 는 모를 때 `0f`(`Fix.speed` 주석) |
    | `speedAccuracy` | 음수 = 무효 | `.infinity` | 코틀린 `loc.hasSpeedAccuracy()` 가 false 일 때와 같다(`LocationCollector.kt:138-142`) |
    | `timestamp` | — | `Int64(timeIntervalSince1970 * 1000)` | 코틀린 `loc.time` 은 UTC 밀리초 |

20. **`ChildSimHarness` 로 들어가는 길은 `RouterView` 안의 `#if DEBUG` 분기 하나뿐이다.** 그 파일에는 이미 `isRunningTests` 분기가 같은 자리에 있다(테스트 프로세스에서 데이터 읽는 화면으로 안 간다). 새 분기를 그 **위**에 둔다 — `-childSim` 은 사람이 일부러 준 인자라 테스트 분기보다 먼저 이긴다. `KidCareApp.swift` 는 건드리지 않는다(공통 절차 B 가 그 diff 가 비어 있는지 본다).

---

## File Structure

```
app/src/test/java/com/kidcare/family/logic/
└─ GoldenFileWriterTest.kt          수정. @Test 다섯 + generate* 다섯 (app/ 에서 유일하게 바뀌는 파일)
i18n/ko.json, i18n/en.json          수정. 키 2개(Task 3)
tools/
├─ ios-strings.py                   수정. INFOPLIST_KEYS 에 두 줄(Task 3)
└─ i18n-untranslated.json           수정(생성물, --write-gaps)
ios/Fixtures/
└─ child-sim-seoul-walk.gpx         신규. 시뮬레이터에 먹일 도보 경로(Task 5)
ios/project.yml                     수정. Info.plist UIBackgroundModes·위치 설명 둘(Task 3)
ios/KidCare/
├─ Localizable.xcstrings            생성물(Task 3)
├─ RouterView.swift                 수정. #if DEBUG -childSim 분기 한 덩어리(Task 4)
├─ Logic/
│  ├─ Fix.swift                     수정. speedAccuracy: Double = .infinity (Task 1)
│  ├─ LocationFilter.swift          신규. Decision·decide·distanceMeters (Task 1)
│  ├─ MovementTrailFilter.swift     신규. shouldRecord·isDisplacementEvidence (Task 1)
│  ├─ RoutePathRefiner.swift        수정. 사본 셋 삭제 → LocationFilter (Task 1, 판정 4)
│  ├─ AdaptiveMovementDetector.swift 신규. 상태 기계 (Task 2)
│  ├─ Segment.swift                 수정. nameLat/nameLng + 명시적 init (Task 2)
│  ├─ SegmentBuilder.swift          신규. build(points) (Task 2)
│  └─ TrailCodec.swift              신규. encodeLine·decode·capped (Task 2)
├─ Child/                           신규 폴더
│  ├─ CollectionMode.swift          모드 표 + STILL_ESCALATE_MILLIS (Task 3)
│  ├─ LocationCollector.swift       CLLocationManager 래퍼 + 소프트웨어 간격 (Task 3)
│  ├─ TrailBuffer.swift             오늘 점 메모리 버퍼 + 자정 넘김 (Task 3)
│  ├─ TrailStore.swift              trail_today.csv 덧붙이기 (Task 3)
│  ├─ DeviceState.swift             배터리·충전·통신 종류 읽기 (Task 3, 판정 8)
│  ├─ TrackingCoordinator.swift     handle() 10단계 + 업로드 판정 (Task 4)
│  ├─ TrailUploader.swift           하루 문서 하나 만들기 + restore() (Task 4)
│  ├─ ChildSimHarness.swift         DEBUG 전용 실행 인자 파싱 (Task 4, 판정 9)
│  └─ ChildSimView.swift            DEBUG 전용 화면(uid·상태·'지금 올리기') (Task 4)
├─ Core/
│  ├─ ChildStatusReporter.swift     신규. children/{childUid} 덮어쓰기 (Task 4)
│  ├─ TrailRepository.swift         수정. save(familyId:childUid:doc:) (Task 4)
│  └─ Documents.swift               수정. platform, 쓰기 모양(firestoreData) (Task 4)
ios/KidCareTests/
├─ golden/locationFilter.json            신규(코틀린 생성물, Task 1)
├─ golden/movementTrailFilter.json       신규(Task 1)
├─ golden/adaptiveMovementDetector.json  신규(Task 2)
├─ golden/segmentBuilder.json            신규(Task 2)
├─ golden/trailCodec.json                신규(Task 2)
├─ GoldenComparisonTests.swift      수정. 테스트 10 + 하한 5줄
├─ LocationFilterTests.swift         신규(안드로이드 테스트 포팅)
├─ MovementTrailFilterTests.swift     신규
├─ AdaptiveMovementDetectorTests.swift 신규
├─ SegmentBuilderTests.swift          신규
├─ TrailCodecTests.swift              신규
├─ LogicTypesTests.swift             수정. Fix.speedAccuracy·Segment.nameLat 기본값
├─ CollectionModeTests.swift          신규
├─ TrailBufferTests.swift             신규
├─ TrailStoreTests.swift              신규
├─ DeviceStateTests.swift             신규
├─ TrackingCoordinatorTests.swift     신규
├─ TrailUploaderTests.swift           신규
├─ ChildSimHarnessTests.swift         신규
├─ ChildDocumentsTests.swift          신규(쓰기 필드 집합)
├─ ChildTrailWriteTests.swift         신규(에뮬레이터)
└─ ReleaseConfigTests.swift          수정. 배경 모드·위치 설명 단언 뒤집기 (Task 3, 판정 12)
```

| Task | 끝나면 |
|---|---|
| 1 | `LocationFilter`·`MovementTrailFilter` 가 코틀린과 같은 답을 내고, 골든 둘이 일부러 망가뜨렸을 때 빨개진다. `RoutePathRefiner` 의 사본 셋이 사라지고 기존 골든이 그대로 초록이다 |
| 2 | `AdaptiveMovementDetector`·`SegmentBuilder`·`TrailCodec` 이 같은 답을 내고, 골든 셋이 문다. `Segment` 가 `nameLat`/`nameLng` 를 갖는다 |
| 3 | 다섯 수집 모드의 (정확도·거리 필터·간격)과 `STILL_ESCALATE_MILLIS` 가 테스트로 고정되고, 앱이 '항상 허용'과 배경 위치를 요구하는 빌드가 되며, 오늘 점이 파일에 남고 다시 읽힌다 |
| 4 | 시뮬레이터에서 좌표를 먹이면 에뮬레이터에 `trails/{dayKey}` 와 `children/{childUid}`(배터리·`platform: "ios"` 포함)가 **안드로이드와 같은 필드 집합**으로 올라가고, 규칙이 그 쓰기를 실제로 통과한다 |
| 5 | 단계 마무리 — 통합 리뷰 한 번, GPX 시뮬레이터 확인 한 번(아이가 만든 경로를 보호자 앱이 그대로 그린다) |

---
### Task 1: `LocationFilter` 와 `MovementTrailFilter` — 거리·정확도·5초 간격을 코틀린에서 옮긴다

**끝나면 `Logic/` 에 두 파일이 생기고, 코틀린이 뽑은 골든 둘이 그 둘을 문다.** `Fix` 가 `speedAccuracy` 를 갖고, `RoutePathRefiner` 가 자기 하버사인 사본을 버리고 `LocationFilter.distanceMeters` 를 쓴다. 화면 변화는 없다.

**Files:**
- Modify: `ios/KidCare/Logic/Fix.swift`(`speedAccuracy` 추가, 머리 주석 수정)
- Create: `ios/KidCare/Logic/LocationFilter.swift`, `ios/KidCare/Logic/MovementTrailFilter.swift`
- Modify: `ios/KidCare/Logic/RoutePathRefiner.swift`(사본 셋 삭제, 머리 주석 :6-11 수정)
- Modify: `app/src/test/java/com/kidcare/family/logic/GoldenFileWriterTest.kt`(`@Test` 둘 + `generate*` 둘)
- Create(생성물): `ios/KidCareTests/golden/locationFilter.json`, `ios/KidCareTests/golden/movementTrailFilter.json`
- Test: `ios/KidCareTests/LocationFilterTests.swift`, `ios/KidCareTests/MovementTrailFilterTests.swift`(신규), `ios/KidCareTests/GoldenComparisonTests.swift`(수정), `ios/KidCareTests/LogicTypesTests.swift`(수정)

**Interfaces:**
- Produces: `Decision`(`.upload`/`.uploadStaleFallback`/`.skipTooClose`/`.rejectInaccurate`/`.rejectImpossible`, `rawValue` 는 코틀린 이름), `LocationFilter.decide(previous:candidate:)`, `LocationFilter.distanceMeters(_:_:)`, `LocationFilter` 상수 일곱, `MovementTrailFilter.shouldRecord(previous:candidate:reportedMoving:)`, `MovementTrailFilter.isDisplacementEvidence(previous:candidate:)`, `Fix.speedAccuracy`
- Consumes: `Fix`(기존), `GoldenComparisonTests.readObject`(기존 private 헬퍼)

**정본:** `app/src/main/java/com/kidcare/family/logic/LocationFilter.kt` 전체, `.../MovementTrailFilter.kt` 전체. 포팅할 테스트는 `app/src/test/java/com/kidcare/family/logic/LocationFilterTest.kt`(131줄)·`MovementTrailFilterTest.kt`(246줄).

- [ ] **Step 1: 안드로이드 테스트를 Swift 로 옮겨 빨갛게 둔다**

`ios/KidCareTests/LocationFilterTests.swift` — `LocationFilterTest.kt` 의 `@Test` 를 **하나도 빼지 않고** 옮긴다. 이름은 코틀린 백틱 이름을 그대로 쓴다(두 파일을 나란히 놓고 읽는 사람이 주 독자다).

```swift
import Foundation
import Testing
@testable import KidCare

/// 정본은 안드로이드 `app/src/test/.../LocationFilterTest.kt` 다 — 그 파일의 테스트를 하나도 빼지 않고 옮겼다.
/// 골든 대조(`GoldenComparisonTests`)와 목적이 다르다: 저쪽은 "두 구현이 같은 함수인가"를 넓은 입력으로 보고,
/// 여기는 "사람이 정한 경계가 그대로인가"를 읽을 수 있는 이름으로 남긴다.
struct LocationFilterTests {

    private let seoulCityHall = Fix(lat: 37.5665, lng: 126.9780, accuracy: 10, at: 1_000_000)

    /// 위도 1도 ≈ 111,320m. 북쪽으로 meters 만큼 옮긴다(코틀린 `near` 와 같은 식).
    private func near(meters: Double, afterMillis: Int64, accuracy: Double = 10) -> Fix {
        Fix(
            lat: seoulCityHall.lat + meters / 111_320.0,
            lng: seoulCityHall.lng,
            accuracy: accuracy,
            at: seoulCityHall.at + afterMillis
        )
    }

    @Test("첫 위치는 무조건 올린다")
    func 첫_위치() {
        #expect(LocationFilter.decide(previous: nil, candidate: seoulCityHall) == .upload)
    }

    @Test("정확도 50m 는 경계값으로 받아들인다 — 완화가 아니라 평소 승인이어야 한다")
    func 정확도_경계() {
        let edge = Fix(lat: seoulCityHall.lat, lng: seoulCityHall.lng, accuracy: 50, at: seoulCityHall.at)
        #expect(LocationFilter.decide(previous: nil, candidate: edge) == .upload)
    }

    @Test("50m 를 조금만 넘어도 평소에는 버린다")
    func 정확도_경계_바로_위() {
        let justOver = near(meters: 5, afterMillis: 60_000, accuracy: 50.001)
        #expect(LocationFilter.decide(previous: seoulCityHall, candidate: justOver) == .rejectInaccurate)
    }

    @Test("15분 동안 못 올렸으면 같은 60m 짜리 점도 받아들인다 — UPLOAD 가 아니라 완화 승인이다")
    func 완화_문턱() {
        let coarse = near(meters: 5, afterMillis: 15 * 60 * 1000, accuracy: 60)
        #expect(LocationFilter.decide(previous: seoulCityHall, candidate: coarse) == .uploadStaleFallback)
    }

    @Test("시계가 거꾸로 가면 물리적으로 불가능한 이동이다")
    func 시계_역행() {
        let back = near(meters: 5, afterMillis: -1_000)
        #expect(LocationFilter.decide(previous: seoulCityHall, candidate: back) == .rejectImpossible)
    }

    // … LocationFilterTest.kt 의 나머지 @Test 를 같은 방식으로 전부 옮긴다.
    // 옮길 때 확인할 것 둘:
    //   1) `accuracy`/`speed` 인자는 Float 접미사 없이 Double 리터럴이 된다.
    //   2) `elapsed / 1000.0` 은 Swift 에서 Int64 나눗셈이 되지 않도록 Double(elapsed) 로 넓힌다.
}
```

`ios/KidCareTests/MovementTrailFilterTests.swift` 도 같은 방식으로 `MovementTrailFilterTest.kt` 를 통째로 옮긴다. 코틀린의 `fix(...)` 도우미(경도 1도 ≈ 88,800m)를 그대로 쓰고, `speedAccuracy: Float.POSITIVE_INFINITY` 기본값은 `.infinity` 가 된다.

`ios/KidCareTests/LogicTypesTests.swift` 에 두 줄을 더한다.

```swift
    @Test("Fix.speedAccuracy 의 기본값은 '모름'(무한대)이다 — 0 이면 모든 속도가 신뢰할 만한 것이 된다")
    func fix_속도오차_기본값() {
        #expect(Fix(lat: 0, lng: 0, accuracy: 10, at: 0).speedAccuracy == .infinity)
    }
```

- [ ] **Step 2: 실패를 확인한다**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/LocationFilterTests -only-testing:KidCareTests/MovementTrailFilterTests`
Expected: **컴파일 실패.** `LocationFilter`·`MovementTrailFilter`·`Fix.speedAccuracy` 가 아직 없다.

- [ ] **Step 3: `Fix` 에 `speedAccuracy` 를 더한다**

`ios/KidCare/Logic/Fix.swift` — 머리 주석에서 "`speedAccuracy` 는 아예 없다 — …그 로직이 여기 없어서다" 문장을 지우고 아래로 바꾼다. `let speed: Double` 아래에 프로퍼티를, `init` 에 **마지막 기본값 매개변수**를 더한다(기존 호출부가 한 곳도 안 바뀐다 — 설계서 §3.2).

```swift
    /// 기기가 보고한 속도 오차(1-sigma, m/s). 정본은 코틀린 `Fix.speedAccuracy`(`LocationFilter.kt:28`).
    ///
    /// 보호자 앱만 있던 시절에는 **일부러 뺐다** — 이 값을 읽는 로직(`AdaptiveMovementDetector`,
    /// `MovementTrailFilter`)이 아이 폰에만 있었고, 채울 수 없는 자리를 남기면 거기 들어가는 값은
    /// 지어낸 것뿐이기 때문이다. 아이 역할이 그 두 로직을 가져오면서 자리가 생겼다.
    ///
    /// 기본값이 `.infinity`("모른다")인 이유는 코틀린과 같다 — 0 으로 두면 `speed - speedAccuracy`
    /// 가 곧 `speed` 라, 실내에서 정지한 폰이 2~5m/s 로 잘못 보고하는 실기기 사례가 전부
    /// "확실한 보행"으로 통과한다(`MovementTrailFilter.kt:124-132`).
    ///
    /// **`init` 의 마지막 기본값 매개변수**로 두는 것이 중요하다. `let speedAccuracy: Double = .infinity`
    /// 처럼 선언부에 기본값을 주면 Swift 가 그 프로퍼티를 memberwise 초기화 목록에서 빼버려
    /// 영원히 무한대로 굳는다 — `speed` 에서 이미 한 번 겪은 사고다(그 프로퍼티 주석).
    let speedAccuracy: Double

    init(lat: Double, lng: Double, accuracy: Double, at: Int64, speed: Double = 0, speedAccuracy: Double = .infinity) {
        self.lat = lat
        self.lng = lng
        self.accuracy = accuracy
        self.at = at
        self.speed = speed
        self.speedAccuracy = speedAccuracy
    }
```

- [ ] **Step 4: `LocationFilter` 를 쓴다**

`ios/KidCare/Logic/LocationFilter.swift`:

```swift
import Foundation

/// [LocationFilter.decide] 의 답. `rawValue` 는 **코틀린 enum 이름 그대로**다 —
/// 골든 파일이 그 이름을 싣고 스위프트가 `Decision(rawValue:)` 로 되돌린다. Swift case 이름을
/// 기계로 변환하면(`String(describing:).uppercased()`) `uploadStaleFallback` 이
/// `UPLOADSTALEFALLBACK` 이 되어 손으로 매핑표를 들고 다녀야 한다(6단계가 `Holiday` 에서 겪었다).
enum Decision: String, Equatable {
    /// Firestore 에 올린다.
    case upload = "UPLOAD"

    /// 올리긴 하는데, 평소 기준이면 버렸을 점이다. 오차가 [LocationFilter.maxAccuracyMeters] 를
    /// 넘지만 마지막 업로드로부터 [LocationFilter.staleFallbackMillis] 가 지나 **아무것도 못 올리고
    /// 있는 상태**라 완화 기준까지 받아들였다는 뜻이다. [upload] 와 따로 두는 이유는 코틀린 주석
    /// (`LocationFilter.kt:35-52`) 그대로 로그와 테스트다 — 완화 승인이 정상 승인과 똑같이 조용하면
    /// "신호가 계속 나쁜 채로 간신히 버티는 중"과 "다 정상"을 구분할 방법이 없다.
    case uploadStaleFallback = "UPLOAD_STALE_FALLBACK"

    /// 거의 안 움직였다. 배터리·통신량을 아끼려고 건너뛴다.
    case skipTooClose = "SKIP_TOO_CLOSE"
    /// 오차가 너무 커서 못 믿는다.
    case rejectInaccurate = "REJECT_INACCURATE"
    /// 물리적으로 불가능한 이동. GPS 오류다.
    case rejectImpossible = "REJECT_IMPOSSIBLE"
}

/// 받은 위치를 올릴지 말지 판정한다. 정본은 안드로이드 `logic/LocationFilter.kt` 다.
///
/// 순서가 중요하다: 못 믿을 점(정확도·순간이동)을 먼저 버리고, 남은 것 중에서 안 움직인 것을
/// 건너뛴다. 반대 순서면 튄 좌표가 '많이 움직였다'로 통과해 버린다.
///
/// 코틀린이 `Float` 로 든 값(`accuracy`)을 여기서는 `Double` 로 넓힌다 — 설계서 §4.1. 넓히면서
/// **문턱 숫자가 미세하게 달라지지 않는지**는 골든 파일의 `constants` 가 기계로 지킨다
/// (`GoldenComparisonTests.위치필터_상수가_같다`).
enum LocationFilter {

    /// 평소 오차 문턱. 이보다 크면 버린다. `LocationFilter.kt:78` (`50f`).
    ///
    /// 100m 에서 50m 로 내렸다(2026-08-07). 90m 짜리 점도 지도에서는 확신에 찬 점 하나로 그려지는데,
    /// 그 점이 장소 이름까지 만들어내면 "옆 건물 이름"이 그대로 부모 화면에 박힌다.
    static let maxAccuracyMeters: Double = 50

    /// 오래 아무것도 못 올렸을 때만 쓰는 완화 문턱(= 옛 [maxAccuracyMeters] 값). `:88` (`100f`).
    /// 굶는 것보다 거친 점을 택한다 — 부모가 묻는 것은 "지금 어디 있냐"이고 침묵은 답이 안 된다.
    static let fallbackMaxAccuracyMeters: Double = 100

    /// 마지막 업로드로부터 이만큼 지나면 완화 문턱을 연다. `:97` (15분).
    /// [heartbeatMillis](10분)보다 **길어야 한다** — 같거나 짧으면 정상 동작 중에도 완화가 상시로 열린다.
    static let staleFallbackMillis: Int64 = 15 * 60 * 1000

    /// 이만큼 안 움직였으면 안 올린다. `:107` (25.0, 코틀린도 `Double`).
    static let minMoveMeters: Double = 25.0

    /// 시속 200km. 이보다 빠르면 GPS 오류로 본다. `:110` (55.6, 코틀린도 `Double`).
    static let maxSpeedMps: Double = 55.6

    /// 안 움직여도 이 시간이 지나면 살아있다는 뜻으로 한 번 올린다. `:113` (10분).
    static let heartbeatMillis: Int64 = 10 * 60 * 1000

    /// `:115`. 코틀린에서는 private 이지만 여기서는 `RoutePathRefiner` 가 같은 값을 쓰므로 내부 공개다 —
    /// 사본을 두면 한쪽만 바뀌는 날이 온다(1단계 판정 기록 4).
    static let earthRadiusMeters: Double = 6_371_000.0

    static func decide(previous: Fix?, candidate: Fix) -> Decision {
        // 올린 게 하나도 없다 = 부모 화면이 통째로 비어 있다. "오래 못 올렸다"의 가장 극단이므로
        // 완화 문턱을 그대로 적용한다(`:118-122`).
        guard let previous else { return acceptByAccuracy(candidate, stale: true) }

        let elapsed = candidate.at - previous.at
        if elapsed <= 0 { return .rejectImpossible }

        let stale = elapsed >= staleFallbackMillis
        let accuracyVerdict = acceptByAccuracy(candidate, stale: stale)
        if accuracyVerdict == .rejectInaccurate { return accuracyVerdict }

        let distance = distanceMeters(previous, candidate)
        if distance / (Double(elapsed) / 1000.0) > maxSpeedMps { return .rejectImpossible }

        // 완화로 통과한 점은 여기서 확정한다 — 순간이동 검사를 **지난 뒤**여야 한다(`:134-138`).
        // 거리·하트비트 검사를 건너뛰는 것은 판단이 아니라 산술이다: stale 이면 이미 15분이 지났고
        // 그러면 하트비트(10분)도 반드시 지났다.
        if accuracyVerdict == .uploadStaleFallback { return accuracyVerdict }

        if distance >= minMoveMeters { return .upload }
        if elapsed >= heartbeatMillis { return .upload }
        return .skipTooClose
    }

    /// 오차만 보고 내리는 1차 판정. 문턱은 `stale` 여부로 갈린다. `:146-150`.
    /// NaN 은 두 비교가 모두 거짓이라 자동으로 거절된다 — 코틀린도 같다.
    private static func acceptByAccuracy(_ candidate: Fix, stale: Bool) -> Decision {
        if candidate.accuracy <= maxAccuracyMeters { return .upload }
        if stale, candidate.accuracy <= fallbackMaxAccuracyMeters { return .uploadStaleFallback }
        return .rejectInaccurate
    }

    /// 하버사인 거리(m). `:153-159`.
    ///
    /// 라디안 변환은 `x * .pi / 180` 이고 자바 `Math.toRadians` 는 `x / 180.0 * PI` 라 마지막 비트가
    /// 다를 수 있다. 그대로 두는 이유는 판정 기록 5 — 두 식의 차이는 적도에서 0.1mm 아래이고,
    /// 골든 대조는 1e-9 허용치를 쓰며, 생성기는 문턱에 정확히 앉는 거리를 만들지 않는다.
    static func distanceMeters(_ a: Fix, _ b: Fix) -> Double {
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLng = (b.lng - a.lng) * .pi / 180
        let h = pow(sin(dLat / 2), 2)
            + cos(a.lat * .pi / 180) * cos(b.lat * .pi / 180) * pow(sin(dLng / 2), 2)
        return 2 * earthRadiusMeters * asin(sqrt(h))
    }
}
```

- [ ] **Step 5: `MovementTrailFilter` 를 쓴다**

`ios/KidCare/Logic/MovementTrailFilter.swift`. 상수 아홉을 `MovementTrailFilter.kt` 의 줄 번호와 함께 옮기고, **`0.7f`·`0.35f` 는 확장값으로 적는다**(판정 기록 2).

```swift
import Foundation

/// 이동 경로 파일에 남길 점을 고른다. 정본은 안드로이드 `logic/MovementTrailFilter.kt`.
///
/// 상태 보고에 쓰는 [LocationFilter] 와 분리한 이유는 목적이 다르기 때문이다 — 상태는 25m/10분이면
/// 충분하지만 경로는 모퉁이를 남기려면 이동 중 5초 점이 필요하다.
///
/// **아이폰에서는 [minIntervalMillis] 가 밀도를 지키는 유일한 장치다.** `CLLocationManager` 에는
/// "5초마다 하나"를 요청하는 손잡이가 없어서(설계서 §5.1) 안드로이드의 요청 주기와 이 필터가 만들던
/// 이중 방어 중 이쪽만 남는다. `Child/CollectionMode` 의 소프트웨어 간격이 같은 5초를 한 번 더 건다.
enum MovementTrailFilter {

    /// `:19`.
    static let minIntervalMillis: Int64 = 5_000

    /// 경로점으로 받는 정확도 상한. `:30` (`50f`). 상태 업로드와 같은 50m 다 — 30m 로 조였더니
    /// 버스·번화가·실내 구간(오차 30~50m 가 정상)이 통째로 비었다.
    static let maxAccuracyMeters: Double = 50

    /// 정지 주기 사이에 이만큼 옮겨졌으면 **좌표 자체가 이동의 증거**다. `:42` (코틀린도 `Double`).
    static let displacementEvidenceMeters: Double = 50.0

    /// 변위를 증거로 인정할 때 오차에 곱하는 배수. `:55`. 문턱은 `max(50m, hypot × 1.5)` 다 —
    /// 오차 40m 두 점의 변위 잡음은 표준편차가 약 57m 라 가만히 있어도 50m 는 예사로 벌어진다.
    static let displacementEvidenceNoiseMultiplier: Double = 1.5

    /// 정확도가 좋은 야외에서 보행으로 볼 수 있는 최소 GNSS 속도. `:58` 의 `0.7f` 다.
    /// **`0.7` 이라고 적으면 안 된다** — 코틀린 `Float` 0.7f 는 실제로 이 값이고, 십진 0.7 을 적으면
    /// 문턱이 미세하게 높아져 경계에서 두 폰이 갈린다(판정 기록 2). 골든의 `constants` 가 지킨다.
    static let movingSpeedMps: Double = 0.699999988079071

    /// 경로점으로 인정하는 최소 변위. `:76`. **오차에 비례해 키우지 않는다** — 예전 `max(5m, hypot)`
    /// 은 걷는 아이를 통째로 지웠다(5초에 6m 를 걷는데 오차 20m 면 28m 를 요구했다). 3m 는 완전히
    /// 같은 좌표가 반복해 들어오는 것만 걸러낸다.
    static let minDisplacementMeters: Double = 3.0

    /// 이 이하 오차의 GNSS 속도만 보행 판정의 보조 근거로 신뢰한다. `:79` (`15f`).
    static let speedTrustMaxAccuracyMeters: Double = 15

    /// 속도 오차를 뺀 뒤에도 이 값 이상이어야 실제 이동 속도로 본다. `:82` 의 `0.35f` 확장값.
    static let minConfidentSpeedMps: Double = 0.3499999940395355

    /// 속도값 하나만 튀어도 같은 좌표를 계속 기록하지 않도록 요구하는 최소 변위. `:85`.
    static let minSpeedEvidenceDisplacementMeters: Double = 3.0

    /// 활동 인식이 정지라고 하는데 좌표가 크게 옮겨졌는가. `:95-109`.
    /// true 면 호출자([Child.TrackingCoordinator])가 이동 확인을 시작한다.
    static func isDisplacementEvidence(previous: Fix?, candidate: Fix) -> Bool {
        guard let previous else { return false }
        guard candidate.accuracy.isFinite, candidate.accuracy <= LocationFilter.maxAccuracyMeters else { return false }
        guard previous.accuracy.isFinite, previous.accuracy <= LocationFilter.maxAccuracyMeters else { return false }
        let elapsed = candidate.at - previous.at
        if elapsed <= 0 { return false }
        let distance = LocationFilter.distanceMeters(previous, candidate)
        if distance / (Double(elapsed) / 1000.0) > LocationFilter.maxSpeedMps { return false }
        let threshold = max(
            displacementEvidenceMeters,
            (previous.accuracy.squareRoot() * 0).isNaN ? 0 : hypot(previous.accuracy, candidate.accuracy) * displacementEvidenceNoiseMultiplier
        )
        return distance >= threshold
    }

    /// `:111-144`.
    static func shouldRecord(previous: Fix?, candidate: Fix, reportedMoving: Bool) -> Bool {
        if !reportedMoving { return false }
        if candidate.accuracy > maxAccuracyMeters { return false }
        if candidate.speed > LocationFilter.maxSpeedMps { return false }
        guard let previous else { return true }

        let elapsed = candidate.at - previous.at
        if elapsed < minIntervalMillis { return false }

        let distance = LocationFilter.distanceMeters(previous, candidate)
        let impliedSpeed = distance / (Double(elapsed) / 1000.0)
        if impliedSpeed > LocationFilter.maxSpeedMps { return false }

        // 정확도가 좋은 야외의 GNSS speed 만 보조 근거로 쓴다. 실내에서는 정지한 폰도 2~5m/s 라고
        // 잘못 보고하는 실기기 사례가 있어 오차가 큰 speed 를 믿으면 안 된다(`:124-125`).
        let speedEvidence: Bool
        if candidate.speedAccuracy.isFinite {
            speedEvidence = candidate.speed - candidate.speedAccuracy >= minConfidentSpeedMps
        } else {
            // 예전 기기/공급자가 속도 정확도를 안 줄 때는 기존 속도 문턱을 쓰되, 아래 실제 변위
            // 조건까지 함께 만족해야 한다(`:129-131`).
            speedEvidence = candidate.speed >= movingSpeedMps
        }
        if previous.accuracy <= speedTrustMaxAccuracyMeters,
           candidate.accuracy <= speedTrustMaxAccuracyMeters,
           speedEvidence,
           distance >= minSpeedEvidenceDisplacementMeters {
            return true
        }

        // 예전에는 여기서 오차에 비례한 반경(hypot)을 요구했다. 그 판정이 걷는 아이를 통째로 지웠다
        // (`minDisplacementMeters` 주석). 이제는 같은 좌표의 반복만 걸러내고 흔들림 판단은 그리는
        // 쪽(`RoutePathRefiner`)으로 넘긴다.
        return distance >= minDisplacementMeters
    }
}
```

> **주의.** 위 `isDisplacementEvidence` 의 `threshold` 줄에 쓸데없는 표현이 섞여 있으면 안 된다. 코틀린은 그냥 `max(DISPLACEMENT_EVIDENCE_METERS, hypot(previous.accuracy, candidate.accuracy) * MULTIPLIER)` 다. 실제로 적을 줄은 이것이다:
> ```swift
>         let threshold = max(
>             displacementEvidenceMeters,
>             hypot(previous.accuracy, candidate.accuracy) * displacementEvidenceNoiseMultiplier
>         )
> ```
> 위 블록에 남아 있는 `(previous.accuracy.squareRoot() * 0).isNaN ? 0 :` 는 **지운다.** 두 `accuracy` 가 유한한 것은 이미 위에서 확인했으므로 방어가 필요 없고, 코틀린에 없는 갈래를 더하면 골든이 곧바로 빨개진다.

- [ ] **Step 6: `RoutePathRefiner` 의 사본 셋을 지운다(판정 기록 4)**

`ios/KidCare/Logic/RoutePathRefiner.swift`:
1. 머리 주석 :6-11 을 바꾼다 — "거리 계산과 순간이동 문턱은 이 파일이 사본으로 갖고 있었다. 아이 역할 1단계가 `LocationFilter` 를 옮겨 오면서 그 전제가 사라졌으므로 사본을 지우고 그쪽을 부른다(코틀린 `RoutePathRefiner.kt:82-103` 도 `LocationFilter` 를 부른다)."
2. `private static let maxSpeedMps`(:35), `private static let earthRadiusMeters`(:39), `private static func distanceMeters`(:42-48) 를 **지운다.**
3. 파일 안의 `distanceMeters(` 호출 넷(:110, :111, :113, :129)을 `LocationFilter.distanceMeters(` 로, `maxSpeedMps` 참조를 `LocationFilter.maxSpeedMps` 로 바꾼다.

```bash
cd /Users/com/work/KidCare
grep -n "distanceMeters\|maxSpeedMps\|earthRadiusMeters" ios/KidCare/Logic/RoutePathRefiner.swift   # 전부 LocationFilter. 접두사가 붙어 있어야 한다
```

- [ ] **Step 7: 코틀린 생성기에 `@Test` 둘을 더한다**

`app/src/test/java/com/kidcare/family/logic/GoldenFileWriterTest.kt` 의 맨 아래(마지막 `@Test` 다음, 클래스 닫는 중괄호 앞)에 더한다. 기존 도우미(`toJson`, `writeGoldenIfPresent`, `offsetLatLng`)를 그대로 쓴다.

```kotlin
    // ==================================================================
    // 6. LocationFilter — 정확도 두 문턱, 완화 창, 25m·10분, 순간이동
    // ==================================================================

    @Test
    fun `골든 - LocationFilter`() {
        val payload = linkedMapOf(
            "constants" to locationFilterConstants(),
            "cases" to generateLocationFilter(),
            "distances" to generateDistances(),
        )
        writeGoldenIfPresent("locationFilter", toJson(payload))
    }

    /** 스위프트가 상수를 그대로 옮겼는지 기계가 보게 한다(1단계 계획서 공통 절차 C-2). */
    private fun locationFilterConstants(): Map<String, Any?> = linkedMapOf(
        "maxAccuracyMeters" to LocationFilter.MAX_ACCURACY_METERS.toDouble(),
        "fallbackMaxAccuracyMeters" to LocationFilter.FALLBACK_MAX_ACCURACY_METERS.toDouble(),
        "staleFallbackMillis" to LocationFilter.STALE_FALLBACK_MILLIS,
        "minMoveMeters" to LocationFilter.MIN_MOVE_METERS,
        "maxSpeedMps" to LocationFilter.MAX_SPEED_MPS,
        "heartbeatMillis" to LocationFilter.HEARTBEAT_MILLIS,
    )

    private fun generateLocationFilter(): List<Map<String, Any?>> {
        val baseLat = 37.5665
        val baseLng = 126.9780
        val t0 = 1_700_000_000_000L
        val cases = mutableListOf<Map<String, Any?>>()

        fun fixJson(f: Fix?): Any? = f?.let {
            linkedMapOf(
                "lat" to it.lat, "lng" to it.lng,
                "accuracy" to it.accuracy.toDouble(), "speed" to it.speed.toDouble(),
                "at" to it.at, "speedAccuracy" to it.speedAccuracy.toDouble(),
            )
        }

        fun add(name: String, previous: Fix?, candidate: Fix) {
            cases += linkedMapOf(
                "name" to name,
                "previous" to fixJson(previous),
                "candidate" to fixJson(candidate),
                "decision" to LocationFilter.decide(previous, candidate).name,
            )
        }

        fun at(meters: Double, afterMillis: Long, accuracy: Float, speed: Float = 0f): Fix {
            val (lat, lng) = offsetLatLng(baseLat to baseLng, meters, 0.0)
            return Fix(lat, lng, accuracy, t0 + afterMillis, speed)
        }

        val base = Fix(baseLat, baseLng, 10f, t0)

        // previous == null — 완화 창이 열린 것과 같다.
        // 정확도는 Float 로 정확히 표현되는 값만 쓴다(설계서 §4.1): 49.5 / 50 / 50.5 / 99.5 / 100 / 100.5
        listOf(49.5f, 50f, 50.5f, 99.5f, 100f, 100.5f).forEach {
            add("first_fix_accuracy_$it", null, Fix(baseLat, baseLng, it, t0))
        }

        // 평소 창(15분 미만): 50 위는 전부 거절.
        listOf(49.5f, 50f, 50.5f, 60f, 100f).forEach {
            add("fresh_accuracy_$it", base, at(5.0, 60_000L, it))
        }

        // 완화 창 경계(15분 = 900_000ms) 양옆. 같은 60m 점이 갈려야 한다.
        listOf(899_999L, 900_000L, 900_001L).forEach {
            add("stale_window_$it", base, at(5.0, it, 60f))
        }

        // 25m 이동 문턱 양옆. 시간은 하트비트(10분)보다 짧게 둬 거리만 갈리게 한다.
        listOf(24.0, 25.0, 26.0).forEach {
            add("move_threshold_$it", base, at(it, 60_000L, 10f))
        }

        // 하트비트(10분) 양옆. 거리는 항상 1m 로 두어 시간만 갈린다.
        listOf(599_999L, 600_000L, 600_001L).forEach {
            add("heartbeat_$it", base, at(1.0, it, 10f))
        }

        // 순간이동(55.6 m/s) 양옆. 1초 사이 이동 거리로 속도를 맞춘다.
        listOf(55.0, 56.0, 60.0).forEach {
            add("teleport_$it", base, at(it, 1_000L, 10f))
        }

        // elapsed <= 0 (시계 역행·동일 시각).
        add("elapsed_zero", base, at(5.0, 0L, 10f))
        add("elapsed_negative", base, at(5.0, -1_000L, 10f))

        // 완화 승인은 순간이동 검사를 **지난 뒤**여야 한다 — 15분 뒤에 1000km 를 간 60m 점.
        run {
            val (lat, lng) = offsetLatLng(baseLat to baseLng, 1_000_000.0, 0.0)
            add("stale_but_teleport", base, Fix(lat, lng, 60f, t0 + 900_000L))
        }

        // 자체 점검: 문턱 양옆이 실제로 갈리는가.
        fun decisionOf(name: String) = cases.first { it["name"] == name }["decision"]
        check(decisionOf("fresh_accuracy_50.0") == "UPLOAD" && decisionOf("fresh_accuracy_50.5") == "REJECT_INACCURATE") {
            "정확도 50m 경계가 안 갈린다 — 생성기가 경계에 도달하지 못했다"
        }
        check(decisionOf("stale_window_899999") == "REJECT_INACCURATE" && decisionOf("stale_window_900000") == "UPLOAD_STALE_FALLBACK") {
            "완화 창 15분 경계가 안 갈린다"
        }
        check(decisionOf("move_threshold_24.0") == "SKIP_TOO_CLOSE" && decisionOf("move_threshold_26.0") == "UPLOAD") {
            "25m 이동 문턱이 안 갈린다"
        }
        check(decisionOf("heartbeat_599999") == "SKIP_TOO_CLOSE" && decisionOf("heartbeat_600000") == "UPLOAD") {
            "하트비트 10분 경계가 안 갈린다"
        }
        check(decisionOf("teleport_55.0") != "REJECT_IMPOSSIBLE" && decisionOf("teleport_56.0") == "REJECT_IMPOSSIBLE") {
            "순간이동 문턱이 안 갈린다"
        }
        check(decisionOf("stale_but_teleport") == "REJECT_IMPOSSIBLE") {
            "완화 승인이 순간이동 검사를 건너뛰었다 — LocationFilter.kt:134-138 의 순서가 깨졌다"
        }
        return cases
    }

    /** distanceMeters 자체도 따로 쓸어본다 — 위·경도 양방향, 적도·극지, 같은 점. */
    private fun generateDistances(): List<Map<String, Any?>> {
        val cases = mutableListOf<Map<String, Any?>>()
        val anchors = listOf(37.5665 to 126.9780, 0.0 to 0.0, 0.0 to 179.9, 89.0 to 10.0, -33.86 to 151.21)
        for ((lat, lng) in anchors) {
            for (meters in listOf(0.0, 1.0, 25.0, 50.0, 150.0, 1_000.0, 100_000.0)) {
                for (bearing in listOf(0.0, 90.0, 180.0, 270.0, 45.0)) {
                    val (toLat, toLng) = offsetLatLng(lat to lng, meters, bearing)
                    val a = Fix(lat, lng, 10f, 0L)
                    val b = Fix(toLat, toLng, 10f, 1_000L)
                    cases += linkedMapOf(
                        "aLat" to lat, "aLng" to lng, "bLat" to toLat, "bLng" to toLng,
                        "meters" to LocationFilter.distanceMeters(a, b),
                    )
                }
            }
        }
        check(cases.count { (it["meters"] as Double) > 0.0 } >= cases.size - anchors.size * 5) {
            "거리 케이스 대부분이 0 이다 — offsetLatLng 가 안 움직였다"
        }
        return cases
    }

    // ==================================================================
    // 7. MovementTrailFilter — 5초 간격, 50m 정확도, 속도 근거, 변위 증거
    // ==================================================================

    @Test
    fun `골든 - MovementTrailFilter`() {
        val payload = linkedMapOf(
            "constants" to linkedMapOf<String, Any?>(
                "minIntervalMillis" to MovementTrailFilter.MIN_INTERVAL_MILLIS,
                "maxAccuracyMeters" to MovementTrailFilter.MAX_ACCURACY_METERS.toDouble(),
                "displacementEvidenceMeters" to MovementTrailFilter.DISPLACEMENT_EVIDENCE_METERS,
                "displacementEvidenceNoiseMultiplier" to MovementTrailFilter.DISPLACEMENT_EVIDENCE_NOISE_MULTIPLIER,
                "movingSpeedMps" to MovementTrailFilter.MOVING_SPEED_MPS.toDouble(),
                "minDisplacementMeters" to MovementTrailFilter.MIN_DISPLACEMENT_METERS,
                "speedTrustMaxAccuracyMeters" to MovementTrailFilter.SPEED_TRUST_MAX_ACCURACY_METERS.toDouble(),
                "minConfidentSpeedMps" to MovementTrailFilter.MIN_CONFIDENT_SPEED_MPS.toDouble(),
                "minSpeedEvidenceDisplacementMeters" to MovementTrailFilter.MIN_SPEED_EVIDENCE_DISPLACEMENT_METERS,
            ),
            "shouldRecord" to generateShouldRecord(),
            "displacementEvidence" to generateDisplacementEvidence(),
        )
        writeGoldenIfPresent("movementTrailFilter", toJson(payload))
    }

    private fun generateShouldRecord(): List<Map<String, Any?>> {
        val baseLat = 37.5665
        val baseLng = 126.9780
        val t0 = 1_700_000_000_000L
        val cases = mutableListOf<Map<String, Any?>>()

        fun fixJson(f: Fix?): Any? = f?.let {
            linkedMapOf(
                "lat" to it.lat, "lng" to it.lng, "accuracy" to it.accuracy.toDouble(),
                "speed" to it.speed.toDouble(), "at" to it.at, "speedAccuracy" to it.speedAccuracy.toDouble(),
            )
        }

        fun add(name: String, previous: Fix?, candidate: Fix, moving: Boolean) {
            // Float 산술과 Double 산술이 갈리는 입력은 골든에 싣지 않는다(1단계 판정 기록 3).
            if (candidate.speedAccuracy.isFinite()) {
                val f = (candidate.speed - candidate.speedAccuracy) >= MovementTrailFilter.MIN_CONFIDENT_SPEED_MPS
                val d = (candidate.speed.toDouble() - candidate.speedAccuracy.toDouble()) >=
                    MovementTrailFilter.MIN_CONFIDENT_SPEED_MPS.toDouble()
                check(f == d) {
                    "$name: 속도 근거가 Float(${f})와 Double(${d})에서 갈린다 — 이 입력은 두 언어가 같은 답을 못 낸다"
                }
            }
            cases += linkedMapOf(
                "name" to name, "previous" to fixJson(previous), "candidate" to fixJson(candidate),
                "reportedMoving" to moving,
                "shouldRecord" to MovementTrailFilter.shouldRecord(previous, candidate, moving),
            )
        }

        fun at(meters: Double, afterMillis: Long, accuracy: Float, speed: Float = 0f, speedAccuracy: Float = Float.POSITIVE_INFINITY): Fix {
            val (lat, lng) = offsetLatLng(baseLat to baseLng, meters, 90.0)
            return Fix(lat, lng, accuracy, t0 + afterMillis, speed, speedAccuracy)
        }

        val previous = Fix(baseLat, baseLng, 5f, t0, 0f, Float.POSITIVE_INFINITY)

        // reportedMoving = false 는 언제나 false.
        add("not_moving", previous, at(100.0, 10_000L, 5f), moving = false)
        // previous == null 은 정확도만 본다.
        listOf(49.5f, 50f, 50.5f).forEach { add("first_accuracy_$it", null, at(0.0, 0L, it), moving = true) }
        // 5초 간격 양옆.
        listOf(4_999L, 5_000L, 5_001L).forEach { add("interval_$it", previous, at(10.0, it, 5f), moving = true) }
        // 3m 최소 변위 양옆(속도 근거 없음).
        listOf(2.0, 3.0, 4.0).forEach { add("displacement_$it", previous, at(it, 10_000L, 5f), moving = true) }
        // 속도 근거 갈래: 정확도 15m 양옆 × 속도오차 유무.
        listOf(14.5f, 15f, 15.5f).forEach {
            add("speed_trust_accuracy_$it", Fix(baseLat, baseLng, it, t0), at(3.0, 10_000L, it, speed = 1.5f, speedAccuracy = 0.5f), moving = true)
        }
        // 속도 정확도가 없을 때의 옛 문턱(0.7f) 양옆.
        listOf(0.5f, 0.75f, 1.0f).forEach {
            add("legacy_speed_$it", Fix(baseLat, baseLng, 5f, t0), at(3.0, 10_000L, 5f, speed = it), moving = true)
        }
        // 순간이동(candidate.speed 자체가 55.6 초과 / impliedSpeed 초과).
        add("speed_over_max", previous, at(10.0, 10_000L, 5f, speed = 60f), moving = true)
        add("implied_over_max", previous, at(600_000.0, 10_000L, 5f), moving = true)

        fun recordOf(name: String) = cases.first { it["name"] == name }["shouldRecord"]
        check(recordOf("interval_4999") == false && recordOf("interval_5000") == true) { "5초 간격 경계가 안 갈린다" }
        check(recordOf("displacement_2.0") == false && recordOf("displacement_4.0") == true) { "3m 변위 경계가 안 갈린다" }
        check(recordOf("first_accuracy_50.0") == true && recordOf("first_accuracy_50.5") == false) { "50m 정확도 경계가 안 갈린다" }
        return cases
    }

    private fun generateDisplacementEvidence(): List<Map<String, Any?>> {
        val baseLat = 37.5665
        val baseLng = 126.9780
        val t0 = 1_700_000_000_000L
        val cases = mutableListOf<Map<String, Any?>>()

        fun add(name: String, previous: Fix?, candidate: Fix) {
            cases += linkedMapOf(
                "name" to name,
                "previous" to previous?.let { linkedMapOf("lat" to it.lat, "lng" to it.lng, "accuracy" to it.accuracy.toDouble(), "at" to it.at) },
                "candidate" to linkedMapOf("lat" to candidate.lat, "lng" to candidate.lng, "accuracy" to candidate.accuracy.toDouble(), "at" to candidate.at),
                "isEvidence" to MovementTrailFilter.isDisplacementEvidence(previous, candidate),
            )
        }

        fun moved(meters: Double, accuracy: Float, afterMillis: Long = 60_000L): Fix {
            val (lat, lng) = offsetLatLng(baseLat to baseLng, meters, 90.0)
            return Fix(lat, lng, accuracy, t0 + afterMillis)
        }

        add("no_previous", null, moved(100.0, 5f))
        // 고정 문턱 50m 양옆(오차가 작아 hypot × 1.5 가 50 을 못 넘는다: hypot(5,5)*1.5 ≈ 10.6).
        listOf(49.0, 50.0, 51.0).forEach { add("fixed_threshold_$it", Fix(baseLat, baseLng, 5f, t0), moved(it, 5f)) }
        // 잡음 비례 문턱: 오차 40m 두 점 → hypot(40,40)*1.5 ≈ 84.9. 양옆을 쓴다.
        listOf(80.0, 90.0).forEach { add("noise_threshold_$it", Fix(baseLat, baseLng, 40f, t0), moved(it, 40f)) }
        // 정확도 상한(LocationFilter 50m) 양옆 — 한쪽만 나빠도 거절이다.
        listOf(49.5f, 50f, 50.5f).forEach {
            add("prev_accuracy_$it", Fix(baseLat, baseLng, it, t0), moved(200.0, 5f))
            add("cand_accuracy_$it", Fix(baseLat, baseLng, 5f, t0), moved(200.0, it))
        }
        // elapsed <= 0, 순간이동.
        add("elapsed_zero", Fix(baseLat, baseLng, 5f, t0), moved(200.0, 5f, afterMillis = 0L))
        add("teleport", Fix(baseLat, baseLng, 5f, t0), moved(200.0, 5f, afterMillis = 1L))

        fun evidenceOf(name: String) = cases.first { it["name"] == name }["isEvidence"]
        check(evidenceOf("fixed_threshold_49.0") == false && evidenceOf("fixed_threshold_51.0") == true) { "고정 50m 문턱이 안 갈린다" }
        check(evidenceOf("noise_threshold_80.0") == false && evidenceOf("noise_threshold_90.0") == true) { "잡음 비례 문턱이 안 갈린다" }
        check(evidenceOf("cand_accuracy_50.0") == true && evidenceOf("cand_accuracy_50.5") == false) { "정확도 상한이 안 갈린다" }
        return cases
    }
```

> `offsetLatLng` 이 이 파일에 이미 있는지 `grep -n "private fun offsetLatLng" app/src/test/java/com/kidcare/family/logic/GoldenFileWriterTest.kt` 로 확인한다. 없으면 `generateRoutePathRefiner` 가 쓰는 것과 같은 이름의 도우미가 다른 모양일 수 있다 — 그 파일에 있는 것을 그대로 쓰고, 시그니처가 다르면 호출부를 맞춘다.

생성하고 결과를 본다.

```bash
cd /Users/com/work/KidCare
export PATH="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:$PATH"
./gradlew :app:testDebugUnitTest --tests 'com.kidcare.family.logic.GoldenFileWriterTest'
python3 - <<'EOF'
import json
for n in ("locationFilter", "movementTrailFilter"):
    d = json.load(open(f"ios/KidCareTests/golden/{n}.json"))
    print(n, {k: (len(v) if isinstance(v, list) else v) for k, v in d.items()})
EOF
git diff --stat 4bda965..HEAD -- app     # 아직 커밋 전이면 git status --short app 으로 본다: 그 한 파일만
```

- [ ] **Step 8: 스위프트 골든 대조를 더한다**

`ios/KidCareTests/GoldenComparisonTests.swift`:

1. `골든_리소스가_번들에_있다` 에 두 줄을 더한다.

```swift
        let locationFilter = try readObject("locationFilter")
        #expect((locationFilter["cases"] as? [[String: Any]])?.count ?? 0 >= 25, "locationFilter.cases 케이스가 너무 적다")
        #expect((locationFilter["distances"] as? [[String: Any]])?.count ?? 0 >= 100, "locationFilter.distances 케이스가 너무 적다")

        let movementTrailFilter = try readObject("movementTrailFilter")
        #expect((movementTrailFilter["shouldRecord"] as? [[String: Any]])?.count ?? 0 >= 20, "movementTrailFilter.shouldRecord 케이스가 너무 적다")
        #expect((movementTrailFilter["displacementEvidence"] as? [[String: Any]])?.count ?? 0 >= 12, "movementTrailFilter.displacementEvidence 케이스가 너무 적다")
```

2. 파일 끝에 절 하나를 더한다.

```swift
    // ==================================================================
    // 6. LocationFilter — 상수·판정·거리
    // ==================================================================

    /// 골든 파일에 실린 **코틀린이 실제로 들고 있는 상수**를 읽어 `Fix` 로 되돌린다.
    private func fix(_ any: Any?) -> Fix? {
        guard let d = any as? [String: Any] else { return nil }
        return Fix(
            lat: double(d["lat"]), lng: double(d["lng"]),
            accuracy: double(d["accuracy"]), at: int64(d["at"]),
            speed: d["speed"].map(double) ?? 0,
            speedAccuracy: d["speedAccuracy"].map(double) ?? .infinity
        )
    }

    /// **이 테스트가 설계서 §4 상수 대조표를 사람 대신 지킨다.** 코틀린 `Float` 상수를 스위프트에
    /// 십진 리터럴로 옮기면(0.35f → 0.35) 문턱이 미세하게 높아져 경계에서 두 폰이 갈린다
    /// (1단계 판정 기록 2). 비트까지 같은지 본다 — 허용치를 두지 않는다.
    @Test("LocationFilter 상수가 코틀린과 비트까지 같다")
    func 위치필터_상수가_같다() throws {
        let c = try #require(try readObject("locationFilter")["constants"] as? [String: Any])
        #expect(LocationFilter.maxAccuracyMeters == double(c["maxAccuracyMeters"]))
        #expect(LocationFilter.fallbackMaxAccuracyMeters == double(c["fallbackMaxAccuracyMeters"]))
        #expect(LocationFilter.staleFallbackMillis == int64(c["staleFallbackMillis"]))
        #expect(LocationFilter.minMoveMeters == double(c["minMoveMeters"]))
        #expect(LocationFilter.maxSpeedMps == double(c["maxSpeedMps"]))
        #expect(LocationFilter.heartbeatMillis == int64(c["heartbeatMillis"]))
    }

    @Test("LocationFilter.decide 가 안드로이드와 같은 판정을 낸다")
    func 위치필터_판정_대조() throws {
        for 사례 in try #require(try readObject("locationFilter")["cases"] as? [[String: Any]]) {
            let name = string(사례["name"])
            let expected = try #require(Decision(rawValue: string(사례["decision"])), "\(name): 모르는 판정 이름")
            let actual = LocationFilter.decide(previous: fix(사례["previous"]), candidate: try #require(fix(사례["candidate"])))
            #expect(actual == expected, "\(name)")
        }
    }

    @Test("LocationFilter.distanceMeters 가 안드로이드와 같다 (허용치 1e-9m)")
    func 거리_대조() throws {
        for 사례 in try #require(try readObject("locationFilter")["distances"] as? [[String: Any]]) {
            let a = Fix(lat: double(사례["aLat"]), lng: double(사례["aLng"]), accuracy: 10, at: 0)
            let b = Fix(lat: double(사례["bLat"]), lng: double(사례["bLng"]), accuracy: 10, at: 1_000)
            let expected = double(사례["meters"])
            let actual = LocationFilter.distanceMeters(a, b)
            // 라디안 변환식이 자바와 한 비트 다를 수 있다(1단계 판정 기록 5). 1e-9m 는 0.1nm 라
            // 로직이 실제로 갈렸으면 절대 이 안에 못 들어온다.
            #expect(abs(actual - expected) < 1e-9, "(\(a.lat),\(a.lng))→(\(b.lat),\(b.lng)) 실제=\(actual) 기대=\(expected)")
        }
    }

    // ==================================================================
    // 7. MovementTrailFilter
    // ==================================================================

    @Test("MovementTrailFilter 상수가 코틀린과 비트까지 같다")
    func 경로필터_상수가_같다() throws {
        let c = try #require(try readObject("movementTrailFilter")["constants"] as? [String: Any])
        #expect(MovementTrailFilter.minIntervalMillis == int64(c["minIntervalMillis"]))
        #expect(MovementTrailFilter.maxAccuracyMeters == double(c["maxAccuracyMeters"]))
        #expect(MovementTrailFilter.displacementEvidenceMeters == double(c["displacementEvidenceMeters"]))
        #expect(MovementTrailFilter.displacementEvidenceNoiseMultiplier == double(c["displacementEvidenceNoiseMultiplier"]))
        #expect(MovementTrailFilter.movingSpeedMps == double(c["movingSpeedMps"]))
        #expect(MovementTrailFilter.minDisplacementMeters == double(c["minDisplacementMeters"]))
        #expect(MovementTrailFilter.speedTrustMaxAccuracyMeters == double(c["speedTrustMaxAccuracyMeters"]))
        #expect(MovementTrailFilter.minConfidentSpeedMps == double(c["minConfidentSpeedMps"]))
        #expect(MovementTrailFilter.minSpeedEvidenceDisplacementMeters == double(c["minSpeedEvidenceDisplacementMeters"]))
    }

    @Test("MovementTrailFilter.shouldRecord 가 안드로이드와 같다")
    func 경로필터_기록_대조() throws {
        for 사례 in try #require(try readObject("movementTrailFilter")["shouldRecord"] as? [[String: Any]]) {
            let actual = MovementTrailFilter.shouldRecord(
                previous: fix(사례["previous"]),
                candidate: try #require(fix(사례["candidate"])),
                reportedMoving: bool(사례["reportedMoving"])
            )
            #expect(actual == bool(사례["shouldRecord"]), "\(string(사례["name"]))")
        }
    }

    @Test("MovementTrailFilter.isDisplacementEvidence 가 안드로이드와 같다")
    func 경로필터_변위증거_대조() throws {
        for 사례 in try #require(try readObject("movementTrailFilter")["displacementEvidence"] as? [[String: Any]]) {
            let actual = MovementTrailFilter.isDisplacementEvidence(
                previous: fix(사례["previous"]),
                candidate: try #require(fix(사례["candidate"]))
            )
            #expect(actual == bool(사례["isEvidence"]), "\(string(사례["name"]))")
        }
    }
```

- [ ] **Step 9: 통과 확인**

```bash
cd /Users/com/work/KidCare/ios
xcodegen generate
xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: 전부 통과. 테스트 수가 M + (옮긴 테스트 수) + 7 이다. **기존 `RoutePathRefinerTests`·`GoldenComparisonTests.경로_다듬기_대조` 가 그대로 초록**이어야 한다 — 그것이 판정 기록 4(사본 삭제)의 검사다.

- [ ] **Step 10: 골든이 정말 무는지 일부러 망가뜨려 확인한다**

하나씩 바꾸고 **골든 테스트만** 돌린 뒤 되돌린다. 넷 다 빨개져야 한다. 하나라도 초록이면 그 골든은 스윕이 아니다 — 멈추고 보고한다.

| # | 어디를 | 어떻게 | 빨개져야 하는 테스트 |
|---|---|---|---|
| 1 | `LocationFilter.maxAccuracyMeters` | `50` → `60` | `위치필터_상수가_같다`, `위치필터_판정_대조` |
| 2 | `LocationFilter.decide` | 완화 확정(`if accuracyVerdict == .uploadStaleFallback`) 줄을 순간이동 검사 **위로** 옮긴다 | `위치필터_판정_대조`(`stale_but_teleport`) |
| 3 | `MovementTrailFilter.movingSpeedMps` | `0.699999988079071` → `0.7` | `경로필터_상수가_같다` |
| 4 | `MovementTrailFilter.shouldRecord` | 마지막 줄 `distance >= minDisplacementMeters` → `distance > minDisplacementMeters` | `경로필터_기록_대조`(`displacement_3.0`) |

```bash
cd /Users/com/work/KidCare/ios
xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/GoldenComparisonTests 2>&1 | tail -20
git diff --stat ios/KidCare/Logic    # 되돌린 뒤: 이 Task 가 의도한 변경만 남아야 한다
```

- [ ] **Step 11: 커밋** (공통 절차 B)

```
iOS 아이 1단계 Task 1: 위치 판정과 경로점 선별을 옮기고 골든으로 묶는다
```

---
### Task 2: 이동 판정기 · 구간 요약 · 하루 CSV — 나머지 순수 로직 셋

**끝나면 `Logic/` 이 아이 역할에 필요한 순수 로직 다섯을 전부 갖는다.** 점 시퀀스를 먹이면 판정기의 상태 전이가 안드로이드와 한 점도 안 갈리고, 같은 점 목록에서 같은 머무름·이동 구간이 나오며(가중 평균 `nameLat`/`nameLng` 포함), 2000개 상한 LTTB 솎기와 CSV 왕복이 같다. 화면 변화는 없다.

**Files:**
- Create: `ios/KidCare/Logic/AdaptiveMovementDetector.swift`, `ios/KidCare/Logic/SegmentBuilder.swift`, `ios/KidCare/Logic/TrailCodec.swift`
- Modify: `ios/KidCare/Logic/Segment.swift`(`nameLat`/`nameLng` + 명시적 `init`, 머리 주석 :18-27 수정)
- Modify: `app/src/test/java/com/kidcare/family/logic/GoldenFileWriterTest.kt`(`@Test` 셋 + `generate*` 셋)
- Create(생성물): `ios/KidCareTests/golden/adaptiveMovementDetector.json`, `.../segmentBuilder.json`, `.../trailCodec.json`
- Test: `ios/KidCareTests/AdaptiveMovementDetectorTests.swift`, `SegmentBuilderTests.swift`, `TrailCodecTests.swift`(신규), `GoldenComparisonTests.swift`(수정), `LogicTypesTests.swift`(수정)

**Interfaces:**
- Produces: `AdaptiveMovementState`(`.fastProbe`/`.slowProbe`/`.moving`, `rawValue` 는 코틀린 이름), `AdaptiveMovementUpdate(state:promotionBuffer:)`, `AdaptiveMovementDetector`(`state`, `reset(fast:)`, `onFix(_:)`), `SegmentBuilder.build(points:)`, `TrailCodec.maxPoints`·`encodeLine(_:)`·`decode(_:)`·`capped(_:)`, `Segment.nameLat`/`nameLng`
- Consumes: `LocationFilter.distanceMeters`·`maxSpeedMps`·`fallbackMaxAccuracyMeters`(Task 1)

**정본:** `logic/AdaptiveMovementDetector.kt` 전체(212줄), `logic/SegmentBuilder.kt` 전체(185줄), `logic/TrailCodec.kt` 전체(139줄). 포팅할 테스트는 같은 이름의 `*Test.kt` 셋(147 + 249 + 90줄).

- [ ] **Step 1: 안드로이드 테스트 셋을 옮겨 빨갛게 둔다**

셋 다 `@Test` 를 하나도 빼지 않고 옮긴다. `SegmentBuilderTest.kt` 는 `nameLat`/`nameLng` 를 확인하는 테스트를 이미 갖고 있으니 그것도 그대로 옮긴다 — 그 테스트가 Swift `Segment` 의 새 필드를 요구하는 첫 사용처다.

```swift
import Foundation
import Testing
@testable import KidCare

/// 정본은 `app/src/test/.../SegmentBuilderTest.kt`.
struct SegmentBuilderTests {

    private func fix(_ afterSeconds: Int64, meters: Double = 0, accuracy: Double = 10) -> Fix {
        Fix(
            lat: 37.5665 + meters / 111_320.0,
            lng: 126.9780,
            accuracy: accuracy,
            at: 1_700_000_000_000 + afterSeconds * 1_000
        )
    }

    @Test("반경 40m 안에 5분 이상 있으면 머무름이다")
    func 머무름_기본() {
        let points = (0...6).map { fix(Int64($0) * 60, meters: Double($0) * 3) }
        let segments = SegmentBuilder.build(points: points)
        #expect(segments.count == 1)
        #expect(segments.first?.type == .stay)
    }

    @Test("이름을 물어볼 좌표는 오차로 가중한 평균이다 — 나쁜 점 하나가 이름을 정하면 안 된다")
    func 이름_좌표는_가중평균() {
        // 정확한 점 다섯과 도착 순간의 나쁜 점 하나. lat 평균은 나쁜 점에 끌려가지만
        // nameLat 은 1/오차² 가중이라 거의 안 움직인다(SegmentBuilder.kt:163-183).
        var points = (0...5).map { fix(Int64($0) * 60, meters: 0, accuracy: 5) }
        points.append(fix(360, meters: 35, accuracy: 50))
        let stay = try? #require(SegmentBuilder.build(points: points).first)
        #expect(stay?.type == .stay)
        #expect((stay!.nameLat - points[0].lat) < (stay!.lat - points[0].lat))
    }

    // … SegmentBuilderTest.kt 의 나머지 @Test 를 전부 옮긴다.
    // 옮길 때 확인할 것: `Segment` 의 `type` 비교는 `.stay`/`.move` 이고,
    // `SegmentType.STAY.name` 에 해당하는 문자열은 `Documents.swift` 의 SegmentDoc 쪽에서만 쓴다.
}
```

`AdaptiveMovementDetectorTests.swift` 와 `TrailCodecTests.swift` 도 같은 방식이다. `TrailCodecTest.kt` 의 왕복 테스트에 **한 줄을 더한다** — 설계서 §4.5 가 요구한 것이다.

```swift
    @Test("encodeLine 은 자기 자신이 decode 로 되돌아온다 — 코틀린과 글자가 같을 필요는 없다")
    func 왕복() {
        // Kotlin 의 Double.toString/Float.toString 과 Swift 의 문자열 변환은 같은 값에 다른 글자를
        // 낼 수 있다(설계서 §4.5). 두 플랫폼이 같은 파일을 읽는 일은 없으므로 계약은 "글자가 같다"가
        // 아니라 "내가 쓴 것을 내가 그대로 읽는다"다. 골든 대조도 문자열이 아니라 decode 한 값으로 한다.
        let original = Fix(lat: 37.5665, lng: 126.9780, accuracy: 12.5, at: 1_700_000_000_123, speed: 1.25)
        let back = try? #require(TrailCodec.decode(TrailCodec.encodeLine(original)).first)
        #expect(back?.lat == original.lat)
        #expect(back?.lng == original.lng)
        #expect(back?.accuracy == original.accuracy)
        #expect(back?.speed == original.speed)
        #expect(back?.at == original.at)
    }
```

- [ ] **Step 2: 실패를 확인한다**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/AdaptiveMovementDetectorTests -only-testing:KidCareTests/SegmentBuilderTests -only-testing:KidCareTests/TrailCodecTests`
Expected: 컴파일 실패(세 타입과 `Segment.nameLat` 이 없다).

- [ ] **Step 3: `Segment` 에 `nameLat`/`nameLng` 를 더한다**

`ios/KidCare/Logic/Segment.swift` 의 머리 주석 :18-27("코틀린의 `nameLat`/`nameLng` 는 일부러 안 옮겼다" 문단)을 아래로 바꾸고, 필드 둘과 **명시적 `init`** 을 더한다. memberwise 초기화는 기본값을 못 받으므로 명시적 `init` 이 아니면 기존 `Segment(...)` 호출이 전부 깨진다(설계서 §3.2).

```swift
    /// **이름을 물어볼 좌표.** 역지오코딩(2단계 `Child/PlaceNamer`)에만 쓴다. 정본은
    /// `SegmentBuilder.kt:32-33`·`staySegment`(:163-183).
    ///
    /// 보호자 앱만 있던 시절에는 **일부러 뺐다** — 서버 문서 `SegmentDoc` 에는 이 필드가 없고
    /// (아이 폰은 계산의 **결과**인 `placeName` 만 올린다) 보호자는 원본 점을 가진 적이 없어
    /// 채울 수도 다시 계산할 수도 없었다. 아이 역할이 `SegmentBuilder` 를 가져오면서 자리가 생겼다.
    ///
    /// `lat`/`lng` 와 따로 두는 이유는 코틀린 주석 그대로다: 저 둘은 지도에 찍고 선을 잇는 좌표라
    /// 의미를 바꾸면 화면·타임라인·경로선이 전부 따라 바뀐다. 이름은 좌표 하나를 건물 이름으로
    /// 바꾸는 일이라 **오차에 훨씬 민감하다** — 단순 평균은 도착 순간의 나쁜 fix 한 개를 그대로
    /// 끌어안아 머무름 전체가 옆 건물 이름을 달 수 있다. 그래서 이 좌표는 **오차로 가중한 평균**
    /// 이다(가중치 = 1/오차²). `.move` 구간에서는 `lat`/`lng` 와 같은 값이다.
    let nameLat: Double
    let nameLng: Double

    /// `nameLat`/`nameLng` 를 **안 넘기면 `lat`/`lng` 가 된다.** 이 기본값 덕분에 보호자 쪽의
    /// 기존 `Segment(...)` 호출(타임라인 요약·미리보기)이 한 곳도 안 바뀐다 — memberwise
    /// 초기화는 기본값을 못 받으므로 명시적 init 이 필요하다(설계서 §3.2).
    init(
        type: SegmentType,
        startAt: Int64,
        endAt: Int64,
        lat: Double,
        lng: Double,
        distanceMeters: Double,
        pointCount: Int,
        nameLat: Double? = nil,
        nameLng: Double? = nil
    ) {
        self.type = type
        self.startAt = startAt
        self.endAt = endAt
        self.lat = lat
        self.lng = lng
        self.distanceMeters = distanceMeters
        self.pointCount = pointCount
        self.nameLat = nameLat ?? lat
        self.nameLng = nameLng ?? lng
    }
```

`LogicTypesTests.swift` 에 한 줄을 더한다.

```swift
    @Test("Segment 의 이름 좌표는 안 넘기면 lat/lng 다 — 보호자 쪽 기존 호출부가 안 깨지는 근거")
    func segment_이름좌표_기본값() {
        let s = Segment(type: .move, startAt: 0, endAt: 1, lat: 37.5, lng: 127.0, distanceMeters: 10, pointCount: 2)
        #expect(s.nameLat == 37.5 && s.nameLng == 127.0)
    }
```

- [ ] **Step 4: `AdaptiveMovementDetector` 를 쓴다**

`ios/KidCare/Logic/AdaptiveMovementDetector.swift`. 코틀린 `ArrayDeque<Fix>` 는 Swift `[Fix]` 로 옮긴다(`removeFirst()` 가 O(n) 이지만 표본이 30~60초 창이라 길어야 십여 개다).

```swift
import Foundation

/// 정본은 코틀린 `AdaptiveMovementState`. `rawValue` 가 코틀린 이름인 이유는 `Decision` 과 같다 —
/// 골든 파일이 그 이름을 싣는다.
enum AdaptiveMovementState: String, Equatable {
    case fastProbe = "FAST_PROBE"
    case slowProbe = "SLOW_PROBE"
    case moving = "MOVING"
}

struct AdaptiveMovementUpdate: Equatable {
    let state: AdaptiveMovementState
    /// 이동 확정 직전의 점들. 경로 시작 부분이 잘리지 않도록 확정 시 한 번만 돌려준다.
    let promotionBuffer: [Fix]

    init(state: AdaptiveMovementState, promotionBuffer: [Fix] = []) {
        self.state = state
        self.promotionBuffer = promotionBuffer
    }
}

/// 활동 인식 결과를 바로 이동으로 믿지 않고 실제 좌표·속도 증거로 확인한다.
/// 정본은 안드로이드 `logic/AdaptiveMovementDetector.kt`.
///
/// **아이폰에서는 이 판정기가 안드로이드보다 더 중요하다.** 안드로이드는 활동 인식(Activity
/// Recognition) 전환을 한 비트 더 갖고 있지만 아이폰은 v1 에서 CoreMotion 을 안 쓴다
/// (설계서 §17 열린 질문 5). 안드로이드도 활동 인식 권한이 없으면 이 판정기 하나로 도는 것이
/// 이미 검증된 갈래다(`ConditionWatcher.kt:47-48`).
///
/// `Sendable` 이 아니다 — 상태를 가진 클래스이고 `@MainActor` 인 `TrackingCoordinator` 안에서만
/// 산다. 격리를 넘길 일이 없으므로 `@unchecked Sendable` 을 붙이지 않는다(Global Constraints).
final class AdaptiveMovementDetector {

    /// `:175`. 30m 로 조였더니 버스·번화가의 30~50m 오차 구간에서 점을 전부 버려 이동 확정에
    /// 영영 못 올라갔다 — 판정 문턱들이 오차에 비례해 커지므로 상한을 올려도 정지 흔들림이
    /// 이동으로 승격되지는 않는다. `MovementTrailFilter` 와 같은 값.
    static let maxAccuracyMeters: Double = 50
    /// `:176`.
    static let fastProbeMillis: Int64 = 30_000
    /// `:177`.
    static let stopConfirmMillis: Int64 = 60_000
    /// `:178`.
    static let minConfirmMillis: Int64 = 10_000
    /// `:179`.
    static let minConfirmPoints = 3
    /// `:180` (`15f`).
    static let speedTrustMaxAccuracyMeters: Double = 15
    /// `:181` 의 `0.35f` 확장값(1단계 판정 기록 2).
    static let minConfidentSpeedMps: Double = 0.3499999940395355
    /// `:182`.
    static let minSpeedDisplacementMeters: Double = 3.0
    /// `:193`. 30m 에서 15m 로 내렸다 — 30m 이던 시절에는 **걷는 아이가 절대 통과하지 못했다**
    /// (확인 창 30초 × 보행 1.0~1.3m/s = 30~39m 인데 오차 15m 면 문턱이 42m 가 됐다).
    static let minNetDisplacementMeters: Double = 15.0
    /// `:194`.
    static let slowProbeMinDisplacementMeters: Double = 15.0
    /// `:195`.
    static let stopRadiusMeters: Double = 15.0
    /// `:209`. 2.0 에서 1.0 으로 내렸다 — 두 점의 변위 잡음은 표준편차가 `hypot` 이므로 1.0 배가
    /// 곧 1-시그마다. 2-시그마는 보행 속도로 도달할 수 없는 거리가 된다.
    static let noiseMultiplier: Double = 1.0
    /// `:210`.
    static let minProgressRatio: Double = 0.6

    private var samples: [Fix] = []
    private var fastProbeStartedAt: Int64?
    private(set) var state: AdaptiveMovementState = .fastProbe

    func reset(fast: Bool = true) {
        samples.removeAll()
        fastProbeStartedAt = nil
        state = fast ? .fastProbe : .slowProbe
    }

    func onFix(_ candidate: Fix) -> AdaptiveMovementUpdate {
        guard hasValidCoordinatesAndTime(candidate) else { return AdaptiveMovementUpdate(state: state) }
        if state == .fastProbe, fastProbeStartedAt == nil { fastProbeStartedAt = candidate.at }
        if !isUsable(candidate) {
            if state == .fastProbe, let startedAt = fastProbeStartedAt,
               candidate.at - startedAt >= Self.fastProbeMillis {
                reset(fast: false)
            }
            return AdaptiveMovementUpdate(state: state)
        }
        if let last = samples.last, candidate.at <= last.at { return AdaptiveMovementUpdate(state: state) }

        switch state {
        case .fastProbe: return onFastProbe(candidate)
        case .slowProbe: return onSlowProbe(candidate)
        case .moving: return onMoving(candidate)
        }
    }

    private func onFastProbe(_ candidate: Fix) -> AdaptiveMovementUpdate {
        samples.append(candidate)
        trimBefore(candidate.at - Self.fastProbeMillis)

        if hasConfirmedMovement() {
            state = .moving
            fastProbeStartedAt = nil
            return AdaptiveMovementUpdate(state: state, promotionBuffer: samples)
        }
        if let startedAt = fastProbeStartedAt, candidate.at - startedAt >= Self.fastProbeMillis {
            keepOnly(candidate)
            state = .slowProbe
            fastProbeStartedAt = nil
        }
        return AdaptiveMovementUpdate(state: state)
    }

    private func onSlowProbe(_ candidate: Fix) -> AdaptiveMovementUpdate {
        let previous = samples.last
        keepOnly(candidate)
        if let previous, hasMovementHint(previous, candidate) {
            samples = [previous, candidate]
            state = .fastProbe
            fastProbeStartedAt = candidate.at
        }
        return AdaptiveMovementUpdate(state: state)
    }

    private func onMoving(_ candidate: Fix) -> AdaptiveMovementUpdate {
        samples.append(candidate)
        trimBefore(candidate.at - Self.stopConfirmMillis)

        guard let first = samples.first else { return AdaptiveMovementUpdate(state: state) }
        if candidate.at - first.at >= Self.stopConfirmMillis, looksStationary() {
            keepOnly(candidate)
            state = .slowProbe
        }
        return AdaptiveMovementUpdate(state: state)
    }

    /// `:102-120`.
    private func hasConfirmedMovement() -> Bool {
        if samples.count < Self.minConfirmPoints { return false }
        let points = samples
        let first = points[0]
        let last = points[points.count - 1]
        if last.at - first.at < Self.minConfirmMillis { return false }

        let recentSpeedEvidence = points.suffix(2).allSatisfy(Self.hasReliableWalkingSpeed)
        let recentDistance = LocationFilter.distanceMeters(points[points.count - 2], last)
        if recentSpeedEvidence, recentDistance >= Self.minSpeedDisplacementMeters { return true }

        let threshold = max(
            Self.minNetDisplacementMeters,
            hypot(first.accuracy, last.accuracy) * Self.noiseMultiplier
        )
        let penultimateDistance = LocationFilter.distanceMeters(first, points[points.count - 2])
        let netDistance = LocationFilter.distanceMeters(first, last)
        return penultimateDistance >= threshold * Self.minProgressRatio && netDistance >= threshold
    }

    /// `:122-136`.
    private func hasMovementHint(_ previous: Fix, _ candidate: Fix) -> Bool {
        let distance = LocationFilter.distanceMeters(previous, candidate)
        let elapsedSeconds = Double(candidate.at - previous.at) / 1_000.0
        if elapsedSeconds <= 0 || distance / elapsedSeconds > LocationFilter.maxSpeedMps { return false }
        if Self.hasReliableWalkingSpeed(candidate), distance >= Self.minSpeedDisplacementMeters { return true }
        let noise = max(
            Self.slowProbeMinDisplacementMeters,
            hypot(previous.accuracy, candidate.accuracy) * Self.noiseMultiplier
        )
        return distance >= noise
    }

    /// `:138-145`.
    private func looksStationary() -> Bool {
        let points = samples
        if points.contains(where: Self.hasReliableWalkingSpeed) { return false }
        guard let first = points.first else { return false }
        let maxDistance = points.map { LocationFilter.distanceMeters(first, $0) }.max() ?? 0
        let maxAccuracy = points.map(\.accuracy).max() ?? 0
        return maxDistance <= max(Self.stopRadiusMeters, maxAccuracy * Self.noiseMultiplier)
    }

    /// `:147-150`.
    private static func hasReliableWalkingSpeed(_ fix: Fix) -> Bool {
        fix.accuracy <= speedTrustMaxAccuracyMeters
            && fix.speedAccuracy.isFinite
            && fix.speed - fix.speedAccuracy >= minConfidentSpeedMps
    }

    /// `:152-155`.
    private func isUsable(_ fix: Fix) -> Bool {
        hasValidCoordinatesAndTime(fix)
            && fix.accuracy.isFinite && fix.accuracy >= 0 && fix.accuracy <= Self.maxAccuracyMeters
            && fix.speed <= LocationFilter.maxSpeedMps
    }

    /// `:157-159`.
    private func hasValidCoordinatesAndTime(_ fix: Fix) -> Bool {
        fix.at >= 0 && fix.lat.isFinite && fix.lng.isFinite
            && fix.lat >= -90 && fix.lat <= 90 && fix.lng >= -180 && fix.lng <= 180
    }

    /// `:161-163`. **`samples.count > 1` 조건이 중요하다** — 마지막 한 점은 아무리 오래돼도 남긴다.
    private func trimBefore(_ oldestAt: Int64) {
        while samples.count > 1, samples[0].at < oldestAt { samples.removeFirst() }
    }

    private func keepOnly(_ fix: Fix) {
        samples = [fix]
    }
}
```

- [ ] **Step 5: `SegmentBuilder` 와 `TrailCodec` 을 쓴다**

`ios/KidCare/Logic/SegmentBuilder.swift` — `SegmentBuilder.kt` 를 그대로 옮긴다. 옮길 때 틀리기 쉬운 네 곳을 적어 둔다.

- `build` 의 첫 필터 문턱은 `LocationFilter.fallbackMaxAccuracyMeters`(100m)지 `maxAccuracyMeters`(50m)가 **아니다**(`:84-92`). 50m 로 자르면 완화로 간신히 건진 점이 구간 계산에서 통째로 빠져 "지도 마커는 움직이는데 타임라인만 비는" 상태가 된다.
- `sortedBy { it.at }` 는 Swift 에서 `sorted { $0.at < $1.at }` 다. **안정 정렬이 아니어도 된다** — 같은 `at` 두 점의 순서는 코틀린도 보장하지 않으므로, 생성기가 같은 `at` 을 만들지 않게 한다(`check` 로 확인).
- `findStayRanges` 의 `outsideRun >= EXIT_CONFIRM_POINTS` 에서 `break` 하는 위치(`:116`)를 그대로 지킨다. 한 칸이라도 밀면 실내에서 6시간짜리 머무름이 수십 개로 쪼개진다.
- `staySegment` 의 가중치는 `1 / (a * a)`, `a = max(accuracy, 5.0)` 다(`:168-171`). **0 은 "완벽"이 아니라 "모름"**이라 5m 로 올려 친다.

`ios/KidCare/Logic/TrailCodec.swift` — `TrailCodec.kt` 를 그대로 옮긴다. 세 곳을 적어 둔다.

- `encodeLine` 은 `"\(fix.lat),\(fix.lng),\(fix.accuracy),\(fix.speed),\(fix.at)"` 다. **코틀린과 글자가 같을 필요가 없다**(설계서 §4.5) — 두 플랫폼이 같은 파일을 읽는 일이 없고, 골든 대조는 `decode` 한 값으로 한다.
- `decode` 는 `text.split(separator: "\n", omittingEmptySubsequences: false)` 로 줄을 나눈다. 코틀린 `lineSequence()` 는 `\r\n`·`\r` 도 줄바꿈으로 보지만 **우리가 쓰는 파일에는 `\n` 뿐**이고, 생성기도 `\n` 만 쓴다(`check` 로 확인한다).
- `capped` 의 LTTB 는 `Int` 나눗셈이 섞이면 조용히 갈린다. `bucketWidth` 는 `Double(points.count - 2) / Double(Self.maxPoints - 2)` 이고, `floor((Double(bucket) + 1) * bucketWidth)` 를 `Int(...)` 로 바꾼 뒤 `+1`, 그리고 `min(..., points.count)` / `min(..., points.count - 1)` 이다(`:88-111` 의 `coerceAtMost` 대상이 `size` 인지 `lastIndex` 인지 **한 줄씩 대조한다** — 여기가 이 파일에서 가장 틀리기 쉬운 자리다).

- [ ] **Step 6: 코틀린 생성기에 `@Test` 셋을 더한다**

`GoldenFileWriterTest.kt` 에 Task 1 과 같은 모양으로 더한다. 핵심만 적는다.

```kotlin
    // ==================================================================
    // 8. AdaptiveMovementDetector — 점 시퀀스를 통째로 먹이고 매 점의 상태를 기록한다
    // ==================================================================

    @Test
    fun `골든 - AdaptiveMovementDetector`() {
        val payload = linkedMapOf(
            "constants" to linkedMapOf<String, Any?>(
                "maxAccuracyMeters" to AdaptiveMovementDetector.MAX_ACCURACY_METERS.toDouble(),
                "fastProbeMillis" to AdaptiveMovementDetector.FAST_PROBE_MILLIS,
                "stopConfirmMillis" to AdaptiveMovementDetector.STOP_CONFIRM_MILLIS,
                "minConfirmMillis" to AdaptiveMovementDetector.MIN_CONFIRM_MILLIS,
                "minConfirmPoints" to AdaptiveMovementDetector.MIN_CONFIRM_POINTS,
                "speedTrustMaxAccuracyMeters" to AdaptiveMovementDetector.SPEED_TRUST_MAX_ACCURACY_METERS.toDouble(),
                "minConfidentSpeedMps" to AdaptiveMovementDetector.MIN_CONFIDENT_SPEED_MPS.toDouble(),
                "minSpeedDisplacementMeters" to AdaptiveMovementDetector.MIN_SPEED_DISPLACEMENT_METERS,
                "minNetDisplacementMeters" to AdaptiveMovementDetector.MIN_NET_DISPLACEMENT_METERS,
                "slowProbeMinDisplacementMeters" to AdaptiveMovementDetector.SLOW_PROBE_MIN_DISPLACEMENT_METERS,
                "stopRadiusMeters" to AdaptiveMovementDetector.STOP_RADIUS_METERS,
                "noiseMultiplier" to AdaptiveMovementDetector.NOISE_MULTIPLIER,
                "minProgressRatio" to AdaptiveMovementDetector.MIN_PROGRESS_RATIO,
            ),
            "cases" to generateAdaptiveMovement(),
        )
        writeGoldenIfPresent("adaptiveMovementDetector", toJson(payload))
    }

    private fun generateAdaptiveMovement(): List<Map<String, Any?>> {
        val cases = mutableListOf<Map<String, Any?>>()

        /** 점 목록을 통째로 먹이고 **매 점마다** 상태와 승격 버퍼 크기를 기록한다. */
        fun addCase(name: String, resetFast: Boolean, points: List<Fix>) {
            val detector = AdaptiveMovementDetector()
            detector.reset(fast = resetFast)
            val steps = points.map { p ->
                val u = detector.onFix(p)
                linkedMapOf<String, Any?>(
                    "state" to u.state.name,
                    "promotionBufferSize" to u.promotionBuffer.size,
                    "promotionBufferAts" to u.promotionBuffer.map { it.at },
                )
            }
            cases += linkedMapOf(
                "name" to name,
                "resetFast" to resetFast,
                "points" to points.map {
                    linkedMapOf<String, Any?>(
                        "lat" to it.lat, "lng" to it.lng, "accuracy" to it.accuracy.toDouble(),
                        "speed" to it.speed.toDouble(), "at" to it.at, "speedAccuracy" to it.speedAccuracy.toDouble(),
                    )
                },
                "steps" to steps,
            )
        }

        // 시나리오 목록(전부 만든다):
        //  - 걷는 아이: 30초 동안 1.2m/s 로 직선 이동 → MOVING 승격, 승격 버퍼가 비지 않는다
        //  - 제자리 흔들림: 오차 20m 안에서 무작위(고정 시드) → 끝까지 MOVING 이 안 된다
        //  - 확인 창(30초) 양옆: 29초·30초·31초에 마지막 점을 둔다
        //  - 최소 표본(3점)·최소 시간(10초) 양옆
        //  - 정지 확인(60초) 양옆: MOVING 에서 59초·60초·61초 동안 오차 반경 안에 머문다
        //  - 진행률 0.6 양옆: 중간 점을 문턱의 55%·60%·65% 지점에 둔다
        //  - 속도 근거 갈래: 정확도 15m 이하 + speedAccuracy 유한, 그리고 그 반대
        //  - 못 쓰는 점(오차 51m, 속도 60m/s, 위도 91, at 음수)이 섞여 들어올 때
        //  - 시각이 뒤로 가거나 같은 점(`candidate.at <= last.at`)
        //  - SLOW_PROBE 에서 hasMovementHint 로 FAST_PROBE 로 되올라가는 갈래
        //  - trimBefore 가 마지막 한 점은 남기는가(창보다 긴 공백 뒤의 점 하나)

        // 자체 점검: 승격이 **적어도 한 번은** 일어나야 하고, 흔들림 시나리오는 한 번도 안 일어나야 한다.
        val promoted = cases.filter { c ->
            @Suppress("UNCHECKED_CAST")
            (c["steps"] as List<Map<String, Any?>>).any { it["state"] == "MOVING" }
        }
        check(promoted.isNotEmpty()) { "어떤 시나리오도 MOVING 에 도달하지 못했다 — 생성기가 이동을 못 만든다" }
        check(promoted.size < cases.size) { "모든 시나리오가 MOVING 이다 — 흔들림 시나리오가 실제로 흔들리지 않는다" }
        return cases
    }
```

`골든 - SegmentBuilder` 와 `골든 - TrailCodec` 도 같은 모양이다. 담을 것은 설계서 §12.2 의 표 그대로다.

- `segmentBuilder.json` — `build(points)` 의 입력 점 목록과 출력 구간 전부(`type`·`startAt`·`endAt`·`lat`·`lng`·`distanceMeters`·`pointCount`·**`nameLat`·`nameLng`**). 40m 반경 양옆, 5분 최소 양옆, 연속 2점 이탈(1점만 튄 경우와 2점 연속), 오차 가중 평균(정확한 점들 + 나쁜 점 하나), 100m 초과 점 제외, 점이 0·1개, 같은 좌표만 하루 종일. `check`: 40m 안/밖 케이스가 각각 `STAY`/`MOVE` 를 내는지, 가중 평균 케이스에서 `nameLat != lat` 인지.
- `trailCodec.json` — `capped` 는 1999·2000·2001·5000개 입력의 **출력 인덱스 목록**을 적는다(점 전체를 다시 적으면 파일이 수 MB 가 된다). `decode` 는 깨진 줄·칸 수 오류·빈 줄·마지막 줄 잘림을 섞은 텍스트와 그 결과다. `check`: 2000 이하는 입력과 같은 개수, 2001 은 정확히 2000 개, 그리고 **`decode` 말뭉치에 자바 전용 숫자 표기(`1d`·`1f`·`0x1p3`)가 없는지**(판정 기록 3 의 사촌: `"1d".toDoubleOrNull()` 은 코틀린에서 1.0 이지만 Swift `Double("1d")` 는 nil 이다).

- [ ] **Step 7: 스위프트 골든 대조 여섯을 더한다**

Task 1 과 같은 모양으로 `GoldenComparisonTests.swift` 에 `…_상수가_같다` 셋과 `…_대조` 셋을 더하고, `골든_리소스가_번들에_있다` 에 하한 세 줄을 더한다.

```swift
        let detector = try readObject("adaptiveMovementDetector")
        #expect((detector["cases"] as? [[String: Any]])?.count ?? 0 >= 15, "adaptiveMovementDetector.cases 가 너무 적다")

        let segmentBuilder = try readObject("segmentBuilder")
        #expect((segmentBuilder["cases"] as? [[String: Any]])?.count ?? 0 >= 15, "segmentBuilder.cases 가 너무 적다")

        let trailCodec = try readObject("trailCodec")
        #expect((trailCodec["capped"] as? [[String: Any]])?.count ?? 0 >= 4, "trailCodec.capped 가 너무 적다")
        #expect((trailCodec["decode"] as? [[String: Any]])?.count ?? 0 >= 8, "trailCodec.decode 가 너무 적다")
```

판정기 대조는 **매 점마다** 본다 — 마지막 상태만 보면 중간에 한 번 잘못 승격했다가 돌아온 구현이 통과한다.

```swift
    @Test("AdaptiveMovementDetector 가 매 점마다 안드로이드와 같은 상태를 낸다")
    func 판정기_대조() throws {
        for 사례 in try #require(try readObject("adaptiveMovementDetector")["cases"] as? [[String: Any]]) {
            let name = string(사례["name"])
            let detector = AdaptiveMovementDetector()
            detector.reset(fast: bool(사례["resetFast"]))
            let points = try #require(사례["points"] as? [[String: Any]]).compactMap { fix($0) }
            let steps = try #require(사례["steps"] as? [[String: Any]])
            #expect(points.count == steps.count, "\(name): 점 수와 단계 수가 다르다")
            for (i, point) in points.enumerated() {
                let update = detector.onFix(point)
                #expect(update.state.rawValue == string(steps[i]["state"]), "\(name) 점 \(i)")
                #expect(update.promotionBuffer.count == int(steps[i]["promotionBufferSize"]), "\(name) 점 \(i) 승격 버퍼 크기")
                #expect(update.promotionBuffer.map(\.at) == (steps[i]["promotionBufferAts"] as? [Any] ?? []).map(int64), "\(name) 점 \(i) 승격 버퍼 내용")
            }
        }
    }
```

구간 대조는 `nameLat`/`nameLng` 를 **반드시 포함**한다 — 그 둘이 이 Task 가 `Segment` 를 고친 이유다. 좌표·거리 비교는 1e-9 허용치를 쓴다.

- [ ] **Step 8: 통과 확인**

```bash
cd /Users/com/work/KidCare
export PATH="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:$PATH"
./gradlew :app:testDebugUnitTest --tests 'com.kidcare.family.logic.GoldenFileWriterTest'
cd ios && xcodegen generate
xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: 전부 통과. 기존 `SegmentSummarizerTests`·`TimelinePanelTests`(둘 다 `Segment` 를 만든다)가 **그대로 초록**이어야 한다 — 그것이 명시적 `init` 기본값의 검사다.

- [ ] **Step 9: 골든이 정말 무는지 일부러 망가뜨려 확인한다**

| # | 어디를 | 어떻게 | 빨개져야 하는 테스트 |
|---|---|---|---|
| 1 | `AdaptiveMovementDetector.minProgressRatio` | `0.6` → `0.5` | `판정기_상수가_같다`, `판정기_대조` |
| 2 | `AdaptiveMovementDetector.trimBefore` | `samples.count > 1` → `samples.count > 0` | `판정기_대조` |
| 3 | `SegmentBuilder.build` 의 첫 필터 | `fallbackMaxAccuracyMeters` → `maxAccuracyMeters` | `구간_대조`(100m 초과 점 케이스) |
| 4 | `SegmentBuilder.staySegment` | 가중치 `1/(a*a)` → `1/a` | `구간_대조`(`nameLat`) |
| 5 | `TrailCodec.capped` | `bucketWidth` 분모 `maxPoints - 2` → `maxPoints` | `솎기_대조` |

다섯 다 빨개진 것을 본 뒤 되돌린다.

- [ ] **Step 10: 커밋** (공통 절차 B)

```
iOS 아이 1단계 Task 2: 이동 판정기·구간 요약·하루 CSV 를 옮기고 골든으로 묶는다
```

---
### Task 3: 수집 층 — 연속 스트림을 안드로이드 밀도로 솎고, 오늘 점을 파일에 남긴다

**끝나면 다섯 수집 모드의 (정확도·거리 필터·간격)이 표 하나에 못박히고 단위 테스트가 그 표와 분기 순서와 `STILL_ESCALATE_MILLIS` 를 지킨다.** 앱이 '항상 허용'과 배경 위치를 요구하는 빌드가 되고(`Info.plist`), 오늘 점이 `trail_today.csv` 에 한 줄씩 붙었다가 다시 읽힌다. 배터리·충전·통신 종류를 읽는다. 아직 Firestore 로 나가는 것은 없다.

**Files:**
- Create: `ios/KidCare/Child/CollectionMode.swift`, `LocationCollector.swift`, `TrailBuffer.swift`, `TrailStore.swift`, `DeviceState.swift`
- Modify: `ios/project.yml`(`info.properties` 에 세 줄)
- Modify: `i18n/ko.json`, `i18n/en.json`(키 2개), `tools/ios-strings.py`(`INFOPLIST_KEYS` 두 줄), `tools/i18n-untranslated.json`(생성물), `ios/KidCare/Localizable.xcstrings`(생성물)
- Modify: `ios/KidCareTests/ReleaseConfigTests.swift`(판정 기록 12)
- Test: `ios/KidCareTests/CollectionModeTests.swift`, `TrailBufferTests.swift`, `TrailStoreTests.swift`, `DeviceStateTests.swift`(신규)

**Interfaces:**
- Produces: `CollectionMode`(`.moving`/`.fastProbe`/`.slowProbe`/`.knownPlace`/`.still`), `CollectionMode.stillEscalateMillis`, `CollectionMode.select(state:insideKnownPlace:slowProbeSince:now:)`, `CollectionMode.settings`(`desiredAccuracy`·`distanceFilterMeters`·`intervalMillis`), `LocationCollector`(프로토콜 `LocationSource` + 실제 구현), `TrailBuffer`, `TrailStore`, `DeviceState.Snapshot`
- Consumes: `AdaptiveMovementState`, `Fix`, `TrailCodec`, `DayPicker.todayKey(zone:nowMillis:)`
- 문구 키: `ios_perm_location_when_in_use`, `ios_perm_location_always`

**정본:** `child/LocationCollector.kt` 전체, `child/TrailStore.kt` 전체, `child/NetworkState.kt`, `TrackingService.kt:823-838`(배터리·충전), `TrailUploader.kt:95-104`(버퍼의 자정 넘김), 설계서 §4.8·§5.1·§5.2·§6.2.

- [ ] **Step 1: 테스트를 먼저 쓴다**

`ios/KidCareTests/CollectionModeTests.swift` — **이 파일이 설계서 §5.1 표의 유일한 계약이다.** 안드로이드에 대응하는 순수 함수가 없어 골든이 못 잡는다(설계서 §12.1).

```swift
import CoreLocation
import Foundation
import Testing
@testable import KidCare

/// 수집 모드 표(설계서 §5.1)와 분기 순서, 그리고 아이폰에만 있는 `STILL_ESCALATE_MILLIS` 를 고정한다.
///
/// **골든 대조가 이 둘을 못 잡는다.** 안드로이드에는 대응하는 순수 함수가 없다 —
/// `LocationCollector.kt:63-70` 은 `requestUpdates()` 안의 `when` 이고, 정지 모드의 방아쇠는
/// 활동 인식 전환이라 아이폰에 그 입력 자체가 없다(설계서 §4.8 끝). 그래서 여기서 못박는다.
struct CollectionModeTests {

    private let t0: Int64 = 1_700_000_000_000

    // MARK: 표 — 설계서 §5.1

    @Test("이동 확정은 .best · 거리 필터 3m · 5초")
    func 이동_확정_설정() {
        let s = CollectionMode.moving.settings
        #expect(s.desiredAccuracy == kCLLocationAccuracyBest)
        #expect(s.distanceFilterMeters == 3)
        #expect(s.intervalMillis == 5_000)
    }

    @Test("이동 확인은 .best · 거리 필터 없음 · 5초")
    func 이동_확인_설정() {
        let s = CollectionMode.fastProbe.settings
        #expect(s.desiredAccuracy == kCLLocationAccuracyBest)
        #expect(s.distanceFilterMeters == nil)
        #expect(s.intervalMillis == 5_000)
    }

    @Test("저주기 확인은 .nearestTenMeters · 거리 필터 없음 · 30초")
    func 저주기_설정() {
        let s = CollectionMode.slowProbe.settings
        #expect(s.desiredAccuracy == kCLLocationAccuracyNearestTenMeters)
        #expect(s.distanceFilterMeters == nil)
        #expect(s.intervalMillis == 30_000)
    }

    @Test("등록 장소 머무름과 정지는 .nearestTenMeters · 거리 필터 없음 · 60초")
    func 정지_설정() {
        for mode in [CollectionMode.knownPlace, .still] {
            let s = mode.settings
            #expect(s.desiredAccuracy == kCLLocationAccuracyNearestTenMeters, "\(mode)")
            #expect(s.distanceFilterMeters == nil, "\(mode)")
            #expect(s.intervalMillis == 60_000, "\(mode)")
        }
    }

    @Test("정지에도 .hundredMeters 이하로는 절대 안 내려간다 — 그게 안드로이드가 거부한 등급이다(설계서 §4.8)")
    func 정확도_바닥() {
        for mode in [CollectionMode.slowProbe, .knownPlace, .still] {
            #expect(mode.settings.desiredAccuracy <= kCLLocationAccuracyNearestTenMeters, "\(mode)")
        }
    }

    @Test("정지 갈래에는 거리 필터를 절대 안 건다 — 완전히 멈춘 폰이 하트비트까지 굶는다(known-issues 11번)")
    func 정지에는_거리필터_없음() {
        for mode in [CollectionMode.fastProbe, .slowProbe, .knownPlace, .still] {
            #expect(mode.settings.distanceFilterMeters == nil, "\(mode)")
        }
        #expect(CollectionMode.moving.settings.distanceFilterMeters == 3)
    }

    // MARK: 분기 순서 — LocationCollector.kt:63-70

    @Test("등록 장소 분기는 이동 판정보다 **아래**다 — 위에 두면 집 반경 안의 놀이터 경로가 통째로 빈다")
    func 등록장소는_이동보다_아래() {
        #expect(CollectionMode.select(state: .moving, insideKnownPlace: true, slowProbeSince: nil, now: t0) == .moving)
        #expect(CollectionMode.select(state: .fastProbe, insideKnownPlace: true, slowProbeSince: nil, now: t0) == .fastProbe)
        #expect(CollectionMode.select(state: .slowProbe, insideKnownPlace: true, slowProbeSince: t0, now: t0) == .knownPlace)
    }

    @Test("등록 장소 밖의 저주기는 slowProbe 다")
    func 저주기_기본() {
        #expect(CollectionMode.select(state: .slowProbe, insideKnownPlace: false, slowProbeSince: t0, now: t0) == .slowProbe)
    }

    // MARK: STILL_ESCALATE_MILLIS — 아이폰에만 있는 상수(설계서 §4.8)

    @Test("SLOW_PROBE 로 5분을 채우면 정지로 내려간다")
    func 정지_승격() {
        let five: Int64 = 5 * 60_000
        #expect(CollectionMode.stillEscalateMillis == five)
        #expect(CollectionMode.select(state: .slowProbe, insideKnownPlace: false, slowProbeSince: t0, now: t0 + five - 1) == .slowProbe)
        #expect(CollectionMode.select(state: .slowProbe, insideKnownPlace: false, slowProbeSince: t0, now: t0 + five) == .still)
    }

    @Test("정지 승격은 등록 장소 분기보다 **위**다 — 둘 다 60초라 결과는 같지만 순서는 안드로이드와 같아야 한다")
    func 정지가_등록장소보다_위() {
        let five: Int64 = 5 * 60_000
        #expect(CollectionMode.select(state: .slowProbe, insideKnownPlace: true, slowProbeSince: t0, now: t0 + five) == .still)
    }

    @Test("FAST_PROBE 로 올라가면 시계가 0 으로 돌아간다 — 호출자가 slowProbeSince 를 nil 로 준다")
    func 시계_초기화() {
        #expect(CollectionMode.select(state: .fastProbe, insideKnownPlace: false, slowProbeSince: nil, now: t0 + 999_999) == .fastProbe)
        // 다시 내려온 직후에는 시계가 지금부터다.
        #expect(CollectionMode.select(state: .slowProbe, insideKnownPlace: false, slowProbeSince: t0 + 999_999, now: t0 + 999_999) == .slowProbe)
    }

    @Test("시계가 없으면(막 내려왔거나 모름) 정지로 내려가지 않는다")
    func 시계_없음() {
        #expect(CollectionMode.select(state: .slowProbe, insideKnownPlace: false, slowProbeSince: nil, now: t0 + 10 * 60_000) == .slowProbe)
    }

    @Test("시계가 거꾸로 가도 정지로 안 내려간다 — 음수 경과를 5분으로 읽지 않는다")
    func 시계_역행() {
        #expect(CollectionMode.select(state: .slowProbe, insideKnownPlace: false, slowProbeSince: t0 + 60_000, now: t0) == .slowProbe)
    }

    // MARK: 소프트웨어 간격 게이트

    @Test("간격 게이트는 마지막으로 **처리한** 점을 기준으로 한다 — 버린 점은 시계를 안 민다")
    func 간격_게이트() {
        var gate = IntervalGate()
        #expect(gate.accept(at: t0, interval: 5_000) == true)          // 첫 점은 항상 통과
        #expect(gate.accept(at: t0 + 4_999, interval: 5_000) == false)
        #expect(gate.accept(at: t0 + 5_000, interval: 5_000) == true)
        // 버린 점(t0+4_999)이 기준이 됐다면 다음 통과가 t0+9_999 가 됐을 것이다.
        #expect(gate.accept(at: t0 + 10_000, interval: 5_000) == true)
    }

    @Test("시간이 거꾸로 온 점은 통과시킨다 — 판정 쪽이 시계 역행을 처리한다(TrackingService.kt:552-568)")
    func 간격_게이트_역행() {
        var gate = IntervalGate()
        _ = gate.accept(at: t0 + 60_000, interval: 5_000)
        #expect(gate.accept(at: t0, interval: 5_000) == true)
    }
}
```

`TrailStoreTests.swift` — 파일 왕복과 "실패를 삼킨다"를 본다. 임시 디렉터리를 주입받게 만든다.

```swift
    @Test("점을 붙였다 다시 읽으면 그대로다. 첫 줄은 dayKey 다")
    func 왕복() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TrailStore(directory: dir)
        store.reset(dayKey: "2026-09-22")
        let points = [
            Fix(lat: 37.5665, lng: 126.9780, accuracy: 10, at: 1, speed: 0),
            Fix(lat: 37.5666, lng: 126.9781, accuracy: 12.5, at: 6_000, speed: 1.25),
        ]
        points.forEach(store.append)
        let saved = try #require(store.load())
        #expect(saved.dayKey == "2026-09-22")
        #expect(saved.points.map(\.at) == [1, 6_000])
        #expect(saved.points[1].speed == 1.25)
    }

    @Test("헤더만 있고 점이 없어도 정상이다 — reset 직후의 모양(TrailStore.kt:39-40)")
    func 헤더만() throws { … }

    @Test("마지막 줄이 잘려 있어도 나머지는 살린다 — 쓰다가 죽은 파일(TrailCodec.decode 주석)")
    func 잘린_줄() throws { … }

    @Test("못 쓰는 경로를 줘도 예외를 던지지 않는다 — 이 파일은 사본이지 원본이 아니다(TrailStore.kt:23-25)")
    func 쓰기_실패를_삼킨다() { … }

    @Test("파일은 iCloud 백업에서 빠진다 — 하루치 위치가 밖으로 나갈 이유가 없다(설계서 §6.2)")
    func 백업_제외() throws {
        …
        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }
```

`TrailBufferTests.swift` — 자정 넘김(`TrailUploader.kt:95-104`).

```swift
    @Test("날짜가 바뀌면 버퍼와 파일을 비우고 그 날짜로 새로 시작한다")
    @Test("같은 날의 점은 계속 쌓인다")
    @Test("restore 는 오늘 파일만 되찾는다 — 어제 파일이면 아무것도 안 한다(TrailUploader.kt:73-83)")
    @Test("restore 가 마지막 점을 돌려준다 — 호출자가 필터 기준점으로 이어 쓴다(비스듬한 선 하나를 막는다)")
```

`DeviceStateTests.swift` — 매핑만 본다(진짜 `UIDevice`·`NWPathMonitor` 를 안 쓴다).

```swift
    @Test("배터리 레벨 0.77 은 77% 다. 못 읽으면(-1) -1 을 그대로 올린다 — 0% 로 뭉개면 부모가 놀란다")
    @Test("charging 과 full 은 충전 중이다(TrackingService.kt:836-837)")
    @Test("통신 종류 값은 NetworkState.kt:23-26 과 같은 글자다: wifi · cell · none")
```

- [ ] **Step 2: 실패를 확인한다**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/CollectionModeTests -only-testing:KidCareTests/TrailStoreTests -only-testing:KidCareTests/TrailBufferTests -only-testing:KidCareTests/DeviceStateTests`
Expected: 컴파일 실패.

- [ ] **Step 3: `CollectionMode` 를 쓴다**

```swift
import CoreLocation
import Foundation

/// 지금 무슨 밀도로 위치를 받을 것인가. 정본은 안드로이드 `child/LocationCollector.kt:63-78` 의 `when` 둘이다.
///
/// **안드로이드의 "몇 밀리초마다 하나"가 아이폰에는 없다.** `CLLocationManager` 는 새 측정이 생길
/// 때마다 콜백을 준다(GNSS 가 붙어 있으면 대략 1초에 한 번). 손잡이는 `desiredAccuracy`(배터리를
/// 정한다)와 `distanceFilter`(이만큼 옮겨져야 준다) 둘뿐이라, **간격은 우리 코드가 만든다** —
/// 스트림을 계속 받되 [IntervalGate] 가 모드별 간격이 안 지난 점을 그 자리에서 버린다(설계서 §5.1).
///
/// 소프트웨어 게이트가 배터리를 아끼지는 않는다(버려진 콜백도 GNSS 는 이미 켜져 있었다).
/// 아이폰에서 배터리를 실제로 정하는 것은 `desiredAccuracy` 하나다 — `.best` ↔ `.nearestTenMeters`
/// 전환이 이 설계의 절약 장치 전부다(설계서 §9.2).
enum CollectionMode: String, Equatable, CaseIterable {
    case moving        // 판정기 MOVING
    case fastProbe     // 판정기 FAST_PROBE
    case slowProbe     // 판정기 SLOW_PROBE
    case knownPlace    // 등록 장소 반경 안 & 이동 아님 (2단계가 실제로 켠다)
    case still         // SLOW_PROBE 로 stillEscalateMillis 연속

    struct Settings: Equatable {
        let desiredAccuracy: CLLocationAccuracy
        /// nil = 거리 필터 없음(`kCLDistanceFilterNone`).
        let distanceFilterMeters: CLLocationDistance?
        let intervalMillis: Int64
    }

    /// 설계서 §5.1 의 표 그대로다.
    ///
    /// **정지에 `.nearestTenMeters` 를 쓰는 근거**(설계서 §4.8): 안드로이드는 정지에도 일부러
    /// HIGH_ACCURACY 를 쓴다 — 하루의 대부분이 정지 구간이고 머무른 곳 이름이 그 점들로 정해진다.
    /// 거부한 대안은 `PRIORITY_BALANCED_POWER_ACCURACY`(WiFi·기지국, 오차 20~60m)였다.
    /// `.nearestTenMeters` 는 그 거부 대상이 아니라 GNSS 를 쓰되 듀티 사이클을 허용하는 등급이고,
    /// 오차 10m 는 50m 정확도 문턱과 40m 머무름 반경 안에 넉넉히 든다.
    /// **`.hundredMeters` 이하로는 절대 안 내린다** — 그게 안드로이드가 거부한 그 등급이다.
    ///
    /// **정지에 거리 필터를 안 거는 근거**: 걸면 완전히 멈춘 폰이 콜백을 하나도 못 받아 하트비트
    /// (10분)가 굶고 상태 문서의 `at` 이 멈춘다 — 안드로이드가 정확히 같은 이유로 이동 확정일
    /// 때만 걸었다(`LocationCollector.kt:109-121`, `known-issues.md` 11번).
    var settings: Settings {
        switch self {
        case .moving:
            return Settings(desiredAccuracy: kCLLocationAccuracyBest, distanceFilterMeters: 3, intervalMillis: 5_000)
        case .fastProbe:
            return Settings(desiredAccuracy: kCLLocationAccuracyBest, distanceFilterMeters: nil, intervalMillis: 5_000)
        case .slowProbe:
            return Settings(desiredAccuracy: kCLLocationAccuracyNearestTenMeters, distanceFilterMeters: nil, intervalMillis: 30_000)
        case .knownPlace, .still:
            return Settings(desiredAccuracy: kCLLocationAccuracyNearestTenMeters, distanceFilterMeters: nil, intervalMillis: 60_000)
        }
    }

    /// **아이폰에만 있는 상수다**(설계서 §4.8 끝, §15-3). 안드로이드의 정지 60초는 활동 인식이
    /// STILL 을 보고할 때 켜지는데(`LocationCollector.kt:65`) 아이폰은 v1 에서 CoreMotion 을 안 써
    /// 그 방아쇠가 없다. 그대로 두면 가만히 있는 폰이 영영 저주기(30초)에 머물러 안드로이드보다
    /// 배터리를 두 배로 쓴다.
    ///
    /// 5분인 이유: 안드로이드의 활동 인식이 STILL 을 보고하기까지 걸리는 시간(30초~2분,
    /// `LocationCollector.kt:220-221`)보다 넉넉히 길게 잡아 **진짜 정지에만** 켜지게 하려는 것이다.
    /// 짧게 잡으면 신호등 앞에서 기다리는 1분이 정지로 내려가 다시 올라오는 데 30초가 더 걸린다.
    ///
    /// 안드로이드에 대응이 없으므로 **골든 대조 대상이 아니다.** `CollectionModeTests` 가 고정한다.
    static let stillEscalateMillis: Int64 = 5 * 60_000

    /// 분기 **순서가 안드로이드와 같아야 한다**(`LocationCollector.kt:63-70`). 특히 등록 장소
    /// 분기가 이동 판정보다 **아래**다 — 위에 두면 집 반경 안의 놀이터에 다녀오는 동안 1분 주기에
    /// 묶여 그 경로가 통째로 빈다(그 주석 :58-62).
    ///
    /// - Parameter slowProbeSince: 판정기가 SLOW_PROBE 로 **연속해서** 머물기 시작한 시각.
    ///   FAST_PROBE·MOVING 으로 올라가는 순간 호출자가 `nil` 로 만든다(= 시계가 0 으로 돌아간다).
    static func select(
        state: AdaptiveMovementState,
        insideKnownPlace: Bool,
        slowProbeSince: Int64?,
        now: Int64
    ) -> CollectionMode {
        // 안드로이드의 `!activityMoving` 자리다. 시간이 그 비트를 대신한다.
        if state == .slowProbe, let since = slowProbeSince, now - since >= stillEscalateMillis {
            return .still
        }
        if state == .moving { return .moving }
        if state == .fastProbe { return .fastProbe }
        if insideKnownPlace { return .knownPlace }
        return .slowProbe
    }
}

/// 모드별 소프트웨어 간격을 강제한다. **마지막으로 통과시킨 점**만 기준이 된다 — 버린 점이
/// 시계를 밀면 간격이 실제보다 길어져 밀도가 안드로이드보다 성글어진다.
struct IntervalGate {
    private var lastAcceptedAt: Int64?

    /// 시간이 거꾸로 온 점은 **통과시킨다.** 여기서 막으면 시계 역행 뒤의 모든 점이 영영 막히는데,
    /// 그 상황을 푸는 것은 `TrackingCoordinator` 의 시계 역행 감지다(`TrackingService.kt:552-568`).
    mutating func accept(at: Int64, interval: Int64) -> Bool {
        guard let last = lastAcceptedAt else {
            lastAcceptedAt = at
            return true
        }
        if at >= last, at - last < interval { return false }
        lastAcceptedAt = at
        return true
    }

    mutating func reset() { lastAcceptedAt = nil }
}
```

- [ ] **Step 4: `LocationCollector` 를 쓴다**

`Child/LocationCollector.swift`. 매니저는 **한 번만** 만들고 앱이 사는 동안 들고 있는다(설계서 §5.2). 테스트가 좌표를 먹일 수 있도록 프로토콜을 하나 낸다.

```swift
import CoreLocation
import Foundation

/// `TrackingCoordinator` 가 보는 좌표 공급원. 테스트는 가짜를 넣는다(설계서 §12.1).
@MainActor
protocol LocationSource: AnyObject {
    /// 점 하나가 소프트웨어 간격 게이트를 통과했을 때 부른다.
    var onFix: ((Fix) -> Void)? { get set }
    func start()
    func stop()
    /// 판정기 상태·등록 장소 여부가 바뀌면 부른다. 모드가 실제로 바뀔 때만 매니저를 다시 건다.
    func updateMode(state: AdaptiveMovementState, insideKnownPlace: Bool, slowProbeSince: Int64?, now: Int64)
}

/// `CLLocationManager` 를 감싸고, 수집 모드에 따라 정확도·거리 필터를 바꾼다.
/// 정본은 안드로이드 `child/LocationCollector.kt`.
///
/// `@MainActor` 인 이유: `CLLocationManagerDelegate` 콜백은 **매니저를 만든 스레드의 런루프**로
/// 오므로 메인에서 만들면 메인으로 온다 — 안드로이드가 `context.mainLooper` 를 넘기는 것
/// (`LocationCollector.kt:150`)과 같은 선택이고, 버퍼를 만지는 스레드가 하나로 유지돼 잠금이
/// 필요 없어지는 것도 같다(`TrailUploader.kt:91-93`).
@MainActor
final class LocationCollector: NSObject, LocationSource {

    var onFix: ((Fix) -> Void)?
    /// 권한이 바뀌면 부른다. 1단계는 로그만 남기고, 화면과 이벤트는 3단계가 잇는다(설계서 §8.1).
    var onAuthorizationChange: ((CLAuthorizationStatus, CLAccuracyAuthorization) -> Void)?

    private let manager = CLLocationManager()
    private var gate = IntervalGate()
    private var mode: CollectionMode = .fastProbe
    private var started = false

    override init() {
        super.init()
        manager.delegate = self
        // **가장 중요한 한 줄이다**(설계서 §5.2). 기본값 true 면 iOS 가 "이 사람 안 움직이네" 하고
        // 업데이트를 멈추는데, 멈춘 뒤에는 **스스로 다시 시작하지 않는다.** 그 하루가 통째로
        // 조용해진다 — 이 앱에서 침묵이 제일 나쁜 고장이다.
        manager.pausesLocationUpdatesAutomatically = false
        // 안드로이드의 상시 알림(`TrackingService.buildNotification`, :840)과 같은 자리다.
        // 몰래 감시하지 않는다는 원칙을 아이폰에서 지키는 방법 — 아이는 파란 표시를 보고
        // 지금 위치가 공유 중임을 안다.
        manager.showsBackgroundLocationIndicator = true
        // `.fitness`/`.automotiveNavigation` 은 iOS 가 그 활동에 맞춰 스트림을 조절한다.
        // 아이가 걷는지 버스를 타는지는 우리가 모른다.
        manager.activityType = .other
        apply(mode)
    }

    func start() {
        guard !started else { return }
        started = true
        // `allowsBackgroundLocationUpdates` 는 '항상 허용' 이전에 켜면 예외로 죽는다.
        // 권한이 실제로 들어온 뒤(아래 델리게이트)에 켠다.
        manager.startUpdatingLocation()
        // 되살아나는 길(설계서 §5.3-1). 약 500m 이동마다 아주 적은 배터리로 앱을 **다시 띄운다**
        // — 재부팅 뒤에도 살고, 지오펜스 20개 자리를 안 쓴다. 지역 감시(§5.3-2)는 장소 목록이
        // 있어야 걸 수 있어 2단계다(1단계 판정 기록 16).
        //
        // **강제 종료 뒤에는 이 길도 앱을 되살리지 않는다**(설계서 §5.3·§15-2). 여기에
        // "죽어도 계속 기록한다"고 적지 않는다 — 부모에게 그것을 말하는 일은 3단계다.
        manager.startMonitoringSignificantLocationChanges()
    }

    func stop() {
        started = false
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        gate.reset()
    }

    func requestAuthorization() {
        // iOS 는 '항상'을 곧바로 못 묻는다. 반드시 두 걸음이다(설계서 §8.1). 1단계는 첫 걸음만
        // 부르고, 두 번째 걸음과 화면 안내는 3단계가 정한다.
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    func updateMode(state: AdaptiveMovementState, insideKnownPlace: Bool, slowProbeSince: Int64?, now: Int64) {
        let next = CollectionMode.select(state: state, insideKnownPlace: insideKnownPlace, slowProbeSince: slowProbeSince, now: now)
        guard next != mode else { return }   // 같은 모드면 다시 안 건다(LocationCollector.kt:168-172 와 같은 이유)
        mode = next
        apply(next)
    }

    private func apply(_ mode: CollectionMode) {
        let s = mode.settings
        manager.desiredAccuracy = s.desiredAccuracy
        manager.distanceFilter = s.distanceFilterMeters ?? kCLDistanceFilterNone
    }

    /// CoreLocation 의 "못 믿음" 표기를 안드로이드 모양으로 옮긴다(1단계 판정 기록 19).
    static func fix(from location: CLLocation) -> Fix {
        Fix(
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            // 음수는 "이 좌표를 믿지 마라"는 뜻이다. 무한대로 올리면 모든 정확도 게이트가
            // 거절한다 — 지어내지 않는다.
            accuracy: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : .infinity,
            at: Int64((location.timestamp.timeIntervalSince1970 * 1000).rounded()),
            // 코틀린 `loc.speed` 는 모를 때 0 이다(`Fix.speed` 주석).
            speed: location.speed >= 0 ? location.speed : 0,
            // 코틀린 `loc.hasSpeedAccuracy()` 가 false 일 때와 같다(`LocationCollector.kt:138-142`).
            speedAccuracy: location.speedAccuracy >= 0 ? location.speedAccuracy : .infinity
        )
    }
}

extension LocationCollector: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            // 묶음으로 올 수 있다. `last` 하나만 쓰면 그 사이의 모퉁이가 사라져 경로가 건물을
            // 가로지르는 직선이 된다(`LocationCollector.kt:127-130`). 시간순으로 전부 넘긴다.
            for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
                let fix = Self.fix(from: location)
                guard gate.accept(at: fix.at, interval: mode.settings.intervalMillis) else { continue }
                onFix?(fix)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            // '항상 허용'이 실제로 들어온 뒤에만 켠다 — 그 전에 켜면 예외로 죽는다.
            manager.allowsBackgroundLocationUpdates = manager.authorizationStatus == .authorizedAlways
            onAuthorizationChange?(manager.authorizationStatus, manager.accuracyAuthorization)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 삼키되 로그는 남긴다. 위치 실패는 흔하고(실내 진입 등) 다음 콜백이 곧 온다.
    }
}
```

> `MainActor.assumeIsolated` 는 **델리게이트가 메인 런루프로 온다는 사실**에 기댄다(매니저를 메인에서 만들었다). 그 전제가 깨지면 런타임에 즉시 죽는다 — 조용히 틀리는 것보다 낫다. `@unchecked Sendable` 은 쓰지 않는다.

- [ ] **Step 5: `TrailStore`·`TrailBuffer`·`DeviceState` 를 쓴다**

`Child/TrailStore.swift` — 코틀린 `TrailStore.kt` 그대로. 다른 점 셋만 적는다(판정 기록 13).

```swift
    /// 위치는 Application Support 아래 `trail_today.csv`(`TrailStore.kt:68` 과 같은 이름).
    /// `.documentDirectory` 가 아닌 이유는 그쪽이 파일 앱에 노출될 수 있어서다(설계서 §6.2).
    ///
    /// **이 폴더는 앱이 만들기 전까지 없다** — 안드로이드 `filesDir` 은 항상 있어서 코틀린에는
    /// 대응 코드가 없다. 그래서 여기서 한 번 만든다.
    init(directory: URL? = nil) {
        let base = directory ?? (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ))
        …
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // 하루치 위치 기록이 iCloud 로 나갈 이유가 없다(설계서 §6.2).
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(&values)
    }

    /// 덧붙이기는 `FileHandle.seekToEnd` + `write` 다. 한 줄 50바이트라 메인에서도 1ms 아래고,
    /// 버퍼를 만지는 스레드가 하나로 유지된다(`TrailUploader.kt:91-93`).
    ///
    /// **쓰기 실패는 삼키고 로그만 남긴다.** 이 파일은 메모리 버퍼의 사본이지 원본이 아니다 —
    /// 여기서 던져 위치 수집 자체를 멈추면, 프로세스가 죽었을 때만 쓸모 있는 보험 때문에 평소
    /// 동작을 잃는다(`TrailStore.kt:23-25`).
    func append(_ fix: Fix) { … }
```

`Child/TrailBuffer.swift` — `TrailUploader.kt:95-104` 의 자정 넘김과 `restore()`(:73-83).

```swift
/// 오늘 확보한 점을 메모리에 쌓고, 날짜가 바뀌면 비우고 새로 시작한다.
///
/// 자정 직전의 마지막 업로드 뒤에 들어온 점 몇 개는 어제 문서에 안 담긴 채 버려지는데
/// **그건 의도된 것이다** — 어제 문서를 다시 쓰려면 쓰기가 하나 더 들고, 자정 무렵 몇 분의
/// 점을 위해 가족당 하루 20쓰기 예산을 쓸 이유가 없다(`TrailUploader.kt:38-44`).
@MainActor
final class TrailBuffer {
    private(set) var points: [Fix] = []
    private(set) var dayKey: String?

    /// 프로세스가 죽었다 살아난 경우 오늘 걸어온 길을 파일에서 되찾는다. 뜰 때 딱 한 번 부른다.
    /// 파일이 어제 것이면 아무것도 안 한다 — 다음 [append] 가 날짜 불일치를 보고 새로 만든다.
    ///
    /// 돌려주는 마지막 점은 호출자가 **필터의 기준점**으로 이어 쓴다. 서비스가 다시 뜬 직후의
    /// 첫 좌표를 무조건 새 출발점으로 넣으면 실제로는 가만히 있어도 이전 마지막 점과 GPS
    /// 오차만큼 비스듬한 선이 하나 생긴다(`TrailUploader.kt:79-82`).
    ///
    /// **그 복구된 점으로는 절대 상태 문서를 쓰지 않는다** — 몇 시간 전 점이 서버 시각으로
    /// "방금"이 되어 부모가 그걸 방금 확인한 위치로 읽는다(`TrackingService.kt:713-717`).
    @discardableResult
    func restore(store: TrailStore, zone: TimeZone, nowMillis: Int64) -> Fix? { … }

    func append(_ fix: Fix, store: TrailStore, zone: TimeZone) { … }
}
```

`Child/DeviceState.swift` — 읽기만 한다(`NetworkState.kt` 와 같은 자리). 배터리 읽기를 주입받는다(판정 기록 8).

```swift
/// 아이 폰의 지금 상태. **읽기만 한다** — 안드로이드 `child/NetworkState.kt` 머리 주석과 같은 이유로
/// 끄고 켜는 기능이 없다.
@MainActor
final class DeviceState {

    struct Snapshot: Equatable {
        /// 0~100. **못 읽으면 -1 이다** — 0 으로 뭉개면 부모 화면이 "다 닳았다"고 거짓말한다
        /// (코틀린 `ChildStatusDoc.battery` 기본값도 -1 이다, `Documents.kt:93`).
        let batteryPercent: Int
        let charging: Bool
        /// `wifi` · `cell` · `none` · 빈 값(모름). 글자는 `NetworkState.kt:23-26` 그대로다.
        let network: String
    }

    /// **시뮬레이터는 배터리를 안 준다**(`batteryLevel` 이 -1, `batteryState` 가 `.unknown`;
    /// `simctl status_bar override` 는 화면 위 막대만 바꾼다). 그래서 읽기를 주입받는다 —
    /// 기본값이 진짜 `UIDevice` 이고, 시뮬레이터 확인은 `ChildSimHarness` 가 값을 넣어 준다
    /// (1단계 판정 기록 8). 실기기 실측은 4단계다.
    init(battery: @escaping () -> (level: Float, state: UIDevice.BatteryState) = { … }) { … }
}
```

- [ ] **Step 6: `Info.plist` 와 문구 키 둘**

공통 절차 A 로 `i18n/ko.json`·`i18n/en.json` 에 키 둘을 넣는다. 한국어는 설계서 §17 열린 질문 10 의 초안 그대로다.

```bash
cd /Users/com/work/KidCare && python3 - <<'EOF'
import json
ADD = {
    'ko': {
        'ios_perm_location_when_in_use': '엄마 아빠가 지금 어디 있는지 볼 수 있게 위치를 보냅니다.',
        'ios_perm_location_always': '엄마 아빠가 지금 어디 있는지 볼 수 있게 위치를 보냅니다. 화면이 꺼져 있을 때도 보내야 길을 잃었을 때 찾을 수 있어요.',
    },
    'en': {
        'ios_perm_location_when_in_use': 'Sends your location so your parents can see where you are.',
        'ios_perm_location_always': 'Sends your location so your parents can see where you are. It has to keep sending while the screen is off so they can find you if you get lost.',
    },
}
for lang, add in ADD.items():
    path = f'i18n/{lang}.json'
    raw = open(path, encoding='utf-8').read()
    d = json.loads(raw)
    assert list(d) == sorted(d) and json.dumps(d, indent=2, ensure_ascii=False) + '\n' == raw, path + ' 모양이 예상과 다르다'
    for k, v in add.items():
        assert k not in d, k
        d[k] = v
    open(path, 'w', encoding='utf-8').write(json.dumps(dict(sorted(d.items())), indent=2, ensure_ascii=False) + '\n')
print('ok')
EOF
```

`tools/ios-strings.py:28` 을 바꾼다.

```python
# Info.plist 키 → i18n 키. 위치 설명 둘은 앱스토어 심사가 직접 읽는 문장이다(설계서 §8.5·§17-10).
INFOPLIST_KEYS = {
    'CFBundleDisplayName': 'app_name',
    'NSLocationWhenInUseUsageDescription': 'ios_perm_location_when_in_use',
    'NSLocationAlwaysAndWhenInUseUsageDescription': 'ios_perm_location_always',
}
```

`ios/project.yml` 의 `targets.KidCare.info.properties` 에 더한다.

```yaml
        # 아이 역할(설계서 §5.2). 이 배열이 있고 startUpdatingLocation() 이 돌고 있으면 iOS 가 앱을
        # 서스펜드하지 않는다 — 안드로이드 포그라운드 서비스에 가장 가까운 것이다.
        # **하나만 둔다.** 배경 모드를 더 넣으면 가이드라인 2.5.4("실제로 쓰는 것만")를 정면으로
        # 만난다(ReleaseConfigTests.출시_Info 가 막는다).
        UIBackgroundModes: [location]
        # 문장 자체는 i18n 에 있고 Localizable.xcstrings 의 InfoPlist 항목으로 실린다
        # (tools/ios-strings.py 의 INFOPLIST_KEYS). 여기에는 기본(한국어) 값이 들어간다.
        NSLocationWhenInUseUsageDescription: 엄마 아빠가 지금 어디 있는지 볼 수 있게 위치를 보냅니다.
        NSLocationAlwaysAndWhenInUseUsageDescription: 엄마 아빠가 지금 어디 있는지 볼 수 있게 위치를 보냅니다. 화면이 꺼져 있을 때도 보내야 길을 잃었을 때 찾을 수 있어요.
```

```bash
cd /Users/com/work/KidCare
python3 tools/ios-strings.py --write-gaps      # 빈 칸이 12개 언어 × 2키 늘어야 한다
git diff tools/i18n-untranslated.json | head -40
python3 tools/ios-strings.py --check; echo $?  # 0
```

- [ ] **Step 7: `ReleaseConfigTests` 의 두 단언을 뒤집는다(판정 기록 12)**

`ios/KidCareTests/ReleaseConfigTests.swift` 의 `출시_Info` 에서 두 줄을 바꾸고 테스트 이름도 고친다.

```swift
    @Test("출시 Info.plist — 수출 규정, 1.0 (1), 아이폰 세로 전용, 위치 문구 둘·배경 모드 location 하나(7단계 판정 기록 3·4·5·15, 아이 1단계 판정 기록 12)")
    func 출시_Info() throws {
        …
        // 7단계까지 이 앱은 권한을 하나도 요청하지 않았다("권한 0개"가 자랑이었다 —
        // `2026-09-12-kidcare-ios-design.md` §1). 아이 역할이 그 성질을 **일부러** 깬다:
        // 같은 바이너리가 백그라운드 위치를 요구하게 되므로 심사에서 가이드라인 2.5.4 를
        // 정면으로 만난다(아이 설계서 §15-7). 그래서 단언을 지우지 않고 **뒤집는다** —
        // 셋째 문구나 둘째 배경 모드가 생기면 그 자리에서 빨개진다.
        #expect(
            info.keys.filter { $0.hasSuffix("UsageDescription") }.sorted()
                == ["NSLocationAlwaysAndWhenInUseUsageDescription", "NSLocationWhenInUseUsageDescription"],
            "권한 문구가 위치 둘 말고 더 생겼다 — 늘릴 때는 심사 근거를 먼저 적는다"
        )
        #expect(info["UIBackgroundModes"] as? [String] == ["location"],
                "배경 모드는 location 하나여야 한다 — 가이드라인 2.5.4 는 실제로 쓰는 것만 허용한다")
```

`PrivacyInfo.xcprivacy` 는 **안 고친다** — `NSPrivacyCollectedDataTypePreciseLocation` 이 이미 들어 있고, `이유_필요_API` 가 훑는 다섯 갈래 중 새로 부르는 것이 없다. `TrailStore` 를 쓰면서 `modificationDate`·`attributesOfItem`·`systemUptime`·`mach_absolute_time` 을 **쓰지 않는다**(판정 기록 12). 그 테스트가 소스를 훑어 지킨다.

- [ ] **Step 8: 통과 확인**

```bash
cd /Users/com/work/KidCare/ios
xcodegen generate
xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: 전부 통과. `ReleaseConfigTests` 가 새 단언으로 초록이고, `LocalizableCatalogTests`·`I18nKeyParityTests`·`LocalizationBundleTests` 도 초록이다.

- [ ] **Step 9: 커밋** (공통 절차 B)

```
iOS 아이 1단계 Task 3: 수집 모드 표와 오늘 경로 파일 — 아이폰에서 안드로이드 밀도를 만든다
```

---
### Task 4: 점 하나가 지나는 길과 하루 문서 — 에뮬레이터에 안드로이드와 같은 모양으로 올린다

**끝나면 시뮬레이터에 좌표를 먹이면 에뮬레이터에 `children/{childUid}` 와 `children/{childUid}/trails/{dayKey}` 가 올라간다.** 필드 집합이 코틀린 `ChildStatusDoc`·`TrailDoc`·`TrailPoint`·`SegmentDoc` 과 같고, 규칙이 그 쓰기를 실제로 통과하며, 남의 자리에 쓰면 거부된다. 업로드 판정(15분/4시간/사건 직후)과 §6.1 의 10단계 순서가 테스트로 박힌다.

**Files:**
- Create: `ios/KidCare/Child/TrackingCoordinator.swift`, `TrailUploader.swift`, `ChildSimHarness.swift`, `ChildSimView.swift`
- Create: `ios/KidCare/Core/ChildStatusReporter.swift`
- Modify: `ios/KidCare/Core/TrailRepository.swift`(`save` 추가, 머리 주석 :5-6 수정), `ios/KidCare/Core/Documents.swift`(`platform`, 쓰기 모양), `ios/KidCare/RouterView.swift`(`#if DEBUG` 분기)
- Test: `ios/KidCareTests/TrackingCoordinatorTests.swift`, `TrailUploaderTests.swift`, `ChildSimHarnessTests.swift`, `ChildDocumentsTests.swift`, `ChildTrailWriteTests.swift`(에뮬레이터)

**Interfaces:**
- Produces: `TrackingCoordinator(...)`·`handle(_:)`·`uploadNow()`, `TrailUploader.upload(familyId:childUid:)`·`restore()`, `ChildStatusReporter.report(...)`, `TrailRepository.save(familyId:childUid:doc:)`, `TrailDoc.firestoreData`·`TrailPoint.firestoreData`·`SegmentDoc.firestoreData`, `ChildStatusWrite`, `ChildStatusDoc.platform`, `ChildSimHarness.launch`
- Consumes: Task 1~3 의 전부, `DayPicker.todayKey`, `AuthGateway`

**정본:** `TrackingService.kt:532-699`(`handle`), `:719-729`(`uploadNow`), `:902-913`(상수), `child/TrailUploader.kt`, `child/StatusReporter.kt`, `core/TrailRepository.kt:31`, `core/model/Documents.kt:88-190`, 설계서 §6.1·§6.3·§6.4·§10.1·§11.1.

- [ ] **Step 1: 테스트를 먼저 쓴다**

`ios/KidCareTests/TrackingCoordinatorTests.swift` — **이 파일이 §6.1 의 계약이다.** 가짜 `LocationSource` 와 가짜 업로더로 점 시퀀스를 먹인다.

```swift
import Foundation
import Testing
@testable import KidCare

/// 설계서 §6.1 의 10단계 **순서**와 §6.4 의 업로드 판정을 고정한다. 순서가 곧 계약이라
/// (`TrackingService.kt:532-699`) 나중에 중간에 끼워 넣으면 조용히 틀어진다.
@MainActor
struct TrackingCoordinatorTests {

    private let t0: Int64 = 1_700_000_000_000

    // MARK: 순서

    @Test("장소 판정은 업로드 판정에 안 묶인다 — SKIP_TOO_CLOSE 도 넘어간다(TrackingService.kt:631-639)")
    func 장소판정은_독립이다() {
        var 장소로_간_점: [Int64] = []
        let c = 만든다(onPlaceFix: { 장소로_간_점.append($0.at) })
        c.handle(fix(at: t0))                       // 첫 점 = UPLOAD
        c.handle(fix(at: t0 + 60_000, meters: 1))   // 25m 못 감 = SKIP_TOO_CLOSE
        #expect(장소로_간_점 == [t0, t0 + 60_000], "SKIP_TOO_CLOSE 가 장소 판정에서 빠졌다")
    }

    @Test("못 믿는 점(정확도·순간이동)은 장소 판정에도 안 넘어간다")
    func 못_믿는_점은_안_넘어간다() {
        var 장소로_간_점: [Int64] = []
        let c = 만든다(onPlaceFix: { 장소로_간_점.append($0.at) })
        c.handle(fix(at: t0))
        c.handle(fix(at: t0 + 60_000, meters: 1, accuracy: 200))
        #expect(장소로_간_점 == [t0])
    }

    @Test("상태 검사는 점을 버릴지와 무관하게 **먼저** 한다(TrackingService.kt:533-537)")
    func 상태검사가_먼저다() {
        var 순서: [String] = []
        let c = 만든다(onCondition: { 순서.append("condition") }, onPlaceFix: { _ in 순서.append("place") })
        c.handle(fix(at: t0, accuracy: 500))   // 정확도로 거절되는 점
        #expect(순서 == ["condition"], "거절되는 점에서도 상태 검사는 돈다")
    }

    @Test("시계가 거꾸로 가면 기준점을 버리고 다음 점을 첫 점처럼 받는다(TrackingService.kt:552-568)")
    func 시계_역행_복구() {
        let c = 만든다()
        c.handle(fix(at: t0 + 600_000))
        c.handle(fix(at: t0))                  // 과거
        c.handle(fix(at: t0 + 1_000, meters: 1))
        #expect(c.lastFix?.at == t0 + 1_000, "lastFix 초기화가 안 돼 이후 점이 영영 막힌다")
    }

    @Test("이동 확정 전의 점들도 승격 버퍼로 경로에 들어간다 — 출발 부분이 잘리지 않는다")
    func 승격_버퍼() { … }

    @Test("머무름은 5분 기준점만 남긴다(STAY_ANCHOR_INTERVAL_MILLIS)")
    func 머무름_기준점() {
        let c = 만든다()
        c.handle(fix(at: t0))                              // 첫 점은 force
        c.handle(fix(at: t0 + 60_000, meters: 1))          // 5분 안 됐다
        c.handle(fix(at: t0 + 300_000, meters: 2))         // 5분
        #expect(c.buffer.points.map(\.at) == [t0, t0 + 300_000])
    }

    @Test("정지 주기 사이의 큰 변위는 이동 확인을 켠다 — 5분 뒤 만료되면 되돌아간다(COORDINATE_KICK_WINDOW_MILLIS)")
    func 좌표_변위_킥() { … }

    // MARK: 업로드 판정 — 설계서 §6.4

    @Test("첫 좌표에서 한 번 올린다 — lastUploadAt 이 0 이고 lastUploadedFix 가 nil 이라(설계서 §10.1)")
    func 첫_좌표_업로드() {
        let 업로드 = 기록기()
        let c = 만든다(업로드: 업로드)
        c.handle(fix(at: t0))
        #expect(업로드.횟수 == 1)
    }

    @Test("15분 **그리고** 25m 를 둘 다 만족해야 올린다")
    func 주기_업로드() {
        let 업로드 = 기록기()
        let c = 만든다(업로드: 업로드)
        c.handle(fix(at: t0))                                        // 1회
        c.handle(fix(at: t0 + 15 * 60_000, meters: 10))              // 25m 못 감 → 안 올린다
        #expect(업로드.횟수 == 1)
        c.handle(fix(at: t0 + 16 * 60_000, meters: 100))             // 둘 다 만족
        #expect(업로드.횟수 == 2)
        c.handle(fix(at: t0 + 17 * 60_000, meters: 300))             // 15분 안 됐다
        #expect(업로드.횟수 == 2)
    }

    @Test("안 움직여도 4시간이 지나면 한 번 올린다 — 부모 화면의 '마지막 신호'가 멎지 않게")
    func 유휴_업로드() {
        let 업로드 = 기록기()
        let c = 만든다(업로드: 업로드)
        c.handle(fix(at: t0))
        c.handle(fix(at: t0 + 4 * 60 * 60_000 - 1, meters: 1))
        #expect(업로드.횟수 == 1)
        c.handle(fix(at: t0 + 4 * 60 * 60_000, meters: 1))
        #expect(업로드.횟수 == 2)
    }

    @Test("사건 직후에는 1·2번을 무시하고 올린다. 다만 1분 안에 또 나면 건너뛴다(known-issues 21번)")
    func 사건_직후_업로드() {
        // 이 갈래를 부르는 코드는 2단계(장소 이벤트)다. 판정만 지금 고정한다(1단계 판정 기록 14).
        let 업로드 = 기록기()
        let c = 만든다(업로드: 업로드)
        c.handle(fix(at: t0))                                          // 1회
        c.handle(fix(at: t0 + 30_000, meters: 1), eventJustWritten: true)   // 1분 안 → 건너뛴다
        #expect(업로드.횟수 == 1)
        c.handle(fix(at: t0 + 61_000, meters: 1), eventJustWritten: true)   // 1분 지남 → 올린다
        #expect(업로드.횟수 == 2)
    }

    @Test("위치를 한 번도 못 잡았으면 올리지 않는다 — 조용히 건너뛰고 로그만 남긴다(설계서 §6.4 끝)")
    func 좌표_없으면_안_올린다() async {
        let 업로드 = 기록기()
        let c = 만든다(업로드: 업로드)
        await c.uploadNow()
        #expect(업로드.횟수 == 0)
    }

    @Test("파일에서 복구한 옛 점으로는 상태 문서를 쓰지 않는다(TrackingService.kt:713-717)")
    func 복구된_점은_상태를_안_쓴다() async { … }

    @Test("업로드가 실패해도 lastUploadAt 을 먼저 갱신한다 — 실패가 이어질 때 fix 마다 재시도하지 않는다")
    func 실패해도_시각을_민다() async { … }
}
```

`ios/KidCareTests/ChildDocumentsTests.swift` — **쓰기 필드 집합이 코틀린과 같은지** 본다. 이 앱의 규율("`firestoreData` 가 곧 계약의 증거", `Documents.swift:18`)을 아이 쪽에도 건다.

```swift
    @Test("하루 문서의 필드는 코틀린 TrailDoc 과 같다 — 넷뿐이다(Documents.kt:148-155)")
    func 하루문서_필드() {
        let doc = TrailDoc(dayKey: "2026-09-22", points: [], segments: [], updatedAt: 1)
        #expect(Set(doc.firestoreData.keys) == ["dayKey", "points", "segments", "updatedAt"])
    }

    @Test("경로점의 필드는 다섯뿐이다 — battery 를 넣지 않는다(Documents.kt:163-167 주석)")
    func 경로점_필드() {
        let p = TrailPoint(lat: 1, lng: 2, accuracy: 3, speed: 4, at: 5)
        #expect(Set(p.firestoreData.keys) == ["lat", "lng", "accuracy", "speed", "at"])
    }

    @Test("구간 요약의 필드는 여덟이다. dayKey 가 없다 — 담고 있는 문서 ID 가 이미 말한다")
    func 구간_필드() { … }

    @Test("상태 문서는 코틀린 필드 + platform 이고, wifiOn 은 안 쓴다(1단계 판정 기록 10)")
    func 상태문서_필드() {
        let w = ChildStatusWrite(fix: …, battery: 77, charging: false, network: "wifi")
        #expect(Set(w.firestoreData.keys) == [
            "lat", "lng", "accuracy", "at", "battery", "charging",
            "ringerMode", "dnd", "network", "lastSeenAt", "lastSeenServerAt", "platform",
        ])
        // 아이폰은 소리 모드를 읽을 API 가 없다. 필드를 **빼면** 기본값 "normal" 이 살아나
        // 부모 화면이 "벨소리"라고 거짓말한다 — 빈 값이 "모른다"다.
        #expect(w.firestoreData["ringerMode"] as? String == "")
        #expect(w.firestoreData["dnd"] as? String == "")
        #expect(w.firestoreData["platform"] as? String == "ios")
        // 서버 시각은 아이 폰 시계로 채우지 않는다(StatusReporter.kt:61-65).
        #expect(w.firestoreData["lastSeenServerAt"] is FieldValue)
    }

    @Test("쓴 것을 다시 읽으면 같다 — firestoreData → init? 왕복")
    func 왕복() { … }
```

`ios/KidCareTests/ChildTrailWriteTests.swift` — 에뮬레이터. 설계서 §12.3 중 1단계에 해당하는 것만(이벤트·장소는 2단계).

```swift
import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 쓰기 경로가 규칙을 **실제로** 통과하는지 본다. 규칙을 못 지킨 쓰기는 조용히 거부되므로
/// 단위 테스트로는 절대 안 잡힌다(설계서 §12.3). 에뮬레이터만 상대한다.
@MainActor
struct ChildTrailWriteTests {

    init() async throws { EmulatorHarness.start() }

    @Test("아이 세션이 자기 상태 문서를 platform 까지 포함해 쓴다 — 규칙이 통과시킨다")
    func 상태문서_쓰기() async throws { … }

    @Test("아이 세션이 자기 하루 문서를 쓴다")
    func 하루문서_쓰기() async throws { … }

    @Test("올린 하루 문서를 보호자가 TrailRepository.fetch 로 그대로 읽는다 — 필드가 한 칸도 안 샌다")
    func 보호자가_읽는다() async throws {
        // 이 테스트가 1단계의 핵심 계약이다: 아이가 쓴 것을 지금 있는 보호자 코드가
        // **한 줄도 안 고치고** 읽는다.
        …
        let doc = try #require(try await TrailRepository.fetch(familyId: familyId, childUid: child.uid, dayKey: dayKey))
        #expect(doc.points.count == 원본.count)
        #expect(doc.segments.first?.type == "STAY")
        #expect(doc.points.first?.speed == 1.25)   // speed 가 0 으로 굳지 않는다
    }

    @Test("남의 아이 자리에 쓰면 거부된다(firestore.rules:148, :165)")
    func 남의_자리는_거부() async throws { … }

    @Test("보호자 세션이 아이의 trails 에 쓰면 거부된다")
    func 보호자는_못_쓴다() async throws { … }
}
```

`ChildSimHarnessTests.swift` — 인자 파싱만(출시 빌드에서는 늘 nil).

- [ ] **Step 2: 실패를 확인한다**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/TrackingCoordinatorTests -only-testing:KidCareTests/ChildDocumentsTests -only-testing:KidCareTests/ChildTrailWriteTests`
Expected: 컴파일 실패.

- [ ] **Step 3: 문서 쓰기 모양과 저장소**

`ios/KidCare/Core/Documents.swift`:

1. `ChildStatusDoc` 에 읽기 필드 하나를 더한다.

```swift
    /// 아이 폰이 아이폰인가. `"ios"` 면 아이폰, **빈 값이면 안드로이드로 본다**(설계서 §10.1).
    /// 지금 서버에 있는 모든 아이 문서에 이 필드가 없고, 모르는 아이의 기능을 조용히 없애면 안 된다.
    /// 읽는 쪽(보호자 화면 잠금)은 4단계다 — 1단계는 아이 폰이 **심기만** 한다.
    var platform: String
```
`init?` 에 `platform = data["platform"] as? String ?? ""` 를 더한다.

2. 쓰기 모양 넷을 더한다. `TrailPoint`·`SegmentDoc` 에는 memberwise `init` 도 함께 낸다(지금은 `init?([String:Any])` 뿐이다).

```swift
extension TrailPoint {
    /// 정본은 코틀린 `TrailPoint`(`Documents.kt:163-167`). **다섯 필드뿐이다** — `battery` 를 넣지
    /// 않는다(배열 원소마다 필드 이름이 같이 저장돼 안 쓰는 필드 하나가 하루 문서 크기를 그대로 키운다).
    ///
    /// 안드로이드는 `Float` 를 넣으므로 서버에 `Double(Float(12.3))` 이 저장되고 아이폰은 `12.3` 이
    /// 저장된다. 둘 다 Firestore 의 `double` 이고 보호자 코드는 `double(_:)` 하나로 읽는다 —
    /// 마지막 비트 차이는 지도·타임라인 어디서도 안 보인다(1단계 판정 기록 11).
    var firestoreData: [String: Any] {
        ["lat": lat, "lng": lng, "accuracy": accuracy, "speed": speed, "at": at]
    }
}

extension TrailDoc {
    var firestoreData: [String: Any] {
        [
            "dayKey": dayKey,
            "points": points.map(\.firestoreData),
            "segments": segments.map(\.firestoreData),
            "updatedAt": updatedAt,
        ]
    }
}

/// `children/{childUid}` 에 덮어쓸 값. 읽기용 [ChildStatusDoc] 과 따로 두는 이유는 두 모양이
/// 실제로 다르기 때문이다 — `lastSeenServerAt` 은 읽을 때 `Timestamp` 지만 쓸 때는
/// `FieldValue.serverTimestamp()` 고, `wifiOn` 은 아이폰이 아예 안 쓴다.
struct ChildStatusWrite {
    let fix: Fix
    let battery: Int
    let charging: Bool
    let network: String

    var firestoreData: [String: Any] {
        [
            "lat": fix.lat,
            "lng": fix.lng,
            "accuracy": fix.accuracy,
            "at": fix.at,
            "battery": battery,
            "charging": charging,
            // **빈 값을 명시적으로 쓴다**(1단계 판정 기록 10). 아이폰은 소리 모드를 읽을 API 가
            // 없고, 필드를 빼면 코틀린·스위프트 양쪽의 기본값 "normal" 이 살아나 부모 화면이
            // "벨소리"라고 거짓말한다. 빈 값이 "모른다"다.
            "ringerMode": "",
            "dnd": "",
            "network": network,
            // `wifiOn` 은 **안 쓴다.** 아이폰은 와이파이 스위치를 못 읽고, false(꺼짐)와 없음(모름)은
            // 다른 말이다(`Documents.kt:108-110`).
            //
            // 옛 필드는 그대로 계속 쓴다 — 아직 새 버전을 못 깐 보호자 폰이 있을 수 있고,
            // 이 값이 없으면 그 화면은 "마지막 신호"를 아예 못 만든다(`StatusReporter.kt:58-60`).
            "lastSeenAt": Int64(Date().timeIntervalSince1970 * 1000),
            // 서버가 자기 시각으로 채운다. 여기서 아이 폰 시계로 채우면 이 필드를 만든 이유가
            // 사라진다(`StatusReporter.kt:61-65` 의 @ServerTimestamp 자리).
            "lastSeenServerAt": FieldValue.serverTimestamp(),
            // 설계서 §10.1. 규칙에 `hasOnly` 가 없어(`firestore.rules:145-148`) 새 필드가 이미 허용된다.
            "platform": "ios",
        ]
    }
}
```

`ios/KidCare/Core/TrailRepository.swift` — 머리 주석의 "**쓰기는 없다** — 보호자 앱은 이 문서들을 읽기만 한다"를 고치고 `save` 를 더한다.

```swift
    /// 그 날 문서를 통째로 덮어쓴다. **쓰기 한 번**이다. 정본은 `core/TrailRepository.kt:31`.
    ///
    /// **아이 역할일 때만 부른다.** 규칙이 `request.auth.uid == childUid` 로 막고 있어
    /// (`firestore.rules:165`) 보호자 세션이 부르면 조용히 거부된다 — 그 거부를 테스트로 박아
    /// 두었다(`ChildTrailWriteTests.보호자는_못_쓴다`).
    ///
    /// 재시도를 새로 만들지 않는다. Firestore SDK 의 오프라인 큐가 이미 한다
    /// (`known-issues.md` 19번) — `setData` 는 로컬에 즉시 반영되고 연결이 돌아오면 저절로 나간다.
    /// 하루 문서는 같은 문서를 덮어쓰므로 큐에 여러 번 쌓여도 마지막 것만 의미가 있다(설계서 §6.5).
    static func save(familyId: String, childUid: String, doc: TrailDoc) async throws {
        try await trailRef(familyId: familyId, childUid: childUid, dayKey: doc.dayKey).setData(doc.firestoreData)
    }
```

`ios/KidCare/Core/ChildStatusReporter.swift` — `child/StatusReporter.kt` 의 `report` 만 옮긴다(`reportRingerMode` 는 소리 모드가 없으므로 **안 옮긴다**).

- [ ] **Step 4: `TrailUploader` 와 `TrackingCoordinator`**

`Child/TrailUploader.swift` — `TrailUploader.kt` 의 `upload`/`uploadLocked`/`buildSegments` 를 옮긴다. 1단계에서 다른 점 둘.

```swift
    /// **머무름에 이름을 안 붙인다.** 역지오코딩(`Child/PlaceNamer`)은 2단계다 — 그때까지
    /// `placeName` 은 전부 빈 문자열이고, 보호자 타임라인은 그 구간을 "머무른 곳"으로 표시한다
    /// (`SegmentDoc.placeName` 주석의 이미 정해진 동작). 2단계가 이 함수 안에서
    /// `GEOCODE_BUDGET_MILLIS`(3초, `TrailUploader.kt:235`) 예산으로 이름을 채운다.
    private func buildSegments(_ points: [Fix]) -> [SegmentDoc] {
        SegmentBuilder.build(points: points).map {
            SegmentDoc(
                type: $0.type == .stay ? "STAY" : "MOVE",   // 코틀린 `SegmentType.name` 그대로
                startAt: $0.startAt, endAt: $0.endAt,
                lat: $0.lat, lng: $0.lng,
                distanceMeters: $0.distanceMeters, pointCount: $0.pointCount,
                placeName: ""
            )
        }
    }

    /// 업로드가 겹치는 것을 막는다. 코틀린은 `Mutex.tryLock()` 으로 "이미 도는 중이면 이번은
    /// 건너뛴다"만 한다(`TrailUploader.kt:58-64`) — 대기하면 큐에 쌓였다가 이미 최신인 문서를
    /// 다시 쓰는 헛일이 된다. `@MainActor` 라 `Bool` 플래그 하나면 같은 일을 한다.
    private var uploading = false
```

그리고 **구간은 솎기 전 원본으로 계산한다**(`TrailUploader.kt:135-138`, 설계서 §6.3). 서버 상한에 맞춘 뒤 계산하면 머무름 경계점이 빠질 수 있다.

```swift
        let rawPoints = buffer.points
        let points = TrailCodec.capped(rawPoints)   // 2000 상한, LTTB
        let segments = buildSegments(rawPoints)     // ← 원본 전체
```

`Child/TrackingCoordinator.swift` — 설계서 §6.1 의 10단계를 그 순서로 쓴다. 뼈대만 적는다(주석에 각 단계의 코틀린 줄 번호를 단다).

```swift
import Foundation

/// 점 하나가 들어왔을 때의 순서를 정한다. 정본은 안드로이드 `TrackingService.handle()`(:532-699).
/// **순서가 곧 계약이다** — 설계서 §6.1 의 10단계 그대로다.
///
/// `@MainActor` 인 이유는 `LocationCollector` 와 같다 — 버퍼를 만지는 스레드가 하나로 유지돼
/// 잠금이 필요 없어진다(`TrailUploader.kt:91-93`).
@MainActor
final class TrackingCoordinator {

    /// `TrackingService.kt:905`.
    static let stayAnchorIntervalMillis: Int64 = 5 * 60_000
    /// `:912`.
    static let coordinateKickWindowMillis: Int64 = 5 * 60_000
    /// 설계서 §6.4. 아무리 잦아도 이보다 자주 안 올린다.
    static let uploadMinIntervalMillis: Int64 = 15 * 60_000
    /// 설계서 §6.4. 안드로이드의 `SAFETY_UPLOAD_INTERVAL_MILLIS`(24시간, `:902`)를 내린 값이다 —
    /// 안드로이드는 그 사이 `locate_now` 로 언제든 최신을 받을 수 있지만 아이폰은 그 통로가 없다.
    static let uploadIdleIntervalMillis: Int64 = 4 * 60 * 60_000
    /// 설계서 §6.4-3. 한 점에서 사건이 둘 이상 날 수 있다(`known-issues.md` 21번).
    static let uploadEventMinGapMillis: Int64 = 60_000

    private(set) var lastFix: Fix?
    private(set) var lastTrailFix: Fix?
    private var lastUploadAt: Int64 = 0          // 메모리에만 둔다(1단계 판정 기록 15)
    private var lastUploadedFix: Fix?
    private let detector = AdaptiveMovementDetector()
    private var insideKnownPlace = false         // 2단계가 켠다
    private var slowProbeSince: Int64?
    private var lastRouteWasMoving = false
    private var forceNextStayPoint = true
    private var coordinateKickExpiresAt: Int64?

    /// 2단계가 잇는 자리. **지금 자리에 둬야** 나중에 순서가 안 틀어진다(1단계 판정 기록 7).
    var onCondition: ((Int64) -> Void)?          // 1번 (3단계: ConditionWatcher)
    var updateKnownPlace: ((Fix) -> Bool)?       // 3번 (2단계: PlaceWatcher.isInsideKnownPlace)
    var onPlaceFix: ((Fix) -> Void)?             // 8번 (2단계: PlaceWatcher.onFix)

    func handle(_ fix: Fix, eventJustWritten: Bool = false) {
        // 1. 상태 검사 — 점을 버릴지와 무관하게 **먼저** 한다(:533-537).
        onCondition?(fix.at)

        // 2. 시계 역행 감지 → 기준점 초기화(:552-568).
        if let previous = lastFix, fix.at < previous.at { 기준점을_버린다() }

        // 3. 등록 장소 안/밖 갱신 → 모드 바꿈(:479-494). 1단계에서는 훅이 nil 이라 늘 false 다.
        let exitedKnownPlace = updateKnownPlace?(fix) ?? false

        // 4. 판정기(:583).
        let update = detector.onFix(fix)
        slowProbeSince = (update.state == .slowProbe) ? (slowProbeSince ?? fix.at) : nil
        source?.updateMode(state: update.state, insideKnownPlace: insideKnownPlace, slowProbeSince: slowProbeSince, now: fix.at)

        // 5. MOVING 이면 경로점 선별, 아니면 5분 기준점(:592-615). 좌표 변위 증거면 이동 확인을 켠다.
        …
        // 6. 좌표 변위 이동 확인 만료(:621-627).
        …
        // 7. LocationFilter.decide.
        let decision = LocationFilter.decide(previous: lastFix, candidate: fix)

        // 8. 거절(정확도·순간이동)이 아니면 장소 판정(:637-639).
        //    **7번의 결과에 안 묶인다** — SKIP_TOO_CLOSE 도 넘긴다. 경계에서 몇 걸음 옮겨 안으로
        //    들어간 순간이 정확히 그 모양이다(:631-636).
        if decision != .rejectInaccurate, decision != .rejectImpossible { onPlaceFix?(fix) }

        // 9. UPLOAD / UPLOAD_STALE_FALLBACK 이면 lastFix = fix.
        switch decision {
        case .upload: break
        case .uploadStaleFallback: 로그를_남긴다()   // 완화 승인이 조용하면 '정확도 기아'를 못 가른다
        case .skipTooClose, .rejectInaccurate, .rejectImpossible: return
        }
        lastFix = fix

        // 10. 업로드 시각 검사(설계서 §6.4).
        if shouldUpload(now: fix.at, fix: fix, eventJustWritten: eventJustWritten) {
            // 실패해도 시각을 먼저 갱신한다 — 실패가 이어질 때 fix 마다 재시도해 같은 비용을
            // 반복해서 물지 않는다(:679-681). 백오프는 두지 않는다(설계서 §4.11·§6.5).
            lastUploadAt = fix.at
            lastUploadedFix = fix
            Task { await uploadNow() }
        }
    }

    /// 설계서 §6.4 의 규칙 셋. 점이 들어올 때마다 판정한다 — 따로 타이머를 걸지 않는다
    /// (안드로이드가 같은 이유로 알람을 안 건다, `TrackingService.kt:392-394`).
    func shouldUpload(now: Int64, fix: Fix, eventJustWritten: Bool) -> Bool {
        // 3. 사건 직후에는 1·2번을 무시한다. 다만 1분 안이면 건너뛴다.
        //    부르는 쪽은 2단계다(1단계 판정 기록 14).
        if eventJustWritten { return now - lastUploadAt >= Self.uploadEventMinGapMillis }
        // 1. 15분 **그리고** 25m.
        if now - lastUploadAt >= Self.uploadMinIntervalMillis {
            guard let last = lastUploadedFix else { return true }   // 한 번도 안 올렸으면 거리 조건은 만족
            if LocationFilter.distanceMeters(last, fix) >= LocationFilter.minMoveMeters { return true }
        }
        // 2. 안 움직였어도 4시간.
        return now - lastUploadAt >= Self.uploadIdleIntervalMillis
    }

    /// 지금 상태와 오늘 경로를 올린다. **쓰기 두 번**(상태 문서 1, 하루 문서 1)이고
    /// 이 앱에서 위치 데이터가 서버로 가는 유일한 경로다(`TrackingService.kt:719-729`).
    ///
    /// **위치를 한 번도 못 잡았으면 올리지 않는다.** 안드로이드는 그때 예외를 던져 명령이 실패로
    /// 끝나는데(:720), 아이폰은 물어본 사람이 없으니 조용히 건너뛰고 로그만 남긴다(설계서 §6.4 끝).
    /// 파일에서 복구한 옛 점으로 대신 채우지 않는 것도 같은 이유다 — 그 점은 몇 시간 전일 수 있는데
    /// 상태 문서에 넣는 순간 서버 시각이 "방금"으로 찍힌다(:713-717).
    func uploadNow() async { … }
}
```

- [ ] **Step 5: `ChildSimHarness` 와 `RouterView` 분기(판정 기록 9·20)**

```swift
import Foundation

#if DEBUG
/// **시뮬레이터에서 아이 파이프라인을 띄우는 임시 문**이다(1단계 계획서 판정 기록 9).
///
/// 역할 선택 화면의 막이 제거와 진짜 `ChildRootView` 는 **3단계**다(설계서 §14). 그런데 1단계의
/// 완료 기준이 "GPX 를 먹이면 보호자가 그 경로를 그린다"라 띄울 방법이 필요하다.
/// `Guardian/ReadOnlyCheck.swift` 가 이미 같은 모양(DEBUG 빌드 + 실행 인자)의 선례다.
///
/// **3단계가 `ChildRootView` 를 만들면 이 파일과 `ChildSimView` 를 지운다.**
/// 출시 빌드에는 `#if DEBUG` 밖이라 존재 자체가 없다.
enum ChildSimHarness {
    struct Launch: Equatable {
        let familyId: String
        /// 시뮬레이터는 배터리를 안 준다(판정 기록 8). `-childSimBattery 77` 로 넣는다.
        let battery: Int?
    }

    /// `-childSim <familyId> [-childSimBattery <0~100>]`.
    static let launch: Launch? = parse(ProcessInfo.processInfo.arguments)

    static func parse(_ arguments: [String]) -> Launch? { … }
}
#endif
```

`ios/KidCare/RouterView.swift` 의 `body` 의 `Group { … }` 첫 갈래로 넣는다. `isRunningTests` **위**다 — 사람이 일부러 준 인자가 이긴다.

```swift
        Group {
            #if DEBUG
            if let sim = ChildSimHarness.launch {
                // 1단계 판정 기록 9·20. 3단계가 ChildRootView 를 만들면 이 세 줄을 지운다.
                ChildSimView(launch: sim)
            } else if isRunningTests {
            #else
            if isRunningTests {
            #endif
                Color.clear
            } else if showMain, let familyId = store.familyId {
            …
```

> `#if` 로 `if/else if` 사슬을 쪼개면 읽기 어렵다. **더 나은 모양**: `body` 맨 위에서 한 번만 갈라라.
> ```swift
>     var body: some View {
>         #if DEBUG
>         if let sim = ChildSimHarness.launch { return AnyView(ChildSimView(launch: sim)) }
>         #endif
>         return AnyView(본_화면)
>     }
> ```
> 둘 중 컴파일되는 쪽을 고르되, **기존 `isRunningTests` 갈래의 동작을 바꾸지 않는다**(그 주석이 이유를 길게 적어 뒀다).

`ChildSimView` 는 SwiftUI 화면 하나다: 익명 로그인한 **uid 를 크게**, 지금 모드·버퍼 점 개수·마지막 업로드 시각, 그리고 '지금 올리기' 버튼 하나(`coordinator.uploadNow()` 를 직접 부른다 — 판정을 건너뛴다). **문구 키를 만들지 않는다**(판정 기록 9).

- [ ] **Step 6: 통과 확인**

```bash
cd /Users/com/work/KidCare/ios
xcodegen generate
xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: 전부 통과. 에뮬레이터 테스트가 실제로 돌았는지(건너뛰지 않았는지) 개수로 확인한다.

- [ ] **Step 7: 커밋** (공통 절차 B)

```
iOS 아이 1단계 Task 4: 점 하나가 지나는 길과 하루 문서 — 안드로이드와 같은 모양으로 올린다
```

---
### Task 5: 단계 마무리 — 통합 리뷰 한 번, GPX 시뮬레이터 확인 한 번

**끝나면 시뮬레이터에서 걸어 다닌 '아이'가 만든 경로를 지금 있는 보호자 앱이 그대로 그린다.** 이 Task 는 새 기능을 만들지 않는다 — 네 Task 가 각자 초록인 것과, 넷을 이어 붙였을 때 한 덩어리로 도는 것은 다른 얘기다.

**Files:**
- Create: `ios/Fixtures/child-sim-seoul-walk.gpx`
- Modify: 여기서 찾은 결함을 고치는 파일들(있으면)

- [ ] **Step 1: 기계 검사**

```bash
cd /Users/com/work/KidCare
# 안드로이드는 골든 생성기 한 파일만 바뀌었다.
git diff --stat 4bda965..HEAD -- app firestore.rules gradlew
# Logic/ 은 Foundation 만 import 한다.
grep -rn "^import " ios/KidCare/Logic | grep -v "import Foundation" ; echo "위가 비어 있어야 한다"
# 금지 표현.
grep -rn "@unchecked Sendable\|nonisolated(unsafe)\|navigationBarBackButtonHidden" ios/KidCare
# 명령을 안 듣는다.
grep -rn "CommandRepository\|locate_now\|start_live_tracking\|commands" ios/KidCare/Child ios/KidCare/Core/ChildStatusReporter.swift
# 이유 필요 API 를 새로 안 부른다(판정 기록 12).
grep -rn "modificationDate\|attributesOfItem\|systemUptime\|mach_absolute_time" ios/KidCare
# 출시 빌드에 시뮬레이터 문이 없다.
grep -n "#if DEBUG" ios/KidCare/Child/ChildSimHarness.swift ios/KidCare/Child/ChildSimView.swift
# 문구.
python3 tools/ios-strings.py --check; echo $?          # 0
swift tools/check-i18n-keys.swift | tail -3            # 빈 칸이 언어당 2키 늘었다
# 테스트 전부.
cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5
```

테스트 개수를 **N** 으로 적어 둔다(선행 조건의 M 과 함께 개발일지에 쓴다 — 개발일지 자체는 3단계나 주인이 정하는 시점에 쓴다).

- [ ] **Step 2: 상수 대조표를 코드와 한 줄씩 대조한다**

설계서 §4 의 표를 **위에서 아래로** 읽으며 Swift 코드와 맞춘다. 기계가 이미 지키는 것(§4.1~4.5 의 상수)은 골든 `constants` 테스트가 있으므로 **그 테스트가 그 상수를 실제로 보는지**만 본다. 기계가 못 지키는 것은 눈으로 본다.

| 설계서 | 어디서 확인 |
|---|---|
| §4.1 `LocationFilter` 일곱 | `GoldenComparisonTests.위치필터_상수가_같다`(여섯) + `earthRadiusMeters` 는 `거리_대조` 가 간접 확인 |
| §4.2 `AdaptiveMovementDetector` 열셋 | `판정기_상수가_같다` |
| §4.3 `MovementTrailFilter` 아홉 | `경로필터_상수가_같다` |
| §4.4 `SegmentBuilder` 넷 | `구간_상수가_같다` |
| §4.5 `TrailCodec.MAX_POINTS` | `솎기_상수가_같다` |
| §4.8 수집 모드 표 + `STILL_ESCALATE_MILLIS` | `CollectionModeTests`(골든 없음 — 안드로이드에 대응 함수가 없다) |
| §4.9 `STAY_ANCHOR`·`COORDINATE_KICK`·업로드 주기 | `TrackingCoordinatorTests` |
| §4.10 `GEOCODE_BUDGET`·`PlaceNamer`·`MAX_GEOFENCES`·`LOW_PERCENT` | **2·3단계다.** 1단계에 없는 것이 맞다 |
| §4.10 `FILE_NAME` = `trail_today.csv` | `TrailStoreTests` |

- [ ] **Step 3: 통합 리뷰** — superpowers:requesting-code-review 로 **1단계 첫 커밋의 부모부터 HEAD 까지**를 한 번 리뷰받는다. 리뷰어에게 이 계획서의 "판정 기록" 스무 줄과 아래 Pre-flight conflict table 을 함께 준다. 특히 여섯 가지를 봐 달라고 적는다.

1. **골든이 정말 스윕인가.** 다섯 파일의 `cases` 가 경계 양옆을 실제로 담고 있는가. 코틀린 생성기의 `check()` 가 "이름만 경계"인 케이스를 잡는가.
2. **`Float` → `Double` 이 문턱을 옮기지 않았는가.** 판정 기록 2 의 두 상수와, 상수를 쓰는 **모든** 비교식.
3. **§6.1 의 10단계 순서가 코틀린과 한 줄씩 같은가.** 특히 8번이 7번에 안 묶이는 것, 1번이 맨 앞인 것, 9번이 `SKIP_TOO_CLOSE` 에서 `lastFix` 를 안 미는 것.
4. **Swift 6 엄격 동시성에서 도망친 자리가 없는가.** `@unchecked Sendable`·`nonisolated(unsafe)` 가 없고, `MainActor.assumeIsolated` 가 쓰인 자리가 실제로 메인인 근거가 주석에 있는가.
5. **상태 문서가 거짓말하지 않는가.** `ringerMode`/`dnd` 가 빈 값으로 **실제로 나가는가**, `wifiOn` 이 없는가, `platform` 이 있는가, `lastSeenServerAt` 이 서버 시각인가, 복구된 옛 점으로 쓰지 않는가.
6. **강제 종료를 없는 일로 적은 곳이 없는가**(판정 기록 17). 주석·문구·로그 전부.

- [ ] **Step 4: 시뮬레이터 확인 준비 — 에뮬레이터에만 쓴다**

6단계 단계 마무리 Step 3 과 같은 순서다. **에뮬레이터는 이미 떠 있다 — 다시 띄우지 않는다.**

1. `ios/KidCare/KidCareApp.swift` 를 **잠시** `FirebaseBootstrap.configureForEmulator(projectId: "kidcare-emulator")` 로 바꾼다.
2. 보호자용과 아이용으로 시뮬레이터 **둘**을 쓴다. 둘 다 이미 부팅돼 있는 것을 쓰고, **끄거나 지우지 않는다.**

```bash
xcrun simctl list devices booted            # 부팅된 것 확인. 둘이 없으면 하나를 boot 한다(erase 하지 않는다)
GUARDIAN=$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; print([d["udid"] for v in json.load(sys.stdin)["devices"].values() for d in v if d["name"]=="iPhone 17"][0])')
CHILD=$(xcrun simctl list devices booted -j    | python3 -c 'import json,sys; print([d["udid"] for v in json.load(sys.stdin)["devices"].values() for d in v if d["name"]!="iPhone 17"][0])')
echo "보호자=$GUARDIAN 아이=$CHILD"
```

3. 두 시뮬레이터에 **덮어 설치한다**(지우지 않는다).

```bash
cd /Users/com/work/KidCare/ios
xcodebuild -project KidCare.xcodeproj -scheme KidCare -destination "platform=iOS Simulator,id=$GUARDIAN" -derivedDataPath /tmp/kidcare-dd-sim build
APP=/tmp/kidcare-dd-sim/Build/Products/Debug-iphonesimulator/KidCare.app
xcrun simctl install "$GUARDIAN" "$APP"
xcrun simctl install "$CHILD" "$APP"
```

4. 보호자 시뮬레이터에서 앱을 열어 **보호자 → 새 가족 만들기**로 가족을 만든다. 가족 ID 를 잡는다.

```bash
EMU="http://127.0.0.1:8080/v1/projects/kidcare-emulator/databases/(default)/documents"
AUTH="Authorization: Bearer owner"
FAMILY=$(curl -s -H "$AUTH" "$EMU/families" | python3 -c 'import json,sys; print(json.load(sys.stdin)["documents"][-1]["name"].split("/")[-1])')
echo "가족=$FAMILY"
```

5. 아이 시뮬레이터에서 **아이 문을 열고 uid 를 읽는다.** 화면에 uid 가 크게 뜬다.

```bash
xcrun simctl launch "$CHILD" com.kidcare.family -childSim "$FAMILY" -childSimBattery 77
xcrun simctl io "$CHILD" screenshot /tmp/p1-00-uid.png      # uid 를 눈으로 읽는다
CHILD_UID=<화면에서 읽은 uid>
```

6. 그 uid 를 **아이 멤버로 심는다.** owner 토큰은 규칙을 건너뛰므로 **데이터 준비에만** 쓴다 — 규칙은 `ChildTrailWriteTests` 가 이미 태웠다.

```bash
NOW=$(python3 -c 'import time; print(int(time.time()*1000))')
curl -s -X PATCH -H "$AUTH" -H "Content-Type: application/json" "$EMU/families/$FAMILY/members/$CHILD_UID" \
  -d "{\"fields\":{\"role\":{\"stringValue\":\"child\"},\"displayName\":{\"stringValue\":\"민준\"},\"fcmToken\":{\"stringValue\":\"\"},\"appVersion\":{\"stringValue\":\"\"},\"joinCode\":{\"stringValue\":\"\"},\"updatedAt\":{\"integerValue\":\"$NOW\"},\"joinedAt\":{\"integerValue\":\"$NOW\"}}}" > /dev/null
```

7. 아이 시뮬레이터에서 위치 권한 대화상자에 **'앱을 사용하는 동안 허용' → '항상 허용'** 순으로 답한다(설계서 §8.1 의 두 걸음). 파란 위치 표시가 상태 막대에 뜨는지 본다.

- [ ] **Step 5: GPX 파일을 만든다**

`ios/Fixtures/child-sim-seoul-walk.gpx` — 서울시청 앞에서 광화문 쪽으로 약 600m 를 걷는 경로다. 좌표는 **50m 간격 13점**이라 5초 게이트(이동 확정 시)와 3m 거리 필터를 넉넉히 넘긴다.

**이 Xcode 의 `xcrun simctl location start` 는 GPX 파일 경로를 안 받는다.** `lat,lon` 인자 나열(또는 `-` 로 표준입력)만 받는다(`simctl help location` 으로 확인). 그래서 이 파일은 **경로의 정본**으로 두고, 재생할 때 좌표만 뽑아 넘긴다 — Step 6 의 `WALK` 가 그 한 줄이다. 파일을 없애고 좌표를 명령에 박지 않는 이유는 경로를 고칠 자리가 하나여야 하기 때문이다(보호자 화면에서 무엇이 그려져야 하는지도 이 파일이 말한다).

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!-- 시뮬레이터에 먹이는 도보 경로(1단계 계획서 Task 5). 서울시청 → 광화문, 약 600m.
     재생은 이 파일을 그대로 넘기는 것이 아니라 좌표만 뽑아
     `xcrun simctl location <UDID> start --speed=1.3 --interval=1 <lat,lon> …` 로 넘긴다
     (simctl 은 GPX 경로를 안 받는다). 시뮬레이터가 두 점 사이를 보간한다.
     <time> 을 일부러 안 넣는다 — 넣으면 재생 시각이 파일에 박혀 며칠 뒤 돌릴 때
     "몇 년 전 점"이 들어오고, LocationFilter 가 시계 역행으로 읽는다. -->
<gpx version="1.1" creator="KidCare" xmlns="http://www.topografix.com/GPX/1/1">
  <wpt lat="37.56650" lon="126.97800"/>
  <wpt lat="37.56695" lon="126.97791"/>
  <wpt lat="37.56740" lon="126.97782"/>
  <wpt lat="37.56785" lon="126.97773"/>
  <wpt lat="37.56830" lon="126.97764"/>
  <wpt lat="37.56875" lon="126.97755"/>
  <wpt lat="37.56920" lon="126.97746"/>
  <wpt lat="37.56965" lon="126.97737"/>
  <wpt lat="37.57010" lon="126.97728"/>
  <wpt lat="37.57055" lon="126.97719"/>
  <wpt lat="37.57100" lon="126.97710"/>
  <wpt lat="37.57145" lon="126.97701"/>
  <wpt lat="37.57190" lon="126.97692"/>
</gpx>
```

- [ ] **Step 6: 시뮬레이터에서 하루를 재생한다 (약 20분)**

**시간이 실제로 든다.** 머무름은 `MIN_STAY_MILLIS`(5분)와 `STAY_ANCHOR_INTERVAL_MILLIS`(5분)가 정하므로 줄일 방법이 없고, 줄이려고 상수를 만지지 않는다. 항목마다 `xcrun simctl io "$CHILD" screenshot /tmp/p1-<번호>.png` 로 남긴다.

**먼저 이 두 가지를 알고 시작한다(실제로 겪은 것이다).**

- **`location set`(정적 좌표)으로는 머무름을 재현할 수 없다.** 좌표가 **한 번만** 전달되고 그 뒤 콜백이 끊긴다. 실제 폰은 가만히 있어도 GPS 가 ±몇 m 씩 흔들려 콜백이 계속 오므로, 제자리를 아주 느리게(`--speed=0.06`) 도는 웨이포인트로 흉내 내야 같은 모양이 된다.
- **`location start` 는 GPX 파일을 안 받는다.** `lat,lon` 을 나열하거나 `-` 로 표준입력에서 한 줄에 하나씩 읽는다. 아래 `WALK` 가 Step 5 의 GPX 에서 좌표를 뽑는다.

```bash
# Step 5 의 GPX 가 경로의 정본이다 — 여기서 좌표만 뽑아 simctl 인자로 만든다.
WALK=$(python3 - <<'EOF'
import re
src = open('/Users/com/work/KidCare/ios/Fixtures/child-sim-seoul-walk.gpx').read()
print(' '.join(f'{lat},{lon}' for lat, lon in re.findall(r'lat="([-0-9.]+)"\s+lon="([-0-9.]+)"', src)))
EOF
)
echo "$WALK"   # 13쌍이 한 줄로 나온다
# 제자리 흔들림(약 ±3m 사각형 한 바퀴). 0.06m/s 로 돌면 한 바퀴가 약 5분이다.
JITTER_START="37.566527,126.978000 37.566519,126.978024 37.566500,126.978034 37.566481,126.978024 37.566473,126.978000 37.566481,126.977976 37.566500,126.977966 37.566519,126.977976 37.566527,126.978000"
JITTER_END="37.571927,126.976920 37.571919,126.976944 37.571900,126.976954 37.571881,126.976944 37.571873,126.976920 37.571881,126.976896 37.571900,126.976886 37.571919,126.976896 37.571927,126.976920"
```

1. **출발 머무름(약 12분).** 제자리 흔들림을 재생한다. 한 바퀴가 약 5분이라 **두 번 건다**(두 번째는 첫 번째가 끝난 뒤에 건다 — 새 `start` 가 이전 재생을 덮어쓴다).
   ```bash
   xcrun simctl location "$CHILD" start --speed=0.06 --interval=1 $JITTER_START
   ```
   - 아이 화면의 버퍼 점 개수가 **1** 이 된다(첫 점은 `forceNextStayPoint` 라 무조건 남는다).
   - **곧바로 업로드가 한 번 나간다**(`lastUploadAt == 0`, 설계서 §10.1). 확인:
     ```bash
     curl -s -H "$AUTH" "$EMU/families/$FAMILY/children/$CHILD_UID" | python3 -m json.tool | head -40
     ```
     `platform: "ios"`, `battery: 77`, `ringerMode: ""`, `dnd: ""`, `network`, `lastSeenServerAt`(서버 시각)이 보이고 **`wifiOn` 이 없다.**
   - 5분이 지나면 점 개수가 **2** 가 된다(5분 기준점).
   - 수집 모드가 `slowProbe` → 5분 뒤 `still` 로 내려가는 것을 화면에서 본다(`STILL_ESCALATE_MILLIS`).

2. **걷기(약 8분).** 보행 속도 1.3m/s, 갱신은 1초에 한 번(실제 폰과 같은 밀도로 들어오고, 5초 게이트가 솎는다).
   ```bash
   xcrun simctl location "$CHILD" start --speed=1.3 --interval=1 $WALK
   ```
   - 모드가 `still`/`slowProbe` → `fastProbe` → `moving` 으로 올라간다. 30초 안에 `moving` 이 돼야 한다(판정기 확인 창).
   - 버퍼 점이 **5초에 하나씩** 는다 — 이것이 "밀도가 안드로이드와 같다"의 눈으로 보는 증거다.
   - 15분째에 주기 업로드가 나간다. 기다리지 않으려면 **'지금 올리기'** 를 누른다.
   - 약 600m 를 1.3m/s 로 걸으므로 재생 자체가 **약 8분**이다. 끝나면 마지막 점에서 좌표가 멎는다.

3. **도착 머무름(약 12분).** 끝점에서 같은 흔들림을 건다(`set` 은 쓰지 않는다 — 위 두 가지 참고).
   ```bash
   xcrun simctl location "$CHILD" start --speed=0.06 --interval=1 $JITTER_END
   ```
   - 5분 뒤 두 번째 머무름이 생긴다. '지금 올리기'를 누른다.
   - **여기서 시계(`TrackingTicker`)도 함께 본다.** 재생이 끝나 좌표가 완전히 멎어도 모드가 `moving` 에 남지 않고 60초 안에 내려간다 — 좌표 없이 도는 시계가 없으면 걸리던 자리다(통합 리뷰 I1). 확인하려면 흔들림을 걸지 말고 `xcrun simctl location "$CHILD" clear` 로 좌표를 끊은 뒤 화면의 수집 모드를 본다.

4. **하루 문서를 본다.**
   ```bash
   DAY=$(python3 -c 'import time; print(time.strftime("%Y-%m-%d"))')
   curl -s -H "$AUTH" "$EMU/families/$FAMILY/children/$CHILD_UID/trails/$DAY" | python3 - <<'EOF'
   import json, sys
   d = json.load(sys.stdin)["fields"]
   pts = d["points"]["arrayValue"].get("values", [])
   segs = d["segments"]["arrayValue"].get("values", [])
   print("dayKey", d["dayKey"]["stringValue"], "점", len(pts), "구간", len(segs))
   print("점 필드", sorted(pts[0]["mapValue"]["fields"])) if pts else None
   for s in segs:
       f = s["mapValue"]["fields"]
       print(f["type"]["stringValue"], f["startAt"]["integerValue"], f["endAt"]["integerValue"],
             round(float(f["distanceMeters"]["doubleValue"])), f["pointCount"]["integerValue"],
             repr(f["placeName"]["stringValue"]), sorted(f))
   EOF
   ```
   확인할 것 넷.
   - 점 필드가 정확히 `['accuracy','at','lat','lng','speed']` 다 — `battery` 가 없다.
   - 구간 필드가 정확히 여덟이다 — `dayKey` 가 없고 `placeName` 은 **빈 문자열**이다(이름은 2단계).
   - 구간이 `STAY` → `MOVE` → `STAY` 순이다. `MOVE` 의 `distanceMeters` 가 **550~650m** 사이다.
   - `updatedAt` 이 방금이다.

5. **보호자가 그린다 — 이 단계의 완료 기준이다.** 보호자 시뮬레이터에서 아이를 고르고 지도 탭을 연다.
   - 지도에 **경로선**이 그려진다(시청 → 광화문). 선이 건물을 가로지르는 직선 하나가 아니라 13점을 따라간다.
   - 상태 카드에 마지막 신호가 "방금 전", 배터리 77% 가 보인다.
   - 타임라인에 세 줄(머무름 · 이동 · 머무름)이 뜨고, 머무름 이름 자리는 "머무른 곳"이다(2단계가 채운다).
   - 날짜를 어제로 넘겼다 오늘로 돌아와도 같다.
   ```bash
   xcrun simctl io "$GUARDIAN" screenshot /tmp/p1-05-guardian-map.png
   ```

6. **되살아나기(설계서 §5.3, 판정 기록 16).** 아이 앱을 **종료(terminate)** 했다가 같은 인자로 다시 띄운다.
   ```bash
   xcrun simctl terminate "$CHILD" com.kidcare.family
   xcrun simctl launch "$CHILD" com.kidcare.family -childSim "$FAMILY" -childSimBattery 77
   ```
   - 버퍼 점 개수가 **0 이 아니다** — 오늘 파일에서 되찾았다.
   - 화면의 "마지막 업로드"가 비어 있다(`lastUploadAt` 이 메모리에만 있으므로 0 으로 돌아갔다, 판정 기록 15).
   - **곧바로 상태 문서를 쓰지 않는다** — 복구된 옛 점으로는 안 쓴다(`TrackingService.kt:713-717`). 새 좌표가 하나 들어온 뒤에 쓴다.
   - 이 확인은 **강제 종료가 아니다.** 강제 종료(앱 전환기에서 위로 밀기) 뒤 되살아나는지는 실기기 항목이고(설계서 §12.4-4), 이 설계는 **안 되살아난다고 가정한다**(§17 열린 질문 3).

7. **오프라인(설계서 §6.5).** 에뮬레이터를 멈추지 말고 **아이 시뮬레이터에서만** 네트워크가 끊긴 상황을 만들 방법이 없다 — 대신 보호자 앱에서 날짜를 어제로 넘겨 "이 날은 기록이 없어요"가 뜨는지 본다(`TrailRepository.fetch` 의 캐시 갈래). 이 항목은 확인만 하고 고치지 않는다.

8. **정리.**
   ```bash
   xcrun simctl location "$CHILD" clear
   ```
   시뮬레이터를 **끄지 않고 앱도 지우지 않는다.**

- [ ] **Step 7: 되돌리고 확인**

`ios/KidCare/KidCareApp.swift` 를 `configureForApp()` 로 되돌리고 `git diff ios/KidCare/KidCareApp.swift` 가 비어 있는지 확인한다. 여기서 찾은 결함은 고친 뒤 테스트를 다시 돌리고 `iOS 아이 1단계 Fix round N: …` 으로 커밋한다.

- [ ] **Step 8: 커밋** (공통 절차 B)

```
iOS 아이 1단계 마무리: 시뮬레이터가 걸은 길을 보호자 지도가 그대로 그린다
```

---

## 1단계 완료 기준

- [ ] `Logic/` 다섯(+ `Fix`·`Segment` 확장)이 Foundation 만 import 하고, 다섯 골든이 전부 초록이며, **다섯 다 일부러 망가뜨렸을 때 빨개지는 것을 확인했다.**
- [ ] 골든의 `constants` 가 설계서 §4.1~4.5 의 상수 전부를 싣고, Swift 상수와 **비트까지** 같다.
- [ ] 안드로이드 `LocationFilterTest`·`MovementTrailFilterTest`·`AdaptiveMovementDetectorTest`·`SegmentBuilderTest`·`TrailCodecTest` 의 `@Test` 가 하나도 빠짐없이 Swift 로 옮겨져 초록이다.
- [ ] `CollectionModeTests` 가 다섯 모드의 (정확도·거리 필터·간격), 분기 순서(등록 장소가 이동보다 아래), `STILL_ESCALATE_MILLIS`(5분, FAST_PROBE 로 시계 0), 간격 게이트를 고정한다.
- [ ] `TrackingCoordinatorTests` 가 §6.1 의 10단계 순서(특히 8번이 7번에 안 묶임)와 §6.4 의 업로드 규칙 셋을 고정한다.
- [ ] 에뮬레이터 테스트가 아이 세션의 상태·하루 문서 쓰기 통과와 남의 자리·보호자 쓰기 거부를 태운다.
- [ ] 시뮬레이터에 GPX 를 먹이면 `trails/{dayKey}` 가 **안드로이드와 같은 필드 집합**(점 다섯 칸·구간 여덟 칸)으로 올라가고, `children/{childUid}` 에 위치·배터리·`platform: "ios"` 가 실리며 `ringerMode`/`dnd` 는 빈 값, `wifiOn` 은 없다.
- [ ] **보호자 앱이 한 줄도 안 바뀐 채로** 그 경로를 지도에 그리고 타임라인에 세 구간을 띄운다.
- [ ] 앱을 종료했다 다시 띄우면 오늘 점을 파일에서 되찾고, 복구된 옛 점으로는 상태 문서를 쓰지 않는다.
- [ ] `Info.plist` 에 배경 모드 `location` 하나와 위치 문구 둘뿐이고, `ReleaseConfigTests` 가 그 수를 못박는다. 개인정보 매니페스트는 안 바뀌었다.
- [ ] 새 문구 키 둘이 ko·en 에만 있고 `tools/i18n-untranslated.json` 이 그만큼 늘었으며 `python3 tools/ios-strings.py --check` 가 0 이다.
- [ ] `Child/` 어디에도 명령(`commands`)을 읽거나 쓰는 코드가 없다.
- [ ] 앱 코드에 `@unchecked Sendable`·`nonisolated(unsafe)` 가 없고, `ChildSimHarness`·`ChildSimView` 는 `#if DEBUG` 안에만 있다.
- [ ] `git diff --stat 4bda965..HEAD -- app firestore.rules gradlew` 가 `GoldenFileWriterTest.kt` **한 줄만** 보여준다.

---

## 자기 검토 결과 (writing-plans self-review)

**설계서 대응.** §14 "1단계 — 위치와 경로"가 적은 다섯 덩어리를 모두 받았다.

- "`Logic/` 다섯 + `Fix.speedAccuracy`, `Segment.nameLat/nameLng`" → Task 1·2.
- "안드로이드 테스트 포팅(빨강 → 초록) + 골든 생성기 다섯 + 대조 테스트 다섯" → Task 1 Step 1·7·8, Task 2 Step 1·6·7. 브리프가 더 요구한 "일부러 망가뜨리기"는 Task 1 Step 10, Task 2 Step 9 다(설계서는 4단계에 적었는데 브리프가 각 단계로 당겼다 — **브리프가 이긴다**).
- "`Child/`: `CollectionMode`, `LocationCollector`, `TrackingCoordinator`, `TrailBuffer`, `TrailStore`, `TrailUploader`" → Task 3·4. **`DeviceState` 가 하나 더 들어갔다**(판정 기록 8) — 브리프가 상태 문서의 배터리를 1단계 산출물로 못박았기 때문이다.
- "`Core/`: `ChildStatusReporter`, `TrailRepository.save`" → Task 4 Step 3. 설계서 §3.3 이 함께 적은 `ChildStatusDoc.platform` 도 여기다(§10.1 이 "첫 좌표에서 한 번 강제 업로드"를 요구했고, 그것은 판정 기록 15 의 `lastUploadAt = 0` 이 공짜로 만든다).
- "`Info.plist` 의 `UIBackgroundModes` 와 위치 사용 설명 두 개" → Task 3 Step 6. 설계서가 예상하지 못한 것 하나를 찾았다: `ReleaseConfigTests` 가 "배경 모드 없음"을 단언하고 있었다(판정 기록 12).
- §4 상수 대조표 전부 → Task 5 Step 2 의 표가 어느 상수를 **무엇이** 지키는지 한 줄씩 적는다. §4.6·4.7·§4.10 의 장소·이름 상수는 2단계라 1단계에 없는 것이 맞다.
- §5.1 연속 스트림 + 소프트웨어 간격 → `CollectionMode` + `IntervalGate`. §5.2 매니저 설정 넷 → `LocationCollector.init`. §5.3 되살아나는 길 → 판정 기록 16(중요 위치 변경만 1단계, 지역 감시는 2단계).
- §6.1 10단계 → 판정 기록 7 과 `TrackingCoordinator.handle`. §6.2 버퍼·파일 → Task 3. §6.3 하루 문서 → Task 4(구간은 솎기 전 원본으로). §6.4 업로드 → 판정 기록 14·15. §6.5 오프라인 → 새로 안 만든다(`TrailRepository.save` 주석).
- §11.1 쓰기가 전부 허용되는가 → `ChildTrailWriteTests`. **규칙은 한 줄도 안 고친다.**
- §12.1·12.2·12.3 → Task 1~4 의 테스트. §12.4(실기기)는 4단계로 남겼다.
- §15-1·15-3·15-7 → 각각 `CollectionMode` 머리 주석, `stillEscalateMillis` 주석, 판정 기록 12.

**브리프 요구 대응.**
- 골든: 옮긴 로직 다섯 **전부**에 붙였고, 각각 망가뜨려 확인하는 단계가 있다(Task 1 Step 10 의 넷 + Task 2 Step 9 의 다섯 = 아홉 가지).
- 밀도: `CollectionMode.settings` 표가 다섯 모드의 정확도·거리 필터·간격을 이름과 숫자로 적고, `STILL_ESCALATE_MILLIS`(5분)를 포함한다. `CollectionModeTests` 가 전부 고정한다.
- 강제 종료: 판정 기록 17 이 "없는 일로 적지 않는다"를 규칙으로 못박고, Task 5 Step 6 이 **종료(terminate)와 강제 종료를 구분**해 적는다. 3단계가 문구를 맡는다.
- 명령 없음: 공통 절차 B 와 Task 5 Step 1 의 `grep` 이 기계로 막는다.
- 에뮬레이터만: 모든 Firestore 테스트가 `EmulatorHarness`, 시뮬레이터 확인이 `configureForEmulator` + owner 토큰 시드. 실기기 페어링 단계가 없다.
- 업로드 15분/4시간: `uploadMinIntervalMillis`·`uploadIdleIntervalMillis` 와 `TrackingCoordinatorTests` 의 두 테스트.
- 산출물(GPX → `trails` + `status` → 보호자가 그린다): Task 5 Step 6-5 가 그 한 줄이다.
- `xcodebuild` 명령·GPX 파일·시뮬레이터 위치 주입 방법: Global Constraints, Task 5 Step 5·6. `xcrun simctl location`(자동화용)과 Simulator 메뉴(Features → Location) 중 **전자를 쓴다** — 스크립트에 적을 수 있고 재현된다.
- 코틀린 `file:line`: 모든 상수 주석, 모든 포팅 파일 머리 주석, 판정 기록에 붙였다.
- Task 4~6개, 각자 테스트로 끝남, 마지막이 통합 리뷰 + 시뮬레이터 패스: 다섯이고 Task 5 가 그것이다. 스캐폴딩(`project.yml`·i18n·`ChildSimHarness`)을 별도 Task 로 빼지 않고 Task 3·4 에 접어 넣었다.

**자리표시 검사.** "TBD / 적절히 / 나중에"는 없다. `…` 로 본문을 줄인 코드 블록이 넷 있다(`TrailStoreTests` 의 뒤쪽 네 테스트, `TrailBufferTests`·`DeviceStateTests` 의 테스트 이름 목록, `TrackingCoordinator.handle` 의 5·6번, `TrailUploader`·`ChildStatusReporter` 본문). 전부 **정본 코틀린 파일과 줄 번호를 함께 적어** 그대로 옮기면 되는 자리이고, 판단이 필요한 곳은 하나도 줄이지 않았다. 실행해야 알 수 있는 값은 셋이다: 선행 조건의 **M**(지금 테스트 수), Task 5 Step 1 의 **N**, Task 5 Step 4 의 시뮬레이터 UDID·가족 ID·아이 uid.

**타입·이름 일관성(고친 것 포함).**
- 테스트와 구현 대조:
  - `CollectionModeTests` 는 `CollectionMode.moving/.fastProbe/.slowProbe/.knownPlace/.still`, `.settings.desiredAccuracy/.distanceFilterMeters/.intervalMillis`, `CollectionMode.stillEscalateMillis`, `CollectionMode.select(state:insideKnownPlace:slowProbeSince:now:)`, `IntervalGate.accept(at:interval:)` 를 쓴다. 전부 Step 3 구현에 있다.
  - `TrackingCoordinatorTests` 는 `handle(_:eventJustWritten:)`, `uploadNow()`, `lastFix`, `buffer.points` 를 쓴다. `buffer` 를 테스트에서 읽으므로 `private(set)` 이어야 한다 — Step 4 뼈대에 반영했다.
  - `ChildDocumentsTests` 는 `TrailDoc.firestoreData`·`TrailPoint(lat:lng:accuracy:speed:at:)`·`SegmentDoc(type:startAt:endAt:lat:lng:distanceMeters:pointCount:placeName:)`·`ChildStatusWrite(fix:battery:charging:network:)` 를 쓴다. `TrailPoint`·`SegmentDoc` 은 지금 `init?([String:Any])` 뿐이라 **memberwise `init` 을 함께 내야 한다** — Step 3 에 적었다.
- 초안에서 고친 것 넷.
  - `Decision`/`AdaptiveMovementState` 를 `String` rawValue 로 바꿨다. 처음에는 Swift case 이름을 골든에서 기계 변환하려 했는데 6단계가 `Holiday` 에서 같은 방법으로 실패했다(판정 기록 6).
  - `Fix.speedAccuracy` 를 선언부 기본값으로 두려다 `init` 마지막 매개변수로 옮겼다 — `speed` 에서 이미 겪은 memberwise 초기화 사고다.
  - `MovementTrailFilter.isDisplacementEvidence` 초안에 코틀린에 없는 방어 표현이 섞여 있었다. Task 1 Step 5 에 **지우라는 경고 상자**로 남겨 뒀다(초안을 그대로 베끼는 사고를 막는다).
  - 상태 문서 쓰기를 `ChildStatusDoc` 에 `firestoreData` 로 달려다 `ChildStatusWrite` 로 나눴다 — 읽기(`Timestamp`)와 쓰기(`FieldValue.serverTimestamp()`)의 타입이 실제로 다르고, `wifiOn` 은 아이폰이 아예 안 쓴다.
- `Float` 확장값 둘(`0.699999988079071`, `0.3499999940395355`)은 파이썬으로 계산했다: `struct.unpack('f', struct.pack('f', 0.7))[0]`, 같은 식의 0.35. 골든 `constants` 가 이 값을 기계로 다시 확인하므로 손으로 옮기다 틀려도 그 자리에서 잡힌다.
- **실행 전에 확인이 필요한 가정 넷.** 전부 선행 조건 `grep` 이나 테스트가 잡고, 다르면 멈추고 보고하게 적었다.
  - `GoldenFileWriterTest.kt` 에 `offsetLatLng`(과 `triangle`)이 지금 이름·시그니처 그대로 있는가(Task 1 Step 7 의 확인 명령).
  - `RoutePathRefiner.swift` 의 사본 셋이 선행 조건 `grep` 이 찾는 이름 그대로인가.
  - `xcrun simctl location` 이 이 Xcode 에 있는가(Xcode 14+). 없으면 Simulator 메뉴 Features → Location → Custom Location 으로 대체하고, GPX 재생은 Xcode 스킴의 "Allow Location Simulation" 으로 돌린다.
  - `MainActor.assumeIsolated` 가 `CLLocationManagerDelegate` 콜백에서 실제로 참인가(매니저를 메인에서 만들었으므로 참이어야 한다). 거짓이면 그 자리에서 죽는다 — 조용히 틀리는 것보다 낫고, Task 5 Step 6 의 시뮬레이터 재생이 곧 그 확인이다.

---

## Pre-flight conflict table

| 짝 | 함께 만지는 것 | 충돌 여부와 처리 |
|---|---|---|
| **7단계(`4bda965` 이전) ↔ Task 3** | `ios/KidCareTests/ReleaseConfigTests.swift:87-90` 의 "권한 문구 0개·배경 모드 없음" 단언, 7단계 판정 기록 10 | **충돌한다.** 아이 역할이 그 성질을 일부러 깬다(설계서 §15-7). 단언을 지우지 않고 뒤집는다 — 위치 문구 정확히 둘, 배경 모드 정확히 `location` 하나(판정 기록 12). 7단계 판정 기록 10 이 왜 뒤집혔는지 테스트 주석에 적는다 |
| **7단계 ↔ Task 3** | `ios/KidCare/PrivacyInfo.xcprivacy`, `ReleaseConfigTests.이유_필요_API` | **안 고친다.** `NSPrivacyCollectedDataTypePreciseLocation` 이 이미 들어 있다(보호자가 아이 위치를 다루기 때문). 다만 `TrailStore` 에서 파일 시각·부팅 시각 API 를 **쓰지 않는다** — 쓰면 그 테스트가 매니페스트와 소스가 다르다고 빨개진다 |
| **2단계 iOS(`RoutePathRefiner`) ↔ Task 1** | `ios/KidCare/Logic/RoutePathRefiner.swift` 의 `distanceMeters`·`earthRadiusMeters`·`maxSpeedMps` 사본, 그 파일 머리 주석 :6-11 | **사본을 지우고 `LocationFilter` 를 부른다**(판정 기록 4). 머리 주석의 전제("`LocationFilter` 타입 자체는 안 옮긴다")가 이 Task 로 사라진다. 기존 `routePathRefiner.json` 골든(케이스 30여 개, 허용치 1e-9)이 **그대로 초록인 것**이 이 변경의 검사다 |
| **2단계 iOS ↔ Task 1** | `ios/KidCare/Logic/Fix.swift` 의 `init` | 새 매개변수가 **마지막 기본값**이라 기존 호출부가 한 곳도 안 바뀐다(설계서 §3.2). 선행 조건에서 호출부 수를 세어 두고, Task 1 뒤에 그 수가 같은지 본다 |
| **1·3·5단계 iOS ↔ Task 2** | `ios/KidCare/Logic/Segment.swift` 의 memberwise 초기화를 쓰는 곳(`SegmentSummarizer`·`TimelinePanel`·그 테스트들) | 명시적 `init` 에 `nameLat: Double? = nil` 을 두고 `nil` 이면 `lat` 을 쓴다 — 기존 `Segment(...)` 가 한 곳도 안 깨진다(설계서 §3.2 가 이 모양을 지정했다). `SegmentSummarizerTests`·`TimelinePanelTests` 가 초록인 것이 검사다 |
| **2단계 iOS ↔ Task 1·2** | `ios/KidCareTests/GoldenComparisonTests.swift` 의 `골든_리소스가_번들에_있다`(지금 다섯 파일의 하한을 본다), private 헬퍼 `readObject`·`int64`·`double`·`bool`·`string` | 하한 줄을 **더하기만** 한다(기존 다섯 줄은 안 건드린다). 헬퍼는 그대로 쓴다. 새로 필요한 `fix(_:)` 헬퍼를 Task 1 이 추가하고 Task 2 가 재사용한다 — 이름이 둘로 갈리지 않게 Task 1 이 먼저다 |
| **2단계 안드로이드 ↔ Task 1·2** | `app/src/test/java/com/kidcare/family/logic/GoldenFileWriterTest.kt` | `app/` 에서 **유일하게** 바뀌는 파일이다(설계서 §12.2·§17 열린 질문 1, 브리프 승인). 기존 `@Test` 다섯을 건드리지 않고 아래에 다섯을 더한다. `repoRoot()`·`writeIfChanged`·`writeGoldenIfPresent`·`toJson` 을 그대로 쓴다. 매 커밋 전 `git diff --stat 4bda965..HEAD -- app` 이 이 한 파일만 보여야 한다 |
| **6단계 ↔ Task 3** | `tools/ios-strings.py:28` 의 `INFOPLIST_KEYS`(지금 `CFBundleDisplayName` 하나), `tools/i18n-untranslated.json`, `LocalizableCatalogTests`·`I18nKeyParityTests` | 매핑 둘을 더하고 `--write-gaps` 로 기록을 다시 쓴다(공통 절차 A). 빈 칸이 12개 언어 × 2키 늘어야 한다 — 그 diff 를 눈으로 본다. `ReleaseConfigTests.앱_이름` 은 `CFBundleDisplayName` 만 보므로 영향이 없다 |
| **7단계 ↔ Task 3** | `ios/project.yml` 의 `targets.KidCare.info.properties` | 키 셋을 **더하기만** 한다. `CFBundleLocalizations`·`ITSAppUsesNonExemptEncryption`·`KidCarePrivacyPolicyURL` 을 건드리지 않는다 |
| **6·7단계 ↔ Task 4** | `ios/KidCare/RouterView.swift` 의 `isRunningTests` 갈래와 `GuardianHomeView(familyId:onLeft:)` 호출 | DEBUG 분기를 **`isRunningTests` 위**에 둔다(판정 기록 20). 기존 갈래의 동작과 그 긴 주석을 바꾸지 않는다. `#if` 로 `if/else if` 사슬을 쪼개는 모양이 컴파일에 걸리면 `body` 맨 위에서 한 번만 갈라라(Task 4 Step 5 의 대안) |
| **1~7단계 ↔ Task 4** | `ios/KidCare/Core/TrailRepository.swift` 머리 주석의 "**쓰기는 없다** — 보호자 앱은 이 문서들을 읽기만 한다" | 그 문장이 **거짓이 된다.** 주석을 고치고, `save` 가 아이 세션 전용임을 규칙 줄 번호와 함께 적는다. `MapViewModel` 의 `fetch` 호출은 안 바뀐다 |
| **1~7단계 ↔ Task 4** | `ios/KidCare/Core/Documents.swift` 의 `TrailPoint`·`SegmentDoc`(지금 `init?([String:Any])` 뿐), `ChildStatusDoc` | memberwise `init` 과 `firestoreData` 를 **더한다**(기존 `init?` 유지). `ChildStatusDoc` 에 `platform` 이 늘면 그 `init?` 을 쓰는 곳(`FamilyRepository.fetchChildStatus`·`observeChildStatus`, `StatusCardTests`)이 전부 기본값 `""` 를 받는다 — 깨지지 않는다 |
| **4단계(보호자 잠금) ↔ Task 4** | `children/{childUid}` 의 `platform` 필드 | 1단계는 **심기만** 하고 읽지 않는다. `Guardian/ChildPlatform` 과 세 화면 잠금은 4단계다(설계서 §10.2). 필드 이름과 값(`"ios"`)을 여기서 확정하므로 4단계는 읽기만 하면 된다 |
| **2단계(장소) ↔ Task 4** | `TrackingCoordinator` 의 훅 셋(`onCondition`·`updateKnownPlace`·`onPlaceFix`), `shouldUpload(…eventJustWritten:)`, `TrailUploader.buildSegments` 의 `placeName` | 순서 의존이 아니라 **자리 예약**이다(판정 기록 7·14). 2단계는 훅을 잇고 `placeName` 을 채우기만 한다 — `handle()` 의 순서와 업로드 판정 함수의 모양을 다시 안 바꾼다 |
| **3단계(아이 화면) ↔ Task 4** | `Child/ChildSimHarness.swift`·`ChildSimView.swift`, `RouterView` 의 DEBUG 분기 | **3단계가 지운다.** 두 파일 머리 주석과 `RouterView` 의 분기 주석에 그렇게 적는다(판정 기록 9). 3단계 계획서가 이 문장을 받아 `ChildRootView` 로 대체한다 |
| **3단계(`ConditionWatcher`) ↔ Task 3** | `Child/DeviceState.swift` | 설계서 §3.4 는 `DeviceState` 를 3단계에 적었는데 1단계로 당겼다(판정 기록 8). 3단계는 **이 파일을 다시 만들지 않고** `ConditionWatcher` 에서 읽어 쓴다. `CONDITION_CHECK_INTERVAL_MILLIS`(60초, `TrackingService.kt:913`)와 배터리 이벤트는 3단계 몫이다 |
| **Task 1 ↔ Task 2** | `LocationFilter.distanceMeters`·`maxSpeedMps`·`fallbackMaxAccuracyMeters`, `GoldenComparisonTests.fix(_:)` 헬퍼 | 순서 의존. Task 2 는 Task 1 이 커밋된 뒤에 컴파일된다 |
| **Task 3 ↔ Task 4** | `LocationSource` 프로토콜, `CollectionMode.select`, `TrailBuffer`·`TrailStore`, `IntervalGate` | 순서 의존. Task 4 의 `TrackingCoordinator` 가 넷을 다 쓴다 |
| **Task 4 ↔ Task 5** | `KidCareApp.swift`(에뮬레이터 임시 전환) | Task 5 가 잠시 바꿨다가 **반드시 되돌린다**. 공통 절차 B 의 `git diff ios/KidCare/KidCareApp.swift` 가 매 커밋에서 빈 것을 본다 |
| 에뮬레이터 상태 ↔ Task 4·5 | 이미 떠 있는 `kidcare-emulator` 의 기존 데이터(6단계가 만든 `sim-child` 등) | **지우지 않는다.** 새 가족을 하나 더 만들어 쓴다. `FAMILY` 를 "마지막 가족"으로 집는 명령은 6단계가 쓰던 것 그대로이므로, 가족을 만든 **직후에** 집는다 |
| 시뮬레이터 상태 ↔ Task 5 | 부팅된 시뮬레이터 둘, 이미 설치된 앱 | **끄지도 지우지도 않는다**(브리프). 덮어 설치한다. 남은 `RoleStore` 값 때문에 보호자 시뮬레이터가 곧장 본 화면으로 갈 수 있다 — 그건 정상이고, 아이 시뮬레이터는 `-childSim` 이 그 갈래보다 먼저 이긴다(판정 기록 20) |
