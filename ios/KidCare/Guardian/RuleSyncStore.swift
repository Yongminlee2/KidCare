import Foundation

/// "규칙(또는 장소)을 바꿨는데 아직 아이 폰에 `sync_rules` 를 확실히 못 보냈다" 깃발. 정본은 안드로이드
/// `guardian/ScheduleSyncStore.kt`·`PlaceSyncStore.kt`.
///
/// 이 깃발이 없으면 조용히 고장 난다. 자녀 폰이 다음 경계에 깨어나는 유일한 수단은 알람 하나인데,
/// 그걸 다시 걸게 하는 신호가 `sync_rules` 다. 규칙은 저장됐는데 명령만 못 나가면 부모는 정해 뒀다고
/// 믿고, 아이 폰은 옛 규칙(또는 이미 지운 장소의 지오펜스)대로 돈다(ScheduleSyncStore.kt:6-13).
///
/// 뷰모델이 아니라 저장소에 두는 이유는 안드로이드와 같다. 앱이 꺼져도 남아서, 다음에 탭을 열 때
/// 한 번 더 보내야 하기 때문이다(:15-23).
struct RuleSyncStore {

    enum Kind: String {
        /// 안드로이드 prefs 파일 `kidcare_schedule_sync`(ScheduleSyncStore.kt:31).
        case schedule
        /// 안드로이드 prefs 파일 `kidcare_place_sync`(PlaceSyncStore.kt:25). 두 깃발을 합치지 않는
        /// 이유는 그 파일 :12-21.
        case place
    }

    let kind: Kind
    private let defaults: UserDefaults

    init(kind: Kind, defaults: UserDefaults = .standard) {
        self.kind = kind
        self.defaults = defaults
    }

    func pendingSync(childUid: String) -> Bool {
        defaults.bool(forKey: key(childUid))
    }

    func setPendingSync(childUid: String, _ value: Bool) {
        defaults.set(value, forKey: key(childUid))
    }

    /// 안드로이드는 파일이 둘이라 키 `pending_sync_<uid>` 가 겹쳐도 되지만, iOS 는 `RoleStore`·
    /// `RequestLog`·`AlarmMemoStore` 와 같은 저장소 하나를 쓰므로 종류를 앞에 붙인다(판정 기록 7).
    private func key(_ childUid: String) -> String {
        "\(kind.rawValue)_sync_pending_sync_\(childUid)"
    }
}
