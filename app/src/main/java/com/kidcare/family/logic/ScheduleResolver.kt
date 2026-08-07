package com.kidcare.family.logic

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * 시간대 규칙 하나. 설계서 §4.3.
 *
 * [days] 는 요일 집합이다. `java.time.DayOfWeek.value` 와 같은 규칙으로
 * 1=월 ~ 7=일 (DayPicker 의 weekdayNames 인덱싱과 동일).
 * [startMinute]/[endMinute] 은 자정부터 잰 분(0..1439). `endMinute <= startMinute`
 * 이면 자정을 넘는 규칙이다 (예: 22:00~07:00 은 1320..420).
 * 요일은 항상 **시작 시각이 속한 날** 기준으로 판정한다 — "평일 22:00~07:00" 은
 * 금요일 밤에 시작해 토요일 새벽까지 이어지지만, 토요일은 요일 집합에 없다.
 *
 * 이 파일은 입력을 검증하지 않는다: [days] 가 비어 있으면 그 규칙은 조용히 아무
 * 날에도 적용되지 않고, [startMinute]/[endMinute] 이 0..1439 밖이면 구간이 그만큼
 * 밀릴 뿐 예외를 던지지 않는다. 둘 다 규칙 편집 화면
 * (`guardian/ScheduleFragment`)에서 이미 막혀 있다: 요일이 비면 저장 자체를 거부하고
 * (`onSaveClicked` 의 첫 관문, `schedule_editor_days_required`), 시각은 시각 선택기
 * (`MaterialTimePicker`)로만 고를 수 있어 0..1439 밖의 값이 들어올 길이 없다.
 * 그래서 여기서는 방어를 겹치지 않는다.
 */
data class ScheduleRule(
    val id: String,
    val days: Set<Int>,
    val startMinute: Int,
    val endMinute: Int,
    val mode: String,
    val enabled: Boolean,
    val priority: Int,
)

/**
 * 어떤 순간의 판정 결과.
 *
 * [mode] 는 그 순간 강제되는 벨소리 모드(없으면 null).
 * [nextBoundaryMillis] 는 이 판정이 바뀌는 다음 시각(시작 또는 끝). 영원히 안 바뀌면 null.
 */
data class Resolution(val mode: String?, val nextBoundaryMillis: Long?)

/**
 * 시간대 규칙을 "지금 이 순간" 에 대해 해석한다.
 *
 * 분 단위(0..1439) 를 직접 비교하지 않는다. 자정을 넘는 규칙(22:00~07:00 같은)을 분으로
 * 비교하려 하면 "지금이 22시 이후이거나 7시 이전" 같은 조건이 경계마다 생겨나고,
 * 요일까지 얽히면 (자정 넘어 다음날로 이어지는데 요일은 어제 기준) 실수하기 딱 좋다.
 *
 * 대신 규칙을 후보 날짜들에 대해 **구체적인 [시작, 끝) 밀리초 구간**으로 펼친 뒤,
 * 그 구간에 지금 시각이 들어있는지만 본다. 자정 넘김은 "끝을 다음 날로 넘긴다"는
 * 한 줄로 끝나고, 요일 판정은 "그 구간이 시작하는 날의 요일"이라는 정의를 그대로 코드로
 * 옮기면 된다.
 *
 * 안드로이드 API 에 의존하지 않는다. JVM 단위 테스트 대상 — ZoneId 와 시각(millis)은
 * 항상 인자로 받고, ZoneId.systemDefault()/System.currentTimeMillis() 는 쓰지 않는다.
 */
object ScheduleResolver {

    /** [nextBoundaryMillis] 를 찾으려고 앞으로 훑는 최대 일수. 규칙은 최대 7일 주기(요일)
     * 이므로 이론상 8일 안에 반드시 다음 시작이나 끝을 만난다. 여유를 둬서 10일로 잡는다.
     * 이 안에 못 찾으면(=활성 규칙이 전혀 없으면) null 을 돌려준다. */
    private const val SEARCH_HORIZON_DAYS = 10L

    /** 규칙 하나가 특정 날짜에 시작할 때 만드는 [시작, 끝) 구간. 자정을 넘으면 끝이 다음 날. */
    private data class Interval(val rule: ScheduleRule, val startAt: Long, val endAt: Long)

    /** [rule] 이 [anchorDate] 에 시작한다고 볼 때의 구간. 그 날 요일이 days 에 없으면 null. */
    private fun intervalStartingOn(rule: ScheduleRule, anchorDate: LocalDate, zone: ZoneId): Interval? {
        val weekday = anchorDate.dayOfWeek.value // 1=월 ~ 7=일, days 와 같은 규칙
        if (weekday !in rule.days) return null
        val dayStart = anchorDate.atStartOfDay(zone).toInstant().toEpochMilli()
        val startAt = dayStart + rule.startMinute * MINUTE_MILLIS
        // 자정을 넘는 규칙: 끝이 시작보다 이르거나 같으면 다음 날로 넘긴다.
        // startMinute == endMinute 인 경우도 이 분기를 탄다 — 그러면 [시작, 끝) 이
        // 정확히 24시간짜리 구간이 되어 "항상 적용" 이 된다. 이는 의도된 동작이다:
        // "00:00~00:00 무음" 처럼 부모가 하루 종일을 뜻하려고 같은 시각을 넣는 것은
        // 말이 되는 입력이다. 다만 부모가 실수로 두 칸에 같은 시각을 잘못 눌러도
        // 똑같이 하루 종일 무음이 되므로, 그 구분은 이 파일이 아니라 화면이 한다:
        // 규칙 입력 화면(`guardian/ScheduleFragment.onSaveClicked`)이 저장 전에
        // "하루 종일로 저장할까요?" 확인을 띄우고(schedule_allday_*), 목록과 편집
        // 판은 그 규칙을 "하루 종일 (00:00부터 24시간)"으로 적어 준다
        // (`ScheduleText.rangeText`).
        val endMinuteAbsolute = if (rule.endMinute <= rule.startMinute) {
            rule.endMinute + MINUTES_PER_DAY
        } else {
            rule.endMinute
        }
        val endAt = dayStart + endMinuteAbsolute * MINUTE_MILLIS
        return Interval(rule, startAt, endAt)
    }

    private const val MINUTES_PER_DAY = 24 * 60
    private const val MINUTE_MILLIS = 60_000L

    /** [rule] 이 만들어낼 수 있는 모든 구간을, [center] 를 기준으로 [daysBefore]~[daysAfter] 범위의
     * 시작 날짜들에 대해 펼친다. enabled == false 규칙은 아예 펼치지 않는다. */
    private fun expand(
        rule: ScheduleRule,
        zone: ZoneId,
        center: LocalDate,
        daysBefore: Long,
        daysAfter: Long,
    ): List<Interval> {
        if (!rule.enabled) return emptyList()
        val result = mutableListOf<Interval>()
        var d = -daysBefore
        while (d <= daysAfter) {
            val anchor = center.plusDays(d)
            intervalStartingOn(rule, anchor, zone)?.let { result += it }
            d++
        }
        return result
    }

    fun resolveAt(rules: List<ScheduleRule>, atMillis: Long, zone: ZoneId): Resolution {
        val today = Instant.ofEpochMilli(atMillis).atZone(zone).toLocalDate()

        // 지금 시각을 포함하는 구간 후보: 오늘과 어제 시작한 것만 보면 충분하다.
        // 자정 넘김 규칙이라도 길이는 최대 24시간(시작==끝이면 정확히 24시간, 그 외엔
        // 그보다 짧다)을 넘지 않으므로, 그저께 시작한 구간이 오늘까지 이어질 수는 없다.
        val activeCandidates = rules.flatMap { expand(it, zone, today, daysBefore = 1, daysAfter = 0) }
            .filter { atMillis >= it.startAt && atMillis < it.endAt }

        val winner = activeCandidates
            .sortedWith(compareByDescending<Interval> { it.rule.priority }.thenByDescending { it.startAt })
            .firstOrNull()

        // 다음 경계: 활성/비활성 규칙 모두의 시작·끝 중, 지금보다 뒤에 있는 가장 이른 것.
        // 앞으로 SEARCH_HORIZON_DAYS 일치를 펼쳐서 찾는다 — 요일 주기가 7일이라 그 안에
        // 반드시 다음 시작을 만나거나, 활성 규칙이 없으면 끝까지 못 찾고 null 이 된다.
        val allNearby = rules.flatMap {
            expand(it, zone, today, daysBefore = 1, daysAfter = SEARCH_HORIZON_DAYS)
        }
        val nextBoundary = allNearby
            .flatMap { listOf(it.startAt, it.endAt) }
            .filter { it > atMillis }
            .minOrNull()

        return Resolution(mode = winner?.rule?.mode, nextBoundaryMillis = nextBoundary)
    }

    fun overlapsOf(rules: List<ScheduleRule>, candidate: ScheduleRule): List<ScheduleRule> {
        // 한 주(요일 주기)를 통째로 펼쳐서 비교한다. 기준일은 아무 날이나 상관없다 —
        // 7일 전부를 시작일 후보로 훑으면 요일 조합에 관계없이 모든 겹침을 잡아낸다.
        val anchor = LocalDate.of(2000, 1, 3) // 임의의 월요일. 요일만 맞으면 어떤 주여도 된다.
        val zone = ZoneId.of("UTC") // 겹침 판정은 규칙끼리의 상대 위치만 보므로 시간대는 무관하다.

        // candidate 는 자기 자신의 enabled 값과 무관하게 항상 켜진 것으로 취급한다
        // (.copy(enabled = true)). 이건 "저장 전 겹침 경고" 용도라서 그렇다 — 부모가
        // 지금 꺼 둔 규칙을 편집하는 중이어도, 나중에 켰을 때 다른 규칙과 부딪힐지는
        // 미리 알고 싶어한다. 반대로 비교 대상인 other 쪽은 아래에서 enabled 를 그대로
        // 걸러낸다: 이미 꺼져 있는 다른 규칙과는 지금 겹쳐도 경고할 대상이 아니다.
        val candidateIntervals = expand(candidate.copy(enabled = true), zone, anchor, daysBefore = 0, daysAfter = 6)
        if (candidateIntervals.isEmpty()) return emptyList()

        return rules.filter { other ->
            if (other.id == candidate.id) return@filter false
            if (!other.enabled) return@filter false
            val otherIntervals = expand(other, zone, anchor, daysBefore = 0, daysAfter = 6)
            otherIntervals.any { o -> candidateIntervals.any { c -> intervalsOverlap(o, c) } }
        }
    }

    private fun intervalsOverlap(a: Interval, b: Interval): Boolean =
        a.startAt < b.endAt && b.startAt < a.endAt
}
