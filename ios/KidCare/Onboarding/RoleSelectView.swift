import SwiftUI

/// 첫 실행 화면. 보호자는 두 갈래(새 가족 / 합류)로 갈린다.
///
/// 아이 버튼을 **지우지 않고 안내로 두는 이유**는 설계서 §1 에 있다 — 지우면
/// 나중에 붙일 자리를 되살려야 하고, 흐리게만 두면 왜 안 되는지를 말해주지 못한다.
struct RoleSelectView: View {

    /// 보호자가 (합류든 새 가족이든) 준비를 끝냈다고 스스로 알려올 때 부른다.
    /// `RouterView` 가 이 신호로만 본 화면으로 넘어간다 — 자세한 이유는
    /// `RouterView` 주석 참고.
    let onGuardianReady: () -> Void

    @State private var 보호자_갈래를_묻는다 = false
    @State private var 아이는_안된다고_알린다 = false
    @State private var 합류로_간다 = false
    @State private var 발급으로_간다 = false

    /// "새 가족 만들기" 한 판을 소유한다. `InviteCodeView` 가 아니라 여기 두는
    /// 이유는 `NewFamilySession` 타입 주석 참고 — 요약하면, `InviteCodeView` 는
    /// `NavigationStack` 의 push 대상이라 SwiftUI 가 그 인스턴스를 다시
    /// 마운트하는 경우가 실측으로 확인됐지만, `RoleSelectView` 자신은 그 문제를
    /// 겪지 않는다(겪는 건 오직 push 된 목적지뿐이었다) — `RouterView` 가 본
    /// 화면으로 넘어갈 때만 사라지는, 이 화면 전체에서 하나뿐인 안정된 자리다.
    @State private var 새_가족_세션: NewFamilySession?

    var body: some View {
        NavigationStack {
            // 정본 `activity_role_select.xml:12-68`: paper 바탕, 가운데 정렬, 안쪽 여백 32.
            VStack(spacing: 0) {
                Image("Mascot3D")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .padding(.bottom, 20)
                    .accessibilityHidden(true)

                // HeadlineSmall 24 medium.
                Text("role_title")
                    .font(.system(size: 24, weight: .medium))
                    .tracking(-0.24)
                    .foregroundStyle(KidCarePalette.ink)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)

                // BodyMedium 15, colorOnSurfaceVariant.
                Text("role_subtitle")
                    .font(.system(size: 15))
                    .lineSpacing(5)
                    .foregroundStyle(KidCarePalette.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 36)

                // 보호자 = 하늘색 채운 버튼, 아이 = 옅은 토널 버튼(XML 머리 주석). 둘 다 폭을 꽉 채운 64,
                // 그림 24 · 글자와 사이 10, TitleMedium 18.
                Button { 보호자_갈래를_묻는다 = true } label: {
                    역할_버튼_글자("role_guardian", 그림: "person.fill.badge.plus")
                }
                .buttonStyle(KidCareFilledButtonStyle(minHeight: 64))
                .padding(.bottom, 12)

                Button { 아이는_안된다고_알린다 = true } label: {
                    역할_버튼_글자("role_child", 그림: "face.smiling")
                }
                .buttonStyle(KidCareTonalButtonStyle(minHeight: 64, fontSize: 18, fullWidth: true))
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KidCarePalette.paper.ignoresSafeArea())
            // 첫 화면에는 제목 막대가 없다(안드로이드 NoActionBar). 밀려 들어간 화면은 뒤로 버튼이 보이게 스스로 켠다.
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("guardian_start_title", isPresented: $보호자_갈래를_묻는다) {
                Button("guardian_start_new_family") {
                    // 세션은 여기, 버튼 액션에서 만든다 — `.navigationDestination`
                    // 의 내용 클로저 안에서 만들면 안 된다. 실측으로 확인했다:
                    // SwiftUI 가 그 클로저를 한 번의 네비게이션에도 여러 번
                    // 불러서(레이아웃/전환 계산 등), `@State` 를 그 안에서 막
                    // 쓰면 매번 nil 을 보고 새 세션을 만드는 것처럼 동작했다
                    // (한 번의 탭에서 서로 다른 세션 인스턴스가 네 개나 찍힘).
                    // 뷰 빌더 클로저는 상태를 읽기만 해야 하는 순수 함수 자리다.
                    if 새_가족_세션 == nil {
                        새_가족_세션 = NewFamilySession(onDone: onGuardianReady)
                    }
                    발급으로_간다 = true
                }
                Button("guardian_start_join_family") { 합류로_간다 = true }
                Button("dialog_cancel", role: .cancel) {}
            }
            .alert("ios_child_unsupported_title", isPresented: $아이는_안된다고_알린다) {
                // 이 알림은 iOS 전용(설계서 §4①④)이라 제목·본문처럼 버튼도
                // 전용 키를 쓴다 — 지도 화면의 배터리 안내 다이얼로그는 무관한
                // 화면이라 그 확인 버튼 키를 빌려 쓰지 않는다(문구가 우연히 같을
                // 뿐이라 그쪽이 나중에 바뀌면 여기까지 말없이 따라 바뀔 뻔했다).
                Button("ios_child_unsupported_confirm", role: .cancel) {}
            } message: {
                Text("ios_child_unsupported_body")
            }
            .navigationDestination(isPresented: $합류로_간다) {
                JoinFamilyView(expectedRole: .guardian, onJoined: onGuardianReady)
            }
            .navigationDestination(isPresented: $발급으로_간다) {
                // 여기서는 이미 있는 세션을 읽기만 한다(만들지 않는다) — 위
                // 버튼 액션 주석 참고. `발급으로_간다` 가 true 가 될 때는 항상
                // 그 액션이 먼저 세션을 만들어 둔 뒤이므로 `새_가족_세션` 은
                // 이 시점에 이미 채워져 있다.
                if let 세션 = 새_가족_세션 {
                    InviteCodeView(
                        mode: .newFamily(session: 세션),
                        onDone: onGuardianReady,
                        onReset: { 새_가족_세션 = nil }
                    )
                }
            }
        }
        .tint(KidCarePalette.sky)
        .onDisappear {
            // RoleSelectView 자체가 사라지는 건 온보딩이 끝났다는 뜻이다
            // (RouterView 가 ChildMapView 로 넘어갈 때만 일어난다) — 세션이
            // 들고 있던 작업/리스너를 마저 정리한다.
            새_가족_세션?.invalidate()
        }
    }

    private func 역할_버튼_글자(_ key: LocalizedStringKey, 그림: String) -> some View {
        HStack(spacing: 10) {
            // 그림은 글자를 꾸미기만 한다 — VoiceOver 가 버튼을 글자 그대로 읽게 숨긴다(UI 테스트도 글자로 찾는다).
            Image(systemName: 그림)
                .font(.system(size: 22))
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(key)
        }
    }
}
