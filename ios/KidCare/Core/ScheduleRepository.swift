import FirebaseFirestore
import Foundation

/// 벨소리 잠금 설정(settings/ringer). 정본은 안드로이드 `core/ScheduleRepository.kt`. 예약
/// 규칙(schedules/)은 5단계가 이 파일에 더한다 — 안드로이드와 같은 자리에 두려고 이름을
/// 미리 맞춘다.
enum ScheduleRepository {

    private static var db: Firestore { Firestore.firestore() }

    private static func ringerSettingsRef(familyId: String, childUid: String) -> DocumentReference {
        db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .collection("settings").document("ringer")
    }

    /// 잠금 스위치를 저장한다. **건드리는 필드만 병합한다** — 이 문서에는 관리 탭의 잠금과
    /// 예약 탭의 공휴일·기본 모드가 함께 있어서, 통째로 덮으면 한쪽이 저장할 때마다 다른
    /// 쪽 값이 기본값으로 돌아간다(ScheduleRepository.kt:88-96).
    ///
    /// 오프라인이면 이 await 는 서버 확인이 올 때까지 안 돌아온다 — 부르는 쪽이
    /// `firstToFinish` 로 15초 제한을 건다(ControlFragment.saveLock :854-860).
    static func setRingerLock(familyId: String, childUid: String, enabled: Bool) async throws {
        try await ringerSettingsRef(familyId: familyId, childUid: childUid)
            .setData(["lockEnabled": enabled], merge: true)
    }

    /// 설정 문서를 구독한다. 문서가 없으면 기본값을 준다(ScheduleRepository.kt:131-144).
    /// 돌려받은 등록은 부르는 쪽이 보호자 화면이 사라질 때 반드시 remove 한다.
    static func observeRingerSettings(
        familyId: String,
        childUid: String,
        onChange: @escaping (RingerSettingsDoc) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        ringerSettingsRef(familyId: familyId, childUid: childUid)
            .addSnapshotListener { snapshot, error in
                if let error { onError(error); return }
                onChange(RingerSettingsDoc(snapshot?.data() ?? [:]))
            }
    }
}
