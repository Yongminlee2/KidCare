# 개발 환경 메모

## 단위 테스트 실행법

이 PC의 사용자 홈이 `C:\Users\사용자` (한글)이라, 기본 상태로는 Gradle JVM 테스트
워커가 `ClassNotFoundException: GradleWorkerMain`으로 죽는다. `gradle.properties`에
이미 넣어둔 `-Dfile.encoding=MS949` 만으로 해결됐다 — 추가 조치(`GRADLE_USER_HOME`
변경 등)는 필요 없었다.

통한 명령 (JDK 21, Android Studio 내장 JBR):

```bash
cd /c/workAndroid/KidCare
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"
./gradlew.bat :app:assembleDebug :app:testDebugUnitTest
```

결과: `BUILD SUCCESSFUL` — 44 actionable tasks. `SmokeTest`(테스트명에 한글 포함)가
`app/build/test-results/testDebugUnitTest/TEST-com.kidcare.family.logic.SmokeTest.xml`에
`tests="1" failures="0" errors="0"`로 기록됨.

`./gradlew.bat --stop`으로 데몬을 내리고 `app/build`를 지운 뒤 처음부터 다시
돌려도 같은 결과가 재현됐다 — 옛 데몬 설정이 남아있어서 우연히 통과한 게 아니다.

### 시도했지만 필요 없었던 것
- `GRADLE_USER_HOME=C:/gradle-home` — MS949 인코딩만으로 충분했으므로 안 씀.
- `C:/workAndroid/gradle-user-ascii` — 이건 애초에 한글 홈으로 가는 정션이라
  효과가 없다는 걸 알고 있었으므로 시도하지 않음.

### JDK 경로
`org.gradle.java.home`은 프로젝트 `gradle.properties`에 넣지 않는다(기계마다
다르므로). 이 기계에서는 빌드 명령 앞에 `JAVA_HOME`을 지정해서 돌렸다:
`C:\Program Files\Android\Android Studio\jbr` (JDK 21).

## local.properties의 sdk.dir — 한글 사용자 홈 함정

`sdk.dir=C:\Users\사용자\...`처럼 원문 한글을 그대로 적으면(UTF-8 바이트로 저장되면)
AGP의 `SdkLocator`가 `local.properties`를 Java `Properties` 규격(ISO-8859-1)으로 읽다가
한글 바이트가 깨져 제어문자가 섞인 경로 문자열이 되고, 결국
`java.io.IOException: Invalid file path`로 `:app:compileDebugJavaWithJavac`의
의존성 계산 단계에서 빌드가 죽는다.

해결: `local.properties`의 한글 부분을 Java Properties의 `\uXXXX` 유니코드 이스케이프로
적는다 (Android Studio가 원래 생성하는 방식과 동일):

```properties
sdk.dir=C\:\\Users\\\uC0AC\uC6A9\uC790\\AppData\\Local\\Android\\Sdk
```

(`\uC0AC\uC6A9\uC790` = "사용자". 콜론과 백슬래시도 Properties 값 규칙대로 이스케이프.)

이 파일은 `.gitignore`에 있어 커밋되지 않는다 — 기계마다 새로 만들어야 한다.

## compileSdk 37로 올린 이유 (브리프의 36에서 편차)

브리프가 지정한 `androidx.core-ktx:1.19.0`은 `compileSdk 37` 이상을 요구한다
(`:app:checkDebugAarMetadata`가 명시적으로 이를 검사해 실패시킨다). 브리프의
`compileSdk = 36`과 `coreKtx = "1.19.0"`이 서로 맞지 않는 조합이었다.

이 기계에는 `android-37.0` 플랫폼이 이미 설치돼 있어서, 추가 다운로드 없이
`app/build.gradle.kts`의 `compileSdk`만 37로 올려서 해결했다. `targetSdk`는
브리프대로 36을 유지했다 — AGP 에러 메시지 자체가 compileSdk와 targetSdk를
독립적으로 올릴 수 있다고 안내한다.

### 새 기계에서 준비할 것: Android SDK Platform 37

`compileSdk = 37`은 **Android SDK Platform 37**이 로컬에 설치되어 있어야 빌드된다.
이 기계는 우연히 이미 설치돼 있어서 빌드가 바로 통과했지만, 새로 이 프로젝트를
받는 기계에는 없을 수 있다 — 그 경우 `compileSdk 37` 관련 리소스/플랫폼을 찾지
못한다는 불친절한 에러로 실패한다. 다음 중 하나로 미리 설치해 둔다:

- Android Studio의 SDK Manager에서 "Android 15 (API 37... 표기는 릴리스에 따라
  다름)" 플랫폼 체크박스 설치, 또는
- 커맨드라인: `sdkmanager "platforms;android-37"`

원인은 위에서 적은 대로 `core-ktx 1.19.0`이 `compileSdk 37`을 요구하기 때문이다.

## Firebase 설정

1. https://console.firebase.google.com 접속 → `프로젝트 만들기`
2. 프로젝트 이름 `KidCare` → Google 애널리틱스는 `사용 안 함` → 만들기
3. 프로젝트 개요 화면에서 안드로이드 아이콘 클릭
   - Android 패키지 이름: `com.kidcare.family`   ← 정확히 이대로
   - 앱 닉네임: 우리아이 지킴이
   - 디버그 서명 인증서 SHA-1: 지금은 비워둔다 (익명 로그인에는 불필요)
4. `google-services.json` 다운로드 → `C:\workAndroid\KidCare\app\google-services.json` 에 저장
5. 왼쪽 메뉴 `빌드 > Authentication` → `시작하기` → `Sign-in method` 탭
   → `익명` 선택 → `사용 설정` → 저장
6. 왼쪽 메뉴 `빌드 > Firestore Database` → `데이터베이스 만들기`
   - 위치: `asia-northeast3 (서울)`
   - 모드: `프로덕션 모드에서 시작`  (규칙은 Task 6 에서 넣는다)

**요금제는 Spark(무료) 그대로 두면 된다 — Blaze로 올리거나 카드를 등록할 필요가 없다.**
2026-08-07 설계 변경(설계서 §2 "Firebase 요금제", §9 결정 기록)으로 원격 명령 전달을
Cloud Functions + FCM 대신 Firestore 스냅샷 리스너로 바꿨다. 익명 인증 + Firestore만
쓰는 1~3단계는 전부 Spark 무료 한도 안에서 돈다. Blaze는 4단계 계획 시점에 실사용에서
명령 유실이 실제로 관측될 때만 다시 검토한다(그때도 카드 없는 대안인 Cloudflare Workers
무료 티어를 먼저 저울질한다).

이 프로젝트(`kidcare-17fe5`)는 위 절차로 이미 만들어졌고 `app/google-services.json`도
받아져 있다 (Task 3 작업 시작 시점 기준). 이 파일은 `.gitignore`에 있어 커밋되지
않으므로, 새 기계에서 이어받으면 위 절차를 다시 밟아 직접 받아야 한다.

## Firestore 보안 규칙 게시 (Task 6)

규칙 원본은 저장소의 `firestore.rules` 다. 콘솔에 붙여넣어 게시한다:

1. https://console.firebase.google.com → `kidcare-17fe5` 프로젝트 → 왼쪽 메뉴
   `빌드 > Firestore Database` → 상단 탭 `규칙`
2. 저장소의 `firestore.rules` 내용 전체를 복사해 편집기에 붙여넣기 (기존 내용을
   덮어쓴다 — 지금 콘솔에는 프로덕션 모드의 기본값, 즉 전부 막힌 규칙이 들어있다)
3. `게시` 클릭

이 작업은 Claude 가 대신 할 수 없다 — 콘솔 게시 버튼은 사람이 직접 눌러야 한다.
Task 6 작업 시점 기준으로 익명 인증은 이미 사용 설정돼 있고 Firestore 도
프로덕션 모드로 만들어져 있었지만, 규칙은 아직 게시 전이었다(임시로 열어둔 기본
규칙 상태). 이 규칙을 게시하기 전에는 페어링을 포함한 모든 Firestore 읽기/쓰기가
막혀 있거나(프로덕션 모드 기본값은 전면 거부) 반대로 완전히 열려 있을 수 있으니,
두 폰 확인(Step 4)은 반드시 게시 이후에 진행한다.

**주의 (4단계에서 반드시 먼저 처리할 것):** `firestore.rules` 의
`children/{childUid}/{document=**}` 규칙은 그 아래 전부를 아이 본인만 쓸 수 있게
막는다. 원격 명령(`commands/`)은 보호자가 써야 하는데, 이 프로젝트는 Cloud
Functions 없이 Spark 무료 요금제로 가기 위해 FCM 푸시 대신 **Firestore 스냅샷
리스너**로 명령을 전달하기로 했다 — 즉 보호자 쓰기가 막힌 채로는 즉시 변경·폰찾기
기능 자체가 동작하지 않는다. 4단계 계획에 `commands/` 전용 규칙 분리를 반드시
넣는다.

### fix round 1 (보안 리뷰) — `inviteCodes` 컬렉션 추가

Task 6 최초 버전은 `families`를 `inviteCode` 필드로 query(`whereEqualTo`)해서 코드를
찾았는데, Firestore 규칙은 `get`과 `list`를 구분하지 못해 이 조회를 열어두려면 결국
`families` 컬렉션 전체를 회원 아닌 사람도 `list`할 수 있게 열어야 했다 — 초대 코드가
전부 새어나가는 구멍이었다. 그리고 `members/{uid}` 의 `create` 규칙이 역할·코드를
전혀 검증하지 않아, 아무나 아무 가족의 `familyId`만 알면 자기를 그 가족의 `guardian`으로
등록할 수 있었다.

고친 구조: `inviteCodes/{code}` 컬렉션을 새로 두고 문서 ID 자체를 코드로 쓴다 —
`get`(정확한 ID 하나)만 허용하고 `list`는 규칙에서 아예 막는다. `families` 문서에는
`ownerUid`(생성자 uid)를, `members` 문서에는 `joinCode`(가입 시 사용한 코드)를
추가해, `members/{uid}`를 `create`할 때 규칙이 서버에서 "보호자 자리는 `ownerUid`
본인만, 자녀 자리는 살아있는 코드를 실제로 아는 사람만" 가져갈 수 있게 대조한다.
`core/model/Documents.kt`의 `FamilyDoc.ownerUid`, `MemberDoc.joinCode`,
`InviteCodeDoc`이 이 변경분이다. 이 프로젝트는 이 시점까지 규칙을 한 번도 게시하지
않았으므로(위 참고) 콘솔에 남아있는 기존 데이터·구버전 문서는 없다 — 마이그레이션
불필요.

### 복합 색인 만들기 (3단계 Fix 2 — 타임라인이 안 뜰 때)

`SegmentRepository.observeSegmentsOfDay`는 `dayKey`(같음 조건) + `startAt`(정렬)을
같이 쓰는 쿼리라서 Firestore 복합 색인이 필요하다. 규칙 게시와 마찬가지로 콘솔에서
사람이 직접 만들어야 하는 절차다. 색인이 없으면 첫 실행에서 이 리스너가
`FAILED_PRECONDITION`으로 죽는데, 그 오류 문구는 `statusBar`에 잠깐 떴다가
10분 안에 다음 status 스냅샷이 덮어써 사라진다 — 지도는 멀쩡하고 타임라인만
영원히 비어 보이는데 화면 어디에도 이유가 안 남는다.

가장 빠른 방법은 색인을 미리 만들지 않고, 앱을 한 번 그대로 돌려서 Firestore가
알려주는 생성 URL을 그대로 쓰는 것이다:

1. 페어링을 마치고 보호자 화면(지도+타임라인)을 한 번 연다.
2. PC에서 아래 명령으로 logcat을 보고 `FAILED_PRECONDITION` 줄을 찾는다 —
   `SegmentRepository.observeSegmentsOfDay`가 예외 객체를 그대로 `Log.w`에
   넘기므로 색인 생성 URL이 줄바꿈 없이 이 로그 줄에 전부 남는다.
   ```bash
   adb logcat -s SegmentRepository:W
   ```
3. 그 줄에 있는 `https://console.firebase.google.com/.../firestore/indexes?create_composite=...`
   URL을 브라우저로 열면, `dayKey` 오름차순 + `startAt` 오름차순 복합 색인 생성
   화면이 이미 채워져 있다. `만들기`만 누르면 된다(콘솔 버튼은 Task 6 규칙
   게시와 같은 이유로 사람이 직접 눌러야 한다 — Claude가 대신 할 수 없다).
4. 색인 상태가 `사용 설정됨`으로 바뀔 때까지(보통 몇 분) 기다린 뒤 앱을 다시
   열어 타임라인이 채워지는지 확인한다.

미리 손으로 만들고 싶으면 콘솔 `Firestore Database > 색인 > 복합 색인 추가`에서
컬렉션 `families/{familyId}/children/{childUid}/segments` 아래에 `dayKey`
오름차순 → `startAt` 오름차순 순서로 필드를 추가해도 된다.

**`SegmentRepository.pointsOfDay`(범위 쿼리 `at` + `orderBy("at")`)는 이 색인이
필요 없다** — 조건과 정렬이 같은 필드(`at`)라서 Firestore 자동 단일 필드 색인만
으로 충분하다(등호/정렬이 서로 다른 필드일 때만 복합 색인이 필요하다). 확인차
검토했고, 별도 조치는 없다.

## 자녀 권한 온보딩 기기 확인 (Task 7)

Task 7은 코드만 작성했고 실기기 확인은 사람이 직접 한다. 확인 절차:

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug && adb -s <아이폰시리얼> install -r app/build/outputs/apk/debug/app-debug.apk
```

1. `pm clear com.kidcare.family` 후 아이 역할로 페어링 → 권한 화면이 나온다
2. `위치 권한` → `켜기` → 시스템 창에서 `앱을 사용하는 동안만 허용` → 화면이
   `위치 '항상 허용'` 단계로 바뀐다
3. `켜기` → (안드로이드 11+ 는) 설정 앱이 열림 → 권한 > 위치 > `항상 허용` 선택
   → 뒤로 → 화면이 `알림` 단계로 바뀐다
4. 알림 허용 → `배터리 최적화 제외` 단계로 바뀜 → `켜기` → 배터리 최적화 제외
   목록 화면이 열림 → 목록에서 직접 `우리아이 지킴이`를 찾아 `제한 없음`으로 바꿈
   (화면에 이 안내 문구가 같이 뜬다)
5. 뒤로 오면 "위치 공유 중" 화면(`ChildHomeActivity`)이 뜬다
6. 앱을 껐다 켜면 (RouterActivity가 페어링 완료 상태를 보고) 바로 "위치 공유 중"
   화면으로 간다
7. 거부 경로 확인: 아무 단계에서나 시스템 다이얼로그가 뜨면 `거부`를 두 번
   누르거나 `다시 묻지 않음`을 체크 → 화면 문구가 "방금 거부돼서... 설정에서
   켜기"로 바뀌고 버튼도 `설정에서 켜기`로 바뀌는지 확인 → 눌러서 앱 설정 화면이
   열리는지, 거기서 권한을 켜고 돌아오면 다음 단계로 정상 진행되는지 확인

**삼성 기기라면** 위 표준 API 확인(4단계)과 별도로, `설정 > 배터리 > 백그라운드
사용 제한 > 절전 앱`에서도 `우리아이 지킴이`를 제외해야 한다. 삼성은 표준
`PowerManager.isIgnoringBatteryOptimizations`와 별개로 자체 절전 앱 목록을 두고
백그라운드에서 앱을 죽이는데, 이건 표준 API로는 확인도 해제도 안 되는
제조사 전용 기능이라 앱 코드로 감지·유도할 수 없다 — 사람이 수동으로 확인해야
한다.

## 지도 (osmdroid — 등록 절차 없음)

보호자 화면 지도는 osmdroid(OpenStreetMap) 를 쓴다. 카카오맵과 달리 앱키 발급이나
플랫폼 등록이 필요 없다 — `implementation(libs.osmdroid.android)` 의존성만으로
빌드하면 바로 동작한다. 원래는 카카오맵 SDK를 썼는데, 소유자가 카카오 네이티브
앱키를 발급받지 않아 지도가 한 번도 그려진 적이 없어서 osmdroid로 교체했다
(교체 근거는 `docs/superpowers/specs/2026-08-06-kidcare-design.md` §9 결정 기록,
세부 API 매핑 근거는 `.superpowers/map-swap-report.md` 참고). 카카오 쪽 코드는
`gradle/libs.versions.toml`의 `kakao-map` 별칭과 `settings.gradle.kts`의 카카오
Maven 저장소에 "카카오로 되돌릴 때 쓴다"라는 주석과 함께 주석 처리된 채로 남아있다
— 나중에 되돌리려면 그 두 곳의 주석을 풀고 `app/build.gradle.kts`에
`implementation(libs.kakao.map)`을 다시 추가하면 된다.

### 두 폰 확인 (Task 10, 1~2단계 최종 확인)

Task 10 코드 작업은 여기까지고, 실기기 확인은 사람이 직접 한다:

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug
adb -s <엄마폰시리얼> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <아이폰시리얼> install -r app/build/outputs/apk/debug/app-debug.apk
```

1. 두 폰 `pm clear com.kidcare.family` → 페어링 → 아이폰 권한 전부 켜기
2. 아이폰을 창가에 두고 1~2분 기다린다
3. 엄마폰에 OpenStreetMap 지도가 뜨고, 아이 위치에 파란 마커가 찍히는지 확인
   (등록 절차가 없으므로 첫 실행부터 바로 떠야 한다 — 안 뜨면 인터넷 연결부터 의심)
4. 위쪽 카드에 `🔋 78% · 15:42 기준` 같은 문구가 보이는지 확인
5. 아이폰을 들고 100m 이상 이동하면 엄마폰 마커가 앱을 만지지 않아도
   따라 움직이는지 확인
6. 엄마폰 앱을 껐다 켜도 마지막 위치가 그대로 보이는지 확인
7. 지도를 손가락으로 확대/축소·이동해보고, 이후 위치 갱신이 와도 부모가 옮긴
   시점이 유지되는지(마커가 처음 찍힐 때만 카메라가 움직여야 한다) 확인

## 카카오 REST API 키 (머무른 곳 이름 표시용)

네이티브 앱 키를 받은 그 화면(`앱 설정 > 앱 키`)에 **REST API 키**가 같이 있다.
같이 복사해서 `local.properties` 에 한 줄 더 넣는다:

```properties
KAKAO_REST_KEY=여기에_REST_API_키
```

없어도 앱은 정상 동작한다 — 머무른 곳이 이름 없이 "머무른 곳"으로만 표시될 뿐이다.
이 키는 좌표를 주소로 바꾸는 데만 쓴다(카카오 로컬 `coord2address`).
