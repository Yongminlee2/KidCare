import SwiftUI

/// 지도 화면. 아이의 마지막 위치 마커와 그 날의 경로선, 그 날의 타임라인을 띄운다.
/// `◀ 오늘 ▶` 로 어제·그제를 넘겨볼 수 있다.
///
/// **화면이 뜰 때 한 번만 읽는다 — 구독하지 않는다.** 안드로이드
/// `FamilyRepository.fetchChildStatus`·`TrailRepository` 주석과 같은 이유다: 아이
/// 폰이 더 이상 주기적으로 위치를 올리지 않아 이 문서들은 하루 한 번, 또는 부모가
/// '지금 위치 확인'을 눌렀을 때만 바뀐다. 그런데도 화면이 떠 있는 내내 리스너를
/// 붙들면 Spark 무료 읽기 한도를 공짜로 태운다. 실시간으로 지켜보는 화면은 이후
/// Task 가 '지금 위치 확인' 버튼을 눌렀을 때만 잠깐 붙이는 라이브 세션으로 따로
/// 만들고, 그건 `FamilyRepository.observeChildStatus` 를 그때 다시 쓴다.
///
/// **상태는 이 뷰가 아니라 `MapViewModel` 이 들고 있다.** Task 4 가 옮겼다 — 이유는
/// `MapViewModel` 타입 주석 참고. 이 뷰는 뷰모델을 그리기만 한다.
struct ChildMapView: View {

    let familyId: String
    let childUid: String?

    @State private var viewModel: MapViewModel
    /// 마커가 처음 생겼을 때 카메라를 한 번만 맞추는 플래그. 지도 렌더링(`NaverMapView`)
    /// 만의 관심사라 `MapViewModel` 로 옮기지 않았다 — 날짜를 넘겨도, 다시 읽어도
    /// 상관없이 이 화면이 떠 있는 동안에는 계속 지켜야 하는 뷰 쪽 그리기 상태다.
    @State private var 카메라를_한번_맞췄나 = false

    init(familyId: String, childUid: String?) {
        self.familyId = familyId
        self.childUid = childUid
        _viewModel = State(initialValue: MapViewModel(familyId: familyId, childUid: childUid))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NaverMapView(
                    markerAt: viewModel.상태.map { (lat: $0.lat, lng: $0.lng) },
                    routeSections: viewModel.경로_구간,
                    카메라를_한번_맞췄나: $카메라를_한번_맞췄나
                )
                .ignoresSafeArea()

                if childUid != nil {
                    StatusCardView(childName: viewModel.아이_이름, status: viewModel.상태, nowMillis: viewModel.서버기준_지금)
                }

                if let 오류 = viewModel.오류 {
                    Text(오류).padding().background(.thinMaterial).foregroundStyle(.red)
                } else if childUid == nil {
                    Text("map_no_child").padding().background(.thinMaterial)
                } else if viewModel.상태 == nil {
                    Text("map_waiting_first_signal").padding().background(.thinMaterial)
                }
            }

            타임라인_패널
        }
        // `.task` 는 화면이 사라지면 스스로 취소한다 — 구독이 아니라 한 번의
        // 읽기라 onDisappear 에서 따로 걷어낼 리스너가 없다.
        .task { await viewModel.하루를_읽는다() }
    }

    /// 지도 아래 타임라인 패널. 정본은 안드로이드 `fragment_map_timeline.xml` 의
    /// `timelinePanel` + `MapTimelineFragment.renderTimeline`(:1011)·
    /// `renderTimelineEmpty`(:1035). 안드로이드는 접었다 펼 수 있는 바텀시트지만,
    /// 이 Task 의 범위는 "행이 보인다/빈 날엔 빈 상태가 보인다"까지다 — 크기
    /// 조절·접기는 다루지 않는다.
    private var 타임라인_패널: some View {
        VStack(spacing: 0) {
            날짜_이동_바

            Group {
                if viewModel.타임라인_행.isEmpty {
                    Text(String(localized: "timeline_empty"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.타임라인_행, id: \.segmentIndex) { row in
                                TimelineRowView(row: row)
                                Divider().padding(.leading, 50)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 220)
        .background(.regularMaterial)
    }

    /// `◀ 오늘 ▶` 날짜 이동 줄. 정본은 안드로이드 `fragment_map_timeline.xml` 의
    /// `prev_day_button`/`day_header`/`next_day_button` + `renderDayHeader`(:867).
    /// 접근성 라벨(`day_prev`/`day_next`)은 안드로이드가 이미 쓰던 키를 그대로
    /// 재사용한다 — 새 키를 만들지 않는다(brief).
    private var 날짜_이동_바: some View {
        HStack {
            Button {
                Task { await viewModel.이전_날로() }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("day_prev"))

            Spacer()

            Text(viewModel.날짜_헤더_문구)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)

            Spacer()

            Button {
                Task { await viewModel.다음_날로() }
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .disabled(!viewModel.다음_날로_갈_수_있는가)
            .accessibilityLabel(Text("day_next"))
        }
        .padding(.horizontal, 10)
        .buttonStyle(.plain)
    }
}
