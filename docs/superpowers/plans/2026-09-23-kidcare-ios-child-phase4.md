# iOS 아이 역할 4단계 구현 계획 — 보호자 차단, 전수 검토, 실기기 확인

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 아이가 아이폰이면 **보호자 앱이 못 하는 것을 못 한다고 말한다.** 지금 보호자 화면은 아이폰 아이에게도 소리 모드 버튼·핸드폰 찾기·메시지·알람·'지금 위치 확인'·'실시간 보기'를 그대로 내밀고, 누르면 `commands/` 문서가 하나 만들어져 **아무도 구독하지 않는 자리에서 영원히 "전달 중"에 머문다**(아이폰 아이는 명령을 안 듣는다, 설계서 §1). 이 단계가 그 거짓말을 끝낸다. 그리고 1~3단계가 열어 둔 이월을 하나씩 닫거나 **왜 안 닫는지를 적어** 닫고, 세 단계 전체를 상수·골든·리스너·비용·정직함 다섯 축으로 훑고, 개발일지를 쓰고, **실기기에서만 풀리는 항목의 점검표를 적어 둔 채 주인의 허락을 기다린다.**

**Architecture:** 판단은 한 곳이다. `Guardian/ChildPlatform.swift` 가 `ChildStatusDoc.platform`(1단계가 이미 심었다, `Documents.swift:186·202·252`) 하나를 읽어 `.android` / `.iOS` / `.unknown` 셋 중 하나를 돌려주고, **화면은 `platform == "ios"` 를 직접 비교하지 않는다**(설계서 §10.2 — 비교가 흩어지면 한 군데를 빠뜨린다). 그 값을 다섯 탭이 같이 보게 하는 것이 `Guardian/ChildPlatformStore.swift` 다 — `RuleSyncStore`·`AlarmMemoStore` 와 같은 `UserDefaults` 저장소이고, **아이 상태 문서를 이미 읽고 있는 셋**(`MapViewModel`·`ControlViewModel`·`PlaceViewModel`)이 읽을 때마다 기억시킨다. **Firestore 읽기가 한 번도 안 는다** — 예약 탭은 상태 문서를 안 읽는 유일한 탭인데, 그 탭을 위해 읽기를 하나 더 사는 대신 기억해 둔 값을 본다(판정 기록 3). 잠금은 **두 겹**이다: 화면이 버튼을 끄거나 숨기고(1겹), 명령을 실제로 보내는 세 함수(`ControlViewModel.send` `:410-418`, `MapViewModel` 의 세 보내기, `ScheduleViewModel.아이에게_알린다` `:512-523`)가 그 앞에서 되돌아간다(2겹). **계약은 "버튼이 흐리다"가 아니라 "`commands/` 문서가 하나도 안 생긴다"이고, 테스트가 그것을 본다.**

**Tech Stack:** Swift 6 strict concurrency / iOS 17 / SwiftUI / Firebase Firestore / Swift Testing / XcodeGen. 새 의존성 없음. 새 Firestore 리스너 없음. 새 화면 없음. **`app/` 을 한 줄도 안 만진다** — 이 단계는 골든 파일을 더하지 않으므로 `GoldenFileWriterTest.kt` 예외조차 쓰지 않는다(판정 기록 12 가 그래도 되는 이유를 적었다).

**Spec:** `docs/superpowers/specs/2026-09-22-kidcare-ios-child-design.md`. 이 단계가 기대는 곳:
- §14 4단계 — 범위 그대로("`platform` 쓰기와 읽기, `Guardian/ChildPlatform` + 세 화면 잠금(§10.2) / 전수 검토: 상수 대조표(§4)를 코드와 한 줄씩 대조, 골든 대조가 정말로 무는지 일부러 값을 망가뜨려 확인 / **주인의 허락을 받은 뒤** 실기기 검증 열 항목(§12.4)")
- §10 전부 — 10.1 아이폰인 것을 아는 법과 **값이 없으면 안드로이드로 본다**, 10.2 무엇을 잠그나와 문구 둘
- §11.2 하루 쓰기 수 — 만든 코드로 다시 세어 안드로이드 대비 배수가 안 나빠졌는지 본다
- §12.4 실기기에서만 확인되는 것 열 항목, §13 실기기 안전(**주인의 명시적 허락 없이는 실기기를 아이로 페어링하지 않는다**)
- §15 아이폰이라서 똑같이 못 하는 것 여덟 — 개발일지의 뼈대다
- §17 열린 질문 3(강제 종료)·4(백그라운드 새로고침)·8(안드로이드 보호자는 후속)·10(문구는 주인이 고칠 수 있다)
- §16 제약 → Global Constraints

**이월 받는 것(전부 결론을 낸다 — 닫거나, 왜 안 닫는지를 적는다):**
- 2단계 **I2** — 도착 5분 안의 이탈이 조용히 사라진다(`Logic/GeofenceEvaluator.swift:106`). → **안 고친다**(판정 기록 8). 개발일지에 적는다.
- 2단계 **M1** — 이름 예산이 최대 두 배까지 늘 수 있다(`Child/PlaceNamer.swift:130` + `Child/TrailUploader.swift:132`). → **안 고친다**(판정 기록 9). `docs/known-issues.md` 에 적는다.
- 2단계 **M2** — `PlaceNameCache.decode` 의 숫자 해석이 정본과 다르다(`Logic/PlaceNameCache.swift:108` vs `logic/PlaceNameCache.kt:84-85`). → **고친다**(판정 기록 10). Task 4.
- 2단계 **M4** — `SKIP_TOO_CLOSE` 에서 난 사건의 강제 업로드가 한 점 뒤처진 좌표를 싣는다(`Child/TrackingCoordinator.swift:215·217·221·297`). → **고친다**(판정 기록 11). Task 4.
- 2단계 **M5** — 규칙이 보호자가 자기 uid 로 사건을 지어내는 것을 안 막는다(`firestore.rules:306-310`). → **안 고친다. 규칙은 절대 안 고친다**(주인 판정). 개발일지 + `docs/known-issues.md`.
- 1단계 **M5** — `LeaveFamilyModelTests` 의 실제 `Task.sleep` 의존 셋(`ios/KidCareTests/LeaveFamilyModelTests.swift:149·268·277`). → **고친다**(판정 기록 13). Task 4.
- 3단계 **M4** — `ios_child_perm_refresh_reason` 이 확인 안 된 것을 말한다(§17 열린 질문 4). → **실기기 점검표 1번.** 문구는 이미 유보를 담게 고쳐져 있다. 실기기에서 안 멎으면 **항목과 문구를 지운다.**
- 3단계 이월 7번 — 코틀린 주석의 `at` 창이 24시간, 규칙은 7일(`ConditionWatcher.kt:145-147`, `EventRepository.kt:25`, `PlaceWatcher.kt:131`). → **`app/` 금지라 못 고친다.** 개발일지의 "안드로이드에서 고칠 것"에 적는다.
- 1단계 **M3** 잔여, 3단계 **I3**·**M1** 잔여, 그리고 세 단계의 실기기 항목 전부. → **실기기 점검표**(Task 4). 주인이 허락할 때까지 **안 돈다.**

---

## 선행 조건

3단계(`docs/superpowers/plans/2026-09-23-kidcare-ios-child-phase3.md`)가 **수정 파동까지 전부 커밋된 뒤** 시작한다. 기준 커밋은 `0b141d6`(3단계 고침 3) 이상이다.

```bash
cd /Users/com/work/KidCare
git status --short                                                        # 비어 있어야 한다
git log --oneline -1                                                      # 0b141d6 이거나 그 뒤
git branch --show-current                                                 # ios-guardian-app

# 1단계가 심은 재료 — 이게 없으면 이 단계 전체가 성립하지 않는다
grep -n "var platform: String" ios/KidCare/Core/Documents.swift            # :186
grep -n 'platform = data\["platform"\]' ios/KidCare/Core/Documents.swift   # :202  ?? "" 여야 한다
grep -n '"platform": "ios"' ios/KidCare/Core/Documents.swift               # :252
grep -n 'platform' ios/KidCareTests/ChildDocumentsTests.swift              # :95-101 없으면 계약이 안 묶여 있다

# 이 단계가 만지는 자리의 지금 모양 — 하나라도 다르면 Pre-flight conflict table 의 해당 행을 먼저 처리한다
grep -n "var 버튼_활성화\|var 새로_확인_활성화" ios/KidCare/Guardian/ControlViewModel.swift      # :193 :196
grep -n "private func send(" ios/KidCare/Guardian/ControlViewModel.swift                       # :410
grep -n "var 위치확인_버튼_활성화" ios/KidCare/Guardian/MapViewModel.swift                      # :585
grep -n "CommandType.startLiveTracking\|CommandType.stopLiveTracking\|CommandType.locateNow" ios/KidCare/Guardian/MapViewModel.swift  # 세 줄
grep -n "disabled(viewModel.childUid == nil)" ios/KidCare/Guardian/ChildMapView.swift          # :180 (실시간 버튼)
grep -n "private func 아이에게_알린다" ios/KidCare/Guardian/ScheduleViewModel.swift             # :512
grep -n "SyncPendingBar" ios/KidCare/Guardian/ScheduleView.swift ios/KidCare/Guardian/RuleListParts.swift  # :63 / :23
grep -n "statusFetch" ios/KidCare/Guardian/ControlViewModel.swift ios/KidCare/Guardian/PlaceViewModel.swift  # :108·:160 / :101·:116
grep -n "기본_하루_읽기\|상태 = 읽은_것.status\|상태 = status" ios/KidCare/Guardian/MapViewModel.swift  # :362 :460 :1174
sed -n '38,56p' ios/KidCare/Guardian/GuardianRootView.swift                # 다섯 뷰모델을 만드는 자리
grep -n "struct RuleSyncStore" ios/KidCare/Guardian/RuleSyncStore.swift    # :12 — 새 저장소가 베끼는 모양

# 이 단계가 고치는 이월의 지금 모양
grep -n "let coordinates = line" ios/KidCare/Logic/PlaceNameCache.swift    # :107-108 (2단계 M2)
grep -n "onPlaceFix?(fix)\|func eventWritten" ios/KidCare/Child/TrackingCoordinator.swift  # :215 :297 (2단계 M4)
grep -n "Task.sleep" ios/KidCareTests/LeaveFamilyModelTests.swift          # :149 :268 :277 (1단계 M5)

# 안드로이드 정본 — 이 단계가 인용하는 줄이 실제로 그 줄인지 확인한다
sed -n '84,85p' app/src/main/java/com/kidcare/family/logic/PlaceNameCache.kt   # toDoubleOrNull 두 줄
sed -n '145,147p' app/src/main/java/com/kidcare/family/child/ConditionWatcher.kt  # at 창을 24시간이라 적은 주석
ls app/src/main/java/com/kidcare/family/guardian/ControlFragment.kt \
   app/src/main/java/com/kidcare/family/guardian/MapTimelineFragment.kt \
   app/src/main/java/com/kidcare/family/guardian/ScheduleFragment.kt        # 후속 과제가 고칠 셋(§17-8)

# 기준 테스트 개수 M — 3단계 마무리 기준 746 이다. 실제로 돌려 확인하고 적어 둔다
cd ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5
```

## Global Constraints

설계서 §16 과 1~3단계 계획서의 목록을 이 단계의 말로 옮긴 것이다.

- **Swift 6 strict concurrency, iOS 17.0, SwiftUI, XcodeGen**(`ios/project.yml`; xcodeproj 를 손으로 고치지 않는다), **Swift Testing**.
- `ios/KidCare/Logic/` 은 **Foundation 만** import 한다. CoreLocation 도 Firebase 도 UIKit 도 안 된다. 이 단계가 `Logic/` 에서 만지는 것은 `PlaceNameCache.decode` 한 함수뿐이고 새 import 가 없다.
- 앱 코드에 **`@unchecked Sendable` 과 `nonisolated(unsafe)` 를 쓰지 않는다.**
- **푸시 알림과 FCM 을 쓰지 않는다**(Spark 무료 요금제). **이 단계는 새 Firestore 리스너를 하나도 만들지 않고, 새 Firestore 읽기도 하나도 더하지 않는다**(판정 기록 3).
- `app/src/main`, `firestore.rules`, `gradlew` 를 **한 줄도** 고치지 않는다. **이 단계는 `app/` 전체를 안 만진다** — 골든 파일을 더하지 않으므로 `GoldenFileWriterTest.kt` 예외도 안 쓴다. **`firestore.rules` 는 주인의 못박은 판정으로 영원히 안 고친다**(2단계 M5 가 그래서 안 닫힌다).
- **정본은 안드로이드다.** 이 계획서가 코틀린과 다르면 코틀린이 맞다. 상수는 인용한 `파일:줄` 에서 그대로 옮긴다.
- **보호자 앱은 안드로이드 아이에게 지금과 한 글자도 다르게 굴면 안 된다**(주인 판정). 모든 잠금은 `.iOS` 에서만 걸리고, `.android` 와 `.unknown` 에서는 코드 경로가 지금과 같다. Task 2·3 의 테스트가 **안드로이드 갈래를 먼저** 본다.
- 새 문구는 `i18n/ko.json`·`i18n/en.json` **둘에만** 넣고 `python3 tools/ios-strings.py` 로 생성한다. **번역을 지어내지 않는다** — 나머지 12개 언어는 영어로 채워지고 `tools/i18n-untranslated.json` 에 남는다. 이 단계가 더하는 키는 **둘뿐**이다(판정 기록 6).
- 테스트는 **운영 Firestore 에 절대 쓰지 않는다.** 에뮬레이터 테스트는 `configureForEmulator(projectId: "kidcare-emulator")`(Auth 127.0.0.1:9099, Firestore 8080)를 쓰고, **커밋 시점의 `KidCareApp.init()` 은 반드시 `configureForApp()` 을 부른다.** 에뮬레이터는 **이미 떠 있는 것을 그대로 쓰고 그 데이터도 지우지 않는다**(3단계가 남긴 가족 `MZO1poA0yAyAmgOEx56X` 포함).
- **실기기를 아이로 페어링하지 않는다.** 설계서 §13 이 그 이유를 적었다 — 진짜 가족 문서에 쓰고 **진짜 아이의 위치를 모으기 시작한다.** 이 단계가 하는 일은 점검표를 **적어 두는 것**까지이고, 실행은 **주인이 하라고 말한 뒤**다(Task 4 Step 8).
- **시뮬레이터를 끄거나 지우지 않는다.** 테스트 전에 앱을 **지우지 않는다**(위에 덮어 설치한다).
- 커밋은 한국어, 작성자 `Yongminlee2 <dydals5678@gmail.com>`. **AI 흔적을 남기지 않는다**(Co-Authored-By 금지).
- 테스트 명령: `cd ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'`.
- 주석은 한국어로 **"왜"** 를 적는다. 실행 전 PATH 는 `export PATH="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:$PATH"` 다. 파일을 새로 만들거나 지웠으면 테스트 전에 `cd ios && xcodegen generate` 를 돌린다.
- Swift 의 `CancellationError` 를 일반 `catch` 로 삼키지 않는다(설계서 §16 마지막 줄).

## 공통 절차 A — 문구 키를 카탈로그에 넣는 법

3단계 공통 절차 A 그대로다. 카탈로그(`ios/KidCare/Localizable.xcstrings`)를 **손으로 고치지 않는다.**

1. `i18n/ko.json` 과 `i18n/en.json` **둘 다**에 키를 넣는다(코드 포인트 순 정렬, 파일 끝 줄바꿈 하나). 나머지 12개 언어 파일에는 넣지 않는다.
2. 키를 더했으므로 `python3 tools/ios-strings.py --write-gaps` 로 빈 칸 기록(`tools/i18n-untranslated.json`)까지 새로 쓴다. diff 의 빈 칸 변화가 **정확히 둘 × 12개 언어**인지 눈으로 본다.
3. 검사: `python3 tools/ios-strings.py --check`(종료 코드 0), `I18nKeyParityTests`·`LocalizableCatalogTests`·`LocalizationBundleTests`.

**이 단계는 Task 1 에서 한 번만 쓴다** — 새 키 둘을 더하고 그 뒤로는 안 건드린다. `INFOPLIST_KEYS` 는 안 바뀐다(새 Info.plist 문구가 없다).

## 공통 절차 B — 커밋

```bash
cd /Users/com/work/KidCare
git diff --stat 0b141d6..HEAD -- app firestore.rules gradlew            # 비어 있어야 한다
git diff ios/KidCare/KidCareApp.swift | grep -n "configureForEmulator"   # 비어 있어야 한다
grep -rn "@unchecked Sendable\|nonisolated(unsafe)" ios/KidCare          # 주석 말고는 비어 있어야 한다
grep -rn "import CoreLocation\|import Firebase\|import UIKit" ios/KidCare/Logic   # 비어 있어야 한다
python3 tools/ios-strings.py --check                                     # 종료 코드 0
git add <이 Task 의 파일들>
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "<한국어 메시지>"
```

## 이 단계에서 다루지 않는 것

- **안드로이드 보호자 화면의 같은 잠금**(설계서 §17 열린 질문 8, 주인 판정 ⑧). `app/` 을 안 고치므로 남는다. 부모가 **안드로이드 폰으로** 아이폰 아이에게 명령을 보내면 영영 "전달 중"에 머문다. 고치는 자리 셋(`guardian/ControlFragment.kt`, `guardian/MapTimelineFragment.kt`, `guardian/ScheduleFragment.kt`)과 재료(`platform` 필드는 1단계가 이미 심었다)를 **개발일지에 적어** 다음 사람에게 넘긴다.
- **`firestore.rules` 수정**(2단계 M5). 주인이 못박았다.
- **`CLMonitor` 로 옮기기**(§17 열린 질문 2). 실기기에서 "죽은 앱을 되살린다"를 확인한 **뒤에** 여는 문이다. 이 단계는 점검표에만 적는다.
- **CoreMotion / 활동 인식**(§17 열린 질문 5), **`startMonitoringVisits`**(§17 열린 질문 11). v1 에서 안 쓴다.
- **업로드 주기 15분/4시간 조정**(§17 열린 질문 6). 실기기 하루 측정 **뒤에** 여는 문이다. Task 4 Step 5 가 숫자로 근거를 만들어 두기만 한다.
- **`TrailUploader(namer:)` 기본값 함정**(2단계 task-3 보고서 걱정 1). 새 호출부가 안 생기므로 이 단계에서는 위험이 없다. 개발일지에 한 줄 남긴다.
- **장소 탭 잠금.** 설계서 §10.2 가 "안 잠근다"라고 적었다 — 장소 저장은 Firestore 쓰기이고 아이폰 아이가 상시 구독으로 받는다(§7.3). 잠그면 **실제로 되는 것을 막는** 거짓말이 된다.
- **알림 탭 잠금.** 같은 이유다. `place_enter`/`place_exit`/`low_battery`/`permission_off` 는 아이폰 아이가 **실제로 쓴다**(2·3단계).

---

## 판정 기록 — 이 계획서가 내린 결정

1. **판단은 `ChildPlatform` 하나가 하고, 화면은 `"ios"` 라는 글자를 모른다.**
   설계서 §10.2 가 그렇게 적었다 — "화면마다 `platform == "ios"` 를 직접 비교하지 않는다. 비교가 흩어지면 한 군데를 빠뜨린다." 이 저장소에는 그 사고의 전례가 있다(`RingerMode.isKnown` 을 안 거치고 `ringerMode` 를 직접 본 자리들). 그래서 `"ios"` 문자열은 **`Documents.swift:252`(아이가 쓰는 곳)와 `ChildPlatform.swift`(보호자가 읽는 곳) 딱 두 군데**에만 있고, Task 4 Step 6 이 `grep` 으로 그 둘뿐인 것을 확인한다.

2. **세 갈래이고, 모르는 것은 안드로이드처럼 대한다.**

   | 재료 | `ChildPlatform` | `명령을_받을_수_있나` | 화면 |
   |---|---|---|---|
   | 상태 문서의 `platform == "ios"` | `.iOS` | **false** | 잠근다 + 문구 |
   | 상태 문서의 `platform` 이 빈 값이거나 다른 값 | `.android` | true | 지금과 똑같다 |
   | 상태 문서를 **아직 못 읽었거나 아예 없다** | `.unknown` | true | 지금과 똑같다. **문구도 안 띄운다** |

   `ChildStatusDoc.platform` 은 필드가 없으면 `""` 로 디코드된다(`Documents.swift:202`, `ChildDocumentsTests.swift:95-101` 이 그 계약을 묶고 있다). 그래서 **`.unknown` 은 "필드가 없다"가 아니라 "문서 자체가 없다"**다.
   방향을 이렇게 잡는 이유는 설계서 §10.1 이 적은 그대로다: 지금 서버에 있는 **모든** 아이 문서에 이 필드가 없고, **모르는 아이의 기능을 조용히 없애면 안 된다.** 틀리는 두 방향의 대가가 같지 않다 — 안드로이드 아이를 아이폰으로 잘못 보면 **멀쩡히 되는 기능이 사라지고 부모는 이유를 모른다.** 반대로 아이폰 아이를 아직 모를 때 버튼이 켜져 있으면, 눌렀을 때 기존의 60초 무응답 문구(`control_command_timeout`)가 뜬다 — 상태 문서를 한 번도 안 쓴 폰에 대해서는 **그 문구가 참말이다.**
   그 창(窓)은 1단계가 이미 닫아 뒀다: 아이폰 아이는 **페어링 뒤 첫 좌표를 받자마자 업로드를 한 번 강제**하고(설계서 §10.1), 그 뒤로는 **업로드마다** `platform: "ios"` 를 덮어쓴다. 창의 길이는 "페어링 후 첫 좌표까지"이고, 그 동안은 위치도 안 오므로 부모 화면의 모든 줄이 이미 "아직 아무 신호 없음"이다.
   **`.unknown` 에서 문구를 띄우지 않는 것이 이 판정의 절반이다.** "이 아이는 아이폰이에요"를 안드로이드 아이에게 말하는 것은 버튼을 끄는 것보다 더 나쁜 거짓말이다.

3. **읽기를 하나도 더 사지 않는다 — `ChildPlatformStore`(UserDefaults)가 다섯 탭을 잇는다.**
   아이 상태 문서를 이미 읽는 탭이 셋이다: 지도(`MapViewModel.swift:362-363` 의 하루 읽기, `:460` 대입 / 실시간 구독 `:1174`), 관리(`ControlViewModel.swift:160`·`:628-630`), 장소(`PlaceViewModel.swift:116`). **예약 탭만 안 읽는다**(`ScheduleViewModel` 의 의존 목록 `:87-98` 에 상태가 없다).
   예약 탭을 위해 `statusFetch` 를 하나 더 다는 길이 있는데 **안 간다.** 가족당 하루 읽기 예산이 50 이고(`known-issues.md` 12번), 이 단계의 목적은 비용을 **안 나쁘게** 하는 것이다(설계서 §11.2). 대신 `RuleSyncStore`(`:12-33`)와 똑같은 모양의 `UserDefaults` 저장소를 아이 uid 로 두고, **상태 문서를 읽는 셋이 읽을 때마다 기억시킨다.** 예약 탭은 기억을 본다.
   **못 맞히는 경우의 대가가 0이라서 되는 설계다.** 기억이 없으면 `.unknown` 이고, `.unknown` 은 아무것도 안 잠근다 — **지금 동작 그대로**다. 기억이 낡아서 `.android` 라고 답하는 최악의 경우도 지금 동작 그대로다. 반대로 낡아서 `.iOS` 라고 답하려면 그 아이가 아이폰에서 안드로이드 폰으로 갈아타야 하는데, 그때는 관리 탭·지도 탭이 열리는 순간 자기 읽기로 기억을 덮고, **예약 탭의 잠금은 애초에 규칙 저장을 막지 않는다**(판정 기록 5). 즉 낡은 기억이 부모가 할 수 있는 일을 하나도 못 막는다.
   저장소이지 뷰모델이 아닌 이유도 `RuleSyncStore.swift:9-10` 과 같다 — 앱이 꺼져도 남아야 두 번째 실행부터는 예약 탭이 처음부터 옳다.

4. **잠금은 두 겹이고, 계약은 아래쪽 겹이다.**
   화면의 `.disabled` 는 사람이 잘못 누르는 것을 막을 뿐이다. 진짜 계약은 **`commands/` 문서가 하나도 안 생긴다**이고, 그것을 지키는 자리는 명령을 실제로 보내는 세 함수다.

   | 보내는 자리 | 줄 | 막는 방법 |
   |---|---|---|
   | `ControlViewModel.send(_:payload:onSent:)` | `:410-418` | 맨 앞에 `guard 플랫폼.명령을_받을_수_있나`. 이미 있는 `guard let childUid`(`:415-418`)와 **같은 모양**으로 붙인다 |
   | `MapViewModel.지금_위치를_확인한다()` | `:626`, 보내기 `:653-655` | 입구 guard |
   | `MapViewModel.실시간_추적을_시작한다()` | `:1048`, 보내기 `:1074-1079` | 입구 guard. 끄기(`:1256-1258`)는 **안 막는다** — 켜진 적이 없으면 불릴 일이 없고, 혹시 켜져 있었다면 끄는 것은 반드시 되어야 한다 |
   | `ScheduleViewModel.아이에게_알린다(_:)` | `:512-523` | 입구 guard + 깃발 처리(판정 기록 5) |

   테스트가 보는 것도 아래쪽 겹이다: **가짜 `commandSend` 가 한 번도 안 불린다.** "버튼이 흐리다"는 눈으로도 보이지만, 흐린 버튼을 우회하는 길(스크린 리더, 키보드, 다음 사람이 뷰를 고치는 것)은 눈에 안 보인다.

5. **예약 탭이 가장 어렵다 — 규칙은 그대로 저장되고, '아이 폰에 알리기'는 아예 사라지고, 왜인지는 탭 맨 위에 늘 적혀 있다.**
   규칙 저장·수정·삭제·기본 모드·공휴일 스위치를 **하나도 안 막는다.** 설계서 §10.2 가 이유를 적었다 — "나중에 그 아이가 안드로이드 폰으로 바뀌면 그대로 동작해야 하기 때문이다." 규칙은 `schedules/` 에 남아 있고, 그 아이가 안드로이드 폰으로 합류하는 날 그 폰이 읽어 간다.
   막는 것은 **`sync_rules` 명령 하나**다(`:523`). 그 명령은 아이폰 아이에게 **영원히 배달되지 않는 채로** `commands/` 에 남는다 — 쓰기 하나를 태우고, `pendingSync` 깃발이 영영 안 내려가고, `SyncPendingBar` 가 "아직 못 알렸어요 / 다시 알리기"를 계속 띄운다. 그게 정확히 이 작업 지시가 금지한 **"끝나지 않는 명령"**이다.
   그래서 `.iOS` 에서는: **① `아이에게_알린다` 가 입구에서 되돌아간다. ② 깃발을 애초에 안 올린다**(다섯 쓰기 갈래가 쓰기 **전에** 올리는 자리 `:334·370·403·432·468`). **③ `SyncPendingBar` 를 숨긴다**(`ScheduleView.swift:63-68`).
   **바는 끄는 게 아니라 숨긴다 — 이 단계의 유일한 '숨기기' 둘 중 하나다.** 흐려진 채로 "아직 못 알렸어요"가 남아 있으면 부모는 그것을 **일시적인 실패**로 읽고 계속 다시 누르려 한다. 알릴 것이 없다는 사실은 버튼이 아니라 **문장**이 말해야 한다.
   **부모가 실제로 보는 것(그대로 적는다):** 탭 맨 위에 늘 있는 한 줄 — "규칙은 저장되지만 아이폰에서는 소리가 바뀌지 않아요."(`ios_child_schedule_not_applied`) 그 아래로 규칙 목록·추가 버튼·기본 모드 넷·공휴일 스위치가 **전부 평소처럼 눌리고 평소처럼 저장된다.** '아이 폰에 알리기' 바는 **한 번도 안 뜬다.**

6. **문구는 둘뿐이고, 설계서의 초안을 그대로 쓴다. 주인이 고칠 수 있다(§17 열린 질문 10).**

   | 키 | ko | en |
   |---|---|---|
   | `ios_child_no_remote_control` | 아이 폰이 아이폰이라 이 기능은 쓸 수 없어요. 위치와 장소 알림은 그대로 와요. | Your child's phone is an iPhone, so this cannot be done. Location and place alerts still arrive. |
   | `ios_child_schedule_not_applied` | 규칙은 저장되지만 아이폰에서는 소리가 바뀌지 않아요. | Rules are saved, but the sound will not change on an iPhone. |

   ko 두 줄은 **설계서 §10.2 의 글자 그대로**다. en 은 이 계획서가 쓴다(ko·en 둘만 채우고 나머지 12개는 영어로 흘러간다 — 번역을 지어내지 않는다).
   **키를 더 안 만드는 것이 판정이다.** 잠긴 컨트롤마다 다른 문장을 주면 같은 사실을 여덟 번 다르게 말하게 되고, 그중 하나만 고치는 사고가 생긴다. 설계서도 "문구는 키 하나로 통일한다"라고 적었다. 문장 하나를 **버튼들이 있는 그 자리**에 두는 것으로 "각 컨트롤이 왜 안 되는지"를 채운다(판정 기록 7 의 배치).

7. **컨트롤마다 끄느냐 숨기느냐 — 기준은 "그 자리에 값이 있는가"다.**
   기본은 **끈다**(`.disabled(true)` + `.opacity(0.38)`). 설계서 §10.2 가 그렇게 정했고, 근거는 역할 선택 화면이 아이 버튼을 지우지도 흐리게만 두지도 않고 **이유를 말하는** 것과 같은 판단이다(`RoleSelectView.swift:4-6`). 흐린 버튼은 "이 앱에 이 기능이 있고, 이 아이에게만 안 된다"를 말한다. 지워 버리면 부모는 **자기 앱이 고장 났거나 업데이트로 기능이 사라졌다**고 읽는다. 그리고 그 아이가 안드로이드 폰으로 바뀌면 **자리가 그대로** 돌아온다.
   **숨기는 것은 둘뿐이고, 둘 다 "그 자리에 표시할 값이 영영 없다"가 이유다.**

   | 자리 | 정본 | 결정 | 왜 |
   |---|---|---|---|
   | 소리 상태 카드 + '새로 확인' | `ControlView.swift:173-198` | **숨긴다** | 이 카드가 하는 일은 `ringerMode` 를 보여주는 것 하나인데, 아이폰 아이는 그 칸을 **일부러 빈 값으로** 쓴다(`Documents.swift:239` — 빼면 기본값 "normal" 이 살아나 부모 화면이 "벨소리"라고 거짓말한다). 그래서 이 카드는 영원히 `control_ringer_status_unknown`("확인되지 않음")이고, 그 옆의 '새로 확인'은 **눌러도 영원히 안 바뀌는 버튼**이다. 값이 없는 칸과 답이 없는 질문을 흐리게 남겨 두느니 지운다 |
   | '아이 폰에 알리기' 바(`SyncPendingBar`) | `ScheduleView.swift:63-68` | **숨긴다** | 판정 기록 5 |
   | 소리 모드 버튼 셋 | `:200-226` | 끈다 | 기능이 있다는 사실은 남긴다 |
   | 잠금 스위치 | `:46-59` | 끈다 | 소리 구역의 일부다. 값은 저장되지만 아이폰 아이가 읽지 않는다 |
   | 핸드폰 찾기 + '소리 끄기' | `:228-251` | 끈다 | |
   | 메시지 칩 넷·입력칸·보내기 | `:68-105` | **셋 다** 끈다 | 보내기만 끄고 입력칸을 열어 두면 **부모가 한 글자씩 써 놓고 못 보내는** 모양이 된다. 쓸 수 없는 편지를 쓰게 하지 않는다 |
   | 알람 시각·이름·맞추기·끄기 | `:110-133`, `:258-281` | **넷 다** 끈다 | 같은 이유 |
   | 인터넷 카드 | `:151-171` | **안 잠근다** | 읽기 전용이고, 아이폰 아이가 `network` 를 **실제로 쓴다**(`Documents.swift:246`) |
   | '지금 위치 확인' | `ChildMapView.swift:124-146` | 끈다 | |
   | '실시간 보기' | `ChildMapView.swift:156-185` | 끈다 | |
   | 예약 탭의 규칙·기본 모드·공휴일 | `ScheduleView.swift` | **안 잠근다** | 판정 기록 5 |
   | 장소 탭·알림 탭 | — | **안 잠근다** | 설계서 §10.2. 실제로 되는 것이다 |

   **문구를 놓는 자리는 셋이다.** ① 관리 탭 맨 위(`ControlView.swift:28` 의 `아이_안내` 바로 아래, 별도 줄) — 그 아래 모든 것이 잠겨 있다. ② 지도 탭의 **두 버튼 옆**(`ChildMapView.swift` 의 버튼 줄 위) — 지도 탭은 잠긴 것이 버튼 둘뿐이고 화면 대부분은 멀쩡하므로, 문장이 탭 꼭대기에 있으면 무엇을 가리키는지 모른다. ③ 예약 탭 맨 위(`ios_child_schedule_not_applied`).

8. **2단계 I2(도착 5분 안의 이탈이 사라진다)를 안 고친다. 대신 개발일지에 적는다.**
   `Logic/GeofenceEvaluator.swift:106` 의 5분 중복 억제는 방향을 안 가리고, 억제된 전환도 `inside` 는 갱신한다(`:121-122`). 도착 3분 뒤에 나가면 **그 방문의 이탈 알림은 영영 안 온다.** 시뮬레이터로 재현됐다(2단계 통합 검토).
   **정본인 `logic/GeofenceEvaluator.kt:113` 이 글자까지 같다.** 여기서 아이폰만 고치면 같은 좌표·같은 장소에서 **두 플랫폼의 알림 목록이 갈린다** — 부모가 아이 둘을 각각 다른 폰으로 보고 있으면 그 차이를 결함으로 읽는다. 3단계가 `EventType.SIGNAL_LOST` 를 안 쓰기로 한 것과 **같은 기준**이다(3단계 판정 기록 7: "한쪽만 쓰기 시작하면 두 플랫폼의 알림 목록이 갈린다").
   고치려면 두 플랫폼을 같이 고쳐야 하는데 `app/` 이 금지다. 그래서 **개발일지의 "안드로이드에서 고칠 것"에 적는다** — 재현 절차(도착 뒤 5분 안에 반경 밖으로)까지.

9. **2단계 M1(이름 예산이 두 배까지 늘 수 있다)을 안 고친다. `known-issues.md` 에 적는다.**
   코틀린은 대기와 요청을 `withTimeoutOrNull(left)` 로 **합쳐** 잘랐고(`child/TrailUploader.kt:201-206`), iOS 는 사전 검사(`PlaceNamer.swift:130`)와 소켓 제한시간(`TrailUploader.swift:132`)으로 나눠 뒀다. 최악의 경우 3초 예산이 ~6초가 된다.
   **대가 전부가 "업로드 한 번이 최대 3초 늦는다"이고, 그 업로드를 기다리는 사람이 없다** — 아이폰 아이는 명령을 안 듣는다(2단계 통합 검토가 그렇게 적었다). 반대편에는 이 기능 전체의 **마지막 단계에서 업로드 경로의 시간 예산 배선을 다시 짜는** 위험이 있다. 그 교환은 성립하지 않는다.
   **다만 실기기에서 값이 달라질 수 있는 항목이라 점검표 9번에 넣는다** — 백그라운드 실행 예산과 부딪치면(2단계 task-3 보고서 걱정 5) 그때는 대가가 "3초 지연"이 아니라 "업로드 실패"가 된다. 그 확인 뒤에 다시 연다.

10. **2단계 M2(`PlaceNameCache.decode` 의 숫자 해석)를 고친다 — 스위프트만 고치고, 골든은 안 늘린다.**
    코틀린 `toDoubleOrNull`(`logic/PlaceNameCache.kt:84-85`)은 앞뒤 공백과 자바식 `d`/`f` 접미사를 받고 스위프트 `Double.init`(`Logic/PlaceNameCache.swift:108`)은 거절한다. `encode` 가 만든 줄에는 그런 글자가 없어 실사용에서는 안 갈리지만, **골든 `decode` 케이스가 그 자리를 안 실어서 누가 이 줄을 바꿔도 대조가 못 잡는다.**
    골든을 늘리려면 `app/src/test/.../GoldenFileWriterTest.kt` 를 고쳐야 한다(설계서 §17 열린 질문 1 의 유일한 예외). **안 쓴다** — 이 단계가 `app/` 을 아예 안 만진다는 것이 더 지키기 쉬운 선이고, 같은 안전을 스위프트 쪽 단위 테스트로 **더 싸게** 살 수 있다. `PlaceNameCacheTests` 에 코틀린이 받는 글자들을 그대로 적은 테스트를 더하고, **그 테스트 주석이 `PlaceNameCache.kt:84-85` 를 인용한다.** 다음 사람이 이 줄을 건드리면 골든이 아니라 그 테스트가 잡는다.
    **관용을 넓히지 않는다.** 리뷰가 이름 댄 둘(앞뒤 공백, 한 글자짜리 `d`/`D`/`f`/`F` 접미사)만 받는다. 코틀린이 받는 16진 실수나 `Infinity` 까지 흉내 내는 것은 정본에 없는 입력을 상상하는 일이다.

11. **2단계 M4(사건 직후 업로드가 한 점 뒤처진 좌표를 싣는다)를 고친다 — 단, `lastFix` 를 옮기지 않는다.**
    `TrackingCoordinator.handle` 은 `skipTooClose` 에도 장소 판정을 돌리고(`:215`, 옳다 — 경계에서 몇 걸음 옮긴 순간이 정확히 그 모양이다), 그 뒤 `:221` 에서 `lastFix = fix` 전에 돌아간다(`:217`). 뒤이어 오는 `eventWritten`(`:297`)이 `lastFix` 로 올리므로 "학교에 도착했어요"와 함께 나가는 상태 문서의 좌표가 **직전 점**이다.
    **고치는 방법이 둘인데 하나는 함정이다.** `lastFix = fix` 를 `skipTooClose` 에서도 하도록 옮기면 다음 좌표의 거리 비교 기준이 바뀌어 **`LocationFilter` 의 판정 자체가 정본(`logic/LocationFilter.kt`)과 갈린다.** 그건 이 설계의 심장이다. **절대 옮기지 않는다.**
    쓰는 방법: `onPlaceFix?(fix)` 를 부르는 그 자리(`:215`)에서 **그 fix 를 따로 기억**하고, `eventWritten(at:)` 이 `lastFix` 대신 그것을 먼저 쓴다. 두 줄이고, `LocationFilter` 가 보는 상태를 하나도 안 건드린다.
    **구현자에게: 이 고침이 `lastFix` 나 `LocationFilter` 의 인자를 건드려야 하는 모양으로 커지면 멈추고 되돌린 뒤 이월로 남긴다.** 정의상 25m 안의 차이이고(2단계 통합 검토), 그것과 필터 판정을 바꾸는 위험은 바꿀 값이 아니다.

12. **골든 파일을 하나도 안 더하므로 `app/` 예외를 안 쓴다. 대신 골든이 *정말로 무는지*를 확인한다.**
    설계서 §14 4단계가 이 단계에 시킨 것은 골든을 **늘리는 것이 아니라** "골든 대조가 정말로 무는지 일부러 값을 망가뜨려 확인"하는 것이다. 2단계가 그 확인에서 실제로 구멍을 찾았다(`GoldenComparisonTests.swift:36-42` 의 주석 — `scheduleResolver.json` 을 `[]` 로 바꿔치기해도 일곱 테스트가 전부 통과했다). 그래서 Task 4 Step 3 은 **아이 역할이 쓰는 골든 다섯**(`locationFilter`·`movementTrailFilter`·`adaptiveMovementDetector`·`segmentBuilder`·`trailCodec`·`geofenceEvaluator`·`placeNameCache`)을 하나씩 망가뜨리고 **어느 테스트가 빨개지는지 이름으로** 적는다.

13. **1단계 M5(`LeaveFamilyModelTests` 의 벽시계 의존 셋)를 고친다.**
    1단계 리뷰가 10회 돌려 재현하지 못해 그대로 뒀지만, 방향은 그때 이미 적혀 있었다: 같은 파일이 **이미 쓰고 있는 `TestSignal`** 로 바꾼다. 셋 중 `:277` 이 특히 위험하다 — `Task { await m.뺀다() }` 가 50ms 안에 끝나면 `eventually { m.빼는중 }` 이 영영 참을 못 보고 멈춘다. 1단계 구현자가 전체 실행 한 번에서 본 빨강의 설명이 이것이다.
    **아이 역할 코드와 무관한데 여기서 고치는 이유**는, 이 단계가 이 기능의 **마지막** 단계이고 남은 벽시계 의존 셋을 다음 사람에게 "간헐적으로 빨개지는 테스트"로 넘기는 것이 이월 중 가장 값싸게 없앨 수 있는 빚이기 때문이다. 앱 코드는 한 줄도 안 바뀐다.

14. **실기기는 점검표까지만 쓰고, 돌리지 않는다.**
    설계서 §13 이 못박았다 — **실제 아이폰을 아이로 페어링하면 진짜 가족 문서에 쓰고 진짜 아이의 위치를 모으기 시작한다. 되돌릴 수 없는 종류의 일이다.** 그래서 이 단계가 만드는 것은 `ios/dev/device-verification.md` **한 장**이고, 그 문서의 첫 줄이 "**주인이 하라고 말하기 전에는 아무것도 하지 않는다**"이다.
    점검표에는 **페어링을 푸는 방법을 먼저** 적는다(설계서 §13: 보호자 앱에서 그 아이의 멤버 문서를 지우면 `firestore.rules:137` 로 아이 화면이 `child_family_gone` 이 되고 수집이 멎는다) — 시작하는 법보다 멈추는 법이 먼저 적혀 있어야 한다.
    **4단계의 나머지 전부는 시뮬레이터 + 에뮬레이터로 확인된다.** 보호자 잠금은 에뮬레이터의 아이 문서에 `platform` 을 넣고 빼는 것만으로 세 갈래를 다 밟을 수 있다(Task 4 Step 7).

---

## File Structure

```
i18n/
├─ ko.json                               수정. 새 키 둘
└─ en.json                               수정. 같음
tools/
└─ i18n-untranslated.json                재생성(--write-gaps)
docs/
├─ known-issues.md                       수정. 2단계 M1·M5 를 기록으로 남긴다
└─ superpowers/plans/
   └─ 2026-09-23-kidcare-ios-child-phase4.md   이 문서
README.md                                수정. 개발일지 한 절 + 개발 현황 표 한 행
ios/KidCare/Guardian/
├─ ChildPlatform.swift                   신규. platform 한 글자 → 세 갈래 판단 (설계서 §10.2)
├─ ChildPlatformStore.swift              신규. 아이 uid 별로 기억. RuleSyncStore.swift:12 와 같은 모양
├─ ControlViewModel.swift                수정. 플랫폼 보관 + send 입구 guard + 두 활성화 조건
├─ ControlView.swift                     수정. 문구 한 줄, 소리 상태 카드 숨김, 나머지 끄기
├─ MapViewModel.swift                    수정. 상태를 읽을 때 기억 + 두 보내기 guard + 버튼 조건 둘
├─ ChildMapView.swift                    수정. 문구 한 줄, 두 버튼 조건
├─ ScheduleViewModel.swift               수정. 플랫폼 주입 + 아이에게_알린다 guard + 깃발 안 올림
├─ ScheduleView.swift                    수정. 문구 한 줄, SyncPendingBar 숨김
├─ PlaceViewModel.swift                  수정. **기억만 시킨다.** 장소 탭은 안 잠근다
└─ GuardianRootView.swift                수정. 다섯 뷰모델에 같은 저장소를 넘긴다 (:38-56)
ios/KidCare/Logic/
└─ PlaceNameCache.swift                  수정. decode 의 숫자 해석을 코틀린과 맞춘다 (2단계 M2)
ios/KidCare/Child/
└─ TrackingCoordinator.swift             수정. 사건 직후 업로드가 그 사건의 좌표를 싣는다 (2단계 M4)
ios/KidCareTests/
├─ ChildPlatformTests.swift              신규. 세 갈래 표 + 저장소 왕복 + 모르면 안 잠근다
├─ GuardianPlatformGateTests.swift       신규. 세 탭이 명령을 한 번도 안 보낸다 / 안드로이드는 그대로
├─ ControlViewModelTests.swift           수정. 안드로이드 갈래가 지금과 같은지 먼저 본다
├─ MapViewModelTests.swift               수정. 같음
├─ ScheduleViewModelTests.swift          수정. 깃발과 바
├─ PlaceNameCacheTests.swift             수정. 코틀린이 받는 글자 (2단계 M2)
├─ TrackingCoordinatorTests.swift        수정. 사건 좌표 (2단계 M4)
└─ LeaveFamilyModelTests.swift           수정. Task.sleep 셋 → TestSignal (1단계 M5)
ios/dev/
└─ device-verification.md                신규. 실기기 점검표. **주인의 허락 전에는 안 돈다**
```

---

## Task 1: 판단 한 곳과 기억 한 곳 — 그리고 모르면 아무것도 안 잠근다

**끝나면 `ChildPlatform` 이 `platform` 한 글자를 세 갈래로 나누고, `ChildPlatformStore` 가 아이 uid 별로 그것을 기억하며, `.unknown` 이 **아무것도 안 잠그는 것**이 테스트로 묶인다. 화면은 아직 한 픽셀도 안 바뀐다.**

**Files:**
- Create: `ios/KidCare/Guardian/ChildPlatform.swift`, `ios/KidCare/Guardian/ChildPlatformStore.swift`, `ios/KidCareTests/ChildPlatformTests.swift`
- Modify: `i18n/ko.json`, `i18n/en.json`, `tools/i18n-untranslated.json`

- [ ] **Step 1: 문구 키 둘을 더한다 (공통 절차 A)**

`i18n/ko.json` 과 `i18n/en.json` 둘 다에, 코드 포인트 순서대로 넣는다. ko 는 **설계서 §10.2 의 글자 그대로**다.

```json
"ios_child_no_remote_control": "아이 폰이 아이폰이라 이 기능은 쓸 수 없어요. 위치와 장소 알림은 그대로 와요.",
"ios_child_schedule_not_applied": "규칙은 저장되지만 아이폰에서는 소리가 바뀌지 않아요.",
```

```json
"ios_child_no_remote_control": "Your child's phone is an iPhone, so this cannot be done. Location and place alerts still arrive.",
"ios_child_schedule_not_applied": "Rules are saved, but the sound will not change on an iPhone.",
```

두 키는 기존 `ios_child_low_power_notice`(`ko.json:150`)와 `ios_child_open_settings`(`:151`) 사이, 그리고 `ios_child_retry`(`:158`) 앞에 각각 들어간다 — **넣기 전에 `sort` 순서를 눈으로 확인한다.**

```bash
cd /Users/com/work/KidCare
python3 tools/ios-strings.py --write-gaps
git diff --stat i18n tools/i18n-untranslated.json ios/KidCare/Localizable.xcstrings
python3 tools/ios-strings.py --check   # 종료 코드 0
```
Expected: `tools/i18n-untranslated.json` 에 **두 키 × 12개 언어**가 는다. 그보다 많으면 다른 키를 건드린 것이다.

- [ ] **Step 2: 테스트를 먼저 쓴다 — `ios/KidCareTests/ChildPlatformTests.swift`**

```swift
import Foundation
import Testing
@testable import KidCare

/// 설계서 §10.1·§10.2. **이 파일이 지키는 것은 "아이폰을 잠근다"가 아니라
/// "모르는 아이를 잠그지 않는다"다** — 그쪽이 틀렸을 때의 대가가 훨씬 크기 때문이다
/// (멀쩡히 되는 안드로이드 아이의 기능이 이유 없이 사라진다).
struct ChildPlatformTests {

    @Test func 아이폰만_아이폰이다() {
        #expect(ChildPlatform.of(platform: "ios") == .iOS)
    }

    /// `Documents.swift:202` 가 없는 필드를 `""` 로 디코드한다. 지금 서버에 있는 모든
    /// 아이 문서가 이 모양이다.
    @Test func 빈_값은_안드로이드다() {
        #expect(ChildPlatform.of(platform: "") == .android)
    }

    /// 모르는 값을 아이폰으로 보면 안 된다 — 나중에 "android" 나 "web" 같은 글자가
    /// 생겨도 잠기는 쪽으로 기울면 안 된다.
    @Test func 모르는_글자도_안드로이드다() {
        #expect(ChildPlatform.of(platform: "android") == .android)
        #expect(ChildPlatform.of(platform: "IOS") == .android)   // 대소문자를 봐준다는 약속이 없다
        #expect(ChildPlatform.of(platform: "web") == .android)
    }

    /// 문서 자체가 없는 것만 `.unknown` 이다.
    @Test func 문서가_없으면_모른다() {
        #expect(ChildPlatform.of(status: nil) == .unknown)
    }

    @Test func 명령을_막는_것은_아이폰뿐이다() {
        #expect(ChildPlatform.iOS.명령을_받을_수_있나 == false)
        #expect(ChildPlatform.android.명령을_받을_수_있나 == true)
        #expect(ChildPlatform.unknown.명령을_받을_수_있나 == true)
    }

    /// **문구는 아이폰일 때만 뜬다.** 모르는 아이에게 "이 아이는 아이폰이에요"라고
    /// 말하는 것은 버튼을 끄는 것보다 더 나쁜 거짓말이다(판정 기록 2).
    @Test func 문구는_아이폰일_때만() {
        #expect(ChildPlatform.iOS.못_한다고_말할까 == true)
        #expect(ChildPlatform.android.못_한다고_말할까 == false)
        #expect(ChildPlatform.unknown.못_한다고_말할까 == false)
    }

    // MARK: - 저장소

    private func 빈_저장소(_ 이름: String = UUID().uuidString) -> ChildPlatformStore {
        ChildPlatformStore(defaults: UserDefaults(suiteName: 이름)!)
    }

    @Test func 기억이_없으면_모른다() {
        #expect(빈_저장소().platform(childUid: "c1") == .unknown)
    }

    @Test func 기억했다_꺼낸다() {
        let s = 빈_저장소()
        s.remember(childUid: "c1", platform: .iOS)
        s.remember(childUid: "c2", platform: .android)
        #expect(s.platform(childUid: "c1") == .iOS)
        #expect(s.platform(childUid: "c2") == .android)
        #expect(s.platform(childUid: "c3") == .unknown)   // 다른 아이의 기억이 새지 않는다
    }

    /// 상태 문서를 못 읽은 것은 **기억을 지우는 일이 아니다.** 네트워크가 잠깐 끊겨
    /// `nil` 이 왔다고 어제 알던 것을 잊으면, 예약 탭이 그 순간 잠금을 놓친다.
    @Test func 모름은_기억을_안_지운다() {
        let s = 빈_저장소()
        s.remember(childUid: "c1", platform: .iOS)
        s.remember(childUid: "c1", platform: .unknown)
        #expect(s.platform(childUid: "c1") == .iOS)
    }

    /// 아이가 폰을 갈아타면 덮인다.
    @Test func 바뀌면_덮는다() {
        let s = 빈_저장소()
        s.remember(childUid: "c1", platform: .iOS)
        s.remember(childUid: "c1", platform: .android)
        #expect(s.platform(childUid: "c1") == .android)
    }

    /// 상태 문서를 통째로 넘기는 길도 같은 답을 준다 — 화면이 두 길을 섞어 써도 갈리지 않는다.
    @Test func 문서로_기억시킨다() {
        let s = 빈_저장소()
        s.remember(childUid: "c1", status: ChildStatusDoc(["lat": 37.5, "lng": 127.0, "platform": "ios"]))
        #expect(s.platform(childUid: "c1") == .iOS)
    }
}
```

- [ ] **Step 3: `ios/KidCare/Guardian/ChildPlatform.swift`**

```swift
import Foundation

/// 아이 폰이 어떤 폰인가. 설계서 §10.2 가 "화면마다 `platform == "ios"` 를 직접 비교하지
/// 않는다 — 비교가 흩어지면 한 군데를 빠뜨린다"라고 정한 그 한 곳이다.
///
/// **`"ios"` 라는 글자는 이 저장소에 두 군데뿐이다**: 아이가 쓰는 `Documents.swift:252` 와
/// 보호자가 읽는 여기. 화면은 이 enum 만 본다.
enum ChildPlatform: Sendable {
    /// 상태 문서가 있고 `platform` 이 `"ios"` 가 **아닌** 모든 경우. 빈 값이 여기다.
    case android
    case iOS
    /// 상태 문서를 아직 못 읽었거나 아예 없다. **아이 폰이 한 번도 위치를 안 올린 가족이다.**
    case unknown

    /// 아이 상태 문서의 `platform` 한 글자로 판단한다.
    ///
    /// **빈 값·모르는 값이 전부 `.android` 인 것이 이 함수의 핵심이다**(설계서 §10.1).
    /// 지금 서버에 있는 모든 아이 문서에 이 필드가 없고, 모르는 아이의 기능을 조용히
    /// 없애면 안 된다. 반대 방향(아이폰인데 아직 안 잠김)은 아이 폰이 페어링 뒤 첫
    /// 좌표에서 업로드를 한 번 강제해 닫는다.
    static func of(platform: String) -> ChildPlatform {
        platform == "ios" ? .iOS : .android
    }

    /// 문서가 없으면 `.unknown`. 있으면 [of(platform:)].
    static func of(status: ChildStatusDoc?) -> ChildPlatform {
        guard let status else { return .unknown }
        return of(platform: status.platform)
    }

    /// 아이 폰이 `commands/` 를 구독하나. **`.iOS` 만 false** 다(설계서 §1·§10.2).
    /// 소리 모드·소리 상태 조회·핸드폰 찾기·메시지·알람·`locate_now`·실시간 보기·
    /// `sync_rules` 가 전부 이 한 줄에 달려 있다.
    var 명령을_받을_수_있나: Bool { self != .iOS }

    /// "아이폰이라 못 해요"를 화면에 적을까. **`.unknown` 에서는 안 적는다** — 모르는
    /// 아이에게 아이폰이라고 말하는 것은 버튼을 끄는 것보다 더 나쁜 거짓말이다.
    var 못_한다고_말할까: Bool { self == .iOS }
}
```

- [ ] **Step 4: `ios/KidCare/Guardian/ChildPlatformStore.swift`**

```swift
import Foundation

/// "이 아이는 아이폰이더라"를 아이 uid 별로 기억한다. 정본이 따로 없는 아이폰 전용
/// 저장소이고, 모양은 `RuleSyncStore.swift:12-33` 을 그대로 베꼈다.
///
/// **왜 기억이 필요한가 — 읽기 예산 때문이다.** 아이 상태 문서를 이미 읽는 탭이 셋이고
/// (지도·관리·장소) 예약 탭만 안 읽는다. 예약 탭에 읽기를 하나 더 달면 가족당 하루 50
/// 읽기 예산(`known-issues.md` 12번)에서 사는 것인데, 이 단계의 목적이 비용을 안 나쁘게
/// 하는 것이다(설계서 §11.2). 그래서 읽는 셋이 기억시키고 예약 탭은 기억을 본다.
///
/// **못 맞혀도 대가가 없다.** 기억이 없으면 `.unknown` 이고 `.unknown` 은 아무것도 안
/// 잠근다 — 지금 동작 그대로다(판정 기록 3).
///
/// 뷰모델이 아니라 저장소인 이유는 `RuleSyncStore.swift:9-10` 과 같다. 앱이 꺼져도 남아야
/// 두 번째 실행부터는 예약 탭이 처음부터 옳다.
struct ChildPlatformStore: Sendable {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func platform(childUid: String) -> ChildPlatform {
        switch defaults.string(forKey: key(childUid)) {
        case "ios": return .iOS
        case .some: return .android
        case nil: return .unknown
        }
    }

    /// **`.unknown` 은 기억을 지우지 않는다.** 네트워크가 잠깐 끊겨 상태 문서를 못 읽은
    /// 것이지, 아이 폰이 안드로이드가 된 것이 아니다. 여기서 지우면 그 순간 예약 탭이
    /// 잠금을 놓친다.
    func remember(childUid: String, platform: ChildPlatform) {
        switch platform {
        case .iOS: defaults.set("ios", forKey: key(childUid))
        case .android: defaults.set("android", forKey: key(childUid))
        case .unknown: return
        }
    }

    /// 상태 문서를 읽은 곳이 그대로 넘기는 길. 문서가 `nil` 이면 아무것도 안 한다.
    func remember(childUid: String, status: ChildStatusDoc?) {
        remember(childUid: childUid, platform: ChildPlatform.of(status: status))
    }

    /// `RoleStore`·`RequestLog`·`AlarmMemoStore`·`RuleSyncStore` 와 저장소 하나를 같이 쓰므로
    /// 종류를 앞에 붙인다(`RuleSyncStore.swift:38-40` 의 같은 이유).
    private func key(_ childUid: String) -> String {
        "child_platform_\(childUid)"
    }
}
```

- [ ] **Step 5: 돌린다**

```bash
cd /Users/com/work/KidCare/ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:KidCareTests/ChildPlatformTests \
  -only-testing:KidCareTests/I18nKeyParityTests \
  -only-testing:KidCareTests/LocalizableCatalogTests 2>&1 | tail -10
```
Expected: PASS. `ChildPlatformTests` 12개.

- [ ] **Step 6: 커밋**

```bash
cd /Users/com/work/KidCare
git add ios/KidCare/Guardian/ChildPlatform.swift ios/KidCare/Guardian/ChildPlatformStore.swift \
        ios/KidCareTests/ChildPlatformTests.swift i18n tools/i18n-untranslated.json \
        ios/KidCare/Localizable.xcstrings ios/project.yml
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" \
    commit -m "iOS 아이 4단계 1: 아이 폰이 아이폰인지 한 곳에서 판단한다 — 모르면 아무것도 안 잠근다"
```

---

## Task 2: 관리 탭과 지도 탭 — 명령 문서가 하나도 안 생긴다

**끝나면 아이폰 아이를 고른 보호자가 관리 탭의 어느 것도 누를 수 없고(소리 상태 카드는 아예 없고), 지도 탭의 '지금 위치 확인'·'실시간 보기'가 꺼져 있으며, 화면을 우회해 뷰모델을 직접 불러도 `commands/` 문서가 **하나도** 안 생긴다. 안드로이드 아이와 모르는 아이에게는 지금과 한 글자도 안 다르다.**

**Files:**
- Modify: `ios/KidCare/Guardian/ControlViewModel.swift`, `ControlView.swift`, `MapViewModel.swift`, `ChildMapView.swift`, `PlaceViewModel.swift`, `GuardianRootView.swift`
- Create: `ios/KidCareTests/GuardianPlatformGateTests.swift`
- Modify: `ios/KidCareTests/ControlViewModelTests.swift`, `MapViewModelTests.swift`

- [ ] **Step 1: 세 뷰모델이 저장소를 받는다**

`GuardianRootView.init`(`:38-56`)이 저장소 하나를 만들어 넷에 넘긴다. **하나여야 한다** — 넷이 각자 `ChildPlatformStore()` 를 만들면 같은 `UserDefaults` 를 보므로 동작은 같지만, 테스트에서 가짜 `defaults` 를 갈아 끼울 자리가 없어진다.

```swift
init(familyId: String, childUid: String?, selectedTab: Binding<GuardianTab>) {
    _selectedTab = selectedTab
    // 다섯 탭이 같은 기억을 본다. 상태 문서를 읽는 셋이 쓰고, 예약 탭은 읽기만 한다(판정 기록 3).
    let platforms = ChildPlatformStore()
    let map = MapViewModel(familyId: familyId, childUid: childUid, platforms: platforms)
    ...
    let control = ControlViewModel(familyId: familyId, childUid: childUid, platforms: platforms)
    ...
    _scheduleViewModel = State(initialValue: ScheduleViewModel(familyId: familyId, childUid: childUid, platforms: platforms))
    _placeViewModel = State(initialValue: PlaceViewModel(familyId: familyId, childUid: childUid, platforms: platforms))
    ...
}
```

각 뷰모델의 `init` 에 `platforms: ChildPlatformStore = ChildPlatformStore()` 를 **기본값 있는 인자로** 더한다. 기본값을 두는 이유는 `ScheduleViewModel`·`PlaceViewModel` 의 호출부가 테스트에 많아서다 — 3단계가 `TrackingCoordinator(ticker:)` 에서 기본값을 **없앤** 것과 반대 판단인데, 근거가 다르다: 거기서는 인자를 빠뜨리면 **조용히 고장**이 났고(멈춘 폰이 `.moving` 에 갇힌다), 여기서는 빠뜨리면 **지금과 똑같이 동작한다**(`.unknown` → 안 잠금). 빠뜨린 대가가 "오늘의 동작"이면 컴파일을 막을 이유가 없다.

`ScheduleViewModel` 도 이 Step 에서 인자만 받아 둔다(쓰는 것은 Task 3).

- [ ] **Step 2: `ControlViewModel` — 기억시키고, 두 활성화를 좁히고, `send` 를 막는다**

`상태를_읽는다`(`:628-630`)가 문서를 받은 자리에서 기억시킨다.

```swift
// 읽기를 하나도 더 안 사고 플랫폼을 안다 — 이 함수가 이미 읽고 있다(판정 기록 3).
if let childUid { platforms.remember(childUid: childUid, status: 상태) }
```

플랫폼을 읽는 계산 프로퍼티 하나와, 그 위에 얹은 세 줄:

```swift
/// 고른 아이의 폰 종류. 상태 문서를 이미 읽었으면 그 값이고, 아직이면 기억해 둔 값이다.
/// 둘 다 없으면 `.unknown` — **아무것도 안 잠근다**(판정 기록 2).
var 플랫폼: ChildPlatform {
    if let 상태 { return ChildPlatform.of(platform: 상태.platform) }
    guard let childUid else { return .unknown }
    return platforms.platform(childUid: childUid)
}

/// 설계서 §10.2. 아이폰 아이는 `commands/` 를 구독하지 않으므로 이 탭의 모든 버튼이
/// "영원히 전달 중"이 된다.
var 명령을_보낼_수_있나: Bool { 플랫폼.명령을_받을_수_있나 }
var 아이폰이라_못_한다고_말할까: Bool { 플랫폼.못_한다고_말할까 }

var 버튼_활성화: Bool { childUid != nil && 명령을_보낼_수_있나 }
var 새로_확인_활성화: Bool { childUid != nil && 명령을_보낼_수_있나 && !상태_읽는_중 && !ringerQueryInFlight }
```

그리고 **아래쪽 겹** — `send`(`:410-418`)의 입구. 이미 있는 `guard let childUid` 바로 뒤다.

```swift
private func send(
    _ type: String,
    payload: [String: String] = [:],
    onSent: @escaping @MainActor () -> Void = {}
) async {
    guard let childUid else {
        commandUi = .failed(String(localized: "map_no_child"))
        return
    }
    // 아이폰 아이에게 보낸 명령은 아무도 안 읽어 영원히 "전달 중"에 머문다(설계서 §1·§10.2).
    // 화면이 버튼을 껐지만 계약은 여기다 — `commands/` 문서를 하나도 안 만든다.
    guard 명령을_보낼_수_있나 else {
        commandUi = .failed(String(localized: "ios_child_no_remote_control"))
        return
    }
    ...
}
```

**`.failed` 로 두는 이유**: 이 자리에 오는 길이 남아 있다면 그것은 화면의 버그이고, 그때 부모가 보는 문장은 **참말이어야** 한다. 조용히 `return` 하면 아무 일도 안 일어난 것처럼 보인다.

- [ ] **Step 3: `ControlView` — 문구 한 줄, 소리 상태 카드 숨김, 나머지 끄기**

`.disabled(!viewModel.버튼_활성화)` 를 쓰는 자리는 Step 2 가 이미 좁혔으므로 **한 줄도 안 고쳐도 꺼진다**(`:56·224·241·328·343`). 이 Step 이 손대는 것은 셋이다.

① **문구 한 줄** — `아이_안내`(`:28-34`) 바로 아래.

```swift
if viewModel.아이폰이라_못_한다고_말할까 {
    Text("ios_child_no_remote_control")
        .font(.subheadline)
        .foregroundStyle(KidCarePalette.inkSoft)
        .padding(.bottom, 16)
}
```
`아이_안내` 를 **재사용하지 않는다** — 그것은 오류 문구 자리라 `:300` 에서 지워지고 `:304` 에서 덮인다. 이 줄은 **늘 있어야** 한다.

② **소리 상태 카드를 숨긴다**(판정 기록 7). `:37-43` 의 소리 구역에서 카드와 방해금지 줄을 감싼다.

```swift
구역_제목("control_section_ringer")
// 아이폰 아이는 `ringerMode` 를 일부러 빈 값으로 쓴다(`Documents.swift:239`). 그래서 이 카드는
// 영원히 "확인되지 않음"이고 그 안의 '새로 확인'은 눌러도 영원히 안 바뀐다. 값이 없는 칸과
// 답이 없는 질문을 흐리게 남겨 두느니 지운다(판정 기록 7).
if viewModel.플랫폼 != .iOS {
    소리_상태_카드.padding(.top, 8)
    if viewModel.방해금지_안내를_보이는가 {
        보조_문구("control_ringer_dnd_note").padding(.top, 6)
    }
}
모드_버튼들.padding(.top, 8)
```
`플랫폼 != .iOS` 를 **여기서만** 직접 쓴다 — 이것은 "명령을 보낼 수 있나"가 아니라 "보여줄 값이 있나"라 다른 질문이다. 판정 기록 1 의 "글자를 비교하지 않는다"는 지킨다(`"ios"` 라는 문자열이 아니라 enum 을 비교한다).

③ **메시지 칩·입력칸과 알람 시각·이름을 끈다.** 지금은 안 꺼진다(판정 기록 7: 보내기만 끄면 부모가 못 보낼 편지를 쓴다).

- 칩 `Button`(`:70`) 에 `.disabled(!viewModel.버튼_활성화)` 를 더한다.
- 메시지 `TextField`(`:95-101`)에 `.disabled(!viewModel.버튼_활성화)`.
- 알람 이름 칸(`:121-125`)에 같은 줄.
- `알람_시각_줄`(`:258-281`)의 누르는 자리에 같은 줄.

넷 다 `.opacity(viewModel.버튼_활성화 ? 1 : 0.38)` 을 같이 붙여 **기존 다섯 자리와 같은 모양**으로 흐려지게 한다.

- [ ] **Step 4: `MapViewModel` — 기억시키고, 버튼 둘을 좁히고, 보내기 둘을 막는다**

기억시키는 자리는 둘이다. 하루 읽기(`:460`)와 실시간 구독(`:1174`).

```swift
// :460 부근 — 상태 = 읽은_것.status 바로 뒤
if let childUid { platforms.remember(childUid: childUid, status: 상태) }
```
```swift
// :1174 부근 — 상태 = status 바로 뒤
if let childUid { platforms.remember(childUid: childUid, status: status) }
```
실시간 쪽도 기억시키는 이유: 실시간이 도는 동안 아이가 폰을 갈아탔다면 그것이 **가장 최신 정보**다.

같은 모양의 계산 프로퍼티와, 버튼 둘:

```swift
var 플랫폼: ChildPlatform {
    if let 상태 { return ChildPlatform.of(platform: 상태.platform) }
    guard let childUid else { return .unknown }
    return platforms.platform(childUid: childUid)
}
var 명령을_보낼_수_있나: Bool { 플랫폼.명령을_받을_수_있나 }
var 아이폰이라_못_한다고_말할까: Bool { 플랫폼.못_한다고_말할까 }

var 위치확인_버튼_활성화: Bool {
    childUid != nil && 명령을_보낼_수_있나 && !commandProgress.isInFlight && !liveTrackingActiveOrTransitioning
}

/// 지금까지 `ChildMapView.swift:180` 에 인라인으로 있던 조건을 여기로 옮긴다 —
/// 판단이 뷰에 흩어져 있으면 다음 사람이 한 군데를 빠뜨린다(판정 기록 1).
var 실시간_버튼_활성화: Bool { childUid != nil && 명령을_보낼_수_있나 }
```

보내기 둘의 입구 guard:

```swift
// `지금_위치를_확인한다()` (:626) 맨 앞
guard 명령을_보낼_수_있나 else { return }
// `실시간_추적을_시작한다()` (:1048) 맨 앞
guard 명령을_보낼_수_있나 else { return }
```
`stopLiveTrackingCore(sendCommand:)`(`:1234-1260`)의 끄기(`:1256-1258`)는 **안 막는다.** 켠 적이 없으면 불릴 일이 없고, 어쩌다 켜져 있었다면 끄는 것은 반드시 되어야 한다(판정 기록 4).

- [ ] **Step 5: `ChildMapView` — 두 버튼 옆에 문구 한 줄**

버튼 줄(`:88-95`) **위**에, 패널 위 영역에 놓는다. 탭 꼭대기가 아니라 **버튼 옆**인 이유는 판정 기록 7 에 적었다.

```swift
if viewModel.아이폰이라_못_한다고_말할까 {
    Text("ios_child_no_remote_control")
        .font(.caption)
        .foregroundStyle(KidCarePalette.ink)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(KidCarePalette.cardSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.bottom, 8)
}
```
`KidCarePalette` 의 실제 이름은 `ios/KidCare/Guardian/KidCarePalette.swift` 를 **열어서 확인하고** 쓴다 — 지도 위에 얹는 카드가 이미 쓰는 색을 그대로 쓴다(`StatusCardView.swift` 가 정본).

실시간 버튼의 `.disabled`(`:180`)를 새 프로퍼티로 바꾼다.

```swift
.disabled(!viewModel.실시간_버튼_활성화)
.opacity(viewModel.실시간_버튼_활성화 ? 1 : 0.55)
```

- [ ] **Step 6: `PlaceViewModel` — 기억만 시킨다**

장소 탭은 **안 잠근다**(설계서 §10.2 — 장소는 아이폰 아이가 상시 구독으로 실제로 받는다). 하는 일은 자기가 이미 읽는 상태 문서를 기억시키는 것 하나다. `statusFetch`(`:116`)의 결과가 들어오는 자리에 `platforms.remember(childUid:status:)` 한 줄.

- [ ] **Step 7: 테스트 — `ios/KidCareTests/GuardianPlatformGateTests.swift`**

```swift
import Foundation
import Testing
@testable import KidCare

/// 설계서 §10.2. **이 파일이 지키는 계약은 "버튼이 흐리다"가 아니라
/// "`commands/` 문서가 하나도 안 생긴다"다.** 흐린 버튼을 우회하는 길(스크린 리더, 키보드,
/// 다음 사람이 뷰를 고치는 것)은 눈에 안 보이기 때문이다(판정 기록 4).
@MainActor
struct GuardianPlatformGateTests {

    private func 저장소(_ 값: [String: ChildPlatform]) -> ChildPlatformStore {
        let s = ChildPlatformStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        for (uid, p) in 값 { s.remember(childUid: uid, platform: p) }
        return s
    }

    /// 보낸 명령을 세는 가짜. **한 번도 안 불리는 것**이 합격이다.
    private final class 보낸_것 {
        var types: [String] = []
    }

    // MARK: - 관리 탭

    @Test func 아이폰이면_관리_탭_명령이_하나도_안_나간다() async {
        let 기록 = 보낸_것()
        let vm = ControlViewModel(
            familyId: "f1", childUid: "c1",
            platforms: 저장소(["c1": .iOS]),
            commandSend: { _, _, type, _ in 기록.types.append(type); return "cmd" }
        )
        await vm.소리_모드를_보낸다(RingerMode.silent)
        await vm.소리_상태를_묻는다()
        await vm.폰찾기_버튼을_눌렀다()
        await vm.소리를_끈다()
        vm.메시지 = "밥 먹었니"
        await vm.메시지를_보낸다()
        await vm.알람을_맞춘다()
        await vm.알람을_끈다()
        #expect(기록.types.isEmpty)
        #expect(vm.버튼_활성화 == false)
        #expect(vm.새로_확인_활성화 == false)
        #expect(vm.아이폰이라_못_한다고_말할까 == true)
    }

    /// **이쪽이 더 중요하다.** 안드로이드 아이에게 지금과 한 글자도 다르면 안 된다(주인 판정).
    @Test func 안드로이드면_지금과_똑같다() async {
        let 기록 = 보낸_것()
        let vm = ControlViewModel(
            familyId: "f1", childUid: "c1",
            platforms: 저장소(["c1": .android]),
            commandSend: { _, _, type, _ in 기록.types.append(type); return "cmd" }
        )
        await vm.소리_모드를_보낸다(RingerMode.silent)
        #expect(기록.types == [CommandType.setRinger])
        #expect(vm.버튼_활성화 == true)
        #expect(vm.아이폰이라_못_한다고_말할까 == false)
    }

    /// 아이를 모를 때도 지금과 똑같다. **문구도 안 뜬다**(판정 기록 2).
    @Test func 모르면_지금과_똑같다() async {
        let 기록 = 보낸_것()
        let vm = ControlViewModel(
            familyId: "f1", childUid: "c1",
            platforms: 저장소([:]),
            commandSend: { _, _, type, _ in 기록.types.append(type); return "cmd" }
        )
        await vm.소리_모드를_보낸다(RingerMode.normal)
        #expect(기록.types == [CommandType.setRinger])
        #expect(vm.버튼_활성화 == true)
        #expect(vm.아이폰이라_못_한다고_말할까 == false)
    }

    /// 상태 문서를 읽으면 기억보다 그쪽이 이긴다 — 아이가 폰을 갈아탄 날의 정답이다.
    @Test func 읽은_문서가_기억을_이긴다() async {
        let s = 저장소(["c1": .android])
        let vm = ControlViewModel(
            familyId: "f1", childUid: "c1", platforms: s,
            statusFetch: { _, _ in ChildStatusDoc(["lat": 37.5, "lng": 127.0, "platform": "ios"]) }
        )
        vm.시작한다()
        await vm.상태를_읽는다()
        #expect(vm.플랫폼 == .iOS)
        #expect(s.platform(childUid: "c1") == .iOS)   // 읽은 김에 기억까지 갱신됐다
    }

    // MARK: - 지도 탭

    @Test func 아이폰이면_지도_탭_명령이_하나도_안_나간다() async {
        let 기록 = 보낸_것()
        let vm = MapViewModel(
            familyId: "f1", childUid: "c1",
            platforms: 저장소(["c1": .iOS]),
            commandSend: { _, _, type, _ in 기록.types.append(type); return "cmd" }
        )
        await vm.지금_위치를_확인한다()
        await vm.실시간_추적을_토글한다()
        #expect(기록.types.isEmpty)
        #expect(vm.위치확인_버튼_활성화 == false)
        #expect(vm.실시간_버튼_활성화 == false)
        #expect(vm.liveTrackingState == .off)
    }

    @Test func 지도_탭도_안드로이드면_지금과_똑같다() async {
        let 기록 = 보낸_것()
        let vm = MapViewModel(
            familyId: "f1", childUid: "c1",
            platforms: 저장소(["c1": .android]),
            commandSend: { _, _, type, _ in 기록.types.append(type); return "cmd" }
        )
        await vm.지금_위치를_확인한다()
        #expect(기록.types == [CommandType.locateNow])
        #expect(vm.위치확인_버튼_활성화 == true || vm.commandProgress.isInFlight)
    }
}
```

**가짜 `commandSend` 의 정확한 인자 이름과 시그니처는 기존 `ControlViewModelTests`·`MapViewModelTests` 를 열어 그대로 베낀다** — 이 계획서가 추측해 적지 않는다. `ControlViewModel.init` 의 `commandSend` 는 `:160` 부근, `MapViewModel.init` 은 `:313` 부근에 있다.

- [ ] **Step 8: 기존 테스트가 안 깨지는지**

`ControlViewModelTests`·`MapViewModelTests` 의 기존 케이스는 `platforms` 를 안 넘기므로 `.unknown` 이고, `.unknown` 은 아무것도 안 잠근다 — **한 줄도 안 고쳐도 전부 초록이어야 한다.** 빨개지는 것이 있으면 그것은 `.unknown` 이 안 잠근다는 약속이 깨졌다는 뜻이다. 고칠 곳은 테스트가 아니라 구현이다.

```bash
cd /Users/com/work/KidCare/ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:KidCareTests/GuardianPlatformGateTests \
  -only-testing:KidCareTests/ControlViewModelTests \
  -only-testing:KidCareTests/MapViewModelTests \
  -only-testing:KidCareTests/LiveTrackingTests 2>&1 | tail -10
```

- [ ] **Step 9: 커밋**

```bash
cd /Users/com/work/KidCare
git add ios/KidCare/Guardian ios/KidCareTests/GuardianPlatformGateTests.swift ios/project.yml
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" \
    commit -m "iOS 아이 4단계 2: 아이폰 아이에게는 관리 탭과 지도 탭이 명령을 만들지 않는다"
```

---

## Task 3: 예약 탭 — 규칙은 그대로 저장되고, 알릴 것은 애초에 없다

**끝나면 아이폰 아이의 예약 탭에서 규칙을 만들고 고치고 지우고 기본 모드와 공휴일을 바꾸는 것이 **전부 평소처럼 되고 평소처럼 저장되며**, `sync_rules` 명령은 한 번도 안 나가고, `pendingSync` 깃발은 한 번도 안 올라가고, '아이 폰에 알리기' 바는 한 번도 안 뜨고, 탭 맨 위에 "규칙은 저장되지만 아이폰에서는 소리가 바뀌지 않아요"가 늘 있다.**

**Files:**
- Modify: `ios/KidCare/Guardian/ScheduleViewModel.swift`, `ScheduleView.swift`
- Modify: `ios/KidCareTests/ScheduleViewModelTests.swift`, `ios/KidCareTests/GuardianPlatformGateTests.swift`

- [ ] **Step 1: 뷰모델이 플랫폼을 본다**

Task 2 Step 1 이 인자만 받아 뒀다. 이제 쓴다.

```swift
/// 예약 탭은 아이 상태 문서를 안 읽는 **유일한 탭**이다. 그래서 여기만 기억에 기댄다
/// (판정 기록 3). 기억이 없으면 `.unknown` 이고 `.unknown` 은 아무것도 안 잠근다 —
/// 못 맞혔을 때의 대가가 "지금 동작 그대로"라서 되는 설계다.
var 플랫폼: ChildPlatform {
    guard let childUid else { return .unknown }
    return platforms.platform(childUid: childUid)
}
var 아이폰이라_규칙이_안_걸린다: Bool { 플랫폼.못_한다고_말할까 }
```

- [ ] **Step 2: `sync_rules` 를 안 보내고, 깃발을 안 올린다**

`아이에게_알린다(_:)`(`:512-539`)의 입구. 기존 `guard let childUid`(`:514-519`) **바로 뒤**다.

```swift
private func 아이에게_알린다(_ generation: Int) async {
    guard !닫힘 else { return }
    guard let childUid else {
        깃발을_바꾼다(false)
        if 글자를_쓸_수_있나(generation) { 상태_줄 = String(localized: "schedule_sync_no_child") }
        return
    }
    // 아이폰 아이는 `commands/` 를 구독하지 않는다(설계서 §1). 여기서 보내면 그 문서는
    // 쓰기 하나를 태우고 아무도 안 읽는 자리에 영원히 남고, 깃발이 영영 안 내려가
    // '아이 폰에 알리기' 바가 "아직 못 알렸어요"를 계속 띄운다 — 부모는 그것을 **일시적인
    // 실패**로 읽고 계속 다시 누른다. 알릴 것이 없다는 사실은 버튼이 아니라 탭 맨 위의
    // 문장이 말한다(판정 기록 5).
    //
    // **규칙 자체는 이미 저장됐고 그대로 둔다** — 그 아이가 나중에 안드로이드 폰으로
    // 바뀌면 그 폰이 읽어 간다(설계서 §10.2).
    guard 플랫폼.명령을_받을_수_있나 else {
        깃발을_바꾼다(false)
        return
    }
    ...
}
```

`상태_줄` 을 **안 건드린다.** 방금 저장한 규칙에 대해 뜨는 성공 문구를 "못 알렸어요"류로 덮으면, 실제로 저장에 성공한 일이 실패처럼 읽힌다. 왜 소리가 안 바뀌는지는 탭 맨 위 문장이 **늘** 말하고 있다.

`깃발을_바꾼다(false)` 를 부르는 이유: 다섯 쓰기 갈래가 **쓰기 전에** 깃발을 올린다(`:334·370·403·432·468`). 여기서 내려야 `RuleSyncStore` 에 남지 않는다. 앞선 버전에서 올라간 채 남아 있던 깃발도 이 한 줄이 치운다.

`다시_알린다()`(`:544-554`)는 **안 고친다** — `아이에게_알린다` 를 거치므로 저절로 막히고, 입구 조건에 `pendingSync` 가 있어 깃발이 안 올라가면 애초에 `nil` 을 돌려준다. `GuardianRootView.swift:91·128` 의 두 호출부도 마찬가지다.

- [ ] **Step 3: `ScheduleView` — 문구 한 줄, 바 숨김**

① 탭 맨 위. 목록 앞이다.

```swift
if viewModel.아이폰이라_규칙이_안_걸린다 {
    Text("ios_child_schedule_not_applied")
        .font(.subheadline)
        .foregroundStyle(KidCarePalette.inkSoft)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 12)
}
```

② `SyncPendingBar`(`:63-68`)를 감싼다.

```swift
// 아이폰 아이에게는 이 바가 **한 번도** 안 뜬다. 깃발이 안 올라가므로 조건만으로도 안 뜨지만,
// 옛 버전이 올려 둔 깃발이 `UserDefaults` 에 남아 있을 수 있어 화면에서도 한 겹 막는다
// (Task 3 Step 2 의 `깃발을_바꾼다(false)` 가 그것을 치우기 **전에** 한 번 그려질 수 있다).
if viewModel.pendingSync && !viewModel.아이폰이라_규칙이_안_걸린다 {
    SyncPendingBar(...)
}
```

**끄지 않고 숨기는 이유는 판정 기록 5·7 에 적었다.** 흐려진 "아직 못 알렸어요"는 일시적 실패로 읽힌다.

③ **규칙 목록·추가 버튼·기본 모드 넷·공휴일 스위치는 한 줄도 안 고친다.** `설정_잠김`(`:143·175`)은 지금 있는 그대로다 — 그것은 다른 이유의 잠금이다.

- [ ] **Step 4: 테스트**

`GuardianPlatformGateTests` 에 더한다.

```swift
// MARK: - 예약 탭

/// 저장은 되고 알림만 안 간다. **이 두 줄이 같은 테스트에 있어야** 한 쪽만 고치는 사고가 잡힌다.
@Test func 아이폰이면_규칙은_저장되고_알림만_안_간다() async {
    let 기록 = 보낸_것()
    let 저장된 = 보낸_것()
    let vm = ScheduleViewModel(
        familyId: "f1", childUid: "c1",
        platforms: 저장소(["c1": .iOS]),
        scheduleSave: { _, _, doc in 저장된.types.append(doc.id); return doc.id },
        commandSend: { _, _, type, _ in 기록.types.append(type); return "cmd" }
    )
    await vm.기본_모드를_고른다(RingerMode.silent)
    #expect(기록.types.isEmpty)          // sync_rules 가 안 나갔다
    #expect(vm.pendingSync == false)      // 깃발이 안 남았다
    #expect(vm.아이폰이라_규칙이_안_걸린다 == true)
}

@Test func 안드로이드면_예약_탭도_지금과_똑같다() async {
    let 기록 = 보낸_것()
    let vm = ScheduleViewModel(
        familyId: "f1", childUid: "c1",
        platforms: 저장소(["c1": .android]),
        commandSend: { _, _, type, _ in 기록.types.append(type); return "cmd" }
    )
    await vm.기본_모드를_고른다(RingerMode.silent)
    #expect(기록.types == [CommandType.syncRules])
    #expect(vm.아이폰이라_규칙이_안_걸린다 == false)
}

/// 옛 버전이 올려 둔 깃발이 남아 있어도 아이폰 아이에게는 안 보인다.
@Test func 남아_있던_깃발도_내려간다() async {
    let 기록 = 보낸_것()
    let store = RuleSyncStore(kind: .schedule, defaults: UserDefaults(suiteName: UUID().uuidString)!)
    store.setPendingSync(childUid: "c1", true)
    let vm = ScheduleViewModel(
        familyId: "f1", childUid: "c1", syncStore: store,
        platforms: 저장소(["c1": .iOS]),
        commandSend: { _, _, type, _ in 기록.types.append(type); return "cmd" }
    )
    vm.시작한다()
    _ = await vm.다시_알린다()?.value
    #expect(기록.types.isEmpty)
    #expect(store.pendingSync(childUid: "c1") == false)
}
```

**다섯 쓰기 갈래 전부**(`규칙을_저장한다`·`켬끔을_바꾼다`·`삭제를_확인했다`·`기본_모드를_고른다`·`공휴일을_바꾼다`)에 대해 같은 확인을 한다 — 위 예시는 하나뿐이지만, 다섯이 각자 `아이에게_알린다` 를 부르므로(`:349·383·414·449·485`) **다섯을 다 돌려야** 한 갈래만 우회하는 사고가 잡힌다. `ScheduleViewModelTests` 의 기존 케이스에서 각 갈래를 부르는 모양을 그대로 베낀다.

```bash
cd /Users/com/work/KidCare/ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:KidCareTests/GuardianPlatformGateTests \
  -only-testing:KidCareTests/ScheduleViewModelTests 2>&1 | tail -10
```

- [ ] **Step 5: 커밋**

```bash
cd /Users/com/work/KidCare
git add ios/KidCare/Guardian/ScheduleViewModel.swift ios/KidCare/Guardian/ScheduleView.swift \
        ios/KidCareTests/GuardianPlatformGateTests.swift ios/KidCareTests/ScheduleViewModelTests.swift
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" \
    commit -m "iOS 아이 4단계 3: 예약 규칙은 그대로 저장하되 아이폰에는 알리지 않는다"
```

---

## Task 4: 전수 검토, 이월 닫기, 개발일지, 실기기 점검표

**끝나면 설계서 §4 의 상수가 코드와 한 줄씩 맞고, 골든 대조를 일부러 깨면 실제로 빨개지고, 모든 리스너와 OS 지역에 떼는 길이 있고, 하루 쓰기 수가 §11.2 의 계산 안에 있고, 아이 기능 전체의 문구 중 아이폰이 못 하는 것을 할 수 있다고 말하는 것이 **하나도** 없고, 이월 넷이 닫히고 셋이 이유와 함께 열린 채 기록되고, README 에 개발일지가 한 절 들어가고, 실기기 점검표가 **적혀 있되 안 돌아간 채로** 남는다.**

**Files:**
- Modify: `ios/KidCare/Logic/PlaceNameCache.swift`(2단계 M2), `ios/KidCare/Child/TrackingCoordinator.swift`(2단계 M4)
- Modify: `ios/KidCareTests/PlaceNameCacheTests.swift`, `TrackingCoordinatorTests.swift`, `LeaveFamilyModelTests.swift`(1단계 M5)
- Modify: `README.md`, `docs/known-issues.md`
- Create: `ios/dev/device-verification.md`

- [ ] **Step 1: 이월 셋을 고친다**

**① 2단계 M2 — `PlaceNameCache.decode` 의 숫자 해석**(판정 기록 10). `ios/KidCare/Logic/PlaceNameCache.swift:107-108`.

```swift
// 코틀린 `toDoubleOrNull`(`logic/PlaceNameCache.kt:84-85`)은 앞뒤 공백과 자바식 `d`/`f`
// 접미사를 받는데 스위프트 `Double.init` 은 거절한다. `encode` 가 만든 줄에는 그런 글자가
// 없어 실사용에서는 안 갈리지만, 두 구현이 **같은 함수**라는 약속은 입력이 어디서 오든
// 지켜져야 한다(2단계 통합 검토 M2). **정본이 받는 것만 받는다** — 16진 실수나 Infinity
// 까지 흉내 내는 것은 정본에 없는 입력을 상상하는 일이다.
private static func 코틀린_실수(_ text: some StringProtocol) -> Double? {
    var s = text.trimmingCharacters(in: .whitespaces)
    if let last = s.last, "dDfF".contains(last) { s.removeLast() }
    return Double(s)
}
```
`:107-108` 의 `Double(coordinates[0])`·`Double(coordinates[1])` 을 이 함수로 바꾼다.

`PlaceNameCacheTests` 에 더한다(주석이 `PlaceNameCache.kt:84-85` 를 인용한다 — 골든이 이 자리를 안 실으므로 **이 테스트가 유일한 대조**다).

```swift
/// 골든 `decode` 케이스가 이 자리를 안 싣는다(2단계 M2). 정본 `logic/PlaceNameCache.kt:84-85`
/// 의 `toDoubleOrNull` 이 받는 글자를 여기에 적어 둔다 — 이 줄을 건드리면 골든이 아니라
/// 이 테스트가 잡는다.
@Test func 코틀린이_받는_숫자를_똑같이_받는다() {
    let c = PlaceNameCache.decode("  37.5 , 127.0  \t집\n37.6d,127.1f\t학교\n")
    #expect(c.find(lat: 37.5, lng: 127.0) == "집")
    #expect(c.find(lat: 37.6, lng: 127.1) == "학교")
}

@Test func 코틀린도_안_받는_것은_안_받는다() {
    #expect(PlaceNameCache.decode("37,5,127.0\t집").find(lat: 37.5, lng: 127.0) == nil)
    #expect(PlaceNameCache.decode("abc,127.0\t집").find(lat: 37.5, lng: 127.0) == nil)
}
```
`find` 의 정확한 시그니처는 `PlaceNameCacheTests` 의 기존 케이스에서 베낀다. **골든 대조 일곱(`장소이름_캐시_대조`)이 그대로 초록인지**를 같이 본다 — 관용을 넓혔는데 기존 케이스가 갈리면 넓힌 것이 틀린 것이다.

**② 2단계 M4 — 사건 직후 업로드가 그 사건의 좌표를 싣는다**(판정 기록 11). `ios/KidCare/Child/TrackingCoordinator.swift`.

`:215` 의 `onPlaceFix?(fix)` 자리:

```swift
if decision != .rejectInaccurate, decision != .rejectImpossible {
    // `eventWritten` 이 쓸 좌표를 여기서 붙든다(2단계 M4). `lastFix` 는 `SKIP_TOO_CLOSE`
    // 에서 갱신되지 **않으므로**(:217 에서 돌아간다), 그 자리에서 난 사건의 강제 업로드가
    // 한 점 뒤처진 좌표를 싣고 있었다 — "학교에 도착했어요"와 함께 직전 위치가 나갔다.
    //
    // **`lastFix = fix` 를 여기로 옮기지 않는다.** 옮기면 다음 좌표의 거리 비교 기준이
    // 바뀌어 `LocationFilter` 의 판정 자체가 정본(`logic/LocationFilter.kt`)과 갈린다.
    // 이 설계의 심장이다.
    사건_판정에_쓴_fix = fix
    onPlaceFix?(fix)
}
```

`eventWritten(at:)`(`:297`):

```swift
func eventWritten(at now: Int64) {
    // 그 사건을 만든 좌표가 있으면 그것을 쓴다(2단계 M4). 없으면 예전대로 `lastFix`.
    guard let fix = 사건_판정에_쓴_fix ?? lastFix,
          shouldUpload(now: now, fix: fix, eventJustWritten: true) else { return }
    ...
}
```

`private var 사건_판정에_쓴_fix: Fix?` 를 `lastFix` 옆에 선언한다.

`TrackingCoordinatorTests` 에 더한다:

```swift
/// 2단계 M4. `SKIP_TOO_CLOSE` 로 거절된 좌표에서 장소 사건이 나면, 그 사건과 함께 올라가는
/// 상태 문서의 좌표는 **그 사건을 만든 좌표**여야 한다 — 한 점 뒤처진 직전 위치가 아니라.
@Test func 사건은_자기_좌표로_올라간다() { /* 25m 안의 두 점을 먹이고 두 번째에서 eventWritten */ }

/// 같은 고침이 `LocationFilter` 가 보는 상태를 안 건드렸는지. **이 테스트가 빨개지면
/// 고침이 잘못된 것이다** — 되돌린다(판정 기록 11).
@Test func 필터_기준점은_안_움직인다() { /* skipTooClose 뒤 lastFix 가 그대로인지 */ }
```

**구현자에게: 이 고침이 `lastFix` 나 `LocationFilter` 의 인자를 건드려야 하는 모양으로 커지면 멈추고 되돌린 뒤 이월로 남긴다.** 정의상 25m 안의 차이이고, 그것과 필터 판정을 바꾸는 위험은 바꿀 값이 아니다.

**③ 1단계 M5 — `LeaveFamilyModelTests` 의 벽시계 셋**(판정 기록 13). `ios/KidCareTests/LeaveFamilyModelTests.swift:149·268·277`.

같은 파일이 **이미 쓰고 있는 `TestSignal`** 로 바꾼다 — 가짜 `remove` 가 `문.wait()` 로 멈춰 있게 하고 테스트가 `문.fire()` 로 푼다. 시간이 판정에서 빠진다. `:277` 이 가장 위험하다: `Task { await m.뺀다() }` 가 50ms 안에 끝나면 `eventually { m.빼는중 }` 이 영영 참을 못 보고 멈춘다.

```bash
# 고친 뒤 20회 돌려 흔들림이 사라진 것을 본다(1단계 리뷰는 10회에서 재현을 못 했다)
cd /Users/com/work/KidCare/ios
for i in $(seq 1 20); do
  xcodebuild test -project KidCare.xcodeproj -scheme KidCare \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:KidCareTests/LeaveFamilyModelTests 2>&1 | tail -1
done
grep -n "Task.sleep" ios/KidCareTests/LeaveFamilyModelTests.swift   # 세 자리가 사라져야 한다
```

- [ ] **Step 2: 상수를 세 단계 통째로 한 줄씩 대조한다**

설계서 §4 의 대조표 전부다. **표를 만들어 값과 인용 줄이 둘 다 맞는지 눈으로 본다. 하나라도 어긋나면 안드로이드가 맞다.**

```bash
cd /Users/com/work/KidCare
A=app/src/main/java/com/kidcare/family
# §4.1 LocationFilter
grep -n "MIN_ACCURACY\|MIN_DISTANCE\|MAX_SPEED\|STALE" $A/logic/LocationFilter.kt
grep -n "static let" ios/KidCare/Logic/LocationFilter.swift
# §4.2 AdaptiveMovementDetector
grep -n "const val\|private const" $A/logic/AdaptiveMovementDetector.kt
grep -n "static let" ios/KidCare/Logic/AdaptiveMovementDetector.swift
# §4.3 MovementTrailFilter / §4.4 SegmentBuilder / §4.5 TrailCodec
grep -n "const val" $A/logic/MovementTrailFilter.kt $A/logic/SegmentBuilder.kt $A/logic/TrailCodec.kt
grep -n "static let" ios/KidCare/Logic/MovementTrailFilter.swift ios/KidCare/Logic/SegmentBuilder.swift ios/KidCare/Logic/TrailCodec.swift
# §4.6 GeofenceEvaluator / §4.7 PlaceNameCache
grep -n "const val" $A/logic/GeofenceEvaluator.kt $A/logic/PlaceNameCache.kt
grep -n "static let" ios/KidCare/Logic/GeofenceEvaluator.swift ios/KidCare/Logic/PlaceNameCache.swift
# §4.8 LocationCollector — 아이폰에서 모양이 바뀐 유일한 자리. STILL_ESCALATE_MILLIS 는 대응이 없다
grep -n "const val" $A/child/LocationCollector.kt
grep -n "static let\|stillEscalate" ios/KidCare/Child/CollectionMode.swift ios/KidCare/Child/LocationCollector.swift
# §4.9 TrackingService — 업로드 주기·조건 검사 주기
grep -n "UPLOAD_MIN_INTERVAL_MILLIS\|UPLOAD_IDLE\|CONDITION_CHECK_INTERVAL_MILLIS" $A/child/TrackingService.kt
grep -n "uploadMinIntervalMillis\|idle\|periodMillis" ios/KidCare/Child/TrackingCoordinator.swift ios/KidCare/Child/TrackingTicker.swift
# §4.10 나머지 넷
grep -n "const val" $A/child/TrailUploader.kt $A/child/PlaceNamer.kt $A/child/PlaceWatcher.kt $A/child/ConditionWatcher.kt $A/core/EventRepository.kt
grep -n "static let" ios/KidCare/Child/TrailUploader.swift ios/KidCare/Child/PlaceNamer.swift ios/KidCare/Child/PlaceWatcher.swift ios/KidCare/Child/ConditionWatcher.swift ios/KidCare/Core/EventRepository.swift
```

**§4.11 확인**: 안드로이드에 대응이 **없어야 하는** 상수는 `STILL_ESCALATE_MILLIS`(5분) **하나뿐**이다(설계서 §15-3). 아이폰 쪽에 코틀린 짝이 없는 상수가 그것 말고 또 있으면, 그것은 이 작업이 **지어낸 값**이라는 뜻이다 — 찾아서 근거를 적거나 없앤다.

```bash
# 코틀린 짝이 없는 상수 찾기 — 값을 하나씩 코틀린 전체에서 되찾아 본다
grep -rn "static let .*Millis\|static let .*Meters\|static let .*Percent" ios/KidCare/Logic ios/KidCare/Child
```

- [ ] **Step 3: 골든 대조가 *정말로 무는지* 일부러 깨 본다**

설계서 §14 4단계가 시킨 것이 이것이다. 2단계가 이 확인에서 실제로 구멍을 찾았다(`GoldenComparisonTests.swift:36-42`). **일곱을 차례로 깨고, 각각이 빨개지는 것을 보고, 되돌린다.**

| # | 깨는 것 | 빨개져야 하는 테스트 |
|---|---|---|
| 1 | `LocationFilter` 의 `minDistanceMeters` 를 한 칸 바꾼다 | `GoldenComparisonTests.위치필터_상수가_같다`·`위치필터_판정_대조` |
| 2 | `MovementTrailFilter` 의 문턱 하나 | `경로필터_상수가_같다`·`경로필터_기록_대조` |
| 3 | `AdaptiveMovementDetector` 의 문턱 하나 | `판정기_상수가_같다`·`판정기_대조` |
| 4 | `SegmentBuilder` 의 머무름 반경 | `구간_상수가_같다`·`구간_대조` |
| 5 | `TrailCodec` 의 솎기 상한 | `코덱_상수가_같다`·`솎기_대조` |
| 6 | `GeofenceEvaluator` 의 5분 억제 값 | `지오펜스_판정_대조` |
| 7 | `PlaceNameCache` 의 30m 매칭 반경 | `장소이름_캐시_대조` |

그리고 **골든 파일 자체가 증발하는 사고**도 다시 본다(2단계가 찾은 구멍):

```bash
cd /Users/com/work/KidCare
cp ios/KidCareTests/golden/geofenceEvaluator.json /tmp/g.json
echo '[]' > ios/KidCareTests/golden/geofenceEvaluator.json
cd ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:KidCareTests/GoldenComparisonTests 2>&1 | tail -5
# 반드시 `골든_리소스가_번들에_있다` 가 빨개져야 한다
cp /tmp/g.json /Users/com/work/KidCare/ios/KidCareTests/golden/geofenceEvaluator.json
cd /Users/com/work/KidCare && git status --short   # 비어 있어야 한다
```

**일곱 중 하나라도 초록이면 그 대조가 무의미하다는 뜻이다 — 대조를 고치고 다시 한다.**

- [ ] **Step 4: 리스너와 OS 지역에 떼는 길이 있는지**

아이 역할이 세 단계에 걸쳐 만든 구독을 한 줄씩 짚는다. **떼는 길이 없는 리스너는 가족이 바뀌거나 아이가 바뀔 때 새는 읽기다**(하루 50 읽기 예산).

```bash
cd /Users/com/work/KidCare
# 구독을 만드는 곳
grep -rn "addSnapshotListener" ios/KidCare
# 떼는 곳 — 위 목록의 각 리스너가 여기 대응이 있어야 한다
grep -rn "\.remove()" ios/KidCare
# 아이 쪽 세션이 멈출 때 떼는 것들
grep -n "func stop()" -A 30 ios/KidCare/Child/ChildSession.swift
# OS 지역 — 3단계 M2 가 stopMonitoring 을 더했다
grep -n "startMonitoring(for:\|stopMonitoring(for:\|monitoredRegions" ios/KidCare/Child/LocationCollector.swift ios/KidCare/Child/PlaceWatcher.swift
# 이 단계가 리스너를 하나도 안 더한 것
git diff 0b141d6..HEAD -- ios/KidCare | grep -n "addSnapshotListener"   # 비어 있어야 한다
```

확인하는 넷:
1. `PlaceRepository.observePlaces`(아이 쪽) — `ChildSession.stop()` 에 떼는 줄이 있는가.
2. `PlaceWatcher.stopMonitoring()`(3단계 M2) — `stop()` 이 부르는가. OS 지역이 스무 개 남지 않는가.
3. 보호자 쪽 `MapViewModel.liveStatusListener`(`:1144`) — `실시간_추적을_정리한다()`(`:1272-1274`)가 `정리한다()`(`:961`)에서 불리는가.
4. `ScheduleViewModel.scheduleListener`·`settingsListener`(`:160·165`) — `정리한다()`(`:180-188`)가 떼는가.

**이 단계가 더한 `ChildPlatformStore` 는 리스너가 아니다**(`UserDefaults` 다). 뗄 것이 없는 것이 그 설계의 값이다.

- [ ] **Step 5: 하루 쓰기·읽기를 만든 코드로 다시 센다**

설계서 §11.2 가 설계 단계에서 센 값이다. **만든 코드의 상수로 다시 세어, 안드로이드 대비 배수가 안 나빠졌는지**만 확인한다(예산 20 을 넘는 것은 이미 주인이 감수하기로 한 상태다 — `known-issues.md` 14번).

```bash
cd /Users/com/work/KidCare
# 손잡이 셋의 실제 값
grep -n "uploadMinIntervalMillis\|uploadIdleIntervalMillis\|eventJustWritten" ios/KidCare/Child/TrackingCoordinator.swift
grep -n "LOW_PERCENT\|REARM_PERCENT" ios/KidCare/Child/ConditionWatcher.swift
grep -n "maxRegions\|20" ios/KidCare/Logic/GeofenceRegionSelection.swift
```

표를 이 모양으로 만들어 **계획서가 아니라 보고서에** 적는다. 설계서 §11.2 의 두 표와 나란히 두고 갈린 칸이 있으면 이유를 적는다.

| 항목 | 설계서 §11.2 | 만든 코드 | 근거(파일:줄) |
|---|---|---|---|
| 명령 왕복 | 0 | 0 | 아이폰 아이는 `commands/` 를 안 만들고 안 읽는다. **이 단계가 보호자 쪽도 0 으로 만들었다**(Task 2·3) |
| 주기 업로드(움직이는 15분 슬롯) | 20 | ? | `uploadMinIntervalMillis` |
| 유휴 업로드(4시간) | 6 | ? | |
| 사건 직후 강제 업로드 | 4 | ? | 1분 간격 규칙에 얼마나 흡수되는가 |
| 장소 이벤트 | 4 | ? | 장소 2곳 × 도착·이탈 |
| `low_battery`/`permission_off` | 0~1 | ? | 3단계 히스테리시스 |
| 부모의 읽음 표시 | 4~5 | ? | |
| `serverNow` | 1~5 | ? | |
| **합계** | **39~45** | **?** | 안드로이드 36~42 대비 배수가 안 커졌으면 합격 |

**최악의 날**(하루 종일 움직임)도 다시 센다: 15분 × 24시간 = 96 업로드 × 2 = **192 쓰기**. 1단계 리뷰가 "여기서 새로 생긴 위험이라, 실사용 데이터가 나오면 가장 먼저 볼 값"이라고 적었다. `uploadMinIntervalMillis` 가 **그 상한을 정하는 유일한 손잡이**라는 것을 보고서와 개발일지에 적는다. **값은 안 바꾼다** — §17 열린 질문 6 이 "실기기에서 하루를 재 본 뒤 조정"이라고 정했고 그 측정이 아직 없다.

**읽기**는 설계서 §11.2 대로 안드로이드보다 **준다**(아이폰 아이는 명령 리스너가 없다). 이 단계는 읽기를 **하나도 안 더했다**(판정 기록 3) — `git diff 0b141d6..HEAD` 에 새 `getDocument`·`addSnapshotListener` 가 없는 것으로 확인한다.

- [ ] **Step 6: 정직함 — 아이폰이 못 하는 것을 할 수 있다고 말하는 문구가 하나도 없는지**

```bash
cd /Users/com/work/KidCare
# "ios" 라는 글자는 두 군데뿐이어야 한다(판정 기록 1)
grep -rn '"ios"' ios/KidCare        # Documents.swift:252 와 ChildPlatform.swift 뿐
# 아이 쪽은 명령을 모른다
grep -rn "commands\|CommandType" ios/KidCare/Child     # 비어 있어야 한다(설계서 §1)
# 푸시·로컬 알림 없음
grep -rn "UNUserNotificationCenter\|FirebaseMessaging" ios/KidCare   # 비어 있어야 한다
# 한 세션짜리 정확도 승격을 안 쓴다
grep -rn "requestTemporaryFullAccuracy" ios/KidCare    # 비어 있어야 한다
# 아이 역할이 더한 문구 전부를 눈으로 읽는다
git diff 0b141d6~30..HEAD -- i18n/ko.json | grep '^+' | grep -v '^+++'
```

그리고 **사람 눈으로** 읽는다. 세 가지를 찾는다.

1. **아이 화면**이 "공유 중"이라고 말하는 모든 조합에서 실제로 점이 올라가는가(3단계 Step 6 과 같은 질문).
2. **보호자 화면**의 어느 문장도 아이폰 아이에 대해 "곧 도착해요 / 전달 중이에요 / 다시 시도할게요"라고 말하지 않는가. Task 2·3 뒤에는 그런 문장에 **닿는 길이 없어야** 한다.
3. **강제 종료**(설계서 §15-2, "가장 큰 차이다")가 아이 화면(`ios_child_force_quit_notice`)과 `ChildSession` 로그 **둘 다**에 적혀 있는가. 3단계 판정 기록 9 가 넣은 두 벌이 그대로 있는지 확인한다.

```bash
grep -n "ios_child_force_quit_notice" i18n/ko.json ios/KidCare/Child/ChildHomeView.swift
grep -n "강제 종료" ios/KidCare/Child/ChildSession.swift
```

- [ ] **Step 7: 시뮬레이터 + 에뮬레이터로 세 갈래를 다 밟는다**

**이 단계의 잠금은 실기기가 없어도 전부 확인된다** — 에뮬레이터의 아이 문서에 `platform` 을 넣고 빼는 것만으로 `.iOS`·`.android`·`.unknown` 셋을 만들 수 있다(판정 기록 14).

1. 에뮬레이터가 떠 있는지 본다(`curl -s http://127.0.0.1:8080`). **데이터를 지우지 않는다** — 3단계가 남긴 가족 `MZO1poA0yAyAmgOEx56X` 을 그대로 쓴다.
2. `KidCareApp.swift` 를 잠깐 `configureForEmulator(projectId: "kidcare-emulator")` 로 바꾼다. **Step 11 에서 반드시 되돌린다.**
3. 보호자 시뮬레이터(`iPhone 17`)에 앱을 **지우지 않고** 덮어 설치하고, 그 가족의 아이를 고른다.
4. 아래 셋을 차례로 만든다. 아이 상태 문서를 직접 고치는 것이 가장 빠르다.

```bash
EMU="http://127.0.0.1:8080/v1/projects/kidcare-emulator/databases/(default)/documents"
F=MZO1poA0yAyAmgOEx56X      # 3단계가 남긴 가족. 실제 값은 에뮬레이터에서 확인한다
C=<아이UID>
# 지금 모양을 먼저 본다
curl -s -H "Authorization: Bearer owner" "$EMU/families/$F/children/$C" | python3 -m json.tool
# ① 아이폰 — platform: "ios"
curl -s -X PATCH -H "Authorization: Bearer owner" -H "Content-Type: application/json" \
  "$EMU/families/$F/children/$C?updateMask.fieldPaths=platform" \
  -d '{"fields":{"platform":{"stringValue":"ios"}}}' > /dev/null
# ② 안드로이드 — platform 을 빈 값으로
curl -s -X PATCH -H "Authorization: Bearer owner" -H "Content-Type: application/json" \
  "$EMU/families/$F/children/$C?updateMask.fieldPaths=platform" \
  -d '{"fields":{"platform":{"stringValue":""}}}' > /dev/null
# ③ 모름 — 상태 문서를 통째로 지운다. **지우기 전에 위 GET 결과를 파일로 남겨 둔다**
```

**③ 을 할 때는 기억도 지운다** — 저장소가 앞선 갈래를 기억하고 있다. 앱을 지우지 않고 기억만 비우는 길이 없으므로, **아이 uid 가 다른 아이**를 하나 더 만들어 그 아이로 ③ 을 본다(그 편이 앱을 지우지 않는다는 규율을 지킨다).

5. 갈래마다 다섯 탭을 눈으로 본다.

| 갈래 | 관리 탭 | 지도 탭 | 예약 탭 | 장소·알림 탭 |
|---|---|---|---|---|
| ① 아이폰 | 맨 위에 `ios_child_no_remote_control`. **소리 상태 카드가 없다.** 모드 셋·잠금·폰찾기·칩·입력칸·보내기·알람 넷이 전부 흐리다. **인터넷 카드는 멀쩡하다** | 버튼 줄 위에 같은 문구. '지금 위치 확인'·'실시간 보기'가 흐리다. **경로·타임라인·상태 카드는 그대로 뜬다** | 맨 위에 `ios_child_schedule_not_applied`. 규칙 추가·수정·삭제·기본 모드·공휴일이 **전부 되고 저장된다.** '아이 폰에 알리기' 바가 **안 뜬다** | **아무것도 안 바뀐다** |
| ② 안드로이드 | **지금과 똑같다.** 문구 없음 | 똑같다 | 똑같다. 규칙을 바꾸면 '아이 폰에 알리기'가 평소대로 뜬다 | 똑같다 |
| ③ 모름 | **②와 똑같다. 문구가 안 뜬다** | 똑같다 | 똑같다 | 똑같다 |

6. **①에서 명령 문서가 진짜로 안 생기는지**를 서버에서 본다. 규칙을 하나 저장하고 소리 버튼을 (흐리지만) 눌러 보려 시도한 뒤:

```bash
curl -s -H "Authorization: Bearer owner" "$EMU/families/$F/children/$C/commands" | python3 -m json.tool | head -40
```
**①을 켠 시각 이후의 문서가 하나도 없어야 한다.** 규칙 문서(`schedules/`)는 **늘어나야** 한다 — 저장은 되고 알림만 안 가는 것이 이 단계의 계약이다.

```bash
curl -s -H "Authorization: Bearer owner" "$EMU/families/$F/children/$C/schedules" | python3 -m json.tool | head -30
```

7. 갈래·탭마다 `xcrun simctl io booted screenshot /tmp/guardian-p4-<번호>.png` 로 남긴다.
8. **아이 시뮬레이터는 이 Step 에서 안 쓴다.** 보호자 쪽만 보는 확인이다.
9. **앱을 지우지 않고** 시뮬레이터도 끄지 않는다. 고쳐 둔 `platform` 은 ②(빈 값)로 되돌려 둔다.

- [ ] **Step 8: 실기기 점검표를 *쓴다.* 돌리지 않는다.**

`ios/dev/device-verification.md` 를 만든다. **첫 줄이 멈춤 조건이다.**

> # 아이폰 아이 실기기 확인 — **주인이 하라고 말하기 전에는 아무것도 하지 않는다**
>
> 실제 아이폰을 아이로 페어링하면 **진짜 가족 문서에 쓰고 진짜 아이의 위치를 모으기 시작한다.**
> 되돌릴 수 없는 종류의 일이다(설계서 §13). 이 문서는 **적어 둔 것**이고, 아직 한 항목도 안 돌았다.
>
> ## 먼저 — 푸는 법
> 시작하는 법보다 멈추는 법이 먼저 있어야 한다.
> 보호자 앱에서 **그 아이의 멤버 문서를 지우면**(`firestore.rules:137` 이 허용한다) 아이 화면이
> `child_family_gone` 으로 바뀌고 수집이 멎는다. 아이 폰에서는 화면의 '다시 연결'이 역할 저장을
> 지운다(3단계 판정 기록 13).
>
> ## 준비
> - **시험용 가족을 따로 만든다.** 주인이 실제로 쓰는 가족에 시험용 아이를 붙이지 않는다(설계서 §13).
> - 아이로 쓸 아이폰은 **지워도 되는 폰**이어야 한다.
> - 확인 중에도 에뮬레이터를 끄지 않는다. 운영 Firebase 를 쓰는 것은 이 문서의 항목뿐이다.
> - 하루짜리 항목(배터리)은 **아침에 100% 에서 시작**해 재야 한다.
>
> ## 항목 — 설계서 §12.4 열 + 세 단계가 남긴 것
>
> | # | 무엇 | 왜 시뮬레이터로 못 보나 | 무엇을 보면 합격인가 | 출처 |
> |---|---|---|---|---|
> | 1 | **백그라운드 앱 새로고침을 끄면 배달이 멎나** | iOS 26 시뮬레이터에 그 설정이 **아예 없다** | 멎으면 지금 문구가 맞다. **안 멎으면 `ChildPermissions` 의 그 항목과 `ios_child_perm_refresh_*` 문구를 지운다** — 거짓 경고를 남겨두지 않는다 | §17-4, 3단계 M4 |
> | 2 | **강제 종료 뒤 되살아나지 않나** | 시뮬레이터가 OS 의 되살리기를 재현 못 한다 | 앱 전환기에서 위로 민 뒤 지역 경계를 넘어도 **아무 일도 안 일어나는 것.** 되살아나면 그건 덤이고, 아이 화면 문구를 그때 고친다 | §17-3, §15-2 |
> | 3 | **화면을 끄고 몇 시간 뒤에도 점이 들어오나** | 시뮬레이터는 잠들지 않는다 | `pausesLocationUpdatesAutomatically` 가 실제로 안 멈추는 것 | §12.4-2 |
> | 4 | **메모리 압박으로 죽은 뒤 지역·중요 위치가 되살리나** | 같음 | 되살아난 실행이 수집을 다시 시작하는 것(1단계 M6 이 그 자리다) | §12.4-3 |
> | 5 | **실제 배터리** | 시뮬레이터에 배터리가 없다. 3단계 확인은 전부 `-childBattery` 주입값이다 | `UIDevice.batteryLevel` 로 15%/20% 히스테리시스가 실제로 넘나드는 것. **그리고 하루 소모율** — 이 숫자가 설계서 §9.1("아직 아무도 안 쟀다")을 대체한다 | §9.1, 3단계 잔여 4 |
> | 6 | **지역 콜백의 지연과 스무 개 전부** | 시뮬레이터는 좌표를 순간이동시킨다 | 스무 개가 다 걸리고, 경계를 넘은 뒤 사건이 나기까지 몇 초/몇 분인가 | §7.2, 2·3단계 잔여 |
> | 7 | **'항상 허용'의 두 걸음과 나중에 뜨는 "계속 허용할까요?"** | 시뮬레이터의 대화상자가 실물과 다르다 | 두 번째 거부가 `.always` 빠짐으로 정확히 넘어가는 것 | §8.1, §12.4-1 |
> | 8 | **로그인 실패로 세션이 안 뜨는 길**(3단계 I3) | 시뮬레이터로 그 갈래를 못 밟았다(코드 읽기로만 확인) | `ios_child_cannot_start` 와 '다시 해보기'가 실제로 뜨고, 눌러서 복구되는 것 | 3단계 I3 잔여 |
> | 9 | **이름 짓기 예산이 백그라운드 실행 시간과 부딪치나**(2단계 M1) | 실 Nominatim 을 시뮬레이터에서 일부러 안 탔다 | 예산 3초가 업로드를 늦추기만 하는지, 아니면 **업로드를 실패시키는지.** 실패시키면 2단계 M1 을 다시 연다 | 2단계 M1, task-3 걱정 5 |
> | 10 | **`requestLocation()` 을 `startUpdatingLocation()` 중에 부르는 것** | 실패해도 조용하다(`didFailWithError` 가 삼킨다) | 두 API 가 같이 도는 동안 점이 계속 오는 것 | 2단계 task-1-2 걱정 1 |
> | 11 | **`network` 가 실제로 갈리나**(1단계 M3) | 시뮬레이터는 맥의 인터페이스를 써서 정상적으로도 `"none"` 이다 | 와이파이/셀룰러/없음이 실제로 갈리는 것 | 1단계 M3 잔여 |
> | 12 | **저전력 모드에서 스트림이 얼마나 드물어지나** | 시뮬레이터에 배터리 설정이 없다 | `ios_child_low_power_notice` 가 거짓말이 아닌 것 | §8.3, 3단계 잔여 2 |
> | 13 | **`didUpdateLocations` 가 묶음으로 오나** | 시뮬레이터는 하나씩 준다 | 온다면 묶음 안의 **모든** 점을 시간순으로 처리해야 경로의 모퉁이가 안 사라진다 | §12.4-9 |
> | 14 | **파란 위치 표시가 실제로 뜨나** | 시뮬레이터에 상태 막대가 다르다 | 아이가 감시 사실을 보는 **유일한 장치**다 | §12.4-10 |
> | 15 | **`CLMonitor`(iOS 17)가 `startMonitoring(for:)` 과 똑같이 되살리나** | 되살리기 자체를 못 본다 | 똑같으면 그때 옮긴다. 다르면 지금 API 를 계속 쓴다 | §17-2 |
>
> ## 하루 측정 뒤에 여는 문 둘
> - **업로드 주기 15분/4시간 조정**(§17-6). 부모가 "너무 뜸하다"고 느끼면 15분을 내리는 대신 사건 직후
>   강제 업로드 조건을 넓히는 쪽이 비용 대비 효과가 낫다.
> - **최악의 날 192 쓰기**. `uploadMinIntervalMillis` 가 그 상한을 정하는 유일한 손잡이다.

**이 Step 은 문서를 만드는 것으로 끝난다.** 실행은 주인이 "해라"라고 말한 뒤이고, 그때는 이 계획서가 아니라 이 문서를 연다.

- [ ] **Step 9: 개발일지를 README 에 쓴다**

`README.md` 의 `## 개발일지` 절(`:133`) 안, **마지막 항목 뒤**에 붙인다. 아래 글을 **그대로** 넣는다(숫자 `N`·`M` 두 자리만 실제 값으로 채운다).

> ### 아이폰도 아이 폰이 됩니다 — 그리고 못 하는 것을 못 한다고 말합니다 (2026-09-23)
>
> 지금까지 아이폰 앱은 **보호자 전용**이었습니다. 역할 선택 화면에서 '아이'를 누르면 "아이폰은 아직 아이로 쓸 수 없어요"가 떴습니다. 이제 아이폰이 아이 폰이 됩니다 — 위치를 모으고, 경로를 그리고, 등록한 장소에 도착하고 떠날 때 부모에게 알리고, 배터리가 떨어지거나 권한이 꺼지면 알립니다. **부모 화면은 한 줄도 안 바뀐 채로** 그것을 읽습니다. 같은 문서, 같은 사건 종류, 같은 문구 키를 쓰기 때문입니다.
>
> 계산 로직 여덟(위치 필터·이동 판정·경로 솎기·구간 만들기·경로 부호화·지오펜스 판정·장소 이름 캐시·지역 스무 개 고르기)은 **안드로이드가 정본**입니다. 코틀린이 뽑은 골든 파일로 두 구현이 같은 답을 내는지 대조하고, 대조가 **정말로 무는지** 일부러 상수를 망가뜨려 확인했습니다. 이 확인에서 실제로 구멍을 하나 찾았습니다 — 골든 파일을 통째로 `[]` 로 바꿔치기해도 테스트가 전부 통과하고 있었습니다(케이스 수를 세는 검사를 더해 막았습니다).
>
> #### 아이폰이 안드로이드를 못 따라가는 것들 — 이유까지
>
> - **부모가 "지금"을 누를 수 없습니다.** '지금 위치 확인'도 '실시간 보기'도 없습니다. 아이폰에는 부모가 보낸 신호로 앱을 깨우는 장치가 **푸시 알림밖에** 없는데, 이 앱은 무료 요금제를 지키려고 푸시를 안 씁니다. 그래서 아이 폰이 **자기 주기로** 올립니다 — 움직이면 15분마다, 가만있으면 4시간마다, 장소 사건 직후에 한 번. 부모가 물어본 적이 없으니 "응답하지 않아요"도 뜨지 않습니다.
> - **소리·예약·핸드폰 찾기·알람·메시지가 통째로 없습니다.** 다른 앱의 소리 모드를 바꾸거나 화면을 잠그거나 벨을 울리는 API 가 아이폰에 **없습니다.** 있는 척할 방법도 없습니다.
> - **시간 간격으로 위치를 요청할 수 없습니다.** 안드로이드는 "5초마다 주세요"라고 말할 수 있는데 아이폰은 거리로만 말합니다. 그래서 연속 스트림을 받아 소프트웨어로 솎아 같은 밀도를 만듭니다. 5초는 **근사치이지 요청값이 아닙니다.**
> - **활동 인식으로 죽은 앱을 깨울 수 없습니다.** 안드로이드는 "걷기 시작했다"는 신호로 서비스를 깨우는데, 아이폰의 CoreMotion 은 앱이 살아 있을 때만 물어볼 수 있습니다. 그래서 좌표 기반 판정기 하나에 더 기대고, **안드로이드에 대응이 없는 상수 하나**(5분 동안 안 움직이면 정말 멈춘 것으로 친다)를 새로 만들었습니다. 이 설계에서 코틀린에 짝이 없는 상수는 그것 하나뿐입니다.
> - **정확한 위치를 끄면 완전히 조용해집니다.** 아이폰에는 "대략적인 위치"라는 상태가 있는데, 그러면 오차가 수 킬로미터라 이 앱의 문턱(50m·100m)에 전부 걸려 **아무것도 안 올라갑니다.** 안드로이드에 정확히 대응하는 상태가 없습니다. 이 앱에서 가장 조용한 고장이라, 아이 화면이 그것만 따로 말합니다.
> - **아이에게 상시 알림을 띄울 수 없습니다.** 안드로이드는 알림 막대에 "위치를 공유하는 중"을 붙박이로 띄우는데, 아이폰은 그 대신 **파란 위치 표시**가 뜹니다. 같은 "몰래 안 한다"를 하지만, 아이가 그것을 눌러 앱을 열 수는 없습니다.
> - **위치 권한이 0개라는 자랑을 잃었습니다.** 지금까지 아이폰 보호자 앱은 위치·카메라·알림 권한을 **하나도** 안 물었습니다. 같은 바이너리가 아이 역할을 하게 되면서 백그라운드 위치를 요구하게 됩니다. 앱스토어 심사 가이드라인 2.5.4 를 정면으로 만나는 자리이고, 내세울 근거는 셋입니다 — 아이 안전이라는 목적, 늘 켜지는 파란 표시, 그리고 "지금 엄마 아빠가 볼 수 있어요"를 숨기지 않는 아이 화면. **'앱 하나' 결정의 대가이고 피할 방법이 없습니다.**
>
> #### 가장 큰 차이 — 앱을 완전히 닫으면 되살아나지 않습니다
>
> 안드로이드에서 아이가 앱을 강제 종료하면 `START_STICKY` 와 부팅 신호로 몇 초 안에 돌아옵니다(위 "아이가 앱을 강제 종료하면" 절). **아이폰은 돌아오지 않습니다.** 앱 전환기에서 위로 밀면 그 뒤로는 지역 경계를 넘어도, 중요 위치가 바뀌어도, 폰을 껐다 켜도 iOS 가 이 앱을 깨우지 않습니다. 아이가 **직접 앱을 다시 열 때까지** 기록이 통째로 없습니다.
>
> 되살리기가 도는 것은 **메모리가 부족해 OS 가 종료했을 때**와 재부팅 뒤뿐입니다. 그 둘은 아이가 한 일이 아니라서 OS 가 책임지고 깨워 줍니다.
>
> 막을 방법이 없습니다. 그래서 **아이 화면에 적었습니다** — 고장일 때만이 아니라 **정상일 때도 늘** 보이는 한 줄입니다. 고장일 때만 띄우면 정작 강제 종료한 아이는 그 화면을 볼 수 없습니다(앱이 없으니까요).
>
> > 앱을 완전히 닫으면(앱 전환기에서 위로 밀기) 위치가 멈춰요. 다시 열 때까지 엄마 아빠가 볼 수 없어요.
>
> 같은 사실을 개발 로그에도 남겨, 나중에 "왜 하루가 통째로 비었지"를 찾는 사람이 한 번에 보게 했습니다. **애플 문서와 현장 보고가 어긋나는 자리**라 "안 되살아난다"를 가정하고 설계했습니다. 실기기에서 반대로 나오면 그건 덤이고, 반대로 가정했다가 틀리면 아이가 모르는 채로 하루가 조용해집니다.
>
> #### 보호자 화면이 아이폰 아이에게 거짓말하지 않습니다
>
> 아이가 아이폰이면 **부모 화면에서 안 되는 것을 안 되는 것으로** 보여 줍니다. 아이 폰이 자기 상태 문서에 `platform: "ios"` 를 적고, 보호자 앱이 그 한 글자를 읽습니다.
>
> - **관리 탭**: 소리 모드 셋·잠금·핸드폰 찾기·메시지·알람이 전부 흐려지고, 그 위에 한 줄이 뜹니다 — "아이 폰이 아이폰이라 이 기능은 쓸 수 없어요. 위치와 장소 알림은 그대로 와요." **소리 상태 카드는 아예 없앴습니다.** 아이폰은 소리 모드를 읽는 API 가 없어 그 칸이 영원히 "확인되지 않음"이고, 옆의 '새로 확인'은 눌러도 영원히 안 바뀌는 버튼이기 때문입니다. **인터넷 상태는 그대로 둡니다** — 그건 아이폰도 실제로 올립니다.
> - **지도 탭**: '지금 위치 확인'과 '실시간 보기'가 흐려지고 버튼 옆에 같은 문구가 붙습니다. 경로·타임라인·상태 카드는 **그대로 뜹니다.**
> - **예약 탭이 가장 어려웠습니다.** 규칙은 **저장됩니다.** 다만 아이폰에서는 적용되지 않습니다. 그래서 규칙을 만들고 고치고 지우는 것을 **하나도 막지 않되**, 탭 맨 위에 늘 한 줄을 둡니다 — "규칙은 저장되지만 아이폰에서는 소리가 바뀌지 않아요." 막지 않는 이유는 그 아이가 나중에 안드로이드 폰으로 바꾸면 저장된 규칙이 **그대로 동작해야** 하기 때문입니다. 대신 '아이 폰에 알리기' 바는 **한 번도 안 뜹니다.** 그 알림은 아무도 안 듣는 자리로 가는 명령이라 영영 "아직 못 알렸어요"에 머물고, 부모는 그것을 일시적인 실패로 읽고 계속 다시 누르게 됩니다.
> - **장소 탭과 알림 탭은 안 잠급니다.** 장소 저장은 명령이 아니라 서버 쓰기이고, 아이폰 아이가 상시 구독으로 실제로 받습니다. 도착·이탈 알림도 실제로 옵니다.
>
> **모르는 아이는 안드로이드로 봅니다.** 이 필드가 생기기 전에 만들어진 가족의 아이 문서에는 `platform` 이 없습니다. 값이 없으면 **아무것도 안 잠그고 문구도 안 띄웁니다.** 틀리는 두 방향의 대가가 같지 않기 때문입니다 — 안드로이드 아이를 아이폰으로 잘못 보면 **멀쩡히 되던 기능이 이유 없이 사라지고**, 반대로 아이폰 아이를 아직 모를 때는 버튼이 잠깐 켜져 있을 뿐이고 그 순간에는 아직 위치도 안 올라온 상태라 기존 문구가 이미 참말입니다. 그 창은 아이 폰이 페어링 뒤 **첫 좌표에서 업로드를 한 번 강제**해 닫습니다.
>
> 잠금은 두 겹입니다. 화면이 버튼을 끄고, **명령을 실제로 보내는 함수들이 그 앞에서 되돌아갑니다.** 계약은 "버튼이 흐리다"가 아니라 **"명령 문서가 하나도 안 생긴다"**이고, 테스트가 그것을 봅니다. 흐린 버튼을 우회하는 길은 눈에 안 보이기 때문입니다.
>
> #### 안드로이드와 똑같이 조용한 곳 하나 — 도착 직후에 떠나면 이탈 알림이 안 옵니다
>
> 검토에서 찾았고 **일부러 안 고쳤습니다.** 같은 장소에서 5분 안에 일어난 두 번째 전환은 헛알림을 막으려고 억제하는데, 이 억제가 **방향을 안 가립니다.** 그래서 학교에 도착하고 3분 뒤에 나가면 "도착했어요"만 가고 **그 방문의 "떠났어요"는 영영 안 옵니다.** 부모 화면에는 아이가 아직 학교에 있는 것으로 남습니다. 시뮬레이터에서 실제로 재현했습니다.
>
> **안드로이드도 글자까지 똑같이 동작합니다.** 여기서 아이폰만 고치면 같은 좌표·같은 장소에서 **두 플랫폼의 알림 목록이 갈립니다** — 아이 둘을 서로 다른 폰으로 보는 부모에게는 그게 더 큰 결함입니다. 고치려면 두 쪽을 같이 고쳐야 해서 아래 "안드로이드에서 고칠 것"에 넣었습니다.
>
> #### 돈 — 하루에 몇 번 쓰나
>
> 목표는 1,000가족이 무료 요금제 안에 드는 것이고, 가족당 예산은 하루 20 쓰기 / 50 읽기입니다. **아이폰 아이 가족은 안드로이드와 거의 같습니다** — 명령 왕복 25가 통째로 사라진 자리에 주기 업로드 30이 들어왔습니다. 안드로이드가 이미 예산의 약 두 배인 채로 "당분간 혼자 쓴다"고 정해 둔 상태이고, **이 작업이 그 배수를 나쁘게 만들지 않는다**는 것이 확인할 전부였습니다.
>
> **읽기는 오히려 줍니다.** 아이폰 아이는 명령 리스너가 없습니다. 보호자 쪽 잠금도 읽기를 **하나도 더 사지 않았습니다** — 이미 아이 상태를 읽고 있던 세 탭이 폰 종류를 기억해 두고, 상태를 안 읽는 예약 탭이 그 기억을 봅니다.
>
> 주의할 값 하나: **하루 종일 움직이는 날은 192 쓰기**까지 갑니다(15분마다 × 24시간 × 문서 둘). 업로드 최소 간격이 그 상한을 정하는 **유일한 손잡이**입니다. 실기기에서 하루를 재 보기 전에는 이 값을 건드리지 않습니다.
>
> #### 실기기는 아직입니다 — 그리고 그건 의도입니다
>
> **실제 아이폰을 아이로 페어링하면 진짜 가족 문서에 쓰고 진짜 아이의 위치를 모으기 시작합니다.** 되돌릴 수 없는 종류의 일이라 **주인의 명시적 허락 없이는 하지 않기로** 했습니다. 개발 중의 모든 확인은 Firebase 에뮬레이터와 시뮬레이터로 했습니다.
>
> 실기기에서만 풀리는 것들을 점검표로 적어 `ios/dev/device-verification.md` 에 두었습니다 — 백그라운드 배달, 강제 종료 뒤 비부활, 실제 배터리 소모, 지역 콜백 지연, 백그라운드 앱 새로고침을 껐을 때, 로그인 실패 경로, 실제 네트워크에서의 이름 짓기 예산. 문서의 **첫 줄이 멈춤 조건**이고, 두 번째 절이 **페어링을 푸는 방법**입니다(시작하는 법보다 멈추는 법이 먼저 있어야 합니다).
>
> 그중 하나는 **틀렸으면 코드를 지우기로** 미리 정했습니다. 백그라운드 앱 새로고침을 끄면 배달이 멎는다고 **가정하고** 아이 화면에 안내를 띄우고 부모에게 알리고 있는데, 애플 문서가 얇고 시뮬레이터에는 그 설정이 **아예 없습니다.** 실기기에서 안 멎는 것이 확인되면 그 항목과 문구를 **지웁니다** — 거짓 경고를 남겨두지 않습니다.
>
> #### 안드로이드에서 고칠 것
>
> 이 작업이 드러냈지만 `app/` 을 안 고치기로 해서 남은 것들입니다.
>
> - **안드로이드 보호자 화면은 아이폰 아이에게 계속 명령 버튼을 보여줍니다.** 부모가 안드로이드 폰으로 아이폰 아이에게 소리 모드나 '지금 위치 확인'을 보내면 **영영 "전달 중"에 머뭅니다.** 고치는 자리는 `guardian/ControlFragment.kt`·`guardian/MapTimelineFragment.kt`·`guardian/ScheduleFragment.kt` 셋이고, 재료(`platform` 필드)는 이 작업이 이미 심어 뒀습니다. 코틀린 `ChildStatusDoc` 에 그 필드가 없어도 터지지는 않습니다 — Firestore 가 모르는 필드를 조용히 버립니다.
> - **도착 직후 이탈이 사라지는 것**(위 절). `logic/GeofenceEvaluator.kt` 의 5분 억제가 방향을 안 가립니다. 재현: 등록한 장소에 들어간 뒤 5분 안에 반경 밖으로 나가면 이탈 사건이 안 생깁니다. 두 플랫폼을 **같이** 고쳐야 합니다.
> - **주석이 보안 규칙과 다릅니다.** `child/ConditionWatcher.kt`·`core/EventRepository.kt`·`child/PlaceWatcher.kt` 의 주석이 사건의 `at` 허용 창을 "과거 24시간"이라고 적었는데 **규칙은 7일**입니다. 규칙이 맞습니다. 주석만 고치면 됩니다.
> - **보안 규칙이 보호자의 자작 알림을 막지 않습니다.** 사건 생성 규칙은 `childUid == request.auth.uid` 만 보고 역할을 안 봅니다. 아이가 남의 이름으로 쓰는 것도, 보호자가 아이 이름으로 쓰는 것도 막히지만, **같은 가족의 보호자는 자기 이름으로 알림을 지어낼 수 있습니다.** 규칙 파일은 두 플랫폼이 공유하므로 따로 다뤄야 합니다.
>
> #### 그래서 지금
>
> iOS 테스트 **N개**, 알려진 문제 **0개**. 아이 역할 코드가 네 단계에 걸쳐 들어갔고 **안드로이드 `app/` 은 한 줄도 안 바뀌었습니다.** 보호자 앱은 안드로이드 아이에게 **지금까지와 한 글자도 다르게 굴지 않습니다** — 새 잠금은 `platform` 이 `"ios"` 일 때만 걸립니다. 실기기 확인은 **주인의 허락을 기다립니다.**

그리고 `## 개발 현황` 표(`:1149`)에 행 하나를 더한다.

| iOS 아이 | 아이폰 아이 역할 — 위치·경로·장소 알림·배터리·아이 화면, 보호자 화면의 정직한 잠금 | ✅ 완료 (실기기 확인은 주인 허락 대기) |

- [ ] **Step 10: `docs/known-issues.md` 에 둘을 기록한다**

닫지 **않기로** 한 둘이다. 번호는 파일의 다음 번호를 쓴다.

1. **아이폰 아이의 이름 짓기 예산이 최대 두 배까지 늘 수 있다**(2단계 M1). 코틀린은 대기와 요청을 합쳐 잘랐고(`child/TrailUploader.kt:201-206`) iOS 는 사전 검사(`PlaceNamer.swift:130`)와 소켓 제한시간(`TrailUploader.swift:132`)으로 나눠 뒀다. 최악의 경우 3초 예산이 ~6초. **대가 전부가 "업로드 한 번이 늦는다"이고 기다리는 사람이 없다**(아이폰 아이는 명령을 안 듣는다). 실기기 점검표 9번에서 백그라운드 실행 예산과 부딪치는지 보고, 부딪치면 다시 연다.
2. **보안 규칙이 보호자의 자작 사건을 막지 않는다**(2단계 M5, `firestore.rules:306-310`). 규칙 파일은 두 플랫폼이 공유하고 **이 작업에서는 안 고치기로** 정해져 있다.

- [ ] **Step 11: 전체 테스트, 되돌리기, 커밋**

```bash
cd /Users/com/work/KidCare
git checkout ios/KidCare/KidCareApp.swift                  # Step 7 의 에뮬레이터 설정을 되돌린다
git diff ios/KidCare/KidCareApp.swift                       # 비어 있어야 한다(configureForApp)
git diff --stat 0b141d6..HEAD -- app firestore.rules gradlew  # 비어 있어야 한다
grep -rn "@unchecked Sendable\|nonisolated(unsafe)" ios/KidCare
grep -rn "import CoreLocation\|import Firebase\|import UIKit" ios/KidCare/Logic
python3 tools/ios-strings.py --check
cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: PASS. 개수는 선행 조건의 M(746)에 Task 1~4 의 순증(약 30)을 더한 값이다. **실제 값을 개발일지의 `N` 에 채운다.**

여기서 찾은 결함은 고친 뒤 테스트를 다시 돌리고 `iOS 아이 4단계 Fix round N: …` 으로 커밋한다.

```bash
cd /Users/com/work/KidCare
git add ios/KidCare/Logic/PlaceNameCache.swift ios/KidCare/Child/TrackingCoordinator.swift \
        ios/KidCareTests README.md docs/known-issues.md ios/dev/device-verification.md
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" \
    commit -m "iOS 아이 4단계 마무리: 전수 대조와 이월 닫기, 개발일지, 실기기 점검표"
```

---

## 4단계 완료 기준

- [ ] 아이폰 아이를 고른 보호자 화면에서 **`commands/` 문서가 하나도 안 생긴다** — 여덟 명령(`set_ringer`·`query_ringer`·`find_phone`·`stop_find`·`message`·`set_alarm`·`cancel_alarm`)과 `locate_now`·`start_live_tracking`·`sync_rules` 전부. 에뮬레이터에서 눈으로 확인했다.
- [ ] 관리 탭의 잠긴 컨트롤이 **전부 흐리고**, 소리 상태 카드는 **없고**, 그 위에 `ios_child_no_remote_control` 한 줄이 있다. 인터넷 카드는 멀쩡하다.
- [ ] 지도 탭의 두 버튼이 흐리고 **버튼 옆에** 같은 문구가 있다. 경로·타임라인·상태 카드는 그대로다.
- [ ] 예약 탭에서 규칙 추가·수정·삭제·기본 모드·공휴일이 **전부 되고 저장된다.** '아이 폰에 알리기' 바가 **한 번도 안 뜨고** `pendingSync` 깃발이 **한 번도 안 올라간다.** 맨 위에 `ios_child_schedule_not_applied` 가 늘 있다.
- [ ] 장소 탭·알림 탭이 **한 줄도 안 바뀌었다.**
- [ ] **안드로이드 아이와 모르는 아이에게는 지금과 한 글자도 안 다르다.** 문구도 안 뜬다. `git diff` 로는 확인이 안 되므로 **테스트 셋**(`안드로이드면_지금과_똑같다`·`모르면_지금과_똑같다`·`지도_탭도_안드로이드면_지금과_똑같다`·`안드로이드면_예약_탭도_지금과_똑같다`)이 그 계약이다.
- [ ] `"ios"` 라는 글자가 저장소에 **두 군데뿐**이다(`Documents.swift:252`, `ChildPlatform.swift`).
- [ ] Firestore **읽기가 하나도 안 늘었다.** 새 `addSnapshotListener`·`getDocument` 가 없다.
- [ ] 설계서 §4 의 상수가 코드와 한 줄씩 맞고, 코틀린에 짝이 없는 상수는 `STILL_ESCALATE_MILLIS` **하나뿐**이다.
- [ ] 골든 일곱을 일부러 깨면 **일곱이 다 빨개진다.** 골든 파일을 `[]` 로 바꿔치기해도 빨개진다.
- [ ] 모든 Firestore 리스너에 떼는 길이 있고, `ChildSession.stop()` 이 OS 지역 스무 개를 걷는다.
- [ ] 하루 쓰기 수가 설계서 §11.2 의 39~45 안이고, 안드로이드 대비 배수가 **안 커졌다.**
- [ ] 이월 넷이 닫혔다 — 2단계 **M2**(숫자 해석), 2단계 **M4**(사건 좌표), 1단계 **M5**(벽시계 셋). 그리고 이 단계가 만든 잠금으로 설계서 §10 이 닫혔다.
- [ ] 이월 셋이 **이유와 함께** 열린 채 기록됐다 — 2단계 **I2**(개발일지), 2단계 **M1**(known-issues + 점검표 9번), 2단계 **M5**(known-issues + 개발일지).
- [ ] 3단계 **M4**(백그라운드 새로고침 문구)가 점검표 **1번**이고, "안 멎으면 항목과 문구를 지운다"가 적혀 있다.
- [ ] `ios/dev/device-verification.md` 가 있고, **첫 줄이 멈춤 조건**이며 **두 번째 절이 푸는 방법**이다. **한 항목도 안 돌았다.**
- [ ] README 에 개발일지 한 절이 들어갔고, 그 안에 ①아이폰이 못 하는 것과 이유 ②강제 종료 차이 ③도착 직후 이탈(안드로이드와 같은 동작) ④안드로이드에서 고칠 것 넷이 전부 있다.
- [ ] `git diff --stat 0b141d6..HEAD -- app firestore.rules gradlew` 가 **비어 있다.**
- [ ] 앱 코드에 `@unchecked Sendable`·`nonisolated(unsafe)` 가 없고, `Logic/` 이 Foundation 만 import 한다.
- [ ] 커밋이 전부 한국어이고 작성자가 `Yongminlee2 <dydals5678@gmail.com>` 이며 `Co-Authored-By` 가 하나도 없다.

---

## 자기 검토 결과 (writing-plans self-review)

**설계서 대응.** §14 4단계가 적은 세 줄을 하나씩 짚는다.

- "`platform` 쓰기(1단계의 상태 문서에 이미 들어 있다)와 읽기, `Guardian/ChildPlatform` + 세 화면 잠금(§10.2)" → Task 1(판단과 기억)·Task 2(관리·지도)·Task 3(예약). **쓰기는 1단계가 이미 했다** — 선행 조건 grep 셋이 그것을 확인한다. 설계서가 표로 적은 잠금 목록과 이 계획서의 판정 기록 7 의 표를 나란히 두면 **한 줄이 늘었다**: 잠금 스위치(`control_lock_switch`). 설계서가 안 적었지만 같은 구역의 같은 종류라 뺄 이유가 없다. **그리고 두 줄이 '끄기'에서 '숨기기'로 바뀌었다**(소리 상태 카드, '아이 폰에 알리기' 바) — 각각의 이유를 판정 기록 7 에 적었다. **주인 확인이 필요한 자리다.**
- "전수 검토: 상수 대조표(§4)를 코드와 한 줄씩 대조, 골든 대조가 **정말로 무는지** 일부러 값을 망가뜨려 확인" → Task 4 Step 2·3. 설계서가 "2단계에서 이 확인이 가장 중요했다"고 적었고, 2단계가 실제로 찾은 구멍(골든 파일 증발)을 Step 3 이 다시 밟는다.
- "**주인의 허락을 받은 뒤** 실기기 검증 열 항목(§12.4)" → Task 4 Step 8. **허락이 없으므로 안 돈다.** §12.4 의 열에 세 단계가 남긴 다섯을 더해 열다섯으로 적었다.
- §10.1 "값이 없으면 안드로이드로 본다" → 판정 기록 2 와 `ChildPlatformTests` 여섯. **`.unknown` 에서 문구도 안 띄우는 것**은 설계서가 명시하지 않았지만 같은 논리의 나머지 절반이라 계획서가 못박았다.
- §10.2 문구 둘 → Task 1 Step 1 에 ko 를 **설계서 글자 그대로** 적었다. en 은 이 계획서가 썼다.
- §11.2 → Task 4 Step 5 의 표. §12.4 → 점검표. §13 → Global Constraints + 점검표 첫 두 줄. §15 → 개발일지. §16 → Global Constraints.
- §17 열린 질문 3·4 → 점검표 2·1번. 8 → "다루지 않는 것" + 개발일지. 10 → 문구 둘을 글자로 적되 "주인이 고칠 수 있다"를 남겼다. 2·5·6·11 → "다루지 않는 것".

**작업 지시의 일곱 항목 대응.** ①보호자 잠금 여덟 → Task 2·3, 컨트롤마다 끄기/숨기기를 판정 기록 7 의 표에 이유까지 적었다. 예약 탭은 판정 기록 5 가 "부모가 실제로 보는 것"을 문장으로 적었다. ②모르는 플랫폼 → 판정 기록 2 + `ChildPlatformTests` + 테스트 `모르면_지금과_똑같다`. ③이월 닫기/미루기 → 머리말의 목록 아홉 줄, 각각에 결정과 판정 기록 번호. ④전수 검토 다섯 축 → Task 4 Step 2(상수)·3(골든)·4(리스너·지역)·5(비용)·6(정직함). ⑤개발일지 → Step 9 에 **한국어 본문을 그대로** 썼고 넷(못 하는 것·강제 종료·도착 직후 이탈·안드로이드 몫)이 전부 있다. ⑥실기기 점검표 → Step 8, **주인 결정임을 문서 첫 줄과 Global Constraints 양쪽에 적었다.** ⑦나머지는 시뮬레이터로 → Step 7 이 세 갈래를 에뮬레이터 `platform` 필드만으로 만든다.

**설계서에서 벗어나거나 구체화하지 못한 것 넷.** 넷 다 본문에 그렇게 적었다.

- **설계서가 잠금 방식을 "버튼을 `.disabled(true)` 로 두고 그 자리에 이유를 한 줄"로 통일했는데, 두 자리를 숨기기로 바꿨다**(소리 상태 카드, '아이 폰에 알리기' 바). 기준은 "그 자리에 표시할 값이 영영 있는가"이고 판정 기록 7 에 적었다. **설계서의 글자에서 벗어난 유일한 자리이고 주인 확인이 필요하다.**
- **설계서가 `ChildPlatform` 만 적었는데 `ChildPlatformStore` 를 하나 더 만들었다.** 설계서가 예약 탭이 상태 문서를 안 읽는다는 사실을 다루지 않았기 때문이다. 대안(예약 탭에 읽기를 하나 더 달기)은 §11.2 가 지키려는 읽기 예산을 깎는다. 판정 기록 3 에 대가 분석까지 적었다.
- **하루 쓰기·읽기의 실제 값은 실행해야 나온다.** Step 5 의 표에 `?` 로 두고 "보고서에 적는다"고 했다. 설계서 §11.2 의 값을 **베껴 적지 않는다** — 그러면 검토가 아니라 복사다.
- **`.unknown` 의 실제 체감 길이**(페어링부터 첫 좌표까지)는 실기기에서만 나온다. 점검표 6번(지역 콜백 지연)과 같은 날 잰다.

**자리표시 검사.** "TBD/적절히/나중에"는 없다. 실행해야 알 수 있는 값 여섯만 비워 뒀다: 선행 조건의 M, Task 4 Step 11 의 최종 개수(개발일지의 `N`), Step 5 의 표 `?` 칸, Step 7 의 가족ID·아이UID, `KidCarePalette` 의 실제 색 이름(파일을 열어 `StatusCardView` 가 쓰는 것을 그대로 쓰라고 적었다), 가짜 `commandSend`·`scheduleSave` 의 정확한 시그니처(기존 테스트에서 **베끼라고** 적었다 — 추측해 쓰지 말라고 못 박았다). `TrackingCoordinatorTests` 의 두 새 테스트 본문도 "25m 안의 두 점"이라는 조건만 적고 기존 케이스의 좌표 만드는 법을 따르라고 했다.

**타입·이름 일관성.**
- 테스트와 구현 대조: `ChildPlatform.android/.iOS/.unknown`·`of(platform:)`·`of(status:)`·`명령을_받을_수_있나`·`못_한다고_말할까`, `ChildPlatformStore(defaults:)`·`platform(childUid:)`·`remember(childUid:platform:)`·`remember(childUid:status:)`, 세 뷰모델의 `플랫폼`·`명령을_보낼_수_있나`·`아이폰이라_못_한다고_말할까`(예약 탭만 `아이폰이라_규칙이_안_걸린다`), `MapViewModel.실시간_버튼_활성화` 가 전부 구현 Step 에 있다.
- 예약 탭만 프로퍼티 이름이 다른 것은 **일부러**다. 그 탭에서 막히는 것은 "명령"이 아니라 "규칙이 걸리는 것"이고, 같은 이름을 쓰면 다음 사람이 규칙 저장까지 막혀 있다고 읽는다.
- 초안에서 고친 것 넷.
  - `ChildPlatform` 을 `String` 원시값 enum 으로 두려다 뺐다. 원시값이 있으면 `ChildPlatform(rawValue: "ios")` 가 생겨 **글자를 다시 흩뿌리는 길**이 열린다(판정 기록 1 이 막으려는 바로 그것).
  - 저장소를 `@Observable` 클래스로 두려다 `struct` + `UserDefaults` 로 바꿨다. `RuleSyncStore` 와 같은 모양이어야 다음 사람이 읽는 데 시간이 안 든다. 관찰이 필요 없는 이유는 `GuardianRootView.swift:36` 의 `.id(store.childUid ?? "")` 가 아이가 바뀔 때 다섯 뷰모델을 통째로 다시 만들기 때문이다.
  - 예약 탭에 `statusFetch` 를 달아 읽기 하나를 사려다 뺐다(판정 기록 3). 못 맞혔을 때의 대가가 0 이라 살 이유가 없다.
  - `ControlViewModel.send` 의 막는 갈래를 조용한 `return` 으로 두려다 `.failed(ios_child_no_remote_control)` 로 바꿨다. 거기 닿는 길이 남아 있다면 그것은 화면의 버그이고, **그때 부모가 보는 문장은 참말이어야** 한다.
- **실행 전에 확인이 필요한 가정 여섯.** 전부 Pre-flight conflict table 에 행이 있고, 다르면 **멈추고 보고**하게 적었다: 세 뷰모델 `init` 의 기존 인자 순서, `ChildStatusDoc` 초기화가 딕셔너리를 받는 모양, `KidCarePalette` 의 색 이름, `ScheduleViewModel` 의 다섯 쓰기 갈래가 `아이에게_알린다` 를 부르는 줄, `RuleSyncStore(kind:defaults:)` 가 `defaults` 인자를 받는지, `TestSignal` 의 실제 API.

---

## Pre-flight conflict table

| 짝 | 함께 만지는 것 | 충돌 여부와 처리 |
|---|---|---|
| **1단계 ↔ 4단계 Task 1** | `Core/Documents.swift` 의 `ChildStatusDoc.platform`(:186·:202)과 `ChildStatusWrite`(:252) | **한 줄도 안 고친다.** 1단계가 "읽는 쪽(보호자 화면 잠금)은 4단계다"라고 그 주석(:185)에 예고해 뒀다. 이 단계는 **읽기만** 한다. `?? ""` 를 바꾸면 `ChildDocumentsTests:95-101` 이 빨개진다 — 그게 정상이다 |
| **1단계 ↔ 4단계 Task 4** | `Child/TrackingCoordinator.swift` 의 `lastFix`·`LocationFilter.decide`(:208·:221) | **`lastFix` 를 옮기지 않는다**(판정 기록 11). 2단계 M4 는 `eventWritten` 이 **어느 좌표를 쓰는가**의 문제이지 필터 상태의 문제가 아니다. 고침이 `lastFix` 나 `LocationFilter` 인자를 건드리는 모양으로 커지면 **멈추고 되돌린 뒤 이월로 남긴다** |
| **1단계 ↔ 4단계 Task 4** | `ios/KidCareTests/LeaveFamilyModelTests.swift` | 아이 역할과 무관한 파일이다. **앱 코드는 한 줄도 안 바뀐다** — 테스트 셋만 `TestSignal` 로 옮긴다. `TestSignal` 의 실제 API 를 같은 파일에서 확인하고 쓴다 |
| **2단계 ↔ 4단계 Task 4** | `Logic/PlaceNameCache.swift` 와 골든 `placeNameCache.json` | 관용을 넓히는 고침이라 **기존 골든 케이스가 전부 그대로 통과해야 한다**(`GoldenComparisonTests.장소이름_캐시_대조`). 하나라도 갈리면 넓힌 것이 틀린 것이다. 골든 파일을 **안 늘린다** — `app/` 예외를 안 쓰는 것이 판정 기록 10·12 다 |
| **2단계 ↔ 4단계 Task 4** | `Logic/GeofenceEvaluator.swift:106·121-122`(2단계 I2) | **안 고친다.** 정본과 글자까지 같다(판정 기록 8). 고치면 두 플랫폼의 알림 목록이 갈린다 |
| **3단계 ↔ 4단계 Task 1·2·3** | `Guardian/` 전체 | 3단계는 `Guardian/` 을 **한 줄도 안 만졌다**(3단계 Task 4 Step 5-7 이 `git diff --stat -- ios/KidCare/Guardian` 가 비어 있음을 확인했다). 겹치지 않는다 |
| **3단계 ↔ 4단계 Task 1** | `i18n/*.json` — 3단계가 아홉을 더하고 셋을 지웠다 | 이 단계는 **둘을 더하기만** 한다. 3단계 판정 기록 14 가 "`ios_child_no_remote_control`·`ios_child_schedule_not_applied` 둘은 4단계 몫"이라고 예고했다 — **계약 이행이다.** `--write-gaps` 로 빈 칸 기록을 새로 쓰고 증가분이 둘 × 12 인지 본다 |
| **3단계 ↔ 4단계 Task 4** | `Child/ChildSession.swift` 의 `stop()` 과 `PlaceWatcher.stopMonitoring()` | **안 고친다.** 3단계 M2 가 이미 넣었다. Task 4 Step 4 는 **있는지 확인만** 한다 |
| **4단계 Task 1 ↔ Task 2·3** | `ChildPlatform`·`ChildPlatformStore` | 순서 의존. Task 1 이 먼저 커밋돼야 Task 2·3 이 컴파일된다 |
| **4단계 Task 2 ↔ Task 3** | `Guardian/GuardianRootView.swift:38-56` | **같은 함수를 두 커밋이 만진다.** Task 2 에서 다섯 뷰모델 전부에 `platforms:` 를 넘기고(예약 탭은 받아만 둔다), Task 3 은 그 인자를 **쓰기만** 한다. 순서를 바꾸면 Task 3 이 `GuardianRootView` 를 또 고쳐야 한다 |
| **4단계 Task 2 ↔ Task 3** | `ios/KidCareTests/GuardianPlatformGateTests.swift` | 같은 파일을 두 커밋이 만진다. Task 2 가 만들고 Task 3 이 예약 탭 절을 **뒤에 덧붙인다.** 가짜 `보낸_것`·`저장소(_:)` 도우미를 Task 3 이 다시 만들지 않는다 |
| **4단계 Task 2 ↔ 기존 보호자 테스트** | `ControlViewModelTests`·`MapViewModelTests`·`ScheduleViewModelTests` | 기존 케이스는 `platforms` 를 안 넘겨 `.unknown` 이고 **한 줄도 안 고쳐도 전부 초록이어야 한다.** 빨개지면 고칠 곳은 테스트가 아니라 구현이다(`.unknown` 이 안 잠근다는 약속이 깨진 것) |
| **4단계 ↔ 보호자 앱의 안드로이드 아이(안 고침)** | `ControlViewModel.버튼_활성화`·`MapViewModel.위치확인_버튼_활성화` 등 기존 조건 | **기존 항(`childUid != nil`, `!commandProgress.isInFlight`, …)을 하나도 안 지운다.** `&& 명령을_보낼_수_있나` 를 **더할** 뿐이다. 지우면 안드로이드 아이의 동작이 바뀐다 |
| **4단계 ↔ 안드로이드 보호자(안 고침)** | `guardian/ControlFragment.kt`·`MapTimelineFragment.kt`·`ScheduleFragment.kt` | **안 고친다**(`app/` 금지, §17-8). 안드로이드 폰의 부모는 아이폰 아이에게 여전히 버튼을 본다. 개발일지 "안드로이드에서 고칠 것"에 자리와 재료를 적어 넘긴다 |
| **4단계 ↔ `firestore.rules`(안 고침)** | 2단계 M5 | **영원히 안 고친다**(주인 판정). `known-issues.md` + 개발일지 |
| **4단계 Step 7 ↔ 에뮬레이터 데이터** | 3단계가 남긴 가족 `MZO1poA0yAyAmgOEx56X` 과 사건 일곱·장소 하나·상태 문서 하나 | **지우지 않는다.** `platform` 필드만 `PATCH` 로 갈아 끼우고, 끝나면 빈 값으로 되돌린다. `.unknown` 갈래는 **아이를 하나 더 만들어** 본다 — 앱을 지우지 않고 기억만 비우는 길이 없기 때문이다 |
| **4단계 Step 7 ↔ `KidCareApp.swift`** | `configureForApp()` 대 `configureForEmulator` | 시뮬레이터 확인 중에만 바꾸고 **Step 11 에서 반드시 되돌린다.** 커밋 시점의 계약은 `configureForApp()` 이다(1단계가 `init()` 첫 줄로 못박았다) |
| **작업 트리 상태 ↔ 4단계 시작** | 선행 조건의 `git status --short` 가 비어 있어야 한다 | 3단계가 `0b141d6` 로 끝났고 이 계획서 파일 자체도 같은 폴더에 들어간다 |
