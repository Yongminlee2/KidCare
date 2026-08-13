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

## 릴리스 서명 (6단계 Task 4)

### 지금 저장소에 붙어 있는 키는 **개발용**이다

`kidcare-dev.jks` 는 R8 을 실제로 검증하려고 이 기계에서 만든 키다. 비밀번호가
`kidcare-dev` 이고 그 사실이 이 문서에 적혀 있다 — 즉 **비밀이 아니다.**

- **다른 사람에게 APK 를 하나라도 주기 전에 진짜 키로 교체할 것.**
- **한 번 배포한 뒤에는 키를 절대 못 바꾼다.** 안드로이드는 서명이 다른 APK 를
  업데이트로 받지 않는다. 바꾸려면 받은 사람이 앱을 지우고 새로 깔아야 하는데,
  이 앱에서 그건 **페어링과 그동안의 기록이 통째로 날아간다**는 뜻이다
  (익명 로그인 uid 가 바뀐다 — `docs/known-issues.md` 1번).
- 그래서 진짜 키를 만드는 순간이 곧 "이 키를 10년 동안 잃어버리지 않겠다"를
  약속하는 순간이다. 키 파일과 비밀번호를 저장소 바깥에 따로 보관할 것.

### 키스토어 만들기

```bash
cd /c/workAndroid/KidCare
keytool -genkeypair -v -keystore kidcare-release.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias kidcare
```

`*.jks` 와 `*.keystore` 는 `.gitignore` 에 있어 커밋되지 않는다.

### 비밀번호는 local.properties 에 적는다

`local.properties` 도 `.gitignore` 에 있다. 네 줄이 필요하다.

```properties
releaseStoreFile=kidcare-release.jks
releaseStorePassword=...
releaseKeyAlias=kidcare
releaseKeyPassword=...
```

경로는 저장소 루트 기준이다. **네 줄 중 하나라도 없거나 파일이 그 자리에 없으면
`:app:packageRelease` 가 실패한다** — 디버그 키로 물러나지 않는다. 조용히 물러나면
누가 서명했는지 알 수 없는 APK 가 `build/outputs` 에 놓이고 빌드는 성공으로 끝난다.

### 빌드

```bash
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleRelease
```

결과: `app/build/outputs/apk/release/app-release.apk`.

### 릴리스 APK 는 디버그가 깔린 폰에 못 덮인다

서명이 다르면 `INSTALL_FAILED_UPDATE_INCOMPATIBLE` 이 난다. **지우고 깔면 페어링이
날아가므로**(위 참고) 두 폰을 릴리스로 옮기는 것은 페어링을 다시 할 각오가 섰을 때
한 번에 해야 하는 일이다. 그때까지 R8 빌드를 폰에서 확인하고 싶으면, 같은 APK 를
디버그 키로 다시 서명해서 깔면 코드·리소스는 그대로 두고 확인할 수 있다.

```bash
BT=/c/workAndroid/sdk-ascii/build-tools/36.0.0
cp app/build/outputs/apk/release/app-release.apk /tmp/r8-test.apk
"$BT/apksigner.bat" sign --ks ~/.android/debug.keystore --ks-pass pass:android \
  --key-pass pass:android --ks-key-alias androiddebugkey /tmp/r8-test.apk
adb -s <시리얼> install -r /tmp/r8-test.apk
```

이건 **확인용 사본**이지 배포물이 아니다. 배포물은 언제나 위 `assembleRelease` 가
낸 `app-release.apk` 다.

### R8 을 건드릴 때 반드시 다시 하는 확인

빌드가 통과하는 것은 아무 증거도 아니다. R8 이 이 앱에서 만드는 고장은 크래시가
아니라 **빈 화면**이다. 절차와 실제로 관측한 값은
`.superpowers/sdd/2026-08-08-kidcare-phase6/task-4-report.md` 에 있다. 요약하면 셋이다.

1. `aapt2 dump resources` 로 디버그·릴리스 리소스 개수를 비교하고, 줄어든 것의
   이름을 확인한다.
2. `app/build/outputs/mapping/release/mapping.txt` 에서
   `com.kidcare.family.core.model.*` 15개가 이름 그대로 남았는지 본다.
3. 릴리스 APK 를 실제 폰에 깔고 화면을 **눈으로** 본다.

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
Cloud Functions + FCM 대신 Firestore 스냅샷 리스너로 바꿨다. Blaze는 실사용에서
명령 유실이 실제로 관측될 때만 다시 검토한다(그때도 카드 없는 대안인 Cloudflare Workers
무료 티어를 먼저 저울질한다).

**"무료 한도 안에서 돈다"는 가족 하나 기준이다.** 예전 이 자리에는 "1~3단계는 전부
Spark 무료 한도 안에서 돈다"라고만 적혀 있었는데, 그 뒤로 실제로 세어 본 결과 옛
구조는 **가족 하나가 하루 1,100 쓰기**로 가족당 예산(20)의 55배였다. 지금은 36~42 로
줄었다. 혼자 쓰는 동안에는 프로젝트 한도(하루 2만 쓰기 / 5만 읽기)의 한참 아래라
아무 문제가 없고, **1,000가족을 담으려면 1.8~2.1배가 모자란다** — 계산과 줄이는
방법은 `docs/known-issues.md` 12·14번에 있다. 넘으면 경고가 아니라 **그날 나머지
시간 동안 Firestore 가 멈춘다**(위치 추적까지 함께).

이 프로젝트(`kidcare-17fe5`)는 위 절차로 이미 만들어졌고 `app/google-services.json`도
받아져 있다 (Task 3 작업 시작 시점 기준). 이 파일은 `.gitignore`에 있어 커밋되지
않으므로, 새 기계에서 이어받으면 위 절차를 다시 밟아 직접 받아야 한다.

## Firestore 보안 규칙·색인 게시

규칙과 색인의 원본은 저장소의 `firestore.rules`, `firestore.indexes.json`이다.
저장소 루트에서 아래 명령을 실행하면 둘을 함께 게시한다:

```bash
firebase login
firebase use kidcare-17fe5
firebase deploy --only firestore
```

Firebase CLI를 쓸 수 없으면 규칙은 콘솔에서 수동으로 게시할 수 있다:

1. https://console.firebase.google.com → `kidcare-17fe5` 프로젝트 → 왼쪽 메뉴
   `빌드 > Firestore Database` → 상단 탭 `규칙`
2. 저장소의 `firestore.rules` 내용 전체를 복사해 편집기에 붙여넣기 (기존 내용을
   덮어쓴다 — 지금 콘솔에는 프로덕션 모드의 기본값, 즉 전부 막힌 규칙이 들어있다)
3. `게시` 클릭

수동 게시를 선택했다면 `firestore.indexes.json`에 선언된 복합 색인 두 개도
`Firestore Database > 색인`에서 별도로 만들어야 한다. CLI 배포가 누락 위험이 가장
적다. 규칙을 게시하기 전에는 페어링을 포함한 Firestore 읽기·쓰기가 막혀 있거나,
오래된 규칙이 적용될 수 있으므로 두 폰 확인은 반드시 게시 이후에 진행한다.

**`firestore.rules` 또는 `firestore.indexes.json`을 고칠 때마다 다시 게시해야 한다.**
로컬 파일을 바꾸는 것만으로는 아무 효과가 없다. 반영됐는지 확인하는 방법: 보호자
폰에서 명령을 하나 보내보고(예: 벨소리 즉시 변경), 아이 폰을 붙인 PC에서
`adb logcat -s CommandRepository:*`를 띄워 `PERMISSION_DENIED`가 찍히지 않는지 본다.
찍히면 콘솔에 옛 규칙이 그대로 남아있다는 뜻이다 — 게시를 다시 확인한다.

**처리됨 (4단계 Task 1):** 예전에는 `firestore.rules`의
`children/{childUid}/{document=**}` 재귀 와일드카드가 그 아래 전부를 아이 본인만
쓸 수 있게 막아서, 원격 명령(`commands/`)에 보호자가 쓸 수 없었다. 이 프로젝트는
Cloud Functions 없이 Spark 무료 요금제로 가기 위해 FCM 푸시 대신 **Firestore
스냅샷 리스너**로 명령을 전달하기로 했으므로 보호자가 `commands/` 문서를 직접
써야만 즉시 변경·폰찾기 기능이 동작한다 — 4단계 Task 1에서 와일드카드를 없애고
`points`·`segments`·`commands`를 하위 컬렉션별로 나눠 보호자의 `commands`
쓰기를 열었다(`commands`는 보호자만 `create`, 아이는 진행 상태만 `update`).
자세한 이유는 `docs/known-issues.md` 5번 참고.

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

### 5단계 당시 기록 — `places`·`events` 규칙 재게시

5단계에서 `firestore.rules` 의 `places`·`events` 블록을 고쳤다. **콘솔에 다시
게시해야 한다.** 로컬 파일만 바꾼 것으로는 아무 효과가 없다(위 "매번 다시 게시").

아래 순서는 0.6 이전의 과거 배포 기록이다. **현재 0.7 N:N 배포에는 적용하지 않는다.**
당시에는 새 APK를 먼저 깔고 규칙을 뒤에 게시했다.

1. 두 폰에 새 APK 를 먼저 설치한다.

   ```bash
   cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug
   adb -s <엄마폰시리얼> install -r app/build/outputs/apk/debug/app-debug.apk
   adb -s <아이폰시리얼> install -r app/build/outputs/apk/debug/app-debug.apk
   ```

2. 그 다음 콘솔에서 규칙을 게시한다 — 절차는 위 1~3단계와 같다
   (`빌드 > Firestore Database` → 탭 `규칙` → `firestore.rules` 내용 **전체**
   붙여넣기 → `게시`).

**거꾸로 하면 안 되는 이유:** 콘솔에는 단계적 배포가 없다. `게시` 를 누르는
순간 새 규칙이 모든 폰에 한꺼번에 적용되는데, 폰에 깔린 APK 는 콘솔에서 못
바꾼다. 이번 변경처럼 **규칙을 조이는 방향**이면, 아직 옛 APK 가 깔린 폰은
새 규칙이 요구하는 모양으로 문서를 안 쓰므로 게시하는 순간부터 그 쓰기가
거부되기 시작한다. APK 를 먼저 깔아두면 게시 전까지 새 기능이 잠깐 안 될 뿐이고
게시하는 순간 정상이 된다 — 조이든 풀든 이 순서가 항상 안전하다.

**게시 전까지 무엇이 안 되는가 — 그리고 화면에는 안 보인다.**

- 부모: 장소 추가·수정·삭제가 저장되지 않는다.
- 아이: 장소를 못 읽어 지오펜스를 아예 걸지 못한다.
- 아이: 도착·이탈·배터리·권한 이벤트 쓰기가 거부된다.
- 부모: 알림 목록이 계속 비어 있고, 알림이 하나도 안 뜬다.

**넷 다 `PERMISSION_DENIED` 로 조용히 죽는다.** 부모 화면에는 "아무 일 없는
하루"와 똑같이 보인다 — 아이가 학교에 안 간 것인지 규칙을 안 게시한 것인지
화면만 봐서는 구분이 안 된다. 이 앱에서 제일 위험한 종류의 실패다. 확인은
아이 폰 로그로 한다:

```bash
adb -s <아이폰시리얼> logcat | grep PERMISSION_DENIED
```

한 줄도 안 나와야 정상이다. 나오면 콘솔에 옛 규칙이 남아있다는 뜻이니 게시를
다시 확인한다.

**게시했는데도 이벤트만 계속 거부된다면** 규칙이 아니라 문서 모양을 의심한다.
새 `events` create 규칙은 `childUid`(= 자기 uid), `read == false`, 그리고
`at`(**밀리초 정수**, 서버 시각 기준 과거 24시간 ~ 미래 1시간 안)을 셋 다
요구한다. 셋 중 하나라도 빠지거나 `at` 을 Firestore `Timestamp` 로 쓰면
비교가 성립하지 않아 **모든** 이벤트 쓰기가 거부된다. 아이 폰 시계가 하루
넘게 틀어져 있어도 같은 증상이 난다 — 그때는 폰 시간을 `자동 설정`으로 돌린다.

**같은 이유로 하루 넘게 오프라인이던 폰의 이벤트도 거부된다.** 시계가 아니라
큐가 원인일 뿐 증상은 똑같다. 이건 고장이 아니라 알려진 유실이고, 조건은
`docs/known-issues.md` 20번에 적혀 있다.

### 6단계 당시 기록 — 규칙을 안 바꿨다

2026-08-08의 6단계 당시에는 규칙이 바뀌지 않았다. 현재 0.7에서는 N:N 권한과
자녀별 경로가 추가됐으므로 이 문장을 현재 배포 지침으로 사용하면 안 된다.

### 0.7 N:N 전환 배포 순서

0.7의 새 규칙은 기존 0.6 자녀 초대 문서도 허용하도록 하위 호환된다. 따라서 이번에는
다음 순서가 안전하다.

1. `firebase deploy --only firestore`로 새 규칙과 두 복합 색인을 먼저 게시한다.
2. 기존 보호자 폰을 0.7로 갱신한다. 보호자 앱이 기존 가족 데이터를 선택한 자녀 아래로
   한 번만 복사하고 `schemaVersion = 2`로 올린다.
3. 기존 자녀 폰을 0.7로 갱신한다.
4. 보호자 화면의 자녀 선택 메뉴에서 추가 자녀 또는 보호자 초대 코드를 발급한다.
5. 지도·알림·관리·예약·장소 탭에서 선택한 자녀가 모두 동일한지 확인한다.

규칙을 먼저 게시하지 않고 0.7 APK부터 설치하면 자녀별 예약·장소·설정 쓰기가
`PERMISSION_DENIED`로 실패한다. 운영 규칙 게시 전에는 0.7을 실사용 폰에 설치하지 않는다.

### ~~복합 색인 만들기 (3단계 Fix 2 — 타임라인이 안 뜰 때)~~ — **이제 필요 없다**

**2026-08-08 대조 — `segments` 복합 색인(`dayKey` + `startAt`)은 더 이상 만들지
않는다.** 그 쿼리를 하던 `SegmentRepository` 자체가 없어졌다(무료 한도 개편,
`docs/known-issues.md` 12번). 하루치는 이제 `trails/{dayKey}` 문서 하나이고 문서 ID
가 곧 날짜라, 보호자 화면은 쿼리가 아니라 **문서 한 건을 ID 로 곧장 읽는다** —
쿼리가 없으니 색인도 없다.

옛 절차를 그대로 따라 콘솔에서 이 색인을 만들어도 아무 해는 없지만, 아무 효과도
없다(그 컬렉션을 읽는 코드가 없다). 현재 필요한 색인은 아래 `commands`와
자녀별 알림 조회용 `events` 두 개다.

당시 이 색인이 없어서 났던 사고는 기록으로 남긴다: 지도는 멀쩡한데 타임라인만
영원히 비어 보였고, 오류 문구는 상태줄에 잠깐 떴다가 다음 스냅샷이 덮어써 사라져
화면 어디에도 이유가 안 남았다. 예외 객체를 통째로 `Log.w` 에 넘겨 둔 덕에 색인
생성 URL 을 logcat 에서 건질 수 있었다 — **예외를 문자열로 줄여 적지 않는 규율이
그때 값을 했다.**

### 현재 필요한 복합 색인

`firestore.indexes.json`에 아래 두 색인이 선언돼 있으며 CLI 배포 시 함께 게시된다.

1. `commands`: `state` 오름차순 + `createdAt` 오름차순
2. `events`: `childUid` 오름차순 + `at` 내림차순

첫 번째가 없으면 원격 명령 리스너가 붙지 않고, 두 번째가 없으면 선택한 자녀의 알림
목록이 비어 보인다.

`FirestoreCommandTransport.observePending`은 `state`(같음 조건) + `createdAt`(정렬)을
같이 쓴다. 없으면 자녀 폰의 명령 리스너가 `FAILED_PRECONDITION`으로 붙지 못하고,
그 결과 **부모가 보내는 것이 전부 안 간다** — 소리·진동 즉시 변경, 핸드폰 찾기,
예약 재적용(`sync_rules`), 메시지, 원격 알람, 그리고 **'지금 위치 확인'까지**.
마지막 것은 무료 한도 개편 뒤로 부모가 위치를 갱신하는 **유일한** 통로라, 이 색인이
없으면 지도가 통째로 옛 위치에 멈춰 있는다.

무서운 건 증상이 조용하다는 것이다. 보내는 쪽(부모 폰)은 쓰기가 성공하므로
`전달 중…`에서 60초를 기다린 뒤 "애기폰이 응답하지 않아요"만 뜬다 — 애기폰이
꺼진 것과 색인이 없는 것이 화면에서 똑같이 보인다. 원인은 **자녀 폰** 로그에만
남는다:

```bash
adb logcat -s TrackingService:W
```

`명령 리스너 실패 — 명령이 안 올 수 있다` 줄에 색인 생성 URL이 통째로 들어 있다.
그 URL을 열고 `만들기`를 누른다.

**누른 뒤 바로 되지 않는다.** 몇 분 동안은 같은 자리에서 메시지만 바뀐다:

```
FAILED_PRECONDITION: The query requires an index.
    That index is currently building and cannot be used yet.
```

`색인이 없다`가 아니라 `만드는 중이다`로 바뀌었으면 제대로 만든 것이다. 상태가
`사용 설정됨`이 될 때까지 기다렸다가 자녀 폰 앱을 다시 켠다(리스너는 서비스가
시작될 때 붙으므로, 색인이 준비돼도 앱을 다시 켜기 전에는 안 붙는다).

손으로 만들려면 컬렉션 `families/{familyId}/children/{childUid}/commands` 아래에
`state` 오름차순 → `createdAt` 오름차순.

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

## 네이버 지도 등록

보호자의 경로 지도와 장소 지정 지도는 네이버 지도 Android SDK를 쓴다. 지도 키는
저장소에 올리지 않고 `.gitignore` 대상인 `local.properties`에서만 읽는다.

1. [네이버 클라우드 플랫폼 콘솔](https://console.ncloud.com/)에 로그인한다.
2. `Services > Application Services > Maps`에서 Application을 등록한다.
3. 사용할 API로 **Dynamic Map**(모바일 동적 지도)을 선택한다.
4. Android 앱을 추가하고 패키지 이름을 정확히 `com.kidcare.family`로 등록한다.
5. 발급 화면의 **NCP Key ID(Client ID)**를 복사한다. Client Secret은 Android 앱에
   넣지 않는다.
6. 프로젝트 루트의 `local.properties`에 다음 한 줄을 추가한다.

```properties
naverMapNcpKeyId=발급받은_Client_ID
```

패키지 이름이 다르면 인증 오류가 나고, Dynamic Map을 선택하지 않았으면 지도가
표시되지 않는다. `local.properties`가 없는 CI 환경에서도 디버그 컴파일과 단위
테스트는 가능하지만, 키가 없는 릴리스 APK 생성은 빈 지도 배포를 막기 위해 실패한다.

### 두 폰 확인 (Task 10, 1~2단계 최종 확인)

Task 10 코드 작업은 여기까지고, 실기기 확인은 사람이 직접 한다:

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug
adb -s <엄마폰시리얼> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <아이폰시리얼> install -r app/build/outputs/apk/debug/app-debug.apk
```

1. 두 폰 `pm clear com.kidcare.family` → 페어링 → 아이폰 권한 전부 켜기
2. 아이폰을 창가에 두고 1~2분 기다린다
3. 엄마폰에 네이버 지도가 뜨고, 아이 위치에 앱 마스코트 마커가 찍히는지 확인
   (안 뜨면 NCP Key ID, Dynamic Map 선택, Android 패키지 등록을 먼저 확인)
4. 위쪽 카드에 `🔋 78% · 15:42 기준` 같은 문구가 보이는지 확인
5. ~~아이폰을 들고 100m 이상 이동하면 엄마폰 마커가 앱을 만지지 않아도 따라
   움직이는지 확인~~ **2026-08-08 — 이제 그러면 안 된다.** 무료 한도 개편으로
   자녀 폰의 주기적 업로드가 없어졌으므로 마커는 **저절로 안 움직인다.**
   대신 이렇게 확인한다: 아이폰을 들고 이동한 뒤 엄마폰 지도 위쪽의
   **'지금 위치 확인'을 누르면** 몇 초 안에 마커가 새 위치로 옮겨가는지 본다.
   안 눌렀는데 따라 움직인다면 그게 오히려 고장이다(어딘가 옛 구독이 남아
   예산을 태우고 있다는 뜻).
6. 엄마폰 앱을 껐다 켜도 마지막 위치가 그대로 보이는지 확인
7. 지도를 손가락으로 확대/축소·이동해보고, 이후 위치 갱신이 와도 부모가 옮긴
   시점이 유지되는지(마커가 처음 찍힐 때만 카메라가 움직여야 한다) 확인

## 주소 조회 (머무른 곳 이름 표시용) — 키 등록 불필요

2026-08-07부터 OpenStreetMap Nominatim을 쓴다. 카카오 REST 키처럼 발급받아 넣을
것이 없다 — `PlaceNamer`가 등록 없이 바로 동작한다.
