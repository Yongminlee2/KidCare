import FirebaseFirestore
import Foundation

/// 하루치 이동 기록(`children/{childUid}/trails/{dayKey}`)을 읽고 쓴다. 정본은 안드로이드
/// `core/TrailRepository.kt`. **방향이 역할마다 다르다** — 보호자 역할은 [fetch] 로 읽기만 하고,
/// 쓰는 것은 아이 역할의 [save] 하나뿐이다(`firestore.rules:163-166` 의 trails 규칙이 그
/// 방향을 강제한다).
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

    /// 그 날 문서를 통째로 덮어쓴다. **쓰기 한 번**이다. 정본은 `core/TrailRepository.kt:31`.
    ///
    /// **아이 역할일 때만 부른다.** 규칙이 `request.auth.uid == childUid` 로 막고 있어
    /// (`firestore.rules:165`) 보호자 세션이 부르면 조용히 거부된다 — 그 거부를 테스트로 박아
    /// 두었다(`ChildTrailWriteTests.보호자는_못_쓴다`).
    ///
    /// 재시도를 새로 만들지 않는다. Firestore SDK 의 오프라인 큐가 이미 한다
    /// (`known-issues.md` 19번) — `setData` 는 로컬에 즉시 반영되고 연결이 돌아오면 저절로 나간다.
    /// 하루 문서는 같은 문서를 덮어쓰므로 큐에 여러 번 쌓여도 마지막 것만 의미가 있다(설계서 §6.5).
    static func save(familyId: String, childUid: String, doc: TrailDoc) async throws {
        try await trailRef(familyId: familyId, childUid: childUid, dayKey: doc.dayKey).setData(doc.firestoreData)
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
