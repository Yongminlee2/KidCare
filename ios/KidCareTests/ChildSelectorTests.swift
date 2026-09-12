import Testing
@testable import KidCare

/// 정본은 안드로이드 `logic/ChildSelectorTest.kt` 다. 케이스 하나하나를 같은 뜻으로 옮긴다.
struct ChildSelectorTests {

    @Test("저장한 자녀가 있으면 목록 순서와 무관하게 유지한다")
    func 저장한_자녀가_있으면_목록_순서와_무관하게_유지한다() {
        let children = [
            SelectableChild(uid: "second", displayName: "둘째", joinedAt: 20),
            SelectableChild(uid: "first", displayName: "첫째", joinedAt: 10),
        ]

        #expect(ChildSelector.select(children: children, preferredUid: "second")?.uid == "second")
    }

    @Test("저장한 자녀가 사라졌으면 가장 먼저 가입한 자녀를 고른다")
    func 저장한_자녀가_사라졌으면_가장_먼저_가입한_자녀를_고른다() {
        let children = [
            SelectableChild(uid: "second", displayName: "둘째", joinedAt: 20),
            SelectableChild(uid: "first", displayName: "첫째", joinedAt: 10),
        ]

        #expect(ChildSelector.select(children: children, preferredUid: "removed")?.uid == "first")
    }

    @Test("옛 문서처럼 가입 시각이 없으면 이름과 uid로 결과가 고정된다")
    func 옛_문서처럼_가입_시각이_없으면_이름과_uid로_결과가_고정된다() {
        let children = [
            SelectableChild(uid: "b", displayName: "아이", joinedAt: 0),
            SelectableChild(uid: "a", displayName: "아이", joinedAt: 0),
        ]

        #expect(ChildSelector.select(children: children, preferredUid: nil)?.uid == "a")
    }

    @Test("자녀가 없으면 선택도 없다")
    func 자녀가_없으면_선택도_없다() {
        #expect(ChildSelector.select(children: [], preferredUid: "anything") == nil)
    }
}
