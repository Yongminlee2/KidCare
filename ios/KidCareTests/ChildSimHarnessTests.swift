import Foundation
import Testing
@testable import KidCare

#if DEBUG
/// 실행 인자 파싱만 본다. 출시 빌드에는 이 타입 자체가 없다(`#if DEBUG`).
struct ChildSimHarnessTests {

    @Test("인자가 없으면 nil 이다 — 평소 실행에서는 아무 일도 안 일어난다")
    func 인자_없음() {
        #expect(ChildSimHarness.parse([]) == nil)
        #expect(ChildSimHarness.parse(["/path/to/KidCare.app"]) == nil)
        #expect(ChildSimHarness.parse(["-readOnlyCheck"]) == nil)
    }

    @Test("-childSim <familyId> 를 읽는다")
    func 가족_아이디() {
        #expect(ChildSimHarness.parse(["-childSim", "FAM1"]) == ChildSimHarness.Launch(familyId: "FAM1", battery: nil))
    }

    @Test("값이 없거나 다음 옵션이 붙어 있으면 nil 이다 — 빈 가족으로 들어가면 규칙이 전부 거부한다")
    func 값_없음() {
        #expect(ChildSimHarness.parse(["-childSim"]) == nil)
        #expect(ChildSimHarness.parse(["-childSim", ""]) == nil)
        #expect(ChildSimHarness.parse(["-childSim", "-childSimBattery", "77"]) == nil)
    }

    @Test("-childSimBattery 는 0~100 만 받는다 — 시뮬레이터가 배터리를 안 주므로 넣어 준다(판정 기록 8)")
    func 배터리() {
        #expect(ChildSimHarness.parse(["-childSim", "FAM1", "-childSimBattery", "77"])?.battery == 77)
        #expect(ChildSimHarness.parse(["-childSim", "FAM1", "-childSimBattery", "0"])?.battery == 0)
        #expect(ChildSimHarness.parse(["-childSim", "FAM1", "-childSimBattery", "100"])?.battery == 100)
        #expect(ChildSimHarness.parse(["-childSim", "FAM1", "-childSimBattery", "101"])?.battery == nil)
        #expect(ChildSimHarness.parse(["-childSim", "FAM1", "-childSimBattery", "-1"])?.battery == nil)
        #expect(ChildSimHarness.parse(["-childSim", "FAM1", "-childSimBattery", "칠십칠"])?.battery == nil)
        #expect(ChildSimHarness.parse(["-childSim", "FAM1", "-childSimBattery"])?.battery == nil)
    }

    @Test("테스트 프로세스는 이 문을 안 탄다 — 아무도 -childSim 을 주지 않았다")
    func 테스트에서는_꺼져있다() {
        #expect(ChildSimHarness.launch == nil, "테스트가 아이 파이프라인을 띄우면 에뮬레이터에 쓰레기 문서가 쌓인다")
    }
}
#endif
