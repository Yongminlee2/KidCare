import CoreLocation
import Testing
import UIKit
@testable import KidCare

/// 설계서 §12.1 이 이름까지 정해 둔 테스트다 — "권한 상태 조합 → 어떤 문장 하나를 보여주나".
/// 안드로이드가 "한 번에 하나만, 고쳐야 다음이 의미 있는 순서"로 정한 것(`ChildHomeActivity.kt:49-51`)을
/// 그대로 고정한다.
@MainActor
struct ChildHomeModelTests {

    private let 정상 = ChildPermissions.Snapshot(
        authorization: .authorizedAlways, accuracy: .fullAccuracy, backgroundRefresh: .available)

    private func 모델(_ p: ChildPermissions.Snapshot, 멤버: Bool? = true, 저전력: Bool = false) -> ChildHomeModel {
        let m = ChildHomeModel()
        m.apply(permissions: p, stillMember: 멤버, lowPower: 저전력)
        return m
    }

    /// **통합 검토 I3 의 재발 방지 자리다.** 초기값이 `.sharing` 이던 시절에는, 로그인이 실패해
    /// 세션이 아예 못 뜬 폰이 "엄마 아빠가 볼 수 있어요"를 띄운 채 굳었다 — 이 앱이 제일
    /// 두려워하는 거짓말(머리 주석)이 정확히 거기서 났다.
    @Test("아무것도 못 받은 화면은 '공유 중'이라고 말하지 않는다 — 수집이 없는 폰의 거짓말이다 (통합 검토 I3)")
    func 시작_전에는_모른다() {
        let m = ChildHomeModel()
        #expect(m.state == .starting)
        #expect(m.state != .sharing)
        #expect(m.bodyKey == "ios_child_starting")
        #expect(m.titleKey == "child_home_title")
        #expect(m.action == nil, "기다리는 동안 누를 것이 없다")
        #expect(m.forceQuitNoticeKey == "ios_child_force_quit_notice", "강제 종료 안내는 여기서도 늘 있다")
    }

    @Test("세션이 못 뜨면 화면이 그렇게 말하고 다시 해 볼 버튼을 준다 (통합 검토 I3)")
    func 못_뜨면_말한다() {
        let m = ChildHomeModel()
        m.cannotStart()
        #expect(m.state == .cannotStart)
        #expect(m.bodyKey == "ios_child_cannot_start")
        #expect(m.action == .init(titleKey: "ios_child_retry", kind: .retry),
                "프로세스 안에 다시 뜰 길이 이 버튼 하나다")
        #expect(m.reasonKey == nil)

        // 다시 눌렀으면 "준비 중"으로 돌아가고 버튼은 거둔다 — 두 번 눌러도 두 벌이 되지 않는다.
        m.starting()
        #expect(m.state == .starting)
        #expect(m.action == nil)

        // 그러고 세션이 뜨면 보통 갈래로 돌아온다.
        m.apply(permissions: 정상, stillMember: true, lowPower: false)
        #expect(m.state == .sharing)
    }

    @Test("다 정상이면 공유 중이라고 말하고 버튼이 없다 (child_sharing_on, ChildHomeActivity.kt:92-97)")
    func 공유중() {
        let m = 모델(정상)
        #expect(m.state == .sharing)
        #expect(m.titleKey == "child_home_title")
        #expect(m.bodyKey == "child_sharing_on")
        #expect(m.action == nil)
    }

    @Test("권한이 빠지면 그 이름과 이유, 그리고 고치는 버튼 (child_permission_missing)")
    func 권한_빠짐() {
        var s = 정상
        s.authorization = .authorizedWhenInUse
        let m = 모델(s)
        #expect(m.state == .permissionMissing(.always))
        #expect(m.bodyKey == "child_permission_missing")
        // `%1$s` 자리에 들어갈 이름
        #expect(m.bodyArgument == String(localized: "ios_child_perm_always_title"))
        #expect(m.reasonKey == "ios_child_perm_always_reason")
        // 두 걸음의 두 번째는 앱이 직접 물을 수 있다(판정 기록 15)
        #expect(m.action == .init(titleKey: "child_go_to_permission", kind: .ask))
    }

    @Test("정확한 위치·백그라운드 새로고침은 설정으로 보낸다 — 물을 API 가 없다")
    func 설정으로() {
        var s = 정상
        s.accuracy = .reducedAccuracy
        #expect(모델(s).action == .init(titleKey: "ios_child_open_settings", kind: .settings))
        s = 정상
        s.backgroundRefresh = .denied
        #expect(모델(s).action == .init(titleKey: "ios_child_open_settings", kind: .settings))
    }

    @Test("가족에서 빠진 것이 권한보다 먼저다 — 권한을 다 켜도 아무 데도 안 간다 (:49-51)")
    func 가족이_먼저() {
        var s = 정상
        s.authorization = .denied
        let m = 모델(s, 멤버: false)
        #expect(m.state == .familyGone)
        #expect(m.titleKey == "child_home_title_gone")
        #expect(m.bodyKey == "child_family_gone")
        #expect(m.action == .init(titleKey: "child_repair", kind: .repair))
    }

    @Test("모르면(nil) 아무 말도 바꾸지 않는다 — 확실하지 않은 것으로 겁주지 않는다 (:146-147)")
    func 모르면_그대로() {
        #expect(모델(정상, 멤버: nil).state == .sharing)
        var s = 정상
        s.authorization = .denied
        #expect(모델(s, 멤버: nil).state == .permissionMissing(.location))
    }

    @Test("저전력 모드는 다른 문장과 **함께** 보인다. 고장이 아니라 주의사항이다 (§8.3)")
    func 저전력_한_줄() {
        #expect(모델(정상, 저전력: false).lowPowerNoticeKey == nil)
        #expect(모델(정상, 저전력: true).lowPowerNoticeKey == "ios_child_low_power_notice")
        var s = 정상
        s.accuracy = .reducedAccuracy
        let m = 모델(s, 저전력: true)
        #expect(m.state == .permissionMissing(.precise))
        #expect(m.lowPowerNoticeKey == "ios_child_low_power_notice", "고장과 함께 보여야 한다")
    }

    @Test("강제 종료 안내는 **늘** 있다 — 정상일 때도. 고장일 때만 두면 정작 그 아이는 못 본다 (§5.3·판정 기록 9)")
    func 강제_종료_안내() {
        #expect(모델(정상).forceQuitNoticeKey == "ios_child_force_quit_notice")
        var s = 정상
        s.authorization = .denied
        #expect(모델(s).forceQuitNoticeKey == "ios_child_force_quit_notice")
        #expect(모델(정상, 멤버: false).forceQuitNoticeKey == "ios_child_force_quit_notice")
    }

    @Test("권한 넷의 순서가 화면에서도 그대로다")
    func 순서() {
        var s = ChildPermissions.Snapshot(
            authorization: .notDetermined, accuracy: .reducedAccuracy, backgroundRefresh: .denied)
        #expect(모델(s).state == .permissionMissing(.location))
        s.authorization = .authorizedWhenInUse
        #expect(모델(s).state == .permissionMissing(.always))
        s.authorization = .authorizedAlways
        #expect(모델(s).state == .permissionMissing(.precise))
        s.accuracy = .fullAccuracy
        #expect(모델(s).state == .permissionMissing(.backgroundRefresh))
        s.backgroundRefresh = .available
        #expect(모델(s).state == .sharing)
    }
}
