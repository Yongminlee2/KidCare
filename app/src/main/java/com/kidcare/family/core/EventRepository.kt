package com.kidcare.family.core

import android.util.Log
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.Query
import com.kidcare.family.core.model.EventDoc
import kotlinx.coroutines.tasks.await

/**
 * events/ 는 방향이 반대인 컬렉션이다 — **아이 폰이 만들고 부모가 읽는다.**
 *
 * 만드는 쪽([add])은 아이 폰이, 읽는 쪽([observeEvents])과 읽음 표시([markRead])는
 * 부모 폰이 쓴다. 한 파일에 둔 이유는 아래 규칙 계약이 세 함수에 걸쳐 있기 때문이다 —
 * 흩어 놓으면 한쪽만 고치고 잊는다.
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

    private const val TAG = "EventRepository"

    /** 문서의 읽음 필드 이름. 규칙의 `hasOnly(['read'])` 와 **글자 그대로** 같아야 한다. */
    private const val FIELD_READ = "read"

    /**
     * 한 번에 들고 오는 최근 사건 수.
     *
     * 목록 화면도 [com.kidcare.family.guardian.AlertService] 도 같은 창을 본다. 100 인
     * 이유: 규칙이 `at` 을 서버 시각 기준 과거 24시간 안으로 묶으므로 살아 있는 이벤트는
     * 사실상 하루치뿐이고, 하루 100건이 넘으려면 아이가 경계에 앉아 있어야 하는데 그건
     * [com.kidcare.family.logic.GeofenceEvaluator] 의 5분 중복 억제가 이미 막는다.
     * 창을 두는 진짜 이유는 비용이다 — 창이 없으면 서비스가 (재)시작될 때마다 쌓인
     * 이벤트 전부를 다시 읽는다(무료 한도, docs/known-issues.md 12번).
     */
    const val RECENT_LIMIT = 100L

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

    /**
     * 최근 사건을 **최신순**으로 구독한다. 알림 탭과 상시 수신 서비스가 같은 함수를 쓴다.
     *
     * ## `at` 으로 거르지 않는다 (여기가 지뢰다)
     *
     * "서비스가 다시 뜰 때 옛 사건으로 다시 알리지 않기"를 `whereGreaterThan("at", 시작
     * 시각)` 으로 푸는 것이 가장 자연스러운데, **그렇게 하면 안 된다.** 규칙(Task 1)이
     * `at` 을 서버 시각 기준 과거 24시간 ~ 미래 1시간 창으로 묶어 두었으므로 아이 폰
     * 시계가 조금 어긋난 채로 적힌 `at` 은 부모 폰이 정한 문턱과 어긋나고, 그 사건은
     * 목록에도 알림에도 **영영 안 나타난다.** 못 알리는 실패는 조용해서 알아챌 방법이
     * 없다 — 부모 눈에는 그냥 "오늘은 조용한 하루"다.
     *
     * 정렬(orderBy)은 거르기가 아니라 줄 세우기다. 값이 이상한 문서도 목록에 남고
     * 자리만 뒤로 갈 뿐이라 위 위험이 없다. 중복 알림 억제는 대신 "이미 알린 문서 ID"를
     * 부모 폰에 기억해 푼다([com.kidcare.family.guardian.AlertService]) — 그쪽이 틀렸을
     * 때의 대가가 **알림 한 번 더**여서 안전한 쪽으로 실패한다.
     *
     * [onError] 를 삼키지 않는 이유는 다른 observe* 와 같다 — 규칙 미게시로 인한
     * 권한 거부가 흔적 없이 사라지면 "그냥 사건이 없음"과 구분이 안 된다.
     *
     * [onChange] 의 `fromCache` 는 이 스냅샷이 **서버가 확인해 준 것인지 캐시본인지**다
     * (`QuerySnapshot.metadata.isFromCache`). 오프라인이면 계속 true 고, 온라인에서도
     * 리스너를 막 걸었을 때 캐시본이 한 번 먼저 온 뒤 서버본이 따라온다. 빈 목록에
     * "아직 온 알림이 없어요"라고 단언해도 되는 것은 **false 일 때뿐이다** —
     * [com.kidcare.family.guardian.ListLoad] 주석에 그 판단을 모아 뒀다.
     */
    fun observeEvents(
        familyId: String,
        onChange: (docs: List<EventDoc>, fromCache: Boolean) -> Unit,
        onError: (Exception) -> Unit,
    ): ListenerRegistration =
        events(familyId)
            .orderBy("at", Query.Direction.DESCENDING)
            .limit(RECENT_LIMIT)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    Log.w(TAG, "observeEvents 실패: familyId=$familyId", error)
                    onError(error)
                    return@addSnapshotListener
                }
                val docs = snapshot?.documents?.mapNotNull { doc ->
                    doc.toObject(EventDoc::class.java)?.copy(id = doc.id)
                } ?: emptyList()
                // snapshot 이 null 인 경우는 error 가 null 이 아닐 때뿐이라 위에서 이미
                // 걸러졌다. 그래도 남는 널 분기는 "아직 서버 확인이 아니다"로 읽는다.
                onChange(docs, snapshot?.metadata?.isFromCache ?: true)
            }

    /**
     * 읽음 표시. 목록을 연 순간 안 읽은 것들을 한꺼번에 넘기는 용도라 하나짜리 함수는
     * 따로 두지 않는다(빈 목록이면 아무 일도 하지 않으므로 "전부 읽음"도 이 함수 하나다).
     *
     * ## `read` 필드 **하나만** 쓴다
     *
     * 규칙의 events update 가 `affectedKeys().hasOnly(['read'])` 다. `readAt`,
     * `updatedAt` 같은 걸 인심 좋게 함께 적으면 그 쓰기는 통째로 거부되고, 부모 화면의
     * 안 읽음 표시는 영영 안 지워진다. 그래서 `set(merge)` 도 문서 객체 통째 쓰기도
     * 쓰지 않고 필드 이름을 하나만 대는 `update` 를 쓴다 — 필드를 하나 더 적고 싶어질
     * 때 이 주석이 먼저 눈에 띄게 하려는 것이다.
     *
     * 일괄 쓰기(batch)라 하나라도 실패하면(예: 그 사이 부모가 지운 문서) 전부 실패한다.
     * 그래도 낱개로 나누지 않는 이유: 읽음 표시는 사람이 볼 때마다 나가는 쓰기라
     * 낱개로 쪼개면 무료 한도의 쓰기 수가 줄 수에 비례해 늘고, 실패했을 때의 대가는
     * "다음에 화면을 다시 열면 한 번 더 시도한다"뿐이다.
     */
    suspend fun markRead(familyId: String, ids: List<String>) {
        if (ids.isEmpty()) return
        val batch = db.batch()
        ids.forEach { id -> batch.update(events(familyId).document(id), FIELD_READ, true) }
        batch.commit().await()
    }
}
