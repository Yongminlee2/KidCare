import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 예약 탭 가짜 Firestore. 쓰기는 기록하고, 테스트가 정한 오류를 던진다.
private actor ScheduleFakeLog {
    private(set) var 저장한_규칙: [ScheduleDoc] = []
    private(set) var 지운_ID: [String] = []
    private(set) var 저장한_기본_모드: [String] = []
    private(set) var 저장한_공휴일: [Bool] = []
    private(set) var 보낸_명령: [String] = []
    private var 쓰기_오류: (any Error)?
    private var 명령_오류: (any Error)?

    func 쓰기_오류를_둔다(_ error: (any Error)?) { 쓰기_오류 = error }
    func 명령_오류를_둔다(_ error: (any Error)?) { 명령_오류 = error }

    func 저장(_ doc: ScheduleDoc) throws -> String {
        if let 쓰기_오류 { throw 쓰기_오류 }
        저장한_규칙.append(doc)
        return doc.id
    }
    func 지운다(_ id: String) throws {
        if let 쓰기_오류 { throw 쓰기_오류 }
        지운_ID.append(id)
    }
    func 기본_모드를_쓴다(_ mode: String) throws {
        if let 쓰기_오류 { throw 쓰기_오류 }
        저장한_기본_모드.append(mode)
    }
    func 공휴일을_쓴다(_ on: Bool) throws {
        if let 쓰기_오류 { throw 쓰기_오류 }
        저장한_공휴일.append(on)
    }
    func 명령(_ type: String) throws -> String {
        if let 명령_오류 { throw 명령_오류 }
        보낸_명령.append(type)
        return "cmd-\(보낸_명령.count)"
    }
}

/// 한 테스트가 쓰는 가짜 한 벌.
private final class ScheduleFakes: Sendable {
    let log = ScheduleFakeLog()
    let sleep = WriteSleepFake()
    let 저장_문 = TestGate()
    let 목록 = TestCallbackBox<([ScheduleDoc], Bool) -> Void>()
    let 설정 = TestCallbackBox<(RingerSettingsDoc) -> Void>()
    let 설정_오류 = TestCallbackBox<(Error) -> Void>()
    let 목록_등록 = TestListenerRegistration()
    let 설정_등록 = TestListenerRegistration()
}

/// 정본은 안드로이드 `guardian/ScheduleFragment.kt`. 줄 번호는 각 테스트 이름에 적었다.
@MainActor
struct ScheduleViewModelTests {

    private struct 가짜_오류: Error {}

    private func 만든다(
        _ f: ScheduleFakes,
        childUid: String? = "child",
        store: RuleSyncStore? = nil,
        저장이_기다린다: Bool = false,
        holidayNext: @escaping (DateComponents) -> (DateComponents, Holiday)? = { _ in nil }
    ) -> ScheduleViewModel {
        var 번호 = 0
        return ScheduleViewModel(
            familyId: "family",
            childUid: childUid,
            syncStore: store ?? RuleSyncStore(kind: .schedule, defaults: TestDefaults.isolated("ScheduleViewModelTests")),
            schedulesObserve: { _, _, onChange, _ in
                f.목록.set(onChange)
                return f.목록_등록
            },
            settingsObserve: { _, _, onChange, onError in
                f.설정.set(onChange)
                f.설정_오류.set(onError)
                return f.설정_등록
            },
            scheduleSave: { _, _, doc in
                if 저장이_기다린다 { await f.저장_문.wait() }
                return try await f.log.저장(doc)
            },
            scheduleDelete: { _, _, id in try await f.log.지운다(id) },
            defaultModeSave: { _, _, mode in try await f.log.기본_모드를_쓴다(mode) },
            holidayOffSave: { _, _, on in try await f.log.공휴일을_쓴다(on) },
            commandSend: { _, _, type, _ in try await f.log.명령(type) },
            writeSleep: { millis in await f.sleep.sleep(millis) },
            today: { DateComponents(year: 2026, month: 9, day: 13) },
            holidayNext: holidayNext,
            newId: {
                번호 += 1
                return "new-\(번호)"
            }
        )
    }

    private func 규칙(_ id: String, _ start: Int, _ end: Int, days: [Int] = [1, 2, 3, 4, 5],
                    mode: String = RingerMode.vibrate, enabled: Bool = true, priority: Int = 0) -> ScheduleDoc {
        ScheduleDoc(id: id, days: days, startMinute: start, endMinute: end, mode: mode, enabled: enabled, priority: priority)
    }

    private func 목록을_받는다(_ f: ScheduleFakes, _ vm: ScheduleViewModel, _ docs: [ScheduleDoc], fromCache: Bool = false) async {
        f.목록.value?(docs, fromCache)
        await eventually { vm.rules.count == docs.count && vm.listLoad == ListLoad.after(fromCache: fromCache) }
    }

    @Test("스냅샷은 시작·끝·ID 순으로 정렬하고, 캐시본이면 아직 '없어요'라고 말하지 않는다(:410-422)")
    func 정렬과_캐시() async {
        let f = ScheduleFakes()
        let vm = 만든다(f)
        vm.시작한다()
        await 목록을_받는다(f, vm, [규칙("b", 1320, 420), 규칙("a", 540, 900), 규칙("c", 540, 600)], fromCache: true)
        #expect(vm.rules.map(\.id) == ["c", "a", "b"])
        #expect(vm.listLoad.emptyText(isEmpty: true, loaded: "없음") == "불러오는 중이에요…")
        await 목록을_받는다(f, vm, [], fromCache: false)
        #expect(vm.listLoad.emptyText(isEmpty: vm.rules.isEmpty, loaded: "없음") == "없음")
    }

    @Test("아이가 없으면 구독하지 않고, 목록은 '불러옴'에 안내 한 줄이다(:351-357)")
    func 아이_없음() {
        let f = ScheduleFakes()
        let vm = 만든다(f, childUid: nil)
        vm.시작한다()
        #expect(vm.listLoad == .loaded)
        #expect(vm.상태_줄 == String(localized: "map_no_child"))
        #expect(f.목록.value == nil)
        #expect(vm.다시_알린다() == nil)
    }

    @Test("요일이 비면 저장하지 않고 경고하며, 하나라도 고르면 경고를 거둔다(:474-493, :251-253)")
    func 요일_없음() async {
        let f = ScheduleFakes()
        let vm = 만든다(f)
        vm.시작한다()
        vm.편집을_연다(nil)
        for day in 1...5 { vm.요일을_누른다(day) }
        await vm.저장을_눌렀다()
        #expect(vm.요일_경고)
        #expect(vm.편집_중)
        #expect(await f.log.저장한_규칙.isEmpty)
        vm.요일을_누른다(6)
        #expect(!vm.요일_경고)
    }

    @Test("시작과 끝이 같으면 하루 종일인지 먼저 묻고, 확인하면 저장한다(:480-482, :503-518)")
    func 하루_종일() async {
        let f = ScheduleFakes()
        let vm = 만든다(f)
        vm.시작한다()
        vm.편집을_연다(nil)
        vm.시작분 = 0
        vm.끝분 = 0
        await vm.저장을_눌렀다()
        #expect(vm.확인창 == .하루_종일(message: "시작과 끝이 00:00(으)로 같아요.\n이대로 저장하면 고른 요일에는 24시간 내내 진동(으)로 바뀝니다."))
        #expect(await f.log.저장한_규칙.isEmpty)
        vm.확인창 = nil
        await vm.하루_종일을_확인했다()
        #expect(await f.log.저장한_규칙.map(\.startMinute) == [0])
    }

    @Test("겹치면 첫 규칙 이름과 나머지 개수를 대고 묻는다 — 꺼둔 규칙과는 겹침을 말하지 않는다(:520-561)")
    func 겹침() async {
        let f = ScheduleFakes()
        let vm = 만든다(f)
        vm.시작한다()
        await 목록을_받는다(f, vm, [
            규칙("night", 1320, 420),
            규칙("eve", 1200, 1380),
            규칙("off", 1260, 300, enabled: false),
        ])
        vm.편집을_연다(nil)   // 기본값 평일 21:00~07:00 진동
        await vm.저장을_눌렀다()
        #expect(vm.확인창 == .겹침(message: "이 시간대는 '평일 · 20:00 ~ 23:00 · 진동' 외 1개 규칙과 겹칩니다.\n겹치는 동안에는 나중에 만든 규칙이 이깁니다."))
        #expect(await f.log.저장한_규칙.isEmpty)
        vm.확인창 = nil
        await vm.겹쳐도_저장한다()
        #expect(await f.log.저장한_규칙.count == 1)
    }

    @Test("새 규칙은 나중에 만든 것이 이긴다 — 스냅샷 전에 두 번 저장해도 우선순위가 겹치지 않고, 고치기는 원래 값을 지킨다(:171-181, :582-588, :976-977)")
    func 우선순위() async {
        let f = ScheduleFakes()
        let vm = 만든다(f)
        vm.시작한다()
        await 목록을_받는다(f, vm, [규칙("old", 540, 600, priority: 4)])
        vm.편집을_연다(nil)
        await vm.저장을_눌렀다()
        vm.편집을_연다(nil)
        await vm.저장을_눌렀다()
        vm.편집을_연다(규칙("old", 540, 600, priority: 4))
        vm.끝분 = 660
        await vm.저장을_눌렀다()
        let 저장 = await f.log.저장한_규칙
        #expect(저장.map(\.id) == ["new-1", "new-2", "old"])
        #expect(저장.map(\.priority) == [5, 6, 4])
    }

    @Test("저장은 편집을 열 때 정한 ID 로, 깃발을 먼저 세우고, 끝나야 편집기를 닫고, sync_rules 를 보낸 뒤 깃발을 내린다(:151-160, :575-629, :894-933)")
    func 저장_흐름() async {
        let f = ScheduleFakes()
        let store = RuleSyncStore(kind: .schedule, defaults: TestDefaults.isolated("ScheduleViewModelTests-flow"))
        let vm = 만든다(f, store: store, 저장이_기다린다: true)
        vm.시작한다()
        vm.편집을_연다(nil)
        #expect(vm.editorNewDocId == "new-1")
        let 저장 = Task { await vm.저장을_눌렀다() }
        await eventually { vm.저장_중 }
        #expect(vm.편집_줄 == "저장 중…")
        #expect(vm.편집_중)
        #expect(vm.pendingSync)
        #expect(store.pendingSync(childUid: "child"))

        await f.저장_문.open()
        await 저장.value
        #expect(!vm.편집_중)
        #expect(vm.상태_줄 == nil)
        #expect(await f.log.저장한_규칙.map(\.id) == ["new-1"])
        #expect(await f.log.저장한_규칙.map(\.days) == [[1, 2, 3, 4, 5]])
        #expect(await f.log.보낸_명령 == [CommandType.syncRules])
        #expect(!vm.pendingSync)
        #expect(!store.pendingSync(childUid: "child"))
    }

    @Test("쓰기가 거부되면 편집기는 열린 채 이유를 말하고 입력값을 지킨다 — 알림은 안 보내고 깃발은 남는다(:567-573, :621-627)")
    func 쓰기_실패() async {
        let f = ScheduleFakes()
        let vm = 만든다(f)
        await f.log.쓰기_오류를_둔다(가짜_오류())
        vm.시작한다()
        vm.편집을_연다(nil)
        vm.요일을_누른다(6)
        await vm.저장을_눌렀다()
        #expect(vm.편집_중)
        #expect(!vm.저장_중)
        #expect(vm.편집_줄 == errorMessage(가짜_오류()))
        #expect(vm.요일 == [1, 2, 3, 4, 5, 6])
        #expect(await f.log.보낸_명령.isEmpty)
        #expect(vm.pendingSync)
    }

    @Test("15초 안에 서버 확인이 없으면 편집기를 닫고 '저장 요청은 보냈지만' 줄을 남긴다 — 알림은 그래도 보낸다(:610-617)")
    func 서버_확인_없음() async {
        let f = ScheduleFakes()
        let vm = 만든다(f, 저장이_기다린다: true)
        vm.시작한다()
        vm.편집을_연다(nil)
        let 저장 = Task { await vm.저장을_눌렀다() }
        await eventually { vm.저장_중 }
        await f.sleep.첫_번째.open()
        await 저장.value
        #expect(!vm.편집_중)
        #expect(vm.상태_줄 == String(localized: "schedule_save_slow"))
        #expect(await f.log.보낸_명령 == [CommandType.syncRules])
    }

    @Test("알림 발행이 실패하면 깃발이 남아 이유를 말하고, 다음에 탭을 열면(다시_알린다) 한 번 더 보내 깃발을 내린다(:913-933, :935-969)")
    func 명령_실패와_재시도() async {
        let f = ScheduleFakes()
        let store = RuleSyncStore(kind: .schedule, defaults: TestDefaults.isolated("ScheduleViewModelTests-retry"))
        store.setPendingSync(childUid: "child", true)   // 지난 세션에서 못 보낸 알림
        let vm = 만든다(f, store: store)
        await f.log.명령_오류를_둔다(가짜_오류())
        vm.시작한다()
        #expect(vm.pendingSync)

        await vm.다시_알린다()?.value
        #expect(vm.상태_줄 == String(format: String(localized: "schedule_sync_failed_format"), errorMessage(가짜_오류())))
        #expect(vm.pendingSync)

        await f.log.명령_오류를_둔다(nil)
        await vm.다시_알린다()?.value
        #expect(!vm.pendingSync)
        #expect(!store.pendingSync(childUid: "child"))
        #expect(await f.log.보낸_명령 == [CommandType.syncRules])
    }

    @Test("저장 중에 뒤로 가면 늦게 온 실패는 목록 줄로 가고, 그사이 새로 연 편집기는 닫지 않는다(판정 기록 3)")
    func 뒤로_가기_중_실패() async {
        let f = ScheduleFakes()
        let vm = 만든다(f, 저장이_기다린다: true)
        await f.log.쓰기_오류를_둔다(가짜_오류())
        vm.시작한다()
        vm.편집을_연다(nil)
        let 저장 = Task { await vm.저장을_눌렀다() }
        await eventually { vm.저장_중 }

        vm.취소를_눌렀다()          // 안드로이드처럼 취소 버튼은 막힌다
        #expect(vm.편집_중)
        vm.뒤로_갔다()              // 시스템 뒤로 버튼은 막을 수 없다
        #expect(!vm.편집_중)
        vm.편집을_연다(nil)

        await f.저장_문.open()
        await 저장.value
        #expect(vm.편집_중)
        #expect(vm.편집_줄 == nil)
        #expect(vm.상태_줄 == errorMessage(가짜_오류()))
        #expect(await f.log.보낸_명령.isEmpty)
    }

    @Test("기본 모드·공휴일 저장이 거부되면 화면도 되돌린다 — 고른 것으로 보이는데 안 바뀐 것이 가장 나쁜 거짓말(:722-727, :801-805)")
    func 설정_되돌리기() async {
        let f = ScheduleFakes()
        let vm = 만든다(f)
        vm.시작한다()
        f.설정.value?(RingerSettingsDoc(["defaultMode": RingerMode.normal, "holidayOff": false]))
        await eventually { vm.defaultMode == RingerMode.normal }

        await f.log.쓰기_오류를_둔다(가짜_오류())
        await vm.기본_모드를_고른다(RingerMode.silent)
        #expect(vm.defaultMode == RingerMode.normal)
        #expect(vm.상태_줄 == errorMessage(가짜_오류()))
        await vm.공휴일을_바꾼다(true)
        #expect(!vm.holidayOff)

        await f.log.쓰기_오류를_둔다(nil)
        await vm.기본_모드를_고른다(RingerMode.silent)
        #expect(vm.defaultMode == RingerMode.silent)
        #expect(vm.상태_줄 == "규칙이 끝나면 무음(으)로 돌아가요.")
        await vm.기본_모드를_고른다("")
        #expect(vm.상태_줄 == "규칙이 끝나도 소리를 그대로 둬요.")
        await vm.공휴일을_바꾼다(true)
        #expect(vm.상태_줄 == "공휴일에는 예약을 쉬어요.")
        #expect(await f.log.저장한_기본_모드 == [RingerMode.silent, ""])
        #expect(await f.log.보낸_명령.count == 3)
    }

    @Test("공휴일 줄은 켜졌을 때만 다음 쉬는 날을 적고, 계산을 못 하면 그렇게 말한다. 설정을 못 읽으면 스위치를 잠근다(:382-388, :810-835)")
    func 공휴일_안내() async {
        let f = ScheduleFakes()
        let vm = 만든다(f, holidayNext: { _ in (DateComponents(year: 2026, month: 10, day: 3), .foundation) })
        #expect(vm.공휴일_안내 == "쉬는 날에는 아래 규칙을 하나도 켜지 않아요.")
        vm.시작한다()
        f.설정.value?(RingerSettingsDoc(["holidayOff": true]))
        await eventually { vm.holidayOff }
        #expect(vm.공휴일_안내 == "다음 쉬는 날은 10월 3일 개천절이에요.")
        f.설정_오류.value?(가짜_오류())
        await eventually { vm.설정_잠김 }

        let g = ScheduleFakes()
        let 모름 = 만든다(g)
        모름.시작한다()
        g.설정.value?(RingerSettingsDoc(["holidayOff": true]))
        await eventually { 모름.holidayOff }
        #expect(모름.공휴일_안내 == "이 기기에서는 공휴일 날짜를 계산하지 못했어요. 스위치를 켜도 요일대로만 돌아요.")
    }

    @Test("켬끔은 그 규칙을 enabled 만 바꿔 저장하고, 삭제는 요약을 대고 물은 뒤 지운다 — 둘 다 알림을 보낸다(:631-666, :852-892)")
    func 켬끔과_삭제() async {
        let f = ScheduleFakes()
        let vm = 만든다(f)
        vm.시작한다()
        let 낮 = 규칙("a", 540, 900, priority: 2)
        await vm.켬끔을_바꾼다(낮, enabled: false)
        #expect(await f.log.저장한_규칙 == [규칙("a", 540, 900, enabled: false, priority: 2)])

        vm.삭제를_눌렀다(낮)
        #expect(vm.확인창 == .삭제(낮, message: "평일 · 09:00 ~ 15:00 · 진동\n\n지우면 이 시간대에는 소리가 저절로 바뀌지 않아요."))
        vm.확인창 = nil
        await vm.삭제를_확인했다(낮)
        #expect(await f.log.지운_ID == ["a"])
        #expect(vm.상태_줄 == nil)
        #expect(await f.log.보낸_명령 == [CommandType.syncRules, CommandType.syncRules])
    }

    @Test("정리하면 리스너 둘을 떼고, 그 뒤로는 다시 구독하지도 알림을 보내지도 않는다(:1158-1177, 4단계 통합 검토 M1)")
    func 정리() async {
        let f = ScheduleFakes()
        let store = RuleSyncStore(kind: .schedule, defaults: TestDefaults.isolated("ScheduleViewModelTests-close"))
        store.setPendingSync(childUid: "child", true)
        let vm = 만든다(f, store: store)
        vm.시작한다()
        vm.정리한다()
        #expect(f.목록_등록.removed)
        #expect(f.설정_등록.removed)
        #expect(vm.다시_알린다() == nil)
        vm.시작한다()
        #expect(await f.log.보낸_명령.isEmpty)

        let g = ScheduleFakes()
        let 먼저_닫힘 = 만든다(g)
        먼저_닫힘.정리한다()
        먼저_닫힘.시작한다()
        #expect(g.목록.value == nil)
    }

    @Test("저장이 도는 중에 정리되면 늦게 온 결과로 알림을 보내지 않고, 깃발은 남아 다음 세션이 보낸다(4단계 통합 검토 M1)")
    func 정리_뒤_늦은_저장() async {
        let f = ScheduleFakes()
        let store = RuleSyncStore(kind: .schedule, defaults: TestDefaults.isolated("ScheduleViewModelTests-late"))
        let vm = 만든다(f, store: store, 저장이_기다린다: true)
        vm.시작한다()
        vm.편집을_연다(nil)
        let 저장 = Task { await vm.저장을_눌렀다() }
        await eventually { vm.저장_중 }
        vm.정리한다()
        await f.저장_문.open()
        await 저장.value
        #expect(await f.log.저장한_규칙.map(\.id) == ["new-1"])
        #expect(await f.log.보낸_명령.isEmpty)
        #expect(store.pendingSync(childUid: "child"))
    }
}
