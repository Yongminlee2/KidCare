import SwiftUI

/// 장소 탭 목록 판. 정본은 `fragment_place.xml` 목록 판(:16-144)과 `item_place.xml`. 위에서 아래로
/// 상태 줄 → 못 보낸 알림 줄 → 상한 안내 → 장소 목록(비면 마스코트) → 추가 버튼.
struct PlaceView: View {

    let viewModel: PlaceViewModel

    var body: some View {
        NavigationStack {
            목록_판
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: Binding(
                    get: { viewModel.편집_중 },
                    set: { if !$0 { viewModel.뒤로_갔다() } }
                )) {
                    PlaceEditorView(viewModel: viewModel)
                }
        }
        .alert(String(localized: "place_delete_title"), isPresented: Binding(
            get: { viewModel.삭제_확인 != nil },
            set: { if !$0 { viewModel.삭제_확인 = nil } }
        ), presenting: viewModel.삭제_확인) { doc in
            Button(String(localized: "place_delete_confirm"), role: .destructive) {
                Task { await viewModel.삭제를_확인했다(doc) }
            }
            Button(String(localized: "place_delete_cancel"), role: .cancel) {}
        } message: { _ in
            Text(verbatim: viewModel.삭제_확인_문구)
        }
    }

    private var 목록_판: some View {
        VStack(spacing: 0) {
            if let 줄 = viewModel.상태_줄 {
                RuleStateLine(text: 줄)
            }
            if viewModel.pendingSync {
                SyncPendingBar(text: String(localized: "place_sync_pending"),
                               retryTitle: String(localized: "place_sync_retry")) {
                    viewModel.다시_알린다()
                }
            }
            if let 안내 = viewModel.상한_안내 {
                // colorSurfaceVariant 바탕, 좌우 20·위아래 10(:72-81).
                Text(verbatim: 안내)
                    .font(.system(size: 15))
                    .foregroundStyle(KidCarePalette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(KidCarePalette.paperFold)
            }
            ZStack {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.places, id: \.id) { place in
                            PlaceRowView(
                                place: place,
                                onEdit: { viewModel.편집을_연다(place) },
                                onDelete: { viewModel.삭제를_눌렀다(place) }
                            )
                            .padding(.horizontal, 20)
                            .padding(.vertical, 5)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .clipped()
                if let 빈_문구 = viewModel.listLoad.emptyText(isEmpty: viewModel.places.isEmpty,
                                                          loaded: String(localized: "place_empty")) {
                    // 이 탭은 처음 켰을 때 늘 비어 있다 — 눈이 먼저 갈 곳이 있어야 "고장인가"가 아니라
                    // "아직 없구나"로 읽힌다(:96-99).
                    VStack(spacing: 0) {
                        Image("Mascot3D")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 104, height: 104)
                            .opacity(0.9)
                            .accessibilityHidden(true)
                        Text(verbatim: 빈_문구)
                            .font(.system(size: 15))
                            .lineSpacing(3)
                            .foregroundStyle(KidCarePalette.inkSoft)
                            .multilineTextAlignment(.center)
                            .padding(.top, 16)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
            }
            .frame(maxHeight: .infinity)
            RuleAddButton(title: String(localized: "place_add"), enabled: viewModel.추가할_수_있나) {
                viewModel.편집을_연다(nil)
            }
        }
        .background(KidCarePalette.paper)
    }
}

/// 장소 한 장(item_place.xml). 스티커든 글자든 누르면 고치기, 오른쪽 끝은 삭제다.
struct PlaceRowView: View {
    let place: PlaceDoc
    let onEdit: () -> Void
    let onDelete: () -> Void

    /// (진한 색, 옅은 색) 짝 넷 — 순서가 곧 번호다(PlaceAdapter.kt:80-88).
    private static let 스티커_색: [(strong: Color, soft: Color)] = [
        (KidCarePalette.sky, KidCarePalette.skySoft),
        (KidCarePalette.apricot, KidCarePalette.apricotSoft),
        (KidCarePalette.grass, KidCarePalette.grassSoft),
        (KidCarePalette.berryInk, KidCarePalette.berrySoft),
    ]

    var body: some View {
        let 색 = Self.스티커_색[PlaceText.stickerIndex(place)]
        HStack(spacing: 0) {
            Button(action: onEdit) {
                HStack(spacing: 0) {
                    Text(verbatim: PlaceText.stickerLetter(place))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(색.strong)
                        .frame(width: 40, height: 40)
                        .background(색.soft, in: Circle())
                        .padding(.trailing, 11)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: place.name)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(KidCarePalette.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(verbatim: PlaceText.rowDetail(place))
                            .font(.system(size: 13))
                            .foregroundStyle(KidCarePalette.inkSoft)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
                // 알림을 둘 다 꺼둔 장소는 쉬는 것 — 흐리게만(PlaceAdapter.kt:49-52).
                .opacity(place.notifyEnter || place.notifyExit ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            RowDeleteButton(label: String(localized: "place_delete"), action: onDelete)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .ruleCard()
    }
}
