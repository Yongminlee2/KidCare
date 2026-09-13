import SwiftUI
import UIKit

/// 선택기 줄. 정본은 `activity_guardian_main.xml:17-62` — 선택기 한 칸과 지구본 버튼.
struct ChildSelectorBar: View {
    let model: ChildSelectorModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 6) {
            ChildMenu(model: model) {
                Text(model.줄_문구)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(KidCarePalette.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(KidCarePalette.skySoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(KidCarePalette.lineSoft, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            // 안드로이드는 앱 안 언어 대화상자를 연다. iOS 는 설정 → 앱 → 언어 칸이 늘 있으므로 그 페이지를 연다(판정 기록 9).
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Image(systemName: "globe")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(KidCarePalette.inkSoft)
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel(Text("language_picker_title"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(KidCarePalette.paper)
    }
}

/// 선택 팝업. 정본은 `showChildMenu`(:243-269) — 아이들(지금 아이에 체크) 뒤에 '＋ 아이 추가', '＋ 보호자 초대 · 현재 N명'.
/// 선택기 줄과 지도 카드가 같은 메뉴를 쓴다(`showChildMenuFrom`, :239-241).
struct ChildMenu<Content: View>: View {
    let model: ChildSelectorModel
    @ViewBuilder let content: () -> Content
    /// 본 화면이 넘겨준 빼기 뷰모델. 미리보기처럼 없는 곳에서는 줄을 그리지 않는다.
    @Environment(LeaveFamilyModel.self) private var leave: LeaveFamilyModel?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Menu {
            ForEach(model.children, id: \.uid) { child in
                Button { model.고른다(child.uid) } label: {
                    if child.uid == model.selectedUid {
                        Label(model.라벨(child), systemImage: "checkmark")
                    } else {
                        Text(model.라벨(child))
                    }
                }
            }
            // 실기기 읽기 전용 확인에서는 진짜 가족에 초대 코드를 만들지 않는다(판정 기록 10). 흐리게 하는 것은 표시용이고,
            // 실제 차단은 `ChildSelectorModel.초대한다` 의 가드다(통합 검토 I3).
            Button("child_selector_add_child") { model.초대한다(.child) }
                .disabled(model.읽기_전용)
            Button(model.보호자_초대_문구) { model.초대한다(.guardian) }
                .disabled(model.읽기_전용)
            // App Store 가이드라인 5.1.1 — 처리방침 링크와 계정 삭제는 앱 안에서 닿아야 한다(7단계 판정 기록 8·9).
            // 안드로이드 메뉴에는 없는 줄이다. 선택기 줄과 지도 카드가 이 메뉴를 함께 쓰므로 모든 탭에서 닿는다.
            if PrivacyPolicyLink.url() != nil || leave != nil {
                Divider()
            }
            // 주소가 비어 있는 동안(주인이 게시하기 전)은 줄 자체가 없다 — 지어낸 주소로 보내지 않는다.
            if let url = PrivacyPolicyLink.url() {
                Button { openURL(url) } label: { Text("ios_privacy_policy") }
            }
            if let leave {
                // 실기기 읽기 전용 확인에서는 누를 수 없다(6단계 판정 기록 10 과 같은 자리). 흐리게 하는 것은 표시용이고,
                // 실제 차단은 `LeaveFamilyModel.묻는다`·`뺀다` 의 가드다.
                Button(role: .destructive) { leave.묻는다() } label: { Text("leave_family_menu") }
                    .disabled(leave.읽기_전용)
            }
        } label: {
            content()
        }
    }
}
