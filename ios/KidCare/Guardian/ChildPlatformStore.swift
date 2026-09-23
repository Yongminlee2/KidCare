import Foundation

/// "이 아이는 아이폰이더라"를 아이 uid 별로 기억한다. 정본이 따로 없는 아이폰 전용
/// 저장소이고, 모양은 `RuleSyncStore.swift:12-40` 을 그대로 베꼈다.
///
/// **왜 기억이 필요한가 — 읽기 예산 때문이다.** 아이 상태 문서를 이미 읽는 탭이 셋이고
/// (지도·관리·장소) 예약 탭만 안 읽는다. 예약 탭에 읽기를 하나 더 달면 가족당 하루 50
/// 읽기 예산(`known-issues.md` 12번)에서 사는 것인데, 이 단계의 목적이 비용을 안 나쁘게
/// 하는 것이다(설계서 §11.2). 그래서 읽는 셋이 기억시키고 예약 탭은 기억을 본다.
///
/// **못 맞혀도 대가가 없다.** 기억이 없으면 `.unknown` 이고 `.unknown` 은 아무것도 안
/// 잠근다 — 지금 동작 그대로다(판정 기록 3).
///
/// 뷰모델이 아니라 저장소인 이유는 `RuleSyncStore.swift:9-10` 과 같다. 앱이 꺼져도 남아야
/// 두 번째 실행부터는 예약 탭이 처음부터 옳다.
struct ChildPlatformStore {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func platform(childUid: String) -> ChildPlatform {
        switch defaults.string(forKey: key(childUid)) {
        case "ios": return .iOS
        case .some: return .android
        case nil: return .unknown
        }
    }

    /// **`.unknown` 은 기억을 지우지 않는다.** 네트워크가 잠깐 끊겨 상태 문서를 못 읽은
    /// 것이지, 아이 폰이 안드로이드가 된 것이 아니다. 여기서 지우면 그 순간 예약 탭이
    /// 잠금을 놓친다.
    func remember(childUid: String, platform: ChildPlatform) {
        switch platform {
        case .iOS: defaults.set("ios", forKey: key(childUid))
        case .android: defaults.set("android", forKey: key(childUid))
        case .unknown: return
        }
    }

    /// 상태 문서를 읽은 곳이 그대로 넘기는 길. 문서가 `nil` 이면 아무것도 안 한다.
    func remember(childUid: String, status: ChildStatusDoc?) {
        remember(childUid: childUid, platform: ChildPlatform.of(status: status))
    }

    /// `RoleStore`·`RequestLog`·`AlarmMemoStore`·`RuleSyncStore` 와 저장소 하나를 같이 쓰므로
    /// 종류를 앞에 붙인다(`RuleSyncStore.swift:38-40` 의 같은 이유).
    private func key(_ childUid: String) -> String {
        "child_platform_\(childUid)"
    }
}
