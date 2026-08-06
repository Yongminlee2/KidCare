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
