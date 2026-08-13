package com.kidcare.family.core

import android.util.Log
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.MetadataChanges
import com.kidcare.family.core.model.PlaceDoc
import com.kidcare.family.logic.Place
import kotlinx.coroutines.tasks.await

/**
 * 장소(places/)를 다룬다. [ScheduleRepository] 와 같은 모양이다.
 *
 * ## 자녀 폰은 구독하지 않는다
 *
 * 한 번 읽기([fetchPlaces])와 실시간 구독([observePlaces])을 함께 두고, 쓰는 쪽을
 * 역할별로 나눈다.
 *
 * - **자녀 폰**은 [fetchPlaces] 만 쓴다. 부르는 순간이 둘뿐이다 —
 *   [com.kidcare.family.child.TrackingService] 가 뜰 때와, 부모가 장소를 고친 뒤
 *   보내는 `sync_rules` 명령을 받았을 때([com.kidcare.family.child.CommandHandler]).
 *   장소는 몇 달에 한 번 바뀌는데 그걸 위해 리스너를 상시 붙들고 있으면, 붙어 있는
 *   내내 읽기가 조용히 늘고(무료 한도, docs/known-issues.md 12번) 리스너를 떼는
 *   책임도 하나 더 생긴다. 예약 규칙에서 내린 것과 같은 판단이다(4단계 Task 8).
 * - **보호자 화면**은 [observePlaces] 로 구독한다. 편집 중인 화면이라 방금 저장한
 *   것이 목록에 바로 보여야 하고, 그 화면이 떠 있는 동안만 붙어 있다.
 *
 * 쓰기는 보호자만 허용된다(firestore.rules 의 places 블록). 이 파일 때문에 규칙을
 * 새로 열 필요가 없다.
 */
object PlaceRepository {

    private const val TAG = "PlaceRepository"

    private val db: FirebaseFirestore get() = FirebaseFirestore.getInstance()

    private fun places(familyId: String, childUid: String) =
        db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .collection("places")

    private fun legacyPlaces(familyId: String) =
        db.collection("families").document(familyId).collection("places")

    /** 자녀 폰의 지오펜스 등록·판정이 쓰는 한 번 읽기. */
    suspend fun fetchPlaces(familyId: String, childUid: String): List<PlaceDoc> {
        var documents = places(familyId, childUid).get().await().documents
        if (documents.isEmpty() && FamilyRepository.familySchemaVersion(familyId) < FamilyRepository.CURRENT_SCHEMA_VERSION) {
            documents = legacyPlaces(familyId).get().await().documents
        }
        return documents.mapNotNull { doc ->
            doc.toObject(PlaceDoc::class.java)?.copy(id = doc.id)
        }
    }

    /**
     * 새 장소면(id 가 비어 있으면) 문서를 새로 만들고, 아니면 그 ID 에 덮어쓴다.
     * [ScheduleRepository.saveSchedule] 과 같은 계약이다 — 만들기와 고치기가 한 경로다.
     */
    suspend fun savePlace(familyId: String, childUid: String, doc: PlaceDoc): String {
        val ref = if (doc.id.isEmpty()) places(familyId, childUid).document()
            else places(familyId, childUid).document(doc.id)
        // id 는 문서 ID 로만 쓰고 본문에는 담지 않는다 — 읽을 때 copy(id = doc.id) 가
        // 채우므로, 본문에 남겨두면 같은 값이 두 군데 있게 된다.
        ref.set(doc.copy(id = "")).await()
        return ref.id
    }

    suspend fun deletePlace(familyId: String, childUid: String, id: String) {
        places(familyId, childUid).document(id).delete().await()
    }

    /** [onError] 를 삼키지 않는 이유는 다른 observe* 와 같다 — 권한 거부가 흔적 없이
     *  사라지면 "그냥 장소가 없음"과 구분이 안 된다.
     *
     *  `fromCache` 의 뜻과 쓰임은 [EventRepository.observeEvents] 와 같다. */
    fun observePlaces(
        familyId: String,
        childUid: String,
        onChange: (docs: List<PlaceDoc>, fromCache: Boolean) -> Unit,
        onError: (Exception) -> Unit,
    ): ListenerRegistration =
        places(familyId, childUid).addSnapshotListener(MetadataChanges.INCLUDE) { snapshot, error ->
            if (error != null) {
                Log.w(TAG, "observePlaces 실패: familyId=$familyId", error)
                onError(error)
                return@addSnapshotListener
            }
            val docs = snapshot?.documents?.mapNotNull { doc ->
                doc.toObject(PlaceDoc::class.java)?.copy(id = doc.id)
            } ?: emptyList()
            onChange(docs, snapshot?.metadata?.isFromCache ?: true)
        }
}

/**
 * [PlaceDoc](Firestore 문서 표현) → [Place]([com.kidcare.family.logic.GeofenceEvaluator]
 * 가 쓰는 순수 판정 모델). 두 클래스가 나뉜 이유는 [PlaceDoc] 문서 주석 참고.
 * `ScheduleDoc.toRule()` 과 같은 자리에 같은 이유로 둔다 — 변환이 여러 곳에 흩어지면
 * 한쪽만 고치고 잊는다.
 */
fun PlaceDoc.toPlace(): Place = Place(
    id = id,
    name = name,
    lat = lat,
    lng = lng,
    radiusMeters = radiusMeters,
    notifyEnter = notifyEnter,
    notifyExit = notifyExit,
)
