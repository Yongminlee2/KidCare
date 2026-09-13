import FirebaseFirestore
import Foundation

/// 벨소리 잠금 설정(settings/ringer)과 예약 규칙(schedules/). 정본은 안드로이드
/// `core/ScheduleRepository.kt`. 예약 규칙과 기본 모드·공휴일은 5단계가 이 파일에 더했다 —
/// 안드로이드와 같은 자리에 두려고 4단계가 이름을 미리 맞춰 두었다.
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

    // MARK: - 예약 규칙과 규칙 바탕 설정 (5단계). 정본은 ScheduleRepository.kt:34-37, 73-129.

    private static func schedules(familyId: String, childUid: String) -> CollectionReference {
        db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .collection("schedules")
    }

    /// id 가 비어 있으면 새 문서를, 아니면 그 ID 에 덮어쓴다(:73-82). 보호자 화면은 늘 ID 를 정해서
    /// 넘긴다 — 저장이 두 번 나가도 규칙이 둘 생기지 않게(ScheduleFragment.kt:151-160).
    ///
    /// 오프라인이면 서버 확인이 올 때까지 안 돌아온다. 부르는 쪽이 `firstToFinish` 로 15초를 건다.
    @discardableResult
    static func saveSchedule(familyId: String, childUid: String, doc: ScheduleDoc) async throws -> String {
        let collection = schedules(familyId: familyId, childUid: childUid)
        let ref = doc.id.isEmpty ? collection.document() : collection.document(doc.id)
        try await ref.setData(doc.firestoreData)
        return ref.documentID
    }

    static func deleteSchedule(familyId: String, childUid: String, id: String) async throws {
        try await schedules(familyId: familyId, childUid: childUid).document(id).delete()
    }

    /// 빈 문자열이면 "규칙이 없는 시간에는 아무것도 강제하지 않는다"(:98-102). `setRingerLock` 과 같은
    /// 이유로 **이 필드 하나만** 병합한다.
    static func setDefaultMode(familyId: String, childUid: String, mode: String) async throws {
        try await ringerSettingsRef(familyId: familyId, childUid: childUid)
            .setData(["defaultMode": mode], merge: true)
    }

    static func setHolidayOff(familyId: String, childUid: String, enabled: Bool) async throws {
        try await ringerSettingsRef(familyId: familyId, childUid: childUid)
            .setData(["holidayOff": enabled], merge: true)
    }

    /// 정렬 없이 준다(문서 ID 순). `fromCache` 는 캐시본인지를 알려준다 — 화면이 캐시본으로
    /// "없어요"라고 단언하지 않게 하려는 것이다(ListLoadState.kt:23-39). 그래서 메타데이터 변화도
    /// 받는다(`MetadataChanges.INCLUDE`, :119).
    static func observeSchedules(
        familyId: String,
        childUid: String,
        onChange: @escaping (_ docs: [ScheduleDoc], _ fromCache: Bool) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        schedules(familyId: familyId, childUid: childUid)
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error { onError(error); return }
                let docs = snapshot?.documents.map { ScheduleDoc(id: $0.documentID, $0.data()) } ?? []
                onChange(docs, snapshot?.metadata.isFromCache ?? true)
            }
    }
}
