import FirebaseFirestore
import Foundation

/// 아이 폰의 지금 상태(위치·배터리·통신)를 `children/{childUid}` 문서 하나에 덮어쓴다.
/// 정본은 안드로이드 `child/StatusReporter.kt:33-68` 의 `report` 다.
///
/// **위치가 들어올 때마다 부르지 않는다.** 업로드 판정(설계서 §6.4)이 통과했을 때만
/// `TrackingCoordinator.uploadNow()` 가 부른다 — 옛 구조에서 이 쓰기가 하루 약 520번이었고
/// 그것 하나로 Spark 무료 한도를 넘겼다(`known-issues.md` 12번).
///
/// 설계서에는 `children/{childUid}/status` 하위 문서로 그려져 있지만 Firestore 는 문서 아래에
/// 바로 필드를 둘 수 있으므로 `children/{childUid}` 문서 자체를 status 로 쓴다 — 문서 하나를
/// 아끼고 읽기도 한 번 줄어든다(`StatusReporter.kt:22-24`).
///
/// `reportRingerMode`(`:75-90`)는 **안 옮긴다.** 아이폰에는 소리 모드를 읽거나 바꾸는 API 가
/// 없고(설계서 §1), 1단계에는 명령 자체가 없다.
enum ChildStatusReporter {

    private static var db: Firestore { Firestore.firestore() }

    /// 덮어쓰기(merge 아님)다 — 코틀린 `.set(ChildStatusDoc(...))` 과 같다. 규칙은
    /// `request.auth.uid == childUid` 인 아이 본인에게만 이 쓰기를 허용한다(`firestore.rules:148`).
    static func report(familyId: String, childUid: String, write: ChildStatusWrite) async throws {
        try await db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .setData(write.firestoreData)
    }
}
