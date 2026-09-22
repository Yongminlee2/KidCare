import Foundation
import Testing
@testable import KidCare

/// 정본은 `child/PlaceWatcher.kt:168-174`(코틀린에서는 인라인이라 골든 대상이 아니다, 설계서 §7.2).
struct GeofenceRegionSelectionTests {

    private func 장소(_ id: String, _ name: String, radius: Double = 100) -> Place {
        Place(id: id, name: name, lat: 37.5, lng: 127.0, radiusMeters: radius)
    }

    @Test("상한은 20 이다 — 아이폰 OS 상한과 같고 부모 화면의 장소 개수 상한과도 같다 (PlaceWatcher.kt:217)")
    func 상한() { #expect(GeofenceRegionSelection.maxRegions == 20) }

    @Test("반경이 0 이하인 장소는 뺀다 — iOS 도 반경 0 을 거부한다 (:169)")
    func 반경0_제외() {
        let 고른것 = GeofenceRegionSelection.choose([
            장소("a", "가", radius: 0), 장소("b", "나", radius: -1), 장소("c", "다", radius: 50),
        ])
        #expect(고른것.map(\.id) == ["c"])
    }

    @Test("이름순으로 앞에서 20개 — 읽어온 순서로 자르면 어떤 장소는 하루는 걸리고 하루는 안 걸린다 (:166-171)")
    func 이름순_스물() {
        let 뒤섞인 = (0..<25).reversed().map { 장소("id\($0)", String(format: "곳%02d", $0)) }
        let 고른것 = GeofenceRegionSelection.choose(뒤섞인)
        #expect(고른것.count == 20)
        #expect(고른것.map(\.name) == (0..<20).map { String(format: "곳%02d", $0) })
    }

    @Test("이름이 같으면 읽어온 순서를 지킨다 — 코틀린 sortedBy 는 안정 정렬이다(판정 기록 3)")
    func 안정_정렬() {
        let 같은이름 = (0..<5).map { 장소("id\($0)", "집") }
        #expect(GeofenceRegionSelection.choose(같은이름, limit: 3).map(\.id) == ["id0", "id1", "id2"])
    }

    @Test("정렬은 UTF-16 코드 단위 비교다 — 코틀린 String.compareTo 와 같다(판정 기록 3)")
    func 코드_단위_정렬() {
        // 전각 A(U+FF21) 는 '가'(U+AC00) 보다 코드 단위가 크다. Swift 의 기본 `<` 는 정규화를
        // 거쳐 다른 답을 낼 수 있다.
        let 고른것 = GeofenceRegionSelection.choose([장소("a", "\u{FF21}"), 장소("b", "가")])
        #expect(고른것.map(\.id) == ["b", "a"])
    }

    @Test("잘린 개수를 부르는 쪽이 알 수 있다 — 조용히 실패하면 '왜 알림이 안 오지'를 알아낼 방법이 없다 (:172-174)")
    func 잘린_개수() {
        let 결과 = GeofenceRegionSelection.chooseWithReport((0..<25).map { 장소("id\($0)", "곳\($0)") })
        #expect(결과.chosen.count == 20)
        #expect(결과.dropped == 5)
    }
}
