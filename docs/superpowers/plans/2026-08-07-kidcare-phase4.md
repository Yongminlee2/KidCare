# KidCare 4단계 구현 계획 (원격 제어·폰찾기·시간대 예약)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 부모가 버튼을 누르면 아이 폰의 소리/진동이 몇 초 안에 바뀌고, 무음이어도 벨을 울려 폰을 찾을 수 있으며, "평일 09:00~15:00 진동" 같은 규칙이 자동으로 적용된다.

**Architecture:** 명령은 `commands/` 컬렉션에 부모가 쓰고, 자녀 폰의 상시 포그라운드 서비스에 붙은 Firestore 스냅샷 리스너가 1~3초 안에 받아 실행한 뒤 같은 문서의 `state`를 갱신한다. 전달 수단은 인터페이스 하나 뒤에 감춰 나중에 FCM으로 갈아끼울 수 있게 한다. 시간대 규칙 해석은 안드로이드에 의존하지 않는 순수 함수로 두고 JUnit으로 먼저 고정한다 — 자정을 넘는 규칙이 이 앱에서 버그가 가장 나기 쉬운 곳이다.

**Tech Stack:** Kotlin (AGP 9 내장), Views + ViewBinding + Material3, `BottomNavigationView`, Firebase Firestore, `AudioManager` / `NotificationManager`(DND) / `AlarmManager` / `Vibrator`, `java.time`, JUnit4

**설계서:** `docs/superpowers/specs/2026-08-06-kidcare-design.md` (§3 문서 구조·보안 규칙, §4.3 시간대 규칙, §4.4 되돌리기, §4.5 핸드폰 찾기)
**미해결 목록:** `docs/known-issues.md` (5번 commands 규칙 구멍, 6번 전달 계층 감싸기)
**직전 단계:** `docs/superpowers/plans/2026-08-07-kidcare-phase3.md`

## Global Constraints

- 프로젝트 루트 `C:\workAndroid\KidCare`. 브랜치를 나누지 않고 `main`에 직접 커밋한다.
- AGP `9.2.1` / Gradle `9.4.1` / compileSdk `37` / minSdk `26` / targetSdk `36`
- namespace·applicationId `com.kidcare.family`. 표시명 `우리아이 지킴이`.
- UI는 Views + ViewBinding + Material3. **Compose를 쓰지 않는다.**
- **`logic/` 패키지는 안드로이드 API를 import 하지 않는다.** `java.time`·`kotlin.math`는 허용. JVM 단위 테스트가 여기 걸린다.
- 사용자 대상 문자열은 전부 한국어이며 `res/values/strings.xml`에 둔다. 코드·XML에 하드코딩하지 않는다. 키 중복 금지.
- 주석은 한국어로 *왜* 그런지를 적는다. `core/AuthGateway.kt`·`logic/SegmentBuilder.kt` 문체를 따른다.
- 모든 시각은 UTC 밀리초로 저장하고, 표시할 때만 기기 시간대로 바꾼다.
- 코루틴에서 `CancellationException`은 반드시 다시 던진다. `runCatching`은 이걸 삼키므로 `onFailure` 안에서 다시 던진다. **이 저장소는 같은 버그를 일곱 번 고쳤다** — `onboarding/GuardianPairingActivity.kt`의 catch 순서가 표준이다.
- 사용자에게 보이는 실패 문구는 반드시 `core/ErrorText.errorMessage(context, throwable)`를 거친다. SDK 영문 원문을 그대로 노출하지 않는다(3단계 실기기 검증에서 잡힌 결함).
- 커밋 메시지는 한국어. 저자는 `Yongminlee2 <dydals5678@gmail.com>` 단독으로 두고, 공동 저자 트레일러를 넣지 않는다.
- 빌드 시 `export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"` 가 필요하다. 테스트 워커가 `ClassNotFoundException: GradleWorkerMain`으로 죽으면 `./gradlew.bat --stop` 후 재시도(`gradle.properties`의 `-Dfile.encoding=MS949`가 이미 대응). `GRADLE_USER_HOME` 우회나 `C:\workAndroid\gradle-user-ascii`는 쓰지 않는다 — 후자는 한글 홈으로 가는 정션이다.
- **현재 단위 테스트 49개.** 어느 작업이든 기존 49개를 깨뜨리면 안 된다.
- `adb`를 실행하지 않는다. 실기기 확인은 사람이 한다. 각 작업의 확인 절차는 보고서에 적는다.

## 이 단계에서 다루지 않는 것

- 장소 반경(지오펜스)·도착/이탈 알림·원격 알람시계·메시지 — 6단계.
- 재설치 후 재연결(`known-issues.md` 1번). 설계 판단이 필요해 계속 보류.
- Blaze·FCM 승격. 이 단계는 Firestore 스냅샷 리스너로 간다. 유실이 실측되면 그때 올린다(설계서 §2).

## 중간 완료 지점

Task 1~6 까지 끝나면 **즉시 제어와 폰찾기가 실제로 동작한다** — 그 시점에 한 번 폰에 올려 확인하고 넘어가는 것을 권한다. Task 7~10 이 예약을 얹는다.

## File Structure

```
firestore.rules                    commands/settings 규칙 추가, children 와일드카드 정밀화  Task 1
app/src/main/java/com/kidcare/family/
├─ logic/                          ★순수 코틀린. 안드로이드 import 금지
│  └─ ScheduleResolver.kt          규칙 해석: 자정 넘김·겹침·즉시변경 충돌       Task 7
├─ core/
│  ├─ model/Documents.kt           CommandDoc·ScheduleDoc·RingerSettingsDoc 추가  Task 2
│  ├─ CommandTransport.kt          전달 수단 인터페이스 (나중에 FCM 으로 교체)    Task 2
│  ├─ FirestoreCommandTransport.kt 스냅샷 리스너 구현체                          Task 2
│  ├─ CommandRepository.kt         발행·구독·상태 전이의 단일 창구                Task 2
│  └─ ScheduleRepository.kt        schedules/ 와 settings/ringer CRUD             Task 8
├─ child/
│  ├─ CommandHandler.kt            받은 명령을 컨트롤러로 분배                    Task 3
│  ├─ RingerController.kt          모드 변경·되돌리기 감시                        Task 4, 5
│  ├─ RingerStateStore.kt          즉시변경 override·잠금 스위치 로컬 보관        Task 4
│  ├─ FindPhoneController.kt       알람 스트림 벨·진동·5분 자동정지               Task 6
│  ├─ FindPhoneActivity.kt         "엄마가 찾고 있어요" 전체화면 + 중지           Task 6
│  ├─ ScheduleApplier.kt           AlarmManager 로 경계마다 깨워 적용             Task 8
│  └─ ScheduleAlarmReceiver.kt     알람 수신 + BOOT_COMPLETED/TIME_SET 재등록     Task 8
└─ guardian/
   ├─ GuardianMainActivity.kt      하단 탭 3개(지도·관리·예약)                    Task 9
   ├─ ControlFragment.kt           즉시 변경·폰찾기·명령 상태                     Task 9
   ├─ ScheduleFragment.kt          규칙 목록·추가·삭제·겹침 경고                  Task 10
   └─ ScheduleAdapter.kt           규칙 한 줄                                     Task 10

app/src/test/java/com/kidcare/family/logic/
└─ ScheduleResolverTest.kt         Task 7
```

**책임 경계:** `logic/`은 계산만, `core/`는 Firestore 접근만, `child/`·`guardian/`은 안드로이드 화면·서비스만. `child/`와 `guardian/`은 서로를 import 하지 않고 `core/`를 통해서만 대화한다.

---

### Task 1: 보안 규칙 — 보호자의 명령 쓰기를 열되 아이의 우회를 막는다

`known-issues.md` 5번. 지금 `match /children/{childUid}/{document=**}`는 그 아래 **모든** 문서의 쓰기를 아이 본인으로 제한한다. 4단계는 부모가 `commands/`에 써야 하므로 이대로면 아무 명령도 못 보낸다.

**단순히 규칙 하나를 더하는 것으로는 안 된다.** Firestore 규칙은 OR 로 평가되므로, 재귀 와일드카드를 그대로 두고 `commands` 규칙만 추가하면 **아이도 계속 `commands/`에 쓸 수 있다.** 그러면 아이가 자기 폰에 `set_ringer(normal)` 명령을 스스로 넣어 무음 예약을 무력화할 수 있다. 이 앱의 위협 모델에 아이가 들어 있다는 점을 잊지 말 것.

그래서 **재귀 와일드카드를 없애고 하위 컬렉션을 명시적으로 나열한다.**

**Files:**
- Modify: `firestore.rules`
- Modify: `docs/setup.md` (규칙 재게시 안내)
- Modify: `docs/known-issues.md` (5번 처리 표시)

**Interfaces:**
- Consumes: 기존 `memberOf(familyId)`, `roleIn(familyId)` 헬퍼
- Produces: `commands/`·`settings/` 접근 규칙 (Task 2~10 전부가 여기에 의존)

- [ ] **Step 1: `children` 블록을 다시 쓴다**

`firestore.rules`의 `match /children/{childUid}/{document=**}` 블록 전체를 아래로 교체한다. 위에 붙어 있는 "4단계에서 고쳐야 한다"는 주석도 함께 지운다(이제 고쳤으므로).

```
      // 재귀 와일드카드(/{document=**})를 쓰지 않고 하위 컬렉션을 하나씩 적는다.
      // 이유: 규칙은 OR 로 평가되므로 와일드카드를 남겨둔 채 commands 규칙만 더하면
      // 아이도 계속 commands 에 쓸 수 있다. 그러면 아이가 자기 폰에 set_ringer(normal)
      // 명령을 스스로 넣어 무음 예약을 무력화할 수 있다 — 이 앱의 위협 모델에는
      // 아이 본인이 들어 있다.
      match /children/{childUid} {
        // 이 문서 자체가 status(현재 위치·배터리·현재 모드)다. 아이만 쓴다.
        allow read: if memberOf(familyId);
        allow write: if memberOf(familyId) && request.auth.uid == childUid;

        match /points/{pointId} {
          allow read: if memberOf(familyId);
          allow write: if memberOf(familyId) && request.auth.uid == childUid;
        }

        match /segments/{segmentId} {
          allow read: if memberOf(familyId);
          allow write: if memberOf(familyId) && request.auth.uid == childUid;
        }

        // 명령은 방향이 반대다: 보호자가 만들고 아이가 실행 결과만 적는다.
        match /commands/{commandId} {
          allow read: if memberOf(familyId);
          // 만드는 것은 보호자만. 항상 pending 으로 시작해야 한다 — 아이를 거치지 않고
          // done 으로 위조된 명령이 화면에 "완료"로 보이는 것을 막는다.
          allow create: if memberOf(familyId)
                        && roleIn(familyId) == 'guardian'
                        && request.resource.data.state == 'pending';
          // 아이는 진행 상태만 갱신한다. type·payload 를 바꿀 수 없으므로
          // "받은 명령을 다른 명령으로 바꿔치기"가 불가능하다.
          allow update: if memberOf(familyId)
                        && request.auth.uid == childUid
                        && request.resource.data.diff(resource.data).affectedKeys()
                             .hasOnly(['state', 'deliveredAt', 'doneAt', 'error']);
          // 오래된 명령 정리는 보호자 몫.
          allow delete: if memberOf(familyId) && roleIn(familyId) == 'guardian';
        }
      }
```

그리고 `places`/`schedules` 블록 옆에 설정 컬렉션을 하나 더한다.

```
      // "아이가 되돌리면 다시 바꾸기" 같은 가족 단위 설정. 보호자가 정하고 아이는 읽는다.
      // families 문서에 필드를 더하지 않는 이유: 그 문서의 update 규칙은
      // hasOnly(['inviteCode','inviteExpiresAt','name']) 로 잠겨 있어 새 필드를 못 쓴다.
      match /settings/{settingId} {
        allow read: if memberOf(familyId);
        allow write: if memberOf(familyId) && roleIn(familyId) == 'guardian';
      }
```

- [ ] **Step 2: 스스로 공격해본다**

규칙 파일만 고치면 끝이 아니다. 아래를 규칙 텍스트에 대고 하나씩 따져 보고 **보고서에 트레이스를 적는다.**

1. 아이가 `commands/` 에 새 문서를 **create** 하려 한다 → 어떻게 막히는가?
2. 아이가 받은 명령의 `type` 을 `find_phone`에서 `locate_now`로 **update** 하려 한다 → 막히는가?
3. 보호자가 `state: "done"` 으로 명령을 만들려 한다 → 막히는가?
4. 아이가 `settings/ringer` 의 잠금 스위치를 끄려 한다 → 막히는가?
5. 3단계까지 동작하던 것이 안 깨지는가: 아이의 `points` 쓰기, `segments` 배치 교체(삭제+생성), 상태 문서 덮어쓰기, 보호자의 읽기 — 넷 다 여전히 허용되는가?
6. 다른 가족의 멤버가 이 가족의 `commands` 를 읽거나 쓸 수 있는가?

5번이 특히 중요하다. 재귀 와일드카드를 없앴으므로 **3단계 기능이 조용히 깨질 수 있다.**

- [ ] **Step 3: 문서를 갱신한다**

`docs/setup.md`의 규칙 게시 항목에 "규칙을 고치면 콘솔에 다시 붙여넣고 게시해야 반영된다"는 한 줄과, 반영 확인 방법(부모 폰에서 명령을 하나 보내보고 `adb logcat -s CommandRepository:*` 에 `PERMISSION_DENIED`가 없는지)을 적는다.

`docs/known-issues.md`의 5번을 "4단계에서 처리함"으로 표시하고, 재귀 와일드카드를 없앤 이유(아이의 self-command 우회)를 한 줄 남긴다. 항목을 지우지 말 것.

- [ ] **Step 4: 빌드는 영향 없지만 확인한다**

```bash
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug :app:testDebugUnitTest
```
49/49 그대로여야 한다(규칙 파일은 빌드에 안 들어간다).

- [ ] **Step 5: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "보안 규칙: 보호자의 명령 쓰기를 열고 아이의 자가 명령을 막는다

재귀 와일드카드를 없애고 points·segments·commands 를 하나씩 적었다. 와일드카드를
남긴 채 commands 규칙만 더하면 규칙이 OR 로 평가돼 아이도 계속 쓸 수 있고,
그러면 아이가 스스로 set_ringer(normal) 을 넣어 무음 예약을 무력화한다.
가족 단위 설정용 settings/ 도 보호자 전용 쓰기로 추가했다."
```

> **사용자 조치:** 이 커밋 후 `firestore.rules`를 Firebase 콘솔 `Firestore Database > 규칙`에 다시 붙여넣고 **게시**해야 반영된다. 안 하면 4단계 기능이 전부 `PERMISSION_DENIED`로 막힌다.

---

### Task 2: 명령 모델과 전달 계층

`known-issues.md` 6번. 지금은 Firestore 스냅샷 리스너로 명령을 전달하지만, 실사용에서 유실이 관측되면 FCM 또는 Cloudflare Workers 중계로 올릴 수 있어야 한다. 그러려면 **전달 수단을 인터페이스 하나 뒤에 감춰** 부르는 쪽 코드가 그대로여야 한다.

**Files:**
- Modify: `app/src/main/java/com/kidcare/family/core/model/Documents.kt`
- Create: `app/src/main/java/com/kidcare/family/core/CommandTransport.kt`
- Create: `app/src/main/java/com/kidcare/family/core/FirestoreCommandTransport.kt`
- Create: `app/src/main/java/com/kidcare/family/core/CommandRepository.kt`

**Interfaces:**
- Consumes: Task 1의 `commands/` 규칙
- Produces:
  - `data class CommandDoc(val id: String = "", val type: String = "", val payload: Map<String, String> = emptyMap(), val state: String = "", val createdAt: Long = 0L, val deliveredAt: Long = 0L, val doneAt: Long = 0L, val error: String = "")`
  - `object CommandType { const val SET_RINGER = "set_ringer"; const val FIND_PHONE = "find_phone"; const val STOP_FIND = "stop_find"; const val SYNC_RULES = "sync_rules" }`
  - `object CommandState { const val PENDING = "pending"; const val DELIVERED = "delivered"; const val DONE = "done"; const val FAILED = "failed" }`
  - `interface CommandTransport` — 아래 Step 2 참고
  - `object CommandRepository` — `suspend fun send(familyId, childUid, type, payload): String`, `fun observePending(familyId, childUid, onCommand, onError): ListenerRegistration`, `fun observeOne(familyId, childUid, commandId, onChange, onError): ListenerRegistration`, `suspend fun markDelivered/markDone/markFailed`

- [ ] **Step 1: 문서 모델을 추가한다**

`core/model/Documents.kt` 맨 아래에 붙인다. Firestore `toObject()`가 인자 없는 생성자를 요구하므로 모든 필드에 기본값을 준다.

```kotlin
/**
 * children/{childUid}/commands/{autoId} — 보호자가 쓰고 자녀가 실행한다.
 *
 * [id] 는 Firestore 문서 ID 라 문서 본문에는 없다. 읽어올 때 채워 넣는다
 * (보호자 화면이 "이 명령"의 상태를 따라가려면 ID 가 필요하다).
 *
 * [payload] 를 Map<String,String> 으로 둔 이유: 명령 종류마다 필요한 값이 다른데
 * 타입마다 필드를 늘리면 Firestore 문서가 빈 필드 투성이가 된다. 값이 몇 개 안 되고
 * 전부 짧은 문자열이라 이 정도면 충분하다.
 *
 * 상태 전이는 pending -> delivered -> done|failed 한 방향뿐이다. 규칙이 자녀에게
 * state/deliveredAt/doneAt/error 만 갱신하도록 제한하므로 type·payload 는 불변이다.
 */
data class CommandDoc(
    val id: String = "",
    val type: String = "",
    val payload: Map<String, String> = emptyMap(),
    val state: String = "",
    val createdAt: Long = 0L,
    val deliveredAt: Long = 0L,
    val doneAt: Long = 0L,
    val error: String = "",
)

object CommandType {
    const val SET_RINGER = "set_ringer"
    const val FIND_PHONE = "find_phone"
    const val STOP_FIND = "stop_find"
    /** 예약 규칙이 바뀌었으니 다시 읽어 알람을 새로 걸라는 신호. */
    const val SYNC_RULES = "sync_rules"
}

object CommandState {
    const val PENDING = "pending"
    const val DELIVERED = "delivered"
    const val DONE = "done"
    const val FAILED = "failed"
}

/** families/{familyId}/schedules/{id} — 시간대별 모드 규칙. */
data class ScheduleDoc(
    val id: String = "",
    val days: List<Int> = emptyList(),      // 1(월)~7(일)
    val startMinute: Int = 0,               // 자정 기준 분 0~1439
    val endMinute: Int = 0,
    val mode: String = "normal",            // "normal" | "vibrate" | "silent"
    val enabled: Boolean = true,
    val priority: Int = 0,
)

/**
 * families/{familyId}/settings/ringer — 가족 단위 설정.
 *
 * families 문서에 넣지 않은 이유: 그 문서의 update 규칙이
 * hasOnly(['inviteCode','inviteExpiresAt','name']) 라 새 필드를 쓸 수 없다.
 */
data class RingerSettingsDoc(
    /** "아이가 되돌리면 다시 바꾸기" 스위치. */
    val lockEnabled: Boolean = false,
)
```

- [ ] **Step 2: 전달 계층 인터페이스를 쓴다**

`core/CommandTransport.kt`:

```kotlin
package com.kidcare.family.core

import com.google.firebase.firestore.ListenerRegistration
import com.kidcare.family.core.model.CommandDoc

/**
 * 명령이 부모 폰에서 아이 폰으로 건너가는 수단.
 *
 * 지금 구현체는 Firestore 스냅샷 리스너 하나뿐이다([FirestoreCommandTransport]).
 * 무료(Spark) 요금제로 가느라 Cloud Functions·FCM 을 안 쓰기로 했기 때문이다(설계서 §2).
 * 실사용에서 명령 유실이 관측되면 FCM 이나 Cloudflare Workers 중계로 올려야 하는데,
 * 그때 부르는 쪽 코드가 그대로이도록 이 인터페이스 하나로 감싼다 —
 * docs/known-issues.md 6번이 요구하는 제약이다.
 */
interface CommandTransport {

    /** 아직 실행되지 않은 명령을 실시간으로 받는다. 자녀 폰에서만 쓴다. */
    fun observePending(
        familyId: String,
        childUid: String,
        onCommand: (CommandDoc) -> Unit,
        onError: (Exception) -> Unit,
    ): ListenerRegistration

    /** 명령 하나의 상태 변화를 따라간다. 보호자 화면이 "전달 중… → 완료"를 보여줄 때 쓴다. */
    fun observeOne(
        familyId: String,
        childUid: String,
        commandId: String,
        onChange: (CommandDoc) -> Unit,
        onError: (Exception) -> Unit,
    ): ListenerRegistration

    /** 명령을 발행하고 문서 ID 를 돌려준다. 보호자 폰에서만 쓴다. */
    suspend fun send(
        familyId: String,
        childUid: String,
        type: String,
        payload: Map<String, String>,
    ): String

    /** 자녀 폰이 진행 상태를 적는다. */
    suspend fun markState(
        familyId: String,
        childUid: String,
        commandId: String,
        state: String,
        error: String = "",
    )
}
```

- [ ] **Step 3: Firestore 구현체를 쓴다**

`core/FirestoreCommandTransport.kt`:

```kotlin
package com.kidcare.family.core

import android.util.Log
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.Query
import com.kidcare.family.core.model.CommandDoc
import com.kidcare.family.core.model.CommandState
import kotlinx.coroutines.tasks.await

/**
 * 자녀 폰은 위치 수집 때문에 어차피 포그라운드 서비스가 상시 돌고 있다.
 * 그 서비스 안에 이 리스너를 얹으면 명령이 1~3초 안에 닿는다 — FCM 이 사주는
 * "잠든 앱 깨우기"가 여기서는 필요 없는 이유다(설계서 §2 Firebase 요금제).
 */
class FirestoreCommandTransport : CommandTransport {

    private val db: FirebaseFirestore get() = FirebaseFirestore.getInstance()

    private fun commands(familyId: String, childUid: String) =
        db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .collection("commands")

    private fun toDoc(id: String, data: Map<String, Any?>): CommandDoc {
        @Suppress("UNCHECKED_CAST")
        val payload = (data["payload"] as? Map<String, Any?>)
            ?.mapValues { it.value?.toString().orEmpty() } ?: emptyMap()
        return CommandDoc(
            id = id,
            type = data["type"] as? String ?: "",
            payload = payload,
            state = data["state"] as? String ?: "",
            createdAt = (data["createdAt"] as? Number)?.toLong() ?: 0L,
            deliveredAt = (data["deliveredAt"] as? Number)?.toLong() ?: 0L,
            doneAt = (data["doneAt"] as? Number)?.toLong() ?: 0L,
            error = data["error"] as? String ?: "",
        )
    }

    override fun observePending(
        familyId: String,
        childUid: String,
        onCommand: (CommandDoc) -> Unit,
        onError: (Exception) -> Unit,
    ): ListenerRegistration =
        commands(familyId, childUid)
            .whereEqualTo("state", CommandState.PENDING)
            .orderBy("createdAt", Query.Direction.ASCENDING)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    Log.w(TAG, "명령 구독 실패: familyId=$familyId", error)
                    onError(error)
                    return@addSnapshotListener
                }
                snapshot?.documents?.forEach { d ->
                    d.data?.let { onCommand(toDoc(d.id, it)) }
                }
            }

    override fun observeOne(
        familyId: String,
        childUid: String,
        commandId: String,
        onChange: (CommandDoc) -> Unit,
        onError: (Exception) -> Unit,
    ): ListenerRegistration =
        commands(familyId, childUid).document(commandId)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    Log.w(TAG, "명령 상태 구독 실패: commandId=$commandId", error)
                    onError(error)
                    return@addSnapshotListener
                }
                snapshot?.data?.let { onChange(toDoc(snapshot.id, it)) }
            }

    override suspend fun send(
        familyId: String,
        childUid: String,
        type: String,
        payload: Map<String, String>,
    ): String {
        val ref = commands(familyId, childUid).document()
        // state 는 반드시 pending 으로 시작해야 한다. 규칙이 그것만 허용한다 —
        // 아이를 거치지 않고 done 으로 위조된 명령이 "완료"로 보이는 것을 막는다.
        ref.set(
            mapOf(
                "type" to type,
                "payload" to payload,
                "state" to CommandState.PENDING,
                "createdAt" to System.currentTimeMillis(),
                "deliveredAt" to 0L,
                "doneAt" to 0L,
                "error" to "",
            )
        ).await()
        return ref.id
    }

    override suspend fun markState(
        familyId: String,
        childUid: String,
        commandId: String,
        state: String,
        error: String,
    ) {
        // 규칙이 자녀에게 이 네 키만 허용한다. 다른 키를 섞으면 통째로 거부된다.
        val update = mutableMapOf<String, Any>("state" to state, "error" to error)
        when (state) {
            CommandState.DELIVERED -> update["deliveredAt"] = System.currentTimeMillis()
            CommandState.DONE, CommandState.FAILED -> update["doneAt"] = System.currentTimeMillis()
        }
        commands(familyId, childUid).document(commandId).update(update).await()
    }

    private companion object {
        const val TAG = "CommandTransport"
    }
}
```

- [ ] **Step 4: 단일 창구를 만든다**

`core/CommandRepository.kt` — 화면과 서비스는 이걸 부르고 전달 수단은 모른다.

```kotlin
package com.kidcare.family.core

import com.google.firebase.firestore.ListenerRegistration
import com.kidcare.family.core.model.CommandDoc
import com.kidcare.family.core.model.CommandState

/**
 * 명령의 단일 창구. 부르는 쪽은 전달 수단을 모른다 — [transport] 를 갈아끼우면
 * FCM 이든 중계 서버든 그대로 돌아간다(docs/known-issues.md 6번).
 */
object CommandRepository {

    private var transport: CommandTransport = FirestoreCommandTransport()

    /** 전달 수단 교체 지점. 지금은 테스트/이관용으로만 쓴다. */
    fun useTransport(newTransport: CommandTransport) {
        transport = newTransport
    }

    suspend fun send(familyId: String, childUid: String, type: String,
                     payload: Map<String, String> = emptyMap()): String =
        transport.send(familyId, childUid, type, payload)

    fun observePending(familyId: String, childUid: String,
                       onCommand: (CommandDoc) -> Unit,
                       onError: (Exception) -> Unit): ListenerRegistration =
        transport.observePending(familyId, childUid, onCommand, onError)

    fun observeOne(familyId: String, childUid: String, commandId: String,
                   onChange: (CommandDoc) -> Unit,
                   onError: (Exception) -> Unit): ListenerRegistration =
        transport.observeOne(familyId, childUid, commandId, onChange, onError)

    suspend fun markDelivered(familyId: String, childUid: String, commandId: String) =
        transport.markState(familyId, childUid, commandId, CommandState.DELIVERED)

    suspend fun markDone(familyId: String, childUid: String, commandId: String) =
        transport.markState(familyId, childUid, commandId, CommandState.DONE)

    suspend fun markFailed(familyId: String, childUid: String, commandId: String, error: String) =
        transport.markState(familyId, childUid, commandId, CommandState.FAILED, error.take(200))
}
```

- [ ] **Step 5: 빌드하고 커밋한다**

```bash
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug :app:testDebugUnitTest
```
49/49 그대로.

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "명령 전달 계층: 인터페이스 뒤에 Firestore 리스너를 감춘다

부르는 쪽이 전달 수단을 모르게 해서, 나중에 FCM 이나 중계 서버로 올릴 때
화면·서비스 코드를 건드리지 않아도 되게 했다(known-issues 6번).
state 는 pending 으로만 만들 수 있고 자녀는 진행 상태만 갱신한다."
```

> **색인 주의:** `observePending`은 `whereEqualTo("state") + orderBy("createdAt")`이라 복합 색인이 필요하다. 없으면 `FAILED_PRECONDITION`이 나고 **생성 URL이 예외 메시지 안에 담겨 logcat 으로만 보인다.** 위 코드가 예외 객체를 그대로 `Log.w`에 넘기는 이유다. 확인 절차를 보고서에 적을 것.

---

### Task 3: 자녀 폰의 명령 수신 루프

받은 명령을 종류별로 분배하고 상태를 적는다. 실제 동작(소리·폰찾기)은 Task 4~6이 채우므로, 이 작업은 **배관만** 놓고 각 종류는 로그만 남긴다.

**Files:**
- Create: `app/src/main/java/com/kidcare/family/child/CommandHandler.kt`
- Modify: `app/src/main/java/com/kidcare/family/child/TrackingService.kt`

**Interfaces:**
- Consumes: `CommandRepository`(Task 2), `RoleStore`, `AuthGateway`
- Produces: `class CommandHandler(context: Context)` with `suspend fun handle(familyId: String, childUid: String, command: CommandDoc)`

- [ ] **Step 1: 분배기를 쓴다**

```kotlin
package com.kidcare.family.child

import android.content.Context
import android.util.Log
import com.kidcare.family.core.CommandRepository
import com.kidcare.family.core.model.CommandDoc
import com.kidcare.family.core.model.CommandType

/**
 * 받은 명령 하나를 실행하고 결과를 되돌려 적는다.
 *
 * 같은 명령을 두 번 실행하지 않도록 최근 처리한 ID 를 기억한다. Firestore 스냅샷은
 * 캐시분과 서버분이 잇달아 오거나 재연결 시 다시 흘러올 수 있어서, 이게 없으면
 * 폰찾기 벨이 두 번 울린다.
 */
class CommandHandler(private val context: Context) {

    private val handled = object : LinkedHashSet<String>() {
        override fun add(element: String): Boolean {
            val added = super.add(element)
            while (size > MAX_REMEMBERED) remove(first())
            return added
        }
    }

    suspend fun handle(familyId: String, childUid: String, command: CommandDoc) {
        if (!handled.add(command.id)) {
            Log.d(TAG, "이미 처리한 명령이라 건너뛴다: ${command.id}")
            return
        }
        runCatching { CommandRepository.markDelivered(familyId, childUid, command.id) }
            .onFailure { if (it is kotlinx.coroutines.CancellationException) throw it
                         else Log.w(TAG, "delivered 표시 실패", it) }

        try {
            when (command.type) {
                CommandType.SET_RINGER -> Log.i(TAG, "SET_RINGER 수신 (Task 4 에서 구현)")
                CommandType.FIND_PHONE -> Log.i(TAG, "FIND_PHONE 수신 (Task 6 에서 구현)")
                CommandType.STOP_FIND -> Log.i(TAG, "STOP_FIND 수신 (Task 6 에서 구현)")
                CommandType.SYNC_RULES -> Log.i(TAG, "SYNC_RULES 수신 (Task 8 에서 구현)")
                else -> {
                    Log.w(TAG, "모르는 명령 종류: ${command.type}")
                    CommandRepository.markFailed(familyId, childUid, command.id, "unknown type")
                    return
                }
            }
            CommandRepository.markDone(familyId, childUid, command.id)
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "명령 실행 실패: ${command.type}", e)
            runCatching { CommandRepository.markFailed(familyId, childUid, command.id, e.message.orEmpty()) }
                .onFailure { if (it is kotlinx.coroutines.CancellationException) throw it }
        }
    }

    private companion object {
        const val TAG = "CommandHandler"
        const val MAX_REMEMBERED = 100
    }
}
```

- [ ] **Step 2: 서비스에 리스너를 붙인다**

`TrackingService`에 필드와 구독을 더한다. **기존 구조를 재배치하지 말 것** — 필드 추가, `onStartCommand`에서 구독 시작, `onDestroy`에서 해제만 한다.

```kotlin
    private val commandHandler by lazy { CommandHandler(this) }
    private var commandListener: com.google.firebase.firestore.ListenerRegistration? = null
```

`onStartCommand`에서 `familyId`를 이미 읽는 자리 근처에 붙인다. 중복 구독을 막기 위해 기존 리스너를 먼저 해제한다.

```kotlin
        commandListener?.remove()
        commandListener = CommandRepository.observePending(
            familyId = familyId,
            childUid = childUid,
            onCommand = { cmd ->
                lifecycleScope.launch { commandHandler.handle(familyId, childUid, cmd) }
            },
            onError = { e -> Log.w(TAG, "명령 리스너 실패 — 명령이 안 올 수 있다", e) },
        )
```

`childUid`는 `AuthGateway.currentUid()`로 얻는다. null 이면 구독하지 않고 로그를 남긴다(로그인 전에는 구독할 수 없다).

`onDestroy`에 한 줄:

```kotlin
        commandListener?.remove()
        commandListener = null
```

- [ ] **Step 3: 빌드하고 확인 절차를 적는다**

```bash
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug :app:testDebugUnitTest
```

보고서에 사람이 할 확인 절차를 적는다: 부모 폰(또는 Firestore 콘솔)에서 `commands` 문서를 하나 만들고, 자녀 폰 logcat 에 `CommandHandler`가 찍히는지, 문서의 `state`가 `pending → delivered → done`으로 바뀌는지. 색인이 없으면 `FAILED_PRECONDITION` 과 생성 URL 이 logcat 에 나온다는 것도 함께.

- [ ] **Step 4: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "자녀 폰: 명령 수신 루프

위치 수집용으로 이미 도는 포그라운드 서비스에 스냅샷 리스너를 얹었다.
스냅샷이 캐시·서버로 두 번 오거나 재연결 시 다시 흐를 수 있어 처리한 명령 ID 를
기억한다 — 없으면 폰찾기 벨이 두 번 울린다."
```

---

### Task 4: 소리·진동 즉시 변경

부모가 누른 모드를 자녀 폰에 적용한다. 무음·진동으로 바꾸려면 **방해 금지 접근 권한**이 필요하므로 온보딩에 한 단계를 더한다.

**Files:**
- Create: `app/src/main/java/com/kidcare/family/child/RingerStateStore.kt`
- Create: `app/src/main/java/com/kidcare/family/child/RingerController.kt`
- Modify: `app/src/main/java/com/kidcare/family/child/CommandHandler.kt`
- Modify: `app/src/main/java/com/kidcare/family/child/StatusReporter.kt` (현재 모드 보고)
- Modify: `app/src/main/java/com/kidcare/family/onboarding/PermissionStep.kt`
- Modify: `app/src/main/java/com/kidcare/family/onboarding/PermissionActivity.kt`
- Modify: `app/src/main/AndroidManifest.xml`, `res/values/strings.xml`

**Interfaces:**
- Consumes: `CommandHandler`(Task 3), `CommandType.SET_RINGER`
- Produces:
  - `object RingerMode { const val NORMAL = "normal"; const val VIBRATE = "vibrate"; const val SILENT = "silent" }`
  - `class RingerStateStore(context)` — `var overrideMode: String?`, `var overrideUntil: Long`, `var lockEnabled: Boolean`
  - `class RingerController(context)` — `fun currentMode(): String`, `fun apply(mode: String): Boolean`, `fun hasDndAccess(): Boolean`
  - `PermissionStep.DND_ACCESS`

- [ ] **Step 1: 권한 단계를 더한다**

매니페스트에 한 줄:

```xml
    <uses-permission android:name="android.permission.ACCESS_NOTIFICATION_POLICY" />
```

`PermissionStep`에 항목을 더한다. **`BATTERY_UNRESTRICTED` 뒤, `ACTIVITY_RECOGNITION` 앞**에 놓는다 — 소리 제어는 이 앱의 핵심 기능이라 선택 사항인 활동 인식보다 먼저 물어야 한다.

```kotlin
    DND_ACCESS(R.string.perm_dnd_title, R.string.perm_dnd_reason) {
        override fun isGranted(context: Context): Boolean {
            // 무음·진동으로 바꾸는 것은 "방해 금지" 정책을 건드리는 일이라
            // 안드로이드가 별도 권한을 요구한다. 목록 화면에서 사람이 직접 켜야 하고
            // 런타임 대화상자로는 못 받는다.
            val nm = context.getSystemService(NotificationManager::class.java)
            return nm.isNotificationPolicyAccessGranted
        }
    },
```

`PermissionActivity.ask()`의 `when`에 분기를 더한다. **분기를 빠뜨리면 버튼이 아무 일도 안 하고 아이가 그 화면에서 영영 못 나간다** — Kotlin 은 statement 로 쓴 `when`의 누락을 경고하지 않는다.

```kotlin
            PermissionStep.DND_ACCESS ->
                startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
```

`strings.xml`:

```xml
    <string name="perm_dnd_title">소리 설정 바꾸기</string>
    <string name="perm_dnd_reason">부모님이 소리·진동을 바꿔줄 수 있게 하는 권한이에요. 목록에서 \'우리아이 지킴이\'를 찾아 켜주세요.</string>
```

- [ ] **Step 2: 로컬 상태 보관소를 쓴다**

`child/RingerStateStore.kt`:

```kotlin
package com.kidcare.family.child

import android.content.Context

object RingerMode {
    const val NORMAL = "normal"
    const val VIBRATE = "vibrate"
    const val SILENT = "silent"

    fun isValid(value: String) = value == NORMAL || value == VIBRATE || value == SILENT
}

/**
 * 즉시 변경과 잠금 스위치를 자녀 폰에 보관한다.
 *
 * Firestore 가 아니라 로컬에 두는 이유: 이 값을 실제로 강제하는 것은 자녀 폰뿐이고,
 * 서비스가 재시작돼도 살아남아야 하며, 네트워크가 끊긴 동안에도 판단이 가능해야 한다.
 * 보호자에게 보여줄 "지금 무슨 모드인가"는 status 문서의 ringerMode 로 따로 올린다.
 */
class RingerStateStore(context: Context) {

    private val prefs = context.getSharedPreferences("kidcare_ringer", Context.MODE_PRIVATE)

    /** 부모가 즉시 변경으로 지정한 모드. null 이면 예약 규칙이 정하는 대로 둔다. */
    var overrideMode: String?
        get() = prefs.getString(KEY_MODE, null)
        set(value) = prefs.edit().putString(KEY_MODE, value).apply()

    /**
     * 즉시 변경이 유효한 끝 시각(UTC 밀리초). 0 이면 해제 시각 없음 —
     * 적용 중인 예약 규칙이 하나도 없을 때다(설계서 §4.3).
     */
    var overrideUntil: Long
        get() = prefs.getLong(KEY_UNTIL, 0L)
        set(value) = prefs.edit().putLong(KEY_UNTIL, value).apply()

    /** "아이가 되돌리면 다시 바꾸기". */
    var lockEnabled: Boolean
        get() = prefs.getBoolean(KEY_LOCK, false)
        set(value) = prefs.edit().putBoolean(KEY_LOCK, value).apply()

    fun clearOverride() {
        overrideMode = null
        overrideUntil = 0L
    }

    private companion object {
        const val KEY_MODE = "override_mode"
        const val KEY_UNTIL = "override_until"
        const val KEY_LOCK = "lock_enabled"
    }
}
```

- [ ] **Step 3: 컨트롤러를 쓴다**

`child/RingerController.kt`:

```kotlin
package com.kidcare.family.child

import android.app.NotificationManager
import android.content.Context
import android.media.AudioManager
import android.util.Log

/**
 * 자녀 폰의 소리 모드를 바꾼다.
 *
 * 무음·진동으로 바꾸는 것은 방해 금지 정책을 건드리는 일이라 권한이 없으면
 * AudioManager 가 조용히 무시하거나 SecurityException 을 던진다. 권한이 없을 때는
 * 실패로 보고해야 부모 화면에 "아이 폰에서 권한을 켜야 해요"가 뜬다 —
 * 조용히 실패하면 부모는 눌렀는데 왜 안 바뀌는지 알 길이 없다.
 */
class RingerController(private val context: Context) {

    private val audio: AudioManager
        get() = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    fun hasDndAccess(): Boolean =
        context.getSystemService(NotificationManager::class.java).isNotificationPolicyAccessGranted

    fun currentMode(): String = when (audio.ringerMode) {
        AudioManager.RINGER_MODE_SILENT -> RingerMode.SILENT
        AudioManager.RINGER_MODE_VIBRATE -> RingerMode.VIBRATE
        else -> RingerMode.NORMAL
    }

    /** 성공하면 true. 권한이 없거나 모드 값이 이상하면 false. */
    fun apply(mode: String): Boolean {
        if (!RingerMode.isValid(mode)) {
            Log.w(TAG, "모르는 모드: $mode")
            return false
        }
        if (mode != RingerMode.NORMAL && !hasDndAccess()) {
            Log.w(TAG, "방해 금지 접근 권한이 없어 $mode 로 바꿀 수 없다")
            return false
        }
        val target = when (mode) {
            RingerMode.SILENT -> AudioManager.RINGER_MODE_SILENT
            RingerMode.VIBRATE -> AudioManager.RINGER_MODE_VIBRATE
            else -> AudioManager.RINGER_MODE_NORMAL
        }
        return try {
            audio.ringerMode = target
            Log.i(TAG, "소리 모드 변경: $mode")
            true
        } catch (e: SecurityException) {
            Log.w(TAG, "소리 모드 변경 거부됨", e)
            false
        }
    }

    private companion object {
        const val TAG = "RingerController"
    }
}
```

- [ ] **Step 4: 명령을 연결하고 현재 모드를 보고한다**

`CommandHandler`의 `SET_RINGER` 가지를 채운다. payload 키는 `mode`, 그리고 `until`(밀리초, 없으면 0).

```kotlin
                CommandType.SET_RINGER -> {
                    val mode = command.payload["mode"].orEmpty()
                    if (!ringer.apply(mode)) {
                        CommandRepository.markFailed(familyId, childUid, command.id, "ringer_denied")
                        return
                    }
                    // 즉시 변경은 다음 예약 경계까지만 유효하다(설계서 §4.3).
                    // 경계 계산은 Task 8 이 붙인다. 지금은 부모가 보낸 값을 그대로 쓴다.
                    state.overrideMode = mode
                    state.overrideUntil = command.payload["until"]?.toLongOrNull() ?: 0L
                }
```

`ringer`/`state`는 `CommandHandler`의 필드로 만든다:

```kotlin
    private val ringer = RingerController(context)
    private val state = RingerStateStore(context)
```

`StatusReporter.report(...)`에 `ringerMode` 인자를 더해 `ChildStatusDoc.ringerMode`를 실제 값으로 채운다(지금은 항상 `"normal"`이 저장되고 있다). `TrackingService`가 `RingerController(this).currentMode()`를 넘긴다.

- [ ] **Step 5: 빌드하고 커밋한다**

```bash
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug :app:testDebugUnitTest
```

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "소리·진동 즉시 변경과 방해금지 권한

권한이 없으면 조용히 무시되는 대신 실패로 보고한다 — 부모가 눌렀는데
왜 안 바뀌는지 모르는 상황을 막는다. 지금까지 항상 normal 로 저장되던
status.ringerMode 도 실제 값으로 채운다."
```

---

### Task 5: 되돌리기 (아이가 바꾸면 다시 바꾸기)

설계서 §4.4. 잠금 스위치가 켜져 있으면 아이가 모드를 바꿨을 때 되돌린다.

**Files:**
- Modify: `app/src/main/java/com/kidcare/family/child/RingerController.kt`
- Create: `app/src/main/java/com/kidcare/family/child/RingerModeReceiver.kt`
- Modify: `app/src/main/java/com/kidcare/family/child/TrackingService.kt`
- Modify: `app/src/main/AndroidManifest.xml`

**Interfaces:**
- Consumes: `RingerController`, `RingerStateStore`(Task 4)
- Produces: `RingerController.desiredMode(): String?` — 지금 강제돼야 할 모드. null 이면 강제하지 않음

- [ ] **Step 1: 강제 대상 모드를 계산하는 함수를 더한다**

`RingerController`에 붙인다. Task 8 이 예약 규칙을 얹기 전까지는 즉시 변경만 본다.

```kotlin
    /**
     * 지금 강제돼야 할 모드. null 이면 아무것도 강제하지 않는다.
     *
     * 즉시 변경은 [RingerStateStore.overrideUntil] 까지만 유효하다. 0 이면
     * 해제 시각이 없다는 뜻이라 계속 유효하다 — 적용 중인 예약 규칙이 하나도
     * 없을 때가 그렇다(설계서 §4.3). 예약 규칙은 Task 8 에서 여기에 합쳐진다.
     */
    fun desiredMode(state: RingerStateStore, nowMillis: Long = System.currentTimeMillis()): String? {
        val until = state.overrideUntil
        if (until != 0L && nowMillis >= until) {
            state.clearOverride()
            return null
        }
        return state.overrideMode
    }
```

- [ ] **Step 2: 변경 감시 리시버를 쓴다**

`child/RingerModeReceiver.kt`:

```kotlin
package com.kidcare.family.child

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * 아이가 소리 모드를 바꾸면 되돌린다.
 *
 * 3초를 기다렸다 되돌리는 이유(설계서 §4.4): 즉시 되돌리면 아이 눈에는 버튼이
 * 안 먹는 것처럼 보이고 폰이 고장난 줄 안다. 잠깐 바뀌었다가 돌아가면
 * "부모가 정해둔 것"이라는 게 전달된다.
 *
 * 서비스가 코드로 등록한다 — 매니페스트에 정적 등록하면 앱이 안 떠 있을 때도
 * 깨어나 되돌리려 들어 배터리만 먹는다.
 */
class RingerModeReceiver(
    private val controller: RingerController,
    private val state: RingerStateStore,
) : BroadcastReceiver() {

    private val handler = Handler(Looper.getMainLooper())
    private var pending: Runnable? = null

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != AudioManager.RINGER_MODE_CHANGED_ACTION) return
        if (!state.lockEnabled) return

        val desired = controller.desiredMode(state) ?: return
        if (controller.currentMode() == desired) return

        pending?.let { handler.removeCallbacks(it) }
        val task = Runnable {
            // 3초 사이에 상황이 바뀌었을 수 있으니 다시 확인한다.
            val stillDesired = controller.desiredMode(state) ?: return@Runnable
            if (controller.currentMode() == stillDesired) return@Runnable
            if (controller.apply(stillDesired)) {
                Log.i(TAG, "아이가 바꾼 모드를 $stillDesired 로 되돌렸다")
            }
        }
        pending = task
        handler.postDelayed(task, REVERT_DELAY_MILLIS)
    }

    fun cancelPending() {
        pending?.let { handler.removeCallbacks(it) }
        pending = null
    }

    private companion object {
        const val TAG = "RingerModeReceiver"
        const val REVERT_DELAY_MILLIS = 3000L
    }
}
```

- [ ] **Step 3: 서비스가 등록·해제한다**

`TrackingService`에 필드를 더하고 `onCreate`에서 등록, `onDestroy`에서 해제한다. API 33+ 에서 `registerReceiver`는 export 플래그를 요구하므로 `ContextCompat.registerReceiver(..., ContextCompat.RECEIVER_NOT_EXPORTED)`를 쓴다.

```kotlin
    private var ringerReceiver: RingerModeReceiver? = null
```

```kotlin
        val controller = RingerController(this)
        val ringerState = RingerStateStore(this)
        ringerReceiver = RingerModeReceiver(controller, ringerState).also {
            androidx.core.content.ContextCompat.registerReceiver(
                this, it,
                android.content.IntentFilter(android.media.AudioManager.RINGER_MODE_CHANGED_ACTION),
                androidx.core.content.ContextCompat.RECEIVER_NOT_EXPORTED,
            )
        }
```

`onDestroy`:

```kotlin
        ringerReceiver?.let { it.cancelPending(); unregisterReceiver(it) }
        ringerReceiver = null
```

- [ ] **Step 4: 무한 루프가 없는지 스스로 따져본다**

컨트롤러가 모드를 바꾸면 그 자체가 다시 `RINGER_MODE_CHANGED_ACTION`을 발생시킨다. 되돌린 뒤 다시 리시버가 돌면 이번엔 `currentMode() == desired` 라 조기 반환한다 — 이게 루프를 끊는 지점이다. **보고서에 이 흐름을 적고**, 아이가 3초 안에 두 번 바꾸는 경우도 함께 따져 볼 것(`removeCallbacks`로 앞의 예약을 취소한다).

- [ ] **Step 5: 빌드하고 커밋한다**

```bash
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug :app:testDebugUnitTest
```

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "되돌리기: 아이가 모드를 바꾸면 3초 뒤 되돌린다

즉시 되돌리면 버튼이 안 먹는 것처럼 보여 폰이 고장난 줄 안다.
컨트롤러가 되돌리며 발생시킨 브로드캐스트는 '이미 원하는 모드'라 조기 반환돼
루프가 끊긴다. 리시버는 서비스가 코드로 등록·해제한다."
```

---

### Task 6: 핸드폰 찾기

설계서 §4.5. 무음이어도 울려야 하고, 부모가 못 끄는 상황에서 계속 울리는 사고를 막아야 한다.

**Files:**
- Create: `app/src/main/java/com/kidcare/family/child/FindPhoneController.kt`
- Create: `app/src/main/java/com/kidcare/family/child/FindPhoneActivity.kt`
- Create: `app/src/main/res/layout/activity_find_phone.xml`
- Modify: `app/src/main/java/com/kidcare/family/child/CommandHandler.kt`
- Modify: `app/src/main/AndroidManifest.xml`, `res/values/strings.xml`

**Interfaces:**
- Consumes: `CommandHandler`(Task 3), `CommandType.FIND_PHONE` / `STOP_FIND`
- Produces: `object FindPhoneController` — `fun start(context: Context)`, `fun stop(context: Context)`, `val isRinging: Boolean`

- [ ] **Step 1: 컨트롤러를 쓴다**

`STREAM_ALARM`으로 재생하는 것이 핵심이다 — 벨소리 무음/진동과 **무관하게** 울린다.

```kotlin
package com.kidcare.family.child

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

/**
 * 폰찾기 벨. 알람 스트림으로 재생하므로 벨소리가 무음·진동이어도 울린다.
 *
 * 5분이 지나면 스스로 멈춘다(설계서 §4.5). 부모가 중지 명령을 못 보내는 상황
 * — 부모 폰 배터리가 나갔다든지 — 에서 아이 폰이 수업 시간 내내 울리는 사고를 막는다.
 *
 * 알람 볼륨을 최대로 올리기 전에 원래 값을 기억했다가 멈출 때 되돌린다.
 * 안 그러면 아이 폰의 알람 소리가 영구히 최대가 된다.
 */
object FindPhoneController {

    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var savedAlarmVolume: Int? = null
    private val handler = Handler(Looper.getMainLooper())
    private var autoStop: Runnable? = null

    val isRinging: Boolean get() = player != null

    fun start(context: Context) {
        if (isRinging) return

        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        savedAlarmVolume = audio.getStreamVolume(AudioManager.STREAM_ALARM)
        audio.setStreamVolume(
            AudioManager.STREAM_ALARM,
            audio.getStreamMaxVolume(AudioManager.STREAM_ALARM),
            0,
        )

        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        player = MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            setDataSource(context, uri)
            isLooping = true
            prepare()
            start()
        }

        vibrator = vibratorOf(context).also {
            it.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 600, 400), 0))
        }

        autoStop = Runnable {
            Log.i(TAG, "5분이 지나 폰찾기를 자동으로 멈춘다")
            stop(context)
        }.also { handler.postDelayed(it, AUTO_STOP_MILLIS) }

        Log.i(TAG, "폰찾기 시작")
    }

    fun stop(context: Context) {
        autoStop?.let { handler.removeCallbacks(it) }
        autoStop = null

        player?.runCatching { stop(); release() }
        player = null

        vibrator?.cancel()
        vibrator = null

        savedAlarmVolume?.let {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audio.setStreamVolume(AudioManager.STREAM_ALARM, it, 0)
        }
        savedAlarmVolume = null
        Log.i(TAG, "폰찾기 중지")
    }

    private fun vibratorOf(context: Context): Vibrator =
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }

    private const val TAG = "FindPhone"
    private const val AUTO_STOP_MILLIS = 5 * 60 * 1000L
}
```

- [ ] **Step 2: 전체화면과 알림을 만든다**

`FindPhoneActivity` — 잠금화면 위에 뜨고 중지 버튼 하나만 있다. API 27+ 는 `setShowWhenLocked`/`setTurnScreenOn`, 그 아래는 윈도우 플래그를 쓴다(minSdk 26).

레이아웃은 큰 문구 하나와 큰 버튼 하나면 된다. 문구는 `strings.xml`에:

```xml
    <string name="find_phone_title">엄마가 폰을 찾고 있어요</string>
    <string name="find_phone_stop">찾았어요 (소리 끄기)</string>
    <string name="find_phone_notification_title">엄마가 폰을 찾고 있어요</string>
    <string name="find_phone_notification_text">눌러서 소리를 끌 수 있어요</string>
```

매니페스트에 액티비티를 등록한다(`android:exported="false"`, `android:launchMode="singleTask"`, `android:excludeFromRecents="true"`).

**전체화면 알림 주의:** 안드로이드 14+ 에서 `USE_FULL_SCREEN_INTENT`는 통화·알람 앱이 아니면 자동 승인되지 않는다. 그래서 전체화면 표시는 **되면 좋은 것**으로 두고, 소리·진동은 그와 무관하게 서비스에서 울린다. 알림은 `IMPORTANCE_HIGH` 채널에 중지 액션을 달아 헤드업으로라도 뜨게 하고, `setFullScreenIntent`도 같이 건다. `NotificationManager.canUseFullScreenIntent()`(API 34+)로 가능 여부를 로그에 남겨 나중에 진단할 수 있게 한다.

- [ ] **Step 3: 명령을 연결한다**

`CommandHandler`의 두 가지를 채운다.

```kotlin
                CommandType.FIND_PHONE -> FindPhoneController.start(context)
                CommandType.STOP_FIND -> FindPhoneController.stop(context)
```

- [ ] **Step 4: 스스로 따져볼 것**

보고서에 답을 적는다.

1. 폰찾기 중에 서비스가 죽으면 벨은? (`MediaPlayer`는 프로세스와 함께 죽는다 — 그게 안전한 쪽인가?)
2. 알람 볼륨 복구가 안 되는 경로가 있는가? 프로세스가 강제 종료되면 저장해둔 값은 사라진다. 그 경우 아이 폰의 알람 볼륨이 최대로 남는데, 받아들일 만한가 아니면 대비가 필요한가?
3. `FIND_PHONE`이 두 번 오면? (`isRinging` 조기 반환으로 막히는지)
4. 방해 금지 권한이 없어도 알람 스트림은 울리는가?

- [ ] **Step 5: 빌드하고 커밋한다**

```bash
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug :app:testDebugUnitTest
```

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "핸드폰 찾기: 알람 스트림으로 울리고 5분 뒤 자동 정지

알람 스트림이라 벨소리가 무음·진동이어도 울린다. 볼륨을 최대로 올리기 전에
원래 값을 기억했다 되돌린다. 5분 자동 정지는 부모가 중지를 못 보내는 상황에서
아이 폰이 수업 내내 울리는 사고를 막는다."
```

---

### Task 7: 시간대 규칙 해석 (TDD)

설계서 §4.3. **이 앱에서 버그가 가장 나기 쉬운 곳**이라 순수 함수로 떼어내 먼저 테스트로 고정한다.

**Files:**
- Create: `app/src/main/java/com/kidcare/family/logic/ScheduleResolver.kt`
- Create: `app/src/test/java/com/kidcare/family/logic/ScheduleResolverTest.kt`

**Interfaces:**
- Consumes: 없음 (순수 로직)
- Produces:
  - `data class ScheduleRule(val id: String, val days: Set<Int>, val startMinute: Int, val endMinute: Int, val mode: String, val enabled: Boolean, val priority: Int)`
  - `data class Resolution(val mode: String?, val nextBoundaryMillis: Long?)`
  - `ScheduleResolver.resolveAt(rules: List<ScheduleRule>, atMillis: Long, zone: ZoneId): Resolution`
  - `ScheduleResolver.overlapsOf(rules: List<ScheduleRule>, candidate: ScheduleRule): List<ScheduleRule>`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```kotlin
package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId

class ScheduleResolverTest {

    private val seoul: ZoneId = ZoneId.of("Asia/Seoul")

    private fun at(y: Int, m: Int, d: Int, h: Int, min: Int): Long =
        LocalDateTime.of(y, m, d, h, min).atZone(seoul).toInstant().toEpochMilli()

    private fun rule(
        id: String = "r", days: Set<Int> = setOf(1, 2, 3, 4, 5),
        start: Int = 9 * 60, end: Int = 15 * 60,
        mode: String = "vibrate", enabled: Boolean = true, priority: Int = 0,
    ) = ScheduleRule(id, days, start, end, mode, enabled, priority)

    @Test
    fun `규칙이 없으면 강제하는 모드도 없다`() {
        val r = ScheduleResolver.resolveAt(emptyList(), at(2026, 8, 7, 10, 0), seoul)
        assertNull(r.mode)
        assertNull(r.nextBoundaryMillis)
    }

    @Test
    fun `꺼진 규칙은 무시한다`() {
        val rules = listOf(rule(enabled = false))
        assertNull(ScheduleResolver.resolveAt(rules, at(2026, 8, 7, 10, 0), seoul).mode)
    }

    @Test
    fun `평일 규칙이 금요일 낮에 적용된다`() {
        // 2026-08-07 은 금요일이다.
        val r = ScheduleResolver.resolveAt(listOf(rule()), at(2026, 8, 7, 10, 0), seoul)
        assertEquals("vibrate", r.mode)
    }

    @Test
    fun `평일 규칙이 토요일에는 적용되지 않는다`() {
        // 2026-08-08 은 토요일이다.
        assertNull(ScheduleResolver.resolveAt(listOf(rule()), at(2026, 8, 8, 10, 0), seoul).mode)
    }

    @Test
    fun `시작 시각 정각에 이미 적용된다`() {
        val r = ScheduleResolver.resolveAt(listOf(rule()), at(2026, 8, 7, 9, 0), seoul)
        assertEquals("vibrate", r.mode)
    }

    @Test
    fun `끝 시각 정각에는 이미 풀린다`() {
        // 09:00~15:00 은 15:00 을 포함하지 않는다. 안 그러면 15:00 에 시작하는
        // 다음 규칙과 한 순간 겹친다.
        assertNull(ScheduleResolver.resolveAt(listOf(rule()), at(2026, 8, 7, 15, 0), seoul).mode)
    }

    @Test
    fun `자정을 넘는 규칙이 밤에 적용된다`() {
        val night = rule(id = "n", days = setOf(1, 2, 3, 4, 5, 6, 7),
                         start = 22 * 60, end = 7 * 60, mode = "silent")
        assertEquals("silent",
            ScheduleResolver.resolveAt(listOf(night), at(2026, 8, 7, 23, 30), seoul).mode)
    }

    @Test
    fun `자정을 넘는 규칙이 새벽에도 적용된다`() {
        val night = rule(id = "n", days = setOf(1, 2, 3, 4, 5, 6, 7),
                         start = 22 * 60, end = 7 * 60, mode = "silent")
        assertEquals("silent",
            ScheduleResolver.resolveAt(listOf(night), at(2026, 8, 8, 3, 0), seoul).mode)
    }

    @Test
    fun `자정을 넘는 규칙의 요일은 시작 시각 기준이다`() {
        // "평일 22:00~07:00" 은 금요일 밤에 시작하므로 토요일 새벽까지 이어진다.
        // 2026-08-07(금) 23:00 시작 -> 2026-08-08(토) 03:00 까지 적용.
        val night = rule(id = "n", days = setOf(1, 2, 3, 4, 5),
                         start = 22 * 60, end = 7 * 60, mode = "silent")
        assertEquals("silent",
            ScheduleResolver.resolveAt(listOf(night), at(2026, 8, 8, 3, 0), seoul).mode)
        // 반대로 토요일 밤 23:00 은 토요일이 요일 집합에 없으므로 적용되지 않는다.
        assertNull(ScheduleResolver.resolveAt(listOf(night), at(2026, 8, 8, 23, 0), seoul).mode)
    }

    @Test
    fun `겹치면 우선순위가 큰 쪽이 이긴다`() {
        val a = rule(id = "a", mode = "vibrate", priority = 0)
        val b = rule(id = "b", mode = "silent", priority = 5)
        assertEquals("silent",
            ScheduleResolver.resolveAt(listOf(a, b), at(2026, 8, 7, 10, 0), seoul).mode)
    }

    @Test
    fun `우선순위가 같으면 나중에 시작한 규칙이 이긴다`() {
        val early = rule(id = "e", start = 9 * 60, end = 15 * 60, mode = "vibrate")
        val late = rule(id = "l", start = 10 * 60, end = 15 * 60, mode = "silent")
        assertEquals("silent",
            ScheduleResolver.resolveAt(listOf(early, late), at(2026, 8, 7, 11, 0), seoul).mode)
    }

    @Test
    fun `다음 경계 시각을 알려준다`() {
        val r = ScheduleResolver.resolveAt(listOf(rule()), at(2026, 8, 7, 10, 0), seoul)
        assertEquals(at(2026, 8, 7, 15, 0), r.nextBoundaryMillis)
    }

    @Test
    fun `적용 중이 아닐 때는 다음 시작 시각이 경계다`() {
        val r = ScheduleResolver.resolveAt(listOf(rule()), at(2026, 8, 7, 7, 0), seoul)
        assertNull(r.mode)
        assertEquals(at(2026, 8, 7, 9, 0), r.nextBoundaryMillis)
    }

    @Test
    fun `겹치는 규칙을 찾아준다`() {
        val existing = rule(id = "a", start = 9 * 60, end = 15 * 60)
        val candidate = rule(id = "b", start = 14 * 60, end = 18 * 60)
        val hits = ScheduleResolver.overlapsOf(listOf(existing), candidate)
        assertEquals(listOf("a"), hits.map { it.id })
    }

    @Test
    fun `자기 자신과는 겹친다고 하지 않는다`() {
        val a = rule(id = "a")
        assertTrue(ScheduleResolver.overlapsOf(listOf(a), a).isEmpty())
    }

    @Test
    fun `요일이 안 겹치면 시간이 겹쳐도 충돌이 아니다`() {
        val weekday = rule(id = "a", days = setOf(1, 2, 3, 4, 5))
        val weekend = rule(id = "b", days = setOf(6, 7))
        assertTrue(ScheduleResolver.overlapsOf(listOf(weekday), weekend).isEmpty())
    }
}
```

- [ ] **Step 2: 테스트를 돌려 실패를 확인한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:testDebugUnitTest --tests "*ScheduleResolverTest*"
```
기대: 컴파일 실패 — `Unresolved reference: ScheduleResolver`

- [ ] **Step 3: 구현한다**

구현 방침을 코드 주석으로 남길 것. 핵심은 **규칙 하나를 "구체적인 시각 구간"으로 펼친 뒤 비교**하는 것이다. 분 단위 비교로 자정 넘김을 다루려 하면 경계마다 특수 처리가 늘어난다.

- `atMillis`가 속한 날과 **그 전날**을 후보로 잡는다(자정 넘김 규칙은 전날 시작분이 오늘 새벽까지 이어진다).
- 각 후보 날에 대해, 그 날의 요일이 `days`에 있으면 `[시작, 끝)` 구간을 밀리초로 만든다. `endMinute <= startMinute`이면 끝은 다음 날로 넘긴다.
- 지금 시각을 포함하는 구간들 중 `priority` 큰 순, 같으면 시작 시각이 늦은 순으로 이긴다.
- `nextBoundaryMillis`는 지금 이후에 오는 모든 구간 경계(시작·끝) 중 가장 이른 것. 앞뒤 며칠치를 펼쳐 찾되, 없으면 null.

`overlapsOf`는 같은 방식으로 두 규칙의 구간을 한 주(7일) 펼쳐 비교하고, `id`가 같은 것은 제외한다.

- [ ] **Step 4: 테스트를 돌려 통과를 확인한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:testDebugUnitTest
```
기대: 전체 통과. 기존 49개 + 새 16개.

- [ ] **Step 5: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "시간대 규칙 해석: 자정 넘김·겹침·경계 계산

규칙을 분 단위로 비교하지 않고 구체적인 시각 구간으로 펼쳐서 비교한다 —
분 비교로 자정 넘김을 다루면 경계마다 특수 처리가 늘어난다.
요일은 시작 시각 기준이라 '평일 22:00~07:00' 이 토요일 새벽까지 이어진다.
단위 테스트 16개."
```

---

### Task 8: 예약 적용 (AlarmManager)

규칙을 실제로 적용한다. 경계마다 깨어나 모드를 바꾸고 다음 알람을 다시 건다.

**Files:**
- Create: `app/src/main/java/com/kidcare/family/core/ScheduleRepository.kt`
- Create: `app/src/main/java/com/kidcare/family/child/ScheduleApplier.kt`
- Create: `app/src/main/java/com/kidcare/family/child/ScheduleAlarmReceiver.kt`
- Modify: `app/src/main/java/com/kidcare/family/child/RingerController.kt` (`desiredMode`에 규칙 합치기)
- Modify: `app/src/main/java/com/kidcare/family/child/CommandHandler.kt` (`SYNC_RULES`)
- Modify: `app/src/main/java/com/kidcare/family/child/TrackingService.kt`, `AndroidManifest.xml`

**Interfaces:**
- Consumes: `ScheduleResolver`(Task 7), `RingerController`·`RingerStateStore`(Task 4)
- Produces:
  - `ScheduleRepository.observeSchedules(familyId, onChange: (List<ScheduleDoc>) -> Unit, onError): ListenerRegistration`
  - `ScheduleRepository.saveSchedule(familyId, doc: ScheduleDoc): String`, `deleteSchedule(familyId, id)`
  - `ScheduleRepository.observeRingerSettings(familyId, onChange: (RingerSettingsDoc) -> Unit, onError): ListenerRegistration`
  - `ScheduleRepository.saveRingerSettings(familyId, doc: RingerSettingsDoc)`
  - `class ScheduleApplier(context)` — `suspend fun refresh(familyId: String)`, `fun applyNow(rules: List<ScheduleRule>)`

- [ ] **Step 1: 저장소를 쓴다**

`core/ScheduleRepository.kt` — `schedules/`는 기존 규칙(보호자 쓰기·멤버 읽기)이 이미 덮고, `settings/`는 Task 1이 추가했다. **규칙 변경이 필요 없다.**

`ScheduleDoc`의 `id`는 문서 ID 라 본문에 없다. 읽을 때 채운다.

- [ ] **Step 2: 적용기를 쓴다**

`ScheduleApplier`가 하는 일:
1. `ScheduleRepository`로 규칙과 잠금 설정을 읽어 `RingerStateStore.lockEnabled`에 반영한다.
2. `ScheduleResolver.resolveAt(...)`으로 지금 강제할 모드와 다음 경계를 구한다.
3. 모드가 있으면 `RingerController.apply(...)`.
4. 다음 경계에 `AlarmManager.setExactAndAllowWhileIdle`로 `ScheduleAlarmReceiver`를 예약한다. 경계가 없으면(규칙이 하나도 없으면) 알람을 취소한다.

**정확한 알람 권한:** API 31+ 는 `SCHEDULE_EXACT_ALARM` 또는 `USE_EXACT_ALARM`이 필요하다. 이 앱은 사용자가 지정한 시각에 소리를 바꾸는 것이므로 `USE_EXACT_ALARM`이 용도에 맞고 별도 승인 없이 부여된다. 매니페스트에 선언하고, `AlarmManager.canScheduleExactAlarms()`가 false 인 경우에는 `setAndAllowWhileIdle`로 물러난 뒤 그 사실을 로그에 남긴다 — 조용히 부정확해지면 "예약이 가끔 안 먹는다"는 진단 불가능한 증상이 된다.

- [ ] **Step 3: `desiredMode`에 규칙을 합친다**

`RingerController.desiredMode`가 지금은 즉시 변경만 본다. 규칙을 인자로 받아 **즉시 변경이 살아 있으면 그것이, 아니면 규칙이** 이기도록 고친다. 설계서 §4.3의 "즉시 변경은 다음 규칙 경계까지만 유효" 규칙이 여기서 완성된다.

`SET_RINGER` 명령을 처리할 때 `overrideUntil`을 부모가 보낸 값이 아니라 **자녀 폰이 직접 계산한 다음 경계**로 채우도록 `CommandHandler`도 고친다. 부모 폰과 자녀 폰의 시계·시간대가 다를 수 있으므로 경계는 실제로 강제하는 쪽이 계산해야 한다.

- [ ] **Step 4: 재부팅·시각변경 대응**

`ScheduleAlarmReceiver`가 `BOOT_COMPLETED`와 `ACTION_TIME_CHANGED`, `ACTION_TIMEZONE_CHANGED`도 받아 전부 다시 걸도록 매니페스트에 인텐트 필터를 더한다. **재부팅하면 AlarmManager 의 예약은 전부 사라진다** — 이걸 빠뜨리면 폰을 껐다 켠 날부터 예약이 조용히 안 먹는다.

- [ ] **Step 5: 빌드하고 확인 절차를 적는다**

```bash
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug :app:testDebugUnitTest
```

보고서에 사람이 할 확인 절차를 적는다: 2~3분 뒤 시작하는 규칙을 만들어 실제로 모드가 바뀌는지, 폰을 재부팅한 뒤에도 다음 경계에 바뀌는지, `adb shell dumpsys alarm | grep kidcare`로 알람이 걸려 있는지.

- [ ] **Step 6: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "예약 적용: 경계마다 깨어나 모드를 바꾼다

재부팅·시각 변경 시 전부 다시 건다 — AlarmManager 예약은 재부팅으로 사라지므로
빠뜨리면 폰을 껐다 켠 날부터 예약이 조용히 안 먹는다.
즉시 변경의 해제 시각은 부모가 보낸 값이 아니라 자녀 폰이 계산한다 —
두 폰의 시계·시간대가 다를 수 있고 실제로 강제하는 쪽은 자녀 폰이다."
```

---

### Task 9: 보호자 하단 탭과 관리 화면

설계서 §3의 화면 구성. 탭이 둘 이상 생기는 지금이 하단 탭을 넣을 때다.

**Files:**
- Modify: `app/src/main/java/com/kidcare/family/guardian/GuardianMainActivity.kt`
- Modify: `app/src/main/res/layout/activity_guardian_main.xml`
- Create: `app/src/main/res/menu/guardian_bottom_nav.xml`
- Create: `app/src/main/java/com/kidcare/family/guardian/ControlFragment.kt`
- Create: `app/src/main/res/layout/fragment_control.xml`
- Modify: `res/values/strings.xml`

**Interfaces:**
- Consumes: `CommandRepository`(Task 2), `ScheduleRepository`(Task 8), `FamilyRepository.findChildUid`
- Produces: `ControlFragment`

- [ ] **Step 1: 하단 탭을 넣는다**

탭 3개: `지도`·`관리`·`예약`. (설계서의 `알림` 탭은 6단계에서 이벤트가 생길 때 넣는다 — 지금 넣으면 영원히 빈 탭이다.)

`MapTimelineFragment`의 기존 동작을 하나도 건드리지 말 것. 프래그먼트 교체 방식은 `replace` 대신 `show`/`hide`를 쓰거나, `replace`를 쓰더라도 지도 프래그먼트가 매번 재생성되며 타일을 다시 받지 않는지 확인할 것 — osmdroid 는 타일을 다시 내려받으므로 탭을 옮길 때마다 통신이 생긴다.

- [ ] **Step 2: 관리 화면을 만든다**

내용:
- 큰 버튼 3개: `벨소리` / `진동` / `무음` — 누르면 `CommandRepository.send(SET_RINGER, mapOf("mode" to ...))`
- 스위치: `아이가 되돌리면 다시 바꾸기` → `ScheduleRepository.saveRingerSettings(...)`
- 빨간 큰 버튼: `📢 핸드폰 찾기` → `send(FIND_PHONE)`. 울리는 동안에는 `소리 끄기`로 바뀌어 `send(STOP_FIND)`
- 명령 상태 표시: 보낸 뒤 `observeOne`으로 따라가며 `전달 중…` → `완료`. **60초 안에 `done`이 안 되면 "애기폰이 응답하지 않아요"** 로 바꾸고, 마지막 신호 시각(`ChildStatusDoc.lastSeenAt`)을 함께 보여준다(설계서 §5)

**모든 실패 문구는 `ErrorText.errorMessage(...)`를 거친다.** 리스너는 `onDestroyView`에서 전부 해제한다.

- [ ] **Step 3: 빌드하고 커밋한다**

```bash
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug :app:testDebugUnitTest
```

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "보호자: 하단 탭과 관리 화면

즉시 변경·되돌리기 스위치·핸드폰 찾기. 명령을 보낸 뒤 상태를 따라가
60초 무응답이면 '애기폰이 응답하지 않아요'로 정직하게 알린다."
```

---

### Task 10: 보호자 예약 화면

**Files:**
- Create: `app/src/main/java/com/kidcare/family/guardian/ScheduleFragment.kt`
- Create: `app/src/main/java/com/kidcare/family/guardian/ScheduleAdapter.kt`
- Create: `app/src/main/res/layout/fragment_schedule.xml`, `res/layout/item_schedule.xml`
- Modify: `GuardianMainActivity.kt`, `res/values/strings.xml`

**Interfaces:**
- Consumes: `ScheduleRepository`(Task 8), `ScheduleResolver.overlapsOf`(Task 7), `CommandRepository`(Task 2)
- Produces: `ScheduleFragment`

- [ ] **Step 1: 목록과 추가 화면을 만든다**

- 규칙 한 줄: `평일 09:00~15:00 진동` + 켬/끔 스위치 + 삭제
- 추가: 요일 토글 7개, 시작·끝 시각(`MaterialTimePicker`), 모드 3택
- **겹침 경고**: 저장 전에 `ScheduleResolver.overlapsOf(...)`를 돌려 겹치는 규칙이 있으면 `"이 시간대는 ○○ 규칙과 겹칩니다"`를 띄운다. 막지는 않는다 — 우선순위로 해결되므로(설계서 §4.3)
- `priority`는 만든 순서대로 자동 부여한다(나중에 만든 것이 큼). 화면에 노출하지 않는다

- [ ] **Step 2: 바뀌면 아이 폰에 알린다**

규칙을 저장·삭제·토글한 뒤 `CommandRepository.send(SYNC_RULES)`를 보낸다. 자녀 폰의 `CommandHandler`가 `ScheduleApplier.refresh(...)`를 불러 알람을 다시 건다.

> 자녀 폰이 `schedules/`를 직접 구독하게 하면 명령이 필요 없어 보이지만, 리스너를 하나 더 상시 유지하는 비용이 생긴다. 규칙 변경은 드문 일이라 명령 한 번이 싸다. 이 판단을 주석으로 남길 것.

- [ ] **Step 3: 빌드하고 커밋한다**

```bash
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug :app:testDebugUnitTest
```

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "보호자: 시간대 예약 화면

겹치는 규칙은 막지 않고 경고만 한다 — 우선순위로 해결되기 때문이다.
규칙이 바뀌면 sync_rules 명령으로 아이 폰이 알람을 다시 걸게 한다."
```

---

## Self-Review

**1. 스펙 커버리지**

| 스펙 항목 | 담당 Task |
|---|---|
| §3 commands 문서 구조·상태 전이 | Task 2 |
| §3 보안 규칙 (commands 구멍, known-issues 5) | Task 1 |
| known-issues 6 전달 계층 감싸기 | Task 2 |
| §4.4 되돌리기 (3초, 잠금 스위치) | Task 5 |
| §4.4 되돌린 사실을 events/ 에 남기고 하루 5회 넘으면 알림 | **6단계.** `events/`와 알림 화면이 그때 생긴다. 계획서 "다루지 않는 것"에 반영 |
| §4.5 핸드폰 찾기 (알람 스트림·볼륨 복구·5분 자동정지·전체화면·DND) | Task 4(권한), Task 6 |
| §4.3 시간대 규칙 (자정 넘김·요일 기준·우선순위·즉시변경 충돌) | Task 7, 8 |
| §4.3 AlarmManager·BOOT_COMPLETED·TIME_SET 재등록 | Task 8 |
| §3 하단 탭·관리 화면·예약 화면 | Task 9, 10 |
| §5 60초 무응답 시 "애기폰이 응답하지 않아요" | Task 9 |

**2. 플레이스홀더 점검** — Task 7 Step 3, Task 8, Task 9~10 은 구현 코드를 전부 적지 않고 **알고리즘 방침과 결정해야 할 것**을 적었다. 화면 코드는 기존 프래그먼트(`MapTimelineFragment`)의 패턴이 확립돼 있어 그대로 따르면 되고, 여기서 전부 받아쓰게 하면 계획서만 길어지고 실제 판단은 줄어든다. 다만 **각 작업이 무엇을 결정하고 무엇을 보고해야 하는지는 명시했다.** Task 1~6은 코드를 그대로 적었다 — 보안 규칙과 소리·알람 제어는 틀리면 조용히 실패하는 영역이라 받아쓰게 하는 편이 낫다.

**3. 타입 일관성**

- `CommandDoc`/`CommandType`/`CommandState`(Task 2) → Task 3·4·6·8·9·10 ✓
- `RingerMode`/`RingerStateStore`(Task 4) → Task 5·8 ✓
- `ScheduleRule`/`Resolution`(Task 7) → Task 8·10 ✓
- `ScheduleDoc`/`RingerSettingsDoc`(Task 2) → Task 8·9·10 ✓
- `RingerController.desiredMode(state, now)`(Task 5) 가 Task 8 에서 규칙 인자를 받도록 **확장**된다 — Task 8 Step 3에 명시 ✓

**4. 발견해서 반영한 것**

- 규칙에 `commands` 블록만 더하면 **아이가 자기 폰에 명령을 넣어 예약을 무력화**할 수 있다(규칙은 OR 평가). 재귀 와일드카드를 없애야 한다 — Task 1의 핵심.
- 잠금 스위치를 `families` 문서에 못 넣는다(그 문서 update 규칙이 `hasOnly` 로 세 필드만 허용). `settings/` 컬렉션이 필요하다 — Task 1·2에 반영.
- 즉시 변경의 해제 시각을 부모 폰이 계산해 보내면 두 폰의 시계·시간대 차이로 어긋난다. 자녀 폰이 계산해야 한다 — Task 8 Step 3.
- `observePending`은 복합 색인이 필요하다. 3단계에서 같은 함정을 겪었으므로 Task 2에 경고를 남겼다.
