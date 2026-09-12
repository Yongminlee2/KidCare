import Testing
@testable import KidCare

/// `FamilyRepository.serverNow`(정확히는 그 안의 `measureWithTimeout`)가 취소돼도
/// 값을 돌려주지 않고 `CancellationError` 를 던지는지 확인한다. 정본은
/// `.superpowers/sdd/2026-09-13-kidcare-ios-phase2/task-1-brief.md` — 오프셋이 아직
/// 캐시되지 않은 **첫 호출**(= `NewFamilySession` 이 초대를 발급하는 그 순간)에서
/// 취소가 떨어지면, 비구조적 `Task` 경주가 부모의 취소를 모르고 값을 돌려줘
/// `createInvite` 가 아무도 못 볼 초대 문서를 10분 TTL 내내 남기던 버그였다.
@Suite(.serialized)
struct ServerNowTests {

    init() async { await EmulatorHarness.start() }

    @Test("취소된 작업 안에서 serverNow 는 CancellationError 를 던진다")
    func 취소되면_던진다() async throws {
        // brief 원안은 실제 "아직 멤버가 아닌 uid" 로 `serverNow` 를 불러 놓고
        // Task 생성 직후(혹은 고정/실측 기반 지연 뒤) cancel() 하는 것이었다. 직접
        // 셋 다 해봤다: (1) 지연 없이 바로 cancel — 취소가 거의 항상 `serverNow`
        // 맨 앞의 `Task.checkCancellation()` 보다 먼저 도착해 `measureWithTimeout`
        // 의 경주엔 닿지도 못하고 끝난다(고치기 전 코드로도 항상 통과 — 이 함수가
        // 고치려는 버그를 하나도 안 건드린다). (2) 고정 지연(5ms, 30ms) — 로컬
        // 에뮬레이터 왕복이 연결이 데워지면 1ms 아래로 떨어져서, 이 파일 하나만
        // 돌 때(차가운 채)와 스위트 전체를 돌 때(데워진 채) 결과가 서로 뒤집혔다.
        // (3) 취소 없이 한 번 먼저 재서 그 시간의 절반을 지연으로 쓰는 자가보정 —
        // 프로브 호출 자체가 연결을 데워버려서 본 호출은 프로브보다도 훨씬 빨리
        // 끝나, 매번 취소가 이미 끝난 응답을 뒤쫓아가 실패했다. 세 방법 다 이
        // 환경에서 근본적으로 결정적이지 않다는 뜻이라, 실제 네트워크 타이밍에
        // 기대는 대신 `measureWithTimeout` 의 `measure` 자리에 끝나는 시점을 테스트가
        // 정확히 아는 가짜 측정을 꽂는다 — "서버 왕복 도중"을 흉내가 아니라 보장으로
        // 만든다.
        let 측정_시작_신호 = AsyncSemaphore()
        let 작업 = Task { () -> Int64 in
            try await FamilyRepository.measureWithTimeout(familyId: "없는가족", uid: "없는사람") { _, _ in
                await 측정_시작_신호.signal()
                // 실제로 안 끝난다 — 밖에서 취소가 오면 이 태스크는 결과를 버린
                // 채 계속 돌게 두는 것이 정상 동작이다(측정 자체는 취소를 모른다,
                // Firestore 쓰기와 같은 처지). 테스트가 끝나면 프로세스와 함께
                // 정리된다.
                try await Task.sleep(for: .seconds(10))
                return 0
            }
        }
        // 가짜 측정이 실제로 시작된 뒤에 취소한다 — "아직 시작도 안 한 태스크를
        // 취소해 맨 앞머리 체크에서 끝나는" 경우(위 (1))를 완전히 배제한다.
        await 측정_시작_신호.wait()
        작업.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await 작업.value
        }
    }
}

/// `signal()`/`wait()` 한 쌍만 필요한 최소 동기화 도구. `AsyncStream` 하나로
/// "신호가 아직 하나도 없으면 기다리고, 있으면 바로 받는다"를 구현한다 — 이 파일
/// 밖에서는 안 쓰므로 여기 둔다.
private actor AsyncSemaphore {
    private var signaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        guard !signaled else { return }
        signaled = true
        let waiters = waiters
        self.waiters = []
        for continuation in waiters { continuation.resume() }
    }

    func wait() async {
        if signaled { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
