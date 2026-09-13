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
    /// 상태 카드에 쓸 아이 이름. 못 읽었으면(또는 아직 읽는 중이면) 안드로이드
    /// `selectedChildLabelText()` 의 기본값과 같은 자리로 물러난다.
    @State private var 아이_이름 = String(localized: "child_default_name")
    /// [FamilyRepository.serverNow] 로 잰 "지금". 상태 카드의 "N분 전" 계산 기준이다
    /// — 기기 시계를 쓰면 부모 폰이 뒤처진 만큼 음수 경과가 나온다(brief 경고).
    /// 아직 못 쟀으면 기기 시계로 시작한다 — 상태 카드가 첫 프레임에 값 없이 뜨는
    /// 것보다 오차 있는 값이라도 있는 편이 낫다.
    @State private var 서버기준_지금 = Int64(Date().timeIntervalSince1970 * 1000)

    private static let logger = Logger(subsystem: "com.kidcare.family", category: "ChildMapView")

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NaverMapView(
                    markerAt: 상태.map { (lat: $0.lat, lng: $0.lng) },
                    routeSections: 경로_구간,
                    카메라를_한번_맞췄나: $카메라를_한번_맞췄나
                )
                .ignoresSafeArea()

                if childUid != nil {
                    StatusCardView(childName: 아이_이름, status: 상태, nowMillis: 서버기준_지금)
                }

                if let 오류 {
                    Text(오류).padding().background(.thinMaterial).foregroundStyle(.red)
                } else if childUid == nil {
                    Text("map_no_child").padding().background(.thinMaterial)
                } else if 상태 == nil {
                    Text("map_waiting_first_signal").padding().background(.thinMaterial)
                }
            }

            타임라인_패널
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

    /// 오늘 하루를 머무름·이동으로 요약한 목록. `Timeline.timelineRows` 와 마찬가지로
    /// 순수 계산이라 `하루기록` 이 바뀔 때마다 다시 구한다.
    private var 타임라인_행: [TimelineRow] {
        guard let 하루기록 else { return [] }
        return Timeline.timelineRows(from: 하루기록.segments, zone: .current)
    }

    /// 지도 아래 타임라인 패널. 정본은 안드로이드 `fragment_map_timeline.xml` 의
    /// `timelinePanel` + `MapTimelineFragment.renderTimeline`(:1011)·
    /// `renderTimelineEmpty`(:1035). 안드로이드는 접었다 펼 수 있는 바텀시트지만,
    /// 이 Task 의 범위는 "행이 보인다/빈 날엔 빈 상태가 보인다"까지다 — 크기
    /// 조절·접기는 다루지 않는다.
    private var 타임라인_패널: some View {
        Group {
            if 타임라인_행.isEmpty {
                Text(String(localized: "timeline_empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(타임라인_행, id: \.segmentIndex) { row in
                            TimelineRowView(row: row)
                            Divider().padding(.leading, 50)
                        }
                    }
                }
            }
        }
        .frame(height: 220)
        .background(.regularMaterial)
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
            // 어긴다(JoinFamilyView 와 같은 규율). `errorMessage` 가 코드별로 이미
            // 있는 문구(서버 설정 미완료, 오프라인, 재로그인)로 좁혀주므로 여기서는
            // 그 결과만 화면에 보여주고, 실제 원인은 로그로만 남긴다.
            Self.logger.error("하루 읽기 실패: \(String(describing: error), privacy: .public)")
            오류 = errorMessage(error)
        }

        // 상태 카드는 하루 기록과 실패를 공유하지 않는다 — 이름 하나, 서버 시각
        // 하나를 못 구했다고 지도·타임라인까지 오류로 덮으면 그 실패와 무관한
        // 정보까지 숨는다. 각자 실패해도 카드가 물러날 기본값(아이_이름 초기값,
        // 기기 시계로 시작한 서버기준_지금)을 이미 갖고 있어 조용히 넘어간다.
        async let 멤버_작업 = try? FamilyRepository.fetchMember(familyId: familyId, uid: childUid)
        async let 서버시각_작업 = try? FamilyRepository.serverNow(familyId: familyId, uid: AuthGateway.currentUid())
        let 멤버 = await 멤버_작업
        let 서버시각 = await 서버시각_작업
        if let name = 멤버?.displayName, !name.isEmpty { 아이_이름 = name }
        if let 서버시각 { 서버기준_지금 = 서버시각 }
    }
}
