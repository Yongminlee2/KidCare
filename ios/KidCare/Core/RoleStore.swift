import Foundation
import Observation

/// 이 기기가 무엇인지(역할), 어느 가족인지, 어느 아이를 보고 있는지를 기억한다.
///
/// `UserDefaults` 를 주입받는 이유는 테스트 때문만이 아니다 — 기본 저장소를 쓰면
/// 테스트가 시뮬레이터에 남긴 값이 다음 실행의 앱 상태가 된다.
@Observable
final class RoleStore {

    @MainActor static let shared = RoleStore(defaults: .standard)

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        role = defaults.string(forKey: "role").flatMap(MemberRole.init(rawValue:))
        familyId = defaults.string(forKey: "familyId")
        childUid = defaults.string(forKey: "childUid")
    }

    // **저장 프로퍼티여야 한다.** UserDefaults 를 그때그때 읽는 계산 프로퍼티로 두면
    // @Observable 이 변경을 추적하지 못해서, 합류가 끝나도 RouterView 가 다시 그려지지
    // 않는다 — 화면이 역할 선택에 머문 채로 아무 일도 안 일어난 것처럼 보인다.
    // 값은 읽을 때 한 번 싣고, 쓸 때마다 UserDefaults 로 흘려보낸다.
    var role: MemberRole? { didSet { defaults.set(role?.rawValue, forKey: "role") } }
    var familyId: String? { didSet { defaults.set(familyId, forKey: "familyId") } }
    var childUid: String? { didSet { defaults.set(childUid, forKey: "childUid") } }

    func clear() {
        role = nil
        familyId = nil
        childUid = nil
        for key in ["role", "familyId", "childUid"] { defaults.removeObject(forKey: key) }
    }
}
