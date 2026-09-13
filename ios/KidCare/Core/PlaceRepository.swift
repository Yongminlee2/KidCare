import FirebaseFirestore
import Foundation

/// 장소(places/). 정본은 안드로이드 `core/PlaceRepository.kt` — `ScheduleRepository` 와 같은 모양이다.
///
/// 보호자 화면만 구독한다. 자녀 폰은 한 번 읽기만 하는데(:14-27), 그 갈래는 이 앱(보호자 전용)에 없다.
/// 쓰기는 보호자만 허용된다(firestore.rules:216-222).
enum PlaceRepository {

    private static var db: Firestore { Firestore.firestore() }

    private static func places(familyId: String, childUid: String) -> CollectionReference {
        db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .collection("places")
    }

    /// 만들기와 고치기가 한 경로다(:56-67). 화면은 늘 ID 를 정해서 넘긴다.
    @discardableResult
    static func savePlace(familyId: String, childUid: String, doc: PlaceDoc) async throws -> String {
        let collection = places(familyId: familyId, childUid: childUid)
        let ref = doc.id.isEmpty ? collection.document() : collection.document(doc.id)
        try await ref.setData(doc.firestoreData)
        return ref.documentID
    }

    static func deletePlace(familyId: String, childUid: String, id: String) async throws {
        try await places(familyId: familyId, childUid: childUid).document(id).delete()
    }

    /// `observeSchedules` 와 같은 계약(:73-93). 돌려받은 등록은 보호자 화면이 사라질 때 remove 한다.
    static func observePlaces(
        familyId: String,
        childUid: String,
        onChange: @escaping (_ docs: [PlaceDoc], _ fromCache: Bool) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        places(familyId: familyId, childUid: childUid)
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error { onError(error); return }
                let docs = snapshot?.documents.map { PlaceDoc(id: $0.documentID, $0.data()) } ?? []
                onChange(docs, snapshot?.metadata.isFromCache ?? true)
            }
    }
}
