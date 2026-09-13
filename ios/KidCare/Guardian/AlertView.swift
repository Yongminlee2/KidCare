import SwiftUI

/// 알림 탭. 정본은 `fragment_alert.xml`(위에서부터 카드 · 상태 한 줄 · 목록)과 `AlertFragment.renderList`(:270-277).
struct AlertView: View {
    let viewModel: AlertViewModel

    var body: some View {
        VStack(spacing: 0) {
            제약_카드
            if let 줄 = viewModel.상태_줄 {
                RuleStateLine(text: 줄)
            }
            ZStack {
                ScrollView {
                    // 줄마다 시각 표기를 그릴 때의 기기 시각. 안드로이드도 bind 할 때 한 번 읽는다(AlertAdapter.kt:101).
                    let now = Int64(Date().timeIntervalSince1970 * 1000)
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.events, id: \.id) { doc in
                            AlertRowView(doc: doc, 새것: viewModel.강조.contains(doc.id), nowMillis: now)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
                // 스크롤한 글이 상태 표시줄 밑으로 비치지 않게(4단계 Task 4 보완 5209a6e 와 같은 처리).
                .clipped()

                if let 문구 = viewModel.빈_목록_문구 {
                    빈_목록(문구)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background(KidCarePalette.paper)
    }

    /// 스위치 카드 자리(fragment_alert.xml:19-53). 스위치 대신 아이폰의 제약을 한 줄로 적는다(설계서 §4 ①).
    private var 제약_카드: some View {
        Text("ios_alert_open_app_hint")
            .font(.system(size: 13))
            .foregroundStyle(KidCarePalette.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(KidCarePalette.paperFold, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 6)
    }

    /// 빈 목록(fragment_alert.xml:83-116). 글자만 떠 있으면 화면의 8할이 빈 종이라 "고장인가"로 읽힌다.
    private func 빈_목록(_ 문구: String) -> some View {
        VStack(spacing: 0) {
            Image("Mascot3D")
                .resizable()
                .scaledToFit()
                .frame(width: 104, height: 104)
                .opacity(0.9)
                .accessibilityHidden(true)
            Text(문구)
                .font(.system(size: 15))
                .foregroundStyle(KidCarePalette.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }
}

/// 알림 한 줄. 정본은 `item_alert.xml` 과 `AlertAdapter.Holder.bind`(:51-74). 누를 것이 없다 — 읽는 목록이다.
struct AlertRowView: View {
    let doc: EventDoc
    /// "이번에 보이기 시작했을 때 안 읽었던 줄". 문서의 read 를 직접 보지 않는다(:25-28).
    let 새것: Bool
    let nowMillis: Int64

    var body: some View {
        let look = AlertText.look(doc)
        HStack(spacing: 12) {
            Image(systemName: look.systemImage)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(look.strong)
                .frame(width: 40, height: 40)
                .background(look.soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(AlertText.line(doc, nowMillis: nowMillis))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(KidCarePalette.ink)
                // detail 이 비면 줄 자체를 없앤다 — 빈 줄이 남으면 줄 높이만 들쭉날쭉해진다(:61-65).
                if !doc.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(doc.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(KidCarePalette.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 48)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(새것 ? KidCarePalette.apricotSoft : KidCarePalette.paperCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(KidCarePalette.lineSoft, lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
    }
}
