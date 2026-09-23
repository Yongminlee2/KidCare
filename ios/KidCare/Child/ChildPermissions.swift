import CoreLocation
import Foundation
import UIKit

/// 아이폰이 요구하는 권한 넷의 상태와 이름. 정본은 `onboarding/PermissionStep.kt` 이고,
/// 그 여섯 중 넷만 옮긴다 — 나머지 둘(`DND_ACCESS`·`NOTIFICATION`)은 아이폰에 **대응이 없다**
/// (설계서 §8.6: 소리 모드를 바꿀 API 가 없고, 아이 폰은 알림을 하나도 안 띄운다).
/// 대신 아이폰에만 있는 둘이 들어온다 — 정확한 위치(§8.2)와 백그라운드 앱 새로고침(§8.4).
///
/// **읽기를 스냅샷으로 갈라 두는 이유.** `CLLocationManager` 와 `UIApplication` 은 테스트에서
/// 만들 수 없다. 판정(어느 상태가 어느 항목을 빠진 것으로 치나)은 순수 함수라 값만 받으면
/// 되고, 그래야 `ChildPermissionsTests` 가 CoreLocation 없이 돈다(설계서 §12.1 의 규율).
enum ChildPermissions {

    /// **순서가 곧 고치는 순서다**(`PermissionStep.kt:13-16` 과 같은 규율). 위치 권한이 없으면
    /// '항상'을 물을 수조차 없고(§8.1 두 걸음), '항상'이 없으면 나머지를 고쳐도 화면을 벗어나는
    /// 순간 하루가 조용해진다.
    enum Item: String, CaseIterable {
        case location
        case always
        case precise
        case backgroundRefresh

        /// 1번은 **이미 14개 언어에 있는 키**를 쓴다(설계서 §8.5 "그대로 쓰는 키").
        var titleKey: String.LocalizationValue {
            switch self {
            case .location: "perm_location_title"
            case .always: "ios_child_perm_always_title"
            case .precise: "ios_child_perm_precise_title"
            case .backgroundRefresh: "ios_child_perm_refresh_title"
            }
        }

        var reasonKey: String.LocalizationValue {
            switch self {
            case .location: "perm_location_reason"
            case .always: "ios_child_perm_always_reason"
            case .precise: "ios_child_perm_precise_reason"
            case .backgroundRefresh: "ios_child_perm_refresh_reason"
            }
        }

        var 이름: String { String(localized: titleKey) }
    }

    /// 지금 이 폰의 값 셋. 화면과 `ConditionWatcher` 가 **같은 스냅샷**을 본다 — 두 곳이
    /// 따로 읽으면 한쪽만 옛 값으로 판단하는 순간이 생긴다.
    struct Snapshot: Equatable {
        var authorization: CLAuthorizationStatus
        var accuracy: CLAccuracyAuthorization
        var backgroundRefresh: UIBackgroundRefreshStatus
    }

    /// 고치는 방법. `.ask` 는 그 자리에서 대화상자를 띄울 수 있다는 뜻이고,
    /// `.settings` 는 **물을 API 가 없어** 설정 앱으로 보내야 한다는 뜻이다.
    enum Fix { case ask, settings }

    /// 아직 안 된 첫 번째. 전부 됐으면 nil. `PermissionStep.firstMissing`(:88-89) 그대로다.
    static func firstMissing(_ s: Snapshot) -> Item? { allMissing(s).first }

    /// 지금 꺼져 있는 것 **전부**. `ConditionWatcher` 가 이 집합의 **증가**를 전환으로 읽는다
    /// (`ConditionWatcher.kt:114-117`: 집합이 늘어난 순간이 곧 전환이다).
    static func allMissing(_ s: Snapshot) -> [Item] {
        Item.allCases.filter { !isGranted($0, s) }
    }

    /// 아직 **묻지도 않았다**. 화면은 이 동안에도 `firstMissing` 으로 `.location` 을 말해야 하지만
    /// (그게 곧 '허용' 버튼이다), 부모에게 보내는 경고는 이 동안 **한 마디도 나가면 안 된다** —
    /// 한 번도 켠 적 없는 것을 "다시 켜주세요"라고 말하는 셈이기 때문이다(통합 검토 I1).
    /// CoreLocation 을 아는 자리를 이 파일 하나로 묶으려고 여기에 둔다(`ConditionWatcher` 는
    /// `import CoreLocation` 없이 돈다).
    static func notYetAsked(_ s: Snapshot) -> Bool { s.authorization == .notDetermined }

    static func isGranted(_ item: Item, _ s: Snapshot) -> Bool {
        switch item {
        case .location:
            return s.authorization == .authorizedAlways || s.authorization == .authorizedWhenInUse
        case .always:
            // '앱 사용 중만'이 안드로이드 `LOCATION_BACKGROUND` 와 정확히 같은 자리다 —
            // 화면상으로는 위치 권한이 여전히 허용이라 아무도 모른다(`ConditionWatcher.kt:32-34`).
            return s.authorization == .authorizedAlways
        case .precise:
            // 오차 1~3km 로 들어와 완화 문턱(100m)도 못 넘는다. 점이 하나도 안 쌓이는데
            // 앱은 멀쩡히 돌고 파란 표시도 켜져 있다(§8.2).
            return s.accuracy == .fullAccuracy
        case .backgroundRefresh:
            // 애플 문서가 얇은 자리다. 확인 전까지 **고장으로 취급**한다(§17 열린 질문 4) —
            // 침묵을 침묵으로 두는 것보다 한 번 더 말하는 쪽이 이 앱의 규율이다.
            return s.backgroundRefresh == .available
        }
    }

    /// 앞의 것이 아직 안 됐으면 뒤의 것은 **판단하지 않는다**. `.location` 이 `.notDetermined`
    /// 인 동안 `.always` 를 "빠졌다"고 부르는 것은 맞지만 고칠 방법이 아직 없기 때문에,
    /// 화면은 늘 `firstMissing` 하나만 말한다(3단계 판정 기록 10).
    static func fix(for item: Item, in s: Snapshot) -> Fix {
        switch item {
        case .location:
            // 한 번 거부되면 앱이 다시 못 묻는다 — 설정으로 보낸다.
            return s.authorization == .notDetermined ? .ask : .settings
        case .always:
            // 두 걸음의 두 번째(§8.1). iOS 가 대화상자를 바로 안 띄울 수 있지만, 부르는 것이
            // 맞다 — 그 뒤 앱이 백그라운드에서 위치를 쓰면 iOS 가 스스로 묻는다.
            return s.authorization == .authorizedWhenInUse ? .ask : .settings
        case .precise:
            // `requestTemporaryFullAccuracyAuthorization` 을 **쓰지 않는다**(§8.2) —
            // 한 세션만 살아서 다음에 또 같은 침묵이 온다.
            return .settings
        case .backgroundRefresh:
            // 물을 API 가 아예 없다.
            return .settings
        }
    }

    /// 진짜 값을 읽는 자리. `@MainActor` 인 이유는 `UIApplication.shared` 다.
    /// `CLLocationManager` 를 여기서 만들지 **않고 받는다** — 매니저는 앱이 사는 동안 하나여야
    /// 하고(설계서 §5.2), 그 하나는 `LocationCollector` 가 들고 있다.
    @MainActor
    static func snapshot(manager: CLLocationManager) -> Snapshot {
        Snapshot(authorization: manager.authorizationStatus,
                 accuracy: manager.accuracyAuthorization,
                 backgroundRefresh: UIApplication.shared.backgroundRefreshStatus)
    }
}
