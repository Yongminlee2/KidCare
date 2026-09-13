import FirebaseFirestore
import Foundation
import Testing
import os
@testable import KidCare

/// "이 아이폰을 가족에서 빼기"의 순서와 실패 규칙(7단계 계획서 판정 기록 8). 서버·계정·이 폰은 모두 가짜로 주입한다.
@MainActor
struct LeaveFamilyModelTests {

    final class 기록: Sendable {
        private let lock = OSAllocatedUnfairLock(initialState: [String]())
        var 순서: [String] { lock.withLock { $0 } }
        func 적는다(_ s: String) { lock.withLock { $0.append(s) } }
    }

    /// 시간 초과가 이기지 않게 하는 기본 sleep — 한 시간.
    static let 오래: @Sendable (Int64) async -> Void = { _ in try? await Task.sleep(nanoseconds: 3_600_000_000_000) }

    private func 만든다(
        _ log: 기록,
        uid: String? = "me",
        읽기_전용: Bool = false,
        remove: @escaping LeaveFamilyModel.RemoveMember,
        auth: LeaveFamilyRepository.AuthOutcome = .deleted,
        sleep: @escaping @Sendable (Int64) async -> Void = LeaveFamilyModelTests.오래
    ) -> LeaveFamilyModel {
        LeaveFamilyModel(
            familyId: "fam",
            읽기_전용: 읽기_전용,
            currentUid: { uid },
            removeMember: remove,
            deleteAuth: { log.적는다("auth"); return auth },
            clearLocal: { log.적는다("local") },
            onLeft: { outcome in log.적는다("left \(outcome.map { "\($0)" } ?? "nil")") },
            sleep: sleep
        )
    }

    @Test("서버가 빠진 것을 확인한 뒤에만 계정, 그다음 이 폰의 기록을 지운다")
    func 순서() async {
        let log = 기록()
        let m = 만든다(log, remove: { familyId, uid in log.적는다("remove \(familyId) \(uid)") })
        m.묻는다()
        await m.뺀다()
        #expect(log.순서 == ["remove fam me", "auth", "left deleted", "local"])
        #expect(m.실패_문구 == nil)
        #expect(m.빼는중 == false)
        #expect(m.묻는중 == false)
        #expect(m.계정_결과 == .deleted)
    }

    @Test("계정 삭제를 서버가 받지 않으면 로그아웃만 한 것을 그대로 알리고, 이 폰의 기록은 지운다")
    func 계정은_로그아웃만() async {
        let log = 기록()
        let m = 만든다(log, remove: { _, _ in log.적는다("remove") }, auth: .signedOutOnly)
        await m.뺀다()
        #expect(log.순서 == ["remove", "auth", "left signedOutOnly", "local"])
        #expect(m.계정_결과 == .signedOutOnly)
        #expect(LeaveFamilyModel.끝_문구(.signedOutOnly) == String(localized: "ios_leave_family_done_signed_out_message"))
        #expect(LeaveFamilyModel.끝_문구(.deleted) == String(localized: "ios_leave_family_done_message"))
    }

    @Test("서버 확인이 15초 안에 안 오면 아무것도 지우지 않고 오프라인이라고 말한다")
    func 시간_초과() async {
        let log = 기록()
        let m = 만든다(
            log,
            remove: { _, _ in try await Task.sleep(nanoseconds: 3_600_000_000_000) },
            sleep: { millis in
                #expect(millis == LeaveFamilyModel.timeoutMillis)
            }
        )
        await m.뺀다()
        #expect(log.순서 == [])
        #expect(m.실패_문구 == String(localized: "ios_leave_family_offline"))
        #expect(m.빼는중 == false)
        #expect(m.계정_결과 == nil)
        #expect(LeaveFamilyModel.timeoutMillis == 15_000)
    }

    @Test("시간 초과로 끝난 뒤에 서버 확인이 늦게 와도 계정과 이 폰의 기록을 지우지 않는다")
    func 늦은_확인() async {
        let log = 기록()
        let 문 = TestSignal()
        let 끝 = TestSignal()
        let m = 만든다(
            log,
            remove: { _, _ in
                await 문.wait()
                log.적는다("remove")
                await 끝.fire()
            },
            sleep: { _ in }
        )
        await m.뺀다()
        #expect(m.실패_문구 == String(localized: "ios_leave_family_offline"))
        await 문.fire()
        await 끝.wait()
        // 늦은 결과가 흘러갈 틈을 준다.
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(log.순서 == ["remove"])
        #expect(m.계정_결과 == nil)
    }

    @Test("서버가 거부하면 errorMessage 문구를 보이고 아무것도 지우지 않는다")
    func 거부() async {
        let log = 기록()
        let denied = NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.permissionDenied.rawValue)
        let m = 만든다(log, remove: { _, _ in throw denied })
        await m.뺀다()
        #expect(log.순서 == [])
        #expect(m.실패_문구 == errorMessage(denied))
        m.실패를_닫는다()
        #expect(m.실패_문구 == nil)
    }

    @Test("서버에 닿지 못했다는 오류(unavailable)도 오프라인 문구로 알리고 아무것도 지우지 않는다")
    func 닿지_못함() async {
        let log = 기록()
        let unavailable = NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.unavailable.rawValue)
        let m = 만든다(log, remove: { _, _ in throw unavailable })
        await m.뺀다()
        #expect(log.순서 == [])
        #expect(m.실패_문구 == String(localized: "ios_leave_family_offline"))
    }

    @Test("로그인한 적이 없으면 서버에 묻지 않고 이 폰의 기록만 지운다")
    func 로그인_전() async {
        let log = 기록()
        let m = 만든다(log, uid: nil, remove: { _, _ in log.적는다("remove") })
        await m.뺀다()
        #expect(log.순서 == ["left nil", "local"])
    }

    @Test("빼는 중에 다시 눌러도 서버에는 한 번만 간다")
    func 두_번_눌러도_한_번() async {
        let log = 기록()
        let m = 만든다(log, remove: { _, _ in
            try await Task.sleep(nanoseconds: 50_000_000)
            log.적는다("remove")
        })
        let first = Task { await m.뺀다() }
        await eventually { m.빼는중 }
        await m.뺀다()
        m.묻는다()                       // 빼는 중에는 대화상자를 다시 열지 않는다
        #expect(m.묻는중 == false)
        await first.value
        #expect(log.순서 == ["remove", "auth", "left deleted", "local"])
    }

    @Test("읽기 전용 확인에서는 묻지도 빼지도 않는다 — 메뉴의 .disabled 에만 기대지 않는다(6단계 통합 검토 I3 와 같은 자리)")
    func 읽기_전용이면_빼지_않는다() async {
        let log = 기록()
        let m = 만든다(log, 읽기_전용: true, remove: { _, _ in log.적는다("remove") })
        m.묻는다()
        #expect(m.묻는중 == false)
        await m.뺀다()
        #expect(log.순서 == [])
        #expect(m.빼는중 == false)
        #expect(m.실패_문구 == nil)
    }

    @Test("마지막 보호자면 경고를 앞에 붙이고, 둘 이상이면 기본 문구만")
    func 확인_문구() {
        let base = String(localized: "ios_leave_family_message")
        #expect(LeaveFamilyModel.확인_문구(보호자_수: 2) == base)
        #expect(LeaveFamilyModel.확인_문구(보호자_수: 1) != base)
        #expect(LeaveFamilyModel.확인_문구(보호자_수: 1).hasSuffix(base))
        // 멤버 목록을 아직 못 받았으면(0) 경고 쪽으로 기운다 — 경고가 빠지는 것보다 남는 것이 안전하다.
        #expect(LeaveFamilyModel.확인_문구(보호자_수: 0) == LeaveFamilyModel.확인_문구(보호자_수: 1))
    }

    @Test("묻고 취소하면 아무것도 지우지 않는다")
    func 취소() async {
        let log = 기록()
        let m = 만든다(log, remove: { _, _ in log.적는다("remove") })
        m.묻는다()
        #expect(m.묻는중)
        m.취소한다()
        #expect(m.묻는중 == false)
        #expect(log.순서 == [])
    }

    @Test("이 폰의 기록 지우기는 이 앱이 쓴 키만 지우고, 설정 앱의 앱별 언어(AppleLanguages) 같은 남의 키는 남긴다")
    func 이_폰의_기록() throws {
        let suite = "LeaveFamilyModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RoleStore(defaults: defaults)
        store.role = .guardian
        store.familyId = "fam"
        store.childUid = "c1"
        RequestLog(defaults: defaults).recordRequest("c1")
        RequestLog(defaults: defaults).recordAnswer("c1")
        AlarmMemoStore(defaults: defaults).recordSent(childUid: "c1", minuteOfDay: 420, label: "학교")
        RuleSyncStore(kind: .schedule, defaults: defaults).setPendingSync(childUid: "c1", true)
        RuleSyncStore(kind: .place, defaults: defaults).setPendingSync(childUid: "c2", true)
        defaults.set(["ja"], forKey: "AppleLanguages")

        LeaveFamilyModel.이_폰의_기록을_지운다(defaults: defaults, roleStore: store)

        #expect(store.role == nil && store.familyId == nil && store.childUid == nil)
        // 네 저장소가 진짜로 쓴 키가 모두 사라지고 남의 키 하나만 남는다 — 저장소가 키 이름을 바꾸면 여기서 드러난다.
        let left = (defaults.persistentDomain(forName: suite) ?? [:]).keys.sorted()
        #expect(left == ["AppleLanguages"], "남은 키: \(left)")
        // 읽기는 도메인에서 직접 한다 — `stringArray(forKey:)` 는 테스트 실행 인자(-AppleLanguages)가 먼저 답한다.
        #expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] as? [String] == ["ja"])
    }
}

/// 처리방침 줄은 https 주소가 있을 때만 뜬다(판정 기록 9). 지금은 비어 있어 줄이 없다 — 주소를 지어내지 않는다.
struct PrivacyPolicyLinkTests {
    @Test("비었거나 https 가 아니거나 호스트가 없으면 nil, https 면 그 주소")
    func 주소() {
        #expect(PrivacyPolicyLink.url(info: nil) == nil)
        #expect(PrivacyPolicyLink.url(info: [:]) == nil)
        #expect(PrivacyPolicyLink.url(info: ["KidCarePrivacyPolicyURL": ""]) == nil)
        #expect(PrivacyPolicyLink.url(info: ["KidCarePrivacyPolicyURL": "https://"]) == nil)
        #expect(PrivacyPolicyLink.url(info: ["KidCarePrivacyPolicyURL": "http://example.com/privacy"]) == nil)
        #expect(PrivacyPolicyLink.url(info: ["KidCarePrivacyPolicyURL": "https://example.com/privacy"])?.absoluteString
                == "https://example.com/privacy")
    }
}
