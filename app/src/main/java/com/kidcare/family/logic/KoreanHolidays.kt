package com.kidcare.family.logic

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.MonthDay

/**
 * 그 해 음력에서 오는 세 기준일. 양력으로 옮긴 값이다.
 *
 * 이 셋만 밖에서 받는 이유: 나머지 공휴일은 전부 날짜가 고정이고 대체공휴일은 규칙으로
 * 계산되는데, 음력 환산만은 천문 계산이라 순수 자바로 못 한다. 안드로이드 쪽 변환기는
 * [com.kidcare.family.core.HolidayCalendar] 에 있다 — 이 파일이 안드로이드를 안 보게
 * 잘라 둔 경계다(logic 패키지 규칙).
 */
data class LunarAnchors(
    /** 음력 1월 1일 (설날). */
    val seollal: LocalDate,
    /** 음력 8월 15일 (추석). */
    val chuseok: LocalDate,
    /** 음력 4월 8일 (부처님오신날). */
    val buddha: LocalDate,
)

/** 공휴일 이름. 화면 문구는 strings.xml 에 있으므로 여기서는 무슨 날인지만 말한다. */
enum class Holiday {
    NEW_YEAR, SEOLLAL, INDEPENDENCE, BUDDHA, CHILDREN, MEMORIAL,
    LIBERATION, CHUSEOK, FOUNDATION, HANGUL, CHRISTMAS, SUBSTITUTE,
}

/**
 * 한 해의 관공서 공휴일을 대체공휴일까지 포함해 만든다.
 *
 * 요일은 매년 같은 자리에 오지만 공휴일은 아니다 — 설날·추석·부처님오신날은 음력이라
 * 해마다 옮겨 다니고, 대체공휴일은 그 해 요일 배치에 따라 생겼다 없어진다. 그래서
 * 부모가 "공휴일엔 예약을 쉬어요"를 요일로는 절대 표현할 수 없고, 앱이 대신 계산해야
 * 한다. 이 파일이 그 계산이다.
 *
 * 대체공휴일 규칙(관공서의 공휴일에 관한 규정 제3조, 2023년 개정 기준):
 * - 설날·추석 연휴: 사흘 중 하나라도 **일요일**과 겹치면 하루 더 쉰다. 토요일은 아니다.
 * - 어린이날: 토요일·일요일 또는 **다른 공휴일**과 겹치면 하루 더 쉰다.
 * - 삼일절·광복절·개천절·한글날·부처님오신날·성탄절: 토요일이나 일요일과 겹치면 하루 더.
 * - 신정(1/1)과 현충일(6/6)은 대체공휴일이 없다.
 *
 * 대체공휴일 자리는 "그 다음의 첫 번째 비공휴일"인데, 여기서는 주말도 함께 건너뛴다.
 * 법문만 보면 토요일도 비공휴일이라 후보가 되지만, 대체공휴일은 쉬는 날을 채워주려고
 * 있는 제도라 실제 지정은 늘 평일이었다. 이 앱에서 하루가 어긋나면 "쉬는 날인데 폰이
 * 무음으로 바뀐다"가 되므로 실제 운영과 같게 맞춘다.
 */
object KoreanHolidays {

    private val NEW_YEAR = MonthDay.of(1, 1)
    private val INDEPENDENCE = MonthDay.of(3, 1)
    private val CHILDREN = MonthDay.of(5, 5)
    private val MEMORIAL = MonthDay.of(6, 6)
    private val LIBERATION = MonthDay.of(8, 15)
    private val FOUNDATION = MonthDay.of(10, 3)
    private val HANGUL = MonthDay.of(10, 9)
    private val CHRISTMAS = MonthDay.of(12, 25)

    private val WEEKEND = setOf(DayOfWeek.SATURDAY, DayOfWeek.SUNDAY)

    fun of(year: Int, anchors: LunarAnchors): Map<LocalDate, Holiday> {
        val days = linkedMapOf<LocalDate, Holiday>()

        days[NEW_YEAR.atYear(year)] = Holiday.NEW_YEAR
        days[INDEPENDENCE.atYear(year)] = Holiday.INDEPENDENCE
        days[CHILDREN.atYear(year)] = Holiday.CHILDREN
        days[MEMORIAL.atYear(year)] = Holiday.MEMORIAL
        days[LIBERATION.atYear(year)] = Holiday.LIBERATION
        days[FOUNDATION.atYear(year)] = Holiday.FOUNDATION
        days[HANGUL.atYear(year)] = Holiday.HANGUL
        days[CHRISTMAS.atYear(year)] = Holiday.CHRISTMAS

        // 설날·추석은 전날·당일·다음날 사흘이다. 부처님오신날은 하루.
        val seolRange = threeDays(anchors.seollal)
        val chuseokRange = threeDays(anchors.chuseok)
        seolRange.forEach { days[it] = Holiday.SEOLLAL }
        chuseokRange.forEach { days[it] = Holiday.CHUSEOK }
        // 어린이날과 겹치는 해가 있다(2025년이 그랬다). 먼저 넣은 어린이날을 덮지 않는다 —
        // 겹침은 아래 대체공휴일 판정이 따로 본다.
        days.putIfAbsent(anchors.buddha, Holiday.BUDDHA)

        val substitutes = mutableSetOf<LocalDate>()

        // 설·추석 연휴: 일요일과 겹칠 때만.
        listOf(seolRange, chuseokRange).forEach { range ->
            if (range.any { it.dayOfWeek == DayOfWeek.SUNDAY }) {
                substitutes += nextWorkday(range.last(), days.keys + substitutes)
            }
        }

        // 어린이날: 주말 또는 다른 공휴일과 겹칠 때.
        val childrensDay = CHILDREN.atYear(year)
        if (childrensDay.dayOfWeek in WEEKEND || childrensDay == anchors.buddha) {
            substitutes += nextWorkday(childrensDay, days.keys + substitutes)
        }

        // 나머지 대체 대상: 주말과 겹칠 때만.
        listOf(
            INDEPENDENCE.atYear(year), LIBERATION.atYear(year),
            FOUNDATION.atYear(year), HANGUL.atYear(year), CHRISTMAS.atYear(year),
            anchors.buddha,
        ).forEach { date ->
            // 부처님오신날이 어린이날과 같은 날이면 위에서 이미 하루를 넣었다. 두 번 넣지 않는다.
            if (date == childrensDay) return@forEach
            if (date.dayOfWeek in WEEKEND) {
                substitutes += nextWorkday(date, days.keys + substitutes)
            }
        }

        substitutes.forEach { days[it] = Holiday.SUBSTITUTE }
        return days
    }

    private fun threeDays(center: LocalDate) =
        listOf(center.minusDays(1), center, center.plusDays(1))

    /** [from] 다음날부터 훑어 공휴일도 주말도 아닌 첫 날. */
    private fun nextWorkday(from: LocalDate, taken: Set<LocalDate>): LocalDate {
        var d = from.plusDays(1)
        while (d in taken || d.dayOfWeek in WEEKEND) d = d.plusDays(1)
        return d
    }
}
