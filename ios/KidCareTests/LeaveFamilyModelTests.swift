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
        deleteAuth: LeaveFamilyModel.DeleteAuth? = nil,
        signOut: LeaveFamilyRepository.AuthOutcome = .signedOutOnly,
        clearLocal: (@MainActor () -> Void)? = nil,
        sleep: @escaping @Sendable (Int64) async -> Void = LeaveFamilyModelTests.오래
    ) -> LeaveFamilyModel {
        LeaveFamilyModel(
            familyId: "fam",
            읽기_전용: 읽기_전용,
            currentUid: { uid },
            removeMember: remove,
            deleteAuth: deleteAuth ?? { log.적는다("auth"); return auth },
            signOut: { log.적는다("signOut"); return signOut },
            clearLocal: { log.적는다("local"); clearLocal?() },
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
        #expect(m.실패 == nil)
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
        #expect(LeaveFamilyModel.끝_문구(.signedOutOnly) == String(localized: "leave_family_done_signed_out_message"))
        #expect(LeaveFamilyModel.끝_문구(.deleted) == String(localized: "leave_family_done_message"))
        #expect(LeaveFamilyModel.끝_문구(.notSignedOut) == String(localized: "ios_leave_family_done_not_signed_out_message"))
    }

    @Test("계정 삭제가 10초 안에 끝나지 않으면 로그아웃으로 물러나 그 결과를 그대로 알리고, 이 폰의 기록을 지운다(리뷰 I1 c)")
    func 계정_삭제_시간_초과() async {
        let log = 기록()
        let 잰_시간 = 기록()
        let m = 만든다(
            log,
            remove: { _, _ in log.적는다("remove") },
            deleteAuth: { log.적는다("auth"); try? await Task.sleep(nanoseconds: 3_600_000_000_000); return .deleted },
            sleep: { millis in
                잰_시간.적는다("\(millis)")
                // 서버 확인 쪽 시간 초과는 이기지 않게, 계정 쪽은 곧바로 끝나게 한다.
                if millis == LeaveFamilyModel.timeoutMillis { try? await Task.sleep(nanoseconds: 3_600_000_000_000) }
            }
        )
        await m.뺀다()
        #expect(log.순서 == ["remove", "auth", "signOut", "left signedOutOnly", "local"])
        #expect(m.계정_결과 == .signedOutOnly)
        #expect(m.실패 == nil)
        #expect(잰_시간.순서.contains("\(LeaveFamilyModel.authTimeoutMillis)"))
        #expect(LeaveFamilyModel.authTimeoutMillis == 10_000)
    }

    @Test("로그아웃도 되지 않았으면 로그아웃했다고 말하지 않는다(리뷰 M2)")
    func 로그아웃도_안_됨() async {
        let log = 기록()
        let m = 만든다(
            log,
            remove: { _, _ in log.적는다("remove") },
            deleteAuth: { log.적는다("auth"); try? await Task.sleep(nanoseconds: 3_600_000_000_000); return .deleted },
            signOut: .notSignedOut,
            sleep: { millis in
                if millis == LeaveFamilyModel.timeoutMillis { try? await Task.sleep(nanoseconds: 3_600_000_000_000) }
            }
        )
        await m.뺀다()
        #expect(log.순서 == ["remove", "auth", "signOut", "left notSignedOut", "local"])
        #expect(m.계정_결과 == .notSignedOut)
    }

    @Test("서버 확인이 15초 안에 안 오면 아무것도 지우지 않고, 실패가 아니라 확인하지 못했다고 말한다(리뷰 I1)")
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
        #expect(m.실패 == LeaveFamilyModel.안내(
            제목: String(localized: "ios_leave_family_unconfirmed_title"),
            문구: String(localized: "leave_family_unconfirmed_message")
        ))
        #expect(m.실패?.제목 != String(localized: "leave_family_failed_title"))
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
        #expect(m.실패 == LeaveFamilyModel.확인하지_못함)
        await 문.fire()
        await 끝.wait()
        // 늦은 결과가 흘러갈 틈을 준다. `끝.wait()` 로 늦은 `remove` 가 실제로 끝난 것은 이미
        // 확인했고, 남은 것은 아무도 안 듣는 `resolve` 하나다 — 벽시계로 기다릴 일이 아니다.
        await 주_액터를_한_바퀴_돌린다()
        #expect(log.순서 == ["remove"])
        #expect(m.계정_결과 == nil)
    }

    @Test("15초 뒤에 늦게 커밋돼 서버에서는 빠졌으면, 다시 누를 때 계정과 이 폰의 기록까지 마무리된다(리뷰 I1 b)")
    func 늦은_커밋_뒤_다시_누르면_마무리() async {
        let log = 기록()
        let 문 = TestSignal()
        let 끝 = TestSignal()
        // 서버 흉내: 첫 호출은 문이 열릴 때 커밋되고, 그 뒤의 호출은 `removeMember` 의 "이미 빠짐" 판정처럼 성공한다.
        let 서버 = 기록()
        let 잰_횟수 = 기록()
        let m = 만든다(
            log,
            remove: { _, _ in
                if 서버.순서.isEmpty {
                    서버.적는다("첫 시도")
                    await 문.wait()
                    log.적는다("late commit")
                    await 끝.fire()
                } else {
                    log.적는다("remove again")
                }
            },
            sleep: { millis in
                // 첫 누름의 서버 확인 한도만 곧바로 끝난다(시간 초과). 두 번째 누름과 계정 쪽 한도는 이기지 않는다.
                if millis == LeaveFamilyModel.timeoutMillis, 잰_횟수.순서.isEmpty {
                    잰_횟수.적는다("첫 한도")
                    return
                }
                try? await Task.sleep(nanoseconds: 3_600_000_000_000)
            }
        )
        await m.뺀다()
        #expect(m.실패 == LeaveFamilyModel.확인하지_못함)
        await 문.fire()
        await 끝.wait()
        m.실패를_닫는다()

        m.묻는다()
        await m.뺀다()
        #expect(log.순서 == ["late commit", "remove again", "auth", "left deleted", "local"])
        #expect(m.실패 == nil)
        #expect(m.계정_결과 == .deleted)
    }

    @Test("서버가 거부하면 errorMessage 문구를 보이고 아무것도 지우지 않는다")
    func 거부() async {
        let log = 기록()
        let denied = NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.permissionDenied.rawValue)
        let m = 만든다(log, remove: { _, _ in throw denied })
        await m.뺀다()
        #expect(log.순서 == [])
        #expect(m.실패 == LeaveFamilyModel.안내(제목: String(localized: "leave_family_failed_title"), 문구: errorMessage(denied)))
        m.실패를_닫는다()
        #expect(m.실패 == nil)
    }

    @Test("서버에 닿지 못했거나 기한을 넘긴 오류(unavailable, deadlineExceeded)도 확인하지 못했다고 알리고 아무것도 지우지 않는다")
    func 닿지_못함() async {
        for code in [FirestoreErrorCode.unavailable, .deadlineExceeded] {
            let log = 기록()
            let error = NSError(domain: FirestoreErrorDomain, code: code.rawValue)
            let m = 만든다(log, remove: { _, _ in throw error })
            await m.뺀다()
            #expect(log.순서 == [])
            #expect(m.실패 == LeaveFamilyModel.확인하지_못함)
        }
    }

    @Test("본 화면인데 로그인 정보가 없으면 서버도 이 폰도 건드리지 않고 실패로 알린다(리뷰 M4)")
    func 로그인_정보_없음() async {
        let log = 기록()
        let m = 만든다(log, uid: nil, remove: { _, _ in log.적는다("remove") })
        await m.뺀다()
        #expect(log.순서 == [])
        #expect(m.실패 == LeaveFamilyModel.안내(
            제목: String(localized: "leave_family_failed_title"),
            문구: String(localized: "leave_family_no_account")
        ))
        #expect(m.계정_결과 == nil)
    }

    @Test("서버에서 빠진 뒤 건 정리(선택기·탭)를 계정 삭제와 이 폰의 기록 지우기보다 먼저 부르고, 뗀 정리는 부르지 않는다(리뷰 M3)")
    func 정리_먼저() async {
        let log = 기록()
        let m = 만든다(log, remove: { _, _ in log.적는다("remove") })
        let 뗄_것 = UUID()
        m.떠나기_전에(UUID()) { log.적는다("teardown") }
        m.떠나기_전에(뗄_것) { log.적는다("removed teardown") }
        m.정리를_뗀다(뗄_것)
        await m.뺀다()
        #expect(log.순서 == ["remove", "teardown", "auth", "left deleted", "local"])
    }

    @Test("빠진 뒤 늦게 온 멤버 스냅샷이 지운 childUid 를 다시 쓰지 못한다 — 진짜 선택기로(리뷰 M3)")
    func 늦은_스냅샷이_선택을_되살리지_않는다() async {
        let log = 기록()
        let store = RoleStore(defaults: TestDefaults.isolated("LeaveFamilyModelTests-M3"))
        store.role = .guardian
        store.familyId = "fam"
        let onChange = TestCallbackBox<([FamilyMember]) -> Void>()
        let selector = ChildSelectorModel(
            familyId: "fam", roleStore: store, 읽기_전용: false,
            membersObserve: { _, change, _ in onChange.set(change); return TestListenerRegistration() }
        )
        selector.시작한다()
        let 아이 = FamilyMember(uid: "c1", role: "child", displayName: "민준", joinedAt: 1)
        onChange.value?([아이])
        await eventually { store.childUid == "c1" }

        let m = 만든다(log, remove: { _, _ in log.적는다("remove") }, clearLocal: { store.clear() })
        m.떠나기_전에(UUID()) { selector.정리한다() }
        await m.뺀다()
        #expect(store.childUid == nil)

        // 리스너를 떼기 직전에 대기열에 올랐던 콜백이 뒤늦게 돈다.
        onChange.value?([아이])
        await 주_액터를_한_바퀴_돌린다()
        #expect(store.childUid == nil)
        #expect(store.familyId == nil)
    }

    @Test("빼는 중에 다시 눌러도 서버에는 한 번만 간다")
    func 두_번_눌러도_한_번() async {
        let log = 기록()
        // 서버 쓰기가 **문이 열릴 때까지** 안 끝난다. 예전에는 50ms 를 기다렸는데, 그 50ms
        // 안에 `뺀다()` 가 끝나 버리면 `eventually { m.빼는중 }` 이 참을 영영 못 본다
        // (1단계 통합 검토 M5 — 이 자리가 가장 위험했다).
        let 문 = TestSignal()
        let m = 만든다(log, remove: { _, _ in
            await 문.wait()
            log.적는다("remove")
        })
        let first = Task { await m.뺀다() }
        await eventually { m.빼는중 }
        await m.뺀다()
        m.묻는다()                       // 빼는 중에는 대화상자를 다시 열지 않는다
        #expect(m.묻는중 == false)
        await 문.fire()
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
        #expect(m.실패 == nil)
    }

    @Test("마지막 보호자면 따로 쓴 문구(새 초대 번호 이야기 없음), 둘 이상이면 기본 문구(리뷰 I2)")
    func 확인_문구() {
        let base = String(localized: "leave_family_message")
        let last = String(localized: "leave_family_last_guardian_message")
        #expect(LeaveFamilyModel.확인_문구(보호자_수: 2) == base)
        #expect(LeaveFamilyModel.확인_문구(보호자_수: 1) == last)
        #expect(last != base && !last.contains(base))
        #expect(last != "leave_family_last_guardian_message", "카탈로그에 키가 없다")
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
