import SwiftUI
import UIKit

/// 아이가 보는 유일한 화면. 정본 배치는 `res/layout/activity_child_home.xml`
/// (언어 버튼 · 마스코트 156 · 제목 · 상태 문장 · 버튼 하나)이고, 색과 버튼 모양은
/// `RoleSelectView` 가 이미 쓰는 `KidCarePalette`·`KidCareFilledButtonStyle` 그대로다.
///
/// **이 뷰는 판단하지 않는다.** 무엇을 말할지는 `ChildHomeModel` 이 정하고 여기는 그리기만
/// 한다 — 권한을 두 곳에서 읽으면 한쪽만 옛 값으로 그리는 순간이 생긴다.
///
/// 버튼은 **하나**다. `action == nil`(공유 중)이면 아예 안 그린다 — 누를 것이 없는 자리에
/// 버튼을 두면 눌러도 아무 일이 없어 그게 더 나쁘다(`ChildHomeActivity.kt:121-123` 의 같은 판단).
///
/// **세 가지 일은 이 뷰가 하지 않고 위로 넘긴다**(`onRefresh`·`onAsk`·`onRepair`).
/// 권한을 읽는 `CLLocationManager` 는 앱이 사는 동안 하나여야 하고(설계서 §5.2) 그 하나는
/// `LocationCollector` 가 들고 있다. 3단계 Task 3 의 `ChildSession` 이 그 셋을 잇는다 —
/// 지금은 주인이 없어 화면이 앱에 안 붙어 있는 것이 정상이다(Pre-flight 표).
struct ChildHomeView: View {

    let model: ChildHomeModel
    /// 화면이 다시 보일 때마다 권한을 **다시 읽어** 모델에 넣어 달라는 부탁. 안드로이드가
    /// `onResume` 에서 매번 다시 판단하는 자리다(`:70-82`) — 아이가 설정 앱에 다녀오면
    /// 그때 값이 바뀌어 있다.
    var onRefresh: () -> Void = {}
    /// 두 걸음짜리 위치 권한 요청(`LocationCollector.requestAuthorization()`, 판정 기록 15).
    /// 두 걸음을 화면이 다시 적지 않는다.
    var onAsk: () -> Void = {}
    /// `RoleStore.clear()` + 세션 정지. 서버가 "이 가족의 멤버가 아니다"라고 확답했을 때만 뜬다.
    var onRepair: () -> Void = {}
    /// 세션이 못 떴을 때의 '다시 해보기'. **프로세스 안에 다시 뜰 길이 이것 하나다** —
    /// `startIfChild` 를 부르는 두 문(앱이 뜰 때·아이로 막 페어링한 순간)은 이미 지나갔고,
    /// 역할이 저장돼 있으면 `RouterView` 는 둘째 문이 있는 화면을 아예 안 그린다(통합 검토 I3).
    var onRetry: () -> Void = {}

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                언어_버튼

                카드

                // 저전력 한 줄과 강제 종료 한 줄은 본문 **아래** 작은 글씨다. 둘 다 고장 문구가
                // 아니라 안내라 카드 밖에 둔다 — 그리고 강제 종료 줄은 늘 있다(판정 기록 9).
                if let 저전력 = model.lowPowerNoticeKey {
                    안내_줄(저전력)
                }
                안내_줄(model.forceQuitNoticeKey)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
        }
        .background(KidCarePalette.paper.ignoresSafeArea())
        .onAppear(perform: onRefresh)
        .onChange(of: scenePhase) { _, phase in
            // 설정 앱에서 권한을 바꾸고 돌아오는 길이 이 한 줄이다.
            if phase == .active { onRefresh() }
        }
    }

    /// 아이 폰도 부모 폰과 따로 언어를 고를 수 있어야 한다 — 둘이 같은 나라 말을 쓴다는 보장이
    /// 없다(XML 주석). 안드로이드는 앱 안 대화상자를 열지만 iOS 는 설정 → 앱 → 언어 칸이 늘
    /// 있으므로 그 페이지를 연다(`ChildSelectorBar` 와 같은 판단).
    private var 언어_버튼: some View {
        HStack {
            Spacer()
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Image(systemName: "globe")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 21, height: 21)
                    .foregroundStyle(KidCarePalette.inkSoft)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("language_picker_title"))
        }
        .padding(.bottom, 44)
    }

    private var 카드: some View {
        VStack(spacing: 0) {
            Image("Mascot3D")
                .resizable()
                .scaledToFit()
                .frame(width: 156, height: 156)
                .accessibilityHidden(true)

            // HeadlineSmall 24, 위 여백 18.
            Text(String(localized: model.titleKey))
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(KidCarePalette.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 18)

            // BodyMedium 15, colorOnSurfaceVariant. 한 번에 **하나**의 문장이다.
            Text(본문)
                .font(.system(size: 15))
                .lineSpacing(5)
                .foregroundStyle(KidCarePalette.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            // 왜 필요한지. 권한이 빠졌을 때만 있다 — 이름만으로는 아이가 무엇을 잃고 있는지 모른다.
            if let 이유 = model.reasonKey {
                Text(String(localized: 이유))
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .foregroundStyle(KidCarePalette.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }

            if let action = model.action {
                Button(String(localized: action.titleKey)) { 누름(action) }
                    .buttonStyle(KidCareFilledButtonStyle(minHeight: 58))
                    .padding(.top, 22)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(KidCarePalette.paperCard, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(KidCarePalette.lineSoft, lineWidth: 1))
    }

    /// `child_permission_missing` 만 `%1$s` 자리에 권한 이름이 든다(`AlertText` 와 같은 모양).
    private var 본문: String {
        let 틀 = String(localized: model.bodyKey)
        guard let 이름 = model.bodyArgument else { return 틀 }
        return String(format: 틀, 이름)
    }

    private func 안내_줄(_ key: String.LocalizationValue) -> some View {
        Text(String(localized: key))
            .font(.system(size: 13))
            .lineSpacing(4)
            .foregroundStyle(KidCarePalette.inkSoft)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
    }

    private func 누름(_ action: ChildHomeModel.Action) {
        switch action.kind {
        case .ask:
            onAsk()
        case .settings:
            // 정확한 위치·백그라운드 새로고침·한 번 거부된 위치 권한은 물을 API 가 없다(§8.2·§8.4).
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        case .repair:
            onRepair()
        case .retry:
            onRetry()
        }
    }
}
