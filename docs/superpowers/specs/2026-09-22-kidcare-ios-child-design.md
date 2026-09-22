# KidCare iOS — 아이(child) 역할 설계서

작성일: 2026-09-22
상태: 설계 승인됨, 구현 시작 전
기준 커밋: `93e5b87` (브랜치 `ios-guardian-app`)
대상: `ios/` 와 `i18n/ko.json`·`i18n/en.json`, `tools/ios-strings.py`.
예외 하나: 골든 파일 생성기 `app/src/test/java/com/kidcare/family/logic/GoldenFileWriterTest.kt`
(§11.2 와 §17 열린 질문 1 참고). **`app/src/main` 은 한 줄도 건드리지 않는다.
`firestore.rules` 도 고치지 않는다.**

> **이 문서와 코드가 다르면 코드가 맞다.** 고칠 때는 문장을 다듬지 말고 해당 파일을
> 열어 대조한 뒤 고칠 것.
>
> **정본은 안드로이드 아이 구현이다.** Firestore 문서 스키마는
> `app/src/main/java/com/kidcare/family/core/model/Documents.kt`, 수집·판정 상수는
> `app/src/main/java/com/kidcare/family/logic/` 와 `.../child/` 다. 이 문서의 모든
> 숫자에는 그 파일의 줄 번호를 붙였다.

---

## 1. 무엇을 만드는가

아이폰을 쓰는 **아이**가 안드로이드 아이 폰과 **같은 Firestore 문서를 쓰게** 한다.
보호자 앱(안드로이드든 아이폰이든)은 한 줄도 안 바뀌어도 그 문서를 읽고 지도와
타임라인을 그린다.

기존 아이폰 앱 하나에 아이 역할을 켠다. 새 앱을 만들지 않는다.

### 만드는 것

| 기능 | 안드로이드 정본 |
|---|---|
| 위치 수집 | `child/LocationCollector.kt` |
| 이동 판정과 경로점 선별 | `logic/AdaptiveMovementDetector.kt`, `logic/MovementTrailFilter.kt` |
| 구간 요약(머무름·이동) | `logic/SegmentBuilder.kt` |
| 하루 문서 업로드 | `child/TrailUploader.kt`, `core/TrailRepository.kt` |
| 상태 보고(위치·배터리·통신) | `child/StatusReporter.kt` |
| 장소 도착·이탈 알림 | `child/PlaceWatcher.kt`, `logic/GeofenceEvaluator.kt` |
| 머무른 곳 이름 | `child/PlaceNamer.kt`, `logic/PlaceNameCache.kt` |
| 배터리·권한 경고 | `child/ConditionWatcher.kt` |
| 아이 화면 | `child/ChildHomeActivity.kt` |
| 페어링(초대 코드, 역할 child) | `core/FamilyRepository.joinFamily` |

### 만들지 않는 것 (아이폰에서 불가능하거나 정직하게 할 수 없는 것)

| 안드로이드 아이 기능 | 아이폰 |
|---|---|
| 소리 모드 원격 전환 (`set_ringer`) | **API 자체가 없다.** 무음↔벨 전환을 제3자 앱이 할 수 없다 |
| 예약 적용 (`ScheduleApplier`) | 위와 같은 이유. 적용할 대상이 없다 |
| 소리 모드 조회 (`query_ringer`) | 읽는 API도 없다 (`AVAudioSession` 은 내 앱의 출력만 안다) |
| 핸드폰 찾기 (`find_phone`) | 무음을 뚫으려면 Critical Alert 권한이 필요하고 애플에 따로 신청·승인받아야 한다 |
| 원격 알람 (`set_alarm`) | 앱이 시스템 알람을 만들 수 없다. 로컬 알림은 무음이면 안 울린다 |
| 메시지 표시 (`message`) | 푸시 없이 잠든 앱을 깨울 방법이 없다(§1 FCM 금지) |
| 실시간 보기 (`start_live_tracking`) | 아래 "명령을 아예 안 듣는다" 참고 |
| 지금 위치 확인 (`locate_now`) | 위와 같다 |

**명령을 아예 안 듣는다.** 안드로이드 아이 폰은 `commands/` 컬렉션에 상시 리스너를
걸고 있고(`TrackingService.kt:449` `subscribeToCommands`), 그게 부모의 물음이 아이
폰에 닿는 유일한 길이다. 아이폰에서는 그 리스너가 **앱이 잠들면 콜백을 주지 않는다** —
그리고 푸시(FCM)를 쓰지 않기로 했으므로 깨울 방법이 없다. 보호자 화면은 60초 안에
응답이 없으면 "애기폰이 응답하지 않아요"를 띄우는데(`logic/DisconnectRule.kt`),
그 화면은 **영원히 그 상태로 남는다.**

그래서 아이폰 아이는 `commands/` 를 구독하지 않고, 보호자 화면은 그 아이에게
명령 버튼을 아예 못 누르게 막는다(§10). 반쪽짜리를 내놓느니 못 한다고 말한다.

**대신 아이폰 아이는 스스로 올린다.** 부모가 물어볼 수 없으므로 아이 폰이 주기적으로
올린다(§6.4). 이게 안드로이드와 가장 크게 다른 한 가지다.

---

## 2. 결정된 것 (바꾸지 않는다)

주인과 이미 합의한 것이다. 구현 중에 되묻지 않는다.

1. **수집 밀도는 안드로이드와 같다.** 이동 중 약 5초. 배터리는 안드로이드가
   아끼는 자리에서만, 같은 방식(이동 여부에 따라)으로 아낀다.
2. **앱은 하나다.** 지금 아이폰 앱의 역할 선택 화면이 아이를 막고 있는데
   (`ios/KidCare/Onboarding/RoleSelectView.swift:89-97`), 그 막이를 푼다. 아이는
   아이 화면만 본다 — 보호자 탭은 하나도 안 보인다. 페어링은 지금 있는 초대 코드
   흐름을 그대로 쓰고 역할만 child 로 저장한다.
3. **계산은 아이 폰이 한다.** 안드로이드와 똑같이, 같은 Firestore 문서를 쓴다.
   보호자 앱은 아무것도 안 바뀐다. 순수 로직은 Swift 로 옮기고 2단계가 한 것처럼
   골든 파일로 대조한다.
4. **보호자 화면은 정직하게 막는다.** 아이가 아이폰이면 못 하는 조작을 회색으로
   잠그고 왜 안 되는지 말한다. 영원히 안 끝날 명령을 보내지 않는다.

---

## 3. 아키텍처 — 만들 Swift 파일

지금 아이폰 앱의 배치를 그대로 따른다.

- `Logic/` — **Foundation 만 import 한다.** Firebase·CoreLocation·SwiftUI 금지.
  골든 파일 대조 대상이다.
- `Core/` — Firestore 를 아는 자리.
- `Child/` — 새 폴더. `Guardian/` 과 같은 층이다. CoreLocation 과 화면이 여기 있다.

### 3.1 `Logic/` — 새로 옮기는 순수 로직 (8개)

| 파일 | 하는 일 하나 | 안드로이드 정본 |
|---|---|---|
| `Logic/LocationFilter.swift` | 이 점을 상태로 올릴지 판정한다. 하버사인 거리도 여기 | `logic/LocationFilter.kt` |
| `Logic/AdaptiveMovementDetector.swift` | 좌표·속도로 이동을 확정/해제하는 상태 기계 | `logic/AdaptiveMovementDetector.kt` |
| `Logic/MovementTrailFilter.swift` | 이 점을 경로로 남길지, 좌표가 이동 증거인지 | `logic/MovementTrailFilter.kt` |
| `Logic/SegmentBuilder.swift` | 점 목록 → 머무름/이동 구간 | `logic/SegmentBuilder.kt` |
| `Logic/TrailCodec.swift` | 점 ↔ CSV 한 줄, 2000개 상한 LTTB 솎기 | `logic/TrailCodec.kt` |
| `Logic/GeofenceEvaluator.swift` | 점 하나로 장소 도착·이탈 판정(히스테리시스·중복 억제) | `logic/GeofenceEvaluator.kt` |
| `Logic/PlaceNameCache.swift` | 좌표 근처의 아는 이름 찾기 | `logic/PlaceNameCache.kt` |
| `Logic/GeofenceRegionSelection.swift` | 장소 목록에서 OS 에 걸 20개를 고르는 규칙 | `child/PlaceWatcher.kt:168-171` (코틀린에서는 인라인) |

### 3.2 고치는 기존 파일 (2개)

- **`Logic/Fix.swift`** — `speedAccuracy: Double = .infinity` 를 더한다.
  지금은 일부러 빼 뒀다(그 파일 주석 :8-9): 그 값을 쓰는 로직이 보호자 앱에 없어서다.
  아이 역할은 `AdaptiveMovementDetector.hasReliableWalkingSpeed`
  (`AdaptiveMovementDetector.kt:147-150`)와 `MovementTrailFilter.shouldRecord`
  (`MovementTrailFilter.kt:126-132`)가 그 값으로 갈린다. `init` 의 마지막 기본값
  매개변수로 더하면 기존 호출부는 한 곳도 안 고친다.
- **`Logic/Segment.swift`** — `nameLat`/`nameLng` 를 더한다. 지금은 일부러 뺐다
  (그 파일 주석 :18-27): 보호자는 `placeName` 결과만 읽으므로 가질 수도 없는 값이다.
  아이 역할은 그 둘로 이름을 묻는다(`SegmentBuilder.kt:163-183`).
  **memberwise 초기화가 기본값을 못 받으므로 명시적 `init` 을 쓴다** —
  `nameLat: Double? = nil` 을 받아 `nil` 이면 `lat` 을 쓰는 모양이면 지금 보호자
  코드의 `Segment(...)` 호출이 한 곳도 안 깨진다.

### 3.3 `Core/` — 더하는 함수 (새 파일 1개 + 기존 3개에 추가)

| 파일 | 더하는 것 | 안드로이드 정본 |
|---|---|---|
| `Core/ChildStatusReporter.swift` (신규) | `children/{childUid}` 문서 덮어쓰기. `platform: "ios"` 포함 | `child/StatusReporter.kt` |
| `Core/TrailRepository.swift` | `save(familyId:childUid:doc:)` — 지금은 `fetch` 만 있다(:36) | `core/TrailRepository.kt:31` |
| `Core/EventRepository.swift` | `add(familyId:doc:)` — 지금은 `observeEvents`·`markRead` 만 있다 | `core/EventRepository.kt:53` |
| `Core/Documents.swift` | `ChildStatusDoc` 에 `platform: String = ""` | — (안드로이드에는 안 더한다, §10.2) |

`Core/PlaceRepository.swift` 는 **새 함수가 필요 없다.** 아이 폰은 이미 있는
`observePlaces(familyId:childUid:)`(:32)를 자기 uid 로 구독한다(§7.3). 1회 읽기용
함수를 따로 두지 않는 이유: 구독의 첫 스냅샷이 곧 그 1회 읽기라 두 벌이 된다.

### 3.4 `Child/` — 새 폴더 (15개)

파일 하나에 책임 하나다.

| 파일 | 하는 일 하나 | 안드로이드 정본 |
|---|---|---|
| `Child/LocationCollector.swift` | `CLLocationManager` 를 감싸고, 수집 모드에 따라 정확도·거리 필터를 바꾼다 | `child/LocationCollector.kt` |
| `Child/CollectionMode.swift` | 모드 → (정확도, 거리 필터, 소프트웨어 간격) 표 하나. 순수 값이라 단위 테스트 대상 | `LocationCollector.kt:63-70` |
| `Child/TrackingCoordinator.swift` | 점 하나가 들어왔을 때의 순서를 정한다. `lastFix`·`lastTrailFix`·판정기·장소 안 여부를 소유 | `child/TrackingService.kt:532` `handle()` |
| `Child/TrailBuffer.swift` | 오늘 점을 메모리에 쌓고 자정을 넘기면 비운다 | `TrailUploader.kt:95-104` |
| `Child/TrailStore.swift` | 오늘 점을 파일 끝에 한 줄씩 덧붙인다(프로세스가 죽어도 남게) | `child/TrailStore.kt` |
| `Child/TrailUploader.swift` | 하루 문서 하나를 만들어 올린다. 머무름에 이름을 붙인다 | `child/TrailUploader.kt` |
| `Child/PlaceWatcher.swift` | 장소를 읽어 OS 지오펜스를 걸고, 점마다 판정해 이벤트를 쓴다 | `child/PlaceWatcher.kt` |
| `Child/PlaceStateStore.swift` | "이 장소 안에 있었다"를 프로세스 밖에 남긴다 | `child/PlaceStateStore.kt` |
| `Child/PlaceNamer.swift` | 좌표 → 이름. 캐시와 초당 1건 제한을 가진 `actor` | `child/PlaceNamer.kt` |
| `Child/ConditionWatcher.swift` | 배터리·권한이 나빠진 순간 한 번만 이벤트를 쓴다 | `child/ConditionWatcher.kt` |
| `Child/DeviceState.swift` | 배터리 %, 충전 중, 통신 종류, 저전력 모드를 읽기만 한다 | `child/NetworkState.kt` + `TrackingService.kt:823-838` |
| `Child/ChildPermissions.swift` | 아이폰이 요구하는 권한 넷의 상태와 이름 | `onboarding/PermissionStep.kt` |
| `Child/ChildHomeModel.swift` | 아이 화면이 무엇을 말할지 정한다(`@Observable`) | `ChildHomeActivity.kt:70-82` |
| `Child/ChildHomeView.swift` | 그 문장을 그린다. 버튼 하나 | `ChildHomeActivity.kt` + `activity_child_home.xml` |
| `Child/ChildRootView.swift` | 역할이 child 일 때의 뿌리. 탭이 없다 | `RouterActivity` 의 child 갈래 |

### 3.5 `Guardian/` — 더하는 것 (1개 + 기존 화면 수정)

| 파일 | 하는 일 |
|---|---|
| `Guardian/ChildPlatform.swift` (신규) | 상태 문서의 `platform` → "이 아이에게 무엇을 보낼 수 있나" |

`ControlViewModel`/`ControlView`, `MapViewModel`/`ChildMapView`,
`ScheduleViewModel`/`ScheduleView` 가 그 값을 읽어 잠근다. 자세한 것은 §10.

### 3.6 동시성 — Swift 6 엄격 모드에서 누가 어디 있나

- `TrackingCoordinator`·`LocationCollector`·`ChildHomeModel` 은 `@MainActor` 다.
  `CLLocationManagerDelegate` 콜백은 매니저를 만든 스레드의 런루프로 오므로
  메인에서 만들면 메인으로 온다 — 안드로이드가 `context.mainLooper` 를 넘기는 것
  (`LocationCollector.kt:150`)과 같은 선택이고, `buffer` 를 만지는 스레드가 하나로
  유지돼 잠금이 필요 없어지는 것도 같다(`TrailUploader.kt:91-93` 주석).
- `PlaceNamer` 는 `actor` 다. 캐시와 "마지막 요청 시각"을 그 안에 둔다 —
  코틀린이 companion + `Mutex` 로 한 일(`PlaceNamer.kt:158-159`)을 언어 기능으로
  대신한다.
- `PlaceStateStore`·`TrailStore` 는 `@MainActor` 에서만 불린다.
- **`@unchecked Sendable` 과 `nonisolated(unsafe)` 를 앱 코드에 쓰지 않는다.**
  Firestore 리스너 핸들은 지금 보호자 코드가 쓰는 방식을 그대로 따른다.

---

## 4. 상수 대조표 — 안드로이드 `파일:줄` → 아이폰

**이 표가 이 설계서의 핵심이다.** 값을 바꾸고 싶으면 안드로이드를 먼저 바꾸고
여기를 고친다. 한쪽만 바꾸면 두 폰이 같은 날을 다르게 기록한다.

### 4.1 `logic/LocationFilter.kt` — 그대로 옮긴다

| 상수 | 값 | 줄 | 아이폰 |
|---|---|---|---|
| `MAX_ACCURACY_METERS` | 50 m | :78 | 같은 값. `Double` 로 넓힘 |
| `FALLBACK_MAX_ACCURACY_METERS` | 100 m | :88 | 같은 값 |
| `STALE_FALLBACK_MILLIS` | 15분 | :97 | 같은 값 |
| `MIN_MOVE_METERS` | 25 m | :107 | 같은 값 |
| `MAX_SPEED_MPS` | 55.6 (시속 200km) | :110 | 같은 값 |
| `HEARTBEAT_MILLIS` | 10분 | :113 | 같은 값 |
| `EARTH_RADIUS_METERS` | 6,371,000 | :115 | 같은 값 |

`Float` → `Double` 로 넓히는 것이 유일한 차이다. 골든 대조에서 경계값이 갈릴 수
있으므로 **생성기는 문턱 정확히 위·아래를 `Float` 로 표현 가능한 값으로만 만든다**
(§11.2).

### 4.2 `logic/AdaptiveMovementDetector.kt` — 그대로 옮긴다

| 상수 | 값 | 줄 |
|---|---|---|
| `MAX_ACCURACY_METERS` | 50 m | :175 |
| `FAST_PROBE_MILLIS` | 30초 | :176 |
| `STOP_CONFIRM_MILLIS` | 60초 | :177 |
| `MIN_CONFIRM_MILLIS` | 10초 | :178 |
| `MIN_CONFIRM_POINTS` | 3 | :179 |
| `SPEED_TRUST_MAX_ACCURACY_METERS` | 15 m | :180 |
| `MIN_CONFIDENT_SPEED_MPS` | 0.35 | :181 |
| `MIN_SPEED_DISPLACEMENT_METERS` | 3 m | :182 |
| `MIN_NET_DISPLACEMENT_METERS` | 15 m | :193 |
| `SLOW_PROBE_MIN_DISPLACEMENT_METERS` | 15 m | :194 |
| `STOP_RADIUS_METERS` | 15 m | :195 |
| `NOISE_MULTIPLIER` | 1.0 | :209 |
| `MIN_PROGRESS_RATIO` | 0.6 | :210 |

전부 같은 값. 이 판정기가 아이폰에서 **안드로이드보다 더 중요하다** — 안드로이드는
활동 인식(Activity Recognition) 전환을 한 비트 더 갖고 있지만 아이폰은 v1 에서 그걸
안 쓰기로 했다(§17 열린 질문 5). 안드로이드도 활동 인식 권한이 없으면 이 판정기
하나로 돈다(`ConditionWatcher.kt:47-48`)므로 이미 검증된 갈래다.

### 4.3 `logic/MovementTrailFilter.kt` — 그대로 옮긴다

| 상수 | 값 | 줄 |
|---|---|---|
| `MIN_INTERVAL_MILLIS` | 5초 | :19 |
| `MAX_ACCURACY_METERS` | 50 m | :30 |
| `DISPLACEMENT_EVIDENCE_METERS` | 50 m | :42 |
| `DISPLACEMENT_EVIDENCE_NOISE_MULTIPLIER` | 1.5 | :55 |
| `MOVING_SPEED_MPS` | 0.7 | :58 |
| `MIN_DISPLACEMENT_METERS` | 3 m | :76 |
| `SPEED_TRUST_MAX_ACCURACY_METERS` | 15 m | :79 |
| `MIN_CONFIDENT_SPEED_MPS` | 0.35 | :82 |
| `MIN_SPEED_EVIDENCE_DISPLACEMENT_METERS` | 3 m | :85 |

`MIN_INTERVAL_MILLIS`(5초)가 아이폰에서 **밀도를 지키는 유일한 장치**가 된다.
CoreLocation 은 "5초마다 한 점"을 요청할 수 없고 있는 대로 준다(§5.1) — 그래서
5초 간격은 이 필터가 만든다. 안드로이드에서는 요청 주기와 이 필터가 둘 다 5초라
이중 방어였는데, 아이폰에서는 이쪽만 남는다.

### 4.4 `logic/SegmentBuilder.kt` — 그대로 옮긴다

| 상수 | 값 | 줄 |
|---|---|---|
| `STAY_RADIUS_METERS` | 40 m | :63 |
| `MIN_STAY_MILLIS` | 5분 | :66 |
| `EXIT_CONFIRM_POINTS` | 2 | :69 |
| `MIN_WEIGHT_ACCURACY_METERS` | 5 m | :79 |

### 4.5 `logic/TrailCodec.kt`

| 상수 | 값 | 줄 | 아이폰 |
|---|---|---|---|
| `MAX_POINTS` | 2000 | :46 | 같은 값 |

CSV 형식(`encodeLine` :49-50)은 **글자 하나까지 같아야 한다** — 두 플랫폼이 같은
파일을 읽는 일은 없지만, 골든 대조가 이 문자열을 직접 비교한다. 코틀린이
`Double.toString`/`Float.toString` 이 만드는 형식을 그대로 쓰는데(:25-27 주석),
Swift 의 `String(describing:)` 은 같은 값에 다른 글자를 낼 수 있다. **그러므로
골든 대조는 문자열이 아니라 `decode` 한 뒤의 값으로 한다** — `encodeLine` 은
"자기 자신이 `decode` 로 되돌아오는가"만 확인한다(왕복 테스트).

### 4.6 `logic/GeofenceEvaluator.kt` — 그대로 옮긴다

| 상수 | 값 | 줄 |
|---|---|---|
| `EXIT_MARGIN_METERS` | 50 m | :52 |
| `DEDUPE_MILLIS` | 5분 | :55 |
| `MAX_ACCURACY_METERS` | `FALLBACK_MAX_ACCURACY_METERS`(100 m) 참조 | :69 |

마지막 것은 **값이 아니라 참조를 옮긴다.** 코틀린이 일부러 숫자를 다시 안 적었다
(:64-67 주석) — 따라 적으면 나중에 한쪽만 바뀐다.

### 4.7 `logic/PlaceNameCache.kt` — 그대로 옮긴다

| 상수 | 값 | 줄 |
|---|---|---|
| `MATCH_RADIUS_METERS` | 30 m | :67 |
| `MAX_ENTRIES` | 300 | :70 |

### 4.8 `child/LocationCollector.kt` — **여기가 유일하게 모양이 바뀐다**

| 안드로이드 | 값 | 줄 | 아이폰 |
|---|---|---|---|
| `MOVING_INTERVAL_MILLIS` | 5초 | :205 | 소프트웨어 간격 5초 + `desiredAccuracy = .best` + `distanceFilter = 3` |
| `LIVE_INTERVAL_MILLIS` | 2초 | :207 | **안 옮긴다.** 실시간 보기가 범위 밖이다 |
| `SLOW_PROBE_INTERVAL_MILLIS` | 30초 | :210 | 소프트웨어 간격 30초 + `.nearestTenMeters` + 거리 필터 없음 |
| `KNOWN_PLACE_INTERVAL_MILLIS` | 60초 | :213 | 소프트웨어 간격 60초 + `.nearestTenMeters` + 거리 필터 없음 |
| `STILL_INTERVAL_MILLIS` | 60초 | :230 | 같은 60초. **다만 켜지는 방아쇠가 다르다** — 아래 참고 |
| `MOVING_MIN_UPDATE_DISTANCE_METERS` | 3 m | :233 | `distanceFilter = 3`, **이동 확정일 때만**(:109-121 과 같은 조건) |
| `Priority.PRIORITY_HIGH_ACCURACY` | — | :97 | 이동은 `kCLLocationAccuracyBest`, 정지는 `kCLLocationAccuracyNearestTenMeters` |
| `Granularity.GRANULARITY_FINE` | — | :99 | `accuracyAuthorization == .fullAccuracy` 확인(§8.2) |
| `setMaxUpdateAgeMillis(0)` | — | :101 | 대응 없음. 연속 스트림이라 캐시된 옛 점이 안 온다 |
| `setWaitForAccurateLocation(true)` | — | :107 | 대응 없음. 정확도 게이트(50 m)가 같은 일을 한다 |

**정지에 `.nearestTenMeters` 를 쓰는 근거.** 안드로이드는 정지에도 일부러
HIGH_ACCURACY 를 쓴다(:81-96) — 하루의 대부분이 정지 구간이고 머무른 곳 이름이 그
점들로 정해지기 때문이다. 거부한 대안은 `PRIORITY_BALANCED_POWER_ACCURACY`
(WiFi·기지국, 오차 20~60 m)였다. 아이폰의 `.nearestTenMeters` 는 그 거부 대상이
아니라 GNSS 를 쓰되 듀티 사이클을 허용하는 등급이고, 오차 10 m 는 `MAX_ACCURACY_METERS`
(50 m)와 `STAY_RADIUS_METERS`(40 m) 안에 넉넉히 든다. **`.hundredMeters` 이하로는
절대 내리지 않는다** — 그게 안드로이드가 거부한 그 등급이다.

**정지에 `distanceFilter` 를 걸지 않는 근거.** 걸면 완전히 멈춘 폰이 콜백을 하나도
못 받아 하트비트(10분, `LocationFilter.kt:113`)가 굶고 상태 문서의 `at` 이 멈춘다 —
안드로이드가 정확히 같은 이유로 이동 확정일 때만 걸었다(`known-issues.md` 11번,
`LocationCollector.kt:109-121`).

**정지 모드를 무엇이 켜나 — 아이폰에만 있는 상수 하나.**
안드로이드의 정지 60초는 **활동 인식이 STILL 을 보고할 때** 켜진다
(`LocationCollector.kt:65`). 아이폰은 v1 에서 CoreMotion 을 안 쓰므로(§17 열린 질문 5)
그 방아쇠가 없다. 그대로 두면 가만히 있는 폰이 영영 SLOW_PROBE(30초)에 머물러
안드로이드보다 배터리를 두 배로 쓴다.

그래서 **아이폰에만 있는 상수 하나를 새로 만든다.**

| 상수 | 값 | 안드로이드 대응 |
|---|---|---|
| `STILL_ESCALATE_MILLIS` | 5분 | **없다.** 활동 인식 전환이 하던 일을 시간으로 대신한다 |

판정기가 SLOW_PROBE 에 **연속 5분** 머물면(=그 사이 FAST_PROBE 로 한 번도 못
올라갔으면) 정지 모드(60초)로 내려간다. FAST_PROBE 로 올라가는 순간 이 시계는
0 으로 돌아간다. 5분인 이유는 안드로이드의 활동 인식이 STILL 을 보고하기까지
걸리는 시간(30초~2분, `LocationCollector.kt:220-221`)보다 넉넉히 길게 잡아
**진짜 정지에만 켜지게** 하려는 것이다. 짧게 잡으면 신호등 앞에서 기다리는 1분이
정지로 내려가 다시 올라오는 데 30초가 더 걸린다.

이 값은 **안드로이드에 대응이 없으므로 골든 대조 대상이 아니다.** 단위 테스트
(`CollectionModeTests`)로만 고정한다.

### 4.9 `child/TrackingService.kt`

| 안드로이드 | 값 | 줄 | 아이폰 |
|---|---|---|---|
| `STAY_ANCHOR_INTERVAL_MILLIS` | 5분 | :905 | 같은 값 |
| `COORDINATE_KICK_WINDOW_MILLIS` | 5분 | :912 | 같은 값 |
| `CONDITION_CHECK_INTERVAL_MILLIS` | 60초 | :913 | 같은 값 |
| `SAFETY_UPLOAD_INTERVAL_MILLIS` | 24시간 | :902 | `UPLOAD_IDLE_INTERVAL_MILLIS` **4시간**으로 내린다(§6.4). `locate_now` 가 없어져 이게 유일한 통로다 |
| `LIVE_REPORT_INTERVAL_MILLIS` | 2초 | :903 | 안 옮긴다 |
| `MAX_LIVE_DURATION_SECONDS` | 10분 | :904 | 안 옮긴다 |

### 4.10 `child/TrailUploader.kt`, `child/PlaceNamer.kt`, `child/PlaceWatcher.kt`, `child/ConditionWatcher.kt`, `core/EventRepository.kt`

| 상수 | 값 | 위치 | 아이폰 |
|---|---|---|---|
| `GEOCODE_BUDGET_MILLIS` | 3초 | `TrailUploader.kt:235` | 같은 값 |
| `TIMEOUT_MILLIS` | 5초 | `PlaceNamer.kt:152` | `URLRequest.timeoutInterval` 5초 |
| `MIN_INTERVAL_MILLIS` | 1초 | `PlaceNamer.kt:153` | 같은 값(actor 안) |
| `ENDPOINT` | Nominatim reverse | `PlaceNamer.kt:146` | 같은 주소(§7) |
| `USER_AGENT` | `KidCare/1.0 (com.kidcare.family)` | `PlaceNamer.kt:150` | 같은 값 |
| `MAX_GEOFENCES` | 20 | `PlaceWatcher.kt:217` | 같은 값. 아이폰의 OS 상한과 정확히 같다 |
| `LOW_PERCENT` | 15 | `ConditionWatcher.kt:173` | 같은 값 |
| `REARM_PERCENT` | 20 | `ConditionWatcher.kt:176` | 같은 값 |
| `RECENT_LIMIT` | 100 | `core/EventRepository.kt:45` | 아이 쪽은 안 읽는다 |
| `FILE_NAME` | `trail_today.csv` | `TrailStore.kt:68` | 같은 이름, Application Support 안 |

### 4.11 찾지 못한 상수 — **없기 때문이다**

작업 지시가 요구한 것 중 안드로이드에 **존재하지 않는** 것들이다. 아이폰에서
새로 만들지 않는다(없는 것을 지어내면 두 플랫폼이 갈린다).

- **업로드 재시도·백오프 상수가 없다.** `TrackingService.kt:679-681` 이 실패해도
  `lastUploadAt` 을 먼저 갱신한다 — "실패가 이어질 때 fix 마다 재시도해 같은 비용을
  반복해서 물지 않으려고". 즉 재시도는 **다음 주기**뿐이고 백오프는 아예 없다.
  진짜 재시도는 Firestore SDK 의 오프라인 큐가 한다(`known-issues.md` 19번:
  "오프라인 처리는 이미 켜져 있다 — 다시 만들지 말 것"). 아이폰도 똑같이 한다.
- **업로드 배치 크기 상수가 없다.** 배치라고 부를 것은 하루 문서 하나뿐이고,
  그 안의 점 개수 상한이 `TrailCodec.MAX_POINTS`(2000) 하나다.
- **지오코딩 재시도 상수가 없다.** 실패하면 그 구간은 이번에 이름 없이 올라가고
  다음 업로드가 다시 묻는다(`TrailUploader.kt:168-171`).
- **명령 제한시간 상수는 보호자 쪽에만 있다.** 아이 쪽에는 없다.

---

## 5. 아이폰에서의 위치 수집

### 5.1 안드로이드의 "시간 간격"이 아이폰에서 무엇이 되나

안드로이드 `LocationRequest` 는 **"몇 밀리초마다 하나"** 를 요청한다.
`CLLocationManager` 에는 그런 손잡이가 없다 — `startUpdatingLocation()` 을 켜면
새 측정이 생길 때마다 `didUpdateLocations` 가 온다(GNSS 가 붙어 있으면 대략 1초에
한 번). 손잡이는 둘뿐이다.

- `desiredAccuracy` — 얼마나 정확하게. **이게 배터리를 정한다.** 낮추면 iOS 가
  GNSS 를 껐다 켰다 할 수 있다.
- `distanceFilter` — 이만큼 옮겨져야 콜백을 준다. 안드로이드의
  `setMinUpdateDistanceMeters` 와 정확히 같은 뜻이다.

그래서 **간격은 우리 코드가 만든다**: 스트림을 계속 받되, 마지막으로 처리한 점에서
모드별 간격이 안 지났으면 그 자리에서 버린다. 이동 중 5초는 이미
`MovementTrailFilter.MIN_INTERVAL_MILLIS`(:19)가 강제하고 있으므로 경로 밀도는
안드로이드와 같다. 정지의 60초는 `CollectionMode` 표가 강제한다.

| 모드 | 언제 | `desiredAccuracy` | `distanceFilter` | 소프트웨어 간격 |
|---|---|---|---|---|
| 이동 확정 (MOVING) | 판정기가 MOVING | `.best` | 3 m | 5초 |
| 이동 확인 (FAST_PROBE) | 판정기가 FAST_PROBE | `.best` | 없음 | 5초 |
| 저주기 확인 (SLOW_PROBE) | 판정기가 SLOW_PROBE | `.nearestTenMeters` | 없음 | 30초 |
| 등록 장소 머무름 | 장소 반경 안 & 이동 아님 | `.nearestTenMeters` | 없음 | 60초 |
| 정지 | SLOW_PROBE 로 `STILL_ESCALATE_MILLIS`(5분) 연속 | `.nearestTenMeters` | 없음 | 60초 |

분기 **순서**는 안드로이드 `LocationCollector.kt:63-70` 과 같다 —
등록 장소 분기가 이동 판정보다 **아래**여야 한다. 위에 두면 집 반경 안의 놀이터에
다녀오는 동안 1분 주기에 묶여 그 경로가 통째로 빈다(그 주석 :58-62).

안드로이드의 "활동 인식 정지" 갈래(`!activityMoving`)는 방아쇠가 없으므로
**SLOW_PROBE 가 5분 이어지면 정지로 내려가는 규칙**이 그 자리를 대신한다(§4.8 끝).
안드로이드도 활동 인식 권한이 꺼지면 좌표 판정기 하나로 도는 같은 모양이 된다
(`ConditionWatcher.kt:47-48`).

### 5.2 `Info.plist` 와 매니저 설정

`ios/project.yml` 의 `targets.KidCare.info.properties` 에 더한다(`Info.plist` 도
같이 갱신된다).

```
UIBackgroundModes: [location]
NSLocationWhenInUseUsageDescription:        (새 i18n 키, §8.5)
NSLocationAlwaysAndWhenInUseUsageDescription: (새 i18n 키, §8.5)
```

매니저는 **한 번만** 만들고 앱이 사는 동안 들고 있는다.

```
manager.allowsBackgroundLocationUpdates = true
manager.pausesLocationUpdatesAutomatically = false
manager.showsBackgroundLocationIndicator = true
manager.activityType = .other
```

- `pausesLocationUpdatesAutomatically = false` 가 **가장 중요한 한 줄이다.**
  기본값 `true` 면 iOS 가 "이 사람 안 움직이네" 하고 업데이트를 멈추는데,
  멈춘 뒤에는 **스스로 다시 시작하지 않는다.** 그 하루는 통째로 조용해진다.
  이 앱에서 침묵이 제일 나쁜 고장이라는 규율(`PlaceStateStore.kt:19`)이 여기 걸린다.
- `showsBackgroundLocationIndicator = true` 는 안드로이드의 상시 알림
  (`TrackingService.buildNotification`, :840)과 같은 자리다 — 몰래 감시하지
  않는다는 원칙(설계서 §1)을 아이폰에서 지키는 방법이다. 아이는 파란 표시를 보고
  지금 위치가 공유 중임을 안다.
- `.other` 를 쓰는 이유: `.fitness`/`.automotiveNavigation` 은 iOS 가 그 활동에
  맞춰 스트림을 조절한다. 아이가 걷는지 버스를 타는지는 우리가 모른다.

### 5.3 앱이 잠들거나 죽을 때

**잠들지 않는다(보통은).** `UIBackgroundModes: location` + 실행 중인
`startUpdatingLocation()` 이 있으면 iOS 는 앱을 서스펜드하지 않고 백그라운드에서
계속 돌린다. 이게 안드로이드 포그라운드 서비스에 가장 가까운 것이다.

**그래도 죽을 수 있다.** 메모리 압박으로 OS 가 종료하거나, 폰이 재부팅되거나,
아이가 앱 전환기에서 위로 밀어 강제 종료할 수 있다.

되살아나는 길 둘을 **둘 다** 건다(어느 하나가 안 될 때를 대비).

1. **중요 위치 변경** — `startMonitoringSignificantLocationChanges()`.
   약 500 m 이동 / 몇 분에 한 번, 아주 적은 배터리로 앱을 **다시 띄운다**
   (`UIApplication.LaunchOptionsKey.location` 이 실려 온다). 재부팅 뒤에도 산다.
   지오펜스 20개 자리를 안 쓴다.
2. **지역 감시** — 등록한 장소를 넘을 때 앱을 다시 띄운다(§6).

되살아나면 `TrailUploader.restore()` 와 같은 일을 한다
(`TrailUploader.kt:73-83`): 오늘 파일을 읽어 버퍼를 되찾고, 마지막 점을 필터의
기준점으로 돌려줘서 "가만히 있었는데 비스듬한 선 하나"가 안 생기게 한다.
그리고 **그 복구된 점으로는 절대 상태 문서를 쓰지 않는다** — 몇 시간 전 점이
서버 시각으로 "방금"이 되어 부모가 그걸 방금 확인한 위치로 읽는다
(`TrackingService.kt:713-717` 의 판단을 그대로 옮긴다).

**강제 종료(앱 전환기에서 위로 밀기)는 다르다.** 그 뒤로는 중요 위치 변경도
지역 감시도 앱을 되살리지 않는다 — 아이가 앱을 직접 열거나 폰을 껐다 켤 때까지
기록이 통째로 없다. 안드로이드는 `START_STICKY` 와 `BOOT_COMPLETED` 로 몇 초 안에
돌아온다(`BootReceiver.kt`). **여기가 아이폰이 안드로이드를 못 따라가는 가장 큰
자리다**(§13-2). 안드로이드도 강제 종료는 못 막고 대신 부모에게 알리기로 했는데
(`known-issues.md` 8번), 아이폰은 "되살아나지도 않는다"가 더해진다. 부모 화면의
무응답 배너(`logic/DisconnectRule`)가 그 자리를 덮는다.

> 강제 종료 뒤의 동작은 애플 문서와 현장 보고가 어긋나는 대목이다. 위 서술은
> "되살아나지 않는다"를 가정한 것이고, 4단계 실기기 검증이 이것을 확인한다
> (§17 열린 질문 3).

---

## 6. 데이터 흐름

### 6.1 점 하나가 지나는 길

안드로이드 `TrackingService.handle()`(:532-699)의 순서를 **글자 그대로** 옮긴다.
순서가 곧 계약이다.

```
CLLocationManager
  │ didUpdateLocations([CLLocation])   ← 묶음으로 올 수 있다
  ├─ 시간순 정렬 후 하나씩              (LocationCollector.kt:130 과 같은 이유:
  │                                     묶음의 lastLocation 만 쓰면 모퉁이가 사라진다)
  ├─ CollectionMode 소프트웨어 간격 게이트
  ↓  Fix
TrackingCoordinator.handle(fix)
  1. ConditionWatcher 검사 (최대 1분에 한 번)       ← 점을 버릴지와 무관하게 먼저
  2. 시계 역행 감지 → lastFix 초기화                 (:552-568)
  3. 등록 장소 안/밖 갱신 → 모드 바꿈                 (:479-494)
  4. AdaptiveMovementDetector.onFix                  (:583)
  5. MOVING 이면  → MovementTrailFilter.shouldRecord → TrailBuffer + TrailStore
     아니면       → recordStayFix (5분 기준점)        (:592-615)
        └ 좌표 변위 증거면 이동 확인을 켠다           (:606-614)
  6. 좌표 변위 이동 확인 만료 검사                     (:621-627)
  7. LocationFilter.decide(lastFix, fix)
  8. 거절(정확도·순간이동)이 아니면 PlaceWatcher.onFix (:637-639)
  9. UPLOAD / UPLOAD_STALE_FALLBACK 이면 lastFix = fix
 10. 업로드 시각 검사 → 필요하면 upload()            (§6.4)
```

**8번이 7번의 결과에 안 묶이는 것이 중요하다.** `SKIP_TOO_CLOSE`(직전 점에서 25 m
못 감)도 장소 판정에는 넘긴다 — 경계에서 몇 걸음 옮겨 안으로 들어간 순간이 정확히
그 모양이다(:631-636 주석).

### 6.2 버퍼와 파일

- **메모리 버퍼**(`TrailBuffer`) — 오늘 점 전부. 날짜가 바뀌면 비우고 새로 시작한다
  (`TrailUploader.kt:96-101`). 자정 직전 마지막 업로드 뒤의 점 몇 개는 어제 문서에
  안 담긴 채 버려지는데 그건 의도된 것이다(그 클래스 주석 :38-44).
- **파일**(`TrailStore`) — 같은 점을 CSV 한 줄씩 **덧붙이기만** 한다. 첫 줄이
  dayKey. 프로세스가 죽었을 때의 보험이다.
  - 위치: `FileManager.default.urls(for: .applicationSupportDirectory, ...)` 아래
    `trail_today.csv`. `.documentDirectory` 가 아닌 이유는 그쪽이 파일 앱에
    노출될 수 있어서다. **`URLResourceValues.isExcludedFromBackup = true`** 를
    건다 — 하루치 위치 기록이 iCloud 로 나갈 이유가 없다.
  - 쓰기 실패는 **삼키고 로그만 남긴다.** 이 파일은 사본이지 원본이 아니다
    (`TrailStore.kt:23-25`).
  - 덧붙이기는 `FileHandle.seekToEnd` + `write` 다. 한 줄 50바이트라 메인에서도
    1 ms 아래고, 버퍼를 만지는 스레드가 하나로 유지된다.

### 6.3 하루 문서

`children/{childUid}/trails/{dayKey}` 하나에 **쓰기 한 번**이다.

```
TrailDoc
  dayKey     : DayPicker.todayKey(폰 시간대, 점의 at)    ← 이미 iOS 에 포팅돼 있다
  points     : TrailCodec.capped(버퍼 전체)              ← 2000개 상한, LTTB
  segments   : SegmentBuilder.build(버퍼 전체) + 이름     ← 원본 전체로 계산한다
  updatedAt  : 지금
```

**구간은 솎기 전 원본으로 계산한다**(`TrailUploader.kt:135-138`). 서버 상한에
맞춘 뒤 계산하면 머무름 경계점이 빠질 수 있다.

### 6.4 언제 올리나 — **여기가 안드로이드와 다르다**

안드로이드는 둘뿐이다: 부모의 `locate_now` 명령, 그리고 하루 한 번 안전 업로드
(`TrackingService.kt:705-706`). 아이폰은 명령을 못 듣는다(§1). 그래서 **아이 폰이
스스로 판단해 올린다.**

규칙 셋. 판정은 점이 들어올 때마다 한다(따로 타이머를 걸지 않는다 — 안드로이드가
같은 이유로 알람을 안 건다, `TrackingService.kt:392-394`).

| 상수 | 값 | 무엇 |
|---|---|---|
| `UPLOAD_MIN_INTERVAL_MILLIS` | 15분 | 아무리 잦아도 이보다 자주 안 올린다 |
| `UPLOAD_IDLE_INTERVAL_MILLIS` | 4시간 | 아무것도 안 움직여도 이만큼 지나면 한 번 올린다 |
| `UPLOAD_EVENT_MIN_GAP_MILLIS` | 1분 | 사건 직후 강제 업로드끼리의 최소 간격 |

판정에 쓰는 상태는 둘이다: `lastUploadAt`(마지막으로 올린 시각)과
`lastUploadedFix`(그때 올린 점). 둘 다 메모리에만 둔다 — 프로세스가 다시 뜨면
0/`nil` 이 되어 업로드가 한 번 더 나가는데, 그건 손해가 아니라 이득이다
(`TrackingService.kt:81-89` 와 같은 판단).

1. `now - lastUploadAt >= UPLOAD_MIN_INTERVAL_MILLIS`(15분) **이고**
   `distanceMeters(lastUploadedFix, fix) >= LocationFilter.MIN_MOVE_METERS`(25 m)
   이면 올린다. `lastUploadedFix` 가 `nil` 이면 거리 조건은 만족으로 친다.
2. 안 움직였어도 `now - lastUploadAt >= UPLOAD_IDLE_INTERVAL_MILLIS`(4시간)이면
   올린다. 부모 화면의 "마지막 신호"가 멎지 않게 하려는 것이다. 안드로이드의
   `SAFETY_UPLOAD_INTERVAL_MILLIS`(24시간, :902)를 내린 값이다 — 안드로이드는
   그 사이 `locate_now` 로 언제든 최신을 받을 수 있지만 아이폰은 그 통로가 없다.
3. **`events/` 에 무언가를 쓴 직후에는 1·2번을 무시하고 올린다.**
   "학교에 도착했어요"를 받고 앱을 연 부모가 그 순간의 경로를 봐야 한다.
   다만 `now - lastUploadAt < UPLOAD_EVENT_MIN_GAP_MILLIS`(1분)이면 건너뛴다 —
   한 점에서 사건이 둘 이상 나올 수 있어서다(`known-issues.md` 21번).

업로드 한 번은 **쓰기 두 번**이다 — 상태 문서 1(`children/{childUid}`),
하루 문서 1(`trails/{dayKey}`). 안드로이드 `uploadNow`(:719-729)와 같다.

**위치를 한 번도 못 잡았으면 올리지 않는다.** 안드로이드는 그때 예외를 던져
명령이 실패로 끝나는데(:720), 아이폰은 물어본 사람이 없으니 조용히 건너뛰고
로그만 남긴다.

### 6.5 오프라인과 재시도

**새로 만들지 않는다.** Firestore SDK 의 오프라인 큐가 이미 한다
(`known-issues.md` 19번: "오프라인 처리는 이미 켜져 있다 — 다시 만들지 말 것").
`set()` 은 로컬에 즉시 반영되고 연결이 돌아오면 저절로 나간다.

- 하루 문서는 **같은 문서를 덮어쓰므로** 큐에 여러 번 쌓여도 마지막 것만 의미가
  있다. 안드로이드와 같다.
- 이벤트는 **각각 다른 문서라 전부 나간다.** 오프라인이 7일을 넘기면 그 초과분은
  규칙이 거부한다(`firestore.rules:309`) — 안드로이드와 똑같은 제약이고
  `known-issues.md` 20번에 근거가 있다.
- 업로드 실패에 백오프를 두지 않는다. 실패해도 `lastUploadAt` 을 먼저 갱신해
  다음 창까지 기다린다(`TrackingService.kt:679-681` 과 같은 판단).

---

## 7. 지오펜스

### 7.1 OS 지오펜스는 "알림"이 아니라 "판정해 보라는 신호"다

안드로이드의 규율을 그대로 옮긴다(`PlaceGeofenceReceiver.kt:13-19`,
`PlaceWatcher.kt:22-35`). 지역 경계 이벤트가 오면 **거기 실려 온 위치를 `Fix` 로
바꿔 보통 점과 똑같은 길로 흘려보낸다.** 알릴지 말지는 언제나
`GeofenceEvaluator` 가 정한다 — 히스테리시스(반경 + 50 m), 5분 중복 억제,
정확도 문턱(100 m)이 전부 거기 있다.

시각은 **위치가 잡힌 순간**(`CLLocation.timestamp`)이지 콜백이 온 순간이 아니다
(`PlaceGeofenceReceiver.kt:43-45`).

지역 이벤트에 위치가 안 실려 오면(iOS 는 `CLRegion` 만 주고 좌표를 안 준다)
그 자리에서 `manager.requestLocation()` 한 번으로 지금 좌표를 얻어 같은 길로
넣는다. 못 얻으면 아무 판단도 하지 않는다 — 지어내지 않는다.

### 7.2 20개 상한

**아이폰의 OS 상한이 20개다.** 안드로이드는 OS 상한이 100 인데 설계가 스스로
20 으로 잘랐다(`PlaceWatcher.kt:217`, 부모 화면의 장소 개수 상한과 같은 값).
**그래서 두 플랫폼의 숫자가 이미 같고, 넘칠 일이 구조적으로 없다.**

그래도 옛 문서나 손으로 넣은 데이터로 20개를 넘는 경우를 대비해 **고르는 규칙을
글자 그대로 옮긴다**(`PlaceWatcher.kt:168-174`).

1. 반경이 0 이하인 장소를 뺀다 — 안드로이드는 그런 값 하나가 목록 전체의 등록을
   실패시키기 때문이었다. iOS 도 반경 0 은 거부한다.
2. **이름순으로 정렬해** 앞에서 20개를 고른다. 읽어온 순서로 자르면 어떤 장소는
   하루는 걸리고 하루는 안 걸린다.
3. 잘렸으면 로그로 남긴다.

이 규칙은 `Logic/GeofenceRegionSelection.swift` 에 순수 함수로 둔다 — 안드로이드는
인라인이라 골든 파일 대상이 아니지만, 단위 테스트는 붙인다.

### 7.3 어느 API 를 쓰나

`CLLocationManager.startMonitoring(for: CLCircularRegion)` 을 쓴다. iOS 17 이
`CLMonitor` 로 대체했다고 표시했지만, **앱이 죽어 있을 때 되살리는 계약이
문서로 굳어 있고 오래 검증된 쪽**이 이것이다. 이 설계 전체가 그 계약에 기대고
있으므로 확실한 쪽을 고른다. 4단계 실기기 검증에서 `CLMonitor` 가 똑같이
되살리는 것을 확인하면 그때 옮긴다(§17 열린 질문 2).

- 등록은 **전부 지우고 다시 건다**(`PlaceWatcher.kt:145-152`). 부모가 지운 장소의
  이벤트가 계속 올라오는 것을 막는다. `manager.monitoredRegions` 를 순회해 지운다.
- `notifyOnEntry = true`, `notifyOnExit = true`.
- 안드로이드가 `setInitialTrigger(0)` 로 "등록하는 순간 이미 안에 있는 장소로
  ENTER 를 쏘지 않게" 한 것(:181)은 iOS 의 기본 동작과 같다 — 따로 할 일이 없다.
  (혹시 들어오더라도 `GeofenceEvaluator` 가 처음 보는 장소에는 조용히 상태만
  심는다, `GeofenceEvaluator.kt:97-103`.)
- 등록을 다시 거는 때는 안드로이드와 같다: 앱이 (다시) 뜰 때,
  그리고 장소 목록을 다시 읽었을 때. **`sync_rules` 명령은 못 받으므로**
  부모가 장소를 고친 것을 즉시 알 방법이 없다 — 그래서 아이폰 아이는
  `PlaceRepository.observePlaces` 로 **상시 구독**한다. 읽기 비용은 장소가 바뀔
  때만 들고(유휴 리스너는 문서가 실제로 도착할 때만 과금된다,
  `known-issues.md` 12번 4항), 이게 없으면 지운 장소의 알림이 영영 계속 울린다
  (README "함께 고쳐야 하는 짝" 의 `writeThenNotify` 가 막는 그 사고다).

### 7.4 앱이 죽어 있는 동안

- 지역 경계를 넘으면 iOS 가 앱을 **다시 띄운다**(백그라운드로). 그때 §7.1 의 길이
  그대로 돈다: 장소 목록을 읽고, 상태 저장소를 읽고, 판정하고, 필요하면 이벤트를
  쓰고, §6.4 의 3번 규칙에 따라 즉시 업로드한다.
- 상태(`PlaceStateStore`)가 프로세스 밖에 있어야 하는 이유가 여기서 커진다.
  메모리에만 두면 아침에 학교에 도착한 사실이 사라지고, 오후에 되살아났을 때
  아이는 이미 학교 밖이라 `inside=false` 로 심겨 **그날의 하교 이탈 알림이 영영
  안 나간다**(`PlaceStateStore.kt:9-20`). 저장소는 `UserDefaults` 다
  (안드로이드의 SharedPreferences 와 같은 자리). 값 형식도 같다: 줄바꿈으로
  레코드, 탭으로 칸, 망가진 줄은 통째로 버린다.
- **강제 종료 뒤에는 이 되살리기도 안 온다**(§5.3).

---

## 8. 권한과 정직함

### 8.1 '항상 허용'까지 가는 길

iOS 는 '항상'을 곧바로 못 묻는다. 반드시 두 걸음이다.

1. `requestWhenInUseAuthorization()` — 아이가 허용하면 앱이 화면에 떠 있는 동안만
   위치가 온다.
2. 그 뒤 `requestAlwaysAuthorization()` — iOS 13+ 에서는 **바로 대화상자가 안 뜰
   수 있다.** 임시로 '항상'처럼 동작하다가, 앱이 실제로 백그라운드에서 위치를 쓴
   뒤에 iOS 가 스스로 "계속 허용할까요?"를 띄운다. 그 순간 아이가 '앱 사용 중만'을
   고르면 조용히 내려앉는다.

그래서 **권한 상태를 한 번 받고 끝내지 않고 계속 본다.**
`locationManagerDidChangeAuthorization` 을 구독해 바뀔 때마다 화면과
`ConditionWatcher` 를 다시 돌린다.

| 상태 | 무엇이 망가지나 | 아이 화면 | 부모가 보는 것 |
|---|---|---|---|
| `.notDetermined` | 아직 아무것도 안 됨 | "위치를 켜야 엄마 아빠가 찾을 수 있어요" + 권한 요청 버튼 | (아직 페어링 직후라 아무것도 없다) |
| `.denied` / `.restricted` | 전부 | 설정으로 보내는 버튼 | `permission_off` 이벤트 |
| `.authorizedWhenInUse` | **백그라운드 수집·지역 감시·되살리기가 전부 죽는다.** 화면을 벗어나는 순간 하루가 조용해진다 | "'항상 허용'으로 바꿔주세요" + 설정 버튼 | `permission_off` 이벤트 |
| `.authorizedAlways` | 없음 | "지금 내가 어디 있는지 엄마 아빠가 볼 수 있어요" | 정상 |

`.authorizedWhenInUse` 가 안드로이드의 `LOCATION_BACKGROUND` 와 정확히 같은
자리다 — "화면상으로는 위치 권한이 여전히 허용이라 아무도 모른다"
(`ConditionWatcher.kt:32-34`).

### 8.2 정확한 위치 끄기 (`accuracyAuthorization == .reducedAccuracy`)

**이 앱에서 가장 조용한 고장이다.** 오차가 1~3 km 로 들어오므로
`LocationFilter.MAX_ACCURACY_METERS`(50 m)는 물론 완화 문턱(100 m)도 못 넘는다.
결과: **점이 하나도 안 쌓이고, 아무것도 안 올라가고, 장소 판정도 전부 보류된다**
(`GeofenceEvaluator.kt:78`). 앱은 멀쩡히 돌고 파란 표시도 켜져 있다.

- 아이 화면: 정확한 위치를 켜 달라고 말하고 설정으로 보낸다.
- 부모: `permission_off` 이벤트.
- **임시 정확도 요청(`requestTemporaryFullAccuracyAuthorization`)은 안 쓴다.**
  그건 한 세션만 살아서 다음에 또 같은 침묵이 온다. 아이가 설정에서 켜는 것이
  유일한 진짜 해결이다.

### 8.3 저전력 모드

`ProcessInfo.processInfo.isLowPowerModeEnabled`, 변화는
`NSProcessInfoPowerStateDidChange` 로 받는다. iOS 가 백그라운드 활동을 줄여
위치가 드물어질 수 있다.

- 아이 화면: 한 줄로 알린다("저전력 모드가 켜져 있어 위치가 드문드문 올 수 있어요").
- 부모: **이벤트를 안 만든다.** 아이가 언제든 껐다 켰다 하는 설정이라 알리기
  시작하면 소음이 된다 — 안드로이드가 `BATTERY_UNRESTRICTED` 를 감시 목록에서
  뺀 것과 정확히 같은 판단이다(`ConditionWatcher.kt:43-46`).

### 8.4 백그라운드 앱 새로고침 끄기

`UIApplication.shared.backgroundRefreshStatus`. 이게 꺼지면 **백그라운드 위치
배달이 멎는다** — 앱이 화면에 있을 때만 점이 들어온다. `.authorizedWhenInUse` 와
같은 크기의 고장이다.

- 아이 화면: 설정에서 켜 달라고 말한다.
- 부모: `permission_off` 이벤트.

> 이 항목은 애플 문서가 얇다. "꺼지면 배달이 멎는다"는 위 서술은 실기기에서
> 확인해야 한다(§17 열린 질문 4). 확인 전까지는 안전한 쪽(고장으로 취급)으로 둔다 —
> 침묵을 침묵으로 두는 것보다 한 번 더 말하는 쪽이 이 앱의 규율에 맞는다.

### 8.5 문구 — 있는 키를 최대한 쓴다

**그대로 쓰는 키**(이미 14개 언어에 다 있다):

| 키 | `i18n/ko.json` | 쓰는 자리 |
|---|---|---|
| `child_home_title` | :33 | 아이 화면 제목 |
| `child_sharing_on` | :46 | 다 정상일 때의 본문 |
| `child_permission_missing` | :35 | 권한이 빠졌을 때(`%1$s` 에 권한 이름) |
| `child_go_to_permission` | :32 | 버튼 |
| `child_home_title_gone` | :34 | 가족에서 빠졌을 때 제목 |
| `child_family_gone` | :31 | 그 본문 |
| `child_repair` | :39 | 그 버튼 |
| `event_detail_permission` | :124 | 이벤트의 `detail`(`%1$s` 에 권한 이름) |
| `event_detail_battery` | :123 | 배터리 이벤트의 `detail` |
| `alert_permission_off` | :10 | 부모 알림 목록 줄 |
| `alert_low_battery` | :6 | 같음 |
| `alert_place_enter` / `alert_place_exit` | :11 / :12 | 같음 |

**새로 만드는 키**(`ko.json`·`en.json` 에만 넣고 `tools/ios-strings.py` 로 생성.
**번역을 지어내지 않는다** — 나머지 12개 언어는 영어로 채워지고
`tools/i18n-untranslated.json` 에 기록된다):

- `ios_child_perm_always_title` / `ios_child_perm_always_reason`
- `ios_child_perm_precise_title` / `ios_child_perm_precise_reason`
- `ios_child_perm_refresh_title` / `ios_child_perm_refresh_reason`
- `ios_child_low_power_notice`
- `ios_child_open_settings` (설정 앱으로 보내는 버튼)
- `ios_child_no_remote_control` (보호자 화면의 잠긴 버튼 옆 설명, §10.2)
- `ios_child_schedule_not_applied` (예약 탭 전용 설명, §10.2)
- `ios_perm_location_when_in_use` (Info.plist 용)
- `ios_perm_location_always` (Info.plist 용)

Info.plist 두 개는 `tools/ios-strings.py:31` 의 `INFOPLIST_KEYS` 에 매핑을
더해야 `InfoPlist.xcstrings` 에 실린다(지금은 `CFBundleDisplayName` 하나뿐이다).

**지우는 키 셋**: `ios_child_unsupported_title` / `_body` / `_confirm`
(`ko.json:148-150`, `en.json:148-150`). 역할 선택 화면이 아이를 더 이상 막지
않으므로 쓸 곳이 사라진다. 이 셋은 iOS 전용이라 안드로이드가 쓰지 않는 것을
확인했다(`grep` 결과 `app/` 에 없음). `tools/i18n-untranslated.json` 에서도
같이 빠진다(§17 열린 질문 7).

### 8.6 안드로이드에는 있는데 아이폰에는 없는 권한

`ConditionWatcher.WATCHED`(:179-184)의 넷 중 둘은 아이폰에 대응이 없다.

- `DND_ACCESS` — 소리 모드를 바꿀 API 자체가 없으니 권한도 없다.
- `NOTIFICATION` — 아이폰 아이는 알림을 하나도 안 띄운다(메시지·알람이 범위 밖).
  푸시도 안 쓴다. 그래서 감시하지 않는다.

아이폰의 감시 목록은 넷이다: **항상 허용 / 정확한 위치 / 백그라운드 앱 새로고침 /
(그 앞단으로) 위치 권한 자체.** 안드로이드와 개수만 같고 내용이 다르다.

---

## 9. 배터리

### 9.1 실제로 얼마나 드나 — **아직 아무도 안 쟀다**

정직하게 적는다. **안드로이드 쪽 숫자도 없다** — `known-issues.md` 10번이
"정지 중에도 GPS를 켜 두기로 했다 — 배터리 대가는 아직 안 재봤다"이고,
README 도 "하루 종일 실사용 검증이 가장 큰 미확인"이라고 적어 뒀다.

아이폰에서 **`.best` 로 연속 수집하는 것은 iOS 가 내주는 가장 비싼 모드다.**
숫자를 지어내지 않는다. 4단계 실기기 검증이 하루를 재고, 그 값이 이 문단을
대체한다.

### 9.2 어떻게 내려가나 — 안드로이드의 상태를 그대로 따른다

| 판정기 상태 | 안드로이드가 하는 것 | 아이폰이 하는 것 |
|---|---|---|
| MOVING | 5초 주기 + 최소 이동 3 m | `.best` + `distanceFilter = 3` + 5초 게이트 |
| FAST_PROBE | 5초 주기, 최대 30초 | `.best` + 필터 없음 + 5초 게이트 |
| SLOW_PROBE | 30초 주기 | `.nearestTenMeters` + 30초 게이트 |
| 정지 / 등록 장소 안 | 60초 주기 | `.nearestTenMeters` + 60초 게이트 |

**내려가는 조건도 같다.** `FAST_PROBE_MILLIS`(30초, :176) 안에 실제 진행이 없으면
SLOW_PROBE 로 내려가고, MOVING 중에도 `STOP_CONFIRM_MILLIS`(60초, :177) 동안
오차 반경 안에 머물면 내려간다. 하루 종일 `.best` 로 남는 일이 없는 것은 이
판정기가 보장한다.

**소프트웨어 게이트가 배터리를 아끼지는 않는다.** 버려진 콜백도 GNSS 는 이미
켜져 있었다. 아이폰에서 배터리를 실제로 정하는 것은 `desiredAccuracy` 하나다 —
그래서 `.best` ↔ `.nearestTenMeters` 전환이 이 설계의 절약 장치 전부다.
`.hundredMeters` 로 더 내리는 선택지는 §4.8 의 근거로 막아 뒀다.

### 9.3 재지 않고는 손대지 않는다

README "위치 문턱을 만질 때"의 규율이 여기도 걸린다. 배터리가 과하다는 실측이
나오기 전에는 위 표의 어떤 값도 바꾸지 않는다. 바꿔야 한다면 안드로이드가
예고해 둔 자리 — 사용자용 "배터리 아끼기" 토글(`LocationCollector.kt:95-96`) —
을 양쪽에 같이 다는 것이 먼저다.

---

## 10. 보호자 화면 — 아이가 아이폰이면 잠근다

### 10.1 아이폰인 것을 어떻게 아나

**아이 폰이 상태 문서에 적는다.** `children/{childUid}` 에 `platform: "ios"`.

```
ChildStatusDoc
  ...기존 필드 그대로...
  platform: "ios"      ← 아이폰 아이만 적는다
```

**규칙 확인: 고칠 것이 없다.**

```
firestore.rules:145-148
  match /children/{childUid} {
    allow read:  if memberOf(familyId);
    allow write: if memberOf(familyId) && request.auth.uid == childUid;
  }
```

필드 목록 제한(`hasOnly`)이 없다. 그 아이 본인이면 어떤 필드든 쓸 수 있으므로
**새 필드가 이미 허용된다.**

**왜 멤버 문서가 아니라 상태 문서인가 — 두 가지다.**

1. **규칙.** `members/{uid}` 의 update 는
   `hasOnly(['displayName','fcmToken','appVersion','updatedAt'])` 로 잠겨 있다
   (`firestore.rules:133-136`). create 에는 제한이 없으므로 가입하는 **그 순간에만**
   적을 수 있고 그 뒤로는 영영 못 고친다. 아이가 폰을 바꾸거나 앱을 다시 깔면
   틀린 값이 남는다. 상태 문서는 업로드마다 덮어쓰므로 항상 지금 값이다.
   (굳이 멤버 문서에 둬야 한다면 필요한 최소 변경은 그 `hasOnly` 목록에
   `'platform'` 한 개를 더하는 것이다. **이 작업에서는 규칙을 안 고친다.**)
2. **읽기 비용 0.** 보호자 화면은 상태 문서를 이미 읽고 있다
   (`FamilyRepository.fetchChildStatus` / `observeChildStatus`). 멤버 문서에 두면
   아이를 고를 때마다 읽기가 하나 더 붙는다 — 가족당 하루 50 읽기 예산에서
   살 이유가 없다.

**값이 없으면 안드로이드로 본다.** 지금 서버에 있는 모든 아이 문서에 이 필드가
없고, 모르는 아이의 기능을 조용히 없애면 안 된다. 반대 방향의 위험(아이폰 아이인데
아직 상태 문서를 한 번도 안 써서 버튼이 켜져 있다)은 **페어링이 끝나고 첫 좌표를
받자마자 업로드를 한 번 강제**해서 없앤다 — 그 한 번이 `platform` 을 심는다.
좌표를 기다리는 이유는 §6.4 의 마지막 규칙과 같다: 위치를 한 번도 못 잡은 채로
상태 문서를 쓰면 부모 화면에 "방금 확인한 위치"라는 거짓이 뜬다.

**안드로이드 보호자는 안전하다.** 코틀린 `ChildStatusDoc`(`Documents.kt:88`)에
이 필드가 없지만 Firestore 의 `toObject` 는 모르는 필드를 조용히 버린다. 터지지
않는다. 다만 **안드로이드 보호자 화면은 아이폰 아이에게 계속 명령 버튼을
보여준다** — 이 작업의 범위 밖이고, 후속 과제로 남긴다(§17 열린 질문 8).

### 10.2 무엇을 잠그나

`Guardian/ChildPlatform.swift` 가 `platform` 하나를 읽어 판단을 돌려준다.
화면마다 `platform == "ios"` 를 직접 비교하지 않는다 — 비교가 흩어지면 한 군데를
빠뜨린다.

```
enum ChildPlatform { case android, iOS, unknown }
extension ChildPlatform {
    var 명령을_받을_수_있나: Bool   // .iOS 만 false
}
```

| 화면 | 잠그는 것 | 정본 |
|---|---|---|
| 관리 탭 | 소리 모드 버튼 셋, 소리 상태 다시 묻기, 핸드폰 찾기, 메시지 보내기, 알람 맞추기/끄기 | `Guardian/ControlView.swift`, `ControlViewModel.swift` |
| 지도 탭 | '지금 위치 확인', '실시간 보기' | `Guardian/ChildMapView.swift`, `MapViewModel.swift` |
| 예약 탭 | 규칙 저장 뒤의 '아이 폰에 알리기'(= `sync_rules`) | `Guardian/ScheduleView.swift` |
| 장소 탭 | **안 잠근다.** 장소 저장은 Firestore 쓰기이고 아이폰 아이가 상시 구독으로 받는다(§7.3) | — |

**잠그는 방식**: 버튼을 `.disabled(true)` 로 두고 **그 자리에 왜 안 되는지를 한
줄로 적는다.** 흐린 버튼만 두지 않는다 — 지금 역할 선택 화면이 아이 버튼을
지우지도 흐리게 두지도 않고 이유를 말하는 것과 같은 판단
(`RoleSelectView.swift:4-6`).

문구는 키 하나로 통일한다 — `ios_child_no_remote_control`:

> 아이 폰이 아이폰이라 이 기능은 쓸 수 없어요. 위치와 장소 알림은 그대로 와요.

**예약 탭에는 한 가지를 더 말한다**(`ios_child_schedule_not_applied`):

> 규칙은 저장되지만 아이폰에서는 소리가 바뀌지 않아요.

규칙을 저장 못 하게 막지는 않는다 — 나중에 그 아이가 안드로이드 폰으로 바뀌면
그대로 동작해야 하기 때문이다.

두 문장 모두 초안이다. 주인이 고칠 수 있다(§17 열린 질문 10).

---

## 11. Firestore 규칙과 비용

### 11.1 아이가 하는 모든 쓰기가 이미 허용되는가 — **그렇다**

| 쓰기 | 경로 | 규칙 | 줄 |
|---|---|---|---|
| 상태(+`platform`) | `families/{f}/children/{uid}` | `write: memberOf && auth.uid == childUid` | :148 |
| 하루 문서 | `.../children/{uid}/trails/{dayKey}` | `write: memberOf && auth.uid == childUid` | :165 |
| 장소 이벤트 | `families/{f}/events/{id}` | `create: memberOf && childUid == auth.uid && read == false && at` 이 과거 7일~미래 1시간 | :306-310 |
| 배터리·권한 이벤트 | 같음 | 같음 | 같음 |
| 멤버 문서 생성(가입) | `families/{f}/members/{uid}` | `create`, 살아있는 초대 코드 대조 | :107-126 |
| 초대 코드 죽이기 | `families/{f}` / `inviteCodes/{code}` | `inviteExpiresAt == 0` 만 / 멤버면 delete | :93-94, :69 |

아이가 하는 **읽기**도 전부 이미 열려 있다.

| 읽기 | 경로 | 규칙 | 줄 |
|---|---|---|---|
| 자기 장소 목록 | `.../children/{uid}/places/{id}` | `read: memberOf && (guardian \|\| auth.uid == childUid)` | :217-218 |
| 자기 멤버 문서(가족에 아직 있나) | `families/{f}/members/{uid}` | `read: memberOf` | :99 |

**규칙 변경이 필요한 것이 하나도 없다.** `platform` 필드가 그 근거의 핵심이고
§10.1 에 적었다.

주의할 계약 셋(어기면 **쓰기가 조용히 거부되고 부모는 그 사건이 없었던 것으로
읽는다**, `core/EventRepository.kt:18-27`):

1. `childUid` 는 반드시 지금 로그인한 uid.
2. `read` 는 반드시 `false` — 문서를 만들 때 이 필드를 건드리지 않는다.
3. `at` 은 **밀리초 정수**이고 서버 시각 기준 과거 7일~미래 1시간 안.
   `Timestamp` 로 쓰면 안 된다.

### 11.2 하루에 몇 번 쓰나 — 안드로이드와 비교

예산은 가족당 **하루 20 쓰기 / 50 읽기**다(`known-issues.md` 12번: Spark 는
프로젝트 전체로 하루 2만 쓰기 / 5만 읽기, 목표가 1,000가족).

**안드로이드 아이 가족**(같은 문서 12·14번의 값, 하루 5회 '지금 위치 확인' 기준):

| 항목 | 하루 쓰기 |
|---|---|
| 명령 왕복 5회 × 5 | 25 |
| 안전 업로드(상태 1 + 하루 문서 1) | 2 |
| `serverNow` | 1~5 |
| 장소 이벤트(2곳 × 도착·이탈) | 4 |
| `low_battery` / `permission_off` | 0~1 |
| 부모의 읽음 표시 | 4~5 |
| **합계** | **36~42** |

**아이폰 아이 가족**(§6.4 의 규칙, 실제로 있을 법한 하루 — 등교·하교·학원 왕복·
저녁 산책으로 이동 구간이 다섯, 각 구간이 15~40분):

| 항목 | 하루 쓰기 |
|---|---|
| 명령 왕복 | **0** (명령이 없다) |
| 주기 업로드 — 움직이는 15분 슬롯 약 10회 × 2 | 20 |
| 유휴 업로드 — 4시간마다, 하루 3회 × 2 | 6 |
| 이벤트 직후 강제 업로드 약 2회 × 2 (나머지는 1분 간격 규칙과 15분 규칙에 흡수) | 4 |
| 장소 이벤트 | 4 |
| `low_battery` / `permission_off` | 0~1 |
| 부모의 읽음 표시 | 4~5 |
| `serverNow` | 1~5 |
| **합계** | **39~45** |

**결론: 안드로이드와 거의 같다(36~42 → 39~45).** 명령 왕복 25 가 통째로 사라진
자리에 주기 업로드 30 이 들어왔다. 둘 다 예산 20 을 **약 2배** 넘는다 —
안드로이드가 이미 1.8~2.1배 초과인 채로 주인이 "당분간 혼자 쓴다"고 정한 상태
(`known-issues.md` 14번)이고, **이 작업이 그 배수를 나쁘게 만들지 않는다**는 것이
여기서 확인해야 할 전부다.

**최악의 날**(하루 종일 움직임): 15분 × 24시간 = 96 업로드 × 2 = 192 쓰기.
`UPLOAD_MIN_INTERVAL_MILLIS` 가 그 상한을 정한다. 이 값을 올리는 것이 비용을
줄이는 첫 손잡이다.

**읽기**는 안드로이드보다 **준다.** 아이폰 아이는 명령 리스너가 없고
(안드로이드는 상시 구독), 대신 장소 목록 구독 하나가 붙는데 장소는 부모가
고칠 때만 바뀌므로 하루 0~2 읽기다. 앱이 되살아날 때마다 장소를 한 번 읽는
것(장소 개수만큼)이 가장 큰 몫이고, 되살아나는 횟수가 하루 몇 번 수준이다.

**저장 용량**은 안드로이드와 같다 — 같은 하루 문서 하나(약 50KB)다.
`known-issues.md` 12번의 "1GB 는 20일이면 찬다"가 그대로 걸린다.

---

## 12. 테스트

### 12.1 단위 테스트 (Swift Testing, `KidCareTests`)

옮긴 로직마다 **안드로이드 테스트를 먼저 Swift 로 옮겨 빨갛게 두고 통과시킨다**
(2단계가 한 방식, README 2026-09-13). 새 파일 여덟:

`LocationFilterTests`, `AdaptiveMovementDetectorTests`, `MovementTrailFilterTests`,
`SegmentBuilderTests`, `TrailCodecTests`, `GeofenceEvaluatorTests`,
`PlaceNameCacheTests`, `GeofenceRegionSelectionTests`.

CoreLocation 을 쓰는 것들은 순수한 부분을 따로 뽑아 테스트한다:

- `CollectionModeTests` — 상태 조합 → (정확도, 거리 필터, 간격). 표가 전부라
  CoreLocation 없이 돈다. **분기 순서**(등록 장소가 이동 판정보다 아래)와
  `STILL_ESCALATE_MILLIS`(5분 뒤 정지로 내려가고, FAST_PROBE 로 올라가면 시계가
  0 이 된다)를 여기서 고정한다. 이 둘은 골든 대조가 못 잡는다 — 안드로이드에
  대응하는 순수 함수가 없다.
- `TrackingCoordinatorTests` — `LocationCollector` 를 프로토콜로 두고 가짜를 넣어
  점 시퀀스를 먹인다. §6.1 의 10단계 순서와 §6.4 의 업로드 판정을 여기서 고정한다.
  `Guardian/` 의 뷰모델 테스트들이 이미 쓰는 방식(`TestDoubles.swift`)과 같다.
- `ChildHomeModelTests` — 권한 상태 조합 → 어떤 문장 하나를 보여주나.
  안드로이드가 "한 번에 하나만, 고쳐야 다음이 의미 있는 순서"로 정한 것
  (`ChildHomeActivity.kt:49-51`)을 그대로 고정한다.

### 12.2 골든 파일 — 코틀린이 정본이다

2단계와 **같은 방식**이다(README 2026-09-13, `GoldenComparisonTests.swift:5-11`):
코틀린 쪽 생성기가 입력을 넓게 만들고 코틀린이 실제로 계산한 답을 JSON 으로 쓴다.
Swift 가 같은 입력에 같은 답을 내는지 대조한다. **갈리면 Swift 를 고친다.**

**골든을 붙이는 로직 일곱** (`ios/KidCareTests/golden/` 에 파일 하나씩):

| 파일 | 무엇을 쓸어보나 |
|---|---|
| `locationFilter.json` | `decide(previous, candidate)` — 정확도 50/100 문턱 양옆, 15분 완화 창 양옆, 25 m 이동 문턱, 10분 하트비트, 시속 200km 순간이동, `previous == null`, `elapsed <= 0`. `distanceMeters` 도 별도 배열로 |
| `adaptiveMovementDetector.json` | **점 시퀀스를 통째로** 먹이고 매 점의 상태와 승격 버퍼 크기를 기록. 30초 확인 창, 10초/3점 최소, 60초 정지 확인, 오차 비례 문턱(`hypot × 1.0`), 진행률 0.6 |
| `movementTrailFilter.json` | `shouldRecord` 와 `isDisplacementEvidence` 각각. 5초 간격, 50 m 정확도, 속도 근거 갈래(정확도 15 m + 속도오차), 변위 증거 `max(50, hypot × 1.5)` |
| `segmentBuilder.json` | `build(points)` — 40 m 반경, 5분 최소, 연속 2점 이탈 확인, 오차 가중 평균(`nameLat`/`nameLng`), 100 m 초과 점 제외 |
| `trailCodec.json` | `capped(points)` — 2000 상한 바로 아래/위/한참 위. `decode` 는 깨진 줄·칸 수 오류를 섞은 텍스트 |
| `geofenceEvaluator.json` | `evaluate(places, states, fix)` — 처음 보는 장소, 반경 경계, 이탈 여유 50 m, 5분 중복 억제, `lastEventAt == 0`, 음수 경과(시계 역행), 알림 스위치 끔, 지워진 장소 정리 |
| `placeNameCache.json` | `find`/`put`/`encode`/`decode` — 30 m 경계, 300개 상한 넘기기, 탭·줄바꿈이 든 이름, 깨진 줄 |

**코틀린 쪽이 그 파일을 어떻게 뽑나** — 기존
`app/src/test/java/com/kidcare/family/logic/GoldenFileWriterTest.kt` 에
`@Test` 일곱 개를 더한다. 그 파일이 이미 갖춘 규율을 그대로 쓴다.

- 손으로 짠 JSON 라이터(`toJson`) — 의존성을 더하지 않는다.
- `writeGoldenIfPresent(name, json)` — `ios/` 가 없으면 생성·검증만 하고 쓰기를
  건너뛴다. **`generate*()` 를 먼저 지역 변수로 평가한 뒤** 이 함수를 부른다.
- `writeIfChanged` — 내용이 같으면 다시 안 써서 git diff 를 안 더럽힌다.
- **생성기 자체 점검.** 2단계에서 "경계값이라 이름 붙인 케이스가 실제로는 경계
  근처에 가지도 못한" 사고가 있었다(README 2026-09-13). 그래서 각 생성기 끝에
  `check(...)` 를 넣어 **경계 바로 아래·위 케이스가 서로 다른 답을 내지 않으면
  생성기가 죽게** 한다. 예: `locationFilter` 는 49.9 m 와 50.1 m 가 각각
  `UPLOAD` 와 `REJECT_INACCURATE` 가 아니면 죽는다.
- `Float` ↔ `Double` 경계: 생성기는 정확도·속도 값을 **`Float` 로 정확히
  표현되는 값**으로만 만든다(§4.1). 안 그러면 두 언어가 같은 함수인데도 문턱
  바로 위에서 갈린다.

**Swift 쪽**: `GoldenComparisonTests.swift` 에 테스트 일곱을 더하고,
"골든 파일이 스윕이라 부를 만큼 케이스를 담고 있는지" 검사(:42-60)에
일곱 줄을 더한다. `[]` 로 비워도 통과하던 사고를 다시 열지 않는다.

**이 작업에서 `app/` 을 건드리는 곳은 이 테스트 파일 하나뿐이다.**
`app/src/main` 은 한 줄도 안 바뀐다 — 2단계와 정확히 같은 예외다
(§17 열린 질문 1에서 주인 확인을 받는다).

### 12.3 에뮬레이터 테스트 (`KidCareTests` + `EmulatorHarness`)

쓰기 경로가 규칙을 **실제로** 통과하는지 본다. 규칙을 못 지킨 쓰기는 조용히
거부되므로 단위 테스트로는 절대 안 잡힌다.

- 아이 세션이 `children/{childUid}` 에 `platform` 을 포함해 쓴다 → 통과.
- 아이 세션이 `trails/{dayKey}` 를 쓴다 → 통과.
- 아이 세션이 `events/` 를 만든다: `childUid == uid`, `read == false`,
  `at` 이 창 안 → 통과. `at` 을 8일 전으로 하면 → **거부**. `read: true` 로
  만들면 → **거부**. 남의 `childUid` 로 만들면 → **거부**.
- 아이 세션이 자기 이벤트를 읽음 처리 → **거부**(`firestore.rules:315-318`).
- 아이 세션이 자기 `places/` 를 읽는다 → 통과.
- 아이 세션이 `places/` 를 쓴다 → **거부**(`firestore.rules:219-221`).
- 보호자 세션이 아이의 `trails/` 를 쓴다 → **거부**.
- 초대 코드로 역할 child 가입 → 멤버 문서가 `role: "child"` 로 생긴다.

`EmulatorHarness.ChildSession`(두 번째 `FirebaseApp` 으로 아이를 흉내 내는 것)이
이미 있으므로 그대로 쓴다.

### 12.4 실기기에서만 확인되는 것

에뮬레이터도 시뮬레이터도 못 잡는다. 4단계 항목이다.

1. '항상 허용'의 두 걸음과, iOS 가 나중에 띄우는 "계속 허용할까요?" 대화상자.
2. 화면을 끄고 몇 시간 뒤에도 점이 계속 들어오는가(`pausesLocationUpdatesAutomatically`
   가 실제로 안 멈추는가).
3. 메모리 압박으로 죽은 뒤 지역 경계·중요 위치 변경이 앱을 되살리는가.
4. **강제 종료 뒤에는 되살아나지 않는가**(§17 열린 질문 3).
5. 정확한 위치를 끄면 실제로 오차가 몇 미터로 오는가(문턱 50/100 m 와의 관계).
6. 저전력 모드에서 스트림이 얼마나 드물어지는가.
7. 백그라운드 앱 새로고침을 끄면 배달이 멎는가(§17 열린 질문 4).
8. 하루 배터리 소모(§9.1).
9. `didUpdateLocations` 가 묶음으로 오는가 — 온다면 안드로이드처럼 묶음 안의
   모든 점을 시간순으로 처리해야 경로의 모퉁이가 안 사라진다.
10. 파란 위치 표시가 실제로 뜨는가(아이가 감시 사실을 보는 유일한 장치).

시뮬레이터로 되는 것: GPX 경로를 먹여 수집→필터→판정→구간→업로드 전체를
돌리는 것, 지역 진입/이탈을 좌표로 만들어 이벤트가 쓰이는 것.

---

## 13. 실기기 안전

**실제 아이폰을 아이로 페어링하면 진짜 가족 문서에 쓰고 진짜 아이의 위치를 모으기
시작한다.** 되돌릴 수 없는 종류의 일이다.

- **주인의 명시적 허락 없이는 실기기를 아이로 페어링하지 않는다.** 4단계에서
  따로 묻는다.
- **개발 중의 모든 테스트는 Firebase 에뮬레이터를 쓴다.**
  `FirebaseBootstrap.configureForEmulator` / `EmulatorHarness` 가 그 자리다.
  운영 Firebase 를 건드리는 테스트는 `KidCareUITests` 스킴에만 둔다 —
  기본 `KidCare` 스킴의 test 액션에 **넣지 않는다**(`project.yml:120-122` 의
  이미 정해진 규율).
- 실기기 확인 전에 **페어링을 푸는 방법**을 먼저 확인해 둔다: 보호자 앱에서
  그 아이의 멤버 문서를 지우면(`firestore.rules:137`) 아이 화면이
  `child_family_gone` 으로 바뀌고 수집이 멎는다.
- 실기기 검증용 가족은 **따로 만든다.** 주인이 실제로 쓰는 가족에 시험용 아이를
  붙이지 않는다.

---

## 14. 구현 순서

각 단계 끝에 **눌러서 확인할 수 있는 것**이 남는다.

### 1단계 — 위치와 경로 (가장 크다)

- `Logic/` 다섯: `LocationFilter`, `AdaptiveMovementDetector`,
  `MovementTrailFilter`, `SegmentBuilder`, `TrailCodec`.
  `Fix.speedAccuracy`, `Segment.nameLat/nameLng` 추가.
- 안드로이드 테스트 포팅(빨강 → 초록) + 골든 생성기 다섯 + 대조 테스트 다섯.
- `Child/`: `CollectionMode`, `LocationCollector`, `TrackingCoordinator`,
  `TrailBuffer`, `TrailStore`, `TrailUploader`.
- `Core/`: `ChildStatusReporter`, `TrailRepository.save`.
- `Info.plist` 의 `UIBackgroundModes` 와 위치 사용 설명 두 개.

**끝나면**: 시뮬레이터에 GPX 경로를 먹이고, 에뮬레이터에 올라간
`trails/{dayKey}` 문서를 보호자 지도가 그대로 그린다.

### 2단계 — 장소 알림과 머무른 곳 이름

- `Logic/`: `GeofenceEvaluator`, `PlaceNameCache`, `GeofenceRegionSelection`.
  골든 둘 + 대조 테스트.
- `Child/`: `PlaceWatcher`, `PlaceStateStore`, `PlaceNamer`.
- `Core/`: `EventRepository.add`, `PlaceRepository.observePlaces` 를 아이 uid 로 구독.
- 에뮬레이터 테스트: 이벤트 쓰기 계약 셋(§11.1)과 거부 경로.

**끝나면**: 시뮬레이터에서 학교 반경을 넘으면 보호자 알림 탭에 "학교에
도착했어요"가 뜨고, 머무름에 이름이 붙는다.

### 3단계 — 아이 화면과 권한, 그리고 아이 역할 켜기

- `Child/`: `ChildPermissions`, `ConditionWatcher`, `DeviceState`,
  `ChildHomeModel`, `ChildHomeView`, `ChildRootView`.
- 역할 선택 화면의 막이 제거, `JoinFamilyView(expectedRole: .child)`,
  `RouterView` 의 child 갈래, `RoleStore` 저장.
- 새 i18n 키(§8.5) + `tools/ios-strings.py` 의 `INFOPLIST_KEYS` 확장 +
  `ios_child_unsupported_*` 셋 제거.

**끝나면**: 에뮬레이터를 상대로 아이로 페어링해 아이 화면까지 가고, 권한을
하나씩 꺼 보면 화면 문장이 바뀌고 `permission_off` 이벤트가 부모 쪽에 뜬다.

### 4단계 — 보호자 차단, 전수 검토, 실기기 확인

- `platform` 쓰기(1단계의 상태 문서에 이미 들어 있다)와 읽기,
  `Guardian/ChildPlatform` + 세 화면 잠금(§10.2).
- 전수 검토: 상수 대조표(§4)를 코드와 한 줄씩 대조, 골든 대조가 **정말로 무는지**
  일부러 값을 망가뜨려 확인(2단계에서 이 확인이 가장 중요했다).
- **주인의 허락을 받은 뒤** 실기기 검증 열 항목(§12.4).

**끝나면**: 아이폰 아이가 붙은 가족에서 보호자 화면이 못 하는 것을 정직하게
잠그고, 실기기에서 하루를 재 본 숫자가 §9.1 을 대체한다.

---

## 15. 아이폰이라서 안드로이드와 똑같이 못 하는 것

구현 중에 "왜 다르지"가 나올 자리를 미리 적는다.

1. **시간 간격으로 위치를 요청할 수 없다.** 연속 스트림을 소프트웨어로 솎아
   같은 밀도를 만든다(§5.1). 5초 간격은 근사치이지 요청값이 아니다.
2. **강제 종료 뒤 되살아나지 않는다.** 안드로이드는 `START_STICKY` 와
   `BOOT_COMPLETED` 로 몇 초 안에 돌아온다. 아이폰은 아이가 앱을 직접 열거나
   폰을 껐다 켤 때까지 아무것도 없다. **가장 큰 차이다.**
3. **활동 인식에 대응하는 "죽은 앱을 깨우는" 장치가 없다.** CoreMotion 은
   살아 있을 때만 물어볼 수 있다. 그래서 좌표 기반 판정기 하나에 더 기대고,
   안드로이드에는 없는 상수 `STILL_ESCALATE_MILLIS`(5분, §4.8) 하나를 새로
   만든다 — 활동 인식 전환이 하던 "이제 정말 멈췄다"를 시간으로 대신한다.
   **이 설계에서 안드로이드에 대응이 없는 유일한 상수다.**
4. **부모가 물어볼 수 없다.** `locate_now`·실시간 보기가 없어지고 아이 폰의
   자체 주기가 그 자리를 대신한다(§6.4). 부모가 "지금" 을 누를 수 없다는 뜻이다.
5. **소리·예약·폰찾기·알람·메시지가 통째로 없다.** API 가 없다.
6. **상시 알림 대신 파란 표시다.** 같은 "몰래 안 한다"를 하지만 아이가 그것을
   눌러 앱을 열 수는 없다.
7. **위치 권한 0개라는 성질을 잃는다.** 지금 아이폰 앱의 자랑이던 것
   (`2026-09-12-kidcare-ios-design.md` §1)이 깨진다. 같은 바이너리가 백그라운드
   위치를 요구하게 되므로 앱스토어 심사에서 가이드라인 2.5.4 를 정면으로 만난다.
   내세울 근거는 셋이다: 아이 안전이라는 목적, 항상 켜지는 파란 표시,
   그리고 "지금 엄마 아빠가 볼 수 있어요"를 숨기지 않는 아이 화면.
   **이건 '앱 하나' 결정의 대가이고, 피할 방법이 없다.**
8. **정확한 위치를 끄면 완전히 조용해진다.** 안드로이드에 정확히 대응하는
   상태가 없다(§8.2).

---

## 16. 지킬 제약

- **Swift 6 엄격 동시성**, **iOS 17**, **SwiftUI**, **XcodeGen**, **Swift Testing**.
- `Logic/` 은 **Foundation 만** import 한다. CoreLocation 도 Firebase 도 안 된다.
- 앱 코드에 **`@unchecked Sendable` 과 `nonisolated(unsafe)` 를 쓰지 않는다.**
- **푸시 알림과 FCM 을 쓰지 않는다.** Spark 무료 요금제를 지킨다.
- 새 문구는 `i18n/ko.json`·`i18n/en.json` **둘에만** 넣고
  `python3 tools/ios-strings.py` 로 생성한다. **번역을 지어내지 않는다** —
  나머지 12개 언어는 영어로 채워지고 `tools/i18n-untranslated.json` 에 남는다.
- 주석은 한국어로, **"왜"** 를 적는다. 코드가 말하는 "무엇"을 되풀이하지 않는다.
- 커밋 메시지는 한국어, 작성자 `Yongminlee2 <dydals5678@gmail.com>`.
  **AI 흔적을 남기지 않는다**(Co-Authored-By 금지).
- `app/src/main`, `firestore.rules`, `gradlew` 를 고치지 않는다.
  유일한 예외는 `app/src/test/.../GoldenFileWriterTest.kt` 다(§12.2, 열린 질문 1).
- `CancellationException` 에 대응하는 Swift 의 `CancellationError` 를
  일반 `catch` 로 삼키지 않는다 — 안드로이드에서 같은 사고를 아홉 번 고쳤다
  (README "코드 작성 규칙").

---

## 17. 열린 질문 — 코드만 봐서는 못 정한 것

각각에 내 추천을 붙였다.

1. **`app/src/test/.../GoldenFileWriterTest.kt` 를 고쳐도 되나?**
   작업 지시는 `app/` 을 고치지 말라고 했는데, 골든 파일은 코틀린이 뽑아야만
   의미가 있다(정본이 코틀린이라서). 2단계가 정확히 같은 예외를 썼고 README 에
   "유일한 변경은 골든 파일을 뽑는 테스트 한 개"라고 적혀 있다.
   **추천: 이 파일 하나만 허용한다.** 안 되면 아이 로직의 교차 검증이 통째로
   사라지는데, 그건 이 설계에서 가장 값싼 안전장치를 버리는 것이다.

2. **지역 감시에 `CLMonitor`(iOS 17)를 쓸까, 예전 API 를 쓸까?**
   **추천: `CLLocationManager.startMonitoring(for:)` 으로 시작한다.**
   deprecated 경고를 받지만 "앱이 죽어 있어도 되살린다"는 계약이 오래 검증됐다.
   이 설계 전체가 그 계약 위에 있다. 4단계에서 `CLMonitor` 가 똑같이
   되살리는 것을 실기기로 확인하면 그때 옮긴다.

3. **강제 종료 뒤에 지역 감시·중요 위치 변경이 앱을 되살리나?**
   애플 문서와 현장 보고가 어긋난다. **추천: "안 되살린다"를 가정하고 설계한다**
   (지금 문서가 그렇게 적혀 있다). 4단계에서 실제로 되살아나면 그건 덤이고,
   반대로 "된다"를 가정했다가 안 되면 하루가 통째로 조용해진다.

4. **백그라운드 앱 새로고침을 끄면 백그라운드 위치가 멎나?**
   애플 문서가 얇다. **추천: 멎는다고 가정하고 고장으로 취급한다**
   (아이 화면 문구 + `permission_off` 이벤트). 4단계에서 안 멎는 것이 확인되면
   그 문구와 이벤트를 뺀다 — 거짓 경고를 남겨두느니 지운다.

5. **CoreMotion(`CMMotionActivityManager`)으로 활동 인식을 흉내 낼까?**
   **추천: v1 에서는 안 쓴다.** 권한과 사용 설명이 하나 더 늘고, 죽은 앱을
   깨우지도 못한다. 안드로이드가 이미 "활동 인식 권한이 없어도 좌표 판정기
   하나로 돈다"고 검증해 뒀다(`ConditionWatcher.kt:47-48`). 실기기에서 짧은
   외출을 자주 놓치면 그때 다시 본다.

6. **업로드 주기 15분 / 4시간이 맞나?**
   §11.2 의 계산으로는 안드로이드와 거의 같은 쓰기 수가 나온다.
   **추천: 그대로 시작하고 4단계에서 하루를 재 본 뒤 조정한다.**
   부모가 "너무 뜸하다"고 느끼면 15분을 내리는 대신, 이벤트 직후 강제 업로드
   조건을 넓히는 쪽(예: 머무름이 끝난 직후)이 비용 대비 효과가 낫다.

7. **`ios_child_unsupported_*` 세 키를 지울까, 남길까?**
   **추천: 지운다.** `ko.json`·`en.json` 에만 있고 안드로이드가 안 쓰는 것을
   확인했다. 쓰는 곳 없는 키를 남기면 다음 사람이 "아직 아이를 막는구나"로
   읽는다.

8. **안드로이드 보호자 화면은 아이폰 아이에게 계속 버튼을 보여준다.**
   이 작업은 `app/` 을 안 고치므로 남는다. 부모가 안드로이드 폰으로 아이폰
   아이에게 명령을 보내면 영영 "전달 중"에 머문다.
   **추천: 후속 과제로 분리한다.** 고치는 자리는 `guardian/ControlFragment.kt`,
   `guardian/MapTimelineFragment.kt`, `guardian/ScheduleFragment.kt` 셋이고,
   재료(`platform` 필드)는 이 작업이 이미 심어 둔다.

9. **아이 화면에 '다시 연결' 버튼을 둘까?**
   안드로이드는 둔다(`ChildHomeActivity.kt:159-181`). 아이가 스스로 감시를 풀
   수 있다는 걱정이 있었는데, 그 버튼은 **서버가 "이 기기는 이 가족의 멤버가
   아니다"라고 확답했을 때에만** 뜨므로 그때는 이미 풀 감시가 없다.
   **추천: 같은 조건으로 둔다.**

10. **사용자에게 보이는 새 문장 넷을 누가 쓰나?**
    위치 사용 설명 둘(`NSLocation*UsageDescription` — 앱스토어 심사가 직접
    읽는다), 보호자 화면의 잠금 설명 둘(§10.2).
    **추천: 이 문서의 초안으로 시작하고 주인이 고친다.** 위치 설명 초안:
    "엄마 아빠가 지금 어디 있는지 볼 수 있게 위치를 보냅니다.
    화면이 꺼져 있을 때도 보내야 길을 잃었을 때 찾을 수 있어요."
    번역은 지어내지 않으므로 `ko`·`en` 둘만 쓴다.

11. **`CLLocationManager.startMonitoringVisits()` 를 배터리 손잡이로 볼까?**
    아이폰에만 있는 아주 저전력 장치로, 도착·출발을 알려준다.
    **추천: 안 쓴다.** 경로를 못 만들고 시각이 거칠어서 이 앱이 하는 일을
    대체하지 못한다. 실기기 배터리 측정이 참담하게 나오면 그때 "정지 구간만
    이걸로 대체"를 검토한다 — 그건 밀도 결정(§2-1)을 다시 여는 일이라
    주인의 판단이 필요하다.
