# KidCare 3단계 구현 계획 (구간 요약·타임라인·경로선)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 하루치 위치 점을 "몇 시부터 몇 시까지 어디에 있었고 언제 어디로 이동했는지"라는 글로 바꿔 보호자 폰에 타임라인으로 보여주고, 같은 하루를 지도 위에 선으로 그린다.

**Architecture:** 자녀 폰이 자기 `points/`를 읽어 머무름/이동 구간으로 묶고, 머무른 곳에는 카카오 로컬 API로 주소 이름을 붙여 `segments/`에 올린다. 보호자 폰은 그 요약본만 읽어 화면을 그린다 — 하루치 원시 점 수백 개를 매번 내려받지 않는다. 구간을 묶는 계산과 문장을 만드는 계산은 안드로이드 API에 의존하지 않는 `logic/` 패키지의 순수 함수로 두고 JUnit으로 먼저 고정한다.

**Tech Stack:** Kotlin (AGP 9 내장), Views + ViewBinding + Material3, RecyclerView, Firebase Firestore, 카카오맵 SDK v2 (RouteLine), 카카오 로컬 REST API (`HttpURLConnection`), `java.time`, JUnit4

**설계서:** `docs/superpowers/specs/2026-08-06-kidcare-design.md`
**미해결 목록:** `docs/known-issues.md`
**직전 단계 계획:** `docs/superpowers/plans/2026-08-06-kidcare-phase1-2.md`

## Global Constraints

- 프로젝트 루트 `C:\workAndroid\KidCare`. 브랜치를 나누지 않고 `main`에 직접 커밋한다.
- AGP `9.2.1` / Gradle `9.4.1` / compileSdk `37` / minSdk `26` / targetSdk `36`
- namespace·applicationId `com.kidcare.family`. 표시명 `우리아이 지킴이`.
- UI는 Views + ViewBinding + Material3. **Compose를 쓰지 않는다.**
- AGP 9는 Kotlin 내장이다. `kotlin-android` 플러그인을 따로 적용하지 않는다.
- **`logic/` 패키지는 안드로이드 API를 import 하지 않는다.** `java.time`·`kotlin.math`는 허용. JVM 단위 테스트가 여기 걸린다.
- 사용자 대상 문자열은 전부 한국어이며 `res/values/strings.xml`에 둔다. 코드·XML에 하드코딩하지 않는다. 키 중복 금지.
- 주석은 한국어로, *왜* 그런지를 적는다. 기존 `core/AuthGateway.kt`·`logic/LocationFilter.kt` 문체를 따른다.
- 모든 시각은 UTC 밀리초(`System.currentTimeMillis()`)로 저장하고, 표시할 때만 기기 시간대로 바꾼다.
- 코루틴에서 `CancellationException`은 반드시 다시 던진다. 이 저장소는 같은 버그를 네 번 고쳤다 — `onboarding/GuardianPairingActivity.kt`의 catch 순서가 표준이다.
- 커밋 메시지는 한국어. 저자 `Yongminlee2 <dydals5678@gmail.com>`. **AI/Claude 관련 표기를 넣지 않는다**(`Co-Authored-By` 포함).
- 비밀값은 커밋하지 않는다: `local.properties`, `app/google-services.json`, `keystore.properties`, `*.jks`
- 빌드 시 `export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"` 가 필요하다. JVM 테스트 워커가 `ClassNotFoundException: GradleWorkerMain`으로 죽으면 `./gradlew.bat --stop` 후 재시도한다(`gradle.properties`의 `-Dfile.encoding=MS949`가 이미 대응한다). `GRADLE_USER_HOME` 우회나 `C:\workAndroid\gradle-user-ascii`는 쓰지 않는다 — 후자는 한글 홈으로 가는 정션이라 무효다.
- **`firestore.rules`를 수정하지 않는다.** 보안 리뷰 3회·재작성 2회를 거친 파일이다. 이 단계가 새로 쓰는 `segments/`와 `points/` 삭제는 기존 `match /children/{childUid}/{document=**}` 규칙이 이미 덮는다(자녀 본인 쓰기 허용, 가족 멤버 읽기 허용). 규칙 변경이 필요해 보이면 진행하지 말고 BLOCKED로 보고한다.
- `adb`를 실행하지 않는다. 실기기 확인은 사용자가 직접 한다. 각 작업의 확인 절차는 보고서에 적는다.

## 이 단계에서 다루지 않는 것

- **재설치 후 재연결**(`docs/known-issues.md` 1번). 부모 폰을 다시 깔면 익명 uid가 바뀌는데, 보안 규칙이 보호자 자리를 `ownerUid`에게만 주므로 새 uid는 보호자가 될 수 없다. 제대로 고치려면 익명 인증 대신 계정 로그인을 붙이거나 규칙을 바꿔야 하고, 아이 쪽에 "다시 연결" 버튼을 다는 것은 아이가 스스로 감시를 풀 수 있게 된다는 뜻이다. **설계 판단이 필요하므로 이 단계에서 손대지 않는다.**
- 소리·진동 제어, 폰찾기, 시간대 예약, 장소 반경 등록, 알림 — 4~6단계.
- 오프라인 위치 버퍼(Room) — 7단계.

## 사용자 준비물

| 준비물 | 필요한 시점 | 없으면 |
|---|---|---|
| 카카오 **네이티브 앱 키** (`local.properties`의 `KAKAO_APP_KEY`) | Task 6 (경로선) | 지도가 안 뜬다. 타임라인 글은 그대로 나온다 |
| 카카오 **REST API 키** (`local.properties`의 `KAKAO_REST_KEY`) | Task 4 (장소 이름) | 머무른 곳이 이름 없이 "머무른 곳"으로만 나온다. 나머지는 정상 |

두 키는 [developers.kakao.com](https://developers.kakao.com)의 **같은 앱 화면 `앱 설정 > 앱 키`**에서 함께 나온다. 네이티브 앱 키를 받을 때 REST API 키도 같이 복사해 두면 된다. Task 4에서 `docs/setup.md`에 절차를 기록한다.

## File Structure

```
app/src/main/java/com/kidcare/family/
├─ logic/                          ★순수 코틀린. 안드로이드 import 금지
│  ├─ LocationFilter.kt            (기존) Fix 에 speed 필드 추가 — Task 3
│  ├─ SegmentBuilder.kt            (신규) 위치 점 목록 → 머무름/이동 구간   Task 1
│  └─ SegmentSummarizer.kt         (신규) 구간 → 사람이 읽는 문장·시각·거리  Task 2
├─ core/
│  ├─ model/Documents.kt           (기존) SegmentDoc 추가 — Task 3
│  └─ SegmentRepository.kt         (신규) segments 읽기/쓰기, points 조회·정리
├─ child/
│  ├─ TrackingService.kt           (기존) 구간 재계산 트리거·주기 전환 — Task 3, 7
│  ├─ LocationCollector.kt         (기존) 활동 인식 기반 주기 전환 — Task 7
│  ├─ SegmentUploader.kt           (신규) points 읽어 SegmentBuilder 돌리고 반영  Task 3
│  ├─ PlaceNamer.kt                (신규) 카카오 로컬 REST 역지오코딩 + 캐시    Task 4
│  └─ PointsCleaner.kt             (신규) 30일 지난 points 삭제               Task 8
└─ guardian/
   ├─ MapTimelineFragment.kt       (기존) 날짜 바·타임라인·경로선 — Task 5, 6, 8
   ├─ TimelineAdapter.kt           (신규) RecyclerView 어댑터                Task 5
   └─ DayPicker.kt                 (신규) 하루의 시작·끝 밀리초 계산 (순수)   Task 5

app/src/test/java/com/kidcare/family/logic/
├─ SegmentBuilderTest.kt           Task 1
├─ SegmentSummarizerTest.kt        Task 2
└─ DayPickerTest.kt                Task 5
```

**책임 경계:** `logic/`은 계산만 한다. `core/`는 Firestore 접근만 한다. `child/`·`guardian/`은 안드로이드 화면·서비스만 담당하고 계산은 `logic/`에 위임한다. `child/`와 `guardian/`은 서로를 import 하지 않는다.

---

### Task 1: 구간 묶기 로직 (TDD)

하루치 위치 점을 "머무름"과 "이동" 구간으로 묶는다. **순수 계산만** 한다 — Firestore도 화면도 없다.

이 단계 전체의 품질이 여기서 갈린다. GPS는 가만히 있어도 몇십 미터씩 튀고, 신호 대기 중 잠깐 멈춘 것과 학원에 도착한 것을 구분해야 한다.

**Files:**
- Create: `app/src/main/java/com/kidcare/family/logic/SegmentBuilder.kt`
- Create: `app/src/test/java/com/kidcare/family/logic/SegmentBuilderTest.kt`

**Interfaces:**
- Consumes: `logic/LocationFilter.kt`의 `data class Fix(lat, lng, accuracy, at)`와 `LocationFilter.distanceMeters(a, b)` (1~2단계에서 이미 있음, 단위 테스트 9개로 고정돼 있음)
- Produces:
  - `enum class SegmentType { STAY, MOVE }`
  - `data class Segment(val type: SegmentType, val startAt: Long, val endAt: Long, val lat: Double, val lng: Double, val distanceMeters: Double, val pointCount: Int)`
  - `SegmentBuilder.STAY_RADIUS_METERS: Double` = 100.0
  - `SegmentBuilder.MIN_STAY_MILLIS: Long` = 5분
  - `SegmentBuilder.EXIT_CONFIRM_POINTS: Int` = 2
  - `SegmentBuilder.build(points: List<Fix>): List<Segment>`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`app/src/test/java/com/kidcare/family/logic/SegmentBuilderTest.kt`:

```kotlin
package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SegmentBuilderTest {

    private val baseLat = 37.5665
    private val baseLng = 126.9780
    private val t0 = 1_700_000_000_000L

    /** 기준점에서 북쪽으로 [meters] 만큼, [minutes] 분 뒤의 점. 위도 1도 = 약 111,320m. */
    private fun p(meters: Double, minutes: Long, accuracy: Float = 10f) = Fix(
        lat = baseLat + meters / 111_320.0,
        lng = baseLng,
        accuracy = accuracy,
        at = t0 + minutes * 60_000L,
    )

    @Test
    fun `점이 없으면 구간도 없다`() {
        assertEquals(emptyList<Segment>(), SegmentBuilder.build(emptyList()))
    }

    @Test
    fun `점이 하나면 구간을 만들지 않는다`() {
        // 구간은 시작과 끝이 있어야 의미가 있다. 점 하나로는 머무름인지 이동인지 알 수 없다.
        assertEquals(emptyList<Segment>(), SegmentBuilder.build(listOf(p(0.0, 0))))
    }

    @Test
    fun `하루 종일 같은 자리에 있으면 머무름 하나로 묶인다`() {
        val points = (0..20).map { p(it * 2.0, it * 10L) }   // 10분 간격, 2m 씩만 흔들림
        val segments = SegmentBuilder.build(points)
        assertEquals(1, segments.size)
        assertEquals(SegmentType.STAY, segments[0].type)
        assertEquals(t0, segments[0].startAt)
        assertEquals(t0 + 200 * 60_000L, segments[0].endAt)
        assertEquals(21, segments[0].pointCount)
    }

    @Test
    fun `5분을 못 채운 정지는 머무름이 아니다`() {
        // 0분과 3분에 같은 자리, 그 뒤 멀리 이동 → 정지 3분은 머무름이 아니라 이동에 흡수된다.
        val points = listOf(
            p(0.0, 0), p(5.0, 3),
            p(2000.0, 10), p(4000.0, 20),
        )
        val segments = SegmentBuilder.build(points)
        assertTrue("머무름이 하나도 없어야 한다: $segments", segments.none { it.type == SegmentType.STAY })
    }

    @Test
    fun `정확히 5분 머무르면 머무름으로 인정한다`() {
        // 경계값. MIN_STAY_MILLIS 는 '이상' 이어야 한다.
        val points = listOf(p(0.0, 0), p(5.0, 5), p(3000.0, 20), p(6000.0, 30))
        val segments = SegmentBuilder.build(points)
        assertEquals(SegmentType.STAY, segments.first().type)
        assertEquals(5 * 60_000L, segments.first().endAt - segments.first().startAt)
    }

    @Test
    fun `GPS 가 한 번 튀어도 머무름이 깨지지 않는다`() {
        // 반경을 벗어난 점이 연속 2개여야 머무름이 끝난다. 1개는 튄 것으로 본다.
        val points = listOf(
            p(0.0, 0), p(10.0, 10),
            p(500.0, 20),           // 튐 (연속 1개)
            p(15.0, 30), p(20.0, 40),
        )
        val segments = SegmentBuilder.build(points)
        assertEquals(1, segments.size)
        assertEquals(SegmentType.STAY, segments[0].type)
        assertEquals(t0 + 40 * 60_000L, segments[0].endAt)
    }

    @Test
    fun `반경을 벗어난 점이 연속 두 개면 머무름이 끝난다`() {
        val points = listOf(
            p(0.0, 0), p(10.0, 10), p(20.0, 20),
            p(3000.0, 30), p(6000.0, 40),        // 연속 2개 → 머무름 종료
            p(9000.0, 50), p(12000.0, 60),
        )
        val segments = SegmentBuilder.build(points)
        assertEquals(SegmentType.STAY, segments[0].type)
        assertEquals(t0 + 20 * 60_000L, segments[0].endAt)
        assertEquals(SegmentType.MOVE, segments[1].type)
    }

    @Test
    fun `머무름 이동 머무름 순서로 나온다`() {
        val points = buildList {
            // 학교: 0~40분
            addAll((0..4).map { p(it * 5.0, it * 10L) })
            // 이동: 50~60분
            add(p(1500.0, 50)); add(p(3000.0, 60))
            // 학원: 70~120분 (3000m 지점 근처)
            addAll((0..5).map { p(3000.0 + it * 5.0, 70 + it * 10L) })
        }
        val segments = SegmentBuilder.build(points)
        assertEquals(
            listOf(SegmentType.STAY, SegmentType.MOVE, SegmentType.STAY),
            segments.map { it.type },
        )
    }

    @Test
    fun `이동 구간은 앞뒤 머무름과 시각이 이어진다`() {
        // 지도에 선을 그릴 때 구간 사이가 끊기면 안 된다.
        val points = buildList {
            addAll((0..4).map { p(it * 5.0, it * 10L) })
            add(p(1500.0, 50)); add(p(3000.0, 60))
            addAll((0..5).map { p(3000.0 + it * 5.0, 70 + it * 10L) })
        }
        val segments = SegmentBuilder.build(points)
        for (i in 0 until segments.size - 1) {
            assertEquals(
                "구간 $i 의 끝과 ${i + 1} 의 시작이 어긋난다: $segments",
                segments[i].endAt, segments[i + 1].startAt,
            )
        }
    }

    @Test
    fun `이동 거리는 점 사이 거리의 합이다`() {
        val points = listOf(
            p(0.0, 0), p(5.0, 5),          // 머무름
            p(1000.0, 20), p(2000.0, 30),  // 이동
            p(3000.0, 40), p(3005.0, 50),  // 머무름
        )
        val move = SegmentBuilder.build(points).first { it.type == SegmentType.MOVE }
        assertTrue("이동 거리가 ${move.distanceMeters}m 로 예상 범위(2800~3200)를 벗어났다",
            move.distanceMeters in 2800.0..3200.0)
    }

    @Test
    fun `머무름의 좌표는 그 구간 점들의 평균이다`() {
        val points = listOf(p(0.0, 0), p(100.0, 5), p(3000.0, 30), p(6000.0, 40))
        val stay = SegmentBuilder.build(points).first { it.type == SegmentType.STAY }
        // 0m 와 100m 의 평균 = 50m 지점
        val expectedLat = baseLat + 50.0 / 111_320.0
        assertEquals(expectedLat, stay.lat, 1e-6)
    }

    @Test
    fun `시각이 뒤섞여 들어와도 정렬해서 처리한다`() {
        // Firestore 쿼리 결과 순서를 믿지 않는다.
        val ordered = (0..10).map { p(it * 2.0, it * 10L) }
        assertEquals(SegmentBuilder.build(ordered), SegmentBuilder.build(ordered.shuffled()))
    }

    @Test
    fun `정확도가 나쁜 점은 계산에서 뺀다`() {
        // 100m 초과 오차는 LocationFilter 가 이미 업로드 단계에서 걸러내지만,
        // 옛 데이터나 다른 경로로 섞여 들어올 수 있으므로 여기서도 방어한다.
        val points = listOf(
            p(0.0, 0), p(5.0, 10),
            p(5000.0, 15, accuracy = 500f),   // 오차 500m — 무시돼야 한다
            p(10.0, 20), p(15.0, 30),
        )
        val segments = SegmentBuilder.build(points)
        assertEquals(1, segments.size)
        assertEquals(SegmentType.STAY, segments[0].type)
        assertEquals(4, segments[0].pointCount)
    }
}
```

- [ ] **Step 2: 테스트를 돌려 실패를 확인한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:testDebugUnitTest --tests "*SegmentBuilderTest*"
```

기대: 컴파일 실패 — `Unresolved reference: SegmentBuilder`

- [ ] **Step 3: 구현을 쓴다**

`app/src/main/java/com/kidcare/family/logic/SegmentBuilder.kt`:

```kotlin
package com.kidcare.family.logic

enum class SegmentType { STAY, MOVE }

/**
 * 하루의 한 토막.
 *
 * STAY 는 한 곳에 머문 구간이고 [lat]/[lng] 는 그 구간 점들의 평균 좌표다.
 * MOVE 는 이동한 구간이고 [lat]/[lng] 는 도착 지점, [distanceMeters] 는 실제 이동 거리다.
 */
data class Segment(
    val type: SegmentType,
    val startAt: Long,
    val endAt: Long,
    val lat: Double,
    val lng: Double,
    val distanceMeters: Double,
    val pointCount: Int,
)

/**
 * 위치 점 목록을 머무름/이동 구간으로 묶는다.
 *
 * 판정 기준은 설계서 §4.2 다:
 *   - 반경 100m 안에 5분 이상 있으면 머무름
 *   - 반경을 벗어난 점이 **연속 2개** 나와야 머무름이 끝난다. 1개는 GPS 가 튄 것으로 본다.
 *   - 5분을 못 채운 정지는 이동에 흡수한다 (신호 대기 같은 것)
 *
 * "연속 2개" 규칙이 핵심이다. 실내에서는 좌표가 수십 미터씩 흔들리고 가끔 수백 미터를
 * 튀는데, 한 점만 보고 머무름을 끊으면 학교에 있는 6시간이 수십 개 구간으로 쪼개진다.
 *
 * 안드로이드 API 에 의존하지 않는다. JVM 단위 테스트 대상.
 */
object SegmentBuilder {

    /** 이 반경 안에 있으면 같은 자리로 본다. */
    const val STAY_RADIUS_METERS: Double = 100.0

    /** 이 시간 이상 머물러야 머무름으로 인정한다. */
    const val MIN_STAY_MILLIS: Long = 5 * 60 * 1000L

    /** 반경을 벗어난 점이 이만큼 연속돼야 머무름을 끝낸다. */
    const val EXIT_CONFIRM_POINTS: Int = 2

    fun build(points: List<Fix>): List<Segment> {
        // Firestore 쿼리 결과 순서를 믿지 않는다. 오차가 큰 점은 계산 자체에서 뺀다.
        val sorted = points
            .filter { it.accuracy <= LocationFilter.MAX_ACCURACY_METERS }
            .sortedBy { it.at }
        if (sorted.size < 2) return emptyList()

        val stays = findStayRanges(sorted)
        return assemble(sorted, stays)
    }

    /** 머무름으로 인정된 구간의 인덱스 범위들. 서로 겹치지 않고 앞에서부터 정렬돼 있다. */
    private fun findStayRanges(points: List<Fix>): List<IntRange> {
        val ranges = mutableListOf<IntRange>()
        var start = 0
        while (start < points.size) {
            val anchor = points[start]
            var lastInside = start
            var outsideRun = 0
            var cursor = start
            while (cursor + 1 < points.size) {
                cursor++
                if (LocationFilter.distanceMeters(anchor, points[cursor]) <= STAY_RADIUS_METERS) {
                    lastInside = cursor
                    outsideRun = 0
                } else {
                    outsideRun++
                    if (outsideRun >= EXIT_CONFIRM_POINTS) break
                }
            }
            val lasted = points[lastInside].at - anchor.at
            if (lastInside > start && lasted >= MIN_STAY_MILLIS) {
                ranges += start..lastInside
                start = lastInside + 1
            } else {
                // 머무름이 아니면 한 칸만 밀고 다시 본다. 하루 점이 수백 개라 이 정도면 충분하다.
                start++
            }
        }
        return ranges
    }

    /** 머무름 범위 사이를 이동 구간으로 채운다. 이동은 앞뒤 머무름의 끝점을 공유해 선이 끊기지 않게 한다. */
    private fun assemble(points: List<Fix>, stays: List<IntRange>): List<Segment> {
        val result = mutableListOf<Segment>()
        var cursor = 0
        for (stay in stays) {
            if (stay.first > cursor) addMove(points, cursor, stay.first, result)
            result += staySegment(points, stay)
            cursor = stay.last
        }
        if (cursor < points.lastIndex) addMove(points, cursor, points.lastIndex, result)
        return result
    }

    private fun addMove(points: List<Fix>, from: Int, to: Int, into: MutableList<Segment>) {
        if (to <= from) return
        var distance = 0.0
        for (i in from until to) distance += LocationFilter.distanceMeters(points[i], points[i + 1])
        into += Segment(
            type = SegmentType.MOVE,
            startAt = points[from].at,
            endAt = points[to].at,
            lat = points[to].lat,
            lng = points[to].lng,
            distanceMeters = distance,
            pointCount = to - from + 1,
        )
    }

    private fun staySegment(points: List<Fix>, range: IntRange): Segment {
        val slice = points.slice(range)
        return Segment(
            type = SegmentType.STAY,
            startAt = slice.first().at,
            endAt = slice.last().at,
            lat = slice.sumOf { it.lat } / slice.size,
            lng = slice.sumOf { it.lng } / slice.size,
            distanceMeters = 0.0,
            pointCount = slice.size,
        )
    }
}
```

- [ ] **Step 4: 테스트를 돌려 통과를 확인한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:testDebugUnitTest --tests "*SegmentBuilderTest*"
```

기대: `BUILD SUCCESSFUL`, 13개 테스트 통과. 기존 18개도 그대로 통과해야 한다.

- [ ] **Step 5: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "구간 묶기: 위치 점을 머무름·이동으로 나누는 순수 로직

반경 100m 5분 이상이면 머무름. 반경을 벗어난 점이 연속 2개여야 끝난다 —
1개로 끊으면 실내 GPS 흔들림에 학교 6시간이 수십 조각으로 쪼개진다.
단위 테스트 13개."
```

---

### Task 2: 구간을 문장으로 바꾸는 로직 (TDD)

구간을 화면에 쓸 한국어 문장·시각·거리 표기로 바꾼다. **순수 계산만** 한다.

**Files:**
- Create: `app/src/main/java/com/kidcare/family/logic/SegmentSummarizer.kt`
- Create: `app/src/test/java/com/kidcare/family/logic/SegmentSummarizerTest.kt`

**Interfaces:**
- Consumes: Task 1의 `Segment`, `SegmentType`
- Produces:
  - `SegmentSummarizer.timeRange(segment: Segment, zone: java.time.ZoneId): String` — `"14:10~15:40"`
  - `SegmentSummarizer.durationText(millis: Long): String` — `"1시간 30분"` / `"25분"` / `"1분 미만"`
  - `SegmentSummarizer.distanceText(meters: Double): String` — `"1.2km"` / `"480m"`

> 문장 전체(예: `"학교 머무름"`)를 여기서 조립하지 않는다. 장소 이름과 결합한 최종 문구는
> `strings.xml`의 서식 문자열로 만들어야 번역·수정이 한 곳에서 된다. 여기서는 그 서식에
> 꽂아 넣을 **조각**만 만든다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`app/src/test/java/com/kidcare/family/logic/SegmentSummarizerTest.kt`:

```kotlin
package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.ZoneId

class SegmentSummarizerTest {

    private val seoul: ZoneId = ZoneId.of("Asia/Seoul")

    private fun segment(startAt: Long, endAt: Long) = Segment(
        type = SegmentType.STAY,
        startAt = startAt, endAt = endAt,
        lat = 37.5, lng = 127.0, distanceMeters = 0.0, pointCount = 2,
    )

    @Test
    fun `시각 범위를 시분으로 보여준다`() {
        // 2026-08-07 14:10 KST = 05:10 UTC
        val start = 1_786_000_200_000L   // 아래 주석 참고
        val zoned = java.time.Instant.ofEpochMilli(start).atZone(seoul)
        val expected = "%02d:%02d~%02d:%02d".format(
            zoned.hour, zoned.minute,
            zoned.plusMinutes(90).hour, zoned.plusMinutes(90).minute,
        )
        assertEquals(expected, SegmentSummarizer.timeRange(segment(start, start + 90 * 60_000L), seoul))
    }

    @Test
    fun `자정을 넘는 구간도 시분만 보여준다`() {
        // 날짜별로 나눠 보여주는 화면이라 날짜는 헤더가 담당한다. 여기서는 시분만.
        val start = 1_786_000_200_000L
        val text = SegmentSummarizer.timeRange(segment(start, start + 12 * 3_600_000L), seoul)
        assertEquals(11, text.length)          // "HH:mm~HH:mm"
        assertEquals('~', text[5])
    }

    @Test
    fun `시간대가 다르면 표시도 달라진다`() {
        val start = 1_786_000_200_000L
        val seoulText = SegmentSummarizer.timeRange(segment(start, start + 60_000L), seoul)
        val utcText = SegmentSummarizer.timeRange(segment(start, start + 60_000L), ZoneId.of("UTC"))
        assertEquals("서울과 UTC 는 9시간 차이라 표시가 같을 수 없다", false, seoulText == utcText)
    }

    @Test
    fun `한 시간 이상이면 시간과 분을 함께 쓴다`() {
        assertEquals("1시간 30분", SegmentSummarizer.durationText(90 * 60_000L))
        assertEquals("2시간 5분", SegmentSummarizer.durationText(125 * 60_000L))
    }

    @Test
    fun `정각이면 분을 붙이지 않는다`() {
        assertEquals("2시간", SegmentSummarizer.durationText(120 * 60_000L))
    }

    @Test
    fun `한 시간 미만이면 분만 쓴다`() {
        assertEquals("25분", SegmentSummarizer.durationText(25 * 60_000L))
    }

    @Test
    fun `1분 미만은 따로 표기한다`() {
        assertEquals("1분 미만", SegmentSummarizer.durationText(30_000L))
        assertEquals("1분 미만", SegmentSummarizer.durationText(0L))
    }

    @Test
    fun `1km 이상은 킬로미터로 소수 한 자리까지 쓴다`() {
        assertEquals("1.2km", SegmentSummarizer.distanceText(1234.0))
        assertEquals("12.3km", SegmentSummarizer.distanceText(12_345.0))
    }

    @Test
    fun `1km 미만은 미터로 십 단위까지 쓴다`() {
        // 아이 위치에 1m 단위 정밀도를 보여주는 것은 없는 정확도를 있는 척하는 것이다.
        assertEquals("480m", SegmentSummarizer.distanceText(483.0))
        assertEquals("50m", SegmentSummarizer.distanceText(51.0))
    }

    @Test
    fun `아주 짧은 거리는 0m 대신 10m 미만으로 쓴다`() {
        assertEquals("10m 미만", SegmentSummarizer.distanceText(4.0))
        assertEquals("10m 미만", SegmentSummarizer.distanceText(0.0))
    }
}
```

- [ ] **Step 2: 테스트를 돌려 실패를 확인한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:testDebugUnitTest --tests "*SegmentSummarizerTest*"
```

기대: 컴파일 실패 — `Unresolved reference: SegmentSummarizer`

- [ ] **Step 3: 구현을 쓴다**

`app/src/main/java/com/kidcare/family/logic/SegmentSummarizer.kt`:

```kotlin
package com.kidcare.family.logic

import java.time.Instant
import java.time.ZoneId

/**
 * 구간을 화면에 쓸 조각으로 바꾼다.
 *
 * 문장 전체를 여기서 조립하지 않는다. 장소 이름과 합친 최종 문구는 strings.xml 의
 * 서식 문자열이 담당해야 문구를 한 곳에서 고칠 수 있다. 여기서 만드는 것은
 * 거기에 꽂아 넣을 시각·기간·거리 조각뿐이다.
 *
 * 안드로이드 API 에 의존하지 않는다(java.time 은 minSdk 26 에서 쓸 수 있다).
 */
object SegmentSummarizer {

    /** "14:10~15:40". 날짜는 화면의 날짜 헤더가 담당하므로 시분만 쓴다. */
    fun timeRange(segment: Segment, zone: ZoneId): String {
        val start = Instant.ofEpochMilli(segment.startAt).atZone(zone)
        val end = Instant.ofEpochMilli(segment.endAt).atZone(zone)
        return "%02d:%02d~%02d:%02d".format(start.hour, start.minute, end.hour, end.minute)
    }

    fun durationText(millis: Long): String {
        val totalMinutes = millis / 60_000L
        if (totalMinutes < 1) return "1분 미만"
        val hours = totalMinutes / 60
        val minutes = totalMinutes % 60
        return when {
            hours == 0L -> "${minutes}분"
            minutes == 0L -> "${hours}시간"
            else -> "${hours}시간 ${minutes}분"
        }
    }

    /**
     * 1km 이상은 "1.2km", 미만은 십 단위로 내림한 "480m".
     *
     * 미터를 1 단위까지 보여주면 GPS 오차(최대 100m 까지 받아들인다)보다 정밀해 보여
     * 없는 정확도를 있는 척하게 된다.
     */
    fun distanceText(meters: Double): String {
        if (meters >= 1000.0) return "%.1fkm".format(meters / 1000.0)
        val tens = (meters / 10).toInt() * 10
        return if (tens < 10) "10m 미만" else "${tens}m"
    }
}
```

- [ ] **Step 4: 테스트를 돌려 통과를 확인한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:testDebugUnitTest
```

기대: `BUILD SUCCESSFUL`. 전체 44개(기존 18 + Task 1의 13 + 이번 10 + 정렬 여유) 중 실패 0. 정확한 수는 실행 결과로 확인해 보고서에 적는다.

- [ ] **Step 5: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "구간 문장화: 시각·기간·거리 표기 로직

거리를 1m 단위로 보여주면 GPS 오차보다 정밀해 보여 없는 정확도를 있는 척하게
되므로 십 단위로 내린다. 단위 테스트 10개."
```

---

### Task 3: 자녀 폰이 구간을 계산해 올린다

자녀 폰이 자기 `points/`를 읽어 `SegmentBuilder`를 돌리고 결과를 `segments/`에 반영한다. 보호자 폰이 하루치 원시 점 수백 개를 매번 내려받지 않도록 하는 것이 목적이다.

**Files:**
- Modify: `app/src/main/java/com/kidcare/family/logic/LocationFilter.kt` (`Fix`에 `speed` 추가)
- Modify: `app/src/test/java/com/kidcare/family/logic/LocationFilterTest.kt` (생성자 변경 반영)
- Modify: `app/src/main/java/com/kidcare/family/child/LocationCollector.kt` (`speed` 채우기)
- Modify: `app/src/main/java/com/kidcare/family/child/StatusReporter.kt` (`speed` 저장)
- Modify: `app/src/main/java/com/kidcare/family/core/model/Documents.kt` (`SegmentDoc` 추가)
- Create: `app/src/main/java/com/kidcare/family/core/SegmentRepository.kt`
- Create: `app/src/main/java/com/kidcare/family/child/SegmentUploader.kt`
- Modify: `app/src/main/java/com/kidcare/family/child/TrackingService.kt` (업로드 후 재계산 트리거)

**Interfaces:**
- Consumes: `SegmentBuilder.build(points)` (Task 1), `Fix` (기존), `RoleStore.familyId` (1단계), `AuthGateway.currentUid()` (1단계)
- Produces:
  - `data class SegmentDoc(val type: String = "", val startAt: Long = 0L, val endAt: Long = 0L, val lat: Double = 0.0, val lng: Double = 0.0, val distanceMeters: Double = 0.0, val pointCount: Int = 0, val placeName: String = "", val dayKey: String = "")`
  - `SegmentRepository.pointsOfDay(familyId, childUid, dayStartMillis, dayEndMillis): List<Fix>` — suspend
  - `SegmentRepository.replaceSegmentsOfDay(familyId, childUid, dayKey, segments: List<SegmentDoc>)` — suspend
  - `SegmentRepository.observeSegmentsOfDay(familyId, childUid, dayKey, onChange: (List<SegmentDoc>) -> Unit, onError: (Exception) -> Unit): ListenerRegistration`
  - `SegmentRepository.dayKeyOf(millis: Long, zone: ZoneId): String` — `"2026-08-07"`
  - `SegmentUploader.rebuildToday(familyId: String, childUid: String)` — suspend

> **`dayKey`를 문서 필드로 두는 이유:** 보호자 폰은 "그 날 하루"만 읽어야 한다. `startAt`
> 범위로 쿼리하면 자정을 걸친 구간이 어느 날에 속하는지 매번 계산해야 하고 시간대가
> 바뀌면 어긋난다. 자녀 폰이 계산할 때 **그 구간이 시작한 날**을 문자열로 박아두면
> 보호자는 `whereEqualTo("dayKey", ...)` 한 줄이면 된다.

- [ ] **Step 1: `Fix`에 speed 를 추가한다**

`logic/LocationFilter.kt`의 `Fix`를 고친다. 기본값을 주므로 기존 호출부는 그대로 컴파일된다.

```kotlin
/** 위치 한 점. 안드로이드 Location 에 의존하지 않는 값 객체다. */
data class Fix(
    val lat: Double,
    val lng: Double,
    val accuracy: Float,
    val at: Long,
    /**
     * m/s. 기기가 속도를 못 주면 0 이다.
     *
     * 기본값을 둔 이유: 이 필드가 없던 시절에 저장된 points 문서는 speed 가 0 으로
     * 읽히는데, 그걸 "정지"로 오해하면 안 된다. 속도는 참고용이고 구간 판정은
     * 좌표와 시각으로만 한다.
     */
    val speed: Float = 0f,
)
```

- [ ] **Step 2: 기존 테스트가 여전히 통과하는지 확인한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:testDebugUnitTest
```

기대: 기본값 덕분에 `LocationFilterTest`가 수정 없이 통과한다. 만약 실패하면 테스트를 약화시키지 말고 코드를 고친다.

- [ ] **Step 3: 수집·저장 경로에 speed 를 흘린다**

`child/LocationCollector.kt`의 `onFix` 호출부:

```kotlin
                val loc = result.lastLocation ?: return
                onFix(Fix(loc.latitude, loc.longitude, loc.accuracy, loc.time, loc.speed))
```

`child/StatusReporter.kt`의 `PointDoc` 생성부에 한 줄 추가:

```kotlin
                speed = fix.speed,
```

> 지금까지 `PointDoc.speed`는 항상 0 으로 저장되고 있었다(`Fix`에 속도가 없었다).
> 3단계에서 속도를 쓸 계획은 없지만, 값이 있는 척하는 필드를 남겨두면 나중에 그걸
> 믿고 계산하는 코드가 조용히 틀린다.

- [ ] **Step 4: `SegmentDoc`을 추가한다**

`core/model/Documents.kt` 맨 아래에 붙인다.

```kotlin
/**
 * children/{childUid}/segments/{autoId} — 하루를 머무름·이동으로 요약한 한 토막.
 *
 * 자녀 폰이 자기 points 를 읽어 계산해 올린다. 보호자 폰이 하루치 원시 점(하루 최대
 * 수백 개)을 매번 내려받으면 느리고 Firestore 읽기 사용량도 커지는데, 요약본은
 * 하루 20~30건이면 끝난다.
 *
 * [dayKey] 는 "2026-08-07" 꼴로, 그 구간이 **시작한 날**을 자녀 폰의 시간대 기준으로
 * 박아둔 값이다. startAt 범위로 쿼리하면 자정을 걸친 구간이 어느 날에 속하는지 매번
 * 계산해야 하고 시간대가 바뀌면 어긋난다.
 */
data class SegmentDoc(
    val type: String = "",          // "STAY" | "MOVE"
    val startAt: Long = 0L,
    val endAt: Long = 0L,
    val lat: Double = 0.0,
    val lng: Double = 0.0,
    val distanceMeters: Double = 0.0,
    val pointCount: Int = 0,
    /** 머무른 곳 이름. Task 4 가 채운다. 비어 있으면 화면이 "머무른 곳"으로 표시한다. */
    val placeName: String = "",
    val dayKey: String = "",
)
```

- [ ] **Step 5: `SegmentRepository`를 쓴다**

`core/SegmentRepository.kt`:

```kotlin
package com.kidcare.family.core

import android.util.Log
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.Query
import com.kidcare.family.core.model.SegmentDoc
import com.kidcare.family.logic.Fix
import kotlinx.coroutines.tasks.await
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * 하루 요약(segments)과 그 재료(points)를 다룬다.
 *
 * 쓰기는 자녀 폰만 한다 — firestore.rules 의 children/{childUid}/{document=**} 규칙이
 * 자녀 본인에게만 쓰기를 허용하기 때문이다. 보호자 폰은 읽기만 한다. 규칙을 고칠
 * 필요가 없도록 일부러 이 방향으로 설계했다.
 */
object SegmentRepository {

    private const val TAG = "SegmentRepository"
    private val dayFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")

    private val db: FirebaseFirestore get() = FirebaseFirestore.getInstance()

    fun dayKeyOf(millis: Long, zone: ZoneId): String =
        Instant.ofEpochMilli(millis).atZone(zone).format(dayFormatter)

    private fun childRef(familyId: String, childUid: String) =
        db.collection("families").document(familyId)
            .collection("children").document(childUid)

    /** 그 날의 원시 위치 점. 자녀 폰이 구간을 계산할 때만 쓴다. */
    suspend fun pointsOfDay(
        familyId: String,
        childUid: String,
        dayStartMillis: Long,
        dayEndMillis: Long,
    ): List<Fix> =
        childRef(familyId, childUid).collection("points")
            .whereGreaterThanOrEqualTo("at", dayStartMillis)
            .whereLessThan("at", dayEndMillis)
            .orderBy("at", Query.Direction.ASCENDING)
            .get().await()
            .documents.mapNotNull { doc ->
                val lat = doc.getDouble("lat") ?: return@mapNotNull null
                val lng = doc.getDouble("lng") ?: return@mapNotNull null
                val at = doc.getLong("at") ?: return@mapNotNull null
                Fix(
                    lat = lat,
                    lng = lng,
                    accuracy = (doc.getDouble("accuracy") ?: 0.0).toFloat(),
                    at = at,
                    speed = (doc.getDouble("speed") ?: 0.0).toFloat(),
                )
            }

    /**
     * 그 날의 요약을 통째로 갈아끼운다.
     *
     * 구간은 새 점이 들어올 때마다 경계가 바뀔 수 있어서(머무름이 길어지거나, 이동이
     * 머무름으로 확정되거나) 부분 수정이 아니라 하루 단위 교체가 맞다. 하루 20~30건이라
     * 배치 한 번에 들어간다.
     */
    suspend fun replaceSegmentsOfDay(
        familyId: String,
        childUid: String,
        dayKey: String,
        segments: List<SegmentDoc>,
    ) {
        val collection = childRef(familyId, childUid).collection("segments")
        val existing = collection.whereEqualTo("dayKey", dayKey).get().await()
        val batch = db.batch()
        existing.documents.forEach { batch.delete(it.reference) }
        segments.forEach { batch.set(collection.document(), it) }
        batch.commit().await()
    }

    /**
     * 보호자 화면이 그 날의 요약을 실시간 구독한다.
     *
     * [onError] 를 삼키면 PERMISSION_DENIED 나 리스너 끊김이 화면에 아무 흔적도 남기지
     * 않아 "그냥 비어 있는 하루"와 구분되지 않는다.
     */
    fun observeSegmentsOfDay(
        familyId: String,
        childUid: String,
        dayKey: String,
        onChange: (List<SegmentDoc>) -> Unit,
        onError: (Exception) -> Unit,
    ): ListenerRegistration =
        childRef(familyId, childUid).collection("segments")
            .whereEqualTo("dayKey", dayKey)
            .orderBy("startAt", Query.Direction.ASCENDING)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    Log.w(TAG, "observeSegmentsOfDay 실패: dayKey=$dayKey", error)
                    onError(error)
                    return@addSnapshotListener
                }
                onChange(snapshot?.documents?.mapNotNull { it.toObject(SegmentDoc::class.java) } ?: emptyList())
            }
}
```

> **Firestore 색인 주의:** `whereEqualTo("dayKey")` + `orderBy("startAt")` 조합과
> `whereGreaterThanOrEqualTo("at")` + `orderBy("at")` 조합은 복합 색인이 필요할 수 있다.
> 색인이 없으면 Firestore 가 예외 메시지에 **생성 링크를 담아** 돌려준다. 그 링크는
> logcat 으로만 보이므로, Step 8 확인 절차에 "logcat 에서 `FAILED_PRECONDITION` 과
> 색인 생성 URL 을 확인하라"를 반드시 적는다.

- [ ] **Step 6: `SegmentUploader`를 쓴다**

`child/SegmentUploader.kt`:

```kotlin
package com.kidcare.family.child

import android.util.Log
import com.kidcare.family.core.SegmentRepository
import com.kidcare.family.core.model.SegmentDoc
import com.kidcare.family.logic.SegmentBuilder
import java.time.Instant
import java.time.ZoneId

/**
 * 오늘치 위치 점을 읽어 구간으로 묶고 Firestore 에 반영한다.
 *
 * 위치 한 점이 올라갈 때마다 부르지 않는다 — 하루 점을 매번 다시 읽으면 Firestore
 * 읽기가 점 개수의 제곱으로 늘어난다. [TrackingService] 가 일정 간격으로만 부른다.
 */
class SegmentUploader(private val zone: ZoneId = ZoneId.systemDefault()) {

    suspend fun rebuildToday(familyId: String, childUid: String) {
        val now = System.currentTimeMillis()
        val dayStart = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
            .atStartOfDay(zone).toInstant().toEpochMilli()
        val dayEnd = dayStart + DAY_MILLIS
        val dayKey = SegmentRepository.dayKeyOf(now, zone)

        val points = SegmentRepository.pointsOfDay(familyId, childUid, dayStart, dayEnd)
        if (points.size < 2) {
            Log.d(TAG, "구간 계산 생략: 오늘 점이 ${points.size}개뿐이다")
            return
        }

        val docs = SegmentBuilder.build(points).map { segment ->
            SegmentDoc(
                type = segment.type.name,
                startAt = segment.startAt,
                endAt = segment.endAt,
                lat = segment.lat,
                lng = segment.lng,
                distanceMeters = segment.distanceMeters,
                pointCount = segment.pointCount,
                dayKey = dayKey,
            )
        }
        SegmentRepository.replaceSegmentsOfDay(familyId, childUid, dayKey, docs)
        Log.i(TAG, "구간 ${docs.size}개 반영 완료: dayKey=$dayKey 점 ${points.size}개")
    }

    private companion object {
        const val TAG = "SegmentUploader"
        const val DAY_MILLIS = 24 * 60 * 60 * 1000L
    }
}
```

- [ ] **Step 7: `TrackingService`가 주기적으로 재계산하게 한다**

`child/TrackingService.kt`에 필드와 호출을 더한다. 업로드가 성공한 뒤에만, 그리고 **10분에 한 번만** 재계산한다.

```kotlin
    private val segmentUploader = SegmentUploader()
    private var lastSegmentRebuildAt = 0L
```

업로드 성공 처리 블록(`lastUploaded = fix` 뒤)에 이어 붙인다:

```kotlin
                // 구간 재계산은 하루치 점을 다시 읽는 작업이라 점이 올라갈 때마다 하면
                // 읽기 사용량이 점 개수의 제곱으로 늘어난다. 10분에 한 번이면 화면이
                // 충분히 최신이면서 비용은 하루 100회 남짓으로 끝난다.
                val now = System.currentTimeMillis()
                if (now - lastSegmentRebuildAt >= SEGMENT_REBUILD_INTERVAL_MILLIS) {
                    lastSegmentRebuildAt = now
                    runCatching { segmentUploader.rebuildToday(familyId, childUid) }
                        .onFailure { e ->
                            if (e is kotlinx.coroutines.CancellationException) throw e
                            Log.w(TAG, "구간 재계산 실패", e)
                        }
                }
```

`companion object`에 상수를 더한다:

```kotlin
        private const val SEGMENT_REBUILD_INTERVAL_MILLIS = 10 * 60 * 1000L
```

> `runCatching`은 `CancellationException`을 삼키므로 `onFailure` 안에서 반드시 다시
> 던진다. 이 저장소가 같은 버그를 네 번 고쳤다.

- [ ] **Step 8: 빌드하고 확인 절차를 기록한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug :app:testDebugUnitTest
```

기대: 빌드 성공, 기존 테스트 전부 통과.

보고서에 사용자용 확인 절차를 적는다:
1. 아이 폰에 설치하고 20분 이상 켜 둔다(점이 최소 2개, 재계산 주기 10분을 넘겨야 한다)
2. Firebase 콘솔 → `families/{id}/children/{childUid}/segments` 에 문서가 생기는지 본다
3. 각 문서에 `type`, `startAt`, `endAt`, `dayKey`가 채워졌는지 본다
4. 안 생기면:
   ```bash
   adb logcat -s SegmentUploader:* SegmentRepository:* TrackingService:* FirebaseFirestore:*
   ```
   `FAILED_PRECONDITION`과 함께 **색인 생성 URL**이 나오면 그 링크를 눌러 색인을 만든다

- [ ] **Step 9: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "구간 업로드: 자녀 폰이 하루 요약을 계산해 올린다

보호자가 하루치 원시 점 수백 개를 매번 내려받지 않도록 자녀 폰에서 계산한다.
10분에 한 번만 재계산 — 점마다 하면 읽기가 점 개수의 제곱으로 늘어난다.
지금까지 항상 0으로 저장되던 PointDoc.speed 도 실제 값으로 채운다."
```

---

### Task 4: 머무른 곳에 이름 붙이기

`"37.5665, 126.9780에 1시간 30분"`은 사람이 읽을 수 없다. 카카오 로컬 REST API로 좌표를 주소로 바꿔 `"○○동 123-4"`처럼 보여준다.

**Files:**
- Create: `app/src/main/java/com/kidcare/family/child/PlaceNamer.kt`
- Modify: `app/build.gradle.kts` (`KAKAO_REST_KEY` BuildConfig 필드)
- Modify: `app/src/main/java/com/kidcare/family/child/SegmentUploader.kt` (이름 채우기)
- Modify: `docs/setup.md` (REST 키 발급 절차 추가)

**Interfaces:**
- Consumes: Task 3의 `SegmentDoc`, `SegmentUploader`
- Produces: `PlaceNamer.nameOf(lat: Double, lng: Double): String?` — suspend. 실패하거나 키가 없으면 null

- [ ] **Step 1: REST 키를 BuildConfig 로 흘린다**

`app/build.gradle.kts`의 `kakaoAppKey` 아래에 한 줄, `defaultConfig` 안에 한 줄 더한다.

```kotlin
val kakaoRestKey: String = localProps.getProperty("KAKAO_REST_KEY") ?: ""
```

```kotlin
        buildConfigField("String", "KAKAO_REST_KEY", "\"$kakaoRestKey\"")
```

- [ ] **Step 2: `docs/setup.md`에 절차를 덧붙인다**

기존 내용은 건드리지 않고 맨 아래에 붙인다.

```markdown
## 카카오 REST API 키 (머무른 곳 이름 표시용)

네이티브 앱 키를 받은 그 화면(`앱 설정 > 앱 키`)에 **REST API 키**가 같이 있다.
같이 복사해서 `local.properties` 에 한 줄 더 넣는다:

```properties
KAKAO_REST_KEY=여기에_REST_API_키
```

없어도 앱은 정상 동작한다 — 머무른 곳이 이름 없이 "머무른 곳"으로만 표시될 뿐이다.
이 키는 좌표를 주소로 바꾸는 데만 쓴다(카카오 로컬 `coord2address`).
```

- [ ] **Step 3: `PlaceNamer`를 쓴다**

`child/PlaceNamer.kt`:

```kotlin
package com.kidcare.family.child

import android.util.Log
import com.kidcare.family.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * 좌표를 사람이 읽는 주소로 바꾼다. 카카오 로컬 REST API 의 coord2address 를 쓴다.
 *
 * HttpURLConnection 을 쓰는 이유: 요청이 이 한 종류뿐이라 HTTP 라이브러리를 하나 더
 * 들이는 값이 안 맞는다.
 *
 * 결과를 메모리에 캐시한다. 아이는 같은 곳(집·학교·학원)에 반복해서 머무르므로
 * 캐시가 없으면 같은 좌표를 하루에 수십 번 물어보게 된다. 좌표는 소수점 4자리
 * (약 11m)로 뭉쳐서 키를 만든다 — 그보다 정밀하게 나눠봐야 같은 건물이다.
 */
class PlaceNamer {

    private val cache = mutableMapOf<String, String>()

    /** 이름을 못 얻으면 null. 키가 없거나 네트워크가 안 되면 조용히 null 이다. */
    suspend fun nameOf(lat: Double, lng: Double): String? {
        if (BuildConfig.KAKAO_REST_KEY.isEmpty()) return null

        val key = "%.4f,%.4f".format(lat, lng)
        cache[key]?.let { return it }

        val name = withContext(Dispatchers.IO) { request(lat, lng) } ?: return null
        cache[key] = name
        return name
    }

    private fun request(lat: Double, lng: Double): String? {
        var connection: HttpURLConnection? = null
        return try {
            val url = URL("$ENDPOINT?x=$lng&y=$lat")
            connection = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                setRequestProperty("Authorization", "KakaoAK ${BuildConfig.KAKAO_REST_KEY}")
                connectTimeout = TIMEOUT_MILLIS
                readTimeout = TIMEOUT_MILLIS
            }
            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                Log.w(TAG, "역지오코딩 실패: HTTP ${connection.responseCode}")
                return null
            }
            parse(connection.inputStream.bufferedReader().use { it.readText() })
        } catch (e: Exception) {
            Log.w(TAG, "역지오코딩 요청 실패", e)
            null
        } finally {
            connection?.disconnect()
        }
    }

    /**
     * 도로명 주소가 있으면 그쪽이 사람에게 더 익숙하고, 없으면 지번 주소를 쓴다.
     * 시·도까지 전부 붙이면 화면에서 잘리므로 읍면동 이하만 남긴다.
     */
    private fun parse(body: String): String? {
        val documents = JSONObject(body).optJSONArray("documents") ?: return null
        if (documents.length() == 0) return null
        val first = documents.optJSONObject(0) ?: return null

        first.optJSONObject("road_address")?.let { road ->
            val name = road.optString("building_name")
            if (name.isNotEmpty()) return name
            val region = road.optString("region_3depth_name")
            val main = road.optString("road_name")
            if (region.isNotEmpty() && main.isNotEmpty()) return "$region $main"
        }
        first.optJSONObject("address")?.let { address ->
            val region = address.optString("region_3depth_name")
            val bunji = address.optString("main_address_no")
            if (region.isNotEmpty()) return if (bunji.isNotEmpty()) "$region $bunji" else region
        }
        return null
    }

    private companion object {
        const val TAG = "PlaceNamer"
        const val ENDPOINT = "https://dapi.kakao.com/v2/local/geo/coord2address.json"
        const val TIMEOUT_MILLIS = 5000
    }
}
```

- [ ] **Step 4: `SegmentUploader`가 머무름에만 이름을 붙이게 한다**

`SegmentUploader`에 필드를 더하고, `docs` 생성부를 고친다.

```kotlin
class SegmentUploader(
    private val zone: ZoneId = ZoneId.systemDefault(),
    private val placeNamer: PlaceNamer = PlaceNamer(),
) {
```

```kotlin
        val docs = SegmentBuilder.build(points).map { segment ->
            // 이동 구간에는 이름을 붙이지 않는다. 이동은 "어디서 어디로"가 앞뒤 머무름
            // 이름으로 이미 드러나고, 이동 중 좌표 하나를 주소로 바꿔봐야 지나가던
            // 길 이름이라 의미가 없다.
            val placeName = if (segment.type == SegmentType.STAY) {
                placeNamer.nameOf(segment.lat, segment.lng).orEmpty()
            } else {
                ""
            }
            SegmentDoc(
                type = segment.type.name,
                startAt = segment.startAt,
                endAt = segment.endAt,
                lat = segment.lat,
                lng = segment.lng,
                distanceMeters = segment.distanceMeters,
                pointCount = segment.pointCount,
                placeName = placeName,
                dayKey = dayKey,
            )
        }
```

`map` 안에서 suspend 함수를 부르므로 `map`을 그대로 쓸 수 없다. `buildList` + `for` 로 바꾸거나 `map`을 유지하려면 바깥이 suspend 여야 한다 — `rebuildToday`가 suspend 이므로 `map` 안의 람다는 suspend 가 아니다. **`for` 루프로 바꿔 쓴다:**

```kotlin
        val docs = buildList {
            for (segment in SegmentBuilder.build(points)) {
                val placeName = if (segment.type == SegmentType.STAY) {
                    placeNamer.nameOf(segment.lat, segment.lng).orEmpty()
                } else {
                    ""
                }
                add(
                    SegmentDoc(
                        type = segment.type.name,
                        startAt = segment.startAt,
                        endAt = segment.endAt,
                        lat = segment.lat,
                        lng = segment.lng,
                        distanceMeters = segment.distanceMeters,
                        pointCount = segment.pointCount,
                        placeName = placeName,
                        dayKey = dayKey,
                    )
                )
            }
        }
```

`import com.kidcare.family.logic.SegmentType` 를 추가한다.

- [ ] **Step 5: 빌드하고 확인한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug :app:testDebugUnitTest
```

기대: 빌드 성공, 테스트 전부 통과.

**REST 키가 없는 경로를 반드시 확인한다** — `local.properties`에 `KAKAO_REST_KEY`가 없는 상태로 빌드해서 `nameOf`가 즉시 null 을 돌려주고 앱이 죽지 않는지 본다. 지금 이 기계에는 키가 없으므로 이게 기본 상태다.

- [ ] **Step 6: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "장소 이름: 카카오 로컬 API 로 머무른 곳 주소 표시

좌표만 보여주면 사람이 읽을 수 없다. 같은 곳에 반복해서 머무르므로 결과를
11m 단위로 뭉쳐 캐시한다. REST 키가 없으면 조용히 이름 없이 동작한다."
```

---

### Task 5: 보호자 폰 타임라인과 날짜 이동

지도 아래에 하루 요약을 목록으로 깔고, 날짜를 앞뒤로 넘길 수 있게 한다.

**Files:**
- Create: `app/src/main/java/com/kidcare/family/logic/DayPicker.kt`
- Create: `app/src/test/java/com/kidcare/family/logic/DayPickerTest.kt`
- Create: `app/src/main/java/com/kidcare/family/guardian/TimelineAdapter.kt`
- Create: `app/src/main/res/layout/item_timeline.xml`
- Modify: `app/src/main/res/layout/fragment_map_timeline.xml`
- Modify: `app/src/main/java/com/kidcare/family/guardian/MapTimelineFragment.kt`
- Modify: `app/src/main/res/values/strings.xml`

**Interfaces:**
- Consumes: `SegmentRepository.observeSegmentsOfDay`, `SegmentRepository.dayKeyOf` (Task 3), `SegmentSummarizer` (Task 2), `SegmentDoc` (Task 3)
- Produces:
  - `DayPicker.todayKey(zone: ZoneId, nowMillis: Long): String`
  - `DayPicker.shift(dayKey: String, days: Long): String`
  - `DayPicker.isFuture(dayKey: String, zone: ZoneId, nowMillis: Long): Boolean`
  - `DayPicker.headerText(dayKey: String, zone: ZoneId, nowMillis: Long): String` — `"오늘"` / `"어제"` / `"8월 5일 (수)"`
  - `TimelineAdapter(onRowClick: (SegmentDoc) -> Unit)` with `submit(list: List<SegmentDoc>)`

- [ ] **Step 1: `DayPicker` 테스트를 쓴다**

`app/src/test/java/com/kidcare/family/logic/DayPickerTest.kt`:

```kotlin
package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId

class DayPickerTest {

    private val seoul: ZoneId = ZoneId.of("Asia/Seoul")

    /** 2026-08-07 14:00 KST */
    private val now = java.time.LocalDateTime.of(2026, 8, 7, 14, 0)
        .atZone(seoul).toInstant().toEpochMilli()

    @Test
    fun `오늘 키는 기기 시간대 기준이다`() {
        assertEquals("2026-08-07", DayPicker.todayKey(seoul, now))
    }

    @Test
    fun `시간대가 다르면 날짜가 달라질 수 있다`() {
        // 서울 8월 7일 14:00 은 UTC 로 8월 7일 05:00 — 같은 날이지만,
        // 서울 8월 7일 08:00 은 UTC 로 8월 6일 23:00 이다.
        val earlyMorning = java.time.LocalDateTime.of(2026, 8, 7, 8, 0)
            .atZone(seoul).toInstant().toEpochMilli()
        assertEquals("2026-08-07", DayPicker.todayKey(seoul, earlyMorning))
        assertEquals("2026-08-06", DayPicker.todayKey(ZoneId.of("UTC"), earlyMorning))
    }

    @Test
    fun `하루 앞뒤로 옮긴다`() {
        assertEquals("2026-08-06", DayPicker.shift("2026-08-07", -1))
        assertEquals("2026-08-08", DayPicker.shift("2026-08-07", 1))
    }

    @Test
    fun `월과 해의 경계를 넘는다`() {
        assertEquals("2026-07-31", DayPicker.shift("2026-08-01", -1))
        assertEquals("2027-01-01", DayPicker.shift("2026-12-31", 1))
    }

    @Test
    fun `윤년 2월을 정확히 넘는다`() {
        // 2028년은 윤년이다.
        assertEquals("2028-02-29", DayPicker.shift("2028-02-28", 1))
        assertEquals("2028-03-01", DayPicker.shift("2028-02-29", 1))
    }

    @Test
    fun `내일은 미래다`() {
        assertTrue(DayPicker.isFuture("2026-08-08", seoul, now))
        assertFalse(DayPicker.isFuture("2026-08-07", seoul, now))
        assertFalse(DayPicker.isFuture("2026-08-06", seoul, now))
    }

    @Test
    fun `오늘과 어제는 이름으로 부른다`() {
        assertEquals("오늘", DayPicker.headerText("2026-08-07", seoul, now))
        assertEquals("어제", DayPicker.headerText("2026-08-06", seoul, now))
    }

    @Test
    fun `그 이전은 날짜와 요일로 쓴다`() {
        // 2026-08-05 는 수요일이다.
        assertEquals("8월 5일 (수)", DayPicker.headerText("2026-08-05", seoul, now))
    }
}
```

- [ ] **Step 2: 테스트를 돌려 실패를 확인한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:testDebugUnitTest --tests "*DayPickerTest*"
```

기대: 컴파일 실패 — `Unresolved reference: DayPicker`

- [ ] **Step 3: `DayPicker`를 쓴다**

`app/src/main/java/com/kidcare/family/logic/DayPicker.kt`:

```kotlin
package com.kidcare.family.logic

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * 타임라인 화면의 "며칠치를 보고 있는가"를 다룬다.
 *
 * 날짜를 밀리초가 아니라 "2026-08-07" 문자열로 다루는 이유: Firestore 의 segments
 * 문서가 같은 형식의 dayKey 필드를 갖고 있어 그대로 쿼리 조건이 되고, 자정 경계를
 * 밀리초로 계산하다 시간대·서머타임에 어긋나는 실수를 피할 수 있다.
 *
 * 안드로이드 API 에 의존하지 않는다. JVM 단위 테스트 대상.
 */
object DayPicker {

    private val formatter: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
    private val weekdayNames = listOf("월", "화", "수", "목", "금", "토", "일")

    fun todayKey(zone: ZoneId, nowMillis: Long): String =
        Instant.ofEpochMilli(nowMillis).atZone(zone).toLocalDate().format(formatter)

    fun shift(dayKey: String, days: Long): String =
        LocalDate.parse(dayKey, formatter).plusDays(days).format(formatter)

    fun isFuture(dayKey: String, zone: ZoneId, nowMillis: Long): Boolean =
        LocalDate.parse(dayKey, formatter)
            .isAfter(Instant.ofEpochMilli(nowMillis).atZone(zone).toLocalDate())

    /** "오늘" / "어제" / "8월 5일 (수)". 최근 이틀은 날짜보다 이름이 빨리 읽힌다. */
    fun headerText(dayKey: String, zone: ZoneId, nowMillis: Long): String {
        val date = LocalDate.parse(dayKey, formatter)
        val today = Instant.ofEpochMilli(nowMillis).atZone(zone).toLocalDate()
        return when (date) {
            today -> "오늘"
            today.minusDays(1) -> "어제"
            else -> "${date.monthValue}월 ${date.dayOfMonth}일 (${weekdayNames[date.dayOfWeek.value - 1]})"
        }
    }

    /** 그 날의 시작(포함)과 끝(제외) 밀리초. 지도가 그 날의 점만 그릴 때 쓴다. */
    fun rangeOf(dayKey: String, zone: ZoneId): LongRange {
        val date = LocalDate.parse(dayKey, formatter)
        val start = date.atStartOfDay(zone).toInstant().toEpochMilli()
        val end = date.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
        return start until end
    }
}
```

- [ ] **Step 4: 테스트를 돌려 통과를 확인한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:testDebugUnitTest --tests "*DayPickerTest*"
```

기대: `BUILD SUCCESSFUL`, 8개 통과.

- [ ] **Step 5: 타임라인 한 줄 레이아웃을 만든다**

`app/src/main/res/layout/item_timeline.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="horizontal"
    android:gravity="center_vertical"
    android:background="?attr/selectableItemBackground"
    android:paddingHorizontal="16dp"
    android:paddingVertical="12dp">

    <TextView
        android:id="@+id/icon_text"
        android:layout_width="32dp"
        android:layout_height="wrap_content"
        android:textSize="20sp"
        android:gravity="center" />

    <LinearLayout
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:layout_marginStart="12dp"
        android:orientation="vertical">

        <TextView
            android:id="@+id/title_text"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:maxLines="1"
            android:ellipsize="end"
            android:textAppearance="?attr/textAppearanceBodyLarge" />

        <TextView
            android:id="@+id/detail_text"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:textAppearance="?attr/textAppearanceBodySmall" />
    </LinearLayout>
</LinearLayout>
```

- [ ] **Step 6: `TimelineAdapter`를 쓴다**

`app/src/main/java/com/kidcare/family/guardian/TimelineAdapter.kt`:

```kotlin
package com.kidcare.family.guardian

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.kidcare.family.R
import com.kidcare.family.core.model.SegmentDoc
import com.kidcare.family.databinding.ItemTimelineBinding
import com.kidcare.family.logic.Segment
import com.kidcare.family.logic.SegmentSummarizer
import com.kidcare.family.logic.SegmentType
import java.time.ZoneId

/**
 * 하루 요약을 한 줄씩 보여준다. 누르면 지도가 그 지점으로 움직인다.
 *
 * 문구 조립은 strings.xml 의 서식 문자열이 하고, 여기서는 SegmentSummarizer 가 만든
 * 조각을 꽂아 넣기만 한다 — 문구를 고칠 때 코드를 건드리지 않게 하려는 것이다.
 */
class TimelineAdapter(
    private val zone: ZoneId,
    private val onRowClick: (SegmentDoc) -> Unit,
) : ListAdapter<SegmentDoc, TimelineAdapter.Holder>(Diff) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) = Holder(
        ItemTimelineBinding.inflate(LayoutInflater.from(parent.context), parent, false)
    )

    override fun onBindViewHolder(holder: Holder, position: Int) = holder.bind(getItem(position))

    inner class Holder(private val binding: ItemTimelineBinding) :
        RecyclerView.ViewHolder(binding.root) {

        fun bind(doc: SegmentDoc) {
            val context = binding.root.context
            val stay = doc.type == SegmentType.STAY.name
            // SegmentSummarizer 는 logic/Segment 를 받으므로 문서를 값 객체로 옮겨 담는다.
            val segment = Segment(
                type = if (stay) SegmentType.STAY else SegmentType.MOVE,
                startAt = doc.startAt, endAt = doc.endAt,
                lat = doc.lat, lng = doc.lng,
                distanceMeters = doc.distanceMeters, pointCount = doc.pointCount,
            )

            binding.iconText.text = context.getString(
                if (stay) R.string.timeline_icon_stay else R.string.timeline_icon_move
            )
            binding.titleText.text = if (stay) {
                doc.placeName.ifEmpty { context.getString(R.string.timeline_unknown_place) }
            } else {
                context.getString(
                    R.string.timeline_move_title,
                    SegmentSummarizer.distanceText(doc.distanceMeters),
                )
            }
            binding.detailText.text = context.getString(
                R.string.timeline_detail,
                SegmentSummarizer.timeRange(segment, zone),
                SegmentSummarizer.durationText(doc.endAt - doc.startAt),
            )
            binding.root.setOnClickListener { onRowClick(doc) }
        }
    }

    private object Diff : DiffUtil.ItemCallback<SegmentDoc>() {
        override fun areItemsTheSame(old: SegmentDoc, new: SegmentDoc) =
            old.startAt == new.startAt && old.type == new.type
        override fun areContentsTheSame(old: SegmentDoc, new: SegmentDoc) = old == new
    }
}
```

`strings.xml`에 추가한다:

```xml
    <string name="timeline_icon_stay">📍</string>
    <string name="timeline_icon_move">🚶</string>
    <string name="timeline_unknown_place">머무른 곳</string>
    <string name="timeline_move_title">이동 %1$s</string>
    <string name="timeline_detail">%1$s · %2$s</string>
    <string name="timeline_empty">이 날은 기록이 없어요</string>
    <string name="day_prev">이전 날</string>
    <string name="day_next">다음 날</string>
```

- [ ] **Step 7: 화면 레이아웃에 날짜 바와 목록을 넣는다**

`res/layout/fragment_map_timeline.xml`을 고친다. 지도는 위 절반, 타임라인은 아래 절반으로 나눈다.

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical">

    <FrameLayout
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1">

        <com.kakao.vectormap.MapView
            android:id="@+id/map_view"
            android:layout_width="match_parent"
            android:layout_height="match_parent" />

        <com.google.android.material.card.MaterialCardView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_gravity="top"
            android:layout_margin="12dp"
            app:cardCornerRadius="16dp">

            <TextView
                android:id="@+id/status_bar"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:padding="16dp"
                android:textAppearance="?attr/textAppearanceBodyLarge" />
        </com.google.android.material.card.MaterialCardView>

        <TextView
            android:id="@+id/no_key_notice"
            android:layout_width="match_parent"
            android:layout_height="match_parent"
            android:background="?attr/colorSurface"
            android:gravity="center"
            android:padding="32dp"
            android:text="@string/map_no_key"
            android:visibility="gone" />
    </FrameLayout>

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:gravity="center_vertical"
        android:paddingHorizontal="8dp">

        <com.google.android.material.button.MaterialButton
            android:id="@+id/prev_day_button"
            style="@style/Widget.Material3.Button.TextButton"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="@string/day_prev" />

        <TextView
            android:id="@+id/day_header"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:gravity="center"
            android:textAppearance="?attr/textAppearanceTitleMedium" />

        <com.google.android.material.button.MaterialButton
            android:id="@+id/next_day_button"
            style="@style/Widget.Material3.Button.TextButton"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="@string/day_next" />
    </LinearLayout>

    <FrameLayout
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1">

        <androidx.recyclerview.widget.RecyclerView
            android:id="@+id/timeline_list"
            android:layout_width="match_parent"
            android:layout_height="match_parent"
            android:clipToPadding="false"
            android:paddingBottom="8dp" />

        <TextView
            android:id="@+id/timeline_empty"
            android:layout_width="match_parent"
            android:layout_height="match_parent"
            android:gravity="center"
            android:text="@string/timeline_empty"
            android:textAppearance="?attr/textAppearanceBodyMedium"
            android:visibility="gone" />
    </FrameLayout>
</LinearLayout>
```

`app/build.gradle.kts`의 `dependencies`에 RecyclerView 를 더한다. `libs.versions.toml`에도 항목을 추가한다.

`gradle/libs.versions.toml`:

```toml
recyclerview = "1.4.0"
```

```toml
androidx-recyclerview = { group = "androidx.recyclerview", name = "recyclerview", version.ref = "recyclerview" }
```

`app/build.gradle.kts`:

```kotlin
    implementation(libs.androidx.recyclerview)
```

> **버전 확인:** `1.4.0`은 이 계획을 쓴 시점의 안정판이다. 빌드가 해석 실패하면
> `https://dl.google.com/dl/android/maven2/androidx/recyclerview/recyclerview/maven-metadata.xml`
> 에서 최신 안정판(알파·베타·RC 제외)을 확인해 쓴다.

- [ ] **Step 8: `MapTimelineFragment`에 날짜 상태와 목록을 붙인다**

기존 구조(빈 앱키 가드, `pendingStatus`, 리스너 정리)를 **그대로 유지하면서** 다음을 더한다.

```kotlin
    private val zone: ZoneId = ZoneId.systemDefault()
    private var dayKey: String = DayPicker.todayKey(zone, System.currentTimeMillis())
    private var segmentListener: ListenerRegistration? = null
    private var childUid: String? = null
    private lateinit var timelineAdapter: TimelineAdapter
```

`onViewCreated`에서:

```kotlin
        timelineAdapter = TimelineAdapter(zone) { doc -> focusOn(doc.lat, doc.lng) }
        binding.timelineList.layoutManager = LinearLayoutManager(requireContext())
        binding.timelineList.adapter = timelineAdapter

        binding.prevDayButton.setOnClickListener { changeDay(-1) }
        binding.nextDayButton.setOnClickListener { changeDay(1) }
        renderDayHeader()
```

새 메서드들:

```kotlin
    private fun changeDay(days: Long) {
        val candidate = DayPicker.shift(dayKey, days)
        // 미래 날짜는 볼 것이 없다. 버튼을 눌러도 아무 일이 없으면 고장으로 보이므로
        // 아예 비활성으로 두고, 여기서는 방어만 한다.
        if (DayPicker.isFuture(candidate, zone, System.currentTimeMillis())) return
        dayKey = candidate
        renderDayHeader()
        subscribeSegments()
    }

    private fun renderDayHeader() {
        _binding ?: return
        binding.dayHeader.text = DayPicker.headerText(dayKey, zone, System.currentTimeMillis())
        binding.nextDayButton.isEnabled =
            !DayPicker.isFuture(DayPicker.shift(dayKey, 1), zone, System.currentTimeMillis())
    }

    private fun subscribeSegments() {
        segmentListener?.remove()
        segmentListener = null
        val familyId = RoleStore(requireContext()).familyId ?: return
        val uid = childUid ?: return
        segmentListener = SegmentRepository.observeSegmentsOfDay(
            familyId = familyId,
            childUid = uid,
            dayKey = dayKey,
            onChange = { docs -> renderTimeline(docs) },
            onError = { e ->
                _binding?.statusBar?.text = getString(R.string.map_error, e.message ?: "")
            },
        )
    }

    private fun renderTimeline(docs: List<SegmentDoc>) {
        _binding ?: return
        timelineAdapter.submitList(docs)
        binding.timelineEmpty.visibility = if (docs.isEmpty()) View.VISIBLE else View.GONE
        drawRoute(docs)          // Task 6 에서 채운다. 지금은 빈 함수로 둔다.
    }

    private fun focusOn(lat: Double, lng: Double) {
        val map = kakaoMap ?: return
        map.moveCamera(CameraUpdateFactory.newCenterPosition(LatLng.from(lat, lng), 16))
    }

    /** Task 6 에서 경로선을 그린다. */
    private fun drawRoute(docs: List<SegmentDoc>) = Unit
```

`childUid`를 찾는 기존 코루틴에서 값을 필드에 저장하고 `subscribeSegments()`를 부른다.

`onDestroyView`에 한 줄 더한다:

```kotlin
        segmentListener?.remove()
        segmentListener = null
```

- [ ] **Step 9: 빌드하고 확인 절차를 기록한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug :app:testDebugUnitTest
```

보고서에 확인 절차를 적는다: 아이 폰을 20분 이상 켜 둔 뒤 부모 폰에서 타임라인에 줄이 나오는지, `이전 날`을 눌러 어제로 갔다가 돌아오는지, `다음 날`이 오늘에서 비활성인지, 줄을 누르면 지도가 그 지점으로 가는지.

- [ ] **Step 10: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "타임라인: 하루 요약 목록과 날짜 이동

날짜를 밀리초 대신 yyyy-MM-dd 문자열로 다룬다 — segments 의 dayKey 와 그대로
맞물리고 자정 경계를 밀리초로 계산하다 시간대에 어긋나는 실수를 피한다.
DayPicker 단위 테스트 8개."
```

---

### Task 6: 지도에 하루 경로 그리기

타임라인과 같은 하루를 지도 위에 선으로 그린다.

**Files:**
- Modify: `app/src/main/java/com/kidcare/family/guardian/MapTimelineFragment.kt`
- Modify: `app/src/main/res/values/strings.xml` (필요 시)

**Interfaces:**
- Consumes: Task 5의 `drawRoute(docs)` 자리, `kakaoMap` 필드
- Produces: 없음 (화면 동작)

- [ ] **Step 1: 카카오 RouteLine API 를 실제 aar 로 확인한다**

문서 기준 형태는 아래와 같으나 **직접 확인하고 쓴다.** Task 10(1~2단계)에서 `javap`로 실제 클래스를 확인하는 방법이 통했다.

```bash
find /c/Users/사용자/.gradle /c/gradle-home -name "android-2.14.1.aar" 2>/dev/null | head -1
```

찾은 aar 의 `classes.jar`를 풀어 `javap`로 아래를 확인한다:
- `com.kakao.vectormap.route.RouteLineStyle.from(float, int)`
- `com.kakao.vectormap.route.RouteLineStyles.from(RouteLineStyle)`
- `com.kakao.vectormap.route.RouteLineSegment.from(List<LatLng>, RouteLineStyles)`
- `com.kakao.vectormap.route.RouteLineOptions.from(RouteLineSegment)`
- `KakaoMap.getRouteLineManager()` → `.getLayer()` → `.addRouteLine(RouteLineOptions)` / `.removeAll()`

시그니처가 다르면 **실제 시그니처를 쓰고 보고서에 무엇이 달랐는지 적는다.** 추측해서 컴파일 안 되는 코드를 남기지 않는다.

- [ ] **Step 2: `drawRoute`를 구현한다**

Task 5에서 빈 함수로 둔 자리를 채운다.

```kotlin
    private var routeLine: RouteLine? = null

    /**
     * 하루 경로를 선으로 그린다.
     *
     * 구간 요약의 좌표만 잇는다 — 원시 점을 전부 내려받으면 하루 수백 개라 느리고,
     * 요약 좌표(머무름 중심 + 이동 끝점)만으로도 "어디서 어디로"는 충분히 보인다.
     * SegmentBuilder 가 이동 구간의 끝을 앞뒤 머무름과 이어붙이도록 만들어 놨기
     * 때문에 이 선은 끊기지 않는다.
     */
    private fun drawRoute(docs: List<SegmentDoc>) {
        val map = kakaoMap ?: return
        val layer = map.routeLineManager?.layer ?: return

        routeLine?.let { layer.remove(it) }
        routeLine = null

        val positions = docs.map { LatLng.from(it.lat, it.lng) }
        if (positions.size < 2) return

        val styles = RouteLineStyles.from(RouteLineStyle.from(14f, ROUTE_COLOR))
        val segment = RouteLineSegment.from(positions, styles)
        routeLine = layer.addRouteLine(RouteLineOptions.from(segment))
    }
```

`companion object`(없으면 만든다)에 색을 둔다:

```kotlin
        private const val ROUTE_COLOR = 0xFF3D6DF5.toInt()
```

`onDestroyView`에 정리를 더한다:

```kotlin
        routeLine = null
```

> `layer.remove(...)`의 정확한 메서드 이름도 Step 1 에서 확인한다. `removeAll()`만
> 있으면 그것을 쓰고, 그 경우 현재 위치 마커가 지워지지 않는지도 확인한다 —
> 마커는 `labelManager`, 경로선은 `routeLineManager`로 서로 다른 레이어다.

- [ ] **Step 3: 빈 앱키 경로가 여전히 안전한지 확인한다**

`drawRoute`는 `kakaoMap ?: return`으로 시작하므로, 앱키가 없어 지도가 초기화되지 않은 상태에서도 `renderTimeline`이 이걸 불러도 아무 일이 없어야 한다. **이 기계에는 앱키가 없으므로 이게 기본 상태다.** 빌드 후 이 경로를 눈으로 확인하고 보고서에 적는다.

- [ ] **Step 4: 빌드**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug :app:testDebugUnitTest
```

- [ ] **Step 5: 커밋**

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "경로선: 하루 이동을 지도에 선으로 표시

원시 점 대신 구간 요약 좌표만 잇는다. SegmentBuilder 가 이동 구간의 끝을
앞뒤 머무름과 이어붙이므로 선이 끊기지 않는다."
```

---

### Task 7: 이동·정지에 따라 수집 주기를 바꾼다

1~2단계는 1분 고정이었다. 설계서 §4.1대로 정지 중에는 5분, 이동 중에는 1분으로 바꿔 배터리를 아낀다.

> 1~2단계에서 일부러 미룬 항목이다. 위치가 안 올라올 때 원인이 수집인지 업로드인지
> 가려낼 수 있어야 했기 때문이다. 이제 업로드 경로가 검증됐으니 붙인다.

**Files:**
- Modify: `app/src/main/java/com/kidcare/family/child/LocationCollector.kt`
- Modify: `app/src/main/AndroidManifest.xml` (`ACTIVITY_RECOGNITION` 권한)
- Modify: `app/src/main/java/com/kidcare/family/onboarding/PermissionStep.kt` (단계 추가)
- Modify: `app/src/main/java/com/kidcare/family/onboarding/PermissionActivity.kt` (요청 분기)
- Modify: `app/src/main/res/values/strings.xml`

**Interfaces:**
- Consumes: `LocationCollector.start(onFix)` (1~2단계), `PermissionStep` (1~2단계)
- Produces: `PermissionStep.ACTIVITY_RECOGNITION` 항목 추가

- [ ] **Step 1: 권한을 선언하고 온보딩에 단계를 더한다**

`AndroidManifest.xml`의 권한 목록에 한 줄:

```xml
    <uses-permission android:name="android.permission.ACTIVITY_RECOGNITION" />
```

`PermissionStep.kt`에 항목을 더한다. **`BATTERY_UNRESTRICTED` 뒤에 놓는다** — 위치가 없으면 활동 인식은 의미가 없고, 이 권한은 거부돼도 앱이 1분 고정으로 계속 동작한다.

```kotlin
    ACTIVITY_RECOGNITION(R.string.perm_activity_title, R.string.perm_activity_reason) {
        override fun isGranted(context: Context): Boolean =
            // API 29 부터 런타임 권한이다. 그 아래에서는 선언만으로 쓸 수 있다.
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) true
            else ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACTIVITY_RECOGNITION
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
    };
```

`PermissionActivity.ask()`의 `when`에 분기를 더한다:

```kotlin
            PermissionStep.ACTIVITY_RECOGNITION ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    requestPermission.launch(Manifest.permission.ACTIVITY_RECOGNITION)
                }
```

`strings.xml`:

```xml
    <string name="perm_activity_title">움직임 감지</string>
    <string name="perm_activity_reason">걷고 있는지 가만히 있는지 알면, 가만히 있을 때는 위치를 덜 자주 확인해서 배터리를 아낄 수 있어요.</string>
```

- [ ] **Step 2: `LocationCollector`가 주기를 바꾸게 한다**

```kotlin
package com.kidcare.family.child

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.util.Log
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionRequest
import com.google.android.gms.location.DetectedActivity
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.kidcare.family.logic.Fix
```

핵심 변경만 적는다. 기존 `start`/`stop` 구조는 유지한다.

```kotlin
    /** 정지 중 주기. 설계서 §4.1 */
    private val stillIntervalMillis = 5 * 60_000L
    /** 이동 중 주기. */
    private val movingIntervalMillis = 60_000L

    private var moving = true      // 처음에는 이동 중으로 본다 — 첫 위치를 빨리 잡아야 한다
    private var onFixCallback: ((Fix) -> Unit)? = null

    @SuppressLint("MissingPermission")
    fun start(onFix: (Fix) -> Unit) {
        onFixCallback = onFix
        requestUpdates()
    }

    /**
     * 주기를 바꿀 때는 기존 요청을 지우고 다시 건다. FusedLocationProvider 는
     * 같은 콜백으로 두 번 요청하면 나중 것이 앞의 것을 대체하지만, 명시적으로
     * 지우는 편이 어떤 주기가 살아있는지 헷갈리지 않는다.
     */
    @SuppressLint("MissingPermission")
    private fun requestUpdates() {
        val callback = onFixCallback ?: return
        stopUpdatesOnly()

        val interval = if (moving) movingIntervalMillis else stillIntervalMillis
        val priority = if (moving) Priority.PRIORITY_HIGH_ACCURACY else Priority.PRIORITY_BALANCED_POWER_ACCURACY
        Log.i(TAG, "수집 주기 변경: ${if (moving) "이동" else "정지"} ${interval / 1000}초")

        val request = LocationRequest.Builder(priority, interval)
            .setMinUpdateIntervalMillis(interval / 2)
            .build()

        val cb = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                val loc = result.lastLocation ?: return
                callback(Fix(loc.latitude, loc.longitude, loc.accuracy, loc.time, loc.speed))
            }
        }
        this.callback = cb
        client.requestLocationUpdates(request, cb, context.mainLooper)
    }

    /** 활동 인식이 상태 변화를 알려줄 때 부른다. 같은 상태면 아무 일도 하지 않는다. */
    fun onMovingChanged(nowMoving: Boolean) {
        if (moving == nowMoving) return
        moving = nowMoving
        requestUpdates()
    }
```

- [ ] **Step 3: 활동 인식 결과를 서비스가 받게 한다**

가장 단순하고 검증하기 쉬운 방식은 `TrackingService` 안에서 `ActivityRecognitionClient`의 전환(transition) 이벤트를 `PendingIntent`로 받아 `onMovingChanged`를 부르는 것이다. `BroadcastReceiver`를 하나 두고 매니페스트에 `exported="false"`로 등록한다.

권한이 없으면 등록을 건너뛰고 **이동 중(1분)으로 고정한다.** 배터리보다 위치 신뢰성이 먼저다.

구현 세부는 구현자가 정하되, 보고서에 다음을 반드시 적는다:
- 권한이 없을 때 어떤 주기로 동작하는지
- 전환 이벤트가 한 번도 안 올 때 무슨 일이 벌어지는지(기본값이 무엇인지)
- 서비스가 재시작될 때 등록이 중복되지 않는지

- [ ] **Step 4: 빌드하고 커밋한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug :app:testDebugUnitTest
```

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "수집 주기: 정지 5분 · 이동 1분으로 전환

활동 인식 권한이 없거나 전환 이벤트가 안 오면 이동(1분)으로 고정한다 —
배터리보다 위치 신뢰성이 먼저다."
```

---

### Task 8: 미해결 항목 정리

`docs/known-issues.md`의 2·3·4번을 처리한다. 1번(재설치 재연결)은 이 단계 범위 밖이다.

**Files:**
- Modify: `app/src/main/java/com/kidcare/family/core/FamilyRepository.kt` (서버 시각 기준 만료)
- Modify: `app/src/main/java/com/kidcare/family/guardian/MapTimelineFragment.kt` (자녀 uid 재구독)
- Create: `app/src/main/java/com/kidcare/family/child/PointsCleaner.kt`
- Modify: `app/src/main/java/com/kidcare/family/child/TrackingService.kt` (정리 호출)
- Modify: `docs/known-issues.md` (처리한 항목 반영)

**Interfaces:**
- Consumes: `FamilyRepository`, `SegmentRepository`, `TrackingService`
- Produces: `PointsCleaner.cleanOldPoints(familyId: String, childUid: String): Int` — suspend, 지운 개수 반환

- [ ] **Step 1: 초대 코드 만료를 서버 시각 기준으로 바꾼다**

문제: `inviteExpiresAt`을 보호자 폰 시계로 쓰는데 규칙은 서버 시각(`request.time`)으로 검사한다. 폰 시계가 느리면 만들자마자 죽은 코드가 되고, 재발급해도 같은 시계를 쓰므로 계속 죽은 코드만 나온다.

`FamilyRepository`에 서버 시각 보정을 넣는다. 가족 문서에 `FieldValue.serverTimestamp()`로 표식을 하나 쓰고 즉시 되읽어 **기기 시계와 서버 시계의 차이를 한 번 재서** 이후 계산에 더한다. 측정은 앱 실행당 한 번이면 충분하다.

```kotlin
    /**
     * 기기 시계와 서버 시계의 차이(밀리초). 서버가 앞서면 양수다.
     *
     * inviteExpiresAt 은 기기 시계로 쓰는데 보안 규칙은 request.time(서버 시각)으로
     * 검사한다. 부모 폰 시계가 15분 느리면 만들자마자 죽은 코드가 되고, 재발급해도
     * 같은 시계를 쓰므로 영원히 죽은 코드만 나온다 — 화면에는 "만료됨"만 뜨고
     * 원인은 아무 데도 안 남는다.
     */
    @Volatile private var serverOffsetMillis: Long? = null

    private suspend fun serverNow(): Long {
        serverOffsetMillis?.let { return System.currentTimeMillis() + it }
        val offset = runCatching { measureServerOffset() }.getOrElse { e ->
            if (e is kotlinx.coroutines.CancellationException) throw e
            Log.w(TAG, "서버 시각 보정 실패 — 기기 시계를 그대로 쓴다", e)
            0L
        }
        serverOffsetMillis = offset
        return System.currentTimeMillis() + offset
    }
```

`measureServerOffset()`의 구현 방식은 구현자가 정한다. 가장 단순한 것은 임시 문서에 `serverTimestamp()`를 쓰고 되읽어 비교한 뒤 지우는 것인데, **그 쓰기가 보안 규칙에 막히지 않는지 반드시 확인한다.** 규칙을 고쳐야 한다면 이 항목을 건너뛰고 보고서에 BLOCKED로 적는다 — 규칙은 이 단계에서 손대지 않는다.

`createFamily`와 `inviteCodeOf`의 `System.currentTimeMillis()` 호출을 `serverNow()`로 바꾼다. `joinFamily`의 만료 검사도 마찬가지다.

- [ ] **Step 2: 지도가 자녀 uid 를 계속 지켜보게 한다**

문제: `MapTimelineFragment`가 `onViewCreated`에서 `findChildUid`를 한 번만 부른다. 부모가 지도를 켜 둔 채 아이가 페어링을 끝내면 화면을 다시 만들기 전까지 "아직 아이 폰이 연결되지 않았어요"가 유지된다.

`FamilyRepository.observeChildJoined`(이미 있다)를 재사용해 구독으로 바꾼다. `onJoined`가 오면 `childUid`를 갱신하고 `observeChildStatus`와 `observeSegmentsOfDay`를 다시 건다. **리스너를 세 개 들고 있게 되므로 `onDestroyView`에서 전부 remove 한다.**

- [ ] **Step 3: 30일 지난 위치 점을 자녀 폰이 지운다**

문제: `dailyCleanup` Cloud Function 이 유일한 삭제 경로였는데 무료 요금제로 가면서 없어졌다. 지금은 `points/`가 무한히 쌓인다.

`child/PointsCleaner.kt`:

```kotlin
package com.kidcare.family.child

import android.util.Log
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import kotlinx.coroutines.tasks.await

/**
 * 30일 지난 위치 점을 지운다.
 *
 * 원래는 Cloud Function 이 매일 새벽에 하기로 했는데, 무료(Spark) 요금제로 가면서
 * Cloud Functions 를 쓰지 않게 됐다. 자녀 폰은 보안 규칙상 자기 데이터를 지울 수
 * 있으므로(children/{childUid}/{document=**} 쓰기 허용) 여기서 대신한다.
 *
 * 한 번에 다 지우지 않고 [BATCH_LIMIT] 개씩만 지운다. 오래 앱을 안 켰다가 수천 개가
 * 쌓였을 때 한 번에 지우려다 실패하면 영원히 못 지운다.
 */
class PointsCleaner {

    private val db: FirebaseFirestore get() = FirebaseFirestore.getInstance()

    /** 지운 개수를 돌려준다. */
    suspend fun cleanOldPoints(familyId: String, childUid: String): Int {
        val cutoff = System.currentTimeMillis() - RETENTION_MILLIS
        val stale = db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .collection("points")
            .whereLessThan("at", cutoff)
            .orderBy("at", Query.Direction.ASCENDING)
            .limit(BATCH_LIMIT)
            .get().await()

        if (stale.isEmpty) return 0

        val batch = db.batch()
        stale.documents.forEach { batch.delete(it.reference) }
        batch.commit().await()
        Log.i(TAG, "오래된 위치 점 ${stale.size()}개 삭제")
        return stale.size()
    }

    private companion object {
        const val TAG = "PointsCleaner"
        const val RETENTION_MILLIS = 30L * 24 * 60 * 60 * 1000L
        const val BATCH_LIMIT = 200L
    }
}
```

`TrackingService`가 하루에 한 번만 부르게 한다. 구간 재계산 옆에 같은 방식(마지막 실행 시각 비교)으로 붙이고, 상수는 `24 * 60 * 60 * 1000L`로 둔다.

- [ ] **Step 4: `docs/known-issues.md`를 갱신한다**

처리한 2·3·4번을 지우지 말고 **"3단계에서 처리함"으로 표시**하고 어떻게 고쳤는지 한 줄 남긴다. 1번(재설치 재연결)은 그대로 둔다. 새로 알게 된 것이 있으면 더한다.

- [ ] **Step 5: 빌드하고 커밋한다**

```bash
cd /c/workAndroid/KidCare && ./gradlew.bat :app:assembleDebug :app:testDebugUnitTest
```

```bash
cd /c/workAndroid/KidCare && git add -A && git commit -m "미해결 정리: 서버 시각 보정·자녀 uid 재구독·오래된 점 삭제

코드 만료를 서버 시계 기준으로 계산한다 — 부모 폰 시계가 느리면 만들자마자
죽은 코드가 나오는데 화면에는 '만료됨'만 뜨고 원인이 안 남았다.
Cloud Function 이 하기로 했던 30일 정리는 자녀 폰이 대신한다."
```

---

## Self-Review

**1. 스펙 커버리지 (3단계 범위)**

| 스펙 항목 | 담당 Task |
|---|---|
| 구간 묶기 규칙 (§4.2 반경 100m·5분·연속 2개·짧은 정지 흡수) | Task 1 |
| 정확도 100m 초과 제외 (§4.2) | Task 1 (Step 3의 `filter`) |
| 장소 이름 ②역지오코딩 ③알 수 없음 (§4.2) | Task 4 |
| 장소 이름 ①등록된 반경 이름 (§4.2) | **6단계.** `places/`가 그때 생긴다 |
| 자녀 폰에서 계산하는 이유 (§4.2) | Task 3 |
| 지도 선 + 타임라인 요약 (§3 화면) | Task 5, 6 |
| 날짜 이동 (§3 화면) | Task 5 |
| 수집 주기 정지 5분·이동 1분 (§4.1) | Task 7 |
| 30일 후 points 삭제 (§3 Cloud Functions ③) | Task 8 |
| 서버 시각 기준 만료 (known-issues 2) | Task 8 |
| 자녀 uid 재구독 (known-issues 3) | Task 8 |
| 재설치 재연결 (known-issues 1) | **범위 밖.** 설계 판단 필요 — 위 "다루지 않는 것" 참고 |

**2. 플레이스홀더 점검** — "TBD"·"적절히"·"위와 비슷하게" 없음. Task 7 Step 3과 Task 8 Step 1은 구현 방식을 구현자에게 맡기지만, **무엇을 결정해야 하고 무엇을 보고해야 하는지 명시**했다. Task 5 Step 8의 `drawRoute`는 빈 함수로 두고 Task 6이 채운다고 적었다.

**3. 타입 일관성**

- `Segment`/`SegmentType`(Task 1) → `SegmentSummarizer`(Task 2), `SegmentUploader`(Task 3), `TimelineAdapter`(Task 5) 전부 같은 이름 ✓
- `SegmentDoc`(Task 3) → `SegmentRepository`(Task 3), `TimelineAdapter`(Task 5), `drawRoute`(Task 6) ✓
- `Fix`에 `speed` 추가(Task 3)는 기본값이 있어 기존 `LocationFilterTest` 9개가 수정 없이 통과 ✓
- `dayKey` 형식 `"yyyy-MM-dd"`가 `SegmentRepository.dayKeyOf`(Task 3)와 `DayPicker`(Task 5)에서 동일 ✓
- `PermissionStep`에 항목 추가(Task 7)는 `firstMissing`이 `entries`를 순회하므로 자동 반영 ✓

**4. 발견해서 반영한 것**

- `SegmentUploader`의 `map` 안에서 suspend 함수(`placeNamer.nameOf`)를 부를 수 없다 — Task 4 Step 4에서 `for` 루프로 바꾸도록 명시했다.
- `whereEqualTo("dayKey") + orderBy("startAt")`은 Firestore 복합 색인이 필요할 수 있다. 색인 부재는 `FAILED_PRECONDITION`으로만 드러나고 화면에는 "기록이 없어요"로 보인다 — Task 3 Step 8 확인 절차에 logcat 확인을 넣었다.
- Task 8 Step 1의 서버 시각 측정이 보안 규칙에 막힐 가능성이 있다. 규칙은 이 단계에서 수정 금지이므로, 막히면 BLOCKED로 보고하도록 명시했다.
