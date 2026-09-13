import FirebaseFirestore
import Foundation

/// 하루치 이동 기록(`children/{childUid}/trails/{dayKey}`)을 읽는다. 정본은 안드로이드
/// `core/TrailRepository.kt`. **쓰기는 없다** — 보호자 앱은 이 문서들을 읽기만 한다
/// (자녀 폰만 쓴다, `firestore.rules` 의 trails 규칙도 그 방향으로 막혀 있다).
///
/// **구독(addSnapshotListener)을 두지 않는다.** 보호자가 화면을 열 때와 '지금 위치
/// 확인'을 눌렀을 때만 [fetch] 로 한 번씩 읽는다 — 안드로이드 `TrailRepository`
/// 주석과 같은 이유로, 무료 한도를 지켜야 하는 앱에서는 이 편이 훨씬 안전하다.
enum TrailRepository {

    private static var db: Firestore { Firestore.firestore() }

    private static func trailRef(familyId: String, childUid: String, dayKey: String) -> DocumentReference {
        db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .collection("trails").document(dayKey)
    }

    /// 그 날 기록이 없으면(아직 안 올렸거나 아이가 꺼져 있던 날) nil.
    ///
    /// ## 오프라인에서 "없다"고 말하지 않는다
    ///
    /// `getDocument()` 은 서버에 못 닿으면 캐시로 답한다. 그 날 문서가 캐시에
    /// 없으면 **"없는 문서"로 답하고 예외도 안 던진다** — 부모가 지하철에서
    /// 어제로 넘기면 화면 한가운데에 "이 날은 기록이 없어요"가 뜬다. 아이가 하루
    /// 종일 걸어 다닌 날에 대고 하는 말이다.
    ///
    /// 둘을 가르는 값이 `metadata.isFromCache` 하나뿐이라 여기서 본다 — 정본은
    /// 안드로이드 `TrailRepository.kt:38-53`(같은 판단이 `FamilyRepository.joinFamily`
    /// 에도 있다).
    ///
    /// 통신이 되는 동안에는 동작이 하나도 안 바뀐다 — 서버가 확인해 준 "없음"은
    /// `isFromCache == false` 라 그대로 nil 로 나간다.
    static func fetch(familyId: String, childUid: String, dayKey: String) async throws -> TrailDoc? {
        let snapshot = try await trailRef(familyId: familyId, childUid: childUid, dayKey: dayKey).getDocument()
        if !snapshot.exists, snapshot.metadata.isFromCache {
            throw TrailRepositoryError.offline(dayKey: dayKey)
        }
        guard let data = snapshot.data() else { return nil }
        return TrailDoc(data)
    }
}

/// 안드로이드가 `IOException` 을 던지는 자리(`TrailRepository.kt:58`)를 그대로
/// 옮긴 것이다. 안드로이드는 새 예외 타입을 만들지 않고 `IOException` 을 재사용해서
/// `errorMessage(ctx, e)` 가 곧바로 `pairing_offline` 문구로 옮긴다(오프라인은 다른
/// 화면에서도 같은 상황이니 문구를 새로 만들지 않는다) — 이 타입을 잡는 쪽도 같은
/// 문구(`pairing_offline`)를 재사용해야 한다(새 오프라인 문구를 만들지 않는다).
enum TrailRepositoryError: Error, Equatable {
    case offline(dayKey: String)
}
