import Foundation
import Testing
@testable import KidCare

struct RoleStoreTests {

    private func 새_저장소() -> RoleStore {
        let suite = "kidcare.test.\(UUID().uuidString)"
        return RoleStore(defaults: UserDefaults(suiteName: suite)!)
    }

    @Test("빈 저장소는 역할이 없다")
    func 빈_저장소() {
        #expect(새_저장소().role == nil)
    }

    @Test("역할과 가족을 적고 다시 읽는다")
    func 적고_읽는다() {
        let store = 새_저장소()
        store.role = .guardian
        store.familyId = "F1"
        store.childUid = "C1"
        #expect(store.role == .guardian)
        #expect(store.familyId == "F1")
        #expect(store.childUid == "C1")
    }

    @Test("clear 는 전부 지운다")
    func clear가_전부_지운다() {
        let store = 새_저장소()
        store.role = .guardian
        store.familyId = "F1"
        store.clear()
        #expect(store.role == nil)
        #expect(store.familyId == nil)
    }
}
