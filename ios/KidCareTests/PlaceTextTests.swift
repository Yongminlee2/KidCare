import Testing
@testable import KidCare

/// 정본은 안드로이드 `PlaceText`·스티커(PlaceAdapter.kt:58-120).
struct PlaceTextTests {

    private func 장소(_ id: String = "p", name: String = "학교", radius: Double = 200, enter: Bool = true, exit: Bool = true) -> PlaceDoc {
        PlaceDoc(id: id, name: name, lat: 37.5, lng: 127, radiusMeters: radius, notifyEnter: enter, notifyExit: exit)
    }

    @Test("알림 문구 네 가지와 줄·요약(:109-120, :43-47)")
    func 문구() {
        #expect(PlaceText.notifyText(장소()) == "도착·이탈 알림")
        #expect(PlaceText.notifyText(장소(exit: false)) == "도착 알림만")
        #expect(PlaceText.notifyText(장소(enter: false)) == "이탈 알림만")
        #expect(PlaceText.notifyText(장소(enter: false, exit: false)) == "알림 꺼둠")
        #expect(PlaceText.rowDetail(장소()) == "도착·이탈 알림 · 반경 200m")
        #expect(PlaceText.summary(장소()) == "학교 (반경 200m)")
    }

    @Test("반경은 Math.round 로 정수 표기(:102-107)")
    func 반경() {
        #expect(PlaceText.radiusMeters(장소(radius: 200.4)) == 200)
        #expect(PlaceText.radiusMeters(장소(radius: 200.5)) == 201)
    }

    @Test("콘솔에서 반경을 Infinity·1e19·NaN 으로 넣은 문서도 죽지 않고 그린다 — 안드로이드와 같은 2147483647m, 편집기는 1000 으로 연다(5단계 통합 검토 M3)")
    func 반경_끝값() {
        #expect(PlaceText.radiusMeters(장소(radius: .infinity)) == 2_147_483_647)
        #expect(PlaceText.summary(장소(radius: .infinity)) == "학교 (반경 2147483647m)")
        #expect(PlaceText.rowDetail(장소(radius: 1e19)) == "도착·이탈 알림 · 반경 2147483647m")
        #expect(PlaceText.radiusMeters(장소(radius: -.infinity)) == -2_147_483_648)
        #expect(PlaceText.radiusMeters(장소(radius: .nan)) == 0)
        #expect(PlaceViewModel.반경을_눈금에(.infinity) == 1000)
        #expect(PlaceViewModel.반경을_눈금에(1e19) == 1000)
        #expect(PlaceViewModel.반경을_눈금에(.nan) == 100)
    }

    @Test("스티커 색은 문서 ID 의 자바 해시로, ID 가 비면 이름으로 고른다 — 순서가 바뀌어도 같은 장소는 같은 색(:58-72)")
    func 스티커() {
        #expect(PlaceText.stickerIndex(장소("3f2a9c1e-7b4d-4e8a-9c2f-1a2b3c4d5e6f")) == 1)
        #expect(PlaceText.stickerIndex(장소("", name: "학교")) == 3)
        #expect(PlaceText.stickerIndex(장소("polygenelubricants")) == 0)
        #expect(PlaceText.stickerLetter(장소(name: "  학원")) == "학")
        #expect(PlaceText.stickerLetter(장소(name: "")) == "")
    }
}
