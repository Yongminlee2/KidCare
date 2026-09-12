import FirebaseFirestore
import SwiftUI

/// 1단계의 지도 화면. 아이의 마지막 위치 마커 하나만 띄운다.
/// 경로선·타임라인·날짜 이동은 3단계다.
struct ChildMapView: View {

    let familyId: String
    let childUid: String?

    @State private var 상태: ChildStatusDoc?
    @State private var 오류: String?
    @State private var 카메라를_한번_맞췄나 = false
    @State private var 구독: ListenerRegistration?

    var body: some View {
        ZStack(alignment: .top) {
            NaverMapView(
                markerAt: 상태.map { (lat: $0.lat, lng: $0.lng) },
                카메라를_한번_맞췄나: $카메라를_한번_맞췄나
            )
            .ignoresSafeArea()

            if let 오류 {
                Text(오류).padding().background(.thinMaterial).foregroundStyle(.red)
            } else if childUid == nil {
                Text("map_no_child").padding().background(.thinMaterial)
            } else if 상태 == nil {
                Text("map_waiting_first_signal").padding().background(.thinMaterial)
            }
        }
        .onAppear { 구독한다() }
        .onDisappear {
            // 리스너를 안 걷으면 화면을 떠난 뒤에도 읽기가 계속 일어난다. 이 앱은
            // Spark 무료 한도 안에서 도는 것이 전제라 그 누수가 곧 요금이다.
            구독?.remove()
            구독 = nil
        }
    }

    private func 구독한다() {
        guard let childUid, 구독 == nil else { return }
        구독 = FamilyRepository.observeChildStatus(
            familyId: familyId,
            childUid: childUid,
            onChange: { 상태 = $0 },
            onError: { 오류 = $0.localizedDescription }
        )
    }
}
