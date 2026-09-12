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
    /// 마커가 처음 생겼을 때 한 번만 카메라를 옮긴다. 그 뒤에는 부모가 옮긴 자리를 지킨다.
    @Binding var 카메라를_한번_맞췄나: Bool

    final class Coordinator {
        let marker = NMFMarker()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> NMFNaverMapView {
        let view = NMFNaverMapView(frame: .zero)
        view.showLocationButton = false   // 보호자 앱은 위치 권한을 쓰지 않는다(설계서 §1)
        view.showZoomControls = true
        return view
    }

    func updateUIView(_ view: NMFNaverMapView, context: Context) {
        guard let markerAt else {
            context.coordinator.marker.mapView = nil
            return
        }
        let position = NMGLatLng(lat: markerAt.lat, lng: markerAt.lng)
        context.coordinator.marker.position = position
        context.coordinator.marker.mapView = view.mapView

        if !카메라를_한번_맞췄나 {
            view.mapView.moveCamera(NMFCameraUpdate(scrollTo: position))
            DispatchQueue.main.async { 카메라를_한번_맞췄나 = true }
        }
    }
}
