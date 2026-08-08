package com.kidcare.family.core

import com.google.firebase.firestore.FirebaseFirestore
import com.kidcare.family.core.model.TrailDoc
import java.io.IOException
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

    /**
     * 그 날 기록이 없으면(아직 안 올렸거나 아이가 꺼져 있던 날) null 이다.
     *
     * ## 오프라인에서 "없다"고 말하지 않는다
     *
     * `get()` 은 서버에 못 닿으면 캐시로 답한다. 그 날 문서가 캐시에 없으면 **"없는
     * 문서"로 답하고 예외도 안 던진다** — 부모가 지하철에서 어제로 넘기면 화면 한가운데에
     * "이 날은 기록이 없어요"가 뜬다. 아이가 하루 종일 걸어 다닌 날에 대고 하는 말이다.
     *
     * 둘을 가르는 값이 `metadata.isFromCache` 하나뿐이라 여기서 본다(같은 판단이
     * [FamilyRepository.joinFamily] 에도 있다 — 거기서도 캐시 답을 "코드가 틀렸다"로
     * 읽으면 아이가 멀쩡한 코드를 계속 다시 입력하게 된다).
     *
     * [IOException] 을 던지는 이유: [errorMessage] 가 이미 IOException 을
     * "인터넷에 연결할 수 없어요"로 옮긴다. 새 예외 타입과 새 문구를 만들면 같은 뜻이
     * 두 벌이 된다. **서버에 못 닿은 것은 실제로 입출력 실패가 맞다.**
     *
     * 통신이 되는 동안에는 동작이 하나도 안 바뀐다 — 서버가 확인해 준 "없음"은
     * `isFromCache == false` 라 그대로 null 로 나간다.
     */
    suspend fun fetch(familyId: String, childUid: String, dayKey: String): TrailDoc? {
        val snapshot = trailRef(familyId, childUid, dayKey).get().await()
        if (!snapshot.exists() && snapshot.metadata.isFromCache) {
            throw IOException("오프라인이라 $dayKey 기록을 못 읽었다(캐시에 없음)")
        }
        return snapshot.toObject(TrailDoc::class.java)
    }
}
