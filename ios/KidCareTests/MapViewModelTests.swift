import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 순수 날짜 이동 로직만 본다 — `childUid` 가 `nil` 이라 네트워크를 전혀 타지 않는다
/// (`이전_날로`/`다음_날로` 내부의 `guard let childUid else { return }` 가 곧바로
/// 물러난다). 정본은 안드로이드 `MapTimelineFragment.changeDay`(:848) 다.
///
/// **UI 없이 돈다** — Task 5(명령 왕복)·7(실시간 세션)이 상태 기계를 뷰 밖으로
/// 옮기는 이유가 바로 이것이다(Task 4 브리프 "계획서 표류 정리"): 시뮬레이터를
/// 띄우지 않고도 `MapViewModel` 하나만 만들어 날짜 이동을 검증할 수 있다.
@MainActor
struct MapViewModelDayNavigationTests {

    @Test("오늘로 시작하고, 오늘에서는 다음 날로 갈 수 없다")
    func 오늘에서_시작한다() {
        let vm = MapViewModel(familyId: "family", childUid: nil)
        let 오늘 = DayPicker.todayKey(zone: .current, nowMillis: Int64(Date().timeIntervalSince1970 * 1000))
        #expect(vm.dayKey == 오늘)
        #expect(vm.다음_날로_갈_수_있는가 == false)
    }

    @Test("오늘에서 다음 날을 여러 번 눌러도 미래로는 못 간다")
    func 미래로_못_간다() async {
        let vm = MapViewModel(familyId: "family", childUid: nil)
        let 오늘 = vm.dayKey
        await vm.다음_날로()
        #expect(vm.dayKey == 오늘)
        // 한 번만 막고 그다음은 안 막는 버그(예: 플래그를 한 번만 검사)를 잡는다.
        await vm.다음_날로()
        await vm.다음_날로()
        #expect(vm.dayKey == 오늘)
    }

    @Test("이전 날로 갔다가 다음 날로 돌아오면 오늘이고, 다음 날 버튼이 다시 막힌다")
    func 이전_다음_왕복() async {
        let vm = MapViewModel(familyId: "family", childUid: nil)
        let 오늘 = vm.dayKey

        await vm.이전_날로()
        #expect(vm.dayKey == DayPicker.shift(dayKey: 오늘, days: -1))
        #expect(vm.다음_날로_갈_수_있는가 == true)

        await vm.다음_날로()
        #expect(vm.dayKey == 오늘)
        #expect(vm.다음_날로_갈_수_있는가 == false)
    }

    @Test("이틀 전까지도 물러날 수 있다 — 하루만 막혀 있는 게 아니다")
    func 이틀_전으로_물러난다() async {
        let vm = MapViewModel(familyId: "family", childUid: nil)
        let 오늘 = vm.dayKey
        await vm.이전_날로()
        await vm.이전_날로()
        #expect(vm.dayKey == DayPicker.shift(dayKey: 오늘, days: -2))
        #expect(vm.다음_날로_갈_수_있는가 == true)
    }
}

/// 날짜를 바꾸면 실제로 그 날의 경로·타임라인이 바뀌는지, 그리고 상태 카드는
/// 손대지 않는지를 에뮬레이터로 확인한다(보안 규칙까지 실제로 태운다). 정본은
/// 안드로이드 `MapTimelineFragment.load`(:304)/`changeDay`(:848).
@Suite(.serialized)
struct MapViewModelReloadTests {

    init() async { await EmulatorHarness.start() }

    private func trailData(dayKey: String, placeName: String, at: Int64) -> [String: Any] {
        [
            "dayKey": dayKey,
            "points": [],
            "segments": [[
                "type": "STAY", "startAt": at, "endAt": at,
                "lat": 37.0, "lng": 127.0, "distanceMeters": 0.0,
                "pointCount": 1, "placeName": placeName,
            ]],
            "updatedAt": at,
        ]
    }

    @Test("날짜를 바꾸면 그 날의 경로·타임라인만 갈아끼우고, 상태 카드는 다시 읽지 않는다")
    @MainActor
    func 날짜를_바꾸면_그날_기록만_바뀐다() async throws {
        let owner = try await EmulatorHarness.freshUser()
        let familyId = try await FamilyRepository.createFamily(guardianUid: owner)
        let invite = try await FamilyRepository.createInvite(familyId: familyId, role: .child, previousCode: nil)

        let child = try await EmulatorHarness.freshUser()
        _ = try await FamilyRepository.joinFamily(
            code: invite.code, uid: child, expectedRole: .child, displayName: "아이"
        )

        let db = Firestore.firestore()
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let childRef = db.collection("families").document(familyId).collection("children").document(child)
        try await childRef.setData([
            "lat": 37.0, "lng": 127.0, "accuracy": 10.0,
            "at": nowMillis, "battery": 55, "charging": false,
            "ringerMode": "normal", "lastSeenAt": nowMillis,
        ])

        let vm = MapViewModel(familyId: familyId, childUid: child)
        let todayKey = vm.dayKey
        let yesterdayKey = DayPicker.shift(dayKey: todayKey, days: -1)
        // 그제는 일부러 문서를 두지 않는다 — "기록 없는 날"로 넘어갔을 때
        // 어제 기록이 눌어붙어 있지 않은지도 같이 본다.

        try await childRef.collection("trails").document(todayKey)
            .setData(trailData(dayKey: todayKey, placeName: "오늘장소", at: nowMillis))
        try await childRef.collection("trails").document(yesterdayKey)
            .setData(trailData(dayKey: yesterdayKey, placeName: "어제장소", at: nowMillis))

        await vm.하루를_읽는다()
        #expect(vm.하루기록?.segments.first?.placeName == "오늘장소")
        #expect(vm.상태?.battery == 55)

        // 상태 카드가 날짜 이동에 딸려 다시 읽히지 않는다는 것을, 서버 값을
        // 실제로 바꿔서 증명한다 — 다시 읽었다면 이 값이 보였을 것이다.
        try await childRef.updateData(["battery": 99])

        await vm.이전_날로()
        #expect(vm.dayKey == yesterdayKey)
        #expect(vm.하루기록?.segments.first?.placeName == "어제장소")
        #expect(vm.상태?.battery == 55)

        // 기록 없는 그제로 한 번 더 물러난다 — 어제 기록이 그대로 남아 있으면 안 된다.
        await vm.이전_날로()
        #expect(vm.하루기록 == nil)
        #expect(vm.타임라인_행.isEmpty)
        #expect(vm.경로_구간.isEmpty)

        await vm.다음_날로()
        await vm.다음_날로()
        #expect(vm.dayKey == todayKey)
        #expect(vm.하루기록?.segments.first?.placeName == "오늘장소")
        #expect(vm.상태?.battery == 55)
    }
}
