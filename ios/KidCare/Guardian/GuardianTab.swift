import Foundation

/// 보호자 하단 탭 다섯. 순서·문구·그림의 정본은 안드로이드 `res/menu/guardian_bottom_nav.xml`
/// (:32-55)과 `GuardianMainActivity.tabs`(:93-99)다. 다섯을 접지 않은 이유(칸 너비)도
/// 그 XML 주석에 있다 — 여기서 순서를 바꾸면 두 폰을 함께 쓰는 부모가 같은 자리에서
/// 다른 탭을 누르게 된다.
///
/// `rawValue` 는 `@SceneStorage` 가 저장하는 값이다. 바꾸면 저장된 선택 탭을 못 읽는다
/// (안드로이드가 탭 태그를 상수로 박아둔 이유와 같다, :74-76).
enum GuardianTab: String, CaseIterable, Identifiable {
    case map, alert, control, schedule, place

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .map: "tab_map"
        case .alert: "tab_alert"
        case .control: "tab_control"
        case .schedule: "tab_schedule"
        case .place: "tab_place"
        }
    }

    var title: String { String(localized: String.LocalizationValue(titleKey)) }

    /// 안드로이드 `ic_tab_*` 그림에 가장 가까운 SF Symbol.
    var systemImage: String {
        switch self {
        case .map: "map"
        case .alert: "bell.badge"
        case .control: "slider.horizontal.3"
        case .schedule: "clock"
        case .place: "mappin.and.ellipse"
        }
    }
}
