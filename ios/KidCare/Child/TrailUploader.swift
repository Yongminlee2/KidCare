import Foundation
import os

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
    private let namer: PlaceNaming
    /// 한 번의 업로드에서 **새** 이름을 묻는 데 쓸 수 있는 시간. 기본값이 정본 상수다
    /// (`TrailUploader.kt:235`) — 주입 자리를 둔 것은 테스트가 벽시계를 안 기다리게 하기 위해서다.
    private let geocodeBudgetMillis: Int64
    private let logger = Logger(subsystem: "com.kidcare.family", category: "TrailUploader")

    /// 업로드가 겹치는 것을 막는다. 코틀린은 `Mutex.tryLock()` 으로 "이미 도는 중이면 이번은
    /// 건너뛴다"만 한다(`TrailUploader.kt:58-64`) — 대기하면 큐에 쌓였다가 이미 최신인 문서를
    /// 다시 쓰는 헛일이 된다. `@MainActor` 라 `Bool` 플래그 하나면 같은 일을 한다.
    private var uploading = false

    init(
        device: DeviceState = DeviceState(),
        report: @escaping StatusReport = ChildStatusReporter.report,
        saveTrail: @escaping TrailSave = TrailRepository.save,
        uid: @escaping UidProvider = AuthGateway.uid,
        now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        // 기본값이 **실제** 이름표다. 이 인자를 안 넘긴 테스트가 진짜 Nominatim 을 부르는 사고는
        // `PlaceNamer.urlSessionFetch` 가 테스트 프로세스에서 막는다(`PlaceNamer.테스트_중`).
        namer: PlaceNaming = PlaceNamer.shared,
        geocodeBudgetMillis: Int64 = PlaceNamer.geocodeBudgetMillis
    ) {
        self.device = device
        self.report = report
        self.saveTrail = saveTrail
        self.uid = uid
        self.now = now
        self.namer = namer
        self.geocodeBudgetMillis = geocodeBudgetMillis
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
        let segments = await buildSegments(points)
        try await saveTrail(familyId, childUid, TrailDoc(
            dayKey: dayKey,
            points: capped.map { TrailPoint($0) },
            segments: segments,
            updatedAt: nowMillis
        ))
    }

    /// 구간 요약을 만든다. 머무름에는 이름을 붙인다. 정본 `TrailUploader.kt:180-224`.
    ///
    /// **이 함수가 안드로이드에서 '지금 위치 확인'의 대기 시간을 정했다**(그 주석 `:160-166`).
    /// 예전에는 그날의 머무름을 처음부터 차례로 **전부** 인터넷에 물었고(한 곳에 초당 1건 + 최대
    /// 5초), 부모 화면이 수십 초씩 "확인하는 중"에 머물렀다. 아이폰 아이는 명령을 아예 안 듣지만
    /// (설계서 §1) 같은 비용이 **업로드 한 번**에 그대로 걸린다.
    ///
    /// 그래서 순서가 이렇다.
    /// 1. 이미 아는 이름부터 전부 채운다 — 네트워크 없이 즉시.
    /// 2. 모르는 곳만, **가장 최근 머무름부터**, `geocodeBudgetMillis`(3초) 안에서만 묻는다.
    ///    부모가 제일 궁금한 것은 방금 있던 곳이다.
    /// 3. 예산을 넘긴 곳은 이번엔 이름 없이 올라간다. 다음 업로드가 다시 묻고, 한 번 얻은 이름은
    ///    디스크 캐시에 남아 그 뒤로는 즉시 나온다. **재시도 상수를 새로 만들지 않는다**(설계서 §4.11).
    ///
    /// 이동 구간에는 이름을 붙이지 않는다 — "어디서 어디로"가 앞뒤 머무름 이름으로 이미 드러나고,
    /// 이동 중 좌표 하나를 주소로 바꿔봐야 지나가던 길 이름이다.
    ///
    /// 이름은 `lat`/`lng` 가 아니라 `nameLat`/`nameLng` 로 묻는다. 앞의 둘은 지도에 찍는 좌표(단순
    /// 평균)고 뒤의 둘은 오차로 가중한 평균이다 — 도착 순간 튄 점 하나가 머무름 전체에 옆 건물
    /// 이름을 달아버리는 것을 막는다(`SegmentBuilder.kt:163-183`).
    ///
    /// 예산을 재는 시계가 주입받은 `now`(밀리초 벽시계)인 것은 코틀린이 같은 자리에서
    /// `System.currentTimeMillis()` 를 쓰기 때문이다(`:192`).
    private func buildSegments(_ points: [Fix]) async -> [SegmentDoc] {
        let segments = SegmentBuilder.build(points: points)

        // 1. 아는 이름부터. 네트워크를 한 번도 안 탄다(`:183-191`).
        var names = [String](repeating: "", count: segments.count)
        for (index, segment) in segments.enumerated() where segment.type == .stay {
            names[index] = await namer.cachedName(lat: segment.nameLat, lng: segment.nameLng) ?? ""
        }

        // 2. 모르는 곳만 뒤에서 앞으로, 예산 안에서(`:192-204`).
        let deadline = now() + geocodeBudgetMillis
        var asked = 0
        for index in segments.indices.reversed() {
            let segment = segments[index]
            if segment.type != .stay || !names[index].isEmpty { continue }
            let left = deadline - now()
            if left <= 0 { break }
            asked += 1
            // 남은 예산과 제한시간 중 **짧은 쪽**을 건다(`:201-202`).
            let timeout = Double(min(left, Int64(PlaceNamer.timeoutSeconds * 1000))) / 1000
            names[index] = await namer.name(
                lat: segment.nameLat, lng: segment.nameLng,
                timeout: timeout, budgetLeftMillis: left) ?? ""
        }
        let unnamed = segments.indices.filter { segments[$0].type == .stay && names[$0].isEmpty }.count
        if asked > 0 || unnamed > 0 {
            logger.info("머무름 이름: 새로 물음 \(asked)곳 · 이번에 이름 없음 \(unnamed)곳")
        }

        return Self.segmentDocs(segments, names: names)
    }

    /// 구간을 서버 문서로 옮긴다. `names` 가 모자라면 그 자리는 빈 문자열이다 — 이름이 없는 구간을
    /// 보호자 타임라인은 "머무른 곳"으로 표시한다(`SegmentDoc.placeName` 주석).
    nonisolated static func segmentDocs(_ segments: [Segment], names: [String] = []) -> [SegmentDoc] {
        segments.enumerated().map { index, segment in
            SegmentDoc(
                type: segment.type == .stay ? "STAY" : "MOVE",   // 코틀린 `SegmentType.name` 그대로
                startAt: segment.startAt,
                endAt: segment.endAt,
                lat: segment.lat,
                lng: segment.lng,
                distanceMeters: segment.distanceMeters,
                pointCount: segment.pointCount,
                placeName: index < names.count ? names[index] : ""
            )
        }
    }
}
