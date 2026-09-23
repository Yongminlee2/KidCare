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
    /// 역할이 사라질 때 아이 파이프라인을 멈추는 길(통합 검토 M3). 주입받는 이유는 테스트
    /// 때문만이 아니다 — 이 타입이 `ChildSession` 을 **아는** 것이 아니라 "역할이 사라지면
    /// 무엇을 같이 멈춰야 한다"만 알게 해 둔다.
    private let 수집을_멈춘다: @MainActor () -> Void

    init(defaults: UserDefaults,
         수집을_멈춘다: @escaping @MainActor () -> Void = { ChildSession.shared.stop() }) {
        self.defaults = defaults
        self.수집을_멈춘다 = 수집을_멈춘다
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

    /// 역할을 지우는 **모든 길**이 여기를 지난다 — 아이 화면의 '다시 연결'(`ChildRootView.swift:29`),
    /// 합류 화면의 '역할 다시 고르기'(`InviteCodeView.swift:103`), 가족 떠나기
    /// (`LeaveFamilyModel.swift:210`). 그중 세션을 같이 멈추는 것은 **첫째뿐**이었다(통합 검토 M3).
    /// 역할이 사라진 폰에서 수집기·티커·장소 리스너·OS 지역 스무 개가 조용히 고아가 된다 —
    /// 그 폰은 다시 페어링하지 않으면 영영 그 상태다.
    ///
    /// **짝을 부르는 쪽이 아니라 여기서 짓는다.** 앞으로 역할을 지우는 길이 하나 더 생겨도
    /// (설정 화면·딥링크·서버 주도 해제) 같이 멈춘다. 안 도는 세션에서 `stop()` 은 아무 일도
    /// 안 한다(전부 nil 이다).
    @MainActor
    func clear() {
        role = nil
        familyId = nil
        childUid = nil
        for key in ["role", "familyId", "childUid"] { defaults.removeObject(forKey: key) }
        수집을_멈춘다()
    }
}
