# iOS 아이 역할 2단계 구현 계획 — 장소 알림과 머무른 곳 이름

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 아이폰 아이가 부모가 정한 장소의 경계를 넘을 때 **안드로이드와 글자까지 같은 `events/` 문서**(`place_enter`·`place_exit`, `placeName` 포함)를 쓰게 한다. 판정은 안드로이드 `logic/GeofenceEvaluator.kt` 를 옮긴 순수 로직이 하고, OS 지역 감시는 "판정해 보라는 신호"로만 쓴다. 그리고 하루 문서의 머무름 구간에 이름을 붙인다(`child/PlaceNamer.kt` + `logic/PlaceNameCache.kt`). 보호자 알림 탭은 한 줄도 안 바뀐 채로 그 사건을 읽는다.

**Architecture:** 판정은 `Logic/` 의 순수 함수 셋(`GeofenceEvaluator`, `PlaceNameCache`, `GeofenceRegionSelection`)에 모으고 코틀린 골든 파일로 대조한다. CoreLocation 과 Firestore 를 아는 자리는 `Child/PlaceWatcher`(장소 목록 소유·지역 등록·점마다 판정·이벤트 쓰기)와 `Child/PlaceStateStore`(UserDefaults, 프로세스 밖 상태) 둘이다. 지역 경계 콜백은 **이벤트를 쓰지 않는다** — 1단계의 `LocationCollector` 에게 좌표 한 번(`requestLocation()`)을 부탁하고, 그 점이 `TrackingCoordinator` 의 보통 길을 지나 `PlaceWatcher.onFix` 로 간다(`PlaceGeofenceReceiver.kt:13-19` 의 규율 그대로). 이름 붙이기는 `actor PlaceNamer` 가 캐시와 "다음에 요청해도 되는 시각"을 들고, **오직 `TrailUploader.buildSegments` 안에서만** 불린다 — 위치 수집 경로는 지오코딩을 기다리지 않는다.

**Tech Stack:** Swift 6 strict concurrency / iOS 17 / SwiftUI / CoreLocation(`CLLocationManager.startMonitoring(for: CLCircularRegion)`) / Firebase Firestore / Swift Testing / XcodeGen. 새 의존성 없음. 코틀린 쪽은 `app/src/test/java/com/kidcare/family/logic/GoldenFileWriterTest.kt` **한 파일만** 만진다.

**Spec:** `docs/superpowers/specs/2026-09-22-kidcare-ios-child-design.md`. 이 단계가 기대는 곳:
- §14 2단계 — 범위 그대로("`Logic/`: GeofenceEvaluator·PlaceNameCache·GeofenceRegionSelection, 골든 둘 + 대조 테스트 / `Child/`: PlaceWatcher·PlaceStateStore·PlaceNamer / `Core/`: EventRepository.add, PlaceRepository.observePlaces 를 아이 uid 로 / 에뮬레이터 테스트: 이벤트 쓰기 계약 셋과 거부 경로")
- §4.6 `GeofenceEvaluator` 상수 셋, §4.7 `PlaceNameCache` 상수 둘, §4.10 `GEOCODE_BUDGET_MILLIS`·`TIMEOUT_MILLIS`·`MIN_INTERVAL_MILLIS`·`ENDPOINT`·`USER_AGENT`·`MAX_GEOFENCES`
- §7 지오펜스 전부(7.1 신호·7.2 20개 상한·7.3 어느 API·7.4 앱이 죽어 있는 동안)
- §11.1 규칙 계약 셋, §12.2 골든 둘, §12.3 에뮬레이터 테스트, §12.4 "시뮬레이터로 되는 것"
- §17 열린 질문 2(주인 판정: 예전 API 로 시작한다)

---

## 선행 조건

1단계(`docs/superpowers/plans/2026-09-22-kidcare-ios-child-phase1.md`)가 **전부 커밋된 뒤** 시작한다. 이 계획서는 1단계 계획서에 적힌 이름(`LocationCollector`, `TrackingCoordinator`, `TrailBuffer`, `TrailStore`, `TrailUploader`, `ChildStatusReporter`)을 쓴다. 시작 전에 이름이 실제로 그대로인지 확인한다.

```bash
cd /Users/com/work/KidCare
git status --short                                                        # 비어 있어야 한다
git log --oneline | grep -E "아이 1단계 Task"                              # 네 줄 이상
ls docs/superpowers/plans/2026-09-22-kidcare-ios-child-phase1.md           # 있어야 한다

# 1단계가 만든 이름 — 하나라도 다르면 Pre-flight conflict table 의 해당 행을 먼저 처리한다
grep -n "enum LocationFilter\|fallbackMaxAccuracyMeters\|static func distanceMeters" ios/KidCare/Logic/LocationFilter.swift   # 세 줄
grep -n "speedAccuracy" ios/KidCare/Logic/Fix.swift                        # 한 줄 이상(마지막 기본값 매개변수)
grep -n "nameLat\|nameLng" ios/KidCare/Logic/Segment.swift                 # 두 줄 이상 + 명시적 init
grep -n "final class LocationCollector\|final class TrackingCoordinator" ios/KidCare/Child/*.swift   # 두 줄
grep -n "func handle(\|isInsideKnownPlace\|func upload(" ios/KidCare/Child/TrackingCoordinator.swift ios/KidCare/Child/TrailUploader.swift | head
grep -n "buildSegments\|SegmentDoc(" ios/KidCare/Child/TrailUploader.swift  # 한 줄 이상
grep -n "static func save(" ios/KidCare/Core/TrailRepository.swift          # 한 줄

# 2단계가 이어 쓰는 기존 자리
grep -n "static func observePlaces" ios/KidCare/Core/PlaceRepository.swift  # 한 줄
grep -n "static func markRead\|private static func events" ios/KidCare/Core/EventRepository.swift   # 두 줄
grep -n "struct PlaceDoc\|struct EventDoc\|enum EventType" ios/KidCare/Core/Documents.swift         # 세 줄
grep -n "골든_리소스가_번들에_있다" ios/KidCareTests/GoldenComparisonTests.swift                      # 한 줄
ls ios/KidCareTests/golden/                                                 # 1단계가 더한 다섯이 함께 보인다

# 기준 테스트 개수(M)를 여기서 적어 둔다
cd ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5
```

## Global Constraints

설계서 §16 과 6단계 계획서의 목록을 이 단계의 말로 옮긴 것이다.

- **Swift 6 strict concurrency, iOS 17.0, SwiftUI, XcodeGen**(`ios/project.yml`; xcodeproj 를 손으로 고치지 않는다), **Swift Testing**.
- `ios/KidCare/Logic/` 은 **Foundation 만** import 한다. CoreLocation 도 Firebase 도 안 된다. 이 폴더가 골든 대조 대상이다.
- 앱 코드에 **`@unchecked Sendable` 과 `nonisolated(unsafe)` 를 쓰지 않는다.**
- **푸시 알림과 FCM 을 쓰지 않는다**(Spark 무료 요금제). 새 Firestore 리스너에는 떼는 길이 있다.
- `app/src/main`, `firestore.rules`, `gradlew` 를 **한 줄도** 고치지 않는다. 유일한 예외는 `app/src/test/java/com/kidcare/family/logic/GoldenFileWriterTest.kt` 다(설계서 §12.2·§17 열린 질문 1, 주인 판정 4).
- **정본은 안드로이드다.** 이 계획서가 코틀린과 다르면 코틀린이 맞다. 상수는 인용한 `파일:줄` 에서 그대로 옮긴다.
- 새 문구는 `i18n/ko.json`·`i18n/en.json` **둘에만** 넣고 `python3 tools/ios-strings.py` 로 생성한다. **번역을 지어내지 않는다.** (이 단계는 새 키가 없다 — 판정 기록 10.)
- 테스트는 **운영 Firestore 에 절대 쓰지 않는다.** 에뮬레이터 테스트는 `configureForEmulator(projectId: "kidcare-emulator")`(Auth 127.0.0.1:9099, Firestore 8080)를 쓰고, 커밋 시점의 `KidCareApp.init()` 은 반드시 `configureForApp()` 을 부른다. **실기기를 아이로 페어링하지 않는다**(설계서 §13, 4단계 몫).
- **시뮬레이터를 끄거나 지우지 않는다.** 테스트 전에 앱을 **지우지 않는다**(위에 덮어 설치한다). 에뮬레이터는 이미 떠 있는 것을 그대로 쓰고 그 데이터도 지우지 않는다.
- 커밋은 한국어, 작성자 `Yongminlee2 <dydals5678@gmail.com>`. **AI 흔적을 남기지 않는다**(Co-Authored-By 금지).
- 테스트 명령: `cd ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'`.
- 주석은 한국어로 **"왜"** 를 적는다. 실행 전 PATH 는 `export PATH="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:$PATH"` 다. 파일을 새로 만들었으면 테스트 전에 `cd ios && xcodegen generate` 를 돌린다.
- Swift 의 `CancellationError` 를 일반 `catch` 로 삼키지 않는다(설계서 §16 마지막 줄).

## 공통 절차 A — 문구 키를 카탈로그에 넣는 법

6단계 계획서 공통 절차 A 그대로다. 카탈로그(`ios/KidCare/Localizable.xcstrings`)를 **손으로 고치지 않는다.**

1. 새 문구가 필요하면 `i18n/ko.json` 과 `i18n/en.json` **둘 다**에 키를 넣는다(코드 포인트 순 정렬, 파일 끝 줄바꿈 하나). 나머지 12개 언어 파일에는 넣지 않는다.
2. 키를 일부러 더하거나 뺐으면 `python3 tools/ios-strings.py --write-gaps` 로 빈 칸 기록(`tools/i18n-untranslated.json`)까지 새로 쓴다. diff 의 빈 칸 변화가 의도한 것인지 눈으로 본다.
3. 평소에는 `python3 tools/ios-strings.py` 를 돌린다. 빈 칸이 기록과 다르면 쓰지 않고 멈춘다.
4. 검사: `python3 tools/ios-strings.py --check`(종료 코드 0), `I18nKeyParityTests`·`LocalizableCatalogTests`·`LocalizationBundleTests`.

**이 단계는 1~3 을 쓸 일이 없다**(판정 기록 10). 그래도 커밋 전 `--check` 는 돌린다.

## 공통 절차 B — 커밋

```bash
cd /Users/com/work/KidCare
git diff --stat 4bda965..HEAD -- app/src/main firestore.rules gradlew   # 비어 있어야 한다
git diff --stat 4bda965..HEAD -- app                                     # GoldenFileWriterTest.kt 한 줄만
git diff ios/KidCare/KidCareApp.swift                                    # 비어 있어야 한다(configureForApp)
grep -rn "@unchecked Sendable\|nonisolated(unsafe)" ios/KidCare          # 비어 있어야 한다
grep -rn "import CoreLocation\|import Firebase" ios/KidCare/Logic        # 비어 있어야 한다
python3 tools/ios-strings.py --check                                     # 종료 코드 0
git add <이 Task 의 파일들>
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" commit -m "<한국어 메시지>"
```

## 이 단계에서 다루지 않는 것

- **아이 화면·권한 화면·`ConditionWatcher`·`permission_off` 이벤트.** 설계서 §14 가 3단계로 뺐다. 지역 등록이 권한 없이 실패하는 경로는 여기서 **로그만** 남긴다(안드로이드 `PlaceWatcher.kt:206-210` 과 같은 자리).
- **보호자 화면 잠금(`platform`)** — 4단계다(설계서 §14).
- **`CLMonitor`** — 주인 판정 1·설계서 §17 열린 질문 2. 4단계 실기기 검증 뒤에 다시 본다.
- **중요 위치 변경(`startMonitoringSignificantLocationChanges`)** — 1단계가 되살리기 두 길 중 하나로 이미 걸었다. 2단계는 지역 감시 쪽만 더한다.
- **실기기 확인** — 설계서 §13 이 금지한다. 4단계에서 주인의 허락을 받고 한다.
- **`sync_rules`·명령 구독** — 아이폰 아이는 `commands/` 를 아예 안 듣는다(설계서 §1). 장소 변경은 상시 구독이 받는다(§7.3).
- **알림 띄우기** — 아이 폰은 알림을 하나도 안 띄운다(§8.6).

---

## 판정 기록 — 이 계획서가 내린 결정

1. **범위는 설계서 §14 2단계 그대로다.** `PlaceNamer`(머무른 곳 이름)가 여기 있는 이유는 §14 가 "**끝나면**: … 머무름에 이름이 붙는다"로 못 박았기 때문이다. 1단계의 `TrailUploader.buildSegments` 는 이름 칸을 빈 문자열로 두고 올라갔고, 2단계 Task 3 이 그 칸을 채운다.

2. **지역 감시는 `CLLocationManager.startMonitoring(for: CLCircularRegion)` 으로 시작한다**(주인 판정 1, 설계서 §7.3·§17 열린 질문 2). deprecated 경고를 받는다. 그 경고를 `@available` 로 덮지 않고 **주석으로 이유를 적는다** — 이 설계 전체가 "앱이 죽어 있어도 되살린다"는 계약 위에 있고 그쪽이 오래 검증됐기 때문이다. 4단계 실기기에서 `CLMonitor` 가 똑같이 되살리는 것을 확인하면 그때 옮긴다.

3. **20개를 고르는 규칙은 순수 함수이고, 코틀린의 정렬을 글자 그대로 재현한다.** 안드로이드는 `places.filter { it.radiusMeters > 0.0 }.sortedBy { it.name }.take(MAX_GEOFENCES)`(`PlaceWatcher.kt:168-171`)다. 그대로 Swift 로 옮기면 **두 군데가 갈린다.**
   - `sortedBy` 는 **안정 정렬**이고 Swift 의 `sorted(by:)` 는 안정성을 보장하지 않는다. 같은 이름 둘이 있으면 어느 쪽이 잘리는지가 실행마다 달라진다 — 이 규칙이 막으려던 "어떤 장소는 하루는 걸리고 하루는 안 걸린다"가 그대로 돌아온다. → 원래 순서를 같이 들고 가는 비교로 안정화한다.
   - 코틀린 `String.compareTo` 는 **UTF-16 코드 단위**를 하나씩 비교한다. Swift 의 `<` 는 정규화(canonical equivalence)를 거친 비교라 한글 조합형·완성형이 섞이면 순서가 다르다. → `utf16` 시퀀스를 사전순으로 직접 비교한다.
   둘 다 `GeofenceRegionSelectionTests` 가 고정한다. 코틀린 쪽은 인라인이라 골든 대상이 아니다(설계서 §7.2 끝).

4. **`PlaceNameCache.put` 의 이름 다듬기에서 코틀린 `trim()` 과 Swift 기본값이 갈린다.** 코틀린 `String.trim()` 은 `Character.isWhitespace` 인데 이것은 **U+00A0(비분리 공백)·U+2007·U+202F·U+0085 를 자르지 않는다.** Swift 의 `.trimmingCharacters(in: .whitespacesAndNewlines)` 는 그 넷을 전부 자른다. 한 글자 차이가 캐시 열쇠가 아니라 **부모 화면에 뜨는 이름**을 바꾸고, 골든 대조에서 조용히 빨개진다. → Swift 쪽은 자바와 같은 집합을 이름 붙여 못 박고(`PlaceNameCache.자바_공백`), 골든 생성기가 U+00A0 이 든 이름을 케이스로 넣어 이 차이를 실제로 고정한다.

5. **지역 경계 콜백은 좌표를 안 준다 — 그래서 아무것도 판정하지 않고 한 점을 부탁한다.** iOS 는 `didEnterRegion`/`didExitRegion` 에 `CLRegion` 만 준다. 설계서 §7.1 대로 `manager.requestLocation()` 한 번으로 지금 좌표를 얻고, **그 점은 보통 점과 똑같은 길**(`TrackingCoordinator.handle`)로 흘려보낸다. 못 얻으면 아무 판단도 하지 않는다.
   여기에 하나가 딸린다. 1단계가 만든 `CollectionMode` 소프트웨어 간격 게이트(정지 60초)는 **아이폰에만 있는 장치**다(설계서 §5.1 — 안드로이드는 간격이 요청 매개변수라 이런 필터가 없다). 그 게이트가 지역 전환으로 얻은 단 하나의 점을 삼키면, OS 가 앱을 깨워 준 그 사건이 통째로 사라진다. → 지역 전환으로 부탁한 점에는 게이트를 **한 번** 건너뛰게 한다(`TrackingCoordinator.bypassIntervalGateOnce`). 안드로이드에 대응이 없는 장치를 안드로이드에 없던 방식으로 막는 것이라 골든 대상이 아니고, `TrackingCoordinatorTests` 로만 고정한다.

6. **상태 저장은 `UserDefaults` 이고 값 형식은 글자 그대로 같다.** 설계서 §7.4 가 정했다(안드로이드 SharedPreferences 자리). 줄바꿈으로 레코드, 탭으로 칸, 칸 수·숫자 변환을 확인하고 이상한 줄은 통째로 버린다(`PlaceStateStore.kt:57-64`). 코틀린이 `apply()` 가 아니라 `commit()`(동기)을 쓴 이유(`:34-38`)는 iOS 에서 저절로 지켜진다 — `UserDefaults.set` 은 그 자리에서 메모리에 반영되고 디스크 플러시는 프로세스가 죽어도 이어진다. 그래도 `synchronize()` 를 **부르지 않는다**(애플이 deprecated 로 표시했고, 막으려는 사고가 여기엔 없다).

7. **`PlaceNamer` 는 `actor` 이고, 속도 제한은 "슬롯을 먼저 확보"해서 지킨다.** 코틀린은 `Mutex` 로 "시각을 읽고 비교하고 갱신"을 통째로 묶었다(`PlaceNamer.kt:77-90`). Swift 의 actor 는 **`await` 지점에서 재진입**하므로, "기다린다 → 그다음 마지막 시각을 갱신한다"로 옮기면 두 호출이 같은 값을 보고 둘 다 짧게 자다가 거의 동시에 쏜다 — 코틀린이 정확히 그 경쟁을 막으려고 Mutex 를 걸었다. → **자기 전에** `다음_허용_시각` 을 1초 뒤로 밀어 슬롯을 확보하고, 그다음에 잔다. Nominatim 사용 정책의 "초당 1건"이 동시 호출에서도 지켜진다.

8. **지오코더는 Nominatim 이다. `CLGeocoder` 를 쓰지 않는다.** 작업 지시는 `CLGeocoder` 의 엄격한 속도 제한을 걱정했는데, **설계서 §4.10 이 정본이고 그 표는 `ENDPOINT`(`PlaceNamer.kt:146`)·`USER_AGENT`(`:150`)·`TIMEOUT_MILLIS`(`:152`)·`MIN_INTERVAL_MILLIS`(`:153`)를 "같은 값"으로 못 박았다.** 이유는 두 플랫폼이 같은 좌표에 같은 이름을 붙여야 하기 때문이다 — `CLGeocoder` 는 애플 지도 데이터라 같은 집에 다른 이름을 준다. 작업 지시가 요구한 세 가지(속도 제한 안에 머문다 / `PlaceNameCache` 의미를 그대로 쓴다 / 위치 수집을 절대 막지 않는다)는 Nominatim 에도 그대로 걸리고, 판정 7(초당 1건)·Task 1(캐시)·판정 9(수집 경로 분리)가 각각 지킨다. **이 갈림은 주인에게 보고한다.**
9. **지오코딩은 위치 수집 경로에서 절대 불리지 않는다.** 부르는 곳은 `TrailUploader.buildSegments` **하나**뿐이고(`TrailUploader.kt:158-224`), 거기서도 ① 아는 이름을 네트워크 없이 먼저 다 채우고 ② 모르는 곳만 **최근 머무름부터** `GEOCODE_BUDGET_MILLIS`(3초, `:235`) 안에서만 묻고 ③ 예산을 넘긴 곳은 이번엔 이름 없이 올린다. `TrackingCoordinator.handle` 은 업로드를 기다리지 않는다(1단계 계약). `PlaceWatcher.onFix` 는 `PlaceNamer` 를 아예 모른다 — 이벤트의 `placeName` 은 **부모가 지은 장소 이름**(`GeofenceHit.placeName`)이지 역지오코딩 결과가 아니다.

10. **새 i18n 키가 하나도 없다.** 이벤트 줄 문구(`alert_place_enter` `%1$s에 도착했어요` / `alert_place_exit` `%1$s에서 나섰어요`)는 보호자 화면이 이미 갖고 있고(설계서 §8.5 "그대로 쓰는 키"), 아이 폰은 문구를 하나도 안 띄운다. 이름 없는 머무름의 `timeline_unknown_place`("머무른 곳")도 보호자 쪽 키다. 그래서 이 단계는 `i18n/*.json` 을 만지지 않는다 — 공통 절차 A 는 `--check` 만 돈다.

11. **골든은 둘이다.** 설계서 §12.2 의 일곱 중 `geofenceEvaluator.json`·`placeNameCache.json` 이 이 단계 몫이다. `GeofenceRegionSelection` 은 코틀린에서 인라인이라 대조할 함수가 없다(§7.2 끝) — 단위 테스트만 붙인다. 생성기 둘 다 끝에 `check(...)` 자체 점검을 넣어 **경계 바로 아래·위가 서로 다른 답을 내지 않으면 생성기가 죽게** 한다(§12.2, 2단계에서 실제로 났던 사고 — README 2026-09-13). 정확도·반경은 **`Float` 로 정확히 표현되는 값**(50.0, 49.5, 100.0, 100.5 …)만 쓴다(§4.1).

12. **이벤트 `at` 창은 7일이다.** 규칙이 `request.time.toMillis() - 7 * 24 * 60 * 60 * 1000` ~ `+ 60 * 60 * 1000` 이다(`firestore.rules:306-310`). 코틀린 `EventRepository.kt:25`·`PlaceWatcher.kt:131-132` 주석은 아직 "24시간"으로 적혀 있다 — 6단계 개발일지가 이미 결함으로 기록했다. **규칙이 맞다.** 에뮬레이터 테스트는 8일 전으로 거부를 확인한다.

13. **에뮬레이터 테스트는 아이 세션의 원시 쓰기로 규칙을 태우고, 그 dict 가 `EventDoc.firestoreData` 와 같은지는 단위 테스트가 본다.** `EventRepository.add` 는 기본 `FirebaseApp`(테스트에서는 보호자 세션)을 쓰는데, 익명 계정은 uid 를 고를 수 없어서 기본 앱을 아이로 만들 방법이 없다. `EventRepositoryTests.아이가_남긴다`(:22-28)가 이미 쓰고 있는 방식 그대로 간다 — 규칙은 원시 dict 로, 직렬화는 단위 테스트로.

14. **`read` 를 절대 읽지 않는다.** `EventDoc.firestoreData` 는 `doc.read` 를 보지 않고 **항상 `false` 를 싣는다**. 규칙이 `request.resource.data.read == false` 를 요구하고(`firestore.rules:308`), 어기면 **쓰기가 조용히 거부되고 부모는 그 사건이 없었던 것으로 읽는다**(`EventRepository.kt:18-27`). 코틀린이 "이 함수는 `EventDoc.read` 를 아예 건드리지 않는다"(`:24`)고 적은 그 자리다.

---

## File Structure

```
app/src/test/java/com/kidcare/family/logic/
└─ GoldenFileWriterTest.kt          수정. @Test 둘 + 생성기 둘 (app/ 에서 유일하게 만지는 파일)
ios/KidCare/
├─ Logic/
│  ├─ GeofenceEvaluator.swift       신규. Place·PlaceState·GeofenceHit·evaluate (logic/GeofenceEvaluator.kt)
│  ├─ PlaceNameCache.swift          신규. find·put·encode·decode (logic/PlaceNameCache.kt)
│  └─ GeofenceRegionSelection.swift 신규. 20개 고르기 (child/PlaceWatcher.kt:168-171)
├─ Core/
│  ├─ Documents.swift               수정. PlaceDoc.asPlace, EventDoc.firestoreData
│  ├─ EventRepository.swift         수정. add(familyId:doc:) (core/EventRepository.kt:53)
│  └─ PlaceRepository.swift         수정. 주석만 — 아이 폰도 observePlaces 를 쓴다(설계서 §3.3)
└─ Child/
   ├─ PlaceStateStore.swift         신규. child/PlaceStateStore.kt
   ├─ PlaceWatcher.swift            신규. child/PlaceWatcher.kt
   ├─ PlaceNamer.swift              신규. child/PlaceNamer.kt (actor)
   ├─ LocationCollector.swift       수정(1단계 파일). RegionMonitor 준수, 지역 콜백, requestOneShotFix()
   ├─ TrackingCoordinator.swift     수정(1단계 파일). 장소 구독·PlaceWatcher 배선·게이트 한 번 건너뛰기
   └─ TrailUploader.swift           수정(1단계 파일). buildSegments 가 이름을 붙인다
ios/KidCareTests/
├─ GeofenceEvaluatorTests.swift     신규
├─ PlaceNameCacheTests.swift        신규
├─ GeofenceRegionSelectionTests.swift 신규
├─ PlaceStateStoreTests.swift       신규
├─ PlaceWatcherTests.swift          신규
├─ PlaceNamerTests.swift            신규
├─ TrailUploaderNamingTests.swift   신규
├─ ChildEventWriteTests.swift       신규(에뮬레이터)
├─ EventDocumentsTests.swift        수정. firestoreData 대조
├─ GoldenComparisonTests.swift      수정. 대조 둘 + 케이스 수 하한 둘
└─ golden/
   ├─ geofenceEvaluator.json        생성물(코틀린이 쓴다)
   └─ placeNameCache.json           생성물(코틀린이 쓴다)
ios/dev/school-crossing.gpx         신규. 시뮬레이터 경계 넘기용(Task 4)
```

| Task | 끝나면 |
|---|---|
| 1 | 판정 로직 셋이 Swift 에 있고, 코틀린 골든 둘과 케이스 단위로 같은 답을 낸다 |
| 2 | 아이 세션이 규칙을 통과하는 `events/` 문서를 쓰고, 지역 등록·상태 보존·거부 경로가 테스트로 고정된다 |
| 3 | 하루 문서의 머무름에 이름이 붙고, 초당 1건·3초 예산·캐시 우선이 테스트로 고정된다 |
| 4 | 단계 마무리 — 상수 전수 대조, 골든이 정말 무는지 일부러 깨 보기, 시뮬레이터 GPX 통과 |

---

### Task 1: 판정 로직 셋과 골든 둘 — 코틀린이 정본이다

**끝나면 `Logic/GeofenceEvaluator`·`PlaceNameCache`·`GeofenceRegionSelection` 이 있고, 코틀린이 뽑은 `golden/geofenceEvaluator.json`·`golden/placeNameCache.json` 의 모든 케이스에서 Swift 가 같은 답을 낸다.** 화면 변화는 없다.

**Files:**
- Create: `ios/KidCare/Logic/GeofenceEvaluator.swift`, `ios/KidCare/Logic/PlaceNameCache.swift`, `ios/KidCare/Logic/GeofenceRegionSelection.swift`
- Modify: `app/src/test/java/com/kidcare/family/logic/GoldenFileWriterTest.kt`(@Test 둘 + 생성기 둘)
- Test: `ios/KidCareTests/GeofenceEvaluatorTests.swift`, `PlaceNameCacheTests.swift`, `GeofenceRegionSelectionTests.swift`(신규), `GoldenComparisonTests.swift`(수정)
- 생성물: `ios/KidCareTests/golden/geofenceEvaluator.json`, `placeNameCache.json`

**Interfaces:**
- Consumes: `LocationFilter.distanceMeters(_:_:)`·`LocationFilter.fallbackMaxAccuracyMeters`·`Fix`(1단계)
- Produces: `Place`, `PlaceState`, `GeofenceHit`, `GeofenceEvaluator.evaluate(places:states:fix:)`, `PlaceNameCache`, `GeofenceRegionSelection.choose(_:limit:)` — Task 2·3 이 쓴다

**정본:** `logic/GeofenceEvaluator.kt`(전체), `logic/PlaceNameCache.kt`(전체), `child/PlaceWatcher.kt:168-174, 217`.

- [ ] **Step 1: 포팅 테스트를 먼저 쓴다(빨강)**

`ios/KidCareTests/GeofenceEvaluatorTests.swift`:

```swift
import Foundation
import Testing
@testable import KidCare

/// 정본은 `logic/GeofenceEvaluator.kt`. 안드로이드 테스트를 옮긴 것이고, 넓은 입력 대조는
/// `GoldenComparisonTests.지오펜스_판정_대조` 가 따로 한다.
struct GeofenceEvaluatorTests {

    /// 위도 1도의 남북 거리(m). `LocationFilter.distanceMeters` 와 같은 지구 반지름에서 나온다 —
    /// 테스트가 "정확히 몇 m 떨어진 점"을 만들 때 쓴다.
    private static let 위도1도 = Double.pi / 180.0 * 6_371_000.0
    private func 북쪽(_ lat: Double, _ meters: Double) -> Double { lat + meters / Self.위도1도 }

    private let 기준위도 = 37.5665
    private let 기준경도 = 126.9780

    private func 장소(_ id: String = "p1", radius: Double = 100, enter: Bool = true, exit: Bool = true) -> Place {
        Place(id: id, name: "학교", lat: 기준위도, lng: 기준경도, radiusMeters: radius,
              notifyEnter: enter, notifyExit: exit)
    }

    private func 점(_ meters: Double, accuracy: Double = 10, at: Int64 = 1_000_000) -> Fix {
        Fix(lat: 북쪽(기준위도, meters), lng: 기준경도, accuracy: accuracy, at: at)
    }

    @Test("상수는 코틀린 그대로다 (:52, :55, :69)")
    func 상수() {
        #expect(GeofenceEvaluator.exitMarginMeters == 50.0)
        #expect(GeofenceEvaluator.dedupeMillis == 5 * 60 * 1000)
        // 숫자를 다시 적지 않고 참조를 옮긴다(:64-67). 두 숫자를 따로 두면 한쪽만 바뀌었을 때
        // 이 검사가 조용히 무의미해진다.
        #expect(GeofenceEvaluator.maxAccuracyMeters == LocationFilter.fallbackMaxAccuracyMeters)
    }

    @Test("못 믿는 점(오차 100m 초과)에서는 아무 판단도 안 하고 상태도 안 건드린다 (:78)")
    func 정확도_문턱() {
        let 이전 = [PlaceState(placeId: "p1", inside: false, lastEventAt: 0)]
        let (hits, next) = GeofenceEvaluator.evaluate(places: [장소()], states: 이전, fix: 점(0, accuracy: 100.5))
        #expect(hits.isEmpty)
        #expect(next == 이전, "못 믿는 점이 상태를 건드리면 다음 좋은 점에서 가짜 전환이 하나 만들어진다")
    }

    @Test("오차가 정확히 100m 면 판정한다 — 문턱은 '초과'다 (:78)")
    func 정확도_경계() {
        let (hits, _) = GeofenceEvaluator.evaluate(
            places: [장소()],
            states: [PlaceState(placeId: "p1", inside: false, lastEventAt: 0)],
            fix: 점(0, accuracy: 100.0))
        #expect(hits.count == 1)
    }

    @Test("처음 보는 장소는 이미 안에 있어도 알리지 않고 기억만 한다 (:97-103)")
    func 처음_보는_장소() {
        let (hits, next) = GeofenceEvaluator.evaluate(places: [장소()], states: [], fix: 점(0))
        #expect(hits.isEmpty, "일어나지도 않은 도착을 지금 시각으로 지어내면 안 된다")
        #expect(next == [PlaceState(placeId: "p1", inside: true, lastEventAt: 0)])
    }

    @Test("반경 안으로 들어오면 도착, 반경 + 여유 50m 를 넘어야 이탈이다 (:90-95)")
    func 히스테리시스() {
        let 밖 = [PlaceState(placeId: "p1", inside: false, lastEventAt: 0)]
        #expect(GeofenceEvaluator.evaluate(places: [장소()], states: 밖, fix: 점(99.5)).hits.count == 1)
        #expect(GeofenceEvaluator.evaluate(places: [장소()], states: 밖, fix: 점(100.5)).hits.isEmpty)

        let 안 = [PlaceState(placeId: "p1", inside: true, lastEventAt: 0)]
        // 반경 100 + 여유 50 = 150. 149.5m 는 아직 안이고 150.5m 는 나갔다.
        #expect(GeofenceEvaluator.evaluate(places: [장소()], states: 안, fix: 점(149.5)).hits.isEmpty)
        let 나감 = GeofenceEvaluator.evaluate(places: [장소()], states: 안, fix: 점(150.5))
        #expect(나감.hits.map(\.entering) == [false])
    }

    @Test("5분 중복 억제 — 알린 적 없음(0)·시계 역행(음수)은 억제하지 않는다 (:109-114)")
    func 중복_억제() {
        let 안 = { (lastEventAt: Int64) in [PlaceState(placeId: "p1", inside: true, lastEventAt: lastEventAt)] }
        let 지금: Int64 = 10_000_000
        // 4분 59.999초 전에 알렸다 → 아직 억제
        #expect(GeofenceEvaluator.evaluate(places: [장소()], states: 안(지금 - 299_999), fix: 점(200, at: 지금)).hits.isEmpty)
        // 정확히 5분 → 낸다
        #expect(GeofenceEvaluator.evaluate(places: [장소()], states: 안(지금 - 300_000), fix: 점(200, at: 지금)).hits.count == 1)
        // 한 번도 안 알렸으면 억제할 것이 없다
        #expect(GeofenceEvaluator.evaluate(places: [장소()], states: 안(0), fix: 점(200, at: 지금)).hits.count == 1)
        // 폰 시계가 뒤로 갔다. '아직 5분이 안 지났다'로 읽으면 그 폰은 다시는 알림을 못 낸다.
        #expect(GeofenceEvaluator.evaluate(places: [장소()], states: 안(지금 + 60_000), fix: 점(200, at: 지금)).hits.count == 1)
    }

    @Test("억제된 전환도 inside 는 바꾸고 lastEventAt 은 안 민다 (:117-120, PlaceState 주석)")
    func 억제되어도_상태는_간다() {
        let 지금: Int64 = 10_000_000
        let 이전 = [PlaceState(placeId: "p1", inside: true, lastEventAt: 지금 - 1_000)]
        let (hits, next) = GeofenceEvaluator.evaluate(places: [장소()], states: 이전, fix: 점(200, at: 지금))
        #expect(hits.isEmpty)
        #expect(next == [PlaceState(placeId: "p1", inside: false, lastEventAt: 지금 - 1_000)],
                "아무도 못 본 사건이 5분 시계를 밀면 그다음 진짜 알림이 조용히 사라진다")
    }

    @Test("부모가 끈 방향은 안 알리지만 inside 는 갱신한다 (:105-107)")
    func 알림_스위치() {
        let 밖 = [PlaceState(placeId: "p1", inside: false, lastEventAt: 0)]
        let (hits, next) = GeofenceEvaluator.evaluate(places: [장소(enter: false)], states: 밖, fix: 점(0))
        #expect(hits.isEmpty)
        #expect(next[0].inside, "안 바꾸면 반대 방향 알림까지 영영 못 나간다")
    }

    @Test("지워진 장소의 상태는 사라진다 (:82-84)")
    func 지워진_장소_정리() {
        let 이전 = [PlaceState(placeId: "p1", inside: true, lastEventAt: 5),
                    PlaceState(placeId: "없어진곳", inside: true, lastEventAt: 7)]
        let (_, next) = GeofenceEvaluator.evaluate(places: [장소()], states: 이전, fix: 점(0))
        #expect(next.map(\.placeId) == ["p1"], "그 장소를 다시 만들었을 때 옛 판정이 되살아나면 안 된다")
    }
}
```

`ios/KidCareTests/PlaceNameCacheTests.swift`:

```swift
import Foundation
import Testing
@testable import KidCare

/// 정본은 `logic/PlaceNameCache.kt`. 열쇠가 아니라 **거리**로 찾는 캐시다(:14-16).
struct PlaceNameCacheTests {

    private static let 위도1도 = Double.pi / 180.0 * 6_371_000.0
    private func 북쪽(_ lat: Double, _ meters: Double) -> Double { lat + meters / Self.위도1도 }
    private let 기준위도 = 37.5665
    private let 기준경도 = 126.9780

    @Test("상수는 코틀린 그대로다 (:67, :70)")
    func 상수() {
        #expect(PlaceNameCache.matchRadiusMeters == 30.0)
        #expect(PlaceNameCache.maxEntries == 300)
    }

    @Test("30m 안에서 가장 가까운 이름을 준다. 경계 밖은 nil (:33-44)")
    func 거리로_찾는다() {
        var cache = PlaceNameCache()
        cache.put(lat: 북쪽(기준위도, 25), lng: 기준경도, name: "먼 쪽")
        cache.put(lat: 북쪽(기준위도, 5), lng: 기준경도, name: "가까운 쪽")
        #expect(cache.find(lat: 기준위도, lng: 기준경도) == "가까운 쪽")
        #expect(cache.find(lat: 북쪽(기준위도, 60), lng: 기준경도) == nil)
    }

    @Test("같은 자리에 넣으면 바꿔 끼운다 — 흔들린 좌표마다 한 칸씩 늘지 않는다 (:46-56)")
    func 같은_자리는_교체() {
        var cache = PlaceNameCache()
        cache.put(lat: 기준위도, lng: 기준경도, name: "옛 이름")
        cache.put(lat: 북쪽(기준위도, 10), lng: 기준경도, name: "새 이름")
        #expect(cache.size == 1)
        #expect(cache.find(lat: 기준위도, lng: 기준경도) == "새 이름")
    }

    @Test("탭·줄바꿈은 공백으로 바꾸고 양끝을 다듬는다. 빈 이름은 안 넣는다 (:51-52)")
    func 이름_다듬기() {
        var cache = PlaceNameCache()
        cache.put(lat: 기준위도, lng: 기준경도, name: "  가\t나\n다\r라  ")
        #expect(cache.find(lat: 기준위도, lng: 기준경도) == "가 나 다 라")
        cache.put(lat: 북쪽(기준위도, 100), lng: 기준경도, name: "   ")
        #expect(cache.size == 1)
    }

    @Test("U+00A0 는 자르지 않는다 — 코틀린 trim() 과 같은 집합이다(판정 기록 4)")
    func 자바와_같은_공백() {
        var cache = PlaceNameCache()
        cache.put(lat: 기준위도, lng: 기준경도, name: "\u{00A0}카페\u{00A0}")
        #expect(cache.find(lat: 기준위도, lng: 기준경도) == "\u{00A0}카페\u{00A0}",
                "Swift 기본 trimmingCharacters(.whitespacesAndNewlines) 는 U+00A0 를 잘라 코틀린과 갈린다")
    }

    @Test("상한을 넘으면 오래된 것부터 버린다 (:55)")
    func 상한() {
        var cache = PlaceNameCache(matchRadiusMeters: 30, maxEntries: 3)
        for i in 0..<5 { cache.put(lat: 북쪽(기준위도, Double(i) * 100), lng: 기준경도, name: "곳\(i)") }
        #expect(cache.size == 3)
        #expect(cache.find(lat: 기준위도, lng: 기준경도) == nil, "가장 먼저 넣은 곳0 이 밀려났다")
        #expect(cache.find(lat: 북쪽(기준위도, 400), lng: 기준경도) == "곳4")
    }

    @Test("한 줄에 한 곳: 위도,경도<탭>이름 (:59)")
    func 부호화() {
        var cache = PlaceNameCache()
        cache.put(lat: 1.5, lng: 2.5, name: "가")
        cache.put(lat: 3.5, lng: 4.5, name: "나")
        #expect(cache.encode() == "1.5,2.5\t가\n3.5,4.5\t나")
    }

    @Test("망가진 줄은 조용히 건너뛴다 — 한 줄 때문에 이름 전체를 잃으면 안 된다 (:72-89)")
    func 복호화() {
        let cache = PlaceNameCache.decode(
            """
            1.5,2.5\t좋은 줄
            탭이없다
            \t앞이비었다
            1.5\t칸이하나
            a,2.5\t위도가숫자아님
            1.5,b\t경도가숫자아님
            3.5,4.5\t또 좋은 줄
            """)
        #expect(cache.size == 2)
        #expect(cache.find(lat: 1.5, lng: 2.5) == "좋은 줄")
        #expect(cache.find(lat: 3.5, lng: 4.5) == "또 좋은 줄")
    }
}
```

`ios/KidCareTests/GeofenceRegionSelectionTests.swift`:

```swift
import Foundation
import Testing
@testable import KidCare

/// 정본은 `child/PlaceWatcher.kt:168-174`(코틀린에서는 인라인이라 골든 대상이 아니다, 설계서 §7.2).
struct GeofenceRegionSelectionTests {

    private func 장소(_ id: String, _ name: String, radius: Double = 100) -> Place {
        Place(id: id, name: name, lat: 37.5, lng: 127.0, radiusMeters: radius)
    }

    @Test("상한은 20 이다 — 아이폰 OS 상한과 같고 부모 화면의 장소 개수 상한과도 같다 (PlaceWatcher.kt:217)")
    func 상한() { #expect(GeofenceRegionSelection.maxRegions == 20) }

    @Test("반경이 0 이하인 장소는 뺀다 — iOS 도 반경 0 을 거부한다 (:169)")
    func 반경0_제외() {
        let 고른것 = GeofenceRegionSelection.choose([
            장소("a", "가", radius: 0), 장소("b", "나", radius: -1), 장소("c", "다", radius: 50),
        ])
        #expect(고른것.map(\.id) == ["c"])
    }

    @Test("이름순으로 앞에서 20개 — 읽어온 순서로 자르면 어떤 장소는 하루는 걸리고 하루는 안 걸린다 (:166-171)")
    func 이름순_스물() {
        let 뒤섞인 = (0..<25).reversed().map { 장소("id\($0)", String(format: "곳%02d", $0)) }
        let 고른것 = GeofenceRegionSelection.choose(뒤섞인)
        #expect(고른것.count == 20)
        #expect(고른것.map(\.name) == (0..<20).map { String(format: "곳%02d", $0) })
    }

    @Test("이름이 같으면 읽어온 순서를 지킨다 — 코틀린 sortedBy 는 안정 정렬이다(판정 기록 3)")
    func 안정_정렬() {
        let 같은이름 = (0..<5).map { 장소("id\($0)", "집") }
        #expect(GeofenceRegionSelection.choose(같은이름, limit: 3).map(\.id) == ["id0", "id1", "id2"])
    }

    @Test("정렬은 UTF-16 코드 단위 비교다 — 코틀린 String.compareTo 와 같다(판정 기록 3)")
    func 코드_단위_정렬() {
        // 전각 A(U+FF21) 는 '가'(U+AC00) 보다 코드 단위가 크다. Swift 의 기본 `<` 는 정규화를
        // 거쳐 다른 답을 낼 수 있다.
        let 고른것 = GeofenceRegionSelection.choose([장소("a", "\u{FF21}"), 장소("b", "가")])
        #expect(고른것.map(\.id) == ["b", "a"])
    }

    @Test("잘린 개수를 부르는 쪽이 알 수 있다 — 조용히 실패하면 '왜 알림이 안 오지'를 알아낼 방법이 없다 (:172-174)")
    func 잘린_개수() {
        let 결과 = GeofenceRegionSelection.chooseWithReport((0..<25).map { 장소("id\($0)", "곳\($0)") })
        #expect(결과.chosen.count == 20)
        #expect(결과.dropped == 5)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/GeofenceEvaluatorTests -only-testing:KidCareTests/PlaceNameCacheTests -only-testing:KidCareTests/GeofenceRegionSelectionTests`
Expected: 컴파일 실패. `Place`·`PlaceNameCache`·`GeofenceRegionSelection` 이 없다.

- [ ] **Step 3: `Logic/GeofenceEvaluator.swift`**

```swift
import Foundation

/// 부모가 정한 장소 하나. 정본 `logic/GeofenceEvaluator.kt:4-12`.
/// `Core/Documents.swift` 의 `PlaceDoc`(Firestore 문서 표현)과 나뉜 이유는 그 문서 주석과 같다 —
/// 판정은 Firestore 를 몰라야 골든 대조가 가능하다.
struct Place: Equatable, Sendable {
    let id: String
    let name: String
    let lat: Double
    let lng: Double
    let radiusMeters: Double
    let notifyEnter: Bool
    let notifyExit: Bool

    init(id: String, name: String, lat: Double, lng: Double, radiusMeters: Double,
         notifyEnter: Bool = true, notifyExit: Bool = true) {
        self.id = id
        self.name = name
        self.lat = lat
        self.lng = lng
        self.radiusMeters = radiusMeters
        self.notifyEnter = notifyEnter
        self.notifyExit = notifyExit
    }
}

/// 장소 하나에 대해 아이 폰이 기억하고 있는 것. 정본 `:14-26`.
///
/// `lastEventAt` 은 **부모에게 실제로 알린** 마지막 시각이다. 전환이 일어난 시각이 아니다.
/// 알리지 않기로 한 전환이 이 값을 밀면, 아무도 못 본 사건 때문에 5분 시계가 다시 돌아
/// **그다음 진짜 알림이 조용히 사라진다.** 알린 적이 없으면 0 이다.
struct PlaceState: Equatable, Sendable {
    let placeId: String
    let inside: Bool
    let lastEventAt: Int64
}

/// 알릴 만한 일이 생겼다. 정본 `:28-34`.
struct GeofenceHit: Equatable, Sendable {
    let placeId: String
    let placeName: String
    let entering: Bool
    let at: Int64
}

/// 위치 한 점으로 장소 도착·이탈을 판정한다. 정본 `logic/GeofenceEvaluator.kt:49-124`.
///
/// OS 지역 감시를 쓰면서도 이 판정을 따로 두는 이유는 안드로이드와 같다 — 그 콜백에는
/// 히스테리시스도, 5분 중복 억제도, 정확도 문턱도 없다. 경계에 앉은 아이 하나 때문에 부모
/// 폰이 하루 종일 운다. 아이폰에서는 이유가 하나 더 붙는다: iOS 의 지역 콜백은 좌표를 아예
/// 안 준다(설계서 §7.1).
///
/// 이 판정은 **본 것만 말한다.** 경계를 건너는 것을 본 적이 없으면 아무 말도 하지 않는다.
enum GeofenceEvaluator {

    /// 이탈로 인정하기 위해 반경에 더 얹는 여유(m). 경계에서 떨리는 것을 막는다(`:52`).
    static let exitMarginMeters: Double = 50.0

    /// 한 장소에 대해 알림을 다시 보내기까지 기다리는 시간(`:55`).
    static let dedupeMillis: Int64 = 5 * 60 * 1000

    /// 이보다 오차가 크면 판정에 쓰지 않는다.
    ///
    /// **숫자를 따로 적지 않는다**(`:57-69`). `fallbackMaxAccuracyMeters` 는 "이보다 나쁜 점은
    /// 아무리 급해도 안 올린다"는 뜻이라, 애초에 여기까지 올 수 있는 점의 상한이 그것이다.
    /// 두 숫자를 따로 두면 나중에 한쪽만 바뀌었을 때 이 검사가 조용히 무의미해진다.
    static let maxAccuracyMeters: Double = LocationFilter.fallbackMaxAccuracyMeters

    static func evaluate(places: [Place], states: [PlaceState], fix: Fix) -> (hits: [GeofenceHit], states: [PlaceState]) {
        // 못 믿는 점에서는 아무 판단도 하지 않는다. 지워진 장소의 상태를 정리하는 것도 판단이라
        // 여기서 같이 미룬다 — 다음 좋은 점 하나면 사라진다(`:76-78`).
        if fix.accuracy > maxAccuracyMeters { return ([], states) }

        // 코틀린 associateBy 는 키가 겹치면 **뒤엣것**을 남긴다. 같은 규칙을 명시한다.
        let byId = Dictionary(states.map { ($0.placeId, $0) }, uniquingKeysWith: { _, last in last })
        var hits: [GeofenceHit] = []
        var next: [PlaceState] = []
        next.reserveCapacity(places.count)

        // 지금 있는 장소만 남긴다 — 부모가 지운 장소의 상태를 계속 들고 있으면 그 장소를 다시
        // 만들었을 때 옛 판정이 되살아난다(`:82-84`).
        for place in places {
            let was = byId[place.id]
            // distanceMeters 는 두 점의 위경도만 읽는다. 정확도·시각 자리는 0 으로 채운다(`:86-89`).
            let distance = LocationFilter.distanceMeters(
                Fix(lat: place.lat, lng: place.lng, accuracy: 0, at: 0), fix)
            let nowInside: Bool = if was?.inside == true {
                // 안에 있던 아이는 반경 + 여유를 넘어야 나간 것으로 본다.
                distance <= place.radiusMeters + exitMarginMeters
            } else {
                distance <= place.radiusMeters
            }

            let notify: Bool
            if let was {
                if nowInside == was.inside {
                    notify = false
                } else if !(nowInside ? place.notifyEnter : place.notifyExit) {
                    // 부모가 끈 방향은 알리지 않는다. 그래도 아래에서 inside 는 갱신한다(`:105-107`).
                    notify = false
                } else {
                    let sinceLast = fix.at - was.lastEventAt
                    // 알린 적이 없으면(0) 억제할 것도 없다. 음수는 폰 시계가 뒤로 갔다는 뜻인데
                    // 그것을 '아직 5분이 안 지났다'로 읽으면 그 폰은 다시는 알림을 못 낸다 —
                    // 침묵이 이 앱에서 제일 나쁜 고장이다(`:109-114`).
                    notify = was.lastEventAt == 0 || sinceLast < 0 || sinceLast >= dedupeMillis
                }
            } else {
                // 처음 보는 장소. 이미 안에 있어도 **알리지 않고 기억만 한다**(`:97-103`).
                // 상태가 없다는 것은 대개 부모가 방금 그 장소를 만들었다는 뜻이고, 그때 아이가
                // 마침 집·학원 안에 있는 것은 아주 흔하다. 여기서 "도착했어요"를 보내면 일어나지도
                // 않은 도착을, 그것도 지금 시각으로 지어내는 것이 된다.
                notify = false
            }

            if notify {
                hits.append(GeofenceHit(placeId: place.id, placeName: place.name, entering: nowInside, at: fix.at))
            }
            // 알리지 않기로 했어도 inside 는 바꾼다. 안 바꾸면 5분 뒤에 같은 전환이 다시 잡혀
            // "늦게 온 도착"이 뜬다. 반대로 lastEventAt 은 **알렸을 때만** 민다(`:117-120`).
            next.append(PlaceState(placeId: place.id, inside: nowInside,
                                   lastEventAt: notify ? fix.at : (was?.lastEventAt ?? 0)))
        }
        return (hits, next)
    }
}
```

- [ ] **Step 4: `Logic/PlaceNameCache.swift`**

```swift
import Foundation

/// 역지오코딩으로 얻은 장소 이름을 좌표 **근처**로 찾는 캐시. 정본 `logic/PlaceNameCache.kt`.
///
/// 열쇠를 버리고 **거리**로 찾는 이유는 그 파일 주석(:3-19)에 있다 — 이름을 묻는 좌표
/// (`Segment.nameLat`/`nameLng`)는 머무름 점들의 오차 가중 평균이라 점이 하나 늘 때마다 몇 미터씩
/// 움직인다. 반올림한 열쇠는 그때마다 달라져 캐시가 거의 안 맞았다.
///
/// 코틀린은 `ArrayDeque` 를 가진 클래스지만 여기서는 **값 타입**이다. `actor PlaceNamer` 안에
/// 두려면 값 타입이 가장 단순하고, 이 타입이 하는 일은 배열 하나 다루기라 참조 의미가 필요 없다.
struct PlaceNameCache: Equatable, Sendable {

    struct Entry: Equatable, Sendable {
        let lat: Double
        let lng: Double
        let name: String
    }

    /// 같은 곳으로 볼 거리(`:67`). 머무름 반경(`SegmentBuilder.stayRadiusMeters`, 40m)보다 조금 작다.
    static let matchRadiusMeters = 30.0

    /// 아이가 다니는 곳은 많아야 수십 곳이다. 넉넉히 두되 끝없이 늘지는 않게(`:70`).
    static let maxEntries = 300

    /// 코틀린 `String.trim()` 이 쓰는 `Character.isWhitespace` 집합이다(판정 기록 4).
    /// **비분리 공백 셋(U+00A0·U+2007·U+202F)과 U+0085(NEL)를 일부러 뺐다** — Swift 기본
    /// `.whitespacesAndNewlines` 는 그 넷을 자르고, 그러면 같은 좌표에 두 플랫폼이 다른 이름을 남긴다.
    static let 자바_공백: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.subtract(CharacterSet(charactersIn: "\u{00A0}\u{2007}\u{202F}\u{0085}"))
        set.formUnion(CharacterSet(charactersIn: "\u{000B}\u{001C}\u{001D}\u{001E}\u{001F}"))
        return set
    }()

    private let matchRadius: Double
    private let limit: Int
    /// 뒤로 갈수록 최근에 넣은 것. 상한을 넘으면 앞(오래된 것)부터 버린다(`:27-28`).
    private var entries: [Entry] = []

    var size: Int { entries.count }

    init(matchRadiusMeters: Double = PlaceNameCache.matchRadiusMeters,
         maxEntries: Int = PlaceNameCache.maxEntries) {
        matchRadius = matchRadiusMeters
        limit = maxEntries
    }

    /// 반경 안에서 가장 가까운 이름. 없으면 nil (`:32-44`).
    func find(lat: Double, lng: Double) -> String? {
        var best: Entry?
        var bestDistance = Double.greatestFiniteMagnitude
        for entry in entries {
            let distance = Self.distanceMeters(lat, lng, entry.lat, entry.lng)
            if distance <= matchRadius && distance < bestDistance {
                best = entry
                bestDistance = distance
            }
        }
        return best?.name
    }

    /// 이름을 넣는다. 같은 자리(반경 안)에 이미 있던 것은 **바꿔 끼운다**(`:46-56`) — 안 그러면
    /// 집처럼 매일 가는 곳이 흔들린 좌표마다 한 칸씩 늘어 상한을 금방 채운다.
    mutating func put(lat: Double, lng: Double, name: String) {
        let clean = name
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: Self.자바_공백)
        if clean.isEmpty { return }
        entries.removeAll { Self.distanceMeters(lat, lng, $0.lat, $0.lng) <= matchRadius }
        entries.append(Entry(lat: lat, lng: lng, name: clean))
        while entries.count > limit { entries.removeFirst() }
    }

    /// 한 줄에 한 곳: `위도,경도<탭>이름` (`:59`).
    ///
    /// 숫자 글자는 코틀린 `Double.toString` 과 다를 수 있다. **그래서 골든 대조는 이 문자열이 아니라
    /// `decode` 한 뒤의 값으로 한다**(설계서 §4.5 가 `TrailCodec` 에 정한 규율과 같다).
    func encode() -> String {
        entries.map { "\($0.lat),\($0.lng)\t\($0.name)" }.joined(separator: "\n")
    }

    /// 망가진 줄은 조용히 건너뛴다 — 캐시 한 줄 때문에 이름 전체를 잃으면 안 된다(`:72-89`).
    static func decode(_ text: String,
                       matchRadiusMeters: Double = PlaceNameCache.matchRadiusMeters,
                       maxEntries: Int = PlaceNameCache.maxEntries) -> PlaceNameCache {
        var cache = PlaceNameCache(matchRadiusMeters: matchRadiusMeters, maxEntries: maxEntries)
        for line in text.components(separatedBy: "\n") {
            // 코틀린 indexOf('\t') <= 0 — 탭이 없거나 맨 앞이면 버린다.
            guard let tab = line.firstIndex(of: "\t"), tab != line.startIndex else { continue }
            let coordinates = line[line.startIndex..<tab].components(separatedBy: ",")
            guard coordinates.count == 2,
                  let lat = Double(coordinates[0]), let lng = Double(coordinates[1]) else { continue }
            cache.put(lat: lat, lng: lng, name: String(line[line.index(after: tab)...]))
        }
        return cache
    }

    private static func distanceMeters(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        LocationFilter.distanceMeters(
            Fix(lat: lat1, lng: lng1, accuracy: 0, at: 0),
            Fix(lat: lat2, lng: lng2, accuracy: 0, at: 0))
    }
}
```

> **주의 하나.** `Double("1.5")` 는 Swift 에서 `"1.5d"`·`"0x1p3"`·`"nan"` 같은 글자도 받고, 코틀린 `toDoubleOrNull`(= `Double.parseDouble`)도 같은 넓이다. 두 쪽이 갈리지 않는 것을 골든의 `broken_lines`·`not_a_number_coordinate` 케이스가 확인한다.

- [ ] **Step 5: `Logic/GeofenceRegionSelection.swift`**

```swift
import Foundation

/// 장소 목록에서 OS 에 걸 20개를 고른다. 정본 `child/PlaceWatcher.kt:168-174`(코틀린에서는 인라인).
///
/// 순수 함수로 따로 뺀 이유(설계서 §3.1·§7.2): 아이폰은 **OS 상한이 정확히 20** 이라 여기서 잘못
/// 자르면 그 장소의 알림이 통째로 사라지는데, `CLLocationManager` 를 끼고는 그것을 테스트할 수 없다.
enum GeofenceRegionSelection {

    /// `PlaceWatcher.kt:217`. 안드로이드는 OS 상한 100 중 스스로 20 으로 잘랐고, 아이폰은 그 20 이
    /// 곧 OS 상한이다 — 그래서 두 플랫폼의 숫자가 이미 같고 넘칠 일이 구조적으로 없다(설계서 §7.2).
    static let maxRegions = 20

    struct Report {
        let chosen: [Place]
        /// 상한·반경 0 으로 빠진 개수. 부르는 쪽이 로그로 남긴다(`:172-174`).
        let dropped: Int
    }

    static func choose(_ places: [Place], limit: Int = maxRegions) -> [Place] {
        chooseWithReport(places, limit: limit).chosen
    }

    static func chooseWithReport(_ places: [Place], limit: Int = maxRegions) -> Report {
        // 1. 반경이 0 이하인 장소를 뺀다. 안드로이드는 그런 값 하나가 목록 전체의 등록을
        //    실패시켰다(`:150-152`). iOS 도 반경 0 인 CLCircularRegion 은 전환을 주지 않는다.
        let usable = places.filter { $0.radiusMeters > 0 }
        // 2. **이름순으로** 앞에서 limit 개. 읽어온 순서로 자르면 어떤 장소는 하루는 걸리고
        //    하루는 안 걸린다(`:166-168`). 코틀린 sortedBy 는 안정 정렬이고 String.compareTo 는
        //    UTF-16 코드 단위 비교인데 Swift 는 둘 다 다르므로(판정 기록 3) 직접 맞춘다.
        let sorted = usable.enumerated().sorted { left, right in
            if left.element.name == right.element.name { return left.offset < right.offset }
            return utf16Less(left.element.name, right.element.name)
        }.map(\.element)
        let chosen = Array(sorted.prefix(limit))
        return Report(chosen: chosen, dropped: places.count - chosen.count)
    }

    /// 코틀린 `String.compareTo` 와 같은 순서 — UTF-16 코드 단위를 앞에서부터 비교하고,
    /// 한쪽이 다른 쪽의 접두사면 짧은 쪽이 앞이다.
    private static func utf16Less(_ a: String, _ b: String) -> Bool {
        var x = a.utf16.makeIterator()
        var y = b.utf16.makeIterator()
        while true {
            switch (x.next(), y.next()) {
            case (nil, nil): return false
            case (nil, _): return true
            case (_, nil): return false
            case let (l?, r?) where l != r: return l < r
            default: continue
            }
        }
    }
}
```

- [ ] **Step 6: 초록을 확인한다**

Run: Step 2 와 같은 명령.
Expected: PASS. `GeofenceEvaluatorTests` 9, `PlaceNameCacheTests` 8, `GeofenceRegionSelectionTests` 6 = 23개.

- [ ] **Step 7: 코틀린 골든 생성기 둘을 더한다**

`app/src/test/java/com/kidcare/family/logic/GoldenFileWriterTest.kt` **끝의 `}` 앞**에 아래를 붙인다. 이 파일의 규율(손으로 짠 `toJson`, `generate*()` 를 먼저 지역 변수로 평가한 뒤 `writeGoldenIfPresent`, `writeIfChanged`, 끝의 `check(...)` 자체 점검)을 그대로 따른다. `PI`·`Random` 은 이미 import 돼 있고 나머지는 같은 패키지라 새 import 가 없다.

```kotlin
    // ==================================================================
    // 6. GeofenceEvaluator — 히스테리시스·5분 중복 억제·정확도 문턱
    // ==================================================================

    /** 남북으로 정확히 [meters] 만큼 떨어진 위도 차이. distanceMeters 와 같은 반지름에서 나온다. */
    private fun latOffset(meters: Double): Double = meters / (PI / 180.0 * 6_371_000.0)

    private fun placeJson(p: Place) = linkedMapOf<String, Any?>(
        "id" to p.id, "name" to p.name, "lat" to p.lat, "lng" to p.lng,
        "radiusMeters" to p.radiusMeters, "notifyEnter" to p.notifyEnter, "notifyExit" to p.notifyExit,
    )

    private fun stateJson(s: PlaceState) = linkedMapOf<String, Any?>(
        "placeId" to s.placeId, "inside" to s.inside, "lastEventAt" to s.lastEventAt,
    )

    @Test
    fun `골든 - GeofenceEvaluator`() {
        val cases = generateGeofenceEvaluator()
        writeGoldenIfPresent("geofenceEvaluator", toJson(cases))
    }

    private fun generateGeofenceEvaluator(): List<Map<String, Any?>> {
        val cases = mutableListOf<Map<String, Any?>>()
        val hitsByName = mutableMapOf<String, List<GeofenceHit>>()
        val baseLat = 37.5665
        val baseLng = 126.9780
        val now = 10_000_000L

        fun add(name: String, places: List<Place>, states: List<PlaceState>, fix: Fix) {
            val (hits, next) = GeofenceEvaluator.evaluate(places, states, fix)
            hitsByName[name] = hits
            cases += linkedMapOf(
                "name" to name,
                "places" to places.map(::placeJson),
                "states" to states.map(::stateJson),
                "fix" to linkedMapOf<String, Any?>(
                    "lat" to fix.lat, "lng" to fix.lng, "accuracy" to fix.accuracy, "at" to fix.at,
                ),
                "hits" to hits.map {
                    linkedMapOf<String, Any?>(
                        "placeId" to it.placeId, "placeName" to it.placeName,
                        "entering" to it.entering, "at" to it.at,
                    )
                },
                "nextStates" to next.map(::stateJson),
            )
        }

        fun place(id: String, radius: Double, enter: Boolean = true, exit: Boolean = true) =
            Place(id, "장소 $id", baseLat, baseLng, radius, enter, exit)

        // 정확도는 Float 로 정확히 표현되는 값만 쓴다(설계서 §4.1) — 안 그러면 두 언어가 같은
        // 함수인데도 문턱 바로 위에서 갈린다.
        fun fix(meters: Double, accuracy: Float, at: Long = now) =
            Fix(baseLat + latOffset(meters), baseLng, accuracy, at)

        val outside = listOf(PlaceState("a", false, 0L))
        val inside = listOf(PlaceState("a", true, 0L))

        // --- 반경 경계(도착) ---
        add("enter_just_inside", listOf(place("a", 100.0)), outside, fix(99.5, 10f))
        add("enter_exact_radius", listOf(place("a", 100.0)), outside, fix(100.0, 10f))
        add("enter_just_outside", listOf(place("a", 100.0)), outside, fix(100.5, 10f))

        // --- 이탈 여유 50m ---
        add("exit_inside_margin", listOf(place("a", 100.0)), inside, fix(149.5, 10f))
        add("exit_exact_margin", listOf(place("a", 100.0)), inside, fix(150.0, 10f))
        add("exit_beyond_margin", listOf(place("a", 100.0)), inside, fix(150.5, 10f))

        // --- 정확도 문턱(참조가 FALLBACK 100m 인지) ---
        add("accuracy_ok_99_5", listOf(place("a", 100.0)), outside, fix(0.0, 99.5f))
        add("accuracy_exact_100", listOf(place("a", 100.0)), outside, fix(0.0, 100f))
        add("accuracy_over_100_5", listOf(place("a", 100.0)), outside, fix(0.0, 100.5f))
        add("accuracy_over_keeps_state", listOf(place("a", 100.0)), inside, fix(1_000.0, 200f))

        // --- 처음 보는 장소 ---
        add("unseen_inside", listOf(place("a", 100.0)), emptyList(), fix(0.0, 10f))
        add("unseen_outside", listOf(place("a", 100.0)), emptyList(), fix(500.0, 10f))

        // --- 5분 중복 억제 ---
        add("dedupe_just_under", listOf(place("a", 100.0)), listOf(PlaceState("a", true, now - 299_999)), fix(500.0, 10f))
        add("dedupe_exact", listOf(place("a", 100.0)), listOf(PlaceState("a", true, now - 300_000)), fix(500.0, 10f))
        add("dedupe_over", listOf(place("a", 100.0)), listOf(PlaceState("a", true, now - 300_001)), fix(500.0, 10f))
        add("dedupe_never_notified", listOf(place("a", 100.0)), listOf(PlaceState("a", true, 0L)), fix(500.0, 10f))
        add("dedupe_clock_went_back", listOf(place("a", 100.0)), listOf(PlaceState("a", true, now + 60_000)), fix(500.0, 10f))

        // --- 알림 스위치 ---
        add("notify_enter_off", listOf(place("a", 100.0, enter = false)), outside, fix(0.0, 10f))
        add("notify_exit_off", listOf(place("a", 100.0, exit = false)), inside, fix(500.0, 10f))

        // --- 지워진 장소 정리·여러 장소·빈 목록 ---
        add(
            "stale_state_dropped",
            listOf(place("a", 100.0)),
            listOf(PlaceState("a", true, 5L), PlaceState("gone", true, 7L)),
            fix(0.0, 10f),
        )
        add(
            "two_places_one_hit",
            listOf(place("a", 100.0), Place("b", "장소 b", baseLat + latOffset(1_000.0), baseLng, 100.0)),
            listOf(PlaceState("a", false, 0L), PlaceState("b", false, 0L)),
            fix(0.0, 10f),
        )
        // 상태에 같은 placeId 가 둘 — associateBy 는 뒤엣것을 남긴다.
        add(
            "duplicate_state_last_wins",
            listOf(place("a", 100.0)),
            listOf(PlaceState("a", false, 0L), PlaceState("a", true, now - 1_000)),
            fix(0.0, 10f),
        )
        add("empty_places", emptyList(), inside, fix(0.0, 10f))
        add("zero_radius", listOf(place("a", 0.0)), outside, fix(0.0, 10f))

        // --- 고정 시드 무작위: 생각 못 한 조합 ---
        val random = Random(20260922)
        repeat(40) { i ->
            val count = random.nextInt(1, 4)
            val places = (0 until count).map { k ->
                Place(
                    "r$k", "무작위 $k",
                    baseLat + latOffset(random.nextDouble(-300.0, 300.0)),
                    baseLng,
                    listOf(25.0, 50.0, 100.0, 200.0, 0.0)[random.nextInt(5)],
                    random.nextBoolean(), random.nextBoolean(),
                )
            }
            val states = places.filter { random.nextBoolean() }.map {
                PlaceState(
                    it.id, random.nextBoolean(),
                    listOf(0L, now - 10_000, now - 400_000, now + 5_000)[random.nextInt(4)],
                )
            }
            val accuracy = listOf(5f, 10f, 49.5f, 50f, 99.5f, 100f, 100.5f)[random.nextInt(7)]
            add(
                "random_$i", places, states,
                Fix(baseLat + latOffset(random.nextDouble(-400.0, 400.0)), baseLng, accuracy, now),
            )
        }

        // 자체 점검 — "경계값"이라 이름 붙인 케이스가 실제로 경계를 가르는지 확인한다.
        // 2단계에서 경계 케이스가 경계 근처에 가지도 못한 사고가 있었다(README 2026-09-13).
        check(hitsByName.getValue("enter_just_inside").size == 1 && hitsByName.getValue("enter_just_outside").isEmpty()) {
            "반경 경계 케이스가 같은 답을 낸다 — 생성기가 경계 근처에 못 갔다"
        }
        check(hitsByName.getValue("exit_inside_margin").isEmpty() && hitsByName.getValue("exit_beyond_margin").size == 1) {
            "이탈 여유 50m 케이스가 같은 답을 낸다"
        }
        check(hitsByName.getValue("accuracy_exact_100").size == 1 && hitsByName.getValue("accuracy_over_100_5").isEmpty()) {
            "정확도 문턱 케이스가 같은 답을 낸다 — MAX_ACCURACY_METERS 참조가 끊겼을 수 있다"
        }
        check(hitsByName.getValue("dedupe_just_under").isEmpty() && hitsByName.getValue("dedupe_exact").size == 1) {
            "5분 중복 억제 경계 케이스가 같은 답을 낸다"
        }
        check(hitsByName.getValue("unseen_inside").isEmpty()) { "처음 보는 장소에서 알림이 나갔다" }

        return cases
    }

    // ==================================================================
    // 7. PlaceNameCache — 30m 경계·300개 상한·망가진 줄
    // ==================================================================

    @Test
    fun `골든 - PlaceNameCache`() {
        val payload = linkedMapOf(
            "find" to generatePlaceNameCacheFind(),
            "put" to generatePlaceNameCachePut(),
            "decode" to generatePlaceNameCacheDecode(),
        )
        writeGoldenIfPresent("placeNameCache", toJson(payload))
    }

    /** 캐시 하나를 (lat, lng, name) 세 칸 줄 목록으로 적는다 — 스위프트가 값으로 대조한다. */
    private fun cacheEntriesJson(cache: PlaceNameCache): List<List<Any?>> =
        cache.encode().lineSequence().filter { it.isNotEmpty() }.map { line ->
            val tab = line.indexOf('\t')
            val coordinates = line.substring(0, tab).split(',')
            listOf<Any?>(coordinates[0].toDouble(), coordinates[1].toDouble(), line.substring(tab + 1))
        }.toList()

    private fun generatePlaceNameCacheFind(): List<Map<String, Any?>> {
        val cases = mutableListOf<Map<String, Any?>>()
        val results = mutableMapOf<String, String?>()
        val baseLat = 37.5665
        val baseLng = 126.9780

        fun add(name: String, puts: List<Triple<Double, Double, String>>, lat: Double, lng: Double) {
            val cache = PlaceNameCache()
            puts.forEach { cache.put(it.first, it.second, it.third) }
            val found = cache.find(lat, lng)
            results[name] = found
            cases += linkedMapOf(
                "name" to name,
                "puts" to puts.map { listOf<Any?>(it.first, it.second, it.third) },
                "lat" to lat, "lng" to lng, "found" to found,
            )
        }

        add("empty", emptyList(), baseLat, baseLng)
        add("just_inside_29_9", listOf(Triple(baseLat + latOffset(29.9), baseLng, "가까운 곳")), baseLat, baseLng)
        add("exact_30", listOf(Triple(baseLat + latOffset(30.0), baseLng, "딱 30m")), baseLat, baseLng)
        add("just_outside_30_1", listOf(Triple(baseLat + latOffset(30.1), baseLng, "먼 곳")), baseLat, baseLng)
        add(
            "nearest_wins",
            listOf(
                Triple(baseLat + latOffset(25.0), baseLng, "먼 쪽"),
                Triple(baseLat + latOffset(5.0), baseLng, "가까운 쪽"),
            ),
            baseLat, baseLng,
        )
        add("not_a_number_coordinate", listOf(Triple(Double.NaN, baseLng, "망가진 좌표")), baseLat, baseLng)

        check(results["just_inside_29_9"] != null && results["just_outside_30_1"] == null) {
            "30m 경계 케이스가 같은 답을 낸다 — 생성기가 경계 근처에 못 갔다"
        }
        return cases
    }

    private fun generatePlaceNameCachePut(): List<Map<String, Any?>> {
        val cases = mutableListOf<Map<String, Any?>>()
        val sizes = mutableMapOf<String, Int>()
        val baseLat = 37.5665
        val baseLng = 126.9780

        fun add(name: String, matchRadius: Double, maxEntries: Int, puts: List<Triple<Double, Double, String>>) {
            val cache = PlaceNameCache(matchRadius, maxEntries)
            puts.forEach { cache.put(it.first, it.second, it.third) }
            sizes[name] = cache.size
            cases += linkedMapOf(
                "name" to name,
                "matchRadiusMeters" to matchRadius,
                "maxEntries" to maxEntries,
                "puts" to puts.map { listOf<Any?>(it.first, it.second, it.third) },
                "size" to cache.size,
                "entries" to cacheEntriesJson(cache),
            )
        }

        add(
            "replace_same_spot", 30.0, 300,
            listOf(Triple(baseLat, baseLng, "옛 이름"), Triple(baseLat + latOffset(10.0), baseLng, "새 이름")),
        )
        add(
            "sanitize", 30.0, 300,
            listOf(
                Triple(baseLat, baseLng, "  가\t나\n다\r라  "),
                Triple(baseLat + latOffset(200.0), baseLng, "   "),
                // 비분리 공백과 NEL 은 코틀린 trim() 이 **안** 자른다(판정 기록 4).
                Triple(baseLat + latOffset(400.0), baseLng, " 카페 "),
                Triple(baseLat + latOffset(600.0), baseLng, "NEL"),
            ),
        )
        add("overflow_drops_oldest", 30.0, 3, (0 until 5).map { Triple(baseLat + latOffset(it * 100.0), baseLng, "곳$it") })
        add("overflow_at_limit", 30.0, 300, (0 until 302).map { Triple(baseLat + latOffset(it * 100.0), baseLng, "많은 곳 $it") })

        check(sizes.getValue("overflow_drops_oldest") == 3 && sizes.getValue("replace_same_spot") == 1) {
            "상한·교체 케이스가 기대한 모양이 아니다 — 생성기가 그 갈래에 못 갔다"
        }
        return cases
    }

    private fun generatePlaceNameCacheDecode(): List<Map<String, Any?>> {
        val cases = mutableListOf<Map<String, Any?>>()

        fun add(name: String, text: String) {
            val cache = PlaceNameCache.decode(text)
            cases += linkedMapOf(
                "name" to name, "text" to text,
                "size" to cache.size, "entries" to cacheEntriesJson(cache),
            )
        }

        add("empty", "")
        add("one_line", "1.5,2.5\t좋은 줄")
        add(
            "broken_lines",
            listOf(
                "1.5,2.5\t좋은 줄",
                "탭이없다",
                "\t앞이비었다",
                "1.5\t칸이하나",
                "1.5,2.5,3.5\t칸이셋",
                "a,2.5\t위도가숫자아님",
                "1.5,b\t경도가숫자아님",
                "",
                "3.5,4.5\t또 좋은 줄",
                "5.5,6.5\t이름에\t탭이 들어 있다",
            ).joinToString("\n"),
        )
        add(
            "round_trip_from_encode",
            PlaceNameCache().also {
                it.put(37.5665, 126.9780, "집")
                it.put(37.5700, 126.9800, "학교 앞")
            }.encode(),
        )
        return cases
    }
```

- [ ] **Step 8: 골든을 뽑는다**

```bash
cd /Users/com/work/KidCare
export PATH="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:$PATH"
./gradlew testDebugUnitTest --tests "com.kidcare.family.logic.GoldenFileWriterTest"
git status --short ios/KidCareTests/golden/     # 새 파일 둘만
python3 -c "
import json
for n in ['geofenceEvaluator','placeNameCache']:
    d = json.load(open('ios/KidCareTests/golden/%s.json' % n))
    print(n, len(d) if isinstance(d, list) else {k: len(v) for k, v in d.items()})
"
git diff --stat 4bda965..HEAD -- app/src/main firestore.rules gradlew   # 비어 있어야 한다
```

Expected: `geofenceEvaluator` 65 케이스, `placeNameCache` find 6 / put 4 / decode 4. `check(...)` 가 죽으면 **골든을 고치지 말고 생성기를 고친다.**

- [ ] **Step 9: Swift 대조 테스트를 더한다**

`ios/KidCareTests/GoldenComparisonTests.swift` 의 `골든_리소스가_번들에_있다` 안에 아래를 더하고, 테스트 이름의 개수를 지금 golden 파일 수로 고친다:

```swift
        let geofenceEvaluator = try readArray("geofenceEvaluator")
        #expect(geofenceEvaluator.count >= 55, "geofenceEvaluator 케이스가 너무 적다")

        let placeNameCache = try readObject("placeNameCache")
        #expect((placeNameCache["find"] as? [[String: Any]])?.count ?? 0 >= 5, "placeNameCache.find 케이스가 너무 적다")
        #expect((placeNameCache["put"] as? [[String: Any]])?.count ?? 0 >= 4, "placeNameCache.put 케이스가 너무 적다")
        #expect((placeNameCache["decode"] as? [[String: Any]])?.count ?? 0 >= 4, "placeNameCache.decode 케이스가 너무 적다")
```

그리고 파일 끝에 대조 둘을 더한다:

```swift
    // ==================================================================
    // 6. GeofenceEvaluator — 히스테리시스·5분 중복 억제·정확도 문턱
    // ==================================================================

    private func place(_ raw: [String: Any]) -> Place {
        Place(id: string(raw["id"]), name: string(raw["name"]),
              lat: double(raw["lat"]), lng: double(raw["lng"]),
              radiusMeters: double(raw["radiusMeters"]),
              notifyEnter: bool(raw["notifyEnter"]), notifyExit: bool(raw["notifyExit"]))
    }

    private func placeState(_ raw: [String: Any]) -> PlaceState {
        PlaceState(placeId: string(raw["placeId"]), inside: bool(raw["inside"]), lastEventAt: int64(raw["lastEventAt"]))
    }

    @Test("장소 도착·이탈 판정이 안드로이드와 같다 (반경 경계·이탈 여유 50m·5분 억제·정확도 100m)")
    func 지오펜스_판정_대조() throws {
        for 사례 in try readArray("geofenceEvaluator") {
            let 이름 = string(사례["name"])
            let places = try #require(사례["places"] as? [[String: Any]]).map(place)
            let states = try #require(사례["states"] as? [[String: Any]]).map(placeState)
            let raw = try #require(사례["fix"] as? [String: Any])
            let fix = Fix(lat: double(raw["lat"]), lng: double(raw["lng"]),
                          accuracy: double(raw["accuracy"]), at: int64(raw["at"]))

            let (hits, next) = GeofenceEvaluator.evaluate(places: places, states: states, fix: fix)

            let 기대_hits = try #require(사례["hits"] as? [[String: Any]]).map {
                GeofenceHit(placeId: string($0["placeId"]), placeName: string($0["placeName"]),
                            entering: bool($0["entering"]), at: int64($0["at"]))
            }
            let 기대_states = try #require(사례["nextStates"] as? [[String: Any]]).map(placeState)
            #expect(hits == 기대_hits, "\(이름): 알림이 다르다")
            #expect(next == 기대_states, "\(이름): 다음 상태가 다르다")
        }
    }

    // ==================================================================
    // 7. PlaceNameCache — 30m 경계·300개 상한·망가진 줄
    // ==================================================================

    /// 코틀린이 적어 둔 항목 목록과 스위프트 캐시가 같은지 본다. **encode 문자열이 아니라 값으로**
    /// 비교한다 — 두 언어의 Double 문자열 표현이 다를 수 있다(설계서 §4.5 의 규율).
    private func 항목_비교(_ cache: PlaceNameCache, _ expected: [[Any]], _ 이름: String) {
        let actual = cache.encode()
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line -> (Double, Double, String) in
                let tab = line.firstIndex(of: "\t")!
                let coordinates = line[line.startIndex..<tab].split(separator: ",")
                return (Double(coordinates[0])!, Double(coordinates[1])!, String(line[line.index(after: tab)...]))
            }
        #expect(actual.count == expected.count, "\(이름): 항목 수가 다르다")
        for (i, 기대) in expected.enumerated() where i < actual.count {
            #expect(actual[i].0 == (기대[0] as! NSNumber).doubleValue, "\(이름)[\(i)] 위도")
            #expect(actual[i].1 == (기대[1] as! NSNumber).doubleValue, "\(이름)[\(i)] 경도")
            #expect(actual[i].2 == (기대[2] as! String), "\(이름)[\(i)] 이름")
        }
    }

    @Test("장소 이름 캐시가 안드로이드와 같다 (30m 경계·교체·300개 상한·망가진 줄)")
    func 장소이름_캐시_대조() throws {
        let payload = try readObject("placeNameCache")

        for 사례 in try #require(payload["find"] as? [[String: Any]]) {
            let 이름 = string(사례["name"])
            var cache = PlaceNameCache()
            for put in try #require(사례["puts"] as? [[Any]]) {
                cache.put(lat: (put[0] as! NSNumber).doubleValue,
                          lng: (put[1] as! NSNumber).doubleValue, name: put[2] as! String)
            }
            #expect(cache.find(lat: double(사례["lat"]), lng: double(사례["lng"])) == 사례["found"] as? String, "find \(이름)")
        }

        for 사례 in try #require(payload["put"] as? [[String: Any]]) {
            let 이름 = string(사례["name"])
            var cache = PlaceNameCache(matchRadiusMeters: double(사례["matchRadiusMeters"]), maxEntries: int(사례["maxEntries"]))
            for put in try #require(사례["puts"] as? [[Any]]) {
                cache.put(lat: (put[0] as! NSNumber).doubleValue,
                          lng: (put[1] as! NSNumber).doubleValue, name: put[2] as! String)
            }
            #expect(cache.size == int(사례["size"]), "put \(이름): 개수")
            항목_비교(cache, try #require(사례["entries"] as? [[Any]]), "put \(이름)")
        }

        for 사례 in try #require(payload["decode"] as? [[String: Any]]) {
            let 이름 = string(사례["name"])
            let cache = PlaceNameCache.decode(string(사례["text"]))
            #expect(cache.size == int(사례["size"]), "decode \(이름): 개수")
            항목_비교(cache, try #require(사례["entries"] as? [[Any]]), "decode \(이름)")
        }
    }
```

- [ ] **Step 10: 전부 돌린다**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: PASS. 순증 25개(포팅 23 + 대조 2).

- [ ] **Step 11: 커밋** — 공통 절차 B 를 돈 뒤:

```bash
git add ios/KidCare/Logic/GeofenceEvaluator.swift ios/KidCare/Logic/PlaceNameCache.swift \
        ios/KidCare/Logic/GeofenceRegionSelection.swift \
        ios/KidCareTests/GeofenceEvaluatorTests.swift ios/KidCareTests/PlaceNameCacheTests.swift \
        ios/KidCareTests/GeofenceRegionSelectionTests.swift ios/KidCareTests/GoldenComparisonTests.swift \
        ios/KidCareTests/golden/geofenceEvaluator.json ios/KidCareTests/golden/placeNameCache.json \
        ios/project.yml app/src/test/java/com/kidcare/family/logic/GoldenFileWriterTest.kt
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" \
    commit -m "iOS 아이 2단계 Task 1: 장소 판정·이름 캐시·20개 고르기를 옮기고 골든 둘로 대조한다"
```

---

### Task 2: 장소를 걸고, 판정하고, 사건을 쓴다

**끝나면 아이 세션이 규칙을 통과하는 `events/` 문서를 쓰고, 부모가 장소를 고치면 아이 폰이 상시 구독으로 받아 지역을 다시 걸며, 앱이 죽었다 살아나도 "안에 있었다"가 남는다.** 에뮬레이터 테스트가 거부 경로 넷을 함께 고정한다.

**Files:**
- Create: `ios/KidCare/Child/PlaceStateStore.swift`, `ios/KidCare/Child/PlaceWatcher.swift`
- Modify: `ios/KidCare/Core/Documents.swift`(`PlaceDoc.asPlace`, `EventDoc.firestoreData`), `ios/KidCare/Core/EventRepository.swift`(`add`), `ios/KidCare/Core/PlaceRepository.swift`(주석), `ios/KidCare/Child/LocationCollector.swift`(1단계), `ios/KidCare/Child/TrackingCoordinator.swift`(1단계)
- Test: `ios/KidCareTests/PlaceStateStoreTests.swift`, `PlaceWatcherTests.swift`, `ChildEventWriteTests.swift`(에뮬레이터), `EventDocumentsTests.swift`(수정), `TrackingCoordinatorTests.swift`(1단계 파일에 추가)

**Interfaces:**
- Consumes: Task 1 의 `Place`·`PlaceState`·`GeofenceEvaluator`·`GeofenceRegionSelection`; 1단계의 `TrackingCoordinator`·`LocationCollector`·`Fix`
- Produces: `PlaceStateStore`, `PlaceWatcher(stateStore:monitor:addEvent:)`, `RegionMonitor` 프로토콜, `EventRepository.add(familyId:doc:)`, `EventDoc.firestoreData`, `PlaceDoc.asPlace` — Task 3·4 와 3단계가 쓴다

**정본:** `child/PlaceWatcher.kt`(전체), `child/PlaceStateStore.kt`(전체), `child/PlaceGeofenceReceiver.kt:13-49`, `core/EventRepository.kt:18-58`, `core/PlaceRepository.kt:102-114`, `firestore.rules:306-318`.

- [ ] **Step 1: 저장소 테스트를 먼저 쓴다(빨강)**

`ios/KidCareTests/PlaceStateStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import KidCare

/// 정본은 `child/PlaceStateStore.kt`. 값 형식(줄바꿈 레코드·탭 칸·망가진 줄 버리기)이 안드로이드와
/// 글자까지 같아야 한다 — 같은 아이가 폰을 바꿔도 읽히기를 바라는 값은 아니지만, 형식이 갈리면
/// "왜 한쪽만 되지"를 대조할 기준이 사라진다.
@MainActor
struct PlaceStateStoreTests {

    private func 빈_저장소() -> PlaceStateStore {
        PlaceStateStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
    }

    @Test("아무것도 없으면 빈 목록이다 — 예외로 수집을 죽이지 않는다")
    func 처음() { #expect(빈_저장소().states.isEmpty) }

    @Test("쓴 그대로 다시 읽힌다")
    func 왕복() {
        let store = 빈_저장소()
        let 값 = [PlaceState(placeId: "a", inside: true, lastEventAt: 1_700_000_000_000),
                  PlaceState(placeId: "b", inside: false, lastEventAt: 0)]
        store.states = 값
        #expect(store.states == 값)
    }

    @Test("줄바꿈 레코드·탭 칸·1/0 — 안드로이드와 글자까지 같다 (:50-55)")
    func 형식() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let store = PlaceStateStore(defaults: defaults)
        store.states = [PlaceState(placeId: "a", inside: true, lastEventAt: 5),
                        PlaceState(placeId: "b", inside: false, lastEventAt: 0)]
        #expect(defaults.string(forKey: PlaceStateStore.key) == "a\t1\t5\nb\t0\t0")
    }

    @Test("망가진 줄은 그 줄만 버린다 — 저장소가 깨졌다고 서비스를 죽이지 않는다 (:57-64)")
    func 망가진_줄() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        defaults.set("a\t1\t5\n칸이하나\n\t1\t5\nb\tx\t아닌숫자\nc\t0\t7\nd\t1\t2\t3", forKey: PlaceStateStore.key)
        let store = PlaceStateStore(defaults: defaults)
        #expect(store.states == [PlaceState(placeId: "a", inside: true, lastEventAt: 5),
                                 PlaceState(placeId: "c", inside: false, lastEventAt: 7)])
    }

    @Test("빈 목록을 쓰면 빈 목록으로 읽힌다")
    func 빈_목록() {
        let store = 빈_저장소()
        store.states = [PlaceState(placeId: "a", inside: true, lastEventAt: 5)]
        store.states = []
        #expect(store.states.isEmpty)
    }
}
```

`ios/KidCareTests/PlaceWatcherTests.swift`:

```swift
import Foundation
import Testing
@testable import KidCare

/// 정본은 `child/PlaceWatcher.kt`. CoreLocation 과 Firestore 는 프로토콜·클로저로 가려 두고,
/// **순서**(상태를 먼저 저장하고 그다음에 이벤트를 쓴다)와 빈 목록 보호를 고정한다.
@MainActor
struct PlaceWatcherTests {

    final class 가짜_감시자: RegionMonitor {
        private(set) var 마지막_등록: [Place] = []
        private(set) var 등록_횟수 = 0
        private(set) var 한_점_부탁 = 0
        func replaceMonitoredRegions(_ places: [Place]) {
            마지막_등록 = places
            등록_횟수 += 1
        }
        func requestOneShotFix() { 한_점_부탁 += 1 }
    }

    /// 이벤트 쓰기가 실패하는 상황을 만든다 — 오프라인·권한 거부가 흔한 상태다.
    struct 쓰기실패: Error {}

    private static let 위도1도 = Double.pi / 180.0 * 6_371_000.0
    private func 북쪽(_ meters: Double) -> Double { 37.5665 + meters / Self.위도1도 }
    private func 점(_ meters: Double, accuracy: Double = 10, at: Int64 = 1_000_000) -> Fix {
        Fix(lat: 북쪽(meters), lng: 126.9780, accuracy: accuracy, at: at)
    }
    private func 장소들(_ count: Int) -> [PlaceDoc] {
        (0..<count).map { PlaceDoc(id: "id\($0)", name: "곳\($0)", lat: 37.5665, lng: 126.9780, radiusMeters: 100) }
    }

    private func 만든다(실패: Bool = false) -> (PlaceWatcher, 가짜_감시자, PlaceStateStore, 기록) {
        let store = PlaceStateStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let monitor = 가짜_감시자()
        let 적힌것 = 기록()
        let watcher = PlaceWatcher(stateStore: store, monitor: monitor) { _, doc in
            적힌것.더한다(doc)
            if 실패 { throw 쓰기실패() }
        }
        return (watcher, monitor, store, 적힌것)
    }

    final class 기록 {
        private(set) var docs: [EventDoc] = []
        func 더한다(_ doc: EventDoc) { docs.append(doc) }
    }

    @Test("장소를 받으면 이름순 20개만 OS 에 건다 (:154-175, GeofenceRegionSelection)")
    func 스물만_건다() {
        let (watcher, monitor, _, _) = 만든다()
        watcher.apply(placeDocs: 장소들(25))
        #expect(monitor.마지막_등록.count == 20)
        #expect(watcher.places.count == 25, "판정은 스물다섯 곳 전부로 한다 — OS 상한은 등록에만 걸린다")
    }

    @Test("장소를 한 번도 못 읽었으면 그대로 돌아간다 — 저장된 상태를 지우지 않는다 (:105-116)")
    func 빈_목록_보호() async throws {
        let (watcher, _, store, 적힌것) = 만든다()
        store.states = [PlaceState(placeId: "id0", inside: true, lastEventAt: 5)]
        try await watcher.onFix(familyId: "f", childUid: "c", fix: 점(1_000))
        #expect(적힌것.docs.isEmpty)
        #expect(store.states.count == 1, "빈 목록으로 판정하면 아이가 이미 안에 있던 곳이 전부 '처음 보는 장소'가 된다")
    }

    @Test("도착하면 place_enter 를 쓴다 — at 은 점의 시각이고 childUid 는 지금 로그인한 uid 다 (:125-139)")
    func 도착_이벤트() async throws {
        let (watcher, _, store, 적힌것) = 만든다()
        watcher.apply(placeDocs: [PlaceDoc(id: "id0", name: "학교", lat: 37.5665, lng: 126.9780, radiusMeters: 100)])
        store.states = [PlaceState(placeId: "id0", inside: false, lastEventAt: 0)]
        try await watcher.onFix(familyId: "f", childUid: "아이uid", fix: 점(0, at: 777))
        #expect(적힌것.docs.count == 1)
        let doc = try #require(적힌것.docs.first)
        #expect(doc.type == EventType.placeEnter)
        #expect(doc.at == 777, "콜백이 온 순간이 아니라 위치가 잡힌 순간이다(PlaceGeofenceReceiver.kt:43-45)")
        #expect(doc.childUid == "아이uid")
        #expect(doc.placeName == "학교")
        #expect(doc.read == false, "규칙이 read == false 를 요구한다(firestore.rules:308)")
    }

    @Test("상태를 **먼저** 저장한다 — 이벤트 쓰기가 실패해도 '안에 있다'는 남는다 (:120-123)")
    func 상태가_먼저다() async {
        let (watcher, _, store, _) = 만든다(실패: true)
        watcher.apply(placeDocs: [PlaceDoc(id: "id0", name: "학교", lat: 37.5665, lng: 126.9780, radiusMeters: 100)])
        store.states = [PlaceState(placeId: "id0", inside: false, lastEventAt: 0)]
        await #expect(throws: 쓰기실패.self) {
            try await watcher.onFix(familyId: "f", childUid: "c", fix: 점(0))
        }
        #expect(store.states == [PlaceState(placeId: "id0", inside: true, lastEventAt: 1_000_000)],
                "반대 순서면 오프라인일 때 같은 도착이 점마다 다시 잡혀 연결이 돌아올 때 여러 번 올라간다")
    }

    @Test("못 믿는 점에서는 저장도 쓰기도 없다 (:78 의 앞단)")
    func 못_믿는_점() async throws {
        let (watcher, _, store, 적힌것) = 만든다()
        watcher.apply(placeDocs: [PlaceDoc(id: "id0", name: "학교", lat: 37.5665, lng: 126.9780, radiusMeters: 100)])
        store.states = [PlaceState(placeId: "id0", inside: false, lastEventAt: 0)]
        try await watcher.onFix(familyId: "f", childUid: "c", fix: 점(0, accuracy: 150))
        #expect(적힌것.docs.isEmpty)
        #expect(store.states == [PlaceState(placeId: "id0", inside: false, lastEventAt: 0)])
    }

    @Test("한 점에서 사건이 둘 이상 나올 수 있다 — 둘 다 쓴다 (known-issues 21번)")
    func 두_사건() async throws {
        let (watcher, _, store, 적힌것) = 만든다()
        watcher.apply(placeDocs: [
            PlaceDoc(id: "집", name: "집", lat: 37.5665, lng: 126.9780, radiusMeters: 100),
            PlaceDoc(id: "놀이터", name: "놀이터", lat: 북쪽(50), lng: 126.9780, radiusMeters: 100),
        ])
        store.states = [PlaceState(placeId: "집", inside: false, lastEventAt: 0),
                        PlaceState(placeId: "놀이터", inside: false, lastEventAt: 0)]
        try await watcher.onFix(familyId: "f", childUid: "c", fix: 점(25))
        #expect(적힌것.docs.count == 2)
    }

    @Test("모드 판정용 안/밖은 50m 게이트를 쓰고 이탈 여유를 그대로 적용한다 (:77-100)")
    func 아는_장소_안인가() {
        let (watcher, _, store, _) = 만든다()
        #expect(watcher.isInsideKnownPlace(점(0)) == false, "장소가 없으면 false 다 — 판단 보류(nil)가 아니다")
        watcher.apply(placeDocs: [PlaceDoc(id: "id0", name: "학교", lat: 37.5665, lng: 126.9780, radiusMeters: 100)])
        #expect(watcher.isInsideKnownPlace(점(0, accuracy: 50.5)) == nil, "평상시 문턱(50m)을 넘는 점에서는 판단을 보류한다")
        #expect(watcher.isInsideKnownPlace(점(0)) == true)
        #expect(watcher.isInsideKnownPlace(점(120)) == false)
        store.states = [PlaceState(placeId: "id0", inside: true, lastEventAt: 0)]
        #expect(watcher.isInsideKnownPlace(점(120)) == true, "이미 안이면 반경 + 여유 50m 까지 안으로 본다")
    }

    @Test("지역 경계 콜백은 이벤트를 안 쓰고 좌표 한 점만 부탁한다 (설계서 §7.1, PlaceGeofenceReceiver.kt:13-19)")
    func 지역_콜백은_신호일_뿐() {
        let (watcher, monitor, _, 적힌것) = 만든다()
        watcher.apply(placeDocs: 장소들(1))
        watcher.regionCrossed(placeId: "id0")
        #expect(적힌것.docs.isEmpty, "그 콜백에는 히스테리시스도 중복 억제도 정확도 문턱도 없다")
        #expect(monitor.한_점_부탁 == 1)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/PlaceStateStoreTests -only-testing:KidCareTests/PlaceWatcherTests`
Expected: 컴파일 실패.

- [ ] **Step 3: `Child/PlaceStateStore.swift`**

```swift
import Foundation

/// "이 장소 안에 있었다"는 사실을 프로세스 밖에 남긴다. 정본 `child/PlaceStateStore.kt`.
///
/// ## 왜 메모리에 두면 안 되나 (`:9-20`)
///
/// `GeofenceEvaluator` 는 **직전 상태와 지금이 다를 때만** 알린다. 그 직전 상태를 메모리에만 두면
/// 아침에 학교에 도착한 사실이 사라지고, 오후에 앱이 되살아났을 때 아이는 이미 학교 밖이라
/// `inside=false` 로 심긴다 — **그날의 하교 이탈 알림이 영영 안 나간다.** 침묵이 이 앱에서 제일
/// 나쁜 고장이다. 아이폰에서는 이 위험이 더 크다: 메모리 압박으로 앱이 죽는 일이 흔하고,
/// 지역 감시가 되살려 주는 그 순간이 곧 판정 순간이다(설계서 §7.4).
///
/// ## 저장 형식 (`:22-28`)
///
/// 값이 세 개짜리 줄 목록이라 JSON 파서를 끌어올 것도 없이 줄바꿈·탭으로 나눈다. `placeId` 는
/// Firestore 자동 ID(영숫자)라 두 구분자가 들어갈 수 없다. 그래도 읽는 쪽은 칸 수와 숫자 변환을
/// 확인하고 이상한 줄은 통째로 버린다 — 저장소가 깨졌을 때 예외로 죽는 것보다 그 장소만
/// "처음 보는 장소"로 되돌리는 쪽이 안전하다.
///
/// `UserDefaults` 는 안드로이드 SharedPreferences 자리다(설계서 §7.4). 코틀린이 `apply()` 대신
/// `commit()`(동기)을 쓴 이유(`:34-38`)는 여기서 저절로 지켜진다 — `set` 은 그 자리에서 메모리에
/// 반영되고 디스크 플러시는 프로세스가 죽어도 이어진다. `synchronize()` 는 부르지 않는다.
@MainActor
final class PlaceStateStore {

    static let key = "kidcare_places.states"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var states: [PlaceState] {
        get {
            (defaults.string(forKey: Self.key) ?? "")
                .components(separatedBy: Self.recordSeparator)
                .compactMap(Self.decode)
        }
        set {
            defaults.set(
                newValue.map(Self.encode).joined(separator: Self.recordSeparator),
                forKey: Self.key)
        }
    }

    private static let recordSeparator = "\n"
    private static let fieldSeparator = "\t"

    private static func encode(_ state: PlaceState) -> String {
        [state.placeId, state.inside ? "1" : "0", String(state.lastEventAt)]
            .joined(separator: fieldSeparator)
    }

    private static func decode(_ row: String) -> PlaceState? {
        let parts = row.components(separatedBy: fieldSeparator)
        // 칸 수·숫자 변환을 확인하고 이상한 줄은 통째로 버린다(`:58-63`).
        guard parts.count == 3, !parts[0].isEmpty, let lastEventAt = Int64(parts[2]) else { return nil }
        return PlaceState(placeId: parts[0], inside: parts[1] == "1", lastEventAt: lastEventAt)
    }
}
```

- [ ] **Step 4: `Core/` 세 곳**

`ios/KidCare/Core/Documents.swift` 의 `PlaceDoc` 바로 아래에 더한다:

```swift
extension PlaceDoc {
    /// `PlaceDoc`(Firestore 문서 표현) → `Place`(판정 모델). 정본 `core/PlaceRepository.kt:102-114`.
    /// 변환을 여러 곳에 흩어 놓으면 한쪽만 고치고 잊는다 — `ScheduleDoc.asRule` 과 같은 자리·같은 이유다.
    var asPlace: Place {
        Place(id: id, name: name, lat: lat, lng: lng, radiusMeters: radiusMeters,
              notifyEnter: notifyEnter, notifyExit: notifyExit)
    }
}
```

`EventDoc` 아래에 더한다(지금은 `firestoreData` 가 **일부러** 없다는 주석이 달려 있다 — 그 문단을 "보호자는 `read` 한 필드만 쓴다. **아이 폰만** 이 문서를 만든다(설계서 §1)"로 고친다):

```swift
extension EventDoc {
    /// 아이 폰이 사건 하나를 만들 때 싣는 본문. 정본 `core/EventRepository.kt:53-58`
    /// (`ref.set(doc.copy(id = ""))` — @Exclude 가 없어 본문에 `"id": ""` 가 실린다).
    ///
    /// ## 규칙과의 계약 셋 (`firestore.rules:306-310`)
    /// 하나라도 어기면 **쓰기가 조용히 거부되고 부모는 그 사건이 없었던 것으로 읽는다**(`:18-27`).
    /// 1. `childUid` 는 반드시 지금 로그인한 uid — 부르는 쪽이 넣는다.
    /// 2. `read` 는 반드시 false. **그래서 여기서는 `self.read` 를 아예 안 읽는다**(`:24`).
    /// 3. `at` 은 **밀리초 정수**이고 서버 시각 기준 과거 7일 ~ 미래 1시간 안. `Timestamp` 로 쓰면 안 된다.
    ///    (코틀린 주석 `:25`·`PlaceWatcher.kt:131` 은 아직 "24시간"이라고 적혀 있다 — 규칙이 맞다.)
    var firestoreData: [String: Any] {
        [
            "id": "",
            "type": type,
            "at": at,
            "childUid": childUid,
            "placeName": placeName,
            "detail": detail,
            "read": false,
        ]
    }
}
```

`ios/KidCare/Core/EventRepository.swift` 의 타입 주석 첫 문단을 고치고(`만드는 쪽(add)은 아이 폰 전용이라 옮기지 않는다` → `만드는 쪽(add)은 아이 폰이, 읽는 쪽과 읽음 표시는 보호자가 쓴다. 한 파일에 둔 이유는 규칙 계약이 세 함수에 걸쳐 있기 때문이다(:11-27)`), `markRead` 위에 더한다:

```swift
    /// 사건 하나를 남긴다. 만들어진 문서 ID 를 돌려준다. 정본 `:52-58`.
    ///
    /// **실패를 삼키지 않는다.** 부르는 쪽(`PlaceWatcher.onFix` → `TrackingCoordinator`)이 로그로
    /// 남기고 다음 위치 점에서 다시 시도한다 — 이벤트 하나를 못 썼다고 위치 수집이 멈추면 안 된다
    /// (`PlaceWatcher.kt:110-112`). 오프라인 재시도는 Firestore SDK 의 큐가 이미 한다(설계서 §6.5).
    @discardableResult
    static func add(familyId: String, doc: EventDoc) async throws -> String {
        let ref = events(familyId).document()
        // id 는 문서 ID 로만 쓴다(`:55`, PlaceRepository.savePlace 와 같은 규율).
        try await ref.setData(doc.firestoreData)
        return ref.documentID
    }
```

`ios/KidCare/Core/PlaceRepository.swift` 의 타입 주석 둘째 문단을 고친다(**코드 변화 없음**):

```swift
/// 보호자 화면과 **아이 폰**이 같은 `observePlaces` 를 쓴다. 아이 폰은 자기 uid 로 상시 구독한다
/// (설계서 §7.3): `sync_rules` 명령을 못 받으므로 부모가 장소를 고친 것을 알 다른 길이 없고, 이게
/// 없으면 **지운 장소의 알림이 영영 계속 울린다.** 1회 읽기용 함수를 따로 두지 않는 이유는 구독의
/// 첫 스냅샷이 곧 그 1회 읽기라 두 벌이 되기 때문이다(설계서 §3.3). 읽기 비용은 장소가 바뀔 때만
/// 든다(known-issues 12번 4항). 쓰기는 보호자만 허용된다(firestore.rules:216-222).
```

- [ ] **Step 5: `Child/PlaceWatcher.swift`**

```swift
import Foundation
import os

/// OS 지역 감시를 거는 쪽. 실제 구현은 `LocationCollector` 가 갖는다 — `PlaceWatcher` 가
/// `CLLocationManager` 를 직접 만지면 테스트에서 그 매니저를 세울 수 없고, 매니저는 앱이 사는 동안
/// 하나여야 한다(설계서 §5.2).
@MainActor
protocol RegionMonitor: AnyObject {
    /// **전부 지우고 다시 건다**(`PlaceWatcher.kt:142-152`). 부모가 지운 장소의 전환이 계속
    /// 올라오는 것을 막는다. 개별 삭제로 맞추려면 "직전에 무엇을 걸었는지"를 따로 기억해야 하는데,
    /// 스무 개짜리 목록을 통째로 다시 거는 비용이 그 기억을 관리하는 비용보다 싸다.
    func replaceMonitoredRegions(_ places: [Place])

    /// 지금 좌표 한 점을 부탁한다. iOS 의 지역 콜백은 좌표를 안 주기 때문이다(설계서 §7.1).
    func requestOneShotFix()
}

/// 아이 폰의 장소 판정. `GeofenceEvaluator` 를 아이폰에 붙이는 껍데기다. 정본 `child/PlaceWatcher.kt`.
///
/// ## OS 지역 감시는 "알림"이 아니라 "판정해 보라는 신호"다 (`:22-35`)
///
/// 전환 콜백에서 곧장 `events/` 에 적으면 히스테리시스(반경 + 50m)도, 5분 중복 억제도, 정확도
/// 문턱도 통째로 건너뛴다 — 경계에 앉은 아이 하나 때문에 부모 폰이 하루 종일 운다. 아이폰에서는
/// 이유가 하나 더 있다: 그 콜백에는 **좌표가 아예 안 실려 온다.** 그래서 `regionCrossed` 는 좌표
/// 한 점을 부탁하기만 하고, 알릴지 말지는 언제나 판정기가 정한다.
///
/// OS 지역 감시를 그래도 거는 이유는 **앱이 죽어 있어도 되살리기 때문**이다(설계서 §7.4).
/// 되살아나면 장소를 읽고, 상태 저장소를 읽고, 판정하고, 필요하면 이벤트를 쓰고, 즉시 업로드한다.
@MainActor
final class PlaceWatcher {

    private let stateStore: PlaceStateStore
    private let monitor: RegionMonitor
    private let addEvent: (String, EventDoc) async throws -> Void
    private let logger = Logger(subsystem: "com.kidcare.family", category: "PlaceWatcher")

    /// 마지막으로 읽어 온 장소 목록. 구독이 채우고 `onFix` 가 읽는다.
    /// 코틀린은 두 코루틴이 부딪혀 `@Volatile` 이었는데(`:46-52`), 여기서는 둘 다 `@MainActor` 라
    /// 잠금이 필요 없다 — `TrailBuffer` 가 스레드를 하나로 유지하는 것과 같은 선택이다(설계서 §3.6).
    private(set) var places: [Place] = []

    init(stateStore: PlaceStateStore,
         monitor: RegionMonitor,
         addEvent: @escaping (String, EventDoc) async throws -> Void = { familyId, doc in
             try await EventRepository.add(familyId: familyId, doc: doc)
         }) {
        self.stateStore = stateStore
        self.monitor = monitor
        self.addEvent = addEvent
    }

    /// 장소 목록을 갈아 끼우고 OS 지역을 다시 건다(`:63-67`). 부르는 곳은
    /// `PlaceRepository.observePlaces` 의 스냅샷 하나뿐이다 — 앱이 (다시) 뜰 때의 첫 스냅샷이
    /// 안드로이드의 `refresh` 자리이고, 그 뒤의 스냅샷이 `sync_rules` 자리다(설계서 §7.3).
    func apply(placeDocs: [PlaceDoc]) {
        places = placeDocs.map(\.asPlace)
        let report = GeofenceRegionSelection.chooseWithReport(places)
        if report.dropped > 0 {
            // 조용히 실패하면 "왜 도착 알림이 안 오지"를 알아낼 방법이 없다(`:172-174`).
            logger.warning("장소 \(self.places.count)개 중 \(report.chosen.count)개만 지역으로 걸었다(상한 \(GeofenceRegionSelection.maxRegions) · 반경 0 제외)")
        }
        monitor.replaceMonitoredRegions(report.chosen)
    }

    /// 현재 좌표가 부모가 등록한 장소 안인지 빠르게 확인한다(`:69-100`).
    ///
    /// 이 값은 알림 판정이 아니라 **수집 주기를 낮추는 데만** 쓴다(설계서 §5.1 의 '등록 장소 머무름'
    /// 갈래). 정확도가 나쁜 점으로 모드를 바꾸면 실제로 학교를 나갔는데도 1분 주기에 머물 수 있으므로
    /// 평상시 문턱(50m)을 넘는 점에서는 판단을 보류한다(nil). 이미 안으로 판정된 장소에는 이탈 여유를
    /// 그대로 적용해 경계의 흔들림으로 주기가 출렁이지 않게 한다.
    func isInsideKnownPlace(_ fix: Fix) -> Bool? {
        guard fix.lat.isFinite, fix.lng.isFinite,
              (-90.0...90.0).contains(fix.lat), (-180.0...180.0).contains(fix.lng),
              fix.accuracy.isFinite, fix.accuracy >= 0,
              fix.accuracy <= LocationFilter.maxAccuracyMeters else { return nil }

        if places.isEmpty { return false }
        let statesById = Dictionary(stateStore.states.map { ($0.placeId, $0) }, uniquingKeysWith: { _, last in last })
        return places.contains { place in
            let distance = LocationFilter.distanceMeters(
                Fix(lat: place.lat, lng: place.lng, accuracy: 0, at: 0), fix)
            let margin = statesById[place.id]?.inside == true ? GeofenceEvaluator.exitMarginMeters : 0
            return distance <= place.radiusMeters + margin
        }
    }

    /// 위치 한 점으로 판정하고, 알릴 것이 나오면 `events/` 에 적는다(`:102-140`).
    ///
    /// 장소를 아직 한 번도 못 읽었거나 정말 하나도 없으면 그대로 돌아간다. **저장된 상태를 지우지
    /// 않는 것이 중요하다** — 여기서 빈 목록으로 판정하면 판정기가 "지금 있는 장소만 남긴다" 규칙에
    /// 따라 상태를 통째로 비우고, 잠시 뒤 장소를 읽어오면 아이가 이미 안에 있는 곳들이 전부
    /// "처음 보는 장소"가 된다(`:105-108`).
    ///
    /// 실패는 여기서 삼키지 않고 위로 던진다(`:110-112`).
    func onFix(familyId: String, childUid: String, fix: Fix) async throws {
        let known = places
        if known.isEmpty { return }

        let previous = stateStore.states
        let (hits, next) = GeofenceEvaluator.evaluate(places: known, states: previous, fix: fix)
        // 상태를 **먼저** 저장한다(`:120-123`). 이벤트 쓰기가 실패해 예외로 빠져나가더라도 "안에
        // 있다"는 사실은 남아야 한다. 반대 순서면 오프라인일 때 같은 전환이 위치 점마다 다시 잡혀
        // 연결이 돌아오는 순간 같은 도착이 여러 번 올라간다.
        if next != previous { stateStore.states = next }

        for hit in hits {
            try await addEvent(familyId, EventDoc(
                id: "",
                type: hit.entering ? EventType.placeEnter : EventType.placeExit,
                // 폰 시계로 잰 값이다(위치가 잡힌 순간). 규칙이 서버 시각과 대조하므로 아이 폰 시계가
                // 한 시간 넘게 앞서 있으면 이 쓰기가 막힌다 — 그건 그 폰의 시계 문제이고, 여기서
                // "지금"으로 바꿔치기하면 일어난 시각을 지어내는 셈이 된다(`:130-133`).
                at: hit.at,
                childUid: childUid,
                placeName: hit.placeName))
        }
    }

    /// OS 가 "경계를 넘었다"고 앱을 깨웠다. **여기서 아무것도 판정하지 않는다**(설계서 §7.1).
    /// iOS 는 `CLRegion` 만 주고 좌표를 안 주므로 지금 좌표 한 점을 부탁하고 끝낸다. 그 점이 보통
    /// 점과 똑같은 길(`TrackingCoordinator.handle`)을 지나 `onFix` 로 온다. 못 얻으면 아무 판단도
    /// 하지 않는다 — 지어내지 않는다.
    func regionCrossed(placeId: String) {
        logger.info("지역 전환 신호: placeId=\(placeId, privacy: .public) — 좌표 한 점을 부탁한다")
        monitor.requestOneShotFix()
    }
}
```

- [ ] **Step 6: 1단계 두 파일에 배선한다**

`ios/KidCare/Child/LocationCollector.swift`(1단계 파일)에 더한다:

```swift
extension LocationCollector: RegionMonitor {

    /// `CLLocationManager.startMonitoring(for:)` 을 쓴다. iOS 17 이 `CLMonitor` 로 대체했다고
    /// 표시했지만, **앱이 죽어 있을 때 되살리는 계약이 문서로 굳어 있고 오래 검증된 쪽**이 이것이다
    /// (설계서 §7.3·§17 열린 질문 2). 이 설계 전체가 그 계약에 기대고 있으므로 확실한 쪽을 고른다.
    /// 4단계 실기기에서 `CLMonitor` 가 똑같이 되살리는 것을 확인하면 그때 옮긴다.
    func replaceMonitoredRegions(_ places: [Place]) {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        for place in places {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng),
                radius: place.radiusMeters,
                // 식별자가 곧 문서 ID 다 — 전환이 올 때 어느 장소인지 알아야 한다(`PlaceWatcher.kt:185-187`).
                identifier: place.id)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            // 안드로이드가 setInitialTrigger(0) 로 "등록하는 순간 이미 안에 있는 장소로 ENTER 를 쏘지
            // 않게" 한 것(:181)은 iOS 의 기본 동작이라 따로 할 일이 없다. 혹시 들어오더라도
            // GeofenceEvaluator 가 처음 보는 장소에는 조용히 상태만 심는다.
            manager.startMonitoring(for: region)
        }
    }

    /// 지역 전환 뒤 좌표 한 점. 결과는 `didUpdateLocations` 로 와서 보통 점과 같은 길을 지난다.
    func requestOneShotFix() {
        // 소프트웨어 간격 게이트가 이 한 점을 삼키면 OS 가 깨워 준 사건이 통째로 사라진다
        // (판정 기록 5). 그 게이트는 아이폰에만 있는 장치라 안드로이드에 대응이 없다.
        coordinator?.bypassIntervalGateOnce()
        manager.requestLocation()
    }
}

extension LocationCollector {
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        MainActor.assumeIsolated { placeWatcher?.regionCrossed(placeId: region.identifier) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        MainActor.assumeIsolated { placeWatcher?.regionCrossed(placeId: region.identifier) }
    }

    /// 지역 감시가 실패했다. 흔한 값이 권한 부족과 "위치가 꺼짐"이다 — 아이가 설정에서 언제든 끌 수
    /// 있으므로 예외가 아니라 흔한 상태다. 수집을 죽이지 않는다(`PlaceWatcher.kt:206-210`).
    /// 잃는 것은 앱이 죽어 있을 때의 반응뿐이고, 살아 있는 동안의 점마다 도는 판정은 그대로다.
    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        MainActor.assumeIsolated {
            logger.warning("지역 감시 실패: \(region?.identifier ?? "(없음)", privacy: .public) \(String(describing: error), privacy: .public)")
        }
    }
}
```

> `MainActor.assumeIsolated` 를 쓰는 근거: 매니저를 **메인에서 만들었으므로** 델리게이트 콜백이 그 런루프로 온다(설계서 §3.6, 안드로이드가 `context.mainLooper` 를 넘기는 것과 같은 선택). 1단계가 `didUpdateLocations` 에 이미 같은 방법을 썼으면 **그 모양을 그대로 따른다**(Pre-flight conflict table).

`ios/KidCare/Child/TrackingCoordinator.swift`(1단계 파일)에 셋을 더한다:

```swift
    /// 지역 전환으로 부탁한 한 점은 소프트웨어 간격 게이트를 건너뛴다(판정 기록 5).
    private var 게이트_한번_건너뛰기 = false

    func bypassIntervalGateOnce() { 게이트_한번_건너뛰기 = true }
```

`handle(fix:)` 의 간격 게이트 자리에서:

```swift
        if 게이트_한번_건너뛰기 {
            게이트_한번_건너뛰기 = false
        } else if fix.at - (마지막_처리_시각 ?? .min) < mode.intervalMillis {
            return
        }
```

그리고 §6.1 의 8번 자리(`LocationFilter.decide` 결과와 **무관하게** 부른다 — `:637-639`)에서 장소 판정을 부르고, 1단계가 비워 둔 자리를 채운다:

```swift
        // 8. 거절(정확도·순간이동)이 아니면 장소 판정. **7번 결과에 안 묶인다**(`:631-636`) —
        //    SKIP_TOO_CLOSE(직전 점에서 25m 못 감)도 넘긴다. 경계에서 몇 걸음 옮겨 안으로 들어간
        //    순간이 정확히 그 모양이다.
        if decision != .rejectInaccurate && decision != .rejectImpossible {
            do {
                try await placeWatcher.onFix(familyId: familyId, childUid: childUid, fix: fix)
                // §6.4 의 3번 규칙: events/ 에 무언가를 쓴 직후에는 1·2번을 무시하고 올린다.
                // 판정은 `uploader` 가 한다(1단계) — 여기서는 "사건이 있었다"만 알린다.
            } catch {
                // 이벤트 하나를 못 쓴 것 때문에 위치 수집이 멈추면 안 된다(`PlaceWatcher.kt:110-112`).
                logger.warning("장소 판정/이벤트 쓰기 실패 — 다음 점에서 다시 한다: \(String(describing: error), privacy: .public)")
            }
        }
```

장소 구독은 `TrackingCoordinator.start()` 에서 건다(떼는 길은 `stop()`):

```swift
        // 부모가 장소를 고친 것을 알 다른 길이 없다 — `sync_rules` 를 못 받기 때문이다(설계서 §7.3).
        // 이 구독이 없으면 지운 장소의 알림이 영영 계속 울린다.
        placesListener = PlaceRepository.observePlaces(
            familyId: familyId, childUid: childUid,
            onChange: { [weak self] docs, _ in
                Task { @MainActor in self?.placeWatcher.apply(placeDocs: docs) }
            },
            onError: { [weak self] error in
                self?.logger.warning("장소 구독 실패: \(String(describing: error), privacy: .public)")
            })
```

`TrackingCoordinatorTests`(1단계 파일)에 셋을 더한다:

```swift
    @Test("장소 판정은 LocationFilter 결과에 안 묶인다 — SKIP_TOO_CLOSE 도 넘어간다 (TrackingService.kt:631-639)")
    @Test("거절(정확도·순간이동)이면 장소 판정을 안 부른다 (:637)")
    @Test("지역 전환으로 부탁한 점은 간격 게이트를 한 번만 건너뛴다(판정 기록 5)")
```

- [ ] **Step 7: 에뮬레이터 테스트 — 규칙 계약 셋과 거부 경로**

`ios/KidCareTests/ChildEventWriteTests.swift`:

```swift
import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 아이 폰이 하는 쓰기가 규칙을 **실제로** 통과하는지 본다(설계서 §11.1·§12.3).
/// 규칙을 못 지킨 쓰기는 조용히 거부되므로 단위 테스트로는 절대 안 잡힌다.
///
/// 아이 세션의 **원시 쓰기**로 규칙을 태운다 — 기본 `FirebaseApp` 은 보호자이고 익명 계정은 uid 를
/// 고를 수 없어 아이로 만들 수 없다(판정 기록 13). 이 dict 가 `EventDoc.firestoreData` 와 같은지는
/// `EventDocumentsTests.아이가_싣는_본문` 이 본다.
@Suite(.serialized)
struct ChildEventWriteTests {

    init() async { await EmulatorHarness.start() }

    private func 가족과_자녀() async throws -> (familyId: String, child: EmulatorHarness.ChildSession) {
        let guardianUid = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: guardianUid)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)
        let child = try await EmulatorHarness.freshChildSession()
        try await EmulatorHarness.joinAsChild(child, familyId: familyId, joinCode: invite.code)
        return (familyId, child)
    }

    private func 지금() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private func 본문(_ childUid: String, at: Int64, read: Bool = false) -> [String: Any] {
        ["id": "", "type": EventType.placeEnter, "at": at,
         "childUid": childUid, "placeName": "학교", "detail": "", "read": read]
    }

    private func 쓴다(_ child: EmulatorHarness.ChildSession, _ familyId: String, _ data: [String: Any]) async throws {
        try await child.db.collection("families").document(familyId)
            .collection("events").document().setData(data)
    }

    @Test("아이가 자기 이름으로 read:false, at 이 창 안이면 통과한다 (firestore.rules:306-310)")
    func 통과() async throws {
        let (familyId, child) = try await 가족과_자녀()
        try await 쓴다(child, familyId, 본문(child.uid, at: 지금()))
    }

    @Test("at 이 8일 전이면 거부된다 — 창은 7일이다(판정 기록 12)")
    func 너무_옛날() async throws {
        let (familyId, child) = try await 가족과_자녀()
        await #expect(throws: (any Error).self) {
            try await 쓴다(child, familyId, 본문(child.uid, at: 지금() - 8 * 24 * 60 * 60 * 1000))
        }
    }

    @Test("at 이 2시간 뒤면 거부된다 — 미래 창은 1시간이다")
    func 너무_미래() async throws {
        let (familyId, child) = try await 가족과_자녀()
        await #expect(throws: (any Error).self) {
            try await 쓴다(child, familyId, 본문(child.uid, at: 지금() + 2 * 60 * 60 * 1000))
        }
    }

    @Test("read: true 로 만들면 거부된다 — 아이가 자기 사건을 미리 읽음 처리할 수 없다 (:308)")
    func 읽음으로_만들기() async throws {
        let (familyId, child) = try await 가족과_자녀()
        await #expect(throws: (any Error).self) {
            try await 쓴다(child, familyId, 본문(child.uid, at: 지금(), read: true))
        }
    }

    @Test("남의 childUid 로 만들면 거부된다 (:307)")
    func 남의_이름() async throws {
        let (familyId, child) = try await 가족과_자녀()
        await #expect(throws: (any Error).self) {
            try await 쓴다(child, familyId, 본문("남의uid", at: 지금()))
        }
    }

    @Test("아이가 자기 사건을 읽음 처리하면 거부된다 — 부모의 안 읽은 목록에서 지울 수 없다 (:315-318)")
    func 아이는_읽음을_못_쓴다() async throws {
        let (familyId, child) = try await 가족과_자녀()
        let ref = child.db.collection("families").document(familyId).collection("events").document()
        try await ref.setData(본문(child.uid, at: 지금()))
        await #expect(throws: (any Error).self) { try await ref.updateData(["read": true]) }
    }

    @Test("아이는 자기 places/ 를 읽을 수 있다 (:217-218) — 상시 구독의 근거다")
    func 장소_읽기() async throws {
        let (familyId, child) = try await 가족과_자녀()
        let snapshot = try await child.db.collection("families").document(familyId)
            .collection("children").document(child.uid).collection("places").getDocuments()
        #expect(snapshot.documents.isEmpty)
    }

    @Test("아이는 places/ 를 쓸 수 없다 — 장소는 부모가 정한다 (:219-221)")
    func 장소_쓰기_거부() async throws {
        let (familyId, child) = try await 가족과_자녀()
        await #expect(throws: (any Error).self) {
            try await child.db.collection("families").document(familyId)
                .collection("children").document(child.uid).collection("places").document("p1")
                .setData(["id": "", "name": "내가 만든 곳", "lat": 37.5, "lng": 127.0,
                          "radiusMeters": 100, "notifyEnter": true, "notifyExit": true])
        }
    }
}
```

`ios/KidCareTests/EventDocumentsTests.swift` 에 더한다:

```swift
    @Test("아이가 싣는 본문은 규칙이 요구하는 모양이다 — read 는 doc 값과 무관하게 항상 false(판정 기록 14)")
    func 아이가_싣는_본문() {
        let doc = EventDoc(id: "무시된다", type: EventType.placeExit, at: 1_700_000_000_000,
                           childUid: "아이uid", placeName: "학교", detail: "", read: true)
        let data = doc.firestoreData
        #expect(data["id"] as? String == "")
        #expect(data["type"] as? String == "place_exit")
        #expect(data["at"] as? Int64 == 1_700_000_000_000, "밀리초 정수여야 한다 — Timestamp 로 쓰면 규칙이 막는다")
        #expect(data["childUid"] as? String == "아이uid")
        #expect(data["placeName"] as? String == "학교")
        #expect(data["read"] as? Bool == false, "read: true 인 doc 을 넘겨도 false 로 나가야 한다")
        #expect(Set(data.keys) == ["id", "type", "at", "childUid", "placeName", "detail", "read"])
    }
```

- [ ] **Step 8: 에뮬레이터를 띄우고 전부 돌린다**

```bash
# 이미 떠 있으면 그대로 쓴다. 데이터를 지우지 않는다.
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/   # 200 이면 살아 있다
# 안 떠 있을 때만: firebase emulators:start --only auth,firestore --project kidcare-emulator
cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: PASS. 순증 23개(`PlaceStateStoreTests` 5 + `PlaceWatcherTests` 9 + `ChildEventWriteTests` 8 + `EventDocumentsTests` 1 + `TrackingCoordinatorTests` 3 = 26 중 일부는 1단계 파일에 들어간다).

- [ ] **Step 9: 커밋**

```bash
git add ios/KidCare/Child/PlaceStateStore.swift ios/KidCare/Child/PlaceWatcher.swift \
        ios/KidCare/Child/LocationCollector.swift ios/KidCare/Child/TrackingCoordinator.swift \
        ios/KidCare/Core/Documents.swift ios/KidCare/Core/EventRepository.swift ios/KidCare/Core/PlaceRepository.swift \
        ios/KidCareTests/PlaceStateStoreTests.swift ios/KidCareTests/PlaceWatcherTests.swift \
        ios/KidCareTests/ChildEventWriteTests.swift ios/KidCareTests/EventDocumentsTests.swift \
        ios/KidCareTests/TrackingCoordinatorTests.swift ios/project.yml
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" \
    commit -m "iOS 아이 2단계 Task 2: 장소를 걸고 점마다 판정해 도착·이탈 사건을 쓴다"
```

---

### Task 3: 머무른 곳 이름 — 캐시가 먼저, 초당 1건, 3초 예산

**끝나면 하루 문서의 머무름 구간에 이름이 붙는다.** 아는 이름은 네트워크 없이 즉시 채우고, 모르는 곳만 최근 머무름부터 3초 예산 안에서 묻는다. 위치 수집 경로는 지오코딩을 **한 번도** 기다리지 않는다.

**Files:**
- Create: `ios/KidCare/Child/PlaceNamer.swift`
- Modify: `ios/KidCare/Child/TrailUploader.swift`(1단계 — `buildSegments` 가 이름을 붙인다)
- Test: `ios/KidCareTests/PlaceNamerTests.swift`, `ios/KidCareTests/TrailUploaderNamingTests.swift`

**Interfaces:**
- Consumes: Task 1 의 `PlaceNameCache`; 1단계의 `Segment.nameLat`/`nameLng`·`TrailUploader.buildSegments`·`SegmentDoc`
- Produces: `actor PlaceNamer`(`cachedName(lat:lng:)`, `name(lat:lng:timeout:)`), `PlaceNamer.geocodeBudget`

**정본:** `child/PlaceNamer.kt`(전체), `child/TrailUploader.kt:158-236`, `logic/SegmentBuilder.kt:163-183`.

**속도 제한을 지키는 세 장치**(작업 지시 3번). ① `PlaceNameCache`(30m 거리 일치, 300개, 디스크 보존) 가 요청 수를 줄이고, ② actor 안의 "슬롯 먼저 확보"가 초당 1건을 보장하고(판정 기록 7), ③ 3초 예산이 한 번의 업로드에서 묻는 총량을 묶는다. **그리고 이 셋 어디에도 위치 수집 경로가 걸리지 않는다** — 부르는 곳은 `TrailUploader.buildSegments` 하나뿐이다(판정 기록 9).

- [ ] **Step 1: 테스트를 먼저 쓴다(빨강)**

`ios/KidCareTests/PlaceNamerTests.swift`:

```swift
import Foundation
import Testing
@testable import KidCare

/// 정본은 `child/PlaceNamer.kt`. 네트워크·시계·잠자기를 전부 주입해 실제 요청 없이 돈다 —
/// 테스트가 OpenStreetMap 공개 서버를 두드리면 그 자체가 사용 정책 위반이다.
struct PlaceNamerTests {

    /// 요청을 기록하고 정해진 답을 주는 가짜.
    actor 가짜_서버 {
        private(set) var 요청: [(url: URL, timeout: TimeInterval, at: Duration)] = []
        private var 답: [Data?]
        private let 시계: 가짜_시계
        init(답: [Data?], 시계: 가짜_시계) { self.답 = 답; self.시계 = 시계 }
        func fetch(_ url: URL, _ timeout: TimeInterval) async throws -> Data {
            요청.append((url, timeout, await 시계.지금))
            guard !답.isEmpty, let data = 답.removeFirst() else { throw URLError(.timedOut) }
            return data
        }
        var 횟수: Int { 요청.count }
    }

    /// 자는 대신 시각만 앞으로 민다.
    actor 가짜_시계 {
        private(set) var 지금: Duration = .zero
        func sleep(until due: Duration) async { if due > 지금 { 지금 = due } }
    }

    private func 본문(_ address: [String: String]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["address": address])
    }

    private func 만든다(답: [Data?], defaults: UserDefaults? = nil) async -> (PlaceNamer, 가짜_서버, 가짜_시계) {
        let 시계 = 가짜_시계()
        let 서버 = 가짜_서버(답: 답, 시계: 시계)
        let namer = PlaceNamer(
            defaults: defaults ?? UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
            fetch: { url, timeout in try await 서버.fetch(url, timeout) },
            now: { await 시계.지금 },
            sleep: { due in await 시계.sleep(until: due) })
        return (namer, 서버, 시계)
    }

    @Test("상수는 코틀린 그대로다 (:146, :150, :152, :153, TrailUploader.kt:235)")
    func 상수() {
        #expect(PlaceNamer.endpoint == "https://nominatim.openstreetmap.org/reverse")
        #expect(PlaceNamer.userAgent == "KidCare/1.0 (com.kidcare.family)")
        #expect(PlaceNamer.timeoutSeconds == 5.0)
        #expect(PlaceNamer.minInterval == .milliseconds(1_000))
        #expect(PlaceNamer.geocodeBudget == .milliseconds(3_000))
    }

    @Test("상호·건물명이 있으면 그것을 쓴다 (:118-139)")
    func 이름_고르기_상호() async {
        let (namer, _, _) = await 만든다(답: [본문(["amenity": "행복 어린이집", "suburb": "역삼동", "road": "테헤란로"])])
        #expect(await namer.name(lat: 37.5, lng: 127.0) == "행복 어린이집")
    }

    @Test("상호가 없으면 행정동 + 도로명. 도로명이 없거나 같으면 행정동만 (:133-138)")
    func 이름_고르기_행정동() async {
        let (a, _, _) = await 만든다(답: [본문(["suburb": "역삼동", "road": "테헤란로"])])
        #expect(await a.name(lat: 37.5, lng: 127.0) == "역삼동 테헤란로")
        let (b, _, _) = await 만든다(답: [본문(["quarter": "역삼1동"])])
        #expect(await b.name(lat: 37.5, lng: 127.0) == "역삼1동")
        let (c, _, _) = await 만든다(답: [본문(["suburb": "역삼동", "road": "역삼동"])])
        #expect(await c.name(lat: 37.5, lng: 127.0) == "역삼동")
    }

    @Test("주소가 없으면 nil 이고, 실패는 캐시하지 않는다 (:38-39, :127)")
    func 실패는_캐시_안_한다() async {
        let (namer, 서버, _) = await 만든다(답: [nil, 본문(["suburb": "역삼동"])])
        #expect(await namer.name(lat: 37.5, lng: 127.0) == nil)
        #expect(await namer.name(lat: 37.5, lng: 127.0) == "역삼동", "한 번의 네트워크 오류가 그 자리를 하루 종일 가두면 안 된다")
        #expect(await 서버.횟수 == 2)
    }

    @Test("캐시가 맞으면 네트워크를 안 탄다 — 30m 안이면 같은 곳이다 (:68)")
    func 캐시_적중() async {
        let (namer, 서버, _) = await 만든다(답: [본문(["amenity": "집"])])
        _ = await namer.name(lat: 37.5, lng: 127.0)
        // 약 11m 북쪽 — 같은 머무름에서 이름 좌표가 흔들리는 폭이다.
        #expect(await namer.name(lat: 37.5001, lng: 127.0) == "집")
        #expect(await 서버.횟수 == 1)
    }

    @Test("네트워크 없이 아는 이름만 준다 (:57-58)")
    func 캐시만_묻기() async {
        let (namer, 서버, _) = await 만든다(답: [본문(["amenity": "집"])])
        #expect(await namer.cachedName(lat: 37.5, lng: 127.0) == nil)
        _ = await namer.name(lat: 37.5, lng: 127.0)
        #expect(await namer.cachedName(lat: 37.5, lng: 127.0) == "집")
        #expect(await 서버.횟수 == 1)
    }

    @Test("요청 간격이 1초 밑으로 안 내려간다 — Nominatim 사용 정책 (:77-90)")
    func 초당_한_건() async {
        let (namer, 서버, _) = await 만든다(답: [본문(["amenity": "가"]), 본문(["amenity": "나"])])
        _ = await namer.name(lat: 37.5, lng: 127.0)
        _ = await namer.name(lat: 38.5, lng: 127.0)
        let 요청 = await 서버.요청
        #expect(요청.count == 2)
        #expect(요청[1].at - 요청[0].at >= .milliseconds(1_000))
    }

    @Test("동시에 둘을 불러도 간격이 지켜진다 — actor 재진입으로 슬롯이 겹치면 안 된다(판정 기록 7)")
    func 동시_호출() async {
        let (namer, 서버, _) = await 만든다(답: [본문(["amenity": "가"]), 본문(["amenity": "나"])])
        async let 하나 = namer.name(lat: 37.5, lng: 127.0)
        async let 둘 = namer.name(lat: 38.5, lng: 127.0)
        _ = await (하나, 둘)
        let 요청 = await 서버.요청
        #expect(요청.count == 2)
        #expect(요청[1].at - 요청[0].at >= .milliseconds(1_000),
                "코틀린이 Mutex 로 막은 그 경쟁이다 — 둘이 같은 값을 보고 둘 다 짧게 자면 안 된다")
    }

    @Test("URL 과 헤더가 코틀린과 같다 (:95-101)")
    func 요청_모양() async {
        let (namer, 서버, _) = await 만든다(답: [본문(["amenity": "집"])])
        _ = await namer.name(lat: 37.5, lng: 127.0, timeout: 2.0)
        let 요청 = try! #require(await 서버.요청.first)
        #expect(요청.url.absoluteString ==
                "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=37.5&lon=127.0&accept-language=ko&zoom=18")
        #expect(요청.timeout == 2.0, "부르는 쪽이 남은 예산을 넘겨 준다(:64-66)")
    }

    @Test("얻은 이름은 디스크에 남아 다음 프로세스가 즉시 쓴다 (:33-35, :73)")
    func 디스크_보존() async {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let (namer, _, _) = await 만든다(답: [본문(["amenity": "집"])], defaults: defaults)
        _ = await namer.name(lat: 37.5, lng: 127.0)
        let (다시, 서버2, _) = await 만든다(답: [], defaults: defaults)
        #expect(await 다시.cachedName(lat: 37.5, lng: 127.0) == "집")
        #expect(await 서버2.횟수 == 0)
    }
}
```

`ios/KidCareTests/TrailUploaderNamingTests.swift`:

```swift
import Foundation
import Testing
@testable import KidCare

/// 머무름에 이름을 붙이는 순서와 예산. 정본 `child/TrailUploader.kt:158-224`.
/// **이 함수가 부모의 대기 시간을 정했다**(그 주석 :160-166) — 아이폰에서는 부모가 물어볼 수
/// 없으므로 대기 시간이 아니라 업로드 한 번의 비용이 걸린다.
@MainActor
struct TrailUploaderNamingTests {

    /// 이름 한 건에 [지연] 만큼 걸리는 가짜. 실제 `PlaceNamer` 와 같은 모양만 갖춘다.
    actor 가짜_이름표 {
        private var 캐시: [String: String] = [:]
        private(set) var 물어본_순서: [String] = []
        private let 지연: Duration
        init(캐시: [String: String] = [:], 지연: Duration = .zero) { self.캐시 = 캐시; self.지연 = 지연 }
        private func 열쇠(_ lat: Double, _ lng: Double) -> String { String(format: "%.4f,%.4f", lat, lng) }
        func cachedName(lat: Double, lng: Double) -> String? { 캐시[열쇠(lat, lng)] }
        func name(lat: Double, lng: Double, timeout: TimeInterval) async -> String? {
            물어본_순서.append(열쇠(lat, lng))
            if 지연 > .zero { try? await Task.sleep(for: 지연) }
            return "물어본 \(열쇠(lat, lng))"
        }
    }

    // (1단계가 만든 TrailUploader 의 초기화 모양을 그대로 쓴다 — 선행 조건 grep 참고)
    @Test("이동 구간에는 이름을 안 붙인다 (:178-180)")
    @Test("아는 이름은 네트워크 없이 먼저 다 채운다 (:186-194)")
    @Test("모르는 곳은 **가장 최근 머무름부터** 묻는다 — 부모가 제일 궁금한 것은 방금 있던 곳이다 (:197)")
    @Test("3초 예산을 넘긴 곳은 이번엔 이름 없이 올라간다 (:200-201, :235)")
    @Test("남은 예산이 5초보다 짧으면 그만큼만 기다린다 (:206-209)")
    @Test("구간은 솎기 전 원본으로 계산한다 — 서버 상한에 맞춘 뒤 계산하면 머무름 경계점이 빠진다 (:135-138)")
```

각 `@Test` 의 본문은 1단계가 만든 `TrailUploader` 의 초기화·주입 모양을 grep 으로 확인한 뒤 그 모양에 맞춰 채운다. **확인 없이 추측해 쓰지 않는다** — 다르면 Pre-flight conflict table 의 해당 행을 먼저 처리한다.

- [ ] **Step 2: 실패를 확인한다**

Run: `cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/PlaceNamerTests -only-testing:KidCareTests/TrailUploaderNamingTests`
Expected: 컴파일 실패.

- [ ] **Step 3: `Child/PlaceNamer.swift`**

```swift
import Foundation
import os

/// 좌표를 사람이 읽는 주소로 바꾼다. 정본 `child/PlaceNamer.kt`.
///
/// **OpenStreetMap Nominatim 을 쓴다.** `CLGeocoder` 가 아니다(판정 기록 8) — 설계서 §4.10 이
/// 엔드포인트·User-Agent·제한시간·최소 간격을 "같은 값"으로 못 박았고, 이유는 두 플랫폼이 같은
/// 좌표에 **같은 이름**을 붙여야 하기 때문이다. 애플 지도 데이터는 같은 집에 다른 이름을 준다.
///
/// Nominatim 은 공개 서버를 무료로 내주는 호의성 서비스라 사용 정책이 있다(초당 최대 1건, 식별
/// 가능한 User-Agent, 결과 캐싱, 다른 서비스로 전환 가능). `awaitRateLimit` 이 첫째를,
/// `userAgent` 가 둘째를, `cache` 가 셋째를 만족한다. 넷째를 위해 엔드포인트를 상수 하나로만 몰아뒀다.
///
/// ## 왜 `actor` 인가 (설계서 §3.6)
/// 코틀린은 companion + `Mutex` 로 "캐시"와 "마지막 요청 시각"을 지켰다(`:158-159`). Swift 에서는
/// 언어 기능으로 대신한다. 다만 actor 는 `await` 지점에서 **재진입**하므로, 잠든 사이에 다른 호출이
/// 들어와 같은 값을 보고 둘 다 짧게 자는 경쟁이 생긴다 — 코틀린이 Mutex 로 막은 그 경쟁이다.
/// 그래서 **자기 전에** 다음 허용 시각을 밀어 슬롯을 먼저 확보한다(판정 기록 7).
///
/// ## 위치 수집을 절대 막지 않는다
/// 부르는 곳은 `TrailUploader.buildSegments` 하나뿐이다. `TrackingCoordinator.handle` 도
/// `PlaceWatcher.onFix` 도 이 타입을 모른다(판정 기록 9).
actor PlaceNamer {

    // Nominatim 사용 정책이 "다른 서비스로 언제든 전환 가능해야 한다"를 요구한다 — 그래서
    // 엔드포인트를 이 상수 하나로만 몰아둔다(`:144-146`).
    static let endpoint = "https://nominatim.openstreetmap.org/reverse"

    /// 앱을 식별하는 값만 넣는다 — 이메일 등 개인정보는 제3자(OSM 재단) 서버로 나가는 이 헤더에
    /// 넣지 않는다(`:148-150`).
    static let userAgent = "KidCare/1.0 (com.kidcare.family)"

    /// `:152`. 연결·읽기 각각의 제한이다. 부르는 쪽이 남은 예산을 넘겨 준다(`:64-66`).
    static let timeoutSeconds: TimeInterval = 5.0

    /// `:153`. Nominatim 정책의 "초당 최대 1건".
    static let minInterval: Duration = .milliseconds(1_000)

    /// 한 번의 업로드에서 새 이름을 묻는 데 쓸 수 있는 시간(`TrailUploader.kt:235`).
    /// 짧게 잡아도 이름이 영영 안 붙는 것은 아니다 — 얻은 이름은 디스크에 남는다.
    static let geocodeBudget: Duration = .milliseconds(3_000)

    private static let defaultsKey = "kidcare_place_names.entries"

    private let defaults: UserDefaults
    private let fetch: (URL, TimeInterval) async throws -> Data
    private let now: () async -> Duration
    private let sleep: (Duration) async -> Void
    private let logger = Logger(subsystem: "com.kidcare.family", category: "PlaceNamer")

    private var cache: PlaceNameCache
    /// 이 시각 전에는 새 요청을 쏘지 않는다. **자기 전에** 민다(판정 기록 7).
    private var nextAllowedAt: Duration = .zero

    init(defaults: UserDefaults = .standard,
         fetch: @escaping (URL, TimeInterval) async throws -> Data = PlaceNamer.urlSessionFetch,
         now: @escaping () async -> Duration = { .nanoseconds(DispatchTime.now().uptimeNanoseconds) },
         sleep: @escaping (Duration) async -> Void = { due in
             let 남은 = due - .nanoseconds(DispatchTime.now().uptimeNanoseconds)
             if 남은 > .zero { try? await Task.sleep(for: 남은) }
         }) {
        self.defaults = defaults
        self.fetch = fetch
        self.now = now
        self.sleep = sleep
        cache = PlaceNameCache.decode(defaults.string(forKey: Self.defaultsKey) ?? "")
    }

    /// 네트워크 없이 이미 아는 이름만. 모르면 nil (`:57-58`).
    func cachedName(lat: Double, lng: Double) -> String? { cache.find(lat: lat, lng: lng) }

    /// 이름을 못 얻으면 nil. 네트워크가 안 되거나 응답이 비어 있으면 조용히 nil 이다(`:60-75`).
    ///
    /// `budgetLeft` 가 주어지면 그 안에 요청 슬롯을 못 잡는 경우 **아예 묻지 않고** nil 로 돌아온다 —
    /// 1초를 기다린 뒤 예산이 끝나 버리면 기다린 시간이 통째로 낭비되기 때문이다.
    func name(lat: Double, lng: Double,
              timeout: TimeInterval = PlaceNamer.timeoutSeconds,
              budgetLeft: Duration? = nil) async -> String? {
        if let cached = cache.find(lat: lat, lng: lng) { return cached }

        let start = await now()
        let due = max(nextAllowedAt, start)
        if let budgetLeft, due - start >= budgetLeft { return nil }
        // 슬롯을 **먼저** 확보한다. 그다음에 잔다(판정 기록 7).
        nextAllowedAt = due + Self.minInterval
        if due > start { await sleep(due) }

        guard let url = URL(string: "\(Self.endpoint)?format=jsonv2&lat=\(lat)&lon=\(lng)&accept-language=ko&zoom=18") else {
            return nil
        }
        let data: Data
        do {
            data = try await fetch(url, timeout)
        } catch is CancellationError {
            // 취소는 삼키지 않는다(설계서 §16) — 위로 그대로 보이게 다시 던진다.
            // 이 함수가 `async` 지만 `throws` 가 아니므로, 취소는 Task 가 이미 알고 있다.
            return nil
        } catch {
            logger.warning("역지오코딩 요청 실패: \(String(describing: error), privacy: .public)")
            return nil
        }
        guard let name = Self.parse(data) else { return nil }

        // 실패한 결과(nil)는 캐시하지 않는다 — 한 번의 네트워크 오류가 그 자리를 하루 종일
        // 이름 없이 가두면 안 된다(`:36-38`).
        cache.put(lat: lat, lng: lng, name: name)
        defaults.set(cache.encode(), forKey: Self.defaultsKey)
        return name
    }

    /// 상호·건물명 같은 구체적 장소명이 있으면 그게 사람에게 가장 익숙하니 그대로 쓴다. 없으면 동
    /// 단위 행정 구역명을 쓰고, 도로명이 있으면 덧붙인다. suburb(행정동)를 quarter(법정동)보다 먼저
    /// 보는 근거는 실제 서울 좌표 4곳 확인 결과다(`:118-139`). 시·도까지 붙이면 화면에서 잘린다.
    static func parse(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let address = root["address"] as? [String: Any] else { return nil }
        func 값(_ key: String) -> String? {
            guard let text = address[key] as? String, !text.isEmpty else { return nil }
            return text
        }
        if let specific = ["amenity", "shop", "building"].lazy.compactMap(값).first { return specific }
        guard let region = ["suburb", "quarter", "neighbourhood", "city_district"].lazy.compactMap(값).first else {
            return nil
        }
        if let road = 값("road"), road != region { return "\(region) \(road)" }
        return region
    }

    /// 요청이 이 한 종류뿐이라 HTTP 라이브러리를 하나 더 들이지 않는다(`:20-23` 과 같은 판단).
    /// 제한시간은 `URLRequest.timeoutInterval` 로 건다 — 코틀린이 소켓 제한시간으로 예산을 지킨 것과
    /// 같은 자리다(`:64-66`).
    static func urlSessionFetch(_ url: URL, _ timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
```

- [ ] **Step 4: `TrailUploader.buildSegments` 가 이름을 붙인다**

1단계가 만든 `buildSegments` 의 빈 이름 칸 자리를 아래로 바꾼다. 주석은 코틀린 `:158-181` 의 이유를 그대로 옮긴다.

```swift
    /// 구간 요약을 만든다. 머무름에는 이름을 붙인다. 정본 `TrailUploader.kt:182-224`.
    ///
    /// 순서가 이렇다.
    /// 1. 이미 아는 이름부터 전부 채운다 — 네트워크 없이 즉시.
    /// 2. 모르는 곳만, **가장 최근 머무름부터**, `PlaceNamer.geocodeBudget`(3초) 안에서만 묻는다.
    ///    부모가 제일 궁금한 것은 방금 있던 곳이다.
    /// 3. 예산을 넘긴 곳은 이번엔 이름 없이 올라간다. 다음 업로드가 다시 묻고, 한 번 얻은 이름은
    ///    디스크 캐시에 남아 그 뒤로는 즉시 나온다. **재시도 상수를 새로 만들지 않는다**(설계서 §4.11).
    ///
    /// 이동 구간에는 이름을 붙이지 않는다 — "어디서 어디로"가 앞뒤 머무름 이름으로 이미 드러나고,
    /// 이동 중 좌표 하나를 주소로 바꿔봐야 지나가던 길 이름이다.
    ///
    /// 이름은 `lat`/`lng` 가 아니라 `nameLat`/`nameLng` 로 묻는다. 앞의 둘은 지도에 찍는 좌표(단순
    /// 평균)고 뒤의 둘은 오차로 가중한 평균이다 — 도착 순간 튄 점 하나가 머무름 전체에 옆 건물
    /// 이름을 달아버리는 것을 막는다(`SegmentBuilder.kt:163-183`).
    private func buildSegments(_ points: [Fix]) async -> [SegmentDoc] {
        let segments = SegmentBuilder.build(points)

        var names = [String](repeating: "", count: segments.count)
        for (i, segment) in segments.enumerated() where segment.type == .stay {
            names[i] = await namer.cachedName(lat: segment.nameLat, lng: segment.nameLng) ?? ""
        }

        let deadline = ContinuousClock.now.advanced(by: PlaceNamer.geocodeBudget)
        var asked = 0
        for i in segments.indices.reversed() {
            let segment = segments[i]
            if segment.type != .stay || !names[i].isEmpty { continue }
            let left = ContinuousClock.now.duration(to: deadline)
            if left <= .zero { break }
            asked += 1
            names[i] = await namer.name(
                lat: segment.nameLat, lng: segment.nameLng,
                timeout: min(left.초, PlaceNamer.timeoutSeconds),
                budgetLeft: left) ?? ""
        }
        let unnamed = segments.indices.filter { segments[$0].type == .stay && names[$0].isEmpty }.count
        if asked > 0 || unnamed > 0 {
            logger.info("머무름 이름: 새로 물음 \(asked)곳 · 이번에 이름 없음 \(unnamed)곳")
        }

        return segments.enumerated().map { i, segment in
            SegmentDoc(type: segment.type.kotlinName, startAt: segment.startAt, endAt: segment.endAt,
                       lat: segment.lat, lng: segment.lng, distanceMeters: segment.distanceMeters,
                       pointCount: segment.pointCount, placeName: names[i])
        }
    }
```

`Duration.초`(초 단위 `TimeInterval`) 헬퍼가 1단계에 없으면 이 파일 아래에 `private extension Duration { var 초: TimeInterval { Double(components.seconds) + Double(components.attoseconds) / 1e18 } }` 를 둔다.

- [ ] **Step 5: 초록을 확인한다**

Run: Step 2 와 같은 명령 → 그다음 전체.
Expected: PASS. 순증 약 16개(`PlaceNamerTests` 10 + `TrailUploaderNamingTests` 6).

- [ ] **Step 6: 커밋**

```bash
git add ios/KidCare/Child/PlaceNamer.swift ios/KidCare/Child/TrailUploader.swift \
        ios/KidCareTests/PlaceNamerTests.swift ios/KidCareTests/TrailUploaderNamingTests.swift ios/project.yml
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" \
    commit -m "iOS 아이 2단계 Task 3: 머무른 곳 이름을 캐시 먼저·초당 1건·3초 예산으로 붙인다"
```

---

### Task 4: 단계 마무리 — 전수 대조, 골든이 정말 무는지, 시뮬레이터 통과

**끝나면 상수 대조표(설계서 §4.6·§4.7·§4.10)가 코드와 한 줄씩 맞고, 골든 대조가 일부러 망가뜨린 값에 실제로 빨개지며, 시뮬레이터에서 학교 반경을 넘으면 보호자 알림 탭에 "학교에 도착했어요"가 뜬다.**

**Files:**
- Create: `ios/dev/school-crossing.gpx`
- Modify: 이 단계에서 찾은 결함이 있으면 그 파일들

- [ ] **Step 1: 상수를 한 줄씩 대조한다**

```bash
cd /Users/com/work/KidCare
# 설계서 §4.6 — GeofenceEvaluator
grep -n "EXIT_MARGIN_METERS\|DEDUPE_MILLIS\|MAX_ACCURACY_METERS" app/src/main/java/com/kidcare/family/logic/GeofenceEvaluator.kt
grep -n "exitMarginMeters\|dedupeMillis\|maxAccuracyMeters" ios/KidCare/Logic/GeofenceEvaluator.swift
# 설계서 §4.7 — PlaceNameCache
grep -n "MATCH_RADIUS_METERS\|MAX_ENTRIES" app/src/main/java/com/kidcare/family/logic/PlaceNameCache.kt
grep -n "matchRadiusMeters\|maxEntries" ios/KidCare/Logic/PlaceNameCache.swift
# 설계서 §4.10 — PlaceNamer·PlaceWatcher·TrailUploader
grep -n "GEOCODE_BUDGET_MILLIS" app/src/main/java/com/kidcare/family/child/TrailUploader.kt
grep -n "TIMEOUT_MILLIS\|MIN_INTERVAL_MILLIS\|ENDPOINT\|USER_AGENT" app/src/main/java/com/kidcare/family/child/PlaceNamer.kt
grep -n "MAX_GEOFENCES" app/src/main/java/com/kidcare/family/child/PlaceWatcher.kt
grep -n "geocodeBudget\|timeoutSeconds\|minInterval\|endpoint\|userAgent" ios/KidCare/Child/PlaceNamer.swift
grep -n "maxRegions" ios/KidCare/Logic/GeofenceRegionSelection.swift
```

표를 만들어 **값과 인용 줄이 둘 다 맞는지** 눈으로 본다. 하나라도 어긋나면 **안드로이드가 맞다.**

- [ ] **Step 2: 골든이 정말 무는지 일부러 깨 본다**

2단계(보호자 앱)에서 이 확인이 가장 중요했다 — 골든 파일을 `[]` 로 비워도 일곱 테스트가 전부 통과하던 사고가 있었다(README 2026-09-13). **넷을 차례로 깨고, 각각이 빨개지는 것을 보고, 되돌린다.**

| # | 깨는 것 | 빨개져야 하는 테스트 |
|---|---|---|
| 1 | `GeofenceEvaluator.exitMarginMeters` 를 `40.0` 으로 | `지오펜스_판정_대조`(exit_* 케이스) |
| 2 | `PlaceNameCache.matchRadiusMeters` 를 `25.0` 으로 | `장소이름_캐시_대조`(find/put) |
| 3 | `golden/geofenceEvaluator.json` 을 `[]` 로 | `골든_리소스가_번들에_있다` |
| 4 | `golden/placeNameCache.json` 을 `{"find":[],"put":[],"decode":[]}` 로 | `골든_리소스가_번들에_있다` |

```bash
cd /Users/com/work/KidCare
cp ios/KidCareTests/golden/geofenceEvaluator.json /tmp/ge.bak
cp ios/KidCareTests/golden/placeNameCache.json /tmp/pnc.bak
# 1·2 는 손으로 값을 고치고 아래를 돌린 뒤 git checkout 으로 되돌린다.
cd ios && xcodebuild test -project KidCare.xcodeproj -scheme KidCare \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KidCareTests/GoldenComparisonTests
# 되돌리기
cd /Users/com/work/KidCare
git checkout ios/KidCare/Logic/GeofenceEvaluator.swift ios/KidCare/Logic/PlaceNameCache.swift
cp /tmp/ge.bak ios/KidCareTests/golden/geofenceEvaluator.json
cp /tmp/pnc.bak ios/KidCareTests/golden/placeNameCache.json
git status --short   # 비어 있어야 한다
```

**넷 중 하나라도 초록이면 그 검사가 무의미하다는 뜻이다 — 검사를 고치고 다시 한다.**

또 하나: **코틀린 생성기의 자체 점검이 무는지**도 본다. `generateGeofenceEvaluator` 의 `enter_just_outside` 를 `fix(99.0, 10f)`(=경계 안)로 바꾸면 `check(...)` 가 죽어야 한다. 확인 뒤 되돌린다.

- [ ] **Step 3: 전체 테스트**

```bash
cd ios && xcodegen generate && xcodebuild test -project KidCare.xcodeproj -scheme KidCare \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```

Expected: PASS. 개수는 선행 조건에 적어 둔 M 에 Task 1~3 의 순증(약 64)을 더한 값이다.

- [ ] **Step 4: 시뮬레이터에서 경계를 넘긴다**

`ios/dev/school-crossing.gpx` 를 만든다. 기준점은 서울시청(37.5665, 126.9780), 장소 반경 100m 다. 위도 0.0015도가 약 167m 라 **남쪽 167m(밖) → 0m(안) → 북쪽 189m(반경 100 + 여유 50 을 넘음)** 로 걷는다.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!-- 시뮬레이터로 장소 경계를 넘긴다(설계서 §12.4 "시뮬레이터로 되는 것").
     기준 장소: lat 37.5665 / lng 126.9780 / 반경 100m.
     첫 점은 밖(약 167m 남쪽), 가운데는 안(0m), 마지막은 이탈 여유 50m 까지 넘은 북쪽 189m.
     한 점에 약 5초씩 나아가면 MovementTrailFilter.MIN_INTERVAL_MILLIS(5초)에 맞는다. -->
<gpx version="1.1" creator="KidCare dev">
  <wpt lat="37.5650" lon="126.9780"><name>밖-출발</name></wpt>
  <wpt lat="37.5655" lon="126.9780"><name>다가감</name></wpt>
  <wpt lat="37.5660" lon="126.9780"><name>경계 근처</name></wpt>
  <wpt lat="37.5665" lon="126.9780"><name>안-도착</name></wpt>
  <wpt lat="37.5665" lon="126.9780"><name>안-머무름</name></wpt>
  <wpt lat="37.5670" lon="126.9780"><name>나가는 중</name></wpt>
  <wpt lat="37.5676" lon="126.9780"><name>여유 안</name></wpt>
  <wpt lat="37.5682" lon="126.9780"><name>밖-이탈</name></wpt>
</gpx>
```

1. 에뮬레이터가 떠 있는지 본다(`curl` 로 8080 확인). **데이터를 지우지 않는다.**
2. `KidCareApp.swift` 를 잠깐 `configureForEmulator(projectId: "kidcare-emulator")` 로 바꾼다. **Step 6 에서 반드시 되돌린다.**
3. 아이로 페어링한다(3단계가 아직 없으므로, 아이 역할 배선이 없다면 `TrackingCoordinator` 를 띄우는 개발용 진입점을 **임시로** 쓰고 커밋하지 않는다). 가족·아이 uid·장소 하나는 에뮬레이터 REST 로 심는다:

```bash
EMU="http://127.0.0.1:8080/v1/projects/kidcare-emulator/databases/(default)/documents"
AUTH="Authorization: Bearer owner"
curl -s -X PATCH -H "$AUTH" -H "Content-Type: application/json" \
  "$EMU/families/<가족ID>/children/<아이UID>/places/school" -d '{"fields":{
    "id":{"stringValue":""},"name":{"stringValue":"학교"},
    "lat":{"doubleValue":37.5665},"lng":{"doubleValue":126.9780},
    "radiusMeters":{"doubleValue":100},
    "notifyEnter":{"booleanValue":true},"notifyExit":{"booleanValue":true}}}' > /dev/null
```

4. **앱을 지우지 않고** 위에 덮어 설치한 뒤 띄운다. 위치 권한은 '항상 허용'으로 준다.
5. 경로를 먹인다. 둘 중 하나:
   - `xcrun simctl location booted run --speed=2 --distance=5 ios/dev/school-crossing.gpx`
   - Xcode 에서 Debug ▸ Simulate Location ▸ Add GPX File to Workspace…
   먼저 `xcrun simctl location booted set 37.5650,126.9780` 으로 출발점을 심어 **"처음 보는 장소"에 밖으로 상태가 박히게** 한다 — 안에서 시작하면 판정기가 조용히 상태만 심고(설계서 §7.1) 도착 알림이 안 나가는 것이 **정상**이다.
6. 본다.
   - 장소 하나가 걸렸다: 콘솔 로그(`PlaceWatcher`)에 잘린 개수 경고가 없다.
   - 경계를 넘는 순간 `events/` 에 문서 하나가 생긴다:
     ```bash
     curl -s -H "$AUTH" "$EMU/families/<가족ID>/events" | python3 -m json.tool | head -40
     ```
     `type` 이 `place_enter`, `placeName` 이 `학교`, `read` 가 `false`, `at` 이 밀리초 정수다.
   - 북쪽 189m 에서 `place_exit` 하나가 더 생긴다. **149m 지점에서는 안 생긴다**(이탈 여유 50m).
   - 5분 안에 같은 방향 전환을 또 만들어도 두 번째는 안 생긴다(중복 억제).
   - 보호자 앱(같은 시뮬레이터에서 보호자로 로그인하거나 안드로이드 보호자)의 **알림 탭에 "학교에 도착했어요"가 뜬다.**
   - `children/<아이UID>/trails/<dayKey>` 의 `segments` 에서 머무름 하나에 `placeName` 이 붙어 있다(네트워크가 되는 환경일 때. 안 되면 빈 문자열이 정상이고, 그렇게 적는다).
   - 항목마다 `xcrun simctl io booted screenshot /tmp/child-p2-<번호>.png` 로 남긴다.
7. **앱을 지우지 않고** 시뮬레이터도 끄지 않는다.

- [ ] **Step 5: 안드로이드와 같은 문서인지 눈으로 대조한다**

같은 가족에서 안드로이드 아이가 쓴 `events/` 문서(이미 에뮬레이터에 있으면 그것, 없으면 `EventRepositoryTests.아이가_남긴다` 의 필드 목록)와 필드 이름·타입·개수를 맞춰 본다. **`id`·`type`·`at`·`childUid`·`placeName`·`detail`·`read` 일곱이고 그 밖에 아무것도 없다.**

- [ ] **Step 6: 되돌리고 확인**

```bash
cd /Users/com/work/KidCare
git checkout ios/KidCare/KidCareApp.swift
git diff ios/KidCare/KidCareApp.swift          # 비어 있어야 한다
git status --short                              # 새 gpx 말고는 비어 있어야 한다
```

여기서 찾은 결함은 고친 뒤 테스트를 다시 돌리고 `iOS 아이 2단계 Fix round N: …` 으로 커밋한다.

- [ ] **Step 7: 커밋**

```bash
git add ios/dev/school-crossing.gpx
git -c user.name="Yongminlee2" -c user.email="dydals5678@gmail.com" \
    commit -m "iOS 아이 2단계 단계 마무리: 상수 전수 대조와 시뮬레이터 경계 넘기 확인"
```

---

## 2단계 완료 기준

- [ ] `Logic/` 셋이 Foundation 만 import 하고, 골든 둘의 모든 케이스에서 코틀린과 같은 답을 낸다.
- [ ] 골든을 일부러 깨면(값 둘·파일 둘) 네 경우 모두 빨개지고, 코틀린 생성기의 `check(...)` 도 문다.
- [ ] 장소가 20개를 넘으면 **이름순 앞에서 20개**만 걸리고, 반경 0 은 빠지며, 잘린 개수가 로그에 남는다.
- [ ] 지역 경계 콜백이 이벤트를 쓰지 않고 좌표 한 점만 부탁한다. 그 점은 간격 게이트를 한 번 건너뛴다.
- [ ] 판정은 `LocationFilter.decide` 결과에 묶이지 않는다(`SKIP_TOO_CLOSE` 도 넘어간다).
- [ ] 상태를 **먼저** 저장하고 그다음에 이벤트를 쓴다. 쓰기가 실패해도 "안에 있다"가 남는다.
- [ ] 장소 목록이 비어 있으면 저장된 상태를 **지우지 않는다.**
- [ ] 아이 세션의 `events/` 쓰기가 규칙을 통과하고, 거부 경로 다섯(8일 전·2시간 뒤·read true·남의 uid·아이의 읽음 쓰기)이 전부 거부된다.
- [ ] 아이가 자기 `places/` 를 읽을 수 있고 쓸 수 없다.
- [ ] 머무름 이름이 캐시 우선 → 최근 순 → 3초 예산으로 붙고, 요청 간격이 1초 밑으로 안 내려간다(동시 호출 포함).
- [ ] 지오코딩이 위치 수집 경로에서 한 번도 안 불린다(`TrackingCoordinator`·`PlaceWatcher` 에 `PlaceNamer` 참조가 없다).
- [ ] 시뮬레이터에서 경계를 넘으면 보호자 알림 탭에 "학교에 도착했어요"가 뜬다.
- [ ] 앱 코드에 `@unchecked Sendable`·`nonisolated(unsafe)` 가 없고, 새 리스너(장소 구독)에 떼는 길이 있다.
- [ ] `python3 tools/ios-strings.py --check` 가 0 이고, `i18n/*.json` 이 안 바뀌었다.
- [ ] `git diff --stat 4bda965..HEAD -- app/src/main firestore.rules gradlew` 가 비어 있고, `app/` 변경은 `GoldenFileWriterTest.kt` 하나뿐이다.

---

## 자기 검토 결과 (writing-plans self-review)

**설계서 대응.** §14 2단계가 적은 네 줄을 하나씩 짚는다.

- "`Logic/`: GeofenceEvaluator, PlaceNameCache, GeofenceRegionSelection. 골든 둘 + 대조 테스트" → Task 1 전부. 골든이 **둘**인 이유(셋이 아닌 이유)는 판정 기록 11 이다.
- "`Child/`: PlaceWatcher, PlaceStateStore, PlaceNamer" → Task 2(앞의 둘)·Task 3(PlaceNamer). `PlaceNamer` 가 2단계인 근거는 §14 의 "끝나면 … 머무름에 이름이 붙는다"이다(판정 기록 1).
- "`Core/`: EventRepository.add, PlaceRepository.observePlaces 를 아이 uid 로 구독" → Task 2 Step 4·6. `PlaceRepository` 는 **새 함수가 없다**(설계서 §3.3) — 주석만 고친다.
- "에뮬레이터 테스트: 이벤트 쓰기 계약 셋(§11.1)과 거부 경로" → Task 2 Step 7. §12.3 이 적은 여덟 중 이 단계 몫 일곱을 넣었고, **`trails/` 쓰기와 초대 코드 child 가입 둘은 1단계·3단계 몫**이라 뺐다(그 두 줄은 "다루지 않는 것"에 적지 않았다 — 1·3단계가 덮는다).
- §4.6·§4.7·§4.10 상수 → Task 1 의 `상수()` 테스트 둘과 Task 4 Step 1 의 전수 대조. §4.6 마지막 줄("값이 아니라 참조를 옮긴다")은 `maxAccuracyMeters == LocationFilter.fallbackMaxAccuracyMeters` 로 **테스트가 고정**한다.
- §7.1(신호일 뿐) → `PlaceWatcher.regionCrossed` + `지역_콜백은_신호일_뿐` 테스트. 시각이 "위치가 잡힌 순간"이라는 것은 `도착_이벤트` 가 `at == 777` 로 고정한다.
- §7.2(20개) → `GeofenceRegionSelection` + 테스트 여섯. 설계서가 적은 세 규칙(반경 0 제외·이름순 20·잘리면 로그)이 각각 테스트와 `logger.warning` 에 있다.
- §7.3(어느 API·전부 지우고 다시·상시 구독) → `LocationCollector.replaceMonitoredRegions`(주인 판정 1 의 근거를 주석에), Task 2 Step 6 의 구독.
- §7.4(앱이 죽어 있는 동안) → `PlaceStateStore` 가 프로세스 밖에 남긴다. **"강제 종료 뒤에는 이 되살리기도 안 온다"는 4단계 실기기 몫**이라 여기서 확인하지 않는다.
- §11.1 계약 셋 → `EventDoc.firestoreData` 주석 + `ChildEventWriteTests` 다섯 + `EventDocumentsTests.아이가_싣는_본문`.
- §12.4 "시뮬레이터로 되는 것" → Task 4 Step 4. 실기기 열 항목은 손대지 않는다.
- §16 제약 → Global Constraints.
- 주인 판정 여섯 개 전부 대응했다. 1(예전 API) → 판정 기록 2. 2(20개, 순수 로직) → 판정 기록 3·`GeofenceRegionSelection`. 3(속도 제한·캐시·수집 비차단) → Task 3 머리말의 세 장치와 판정 기록 7·9. 4(골든 + 일부러 깨기) → Task 1 Step 7~9, Task 4 Step 2. 5(에뮬레이터만) → Global Constraints·Task 2 Step 8·Task 4 Step 4. 6(명령 없음) → "다루지 않는 것".

**설계서에서 구체화하지 못한 것 둘.** 둘 다 본문에 그렇게 적었다.
- **지오코더 갈림.** 작업 지시는 `CLGeocoder` 를 전제했는데 설계서 §4.10 은 Nominatim 을 "같은 값"으로 못 박았다. 설계서를 따르고 판정 기록 8 에 근거를 적었다. **주인 확인이 필요하다.**
- **강제 종료 뒤 되살아나는가**(§17 열린 질문 3). 시뮬레이터로 못 본다. 4단계 항목이고 이 계획서는 "안 되살아난다"를 가정한 채로 아무것도 걸지 않는다.

**자리표시 검사.** "TBD/적절히/나중에"는 없다. 실행해야 알 수 있는 값 넷만 비워 뒀다: 선행 조건의 테스트 개수 M, Task 4 Step 3 의 최종 개수, Task 4 Step 4 의 가족ID·아이UID, Task 3 Step 1 의 `TrailUploaderNamingTests` 본문(1단계 초기화 모양에 맞춰야 해서 `@Test` 이름만 적고 "grep 으로 확인한 뒤 채운다"로 남겼다 — 추측해 쓰지 말라고 못 박았다).

**타입·이름 일관성(고친 것 포함).**
- 테스트와 구현 대조:
  - `GeofenceEvaluatorTests` 가 쓰는 `Place(id:name:lat:lng:radiusMeters:notifyEnter:notifyExit:)`, `PlaceState(placeId:inside:lastEventAt:)`, `GeofenceHit(placeId:placeName:entering:at:)`, `GeofenceEvaluator.evaluate(places:states:fix:) -> (hits:states:)` 가 Step 3 구현에 모두 있다.
  - `PlaceNameCacheTests` 가 쓰는 `init(matchRadiusMeters:maxEntries:)`, `find(lat:lng:)`, `mutating put(lat:lng:name:)`, `encode()`, `static decode(_:)`, `size`, `자바_공백` 이 Step 4 에 있다.
  - `PlaceWatcherTests` 가 쓰는 `PlaceWatcher(stateStore:monitor:addEvent:)`, `apply(placeDocs:)`, `places`, `onFix(familyId:childUid:fix:)`, `isInsideKnownPlace(_:)`, `regionCrossed(placeId:)`, `RegionMonitor.replaceMonitoredRegions(_:)`·`requestOneShotFix()` 가 Step 5 에 있다.
  - `PlaceNamerTests` 가 쓰는 `PlaceNamer(defaults:fetch:now:sleep:)`, `cachedName(lat:lng:)`, `name(lat:lng:timeout:budgetLeft:)`, 상수 다섯이 Step 3 에 있다.
- 초안에서 고친 것 다섯.
  - `PlaceNameCache` 를 클래스로 두려다 **struct** 로 바꿨다. `actor PlaceNamer` 의 저장 프로퍼티가 되려면 `Sendable` 이어야 하고, 참조 타입이면 `@unchecked Sendable` 이 필요해진다 — 금지된 것이다.
  - `PlaceNamer.name` 에 `budgetLeft` 를 더했다. 처음에는 예산을 부르는 쪽에서만 봤는데, 그러면 1초를 기다린 뒤 예산이 끝나 버려 그 대기가 통째로 낭비된다.
  - 속도 제한을 "자고 나서 갱신"으로 썼다가 actor 재진입 때문에 **"자기 전에 슬롯 확보"**로 바꿨다(판정 기록 7). `동시_호출` 테스트가 그것을 고정한다.
  - `GeofenceRegionSelection.choose` 만 두려다 `chooseWithReport` 를 더했다 — 잘린 개수를 로그로 남기라는 `PlaceWatcher.kt:172-174` 를 지키려면 개수가 필요하다.
  - 지역 콜백에서 `PlaceWatcher` 가 직접 `CLLocationManager` 를 부르게 하려다 `RegionMonitor` 프로토콜로 갈랐다 — 매니저는 앱이 사는 동안 하나여야 하고(설계서 §5.2), 그러면 `PlaceWatcher` 를 테스트할 수 없다.
- **실행 전에 확인이 필요한 가정 넷.** 전부 Pre-flight conflict table 에 행이 있고, 다르면 멈추고 보고하게 적었다.
  - 1단계의 이름들(`LocationFilter.fallbackMaxAccuracyMeters`·`distanceMeters`, `Segment.nameLat/nameLng`, `TrailUploader.buildSegments`, `TrackingCoordinator.handle` 의 게이트 위치)
  - 1단계가 `didUpdateLocations` 에서 쓴 메인 액터 건너오기 방식(`MainActor.assumeIsolated` 인가 `Task { @MainActor }` 인가)
  - `Duration.초` 헬퍼가 1단계에 이미 있는가
  - `xcrun simctl location booted run` 이 이 Xcode 버전에 있는가(없으면 Xcode 의 GPX 메뉴로 간다 — Step 4 에 둘 다 적었다)

---

## Pre-flight conflict table

| 짝 | 함께 만지는 것 | 충돌 여부와 처리 |
|---|---|---|
| **1단계 Task(작업 중) ↔ 2단계 Task 1** | `Logic/LocationFilter.swift` 의 `distanceMeters(_:_:)`·`fallbackMaxAccuracyMeters`·`maxAccuracyMeters` | `GeofenceEvaluator`·`PlaceNameCache`·`PlaceWatcher` 가 셋 다 쓴다. 2026-09-22 HEAD `4bda965` 에는 없다. 선행 조건 grep 으로 확인하고, 이름이 다르면(예: `FALLBACK_MAX_ACCURACY_METERS` 를 `staleMaxAccuracyMeters` 로 지었으면) **커밋된 이름에 맞춘다.** 값을 다시 적지 않는다(설계서 §4.6 의 "참조를 옮긴다") |
| **1단계 ↔ 2단계 Task 1** | `Logic/Fix.swift` — 1단계가 `speedAccuracy` 를 **마지막 기본값 매개변수**로 더한다 | 이 계획서의 모든 `Fix(lat:lng:accuracy:at:)` 호출이 그대로 컴파일된다. 1단계가 그 자리를 다르게 뒀으면(예: 세 번째 인자) 이 계획서의 `Fix(...)` 를 전부 고친다 |
| **1단계 ↔ 2단계 Task 3** | `Logic/Segment.swift` 의 `nameLat`/`nameLng` 와 **명시적 `init`** | `buildSegments` 가 `segment.nameLat`/`nameLng` 로 이름을 묻는다(`SegmentBuilder.kt:163-183`). 없으면 1단계가 안 끝난 것이다 — **2단계를 시작하지 않는다** |
| **1단계 ↔ 2단계 Task 2** | `Child/LocationCollector.swift` — 매니저 소유, 델리게이트, `didUpdateLocations` 의 메인 액터 건너오기 | Task 2 는 이 파일에 `extension` 둘을 더한다(`RegionMonitor` 준수 + 지역 델리게이트 셋). 1단계가 델리게이트를 `nonisolated` + `MainActor.assumeIsolated` 로 썼으면 그대로 따르고, `Task { @MainActor in }` 로 썼으면 **그 모양으로 바꾼다** — 한 파일에 두 방식이 섞이면 다음 사람이 어느 쪽이 옳은지 모른다. `coordinator`·`placeWatcher` 참조가 1단계에 없으면 약한 참조 프로퍼티를 더한다 |
| **1단계 ↔ 2단계 Task 2** | `Child/TrackingCoordinator.swift` — §6.1 의 10단계 순서, 소프트웨어 간격 게이트, `isInsideKnownPlace` 자리(3번), 업로드 판정(10번) | Task 2 는 ① 8번 자리에 `placeWatcher.onFix` 를 넣고 ② 3번 자리의 1단계 임시값을 `placeWatcher.isInsideKnownPlace` 로 바꾸고 ③ 게이트에 `게이트_한번_건너뛰기` 한 갈래를 더하고 ④ `start()`/`stop()` 에 장소 구독을 단다. 1단계가 3번 자리를 "항상 false" 같은 임시값으로 뒀으면 그 줄을 지운다. **8번이 7번 결과에 묶여 있으면 푼다**(`TrackingService.kt:631-639`) |
| **1단계 ↔ 2단계 Task 2** | §6.4 3번 규칙("events 에 쓴 직후 강제 업로드") | 1단계가 `uploader` 안에 그 갈래를 이미 만들었으면 Task 2 는 "사건이 있었다"만 알린다. **없으면 1단계가 덜 끝난 것이다** — 그 규칙은 설계서 §6.4 가 1단계 몫으로 둔 업로드 판정의 일부다. 없으면 Task 2 에서 만들고 1단계 계획서에 어긋난 것을 보고한다 |
| **1단계 ↔ 2단계 Task 3** | `Child/TrailUploader.swift` 의 `buildSegments`, `SegmentDoc` 만들기, `namer` 주입 자리 | 1단계는 `placeName: ""` 로 올렸을 것이다. Task 3 이 그 함수를 통째로 바꾸고 `PlaceNamer` 를 주입받게 한다 — 초기화 시그니처가 바뀌므로 1단계의 `TrailUploader` 생성 자리(`TrackingCoordinator`)와 테스트를 같이 고친다. `buildSegments` 가 `async` 가 아니었으면 `async` 로 바꾸고 부르는 쪽에 `await` 를 더한다 |
| **1단계 ↔ 2단계 Task 3** | `Duration.초` 같은 시간 변환 헬퍼 | 1단계가 이미 뒀으면 **다시 만들지 않는다.** 없으면 `TrailUploader.swift` 안의 `private extension` 으로 둔다(공용으로 올리는 것은 쓰는 곳이 둘 이상 생길 때) |
| **1단계 ↔ 2단계 Task 1·4** | `ios/KidCareTests/golden/` 과 `GoldenComparisonTests.골든_리소스가_번들에_있다` | 1단계가 다섯(`locationFilter`·`adaptiveMovementDetector`·`movementTrailFilter`·`segmentBuilder`·`trailCodec`)을 더한다. Task 1 은 그 검사 **안에 두 덩어리를 더할 뿐** 기존 줄을 안 건드린다. 테스트 이름의 "다섯 개"는 그때 개수로 고친다 |
| **1단계 ↔ 2단계 Task 1** | `app/src/test/.../GoldenFileWriterTest.kt` | 1단계가 `@Test` 다섯과 생성기 다섯을 더한다. Task 1 은 **파일 끝에** 둘을 더한다 — 같은 파일이므로 **1단계가 커밋된 뒤에 시작한다.** `latOffset` 같은 도우미를 1단계가 이미 만들었으면 다시 만들지 않고 그것을 쓴다 |
| **1단계 ↔ 2단계 Task 2** | `Core/Documents.swift` — 1단계가 `ChildStatusDoc.platform` 과 `TrailDoc`/`SegmentDoc` 을 만진다 | Task 2 는 `PlaceDoc` 아래와 `EventDoc` 아래에 `extension` 을 더한다. 파일 안 자리가 달라 충돌이 없다. 다만 **같은 파일이라 순서 의존**이다 |
| **1단계 ↔ 2단계 Task 2** | `Core/EventRepository.swift` | 1단계는 이 파일을 안 만진다(설계서 §3.3 은 `add` 를 이 단계 몫으로 둔다). 1단계가 먼저 더했으면 중복을 만들지 말고 그 구현이 판정 기록 14(항상 `read: false`)를 지키는지 확인한다 |
| **1단계 ↔ 2단계 Task 2** | `Info.plist`/`project.yml` 의 `UIBackgroundModes`·위치 사용 설명 둘 | 1단계가 넣는다(설계서 §14). 2단계는 **아무것도 더하지 않는다** — 지역 감시는 같은 '항상 허용' 권한을 쓴다. 없으면 1단계가 덜 끝난 것이다 |
| **2단계 Task 1 ↔ Task 2** | `Place`·`PlaceState`·`GeofenceEvaluator`·`GeofenceRegionSelection` | 순서 의존. Task 2 는 Task 1 이 커밋된 뒤에 컴파일된다 |
| **2단계 Task 1 ↔ Task 3** | `PlaceNameCache` | 순서 의존. `actor PlaceNamer` 의 저장 프로퍼티가 되려면 `Sendable` 한 **값 타입**이어야 한다 |
| **2단계 Task 2 ↔ Task 3** | `Child/TrailUploader.swift`, `Child/TrackingCoordinator.swift` | Task 2 는 `TrackingCoordinator` 만, Task 3 은 `TrailUploader` 와 그 생성 한 줄만 만진다. Task 3 이 `buildSegments` 를 `async` 로 바꾸면 Task 2 가 더한 업로드 호출부에 `await` 가 필요할 수 있다 — Task 3 에서 같이 고친다 |
| **2단계 Task 2 ↔ 3단계** | `permission_off` 이벤트, 아이 화면 | 3단계가 `ConditionWatcher` 로 쓴다. `EventRepository.add` 와 `EventDoc.firestoreData` 를 이 단계가 먼저 만들어 두므로 3단계는 그대로 쓴다 |
| **2단계 Task 2 ↔ 4단계** | `Guardian/ChildPlatform` 과 세 화면 잠금 | 겹치지 않는다. `platform` 필드는 1단계가 상태 문서에 심는다 |
| **2단계 ↔ 보호자 앱(안 고침)** | `Guardian/AlertText`·`AlertViewModel` 이 `place_enter`/`place_exit` 를 이미 그린다 | **보호자 쪽은 한 줄도 안 바뀐다.** 이 단계가 쓰는 `type` 값 둘은 `EventType.placeEnter`/`placeExit` 상수를 참조하므로 리터럴이 갈릴 일이 없다 |
| **작업 트리 상태 ↔ 2단계 시작** | 다른 에이전트가 1단계 계획서를 `docs/superpowers/plans/` 에 커밋하는 중이다(2026-09-22) | 선행 조건 `git status --short` 가 비어 있어야 한다. 이 계획서 파일 자체도 그 에이전트의 커밋과 같은 폴더에 들어가므로, **옮겨 넣기 전에 1단계 계획서 커밋이 끝났는지 확인한다** |
| **코틀린 주석의 낡은 값 ↔ Task 2** | `EventRepository.kt:25`·`PlaceWatcher.kt:131-132` 가 `at` 창을 "24시간"으로 적었다 | 규칙이 7일이다(`firestore.rules:306-310`). **코틀린 주석을 고치지 않는다**(`app/src/main` 금지). 판정 기록 12 에 적고, 4단계 개발일지의 "안드로이드에서 찾은 것"에 한 줄 남긴다 |
