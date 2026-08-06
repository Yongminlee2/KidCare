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
