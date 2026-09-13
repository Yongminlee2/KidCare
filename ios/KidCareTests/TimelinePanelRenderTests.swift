import SwiftUI
import Testing
import UIKit
@testable import KidCare

/// 통합 검토 D1 — 실기기 확인(실제 가족 데이터)에서 "머무른 곳" 행의 시각·기간 줄이
/// 통째로 빈 채로 보였다. 원인은 문구 서식이나 데이터 모양이 아니라 패널 바탕이었다:
/// `.regularMaterial` 위에서 `.secondary` 로 그린 상세 줄과 행 사이 `Divider` 가 화면에
/// 전혀 찍히지 않았다(시뮬레이터에서 이름 있는 머무름·이동 행까지 똑같이 재현됐고,
/// 바탕만 불투명 색으로 바꾸자 같은 빌드에서 나타났다).
///
/// 문자열 조립(`timeline_detail`)만 보는 테스트는 이 결함을 절대 못 잡는다 —
/// 문자열은 처음부터 멀쩡했다. 그래서 테스트 호스트 앱의 실제 창에 패널을 띄우고
/// `drawHierarchy` 로 렌더 결과를 받아, 카드 안에 글자 줄이 몇 개 찍혔는지 픽셀로 센다.
///
/// 안드로이드처럼 가로 카드로 바꾼 뒤에도 목적은 같다 — 카드의 시각·기간 두 줄이
/// 패널(과 카드) 바탕 위에 실제로 보여야 한다.
@Suite(.serialized)
@MainActor
struct TimelinePanelRenderTests {

    init() async { await EmulatorHarness.start() }

    @Test("D1: 펼친 패널에서 이름 없는 머무름 카드의 시각·기간 두 줄이 실제로 그려진다")
    func 머무름_카드의_상세_줄이_그려진다() async throws {
        let model = MapViewModel(familyId: "family", childUid: "child", dayLoad: { _, _, dayKey in
            let start: Int64 = 1_757_000_000_000
            return (nil, TrailDoc([
                "dayKey": dayKey,
                "segments": [[
                    "type": "STAY", "startAt": start, "endAt": start + 600_000,
                    "lat": 37.5, "lng": 127.0, "distanceMeters": 0.0, "pointCount": 3, "placeName": "",
                ]] as [[String: Any]],
            ]))
        })
        await model.하루를_읽는다()
        try #require(model.타임라인_행.count == 1)

        let store = TimelinePanelStore()
        store.isExpanded = true
        let size = CGSize(width: 402, height: TimelinePanel.collapsedPanelHeight + TimelinePanel.defaultContentHeight)
        let host = UIHostingController(rootView: TimelinePanelView(viewModel: model, rootHeight: 874, store: store))
        host.safeAreaRegions = []
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        try? await Task.sleep(nanoseconds: 800_000_000) // 첫 레이아웃과 렌더가 끝날 시간

        let bounds = host.view.bounds
        let image = UIGraphicsImageRenderer(bounds: bounds).image { _ in
            _ = host.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }

        // 손잡이(28) + 경로 요약 줄(54) 아래 174 가 콘텐츠다(82..<256). 카드는 목록 여백
        // (가로 10·세로 6)과 카드 여백(가로 5·세로 2) 안쪽, x 15..<147·y 90..<248 에 놓인다.
        // 테두리 안쪽만 본다. 머무름 카드는 위에서부터 아이콘 그림 · 제목 · 시각 줄 · 기간 줄
        // 이라 글자 띠가 4개여야 한다 — 상세 줄이 안 찍히면 2개로 줄어든다.
        let 띠_수 = Self.글자_띠_수(image, x: 17..<145, y: 92..<246)
        #expect(띠_수 >= 4, "카드의 시각·기간 두 줄이 그려지지 않았다 — 글자 띠 \(띠_수)개")
    }

    /// 영역을 위에서 아래로 훑어 "어두운 불투명 픽셀이 하나라도 있는 가로줄"이 이어진
    /// 덩어리 수를 센다. 아이콘 그림·제목·상세 두 줄이 모두 찍히면 4 이상이다.
    private static func 글자_띠_수(_ image: UIImage, x: Range<Int>, y: Range<Int>) -> Int {
        guard let cg = image.cgImage else { return 0 }
        let scale = Int(image.scale.rounded())
        let width = cg.width
        let height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        var 띠_수 = 0
        var 띠_안 = false
        for py in (y.lowerBound * scale)..<min(y.upperBound * scale, height) {
            var 어두움 = false
            for px in (x.lowerBound * scale)..<min(x.upperBound * scale, width) {
                let i = (py * width + px) * 4
                let 밝기 = (Int(pixels[i]) * 299 + Int(pixels[i + 1]) * 587 + Int(pixels[i + 2]) * 114) / 1000
                if 밝기 < 200, pixels[i + 3] > 200 {
                    어두움 = true
                    break
                }
            }
            if 어두움, !띠_안 { 띠_수 += 1 }
            띠_안 = 어두움
        }
        return 띠_수
    }
}
