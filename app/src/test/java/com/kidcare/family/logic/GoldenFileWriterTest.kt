package com.kidcare.family.logic

import org.junit.Test
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.PI
import kotlin.math.cos
import kotlin.random.Random

/**
 * JUnit 테스트 모양을 빌린 **생성기**다 — 검증이 아니라 골든 파일을 만드는 것이 목적이다.
 *
 * 왜 필요한가: Task 3~9 가 포팅한 여덟 로직은 각자의 포팅 테스트를 통과한다. 그런데 그
 * 테스트들은 "포팅한 사람이 떠올린 입력"만 확인한다 — 두 구현이 **생각하지 못한 입력**
 * 에서도 같은 답을 내는지는 아무도 안 봤다. 이 파일은 다섯 로직 각각에 대해 입력을
 * 프로그램으로 넓게(경계 주변은 촘촘히, 무작위는 고정 시드로) 만들고, 코틀린이 실제로
 * 계산한 결과를 함께 JSON 으로 적어 둔다. `ios/KidCareTests/GoldenComparisonTests.swift`
 * 가 같은 입력을 스위프트 구현에 먹여 같은 답이 나오는지 대조한다 — 코틀린이 정본이므로
 * 갈리면 스위프트를 고친다.
 *
 * `@Ignore` 를 붙이지 않는다 — 안드로이드 CI 에서 매번 같이 돌아 파일이 최신으로
 * 유지되는 편이 낫다. 대신 [writeIfChanged] 가 내용이 같으면 다시 쓰지 않아 git diff 를
 * 더럽히지 않는다.
 */
class GoldenFileWriterTest {

    // ------------------------------------------------------------------
    // 아주 작은 JSON 라이터. 의존성을 새로 더하지 않으려고 손으로 짠다 — 이 파일이
    // 다루는 값 모양(맵·리스트·문자열·숫자·불리언·null)이 단순해서 굳이 라이브러리가
    // 필요 없다.
    // ------------------------------------------------------------------

    private fun jsonString(s: String): String {
        val sb = StringBuilder("\"")
        for (c in s) {
            when (c) {
                '"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                else -> if (c.code < 0x20) sb.append("\\u%04x".format(c.code)) else sb.append(c)
            }
        }
        sb.append("\"")
        return sb.toString()
    }

    private fun toJson(value: Any?): String = when (value) {
        null -> "null"
        is String -> jsonString(value)
        is Boolean -> value.toString()
        is Int -> value.toString()
        is Long -> value.toString()
        is Float -> toJson(value.toDouble())
        // JSON 에는 무한대·NaN 리터럴이 없다(RFC 8259). 그대로 적으면 `Infinity` 라는 맨몸
        // 토큰이 나와 파일 전체가 파싱 불가가 된다 — 스위프트 `JSONSerialization` 이 실제로
        // 그렇게 죽었다. 문자열로 적고 읽는 쪽(`GoldenComparisonTests.double`)이 되돌린다.
        // `Fix.speedAccuracy` 의 기본값이 바로 이 경우다(무한대 = "모른다").
        is Double -> if (value.isFinite()) value.toString() else jsonString(value.toString())
        is Map<*, *> -> value.entries.joinToString(",", "{", "}") { (k, v) -> "${jsonString(k.toString())}:${toJson(v)}" }
        is List<*> -> value.joinToString(",", "[", "]") { toJson(it) }
        else -> error("골든 JSON 라이터가 ${value::class} 를 모른다")
    }

    /**
     * `ios/` 가 없으면(희소 체크아웃, ios 를 뺀 아카이브, 읽기전용 CI 마운트 등)
     * `null` 을 돌려준다 — 더 이상 여기서 죽지 않는다. 예전에는 이 함수가 없으면
     * `error()` 로 죽었는데, 그 호출이 `writeIfChanged(goldenFile(...), toJson(generate...()))`
     * 처럼 인자로 얽혀 있어서 `generate*()`(그 안의 `check()` 자체 검증 포함)가 아예
     * 실행되지 못한 채 안드로이드 전용 실행 환경이 죽는 원인이 됐다 — 지금은 각
     * `@Test` 가 `generate*()` 결과를 먼저 지역 변수로 평가한 다음에만 이 함수를
     * 부르므로, 생성·검증은 `ios/` 유무와 무관하게 항상 실행된다.
     */
    private fun repoRoot(): File? {
        var dir = File(System.getProperty("user.dir") ?: ".").absoluteFile
        while (true) {
            if (File(dir, "settings.gradle.kts").exists() && File(dir, "ios").isDirectory) return dir
            dir = dir.parentFile ?: return null
        }
    }

    /** 내용이 이미 같으면 다시 쓰지 않는다 — git diff 를 매 실행마다 더럽히지 않으려고. */
    private fun writeIfChanged(file: File, content: String) {
        file.parentFile?.mkdirs()
        if (file.exists() && file.readText() == content) return
        file.writeText(content)
    }

    /**
     * `content` 는 이미 다 계산된 값이어야 한다(호출부에서 `generate*()` 를 먼저 지역
     * 변수로 평가해 두는 이유). `ios/` 를 못 찾으면 파일 쓰기만 건너뛰고 로그를 남긴다 —
     * 생성·자체 검증은 이 함수 호출 전에 이미 끝나 있으므로 여기서는 안 죽는다.
     */
    private fun writeGoldenIfPresent(name: String, content: String) {
        val root = repoRoot()
        if (root == null) {
            println(
                "[GoldenFileWriterTest] ios/ 디렉터리를 못 찾아 golden/$name.json 쓰기를 건너뛴다" +
                    " (희소 체크아웃 · ios 를 뺀 아카이브 · 읽기전용 CI 마운트 등을 가정한다)." +
                    " 생성과 자체 검증(check)은 이미 정상적으로 끝났다.",
            )
            return
        }
        writeIfChanged(File(root, "ios/KidCareTests/golden/$name.json"), content)
    }

    // ==================================================================
    // 1. ScheduleResolver — 자정 넘김·겹침·우선순위·공휴일·여러 시간대
    // ==================================================================

    @Test
    fun `골든 - ScheduleResolver`() {
        val payload = linkedMapOf(
            "resolve" to generateScheduleResolver(),
            "overlaps" to generateScheduleResolverOverlaps(),
        )
        writeGoldenIfPresent("scheduleResolver", toJson(payload))
    }

    private fun generateScheduleResolver(): List<Map<String, Any?>> {
        val seoul = ZoneId.of("Asia/Seoul")
        val utc = ZoneId.of("UTC")
        val ny = ZoneId.of("America/New_York")

        val cases = mutableListOf<Map<String, Any?>>()

        fun ruleJson(r: ScheduleRule): Map<String, Any?> = linkedMapOf(
            "id" to r.id,
            "days" to r.days.sorted(),
            "startMinute" to r.startMinute,
            "endMinute" to r.endMinute,
            "mode" to r.mode,
            "enabled" to r.enabled,
            "priority" to r.priority,
        )

        fun addCase(rules: List<ScheduleRule>, atMillis: Long, zone: ZoneId, holidays: Set<LocalDate> = emptySet()) {
            val resolution = ScheduleResolver.resolveAt(rules, atMillis, zone, holidays)
            cases += linkedMapOf(
                "rules" to rules.map(::ruleJson),
                "atMillis" to atMillis,
                "zone" to zone.id,
                "holidays" to holidays.sorted().map { it.toString() },
                "mode" to resolution.mode,
                "nextBoundaryMillis" to resolution.nextBoundaryMillis,
            )
        }

        fun dayStart(date: LocalDate, zone: ZoneId): Long = date.atStartOfDay(zone).toInstant().toEpochMilli()

        // 어떤 경계(분 단위) 주변을 촘촘히 훑는 순간들. -1.5분, -1분, -1초, 0, +1초, +1분, +1.5분.
        val denseOffsets = listOf(-90_000L, -60_000L, -1_000L, 0L, 1_000L, 60_000L, 90_000L)
        fun boundaryMoments(date: LocalDate, zone: ZoneId, minute: Int): List<Long> {
            val base = dayStart(date, zone) + minute * 60_000L
            return denseOffsets.map { base + it }
        }

        // --- 시나리오 1: 자정 넘김 규칙(평일 22:00~07:00). 시작·끝 경계, 그리고 요일 밖(토요일). ---
        run {
            val rule = ScheduleRule("cross-midnight", setOf(1, 2, 3, 4, 5), 1320, 420, "SILENT", true, 1)
            val monday = LocalDate.of(2026, 1, 5) // 확인된 월요일
            boundaryMoments(monday, seoul, 1320).forEach { addCase(listOf(rule), it, seoul) }
            boundaryMoments(monday.plusDays(1), seoul, 420).forEach { addCase(listOf(rule), it, seoul) }
            boundaryMoments(monday.plusDays(5), seoul, 1320).forEach { addCase(listOf(rule), it, seoul) } // 토요일: 시작 안 함
        }

        // --- 시나리오 2: 맞닿은 두 규칙(08:00~12:00, 12:00~15:00). 경계에서 정확히 바뀌는지. ---
        run {
            val a = ScheduleRule("morning", setOf(1, 2, 3, 4, 5, 6, 7), 480, 720, "VIBRATE", true, 1)
            val b = ScheduleRule("noon", setOf(1, 2, 3, 4, 5, 6, 7), 720, 900, "SILENT", true, 1)
            val day = LocalDate.of(2026, 1, 5)
            boundaryMoments(day, seoul, 720).forEach { addCase(listOf(a, b), it, seoul) }
        }

        // --- 시나리오 3: 같은 우선순위로 겹치는 두 규칙. 나중에 시작한 쪽이 이겨야 한다. ---
        run {
            val a = ScheduleRule("early", setOf(1, 2, 3, 4, 5, 6, 7), 480, 900, "VIBRATE", true, 1)
            val b = ScheduleRule("late", setOf(1, 2, 3, 4, 5, 6, 7), 700, 1000, "SILENT", true, 1)
            val day = LocalDate.of(2026, 1, 5)
            val start = dayStart(day, seoul)
            listOf(
                start + 600 * 60_000L, // A만 활성
                start + 750 * 60_000L, // 둘 다 활성 → B(나중 시작)가 이겨야
                start + 950 * 60_000L, // B만 활성
            ).forEach { addCase(listOf(a, b), it, seoul) }
            boundaryMoments(day, seoul, 700).forEach { addCase(listOf(a, b), it, seoul) } // B 시작 경계
            boundaryMoments(day, seoul, 900).forEach { addCase(listOf(a, b), it, seoul) } // A 끝 경계
        }

        // --- 시나리오 4: 우선순위가 다르게 겹치는 두 규칙. 우선순위가 이겨야 한다. ---
        run {
            val low = ScheduleRule("low", setOf(1, 2, 3, 4, 5, 6, 7), 480, 900, "VIBRATE", true, 1)
            val high = ScheduleRule("high", setOf(1, 2, 3, 4, 5, 6, 7), 600, 700, "SILENT", true, 10)
            val day = LocalDate.of(2026, 1, 5)
            val start = dayStart(day, seoul)
            listOf(
                start + 500 * 60_000L, // low 만
                start + 650 * 60_000L, // 겹침 구간 — high(우선순위 큼)가 이겨야
                start + 850 * 60_000L, // low 만 (high 끝난 뒤)
            ).forEach { addCase(listOf(low, high), it, seoul) }
            boundaryMoments(day, seoul, 600).forEach { addCase(listOf(low, high), it, seoul) }
            boundaryMoments(day, seoul, 700).forEach { addCase(listOf(low, high), it, seoul) }
        }

        // --- 시나리오 5: 하루 종일 규칙(startMinute == endMinute). ---
        run {
            val allDay = ScheduleRule("all-day", setOf(1), 0, 0, "SILENT", true, 1)
            val monday = LocalDate.of(2026, 1, 5)
            val start = dayStart(monday, seoul)
            listOf(start, start + 12 * 3_600_000L, start + 23 * 3_600_000L + 59 * 60_000L)
                .forEach { addCase(listOf(allDay), it, seoul) }
            boundaryMoments(monday, seoul, 0).forEach { addCase(listOf(allDay), it, seoul) }
            boundaryMoments(monday.plusDays(1), seoul, 0).forEach { addCase(listOf(allDay), it, seoul) } // 하루 뒤 자정: 다음 발동은 다음주 월요일
        }

        // --- 시나리오 6: 꺼진 규칙은 절대 안 이긴다. ---
        run {
            val disabled = ScheduleRule("disabled", setOf(1, 2, 3, 4, 5, 6, 7), 0, 0, "SILENT", false, 100)
            val active = ScheduleRule("active", setOf(1, 2, 3, 4, 5, 6, 7), 480, 900, "VIBRATE", true, 1)
            val day = LocalDate.of(2026, 1, 5)
            val start = dayStart(day, seoul)
            listOf(start, start + 600 * 60_000L, start + 1200 * 60_000L).forEach { addCase(listOf(disabled, active), it, seoul) }
        }

        // --- 시나리오 7: 공휴일. 시작일이 공휴일이면 그 규칙은 시작하지 않는다(자정 넘김 포함). ---
        run {
            val rule = ScheduleRule("weekday-night", setOf(1, 2, 3, 4, 5), 1320, 420, "SILENT", true, 1)
            val monday = LocalDate.of(2026, 1, 5)
            val holidays = setOf(monday) // 월요일이 공휴일
            boundaryMoments(monday, seoul, 1320).forEach { addCase(listOf(rule), it, seoul, holidays) } // 시작 못함
            boundaryMoments(monday.plusDays(1), seoul, 420).forEach { addCase(listOf(rule), it, seoul, holidays) }
            // 일요일 밤 시작(일요일은 공휴일 아님) → 월요일 아침까지는 이어져야, 월요일이 공휴일이어도.
            val sunday = monday.minusDays(1)
            val sundayRule = ScheduleRule("weekend-incl-sunday", setOf(7, 1, 2, 3, 4, 5), 1320, 420, "SILENT", true, 1)
            boundaryMoments(sunday, seoul, 1320).forEach { addCase(listOf(sundayRule), it, seoul, holidays) }
        }

        // --- 시나리오 8: 여러 시간대(UTC, America/New_York)에서 자정 넘김 규칙을 반복. ---
        run {
            val rule = ScheduleRule("cross-midnight-tz", setOf(1, 2, 3, 4, 5), 1320, 420, "SILENT", true, 1)
            val monday = LocalDate.of(2026, 1, 5)
            for (zone in listOf(utc, ny)) {
                boundaryMoments(monday, zone, 1320).forEach { addCase(listOf(rule), it, zone) }
                boundaryMoments(monday.plusDays(1), zone, 420).forEach { addCase(listOf(rule), it, zone) }
            }
            // 서머타임이 걸리는 시기의 뉴욕(2026-03-08 이 미국 서머타임 시작일).
            val dstDay = LocalDate.of(2026, 3, 8)
            boundaryMoments(dstDay, ny, 1320).forEach { addCase(listOf(rule), it, ny) }
        }

        return cases
    }

    /**
     * `overlapsOf` — 저장 전 겹침 경고. `resolveAt` 과 같은 파일(같은 대상)의 다른 공개
     * 함수인데도 대조가 없었다: 맞닿음(겹침 아님)·부분 겹침·완전 포함(양방향)·자정을
     * 넘는 후보가 다음날 규칙과 겹치는 경우·같은 id 를 가진 목록 항목(제외돼야 함)·
     * 꺼진 규칙(후보 자신이든 비교 대상이든)을 스윕한다.
     */
    private fun generateScheduleResolverOverlaps(): List<Map<String, Any?>> {
        val cases = mutableListOf<Map<String, Any?>>()

        fun ruleJson(r: ScheduleRule): Map<String, Any?> = linkedMapOf(
            "id" to r.id,
            "days" to r.days.sorted(),
            "startMinute" to r.startMinute,
            "endMinute" to r.endMinute,
            "mode" to r.mode,
            "enabled" to r.enabled,
            "priority" to r.priority,
        )

        fun addCase(name: String, rules: List<ScheduleRule>, candidate: ScheduleRule) {
            val overlapping = ScheduleResolver.overlapsOf(rules, candidate)
            cases += linkedMapOf(
                "name" to name,
                "rules" to rules.map(::ruleJson),
                "candidate" to ruleJson(candidate),
                "overlappingIds" to overlapping.map { it.id }.sorted(),
            )
        }

        // --- 맞닿음은 겹침이 아니다(양쪽 모두). ---
        run {
            val candidate = ScheduleRule("cand", setOf(1), 480, 720, "SILENT", true, 1) // 08:00~12:00 월
            val abutAfter = ScheduleRule("abut-after", setOf(1), 720, 900, "SILENT", true, 1) // 12:00~15:00
            val abutBefore = ScheduleRule("abut-before", setOf(1), 300, 480, "SILENT", true, 1) // 05:00~08:00
            addCase("abutting_both_sides_no_overlap", listOf(abutAfter, abutBefore), candidate)
        }

        // --- 부분 겹침 / 완전 포함(양방향) / 다른 요일(겹침 아님)을 한 번에. ---
        run {
            val candidate = ScheduleRule("cand", setOf(1), 480, 720, "SILENT", true, 1) // 08:00~12:00 월
            val partial = ScheduleRule("partial", setOf(1), 600, 800, "SILENT", true, 1) // 10:00~13:20, 부분 겹침
            val containsCandidate = ScheduleRule("contains-candidate", setOf(1), 0, 1439, "SILENT", true, 1) // 후보를 통째로 포함
            val containedByCandidate = ScheduleRule("contained-by-candidate", setOf(1), 600, 650, "SILENT", true, 1) // 후보 안에 통째로 포함됨
            val differentDay = ScheduleRule("different-day", setOf(2), 480, 720, "SILENT", true, 1) // 시간은 같지만 화요일
            addCase(
                "partial_contains_contained_differentday",
                listOf(partial, containsCandidate, containedByCandidate, differentDay),
                candidate,
            )
        }

        // --- 같은 id 를 가진 목록 항목은 기하적으로 겹쳐도 제외된다(자기 자신이므로). ---
        run {
            val candidate = ScheduleRule("dup", setOf(1), 480, 720, "SILENT", true, 1)
            val sameIdOverlapping = ScheduleRule("dup", setOf(1), 500, 600, "SILENT", true, 1) // 겹치지만 id 가 후보와 같다
            val genuineOverlap = ScheduleRule("other", setOf(1), 500, 600, "SILENT", true, 1) // 겹치고 id 도 다르다
            addCase("same_id_excluded", listOf(sameIdOverlapping, genuineOverlap), candidate)
        }

        // --- 꺼진 규칙은 목록 쪽이면 기하적으로 겹쳐도 후보에서 빠진다. 후보 자신의
        // enabled 는 결과에 영향이 없어야 한다(늘 켜진 것으로 취급됨 — 저장 전 경고이므로). ---
        run {
            val disabledCandidate = ScheduleRule("cand-off", setOf(1), 480, 720, "SILENT", false, 1)
            val disabledOther = ScheduleRule("other-off", setOf(1), 500, 600, "SILENT", false, 1) // 겹치지만 꺼져 있다
            val enabledOther = ScheduleRule("other-on", setOf(1), 500, 600, "SILENT", true, 1) // 겹치고 켜져 있다
            addCase("disabled_candidate_and_disabled_other", listOf(disabledOther, enabledOther), disabledCandidate)
        }

        // --- 자정을 넘는 후보가 다음날 규칙과 겹친다. ---
        run {
            val candidate = ScheduleRule("night", setOf(1), 1320, 420, "SILENT", true, 1) // 월 22:00~화 07:00
            val nextDayMorning = ScheduleRule("tue-morning", setOf(2), 360, 540, "SILENT", true, 1) // 화 06:00~09:00, 겹침
            val nextDayNoOverlap = ScheduleRule("tue-late", setOf(2), 600, 700, "SILENT", true, 1) // 화 10:00~11:40, 안 겹침
            addCase("candidate_crosses_midnight_into_next_day", listOf(nextDayMorning, nextDayNoOverlap), candidate)
        }

        // --- 겹침이 전혀 없는 통제 사례. ---
        run {
            val candidate = ScheduleRule("lonely", setOf(1), 480, 720, "SILENT", true, 1)
            val farAway = ScheduleRule("far", setOf(1), 1000, 1100, "SILENT", true, 1)
            addCase("no_overlap_control", listOf(farAway), candidate)
        }

        return cases
    }

    // ==================================================================
    // 2. RoutePathRefiner — 튐 제거·평활·문턱값 경계
    // ==================================================================

    @Test
    fun `골든 - RoutePathRefiner`() {
        val payload = generateRoutePathRefiner()
        writeGoldenIfPresent("routePathRefiner", toJson(payload))
    }

    private val baseLat = 37.5665
    private val baseLng = 126.9780
    private val metersPerDegLat = 6_371_000.0 * PI / 180.0

    /** 평면 근사로 (동쪽, 북쪽) 오프셋 미터를 위경도로 바꾼다. 이 파일이 다루는 거리(최대
     * 수백 m)에서는 지구 곡률 오차가 1e-9 미만이라 무시해도 된다. */
    private fun offsetLatLng(base: Pair<Double, Double>, eastMeters: Double, northMeters: Double): Pair<Double, Double> {
        val dLat = northMeters / metersPerDegLat
        val dLng = eastMeters / (metersPerDegLat * cos(Math.toRadians(base.first)))
        return (base.first + dLat) to (base.second + dLng)
    }

    /**
     * A-B-C 세 변 길이(firstArm, secondArm, bridge)를 만족하는 평면 삼각형. C 는 A 의 정동쪽.
     *
     * 세 변이 삼각형 부등식을 어기면(가장 긴 변이 나머지 둘의 합보다 크거나 같으면) 실수
     * 해가 없다. `coerceAtLeast(0.0)` 로 조용히 0에 묶으면 "요청한 변 길이"가 아니라
     * **완전히 다른(대개 훨씬 긴) 변을 가진 일직선 배치**가 만들어지는데, 호출한 쪽은
     * 자기가 원한 경계값을 그대로 테스트하고 있다고 착각한다 — 실제로 팔 길이 25m 를
     * 요청했는데 95~100m 짜리 일직선이 나온 채 "25m 경계 테스트"라는 이름을 달고 있던
     * 회귀가 있었다. 예전 `parseDurationText`/`parseDistanceText`가 모르는 형식에 `error()`
     * 로 죽던 것과 같은 판단이다 — 불가능한 모양을 조용히 다른 모양으로 바꿔치기하지
     * 않는다.
     */
    private fun triangle(firstArm: Double, secondArm: Double, bridge: Double): Triple<Pair<Double, Double>, Pair<Double, Double>, Pair<Double, Double>> {
        val a = baseLat to baseLng
        val c = offsetLatLng(a, bridge, 0.0)
        val x = (firstArm * firstArm - secondArm * secondArm + bridge * bridge) / (2 * bridge)
        val ySquared = firstArm * firstArm - x * x
        if (ySquared < 0.0) {
            error(
                "triangle($firstArm, $secondArm, $bridge) 는 삼각형 부등식을 어긴다 " +
                    "(가장 긴 변이 나머지 둘의 합 이상이다) — 실수 해가 없는 모양을 요청했다.",
            )
        }
        val y = kotlin.math.sqrt(ySquared)
        val b = offsetLatLng(a, x, y)
        return Triple(a, b, c)
    }

    /**
     * "이름_boundary_값" 꼴 형제 케이스들이 정말 경계를 스윕하는지 마지막에 한 번
     * 못박는다. 같은 그룹(예: "spike_arm_boundary") 의 형제 케이스 두 개 이상이 있는데
     * 그 legs 출력이 전부 같다면, 그 그룹은 입력 기하가 잘못돼 경계 양쪽을 실제로는
     * 건드리지 못하는(그런데 이름은 경계 테스트인 척하는) 죽은 케이스다 — 지금 이
     * 파일에서 실제로 그런 사례(spike_arm_boundary, spike_ratio_boundary)가 있었다.
     * 조용히 통과하는 대신 생성 자체를 실패시킨다.
     */
    private fun validateBoundaryGroupsSweepSomething(cases: List<Map<String, Any?>>) {
        val boundaryNamePattern = Regex("^(.*_boundary)_[^_]+$")
        val groups = cases
            .mapNotNull { case ->
                val name = case["name"] as? String ?: return@mapNotNull null
                val group = boundaryNamePattern.find(name)?.groupValues?.get(1) ?: return@mapNotNull null
                group to case
            }
            .groupBy({ it.first }, { it.second })

        groups.forEach { (group, members) ->
            if (members.size < 2) return@forEach
            val distinctOutputs = members.map { toJson(it["legs"]) }.distinct()
            check(distinctOutputs.size >= 2) {
                "\"$group\" 형제 케이스 ${members.size}개가 전부 같은 결과를 낸다 " +
                    "— 경계를 못 건드리는 죽은 스윕이다. 입력 기하(삼각형 변 길이 등)를 다시 본다."
            }
        }
    }

    private fun fixJson(f: Fix): Map<String, Any?> = linkedMapOf(
        "lat" to f.lat, "lng" to f.lng, "accuracy" to f.accuracy.toDouble(), "at" to f.at, "speed" to f.speed.toDouble(),
    )

    private fun generateRoutePathRefiner(): List<Map<String, Any?>> {
        val cases = mutableListOf<Map<String, Any?>>()

        fun addCase(name: String, points: List<Fix>) {
            val legs = RoutePathRefiner.refine(points)
            cases += linkedMapOf(
                "name" to name,
                "points" to points.map(::fixJson),
                "legs" to legs.map { leg -> leg.points.map(::fixJson) },
            )
        }

        val t0 = 1_700_000_000_000L

        // --- 정확도 문턱(50m) 경계. accuracy=0 은 '모름'이라 항상 통과한다. ---
        run {
            val p0 = Fix(baseLat, baseLng, 49.9f, t0)
            val p1 = Fix(baseLat, baseLng, 50.0f, t0 + 30_000)
            val p2 = Fix(baseLat, baseLng, 50.1f, t0 + 60_000) // 이 점만 필터링돼 사라진다
            val p3 = Fix(baseLat, baseLng, 0f, t0 + 90_000)
            addCase("accuracy_boundary_50", listOf(p0, p1, p2, p3))
        }

        // --- 시간 공백 문턱(10분=600_000ms). 거리는 항상 150m 를 넘겨 시간만 갈린다. ---
        run {
            val (east, _) = offsetLatLng(baseLat to baseLng, 200.0, 0.0)
            val far = east to baseLng
            listOf(599_999L, 600_000L, 600_001L).forEach { elapsed ->
                val p0 = Fix(baseLat, baseLng, 10f, t0)
                val p1 = Fix(far.first, far.second, 10f, t0 + elapsed)
                addCase("gap_time_boundary_$elapsed", listOf(p0, p1))
            }
        }

        // --- 거리 공백 문턱(150m). 시간은 항상 10분을 넉넉히 넘겨(700s) 거리만 갈린다. ---
        run {
            listOf(149.9, 150.0, 150.1).forEach { meters ->
                val far = offsetLatLng(baseLat to baseLng, meters, 0.0)
                val p0 = Fix(baseLat, baseLng, 10f, t0)
                val p1 = Fix(far.first, far.second, 10f, t0 + 700_000L)
                addCase("gap_distance_boundary_${meters}", listOf(p0, p1))
            }
        }

        // --- 순간이동 문턱(55.6 m/s). 1초 사이 이동 거리로 속도를 정확히 맞춘다. ---
        run {
            listOf(55.5, 55.6, 55.7).forEach { speed ->
                val far = offsetLatLng(baseLat to baseLng, speed, 0.0) // 1초이므로 거리=속도
                val p0 = Fix(baseLat, baseLng, 10f, t0)
                val p1 = Fix(far.first, far.second, 10f, t0 + 1_000L)
                addCase("implied_speed_boundary_${speed}", listOf(p0, p1))
            }
        }

        // --- 튐(spike) 제거: 네 조건(시간폭·팔 길이·다리 길이·우회비) 각각의 경계. ---
        run {
            // 시간폭(20_000ms) 경계. 팔=40/40, 다리=5(안전).
            listOf(19_999L, 20_000L, 20_001L, 21_000L).forEach { span ->
                val (a, b, c) = triangle(40.0, 40.0, 5.0)
                val p0 = Fix(a.first, a.second, 10f, t0)
                val p1 = Fix(b.first, b.second, 10f, t0 + span / 2)
                val p2 = Fix(c.first, c.second, 10f, t0 + span)
                addCase("spike_span_boundary_$span", listOf(p0, p1, p2))
            }
            // 팔 길이(25m) 경계. 두 팔을 같이 스윕한다(값을 하나만 바꾸면서 secondArm=40 을
            // 고정하면 firstArm≈25, secondArm=40, bridge<=15 가 삼각형 부등식을 어겨(25+15<40)
            // triangle() 이 죽는다 — 40 을 고정한 채로는 애초에 이 경계를 만들 수 없다).
            // 두 팔이 같으면 다리=5(안전, 15 이하), 시간폭=5000(안전)로 우회비는 항상
            // 2*arm/5 ≈ 10 이상이라 팔 길이만이 결과를 가른다.
            listOf(24.9, 25.0, 25.1).forEach { arm ->
                val (a, b, c) = triangle(arm, arm, 5.0)
                val p0 = Fix(a.first, a.second, 10f, t0)
                val p1 = Fix(b.first, b.second, 10f, t0 + 2_500)
                val p2 = Fix(c.first, c.second, 10f, t0 + 5_000)
                addCase("spike_arm_boundary_$arm", listOf(p0, p1, p2))
            }
            // 다리 길이(15m) 경계. 팔=40/40(안전), 시간폭=5000(안전).
            listOf(14.9, 15.0, 15.1).forEach { bridge ->
                val (a, b, c) = triangle(40.0, 40.0, bridge)
                val p0 = Fix(a.first, a.second, 10f, t0)
                val p1 = Fix(b.first, b.second, 10f, t0 + 2_500)
                val p2 = Fix(c.first, c.second, 10f, t0 + 5_000)
                addCase("spike_bridge_boundary_$bridge", listOf(p0, p1, p2))
            }
            // 우회비(4.0) 경계. 다리를 15(다리 문턱 자체)에 두면 그 문턱에서 이미 막혀
            // (bridge>15 면 거부, 15는 통과) ratio 비교까지 못 간다 — 옆의
            // spike_bridge_boundary_15.0 케이스가 "15.0 은 통과"를 이미 증명하고 있으니
            // 다리는 문턱에서 안전하게 떨어진 13(<=15, 넉넉히 안쪽)으로 두고 팔만
            // 조절해 비율만으로 갈리게 한다. ratio = 2*arm/13: 25.5→3.92, 26.0→4.00,
            // 26.5→4.08 — 팔은 셋 다 25 이상(안전)이라 팔 길이 문턱은 안 걸린다.
            listOf(25.5, 26.0, 26.5).forEach { arm ->
                val (a, b, c) = triangle(arm, arm, 13.0)
                val p0 = Fix(a.first, a.second, 10f, t0)
                val p1 = Fix(b.first, b.second, 10f, t0 + 2_500)
                val p2 = Fix(c.first, c.second, 10f, t0 + 5_000)
                addCase("spike_ratio_boundary_$arm", listOf(p0, p1, p2))
            }
        }

        // --- 다양한 speed 값이 평활(과정 잡음)에 실제로 반영되는지. Task 8 에서 speed 가
        // 항상 0 으로 굳어 있던 버그가 있었다 — 이 시나리오가 그 회귀를 잡는다. ---
        run {
            val p0 = Fix(baseLat, baseLng, 30f, t0, speed = 0f)
            val p1 = offsetLatLng(baseLat to baseLng, 50.0, 0.0).let { Fix(it.first, it.second, 20f, t0 + 10_000, speed = 0f) }
            val p2 = offsetLatLng(baseLat to baseLng, 100.0, 0.0).let { Fix(it.first, it.second, 20f, t0 + 20_000, speed = 25f) }
            val p3 = offsetLatLng(baseLat to baseLng, 150.0, 0.0).let { Fix(it.first, it.second, 20f, t0 + 30_000, speed = 25f) }
            addCase("varied_speed_values", listOf(p0, p1, p2, p3))

            val z0 = Fix(baseLat, baseLng, 30f, t0, speed = 0f)
            val z1 = offsetLatLng(baseLat to baseLng, 50.0, 0.0).let { Fix(it.first, it.second, 20f, t0 + 10_000, speed = 0f) }
            val z2 = offsetLatLng(baseLat to baseLng, 100.0, 0.0).let { Fix(it.first, it.second, 20f, t0 + 20_000, speed = 0f) }
            val z3 = offsetLatLng(baseLat to baseLng, 150.0, 0.0).let { Fix(it.first, it.second, 20f, t0 + 30_000, speed = 0f) }
            addCase("zero_speed_values", listOf(z0, z1, z2, z3))
        }

        // --- 끝점 정확도(12m) 경계: 마지막 점이 충분히 정확하면 평활 대신 원본을 쓴다. ---
        run {
            listOf(11.9f, 12.0f, 12.1f).forEach { lastAccuracy ->
                val p0 = Fix(baseLat, baseLng, 30f, t0)
                val far = offsetLatLng(baseLat to baseLng, 30.0, 0.0)
                val p1 = Fix(far.first, far.second, lastAccuracy, t0 + 30_000)
                addCase("precise_endpoint_boundary_$lastAccuracy", listOf(p0, p1))
            }
        }

        // --- 같은 시각 중복 콜백은 버려진다. ---
        run {
            val p0 = Fix(baseLat, baseLng, 10f, t0)
            val p1 = Fix(baseLat + 0.0001, baseLng, 10f, t0) // p0 와 같은 시각
            val p2 = Fix(baseLat + 0.0002, baseLng, 10f, t0 + 30_000)
            addCase("duplicate_timestamp", listOf(p0, p1, p2))
        }

        // --- 입력이 시간순이 아니어도 내부에서 정렬한다. ---
        run {
            val p0 = Fix(baseLat, baseLng, 10f, t0 + 60_000)
            val p1 = Fix(baseLat + 0.0001, baseLng, 10f, t0)
            val p2 = Fix(baseLat + 0.0002, baseLng, 10f, t0 + 30_000)
            addCase("unsorted_input", listOf(p0, p1, p2))
        }

        // --- 범위를 벗어난 점(위도>90, 경도>180, at<=0)은 조용히 버려진다. ---
        run {
            val bad1 = Fix(95.0, baseLng, 10f, t0)
            val bad2 = Fix(baseLat, 185.0, 10f, t0 + 10_000)
            val bad3 = Fix(baseLat, baseLng, 10f, 0L)
            val good1 = Fix(baseLat, baseLng, 10f, t0 + 20_000)
            val good2 = Fix(baseLat + 0.0001, baseLng, 10f, t0 + 30_000)
            addCase("invalid_points_filtered", listOf(bad1, bad2, bad3, good1, good2))
        }

        // --- 두 다리(leg)로 갈라지는 긴 궤적: 사이에 공백이 끼어 있다. ---
        run {
            val p0 = Fix(baseLat, baseLng, 10f, t0)
            val p1 = offsetLatLng(baseLat to baseLng, 20.0, 0.0).let { Fix(it.first, it.second, 10f, t0 + 20_000) }
            val far = offsetLatLng(baseLat to baseLng, 500.0, 0.0)
            val p2 = Fix(far.first, far.second, 10f, t0 + 20_000 + 900_000L) // 15분·500m 공백 → 끊김
            val p3 = offsetLatLng(far, 20.0, 0.0).let { Fix(it.first, it.second, 10f, t0 + 20_000 + 900_000L + 20_000) }
            addCase("two_legs_with_gap", listOf(p0, p1, p2, p3))
        }

        // --- 과정 잡음 바닥(4.0 m/s) 경계. speed<=4.0 이면 과정 속도가 늘 4.0 으로 눌려
        // (3.9 와 4.0 은 결과가 같아야 정상이다) speed>4.0 부터 실제 speed 를 따라가야
        // 한다(4.1). Task 8 의 "speed 가 항상 0" 회귀가 되돌아오면 셋 다 같아진다. ---
        run {
            listOf(3.9f, 4.0f, 4.1f).forEach { speed ->
                val p0 = Fix(baseLat, baseLng, 20f, t0, speed = 0f)
                val far = offsetLatLng(baseLat to baseLng, 30.0, 0.0)
                val p1 = Fix(far.first, far.second, 20f, t0 + 10_000, speed = speed)
                addCase("process_speed_floor_boundary_$speed", listOf(p0, p1))
            }
        }

        // --- 한 다리 안에서 정확도가 문턱(50m) 위아래를 여러 번 오간다. accuracy_boundary_50
        // 은 경계 하나만 보지만, 실제 데이터는 한 다리 안에서 정확도가 계속 출렁인다 —
        // 필터링된 점 뒤에도 남은 점들의 평활이 이어지는지를 본다. ---
        run {
            val accuracies = listOf(30f, 60f, 45f, 70f, 20f, 55f, 10f)
            val points = accuracies.mapIndexed { index, accuracy ->
                val offset = offsetLatLng(baseLat to baseLng, index * 10.0, 0.0)
                Fix(offset.first, offset.second, accuracy, t0 + index * 15_000L)
            }
            addCase("accuracy_mixed_sequence", points)
        }

        // --- 튐 제거와 다리 나누기(gap)가 같은 궤적 안에서 만난다. 튐 제거는 정렬된 전체
        // 목록에서 먼저 끝나야 하고, 그 직후 큰 공백으로 다리가 갈려도 새 다리의 첫
        // 점(평활 시드)은 영향을 안 받아야 한다. ---
        run {
            val (spikeA, spikeB, spikeC) = triangle(40.0, 40.0, 5.0) // 뚜렷한 튐(우회비 큼) — 제거돼야 함
            val p0 = Fix(spikeA.first, spikeA.second, 10f, t0)
            val p1 = Fix(spikeB.first, spikeB.second, 10f, t0 + 5_000)
            val p2 = Fix(spikeC.first, spikeC.second, 10f, t0 + 10_000)
            val far = offsetLatLng(spikeC, 500.0, 0.0)
            val p3 = Fix(far.first, far.second, 10f, t0 + 10_000 + 900_000L) // 15분·500m 공백 → 끊김
            val p4 = offsetLatLng(far, 20.0, 0.0).let { Fix(it.first, it.second, 10f, t0 + 10_000 + 900_000L + 20_000) }
            addCase("spike_then_gap_split", listOf(p0, p1, p2, p3, p4))
        }

        // --- 빈 입력. ---
        addCase("empty", emptyList())

        validateBoundaryGroupsSweepSomething(cases)
        return cases
    }

    // ==================================================================
    // 3. KoreanHolidays — 2025~2030년 전체 공휴일
    // ==================================================================

    @Test
    fun `골든 - KoreanHolidays`() {
        val payload = generateKoreanHolidays()
        writeGoldenIfPresent("koreanHolidays", toJson(payload))
    }

    /**
     * 2025~2030년 음력 기준일(설날·추석·부처님오신날).
     *
     * 이 파일이 `android.icu.util.ChineseCalendar` 를 쓸 수 없어서(순수 JVM 단위
     * 테스트에는 안드로이드 런타임이 없다 — `core/HolidayCalendar.kt` 는 그래서 애초에
     * JVM 단위 테스트 대상이 아니다) 실제 값을 상수로 못박는다. 2025~2027년 값은
     * `KoreanHolidaysTest.kt`/`HolidayCalendarTests.swift` 에 이미 "확인된 값"으로 못박혀
     * 있는 값과 정확히 같다(교차 확인됨). 2028~2030년 값은 macOS `Foundation` 의
     * `Calendar(identifier: .chinese)` (iOS 와 동일한 구현)로 직접 계산해 얻었다 —
     * iOS 가 스스로 계산하는 값과 같은 소스이므로, 이 파일이 실제로 대조하는 것은
     * "코틀린 KoreanHolidays.of() 와 스위프트 KoreanHolidays.of() 가 **같은 기준일이
     * 주어졌을 때** 같은 대체공휴일을 계산하는가" 다 — 음력 환산 자체의 정오는
     * `HolidayCalendarTests.swift` 가 이미 아홉 값으로 따로 확인한다.
     */
    private fun lunarAnchorsTable(): Map<Int, LunarAnchors> = mapOf(
        2025 to LunarAnchors(LocalDate.of(2025, 1, 29), LocalDate.of(2025, 10, 6), LocalDate.of(2025, 5, 5)),
        2026 to LunarAnchors(LocalDate.of(2026, 2, 17), LocalDate.of(2026, 9, 25), LocalDate.of(2026, 5, 24)),
        2027 to LunarAnchors(LocalDate.of(2027, 2, 6), LocalDate.of(2027, 9, 15), LocalDate.of(2027, 5, 13)),
        2028 to LunarAnchors(LocalDate.of(2028, 1, 26), LocalDate.of(2028, 10, 3), LocalDate.of(2028, 5, 2)),
        2029 to LunarAnchors(LocalDate.of(2029, 2, 13), LocalDate.of(2029, 9, 22), LocalDate.of(2029, 5, 20)),
        2030 to LunarAnchors(LocalDate.of(2030, 2, 3), LocalDate.of(2030, 9, 12), LocalDate.of(2030, 5, 9)),
    )

    private fun generateKoreanHolidays(): List<Map<String, Any?>> =
        lunarAnchorsTable().toSortedMap().map { (year, anchors) ->
            val days = KoreanHolidays.of(year, anchors)
            linkedMapOf(
                "year" to year,
                "seollal" to anchors.seollal.toString(),
                "chuseok" to anchors.chuseok.toString(),
                "buddha" to anchors.buddha.toString(),
                "holidays" to days.entries.associate { (date, holiday) -> date.toString() to holiday.name },
            )
        }

    // ==================================================================
    // 4. SegmentSummarizer — 경계값. 코틀린도 이제 문장이 아니라 값(Duration·Distance)을
    // 돌려준다(origin/main 0feb0e3). 그래서 **실제 함수가 돌려준 값**을 그대로 구조로 옮겨
    // JSON 에 적는다 — 생성기가 로직을 다시 구현해 저 혼자와 대조하는 헛일이 되지 않는다.
    // ==================================================================

    @Test
    fun `골든 - SegmentSummarizer`() {
        val payload = generateSegmentSummarizer()
        writeGoldenIfPresent("segmentSummarizer", toJson(payload))
    }

    private fun durationJson(value: SegmentSummarizer.Duration): Map<String, Any?> = when (value) {
        SegmentSummarizer.Duration.UnderMinute -> linkedMapOf("case" to "underOneMinute")
        is SegmentSummarizer.Duration.Minutes -> linkedMapOf("case" to "minutes", "minutes" to value.minutes)
        is SegmentSummarizer.Duration.Hours -> linkedMapOf("case" to "hours", "hours" to value.hours)
        is SegmentSummarizer.Duration.HoursMinutes ->
            linkedMapOf("case" to "hoursMinutes", "hours" to value.hours, "minutes" to value.minutes)
    }

    /**
     * 여기서 만드는 맵의 키는 나중에 입력값("meters")과 합쳐진다 — 그래서 case 가 만드는
     * 미터 출력값은 일부러 "roundedMeters" 로 다르게 부른다. 둘 다 "meters" 로 두면
     * `Map` 합치기(`+`)에서 뒤에 합쳐지는 입력값이 이 출력값을 조용히 덮어써 버린다
     * (실제로 그 버그가 있었다 — 골든 파일에 십 단위로 내림된 결과 대신 원래 입력이
     * 그대로 찍혀 있었다).
     *
     * 킬로미터는 화면 서식이 소수 한 자리로 자른다(SegmentSummarizer.distance 주석).
     * 예전 골든 파일은 "%.1fkm" 문장을 파싱한 값이었으므로 같은 자리에서 반올림해 적는다.
     */
    private fun distanceJson(value: SegmentSummarizer.Distance): Map<String, Any?> = when (value) {
        SegmentSummarizer.Distance.UnderTenMeters -> linkedMapOf("case" to "underTenMeters")
        is SegmentSummarizer.Distance.Meters -> linkedMapOf("case" to "meters", "roundedMeters" to value.meters)
        is SegmentSummarizer.Distance.Kilometers ->
            linkedMapOf("case" to "kilometers", "kilometers" to String.format(java.util.Locale.ROOT, "%.1f", value.kilometers).toDouble())
    }

    private fun generateSegmentSummarizer(): Map<String, Any?> {
        val durationMillis = mutableListOf<Long>()
        // 59/60초 경계, 정확한 시간 경계.
        durationMillis += listOf(0L, 1L, 59_000L, 59_999L, 60_000L, 60_001L, 119_999L, 120_000L)
        durationMillis += listOf(3_599_999L, 3_600_000L, 3_600_001L, 3_659_999L, 3_660_000L, 3_660_001L) // 1시간 경계
        durationMillis += listOf(7_200_000L, 90_000_000L) // 정확한 2시간, 25시간
        // 무작위(고정 시드)로 뽑은 평범한 값들.
        val durationRandom = Random(20260913)
        repeat(30) { durationMillis += durationRandom.nextLong(0L, 100_000_000L) }

        val durations = durationMillis.distinct().sorted().map { millis ->
            durationJson(SegmentSummarizer.duration(millis)) + mapOf("millis" to millis)
        }

        val distanceMeters = mutableListOf<Double>()
        // 9/10m, 999/1000m 경계, 그리고 십 단위 내림이 매번 걸리는 자리들.
        distanceMeters += listOf(0.0, 5.0, 9.0, 9.9, 9.99, 10.0, 10.01, 10.1, 19.9, 20.0, 20.1)
        distanceMeters += listOf(99.9, 100.0, 100.1, 999.0, 999.9, 999.99, 1000.0, 1000.01, 1000.1)
        distanceMeters += listOf(1049.0, 1050.0, 1150.0, 1250.0, 1251.0, 1349.0, 1350.0, 1450.0) // .x5 반올림 경계
        // 무작위(고정 시드)로 뽑은 평범한 값들.
        val distanceRandom = Random(20260914)
        repeat(30) { distanceMeters += distanceRandom.nextDouble(0.0, 5000.0) }

        val distances = distanceMeters.distinct().sorted().map { meters ->
            distanceJson(SegmentSummarizer.distance(meters)) + mapOf("meters" to meters)
        }

        val zones = listOf(ZoneId.of("Asia/Seoul"), ZoneId.of("UTC"), ZoneId.of("America/New_York"))
        val timeRanges = mutableListOf<Map<String, Any?>>()
        val baseStart = 1_700_000_000_000L
        val timeRangeRandom = Random(20260915)
        for (zone in zones) {
            repeat(8) {
                val startAt = baseStart + timeRangeRandom.nextLong(0L, 400_000_000L)
                val endAt = startAt + timeRangeRandom.nextLong(0L, 6L * 3_600_000L)
                val segment = Segment(SegmentType.MOVE, startAt, endAt, 0.0, 0.0, 0.0, 1, 0.0, 0.0)
                val text = SegmentSummarizer.timeRange(segment, zone)
                val match = Regex("^(\\d{2}):(\\d{2})~(\\d{2}):(\\d{2})$").find(text)
                    ?: error("timeRange 형식을 못 읽는다: '$text'")
                val (sh, sm, eh, em) = match.destructured
                timeRanges += linkedMapOf(
                    "startAt" to startAt, "endAt" to endAt, "zone" to zone.id,
                    "startHour" to sh.toInt(), "startMinute" to sm.toInt(),
                    "endHour" to eh.toInt(), "endMinute" to em.toInt(),
                )
            }
        }
        // 자정을 넘는 구간도 함께.
        run {
            val seoul = ZoneId.of("Asia/Seoul")
            val start = LocalDate.of(2026, 1, 5).atStartOfDay(seoul).toInstant().toEpochMilli() + 23 * 3_600_000L + 50 * 60_000L
            val end = start + 20 * 60_000L
            val segment = Segment(SegmentType.MOVE, start, end, 0.0, 0.0, 0.0, 1, 0.0, 0.0)
            val text = SegmentSummarizer.timeRange(segment, seoul)
            val match = Regex("^(\\d{2}):(\\d{2})~(\\d{2}):(\\d{2})$").find(text)!!
            val (sh, sm, eh, em) = match.destructured
            timeRanges += linkedMapOf(
                "startAt" to start, "endAt" to end, "zone" to seoul.id,
                "startHour" to sh.toInt(), "startMinute" to sm.toInt(),
                "endHour" to eh.toInt(), "endMinute" to em.toInt(),
            )
        }

        return linkedMapOf("durations" to durations, "distances" to distances, "timeRanges" to timeRanges)
    }

    // ==================================================================
    // 5. RouteWindows — 창 배분: 하나·둘·여럿, 맞닿음·겹침·멀리 떨어짐, 홀짝 중간점
    // ==================================================================

    @Test
    fun `골든 - RouteWindows`() {
        val payload = generateRouteWindows()
        writeGoldenIfPresent("routeWindows", toJson(payload))
    }

    private fun generateRouteWindows(): List<Map<String, Any?>> {
        val cases = mutableListOf<Map<String, Any?>>()

        fun addCase(name: String, moves: List<LongRange>) {
            val windows = RouteWindows.partition(moves)
            cases += linkedMapOf(
                "name" to name,
                "moves" to moves.map { listOf(it.first, it.last) },
                "windows" to windows.map { listOf(it.first, it.last) },
            )
        }

        addCase("empty", emptyList())
        addCase("single", listOf(1_000L..5_000L))

        // 맞닿음·간격 1(홀수 중간점)·간격 2(짝수 중간점).
        addCase("adjacent", listOf(1_000L..2_000L, 2_001L..3_000L))
        addCase("gap_1_odd_midpoint", listOf(1_000L..2_000L, 2_002L..3_000L))
        addCase("gap_2_even_midpoint", listOf(1_000L..2_000L, 2_003L..3_000L))

        addCase("far_apart", listOf(0L..1_000L, 100_000L..101_000L))

        addCase("overlapping", listOf(1_000L..5_000L, 3_000L..8_000L))
        addCase("fully_contained", listOf(1_000L..5_000L, 2_000L..3_000L))

        addCase("unsorted_input", listOf(5_000L..6_000L, 0L..1_000L, 2_000L..3_000L))

        addCase(
            "extreme_values",
            listOf(Long.MIN_VALUE..(Long.MIN_VALUE + 1_000), (Long.MAX_VALUE - 1_000)..Long.MAX_VALUE),
        )

        addCase(
            "three_moves_mixed",
            listOf(0L..1_000L, 1_500L..2_000L, 2_000L..2_000L), // 맞닿음 + 간격
        )

        // 많은 구간(고정 시드 무작위): 겹침도 섞여 나온다(gap 이 음수일 때).
        val random = Random(20260916)
        repeat(6) { setIndex ->
            var t = random.nextLong(0L, 1_000L)
            val moves = mutableListOf<LongRange>()
            val count = random.nextInt(5, 13)
            repeat(count) {
                val duration = random.nextLong(100L, 5_000L)
                val start = t
                val end = start + duration
                moves += start..end
                val gap = random.nextLong(-1_000L, 6_000L)
                t = end + gap
            }
            addCase("random_set_$setIndex", moves)
        }

        return cases
    }

    // ==================================================================
    // 6. LocationFilter — 정확도 두 문턱, 완화 창, 25m·10분, 순간이동
    // ==================================================================

    @Test
    fun `골든 - LocationFilter`() {
        val payload = linkedMapOf(
            "constants" to locationFilterConstants(),
            "cases" to generateLocationFilter(),
            "distances" to generateDistances(),
        )
        writeGoldenIfPresent("locationFilter", toJson(payload))
    }

    /** 스위프트가 상수를 그대로 옮겼는지 기계가 보게 한다(1단계 계획서 공통 절차 C-2). */
    private fun locationFilterConstants(): Map<String, Any?> = linkedMapOf(
        "maxAccuracyMeters" to LocationFilter.MAX_ACCURACY_METERS.toDouble(),
        "fallbackMaxAccuracyMeters" to LocationFilter.FALLBACK_MAX_ACCURACY_METERS.toDouble(),
        "staleFallbackMillis" to LocationFilter.STALE_FALLBACK_MILLIS,
        "minMoveMeters" to LocationFilter.MIN_MOVE_METERS,
        "maxSpeedMps" to LocationFilter.MAX_SPEED_MPS,
        "heartbeatMillis" to LocationFilter.HEARTBEAT_MILLIS,
    )

    /**
     * `Fix` 한 점을 골든 JSON 으로. `Float` 필드는 전부 `Double` 로 넓혀 적는다(설계서 §4.1).
     *
     * 이름이 [fixJson] 이 아닌 이유: 그 이름으로 두면 위의 `fixJson(Fix)`(경로 다듬기용, 5개 필드)와
     * **오버로드**가 되고, 인자가 non-null `Fix` 일 때 코틀린이 더 구체적인 옛 것을 골라
     * `speedAccuracy` 가 조용히 빠진다 — 실제로 판정기 골든이 그렇게 만들어졌고 스위프트 대조가
     * 잡아냈다. 이름을 갈라 그 갈래를 아예 없앤다.
     */
    private fun fullFixJson(f: Fix?): Any? = f?.let {
        linkedMapOf(
            "lat" to it.lat, "lng" to it.lng,
            "accuracy" to it.accuracy.toDouble(), "speed" to it.speed.toDouble(),
            "at" to it.at, "speedAccuracy" to it.speedAccuracy.toDouble(),
        )
    }

    private fun generateLocationFilter(): List<Map<String, Any?>> {
        val t0 = 1_700_000_000_000L
        val cases = mutableListOf<Map<String, Any?>>()

        fun add(name: String, previous: Fix?, candidate: Fix) {
            cases += linkedMapOf(
                "name" to name,
                "previous" to fullFixJson(previous),
                "candidate" to fullFixJson(candidate),
                "decision" to LocationFilter.decide(previous, candidate).name,
            )
        }

        fun at(meters: Double, afterMillis: Long, accuracy: Float, speed: Float = 0f): Fix {
            val (lat, lng) = offsetLatLng(baseLat to baseLng, 0.0, meters)
            return Fix(lat, lng, accuracy, t0 + afterMillis, speed)
        }

        val base = Fix(baseLat, baseLng, 10f, t0)

        // previous == null — 완화 창이 열린 것과 같다.
        // 정확도는 Float 로 정확히 표현되는 값만 쓴다(설계서 §4.1): 49.5 / 50 / 50.5 / 99.5 / 100 / 100.5
        listOf(49.5f, 50f, 50.5f, 99.5f, 100f, 100.5f).forEach {
            add("first_fix_accuracy_$it", null, Fix(baseLat, baseLng, it, t0))
        }

        // 평소 창(15분 미만): 50 위는 전부 거절. 거리를 이동 문턱(25m) 위로 둬서 **정확도만**
        // 판정을 가르게 한다 — 5m 로 두면 통과한 점도 SKIP_TOO_CLOSE 가 되어 경계가 안 보인다.
        listOf(49.5f, 50f, 50.5f, 60f, 100f).forEach {
            add("fresh_accuracy_$it", base, at(30.0, 60_000L, it))
        }

        // 완화 창 경계(15분 = 900_000ms) 양옆. 같은 60m 점이 갈려야 한다.
        listOf(899_999L, 900_000L, 900_001L).forEach {
            add("stale_window_$it", base, at(5.0, it, 60f))
        }

        // 25m 이동 문턱 양옆. 시간은 하트비트(10분)보다 짧게 둬 거리만 갈리게 한다.
        listOf(24.0, 25.0, 26.0).forEach {
            add("move_threshold_$it", base, at(it, 60_000L, 10f))
        }

        // 하트비트(10분) 양옆. 거리는 항상 1m 로 두어 시간만 갈린다.
        listOf(599_999L, 600_000L, 600_001L).forEach {
            add("heartbeat_$it", base, at(1.0, it, 10f))
        }

        // 순간이동(55.6 m/s) 양옆. 1초 사이 이동 거리로 속도를 맞춘다.
        listOf(55.0, 56.0, 60.0).forEach {
            add("teleport_$it", base, at(it, 1_000L, 10f))
        }

        // elapsed <= 0 (시계 역행·동일 시각).
        add("elapsed_zero", base, at(5.0, 0L, 10f))
        add("elapsed_negative", base, at(5.0, -1_000L, 10f))

        // 완화 승인은 순간이동 검사를 **지난 뒤**여야 한다 — 15분 뒤에 1000km 를 간 60m 점.
        run {
            val (lat, lng) = offsetLatLng(baseLat to baseLng, 0.0, 1_000_000.0)
            add("stale_but_teleport", base, Fix(lat, lng, 60f, t0 + 900_000L))
        }

        // 자체 점검: 문턱 양옆이 실제로 갈리는가.
        fun decisionOf(name: String) = cases.first { it["name"] == name }["decision"]
        check(decisionOf("fresh_accuracy_50.0") == "UPLOAD" && decisionOf("fresh_accuracy_50.5") == "REJECT_INACCURATE") {
            "정확도 50m 경계가 안 갈린다 — 생성기가 경계에 도달하지 못했다"
        }
        check(decisionOf("stale_window_899999") == "REJECT_INACCURATE" && decisionOf("stale_window_900000") == "UPLOAD_STALE_FALLBACK") {
            "완화 창 15분 경계가 안 갈린다"
        }
        check(decisionOf("move_threshold_24.0") == "SKIP_TOO_CLOSE" && decisionOf("move_threshold_26.0") == "UPLOAD") {
            "25m 이동 문턱이 안 갈린다"
        }
        check(decisionOf("heartbeat_599999") == "SKIP_TOO_CLOSE" && decisionOf("heartbeat_600000") == "UPLOAD") {
            "하트비트 10분 경계가 안 갈린다"
        }
        check(decisionOf("teleport_55.0") != "REJECT_IMPOSSIBLE" && decisionOf("teleport_56.0") == "REJECT_IMPOSSIBLE") {
            "순간이동 문턱이 안 갈린다"
        }
        check(decisionOf("stale_but_teleport") == "REJECT_IMPOSSIBLE") {
            "완화 승인이 순간이동 검사를 건너뛰었다 — LocationFilter.kt:134-138 의 순서가 깨졌다"
        }
        return cases
    }

    /** distanceMeters 자체도 따로 쓸어본다 — 위·경도 양방향, 적도·극지, 같은 점. */
    private fun generateDistances(): List<Map<String, Any?>> {
        val cases = mutableListOf<Map<String, Any?>>()
        val anchors = listOf(37.5665 to 126.9780, 0.0 to 0.0, 0.0 to 179.9, 89.0 to 10.0, -33.86 to 151.21)
        for ((lat, lng) in anchors) {
            for (meters in listOf(0.0, 1.0, 25.0, 50.0, 150.0, 1_000.0, 100_000.0)) {
                for (bearing in listOf(0.0, 90.0, 180.0, 270.0, 45.0)) {
                    // offsetLatLng 은 (동쪽, 북쪽) 미터를 받는다 — 방위각을 그 둘로 푼다.
                    val radians = Math.toRadians(bearing)
                    val (toLat, toLng) = offsetLatLng(lat to lng, meters * kotlin.math.sin(radians), meters * cos(radians))
                    val a = Fix(lat, lng, 10f, 0L)
                    val b = Fix(toLat, toLng, 10f, 1_000L)
                    cases += linkedMapOf(
                        "aLat" to lat, "aLng" to lng, "bLat" to toLat, "bLng" to toLng,
                        "meters" to LocationFilter.distanceMeters(a, b),
                    )
                }
            }
        }
        check(cases.count { (it["meters"] as Double) > 0.0 } >= cases.size - anchors.size * 5) {
            "거리 케이스 대부분이 0 이다 — offsetLatLng 가 안 움직였다"
        }
        return cases
    }

    // ==================================================================
    // 7. MovementTrailFilter — 5초 간격, 50m 정확도, 속도 근거, 변위 증거
    // ==================================================================

    @Test
    fun `골든 - MovementTrailFilter`() {
        val payload = linkedMapOf(
            "constants" to linkedMapOf<String, Any?>(
                "minIntervalMillis" to MovementTrailFilter.MIN_INTERVAL_MILLIS,
                "maxAccuracyMeters" to MovementTrailFilter.MAX_ACCURACY_METERS.toDouble(),
                "displacementEvidenceMeters" to MovementTrailFilter.DISPLACEMENT_EVIDENCE_METERS,
                "displacementEvidenceNoiseMultiplier" to MovementTrailFilter.DISPLACEMENT_EVIDENCE_NOISE_MULTIPLIER,
                "movingSpeedMps" to MovementTrailFilter.MOVING_SPEED_MPS.toDouble(),
                "minDisplacementMeters" to MovementTrailFilter.MIN_DISPLACEMENT_METERS,
                "speedTrustMaxAccuracyMeters" to MovementTrailFilter.SPEED_TRUST_MAX_ACCURACY_METERS.toDouble(),
                "minConfidentSpeedMps" to MovementTrailFilter.MIN_CONFIDENT_SPEED_MPS.toDouble(),
                "minSpeedEvidenceDisplacementMeters" to MovementTrailFilter.MIN_SPEED_EVIDENCE_DISPLACEMENT_METERS,
            ),
            "shouldRecord" to generateShouldRecord(),
            "displacementEvidence" to generateDisplacementEvidence(),
        )
        writeGoldenIfPresent("movementTrailFilter", toJson(payload))
    }

    private fun generateShouldRecord(): List<Map<String, Any?>> {
        val t0 = 1_700_000_000_000L
        val cases = mutableListOf<Map<String, Any?>>()

        fun add(name: String, previous: Fix?, candidate: Fix, moving: Boolean) {
            // Float 산술과 Double 산술이 갈리는 입력은 골든에 싣지 않는다(1단계 판정 기록 3).
            if (candidate.speedAccuracy.isFinite()) {
                val f = (candidate.speed - candidate.speedAccuracy) >= MovementTrailFilter.MIN_CONFIDENT_SPEED_MPS
                val d = (candidate.speed.toDouble() - candidate.speedAccuracy.toDouble()) >=
                    MovementTrailFilter.MIN_CONFIDENT_SPEED_MPS.toDouble()
                check(f == d) {
                    "$name: 속도 근거가 Float(${f})와 Double(${d})에서 갈린다 — 이 입력은 두 언어가 같은 답을 못 낸다"
                }
            }
            cases += linkedMapOf(
                "name" to name, "previous" to fullFixJson(previous), "candidate" to fullFixJson(candidate),
                "reportedMoving" to moving,
                "shouldRecord" to MovementTrailFilter.shouldRecord(previous, candidate, moving),
            )
        }

        fun at(meters: Double, afterMillis: Long, accuracy: Float, speed: Float = 0f, speedAccuracy: Float = Float.POSITIVE_INFINITY): Fix {
            val (lat, lng) = offsetLatLng(baseLat to baseLng, meters, 0.0)
            return Fix(lat, lng, accuracy, t0 + afterMillis, speed, speedAccuracy)
        }

        val previous = Fix(baseLat, baseLng, 5f, t0, 0f, Float.POSITIVE_INFINITY)

        // reportedMoving = false 는 언제나 false.
        add("not_moving", previous, at(100.0, 10_000L, 5f), moving = false)
        // previous == null 은 정확도만 본다.
        listOf(49.5f, 50f, 50.5f).forEach { add("first_accuracy_$it", null, at(0.0, 0L, it), moving = true) }
        // 5초 간격 양옆.
        listOf(4_999L, 5_000L, 5_001L).forEach { add("interval_$it", previous, at(10.0, it, 5f), moving = true) }
        // 3m 최소 변위 양옆(속도 근거 없음).
        listOf(2.0, 3.0, 4.0).forEach { add("displacement_$it", previous, at(it, 10_000L, 5f), moving = true) }
        // 속도 근거 갈래: 정확도 15m 양옆 × 속도오차 유무.
        listOf(14.5f, 15f, 15.5f).forEach {
            add("speed_trust_accuracy_$it", Fix(baseLat, baseLng, it, t0), at(3.0, 10_000L, it, speed = 1.5f, speedAccuracy = 0.5f), moving = true)
        }
        // 속도 정확도가 없을 때의 옛 문턱(0.7f) 양옆.
        listOf(0.5f, 0.75f, 1.0f).forEach {
            add("legacy_speed_$it", Fix(baseLat, baseLng, 5f, t0), at(3.0, 10_000L, 5f, speed = it), moving = true)
        }
        // previous 가 있는 상태에서의 정확도 상한 양옆.
        listOf(49.5f, 50f, 50.5f).forEach { add("cand_accuracy_$it", previous, at(10.0, 10_000L, it), moving = true) }
        // 속도 오차를 뺀 값이 0.35f 문턱 양옆에 앉는 입력. shouldRecord 에서는 MIN_SPEED_EVIDENCE_
        // DISPLACEMENT_METERS 와 MIN_DISPLACEMENT_METERS 가 둘 다 3.0 이라 이 갈래가 최종 답을
        // 혼자 뒤집지는 못하지만, 위 add() 의 Float/Double 일치 검사를 실제로 돌리는 것이 목적이다
        // (판정 기록 3 — 같은 식을 AdaptiveMovementDetector 는 혼자 판정에 쓴다).
        listOf(0.8f to 0.5f, 0.85f to 0.5f, 1.0f to 0.5f).forEach { (speed, speedAccuracy) ->
            add(
                "confident_speed_${speed}_$speedAccuracy",
                Fix(baseLat, baseLng, 5f, t0),
                at(4.0, 10_000L, 5f, speed = speed, speedAccuracy = speedAccuracy),
                moving = true,
            )
        }
        // 순간이동(candidate.speed 자체가 55.6 초과 / impliedSpeed 초과).
        add("speed_over_max", previous, at(10.0, 10_000L, 5f, speed = 60f), moving = true)
        add("implied_over_max", previous, at(600_000.0, 10_000L, 5f), moving = true)

        fun recordOf(name: String) = cases.first { it["name"] == name }["shouldRecord"]
        check(recordOf("interval_4999") == false && recordOf("interval_5000") == true) { "5초 간격 경계가 안 갈린다" }
        check(recordOf("displacement_2.0") == false && recordOf("displacement_4.0") == true) { "3m 변위 경계가 안 갈린다" }
        check(recordOf("first_accuracy_50.0") == true && recordOf("first_accuracy_50.5") == false) { "50m 정확도 경계가 안 갈린다" }
        check(recordOf("cand_accuracy_50.0") == true && recordOf("cand_accuracy_50.5") == false) { "previous 가 있을 때의 50m 정확도 경계가 안 갈린다" }
        return cases
    }

    private fun generateDisplacementEvidence(): List<Map<String, Any?>> {
        val t0 = 1_700_000_000_000L
        val cases = mutableListOf<Map<String, Any?>>()

        fun add(name: String, previous: Fix?, candidate: Fix) {
            cases += linkedMapOf(
                "name" to name,
                "previous" to previous?.let { linkedMapOf("lat" to it.lat, "lng" to it.lng, "accuracy" to it.accuracy.toDouble(), "at" to it.at) },
                "candidate" to linkedMapOf("lat" to candidate.lat, "lng" to candidate.lng, "accuracy" to candidate.accuracy.toDouble(), "at" to candidate.at),
                "isEvidence" to MovementTrailFilter.isDisplacementEvidence(previous, candidate),
            )
        }

        fun moved(meters: Double, accuracy: Float, afterMillis: Long = 60_000L): Fix {
            val (lat, lng) = offsetLatLng(baseLat to baseLng, meters, 0.0)
            return Fix(lat, lng, accuracy, t0 + afterMillis)
        }

        add("no_previous", null, moved(100.0, 5f))
        // 고정 문턱 50m 양옆(오차가 작아 hypot × 1.5 가 50 을 못 넘는다: hypot(5,5)*1.5 ≈ 10.6).
        listOf(49.0, 50.0, 51.0).forEach { add("fixed_threshold_$it", Fix(baseLat, baseLng, 5f, t0), moved(it, 5f)) }
        // 잡음 비례 문턱: 오차 40m 두 점 → hypot(40,40)*1.5 ≈ 84.9. 양옆을 쓴다.
        listOf(80.0, 90.0).forEach { add("noise_threshold_$it", Fix(baseLat, baseLng, 40f, t0), moved(it, 40f)) }
        // 정확도 상한(LocationFilter 50m) 양옆 — 한쪽만 나빠도 거절이다.
        listOf(49.5f, 50f, 50.5f).forEach {
            add("prev_accuracy_$it", Fix(baseLat, baseLng, it, t0), moved(200.0, 5f))
            add("cand_accuracy_$it", Fix(baseLat, baseLng, 5f, t0), moved(200.0, it))
        }
        // elapsed <= 0, 순간이동.
        add("elapsed_zero", Fix(baseLat, baseLng, 5f, t0), moved(200.0, 5f, afterMillis = 0L))
        add("teleport", Fix(baseLat, baseLng, 5f, t0), moved(200.0, 5f, afterMillis = 1L))

        fun evidenceOf(name: String) = cases.first { it["name"] == name }["isEvidence"]
        check(evidenceOf("fixed_threshold_49.0") == false && evidenceOf("fixed_threshold_51.0") == true) { "고정 50m 문턱이 안 갈린다" }
        check(evidenceOf("noise_threshold_80.0") == false && evidenceOf("noise_threshold_90.0") == true) { "잡음 비례 문턱이 안 갈린다" }
        check(evidenceOf("cand_accuracy_50.0") == true && evidenceOf("cand_accuracy_50.5") == false) { "정확도 상한이 안 갈린다" }
        return cases
    }

    // ==================================================================
    // 8. AdaptiveMovementDetector — 점 시퀀스를 통째로 먹이고 매 점의 상태를 기록한다
    // ==================================================================

    @Test
    fun `골든 - AdaptiveMovementDetector`() {
        val payload = linkedMapOf(
            "constants" to linkedMapOf<String, Any?>(
                "maxAccuracyMeters" to AdaptiveMovementDetector.MAX_ACCURACY_METERS.toDouble(),
                "fastProbeMillis" to AdaptiveMovementDetector.FAST_PROBE_MILLIS,
                "stopConfirmMillis" to AdaptiveMovementDetector.STOP_CONFIRM_MILLIS,
                "minConfirmMillis" to AdaptiveMovementDetector.MIN_CONFIRM_MILLIS,
                "minConfirmPoints" to AdaptiveMovementDetector.MIN_CONFIRM_POINTS,
                "speedTrustMaxAccuracyMeters" to AdaptiveMovementDetector.SPEED_TRUST_MAX_ACCURACY_METERS.toDouble(),
                "minConfidentSpeedMps" to AdaptiveMovementDetector.MIN_CONFIDENT_SPEED_MPS.toDouble(),
                "minSpeedDisplacementMeters" to AdaptiveMovementDetector.MIN_SPEED_DISPLACEMENT_METERS,
                "minNetDisplacementMeters" to AdaptiveMovementDetector.MIN_NET_DISPLACEMENT_METERS,
                "slowProbeMinDisplacementMeters" to AdaptiveMovementDetector.SLOW_PROBE_MIN_DISPLACEMENT_METERS,
                "stopRadiusMeters" to AdaptiveMovementDetector.STOP_RADIUS_METERS,
                "noiseMultiplier" to AdaptiveMovementDetector.NOISE_MULTIPLIER,
                "minProgressRatio" to AdaptiveMovementDetector.MIN_PROGRESS_RATIO,
            ),
            "cases" to generateAdaptiveMovement(),
        )
        writeGoldenIfPresent("adaptiveMovementDetector", toJson(payload))
    }

    /**
     * `speed - speedAccuracy >= MIN_CONFIDENT_SPEED_MPS` 는 코틀린에서 Float 뺄셈이고 스위프트에서
     * Double 뺄셈이다(판정 기록 3). 두 산술이 갈리는 입력은 골든에 싣지 않는다 — 실으면 두 언어가
     * 같은 답을 낼 수 없는 케이스를 "회귀"라고 부르게 된다.
     */
    private fun checkSpeedEvidenceAgrees(name: String, f: Fix, threshold: Float) {
        if (!f.speedAccuracy.isFinite()) return
        val asFloat = (f.speed - f.speedAccuracy) >= threshold
        val asDouble = (f.speed.toDouble() - f.speedAccuracy.toDouble()) >= threshold.toDouble()
        check(asFloat == asDouble) {
            "$name: 속도 근거가 Float($asFloat)와 Double($asDouble)에서 갈린다 — 두 언어가 같은 답을 못 낸다"
        }
    }

    private fun generateAdaptiveMovement(): List<Map<String, Any?>> {
        val cases = mutableListOf<Map<String, Any?>>()

        /** 기준점에서 동쪽으로 [metersEast] 만큼, [seconds] 초의 점. */
        fun mv(
            seconds: Long,
            metersEast: Double = 0.0,
            accuracy: Float = 5f,
            speed: Float = 0f,
            speedAccuracy: Float = Float.POSITIVE_INFINITY,
            lat: Double? = null,
        ): Fix {
            val (la, ln) = offsetLatLng(baseLat to baseLng, metersEast, 0.0)
            return Fix(lat ?: la, ln, accuracy, seconds * 1_000L, speed, speedAccuracy)
        }

        /** 점 목록을 통째로 먹이고 **매 점마다** 상태와 승격 버퍼를 기록한다. */
        fun addCase(name: String, resetFast: Boolean, points: List<Fix>) {
            points.forEach { checkSpeedEvidenceAgrees(name, it, AdaptiveMovementDetector.MIN_CONFIDENT_SPEED_MPS) }
            val detector = AdaptiveMovementDetector()
            detector.reset(fast = resetFast)
            val steps = points.map { p ->
                val u = detector.onFix(p)
                linkedMapOf<String, Any?>(
                    "state" to u.state.name,
                    "promotionBufferSize" to u.promotionBuffer.size,
                    "promotionBufferAts" to u.promotionBuffer.map { it.at },
                )
            }
            cases += linkedMapOf(
                "name" to name,
                "resetFast" to resetFast,
                "points" to points.map { fullFixJson(it) },
                "steps" to steps,
            )
        }

        // 걷는 아이: 30초 동안 1.2m/s 직선. 이 판정기의 존재 이유다.
        addCase("walking_1_2mps", true, (0L..30L step 5L).map { mv(it, it * 1.2, accuracy = 10f) })
        // 제자리 흔들림(고정 시드): 오차 20m 안에서 무작위. 끝까지 MOVING 이 안 돼야 한다.
        run {
            val random = Random(20260922)
            addCase(
                "jitter_in_place",
                true,
                (0L..60L step 5L).map { mv(it, random.nextDouble(-6.0, 6.0), accuracy = 20f) },
            )
        }
        // 확인 창(30초) 양옆 — 마지막 점을 29·30·31초에 둔다. 흔들림이라 확정은 안 되고,
        // 30초가 지나야 SLOW_PROBE 로 내려간다.
        listOf(29L, 30L, 31L).forEach { last ->
            addCase("fast_probe_window_$last", true, listOf(mv(0), mv(10, 2.0), mv(20, -1.0), mv(last, 1.0)))
        }
        // 최소 표본(3점) 양옆: 두 점만으로는 아무리 멀어도 확정하지 않는다.
        addCase("min_points_2", true, listOf(mv(0, 0.0, accuracy = 7f), mv(12, 40.0, accuracy = 7f)))
        addCase("min_points_3", true, listOf(mv(0, 0.0, accuracy = 7f), mv(6, 20.0, accuracy = 7f), mv(12, 40.0, accuracy = 7f)))
        // 최소 시간(10초) 양옆: 세 점이 9초·10초 안에 들어온 경우.
        listOf(9L, 10L, 11L).forEach { span ->
            addCase(
                "min_confirm_millis_$span",
                true,
                listOf(mv(0, 0.0, accuracy = 7f), mv(span / 2, 20.0, accuracy = 7f), mv(span, 40.0, accuracy = 7f)),
            )
        }
        // 진행률 0.6 양옆: 오차 7m 두 점의 문턱은 max(15, hypot(7,7)) = 15m. 중간 점을 15×0.55·
        // 0.60·0.65 지점에 두고 마지막 점은 문턱을 넉넉히 넘긴다.
        listOf(0.55, 0.60, 0.65).forEach { ratio ->
            addCase(
                "progress_ratio_$ratio",
                true,
                listOf(mv(0, 0.0, accuracy = 7f), mv(6, 15.0 * ratio, accuracy = 7f), mv(12, 40.0, accuracy = 7f)),
            )
        }
        // 속도 근거 갈래: 정확도 15m 이하 + speedAccuracy 유한 → 최근 두 점만으로 확정한다.
        addCase(
            "speed_evidence_confident",
            true,
            (0L..10L step 5L).map { mv(it, it * 1.2, accuracy = 10f, speed = 1.2f, speedAccuracy = 0.2f) },
        )
        // 그 반대: 같은 속도인데 오차가 커서 속도를 못 믿는다.
        addCase(
            "speed_evidence_distrusted",
            true,
            (0L..10L step 5L).map { mv(it, it * 0.2, accuracy = 20f, speed = 1.2f, speedAccuracy = 0.2f) },
        )
        // 못 쓰는 점이 섞여 들어온다(오차 51m, 속도 60m/s, 위도 91, at 음수).
        addCase("unusable_accuracy", true, listOf(mv(0), mv(5, 10.0, accuracy = 51f), mv(10, 20.0), mv(15, 30.0)))
        addCase("unusable_speed", true, listOf(mv(0), mv(5, 10.0, speed = 60f), mv(10, 20.0), mv(15, 30.0)))
        addCase("unusable_latitude", true, listOf(mv(0), mv(5, 10.0, lat = 91.0), mv(10, 20.0), mv(15, 30.0)))
        addCase("unusable_negative_at", true, listOf(mv(0), Fix(baseLat, baseLng, 5f, -1_000L), mv(10, 20.0), mv(15, 30.0)))
        // 오차가 계속 나쁘면 30초 뒤 FAST_PROBE 가 SLOW_PROBE 로 내려간다(onFix 의 !isUsable 갈래).
        addCase("unusable_for_whole_window", true, (0L..35L step 5L).map { mv(it, it * 8.0, accuracy = 55f) })
        // 시각이 뒤로 가거나 같은 점.
        addCase("time_goes_back", true, listOf(mv(0), mv(10, 12.0), mv(5, 24.0), mv(20, 24.0)))
        addCase("time_repeats", true, listOf(mv(0), mv(10, 12.0), mv(10, 24.0), mv(20, 24.0)))
        // SLOW_PROBE 에서 hasMovementHint 로 FAST_PROBE 로 되올라가는 갈래.
        addCase("slow_probe_hint", false, listOf(mv(0, 0.0, accuracy = 15f), mv(30, 36.0, accuracy = 15f)))
        // 힌트가 부족해 SLOW_PROBE 에 머무는 갈래.
        addCase("slow_probe_no_hint", false, listOf(mv(0, 0.0, accuracy = 15f), mv(30, 5.0, accuracy = 15f)))
        // trimBefore 가 마지막 한 점은 남기는가 — 창(30초)보다 훨씬 긴 공백 뒤의 점 하나.
        addCase("trim_keeps_last", true, listOf(mv(0), mv(5, 3.0), mv(600, 5.0), mv(605, 8.0), mv(610, 11.0)))
        // 정지 확인(60초) 양옆. 승격은 **속도 근거 없이** 변위로만 시킨다 — 속도 근거로 올리면
        // 그 점들이 looksStationary 에서 "보행 중"으로 계속 걸려 창이 60초여도 안 내려간다.
        // 승격 마지막 점이 10초이므로 정지 확인 창은 55·60·65초 뒤(=65·70·75초)에서 갈린다.
        listOf(55L, 60L, 65L).forEach { hold ->
            val promote = listOf(mv(0, 0.0, accuracy = 7f), mv(5, 20.0, accuracy = 7f), mv(10, 40.0, accuracy = 7f))
            val stay = (15L..(10L + hold) step 5L).map { mv(it, 40.0 + (it % 3), accuracy = 10f) }
            addCase("stop_confirm_$hold", true, promote + stay)
        }

        // 자체 점검: 승격이 적어도 한 번은 일어나야 하고, 흔들림 시나리오는 한 번도 안 일어나야 한다.
        fun statesOf(name: String): List<Any?> {
            @Suppress("UNCHECKED_CAST")
            val steps = cases.first { it["name"] == name }["steps"] as List<Map<String, Any?>>
            return steps.map { it["state"] }
        }
        val promoted = cases.filter { c ->
            @Suppress("UNCHECKED_CAST")
            (c["steps"] as List<Map<String, Any?>>).any { it["state"] == "MOVING" }
        }
        check(promoted.isNotEmpty()) { "어떤 시나리오도 MOVING 에 도달하지 못했다 — 생성기가 이동을 못 만든다" }
        check(promoted.size < cases.size) { "모든 시나리오가 MOVING 이다 — 흔들림 시나리오가 실제로 흔들리지 않는다" }
        check(statesOf("walking_1_2mps").contains("MOVING")) { "걷는 아이가 이동으로 확정되지 않는다" }
        check(!statesOf("jitter_in_place").contains("MOVING")) { "제자리 흔들림이 이동으로 승격됐다" }
        check(statesOf("min_points_2").none { it == "MOVING" } && statesOf("min_points_3").contains("MOVING")) {
            "최소 표본(3점) 경계가 안 갈린다"
        }
        check(statesOf("min_confirm_millis_9").none { it == "MOVING" } && statesOf("min_confirm_millis_10").contains("MOVING")) {
            "최소 확인 시간(10초) 경계가 안 갈린다"
        }
        check(statesOf("progress_ratio_0.55").none { it == "MOVING" } && statesOf("progress_ratio_0.65").contains("MOVING")) {
            "진행률 0.6 경계가 안 갈린다"
        }
        check(statesOf("stop_confirm_55").last() == "MOVING" && statesOf("stop_confirm_60").last() == "SLOW_PROBE") {
            "정지 확인(60초) 경계가 안 갈린다: 55=${statesOf("stop_confirm_55").last()} 60=${statesOf("stop_confirm_60").last()}"
        }
        check(statesOf("slow_probe_hint").last() == "FAST_PROBE" && statesOf("slow_probe_no_hint").last() == "SLOW_PROBE") {
            "SLOW_PROBE 복귀 갈래가 안 갈린다"
        }
        check(cases.size >= 15) { "판정기 케이스가 ${cases.size}개뿐이다 — 스윕이라 부르기에 모자란다" }
        return cases
    }

    // ==================================================================
    // 9. SegmentBuilder — 40m 반경, 5분, 연속 2점 이탈, 오차 가중 이름 좌표
    // ==================================================================

    @Test
    fun `골든 - SegmentBuilder`() {
        val payload = linkedMapOf(
            "constants" to linkedMapOf<String, Any?>(
                "stayRadiusMeters" to SegmentBuilder.STAY_RADIUS_METERS,
                "minStayMillis" to SegmentBuilder.MIN_STAY_MILLIS,
                "exitConfirmPoints" to SegmentBuilder.EXIT_CONFIRM_POINTS,
                "minWeightAccuracyMeters" to SegmentBuilder.MIN_WEIGHT_ACCURACY_METERS,
            ),
            "cases" to generateSegmentBuilder(),
        )
        writeGoldenIfPresent("segmentBuilder", toJson(payload))
    }

    private fun generateSegmentBuilder(): List<Map<String, Any?>> {
        val t0 = 1_700_000_000_000L
        val cases = mutableListOf<Map<String, Any?>>()

        /** 기준점에서 북쪽으로 [meters], [minutes] 분 뒤. */
        fun sp(meters: Double, minutes: Long, accuracy: Float = 10f): Fix {
            val (la, ln) = offsetLatLng(baseLat to baseLng, 0.0, meters)
            return Fix(la, ln, accuracy, t0 + minutes * 60_000L)
        }

        fun segmentJson(s: Segment): Map<String, Any?> = linkedMapOf(
            "type" to s.type.name,
            "startAt" to s.startAt, "endAt" to s.endAt,
            "lat" to s.lat, "lng" to s.lng,
            "distanceMeters" to s.distanceMeters, "pointCount" to s.pointCount,
            "nameLat" to s.nameLat, "nameLng" to s.nameLng,
        )

        fun add(name: String, points: List<Fix>) {
            // 같은 at 이 둘 이상이면 코틀린 sortedBy(안정)와 스위프트 sorted(불안정)가 갈릴 수 있다.
            // 생성기가 그런 입력을 아예 안 만든다(브리프 Step 5).
            check(points.map { it.at }.toSet().size == points.size) {
                "$name: 같은 at 을 가진 점이 있다 — 정렬 순서가 두 언어에서 갈릴 수 있는 입력이다"
            }
            cases += linkedMapOf(
                "name" to name,
                "points" to points.map { fullFixJson(it) },
                "segments" to SegmentBuilder.build(points).map(::segmentJson),
            )
        }

        add("empty", emptyList())
        add("single_point", listOf(sp(0.0, 0)))
        add("all_day_same_place", (0..20).map { sp(it * 2.0, it * 10L) })
        // 40m 반경 양옆. 반경 밖 점을 **마지막**에 둔다 — 가운데 두면 EXIT_CONFIRM_POINTS(연속 2)
        // 규칙이 한 점 이탈을 흡수해서 반경 자체가 판정을 안 가른다(그게 그 규칙의 존재 이유다).
        // 마지막 점이면 lastInside 가 달라져 pointCount·endAt 이 갈린다.
        listOf(39.0, 40.0, 41.0).forEach { radius ->
            add("stay_radius_$radius", listOf(sp(0.0, 0), sp(5.0, 5), sp(radius, 10)))
        }
        // 5분 최소 양옆 — 4분·5분·6분 뒤에 떠난다.
        listOf(4L, 5L, 6L).forEach { minutes ->
            add("min_stay_$minutes", listOf(sp(0.0, 0), sp(5.0, minutes), sp(3000.0, 30), sp(6000.0, 40)))
        }
        // 이탈이 1점(튐)과 2점(진짜 이탈).
        add("single_outlier", listOf(sp(0.0, 0), sp(10.0, 10), sp(500.0, 20), sp(15.0, 30), sp(20.0, 40)))
        add("two_outliers", listOf(sp(0.0, 0), sp(10.0, 10), sp(20.0, 20), sp(3000.0, 30), sp(6000.0, 40), sp(9000.0, 50), sp(12000.0, 60)))
        // 오차 가중 이름 좌표: 정확한 점들 + 나쁜 점 하나(반경 안).
        add("weighted_name", listOf(sp(30.0, 0, accuracy = 90f), sp(0.0, 10), sp(0.0, 20), sp(0.0, 30)))
        // 오차 0 인 옛 점(무한 가중치 방지 floor).
        add("zero_accuracy", listOf(sp(30.0, 0, accuracy = 0f), sp(0.0, 10), sp(0.0, 20), sp(0.0, 30)))
        // 오차가 모두 같으면 가중 평균 = 산술 평균.
        add("uniform_accuracy", listOf(sp(0.0, 0), sp(30.0, 5), sp(3000.0, 30), sp(6000.0, 40)))
        // 100m 초과 점 제외 / 완화 문턱(50~100m) 점 유지 — 이 두 개가 build 첫 필터의 경계다.
        add("over_fallback_accuracy", listOf(sp(0.0, 0), sp(5.0, 10), sp(5000.0, 15, accuracy = 500f), sp(10.0, 20), sp(15.0, 30)))
        listOf(99.5f, 100f, 100.5f).forEach { accuracy ->
            add("fallback_accuracy_$accuracy", listOf(sp(0.0, 0), sp(5.0, 10, accuracy = accuracy), sp(10.0, 20), sp(15.0, 30)))
        }
        // 머무름 → 이동 → 머무름.
        add(
            "stay_move_stay",
            (0..4).map { sp(it * 5.0, it * 10L) } +
                listOf(sp(1500.0, 50), sp(3000.0, 60)) +
                (0..5).map { sp(3000.0 + it * 5.0, 70 + it * 10L) },
        )
        // 처음부터 끝까지 이동만.
        add("move_only", (0..6).map { sp(it * 500.0, it * 10L) })
        // 뒤섞인 입력(정렬 확인). at 이 전부 다르다.
        add("shuffled_input", listOf(sp(6.0, 30), sp(0.0, 0), sp(4.0, 20), sp(2.0, 10), sp(8.0, 40)))

        fun typesOf(name: String): List<Any?> {
            @Suppress("UNCHECKED_CAST")
            val segments = cases.first { it["name"] == name }["segments"] as List<Map<String, Any?>>
            return segments.map { it["type"] }
        }
        fun segmentsOf(name: String): List<Map<String, Any?>> {
            @Suppress("UNCHECKED_CAST")
            return cases.first { it["name"] == name }["segments"] as List<Map<String, Any?>>
        }
        check(
            segmentsOf("stay_radius_39.0").first()["pointCount"] == 3 &&
                segmentsOf("stay_radius_41.0").first()["pointCount"] == 2,
        ) {
            "40m 반경 경계가 안 갈린다: 39m=${segmentsOf("stay_radius_39.0")} 41m=${segmentsOf("stay_radius_41.0")}"
        }
        check(!typesOf("min_stay_4").contains("STAY") && typesOf("min_stay_5").contains("STAY")) {
            "5분 최소 머무름 경계가 안 갈린다"
        }
        check(typesOf("single_outlier") == listOf("STAY")) { "한 점 튐이 머무름을 깼다" }
        check(typesOf("two_outliers").contains("MOVE")) { "연속 2점 이탈이 머무름을 안 끝냈다" }
        check(segmentsOf("over_fallback_accuracy").first()["pointCount"] == 4) { "100m 초과 점이 계산에 섞였다" }
        check(segmentsOf("fallback_accuracy_100.0").first()["pointCount"] == 4) { "완화 문턱(100m) 점이 빠졌다" }
        check(segmentsOf("fallback_accuracy_100.5").first()["pointCount"] == 3) { "완화 문턱 바로 위 점이 안 빠졌다" }
        run {
            val stay = segmentsOf("weighted_name").first { it["type"] == "STAY" }
            check(stay["nameLat"] != stay["lat"]) { "가중 평균이 단순 평균과 같다 — 가중치가 안 걸렸다" }
            val good = baseLat
            val nameOffset = kotlin.math.abs(stay["nameLat"] as Double - good)
            val meanOffset = kotlin.math.abs(stay["lat"] as Double - good)
            check(nameOffset < meanOffset) { "이름 좌표가 단순 평균보다 좋은 점에 가깝지 않다" }
        }
        check(typesOf("move_only").all { it == "MOVE" } && typesOf("move_only").isNotEmpty()) { "이동만 있는 하루가 MOVE 를 안 낸다" }
        check(cases.size >= 15) { "구간 케이스가 ${cases.size}개뿐이다" }
        return cases
    }

    // ==================================================================
    // 10. TrailCodec — 2000점 LTTB 솎기, 깨진 줄 복구
    // ==================================================================

    @Test
    fun `골든 - TrailCodec`() {
        val payload = linkedMapOf(
            "constants" to linkedMapOf<String, Any?>("maxPoints" to TrailCodec.MAX_POINTS),
            "capped" to generateCapped(),
            "decode" to generateDecode(),
        )
        writeGoldenIfPresent("trailCodec", toJson(payload))
    }

    /**
     * `capped` 케이스의 점을 만드는 **결정적 레시피**. 스위프트 테스트가 같은 식으로 같은 점을 다시
     * 만든다 — 점 11,000개를 JSON 에 적으면 파일이 수백 KB 가 되기 때문이다(브리프 Step 6).
     *
     * 32비트 LCG 정수 연산과 1e7 나눗셈만 쓴다. 두 언어의 32비트 곱셈은 같은 자리에서 넘치고
     * Double 나눗셈은 IEEE-754 라 결과가 비트까지 같다. **삼각함수를 안 쓰는 것이 중요하다** —
     * sin/cos 의 1 ULP 차이가 LTTB 의 면적 비교를 뒤집어 다른 인덱스를 고르게 할 수 있다.
     *
     * 같은 이유로 **첫 점의 위도를 정확히 0.0** 으로 둔다. `capped` 의 longitudeScale 은
     * `cos(첫 점 위도 × PI/180)` 인데, 0 이면 `cos(0.0) = 1.0` 이라 어떤 libm 에서도 같다.
     *
     * `at` 은 인덱스 그대로다 — 그래서 골든에 적는 출력 `at` 목록이 곧 **출력 인덱스 목록**이다.
     */
    private fun cappedPoints(count: Int): List<Fix> {
        var state = 20260922
        fun next(): Int {
            state = (state * 1103515245 + 12345) and 0x7FFFFFFF
            return state
        }
        var latMicro = 0L
        var lngMicro = 0L
        val points = ArrayList<Fix>(count)
        for (i in 0 until count) {
            points += Fix(latMicro / 1e7, lngMicro / 1e7, 10f, i.toLong(), 0f)
            latMicro += (next() % 2001 - 1000).toLong()
            lngMicro += (next() % 2001 - 1000).toLong()
        }
        check(points.first().lat == 0.0) { "첫 점의 위도가 정확히 0.0 이 아니다 — longitudeScale 이 결정적이지 않다" }
        return points
    }

    private fun generateCapped(): List<Map<String, Any?>> {
        val cases = mutableListOf<Map<String, Any?>>()
        for (count in listOf(1_999, 2_000, 2_001, 5_000)) {
            val points = cappedPoints(count)
            cases += linkedMapOf(
                "name" to "count_$count",
                "count" to count,
                "outputAts" to TrailCodec.capped(points).map { it.at },
            )
        }
        fun outputOf(name: String): List<*> = cases.first { it["name"] == name }["outputAts"] as List<*>
        check(outputOf("count_1999").size == 1_999 && outputOf("count_2000").size == 2_000) {
            "상한 이하인데 개수가 바뀌었다"
        }
        check(outputOf("count_2001").size == TrailCodec.MAX_POINTS && outputOf("count_5000").size == TrailCodec.MAX_POINTS) {
            "상한을 넘겼는데 정확히 ${TrailCodec.MAX_POINTS}개가 아니다"
        }
        check(outputOf("count_5000").first() == 0L && outputOf("count_5000").last() == 4_999L) {
            "출발점·도착점이 안 남았다"
        }
        check(outputOf("count_5000").distinct().size == TrailCodec.MAX_POINTS) { "같은 점이 두 번 뽑혔다" }
        return cases
    }

    /** 십진 정수·소수·지수만 허용한다. 자바 전용 표기(`1d`·`1f`·`0x1p3`·`Infinity`)를 걸러내려는 것이다. */
    private val decimalNumber = Regex("^[+-]?\\d+(\\.\\d+)?([eE][+-]?\\d+)?$")
    private val decimalInteger = Regex("^[+-]?\\d+$")

    private fun generateDecode(): List<Map<String, Any?>> {
        val cases = mutableListOf<Map<String, Any?>>()

        fun add(name: String, text: String) {
            // 코틀린과 스위프트의 숫자 파싱이 갈리는 글자를 골든에 싣지 않는다(판정 기록 3 의 사촌).
            //  - `"1d".toDoubleOrNull()` 은 코틀린에서 1.0 이지만 Swift `Double("1d")` 는 nil 이다.
            //  - 코틀린은 앞뒤 공백·`Infinity`·16진 부동소수도 받는다. Swift 는 아니다.
            //  - accuracy/speed 는 코틀린이 Float 로 읽으므로, Float 로 반올림되면서 값이 달라지는
            //    글자(예: "12.345")도 실으면 안 된다.
            check(!text.contains('\r')) { "$name: 말뭉치에 \\r 이 있다 — 코틀린 lineSequence 만 줄로 취급한다" }
            for (line in text.split("\n")) {
                val parts = line.split(',')
                if (parts.size != 5) continue
                for (i in 0..3) {
                    check((parts[i].toDoubleOrNull() != null) == decimalNumber.matches(parts[i])) {
                        "$name: 칸 $i 의 '${parts[i]}' 는 두 언어의 숫자 파싱이 갈릴 수 있는 글자다"
                    }
                }
                check((parts[4].toLongOrNull() != null) == decimalInteger.matches(parts[4])) {
                    "$name: 시각 칸의 '${parts[4]}' 는 두 언어의 정수 파싱이 갈릴 수 있는 글자다"
                }
                for (i in 2..3) {
                    val asFloat = parts[i].toFloatOrNull()?.toDouble()
                    check(asFloat == parts[i].toDoubleOrNull()) {
                        "$name: 칸 $i 의 '${parts[i]}' 는 Float($asFloat)와 Double(${parts[i].toDoubleOrNull()})이 갈린다"
                    }
                }
            }
            cases += linkedMapOf(
                "name" to name,
                "text" to text,
                "points" to TrailCodec.decode(text).map { fullFixJson(it) },
            )
        }

        val good = listOf(
            Fix(37.5665, 126.9780, 12.5f, 1_754_500_000_000L, 1.25f),
            Fix(0.0, 0.0, 5.0f, 1L, 0.0f),
            Fix(-33.86, 151.21, 25.0f, 1_700_000_000_123L, 3.5f),
        )
        val encoded = good.map { TrailCodec.encodeLine(it) }

        add("empty", "")
        add("single", encoded[0])
        add("three_lines", encoded.joinToString("\n"))
        add("trailing_newline", encoded.joinToString("\n") + "\n")
        add("leading_blank_line", "\n" + encoded.joinToString("\n"))
        add("blank_line_between", encoded[0] + "\n\n" + encoded[1])
        add("truncated_last_line", encoded[0] + "\n37.5,126.9,10.0")
        add("too_many_fields", encoded[0] + "\n37.5,126.9,10.0,0.0,100,200\n" + encoded[1])
        add("non_numeric", "abc,def,ghi,jkl,mno\n" + encoded[0])
        add("empty_fields", ",,,,\n" + encoded[0])
        add("partially_empty_field", "37.5,,10.0,0.0,100\n" + encoded[0])
        add("fractional_time", "37.5,126.9,10.0,0.0,1.5\n" + encoded[0])
        add("all_broken", "one\ntwo,three\nfour,five,six,seven")
        add("negative_and_exponent", "-33.86,151.21,5.0,0.0,-100\n1.5e2,-1.25e1,10.0,0.5,200")

        fun pointsOf(name: String): List<*> = cases.first { it["name"] == name }["points"] as List<*>
        check(pointsOf("empty").isEmpty() && pointsOf("all_broken").isEmpty()) { "빈 입력·전부 깨진 입력이 점을 냈다" }
        check(pointsOf("three_lines").size == 3) { "정상 세 줄이 세 점으로 안 돌아왔다" }
        check(pointsOf("trailing_newline").size == 3) { "끝 줄바꿈이 점을 하나 더 만들었다" }
        check(pointsOf("truncated_last_line").size == 1) { "잘린 줄이 안 버려졌거나 멀쩡한 줄까지 버렸다" }
        check(cases.size >= 8) { "decode 케이스가 ${cases.size}개뿐이다" }
        return cases
    }
}
