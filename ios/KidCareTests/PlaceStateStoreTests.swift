import Foundation
import Testing
@testable import KidCare

/// 정본은 `child/PlaceStateStore.kt`. 값 형식(줄바꿈 레코드·탭 칸·망가진 줄 버리기)이 안드로이드와
/// 글자까지 같아야 한다 — 같은 아이가 폰을 바꿔도 읽히기를 바라는 값은 아니지만, 형식이 갈리면
/// "왜 한쪽만 되지"를 대조할 기준이 사라진다.
@MainActor
struct PlaceStateStoreTests {

    private func 빈_저장소() -> PlaceStateStore {
        PlaceStateStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
    }

    @Test("아무것도 없으면 빈 목록이다 — 예외로 수집을 죽이지 않는다")
    func 처음() { #expect(빈_저장소().states.isEmpty) }

    @Test("쓴 그대로 다시 읽힌다")
    func 왕복() {
        let store = 빈_저장소()
        let 값 = [PlaceState(placeId: "a", inside: true, lastEventAt: 1_700_000_000_000),
                  PlaceState(placeId: "b", inside: false, lastEventAt: 0)]
        store.states = 값
        #expect(store.states == 값)
    }

    @Test("줄바꿈 레코드·탭 칸·1/0 — 안드로이드와 글자까지 같다 (:50-55)")
    func 형식() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let store = PlaceStateStore(defaults: defaults)
        store.states = [PlaceState(placeId: "a", inside: true, lastEventAt: 5),
                        PlaceState(placeId: "b", inside: false, lastEventAt: 0)]
        #expect(defaults.string(forKey: PlaceStateStore.key) == "a\t1\t5\nb\t0\t0")
    }

    @Test("망가진 줄은 그 줄만 버린다 — 저장소가 깨졌다고 서비스를 죽이지 않는다 (:57-64)")
    func 망가진_줄() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        defaults.set("a\t1\t5\n칸이하나\n\t1\t5\nb\tx\t아닌숫자\nc\t0\t7\nd\t1\t2\t3", forKey: PlaceStateStore.key)
        let store = PlaceStateStore(defaults: defaults)
        #expect(store.states == [PlaceState(placeId: "a", inside: true, lastEventAt: 5),
                                 PlaceState(placeId: "c", inside: false, lastEventAt: 7)])
    }

    @Test("빈 목록을 쓰면 빈 목록으로 읽힌다")
    func 빈_목록() {
        let store = 빈_저장소()
        store.states = [PlaceState(placeId: "a", inside: true, lastEventAt: 5)]
        store.states = []
        #expect(store.states.isEmpty)
    }
}
