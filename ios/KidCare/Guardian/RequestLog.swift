import Foundation

/// "언제 물어봤고 언제 대답을 받았나"를 부모 폰에 남긴다. 정본은 안드로이드
/// `guardian/RequestLog.kt`.
///
/// 무응답 배너(`DisconnectRule`)의 판정 재료다. 판정 자체는 `DisconnectRule` 이
/// 하고, 이 타입은 값을 들고만 있는다.
///
/// ## 왜 부모 폰 안에 두나
///
/// 서버에 두면 그 자체가 쓰기·읽기라 무료 한도를 갉아먹는다 — 이 작업이 없애려던
/// 비용을 판정 재료가 되살리는 셈이다. 그리고 이 값은 **이 부모 폰이 무엇을
/// 물었나** 라는 이 기기만의 사실이라 애초에 공유할 이유가 없다.
///
/// ## 왜 기기 시계를 그대로 쓰나
///
/// 두 값을 적는 것도, 읽어서 빼는 것도 전부 이 폰이다. 그래서 폰 시계가 서버와
/// 얼마나 어긋나 있든 **차이는 정확하다.** 여기에 `FamilyRepository.serverNow`
/// 같은 서버 보정 시각을 섞으면 오히려 보정 오차(왕복 절반 추정)가 그대로
/// 오차로 들어온다.
///
/// `recordAnswer` 가 화면 갱신을 겸하지 않는 것에 주의할 것 — 안드로이드는
/// `recordAnswer()` 가 `GuardianMainActivity.refreshBanner()` 도 함께 부르지만,
/// 이 앱은 그 배너 화면 자체가 아직 없다(Phase 4 의 몫) — 여기서는 기록만 한다.
///
/// `UserDefaults` 를 주입받는 이유는 `RoleStore` 와 같다 — 기본 저장소를 쓰면
/// 테스트가 시뮬레이터에 남긴 값이 다음 실행/다른 테스트의 상태가 된다.
struct RequestLog {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 마지막으로 '지금 위치 확인'을 보낸 시각. 0 이면 **한 번도 물어본 적이 없다.**
    func lastRequestAt(childUid: String?) -> Int64 {
        at(Self.requestKey, childUid: childUid)
    }

    /// 마지막으로 아이 폰의 대답을 확인한 시각.
    func lastAnswerAt(childUid: String?) -> Int64 {
        at(Self.answerKey, childUid: childUid)
    }

    func recordRequest(_ childUid: String) {
        record(Self.requestKey, childUid: childUid)
    }

    func recordAnswer(_ childUid: String) {
        record(Self.answerKey, childUid: childUid)
    }

    private func at(_ prefix: String, childUid: String?) -> Int64 {
        guard let childUid else { return 0 }
        return Int64(defaults.integer(forKey: "\(prefix)_\(childUid)"))
    }

    private func record(_ prefix: String, childUid: String) {
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        defaults.set(Int(nowMillis), forKey: "\(prefix)_\(childUid)")
    }

    private static let requestKey = "last_request_at"
    private static let answerKey = "last_answer_at"
}
