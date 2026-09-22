import Foundation

/// 한 번의 업로드가 하는 일 — **쓰기 두 번**(상태 문서 1 + 하루 문서 1)이다.
/// `TrackingCoordinator` 가 판정만 하고 실제 쓰기는 이쪽에 맡긴다. 테스트는 세는 가짜를 넣는다.
@MainActor
protocol ChildUploading: AnyObject {
    /// - Parameter dayKey: 오늘 확보한 점이 하나도 없으면 `nil` — 그때도 **상태 문서는 쓴다**.
    ///   안드로이드도 `uploadNow` 가 `reporter.report` 를 먼저 부르고 `TrailUploader.upload` 안에서
    ///   "오늘 확보한 점이 하나도 없다"를 따로 건너뛴다(`TrailUploader.kt:125-129`).
    func upload(familyId: String, fix: Fix, points: [Fix], dayKey: String?) async throws
}

/// 오늘 점을 하루 문서 하나로 올린다. 정본은 안드로이드 `child/TrailUploader.kt` 의
/// `upload`/`uploadLocked`/`buildSegments` 와 `TrackingService.uploadNow()`(:719-729)다.
///
/// 메모리 버퍼와 파일은 `TrailBuffer`·`TrailStore` 가 들고 있다(코틀린은 이 클래스가 함께 들고
/// 있지만, 아이폰에서는 버퍼를 `TrackingCoordinator` 가 화면에 보여줘야 해서 갈랐다).
@MainActor
final class TrailUploader: ChildUploading {

    typealias StatusReport = (String, String, ChildStatusWrite) async throws -> Void
    typealias TrailSave = (String, String, TrailDoc) async throws -> Void
    typealias UidProvider = () async throws -> String

    private let device: DeviceState
    private let report: StatusReport
    private let saveTrail: TrailSave
    private let uid: UidProvider
    private let now: () -> Int64

    /// 업로드가 겹치는 것을 막는다. 코틀린은 `Mutex.tryLock()` 으로 "이미 도는 중이면 이번은
    /// 건너뛴다"만 한다(`TrailUploader.kt:58-64`) — 대기하면 큐에 쌓였다가 이미 최신인 문서를
    /// 다시 쓰는 헛일이 된다. `@MainActor` 라 `Bool` 플래그 하나면 같은 일을 한다.
    private var uploading = false

    init(
        device: DeviceState = DeviceState(),
        report: @escaping StatusReport = ChildStatusReporter.report,
        saveTrail: @escaping TrailSave = TrailRepository.save,
        uid: @escaping UidProvider = AuthGateway.uid,
        now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.device = device
        self.report = report
        self.saveTrail = saveTrail
        self.uid = uid
        self.now = now
    }

    func upload(familyId: String, fix: Fix, points: [Fix], dayKey: String?) async throws {
        guard !uploading else { return }
        uploading = true
        defer { uploading = false }

        let childUid = try await uid()
        let snapshot = device.snapshot()
        let nowMillis = now()
        try await report(familyId, childUid, ChildStatusWrite(
            fix: fix,
            battery: snapshot.batteryPercent,
            charging: snapshot.charging,
            network: snapshot.network,
            lastSeenAt: nowMillis
        ))

        guard let dayKey else { return }   // 오늘 확보한 점이 하나도 없다(`TrailUploader.kt:126-129`)
        // 상한을 넘으면 하루 전체의 경로 모양을 보존해 대표점을 고른다(`TrailCodec.maxPoints` 주석).
        let capped = TrailCodec.capped(points)
        // **구간은 솎기 전 원본으로 계산한다**(`TrailUploader.kt:135-138`, 설계서 §6.3).
        // 서버 상한에 맞춘 뒤 계산하면 머무름 경계점이 빠질 수 있다.
        let segments = Self.buildSegments(points)
        try await saveTrail(familyId, childUid, TrailDoc(
            dayKey: dayKey,
            points: capped.map { TrailPoint($0) },
            segments: segments,
            updatedAt: nowMillis
        ))
    }

    /// **머무름에 이름을 안 붙인다.** 역지오코딩(`Child/PlaceNamer`)은 2단계다 — 그때까지
    /// `placeName` 은 전부 빈 문자열이고, 보호자 타임라인은 그 구간을 "머무른 곳"으로 표시한다
    /// (`SegmentDoc.placeName` 주석의 이미 정해진 동작). 2단계가 이 함수 안에서
    /// `GEOCODE_BUDGET_MILLIS`(3초, `TrailUploader.kt:235`) 예산으로 이름을 채운다.
    nonisolated static func buildSegments(_ points: [Fix]) -> [SegmentDoc] {
        SegmentBuilder.build(points: points).map {
            SegmentDoc(
                type: $0.type == .stay ? "STAY" : "MOVE",   // 코틀린 `SegmentType.name` 그대로
                startAt: $0.startAt,
                endAt: $0.endAt,
                lat: $0.lat,
                lng: $0.lng,
                distanceMeters: $0.distanceMeters,
                pointCount: $0.pointCount,
                placeName: ""
            )
        }
    }
}
