package com.kidcare.family.core

import com.google.firebase.firestore.FirebaseFirestore
import com.kidcare.family.core.model.TrailDoc
import kotlinx.coroutines.tasks.await

/**
 * 하루치 이동 기록(`children/{childUid}/trails/{dayKey}`)을 다룬다. 옛
 * `SegmentRepository`(points 읽기 + segments 하루 교체)를 대신한다.
 *
 * 쓰기는 자녀 폰만, 읽기는 양쪽 다. firestore.rules 의 trails 규칙이
 * 옛 points 규칙과 같은 모양(자녀 쓰기·멤버 읽기)이라 방향은 그대로다.
 *
 * **구독(addSnapshotListener)을 아예 두지 않는다.** 옛 `observeSegmentsOfDay` 는
 * 보호자 화면이 떠 있는 내내 붙어 있었는데, 그러면 자녀 폰이 문서를 쓸 때마다
 * 읽기가 자동으로 발생한다. 지금은 보호자가 화면을 열 때와 '지금 위치 확인'을
 * 눌렀을 때만 [fetch] 로 한 번씩 읽는다 — 언제 얼마나 읽는지가 호출부 코드에
 * 그대로 보이는 쪽이, 무료 한도를 지켜야 하는 앱에서는 훨씬 안전하다.
 */
object TrailRepository {

    private val db: FirebaseFirestore get() = FirebaseFirestore.getInstance()

    private fun trailRef(familyId: String, childUid: String, dayKey: String) =
        db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .collection("trails").document(dayKey)

    /** 그 날 문서를 통째로 덮어쓴다. 자녀 폰만 부른다(규칙이 그렇게 막혀 있다). */
    suspend fun save(familyId: String, childUid: String, doc: TrailDoc) {
        trailRef(familyId, childUid, doc.dayKey).set(doc).await()
    }

    /** 그 날 기록이 없으면(아직 안 올렸거나 아이가 꺼져 있던 날) null 이다. */
    suspend fun fetch(familyId: String, childUid: String, dayKey: String): TrailDoc? =
        trailRef(familyId, childUid, dayKey).get().await().toObject(TrailDoc::class.java)
}
