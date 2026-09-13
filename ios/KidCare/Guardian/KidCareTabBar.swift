import SwiftUI

/// 보호자 하단 탭 띠. 정본은 `activity_guardian_main.xml:90-104` + `themes.xml:186-195`(`Widget.KidCare.BottomNav`).
///
/// **시스템 탭 막대를 쓰지 않는 이유:** iOS 26 의 `TabView` 는 탭 막대를 화면 가장자리에서 떨어진 떠 있는 유리
/// 캡슐로 그린다. 안드로이드는 화면 폭을 꽉 채운 붙박이 띠에 위쪽 1dp 선이다 — 같은 가족의 두 폰이 다른 앱처럼 보인다.
/// 그래서 `TabView` 는 탭 상태·수명(뷰모델 유지, 탭마다의 `onAppear`/`onDisappear`)만 맡기고 막대는 숨긴 뒤
/// (`GuardianRootView`), 이 띠를 그 아래에 둔다.
///
/// 치수는 Material 1.14.0 `Widget.Material3.BottomNavigationView` 기본값:
/// 최소 높이 80(`m3_bottom_nav_min_height`), 그림 24(`m3_comp_nav_bar_item_icon_size`), 위 여백 12
/// (`m3_bottom_nav_item_padding_top`), 선택 알약 64×34 sky_soft(themes.xml:193-194), 알약과 이름 사이 4
/// (`m3_navigation_item_active_indicator_label_padding`), 이름 LabelMedium 13 medium. 색은
/// `color/bottom_nav_item.xml` — 선택 sky, 나머지 ink_soft. 이름은 늘 보인다(`labelVisibilityMode="labeled"`).
struct KidCareTabBar: View {

    @Binding var selection: GuardianTab

    var body: some View {
        VStack(spacing: 0) {
            // 그림자 대신 선으로 띠를 바탕에서 뗀다(activity_guardian_main.xml:90-96, colorOutlineVariant).
            Rectangle()
                .fill(KidCarePalette.lineSoft)
                .frame(height: 1)
            HStack(spacing: 0) {
                ForEach(GuardianTab.allCases) { tab in
                    칸(tab)
                }
            }
            .frame(height: 80)
        }
        // 홈 인디케이터 자리까지 띠 바탕을 칠한다(안드로이드 navigationBarColor = paper_card, themes.xml:67).
        .background(KidCarePalette.paperCard.ignoresSafeArea(edges: .bottom))
    }

    private func 칸(_ tab: GuardianTab) -> some View {
        let 선택됨 = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Capsule()
                        .fill(선택됨 ? KidCarePalette.skySoft : Color.clear)
                        .frame(width: 64, height: 34)
                    // 선 그림 그대로 둔다 — 시스템 탭 막대는 선택 칸을 `.fill` 로 바꿔 '예약'의 시계가 까만 원판이 됐다.
                    // 안드로이드 `ic_tab_*` 는 선택 여부와 무관하게 같은 그림에 색만 바뀐다.
                    Image(systemName: tab.systemImage)
                        .symbolVariant(.none)
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                Text(verbatim: tab.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            // 그림 위 여백 12 에서 알약(그림보다 위아래로 5 크다)만큼 뺀다.
            .padding(.top, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .foregroundStyle(선택됨 ? KidCarePalette.sky : KidCarePalette.inkSoft)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: tab.title))
        .accessibilityAddTraits(선택됨 ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("tab_\(tab.rawValue)")
    }
}
