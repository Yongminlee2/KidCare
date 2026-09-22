import CoreLocation
import Testing
import UIKit
@testable import KidCare

/// 감시하는 권한 넷과 **그 순서**를 고정한다. 순서는 "이걸 고쳐야 다음이 의미 있는가"이고
/// 정본은 `onboarding/PermissionStep.kt:18-89` 다(그쪽 여섯 중 넷, 설계서 §8.6).
struct ChildPermissionsTests {

    /// 전부 정상인 조합 하나 — 여기서 nil 이 안 나오면 아래 갈래들이 전부 의미가 없다.
    private let 정상 = ChildPermissions.Snapshot(
        authorization: .authorizedAlways, accuracy: .fullAccuracy, backgroundRefresh: .available)

    @Test("다 켜져 있으면 빠진 것이 없다")
    func 정상이면_없다() {
        #expect(ChildPermissions.firstMissing(정상) == nil)
    }

    @Test("위치 권한 자체가 먼저다 — 없으면 나머지를 물을 수조차 없다 (§8.1)")
    func 위치가_먼저() {
        for status in [CLAuthorizationStatus.notDetermined, .denied, .restricted] {
            var s = 정상
            s.authorization = status
            // 정확한 위치도 새로고침도 같이 꺼 둔다. 그래도 **위치 권한이 이긴다**.
            s.accuracy = .reducedAccuracy
            s.backgroundRefresh = .denied
            #expect(ChildPermissions.firstMissing(s) == .location, "\(status)")
        }
    }

    @Test("'앱 사용 중만'은 항상 허용이 빠진 것이다 — 화면을 벗어나면 하루가 조용해진다 (§8.1)")
    func 앱_사용_중만() {
        var s = 정상
        s.authorization = .authorizedWhenInUse
        #expect(ChildPermissions.firstMissing(s) == .always)
    }

    @Test("정확한 위치가 꺼지면 점이 하나도 안 쌓인다 — 가장 조용한 고장 (§8.2)")
    func 정확한_위치() {
        var s = 정상
        s.accuracy = .reducedAccuracy
        #expect(ChildPermissions.firstMissing(s) == .precise)
    }

    @Test("백그라운드 앱 새로고침이 꺼지면 앱을 볼 때만 점이 온다 (§8.4·§17-4)")
    func 새로고침() {
        var s = 정상
        s.backgroundRefresh = .denied
        #expect(ChildPermissions.firstMissing(s) == .backgroundRefresh)
        s.backgroundRefresh = .restricted
        #expect(ChildPermissions.firstMissing(s) == .backgroundRefresh)
    }

    @Test("여럿이 꺼져 있으면 고치는 순서대로 앞의 것 하나만 준다")
    func 순서() {
        var s = 정상
        s.authorization = .authorizedWhenInUse
        s.accuracy = .reducedAccuracy
        s.backgroundRefresh = .denied
        #expect(ChildPermissions.firstMissing(s) == .always)
    }

    @Test("꺼진 것 전부의 이름 집합 — ConditionWatcher 가 이 집합의 증가를 전환으로 읽는다")
    func 꺼진_전부() {
        var s = 정상
        s.authorization = .authorizedWhenInUse
        s.backgroundRefresh = .denied
        #expect(ChildPermissions.allMissing(s) == [.always, .backgroundRefresh])
        #expect(ChildPermissions.allMissing(정상).isEmpty)
    }

    @Test("항목마다 제목·이유 키가 있고, 위치 권한만 기존 14개 언어 키를 쓴다 (§8.5)")
    func 문구_키() {
        #expect(ChildPermissions.Item.location.titleKey == "perm_location_title")
        #expect(ChildPermissions.Item.location.reasonKey == "perm_location_reason")
        #expect(ChildPermissions.Item.always.titleKey == "ios_child_perm_always_title")
        #expect(ChildPermissions.Item.precise.titleKey == "ios_child_perm_precise_title")
        #expect(ChildPermissions.Item.backgroundRefresh.titleKey == "ios_child_perm_refresh_title")
        for item in ChildPermissions.Item.allCases {
            // `String.LocalizationValue` 에는 `isEmpty` 가 없다 — 빈 리터럴과 견준다(브리프에서 바꾼 한 줄).
            #expect(item.reasonKey != "")
        }
    }

    @Test("대화상자로 고칠 수 있는 것과 설정으로 보내야 하는 것이 갈린다 (판정 기록 15)")
    func 고치는_방법() {
        var s = 정상
        s.authorization = .notDetermined
        #expect(ChildPermissions.fix(for: .location, in: s) == .ask)
        s.authorization = .authorizedWhenInUse
        #expect(ChildPermissions.fix(for: .always, in: s) == .ask)
        s.authorization = .denied
        #expect(ChildPermissions.fix(for: .location, in: s) == .settings)
        // 정확한 위치와 새로고침은 물을 API 자체가 없다(§8.2 — 임시 정확도는 안 쓴다).
        #expect(ChildPermissions.fix(for: .precise, in: 정상) == .settings)
        #expect(ChildPermissions.fix(for: .backgroundRefresh, in: 정상) == .settings)
    }
}
