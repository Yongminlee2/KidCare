import SwiftUI

// 안드로이드 Material 3 부품을 그대로 옮긴 공용 조각들. 값의 정본은 `res/values/themes.xml` 의 `Widget.KidCare.*`
// 와, 그 스타일이 물려받는 Material 1.14.0(`gradle/libs.versions.toml`)의 기본값이다 — 시스템 모양(둥근 테두리 입력칸,
// 흰 유리 손잡이 슬라이더, 캡슐 버튼)은 두 폰을 함께 쓰는 부모 눈에 다른 앱으로 보인다.

// MARK: - 버튼

/// `Widget.KidCare.Button`(themes.xml:156-161): 채운 sky, 글자 on_accent, 모서리 Medium 18.
/// 꺼졌을 때는 M3 `m3_button_background_color_selector` 대로 ink 12% 바탕, ink 38% 글자.
struct KidCareFilledButtonStyle: ButtonStyle {
    var minHeight: CGFloat = 64
    var fontSize: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        KidCareButtonBody(
            configuration: configuration, minHeight: minHeight, fontSize: fontSize, fullWidth: true,
            background: KidCarePalette.sky, foreground: KidCarePalette.onAccent
        )
    }
}

/// `Widget.KidCare.Button.Tonal`(themes.xml:165-167): sky_soft 바탕, sky 글자, 최소 높이 50, 모서리 18.
struct KidCareTonalButtonStyle: ButtonStyle {
    var minHeight: CGFloat = 50
    var fontSize: CGFloat = 15
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        KidCareButtonBody(
            configuration: configuration, minHeight: minHeight, fontSize: fontSize, fullWidth: fullWidth,
            background: KidCarePalette.skySoft, foreground: KidCarePalette.sky
        )
    }
}

/// `Widget.KidCare.Button.Text`(themes.xml:168-170): 바탕 없음, sky LabelLarge 15 medium, 최소 높이 48, 좌우 12.
struct KidCareTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        KidCareButtonBody(
            configuration: configuration, minHeight: 48, fontSize: 15, fullWidth: false,
            background: nil, foreground: KidCarePalette.sky, horizontalPadding: 12
        )
    }
}

private struct KidCareButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let minHeight: CGFloat
    let fontSize: CGFloat
    let fullWidth: Bool
    let background: Color?
    let foreground: Color
    var horizontalPadding: CGFloat = 24

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: fontSize, weight: .medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(isEnabled ? foreground : KidCarePalette.ink.opacity(0.38))
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: minHeight)
            .background {
                if let background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isEnabled ? background : KidCarePalette.ink.opacity(0.12))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - 입력칸

/// `Widget.KidCare.TextField`(themes.xml:196-198) = M3 `OutlinedBox` + 모서리 Small 12, 테두리 1(초점 2).
///
/// 이름표는 안드로이드처럼 **떠오른다**: 비어 있고 초점이 없으면 입력칸 안의 안내 글자(입력 글자 크기, ink_soft)이고,
/// 초점이 오거나 글자가 있으면 테두리 위로 올라가 BodySmall 13 이 된다(초점이면 sky). 테두리는 이름표 뒤에서
/// 끊긴다(`mtrl_textinput_box_label_cutout_padding` 4) — 뒤 바탕색(`surface`)을 이름표 뒤에 깔아 끊는다.
struct KidCareOutlinedField: View {

    enum Keyboard {
        case standard
        /// `InviteCodeField` 의 자판 규칙(ASCII, 대문자, 자동 고침 끔).
        case inviteCode
        /// 안드로이드 `textPersonName`.
        case personName
    }

    let label: LocalizedStringKey
    @Binding var text: String
    var keyboard: Keyboard = .standard
    /// 입력 글자. 기본은 BodyLarge 17(`m3_comp_outlined_text_field_input_text_type`).
    var fontSize: CGFloat = 17
    var fontWeight: Font.Weight = .regular
    var tracking: CGFloat = 0
    /// 안드로이드 `android:gravity="center"` — 글자와 이름표가 함께 가운데로 간다.
    var centered = false
    var minHeight: CGFloat = 56
    /// 여러 줄 입력(`textMultiLine` + `maxLines`). nil 이면 한 줄.
    var lines: ClosedRange<Int>? = nil
    /// 안드로이드 `android:maxLength` — 넘치는 글자는 들어오는 즉시 자른다.
    var maxLength: Int? = nil
    /// `app:counterEnabled` — 상자 아래 오른쪽에 "n/최대".
    var showsCounter = false
    var surface: Color = KidCarePalette.paper

    @FocusState private var 초점: Bool

    private var 떠있음: Bool { 초점 || !text.isEmpty }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            입력칸
                .font(.system(size: fontSize, weight: fontWeight))
                .tracking(tracking)
                .foregroundStyle(KidCarePalette.ink)
                .tint(KidCarePalette.sky)
                .multilineTextAlignment(centered ? .center : .leading)
                .focused($초점)
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: centered ? .center : .leading)
                .accessibilityLabel(Text(label))
                // 테두리와 이름표는 겹쳐 그리기만 한다 — 크기를 정하는 것은 입력칸뿐이다(ZStack 형제로 두면 둘러싼 칸의
                // 남는 높이를 이름표가 나눠 가져 상자가 부풀었다).
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(초점 ? KidCarePalette.sky : KidCarePalette.line, lineWidth: 초점 ? 2 : 1)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: 이름표_정렬) { 이름표 }
                .contentShape(Rectangle())
                .onTapGesture { 초점 = true }
                .animation(.easeOut(duration: 0.15), value: 떠있음)

            if showsCounter, let maxLength {
                Text(verbatim: "\(text.count)/\(maxLength)")
                    .font(.system(size: 13))
                    .foregroundStyle(KidCarePalette.inkSoft)
                    .padding(.horizontal, 16)
            }
        }
        .onChange(of: text) { _, 새_값 in
            if let maxLength, 새_값.count > maxLength { text = String(새_값.prefix(maxLength)) }
        }
    }

    @ViewBuilder
    private var 입력칸: some View {
        if let lines {
            TextField("", text: $text, axis: .vertical)
                .lineLimit(lines)
                .modifier(자판(kind: keyboard))
        } else {
            TextField("", text: $text)
                .modifier(자판(kind: keyboard))
        }
    }

    private var 이름표: some View {
        Text(label)
            .font(.system(size: 떠있음 ? 13 : fontSize))
            .foregroundStyle(초점 ? KidCarePalette.sky : KidCarePalette.inkSoft)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .background(떠있음 ? surface : Color.clear)
            .padding(.horizontal, 12)
            .padding(.top, !떠있음 && lines != nil ? 16 : 0)
            // 떠오른 이름표의 가운데가 테두리 선 위에 온다(13pt 한 줄 높이의 절반).
            .offset(y: 떠있음 ? -8 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var 이름표_정렬: Alignment {
        if 떠있음 || lines != nil { return centered ? .top : .topLeading }
        return centered ? .center : .leading
    }
}

private struct 자판: ViewModifier {
    let kind: KidCareOutlinedField.Keyboard

    @ViewBuilder
    func body(content: Content) -> some View {
        switch kind {
        case .standard: content
        case .inviteCode: content.inviteCodeKeyboard()
        case .personName: content.textContentType(.name).autocorrectionDisabled()
        }
    }
}

// MARK: - 슬라이더

/// `com.google.android.material.slider.Slider`(fragment_place.xml:267-274) — Material 1.14.0 `Widget.Material3.Slider`.
///
/// 손잡이는 둥근 원이 아니라 세로 막대다(`m3_comp_slider_active_handle_width` 4 × `_height` 44, sky). 트랙은 높이 16
/// (`m3_comp_slider_inactive_track_height`), 손잡이 양옆으로 6 틈(`_active_handle_leading_space`), 안쪽 모서리 2
/// (`trackInsideCornerSize`). 지나온 쪽 sky, 남은 쪽 `colorSecondaryContainer` = apricot_soft(themes.xml:12).
/// 눈금은 칸마다 4 점(`m3_comp_slider_stop_indicator_size`) — 지나온 쪽 on_accent, 남은 쪽 on_apricot_soft.
/// 트랙 좌우 여백 16(`mtrl_slider_track_side_padding`), 전체 높이 48(`mtrl_slider_widget_height`).
struct KidCareSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let accessibilityLabel: LocalizedStringKey
    let accessibilityValue: String

    private let 옆_여백: CGFloat = 16
    private let 트랙_높이: CGFloat = 16
    private let 손잡이_폭: CGFloat = 4
    private let 손잡이_높이: CGFloat = 44
    private let 틈: CGFloat = 6
    private let 눈금_크기: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let 폭 = max(geo.size.width - 옆_여백 * 2, 1)
            let 가운데 = geo.size.height / 2
            let x = 옆_여백 + 폭 * 비율
            let 앞_끝 = x - 손잡이_폭 / 2 - 틈
            let 뒤_시작 = x + 손잡이_폭 / 2 + 틈
            // 끝 눈금이 트랙의 둥근 끝 안에 들도록 트랙을 눈금 자리보다 조금 넓힌다.
            let 트랙_시작 = 옆_여백 - 트랙_높이 / 2 + 눈금_크기 / 2
            let 트랙_끝 = 옆_여백 + 폭 + 트랙_높이 / 2 - 눈금_크기 / 2

            ZStack(alignment: .topLeading) {
                if 앞_끝 > 트랙_시작 {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 트랙_높이 / 2, bottomLeadingRadius: 트랙_높이 / 2,
                        bottomTrailingRadius: 2, topTrailingRadius: 2, style: .continuous
                    )
                    .fill(KidCarePalette.sky)
                    .frame(width: 앞_끝 - 트랙_시작, height: 트랙_높이)
                    .position(x: (트랙_시작 + 앞_끝) / 2, y: 가운데)
                }
                if 트랙_끝 > 뒤_시작 {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 2, bottomLeadingRadius: 2,
                        bottomTrailingRadius: 트랙_높이 / 2, topTrailingRadius: 트랙_높이 / 2, style: .continuous
                    )
                    .fill(KidCarePalette.apricotSoft)
                    .frame(width: 트랙_끝 - 뒤_시작, height: 트랙_높이)
                    .position(x: (뒤_시작 + 트랙_끝) / 2, y: 가운데)
                }
                ForEach(0...칸_수, id: \.self) { i in
                    let 눈금_x = 옆_여백 + 폭 * CGFloat(i) / CGFloat(칸_수)
                    // 손잡이 틈 안에 떨어지는 눈금은 그리지 않는다.
                    if 눈금_x + 눈금_크기 / 2 < 앞_끝 - 2 || 눈금_x - 눈금_크기 / 2 > 뒤_시작 + 2 {
                        Circle()
                            .fill(눈금_x < x ? KidCarePalette.onAccent : KidCarePalette.onApricotSoft)
                            .frame(width: 눈금_크기, height: 눈금_크기)
                            .position(x: 눈금_x, y: 가운데)
                    }
                }
                RoundedRectangle(cornerRadius: 손잡이_폭 / 2, style: .continuous)
                    .fill(KidCarePalette.sky)
                    .frame(width: 손잡이_폭, height: 손잡이_높이)
                    .position(x: x, y: 가운데)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    값을_맞춘다(Double((g.location.x - 옆_여백) / 폭))
                }
            )
        }
        .frame(height: 48)
        .accessibilityElement()
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(verbatim: accessibilityValue))
        .accessibilityAdjustableAction { 방향 in
            switch 방향 {
            case .increment: 값을_정한다(value + step)
            case .decrement: 값을_정한다(value - step)
            @unknown default: break
            }
        }
    }

    private var 칸_수: Int {
        max(1, Int(((range.upperBound - range.lowerBound) / step).rounded()))
    }

    private var 비율: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(max((value - range.lowerBound) / span, 0), 1))
    }

    private func 값을_맞춘다(_ 비율: Double) {
        값을_정한다(range.lowerBound + min(max(비율, 0), 1) * (range.upperBound - range.lowerBound))
    }

    /// 눈금에 붙이고 범위 안으로 자른다 — 안드로이드 `stepSize` 는 눈금 사이 값을 허락하지 않는다.
    private func 값을_정한다(_ raw: Double) {
        let steps = ((raw - range.lowerBound) / step).rounded()
        let 새_값 = min(max(range.lowerBound + steps * step, range.lowerBound), range.upperBound)
        if 새_값 != value { value = 새_값 }
    }
}
