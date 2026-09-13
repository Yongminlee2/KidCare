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

/// 가족 멤버 한 명. 정본은 `FamilyRepository.kt:522-527`.
///
/// `role` 을 `MemberRole` 이 아니라 문자열로 두는 이유: 선택기는 "child"/"guardian" 만 걸러 쓰고, 모르는 역할
/// 문서가 하나 섞여도 목록 전체가 깨지면 안 된다(`MemberDoc(_:)` 는 모르는 역할이면 nil 을 돌려준다).
struct FamilyMember: Hashable, Sendable {
    let uid: String
    let role: String
    let displayName: String
    let joinedAt: Int64
}

enum PairingError: Error, Equatable {
    case notFound
    case offline
    case expired
    case wrongRole
}

/// 체크 continuation 을 딱 한 번만 resume 하게 지키는 actor.
///
/// `measureWithTimeout` 은 continuation 하나를 두고 세 갈래(측정 성공/실패, 시간
/// 초과, 부모 취소)가 경주한다. 셋 다 자기가 이기면 resume 을 시도하므로, 실제로
/// 이긴 단 하나만 continuation 을 건드리고 나머지는 조용히 버려야 한다(같은
/// continuation 을 두 번 resume 하면 그 자체가 런타임 크래시다). actor 격리
/// 하나로 그 경합을 막는다.
///
/// continuation 을 생성자가 아니라 `attach` 로 나중에 받는 이유: 취소를 관측하는
/// `withTaskCancellationHandler` 의 onCancel 은 **이미 취소된 채로 들어오면
/// continuation 을 만드는 코드(operation)보다 먼저, 다른 스레드에서 동시에** 실행될
/// 수 있다 — 그 순간엔 아직 continuation 이 없다. 그래서 "취소가 먼저 왔다"는
/// 사실만 `pendingResult` 에 적어두고, continuation 이 나중에 붙으면 그 자리에서
/// 바로 그 결과로 끝낸다. 반대로 continuation 이 먼저 오면 평범하게 결과를
/// 기다린다. 어느 쪽이 먼저 와도 딱 한 번만 resume 된다.
private actor ResumeOnce<T: Sendable> {
    private var continuation: CheckedContinuation<T, Error>?
    private var pendingResult: Result<T, Error>?
    private var settled = false

    func attach(_ continuation: CheckedContinuation<T, Error>) {
        guard !settled else { return }
        if let pendingResult {
            settled = true
            continuation.resume(with: pendingResult)
        } else {
            self.continuation = continuation
        }
    }

    func resume(_ result: Result<T, Error>) {
        guard !settled else { return }
        if let continuation {
            settled = true
            continuation.resume(with: result)
        } else {
            pendingResult = result
        }
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
    ///
    /// **반드시 취소를 완성시킨다.** 안드로이드 `FamilyRepository.serverNow` 의 같은
    /// 이름 규율과 동일하다 — 시간 초과는 기기 시계로 물러나 값을 돌려주지만, 취소는
    /// 값을 만들어 돌려주지 않고 다시 던진다. 이 함수가 `throws` 가 아니던 시절에는
    /// 취소된 뒤에도 항상 정상값을 돌려줬다: `NewFamilySession.invalidate()` 가
    /// `준비_작업` 을 취소해도 `createInvite` 안의 `await serverNow(...)` 가 그냥
    /// 유효한 시각을 내놓고, 뒤이은 코드 충돌 루프와 `setData` 가 그대로 실행되어
    /// 아무도 볼 일 없는 `inviteCodes/{code}` 문서가 10분 TTL을 꽉 채우고서야
    /// 사라지는 결과로 이어졌다. `try Task.checkCancellation()` 을 맨 앞에 둬서,
    /// 이미 취소된 채로 불린 호출은 서버를 다녀오지도 않고 곧바로 던진다 — 다만
    /// 이건 캐시가 있어 서버를 안 다녀오는 경로, 혹은 호출 시점에 이미 취소된
    /// 경우만 잡는다. 오프셋이 아직 캐시되지 않은 **첫 호출**은 반드시
    /// `measureWithTimeout` 의 서버 왕복을 기다리는데, 그 왕복 도중에 떨어지는
    /// 취소는 이 앞머리 체크로는 못 잡는다 — `measureWithTimeout` 자신이
    /// `withTaskCancellationHandler` 로 그 창을 막는다(아래 주석).
    static func serverNow(familyId: String?, uid: String?) async throws -> Int64 {
        try Task.checkCancellation()
        if let offset = serverOffsetLock.withLock({ $0 }) { return deviceNow() + offset }

        let measured: Int64?
        do {
            measured = try await measureWithTimeout(familyId: familyId, uid: uid)
        } catch is CancellationError {
            // 부른 쪽이 취소된 정상 종료다 — 값을 캐시하지도, 기기 시계로 물러나
            // 돌려주지도 않는다. 그대로 다시 던져 호출부(`createInvite`/`joinFamily`)
            // 가 뒤이은 쓰기를 실행하지 못하게 막는다.
            throw CancellationError()
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
    ///
    /// **부모의 취소도 이 경주에 세 번째 선수로 넣는다.** 비구조적 `Task` 둘은 부모의
    /// 취소를 물려받지 않고, `CheckedContinuation` 자체도 취소를 모른다 — 그래서
    /// `withTaskCancellationHandler` 로 **이 함수 자신의(=측정 태스크가 아니라
    /// `measureWithTimeout` 을 부른 구조적 태스크의)** 취소를 관측해 continuation 을
    /// `CancellationError` 로 재개한다. 측정 태스크는 멈추지 않고 계속 돌게 둔다 —
    /// 결과만 버린다. onCancel 이 트리거되면 `resumeOnce`(위 두 태스크와 같은
    /// instance)로 재개하므로 셋 중 이긴 하나만 실제로 continuation 을 건드린다.
    ///
    /// **`measure` 를 주입받는 이유(`private` 이 아닌 이유도 같다):** 로컬 에뮬레이터
    /// 왕복은 연결이 데워지면 1ms 아래로 떨어진다(실측 확인 — 취소를 고정 지연
    /// 뒤에 걸거나 방금 잰 실제 왕복 시간의 절반 뒤에 걸어도, 스위트를 통째로
    /// 돌리는 순간 매번 취소가 이미 끝난 응답을 뒤쫓아가 실패했다). 그래서
    /// "서버 왕복 도중" 을 실제 네트워크 타이밍으로 흉내 내는 테스트는 이 환경에서
    /// 근본적으로 결정적일 수 없다. `measure` 자리에 테스트가 직접 제어하는(=끝나는
    /// 시점을 정확히 아는) 가짜 측정을 꽂으면, 실제 왕복이 몇 ms 가 걸리든과 무관하게
    /// "아직 안 끝났을 때" 취소를 걸 수 있다. 기본값은 프로덕션이 그대로 쓰는
    /// `measureServerOffset` 이라 호출부(`serverNow`) 동작은 안 바뀐다.
    static func measureWithTimeout(
        familyId: String?,
        uid: String?,
        measure: @escaping @Sendable (String?, String?) async throws -> Int64 = measureServerOffset
    ) async throws -> Int64 {
        let resumeOnce = ResumeOnce<Int64>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int64, Error>) in
                Task { await resumeOnce.attach(continuation) }
                Task {
                    do {
                        let value = try await measure(familyId, uid)
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
        } onCancel: {
            Task { await resumeOnce.resume(.failure(CancellationError())) }
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

        // 서버에 **저장되는** 기본 이름은 문구 키를 쓰지 않는다. 키 값은 언어마다 달라지고(6단계부터 14개),
        // role_guardian 은 화면용이라 "보호자 (엄마·아빠)"다. 안드로이드는 이 값들을 글자 그대로 저장한다
        // (FamilyRepository.kt:145, 156, 349 — README "안드로이드에 남은 다국어 구멍" 3번).
        try await familyRef.setData(
            FamilyDoc(
                name: "우리 가족",
                createdAt: bootTime,
                ownerUid: guardianUid,
                schemaVersion: FamilyDoc.currentSchemaVersion
            ).firestoreData
        )
        try await familyRef.collection("members").document(guardianUid).setData(
            MemberDoc(
                role: .guardian,
                displayName: "보호자",
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
        let now = try await serverNow(familyId: familyId, uid: creatorUid)
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

        let now = try await serverNow(familyId: doc.familyId, uid: uid)
        guard doc.expiresAt > now else { throw PairingError.expired }

        let familyRef = db.collection("families").document(doc.familyId)
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        // 저장 이름은 글자 그대로다 — 문구 키를 쓰지 않는 이유는 createFamily 의 주석.
        let fallback = doc.role == .guardian ? "보호자" : "아이"
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
    /// 정렬은 포팅된 `ChildSelector.select` 가 한다(정본은 안드로이드
    /// `logic/ChildSelector.kt`) — 같은 가족, 같은 저장된 선호값인데 두 폰이 서로
    /// 다른 자녀를 고르면 Phase 3 지도가 보호자마다 다른 아이를 보여준다. Phase 1
    /// 은 이 정렬을 여기 인라인으로 흉내내 뒀었다(가입 시각 오름차순 → 표시 이름 →
    /// uid, 가입 시각 0 은 "모름"으로 보고 가장 늦은 값으로 취급); Phase 2 가 그
    /// 인라인을 지우고 실제 포트를 부르는 것으로 바꿨다.
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
    /// 리스너가 나중에 고른 아이가 갈릴 수 있다 — 그래서 로직을 한 곳에 두고, 그
    /// 로직 자체는 `ChildSelector.select` 에 맡긴다.
    private static func selectChildUid(
        from children: [(uid: String, member: MemberDoc)],
        preferred: String?
    ) -> String? {
        let selectable = children.map {
            SelectableChild(uid: $0.uid, displayName: $0.member.displayName, joinedAt: $0.member.joinedAt)
        }
        return ChildSelector.select(children: selectable, preferredUid: preferred)?.uid
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

    /// 자녀의 마지막 상태(children/{childUid} 문서, 별도 status 하위 문서가 아니다)를
    /// **한 번** 읽는다. 문서가 아직 없으면(자녀 폰이 한 번도 안 올렸으면) nil.
    ///
    /// 정본은 안드로이드 `FamilyRepository.fetchChildStatus` 다. 옛 상시 구독
    /// (`observeChildStatus`)을 이 화면(`ChildMapView`)에서 걷어낸 이유가 안드로이드와
    /// 같다: 아이 폰이 더 이상 주기적으로 위치를 올리지 않아 이 문서가 거의 안
    /// 바뀌는데(부모가 '지금 위치 확인'을 누르거나 하루 한 번), 화면이 떠 있는 내내
    /// 리스너를 붙들고 있으면 Spark 무료 읽기 한도만 축낸다.
    static func fetchChildStatus(familyId: String, childUid: String) async throws -> ChildStatusDoc? {
        let snap = try await db.collection("families").document(familyId)
            .collection("children").document(childUid).getDocument()
        guard let data = snap.data() else { return nil }
        return ChildStatusDoc(data)
    }

    /// 멤버 문서 하나를 **한 번** 읽는다. 상태 카드가 아이 이름을 보여주는 데만
    /// 쓴다(안드로이드 `child_name` 텍스트뷰와 같은 자리). 목록 전체를 구독하는
    /// `applyMembers`(안드로이드) 수준의 기능은 아직 이 화면에 없다 — 다중 자녀
    /// 선택기·이름 중복 처리는 이 Task 의 범위 밖이라, 문서가 없으면(또는 아직
    /// 안 읽었으면) 화면이 `child_default_name` 으로 물러난다.
    static func fetchMember(familyId: String, uid: String) async throws -> MemberDoc? {
        let snap = try await db.collection("families").document(familyId)
            .collection("members").document(uid).getDocument()
        guard let data = snap.data() else { return nil }
        return MemberDoc(data)
    }

    /// 아이 상태 문서를 구독한다. 돌려받은 등록은 화면이 사라질 때 반드시 remove 한다.
    ///
    /// **1단계 지도(`ChildMapView`)는 이제 이 함수를 쓰지 않는다** — 위
    /// `fetchChildStatus` 로 바뀌었다(이유는 그 함수 주석). 이 함수 자체는 지우지
    /// 않고 남겨둔다: Phase 3의 '지금 위치 확인' 라이브 추적 세션이 화면에 떠
    /// 있는 짧은 시간 동안만 진짜 실시간 구독이 필요하고, 그때 이 함수를 다시
    /// 쓴다.
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

    /// 보호자·자녀 전체 멤버를 감시한다. 선택기와 초대 완료 판정이 쓴다(`FamilyRepository.kt:245-267`).
    /// 붙인 리스너는 부르는 쪽이 사라질 때 반드시 remove 한다.
    static func observeMembers(
        familyId: String,
        onChange: @escaping ([FamilyMember]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        db.collection("families").document(familyId).collection("members")
            .addSnapshotListener { snapshot, error in
                if let error { onError(error); return }
                onChange(snapshot?.documents.map(familyMember) ?? [])
            }
    }

    /// 한 번 읽는다. 초대 화면이 "이미 있던 멤버"를 기준으로 삼는다(`:269-278`, `GuardianPairingActivity.kt:121`).
    static func fetchMembers(familyId: String) async throws -> [FamilyMember] {
        try await db.collection("families").document(familyId).collection("members")
            .getDocuments().documents.map(familyMember)
    }

    private static func familyMember(_ doc: QueryDocumentSnapshot) -> FamilyMember {
        let data = doc.data()
        return FamilyMember(
            uid: doc.documentID,
            role: data["role"] as? String ?? "",
            displayName: data["displayName"] as? String ?? "",
            joinedAt: (data["joinedAt"] as? NSNumber)?.int64Value ?? 0
        )
    }
}
