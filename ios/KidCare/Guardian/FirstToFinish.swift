import Foundation

// 지도 탭(`MapViewModel`)과 관리 탭(`ControlViewModel`)이 함께 쓴다 — 안드로이드
// `withTimeoutOrNull(SEND_TIMEOUT_MILLIS)` 두 자리(MapTimelineFragment.kt:384, ControlFragment.kt:533)와
// 같은 장치.

/// `withTimeoutOrNull` 같은 것. Firestore 쓰기는 취소에 응하지 않으므로
/// (`FamilyRepository.measureWithTimeout` 주석과 같은 근거) 시간 초과 쪽이
/// 이겨도 진 태스크(대개 오프라인 상태로 계속 도는 실제 쓰기)를 강제로 멈추지
/// 않고 결과만 버려둔 채 계속 돌게 둔다. `withThrowingTaskGroup` 을 쓰지 않는
/// 이유도 같은 문서가 설명한 것과 같다 — 스코프를 빠져나갈 때 취소된 태스크가
/// 실제로 끝나기를 기다려 버리면(오프라인이면 영원히) 시간 제한이 장식으로
/// 전락한다.
func firstToFinish<T: Sendable>(
    timeoutMillis: Int64,
    sleep: @escaping @Sendable (Int64) async -> Void,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T? {
    try Task.checkCancellation()
    let race = CommandRace<T>()
    Task {
        do {
            let value = try await operation()
            await race.resolve(.success(value))
        } catch {
            await race.resolve(.failure(error))
        }
    }
    Task {
        await sleep(timeoutMillis)
        await race.resolve(.success(nil))
    }
    return try await race.outcome()
}

/// [firstToFinish] 전용 "누가 먼저 끝나는지" 심판. 두 번째부터의
/// `resolve` 호출은 조용히 버린다 — 이긴 쪽만 결과를 낸다. actor 로 묶어 두
/// 태스크가 동시에 `resolve` 를 불러도 경합이 없다.
private actor CommandRace<T: Sendable> {
    private var result: Result<T?, Error>?
    private var waiters: [CheckedContinuation<T?, Error>] = []

    func resolve(_ newResult: Result<T?, Error>) {
        guard result == nil else { return }
        result = newResult
        for waiter in waiters { waiter.resume(with: newResult) }
        waiters.removeAll()
    }

    func outcome() async throws -> T? {
        if let result { return try result.get() }
        return try await withCheckedThrowingContinuation { waiters.append($0) }
    }
}
