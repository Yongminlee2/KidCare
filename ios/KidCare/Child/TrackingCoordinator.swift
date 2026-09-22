import Foundation

/// 점 하나가 들어왔을 때의 순서를 정한다. 정본은 안드로이드 `TrackingService.handle()`(:532-699).
/// **순서가 곧 계약이다** — 설계서 §6.1 의 10단계 그대로다.
///
/// `@MainActor` 인 이유는 `LocationCollector` 와 같다 — 버퍼를 만지는 스레드가 하나로 유지돼
/// 잠금이 필요 없어진다(`TrailUploader.kt:91-93`).
///
/// **이 단계에는 명령이 하나도 없다.** '지금 위치 확인'·실시간 보기·명령 컬렉션 구독이 전부 범위
/// 밖이라(계획서 "다루지 않는 것") 안드로이드의 `handleLiveFix`(:571)와 `liveTracking` 갈래는
/// 옮기지 않았다.
@MainActor
final class TrackingCoordinator {

    /// `TrackingService.kt:905`.
    static let stayAnchorIntervalMillis: Int64 = 5 * 60_000
    /// `:912`.
    static let coordinateKickWindowMillis: Int64 = 5 * 60_000
    /// 설계서 §6.4. 아무리 잦아도 이보다 자주 안 올린다.
    static let uploadMinIntervalMillis: Int64 = 15 * 60_000
    /// 설계서 §6.4. 안드로이드의 `SAFETY_UPLOAD_INTERVAL_MILLIS`(24시간, `:902`)를 내린 값이다 —
    /// 안드로이드는 그 사이 '지금 위치 확인' 명령으로 언제든 최신을 받을 수 있지만 아이폰은 그 통로가 없다.
    static let uploadIdleIntervalMillis: Int64 = 4 * 60 * 60_000
    /// 설계서 §6.4-3. 한 점에서 사건이 둘 이상 날 수 있다(`known-issues.md` 21번).
    static let uploadEventMinGapMillis: Int64 = 60_000

    let familyId: String
    let buffer: TrailBuffer

    private let zone: TimeZone
    private let store: TrailStore
    private let uploader: ChildUploading
    private weak var source: LocationSource?
    /// 좌표가 없을 때 시계를 미는 유일한 입력([tick]). **이 객체가 갖고 있다** — 다른 주인이 없다.
    private let ticker: Ticking?

    private(set) var lastFix: Fix?
    private(set) var lastTrailFix: Fix?
    /// **메모리에만 둔다**(아이 1단계 판정 기록 15, `TrackingService.kt:81-89`). 프로세스가 다시
    /// 뜨면 0 이 되어 업로드가 한 번 더 나가는데 그게 손해가 아니라 이득이다 — 되살아난 직후
    /// 부모가 최신을 한 번 받는다. 그리고 이 성질이 설계서 §10.1 의 "페어링 뒤 첫 좌표에서
    /// 업로드를 한 번 강제"를 공짜로 만든다(그 한 번이 `platform: "ios"` 를 심는다).
    private(set) var lastUploadAt: Int64 = 0
    private(set) var lastUploadedFix: Fix?
    private(set) var coordinateKickExpiresAt: Int64?

    private let detector = AdaptiveMovementDetector()
    private var insideKnownPlace = false         // 2단계가 켠다
    private var slowProbeSince: Int64?
    private var lastRouteWasMoving = false
    private var forceNextStayPoint = true
    /// 마지막으로 **들어온** 점의 시각. `lastFix` 와 다르다 — 거절된 점도 시계를 민다.
    /// [tick] 이 "좌표가 얼마나 끊겼나"를 재는 기준이다.
    private var lastHandledAt: Int64 = 0
    /// 이 코디네이터가 마지막으로 본 시각. 좌표([handle])와 시계([tick])가 **함께** 민다.
    /// [mode] 가 "지금이 언제인가"로 쓴다 — 좌표가 끊겨도 정지 승격 시계가 흘러야 한다.
    private var clockAt: Int64 = 0

    /// 마지막으로 시작한 업로드. 화면(`ChildSimView`)이 "올리는 중"을 알고, 테스트가 기다린다.
    private(set) var uploadTask: Task<Void, Never>?

    /// 2단계·3단계가 잇는 자리. **지금 자리에 둬야** 나중에 순서가 안 틀어진다(1단계 판정 기록 7).
    var onCondition: ((Int64) -> Void)?          // 1번 (3단계: ConditionWatcher)
    /// 3번. 2단계가 `PlaceWatcher.isInsideKnownPlace(fix)` 를 잇는다 — 등록 장소 안이면 `true`,
    /// 밖이면 `false`, **판단할 재료가 없으면 `nil`**(그때는 아무것도 안 바꾼다,
    /// `TrackingService.kt:521`). 1단계에서는 훅 자체가 nil 이라 늘 바깥이다.
    var updateKnownPlace: ((Fix) -> Bool?)?
    var onPlaceFix: ((Fix) -> Void)?             // 8번 (2단계: PlaceWatcher.onFix)

    init(
        familyId: String,
        zone: TimeZone = .current,
        buffer: TrailBuffer = TrailBuffer(),
        store: TrailStore = TrailStore(),
        uploader: ChildUploading = TrailUploader(),
        source: LocationSource? = nil,
        ticker: Ticking? = nil
    ) {
        self.familyId = familyId
        self.zone = zone
        self.buffer = buffer
        self.store = store
        self.uploader = uploader
        self.source = source
        self.ticker = ticker
        source?.onFix = { [weak self] fix in self?.handle(fix) }
        // **진짜 파이프라인은 이 인자를 반드시 넘겨야 한다**(1단계는 `ChildSimView`, 3단계는
        // `ChildRootView`). 안 넘기면 좌표가 끊긴 폰이 `.moving` 에 갇힌다 — 그 고리를 푸는
        // 입력이 이것 하나뿐이다([TrackingTicker] 머리 주석). 기본값이 nil 인 것은 테스트가
        // 시계를 **직접** 돌리기 위해서다(벽시계를 기다리는 테스트를 만들지 않는다).
        ticker?.onTick = { [weak self] now in self?.tick(now) }
        ticker?.start()
    }

    /// 지금 걸려야 할 수집 모드. 화면과 테스트가 읽는다.
    var mode: CollectionMode {
        CollectionMode.select(
            state: detector.state,
            insideKnownPlace: insideKnownPlace,
            slowProbeSince: slowProbeSince,
            now: clockAt
        )
    }

    /// 프로세스가 죽었다 살아난 뒤 오늘 걸어온 길을 되찾는다. 뜰 때 딱 한 번 부른다.
    ///
    /// 되찾은 마지막 점은 **경로 필터의 기준점**(`lastTrailFix`)으로만 쓴다 —
    /// **`lastFix` 에는 절대 넣지 않는다.** 넣으면 그 몇 시간 전 점으로 상태 문서가 써지고
    /// 서버 시각이 "방금"으로 찍힌다(`TrackingService.kt:713-717`).
    func restore(nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        lastTrailFix = buffer.restore(store: store, zone: zone, nowMillis: nowMillis)
    }

    func handle(_ fix: Fix, eventJustWritten: Bool = false) {
        // 1. 상태 검사 — 점을 버릴지와 무관하게 **먼저** 한다(:533-537). 아래 판정에서 걸러지는
        //    점이라도 "이 폰이 아직 살아 있고 지금 배터리가 이렇다"는 사실은 똑같이 유효하다.
        onCondition?(fix.at)
        lastHandledAt = fix.at
        clockAt = max(clockAt, fix.at)

        // 아이폰의 `!activityMoving` 자리다. 활동 인식이 없어 '정지 모드'가 그 비트를 대신한다
        // (설계서 §4.8, 계획서 판정 기록의 STILL_ESCALATE_MILLIS). **판정기를 돌리기 전에** 읽는다
        // — 안드로이드의 `activityMoving` 도 이 fix 가 오기 전의 값이다.
        let wasStill = CollectionMode.select(
            state: detector.state,
            insideKnownPlace: insideKnownPlace,
            slowProbeSince: slowProbeSince,
            now: fix.at
        ) == .still

        // 2. 시계 역행 감지 → 기준점 초기화(:552-568). 안 하면 `elapsed <= 0` 이라 그 뒤의 모든
        //    정상 점이 영영 REJECT_IMPOSSIBLE 로 막히는데, 로그도 조용해서 알아챌 방법이 없다.
        if let previous = lastFix, fix.at < previous.at {
            // 시계가 거꾸로 갔으면 [tick] 이 밀어 둔 시각도 함께 버린다 — 안 그러면 [mode] 가
            // 미래를 '지금'으로 읽어 정지 승격이 한 주기 이르게 걸린다.
            clockAt = fix.at
            lastFix = nil
            lastTrailFix = nil
            detector.reset()
            slowProbeSince = nil
            lastRouteWasMoving = false
            forceNextStayPoint = true
            // `coordinateKickExpiresAt` 은 **일부러 안 건드린다** — 안드로이드도 여기서 안 지운다
            // (:559-568). 시간이 제자리로 오면 아래 6번이 알아서 만료시킨다.
        }

        // 3. 등록 장소 안/밖 갱신 → 모드 바꿈(:570 → :519-530). 1단계에서는 훅이 nil 이라 늘 밖이다.
        _ = updateKnownPlaceSampling(fix)

        // 4. 판정기(:583). 안드로이드의 `movementEligible`(활동 인식 || 지오펜스 이탈)은 아이폰에
        //    입력이 없어 **언제나 참**이다 — 판정기 하나로 도는 갈래는 안드로이드에서도 활동 인식
        //    권한이 없을 때 이미 도는 길이다(`AdaptiveMovementDetector` 머리 주석).
        let update = detector.onFix(fix)
        slowProbeSince = (update.state == .slowProbe) ? (slowProbeSince ?? fix.at) : nil
        // **수집기에 미는 것은 여기가 아니다.** 5·6번이 판정기와 `slowProbeSince` 를 더 바꾸므로
        // 여기서 밀면 수집기가 한 박자 옛 모드를 들고 다음 좌표까지(정지 주기면 60초) 기다린다.
        // 안드로이드는 `onActivityMovingChanged(true)` 가 **그 자리에서** `collector` 를 다시 건다
        // (`TrackingService.kt:473-477`) — 그 "그 자리"가 6번 뒤다. 아래 `pushMode` 가 그것이다.

        // 5. MOVING 이면 경로점 선별, 아니면 5분 기준점(:586-615).
        let routeMoving = update.state == .moving
        if !update.promotionBuffer.isEmpty {
            // 이동 확정 **전**의 점들이다. 이걸 빼면 출발 부분이 통째로 잘린다(:588-590).
            recordMovementFixes(update.promotionBuffer)
        }
        if routeMoving {
            recordMovementFixes([fix])
            forceNextStayPoint = false
            // 좌표 변위로 켠 이동 확인이 실제 이동으로 이어졌다 — 움직이는 동안 계속 연장한다(:595-598).
            if coordinateKickExpiresAt != nil {
                coordinateKickExpiresAt = fix.at + Self.coordinateKickWindowMillis
            }
        } else {
            // 정지 주기 한 번 사이에 좌표가 크게 옮겨졌다 — 가방 속 폰의 버스 이동처럼 활동 인식이
            // 통째로 놓치는 사례다(:600-614). 아이폰에서는 '정지 모드'가 그 자리다.
            let displacementEvidence = wasStill && !insideKnownPlace &&
                MovementTrailFilter.isDisplacementEvidence(previous: lastTrailFix, candidate: fix)
            let force = forceNextStayPoint || lastRouteWasMoving || displacementEvidence
            if recordStayFix(fix, force: force) { forceNextStayPoint = false }
            if displacementEvidence {
                coordinateKickExpiresAt = fix.at + Self.coordinateKickWindowMillis
                // 안드로이드 `onActivityMovingChanged(true)`(:477-481)와 같다.
                detector.reset(fast: !insideKnownPlace)
                slowProbeSince = nil
            }
        }
        lastRouteWasMoving = routeMoving

        // 6. 좌표 변위로 켠 이동 확인의 만료(:621-627). 이게 없으면 배터리가 계속 샌다.
        if let expiry = coordinateKickExpiresAt, !routeMoving, fix.at > expiry {
            coordinateKickExpiresAt = nil
            // `onActivityMovingChanged(false)` — 느린 확인으로 돌아가고 다음 기준점을 강제한다.
            detector.reset(fast: false)
            slowProbeSince = nil
            forceNextStayPoint = true
        }

        // 6-1. **이제야** 수집 모드를 수집기에 건다(위 4번 주석). 판정기와 `slowProbeSince` 가
        //      더 안 바뀐 뒤라야 수집기가 최종 모드를 받는다.
        pushMode(now: fix.at)

        // 7. 올릴지 말지(:629).
        let decision = LocationFilter.decide(previous: lastFix, candidate: fix)

        // 8. 거절(정확도·순간이동)이 아니면 장소 판정(:631-639).
        //    **7번의 결과에 안 묶인다** — SKIP_TOO_CLOSE 도 넘긴다. 경계에서 몇 걸음 옮겨 안으로
        //    들어간 순간이 정확히 그 모양이다.
        //    이 훅은 **동기**라 사건을 실제로 썼는지 여기서 기다리지 않는다. 쓰기가 끝나면 그쪽이
        //    [eventWritten] 으로 되돌아와 §6.4-3 규칙을 켠다(2단계 배선).
        if decision != .rejectInaccurate, decision != .rejectImpossible { onPlaceFix?(fix) }

        // 9. UPLOAD / UPLOAD_STALE_FALLBACK 이면 lastFix = fix(:641-672).
        switch decision {
        case .upload, .uploadStaleFallback:
            // 완화 승인이 조용하면 '정확도 기아'와 '다 정상'을 로그에서 못 가른다(:643-651).
            // 아이폰에는 adb logcat 이 없고 1단계에는 기록 통로가 없어 여기서는 상태만 남긴다.
            break
        case .skipTooClose, .rejectInaccurate, .rejectImpossible:
            return
        }
        lastFix = fix

        // 10. 업로드 시각 검사(설계서 §6.4).
        if shouldUpload(now: fix.at, fix: fix, eventJustWritten: eventJustWritten) {
            // 실패해도 시각을 먼저 갱신한다 — 실패가 이어질 때 fix 마다 재시도해 같은 비용을
            // 반복해서 물지 않는다(:679-681). 백오프는 두지 않는다(설계서 §4.11·§6.5).
            lastUploadAt = fix.at
            lastUploadedFix = fix
            uploadTask = Task { [weak self] in await self?.uploadNow() }
        }
    }

    /// 좌표가 **하나도 안 들어오는 동안** 도는 유일한 길이다([Ticking], 기본 60초).
    ///
    /// `handle()` 안의 시계 셋(정지 확인 60초·하트비트 10분·유휴 업로드 4시간)은 전부 좌표가
    /// 있어야 만난다. 이동 확정(`.moving`)은 3m 거리 필터를 걸므로 폰이 완전히 멈추면 그 좌표가
    /// 끊기고, 끊기면 세 시계가 함께 굶는다 — 자기를 가두는 고리다. 안드로이드는 활동 인식의
    /// STILL 전환이 그 고리를 밖에서 끊어 준다(`TrackingService.kt:473-477`). 여기가 그 자리다.
    ///
    /// **새 좌표를 지어내지 않는다.** 버퍼에 점을 넣지 않고 `lastFix`·`lastTrailFix` 를 건드리지
    /// 않는다 — 이 함수가 만질 수 있는 것은 "지금 몇 시인가"에서 따라 나오는 것뿐이다.
    func tick(_ now: Int64) {
        // 좌표를 한 번도 못 받았으면 내릴 모드도 올릴 것도 없다. 시계가 거꾸로 간 tick 도 버린다
        // — 시계 역행 복구는 좌표가 있을 때만 한다(`handle` 의 2번).
        guard lastHandledAt > 0, now > clockAt else { return }
        clockAt = now

        // 1. 상태 검사. 좌표와 무관하게 유효하다 — 안드로이드도 `checkConditions` 를 60초
        //    간격으로 돌리고(`TrackingService.kt:399-403`), 그 간격이 이 시계의 주기와 같다.
        onCondition?(now)

        // 2. 좌표가 정지 확인 시간만큼 끊겼다 = 안드로이드에서 활동 인식이 STILL 을 보고한 것과
        //    같은 사실이다. `onActivityMovingChanged(false)`(:473-477) 를 그대로 한다 — 판정기를
        //    느린 확인으로 내리고 다음 기준점을 강제한다. 모드가 내려가면 3m 거리 필터가 풀려
        //    좌표가 다시 흐르고, 그때부터 하트비트(10분)도 정상으로 돈다.
        //    **움직이는 동안에는 절대 안 걸린다** — 5초마다 좌표가 들어오므로 끊긴 적이 없다.
        if now - lastHandledAt >= AdaptiveMovementDetector.stopConfirmMillis, detector.state != .slowProbe {
            detector.reset(fast: false)
            lastRouteWasMoving = false
            forceNextStayPoint = true
        }

        // 3. 좌표 변위로 켠 이동 확인의 만료(`handle` 의 6번). 이것도 좌표를 기다리면 안 된다 —
        //    킥을 켜 놓고 폰이 멈추면 5초 확인이 영영 안 풀려 배터리가 계속 샌다.
        if let expiry = coordinateKickExpiresAt, now > expiry {
            coordinateKickExpiresAt = nil
            detector.reset(fast: false)
            forceNextStayPoint = true
        }

        // 4. `handle` 의 4번과 같은 식이다. 느린 확인에 있으면 정지 승격 시계를 **좌표 없이도** 민다.
        slowProbeSince = (detector.state == .slowProbe) ? (slowProbeSince ?? now) : nil
        pushMode(now: now)

        // 5. 유휴 업로드(설계서 §6.4 규칙 2). 마지막으로 **실제로 받은** 점을 다시 올릴 뿐이다 —
        //    거리가 0 이라 규칙 1(15분 **그리고** 25m)은 여기서 절대 안 걸리고, 4시간 규칙만 만난다.
        //    올라가는 `at` 은 그 점의 진짜 시각이라 부모 화면이 위치를 "방금"으로 속이지 않는다.
        guard let fix = lastFix, shouldUpload(now: now, fix: fix, eventJustWritten: false) else { return }
        lastUploadAt = now
        lastUploadedFix = fix
        uploadTask = Task { [weak self] in await self?.uploadNow() }
    }

    /// `events/` 에 사건을 실제로 쓴 직후에 부른다 — 설계서 §6.4 규칙 3("사건 직후에는 1·2번을
    /// 무시하고 올린다. 다만 1분 안이면 건너뛴다").
    ///
    /// 왜 `handle` 안이 아니라 되돌아오는 문인가: 장소 판정([onPlaceFix])은 Firestore 쓰기라
    /// 비동기인데 `handle` 은 동기다. 여기서 `await` 하려고 `handle` 을 비동기로 바꾸면 좌표
    /// 하나가 통과하는 순서(설계서 §6.1 의 10단계)가 위치 콜백과 엇갈릴 수 있다 — 1단계가 그
    /// 순서를 계약으로 못박았으므로 건드리지 않고, 쓰기가 끝난 쪽이 이 문으로 돌아온다.
    /// 안드로이드는 `handle` 이 코루틴이라 그 자리에서 기다린다(`TrackingService.kt:631-639`).
    func eventWritten(at now: Int64) {
        guard let fix = lastFix, shouldUpload(now: now, fix: fix, eventJustWritten: true) else { return }
        lastUploadAt = now
        lastUploadedFix = fix
        uploadTask = Task { [weak self] in await self?.uploadNow() }
    }

    /// 지금 모드를 좌표원에 건다. 모드가 실제로 바뀔 때만 매니저를 다시 거는 것은 저쪽 몫이다.
    private func pushMode(now: Int64) {
        source?.updateMode(
            state: detector.state,
            insideKnownPlace: insideKnownPlace,
            slowProbeSince: slowProbeSince,
            now: now
        )
    }

    /// 설계서 §6.4 의 규칙 셋. 점이 들어올 때마다, 그리고 [tick] 마다 판정한다.
    ///
    /// 규칙 1·2 는 지금 쓰이고, 규칙 3(사건 직후)은 **판정만** 지금 있다 — 부르는 쪽(장소 이벤트)은
    /// 2단계다(1단계 판정 기록 14). 인자를 지금 두지 않으면 2단계가 이 함수의 모양을 바꾸게 된다.
    func shouldUpload(now: Int64, fix: Fix, eventJustWritten: Bool) -> Bool {
        // 3. 사건 직후에는 1·2번을 무시한다. 다만 1분 안이면 건너뛴다 — 한 점에서 사건이 둘 이상
        //    날 수 있다(`known-issues.md` 21번).
        if eventJustWritten { return now - lastUploadAt >= Self.uploadEventMinGapMillis }
        // 1. 15분 **그리고** 25m.
        if now - lastUploadAt >= Self.uploadMinIntervalMillis {
            guard let last = lastUploadedFix else { return true }   // 한 번도 안 올렸으면 거리 조건은 만족
            if LocationFilter.distanceMeters(last, fix) >= LocationFilter.minMoveMeters { return true }
        }
        // 2. 안 움직였어도 4시간 — 부모 화면의 '마지막 신호'가 멎지 않게.
        return now - lastUploadAt >= Self.uploadIdleIntervalMillis
    }

    /// 지금 상태와 오늘 경로를 올린다. **쓰기 두 번**(상태 문서 1, 하루 문서 1)이고
    /// 이 앱에서 위치 데이터가 서버로 가는 유일한 경로다(`TrackingService.kt:719-729`).
    ///
    /// **위치를 한 번도 못 잡았으면 올리지 않는다.** 안드로이드는 그때 예외를 던져 명령이 실패로
    /// 끝나는데(:720), 아이폰은 물어본 사람이 없으니 조용히 건너뛴다(설계서 §6.4 끝).
    /// 파일에서 복구한 옛 점으로 대신 채우지 않는 것도 같은 이유다 — 그 점은 몇 시간 전일 수 있는데
    /// 상태 문서에 넣는 순간 서버 시각이 "방금"으로 찍힌다(:713-717).
    func uploadNow() async {
        guard let fix = lastFix else { return }
        do {
            try await uploader.upload(familyId: familyId, fix: fix, points: buffer.points, dayKey: buffer.dayKey)
        } catch is CancellationError {
            // 취소는 실패가 아니다. 일반 catch 로 삼키면 안드로이드에서 아홉 번 고친 실수를
            // 반복하게 된다 — 여기가 태스크의 꼭대기라 되던질 곳이 없으므로 갈래만 나눠 둔다.
        } catch {
            // 화면이 없는 자리라 사람에게 보여줄 방법이 없다. 다음 업로드 창이 다시 시도한다
            // (:691-697). 재시도·백오프를 새로 만들지 않는다 — Firestore SDK 의 오프라인 큐가 있다.
        }
    }

    /// 등록 장소 안에서는 학교 복도 같은 작은 움직임을 이동 경로로 만들지 않는다.
    /// 정본은 `TrackingService.updateKnownPlaceSampling`(:519-530). 돌려주는 값은 "방금 나왔는가"다
    /// — 지오펜스 이탈은 실제 이동의 강한 증거라 곧바로 5초 확인을 시작한다.
    @discardableResult
    private func updateKnownPlaceSampling(_ fix: Fix) -> Bool {
        guard let inside = updateKnownPlace?(fix), insideKnownPlace != inside else { return false }
        let wasInside = insideKnownPlace
        insideKnownPlace = inside
        detector.reset(fast: !inside)
        slowProbeSince = nil
        forceNextStayPoint = inside

        let exited = wasInside && !inside
        // 안드로이드 `collector.onMovingChanged(true)`(:558)가 판정기를 빠른 확인으로 되돌린다.
        if exited { detector.reset(fast: true) }
        return exited
    }

    /// `TrackingService.recordMovementFixes`(:496-503).
    private func recordMovementFixes(_ fixes: [Fix]) {
        for candidate in fixes.sorted(by: { $0.at < $1.at }) {
            guard MovementTrailFilter.shouldRecord(previous: lastTrailFix, candidate: candidate, reportedMoving: true) else { continue }
            collect(candidate)
        }
    }

    /// 머무름도 시작점과 5분 기준점은 남긴다. 그래야 하루치를 올렸을 때 학교·집에 있었던 시간이
    /// 보이면서, GPS 흔들림이 촘촘한 이동선이 되지 않는다(`TrackingService.kt:505-530`).
    @discardableResult
    private func recordStayFix(_ candidate: Fix, force: Bool) -> Bool {
        if !candidate.lat.isFinite || !candidate.lng.isFinite
            || candidate.lat < -90 || candidate.lat > 90
            || candidate.lng < -180 || candidate.lng > 180
            || !candidate.accuracy.isFinite || candidate.accuracy < 0
            || candidate.accuracy > LocationFilter.maxAccuracyMeters
            || candidate.speed > LocationFilter.maxSpeedMps {
            return false
        }

        if let previous = lastTrailFix {
            let elapsed = candidate.at - previous.at
            if elapsed <= 0 { return false }
            if !force, elapsed < Self.stayAnchorIntervalMillis { return false }
            let impliedSpeed = LocationFilter.distanceMeters(previous, candidate) / (Double(elapsed) / 1_000.0)
            if impliedSpeed > LocationFilter.maxSpeedMps { return false }
        }

        collect(candidate)
        return true
    }

    /// `TrailUploader.onCollected`(:95-104) 자리. 메모리와 파일에 함께 남긴다.
    private func collect(_ fix: Fix) {
        buffer.append(fix, store: store, zone: zone)
        lastTrailFix = fix
    }
}
