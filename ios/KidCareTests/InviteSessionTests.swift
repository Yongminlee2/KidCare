import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 정본은 `GuardianPairingActivity.kt` 의 초대 갈래. 줄 번호는 테스트 이름에 적는다.
@MainActor
struct InviteSessionTests {

    final class 가짜_멤버_구독: Sendable {
        let onChange = TestCallbackBox<([FamilyMember]) -> Void>()
        let onError = TestCallbackBox<(Error) -> Void>()
        let registration = TestListenerRegistration()
        let 횟수 = TestCounter()
        func 보낸다(_ members: [FamilyMember]) { onChange.value?(members) }
    }

    actor 발급_기록 {
        private(set) var 이전_코드들: [String?] = []
        func 기록(_ previous: String?) { 이전_코드들.append(previous) }
    }

    /// 서버의 `inviteCodes` 흉내. 진짜 `FamilyRepository.createInvite` 처럼 발급이 `previousCode` 를 받으면
    /// 새 코드를 쓴 **뒤에** 그 코드를 지운다 — 옛 세션(경주 안에서 이전 코드를 넘기던 코드)도 같은 가짜로 빨갛게 드러난다.
    actor 가짜_초대_저장소 {
        private(set) var 살아있는_코드: Set<String> = []
        private(set) var 지운_코드: [String] = []
        private var 순번 = 0
        func 발급(_ previous: String?) -> String {
            순번 += 1
            let code = 순번 == 1 ? "ABC234" : "NEW\(순번)00"
            살아있는_코드.insert(code)
            if let previous { 지운다(previous) }
            return code
        }
        func 지운다(_ code: String) {
            살아있는_코드.remove(code)
            지운_코드.append(code)
        }
    }

    @MainActor final class 합류_기록 {
        var 멤버들: [FamilyMember] = []
    }

    private static let 지금 = Int64(1_789_279_920_000)
    private static let 오래_잔다: @Sendable (Int64) async -> Void = { _ in try? await Task.sleep(nanoseconds: 60_000_000_000) }

    private func 멤버(_ uid: String, _ role: String) -> FamilyMember {
        FamilyMember(uid: uid, role: role, displayName: "", joinedAt: 1)
    }

    /// 기본 가짜: 기준 멤버 둘(g1 보호자, c1 아이), 첫 발급은 ABC234, 새 번호는 XYZ789, 만료는 10분 뒤.
    private func 만든다(
        role: MemberRole = .child,
        expiresIn: Int64 = 600_000,
        기록: 발급_기록 = 발급_기록(),
        구독: 가짜_멤버_구독 = 가짜_멤버_구독(),
        합류: 합류_기록 = 합류_기록(),
        sleep: @escaping @Sendable (Int64) async -> Void = InviteSessionTests.오래_잔다,
        create: InviteSession.Create? = nil,
        deleteCode: @escaping InviteSession.DeleteCode = { _ in }
    ) -> InviteSession {
        let now = Self.지금
        let 기준 = [멤버("g1", "guardian"), 멤버("c1", "child")]
        let 순번 = TestCounter()
        return InviteSession(
            familyId: "fam",
            role: role,
            create: create ?? { _, role, previous in
                await 기록.기록(previous)
                let code = await 순번.next() == 1 ? "ABC234" : "XYZ789"
                return InviteCodeInfo(code: code, expiresAt: now + expiresIn, role: role)
            },
            deleteCode: deleteCode,
            fetch: { _ in 기준 },
            observe: { _, onChange, onError in
                구독.onChange.set(onChange)
                구독.onError.set(onError)
                Task { await 구독.횟수.next() }
                return 구독.registration
            },
            deviceNow: { now },
            sleep: sleep,
            onJoined: { 합류.멤버들.append($0) }
        )
    }

    @Test("아이 초대: 번호·안내·만료·'새 번호 받기'가 뜨고 진행 표시가 꺼진다(:197-215, :232-240)")
    func 아이_초대_발급() async {
        let s = 만든다(role: .child)
        #expect(s.제목 == String(localized: "pairing_guardian_title"))
        s.시작한다()
        await eventually { s.코드 == "ABC234" }
        #expect(s.안내 == String(localized: "pairing_guardian_hint"))
        #expect(s.만료_문구 == "이 번호는 10분 뒤에 만료돼요")
        #expect(s.버튼_문구 == "새 번호 받기")
        #expect(s.버튼_활성)
        #expect(!s.진행중)
    }

    @Test("보호자 초대는 다른 보호자용 제목과 안내를 쓴다(:232-240)")
    func 보호자_초대_문구() async {
        let s = 만든다(role: .guardian)
        #expect(s.제목 == String(localized: "pairing_guardian_invite_guardian_title"))
        #expect(s.안내 == String(localized: "pairing_guardian_invite_guardian_hint"))
        s.시작한다()
        await eventually { s.코드 != nil }
        #expect(s.안내 == String(localized: "pairing_guardian_invite_guardian_hint"))
    }

    @Test("만료 분은 기기 시계로 올림하고 최소 1분(:203-205)")
    func 만료_분() async {
        for (expiresIn, 분) in [(Int64(1), Int64(1)), (-5_000, 1), (600_001, 11)] {
            let s = 만든다(expiresIn: expiresIn)
            s.시작한다()
            await eventually { s.코드 != nil }
            #expect(s.만료_분 == 분, "\(expiresIn)")
        }
    }

    @Test("기준에 없던 같은 역할 멤버가 들어오면 한 번만 넘어가고 감시를 뗀다(:123-130, :46-50, :217-230)")
    func 합류는_한_번() async {
        let 구독 = 가짜_멤버_구독(), 합류 = 합류_기록()
        let s = 만든다(role: .child, 구독: 구독, 합류: 합류)
        s.시작한다()
        await eventually { s.코드 != nil && 구독.onChange.value != nil }
        구독.보낸다([멤버("g1", "guardian"), 멤버("c1", "child")])
        구독.보낸다([멤버("g1", "guardian"), 멤버("c1", "child"), 멤버("g2", "guardian")])
        구독.보낸다([멤버("g1", "guardian"), 멤버("c1", "child"), 멤버("g2", "guardian"), 멤버("c2", "child")])
        구독.보낸다([멤버("c2", "child"), 멤버("c3", "child")])
        await eventually { !합류.멤버들.isEmpty }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(합류.멤버들.map(\.uid) == ["c2"])
        #expect(구독.registration.removed)
    }

    @Test("20초 안에 발급이 안 끝나면 pairing_offline 과 '다시 시도', 누르면 처음부터 다시 한다(:133-146, :163-168, :77-79)")
    func 시간_초과() async {
        let 기록 = 발급_기록(), 첫_발급 = TestGate(), 발급_횟수 = TestCounter(), 잠_횟수 = TestCounter()
        let now = Self.지금
        let s = 만든다(
            sleep: { _ in
                if await 잠_횟수.next() == 1 { return }                        // 첫 판은 곧장 시간 초과
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            },
            create: { _, role, previous in
                await 기록.기록(previous)
                if await 발급_횟수.next() == 1 { await 첫_발급.wait() }        // 첫 발급은 매달린다
                return InviteCodeInfo(code: "QWE345", expiresAt: now + 600_000, role: role)
            }
        )
        s.시작한다()
        await eventually { s.버튼_문구 == "다시 시도" }
        #expect(s.안내 == String(localized: "pairing_offline"))
        #expect(s.버튼_활성)
        #expect(!s.진행중)
        #expect(s.코드 == nil)
        s.버튼을_눌렀다()
        await eventually { s.코드 == "QWE345" }
        #expect(await 기록.이전_코드들 == [nil, nil])
        await 첫_발급.open()
    }

    @Test("발급 실패는 pairing_failed 에 errorMessage 를 끼운다(:147-159)")
    func 발급_실패() async {
        let error = NSError(domain: "test", code: 7, userInfo: [NSLocalizedDescriptionKey: "boom"])
        let s = 만든다(create: { _, _, _ in throw error })
        s.시작한다()
        await eventually { s.버튼_문구 == "다시 시도" }
        #expect(s.안내 == String(format: String(localized: "pairing_failed"), errorMessage(error)))
        #expect(!s.진행중)
    }

    @Test("'새 번호 받기'는 새로 받은 번호를 띄운 뒤 이전 코드를 지우고, 기준 멤버와 감시는 그대로 둔다(:171-194)")
    func 새_번호() async {
        let 기록 = 발급_기록(), 구독 = 가짜_멤버_구독(), 저장소 = 가짜_초대_저장소(), now = Self.지금
        let s = 만든다(기록: 기록, 구독: 구독, create: { _, role, previous in
            await 기록.기록(previous)
            return InviteCodeInfo(code: await 저장소.발급(previous), expiresAt: now + 600_000, role: role)
        }, deleteCode: { await 저장소.지운다($0) })
        s.시작한다()
        await eventually { s.코드 == "ABC234" && s.버튼_활성 }
        s.버튼을_눌렀다()
        await eventually { s.코드 == "NEW200" && s.버튼_활성 }
        // 발급에는 이전 코드를 넘기지 않는다 — 삭제는 새 번호가 받아들여진 뒤 세션이 따로 부른다(통합 검토 I1).
        #expect(await 기록.이전_코드들 == [nil, nil])
        for _ in 0..<200 where await 저장소.지운_코드.isEmpty { try? await Task.sleep(nanoseconds: 1_000_000) }
        #expect(await 저장소.지운_코드 == ["ABC234"])
        #expect(await 저장소.살아있는_코드 == ["NEW200"])
        #expect(!구독.registration.removed)
    }

    @Test("시간 초과에 진 '새 번호'가 늦게 끝나도 화면에 떠 있는 이전 코드를 지우지 않는다(통합 검토 I1)")
    func 늦게_끝난_새_번호는_이전_코드를_지우지_않는다() async {
        let 저장소 = 가짜_초대_저장소(), 잠_횟수 = TestCounter(), 발급_횟수 = TestCounter()
        let 문 = TestGate(), 늦은_발급_끝 = TestSignal(), now = Self.지금
        let s = 만든다(
            sleep: { _ in
                if await 잠_횟수.next() == 2 { return }                          // '새 번호' 경주만 곧장 20초가 지난다
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            },
            create: { _, role, previous in
                if await 발급_횟수.next() == 2 { await 문.wait() }               // 새 번호 발급은 느린 네트워크에 매달린다
                let code = await 저장소.발급(previous)
                if await 발급_횟수.value == 2 { await 늦은_발급_끝.fire() }
                return InviteCodeInfo(code: code, expiresAt: now + 600_000, role: role)
            },
            deleteCode: { await 저장소.지운다($0) }
        )
        s.시작한다()
        await eventually { s.코드 == "ABC234" && s.버튼_활성 }
        s.버튼을_눌렀다()
        await eventually { s.안내 == String(localized: "pairing_offline") && s.버튼_활성 }
        #expect(s.코드 == "ABC234")

        // 25초쯤: 매달렸던 발급이 끝나 새 코드 문서를 쓴다.
        await 문.open()
        await 늦은_발급_끝.wait()
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(await 저장소.지운_코드.isEmpty)
        #expect(await 저장소.살아있는_코드.contains("ABC234"))
        #expect(s.코드 == "ABC234")
        #expect(s.안내 == String(localized: "pairing_offline"))
    }

    @Test("감시 오류는 안내 자리에 pairing_failed 한 줄, 번호는 그대로(:131-133)")
    func 감시_오류() async {
        let 구독 = 가짜_멤버_구독()
        let s = 만든다(구독: 구독)
        s.시작한다()
        await eventually { s.코드 != nil && 구독.onError.value != nil }
        let error = NSError(domain: "test", code: 8, userInfo: [NSLocalizedDescriptionKey: "listen"])
        구독.onError.value?(error)
        await eventually { s.안내 == String(format: String(localized: "pairing_failed"), errorMessage(error)) }
        #expect(s.코드 == "ABC234")
    }

    @Test("정리하면 감시를 떼고, 늦게 온 합류는 무시한다(:241-244)")
    func 정리() async {
        let 구독 = 가짜_멤버_구독(), 합류 = 합류_기록()
        let s = 만든다(구독: 구독, 합류: 합류)
        s.시작한다()
        await eventually { 구독.onChange.value != nil }
        s.정리한다()
        #expect(구독.registration.removed)
        구독.보낸다([멤버("c9", "child")])
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(합류.멤버들.isEmpty)
    }

    @Test("정리 뒤에 늦게 온 감시 오류는 안내를 덮지 않는다")
    func 정리_뒤_늦은_감시_오류() async {
        let 구독 = 가짜_멤버_구독()
        let s = 만든다(구독: 구독)
        s.시작한다()
        await eventually { s.코드 != nil && 구독.onError.value != nil }
        let 안내 = s.안내
        s.정리한다()
        구독.onError.value?(NSError(domain: "test", code: 9))
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(s.안내 == 안내)
    }

    @Test("정리 뒤에 늦게 끝난 발급은 번호도 감시도 만들지 않는다(계획서 통합 리뷰 3)")
    func 정리_뒤_늦은_발급() async {
        let 문 = TestGate(), 들어감 = TestSignal(), 구독 = 가짜_멤버_구독(), now = Self.지금
        let s = 만든다(구독: 구독, create: { _, role, _ in
            await 들어감.fire()
            await 문.wait()
            return InviteCodeInfo(code: "LATE22", expiresAt: now + 600_000, role: role)
        })
        s.시작한다()
        // 발급이 실제로 매달린 뒤에 닫는다 — 그 전에 닫으면 취소 검사에서 끝나 늦은 결과 갈래를 지나지 않는다.
        await 들어감.wait()
        s.정리한다()
        await 문.open()
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(s.코드 == nil)
        #expect(await 구독.횟수.value == 0)
    }

    @Test("정리 뒤에 늦게 끝난 '새 번호'는 번호를 바꾸지 않는다")
    func 정리_뒤_늦은_새_번호() async {
        let 문 = TestGate(), 들어감 = TestSignal(), 횟수 = TestCounter(), now = Self.지금
        let s = 만든다(create: { _, role, _ in
            if await 횟수.next() == 2 { await 들어감.fire(); await 문.wait() }
            return InviteCodeInfo(code: await 횟수.value == 1 ? "ABC234" : "NEW777", expiresAt: now + 600_000, role: role)
        })
        s.시작한다()
        await eventually { s.코드 == "ABC234" && s.버튼_활성 }
        s.버튼을_눌렀다()
        await 들어감.wait()
        s.정리한다()
        await 문.open()
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(s.코드 == "ABC234")
        #expect(!s.버튼_활성)
    }

    @Test("시작을 여러 번 불러도(커버 재마운트) 발급은 한 번뿐이다(계획서 통합 리뷰 3)")
    func 시작_중복() async {
        let 기록 = 발급_기록()
        let s = 만든다(기록: 기록)
        s.시작한다()
        s.시작한다()
        await eventually { s.코드 != nil }
        s.시작한다()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(await 기록.이전_코드들 == [nil])
    }
}
