import SwiftUI

/// 예약·장소 목록 판이 함께 쓰는 조각. 두 XML 은 "같은 뼈대"를 쓴다(item_place.xml:2-4).
/// 한쪽만 고치면 탭을 넘길 때 선이 튄다(README "네 탭을 한 격자에").

/// 목록 위 오류·저장 결과 한 줄(fragment_schedule.xml:221-230, fragment_place.xml:23-32).
struct RuleStateLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(KidCarePalette.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
    }
}

/// "아직 애기폰에 전달되지 않았어요" 줄(fragment_schedule.xml:232-271, fragment_place.xml:34-68).
/// 바탕은 colorErrorContainer(berry_soft), 글자와 버튼은 colorOnErrorContainer(on_berry_soft) —
/// 기본 하늘색 글자 버튼이면 이 바탕 위에서 1.7:1 로 안 보인다(:259-261).
struct SyncPendingBar: View {
    let text: String
    let retryTitle: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(KidCarePalette.onBerrySoft)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: retry) {
                Text(retryTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(KidCarePalette.onBerrySoft)
                    .frame(minHeight: 48)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(KidCarePalette.berrySoft)
    }
}

/// 목록 맨 아래 추가 버튼(fragment_schedule.xml:299-311, fragment_place.xml:131-143). `Widget.KidCare.Button`
/// — 채운 sky, 모서리 18, 높이 48, 그림 22·간격 8, TitleMedium. 잠기면 Material3 비활성 색(글자 38%, 바탕 12%).
struct RuleAddButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 20, weight: .semibold))
                Text(title).font(.system(size: 18, weight: .medium))
            }
            .foregroundStyle(enabled ? KidCarePalette.onAccent : KidCarePalette.ink.opacity(0.38))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(enabled ? KidCarePalette.sky : KidCarePalette.ink.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}

/// 줄 끝 삭제 그림 버튼 44×44(item_schedule.xml:122-139, `dimens.xml` row_icon_button). 그림 21, berry_ink.
struct RowDeleteButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 18))
                .foregroundStyle(KidCarePalette.berryInk)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

extension View {
    /// 목록 카드 한 장. `Widget.KidCare.Card`(themes.xml:170-176) — paper_card, 모서리 18(item 이
    /// `ShapeAppearance.KidCare.Medium` 을 적었다, item_schedule.xml:22), 테두리 line_soft 1.
    func ruleCard() -> some View {
        background(KidCarePalette.paperCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(KidCarePalette.lineSoft, lineWidth: 1))
    }
}
