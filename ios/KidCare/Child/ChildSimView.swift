import FirebaseFirestore
import Foundation
import os
import SwiftUI
import UIKit

#if DEBUG
/// `ChildSimHarness` 로 띄우는 **시뮬레이터 확인 전용 화면**이다(판정 기록 9).
///
/// **문구 키를 만들지 않는다.** 출시 빌드에 없는 화면에 14개 언어 칸을 더하면 번역 빈 칸
/// 기록만 늘어난다. 그래서 이 파일의 글자는 전부 `Text(verbatim:)` 이다.
///
/// **3단계가 `ChildRootView` 를 만들면 이 파일과 `ChildSimHarness` 를 지운다.**
@MainActor
@Observable
final class ChildSimModel {

    private(set) var uid = ""
    private(set) var failure = ""
    private(set) var pointCount = 0
    private(set) var mode: CollectionMode = .fastProbe
    private(set) var lastUploadAt: Int64 = 0
    private(set) var uploading = false

    let launch: ChildSimHarness.Launch

    private(set) var placeCount = 0

    private var collector: LocationCollector?
    private var coordinator: TrackingCoordinator?
    private var placeWatcher: PlaceWatcher?
    private var placesListener: ListenerRegistration?
    private let logger = Logger(subsystem: "com.kidcare.family", category: "ChildSim")

    init(launch: ChildSimHarness.Launch) {
        self.launch = launch
    }

    func start() async {
        guard coordinator == nil else { return }
        do {
            uid = try await AuthGateway.uid()
        } catch {
            failure = "로그인 실패: \(error)"
            return
        }

        let collector = LocationCollector()
        // 시뮬레이터는 배터리를 안 준다 — 값을 넣어 주면 상태 문서에 실제 숫자가 실린다(판정 기록 8).
        let device = launch.battery.map { value in
            DeviceState(battery: { (Float(value) / 100, .unplugged) })
        } ?? DeviceState()
        // **빼면 안 된다.** 좌표가 끊긴 폰이 `.moving` 에 갇혀 하루 종일 조용해진다
        // (`TrackingTicker` 머리 주석). 3단계 `ChildRootView` 도 같은 인자를 넘겨야 한다.
        let ticker = TrackingTicker()
        let coordinator = TrackingCoordinator(
            familyId: launch.familyId,
            uploader: TrailUploader(device: device),
            source: collector,
            ticker: ticker
        )
        // 되살아난 직후 오늘 걸어온 길을 되찾는다. 복구한 점은 상태 문서로 안 나간다.
        coordinator.restore()
        // `TrackingCoordinator.init` 이 걸어 둔 것을 덮어쓴다 — 화면을 함께 갱신하려는 것뿐이고
        // 판정 코드는 그대로 부른다.
        collector.onFix = { [weak self] fix in
            coordinator.handle(fix)
            self?.refresh()
        }
        // 같은 이유로 덮어쓴다 — 좌표 없이 모드가 내려가는 것을 **화면에서 봐야** 확인이 된다.
        ticker.onTick = { [weak self] now in
            coordinator.tick(now)
            self?.refresh()
        }

        // 2단계 배선. 장소 판정은 `LocationCollector` 를 지역 감시자로 쓰고(매니저가 하나여야 한다),
        // 지역 전환 콜백은 그 수집기가 다시 `PlaceWatcher` 로 돌려준다.
        let placeWatcher = PlaceWatcher(stateStore: PlaceStateStore(), monitor: collector)
        collector.placeWatcher = placeWatcher
        // 3번 단계. 안/밖/모름 셋을 그대로 넘긴다 — `Bool` 로 좁히면 "모른다" 갈래가 사라진다.
        coordinator.updateKnownPlace = { [weak placeWatcher] fix in placeWatcher?.isInsideKnownPlace(fix) }
        // 8번 단계. 쓰기는 비동기라 `handle` 이 기다리지 않고, 끝난 뒤 `eventWritten` 으로 돌아와
        // 설계서 §6.4-3(사건 직후 업로드)을 켠다.
        let familyId = launch.familyId
        let childUid = uid
        coordinator.onPlaceFix = { [weak self, weak coordinator, weak placeWatcher] fix in
            Task { @MainActor in
                guard let placeWatcher else { return }
                do {
                    let written = try await placeWatcher.onFix(familyId: familyId, childUid: childUid, fix: fix)
                    if written > 0 { coordinator?.eventWritten(at: fix.at) }
                } catch is CancellationError {
                    // 취소는 실패가 아니다(1단계 `uploadNow` 와 같은 규율).
                } catch {
                    // 이벤트 하나를 못 쓴 것 때문에 위치 수집이 멈추면 안 된다(`PlaceWatcher.kt:110-112`).
                    self?.logger.warning("장소 이벤트 쓰기 실패 — 다음 점에서 다시 한다: \(String(describing: error), privacy: .public)")
                }
                self?.refresh()
            }
        }
        // 부모가 장소를 고친 것을 알 다른 길이 없다 — `sync_rules` 를 못 받기 때문이다(설계서 §7.3).
        // 이 구독이 없으면 지운 장소의 알림이 영영 계속 울린다. 첫 스냅샷이 안드로이드의 `refresh`
        // 자리(= 지역 등록)이고, 그 뒤의 스냅샷이 `sync_rules` 자리다.
        placesListener = PlaceRepository.observePlaces(
            familyId: familyId, childUid: childUid,
            onChange: { [weak self] docs, _ in
                Task { @MainActor in
                    placeWatcher.apply(placeDocs: docs)
                    self?.refresh()
                }
            },
            onError: { [weak self] error in
                self?.logger.warning("장소 구독 실패: \(String(describing: error), privacy: .public)")
            })

        self.collector = collector
        self.coordinator = coordinator
        self.placeWatcher = placeWatcher

        collector.requestAuthorization()
        collector.start()
        refresh()
    }

    /// 리스너를 떼는 길(Global Constraints — 새 Firestore 리스너에는 떼는 길이 있다).
    func stop() {
        placesListener?.remove()
        placesListener = nil
    }

    /// '지금 올리기'. `TrackingCoordinator` 의 업로드 **판정을 건너뛰고** 직접 부른다 —
    /// 15분을 기다리지 않고 경로를 보기 위한 것이고, 판정 코드는 건드리지 않는다(판정 기록 9).
    func uploadNow() async {
        guard let coordinator else { return }
        uploading = true
        await coordinator.uploadNow()
        uploading = false
        refresh()
    }

    private func refresh() {
        guard let coordinator else { return }
        pointCount = coordinator.buffer.points.count
        mode = coordinator.mode
        lastUploadAt = coordinator.lastUploadAt
        placeCount = placeWatcher?.places.count ?? 0
    }
}

struct ChildSimView: View {

    @State private var model: ChildSimModel

    init(launch: ChildSimHarness.Launch) {
        _model = State(initialValue: ChildSimModel(launch: launch))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: "아이 역할 시뮬레이터 확인 (DEBUG 전용)")
                .font(.headline)
            // 이 uid 로 멤버 문서를 심는다(시뮬레이터 확인 절차).
            Text(verbatim: model.uid.isEmpty ? "로그인 중…" : model.uid)
                .font(.system(.title3, design: .monospaced))
                .textSelection(.enabled)
            Text(verbatim: "가족 \(model.launch.familyId)")
            Text(verbatim: "수집 모드 \(model.mode.rawValue) · 오늘 점 \(model.pointCount)개 · 장소 \(model.placeCount)곳")
            Text(verbatim: model.lastUploadAt == 0
                 ? "아직 안 올렸다"
                 : "마지막 업로드 판정 시각 \(model.lastUploadAt)")
            if let battery = model.launch.battery {
                Text(verbatim: "배터리 주입 \(battery)%")
            }
            if !model.failure.isEmpty {
                Text(verbatim: model.failure).foregroundStyle(.red)
            }
            Button {
                Task { await model.uploadNow() }
            } label: {
                Text(verbatim: model.uploading ? "올리는 중…" : "지금 올리기")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.uploading || model.uid.isEmpty)
            Spacer()
        }
        .padding()
        .task { await model.start() }
        .onDisappear { model.stop() }
    }
}
#endif
