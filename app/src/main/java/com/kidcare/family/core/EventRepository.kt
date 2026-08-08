package com.kidcare.family.core

import com.google.firebase.firestore.FirebaseFirestore
import com.kidcare.family.core.model.EventDoc
import kotlinx.coroutines.tasks.await

/**
 * events/ 는 방향이 반대인 컬렉션이다 — **아이 폰이 만들고 부모가 읽는다.**
 *
 * 지금은 만드는 쪽([add])만 있다. 읽기·읽음 표시는 알림 탭(5단계 Task 4)이 여기에
 * 이어 붙인다. 쓰기만 있는 저장소를 미리 만든 이유는 두 곳이 곧 같은 쓰기를 하기
 * 때문이다 — 장소 도착·이탈([com.kidcare.family.child.PlaceWatcher])과 배터리·권한
 * 경고(Task 7). 그 둘이 각자 Firestore 를 직접 두드리면 아래 규칙 계약이 두 벌로
 * 갈라진다.
 *
 * ## 규칙과의 계약 (firestore.rules 의 events create)
 *
 * 세 가지가 서버에서 강제된다. 하나라도 어기면 **쓰기가 조용히 거부되고 부모는 그
 * 사건이 일어나지 않은 것으로 읽는다.**
 *
 * 1. `childUid == request.auth.uid` — 지금 로그인된 uid 를 그대로 넣어야 한다.
 * 2. `read == false` — 그래서 이 함수는 [EventDoc.read] 를 아예 건드리지 않는다.
 * 3. `at` 이 서버 시각 기준 과거 24시간 ~ 미래 1시간 안 — [EventDoc.at] 이 **Long
 *    밀리초**여야 하는 이유다(그 필드 주석 참고).
 */
object EventRepository {

    private val db: FirebaseFirestore get() = FirebaseFirestore.getInstance()

    private fun events(familyId: String) =
        db.collection("families").document(familyId).collection("events")

    /** 사건 하나를 남긴다. 만들어진 문서 ID 를 돌려준다. */
    suspend fun add(familyId: String, doc: EventDoc): String {
        val ref = events(familyId).document()
        // id 는 문서 ID 로만 쓴다(PlaceRepository.savePlace 와 같은 규율).
        ref.set(doc.copy(id = "")).await()
        return ref.id
    }
}
