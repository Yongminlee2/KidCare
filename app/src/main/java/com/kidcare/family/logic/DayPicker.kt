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
