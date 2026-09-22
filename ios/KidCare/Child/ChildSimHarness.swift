import Foundation

#if DEBUG
/// **시뮬레이터에서 아이 파이프라인을 띄우는 임시 문**이다(아이 1단계 계획서 판정 기록 9).
///
/// 역할 선택 화면의 막이 제거와 진짜 `ChildRootView` 는 **3단계**다(설계서 §14). 그런데 1단계의
/// 완료 기준이 "GPX 를 먹이면 보호자가 그 경로를 그린다"라 띄울 방법이 필요하다.
/// `Guardian/ReadOnlyCheck.swift` 가 이미 같은 모양(DEBUG 빌드 + 실행 인자)의 선례다.
///
/// **3단계가 `ChildRootView` 를 만들면 이 파일과 `ChildSimView` 를 지운다.**
/// 출시 빌드에는 `#if DEBUG` 밖이라 존재 자체가 없다.
enum ChildSimHarness {

    struct Launch: Equatable {
        let familyId: String
        /// 시뮬레이터는 배터리를 안 준다(판정 기록 8). `-childSimBattery 77` 로 넣는다.
        let battery: Int?
    }

    /// `-childSim <familyId> [-childSimBattery <0~100>]`.
    static let launch: Launch? = parse(ProcessInfo.processInfo.arguments)

    static func parse(_ arguments: [String]) -> Launch? {
        guard let index = arguments.firstIndex(of: "-childSim"), index + 1 < arguments.count else { return nil }
        let familyId = arguments[index + 1]
        // 값 자리에 다음 옵션이 와 있으면 familyId 를 안 준 것이다 — 빈 가족으로 들어가면
        // 규칙이 전부 거부해서 원인을 찾는 데 시간이 든다.
        guard !familyId.isEmpty, !familyId.hasPrefix("-") else { return nil }

        var battery: Int?
        if let batteryIndex = arguments.firstIndex(of: "-childSimBattery"), batteryIndex + 1 < arguments.count,
           let value = Int(arguments[batteryIndex + 1]), (0...100).contains(value) {
            battery = value
        }
        return Launch(familyId: familyId, battery: battery)
    }
}
#endif
