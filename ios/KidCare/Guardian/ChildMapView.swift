import SwiftUI
import os

/// 지도 화면. 아이의 마지막 위치 마커와 그 날의 경로선을 띄운다.
/// 타임라인·날짜 이동은 이후 Task 다.
///
/// **화면이 뜰 때 한 번만 읽는다 — 구독하지 않는다.** 안드로이드
/// `FamilyRepository.fetchChildStatus`·`TrailRepository` 주석과 같은 이유다: 아이
/// 폰이 더 이상 주기적으로 위치를 올리지 않아 이 문서들은 하루 한 번, 또는 부모가
/// '지금 위치 확인'을 눌렀을 때만 바뀐다. 그런데도 화면이 떠 있는 내내 리스너를
/// 붙들면 Spark 무료 읽기 한도를 공짜로 태운다. 실시간으로 지켜보는 화면은 이후
/// Task 가 '지금 위치 확인' 버튼을 눌렀을 때만 잠깐 붙이는 라이브 세션으로 따로
/// 만들고, 그건 `FamilyRepository.observeChildStatus` 를 그때 다시 쓴다.
struct ChildMapView: View {

    let familyId: String
    let childUid: String?

    @State private var 상태: ChildStatusDoc?
    @State private var 하루기록: TrailDoc?
    @State private var 오류: String?
    @State private var 카메라를_한번_맞췄나 = false

    private static let logger = Logger(subsystem: "com.kidcare.family", category: "ChildMapView")

    var body: some View {
        ZStack(alignment: .top) {
            NaverMapView(
                markerAt: 상태.map { (lat: $0.lat, lng: $0.lng) },
                routeSections: 경로_구간,
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
        .task { await 하루를_읽는다() }
    }

    /// `RouteOverlay.sections` 는 순수 계산이라 `하루기록` 이 바뀔 때마다 다시
    /// 구하면 그만이다 — 따로 저장할 상태가 아니다.
    private var 경로_구간: [RouteSection] {
        guard let 하루기록 else { return [] }
        return RouteOverlay.sections(points: 하루기록.points, segments: 하루기록.segments)
    }

    /// 상태와 그 날 경로를 순서대로 한 번씩 읽는다. 정본은 안드로이드
    /// `MapTimelineFragment.load` — 상태 먼저, 경로 다음(둘 다 성공해야 화면을
    /// 갱신한다), 실패하면 하나의 오류 문구로 합쳐 보여준다(읽기 2회를 넘지 않는다).
    private func 하루를_읽는다() async {
        guard let childUid else { return }
        do {
            let status = try await FamilyRepository.fetchChildStatus(familyId: familyId, childUid: childUid)
            let dayKey = DayPicker.todayKey(
                zone: .current, nowMillis: Int64(Date().timeIntervalSince1970 * 1000)
            )
            let trail = try await TrailRepository.fetch(familyId: familyId, childUid: childUid, dayKey: dayKey)
            상태 = status
            하루기록 = trail
            // 이전 시도가 남긴 오류가 있었다면, 이번에 성공했으니 지운다 — 안
            // 지우면 그 옛 오류 문구가 화면에 계속 남아 방금 받은 정상 상태를
            // 가린다(3차 리뷰 Important).
            오류 = nil
        } catch is CancellationError {
            // 화면이 사라지며 정상 취소된 것이다 — 오류로 취급하지 않는다.
            return
        } catch is TrailRepositoryError {
            // 오프라인이라 그 날 기록을 못 읽었다 — "이 날은 기록이 없어요"로
            // 잘못 보여주면 안 된다(TrailRepository.fetch 주석). 안드로이드가
            // IOException 을 pairing_offline 문구로 옮기는 것과 같은 재사용이다.
            Self.logger.error("하루 기록 읽기 실패(오프라인)")
            오류 = String(localized: "pairing_offline")
        } catch {
            // Firestore/네트워크 원문은 영어라 그대로 보여주면 로캘라이즈 규칙을
            // 어긴다(JoinFamilyView 와 같은 규율). 화면에는 공용 문구만 보여주고,
            // 실제 원인은 로그로만 남긴다.
            Self.logger.error("하루 읽기 실패: \(String(describing: error), privacy: .public)")
            오류 = String(localized: "error_unknown")
        }
    }
}
