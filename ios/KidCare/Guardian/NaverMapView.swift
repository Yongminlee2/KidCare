import NMapsGeometry
import NMapsMap
import SwiftUI

/// 네이버 지도를 SwiftUI 에 끼워 넣는다.
///
/// **지도 뷰를 매번 새로 만들지 않는다.** `makeUIView` 에서 한 번 만들고 `updateUIView`
/// 는 마커와 카메라만 손댄다. 안드로이드가 탭을 바꿀 때 프래그먼트를 replace 하지 않는
/// 것과 같은 이유다 — 지도를 다시 만들면 타일을 처음부터 내려받고, 부모가 옮겨둔
/// 지도 위치도 초기화된다.
struct NaverMapView: UIViewRepresentable {

    var markerAt: (lat: Double, lng: Double)?
    /// 그 날 경로선. 정본은 안드로이드 `MapTimelineFragment.buildRouteSections` +
    /// `GradientRouteOverlay` — `RouteOverlay.sections(points:segments:)` 가 만든다.
    var routeSections: [RouteSection] = []
    /// Task 6: 타임라인 패널의 지금 전체 높이(접힘 뼈대 + 콘텐츠). 네이버 지도
    /// SDK 이용약관상 로고가 패널에 가려지면 안 되므로, 이 값만큼 로고 여백을
    /// 띄운다 — 정본은 안드로이드 `updateNaverLogoMargin`(:1194).
    var panelHeight: CGFloat = 0
    /// 마커가 처음 생겼을 때 한 번만 카메라를 옮긴다. 그 뒤에는 부모가 옮긴 자리를 지킨다.
    @Binding var 카메라를_한번_맞췄나: Bool
    /// M3(리뷰)·Task 7: `MapViewModel.카메라를_다시_맞춰야_한다` — '지금 위치
    /// 확인'이 `done` 으로 끝난 직후, 또는 실시간 추적이 새 신호를 받을 때마다
    /// true. 마커가 이미 있어도(`카메라를_한번_맞췄나` 가 이미 true 라도) 이번
    /// 한 번은 카메라를 강제로 다시 옮긴다 — 정본은 안드로이드 `renderMapStatus`
    /// 의 `shouldFocusChild = marker == null || focusChildOnNextLoad ||
    /// liveTrackingActive`(:784), 세 조건 전부 `MapViewModel` 쪽에서 이 한 신호로
    /// 합쳐진다.
    @Binding var 카메라를_다시_맞춰야_한다: Bool
    /// Task 8: `MapViewModel.포커스_요청` — 타임라인 행을 탭해 특정 좌표로 카메라를
    /// 옮겨야 할 때. 소비한 뒤 `nil` 로 되돌려 [MapViewModel.포커스_요청을_마쳤다]
    /// 를 대신한다.
    @Binding var 포커스_요청: MapFocusRequest?
    /// Task 8: `MapViewModel.경로_전체_보기_요청` — 값이 바뀔 때마다(카운터이므로
    /// "다르면 새 요청") 지금 보이는 경로 전체가 화면에 들어오게 카메라를 맞춘다.
    /// 일반 갱신마다 다시 맞추지 않는다(Task 1 규율) — [Coordinator.lastFitRequest]
    /// 가 마지막으로 처리한 값을 기억해 걸러낸다.
    var 경로_전체_보기_요청: Int = 0

    final class Coordinator {
        let marker = NMFMarker()
        /// 이전 경로선. 매번 새로 그리기 전에 지운다 — 안 지우면 날짜를 넘길
        /// 때마다(또는 재조회 때마다) 선이 겹겹이 쌓인다(안드로이드 `drawRoute` 주석).
        var routeOverlay: NMFMultipartPath?
        /// 마지막으로 처리한 [경로_전체_보기_요청] 값. 처음엔 0 과 같아도(둘 다
        /// 초기값 0) 문제없다 — 화면 진입 직후엔 아직 실제 요청(1 이상)이 없다.
        var lastFitRequest = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> NMFNaverMapView {
        let view = NMFNaverMapView(frame: .zero)
        view.showLocationButton = false   // 보호자 앱은 위치 권한을 쓰지 않는다(설계서 §1)
        view.showZoomControls = true
        return view
    }

    func updateUIView(_ view: NMFNaverMapView, context: Context) {
        renderRoute(routeSections, on: view.mapView, coordinator: context.coordinator)
        // 안드로이드 `updateNaverLogoMargin` 의 네 인자(left=dp(14), top=0, right=0,
        // bottom=panelHeight+dp(8))와 같은 값 — 패널이 늘어나는 만큼 로고도 같이
        // 밀려 올라가 어느 높이에서도 가려지지 않는다.
        view.mapView.logoMargin = UIEdgeInsets(top: 0, left: 14, bottom: panelHeight + 8, right: 0)

        // Task 8: 경로 전체 보기(정본 안드로이드 `fitWholeRoute` 네 호출 자리) —
        // 이 값이 지난번 처리한 값과 다를 때만 움직인다. `updateUIView` 는 이
        // 뷰의 다른 프로퍼티(마커 위치 등)가 바뀔 때도 매번 다시 불리므로, 값
        // 비교 없이 매번 fitWholeRoute 를 부르면 부모가 방금 옮겨본 지도를 일반
        // 갱신마다 도로 빼앗는다(Task 1 규율).
        if context.coordinator.lastFitRequest != 경로_전체_보기_요청 {
            context.coordinator.lastFitRequest = 경로_전체_보기_요청
            fitWholeRoute(routeSections, on: view.mapView)
        }

        // Task 8: 타임라인 행 탭 포커스 — 정본은 안드로이드 `focusOn`(:1039).
        if let target = 포커스_요청 {
            let position = NMGLatLng(lat: target.lat, lng: target.lng)
            view.mapView.moveCamera(NMFCameraUpdate(scrollTo: position, zoomTo: target.zoom))
            DispatchQueue.main.async { 포커스_요청 = nil }
        }

        guard let markerAt else {
            context.coordinator.marker.mapView = nil
            return
        }
        let position = NMGLatLng(lat: markerAt.lat, lng: markerAt.lng)
        context.coordinator.marker.position = position
        context.coordinator.marker.mapView = view.mapView

        // M3(리뷰): 안드로이드 `shouldFocusChild` 와 같은 판단 — 처음 생겼을 때든,
        // '지금 위치 확인' 이 방금 새 위치를 받아왔을 때든, 실시간 추적이 새
        // 신호를 받았을 때든 카메라가 따라간다.
        let 강제_재조준 = 카메라를_다시_맞춰야_한다
        if !카메라를_한번_맞췄나 || 강제_재조준 {
            view.mapView.moveCamera(NMFCameraUpdate(scrollTo: position))
            DispatchQueue.main.async {
                카메라를_한번_맞췄나 = true
                if 강제_재조준 { 카메라를_다시_맞춰야_한다 = false }
            }
        }
    }

    /// Task 8: 지금 보이는 경로 전체가 화면에 들어오게 카메라를 맞춘다. 정본은
    /// 안드로이드 `fitWholeRoute`(:1177) — 왼쪽/오른쪽 48, 위 112, 아래
    /// (패널 높이 + 24)의 비대칭 여백과 350ms 애니메이션까지 그대로 옮긴다.
    /// 좌표가 2개 미만이면(선을 그릴 게 없으면) 아무 일도 하지 않는다.
    private func fitWholeRoute(_ sections: [RouteSection], on map: NMFMapView) {
        let coordinates = sections.flatMap(\.coordinates)
        guard coordinates.count >= 2 else { return }
        let latLngs = coordinates.map { NMGLatLng(lat: $0.lat, lng: $0.lng) }
        let bounds = NMGLatLngBounds(latLngs: latLngs)
        let insets = UIEdgeInsets(top: 112, left: 48, bottom: panelHeight + 24, right: 48)
        let update = NMFCameraUpdate(fit: bounds, paddingInsets: insets)
        // 안드로이드 `CameraAnimation.Easing`(가속·감속이 모두 있는 완만한
        // 애니메이션)에 가장 가까운 iOS SDK 값 — 이 SDK 에는 이름이 같은 값이
        // 없어(`easeIn`/`easeOut`/`linear`/`fly` 뿐) 감속(도착 직전 느려짐)이
        // 도착지에 부드럽게 안착하는 인상을 준다는 이유로 `.easeOut` 을 고른다.
        update.animation = .easeOut
        update.animationDuration = 0.35
        map.moveCamera(update)
    }

    /// 정본은 안드로이드 `MapTimelineFragment.renderRouteOverlay` + `GradientRouteOverlay`.
    /// 지도 뷰 자체는 새로 만들지 않는다(타입 주석 참고) — 여기서는 오버레이 하나만
    /// 지우고 새로 얹는다.
    private func renderRoute(_ sections: [RouteSection], on map: NMFMapView, coordinator: Coordinator) {
        coordinator.routeOverlay?.mapView = nil
        coordinator.routeOverlay = nil

        let legs = sections.map(\.coordinates).filter { $0.count >= 2 }
        guard !legs.isEmpty else { return }

        let parts = RouteGradient.parts(legs: legs)
        guard !parts.isEmpty else { return }

        let lineParts = parts.map { part in part.coordinates.map { NMGLatLng(lat: $0.lat, lng: $0.lng) } }
        guard let overlay = NMFMultipartPath(lineParts) else { return }
        overlay.colorParts = parts.map { RouteGradient.pathColor(at: $0.fraction) }
        overlay.width = 8
        overlay.outlineWidth = 4
        overlay.mapView = map
        coordinator.routeOverlay = overlay
    }
}

/// 안드로이드 `GradientRouteOverlay` 와 같은 살구색→분홍색→라벤더색 그라데이션.
/// 색 값은 `app/src/main/res/values/colors.xml` 의 route_apricot·route_pink·
/// route_lavender·route_halo 를 그대로 옮겼다 — 안드로이드가 정본이라 숫자를 새로
/// 정하지 않는다(두 폰이 같은 경로를 다르게 색칠하면 안 된다).
///
/// 비즈 마커(구간 3등분 지점의 작은 원)는 옮기지 않았다 — 이 앱이 새로 그린
/// 선을 눈으로 확인하는 이번 과제의 목적에는 리본 자체로 충분하고, 마커 비트맵
/// 렌더링은 별도 검증(정확한 픽셀 크기·anchor)이 필요한 장식이라 범위 밖으로 둔다.
private enum RouteGradient {
    static let apricot = UIColor(red: 0xF3 / 255, green: 0xA3 / 255, blue: 0x5E / 255, alpha: 1)
    static let pink = UIColor(red: 0xEA / 255, green: 0x79 / 255, blue: 0xAF / 255, alpha: 1)
    static let lavender = UIColor(red: 0x9B / 255, green: 0x7D / 255, blue: 0xE2 / 255, alpha: 1)
    static let halo = UIColor(red: 1, green: 1, blue: 1, alpha: 0xF7 / 255)

    /// 안드로이드 `GradientRouteOverlay.MAX_COLOR_PARTS` 와 같은 32 — 하루 점이
    /// 많아도 파트 수를 제한해 지도를 가볍게 유지한다.
    private static let maxColorParts = 32

    struct Part {
        let coordinates: [(lat: Double, lng: Double)]
        let fraction: Double
    }

    /// 안드로이드 `GradientRouteOverlay.buildParts` 를 그대로 옮긴다 — 레그 전체를
    /// 이어 붙인 총 변(edge) 수를 최대 32파트로 고르게 나눠, 파트마다 하나의 고정
    /// 색을 준다(파트 경계에서 색이 바뀌는 계단식 그라데이션).
    static func parts(legs: [[(lat: Double, lng: Double)]]) -> [Part] {
        let totalEdges = max(legs.reduce(0) { $0 + max($1.count - 1, 0) }, 1)
        let chunkEdges = max(Int((Double(totalEdges) / Double(maxColorParts)).rounded(.up)), 1)
        var result: [Part] = []
        var completedEdges = 0
        for leg in legs {
            let lastIndex = leg.count - 1
            var firstEdge = 0
            while firstEdge < lastIndex {
                let lastEdgeExclusive = min(firstEdge + chunkEdges, lastIndex)
                let midpoint = Double(completedEdges + (firstEdge + lastEdgeExclusive) / 2)
                result.append(Part(
                    coordinates: Array(leg[firstEdge...lastEdgeExclusive]),
                    fraction: min(max(midpoint / Double(totalEdges), 0), 1)
                ))
                firstEdge = lastEdgeExclusive
            }
            completedEdges += lastIndex
        }
        return result
    }

    static func pathColor(at fraction: Double) -> NMFPathColor {
        let color = colorAt(fraction)
        return NMFPathColor(color: color, outlineColor: halo, passedColor: color, passedOutlineColor: halo)
    }

    private static func colorAt(_ fraction: Double) -> UIColor {
        fraction <= 0.5
            ? blend(apricot, pink, fraction * 2)
            : blend(pink, lavender, (fraction - 0.5) * 2)
    }

    private static func blend(_ from: UIColor, _ to: UIColor, _ amount: Double) -> UIColor {
        let t = CGFloat(min(max(amount, 0), 1))
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        from.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        to.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        return UIColor(
            red: fr + (tr - fr) * t,
            green: fg + (tg - fg) * t,
            blue: fb + (tb - fb) * t,
            alpha: fa + (ta - fa) * t
        )
    }
}
