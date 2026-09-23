import CoreLocation
import Foundation
import Observation
import UIKit

/// 아이 화면이 **무엇을 말할지** 정한다. 그림은 `ChildHomeView` 가 그린다.
/// 정본 `child/ChildHomeActivity.kt:70-82`(`onResume` 의 세 갈래)와 `:49-51`(순서의 근거).
///
/// **한 번에 하나만 말한다.** 순서는 "이걸 고쳐야 다음이 의미가 있는가"다 — 가족에서 빠졌으면
/// 권한을 다 켜도 아무 데도 안 가고, 위치 권한이 없으면 '항상 허용'을 물을 수조차 없다.
/// 그래서 **공유가 안 되는 이유가 하나라도 있으면 "공유 중"이라고 말하지 않는다** — 이 앱이
/// 제일 두려워하는 거짓말이 그것이다(`core/FamilyRepository.kt:408-411` 의 같은 기준).
///
/// 안드로이드의 Play 서비스 갈래(`:125-136`)는 **안 옮긴다.** 아이폰에 대응하는 재료가 없고,
/// 그 자리의 "조용한 고장"은 아이폰에서는 정확한 위치 끄기다(설계서 §8.2) — 이미 권한 넷 안에 있다.
@MainActor
@Observable
final class ChildHomeModel {

    enum State: Equatable {
        /// **아직 아무것도 모른다.** `apply` 를 한 번도 못 받은 화면이다 — 세션이 뜨는 동안의
        /// 짧은 순간이고, 세션이 아예 못 뜨면 여기서 더 나아가지 않는다. 예전 초기값은
        /// `.sharing` 이었는데, 그러면 수집이 하나도 없는 폰이 "엄마 아빠가 볼 수 있어요"라고
        /// 말한다 — 이 앱이 제일 두려워하는 거짓말이 정확히 그것이다(통합 검토 I3).
        case starting
        case sharing
        case permissionMissing(ChildPermissions.Item)
        case familyGone
        /// 세션을 못 띄웠다(로그인 실패 등). 화면이 그 사실을 말하고 다시 해 볼 버튼을 준다.
        case cannotStart
    }

    struct Action: Equatable {
        enum Kind { case ask, settings, repair, retry }
        let titleKey: String.LocalizationValue
        let kind: Kind
    }

    private(set) var state: State = .starting
    /// 저전력 모드 한 줄. **다른 문장과 함께** 보인다 — 고장이 아니라 주의사항이라서다(§8.3).
    /// 이벤트를 만들지 않는 이유도 같다: 아이가 언제든 껐다 켜는 설정이라 알리면 소음이 된다
    /// (`ConditionWatcher.kt:43-46` 이 `BATTERY_UNRESTRICTED` 를 감시에서 뺀 것과 같은 판단).
    private(set) var lowPowerNoticeKey: String.LocalizationValue?

    /// 강제 종료 안내는 **늘** 있다. 고장일 때만 보여주면 정작 강제 종료한 아이는 그 화면을
    /// 못 본다 — 앱이 없으니까(3단계 판정 기록 9, 설계서 §5.3·§15-2).
    let forceQuitNoticeKey: String.LocalizationValue = "ios_child_force_quit_notice"

    var titleKey: String.LocalizationValue {
        state == .familyGone ? "child_home_title_gone" : "child_home_title"
    }

    var bodyKey: String.LocalizationValue {
        switch state {
        case .starting: "ios_child_starting"
        case .sharing: "child_sharing_on"
        case .permissionMissing: "child_permission_missing"
        case .familyGone: "child_family_gone"
        case .cannotStart: "ios_child_cannot_start"
        }
    }

    /// `child_permission_missing` 의 `%1$s` 자리(권한 이름). 나머지 상태에는 인자가 없다.
    var bodyArgument: String? {
        if case .permissionMissing(let item) = state { return item.이름 }
        return nil
    }

    var reasonKey: String.LocalizationValue? {
        if case .permissionMissing(let item) = state { return item.reasonKey }
        return nil
    }

    private(set) var action: Action?

    /// `stillMember` 가 `nil` 이면 **아무 말도 바꾸지 않는다**(`:146-147` — "확실하지 않은 것으로
    /// 화면을 겁주지 않는다"). 오프라인에서 읽기가 캐시로 대답한 "없음"이 정확히 그 자리다.
    func apply(permissions: ChildPermissions.Snapshot, stillMember: Bool?, lowPower: Bool) {
        lowPowerNoticeKey = lowPower ? "ios_child_low_power_notice" : nil

        if stillMember == false {
            state = .familyGone
            // 이 버튼은 서버가 "이 기기는 이 가족의 멤버가 아니다"라고 확답했을 때에만 뜬다
            // (`:168-173`). 그 시점에는 눌러서 풀 감시가 남아 있지 않다.
            action = Action(titleKey: "child_repair", kind: .repair)
            return
        }
        guard let missing = ChildPermissions.firstMissing(permissions) else {
            state = .sharing
            action = nil
            return
        }
        state = .permissionMissing(missing)
        action = switch ChildPermissions.fix(for: missing, in: permissions) {
        case .ask: Action(titleKey: "child_go_to_permission", kind: .ask)
        case .settings: Action(titleKey: "ios_child_open_settings", kind: .settings)
        }
    }

    /// 세션이 아예 못 떴다(`ChildSession.build` 의 로그인 실패 갈래). 예전에는 그 자리가
    /// "화면은 아무 말도 바꾸지 않는다"였는데, 초기값이 `.sharing` 이라 **아무 말도 안 바꾸는
    /// 것이 곧 거짓말**이었다(통합 검토 I3). 권한 스냅샷을 읽을 수집기조차 없는 상태라
    /// `apply` 를 쓸 수 없어 따로 둔다.
    func cannotStart() {
        state = .cannotStart
        action = Action(titleKey: "ios_child_retry", kind: .retry)
    }

    /// 다시 해 보는 중. 버튼을 거두고 "준비 중"으로 되돌린다 — 결과는 세션이 뜬 뒤
    /// `apply` 가, 또 실패하면 `cannotStart` 가 말한다.
    func starting() {
        state = .starting
        action = nil
    }
}
