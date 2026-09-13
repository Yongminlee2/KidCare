import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

private actor PlaceFakeLog {
    private(set) var 저장한_장소: [PlaceDoc] = []
    private(set) var 지운_ID: [String] = []
    private(set) var 보낸_명령: [String] = []
    private var 쓰기_오류: (any Error)?
    private var 명령_오류: (any Error)?

    func 쓰기_오류를_둔다(_ error: (any Error)?) { 쓰기_오류 = error }
    func 명령_오류를_둔다(_ error: (any Error)?) { 명령_오류 = error }

    func 저장(_ doc: PlaceDoc) throws -> String {
        if let 쓰기_오류 { throw 쓰기_오류 }
        저장한_장소.append(doc)
        return doc.id
    }
    func 지운다(_ id: String) throws {
        if let 쓰기_오류 { throw 쓰기_오류 }
        지운_ID.append(id)
    }
    func 명령(_ type: String) throws -> String {
        if let 명령_오류 { throw 명령_오류 }
        보낸_명령.append(type)
        return "cmd-\(보낸_명령.count)"
    }
}

private final class PlaceFakes: Sendable {
    let log = PlaceFakeLog()
    let sleep = WriteSleepFake()
    let 저장_문 = TestGate()
    let 삭제_문 = TestGate()
    let 명령_문 = TestGate()
    let 명령_도착 = TestSignal()
    let 위치_문 = TestGate()
    let 목록 = TestCallbackBox<([PlaceDoc], Bool) -> Void>()
    let 목록_오류 = TestCallbackBox<(Error) -> Void>()
    let 목록_등록 = TestListenerRegistration()
}

/// 정본은 안드로이드 `guardian/PlaceFragment.kt`. 줄 번호는 각 테스트 이름에 적었다.
@MainActor
struct PlaceViewModelTests {

    private struct 가짜_오류: Error {}

    private func 만든다(
        _ f: PlaceFakes,
        childUid: String? = "child",
        store: RuleSyncStore? = nil,
        아이_위치: (lat: Double, lng: Double)? = nil,
        위치가_기다린다: Bool = false,
        저장이_기다린다: Bool = false,
        삭제가_기다린다: Bool = false,
        명령이_기다린다: Bool = false
    ) -> PlaceViewModel {
        var 번호 = 0
        return PlaceViewModel(
            familyId: "family",
            childUid: childUid,
            syncStore: store ?? RuleSyncStore(kind: .place, defaults: TestDefaults.isolated("PlaceViewModelTests")),
            placesObserve: { _, _, onChange, onError in
                f.목록.set(onChange)
                f.목록_오류.set(onError)
                return f.목록_등록
            },
            placeSave: { _, _, doc in
                if 저장이_기다린다 { await f.저장_문.wait() }
                return try await f.log.저장(doc)
            },
            placeDelete: { _, _, id in
                if 삭제가_기다린다 { await f.삭제_문.wait() }
                try await f.log.지운다(id)
            },
            statusFetch: { _, _ in
                if 위치가_기다린다 { await f.위치_문.wait() }
                guard let 아이_위치 else { return nil }
                return ChildStatusDoc(["lat": 아이_위치.lat, "lng": 아이_위치.lng])
            },
            commandSend: { _, _, type, _ in
                if 명령이_기다린다 {
                    await f.명령_도착.fire()
                    await f.명령_문.wait()
                }
                return try await f.log.명령(type)
            },
            writeSleep: { millis in await f.sleep.sleep(millis) },
            newId: {
                번호 += 1
                return "new-\(번호)"
            }
        )
    }

    private func 장소(_ id: String, _ name: String, radius: Double = 200) -> PlaceDoc {
        PlaceDoc(id: id, name: name, lat: 37.5, lng: 127.0, radiusMeters: radius, notifyEnter: true, notifyExit: true)
    }

    private func 시작하고_위치를_읽는다(_ vm: PlaceViewModel) async {
        vm.시작한다()
        await vm.아이_위치_읽기?.value
    }

    @Test("스냅샷은 이름의 UTF-16 순서로 정렬하고, 캐시본이면 불러오는 중이다(:446-455, 판정 기록 10)")
    func 정렬과_캐시() async {
        let f = PlaceFakes()
        let vm = 만든다(f)
        vm.시작한다()
        f.목록.value?([장소("a", "Ａ"), 장소("b", "😀"), 장소("c", "가게")], true)
        await eventually { vm.places.count == 3 }
        #expect(vm.places.map(\.name) == ["가게", "😀", "Ａ"])
        #expect(vm.listLoad == .loading)
    }

    @Test("20개를 채우면 추가가 잠기고 이유가 뜨며, 편집도 열리지 않는다(:68-71, :461-463, :791-804)")
    func 상한() async {
        let f = PlaceFakes()
        let vm = 만든다(f)
        vm.시작한다()
        f.목록.value?((1...19).map { 장소("id\($0)", "장소\($0)") }, false)
        await eventually { vm.places.count == 19 }
        #expect(vm.추가할_수_있나)
        #expect(vm.상한_안내 == nil)

        f.목록.value?((1...20).map { 장소("id\($0)", "장소\($0)") }, false)
        await eventually { vm.places.count == 20 }
        #expect(!vm.추가할_수_있나)
        #expect(vm.상한_안내 == "장소는 20개까지 정할 수 있어요. 새로 만들려면 안 쓰는 장소를 먼저 지워주세요.")
        vm.편집을_연다(nil)
        #expect(!vm.편집_중)
    }

    @Test("새 장소는 아이의 마지막 확인 위치에서 배율 16으로 열리고 반경 200 원이 그려진다(:410-444, :459-485, :515-536)")
    func 아이_위치에서_연다() async {
        let f = PlaceFakes()
        let vm = 만든다(f, 아이_위치: (37.5665, 126.978))
        await 시작하고_위치를_읽는다(vm)
        vm.편집을_연다(nil)
        #expect(vm.좌표를_골랐나)
        #expect(!vm.지도_안내가_보이나)
        #expect(vm.카메라_요청 == PlaceViewModel.카메라(lat: 37.5665, lng: 126.978, zoom: 16, 번호: 1))
        #expect(vm.원 == PlaceViewModel.반경_원(lat: 37.5665, lng: 126.978, radiusMeters: 200))
    }

    @Test("아이 위치를 모르면 한반도 전체(36.5, 127.8, 배율 6)로 열고, 지도를 안 만진 채 저장하면 막고 안내한다(:48-51, :526-529, :594-614)")
    func 위치_모름() async {
        let f = PlaceFakes()
        let vm = 만든다(f)
        await 시작하고_위치를_읽는다(vm)
        vm.편집을_연다(nil)
        #expect(vm.카메라_요청 == PlaceViewModel.카메라(lat: 36.5, lng: 127.8, zoom: 6, 번호: 1))
        #expect(vm.지도_안내가_보이나)
        #expect(vm.원 == nil)
        vm.이름을_바꾼다("학교")
        await vm.저장을_눌렀다()
        #expect(vm.편집_줄 == "아이 폰 위치를 아직 몰라서 지도가 넓게 열렸어요. 손으로 옮겨 찾아주세요.")
        #expect(await f.log.저장한_장소.isEmpty)
    }

    @Test("늦게 도착한 아이 위치는 부모가 아직 지도를 안 만진 편집기에만 들어간다 — (0,0)은 위치가 아니다(:421-437)")
    func 늦게_온_위치() async {
        let f = PlaceFakes()
        let vm = 만든다(f, 아이_위치: (37.5, 127.0), 위치가_기다린다: true)
        vm.시작한다()
        vm.편집을_연다(nil)
        await f.위치_문.open()
        await vm.아이_위치_읽기?.value
        #expect(vm.좌표를_골랐나)
        #expect(vm.카메라_요청 == PlaceViewModel.카메라(lat: 37.5, lng: 127.0, zoom: 16, 번호: 2))

        let g = PlaceFakes()
        let 만진 = 만든다(g, 아이_위치: (37.5, 127.0), 위치가_기다린다: true)
        만진.시작한다()
        만진.편집을_연다(nil)
        만진.지도를_만졌다(centerLat: 36.0, centerLng: 127.5)
        await g.위치_문.open()
        await 만진.아이_위치_읽기?.value
        #expect(만진.원 == PlaceViewModel.반경_원(lat: 36.0, lng: 127.5, radiusMeters: 200))
        #expect(만진.카메라_요청?.번호 == 1)

        let h = PlaceFakes()
        let 영점 = 만든다(h, 아이_위치: (0, 0))
        await 시작하고_위치를_읽는다(영점)
        #expect(영점.아이_위치 == nil)
    }

    @Test("손이 닿는 순간의 가운데가 좌표이고, 그 뒤로는 사람이 옮긴 멈춤만 좌표를 바꾼다(:242-257, :274-283, 판정 기록 8)")
    func 지도_좌표() async {
        let f = PlaceFakes()
        let vm = 만든다(f)
        await 시작하고_위치를_읽는다(vm)
        vm.편집을_연다(nil)
        vm.지도가_멈췄다(centerLat: 36.5, centerLng: 127.8, 사람이_옮겼나: false)   // 한반도로 여는 프로그램 이동
        #expect(!vm.좌표를_골랐나)

        vm.지도를_만졌다(centerLat: 35.1, centerLng: 129.0)
        #expect(vm.좌표를_골랐나)
        #expect(vm.원 == PlaceViewModel.반경_원(lat: 35.1, lng: 129.0, radiusMeters: 200))

        vm.지도가_멈췄다(centerLat: 35.2, centerLng: 129.1, 사람이_옮겼나: true)
        #expect(vm.원?.lat == 35.2)
        vm.지도가_멈췄다(centerLat: 1, centerLng: 2, 사람이_옮겼나: false)
        #expect(vm.원?.lat == 35.2)
        vm.지도가_멈췄다(centerLat: 91, centerLng: 0, 사람이_옮겼나: true)
        #expect(vm.원?.lat == 35.2)
        vm.반경 = 450
        #expect(vm.원?.radiusMeters == 450)
        #expect(vm.반경_문구 == "반경 450m")
    }

    @Test("(0,0)은 좌표가 아니다 — (0,0)으로 저장된 장소를 열면 한반도로 열고, 안 만진 채 저장하면 막으며, 만진 순간의 가운데로 저장한다(주인 판정)")
    func 영점은_저장하지_않는다() async {
        let f = PlaceFakes()
        let vm = 만든다(f)
        await 시작하고_위치를_읽는다(vm)
        let 영점 = PlaceDoc(id: "zero", name: "학교", lat: 0, lng: 0, radiusMeters: 200, notifyEnter: true, notifyExit: true)
        vm.편집을_연다(영점)
        #expect(!vm.좌표를_골랐나)
        #expect(vm.원 == nil)
        #expect(vm.카메라_요청 == PlaceViewModel.카메라(lat: 36.5, lng: 127.8, zoom: 6, 번호: 1))
        vm.지도를_만졌다(centerLat: 0, centerLng: 0)
        #expect(!vm.좌표를_골랐나)
        await vm.저장을_눌렀다()
        #expect(vm.편집_줄 == "아이 폰 위치를 아직 몰라서 지도가 넓게 열렸어요. 손으로 옮겨 찾아주세요.")
        #expect(await f.log.저장한_장소.isEmpty)

        vm.지도를_만졌다(centerLat: 36.5, centerLng: 127.8)
        await vm.저장을_눌렀다()
        #expect(await f.log.저장한_장소.map { [$0.lat, $0.lng] } == [[36.5, 127.8]])
    }

    @Test("반경은 50m 눈금에 맞추고 100~1000 으로 자르며, 0 은 '안 정해짐'이라 기본 200 으로 연다(:476, :538-549)")
    func 반경_눈금() {
        #expect(PlaceViewModel.반경을_눈금에(175) == 200)
        #expect(PlaceViewModel.반경을_눈금에(174) == 150)
        #expect(PlaceViewModel.반경을_눈금에(125) == 150)
        #expect(PlaceViewModel.반경을_눈금에(25) == 100)
        #expect(PlaceViewModel.반경을_눈금에(5000) == 1000)

        let f = PlaceFakes()
        let vm = 만든다(f)
        vm.편집을_연다(장소("p", "학교", radius: 175))
        #expect(vm.반경 == 200)
        #expect(vm.좌표를_골랐나)
        vm.취소를_눌렀다()
        vm.편집을_연다(장소("q", "학원", radius: 0))
        #expect(vm.반경 == 200)
    }

    @Test("이름은 20자에서 멈추고, 공백뿐이면 저장을 막는다 — 알림 문구에 그대로 들어가는 이름이다(:588-609, fragment_place.xml:187)")
    func 이름() async {
        let f = PlaceFakes()
        let vm = 만든다(f, 아이_위치: (37.5, 127))
        await 시작하고_위치를_읽는다(vm)
        vm.편집을_연다(nil)
        vm.이름을_바꾼다(String(repeating: "가", count: 25))
        #expect(vm.이름.count == 20)
        vm.이름을_바꾼다("   ")
        await vm.저장을_눌렀다()
        #expect(vm.이름_경고)
        #expect(await f.log.저장한_장소.isEmpty)
    }

    @Test("저장은 다듬은 이름과 편집 좌표·반경·스위치로 쓰고, 끝나야 닫고, sync_rules 를 보내 깃발을 내린다(:658-694, :620-656)")
    func 저장_흐름() async {
        let f = PlaceFakes()
        let vm = 만든다(f, 아이_위치: (37.5665, 126.978), 저장이_기다린다: true)
        await 시작하고_위치를_읽는다(vm)
        vm.편집을_연다(nil)
        vm.이름을_바꾼다("  학교 ")
        vm.반경 = 300
        vm.나섬_알림 = false
        #expect(vm.알림_없음_안내가_보이나 == false)
        let 저장 = Task { await vm.저장을_눌렀다() }
        await eventually { vm.저장_중 }
        #expect(vm.편집_줄 == "저장 중…")
        #expect(vm.pendingSync)

        await f.저장_문.open()
        await 저장.value
        #expect(!vm.편집_중)
        #expect(await f.log.저장한_장소 == [PlaceDoc(id: "new-1", name: "학교", lat: 37.5665, lng: 126.978, radiusMeters: 300, notifyEnter: true, notifyExit: false)])
        #expect(await f.log.보낸_명령 == [CommandType.syncRules])
        #expect(!vm.pendingSync)
    }

    @Test("쓰기가 거부되면 편집기가 열린 채 이유를 말하고, 저장 중에 뒤로 갔으면 그 이유는 목록 줄로 간다(:688-692, 판정 기록 3)")
    func 쓰기_실패와_뒤로_가기() async {
        let f = PlaceFakes()
        let vm = 만든다(f, 아이_위치: (37.5, 127), 저장이_기다린다: true)
        await f.log.쓰기_오류를_둔다(가짜_오류())
        await 시작하고_위치를_읽는다(vm)

        vm.편집을_연다(nil)
        vm.이름을_바꾼다("학교")
        let 첫_저장 = Task { await vm.저장을_눌렀다() }
        await eventually { vm.저장_중 }
        await f.저장_문.open()
        await 첫_저장.value
        #expect(vm.편집_중)
        #expect(!vm.저장_중)
        #expect(vm.편집_줄 == errorMessage(가짜_오류()))

        let g = PlaceFakes()
        let 떠난 = 만든다(g, 아이_위치: (37.5, 127), 저장이_기다린다: true)
        await g.log.쓰기_오류를_둔다(가짜_오류())
        await 시작하고_위치를_읽는다(떠난)
        떠난.편집을_연다(nil)
        떠난.이름을_바꾼다("학원")
        let 두번째_저장 = Task { await 떠난.저장을_눌렀다() }
        await eventually { 떠난.저장_중 }
        떠난.뒤로_갔다()
        떠난.편집을_연다(nil)
        await g.저장_문.open()
        await 두번째_저장.value
        #expect(떠난.편집_중)
        #expect(떠난.편집_줄 == nil)
        #expect(떠난.상태_줄 == errorMessage(가짜_오류()))
    }

    @Test("삭제는 요약을 대고 물은 뒤 지우고 알린다. 알림이 실패하면 깃발이 남고, 다시 알리면 내린다(:696-721, :723-787)")
    func 삭제와_재시도() async {
        let f = PlaceFakes()
        let vm = 만든다(f)
        vm.시작한다()
        let 학교 = 장소("school", "학교")
        vm.삭제를_눌렀다(학교)
        #expect(vm.삭제_확인 == 학교)
        #expect(vm.삭제_확인_문구 == "학교 (반경 200m)\n\n지우면 이곳에 도착하거나 나서도 알림이 오지 않아요.")
        vm.삭제_확인 = nil

        await f.log.명령_오류를_둔다(가짜_오류())
        await vm.삭제를_확인했다(학교)
        #expect(await f.log.지운_ID == ["school"])
        #expect(vm.상태_줄 == String(format: String(localized: "place_sync_failed_format"), errorMessage(가짜_오류())))
        #expect(vm.pendingSync)

        await f.log.명령_오류를_둔다(nil)
        await vm.다시_알린다()?.value
        #expect(!vm.pendingSync)
        #expect(await f.log.보낸_명령 == [CommandType.syncRules])
    }

    @Test("정리하면 리스너를 떼고, 늦게 도착한 아이 위치로 지도를 옮기지 않으며, 다시 구독하지 않는다(:899-919, 4단계 통합 검토 M1)")
    func 정리() async {
        let f = PlaceFakes()
        let vm = 만든다(f, 아이_위치: (37.5, 127.0), 위치가_기다린다: true)
        vm.시작한다()
        vm.편집을_연다(nil)
        let 읽기 = vm.아이_위치_읽기
        vm.정리한다()
        #expect(f.목록_등록.removed)
        await f.위치_문.open()
        await 읽기?.value
        #expect(!vm.좌표를_골랐나)
        #expect(vm.카메라_요청?.번호 == 1)
        #expect(vm.다시_알린다() == nil)

        let g = PlaceFakes()
        let 먼저_닫힘 = 만든다(g)
        먼저_닫힘.정리한다()
        먼저_닫힘.시작한다()
        #expect(g.목록.value == nil)
    }

    @Test("저장이 도는 중에 정리되면 늦게 온 결과로 화면을 만지지도 sync_rules 를 보내지도 않고, 깃발은 남아 다음 세션이 보낸다(5단계 통합 검토 I1)")
    func 정리_뒤_늦은_저장() async {
        let f = PlaceFakes()
        let store = RuleSyncStore(kind: .place, defaults: TestDefaults.isolated("PlaceViewModelTests-late-save"))
        let vm = 만든다(f, store: store, 아이_위치: (37.5, 127.0), 저장이_기다린다: true)
        await 시작하고_위치를_읽는다(vm)
        vm.편집을_연다(nil)
        vm.이름을_바꾼다("학교")
        let 저장 = Task { await vm.저장을_눌렀다() }
        await eventually { vm.저장_중 }
        vm.정리한다()
        await f.저장_문.open()
        await 저장.value
        #expect(await f.log.저장한_장소.map(\.id) == ["new-1"])
        #expect(await f.log.보낸_명령.isEmpty)
        #expect(store.pendingSync(childUid: "child"))
        #expect(vm.pendingSync)
        #expect(vm.편집_중)
        #expect(vm.저장_중)
        #expect(vm.편집_줄 == "저장 중…")
        #expect(vm.상태_줄 == nil)
    }

    @Test("삭제가 도는 중에 정리되면 늦게 온 결과로 목록 줄을 바꾸지도 sync_rules 를 보내지도 않고, 깃발은 남는다(5단계 통합 검토 I1)")
    func 정리_뒤_늦은_삭제() async {
        let f = PlaceFakes()
        let store = RuleSyncStore(kind: .place, defaults: TestDefaults.isolated("PlaceViewModelTests-late-delete"))
        let vm = 만든다(f, store: store, 삭제가_기다린다: true)
        vm.시작한다()
        let 삭제 = Task { await vm.삭제를_확인했다(장소("school", "학교")) }
        await eventually { vm.pendingSync }
        let 지우는_중 = vm.상태_줄
        #expect(지우는_중 == String(localized: "place_deleting"))
        vm.정리한다()
        await f.삭제_문.open()
        await 삭제.value
        #expect(await f.log.지운_ID == ["school"])
        #expect(await f.log.보낸_명령.isEmpty)
        #expect(store.pendingSync(childUid: "child"))
        #expect(vm.pendingSync)
        #expect(vm.상태_줄 == 지우는_중)
    }

    @Test("sync_rules 발행을 기다리는 중에 정리되면 늦게 온 성공으로 깃발을 내리지 않는다 — 다음 세션이 한 번 더 보낸다(5단계 통합 검토 I1)")
    func 정리_뒤_늦은_알림() async {
        let f = PlaceFakes()
        let store = RuleSyncStore(kind: .place, defaults: TestDefaults.isolated("PlaceViewModelTests-late-command"))
        let vm = 만든다(f, store: store, 명령이_기다린다: true)
        vm.시작한다()
        let 삭제 = Task { await vm.삭제를_확인했다(장소("school", "학교")) }
        await f.명령_도착.wait()
        let 그때_줄 = vm.상태_줄
        vm.정리한다()
        await f.명령_문.open()
        await 삭제.value
        #expect(await f.log.보낸_명령 == [CommandType.syncRules])
        #expect(store.pendingSync(childUid: "child"))
        #expect(vm.pendingSync)
        #expect(vm.상태_줄 == 그때_줄)
    }

    @Test("정리 뒤에 늦게 도착한 스냅샷·오류 콜백은 목록도 상태 줄도 바꾸지 않는다(5단계 통합 검토 M2)")
    func 정리_뒤_늦은_콜백() async {
        let f = PlaceFakes()
        let vm = 만든다(f)
        vm.시작한다()
        f.목록.value?([장소("a", "학교")], false)
        await eventually { vm.places.count == 1 }
        let 바뀜 = f.목록.value
        let 오류 = f.목록_오류.value
        vm.정리한다()
        바뀜?([], true)
        오류?(가짜_오류())
        await 메인_대기열을_비운다()
        #expect(vm.places.map(\.id) == ["a"])
        #expect(vm.listLoad == ListLoad.after(fromCache: false))
        #expect(vm.상태_줄 == nil)
    }
}
