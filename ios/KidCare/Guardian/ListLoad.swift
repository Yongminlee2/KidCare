import Foundation

/// 목록 화면 셋(예약·장소, 6단계의 알림)이 함께 쓰는 "빈 목록" 판정. 정본은 안드로이드
/// `guardian/ListLoadState.kt`.
///
/// 목록이 비었다는 사실만 보고 "없어요"를 띄우면, 못 불러온 화면과 정말 빈 화면이 **같은 말을
/// 한다**(:13-18). 부모는 가운데 큰 글씨를 읽고 "아직 없구나"로 이해하는데 진실은 "아무것도 못
/// 읽었다"다. 그래서 세 상태를 나눈다.
enum ListLoad: Equatable {
    /// 첫 스냅샷을 아직 못 받았다. 캐시본만 받은 상태(오프라인)도 여기다(:43-51).
    case loading
    /// 서버가 확인해 준 스냅샷을 받았다. 비어 있다면 정말 비어 있다.
    case loaded
    /// 못 불러왔다. 이유는 목록 위 한 줄이 이미 말하므로 빈 자리는 통째로 비운다(:59-63).
    case failed

    /// 캐시본으로는 `loaded` 로 올리지 않는다 — 오프라인은 네 번째 상태가 아니다(:23-39).
    static func after(fromCache: Bool) -> ListLoad {
        fromCache ? .loading : .loaded
    }

    /// 빈 목록 자리에 쓸 문구. nil 이면 그 자리를 감춘다(:80-97). [loaded] 는 `loaded` 일 때만 쓴다.
    func emptyText(isEmpty: Bool, loaded: @autoclosure () -> String) -> String? {
        guard isEmpty, self != .failed else { return nil }
        return self == .loaded ? loaded() : String(localized: "list_loading")
    }
}
