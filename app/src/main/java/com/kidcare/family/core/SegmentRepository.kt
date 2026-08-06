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

    /**
     * 그 날의 원시 위치 점. 자녀 폰이 구간을 계산할 때만 쓴다.
     *
     * at 범위 + orderBy 조합은 복합 색인을 요구할 수 있다. 색인이 없으면 이 get() 이
     * FAILED_PRECONDITION 과 함께 색인 생성 URL 을 담은 예외를 던지는데, 여기서 잡지
     * 않고 그대로 위(SegmentUploader → TrackingService)로 올려보낸다 — 호출부가 예외
     * 객체 전체를 로그로 남기므로 그 URL 이 logcat 에서 사라지지 않는다.
     */
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
     *
     * 삭제와 추가를 한 WriteBatch 에 묶는 이유: 배치는 원자적으로 커밋되므로, 보호자
     * 화면의 리스너(observeSegmentsOfDay)는 "옛 문서가 지워지고 새 문서가 아직 안 들어온"
     * 중간 상태를 절대 보지 못한다. 스냅샷은 커밋 전(옛 상태 그대로) 아니면 커밋 후
     * (새 상태 그대로) 둘 중 하나만 전달되고, 화면이 깜빡이며 "하루가 통째로 비었다"로
     * 보이는 순간은 없다.
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
     * 않아 "그냥 비어 있는 하루"와 구분되지 않는다. 여기서도 예외 객체를 그대로
     * Log.w 에 넘긴다 — dayKey + startAt 색인이 없을 때 FAILED_PRECONDITION 이 담고
     * 오는 색인 생성 URL 이 message 만 잘라 찍으면 잘려 나갈 수 있기 때문이다.
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
