import Foundation

/// 실기기 확인 전용 스위치(6단계 계획서 판정 기록 10).
///
/// 알림 탭은 **여는 순간** 진짜 가족의 사건에 `read: true` 를 쓰고(`AlertFragment.kt:211-228`), 선택기 메뉴는
/// 진짜 가족에 초대 코드를 만든다. 실기기 확인은 읽기만 해야 하므로, DEBUG 빌드를 `-readOnlyCheck` 인자로
/// 띄웠을 때만 읽음 쓰기를 빈 동작으로 바꾸고 초대 두 줄을 흐리게 한다(초대 쪽은 6단계 Task 4 가 쓴다).
/// 출시 빌드에서는 늘 false 다. 판단 코드(뷰모델)는 건드리지 않고 주입만 바꾼다 — 그래야 실기기에서 본
/// 화면이 출시 화면과 같다.
enum ReadOnlyCheck {
    static let isOn: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-readOnlyCheck")
        #else
        return false
        #endif
    }()
}
