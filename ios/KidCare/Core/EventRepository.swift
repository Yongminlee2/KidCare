import FirebaseFirestore
import Foundation
import os

/// events/ 는 방향이 반대인 컬렉션이다 — **아이 폰이 만들고 보호자가 읽는다.** 정본은 안드로이드
/// `core/EventRepository.kt`. 만드는 쪽(`add`)은 아이 폰이, 읽는 쪽과 읽음 표시는 보호자가 쓴다.
/// 한 파일에 둔 이유는 규칙 계약이 세 함수에 걸쳐 있기 때문이다(`:11-27`) — 흩어 놓으면 한쪽만
/// 고치고 잊는다.
enum EventRepository {

    /// 한 번에 들고 오는 최근 사건 수(`EventRepository.kt:45`). 목록 화면과 안드로이드 상시 수신 서비스가
    /// 같은 창을 본다. 창이 없으면 구독할 때마다 쌓인 사건 전부를 다시 읽는다(무료 한도).
    static let recentLimit = 100

    /// 규칙의 `hasOnly(['read'])` 와 **글자 그대로** 같아야 한다(:32-33).
    private static let fieldRead = "read"

    private static var db: Firestore { Firestore.firestore() }
    private static let logger = Logger(subsystem: "com.kidcare.family", category: "EventRepository")

    private static func events(_ familyId: String) -> CollectionReference {
        db.collection("families").document(familyId).collection("events")
    }

    /// 최근 사건을 **최신순**으로 구독한다(:86-112).
    ///
    /// `at` 으로 **거르지 않는다**(:63-75). 아이 폰 시계가 어긋난 채 적힌 at 은 보호자 폰이 정한 문턱과 어긋나
    /// 목록에 영영 안 나타난다. 정렬은 거르기가 아니라 줄 세우기라서 그런 위험이 없다.
    /// `includeMetadataChanges: true` 가 빠지면 빈 캐시 결과 뒤에 오는 빈 서버 결과를 못 받아 "불러오는 중"에
    /// 갇힌다(:97-99). `fromCache` 가 false 일 때만 "없어요"를 단언할 수 있다(`ListLoad`).
    static func observeEvents(
        familyId: String,
        childUid: String?,
        onChange: @escaping (_ docs: [EventDoc], _ fromCache: Bool) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        let base: Query = childUid.map { events(familyId).whereField("childUid", isEqualTo: $0) } ?? events(familyId)
        return base
            .order(by: "at", descending: true)
            .limit(to: recentLimit)
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error {
                    logger.warning("observeEvents 실패: familyId=\(familyId, privacy: .public) \(String(describing: error), privacy: .public)")
                    onError(error)
                    return
                }
                let docs = snapshot?.documents.map { EventDoc(id: $0.documentID, $0.data()) } ?? []
                onChange(docs, snapshot?.metadata.isFromCache ?? true)
            }
    }

    /// 사건 하나를 남긴다. 만들어진 문서 ID 를 돌려준다. 정본 `:52-58`.
    ///
    /// **실패를 삼키지 않는다.** 부르는 쪽(`PlaceWatcher.onFix` → `TrackingCoordinator`)이 로그로
    /// 남기고 다음 위치 점에서 다시 시도한다 — 이벤트 하나를 못 썼다고 위치 수집이 멈추면 안 된다
    /// (`PlaceWatcher.kt:110-112`). 오프라인 재시도는 Firestore SDK 의 큐가 이미 한다(설계서 §6.5).
    @discardableResult
    static func add(familyId: String, doc: EventDoc) async throws -> String {
        let ref = events(familyId).document()
        // id 는 문서 ID 로만 쓴다(`:55`, PlaceRepository.savePlace 와 같은 규율).
        try await ref.setData(doc.firestoreData)
        return ref.documentID
    }

    /// 읽음 표시. **`read` 필드 하나만** 쓴다(:114-130). `readAt` 같은 것을 함께 적으면 쓰기가 통째로 거부되고
    /// 안 읽음 표시가 영영 안 지워진다. 일괄 쓰기라 하나가 실패하면 전부 실패하는데, 대가는 "다음에 탭을 열면
    /// 한 번 더 시도"뿐이고 낱개로 쪼개면 쓰기 수가 줄 수만큼 는다.
    static func markRead(familyId: String, ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let batch = db.batch()
        for id in ids {
            batch.updateData([fieldRead: true], forDocument: events(familyId).document(id))
        }
        try await batch.commit()
    }
}
