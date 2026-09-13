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
    /// colors.xml:14-16 — 벨소리 스티커(ScheduleAdapter.kt:224)와 시각 버튼(fragment_schedule.xml:565-567).
    static let apricot = Color(hex: 0xF2A05F)
    static let apricotSoft = Color(hex: 0xFFF0E2)
    static let onApricotSoft = Color(hex: 0x5A3216)
    /// colors.xml:23 — `themes.xml:20` 의 colorError. 삭제 그림, 경고 글자, 일요일 칸.
    static let berryInk = Color(hex: 0xB64C66)
    /// colors.xml:25 — `themes.xml:36` 의 colorOutline. 입력칸 테두리.
    static let line = Color(hex: 0xA398AE)
    /// colors.xml:26 — 카드 테두리, 고르지 않은 칸, 하루 띠 바탕.
    static let lineSoft = Color(hex: 0xE9E1ED)
    /// colors.xml:6 — `themes.xml:29` 의 colorSurfaceVariant. 장소 상한 안내 바탕.
    static let paperFold = Color(hex: 0xF5F0FF)
    /// colors.xml:29 — 타임라인 패널 손잡이(`bg_timeline_handle.xml`)와 경로선 끝색.
    static let routeLavender = Color(hex: 0x9B7DE2)
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
