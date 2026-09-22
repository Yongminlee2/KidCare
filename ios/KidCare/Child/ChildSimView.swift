import Foundation
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

    private var collector: LocationCollector?
    private var coordinator: TrackingCoordinator?

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
        let coordinator = TrackingCoordinator(
            familyId: launch.familyId,
            uploader: TrailUploader(device: device),
            source: collector
        )
        // 되살아난 직후 오늘 걸어온 길을 되찾는다. 복구한 점은 상태 문서로 안 나간다.
        coordinator.restore()
        // `TrackingCoordinator.init` 이 걸어 둔 것을 덮어쓴다 — 화면을 함께 갱신하려는 것뿐이고
        // 판정 코드는 그대로 부른다.
        collector.onFix = { [weak self] fix in
            coordinator.handle(fix)
            self?.refresh()
        }
        self.collector = collector
        self.coordinator = coordinator

        collector.requestAuthorization()
        collector.start()
        refresh()
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
            Text(verbatim: "수집 모드 \(model.mode.rawValue) · 오늘 점 \(model.pointCount)개")
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
    }
}
#endif
