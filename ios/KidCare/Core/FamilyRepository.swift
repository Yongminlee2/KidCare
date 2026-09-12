import FirebaseFirestore
import Foundation

struct InviteCodeInfo {
    let code: String
    let expiresAt: Int64
    let role: MemberRole
}

struct JoinResult {
    let familyId: String
    let role: MemberRole
}

enum PairingError: Error, Equatable {
    case notFound
    case offline
    case expired
    case wrongRole
}

/// 가족 문서와 멤버·초대 코드를 다룬다. 정본은 안드로이드 `core/FamilyRepository.kt` 다.
enum FamilyRepository {

    private static var db: Firestore { Firestore.firestore() }

    private static let inviteTtlMillis: Int64 = 10 * 60 * 1000
    private static let measureTimeoutNanos: UInt64 = 15_000_000_000

    /// 기기 시계와 서버 시계의 차이(밀리초). 서버가 앞서면 양수다.
    /// 프로세스당 한 번만 재고 캐시한다.
    nonisolated(unsafe) private static var serverOffsetMillis: Int64?

    private static func deviceNow() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    /// 서버 기준 "지금"(UTC 밀리초).
    ///
    /// 초대 코드의 만료는 기기 시계로 쓰는데 보안 규칙은 서버 시각으로 검사한다.
    /// 폰 시계가 15분 느리면 **만들자마자 죽은 코드**가 되고, 재발급해도 같은 시계를
    /// 쓰므로 영원히 죽은 코드만 나온다 — 화면에는 "만료됨"만 뜨고 원인은 아무 데도
    /// 안 남는다.
    static func serverNow(familyId: String?, uid: String?) async -> Int64 {
        if let offset = serverOffsetMillis { return deviceNow() + offset }

        let measured: Int64?
        do {
            measured = try await withThrowingTaskGroup(of: Int64.self) { group in
                group.addTask { try await measureServerOffset(familyId: familyId, uid: uid) }
                group.addTask {
                    try await Task.sleep(nanoseconds: measureTimeoutNanos)
                    throw PairingError.offline
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
        } catch is CancellationError {
            // 부른 쪽이 취소된 정상 종료다. 값을 캐시하지 않고 기기 시계를 준다.
            return deviceNow()
        } catch {
            measured = nil
        }

        guard let offset = measured else {
            // 시간 초과는 **캐시하지 않는다.** 0 을 굳히면 그 뒤 초대 코드 만료가
            // 전부 기기 시계로 계산돼 "만들자마자 죽은 코드"가 되살아난다.
            return deviceNow()
        }
        serverOffsetMillis = offset
        return deviceNow() + offset
    }

    /// members/{uid} 의 updatedAt 에 서버 타임스탬프를 쓰고 **서버에서** 다시 읽는다.
    /// 아직 멤버가 아니면 규칙이 막으므로 실패하고, 부르는 쪽이 기기 시계로 물러난다.
    private static func measureServerOffset(familyId: String?, uid: String?) async throws -> Int64 {
        guard let familyId, let uid else { return 0 }
        let ref = db.collection("families").document(familyId).collection("members").document(uid)
        let before = deviceNow()
        try await ref.updateData(["updatedAt": FieldValue.serverTimestamp()])
        let after = deviceNow()
        let snap = try await ref.getDocument(source: .server)
        guard let ts = snap.get("updatedAt") as? Timestamp else { return 0 }
        let serverMillis = Int64(ts.dateValue().timeIntervalSince1970 * 1000)
        // 왕복의 절반을 오차로 보고 중간값을 쓴다 — before 만 쓰면 지연이 클수록
        // 오프셋을 과대평가한다.
        return serverMillis - (before + after) / 2
    }

    /// 가족 문서를 만들고 보호자를 첫 멤버로 넣는다.
    ///
    /// 순서가 중요하다: members/{uid} 를 만들 때 규칙이 families/{id}.ownerUid 를
    /// 대조하므로 가족 문서가 **먼저** 있어야 한다.
    static func createFamily(guardianUid: String) async throws -> String {
        let bootTime = deviceNow()
        let familyRef = db.collection("families").document()

        try await familyRef.setData(
            FamilyDoc(
                name: String(localized: "family_default_name"),
                createdAt: bootTime,
                ownerUid: guardianUid,
                schemaVersion: FamilyDoc.currentSchemaVersion
            ).firestoreData
        )
        try await familyRef.collection("members").document(guardianUid).setData(
            MemberDoc(
                role: .guardian,
                displayName: String(localized: "role_guardian"),
                updatedAt: bootTime,
                joinedAt: bootTime
            ).firestoreData
        )
        return familyRef.documentID
    }

    /// 초대 코드를 발급한다. `previousCode` 를 주면 발급 뒤 그 코드를 지운다.
    static func createInvite(
        familyId: String,
        role: MemberRole,
        previousCode: String?
    ) async throws -> InviteCodeInfo {
        let creatorUid = try await AuthGateway.uid()
        let now = await serverNow(familyId: familyId, uid: creatorUid)
        let expiresAt = now + inviteTtlMillis

        // 6자리 충돌은 드물지만 다른 가족의 살아있는 코드를 덮어쓰면 안 된다.
        // 문서 ID 한 건만 확인하므로 목록 조회 권한도 색인도 필요 없다.
        var code = ""
        for _ in 0..<8 {
            let candidate = InviteCode.generate()
            let existing = try await db.collection("inviteCodes").document(candidate).getDocument()
            if !existing.exists { code = candidate; break }
        }
        guard !code.isEmpty else {
            throw NSError(domain: "KidCare", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "겹치지 않는 초대 코드를 만들지 못했다"])
        }

        try await db.collection("inviteCodes").document(code).setData(
            InviteCodeDoc(familyId: familyId, expiresAt: expiresAt, role: role, createdByUid: creatorUid).firestoreData
        )

        if let previousCode, !previousCode.isEmpty, previousCode != code {
            // 실패해도 넘어간다 — 옛 코드가 남는 것은 만료로 죽지만, 여기서 던지면
            // 방금 발급한 새 코드를 화면이 못 받는다.
            try? await db.collection("inviteCodes").document(previousCode).delete()
        }
        return InviteCodeInfo(code: code, expiresAt: expiresAt, role: role)
    }

    /// 초대 코드로 가족에 합류한다. 아이폰 보호자가 쓰는 주된 경로다.
    static func joinFamily(
        code: String,
        uid: String,
        expectedRole: MemberRole,
        displayName: String
    ) async throws -> JoinResult {
        let normalized = InviteCode.normalize(code)
        let codeRef = db.collection("inviteCodes").document(normalized)
        let codeDoc = try await codeRef.getDocument()

        guard codeDoc.exists else {
            // 없는 게 아니라 **물어볼 수가 없었던** 경우일 수 있다. 오프라인이면 이
            // 읽기는 캐시로 답하는데 이 코드가 캐시에 있을 리 없으므로 똑같이
            // "없음"으로 나온다 — 그러면 "코드가 틀렸다"가 아니라 "인터넷이 안 된다"고
            // 말해야 한다. 안 그러면 멀쩡한 코드를 계속 다시 입력하게 된다.
            throw codeDoc.metadata.isFromCache ? PairingError.offline : PairingError.notFound
        }
        guard let doc = InviteCodeDoc(codeDoc.data() ?? [:]) else { throw PairingError.notFound }
        guard doc.role == expectedRole else { throw PairingError.wrongRole }

        let now = await serverNow(familyId: doc.familyId, uid: uid)
        guard doc.expiresAt > now else { throw PairingError.expired }

        let familyRef = db.collection("families").document(doc.familyId)
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = doc.role == .guardian
            ? String(localized: "role_guardian")
            : String(localized: "role_child")
        let name = trimmed.isEmpty ? fallback : String(trimmed.prefix(20))

        try await familyRef.collection("members").document(uid).setData(
            MemberDoc(role: doc.role, displayName: name, updatedAt: now, joinCode: normalized, joinedAt: now).firestoreData
        )

        try? await codeRef.delete()
        return JoinResult(familyId: doc.familyId, role: doc.role)
    }

    /// 가족의 자녀 uid 하나를 고른다. `preferred` 가 아직 멤버면 그것을 유지한다.
    static func findChildUid(familyId: String, preferred: String?) async throws -> String? {
        let snap = try await db.collection("families").document(familyId)
            .collection("members").whereField("role", isEqualTo: MemberRole.child.rawValue).getDocuments()
        let uids = snap.documents.map(\.documentID).sorted()
        if let preferred, uids.contains(preferred) { return preferred }
        return uids.first
    }

    /// 아이 상태 문서를 구독한다. 돌려받은 등록은 화면이 사라질 때 반드시 remove 한다.
    ///
    /// onError 없이 에러를 삼키면 권한 거부나 리스너 끊김이 나도 화면은 계속 비어
    /// 있기만 하고 아무 데도 단서가 안 남는다 — 이 앱에서 가장 흔한 실패 유형인데
    /// 원인을 알 방법이 없었다(안드로이드 쪽 같은 함수의 주석).
    static func observeChildStatus(
        familyId: String,
        childUid: String,
        onChange: @escaping (ChildStatusDoc?) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        db.collection("families").document(familyId)
            .collection("children").document(childUid)
            .addSnapshotListener { snapshot, error in
                if let error { onError(error); return }
                guard let data = snapshot?.data() else { onChange(nil); return }
                onChange(ChildStatusDoc(data))
            }
    }
}
