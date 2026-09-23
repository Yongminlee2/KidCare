import Foundation
import Testing
@testable import KidCare

@MainActor
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

    // 위의 "적고_읽는다" 는 쓴 인스턴스를 그대로 다시 읽으므로, `didSet` 을 전부
    // 지우고 프로퍼티를 메모리에만 두어도 초록으로 남는다 — 실제로는 그러면 앱을
    // 껐다 켰을 때 아무것도 안 남는데 이 스위트는 그걸 잡지 못했다. 실제 사용자가
    // 제일 먼저 만나는 실패가 이거다: 가족에 합류하고 앱을 죽였다 다시 켰더니
    // `joinFamily` 가 이미 써버린 초대 코드를 다시 넣으라며 역할 선택으로
    // 돌아간다. `UserDefaults` 는 프로세스 안에서도 디스크에 바로 쓰므로, 같은
    // 스위트를 가리키는 **두 번째** `RoleStore` 인스턴스를 새로 만들어 읽는 것으로
    // "다시 실행됐다"를 흉내 낸다.
    @Test("다른 RoleStore 인스턴스로도 값이 남아 있다 (재실행 흉내)")
    func 재실행해도_값이_남는다() {
        let suite = "kidcare.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        let 첫번째 = RoleStore(defaults: defaults)
        첫번째.role = .child
        첫번째.familyId = "F1"
        첫번째.childUid = "C1"

        // 같은 UserDefaults 스위트를 가리키는 두 번째 인스턴스 — 앱을 새로
        // 띄우면 실제로 이렇게 된다(RoleStore.shared 가 매 프로세스마다 다시
        // 만들어진다).
        let 두번째 = RoleStore(defaults: defaults)
        #expect(두번째.role == .child)
        #expect(두번째.familyId == "F1")
        #expect(두번째.childUid == "C1")
    }

    /// **통합 검토 M3.** 역할을 지우는 길이 셋인데(`ChildRootView.swift:29`,
    /// `InviteCodeView.swift:103`, `LeaveFamilyModel.swift:210`) 세션을 같이 멈추는 것은
    /// 첫째뿐이었다. 역할이 사라진 폰에서 수집기·티커·리스너·OS 지역 스무 개가 조용히
    /// 고아가 된다. 짝을 **여기서** 지어 두면 앞으로 어느 길이 생겨도 같이 멈춘다.
    @Test("역할을 지우면 아이 수집도 같이 멈춘다 (통합 검토 M3)")
    func 역할을_지우면_수집도_멈춘다() {
        final class 센다 { var 횟수 = 0 }
        let 멈춤 = 센다()
        let store = RoleStore(defaults: UserDefaults(suiteName: "kidcare.test.\(UUID().uuidString)")!,
                              수집을_멈춘다: { 멈춤.횟수 += 1 })
        store.role = .child
        store.familyId = "fam"

        store.clear()

        #expect(멈춤.횟수 == 1)
        #expect(store.role == nil)
        #expect(store.familyId == nil)
    }
}
