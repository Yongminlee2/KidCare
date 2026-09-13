import FirebaseFirestore
import Foundation

/// 명령의 단일 창구. 정본은 안드로이드 `core/CommandRepository.kt`·
/// `FirestoreCommandTransport.kt`.
///
/// **이 앱은 보호자 전용이다.** 안드로이드의 `markDelivered`/`markDone`/`markFailed`
/// (자녀 폰이 명령 실행 결과를 적는 갈래)는 옮기지 않는다 — 이 앱이 그 문서를
/// 쓸 일이 없다. 이 타입이 하는 일은 딱 둘, **명령을 만드는 것**과 **명령 문서
/// 하나를 구독하는 것**뿐이다.
enum CommandRepository {

    private static var db: Firestore { Firestore.firestore() }

    private static func commands(familyId: String, childUid: String) -> CollectionReference {
        db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .collection("commands")
    }

    /// 명령 문서를 만든다. 정본은 안드로이드 `FirestoreCommandTransport.send` —
    /// 그 함수가 쓰는 것과 정확히 같은 필드 이름·개수를 쓴다. `firestore.rules`
    /// 의 `commands` create 규칙은 `state == 'pending'` 하나만 검사하지만,
    /// `type`·`payload`·시각 세 쌍이 하나라도 이름이 어긋나면 안드로이드(자녀 폰)
    /// 가 이 문서를 못 읽는다(`CommandDoc` 주석).
    ///
    /// **`state` 는 반드시 `pending` 으로 시작한다** — 보호자가 처음부터 `done`
    /// 으로 위조해서 만드는 것을 규칙이 막는다(코틀린 `send` 주석과 같은 이유).
    static func send(
        familyId: String,
        childUid: String,
        type: String,
        payload: [String: String] = [:]
    ) async throws -> String {
        let ref = commands(familyId: familyId, childUid: childUid).document()
        try await ref.setData([
            "type": type,
            "payload": payload,
            "state": CommandState.pending,
            "createdAt": Int64(Date().timeIntervalSince1970 * 1000),
            "deliveredAt": Int64(0),
            "doneAt": Int64(0),
            "error": "",
        ])
        return ref.documentID
    }

    /// 명령 문서 하나를 구독한다. **부르는 쪽이 답이 오면(또는 시간 초과되면)
    /// 반드시 반환된 등록을 remove 해야 한다** — 상시 구독으로 두면 Spark 무료
    /// 읽기 한도를 계속 갉아먹는다(`MapViewModel.stopCommandTracking` 참고).
    static func observeOne(
        familyId: String,
        childUid: String,
        commandId: String,
        onChange: @escaping (CommandDoc) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        commands(familyId: familyId, childUid: childUid).document(commandId)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onError(error)
                    return
                }
                guard let snapshot, let data = snapshot.data() else { return }
                onChange(CommandDoc(id: snapshot.documentID, data))
            }
    }
}
