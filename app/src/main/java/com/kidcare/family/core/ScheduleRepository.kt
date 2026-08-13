package com.kidcare.family.core

import android.util.Log
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.MetadataChanges
import com.kidcare.family.core.model.RingerSettingsDoc
import com.kidcare.family.core.model.ScheduleDoc
import com.kidcare.family.logic.ScheduleRule
import kotlinx.coroutines.tasks.await

/**
 * 시간대 규칙(schedules/)과 벨소리 잠금 설정(settings/ringer)을 다룬다.
 *
 * 둘 다 firestore.rules 가 이미 덮는다 — schedules 는 "보호자 쓰기·멤버 읽기",
 * settings 는 Task 1 이 같은 규칙으로 추가했다. 이 파일 때문에 규칙을 새로 열
 * 필요가 없다.
 *
 * 실시간 구독([observeSchedules]/[observeRingerSettings])과 한 번 읽기
 * ([fetchSchedules]/[fetchRingerSettings]) 를 함께 둔다. 알람이 울릴 때
 * (ScheduleAlarmReceiver → ScheduleApplier) 는 그 순간에만 규칙이 필요하고
 * 처리가 끝나면 프로세스가 곧 다시 잠들 수 있으므로, 리스너를 새로 붙였다가
 * 반드시 떼야 하는 부담 없이 fetch 한 번으로 끝내는 쪽이 맞다. 실시간 구독은
 * 화면이 떠 있는 동안 값이 바뀌는 걸 바로 보여줘야 하는 규칙 관리 화면
 * (Task 9~10)이 쓴다.
 */
object ScheduleRepository {

    private const val TAG = "ScheduleRepository"

    private val db: FirebaseFirestore get() = FirebaseFirestore.getInstance()

    private fun schedules(familyId: String, childUid: String) =
        db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .collection("schedules")

    private fun legacySchedules(familyId: String) =
        db.collection("families").document(familyId).collection("schedules")

    private fun ringerSettingsRef(familyId: String, childUid: String) =
        db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .collection("settings").document("ringer")

    private fun legacyRingerSettingsRef(familyId: String) =
        db.collection("families").document(familyId)
            .collection("settings").document("ringer")

    /** 알람 처리·되돌리기 판정에 쓰는 한 번 읽기. enabled==false 인 규칙도 그대로 준다 —
     * 켜져 있는지 판단은 [com.kidcare.family.logic.ScheduleResolver] 의 몫이다. */
    suspend fun fetchSchedules(familyId: String, childUid: String): List<ScheduleDoc> {
        var documents = schedules(familyId, childUid).get().await().documents
        if (documents.isEmpty() && FamilyRepository.familySchemaVersion(familyId) < FamilyRepository.CURRENT_SCHEMA_VERSION) {
            documents = legacySchedules(familyId).get().await().documents
        }
        return documents.mapNotNull { doc ->
            doc.toObject(ScheduleDoc::class.java)?.copy(id = doc.id)
        }
    }

    suspend fun fetchRingerSettings(familyId: String, childUid: String): RingerSettingsDoc {
        val childDoc = ringerSettingsRef(familyId, childUid).get().await()
        if (childDoc.exists()) return childDoc.toObject(RingerSettingsDoc::class.java) ?: RingerSettingsDoc()
        if (FamilyRepository.familySchemaVersion(familyId) < FamilyRepository.CURRENT_SCHEMA_VERSION) {
            return legacyRingerSettingsRef(familyId).get().await()
                .toObject(RingerSettingsDoc::class.java) ?: RingerSettingsDoc()
        }
        return RingerSettingsDoc()
    }

    /** 새 규칙이면(id 가 비어 있으면) 문서를 새로 만들고, 아니면 그 ID 에 덮어쓴다.
     * 어느 쪽이든 만들어진/쓰인 문서의 ID 를 돌려준다. */
    suspend fun saveSchedule(familyId: String, childUid: String, doc: ScheduleDoc): String {
        val ref = if (doc.id.isEmpty()) schedules(familyId, childUid).document()
            else schedules(familyId, childUid).document(doc.id)
        // id 는 문서 ID 로만 쓰고 본문에는 담지 않는다 — 안 그러면 다음에 읽을 때
        // copy(id = doc.id) 가 덮어쓰기 전까지 문서 안에 중복된 값이 남는다.
        ref.set(doc.copy(id = "")).await()
        return ref.id
    }

    suspend fun deleteSchedule(familyId: String, childUid: String, id: String) {
        schedules(familyId, childUid).document(id).delete().await()
    }

    suspend fun saveRingerSettings(familyId: String, childUid: String, doc: RingerSettingsDoc) {
        ringerSettingsRef(familyId, childUid).set(doc).await()
    }

    /** [onError] 를 삼키지 않는 이유는 다른 observe* 함수들과 같다(SegmentRepository 참고) —
     * 색인 누락·권한 거부가 화면에 흔적 없이 사라지면 "그냥 빈 목록"과 구분이 안 된다.
     *
     * `fromCache` 의 뜻과 쓰임은 [EventRepository.observeEvents] 와 같다. */
    fun observeSchedules(
        familyId: String,
        childUid: String,
        onChange: (docs: List<ScheduleDoc>, fromCache: Boolean) -> Unit,
        onError: (Exception) -> Unit,
    ): ListenerRegistration =
        schedules(familyId, childUid).addSnapshotListener(MetadataChanges.INCLUDE) { snapshot, error ->
            if (error != null) {
                Log.w(TAG, "observeSchedules 실패: familyId=$familyId", error)
                onError(error)
                return@addSnapshotListener
            }
            val docs = snapshot?.documents?.mapNotNull { doc ->
                doc.toObject(ScheduleDoc::class.java)?.copy(id = doc.id)
            } ?: emptyList()
            onChange(docs, snapshot?.metadata?.isFromCache ?: true)
        }

    fun observeRingerSettings(
        familyId: String,
        childUid: String,
        onChange: (RingerSettingsDoc) -> Unit,
        onError: (Exception) -> Unit,
    ): ListenerRegistration =
        ringerSettingsRef(familyId, childUid).addSnapshotListener { snapshot, error ->
            if (error != null) {
                Log.w(TAG, "observeRingerSettings 실패: familyId=$familyId", error)
                onError(error)
                return@addSnapshotListener
            }
            onChange(snapshot?.toObject(RingerSettingsDoc::class.java) ?: RingerSettingsDoc())
        }
}

/**
 * [ScheduleDoc](Firestore 문서 표현) → [ScheduleRule](ScheduleResolver 가 쓰는 순수
 * 판정 모델). 두 클래스가 필드는 같은데도 나뉜 이유는 [ScheduleDoc] 문서 주석 참고.
 * [ScheduleApplier][com.kidcare.family.child.ScheduleApplier] 와
 * [CommandHandler][com.kidcare.family.child.CommandHandler] 가 각자 규칙을 읽어
 * 경계를 계산할 때 이 변환이 필요해서, 중복해 적지 않도록 여기 한 곳에 둔다.
 */
fun ScheduleDoc.toRule(): ScheduleRule = ScheduleRule(
    id = id,
    days = days.toSet(),
    startMinute = startMinute,
    endMinute = endMinute,
    mode = mode,
    enabled = enabled,
    priority = priority,
)
