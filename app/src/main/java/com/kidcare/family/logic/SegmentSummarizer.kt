package com.kidcare.family.logic

import java.time.Instant
import java.time.ZoneId
import java.util.Locale

/**
 * 구간을 화면에 쓸 조각으로 바꾼다.
 *
 * 문장은 여기서 만들지 않는다. 기간과 거리는 **값**으로 돌려주고 화면
 * (guardian/TimelineText)이 strings.xml 로 번역한다 — 예전에는 "1시간 30분"·
 * "10m 미만"을 여기서 직접 만들어, 폰 언어를 바꿔도 이 조각들만 한국어로 남았다.
 *
 * 안드로이드 API 에 의존하지 않는다(java.time 은 minSdk 26 에서 쓸 수 있다).
 */
object SegmentSummarizer {

    sealed interface Duration {
        data object UnderMinute : Duration
        data class Minutes(val minutes: Long) : Duration
        data class Hours(val hours: Long) : Duration
        data class HoursMinutes(val hours: Long, val minutes: Long) : Duration
    }

    sealed interface Distance {
        data object UnderTenMeters : Distance
        data class Meters(val meters: Int) : Distance
        data class Kilometers(val kilometers: Double) : Distance
    }

    /** "14:10~15:40". 숫자뿐이라 번역할 것이 없다. 날짜는 화면의 날짜 헤더가 담당한다. */
    fun timeRange(segment: Segment, zone: ZoneId): String {
        val start = Instant.ofEpochMilli(segment.startAt).atZone(zone)
        val end = Instant.ofEpochMilli(segment.endAt).atZone(zone)
        return String.format(Locale.ROOT, "%02d:%02d~%02d:%02d", start.hour, start.minute, end.hour, end.minute)
    }

    fun duration(millis: Long): Duration {
        val totalMinutes = millis / 60_000L
        if (totalMinutes < 1) return Duration.UnderMinute
        val hours = totalMinutes / 60
        val minutes = totalMinutes % 60
        return when {
            hours == 0L -> Duration.Minutes(minutes)
            minutes == 0L -> Duration.Hours(hours)
            else -> Duration.HoursMinutes(hours, minutes)
        }
    }

    /**
     * 1km 이상은 킬로미터(소수 한 자리는 화면 서식이 자른다), 미만은 십 단위로 내림한 미터.
     *
     * 미터를 1 단위까지 보여주면 GPS 오차(최대 100m 까지 받아들인다)보다 정밀해 보여
     * 없는 정확도를 있는 척하게 된다.
     */
    fun distance(meters: Double): Distance {
        if (meters >= 1000.0) return Distance.Kilometers(meters / 1000.0)
        val tens = (meters / 10).toInt() * 10
        return if (tens < 10) Distance.UnderTenMeters else Distance.Meters(tens)
    }
}
