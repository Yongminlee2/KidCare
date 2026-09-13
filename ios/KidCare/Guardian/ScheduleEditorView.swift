import SwiftUI

/// 예약 편집 판. 정본은 `fragment_schedule.xml` 편집 판(:314-758) — 제목, 요일 일곱, 시각 두 칸, 범위 안내,
/// 모드 셋, 진행 줄, 취소·저장. 바탕은 colorSurface(paper), 좌우 20·위아래 16.
/// 내비게이션 바는 시스템 뒤로 버튼만 보인다(판정 기록 4). 뒤로 가면 `뒤로_갔다()` 가 불린다.
struct ScheduleEditorView: View {

    let viewModel: ScheduleViewModel

    private enum 시각_칸: String, Identifiable {
        case 시작, 끝
        var id: String { rawValue }
    }

    @State private var 고르는_칸: 시각_칸?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: viewModel.편집기_제목)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(KidCarePalette.ink)

                머리말("schedule_editor_days_label")
                요일_줄
                if viewModel.요일_경고 {
                    Text("schedule_editor_days_required")
                        .font(.system(size: 13))
                        .foregroundStyle(KidCarePalette.berryInk)
                        .padding(.top, 8)
                }

                머리말("schedule_editor_time_label")
                HStack(spacing: 0) {
                    시각_버튼(.시작)
                    Text("schedule_range_separator")
                        .font(.system(size: 18))
                        .foregroundStyle(KidCarePalette.inkSoft)
                        .padding(.horizontal, 12)
                    시각_버튼(.끝)
                }
                if let 안내 = viewModel.범위_안내 {
                    Text(verbatim: 안내)
                        .font(.system(size: 13))
                        .foregroundStyle(KidCarePalette.inkSoft)
                        .padding(.top, 8)
                }

                머리말("schedule_editor_mode_label")
                HStack(spacing: 8) {
                    모드_버튼(RingerMode.normal, 제목: String(localized: "schedule_mode_normal"))
                    모드_버튼(RingerMode.vibrate, 제목: String(localized: "schedule_mode_vibrate"))
                    모드_버튼(RingerMode.silent, 제목: String(localized: "schedule_mode_silent"))
                }

                HStack(spacing: 10) {
                    if viewModel.저장_중 {
                        ProgressView().controlSize(.small).frame(width: 18, height: 18)
                    }
                    if let 줄 = viewModel.편집_줄 {
                        Text(verbatim: 줄).font(.system(size: 13)).foregroundStyle(KidCarePalette.ink)
                    }
                }
                .padding(.top, 20)

                HStack(spacing: 10) {
                    // 취소는 외곽선 버튼이라 저장과 같은 격자에 앉는다(:721-742). 쓰기 중에는 잠근다.
                    Button { viewModel.취소를_눌렀다() } label: {
                        Text("schedule_editor_cancel")
                            .font(.system(size: 16))
                            .foregroundStyle(KidCarePalette.inkSoft)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(KidCarePalette.lineSoft, lineWidth: 1.5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { Task { await viewModel.저장을_눌렀다() } } label: {
                        Text("schedule_editor_save")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(KidCarePalette.onAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(KidCarePalette.sky, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .disabled(viewModel.저장_중)
                .opacity(viewModel.저장_중 ? 0.38 : 1)
                .padding(.top, 24)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .clipped()
        .background(KidCarePalette.paper)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $고르는_칸) { 칸 in
            시각_시트(칸)
        }
    }

    private func 머리말(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(KidCarePalette.ink)
            .padding(.top, 24)
            .padding(.bottom, 10)
    }

    /// 요일 일곱. 여백은 칸 **사이**에만(:348-353). 고르면 sky 바탕·흰 글자, 안 고르면 paper_card·line_soft,
    /// 글자는 평일 ink·토 sky·일 berry_ink(res/color/day_chip_*.xml).
    private var 요일_줄: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let 고름 = viewModel.요일.contains(day)
                Button { viewModel.요일을_누른다(day) } label: {
                    Text(verbatim: ScheduleText.dayName(day))
                        .font(.system(size: 15))
                        .foregroundStyle(고름 ? KidCarePalette.onAccent : Self.요일_글자색(day))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(고름 ? KidCarePalette.sky : KidCarePalette.paperCard, in: Capsule())
                        .overlay(Capsule().stroke(고름 ? KidCarePalette.sky : KidCarePalette.lineSoft, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private static func 요일_글자색(_ day: Int) -> Color {
        switch day {
        case 6: return KidCarePalette.sky
        case 7: return KidCarePalette.berryInk
        default: return KidCarePalette.ink
        }
    }

    /// 살구빛 시각 칸(:555-591). 그림은 뺐다 — 머리말이 이미 "몇 시부터 몇 시까지"라 말한다(:544-547).
    private func 시각_버튼(_ 칸: 시각_칸) -> some View {
        let minute = 칸 == .시작 ? viewModel.시작분 : viewModel.끝분
        return Button { 고르는_칸 = 칸 } label: {
            Text(verbatim: ScheduleText.timeText(minute))
                .font(.system(size: 18))
                .monospacedDigit()
                .foregroundStyle(KidCarePalette.onApricotSoft)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(KidCarePalette.apricotSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// 24시간 바퀴(판정 기록 5). 로캘은 고르기 하나에만 건다 — 라벨까지 걸면 6단계에 영어가 들어올 때
    /// 한국어 화면에 영어 라벨이 뜬다(4단계 Task 4 보고서).
    @ViewBuilder
    private func 시각_시트(_ 칸: 시각_칸) -> some View {
        VStack(spacing: 8) {
            if 칸 == .시작 {
                Text("schedule_editor_start_title").font(.system(size: 18, weight: .medium)).foregroundStyle(KidCarePalette.ink)
            } else {
                Text("schedule_editor_end_title").font(.system(size: 18, weight: .medium)).foregroundStyle(KidCarePalette.ink)
            }
            DatePicker("", selection: Binding(
                get: { ControlInput.date(minuteOfDay: 칸 == .시작 ? viewModel.시작분 : viewModel.끝분) },
                set: { date in
                    let minute = ControlInput.minuteOfDay(date)
                    if 칸 == .시작 { viewModel.시작분 = minute } else { viewModel.끝분 = minute }
                }
            ), displayedComponents: .hourAndMinute)
            .datePickerStyle(.wheel)
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "en_GB"))
        }
        .padding(.top, 24)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }

    /// 모드 버튼 셋(:614-695). 고른 것은 그 모드의 옅은 색 바탕·진한 테두리·진한 그림과 글자, 나머지는
    /// paper_card·line_soft·ink_soft. 색표는 목록 스티커와 같다(ScheduleFragment.kt:1085-1109).
    private func 모드_버튼(_ mode: String, 제목: String) -> some View {
        let 고름 = viewModel.모드 == mode
        let look = ScheduleModeLook.of(mode)
        return Button { viewModel.모드를_고른다(mode) } label: {
            VStack(spacing: 3) {
                Image(systemName: look.systemImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                Text(verbatim: 제목).font(.system(size: 13)).lineLimit(1)
            }
            .foregroundStyle(고름 ? look.strong : KidCarePalette.inkSoft)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(고름 ? look.soft : KidCarePalette.paperCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(고름 ? look.strong : KidCarePalette.lineSoft, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}
