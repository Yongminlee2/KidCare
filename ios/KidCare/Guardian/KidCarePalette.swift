import SwiftUI

/// 안드로이드 `res/values/colors.xml`(:4-23)의 값 그대로. 설계서 §4 "색과 치수는 안드로이드
/// 리소스에서 그대로 가져온다 — 눈대중으로 다시 고르지 않는다".
enum KidCarePalette {
    static let paper = Color(hex: 0xFFFBF6)
    static let paperCard = Color(hex: 0xFFFEFC)
    static let ink = Color(hex: 0x342D3F)
    static let inkSoft = Color(hex: 0x776E84)
    static let sky = Color(hex: 0x826DCC)
    static let skySoft = Color(hex: 0xEEE9FF)
    static let onAccent = Color(hex: 0xFFFFFF)
    static let grass = Color(hex: 0x7E9D68)
    static let grassSoft = Color(hex: 0xEDF4E7)
    static let berry = Color(hex: 0xE878AC)
    static let onBerry = Color(hex: 0x48152D)
    /// `themes.xml:22` 의 `colorErrorContainer` — 무응답 배너 바탕.
    static let berrySoft = Color(hex: 0xFDE8F2)
    /// `themes.xml:23` 의 `colorOnErrorContainer` — 무응답 배너 글자.
    static let onBerrySoft = Color(hex: 0x5B213C)
}

private extension Color {
    /// sRGB 로 명시한다 — 앱 아이콘 작업에서 색공간을 안 적었다가 `#CFEDE7` 이
    /// `#D7F0EC` 로 나온 일이 있다(README 2단계 개발일지).
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
