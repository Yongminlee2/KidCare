import Testing
@testable import KidCare

/// 정본은 안드로이드 `guardian/ListLoadState.kt`. 못 불러온 화면과 정말 빈 화면이 같은 말을
/// 하지 않게 하는 판정이다(:13-18).
struct ListLoadTests {

    @Test("캐시본은 불러오는 중으로 접는다 — 오프라인은 네 번째 상태가 아니다(:23-39)")
    func 캐시본() {
        #expect(ListLoad.after(fromCache: true) == .loading)
        #expect(ListLoad.after(fromCache: false) == .loaded)
    }

    @Test("빈 목록 문구는 서버가 확인한 뒤에만 '없어요'라고 말하고, 실패면 자리를 감춘다(:80-97)")
    func 빈_목록_문구() {
        #expect(ListLoad.loading.emptyText(isEmpty: true, loaded: "없음") == String(localized: "list_loading"))
        #expect(ListLoad.loaded.emptyText(isEmpty: true, loaded: "없음") == "없음")
        #expect(ListLoad.failed.emptyText(isEmpty: true, loaded: "없음") == nil)
        #expect(ListLoad.loaded.emptyText(isEmpty: false, loaded: "없음") == nil)
    }
}
