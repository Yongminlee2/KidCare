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
        case sharing
        case permissionMissing(ChildPermissions.Item)
        case familyGone
    }

    struct Action: Equatable {
        enum Kind { case ask, settings, repair }
        let titleKey: String.LocalizationValue
        let kind: Kind
    }

    private(set) var state: State = .sharing
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
        case .sharing: "child_sharing_on"
        case .permissionMissing: "child_permission_missing"
        case .familyGone: "child_family_gone"
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
}
