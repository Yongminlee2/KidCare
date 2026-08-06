# KidCare — 자녀 관리 안드로이드 앱 설계서

작성일: 2026-08-06
상태: 초안 (사용자 검토 대기)

## 1. 무엇을 만드는가

부모(엄마) 폰과 자녀(아이) 폰에 각각 설치해서, 부모가 자녀 폰의 위치 이력을 보고
소리/진동 모드를 원격으로 제어하는 안드로이드 네이티브 앱.

핵심 기능 6가지:

1. **위치 경로 이력** — 카카오맵 위에 하루 이동 경로를 선으로 그리고, 그 아래에
   "몇 시부터 몇 시까지 어디에 있었고, 언제 어디로 이동했는지"를 글로 요약해 보여준다.
2. **소리/진동 즉시 변경** — 부모가 버튼을 누르면 자녀 폰의 벨소리/진동/무음이 바로 바뀐다.
3. **시간대별 모드 예약** — "평일 09:00~15:00 진동", "매일 22:00~07:00 무음" 같은 규칙을
   등록하면 자동으로 적용된다.
4. **핸드폰 찾기** — 무음 상태여도 최대 볼륨으로 벨을 울리고 진동하며 화면을 켠다.
5. **알림 4종** — 장소 도착/이탈, 원격 알람시계 예약, 상황 경고(배터리·전원·연결끊김),
   부모가 보내는 짧은 메시지.
6. **페어링** — 부모 폰이 6자리 초대 코드를 만들고 자녀 폰이 입력하면 연결된다.

### 만들지 않는 것 (명시적 제외)

- **몰래 감시(은닉) 기능**. 자녀 폰에 앱 아이콘이 보이고, 아이도 자기 위치가 공유 중임을
  확인할 수 있다. 접근성 서비스로 다른 앱을 훔쳐보는 방식(스토커웨어 기법)은 쓰지 않는다.
- **기기관리자(Device Admin) 권한을 이용한 앱 삭제 방지**. 오작동 시 폰 초기화까지 얽히고
  아이 폰에 걸어두기엔 위험이 크다. 대신 삭제되면 신호가 끊기고 15분 뒤 "연결 끊김"으로
  부모에게 알린다. (안드로이드는 앱이 자기 삭제 순간을 감지할 수 없다.)
- **통화·문자·앱 사용시간 감시**. 이번 범위 밖.

### 배포 방식

가족끼리 APK 직접 설치. 플레이스토어에 올리지 않는다.
따라서 개인정보처리방침 문서, 데이터 안전 신고, 백그라운드 위치 권한 신청서,
가족 정책 심사 대응은 이번 범위에 포함하지 않는다.

## 2. 기술 스택과 프로젝트 구성

### 위치와 빌드 환경

- 프로젝트 루트: `C:\workAndroid\KidCare` (독립 Gradle 루트, HomeCam과 무관)
- AGP 9.2.1 (Kotlin 내장) / Gradle 9.4.1
- compileSdk 37 / minSdk 26 / targetSdk 36
  (compileSdk 는 `core-ktx 1.19.0` 이 요구하는 최소값이다. 36 으로 두면 AGP 가 빌드를 거부한다.)
- UI: Views + ViewBinding + Material3 (Compose 안 씀 — 기존 프로젝트 관례 유지)
- applicationId: `com.kidcare.family`

> minSdk 26의 근거: 카카오맵 SDK v2는 API 23 이상을 요구하고, 기존 프로젝트가 26을 쓴다.
> 26이면 `JobScheduler`, `NotificationChannel`, `ForegroundService`가 모두 안정적으로 쓸 수 있다.

### 외부 의존성

| 의존성 | 용도 | 비고 |
|---|---|---|
| `com.kakao.maps.open:android` | 지도 표시, 경로 폴리라인, 역지오코딩 | 카카오 개발자 앱키 필요. Maven repo `https://devrepo.kakao.com/nexus/content/groups/public/` 추가 |
| Firebase Auth (익명) | 기기 식별 | 계정 생성 불필요 |
| Firebase Firestore | 위치·명령·예약·이벤트 저장 | |
| Firebase Cloud Messaging | 명령/알림 즉시 전달 | |
| Firebase Cloud Functions | 푸시 발송, 오래된 데이터 정리 | **Blaze 플랜 필요** |
| `play-services-location` | FusedLocationProvider, Geofencing, ActivityRecognition | 위치 수집·장소 판정·이동/정지 감지를 모두 담당 |
| Room | 자녀 폰 오프라인 위치 버퍼 | |

### Firebase 요금제 — Spark(무료)로 간다

**2026-08-07 변경.** 처음에는 Blaze(종량제)를 택했다. FCM 푸시를 보내려면 Cloud Functions가
필요하고 그건 Blaze 전용이기 때문이다. 다시 따져보니 이 앱에는 그 전제가 성립하지 않는다.

FCM이 사주는 것은 **"잠든 앱을 깨우는 능력"** 인데, **자녀 폰은 잠들지 않는다.** 위치 수집을
위해 어차피 상시 포그라운드 서비스가 돌고 배터리 최적화도 제외해 둔다(§2 자녀폰 ⑥). 그
서비스 안에 Firestore 스냅샷 리스너를 얹으면 명령이 1~3초 안에 도착한다. 추가 비용 0원,
카드 등록 불필요.

무료와 유료가 실제로 갈리는 경우는 하나뿐이다: **OEM 절전 정책이 포그라운드 서비스까지
강제 종료했을 때.** 배터리 최적화 제외를 걸어두면 드물고, 그 설정은 위치 추적 때문에 어차피
해야 한다. 그 한 줄을 위해 카드를 등록시키는 것은 값이 맞지 않는다.

**나중에 실사용에서 명령 유실이 실제로 관측되면** 두 갈래로 올릴 수 있다.

1. Blaze + Cloud Functions + FCM (원래 계획)
2. **Cloudflare Workers 무료 티어**에 푸시 중계기를 띄우고 서비스 계정 키를 거기 보관.
   카드 등록이 없고 키가 APK 안에 들어가지 않는다.

`google-services.json`에 FCM 설정이 이미 들어 있으므로 **어느 쪽으로 가든 Firebase를 다시
만들 필요는 없다.** 그러려면 명령 전달 계층을 인터페이스 하나로 감싸서, 전송 수단을 바꿔도
호출하는 쪽 코드가 그대로여야 한다 — 4단계 설계의 필수 제약이다.

**서비스 계정 키를 APK에 넣어 폰이 직접 FCM을 호출하는 방식은 쓰지 않는다.** APK를 가진
사람이면 누구나 이 Firebase 프로젝트에 쓸 수 있게 된다.

## 3. 아키텍처

### 앱 구성

APK는 하나. 첫 실행 시 역할을 고른다.

```
설치 → 역할 선택 ─┬─ 보호자 → 초대코드 생성 → 자녀가 연결될 때까지 대기
                 └─ 자녀   → 초대코드 입력 → 권한 온보딩 → 상시 서비스 시작
```

페어링 후 역할은 잠긴다. 바꾸려면 앱 데이터를 초기화하고 부모 폰의 코드를 다시 받아야 한다.

### 모듈 경계

단일 `:app` 모듈 안에서 패키지로 나눈다. (모듈 분리는 빌드만 느려지고 이득이 없는 규모)

```
com.kidcare.family
├─ core/           역할·페어링·Firebase 접근 (양쪽 공용)
│   ├─ FamilyRepository      가족 문서 CRUD, 페어링
│   ├─ CommandRepository     명령 발행/수신/상태전이
│   ├─ LocationRepository    포인트·구간 읽기/쓰기
│   ├─ ScheduleRepository    시간대 규칙
│   └─ model/                Firestore 문서와 1:1 대응하는 데이터 클래스
├─ child/          자녀 폰 전용
│   ├─ TrackingService       상시 포그라운드 서비스 (전체 조율자)
│   ├─ LocationCollector     FusedLocation + ActivityRecognition
│   ├─ SegmentUploader       SegmentBuilder를 호출해 결과를 Firestore에 반영
│   ├─ RingerController      소리/진동 모드 변경·감시·되돌리기
│   ├─ FindPhoneController   폰찾기 벨/진동/화면
│   ├─ ScheduleApplier       AlarmManager로 시간대 규칙 적용
│   ├─ RemoteAlarmScheduler  원격 알람시계
│   ├─ GeofenceMonitor       장소 도착/이탈
│   ├─ HealthReporter        배터리·전원·권한 상태 보고
│   └─ OfflineBuffer         Room 기반 미전송 위치 큐
├─ guardian/       보호자 폰 전용
│   ├─ MapTimelineFragment   지도 + 타임라인 (메인)
│   ├─ ControlFragment       즉시 변경·폰찾기·메시지·알람
│   ├─ ScheduleFragment      시간대 규칙 + 장소 등록
│   ├─ EventsFragment        알림 이력
│   └─ CommandTracker        명령 상태 표시(전달 중/완료/무응답)
└─ logic/          양쪽에서 쓰는 순수 계산   ★전부 단위테스트 대상
    ├─ ScheduleResolver      규칙 겹침·자정 넘김·즉시변경 충돌 해석
    ├─ GeofenceEvaluator     반경 진입/이탈 판정 (히스테리시스 포함)
    ├─ SegmentBuilder        위치 점 목록 → 머무름/이동 구간
    └─ SegmentSummarizer     구간을 사람이 읽는 문장으로
```

각 클래스는 "무엇을 하는가 / 어떻게 쓰는가 / 무엇에 의존하는가"가 한 줄로 설명되어야 한다.
특히 `logic/` 아래는 안드로이드 API에 의존하지 않는 순수 코틀린으로 유지해 JVM 테스트가
가능하게 한다. 이 경계를 지키는 것이 테스트 전략의 전제다.

### 데이터 흐름

```
[자녀폰]                        [Firebase]                     [보호자폰]
LocationCollector
  → 50m 이상 이동?
  → points/ 쓰기      ────────►  points/
  → SegmentBuilder
  → segments/ 갱신    ────────►  segments/  ───────────────►  타임라인 화면
  → status 덮어쓰기   ────────►  status     ───────────────►  상단 상태줄

                                 commands/  ◄───────────────  버튼 누름
                                    │
                    Cloud Function ─┘ (onCreate)
                                    ↓ FCM 고우선순위
TrackingService ◄──────────────────┘
  → 실행 → commands/{id}.state = done  ──►  ─────────────►  "완료" 표시

GeofenceMonitor / HealthReporter
  → events/ 쓰기      ────────►  events/
                                    │
                    Cloud Function ─┘ (onCreate)
                                    ↓ FCM
                                                            알림 표시
```

### Firestore 문서 구조

```
families/{familyId}
  name, createdAt, inviteCode, inviteExpiresAt

  members/{uid}
    role: "guardian" | "child"
    displayName, fcmToken, appVersion, updatedAt

  children/{childUid}/status            (문서 1개, 계속 덮어씀)
    lat, lng, accuracy, at
    battery, charging
    ringerMode: "normal" | "vibrate" | "silent"
    lastSeenAt
    permissions: { location, background, dnd, batteryOpt, notification, exactAlarm }

  children/{childUid}/points/{autoId}   (30일 뒤 자동 삭제)
    lat, lng, accuracy, speed, at, battery

  children/{childUid}/segments/{autoId}
    type: "stay" | "move"
    startAt, endAt
    placeId | null, placeName, lat, lng      (stay)
    distanceMeters, fromName, toName          (move)

  children/{childUid}/commands/{autoId}
    type: "set_ringer" | "find_phone" | "stop_find" | "locate_now"
        | "set_alarm" | "cancel_alarm" | "message" | "sync_rules"
    payload: {...}
    state: "pending" | "delivered" | "done" | "failed"
    createdAt, deliveredAt, doneAt, error

  places/{id}
    name, lat, lng, radiusMeters
    notifyEnter, notifyExit

  schedules/{id}
    days: [1..7]
    startMinute, endMinute        (0~1439, 자정 기준 분)
    mode: "normal" | "vibrate" | "silent"
    enabled, priority

  events/{id}
    type: "enter" | "exit" | "low_battery" | "power_off"
        | "signal_lost" | "permission_off" | "command_failed"
    at, childUid, placeName, detail, read
```

### 보안 규칙

- 로그인하지 않은 요청은 전부 거부.
- `families/{familyId}` 하위는 `members/{uid}` 문서가 존재하는 uid만 접근 가능.
- 자녀 uid는 `children/{자기uid}` 아래에만 쓸 수 있다. `commands/`는 읽기 + `state` 필드
  갱신만 허용(명령 생성 불가).
- 보호자 uid만 `commands/`, `places/`, `schedules/` 생성·수정 가능.
- `inviteCode`는 10분 뒤 만료. 페어링이 끝나면 즉시 무효화한다.

### Cloud Functions (3개)

1. `onCommandCreated` — `commands/` 문서 생성 시 해당 자녀 폰에 FCM 고우선순위 data 메시지.
2. `onEventCreated` — `events/` 문서 생성 시 가족 내 보호자 전원에게 FCM 알림 메시지.
3. `dailyCleanup` — 매일 04:00(KST) 30일 지난 `points/` 삭제.

## 4. 핵심 로직 규칙

이 절의 규칙들이 앱의 실제 품질을 가른다. 전부 `logic/` 패키지의 순수 함수로 구현하고
단위 테스트로 고정한다.

### 4.1 위치 수집 주기

| 상태 | 주기 | 정확도 |
|---|---|---|
| 정지 (ActivityRecognition = STILL) | 5분 | BALANCED_POWER |
| 이동 (WALKING/RUNNING/ON_BICYCLE/IN_VEHICLE) | 1분 | HIGH_ACCURACY |
| 부모가 "지금 위치" 요청 | 즉시 1회 | HIGH_ACCURACY |

- 직전 업로드 지점에서 50m 이내면 업로드를 생략한다(배터리·통신량·Firestore 사용량).
  단 10분 이상 업로드가 없었으면 정지 상태 확인용으로 한 번 올린다.
- 정확도(accuracy) 100m 초과 지점은 구간 계산에서 제외한다. 지도에는 흐리게 표시한다.
- 기본값은 위와 같고, 앱 설정에서 "촘촘히 / 잡으면 쓰기 / 배터리 아끼기" 3단으로 바꿀 수 있다.

### 4.2 구간 묶기 (SegmentBuilder)

- **머무름 판정**: 연속된 지점들이 반경 100m 안에 **5분 이상** 유지되면 `stay`.
- 머무름이 끝나는 조건: 반경 100m를 벗어난 지점이 **연속 2개** 나올 때. (1개는 GPS 튐일 수 있음)
- `stay`가 아닌 구간은 `move`. 이동 거리는 지점 간 거리의 합.
- 5분 미만의 짧은 정지는 `move` 안에 흡수한다(신호 대기 등).
- **장소 이름**: ① `places/`에 등록된 반경 안이면 그 이름, ② 아니면 카카오 로컬 API
  역지오코딩으로 "○○동 123-4", ③ 조회 실패 시 "알 수 없는 장소".
- 구간 계산은 자녀 폰에서 한다. 보호자 폰이 하루치 원시 점(최대 ~500개)을 매번 읽으면
  느리고 Firestore 읽기 사용량도 커진다. 요약본은 하루 20~30건이면 충분하다.

### 4.3 시간대 규칙 해석 (ScheduleResolver)

가장 버그가 나기 쉬운 부분이므로 규칙을 명시적으로 고정한다.

- 시각은 **자정 기준 분(0~1439)** 으로 저장한다.
- `startMinute > endMinute`이면 자정을 넘는 규칙이다. 예: `22:00~07:00` = `1320 ~ 420`.
  이 경우 "오늘 22:00부터 내일 07:00까지"로 해석하며, **요일은 시작 시각 기준**으로 판정한다.
  즉 "평일 22:00~07:00"은 금요일 밤~토요일 아침을 포함한다.
- 두 규칙이 겹치면 `priority`가 큰 쪽이 이긴다. 같으면 **나중에 시작한 규칙**이 이긴다.
  `priority`는 규칙을 만든 순서대로 자동 부여하며(나중에 만든 것이 큼) v1에서는 화면에
  노출하지 않는다. 겹치는 규칙을 만들면 "이 시간대는 ○○ 규칙과 겹칩니다"라고 경고만 띄운다.
- **즉시 변경과의 충돌**: 부모가 즉시 변경을 누르면 그 모드는 **다음 규칙 경계 시각까지만**
  유효하다. 그 시각이 되면 규칙이 다시 적용된다. 보호자 화면에는
  "22:00에 무음으로 자동 전환됩니다"를 미리 표시한다.
  **적용 중인 규칙이 하나도 없으면 즉시 변경은 계속 유지된다**(해제 시각 없음). 이때
  보호자 화면에는 자동 전환 안내 대신 "예약된 규칙 없음"이라고 표시한다.
- 적용은 `AlarmManager.setExactAndAllowWhileIdle`로 규칙 경계마다 깨워서 수행한다.
  `BOOT_COMPLETED`와 `TIME_SET` 수신 시 전부 재등록한다.
- 시각은 모두 UTC 밀리초로 저장하고 표시할 때만 기기 시간대로 바꾼다.

### 4.4 되돌리기 (RingerController)

"아이가 되돌리면 다시 바꾸기" 스위치가 켜져 있으면:

- `AudioManager.RINGER_MODE_CHANGED_ACTION`을 수신한다.
- 현재 적용돼야 할 모드(= 즉시 변경 또는 규칙이 정한 모드)와 다르면 **3초 뒤** 되돌린다.
  즉시 되돌리면 무한 루프처럼 보이고 아이가 폰이 고장난 줄 안다.
- 되돌린 사실을 `events/`에 남긴다. 하루 5회를 넘으면 부모에게 알린다
  (계속 싸우게 두지 않고 부모가 판단하게 한다).

### 4.5 핸드폰 찾기 (FindPhoneController)

- `STREAM_ALARM`으로 재생한다. 벨소리 무음/진동 상태와 무관하게 울린다.
- 실행 전 현재 알람 볼륨을 저장하고 최대로 올린다. 끝나면 복구한다.
- 전체 화면 알림 + `KEYGUARD_DISABLE`로 잠금화면 위에 "엄마가 찾고 있어요" + 중지 버튼.
- **5분이 지나면 자동으로 멈춘다.** 부모가 못 끄는 상황에서 계속 울리는 사고를 막는다.
- 부모 폰에서도 `stop_find` 명령으로 끌 수 있다.
- 이 기능은 **방해금지 접근 권한(ACCESS_NOTIFICATION_POLICY)** 이 필요하다.

### 4.6 장소 판정 (GeofenceEvaluator)

- `GeofencingClient`(OS 제공)를 1차로 쓴다. 배터리 효율이 좋다.
- 지오펜스는 최대 100개까지 등록 가능하나, 실용상 20개로 제한한다.
- **히스테리시스**: 진입은 반경 그대로, 이탈은 반경 + 50m를 넘어야 인정한다.
  경계에 앉아 있을 때 도착/이탈 알림이 반복되는 것을 막는다.
- 같은 장소의 같은 방향 이벤트는 5분 안에 중복 발행하지 않는다.
- `BOOT_COMPLETED` 후 지오펜스를 재등록한다(OS가 재부팅 시 지운다).

## 5. 오류 처리

| 상황 | 처리 |
|---|---|
| 자녀 폰 인터넷 끊김 | Room에 위치를 쌓아두고 연결되면 일괄 업로드. 최대 24시간분(초과분은 오래된 것부터 버림) |
| 명령이 전달 안 됨 | `commands.state`로 추적. 보호자 화면에 `전달 중…` → `완료`. **60초 무응답이면 "애기폰이 응답하지 않아요"** 로 정직하게 표시하고, 마지막 신호 시각을 함께 보여준다 |
| 명령 중복 실행 | 명령 문서 ID를 자녀 폰이 기억(최근 100개). 이미 처리한 ID는 무시한다 |
| 권한이 꺼짐 | 자녀 폰이 `status.permissions`에 실시간 반영. 보호자 화면 상단에 빨간 띠로 경고 + 어떤 권한인지 명시 |
| 서비스가 강제 종료됨 | `START_STICKY` + `BOOT_COMPLETED` 재시작 + 15분 무신호 시 `signal_lost` 이벤트 |
| GPS 튐 | 정확도 100m 초과 지점 제외. 직전 지점 대비 시속 200km 초과 이동은 버림 |
| 카카오맵 앱키 오류 | 지도 대신 "지도 키 설정이 필요합니다" 안내 화면. 나머지 기능은 정상 동작 |
| Firebase 사용량 초과 | 예산 알림 설정 안내. 앱은 쓰기 실패 시 로컬 버퍼에 보관 |
| 폰찾기 벨이 안 꺼짐 | 자녀 폰 화면 중지 버튼 + 5분 자동 정지 (이중 안전장치) |
| 배터리 최적화가 다시 켜짐 | 주기적으로 확인해 꺼져 있으면 부모에게 알림 |

## 6. 테스트 전략

### 단위 테스트 (JUnit, `logic/`과 `SegmentBuilder` 대상)

안드로이드 API에 의존하지 않는 순수 로직만 대상으로 한다.

- `ScheduleResolverTest` — **가장 두껍게 깐다**
  - 자정 넘는 규칙(22:00~07:00)이 어제/오늘/내일 경계에서 올바르게 판정되는가
  - 요일 판정이 시작 시각 기준인가 (금요일 밤 규칙이 토요일 새벽까지 유지되는가)
  - 규칙 2개가 겹칠 때 우선순위/나중 시작 규칙이 이기는가
  - 즉시 변경이 다음 경계에서 정확히 해제되는가
  - 규칙이 하나도 없을 때, 전부 비활성일 때
- `SegmentBuilderTest`
  - 5분 미만 정지가 이동에 흡수되는가
  - GPS 튐 1개가 머무름을 깨뜨리지 않는가
  - 하루 종일 집에 있으면 머무름 1개로 나오는가
  - 정확도 나쁜 지점이 제외되는가
- `GeofenceEvaluatorTest`
  - 히스테리시스가 경계 왕복에서 알림 폭탄을 막는가
  - 중복 억제 5분이 동작하는가

### 계측 테스트는 두지 않는다

기기·권한·OEM 정책에 좌우돼서 CI 가치가 낮고, 실제 검증은 두 대의 실기기로 한다.
대신 각 구현 단계마다 실기기 확인 절차를 계획에 넣는다.

### 이 PC 환경 주의사항

- 사용자 홈이 `C:\Users\사용자`(한글)라서 JVM 테스트 워커가 `ClassNotFoundException`으로
  죽는다. `gradle.properties`에 `org.gradle.jvmargs=... -Dfile.encoding=MS949`를 넣는다.
- `GRADLE_USER_HOME`으로는 해결되지 않는다. `gradle-user-ascii`는 한글 경로로 가는 정션이다.

## 7. 구현 순서

단계마다 실기기에 설치해 확인하고 넘어간다.
이 설계서는 7단계 전체를 덮지만, **구현 계획서는 단계별로 따로 쓴다.** 앱 하나를 한 번에
계획하면 뒤 단계가 앞 단계의 실기기 결과를 반영하지 못한다. 1~2단계를 먼저 계획하고,
실기기로 위치가 제대로 올라오는 것을 확인한 뒤 3단계 이후를 계획한다.

| 단계 | 내용 | 완료 기준 |
|---|---|---|
| 1 | 프로젝트 뼈대, Firebase 연결, 역할 선택, 페어링 | 두 폰이 서로 연결됐다고 표시된다 |
| 2 | 권한 온보딩, 위치 수집, 지도에 현재 위치 | 부모 폰 지도에 아이 현재 위치가 보인다 |
| 3 | 구간 요약, 타임라인, 날짜 이동 | 하루 경로가 선 + 글로 보인다 |
| 4 | 소리/진동 즉시 변경, 되돌리기, 핸드폰 찾기 | 버튼 누르면 5초 안에 아이 폰이 반응한다 |
| 5 | 시간대 예약 | 등록한 시각에 모드가 자동으로 바뀐다 |
| 6 | 장소 반경, 도착/이탈 알림, 메시지, 원격 알람, 상황 경고 | 알림이 부모 폰에 뜬다 |
| 7 | 오프라인 처리, 예외 화면, 릴리스 APK 서명 | 비행기 모드 후 복구 시 데이터가 안 빠진다 |

## 8. 사용자가 직접 해야 하는 준비

코드로 대신할 수 없는 것들. 각 단계에서 누를 버튼 순서까지 안내한다.

1. **카카오 개발자 앱키** — [developers.kakao.com](https://developers.kakao.com) 가입 →
   애플리케이션 추가 → 플랫폼에 Android 등록(패키지명 `com.kidcare.family` + 키 해시) →
   네이티브 앱 키 발급. 키는 `local.properties`에 넣고 git에 올리지 않는다.
2. **Firebase 프로젝트** — 콘솔에서 프로젝트 생성 → Android 앱 추가(같은 패키지명) →
   `google-services.json` 내려받아 `app/`에 넣기 → Blaze 플랜 업그레이드 →
   예산 알림 1,000원 설정 → Firestore·Authentication(익명)·Cloud Messaging 활성화.
3. **두 폰에 설치 후 권한 켜기** — 자녀 폰의 위치(항상 허용), 방해금지 접근,
   배터리 최적화 제외, 알림, 정확한 알람, 활동 인식.
   삼성 기기는 "설정 → 배터리 → 백그라운드 사용 제한"에서도 제외해야 한다.

## 9. 결정 기록

| 결정 | 대안 | 이유 |
|---|---|---|
| ~~Firebase Blaze~~ → **Spark 무료** | Blaze + Cloud Functions + FCM | 2026-08-07 뒤집음. 자녀 폰은 위치 수집용 포그라운드 서비스로 상시 깨어 있으므로 FCM이 사주는 "잠든 앱 깨우기"가 필요 없다. Firestore 리스너로 1~3초면 명령이 닿는다. 카드 등록 없이 간다. 유실이 실제로 관측되면 Blaze 또는 Cloudflare Workers 중계로 승격 |
| 단일 APK + 역할 선택 | 보호자용/자녀용 APK 분리 | 빌드와 설치가 한 번. 페어링으로 역할이 잠기므로 아이가 임의로 바꿀 수 없다 |
| 구간 계산을 자녀 폰에서 | 보호자 폰에서 / Cloud Function에서 | 보호자가 원시 점을 매번 읽으면 느리고 사용량이 크다. Function은 비용 발생 지점이 늘어난다 |
| 지도+타임라인 병행 | 지도만 / 목록만 | "몇 시에 어디서 어디로"라는 요구가 글 요약이라야 한 눈에 읽힌다. 지도는 맥락용 |
| 은닉 기능 없음 | 아이콘 숨김 | 스토커웨어 기법이고 정책 위반. 투명한 공유가 가족 관계에도 낫다 |
| 기기관리자 권한 안 씀 | 삭제 방지 | 오작동 시 기기 초기화까지 얽히는 위험이 이득보다 크다 |
| Views + ViewBinding | Compose | 기존 프로젝트 관례 유지. 지도 SDK가 View 기반이라 상호운용 비용도 없다 |

## 10. 남은 미결정 사항

- 앱 이름(한글 표시명). 현재 가안: "우리아이 지킴이". 사용자 확정 필요.
- 자녀가 여러 명인 경우. 이번 설계는 데이터 구조상 다자녀를 지원하지만
  (`children/{childUid}`), 보호자 화면 UI는 자녀 1명 기준으로 만든다.
  2명 이상이 필요해지면 상단에 자녀 선택 탭을 추가한다.
- 보호자가 2명(엄마·아빠)인 경우. 데이터 구조는 지원한다(`members/`에 여러 guardian).
  초대 코드를 한 번 더 발급하면 된다. UI 작업은 1단계에 포함한다.
