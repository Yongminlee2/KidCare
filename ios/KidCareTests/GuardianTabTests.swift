import Testing
@testable import KidCare

/// 정본은 `res/menu/guardian_bottom_nav.xml:32-55` 와 `GuardianMainActivity.kt:93-99`.
@MainActor
struct GuardianTabTests {

    @Test("탭 다섯은 안드로이드와 같은 순서·같은 문구 키다")
    func 순서와_문구() {
        #expect(GuardianTab.allCases.map(\.titleKey) == ["tab_map", "tab_alert", "tab_control", "tab_schedule", "tab_place"])
    }

    @Test("문구 키가 카탈로그에 있어 키 이름이 그대로 보이지 않는다")
    func 문구가_번역된다() {
        for tab in GuardianTab.allCases {
            #expect(tab.title != tab.titleKey, "\(tab.titleKey) 가 카탈로그에 없다")
        }
    }

    @Test("저장되는 값(rawValue)은 바뀌지 않는다 — @SceneStorage 가 이 문자열로 복원한다")
    func 저장값() {
        #expect(GuardianTab.allCases.map(\.rawValue) == ["map", "alert", "control", "schedule", "place"])
    }
}
