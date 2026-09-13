import SwiftUI

/// 장소 편집 판. 정본은 `fragment_place.xml` 편집 판(:146-364) — 제목, 이름, 지도(십자·원), 반경, 알림
/// 스위치 둘, 진행 줄, 취소·저장. 안쪽 여백 16(:159). 시스템 뒤로 버튼이 늘 보인다 — 지도가 가장자리
/// 밀기를 삼켜도 이 버튼으로 나갈 수 있다(Global Constraints).
struct PlaceEditorView: View {

    let viewModel: PlaceViewModel

    /// 지도에 손가락이 닿아 있는 동안 스크롤을 잠근다 — 세로로 끌면 스크롤이 먼저 먹어 지도를 위아래로
    /// 못 옮기던 문제의 자리(PlaceFragment.kt:238-246, 판정 기록 8).
    @State private var 지도를_만지는_중 = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: viewModel.편집기_제목)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(KidCarePalette.ink)

                항목_제목("place_editor_name_label").padding(.top, 20)
                // Widget.KidCare.TextField — 외곽선 상자, 모서리 12, 떠오르는 이름표 'place_editor_name_hint'(xml :174-190).
                KidCareOutlinedField(
                    label: "place_editor_name_hint",
                    text: Binding(get: { viewModel.이름 }, set: { viewModel.이름을_바꾼다($0) })
                )
                .padding(.top, 8)
                if viewModel.이름_경고 {
                    Text("place_editor_name_required")
                        .font(.system(size: 13))
                        .foregroundStyle(KidCarePalette.berryInk)
                        .padding(.top, 6)
                }

                항목_제목("place_editor_map_label").padding(.top, 20)
                Text("place_editor_map_hint")
                    .font(.system(size: 13))
                    .foregroundStyle(KidCarePalette.inkSoft)
                    .padding(.top, 4)
                if viewModel.지도_안내가_보이나 {
                    Text("place_editor_no_child_location")
                        .font(.system(size: 13))
                        .foregroundStyle(KidCarePalette.berryInk)
                        .padding(.top, 4)
                }
                ZStack {
                    PlacePickerMapView(
                        camera: viewModel.카메라_요청,
                        circle: viewModel.원,
                        onTouchDown: { lat, lng in
                            지도를_만지는_중 = true
                            viewModel.지도를_만졌다(centerLat: lat, centerLng: lng)
                        },
                        onTouchEnd: { 지도를_만지는_중 = false },
                        onIdle: { lat, lng, byUser in
                            viewModel.지도가_멈췄다(centerLat: lat, centerLng: lng, 사람이_옮겼나: byUser)
                        }
                    )
                    // 십자는 누를 수 없어야 한다 — 정확히 좌표를 정하는 자리에서 터치를 먹으면 안 된다(:228-230).
                    PlaceCrosshair()
                        .frame(width: 48, height: 48)
                        .allowsHitTesting(false)
                        .accessibilityLabel(Text("place_editor_map_hint"))
                }
                .frame(height: 260)
                .clipped()
                .padding(.top, 8)

                항목_제목("place_editor_radius_label").padding(.top, 20)
                // 슬라이더 손잡이 위 말풍선은 손가락에 가려서 숫자로도 적는다(:258-259).
                Text(verbatim: viewModel.반경_문구)
                    .font(.system(size: 17))
                    .foregroundStyle(KidCarePalette.ink)
                    .padding(.top, 4)
                // M3 슬라이더(막대 손잡이, 눈금) — 100~1000 m, 50 m 눈금(xml :267-274). VoiceOver 는 위아래 쓸기로 한 눈금씩.
                KidCareSlider(
                    value: Binding(get: { viewModel.반경 }, set: { viewModel.반경 = $0 }),
                    range: PlaceViewModel.minRadiusMeters...PlaceViewModel.maxRadiusMeters,
                    step: PlaceViewModel.radiusStepMeters,
                    accessibilityLabel: "place_editor_radius_label",
                    accessibilityValue: viewModel.반경_문구
                )
                .padding(.top, 4)

                항목_제목("place_editor_notify_label").padding(.top, 12)
                Toggle(isOn: Binding(get: { viewModel.도착_알림 }, set: { viewModel.도착_알림 = $0 })) {
                    Text("place_editor_notify_enter").font(.system(size: 17)).foregroundStyle(KidCarePalette.ink)
                }
                .tint(KidCarePalette.sky)
                .frame(minHeight: 52)
                .padding(.top, 8)
                Toggle(isOn: Binding(get: { viewModel.나섬_알림 }, set: { viewModel.나섬_알림 = $0 })) {
                    Text("place_editor_notify_exit").font(.system(size: 17)).foregroundStyle(KidCarePalette.ink)
                }
                .tint(KidCarePalette.sky)
                .frame(minHeight: 52)
                if viewModel.알림_없음_안내가_보이나 {
                    Text("place_editor_notify_none_hint")
                        .font(.system(size: 13))
                        .foregroundStyle(KidCarePalette.inkSoft)
                        .padding(.top, 4)
                }

                HStack(spacing: 10) {
                    if viewModel.저장_중 {
                        ProgressView().frame(width: 20, height: 20)
                    }
                    if let 줄 = viewModel.편집_줄 {
                        Text(verbatim: 줄).font(.system(size: 15)).foregroundStyle(KidCarePalette.ink)
                    }
                }
                .padding(.top, 20)

                HStack(spacing: 8) {
                    // 장소 편집의 취소는 글자 버튼이다(:346-352 — 예약 편집과 다르다, XML 그대로).
                    Button { viewModel.취소를_눌렀다() } label: {
                        Text("place_editor_cancel")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(KidCarePalette.sky)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { Task { await viewModel.저장을_눌렀다() } } label: {
                        Text("place_editor_save")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(KidCarePalette.onAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(KidCarePalette.sky, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .disabled(viewModel.저장_중)
                .opacity(viewModel.저장_중 ? 0.38 : 1)
                .padding(.top, 16)
            }
            .padding(16)
        }
        .scrollDisabled(지도를_만지는_중)
        .clipped()
        .background(KidCarePalette.paper)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func 항목_제목(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(KidCarePalette.ink)
    }
}
