# 6단계 구현 계획 — 오프라인·예외 화면·출시 준비

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 통신이 끊겨도 데이터가 안 빠지고, 실패한 자리마다 무엇을 해야 하는지 화면이 말하고, 서명된 릴리스 APK 가 나온다.

**Architecture:** 오프라인은 새로 만들 것이 거의 없다 — Firestore 는 안드로이드에서 로컬 캐시와 쓰기 큐가 기본으로 켜져 있고, 자녀 폰의 하루치 경로는 이미 파일에 쌓인다. 이 단계가 하는 일은 **그 사실을 확인하고, 화면이 거짓말하지 않게 만드는 것**이다. 그 위에 런처 아이콘, 예외 화면, R8 을 켠 서명 빌드를 얹는다.

**Tech Stack:** Kotlin, Views + ViewBinding + Material3, Firebase Firestore, R8, Android adaptive icon.

## Global Constraints

- AGP 9.2.1 / Gradle 9.4.1 / compileSdk 37 / minSdk 26 / targetSdk 36. Compose 안 씀.
- 빌드: `export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"` 후 `cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug :app:testDebugUnitTest`
- **새 의존성 금지.**
- 주석은 한국어로 **왜** 를 적는다. 집필 기준은 `core/AuthGateway.kt`.
- 문구는 전부 `strings.xml`, 한국어.
- 커밋 한국어, author `Yongminlee2 <dydals5678@gmail.com>`, **도구·AI 흔적 금지**.
- `CancellationException` 은 어떤 일반 catch 보다 **먼저** 다시 던진다.
- **서명 키와 비밀번호는 절대 커밋하지 않는다.** `local.properties`(이미 gitignore)와 `*.jks` 를 쓴다.
- 색은 `@color` 이름만, 캐릭터는 `mascot_*` 고정색.

## 이 단계에서 다루지 않는 것

- 플레이스토어 등록·정책 심사·개인정보처리방침. 사이드로드 전제다(설계서 §1).
- 무료 한도 초과(현재 1.8~2.1배). 사용자가 혼자 쓰는 동안 미루기로 정했다 — `docs/known-issues.md` 14번.
- WiFi 원격 제어. 일반 앱은 안드로이드 10부터 불가능하고, 기기 소유자(Device Owner) 등록은 아이 폰 초기화가 필요해 사용자 결정 대기 중이다.

---

### Task 1: 런처 아이콘

**Files:**
- Create: `app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`, `ic_launcher_round.xml`
- Create: `app/src/main/res/drawable/ic_launcher_foreground.xml`, `ic_launcher_monochrome.xml`
- Create: `app/src/main/res/values/ic_launcher_background.xml`
- Modify: `AndroidManifest.xml`

**Interfaces:**
- Consumes: `res/drawable/ic_mascot.xml`(새싹이), `values/colors.xml` 의 `mascot_*`
- Produces: `@mipmap/ic_launcher`

- [ ] **Step 1: 적응형 아이콘을 만든다**

지금 앱은 아이콘 선언이 아예 없어서 안드로이드 기본 로봇이 뜬다. 아이 폰 홈 화면에 로봇이 있으면 그게 뭔지 아무도 모른다.

새싹이를 그대로 쓰되 **적응형 아이콘 규격을 지킨다**: 108×108dp 캔버스에 안전 영역은 가운데 66dp 원. 바깥 18dp 는 기기 모양(원·둥근 사각·물방울)에 따라 잘리므로 새싹의 잎이 거기 걸리면 안 된다. `ic_mascot.xml` 을 그대로 넣으면 잎이 잘린다 — 얼굴과 잎을 **함께 66dp 안에** 다시 앉힌 별도 벡터를 만든다.

배경은 단색 `mascot_face` 가 아니라 `sky_soft` 같은 팔레트 색으로 둔다. 얼굴색과 배경이 같으면 실루엣이 사라진다.

`ic_launcher_monochrome` 도 같이 만든다(안드로이드 13+ 테마 아이콘). 단색이라 얼굴 안쪽 눈·볼이 다 뭉치므로 **윤곽과 새싹만 남긴 별도 경로**여야 한다.

- [ ] **Step 2: 눈으로 확인한다**

`ic_mascot` 을 그대로 축소해 넣고 "되겠지" 하고 넘어간 적이 있다 — 5단계에서 24dp 핀은 얼굴을 다시 앉혀야 살아났다. 여기서도 **실제 크기로 렌더해 확인할 것.** 48dp(런처), 그리고 원형·둥근사각 마스크 둘 다. 안전 영역 밖으로 넘어간 획이 하나라도 있으면 다시 앉힌다.

- [ ] **Step 3: 빌드하고 커밋한다**

```bash
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug
```

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "런처 아이콘: 새싹이

아이콘 선언이 없어 기본 로봇이 떴다. 아이 폰 홈에 로봇이 있으면 그게 뭔지
아무도 모른다. 적응형 규격의 안전 영역(가운데 66dp) 안으로 얼굴과 잎을
다시 앉혔다 — 그대로 축소하면 잎이 기기 모양에 잘린다."
```

---

### Task 2: 오프라인에서 무엇이 되고 무엇이 안 되는지 확인하고 화면을 맞춘다

**Files:**
- Modify: `core/FirestoreProvider` 또는 `KidCareApp.kt`(설정을 명시하는 자리)
- Modify: `guardian/MapTimelineFragment.kt`, `guardian/AlertFragment.kt`, `guardian/ControlFragment.kt`
- Modify: `child/ChildHomeActivity.kt`
- Modify: `res/values/strings.xml`, `docs/known-issues.md`

**Interfaces:**
- Consumes: 기존 저장소 전부
- Produces: 없음(동작 확인과 문구 수정)

- [ ] **Step 1: 먼저 읽어서 확인한다 — 새로 만들기 전에**

Firestore 안드로이드 SDK 는 **로컬 캐시와 쓰기 큐가 기본으로 켜져 있다.** 오프라인에서 한 쓰기는 큐에 쌓였다가 연결되면 올라가고, 읽기는 캐시에서 나온다. 지금 코드는 이 설정을 명시한 곳이 없다 — **기본값에 기대고 있다는 사실 자체를 코드에 적는다.** 다음 사람이 "오프라인 처리가 없네" 하고 중복 구현하는 것을 막는 것이 이 단계의 절반이다.

실제로 확인할 것(코드를 읽어 답을 적을 것, 추측 금지):
1. 자녀 폰이 오프라인일 때 `trails` 쓰기는 큐에 쌓이는가, 아니면 `await()` 이 걸려 코루틴이 멈추는가?
2. 이벤트 쓰기가 큐에 오래 남아 있다가 올라가면, Task 1 의 규칙이 요구하는 `at` 창(서버 시각 기준 과거 24시간)을 벗어나 **거부**되는가? 벗어난다면 그건 오프라인에서 생긴 도착 알림이 통째로 사라진다는 뜻이다. **이게 이 작업에서 제일 중요한 질문이다.**
3. 보호자가 오프라인에서 명령을 보내면 화면은 무엇을 말하는가? 큐에 쌓인 명령은 나중에 배달되는데, 그때 아이가 이미 다른 곳에 있으면 뒤늦은 명령이 실행된다.
4. `AlertService` 의 리스너는 오프라인에서 캐시본을 한 번 더 내보내는가? 그러면 이미 알린 이벤트로 알림이 다시 뜨는가? (Task 4 가 id 집합으로 막았다 — 확인할 것)

- [ ] **Step 2: 화면이 거짓말하지 않게 고친다**

찾은 것 중 화면이 잘못 말하는 자리를 고친다. 최소한 이건 확실하다: **오프라인에서 "보냈어요"는 거짓말이다.** 쓰기가 큐에 들어간 것이지 아이 폰에 간 것이 아니다.

`Firestore.addSnapshotListener` 의 `QuerySnapshot.metadata.isFromCache` / `hasPendingWrites` 로 캐시본과 서버본을 구분할 수 있다. 이걸 써서 "아직 안 갔어요" 를 말한다.

- [ ] **Step 3: 찾은 것을 문서에 적는다**

`docs/known-issues.md` 에 오프라인 동작을 절로 적는다. 특히 2번의 답이 "거부된다"면 그것은 **알려진 데이터 유실**이므로 숫자와 조건을 명시한다.

- [ ] **Step 4: 빌드하고 커밋한다**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "오프라인: 기본값에 기대고 있다는 사실을 코드에 적고 화면을 맞춘다

Firestore 는 캐시와 쓰기 큐가 원래 켜져 있어 새로 만들 것이 거의 없었다.
문제는 화면이었다 — 오프라인에서 '보냈어요'는 거짓말이다. 쓰기가 큐에
들어간 것이지 아이 폰에 간 것이 아니다."
```

---

### Task 3: 예외 화면

**Files:**
- Modify: `RouterActivity.kt`, `onboarding/PermissionActivity.kt`, `guardian/GuardianMainActivity.kt`, `child/ChildHomeActivity.kt`
- Modify: `core/ErrorText.kt`, `res/values/strings.xml`

**Interfaces:**
- Consumes: `core/RoleStore`, `core/AuthGateway`, `core/FamilyRepository`
- Produces: 없음

- [ ] **Step 1: 막다른 골목을 찾는다**

각 상황에서 화면이 무엇을 보여주고 **사용자가 무엇을 할 수 있는지** 코드로 확인한다. 나갈 길이 없는 자리가 이 작업이 고칠 대상이다.

1. 익명 로그인이 실패한 채로 앱을 켰다(비행기 모드 첫 실행).
2. 아이가 권한을 "다시 묻지 않음" 으로 거부했다 — 설정 앱으로 보내는 길이 있는가?
3. 부모가 가족을 지웠거나 멤버 문서가 사라졌다 — 아이 폰은 무엇을 말하는가?
4. 역할은 저장돼 있는데 `familyId` 가 없다(설치 중 끊김).
5. 보호자 폰에서 아이가 아직 한 번도 페어링을 안 했다.
6. 구글 플레이 서비스가 없거나 옛 버전이다(위치·지오펜스가 통째로 안 된다).

- [ ] **Step 2: 모든 막다른 골목에 나갈 길을 준다**

원칙 하나: **화면은 무엇이 잘못됐는지와 다음에 무엇을 누를지를 같이 말한다.** "오류가 발생했습니다" 만 있는 화면은 이 작업 뒤에 하나도 남으면 안 된다.

`역할 다시 고르기` 는 이미 두 페어링 화면에 있다. 같은 탈출구가 필요한 자리가 더 있는지 본다.

- [ ] **Step 3: 빌드하고 커밋한다**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "예외 화면: 막다른 골목마다 나갈 길을 둔다

'오류가 발생했습니다'만 있는 화면은 사용자를 가둔다. 무엇이 잘못됐는지와
다음에 무엇을 누를지를 같은 자리에서 말한다."
```

---

### Task 4: 릴리스 빌드

**Files:**
- Modify: `app/build.gradle.kts`
- Create: `app/proguard-rules.pro`
- Create: `app/src/main/res/raw/keep.xml` (필요할 때만)
- Modify: `docs/setup.md`, `.gitignore`

**Interfaces:**
- Consumes: 없음
- Produces: 서명된 `app-release.apk`

- [ ] **Step 1: 서명 설정을 붙인다**

키스토어는 **사용자가 직접 만든다** — 비밀번호를 계획서나 저장소에 적지 않는다. `docs/setup.md` 에 명령을 적어 둔다:

```bash
keytool -genkeypair -v -keystore kidcare-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias kidcare
```

`build.gradle.kts` 는 `local.properties` 에서 읽고, **값이 없으면 릴리스 빌드를 조용히 디버그 키로 서명하지 말고 실패시킨다.** 조용히 넘어가면 서명 키가 뭔지 모르는 APK 가 배포된다.

`.gitignore` 에 `*.jks`, `*.keystore` 를 넣는다.

- [ ] **Step 2: R8 을 켜고 잘려나간 것을 찾는다**

`isMinifyEnabled = true`, `isShrinkResources = true` 로 올린다. **여기가 이 단계에서 가장 위험한 자리다.**

이 저장소가 이미 겪은 함정: **`getIdentifier` 로만 부르는 리소스는 릴리스에서 잘린다.** 코드에서 이름으로만 참조되는 것들을 전부 찾아 확인한다 — 문자열 키, 드로어블 이름, raw 리소스. Firestore `toObject()` 가 쓰는 데이터 클래스는 **리플렉션으로 필드를 읽으므로 난독화되면 전부 null 이 된다.** `core/model/Documents.kt` 의 모든 클래스에 `-keep` 이 필요하다.

- [ ] **Step 3: 디버그와 릴리스를 나란히 놓고 비교한다**

빌드가 통과하는 것은 아무 증거도 아니다. 이 저장소의 `docs/known-issues.md` 와 메모리에 같은 교훈이 두 번 적혀 있다.

확인할 것:
- `aapt2 dump resources` 로 디버그·릴리스의 리소스 **개수**를 비교한다. 줄었으면 무엇이 줄었는지 이름으로 확인한다.
- 릴리스 APK 를 실제로 깔아 페어링 → 위치 확인 → 소리 변경까지 해 본다. `toObject()` 가 깨지면 화면이 전부 비어 보인다.

- [ ] **Step 4: 버전을 올린다**

`versionCode = 1` / `versionName = "0.1"` 을 지금 상태에 맞춘다. 1~5단계가 다 들어 있다.

- [ ] **Step 5: 빌드하고 커밋한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleRelease
```

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "릴리스 빌드: 서명·R8·리소스 축소

빌드가 통과하는 것은 증거가 아니다. Firestore toObject 는 리플렉션으로
필드를 읽어 난독화되면 전부 null 이 되고, 이름으로만 부르는 리소스는
조용히 잘린다 — 디버그와 릴리스의 리소스 개수를 나란히 비교했다."
```

---

### Task 5: 문서 정리와 최종 점검

**Files:**
- Modify: `README.md`, `docs/known-issues.md`, `docs/setup.md`, `docs/superpowers/specs/2026-08-06-kidcare-design.md`

- [ ] **Step 1: 문서가 지금 코드와 맞는지 본다**

이 저장소는 **코드와 반대되는 주석을 두 번 배포했다.** 설계서 §3 의 명령 목록, §4.6, `docs/setup.md` 의 색인·규칙 절차, `README.md` 의 단계 표를 지금 상태에 맞춘다.

특히 확인할 것: 무료 한도 숫자(1.8~2.1배 초과), 명령 타입 목록(`message`·`set_alarm`·`cancel_alarm` 은 5단계에서 실제로 만들어졌다), `points`·`segments` 가 `trails` 하나로 합쳐진 것, 탭 다섯 개.

- [ ] **Step 2: README 에 5·6단계를 적는다**

개발일지 형식은 이미 있다 — **무엇이 잘못됐고 어떻게 잡혔는지**를 중심으로 이어 쓴다. 5단계에서 실기기 없이 잡힌 것들(옛 `events` 규칙이 열려 있던 것, `dataSync` 6시간 제한, 부모가 장소를 만드는 순간 도착 알림이 뜨던 것)이 좋은 재료다.

- [ ] **Step 3: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "문서: 5·6단계 반영과 어긋난 서술 정리"
```

---

## Self-Review

**1. 스펙 커버리지**

| 설계서 항목 | 담당 Task |
|---|---|
| 7단계 "오프라인 처리" | Task 2 |
| 7단계 "예외 화면" | Task 3 |
| 7단계 "릴리스 APK 서명" | Task 4 |
| §1 앱 이름·아이콘 | Task 1 |
| §4.4 되돌린 사실을 events 에 남기고 하루 5회 넘으면 알림 | **여전히 안 만든다.** 5단계 계획이 미룬 이유(잠금 스위치와 얽힌 `RingerModeReceiver` 를 건드려야 한다)가 그대로다. 5단계 이벤트 배선이 실기기에서 확인된 뒤에 별도로 다룬다 — `docs/known-issues.md` 에 적을 것 |

**2. 플레이스홀더 점검** — Task 2·3 은 "무엇을 확인하고 무엇을 결정할지"를 적었고 코드를 받아쓰게 하지 않았다. 둘 다 **먼저 읽어서 사실을 확인하는 것이 작업의 절반**이고, 확인 전에 코드를 지정하면 없는 문제를 고치게 된다. Task 1·4 는 구체적인 파일·명령·검증 방법을 적었다.

**3. 타입 일관성** — 이 단계는 새 타입을 거의 만들지 않는다. Task 4 의 `-keep` 규칙이 `core/model/Documents.kt` 의 **모든** 데이터 클래스를 덮는지가 유일한 일관성 위험이다.

**4. 발견해서 반영한 것**

- 앱 아이콘이 **아예 없다**(기본 로봇). 매니페스트에 `android:icon` 선언 자체가 없다.
- 릴리스 빌드가 `isMinifyEnabled = false` 에 서명 설정도 없다 — 지금 `assembleRelease` 를 하면 서명 안 된 APK 가 나온다.
- Firestore 오프라인 설정을 명시한 코드가 한 줄도 없다. 기본값이 맞지만, **적혀 있지 않으면 다음 사람이 중복 구현한다.**
- 규칙의 `at` 창(과거 24시간)과 오프라인 쓰기 큐가 부딪힐 수 있다. 오래 오프라인이던 아이 폰의 도착 알림이 통째로 거부될 수 있다 — Task 2 Step 1 의 2번이 이걸 확인한다.
