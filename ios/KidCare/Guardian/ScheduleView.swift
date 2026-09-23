import SwiftUI

/// 예약 탭 목록 판. 정본은 `fragment_schedule.xml` 목록 판(:16-312)과 `item_schedule.xml`.
/// 위에서 아래로 기본 모드 카드 → 공휴일 카드 → 상태 줄 → 못 보낸 알림 줄 → 규칙 목록 → 추가 버튼.
/// 편집 판은 탭 안 `NavigationStack` 으로 push 한다(판정 기록 2).
struct ScheduleView: View {

    let viewModel: ScheduleViewModel

    var body: some View {
        NavigationStack {
            목록_판
                // 목록 판에는 화면 제목이 없다 — 아래 탭이 이미 "예약"이라 말한다(README "밀도").
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: Binding(
                    get: { viewModel.편집_중 },
                    set: { if !$0 { viewModel.뒤로_갔다() } }
                )) {
                    ScheduleEditorView(viewModel: viewModel)
                }
        }
        .alert(확인_제목, isPresented: Binding(
            get: { viewModel.확인창 != nil },
            set: { if !$0 { viewModel.확인창 = nil } }
        ), presenting: viewModel.확인창) { 확인 in
            switch 확인 {
            case .하루_종일:
                Button(String(localized: "schedule_allday_confirm")) { Task { await viewModel.하루_종일을_확인했다() } }
                Button(String(localized: "schedule_allday_cancel"), role: .cancel) {}
            case .겹침:
                Button(String(localized: "schedule_overlap_confirm")) { Task { await viewModel.겹쳐도_저장한다() } }
                Button(String(localized: "schedule_overlap_cancel"), role: .cancel) {}
            case .삭제(let doc, _):
                Button(String(localized: "schedule_delete_confirm"), role: .destructive) { Task { await viewModel.삭제를_확인했다(doc) } }
                Button(String(localized: "schedule_delete_cancel"), role: .cancel) {}
            }
        } message: { 확인 in
            Text(verbatim: 확인.message)
        }
    }

    private var 확인_제목: String {
        switch viewModel.확인창 {
        case .하루_종일: return String(localized: "schedule_allday_title")
        case .겹침: return String(localized: "schedule_overlap_title")
        case .삭제: return String(localized: "schedule_delete_title")
        case nil: return ""
        }
    }

    private var 목록_판: some View {
        VStack(spacing: 0) {
            // 탭 맨 위에 **늘** 있는 한 줄. 그 아래로 규칙 목록·추가 버튼·기본 모드 넷·공휴일
            // 스위치가 전부 평소처럼 눌리고 평소처럼 저장된다 — 그 아이가 나중에 안드로이드
            // 폰으로 바뀌면 그 폰이 읽어 간다(설계서 §10.2, 판정 기록 5).
            if viewModel.아이폰이라_규칙이_안_걸린다 {
                Text("ios_child_schedule_not_applied")
                    .font(.subheadline)
                    .foregroundStyle(KidCarePalette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }
            기본_모드_카드
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 6)
            공휴일_카드
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            if let 줄 = viewModel.상태_줄 {
                RuleStateLine(text: 줄)
            }
            // 아이폰 아이에게는 이 바가 **한 번도** 안 뜬다. 깃발이 안 올라가므로 조건만으로도
            // 안 뜨지만, 옛 버전이 올려 둔 깃발이 `UserDefaults` 에 남아 있을 수 있어 화면에서도
            // 한 겹 막는다(`아이에게_알린다` 의 `깃발을_바꾼다(false)` 가 그것을 치우기 **전에**
            // 한 번 그려질 수 있다). 끄지 않고 **숨기는** 이유는 판정 기록 5·7 이다 — 흐려진
            // "아직 못 알렸어요"는 일시적 실패로 읽혀 부모가 계속 다시 누른다.
            if viewModel.pendingSync && !viewModel.아이폰이라_규칙이_안_걸린다 {
                SyncPendingBar(text: String(localized: "schedule_sync_pending"),
                               retryTitle: String(localized: "schedule_sync_retry")) {
                    viewModel.다시_알린다()
                }
            }
            ZStack {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.rules, id: \.id) { rule in
                            ScheduleRowView(
                                rule: rule,
                                onEdit: { viewModel.편집을_연다(rule) },
                                onToggle: { on in Task { await viewModel.켬끔을_바꾼다(rule, enabled: on) } },
                                onDelete: { viewModel.삭제를_눌렀다(rule) }
                            )
                            .padding(.horizontal, 20)
                            .padding(.vertical, 5)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
                // 4단계 Task 4 보완(5209a6e)과 같다 — 스크롤한 줄이 위 카드 밑으로 비치지 않게 자른다.
                .clipped()
                if let 빈_문구 = viewModel.listLoad.emptyText(isEmpty: viewModel.rules.isEmpty,
                                                          loaded: String(localized: "schedule_empty")) {
                    Text(빈_문구)
                        .font(.system(size: 15))
                        .foregroundStyle(KidCarePalette.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(24)
                }
            }
            .frame(maxHeight: .infinity)
            RuleAddButton(title: String(localized: "schedule_add")) { viewModel.편집을_연다(nil) }
        }
        .background(KidCarePalette.paper)
    }

    // MARK: 기본 모드 카드 (:23-149, 칠하기 ScheduleFragment.kt:731-758)

    private var 기본_모드_카드: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("schedule_default_label")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(KidCarePalette.ink)
            HStack(spacing: 6) {
                기본_모드_칸("", 제목: String(localized: "schedule_default_none"))
                기본_모드_칸(RingerMode.normal, 제목: String(localized: "schedule_mode_normal"))
                기본_모드_칸(RingerMode.vibrate, 제목: String(localized: "schedule_mode_vibrate"))
                기본_모드_칸(RingerMode.silent, 제목: String(localized: "schedule_mode_silent"))
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ruleCard()
    }

    /// 고른 칸만 그 모드의 옅은 색으로 차고 테두리·글자는 진한 색이다. '그대로 두기'는 ink_soft/line_soft(:738-747).
    private func 기본_모드_칸(_ mode: String, 제목: String) -> some View {
        let 고름 = viewModel.defaultMode == mode
        let look = mode.isEmpty ? ScheduleModeLook.그대로_두기 : ScheduleModeLook.of(mode)
        return Button {
            Task { await viewModel.기본_모드를_고른다(mode) }
        } label: {
            Text(제목)
                .font(.system(size: 12))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(고름 ? look.strong : KidCarePalette.inkSoft)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(고름 ? look.soft : KidCarePalette.paperCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(고름 ? look.strong : KidCarePalette.lineSoft, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.설정_잠김)
        .opacity(viewModel.설정_잠김 ? 0.38 : 1)
    }

    // MARK: 공휴일 카드 (:151-219)

    private var 공휴일_카드: some View {
        HStack(spacing: 0) {
            Image(systemName: "calendar")
                .font(.system(size: 20))
                .foregroundStyle(KidCarePalette.berryInk)
                .frame(width: 24, height: 24)
                .padding(.trailing, 12)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("schedule_holiday_title")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(KidCarePalette.onBerrySoft)
                Text(verbatim: viewModel.공휴일_안내)
                    .font(.system(size: 13))
                    .foregroundStyle(KidCarePalette.onBerrySoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 사람이 민 값만 저장으로 간다 — 스냅샷이 대입한 값으로는 쓰기가 안 나간다(:227-230).
            Toggle("", isOn: Binding(
                get: { viewModel.holidayOff },
                set: { on in Task { await viewModel.공휴일을_바꾼다(on) } }
            ))
            .labelsHidden()
            .tint(KidCarePalette.sky)
            .frame(minHeight: 48)
            .padding(.leading, 8)
            .disabled(viewModel.설정_잠김)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(KidCarePalette.berrySoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// 소리 모드 하나의 생김새 — 그림, 진한 색, 옅은 색. 스티커·하루 띠·편집 판 버튼이 같은 표를 쓴다
/// (ScheduleAdapter.kt:215-231). 그림 이름은 관리 탭과 같다(판정 기록 13).
struct ScheduleModeLook {
    let systemImage: String
    let strong: Color
    let soft: Color

    static func of(_ mode: String) -> ScheduleModeLook {
        switch mode {
        case RingerMode.normal:
            return ScheduleModeLook(systemImage: "speaker.wave.2.fill", strong: KidCarePalette.apricot, soft: KidCarePalette.apricotSoft)
        case RingerMode.vibrate:
            return ScheduleModeLook(systemImage: "iphone.radiowaves.left.and.right", strong: KidCarePalette.sky, soft: KidCarePalette.skySoft)
        case RingerMode.silent:
            return ScheduleModeLook(systemImage: "speaker.slash.fill", strong: KidCarePalette.grass, soft: KidCarePalette.grassSoft)
        default:
            // 모르는 값이면 색으로 아는 척하지 않는다(:229-230).
            return ScheduleModeLook(systemImage: "alarm", strong: KidCarePalette.inkSoft, soft: KidCarePalette.lineSoft)
        }
    }

    /// 기본 모드 카드의 '그대로 두기' 칸.
    static let 그대로_두기 = ScheduleModeLook(systemImage: "", strong: KidCarePalette.inkSoft, soft: KidCarePalette.lineSoft)
}

/// 규칙 한 장(item_schedule.xml). 누르는 자리 셋(고치기·켬끔·삭제)을 겹치지 않게 나눈다(:2-4).
struct ScheduleRowView: View {
    let rule: ScheduleDoc
    let onEdit: () -> Void
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        let look = ScheduleModeLook.of(rule.mode)
        HStack(spacing: 0) {
            Button(action: onEdit) {
                HStack(spacing: 0) {
                    Image(systemName: look.systemImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 21, height: 21)
                        .foregroundStyle(look.strong)
                        .frame(width: 40, height: 40)
                        .background(look.soft, in: Circle())
                        .padding(.trailing, 11)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: ScheduleText.daysText(rule.days))
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(KidCarePalette.ink)
                        Text(verbatim: ScheduleText.rowDetail(rule))
                            .font(.system(size: 13))
                            .foregroundStyle(KidCarePalette.inkSoft)
                        DayRibbonView(start: rule.startMinute, end: rule.endMinute, color: look.strong)
                            .frame(height: 4)
                            .padding(.top, 4)
                            .opacity(rule.enabled ? 1 : 0.45)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
                // 꺼둔 규칙은 지워진 게 아니라 쉬는 것 — 흐리게만 한다(ScheduleAdapter.kt:56-58).
                .opacity(rule.enabled ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(get: { rule.enabled }, set: onToggle))
                .labelsHidden()
                .tint(KidCarePalette.sky)
                .padding(.leading, 6)
            RowDeleteButton(label: String(localized: "schedule_delete"), action: onDelete)
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .ruleCard()
    }
}

/// 하루 띠(item_schedule.xml:86-111). 바탕 line_soft·모서리 5(bg_ribbon_track.xml), 조각 폭은 분 비율.
struct DayRibbonView: View {
    let start: Int
    let end: Int
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let pieces = DayRibbon.pieces(start: start, end: end)
            let total = CGFloat(max(pieces.reduce(0) { $0 + $1.weight }, 1))
            HStack(spacing: 0) {
                ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                    Rectangle()
                        .fill(piece.filled ? color : Color.clear)
                        .frame(width: geo.size.width * CGFloat(piece.weight) / total)
                }
            }
        }
        .background(KidCarePalette.lineSoft)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
