package com.kidcare.family.core

import android.icu.util.ChineseCalendar
import android.icu.util.TimeZone
import android.util.Log
import com.kidcare.family.logic.Holiday
import com.kidcare.family.logic.KoreanHolidays
import com.kidcare.family.logic.LunarAnchors
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

/**
 * 그 해 공휴일을 계산해 준다. 음력 환산은 안드로이드가 들고 있는 ICU 달력을 쓴다.
 *
 * **표를 안 쓴 이유가 이 파일의 요점이다.** 설날·추석·부처님오신날은 음력이라
 * 해마다 옮겨 다니는데, 몇 해치를 코드에 적어 두면 그 해가 지나는 순간 앱이 조용히
 * 틀린다 — 부모는 공휴일에 쉬는 줄 알고 있는데 아이 폰만 평일처럼 무음이 된다.
 * [ChineseCalendar] 는 안드로이드 7(API 24)부터 기기에 들어 있고 천문 계산으로
 * 음력을 뽑으므로 표를 갱신할 일이 없다.
 *
 * 한계 하나는 알고 쓴다: 우리 음력은 한국 시각(UTC+9) 기준이고 ICU 의 계산은
 * 중국 시각(UTC+8) 기준이라, 삭(달의 위상)이 자정 언저리에 걸리는 드문 해에는
 * 하루가 어긋날 수 있다(20세기 이후 몇 차례). 그런 해에는 연휴가 하루 밀려 보이는데,
 * 이 앱에서 그 결과는 "쉬는 날 하루가 예약을 안 쉰다" 정도라 표를 손으로 관리하다
 * 통째로 틀리는 쪽보다 낫다고 봤다.
 */
object HolidayCalendar {

    private const val TAG = "HolidayCalendar"

    /** ICU 의 중국식 연호는 서기 + 2637 이다(기원전 2637년이 1년). */
    private const val CHINESE_ERA_OFFSET = 2637

    private val KOREA: ZoneId = ZoneId.of("Asia/Seoul")

    /** 해마다 한 번만 계산하면 되는 값이라 들고 있는다. 앱 수명 동안 몇 개 안 쌓인다. */
    private val cache = HashMap<Int, Map<LocalDate, Holiday>>()

    @Synchronized
    fun of(year: Int): Map<LocalDate, Holiday> = cache.getOrPut(year) {
        val anchors = anchorsOf(year) ?: return@getOrPut emptyMap()
        KoreanHolidays.of(year, anchors)
    }

    /**
     * [date] 언저리의 공휴일. 앞뒤 해까지 함께 주는 이유는 연말연시다 — 설날이 1월 초면
     * 연휴가 전해 12월로 넘어가고, 예약 판정은 늘 며칠 앞뒤를 함께 훑는다.
     */
    fun around(date: LocalDate): Set<LocalDate> =
        of(date.year - 1).keys + of(date.year).keys + of(date.year + 1).keys

    /** [from] 이후(당일 포함) 가장 이른 공휴일. 없으면 null — 화면이 다음 쉬는 날을 알려줄 때 쓴다. */
    fun next(from: LocalDate): Pair<LocalDate, Holiday>? =
        (of(from.year) + of(from.year + 1))
            .filterKeys { !it.isBefore(from) }
            .minByOrNull { it.key }
            ?.toPair()

    private fun anchorsOf(year: Int): LunarAnchors? = try {
        LunarAnchors(
            seollal = solarOf(year, lunarMonth = 1, lunarDay = 1),
            chuseok = solarOf(year, lunarMonth = 8, lunarDay = 15),
            buddha = solarOf(year, lunarMonth = 4, lunarDay = 8),
        ).also {
            // 해마다 한 번 찍힌다. 이 계산은 틀려도 예외가 안 나고 그냥 엉뚱한 날짜가
            // 되는 종류라, 실기기에서 눈으로 맞춰볼 수 있는 자리가 하나는 있어야 한다
            // (부모 화면의 '다음 쉬는 날' 한 줄이 같은 값을 보여주는 것도 같은 이유다).
            Log.i(TAG, "${'$'}year 년 음력 기준일: 설날 ${'$'}{it.seollal}, 추석 ${'$'}{it.chuseok}, 부처님오신날 ${'$'}{it.buddha}")
        }
    } catch (e: Exception) {
        // 기기의 ICU 가 이 달력을 못 다루는 경우다. 공휴일을 모르는 채로 도는 것이
        // 맞지, 넘겨짚은 날짜로 예약을 쉬게 하면 안 된다.
        Log.w(TAG, "음력 환산 실패 — ${year}년 공휴일을 비운다", e)
        null
    }

    /** 음력 [lunarMonth]월 [lunarDay]일(윤달 아님)의 양력 날짜. */
    private fun solarOf(year: Int, lunarMonth: Int, lunarDay: Int): LocalDate {
        val calendar = ChineseCalendar(TimeZone.getTimeZone("Asia/Seoul"), Locale.KOREA)
        calendar.clear()
        calendar.set(ChineseCalendar.EXTENDED_YEAR, year + CHINESE_ERA_OFFSET)
        // ICU 의 MONTH 는 0부터 센다. IS_LEAP_MONTH 를 0 으로 못 박아야 윤달이 아닌
        // 본달을 얻는다 — 윤5월이 있는 해에 이걸 빼면 엉뚱한 달이 나온다.
        calendar.set(ChineseCalendar.MONTH, lunarMonth - 1)
        calendar.set(ChineseCalendar.IS_LEAP_MONTH, 0)
        calendar.set(ChineseCalendar.DAY_OF_MONTH, lunarDay)
        return Instant.ofEpochMilli(calendar.timeInMillis).atZone(KOREA).toLocalDate()
    }
}
