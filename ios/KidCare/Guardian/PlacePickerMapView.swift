import NMapsGeometry
import NMapsMap
import SwiftUI
import UIKit

/// 장소 편집의 지도. 정본은 안드로이드 `PlaceFragment` 의 지도 부분(:235-283, :504-580)과
/// `fragment_place.xml:228-249`. 지도 뷰는 `makeUIView` 에서 한 번만 만들고, `updateUIView` 는 카메라
/// 요청(번호가 바뀔 때만)과 반경 원만 손댄다.
struct PlacePickerMapView: UIViewRepresentable {

    var camera: PlaceViewModel.카메라?
    var circle: PlaceViewModel.반경_원?
    /// 손가락이 닿은 순간. 그때의 지도 가운데를 준다(판정 기록 8).
    var onTouchDown: (_ centerLat: Double, _ centerLng: Double) -> Void
    var onTouchEnd: () -> Void
    /// 카메라가 멈췄다. [byUser] 는 마지막 움직임이 제스처였는가.
    var onIdle: (_ centerLat: Double, _ centerLng: Double, _ byUser: Bool) -> Void

    /// PlaceFragment.kt:949-953 — 채움 `0x333D6DF5`, 테두리 `0xBB3D6DF5`, 4dp. 정확도 원(지도 탭)보다
    /// 진하다 — 저건 번짐이고 이건 부모가 지금 정하는 값이다.
    static let fillColor = UIColor(red: 0x3D / 255.0, green: 0x6D / 255.0, blue: 0xF5 / 255.0, alpha: 0x33 / 255.0)
    static let strokeColor = UIColor(red: 0x3D / 255.0, green: 0x6D / 255.0, blue: 0xF5 / 255.0, alpha: 0xBB / 255.0)
    static let strokeWidth: Double = 4

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PlacePickerMapView
        weak var mapView: NMFMapView?
        var circleOverlay: NMFCircleOverlay?
        var lastCameraNumber: Int?
        /// 마지막 카메라 움직임의 원인. `NMFMapChangedByGesture`(-1)일 때만 사람이 옮긴 것이다.
        var lastReason = NMFMapChangedByDeveloper

        init(parent: PlacePickerMapView) {
            self.parent = parent
        }

        /// 지속시간 0 누르기 — 손이 닿는 순간 `.began`. 안드로이드 `ACTION_DOWN`(:249) 자리다.
        @objc func touched(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                guard let mapView else { return }
                let target = mapView.cameraPosition.target
                parent.onTouchDown(target.lat, target.lng)
            case .ended, .cancelled, .failed:
                parent.onTouchEnd()
            default:
                break
            }
        }

        /// 지도 자신의 이동·확대 제스처와 함께 인식한다 — 안드로이드 리스너가 `false` 를 돌려 지도 처리를
        /// 잇게 한 것과 같다(:253-254).
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> NMFNaverMapView {
        let view = NMFNaverMapView(frame: .zero)
        // PlaceFragment.kt:262-267 — 줌·위치·축척 버튼 끔, 로고 여백 왼쪽 8·아래 8.
        view.showZoomControls = false
        view.showLocationButton = false   // 보호자 앱은 위치 권한을 쓰지 않는다(설계서 §1)
        view.showScaleBar = false
        view.mapView.logoMargin = UIEdgeInsets(top: 0, left: 8, bottom: 8, right: 0)
        view.mapView.addCameraDelegate(delegate: context.coordinator)

        let touch = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.touched(_:)))
        touch.minimumPressDuration = 0
        touch.cancelsTouchesInView = false
        touch.delegate = context.coordinator
        view.mapView.addGestureRecognizer(touch)

        context.coordinator.mapView = view.mapView
        return view
    }

    func updateUIView(_ view: NMFNaverMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        if let camera, camera.번호 != coordinator.lastCameraNumber {
            coordinator.lastCameraNumber = camera.번호
            // 개발자 이동이라 뒤따르는 멈춤은 `byUser == false` 로 온다 — 뷰모델이 버린다.
            view.mapView.moveCamera(NMFCameraUpdate(scrollTo: NMGLatLng(lat: camera.lat, lng: camera.lng), zoomTo: camera.zoom))
        }

        guard let circle else {
            coordinator.circleOverlay?.mapView = nil
            coordinator.circleOverlay = nil
            return
        }
        let center = NMGLatLng(lat: circle.lat, lng: circle.lng)
        if let overlay = coordinator.circleOverlay {
            overlay.center = center
            overlay.radius = circle.radiusMeters
        } else {
            // 중심과 반경을 넣은 **뒤에** 지도에 붙인다(NMFCircleOverlay.h:22-24, 안드로이드 :573-575).
            let overlay = NMFCircleOverlay(center, radius: circle.radiusMeters)
            overlay.fillColor = Self.fillColor
            overlay.outlineColor = Self.strokeColor
            overlay.outlineWidth = Self.strokeWidth
            overlay.mapView = view.mapView
            coordinator.circleOverlay = overlay
        }
    }

    static func dismantleUIView(_ view: NMFNaverMapView, coordinator: Coordinator) {
        view.mapView.removeCameraDelegate(delegate: coordinator)
        coordinator.circleOverlay?.mapView = nil
        coordinator.circleOverlay = nil
    }
}

/// 네이버 SDK 헤더는 동시성 주석이 없다. 콜백은 메인 스레드에서 오므로 `@preconcurrency` 준수로
/// 메인 액터 격리를 런타임에 확인하게 둔다(`nonisolated(unsafe)` 를 쓰지 않는다).
extension PlacePickerMapView.Coordinator: @preconcurrency NMFMapViewCameraDelegate {

    func mapView(_ mapView: NMFMapView, cameraWillChangeByReason reason: Int, animated: Bool) {
        lastReason = reason
    }

    func mapViewCameraIdle(_ mapView: NMFMapView) {
        let target = mapView.cameraPosition.target
        parent.onIdle(target.lat, target.lng, lastReason == NMFMapChangedByGesture)
        lastReason = NMFMapChangedByDeveloper
    }
}

/// 지도 한가운데 고정 십자(`ic_map_crosshair.xml`). 48 격자에 흰 밑획 6 을 먼저 깔고 잉크 윗획 2.5 를
/// 얹는다 — 흰 도로·초록 공원·파란 물 어느 바닥에서도 한쪽은 보인다. 색은 XML 값 `#4A4038`(판정 기록 13).
/// 가운데를 비워 찍으려는 지점을 가리지 않는다.
struct PlaceCrosshair: View {

    private static let 잉크 = Color(.sRGB, red: 0x4A / 255.0, green: 0x40 / 255.0, blue: 0x38 / 255.0, opacity: 1)

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 48
            var 획 = Path()
            for (from, to) in [(CGPoint(x: 24, y: 6), CGPoint(x: 24, y: 18)),
                               (CGPoint(x: 24, y: 30), CGPoint(x: 24, y: 42)),
                               (CGPoint(x: 6, y: 24), CGPoint(x: 18, y: 24)),
                               (CGPoint(x: 30, y: 24), CGPoint(x: 42, y: 24))] {
                획.move(to: from)
                획.addLine(to: to)
            }
            let 고리 = Path(ellipseIn: CGRect(x: 15, y: 15, width: 18, height: 18))
            let 크기 = CGAffineTransform(scaleX: scale, y: scale)
            let 선 = 획.applying(크기)
            let 원 = 고리.applying(크기)
            context.stroke(선, with: .color(.white), style: StrokeStyle(lineWidth: 6 * scale, lineCap: .round))
            context.stroke(원, with: .color(.white), lineWidth: 6 * scale)
            context.stroke(선, with: .color(Self.잉크), style: StrokeStyle(lineWidth: 2.5 * scale, lineCap: .round))
            context.stroke(원, with: .color(Self.잉크), lineWidth: 2.5 * scale)
        }
    }
}
