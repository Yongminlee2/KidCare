import SwiftUI

/// 관리 탭 화면. 정본은 안드로이드 `fragment_control.xml` — 구역 순서(인터넷 → 소리 → 잠금 →
/// 폰찾기 → 한마디 → 알람 → 상태 줄)와 색·치수를 그대로 옮긴다. 판단은 전부 `ControlViewModel`.
///
/// 소리 모드 버튼 셋을 채운 색이 아니라 옅은 색으로 둔 이유(xml :6-9): 셋 다 진하면 "지금
/// 눌러야 할 것"이 셋으로 보이는데, 이 화면에서 진짜 강한 동작은 핸드폰 찾기 하나뿐이다.
struct ControlView: View {

    let viewModel: ControlViewModel

    /// 카드 모서리 `ShapeAppearance.KidCare.Small`(themes.xml:82-85).
    private let 카드_모서리: CGFloat = 12
    /// 버튼 모서리 — `Widget.KidCare.Button.*` 는 전부 `ShapeAppearance.KidCare.Medium`(themes.xml:86-89,
    /// :156-170)이라 카드보다 둥글다.
    private let 버튼_모서리: CGFloat = 18

    /// 칩은 입력칸을 채우기만 한다 — 잘못 누른 한 줄은 아이 폰에 이미 떠서 되돌릴 수 없다(xml :300-303).
    private let 칩_문구: [String.LocalizationValue] = [
        "control_message_chip_where", "control_message_chip_call",
        "control_message_chip_come_home", "control_message_chip_meal",
    ]

    var body: some View {
        @Bindable var vm = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let 안내 = viewModel.아이_안내 {
                    Text(안내)
                        .font(.subheadline)
                        .foregroundStyle(KidCarePalette.inkSoft)
                        .padding(.bottom, 16)
                }

                구역_제목("control_section_network").padding(.top, 4)
                인터넷_카드.padding(.top, 8)

                구역_제목("control_section_ringer")
                소리_상태_카드.padding(.top, 8)
                if viewModel.방해금지_안내를_보이는가 {
                    보조_문구("control_ringer_dnd_note").padding(.top, 6)
                }
                모드_버튼들.padding(.top, 8)

                // 사람이 민 값만 저장으로 간다 — 서버에서 온 값은 get 으로만 들어온다(:234-238).
                Toggle(isOn: Binding(
                    get: { viewModel.lockEnabled },
                    set: { 값 in Task { await viewModel.잠금을_바꾼다(값) } }
                )) {
                    Text("control_lock_switch").font(.body).foregroundStyle(KidCarePalette.ink)
                }
                .tint(KidCarePalette.sky)
                .frame(minHeight: 48)
                // 아이가 없으면 저장할 곳이 없다. 뷰모델이 값을 안 바꾸는 setter 라 스위치가 켜진
                // 모양으로 남을 수 있어 아예 막는다(통합 검토 M2, 다른 보내는 버튼들과 같다).
                .disabled(!viewModel.버튼_활성화)
                .opacity(viewModel.버튼_활성화 ? 1 : 0.38)
                .padding(.top, 20)
                보조_문구("control_lock_hint")

                구분선

                폰찾기_구역

                구분선

                구역_제목("control_section_message")
                줄바꿈_배치(간격: 8) {
                    ForEach(칩_문구.indices, id: \.self) { i in
                        Button {
                            vm.메시지 = String(localized: 칩_문구[i])
                        } label: {
                            // M3 `Chip.Suggestion`: 높이 32, 모서리 shapeAppearanceCornerSmall(= KidCare.Small 12,
                            // themes.xml:82-85), 선 1 colorOutline(line), 바탕 colorSurface(paper), 글자 LabelLarge 15
                            // medium colorOnSurfaceVariant(ink_soft), 좌 8+8 · 우 6+10. 누르는 자리는 48 이다
                            // (`chipMinTouchTargetSize`) — 그만큼 위아래로 비워 줄 간격도 안드로이드와 같아진다.
                            Text(String(localized: 칩_문구[i]))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(KidCarePalette.inkSoft)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 32)
                                .background(KidCarePalette.paper, in: RoundedRectangle(cornerRadius: 카드_모서리, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 카드_모서리, style: .continuous)
                                        .strokeBorder(KidCarePalette.line, lineWidth: 1)
                                )
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 10)
                // `Widget.KidCare.TextField` + counterEnabled(xml :349-369) — 100자에서 입력이 멈출 때 왜 멈췄는지 보인다.
                KidCareOutlinedField(
                    label: "control_message_hint",
                    text: $vm.메시지,
                    lines: 1...3,
                    maxLength: ControlViewModel.messageMaxLength,
                    showsCounter: true
                )
                .padding(.top, 8)
                옅은_버튼("control_message_send", 그림: "paperplane.fill") {
                    await viewModel.메시지를_보낸다()
                }
                .padding(.top, 8)
                보조_문구("control_message_hint_detail").padding(.top, 8)

                구분선

                구역_제목("control_section_alarm")
                if let 알람 = viewModel.알람_상태_문구 {
                    Text(알람)
                        .font(.subheadline)
                        .foregroundStyle(KidCarePalette.inkSoft)
                        .padding(.top, 8)
                }
                알람_시각_줄
                    .padding(.top, 10)
                // 20자면 아이 폰 알림 제목 한 줄이다(xml :433-450).
                KidCareOutlinedField(
                    label: "control_alarm_label_hint",
                    text: $vm.알람_이름,
                    maxLength: ControlViewModel.alarmLabelMaxLength
                )
                .padding(.top, 8)
                옅은_버튼("control_alarm_set", 그림: "alarm") {
                    await viewModel.알람을_맞춘다()
                }
                .padding(.top, 8)
                // 폰찾기의 '이미 울리고 있다면'과 같은 이유로 늘 살아 있다(xml :465-467).
                글자_버튼("control_alarm_cancel") { await viewModel.알람을_끈다() }
                    .padding(.top, 4)
                보조_문구("control_alarm_hint_detail").padding(.top, 8)

                명령_상태_줄.padding(.top, 16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        // 스크롤한 글이 상태 표시줄(시계) 밑으로 비쳐 겹치지 않게 제 영역에서 자른다 — 안드로이드는
        // 상태 표시줄을 바탕색으로 칠해 같은 겹침이 없다. 바탕색은 잘린 뒤에 깔아 위쪽 안전 영역까지 채운다.
        .clipped()
        .background(KidCarePalette.paper)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - 구역

    private var 인터넷_카드: some View {
        // 보기만 한다 — 끄고 켜기는 안드로이드가 다른 앱에 허용하지 않는다는 사실을 카드 안에 적는다(xml :43-45).
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: viewModel.인터넷_아이콘)
                .font(.system(size: 18))
                .foregroundStyle(KidCarePalette.sky)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(viewModel.인터넷_문구).font(.subheadline).foregroundStyle(KidCarePalette.ink)
                if let 스위치 = viewModel.와이파이_스위치_문구 {
                    Text(스위치).font(.caption).foregroundStyle(KidCarePalette.inkSoft).padding(.top, 1)
                }
                보조_문구("control_network_readonly").padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(KidCarePalette.skySoft, in: RoundedRectangle(cornerRadius: 카드_모서리, style: .continuous))
    }

    private var 소리_상태_카드: some View {
        HStack(spacing: 9) {
            Image(systemName: viewModel.소리_상태_아이콘)
                .font(.system(size: 18))
                .foregroundStyle(KidCarePalette.grass)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(viewModel.소리_상태_문구)
                .font(.subheadline)
                .foregroundStyle(KidCarePalette.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await viewModel.소리_상태를_묻는다() }
            } label: {
                Label("control_ringer_refresh", systemImage: "arrow.clockwise").font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(KidCarePalette.sky)
            .disabled(!viewModel.새로_확인_활성화)
            .opacity(viewModel.새로_확인_활성화 ? 1 : 0.38)
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .background(KidCarePalette.grassSoft, in: RoundedRectangle(cornerRadius: 카드_모서리, style: .continuous))
    }

    private var 모드_버튼들: some View {
        HStack(spacing: 12) {
            모드_버튼(RingerMode.normal, 문구: "control_mode_normal", 그림: "speaker.wave.2.fill")
            모드_버튼(RingerMode.vibrate, 문구: "control_mode_vibrate", 그림: "iphone.radiowaves.left.and.right")
            모드_버튼(RingerMode.silent, 문구: "control_mode_silent", 그림: "speaker.slash.fill")
        }
    }

    /// 그림을 위, 이름을 아래 두 줄로 — 셋으로 갈린 폭에서 큰 글꼴이면 한 줄은 말줄임으로 잘린다(xml :185-186).
    /// 선택된 모드만 채운 색이다(renderRingerState :1029-1044 — sky/on_accent, 나머지 sky_soft/sky).
    private func 모드_버튼(_ mode: String, 문구: LocalizedStringKey, 그림: String) -> some View {
        let 선택됨 = viewModel.선택된_모드인가(mode)
        return Button {
            Task { await viewModel.소리_모드를_보낸다(mode) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: 그림).font(.system(size: 22))
                Text(문구).font(.subheadline.weight(.medium))
            }
            .foregroundStyle(선택됨 ? KidCarePalette.onAccent : KidCarePalette.sky)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(선택됨 ? KidCarePalette.sky : KidCarePalette.skySoft, in: RoundedRectangle(cornerRadius: 버튼_모서리, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.버튼_활성화)
        .opacity(viewModel.버튼_활성화 ? 1 : 0.38)
    }

    private var 폰찾기_구역: some View {
        let 울리는_중 = viewModel.울리는_중이라고_믿는가
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                Task { await viewModel.폰찾기_버튼을_눌렀다() }
            } label: {
                Label(울리는_중 ? "control_find_stop" : "control_find_phone", systemImage: "bell.and.waves.left.and.right")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(KidCarePalette.onBerry)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(KidCarePalette.berry, in: RoundedRectangle(cornerRadius: 버튼_모서리, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.버튼_활성화)
            .opacity(viewModel.버튼_활성화 ? 1 : 0.38)
            보조_문구("control_find_hint").padding(.top, 8)
            // 앱을 새로 열면 아이 폰이 울리는지 알 방법이 없다 — 언제든 끌 길을 열어 둔다.
            // 우리가 방금 울렸으면 큰 버튼이 같은 일을 하므로 숨긴다(:886-887).
            if !울리는_중 {
                글자_버튼("control_find_stop_hint") { await viewModel.소리를_끈다() }
                    .padding(.top, 4)
            }
        }
    }

    /// 안드로이드는 테두리 버튼(`alarm_time_button`, xml :421-431)을 눌러 24시간 고정 시각 창을
    /// 띄운다(:412-426). 여기서는 시스템 시각 고르기를 그 자리에 둔다(계획서 판정 기록 6).
    /// 로캘 `en_GB`(24시간, "07:30")는 **고르기에만** 건다 — 줄 전체에 걸면 라벨 문구까지 그
    /// 로캘의 번역을 찾는다(6단계에서 영어가 들어오면 한국어 화면에 영어 라벨이 뜬다).
    /// 숫자로 입력하게 하지 않는 이유는 0~1439 밖 값이 생길 수 있어서다(xml :398-399).
    private var 알람_시각_줄: some View {
        HStack(spacing: 8) {
            Label("control_alarm_picker_title", systemImage: "alarm")
                .font(.headline)
                .foregroundStyle(KidCarePalette.sky)
            Spacer(minLength: 8)
            DatePicker(
                "",
                selection: Binding(
                    get: { ControlInput.date(minuteOfDay: viewModel.alarmMinute) },
                    set: { viewModel.alarmMinute = ControlInput.minuteOfDay($0) }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "en_GB"))
        }
        .frame(minHeight: 64)
        .padding(.horizontal, 14)
        .overlay(
            RoundedRectangle(cornerRadius: 버튼_모서리, style: .continuous)
                .stroke(KidCarePalette.inkSoft.opacity(0.4))
        )
    }

    /// 명령 상태 한 줄(xml :484-506). 스피너는 `sending` 에서만 돈다.
    private var 명령_상태_줄: some View {
        HStack(spacing: 10) {
            if viewModel.commandUi.isSpinning {
                ProgressView().controlSize(.small)
            }
            if let 문구 = viewModel.commandUi.text {
                Text(문구).font(.subheadline).foregroundStyle(KidCarePalette.ink)
            }
        }
    }

    // MARK: - 조각

    /// 구역 제목 — 15sp medium `ink`(xml :34-41).
    private func 구역_제목(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(KidCarePalette.ink)
    }

    private func 보조_문구(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption)
            .foregroundStyle(KidCarePalette.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 1dp 구분선, 위아래 20(xml :255-259).
    private var 구분선: some View {
        Divider().padding(.vertical, 20)
    }

    /// `Widget.KidCare.Button.Tonal` 높이 58.
    private func 옅은_버튼(_ key: LocalizedStringKey, 그림: String, action: @escaping @MainActor () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Label(key, systemImage: 그림)
                .font(.headline)
                .foregroundStyle(KidCarePalette.sky)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(KidCarePalette.skySoft, in: RoundedRectangle(cornerRadius: 버튼_모서리, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.버튼_활성화)
        .opacity(viewModel.버튼_활성화 ? 1 : 0.38)
    }

    /// `Widget.KidCare.Button.Text`.
    private func 글자_버튼(_ key: LocalizedStringKey, action: @escaping @MainActor () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(key)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(KidCarePalette.sky)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.버튼_활성화)
        .opacity(viewModel.버튼_활성화 ? 1 : 0.38)
    }
}

/// 칩 넷을 폭에 맞춰 줄바꿈한다 — 안드로이드 `ChipGroup` 기본 간격 8dp.
private struct 줄바꿈_배치: Layout {
    var 간격: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let 너비 = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, 줄높이: CGFloat = 0, 최대너비: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > 너비 {
                x = 0
                y += 줄높이 + 간격
                줄높이 = 0
            }
            x += size.width + 간격
            줄높이 = max(줄높이, size.height)
            최대너비 = max(최대너비, x - 간격)
        }
        return CGSize(width: 최대너비, height: y + 줄높이)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, 줄높이: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += 줄높이 + 간격
                줄높이 = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + 간격
            줄높이 = max(줄높이, size.height)
        }
    }
}

/// 관리 탭 화면의 순수 도우미.
enum ControlInput {

    /// 안드로이드 `android:maxLength` — 넘치는 글자는 들어오는 즉시 자른다.
    static func clamp(_ text: String, max: Int) -> String {
        String(text.prefix(max))
    }

    /// 하루 안의 분을 `DatePicker` 가 다룰 날짜로. 날짜 부분은 의미가 없다 — 명령에는 분만 간다.
    /// 2001-01-01 을 쓰는 이유: 어느 시간대에서도 서머타임 전환일이 아니라 시·분이 그대로 돌아온다.
    static func date(minuteOfDay: Int, calendar: Calendar = .current) -> Date {
        let components = DateComponents(year: 2001, month: 1, day: 1, hour: minuteOfDay / 60, minute: minuteOfDay % 60)
        return calendar.date(from: components) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
