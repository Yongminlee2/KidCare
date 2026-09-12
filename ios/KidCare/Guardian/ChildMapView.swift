import SwiftUI
import os

/// 1단계의 지도 화면. 아이의 마지막 위치 마커 하나만 띄운다.
/// 경로선·타임라인·날짜 이동은 3단계다.
///
/// **화면이 뜰 때 한 번만 읽는다 — 구독하지 않는다.** 안드로이드
/// `FamilyRepository.fetchChildStatus` 주석과 같은 이유다: 아이 폰이 더 이상
/// 주기적으로 위치를 올리지 않아 이 문서는 하루 한 번, 또는 부모가 '지금 위치
/// 확인'을 눌렀을 때만 바뀐다. 그런데도 화면이 떠 있는 내내 리스너를 붙들면
/// Spark 무료 읽기 한도를 공짜로 태운다. 실시간으로 지켜보는 화면은 Phase 3가
/// '지금 위치 확인' 버튼을 눌렀을 때만 잠깐 붙이는 라이브 세션으로 따로 만들고,
/// 그건 `FamilyRepository.observeChildStatus` 를 그때 다시 쓴다.
struct ChildMapView: View {

    let familyId: String
    let childUid: String?

    @State private var 상태: ChildStatusDoc?
    @State private var 오류: String?
    @State private var 카메라를_한번_맞췄나 = false

    private static let logger = Logger(subsystem: "com.kidcare.family", category: "ChildMapView")

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
        // `.task` 는 화면이 사라지면 스스로 취소한다 — 구독이 아니라 한 번의
        // 읽기라 onDisappear 에서 따로 걷어낼 리스너가 없다.
        .task { await 상태를_읽는다() }
    }

    private func 상태를_읽는다() async {
        guard let childUid else { return }
        do {
            상태 = try await FamilyRepository.fetchChildStatus(familyId: familyId, childUid: childUid)
            // 이전 시도가 남긴 오류가 있었다면, 이번에 성공했으니 지운다 — 안
            // 지우면 그 옛 영어 원문/오류 문구가 화면에 계속 남아 방금 받은 정상
            // 상태를 가린다(3차 리뷰 Important).
            오류 = nil
        } catch is CancellationError {
            // 화면이 사라지며 정상 취소된 것이다 — 오류로 취급하지 않는다.
            return
        } catch {
            // Firestore/네트워크 원문은 영어라 그대로 보여주면 로캘라이즈 규칙을
            // 어긴다(JoinFamilyView 와 같은 규율). 화면에는 공용 문구만 보여주고,
            // 실제 원인은 로그로만 남긴다.
            Self.logger.error("아이 상태 읽기 실패: \(String(describing: error), privacy: .public)")
            오류 = String(localized: "error_unknown")
        }
    }
}
