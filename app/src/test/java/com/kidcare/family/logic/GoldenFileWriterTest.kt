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
        is Float -> value.toDouble().toString()
        is Double -> value.toString()
        is Map<*, *> -> value.entries.joinToString(",", "{", "}") { (k, v) -> "${jsonString(k.toString())}:${toJson(v)}" }
        is List<*> -> value.joinToString(",", "[", "]") { toJson(it) }
        else -> error("골든 JSON 라이터가 ${value::class} 를 모른다")
    }

    private fun repoRoot(): File {
        var dir = File(System.getProperty("user.dir") ?: ".").absoluteFile
        while (true) {
            if (File(dir, "settings.gradle.kts").exists() && File(dir, "ios").isDirectory) return dir
            dir = dir.parentFile ?: error("저장소 루트를 못 찾았다 (settings.gradle.kts 와 ios/ 가 있는 폴더가 없다)")
        }
    }

    private fun goldenFile(name: String): File = File(repoRoot(), "ios/KidCareTests/golden/$name.json")

    /** 내용이 이미 같으면 다시 쓰지 않는다 — git diff 를 매 실행마다 더럽히지 않으려고. */
    private fun writeIfChanged(file: File, content: String) {
        file.parentFile?.mkdirs()
        if (file.exists() && file.readText() == content) return
        file.writeText(content)
    }

    // ==================================================================
    // 1. ScheduleResolver — 자정 넘김·겹침·우선순위·공휴일·여러 시간대
    // ==================================================================

    @Test
    fun `골든 - ScheduleResolver`() {
        writeIfChanged(goldenFile("scheduleResolver"), toJson(generateScheduleResolver()))
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

    // ==================================================================
    // 2. RoutePathRefiner — 튐 제거·평활·문턱값 경계
    // ==================================================================

    @Test
    fun `골든 - RoutePathRefiner`() {
        writeIfChanged(goldenFile("routePathRefiner"), toJson(generateRoutePathRefiner()))
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

    /** A-B-C 세 변 길이(firstArm, secondArm, bridge)를 만족하는 평면 삼각형. C 는 A 의 정동쪽. */
    private fun triangle(firstArm: Double, secondArm: Double, bridge: Double): Triple<Pair<Double, Double>, Pair<Double, Double>, Pair<Double, Double>> {
        val a = baseLat to baseLng
        val c = offsetLatLng(a, bridge, 0.0)
        val x = (firstArm * firstArm - secondArm * secondArm + bridge * bridge) / (2 * bridge)
        val ySquared = (firstArm * firstArm - x * x).coerceAtLeast(0.0)
        val y = kotlin.math.sqrt(ySquared)
        val b = offsetLatLng(a, x, y)
        return Triple(a, b, c)
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
            // 팔 길이(25m) 경계. secondArm=40(안전), 다리=5(안전), 시간폭=5000(안전).
            listOf(24.9, 25.0, 25.1).forEach { arm ->
                val (a, b, c) = triangle(arm, 40.0, 5.0)
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
            // 우회비(4.0) 경계. 다리=15(자기 한계에 걸쳐 있음), 팔은 균등하게 조절.
            listOf(29.25, 30.0, 30.75).forEach { arm ->
                val (a, b, c) = triangle(arm, arm, 15.0)
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

        // --- 빈 입력. ---
        addCase("empty", emptyList())

        return cases
    }

    // ==================================================================
    // 3. KoreanHolidays — 2025~2030년 전체 공휴일
    // ==================================================================

    @Test
    fun `골든 - KoreanHolidays`() {
        writeIfChanged(goldenFile("koreanHolidays"), toJson(generateKoreanHolidays()))
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
    // 4. SegmentSummarizer — 경계값. 스위프트는 구조를 돌려주고 코틀린은 한국어 문장을
    // 돌려준다(Phase 2 의 의도된 차이). 그래서 코틀린이 **실제로 돌려준 문장**을 이 안에서
    // 파싱해 구조로 바꾼 다음 JSON 에 적는다 — 그래야 "실제 함수의 출력"을 대조하는
    // 것이지, 생성기가 로직을 다시 구현해 저 혼자와 대조하는 헛일이 되지 않는다.
    // ==================================================================

    @Test
    fun `골든 - SegmentSummarizer`() {
        writeIfChanged(goldenFile("segmentSummarizer"), toJson(generateSegmentSummarizer()))
    }

    private fun parseDurationText(text: String): Map<String, Any?> {
        Regex("^(\\d+)시간 (\\d+)분$").find(text)?.let {
            val (h, m) = it.destructured
            return linkedMapOf("millisText" to text, "case" to "hoursMinutes", "hours" to h.toInt(), "minutes" to m.toInt())
        }
        Regex("^(\\d+)시간$").find(text)?.let {
            return linkedMapOf("millisText" to text, "case" to "hours", "hours" to it.groupValues[1].toInt())
        }
        Regex("^(\\d+)분$").find(text)?.let {
            return linkedMapOf("millisText" to text, "case" to "minutes", "minutes" to it.groupValues[1].toInt())
        }
        if (text == "1분 미만") return linkedMapOf("millisText" to text, "case" to "underOneMinute")
        error("durationText 형식을 못 읽는다: '$text'")
    }

    /**
     * 여기서 만드는 맵의 키는 나중에 입력값("meters")과 합쳐진다 — 그래서 case 가 만드는
     * 미터 출력값은 일부러 "roundedMeters" 로 다르게 부른다. 둘 다 "meters" 로 두면
     * `Map` 합치기(`+`)에서 뒤에 합쳐지는 입력값이 이 출력값을 조용히 덮어써 버린다
     * (실제로 그 버그가 있었다 — 골든 파일에 십 단위로 내림된 결과 대신 원래 입력이
     * 그대로 찍혀 있었다).
     */
    private fun parseDistanceText(text: String): Map<String, Any?> {
        if (text == "10m 미만") return linkedMapOf("case" to "underTenMeters")
        if (text.endsWith("km")) return linkedMapOf("case" to "kilometers", "kilometers" to text.removeSuffix("km").toDouble())
        if (text.endsWith("m")) return linkedMapOf("case" to "meters", "roundedMeters" to text.removeSuffix("m").toInt())
        error("distanceText 형식을 못 읽는다: '$text'")
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
            val text = SegmentSummarizer.durationText(millis)
            parseDurationText(text) + mapOf("millis" to millis)
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
            val text = SegmentSummarizer.distanceText(meters)
            parseDistanceText(text) + mapOf("meters" to meters)
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
        writeIfChanged(goldenFile("routeWindows"), toJson(generateRouteWindows()))
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
}
