import Foundation
@testable import KidCare

/// 쓰기 제한시간(15초) 가짜. 첫 번째 sleep 과 나머지를 따로 연다.
///
/// 저장 쓰기가 매달린 동안에는 그 쓰기의 sleep 이 반드시 첫 번째로 불린다(`firstToFinish` 가 쓰기와
/// 제한시간을 동시에 띄우고, 그 전에는 아무도 sleep 하지 않는다). 그래서 `첫_번째` 만 열면 저장만
/// 시간 초과되고, 뒤따르는 `sync_rules` 발행은 `나머지` 가 닫혀 있어 제때 끝난다. `Task.yield()`
/// 횟수로 순서를 가정하지 않는다(3단계 리뷰 I2).
final class WriteSleepFake: Sendable {
    let 첫_번째 = TestGate()
    let 나머지 = TestGate()
    private let 횟수 = TestCounter()

    func sleep(_ millis: Int64) async {
        if await 횟수.next() == 1 {
            await 첫_번째.wait()
        } else {
            await 나머지.wait()
        }
    }
}

/// 이미 메인 액터 대기열에 오른 콜백(`Task { @MainActor in }`)이 다 돌 때까지 기다린다. "정리 뒤에는
/// 아무것도 안 바뀐다"처럼 **바뀌지 않음**을 볼 때는 `eventually` 로 기다릴 조건이 없다. 그래서 같은
/// 우선순위의 빈 작업을 뒤에 세우고 끝나기를 기다린다 — 메인 액터는 순서대로 돌리므로 앞의 콜백이 먼저 끝난다.
@MainActor
func 메인_대기열을_비운다() async {
    await Task { @MainActor in }.value
}
