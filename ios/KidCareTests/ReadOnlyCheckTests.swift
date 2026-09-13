import Foundation
import Testing
import os
@testable import KidCare

/// 실기기 읽기 전용 확인(-readOnlyCheck)의 읽음 쓰기 차단. 스위치 자체는 프로세스 인자라 테스트에서 켤 수 없으므로,
/// 스위치가 고르는 구현을 `ReadOnlyCheck.alertMarkRead` 로 빼서 그 함수를 직접 본다(6단계 통합 검토 I2).
/// 진짜 `EventRepository.markRead` 는 부르지 않는다 — 테스트 호스트 앱이 어느 Firestore 를 보는지와 상관없이
/// 쓰기가 나갈 길을 만들지 않기 위해, 저장소 쓰기를 기록하는 가짜로 바꿔 넘긴다.
struct ReadOnlyCheckTests {

    final class 쓰기_기록: Sendable {
        private let 잠금 = OSAllocatedUnfairLock(initialState: [String]())
        var 호출: [String] { 잠금.withLock { $0 } }
        func 적는다(_ familyId: String, _ ids: [String]) {
            잠금.withLock { $0.append("\(familyId):\(ids.joined(separator: ","))") }
        }
    }

    @Test("읽기 전용이면 알림 읽음 쓰기가 저장소를 한 번도 부르지 않고 오류 없이 끝난다")
    func 읽기_전용이면_읽음을_쓰지_않는다() async throws {
        let 기록 = 쓰기_기록()
        let markRead = ReadOnlyCheck.alertMarkRead(readOnly: true, writer: { familyId, ids in 기록.적는다(familyId, ids) })
        try await markRead("fam", ["e1", "e2"])
        try await markRead("fam", ["e3"])
        #expect(기록.호출.isEmpty)
    }

    @Test("평소에는 받은 저장소 쓰기를 그대로 부른다 — 위 테스트가 가짜를 안 부른 것이 우연이 아님을 보인다")
    func 평소에는_읽음을_쓴다() async throws {
        let 기록 = 쓰기_기록()
        let markRead = ReadOnlyCheck.alertMarkRead(readOnly: false, writer: { familyId, ids in 기록.적는다(familyId, ids) })
        try await markRead("fam", ["e1", "e2"])
        #expect(기록.호출 == ["fam:e1,e2"])
    }
}
