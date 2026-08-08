# 5단계 구현 계획 — 장소 알림·메시지·원격 알람

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 부모가 정한 장소에 아이가 도착·이탈하면 부모 폰에 알림이 뜨고, 부모가 아이 폰에 메시지와 알람시계를 보낼 수 있게 한다.

**Architecture:** 장소 판정은 자녀 폰이 `GeofencingClient` 로 하고, 판정 로직(히스테리시스·중복 억제)은 안드로이드에 안 기대는 순수 코틀린 `logic/GeofenceEvaluator` 에 둔다. 이벤트는 `families/{fid}/events/{id}` 에 쌓이고, **부모 폰이 포그라운드 서비스로 그 컬렉션을 상시 구독**해 로컬 알림을 띄운다 — FCM 이 없으므로 이것 말고는 "저절로 뜨는 알림"을 만들 방법이 없다. 메시지와 알람시계는 이미 있는 `commands/` 통로를 그대로 쓴다.

**Tech Stack:** Kotlin, Views + ViewBinding + Material3, Firebase Firestore(익명 인증, Spark), play-services-location(GeofencingClient), AlarmManager, JUnit4.

## Global Constraints

- AGP 9.2.1 / Gradle 9.4.1 / compileSdk 37 / minSdk 26 / targetSdk 36. Compose 안 씀.
- 빌드: `export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"` 후 `cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug :app:testDebugUnitTest`
- **새 의존성 금지.** `play-services-location` 은 이미 있다(GeofencingClient 포함).
- 주석은 한국어로 **왜** 를 적는다. 집필 기준은 `core/AuthGateway.kt`.
- 사용자에게 보이는 문구는 전부 `strings.xml`. 부모가 한 번 읽고 알아야 한다.
- 커밋 메시지 한국어, author `Yongminlee2 <dydals5678@gmail.com>`, **도구·AI 흔적 금지**.
- `CancellationException` 은 어떤 일반 catch·`runCatching` 보다 **먼저** 다시 던진다. 이 저장소에서 같은 사고를 아홉 번 고쳤다.
- 프래그먼트는 `onDestroyView` 에서 리스너를 전부 해제하고 바인딩을 null 로 둔다. 늦게 오는 콜백은 바인딩 null 검사로 막는다.
- 실패 문구는 전부 `core/ErrorText.errorMessage(...)` 를 거친다. SDK 원문이 부모에게 보이면 안 된다.
- 색은 `@color` 이름만 쓴다. 캐릭터 색만 `mascot_*` 고정색이다(`values/colors.xml` 참고).
- **자녀가 곧 공격자다.** 아이는 폰과 API 키를 쥐고 있어 앱을 거치지 않고 Firestore 를 직접 두드릴 수 있다. 앱 코드의 검사는 약속이고, 강제하는 곳은 `firestore.rules` 뿐이다.

## 이 단계에서 다루지 않는 것

- 오프라인 버퍼·예외 화면·릴리스 서명 — 6단계.
- 자녀→보호자 자유 메시지. 이번엔 보호자→자녀 단방향 + 아이의 "확인했어요" 응답까지다. 아이가 문장을 쓰는 통로는 새 컬렉션과 새 규칙이 필요해 따로 다룬다.
- 무료 한도 총량. 사용자가 "당분간 혼자 쓴다"고 정했다(2026-08-08). 이벤트마다 쓰기가 하나씩 늘어나는 것은 알고 넘어가며, `docs/known-issues.md` 에 숫자로 남긴다.

---

### Task 1: 보안 규칙에 places·events 를 연다

**Files:**
- Modify: `firestore.rules`
- Modify: `docs/setup.md`

**Interfaces:**
- Produces: `places/{placeId}`(보호자 쓰기·멤버 읽기), `events/{eventId}`(자녀 생성·멤버 읽기·보호자 읽음표시)

- [ ] **Step 1: 규칙을 더한다**

`families/{familyId}` 블록 안, `schedules` 옆에 넣는다. **재귀 와일드카드를 만들지 말 것** — 규칙은 OR 로 평가되므로 와일드카드가 하나라도 살아 있으면 아이가 자기 폰에 명령을 넣어 예약을 무력화할 수 있다(4단계 Task 1 의 핵심).

```
      // 장소는 부모가 정한다. 아이는 읽기만 — 자기 폰의 지오펜스를 등록하려면
      // 좌표와 반경을 알아야 하기 때문이다. 쓰기를 열면 아이가 학교 반경을
      // 0 으로 만들어 도착 알림을 없앨 수 있다.
      match /places/{placeId} {
        allow read: if memberOf(familyId);
        allow write: if memberOf(familyId) && roleIn(familyId) == 'guardian';
      }

      // 이벤트는 방향이 반대다: 아이 폰이 만들고 부모가 읽는다.
      match /events/{eventId} {
        allow read: if memberOf(familyId);
        // 만드는 것은 아이만. childUid 를 자기 uid 로 적게 강제해 남의 이름으로
        // 사건을 지어내지 못하게 한다. read 는 항상 false 로 시작해야 한다 —
        // 아이가 만들면서 미리 읽음 표시를 해 두면 부모 화면에서 사라진다.
        allow create: if memberOf(familyId)
                      && request.resource.data.childUid == request.auth.uid
                      && request.resource.data.read == false;
        // 읽음 표시는 부모만, 그리고 read 필드 하나만. 막는 공격: 아이가 자기
        // 도착 기록의 placeName 이나 at 을 사후에 고치는 것.
        allow update: if memberOf(familyId)
                      && roleIn(familyId) == 'guardian'
                      && request.resource.data.diff(resource.data).affectedKeys()
                           .hasOnly(['read']);
        // 지우는 것도 부모만. 아이가 자기 이탈 기록을 지우면 알림의 뜻이 없다.
        allow delete: if memberOf(familyId) && roleIn(familyId) == 'guardian';
      }
```

- [ ] **Step 2: 게시 절차를 문서에 적는다**

`docs/setup.md` 의 규칙 절에 5단계 항목을 더한다. **APK 를 먼저 깔고 규칙을 뒤에 게시**해야 한다는 순서와, 게시 전에는 장소·알림이 `PERMISSION_DENIED` 로 조용히 죽는다는 것을 적는다.

- [ ] **Step 3: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "보안 규칙: 장소는 부모만 쓰고 이벤트는 아이만 만든다

아이 쓰기를 열면 학교 반경을 0 으로 만들어 도착 알림을 없앨 수 있고,
이벤트 수정을 열면 자기 이탈 기록을 지울 수 있다. 방향을 서로 반대로 둔다."
```

---

### Task 2: 장소 판정 로직 (TDD)

**Files:**
- Create: `app/src/main/java/com/kidcare/family/logic/GeofenceEvaluator.kt`
- Test: `app/src/test/java/com/kidcare/family/logic/GeofenceEvaluatorTest.kt`

**Interfaces:**
- Consumes: `logic/LocationFilter.distanceMeters(a, b)`, `logic/Fix`
- Produces: `Place(id, name, lat, lng, radiusMeters, notifyEnter, notifyExit)`, `PlaceState(placeId, inside, lastEventAt)`, `GeofenceHit(placeId, placeName, entering, at)`, `GeofenceEvaluator.evaluate(places, states, fix): Pair<List<GeofenceHit>, List<PlaceState>>`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```kotlin
package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GeofenceEvaluatorTest {

    private val school = Place("p1", "학교", 37.5000, 127.0000, 200.0, true, true)

    /** 반경 안의 좌표. 위도 1도는 약 111km 라 0.001도는 약 111m 다. */
    private fun near(at: Long, dLat: Double) =
        Fix(37.5000 + dLat, 127.0000, 10f, at)

    @Test
    fun `반경 안으로 들어오면 도착이다`() {
        val (hits, states) = GeofenceEvaluator.evaluate(
            listOf(school), emptyList(), near(1000L, 0.0),
        )
        assertEquals(1, hits.size)
        assertTrue(hits[0].entering)
        assertTrue(states[0].inside)
    }

    @Test
    fun `이미 안에 있으면 다시 도착하지 않는다`() {
        val inside = PlaceState("p1", inside = true, lastEventAt = 1000L)
        val (hits, _) = GeofenceEvaluator.evaluate(
            listOf(school), listOf(inside), near(999_000L, 0.0),
        )
        assertTrue(hits.isEmpty())
    }

    @Test
    fun `반경을 살짝 벗어난 것으로는 이탈이 아니다`() {
        // 반경 200m + 여유 50m = 250m 를 넘어야 이탈이다. 0.002도 = 약 222m.
        val inside = PlaceState("p1", inside = true, lastEventAt = 1000L)
        val (hits, states) = GeofenceEvaluator.evaluate(
            listOf(school), listOf(inside), near(999_000L, 0.002),
        )
        assertTrue(hits.isEmpty())
        assertTrue("아직 안에 있는 것으로 본다", states[0].inside)
    }

    @Test
    fun `여유까지 벗어나면 이탈이다`() {
        // 0.003도 = 약 333m > 250m
        val inside = PlaceState("p1", inside = true, lastEventAt = 1000L)
        val (hits, states) = GeofenceEvaluator.evaluate(
            listOf(school), listOf(inside), near(999_000L, 0.003),
        )
        assertEquals(1, hits.size)
        assertTrue(!hits[0].entering)
        assertTrue(!states[0].inside)
    }

    @Test
    fun `같은 장소의 같은 방향은 5분 안에 두 번 나오지 않는다`() {
        val justLeft = PlaceState("p1", inside = false, lastEventAt = 1_000_000L)
        // 1분 뒤 다시 들어옴 — 경계에 앉아 있는 상황
        val (hits, _) = GeofenceEvaluator.evaluate(
            listOf(school), listOf(justLeft), near(1_060_000L, 0.0),
        )
        assertTrue("5분이 안 지났으므로 알리지 않는다", hits.isEmpty())
    }

    @Test
    fun `5분이 지나면 다시 알린다`() {
        val justLeft = PlaceState("p1", inside = false, lastEventAt = 1_000_000L)
        val (hits, _) = GeofenceEvaluator.evaluate(
            listOf(school), listOf(justLeft), near(1_400_000L, 0.0),
        )
        assertEquals(1, hits.size)
    }

    @Test
    fun `알림을 끈 방향은 상태만 바뀌고 알리지 않는다`() {
        val quiet = school.copy(notifyEnter = false)
        val (hits, states) = GeofenceEvaluator.evaluate(
            listOf(quiet), emptyList(), near(1000L, 0.0),
        )
        assertTrue("알림은 없다", hits.isEmpty())
        assertTrue("그래도 안에 있다는 사실은 기억한다", states[0].inside)
    }

    @Test
    fun `오차가 큰 점은 판정에 쓰지 않는다`() {
        // 정확도 300m 짜리 점으로 반경 200m 장소의 도착을 판정할 수는 없다.
        val vague = Fix(37.5000, 127.0000, 300f, 1000L)
        val (hits, states) = GeofenceEvaluator.evaluate(listOf(school), emptyList(), vague)
        assertTrue(hits.isEmpty())
        assertTrue("상태도 건드리지 않는다", states.isEmpty())
    }

    @Test
    fun `장소가 없으면 아무 일도 없다`() {
        val (hits, states) = GeofenceEvaluator.evaluate(emptyList(), emptyList(), near(1000L, 0.0))
        assertTrue(hits.isEmpty())
        assertTrue(states.isEmpty())
    }

    @Test
    fun `지워진 장소의 상태는 따라서 사라진다`() {
        val stale = PlaceState("없어진장소", inside = true, lastEventAt = 1000L)
        val (_, states) = GeofenceEvaluator.evaluate(
            listOf(school), listOf(stale), near(999_000L, 0.0),
        )
        assertEquals(1, states.size)
        assertEquals("p1", states[0].placeId)
    }
}
```

- [ ] **Step 2: 실패를 확인한다**

```bash
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"
cd /c/workAndroid/KidCare && ./gradlew.bat :app:testDebugUnitTest --tests "*GeofenceEvaluatorTest*"
```

기대: 컴파일 실패(`GeofenceEvaluator` 없음).

- [ ] **Step 3: 최소 구현을 쓴다**

```kotlin
package com.kidcare.family.logic

/** 부모가 정한 장소 하나. 안드로이드에 안 기대는 값 객체다. */
data class Place(
    val id: String,
    val name: String,
    val lat: Double,
    val lng: Double,
    val radiusMeters: Double,
    val notifyEnter: Boolean = true,
    val notifyExit: Boolean = true,
)

/** 장소 하나에 대해 아이 폰이 기억하고 있는 것. */
data class PlaceState(
    val placeId: String,
    val inside: Boolean,
    val lastEventAt: Long,
)

/** 알릴 만한 일이 생겼다. */
data class GeofenceHit(
    val placeId: String,
    val placeName: String,
    val entering: Boolean,
    val at: Long,
)

/**
 * 위치 한 점으로 장소 도착·이탈을 판정한다.
 *
 * OS 의 GeofencingClient 를 쓰면서도 이 판정을 따로 두는 이유가 둘이다.
 * 하나, 삼성 기기는 절전 상태에서 지오펜스 전환을 몇 분씩 늦게 준다 — 이미 받고
 * 있는 위치 점으로 같은 판정을 한 번 더 하면 그 지연을 메운다. 둘, 히스테리시스와
 * 중복 억제는 안드로이드가 안 해 주는데 이게 없으면 경계에 앉은 아이 때문에
 * 부모 폰이 하루 종일 운다.
 */
object GeofenceEvaluator {

    /** 이탈로 인정하기 위해 반경에 더 얹는 여유(m). 경계에서 떨리는 것을 막는다. */
    const val EXIT_MARGIN_METERS: Double = 50.0

    /** 같은 장소·같은 방향을 다시 알리기까지 기다리는 시간. */
    const val DEDUPE_MILLIS: Long = 5 * 60 * 1000L

    /**
     * 이보다 오차가 크면 판정에 쓰지 않는다.
     *
     * 반경 200m 짜리 장소를 오차 300m 인 점으로 판정하면 도착·이탈이 아무 때나
     * 뒤집힌다. 못 믿는 점은 **상태도 건드리지 않는다** — 건드리면 다음 좋은 점이
     * 왔을 때 가짜 전환이 하나 만들어진다.
     */
    const val MAX_ACCURACY_METERS: Float = 100f

    fun evaluate(
        places: List<Place>,
        states: List<PlaceState>,
        fix: Fix,
    ): Pair<List<GeofenceHit>, List<PlaceState>> {
        if (fix.accuracy > MAX_ACCURACY_METERS) return emptyList<GeofenceHit>() to states
        if (places.isEmpty()) return emptyList<GeofenceHit>() to emptyList()

        val byId = states.associateBy { it.placeId }
        val hits = mutableListOf<GeofenceHit>()
        // 지금 있는 장소만 남긴다 — 부모가 지운 장소의 상태를 계속 들고 있으면
        // 그 장소를 다시 만들었을 때 옛 판정이 되살아난다.
        val next = places.map { place ->
            val was = byId[place.id]
            val distance = LocationFilter.distanceMeters(
                Fix(place.lat, place.lng, 0f, 0L), fix,
            )
            val nowInside = if (was?.inside == true) {
                // 안에 있던 아이는 반경 + 여유를 넘어야 나간 것으로 본다.
                distance <= place.radiusMeters + EXIT_MARGIN_METERS
            } else {
                distance <= place.radiusMeters
            }
            if (was == null) {
                // 처음 보는 장소. 안에 있으면 도착으로 친다 — 앱을 켠 순간 이미
                // 학교에 있는 경우가 흔하고, 그때 아무 말도 안 하면 부모는
                // 아이가 아직 안 갔다고 읽는다.
                if (nowInside && place.notifyEnter) {
                    hits += GeofenceHit(place.id, place.name, true, fix.at)
                }
                PlaceState(place.id, nowInside, if (nowInside) fix.at else 0L)
            } else if (nowInside == was.inside) {
                was
            } else {
                val quiet = fix.at - was.lastEventAt < DEDUPE_MILLIS
                val wanted = if (nowInside) place.notifyEnter else place.notifyExit
                if (!quiet && wanted) {
                    hits += GeofenceHit(place.id, place.name, nowInside, fix.at)
                }
                // 알리지 않기로 했어도 상태는 바꾼다. 안 바꾸면 5분 뒤에 같은
                // 전환이 다시 잡혀 "늦게 온 도착"이 뜬다.
                PlaceState(place.id, nowInside, if (quiet) was.lastEventAt else fix.at)
            }
        }
        return hits to next
    }
}
```

- [ ] **Step 4: 통과를 확인한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:testDebugUnitTest
```

기대: 전부 통과(기존 93개 + 새로 10개 = 103개).

- [ ] **Step 5: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "장소 판정 로직: 히스테리시스와 중복 억제

경계에 앉은 아이 때문에 부모 폰이 하루 종일 울지 않게 이탈은 반경에 50m 를
더 얹어 인정하고, 같은 장소의 같은 방향은 5분 안에 다시 알리지 않는다.
못 믿는 점(오차 100m 초과)은 상태도 건드리지 않는다 — 건드리면 다음
좋은 점에서 가짜 전환이 하나 만들어진다."
```

---

### Task 3: 장소 화면과 자녀 폰 판정 배선

**Files:**
- Create: `app/src/main/java/com/kidcare/family/core/PlaceRepository.kt`
- Create: `app/src/main/java/com/kidcare/family/child/PlaceWatcher.kt`
- Create: `app/src/main/java/com/kidcare/family/child/PlaceStateStore.kt`
- Create: `app/src/main/java/com/kidcare/family/guardian/PlaceFragment.kt`, `guardian/PlaceAdapter.kt`
- Create: `app/src/main/res/layout/fragment_place.xml`, `res/layout/item_place.xml`
- Modify: `core/model/Documents.kt`(`PlaceDoc`, `EventDoc`), `child/TrackingService.kt`, `guardian/GuardianMainActivity.kt`, `res/menu/guardian_bottom_nav.xml`, `res/values/strings.xml`

**Interfaces:**
- Consumes: `logic/GeofenceEvaluator`, `core/AuthGateway`, `core/RoleStore`, `core/ErrorText`
- Produces: `PlaceRepository.observePlaces/savePlace/deletePlace`, `PlaceWatcher.onFix(fix)`, `EventDoc`

- [ ] **Step 1: 문서 모델과 저장소를 만든다**

`PlaceDoc(id, name, lat, lng, radiusMeters, notifyEnter, notifyExit)` 과
`EventDoc(id, type, at, childUid, placeName, detail, read)` 를 `core/model/Documents.kt` 에 더한다.
**모든 필드에 기본값을 준다** — Firestore `toObject()` 가 인자 없는 생성자를 요구한다.

`PlaceRepository` 는 `ScheduleRepository` 와 같은 모양으로 쓴다. 자녀 폰은 장소가 자주 안 바뀌므로 **상시 구독 대신 `TrackingService` 시작 때와 `sync_rules` 명령 때 한 번씩 읽는다** — 예약 규칙과 같은 판단이다(4단계 Task 8 참고). 부모 화면은 편집 중이라 구독한다.

- [ ] **Step 2: 자녀 폰에 판정을 배선한다**

`PlaceWatcher` 가 `GeofenceEvaluator` 를 감싼다. `TrackingService` 가 위치 점을 받을 때마다 `onFix(fix)` 를 부르고, `GeofenceHit` 이 나오면 `events/` 에 문서를 만든다.

상태(`PlaceState` 목록)는 `PlaceStateStore`(SharedPreferences)에 넣는다. **메모리에만 두면 안 된다** — 아이가 앱을 강제 종료하거나 폰이 재부팅되면 "안에 있었다"는 사실이 사라져, 다음에 앱이 켜질 때 이미 학교에 있는데도 도착 알림이 한 번 더 뜬다. `FindPhoneStateStore` 가 같은 이유로 존재한다.

`GeofencingClient` 등록도 여기서 한다. 최대 20개로 자르고, `BOOT_COMPLETED` 뒤 다시 등록한다(OS 가 재부팅 때 지운다 — `child/BootReceiver.kt` 에 이어 붙인다).

- [ ] **Step 3: 부모 화면을 만든다**

하단 탭에 `장소` 를 넣는다(탭 4개: 지도·관리·예약·장소). 목록 한 줄은 `학교 · 반경 200m · 도착·이탈 알림`. 추가 화면은 이름, 반경(슬라이더 100~1000m), 도착/이탈 알림 스위치 둘, 그리고 좌표.

**좌표는 지도에서 찍게 한다.** 위경도를 숫자로 입력하게 하면 부모가 못 쓴다. `MapTimelineFragment` 가 이미 osmdroid 를 띄우므로 같은 방식으로 지도를 하나 더 띄우고 화면 중앙을 좌표로 삼는다(가운데 고정 십자 + "여기로 정하기"). 지도의 시작 위치는 아이의 마지막 확인 위치로 둔다 — 부모가 정하려는 장소는 거의 항상 그 근처다.

저장 뒤에는 `sync_rules` 명령을 보낸다. 자녀 폰이 장소를 다시 읽어 지오펜스를 다시 걸어야 한다. **만들기·고치기·지우기·스위치 토글 네 갈래를 모두 덮을 것** — 4단계 Task 10 에서 같은 요구를 놓칠 뻔했다.

- [ ] **Step 4: 빌드하고 커밋한다**

```bash
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug :app:testDebugUnitTest
```

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "장소: 부모가 지도에서 찍고 아이 폰이 판정한다

위경도를 숫자로 넣게 하면 부모가 못 쓴다 — 지도 가운데를 좌표로 삼는다.
안에 있었다는 사실은 SharedPreferences 에 남긴다. 메모리에만 두면 재부팅
뒤에 이미 학교에 있는데도 도착 알림이 한 번 더 뜬다."
```

---

### Task 4: 알림 탭과 보호자 상시 수신

**Files:**
- Create: `app/src/main/java/com/kidcare/family/core/EventRepository.kt`
- Create: `app/src/main/java/com/kidcare/family/guardian/AlertService.kt`
- Create: `app/src/main/java/com/kidcare/family/guardian/AlertFragment.kt`, `guardian/AlertAdapter.kt`
- Create: `app/src/main/res/layout/fragment_alert.xml`, `res/layout/item_alert.xml`
- Modify: `AndroidManifest.xml`, `guardian/GuardianMainActivity.kt`, `res/menu/guardian_bottom_nav.xml`, `child/BootReceiver.kt`, `res/values/strings.xml`

**Interfaces:**
- Consumes: `EventDoc`(Task 3), `core/RoleStore`, `core/AuthGateway`
- Produces: `EventRepository.observeEvents/markRead/markAllRead`, `AlertService`

- [ ] **Step 1: 알림 탭을 만든다**

탭 5개가 되면 하단이 빽빽하다. **`장소` 를 `예약` 옆 탭이 아니라 `관리` 화면 안의 줄로 넣고 하단 탭은 넷(지도·알림·관리·예약)으로 유지할지**, 아니면 다섯을 그대로 둘지 실제 화면을 보고 정한다. 어느 쪽이든 **결정과 이유를 보고서에 적을 것.**

목록 한 줄: `🏫 학교에 도착했어요 · 오후 3시 12분`. 안 읽은 것은 배경을 살구빛으로 두고, 화면을 열면 읽음으로 바꾼다.

- [ ] **Step 2: 상시 수신 서비스를 만든다**

`AlertService` 는 보호자 폰의 포그라운드 서비스다. `events/` 를 구독하다가 새 문서가 오면 로컬 알림을 띄운다.

**왜 포그라운드 서비스인가:** FCM 이 없으므로(무료 요금제, Cloud Functions 없음) 아이 폰이 부모 폰을 깨울 방법이 없다. Firestore 리스너는 앱이 백그라운드로 내려가면 Doze 에서 끊긴다. 부모가 앱을 열어야만 알림을 본다면 그건 알림이 아니다. **이 판단을 클래스 주석에 남길 것.**

부모 폰에도 상시 알림이 하나 뜬다는 사실을 **부모에게 먼저 말한다.** 알림 탭 위에 한 줄로 설명하고 켜고 끄는 스위치를 둔다 — 끄면 앱을 열 때만 알림을 본다. 기본값은 **꺼짐**: 묻지도 않고 부모 폰에 상시 알림을 띄우는 것은 무례하다.

`BOOT_COMPLETED` 로 다시 켠다. 지금 `BootReceiver` 는 자녀 역할만 보고 서비스를 켜므로, 보호자 역할 분기를 더한다.

- [ ] **Step 3: 빌드하고 커밋한다**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "알림 탭과 보호자 상시 수신

FCM 이 없어 아이 폰이 부모 폰을 깨울 방법이 없다. 부모가 앱을 열어야만
보는 알림은 알림이 아니므로 포그라운드 서비스로 events 를 구독한다.
부모 폰에도 상시 알림이 뜨는 일이라 기본값은 꺼짐이고 먼저 설명한다."
```

---

### Task 5: 메시지 (보호자 → 자녀)

**Files:**
- Create: `app/src/main/java/com/kidcare/family/child/MessageActivity.kt`
- Create: `app/src/main/res/layout/activity_message.xml`
- Modify: `child/CommandHandler.kt`, `guardian/ControlFragment.kt`, `AndroidManifest.xml`, `res/values/strings.xml`

**Interfaces:**
- Consumes: `CommandType.MESSAGE`(4단계 Task 2 에 이미 있다 — 실제 상수명을 확인하고 그것을 쓸 것), `CommandRepository.send`
- Produces: `MessageActivity`

- [ ] **Step 1: 보내는 쪽을 만든다**

`ControlFragment` 에 입력칸과 `보내기` 를 더한다. 길이 상한 100자 — 아이가 한 화면에서 읽을 수 있어야 하고, 긴 글은 이 통로가 할 일이 아니다.

자주 쓰는 문장을 칩으로 둔다: `지금 어디야?`, `전화 좀 해줘`, `집으로 와`, `밥 먹었어?`. 부모가 걸어가면서 한 손으로 보내는 화면이다.

- [ ] **Step 2: 받는 쪽을 만든다**

`CommandHandler` 가 `message` 명령을 받으면 `MessageActivity` 를 전체화면으로 띄운다. `FindPhoneController` 가 전체화면 알림을 띄우는 방식(`USE_FULL_SCREEN_INTENT`)을 그대로 따르되, **소리는 내지 않는다** — 메시지는 폰찾기가 아니다. 진동 한 번과 알림이면 된다.

화면에는 새싹이, 부모의 문장, 그리고 큰 `확인했어요` 버튼 하나. 누르면 명령이 `done` 이 되어 부모 화면의 상태 줄이 `읽음` 으로 바뀐다. **이것이 아이가 답하는 유일한 통로다** — 자유 문장은 이번 범위가 아니다.

무음·방해금지여도 화면은 떠야 한다. 다만 잠금화면을 강제로 깨우지는 않는다(폰찾기와 다르다).

- [ ] **Step 3: 빌드하고 커밋한다**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "메시지: 부모가 보내고 아이가 확인한다

폰찾기와 같은 전체화면을 쓰되 소리는 내지 않는다 — 메시지는 폰찾기가 아니다.
'확인했어요' 한 번이 아이가 답하는 통로이고, 그게 부모 화면의 '읽음'이 된다."
```

---

### Task 6: 원격 알람시계

**Files:**
- Create: `app/src/main/java/com/kidcare/family/child/RemoteAlarmController.kt`
- Create: `app/src/main/java/com/kidcare/family/child/RemoteAlarmReceiver.kt`
- Create: `app/src/main/java/com/kidcare/family/child/RemoteAlarmStore.kt`
- Modify: `child/CommandHandler.kt`, `guardian/ControlFragment.kt`, `AndroidManifest.xml`, `res/values/strings.xml`

**Interfaces:**
- Consumes: `CommandType.SET_ALARM` / `CANCEL_ALARM`(실제 상수명 확인), `child/FindPhoneController`(울리는 방식 참고)
- Produces: `RemoteAlarmController.set(atMillis, label)/cancel()`

- [ ] **Step 1: 거는 쪽을 만든다**

`ControlFragment` 에 `MaterialTimePicker` 로 시각을 고르고 짧은 이름(`학원 가야 해`)을 붙여 보낸다. 페이로드는 문자열 맵이므로 `atMinuteOfDay`(0~1439)와 `label` 로 보낸다.

**절대 시각(epoch)을 부모 폰에서 계산해 보내지 말 것.** 두 폰의 시간대와 시계가 다르다 — 4단계 Task 8 에서 즉시 변경의 해제 시각을 같은 이유로 자녀 폰이 계산하게 옮겼다. 자녀 폰이 "오늘 그 시각, 이미 지났으면 내일"로 푼다.

- [ ] **Step 2: 울리는 쪽을 만든다**

`AlarmManager.setAlarmClock` 을 쓴다. `setExactAndAllowWhileIdle` 과 달리 Doze 를 확실히 뚫고, 상태바에 알람 아이콘이 떠서 **아이도 알람이 걸린 것을 안다** — 이 앱은 몰래 하지 않는다(설계서 §1).

울리는 방식은 `FindPhoneController` 와 같은 알람 스트림이되 **볼륨을 최대로 올리지 않는다.** 폰찾기는 잃어버린 폰을 찾는 것이라 최대가 맞지만, 알람시계는 아이 옆에 있는 폰이다.

멈춤·5분 뒤 자동 정지·프로세스가 죽어도 복구는 `FindPhoneController` 의 규율을 그대로 따른다(`RemoteAlarmStore`). 그 클래스를 먼저 읽을 것 — 강제 종료로 아이 폰 볼륨이 밤새 최대로 남았던 사고가 거기 적혀 있다.

- [ ] **Step 3: 빌드하고 커밋한다**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "원격 알람시계: 부모가 걸고 아이 폰이 시각을 푼다

절대 시각을 부모 폰에서 계산해 보내면 두 폰의 시간대·시계 차이로 어긋난다.
setAlarmClock 을 쓰는 이유는 Doze 를 뚫는 것과, 상태바에 알람이 보여서
아이도 걸린 걸 안다는 것 둘이다 — 이 앱은 몰래 하지 않는다."
```

---

### Task 7: 상황 경고

**Files:**
- Create: `app/src/main/java/com/kidcare/family/child/ConditionWatcher.kt`
- Modify: `child/TrackingService.kt`, `child/StatusReporter.kt`, `guardian/AlertAdapter.kt`, `res/values/strings.xml`, `docs/known-issues.md`

**Interfaces:**
- Consumes: `EventDoc`(Task 3), `PlaceWatcher` 가 이벤트를 쓰는 경로
- Produces: `ConditionWatcher.check()`

- [ ] **Step 1: 세 가지를 감시한다**

`low_battery` — 배터리 15% 아래로 처음 내려갈 때 한 번. 다시 충전됐다가 또 내려가면 다시 한 번. **매번 알리면 안 된다.**

`permission_off` — 위치·방해금지 권한이 켜져 있다가 꺼졌을 때. 이게 이 앱에서 제일 중요한 경고다. 권한이 꺼지면 앱은 멀쩡히 켜져 있는데 아무것도 못 한다 — 부모 화면에는 그냥 "조용한 하루"로 보인다.

`power_off` 는 만들지 않는다. 안드로이드가 `ACTION_SHUTDOWN` 을 보장하지 않고, 배터리가 빠지거나 강제 종료되면 아예 안 온다. **없는 신호를 있는 척하면 부모가 그 부재를 "괜찮다"로 읽는다.** 대신 4단계에서 만든 연결 끊김 배너가 그 자리를 덮는다. 이 판단을 `docs/known-issues.md` 에 적을 것.

- [ ] **Step 2: 빌드하고 커밋한다**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "상황 경고: 배터리와 권한

권한이 꺼지면 앱은 멀쩡히 켜져 있는데 아무것도 못 하고, 부모 화면에는
'조용한 하루'로 보인다 — 이 앱에서 제일 중요한 경고다. power_off 는
만들지 않는다: 안드로이드가 보장하지 않는 신호를 있는 척하면 부모가
그 부재를 괜찮다고 읽는다."
```

---

## Self-Review

**1. 스펙 커버리지**

| 설계서 항목 | 담당 Task |
|---|---|
| §3 `places/{id}` 문서 구조 | Task 3 |
| §3 `events/{id}` 문서 구조·타입 | Task 3, 7 |
| §3 보안 규칙 (places 보호자 전용, events 방향 반대) | Task 1 |
| §4.6 GeofencingClient·20개 제한·히스테리시스·5분 중복 억제·BOOT 재등록 | Task 2, 3 |
| §3 명령 `set_alarm`·`cancel_alarm` | Task 6 |
| §3 명령 `message` | Task 5 |
| §3 알림 탭 | Task 4 |
| §4.4 되돌린 사실을 events 에 남기고 하루 5회 넘으면 알림 | **6단계로 미룬다.** 되돌리기 이벤트는 `RingerModeReceiver` 를 건드려야 하는데, 그 파일은 4단계에서 잠금 스위치와 얽혀 리뷰를 두 번 거쳤다. 이번 단계의 이벤트 배선이 실기기에서 확인된 뒤에 붙이는 편이 안전하다 |
| §5 오프라인·예외 화면 | 6단계 |

**2. 플레이스홀더 점검** — Task 1·2 는 코드를 그대로 적었다(보안 규칙과 순수 로직은 틀리면 조용히 실패하는 영역이다). Task 3~7 은 알고리즘 방침과 **결정해야 할 것**을 적었다 — 화면 코드는 `MapTimelineFragment`·`ScheduleFragment` 로 패턴이 확립돼 있고, 전부 받아쓰게 하면 계획서만 길어지고 실제 판단이 줄어든다. 다만 각 작업이 무엇을 결정하고 무엇을 보고해야 하는지는 명시했다.

**3. 타입 일관성**

- `Place`/`PlaceState`/`GeofenceHit`(Task 2) → Task 3 ✓
- `PlaceDoc`/`EventDoc`(Task 3) → Task 4·7 ✓
- `CommandType.MESSAGE`/`SET_ALARM`/`CANCEL_ALARM` 은 4단계 Task 2 에 이미 있다 — **Task 5·6 은 실제 상수명을 `core/model/Documents.kt` 에서 확인하고 그것을 쓴다.** 계획서가 부르는 이름과 다르면 실제 쪽이 이긴다.
- `LocationFilter.distanceMeters`(1단계) → Task 2 ✓. `Fix` 의 생성자는 `(lat, lng, accuracy, at, speed=0f)` 다.

**4. 발견해서 반영한 것**

- 장소에 **아이 쓰기를 열면 학교 반경을 0 으로 만들어 도착 알림을 없앨 수 있다.** 아이는 읽기만 — 그런데 자기 폰 지오펜스를 걸려면 읽기는 필요하다. Task 1 에 반영.
- 이벤트를 아이가 만드는데 `read` 를 같이 쓸 수 있으면 **미리 읽음 표시를 해 두어 부모 화면에서 사라지게** 할 수 있다. `create` 에서 `read == false` 를 강제한다.
- `PlaceState` 를 메모리에만 두면 재부팅 뒤 **이미 학교에 있는데 도착 알림이 한 번 더** 뜬다. Task 3 에 반영.
- 절대 시각을 부모 폰이 계산해 보내면 시간대·시계 차이로 어긋난다. 4단계에서 겪은 것과 같은 함정이라 Task 6 에 명시.
- `power_off` 이벤트는 **만들지 않는 것이 정직하다.** Task 7.
