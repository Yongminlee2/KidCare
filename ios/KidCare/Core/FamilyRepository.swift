import FirebaseFirestore
import Foundation
import os

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

/// 체크 continuation 을 딱 한 번만 resume 하게 지키는 최소 actor.
///
/// `measureWithTimeout` 이 측정 태스크와 시간 제한 태스크를 경주시키는데, 두 태스크
/// 모두 자기가 끝나면 resume 을 시도한다 — 이긴 쪽만 실제로 continuation 을
/// 건드려야 하고 진 쪽의 시도는 조용히 버려야 한다(continuation 을 두 번 resume
/// 하면 그 자체가 런타임 크래시다). actor 격리 하나로 그 경합을 막는다.
private actor ResumeOnce<T: Sendable> {
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<T, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

/// 가족 문서와 멤버·초대 코드를 다룬다. 정본은 안드로이드 `core/FamilyRepository.kt` 다.
enum FamilyRepository {

    private static var db: Firestore { Firestore.firestore() }

    private static let inviteTtlMillis: Int64 = 10 * 60 * 1000
    /// 서버 시각 보정을 포기하기까지. 안드로이드 예약 화면의 쓰기 제한시간
    /// (`ScheduleFragment.WRITE_TIMEOUT_MILLIS`)과 일부러 같은 숫자다 — 둘 다
    /// "오프라인이면 서버 확인이 영영 안 온다"는 같은 사실을 막는 장치라 서로 다른
    /// 값을 쓸 이유가 없다. 근거 있는 값은 아니다(안드로이드 쪽과 같은
    /// known-issues 항목).
    private static let measureTimeoutNanos: UInt64 = 15_000_000_000

    /// 기기 시계와 서버 시계의 차이(밀리초). 서버가 앞서면 양수다.
    /// 프로세스당 한 번만 재고 캐시한다.
    ///
    /// **`nonisolated(unsafe)` 를 쓰지 않는다.** `Int64?` 는 원자적으로 읽고 쓸 수
    /// 있는 크기가 아니다 — 페어링 태스크가 값을 쓰는 동안 지도 화면 태스크가
    /// 읽으면 절반만 쓰인 값을 볼 수 있고, 그러면 `deviceNow() + 쓰레기` 가
    /// `createInvite` 로 흘러가 규칙이 이유도 없이 거부하는 `expiresAt` 을 만든다.
    /// 안드로이드는 `@Volatile` 로 이걸 막는다. 배포 대상이 iOS 17 이라 Swift 6 의
    /// `Mutex`(iOS 18+)는 쓸 수 없어 `OSAllocatedUnfairLock`(iOS 16+)으로 같은
    /// 보장을 준다.
    private static let serverOffsetLock = OSAllocatedUnfairLock<Int64?>(initialState: nil)

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
        if let offset = serverOffsetLock.withLock({ $0 }) { return deviceNow() + offset }

        let measured: Int64?
        do {
            measured = try await measureWithTimeout(familyId: familyId, uid: uid)
        } catch is CancellationError {
            // 부른 쪽이 취소된 정상 종료다. 값을 캐시하지 않고 기기 시계를 준다.
            return deviceNow()
        } catch {
            measured = nil
        }

        guard let offset = measured else {
            // 시간 초과든 진짜 실패든 **캐시하지 않는다** — 안드로이드와 의도적으로
            // 다른 지점이다. 안드로이드(FamilyRepository.kt)는 시간 초과는 안 캐시하지만
            // 진짜 실패(주로 "아직 멤버가 아니라 잴 문서가 없다")는 0 으로 캐시한다.
            // 그런데 이 실패는 가입 전 첫 호출에서 거의 항상 일어나는 경우라, 0 을
            // 굳히면 그 프로세스가 살아있는 내내 이후의 모든 초대·가입이 기기
            // 시계로 계산된다 — 오프셋이 막아야 할 "만들자마자 죽은 코드"를 오프셋
            // 자신이 다시 만드는 셈이다. 그래서 여기서는 두 경우 다 캐시하지 않고
            // 다음 호출이 다시 잰다.
            return deviceNow()
        }
        serverOffsetLock.withLock { $0 = offset }
        return deviceNow() + offset
    }

    /// `measureServerOffset` 을 `withThrowingTaskGroup` 으로 시간 제한 하면 안 된다.
    /// 구조적 동시성의 스코프 규칙상, 진 쪽(시간 초과 태스크)이 먼저 던지면 그룹은
    /// 이긴 쪽(측정 태스크)을 취소한 **뒤 그 태스크가 끝나기를 기다렸다가** 다시
    /// 던진다. 그런데 Firestore 의 async 브리지는 취소를 지원하지 않는 자리가 있어
    /// (`updateData` 가 대표적) 오프라인에서는 그 태스크가 영영 안 끝난다 — 그러면
    /// 그룹이 거기서 막혀 15초 시간 제한이 장식으로 전락한다. 그래서 비구조적
    /// `Task` 둘을 직접 만들어 경주시키고, 먼저 끝난 쪽만 continuation 을 한 번
    /// resume 한다. 진 태스크(대개 오프라인 상태로 영원히 매달린 Firestore 쓰기)는
    /// 버려두고 계속 돌게 둔다 — 결과는 버린다. Firestore 쪽에 취소를 강제할
    /// 방법이 없는 한 이게 유일한 탈출구다.
    private static func measureWithTimeout(familyId: String?, uid: String?) async throws -> Int64 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int64, Error>) in
            let resumeOnce = ResumeOnce(continuation)
            Task {
                do {
                    let value = try await measureServerOffset(familyId: familyId, uid: uid)
                    await resumeOnce.resume(.success(value))
                } catch {
                    await resumeOnce.resume(.failure(error))
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: measureTimeoutNanos)
                await resumeOnce.resume(.failure(PairingError.offline))
            }
        }
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

        do {
            try await familyRef.collection("members").document(uid).setData(
                MemberDoc(role: doc.role, displayName: name, updatedAt: now, joinCode: normalized, joinedAt: now).firestoreData
            )
        } catch {
            let ns = error as NSError
            guard ns.domain == FirestoreErrorDomain, ns.code == FirestoreErrorCode.permissionDenied.rawValue else {
                throw error
            }
            // PERMISSION_DENIED 하나만으로는 "다른 사람이 이 코드를 먼저 썼다"와
            // "운영 규칙이 아직 구버전이다"를 구분할 수 없다. 코드를 서버에서 다시
            // 읽어 같은 가족·역할로 여전히 살아 있으면 만료가 아니라 규칙 게시
            // 오류이므로 원래 에러를 그대로 다시 던진다 — 그래야 호출부가 "만료됨"
            // 이라는 거짓 안내를 내보내지 않는다. 가입 첫 시도는 아직 멤버가
            // 아니라 measureServerOffset 이 반드시 실패해 serverNow() 가 기기
            // 시계로 물러나므로, 폰 시계가 조금만 빨라도 위의 클라이언트 쪽 만료
            // 검사는 통과하고 규칙만 거부하는 경우가 실제로 흔하다 — 가정이 아니다.
            let latestSnap = try? await codeRef.getDocument(source: .server)
            let latestDoc = latestSnap.flatMap { InviteCodeDoc($0.data() ?? [:]) }
            let stillValid = latestSnap?.exists == true
                && latestDoc?.familyId == doc.familyId
                && latestDoc?.role == expectedRole
                && (latestDoc?.expiresAt ?? 0) > now
            throw stillValid ? error : PairingError.expired
        }

        try? await codeRef.delete()
        return JoinResult(familyId: doc.familyId, role: doc.role)
    }

    /// 가족의 자녀 uid 하나를 고른다. `preferred` 가 아직 멤버면 그것을 유지한다.
    ///
    /// 정렬 규칙은 안드로이드 `logic/ChildSelector.kt` 와 반드시 같아야 한다 — 같은
    /// 가족, 같은 저장된 선호값인데 두 폰이 서로 다른 자녀를 고르면 Phase 3 지도가
    /// 보호자마다 다른 아이를 보여준다. `ChildSelector` 는 가입 시각 오름차순 →
    /// 표시 이름 → uid 순으로 고르고, 가입 시각이 0(옛 문서 등, "모름")이면
    /// 가장 늦은 값으로 취급해 뒤로 보낸다. Phase 2 가 이 함수를 포팅된
    /// `ChildSelector` 호출로 통째로 바꾸는데, 그때도 이 정렬은 그대로 유지해야
    /// 한다 — 정렬 기준 자체가 두 플랫폼이 맞춰야 하는 계약이다.
    static func findChildUid(familyId: String, preferred: String?) async throws -> String? {
        let snap = try await db.collection("families").document(familyId)
            .collection("members").whereField("role", isEqualTo: MemberRole.child.rawValue).getDocuments()

        let children: [(uid: String, member: MemberDoc)] = snap.documents.compactMap { doc in
            guard let member = MemberDoc(doc.data()) else { return nil }
            return (doc.documentID, member)
        }
        return selectChildUid(from: children, preferred: preferred)
    }

    /// `findChildUid` 와 `observeChildJoined` 가 같이 쓰는 선택 규칙. 한 번 조회할
    /// 때와 실시간으로 지켜볼 때가 서로 다른 정렬을 쓰면, 코드가 뜬 순간 고른 아이와
    /// 리스너가 나중에 고른 아이가 갈릴 수 있다 — 그래서 로직을 한 곳에 둔다.
    private static func selectChildUid(
        from children: [(uid: String, member: MemberDoc)],
        preferred: String?
    ) -> String? {
        if let preferred, children.contains(where: { $0.uid == preferred }) { return preferred }

        return children.min { a, b in
            let aJoined = a.member.joinedAt > 0 ? a.member.joinedAt : Int64.max
            let bJoined = b.member.joinedAt > 0 ? b.member.joinedAt : Int64.max
            if aJoined != bJoined { return aJoined < bJoined }
            if a.member.displayName != b.member.displayName { return a.member.displayName < b.member.displayName }
            return a.uid < b.uid
        }?.uid
    }

    /// 자녀가 members 에 들어오는 순간을 감시한다. 정본은 안드로이드
    /// `FamilyRepository.observeChildJoined` 다.
    ///
    /// 보호자가 초대 코드를 띄운 화면은 "코드를 보여줬다"가 아니라 "아이가 실제로
    /// 들어왔다"가 끝이다 — 그 순간을 화면이 스스로 알아야 폴링 없이 다음으로
    /// 넘어갈 수 있다. `onError` 없이 에러를 삼키면 권한 거부나 리스너 끊김이 나도
    /// 화면은 계속 코드만 보여주고 아무 데도 단서가 안 남는다(안드로이드 쪽 같은
    /// 함수의 주석과 같은 이유). 붙인 리스너는 호출부가 화면이 사라질 때 반드시
    /// remove 해야 한다 — 안 그러면 화면을 나간 뒤에도 Firestore 읽기 비용이 계속
    /// 나간다.
    static func observeChildJoined(
        familyId: String,
        preferredChildUid: String?,
        onJoined: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        db.collection("families").document(familyId)
            .collection("members").whereField("role", isEqualTo: MemberRole.child.rawValue)
            .addSnapshotListener { snapshot, error in
                if let error { onError(error); return }
                let children: [(uid: String, member: MemberDoc)] = snapshot?.documents.compactMap { doc in
                    guard let member = MemberDoc(doc.data()) else { return nil }
                    return (doc.documentID, member)
                } ?? []
                guard let uid = selectChildUid(from: children, preferred: preferredChildUid) else { return }
                onJoined(uid)
            }
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
