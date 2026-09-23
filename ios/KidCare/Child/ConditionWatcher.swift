import Foundation
import os

/// 아이 폰이 **자기 상태**를 감시해 부모에게 알린다. 정본은 `child/ConditionWatcher.kt` 다.
///
/// 장소 사건(`PlaceWatcher`)이 "아이가 어디 갔다"라면 여기는 "이 폰이 지금 제구실을 못 하고
/// 있다"이다. 쓰는 길은 완전히 같다 — `EventRepository.add` 로 `events/` 에 문서 하나.
/// 규칙과의 계약(`childUid`·`read == false`·`at` 은 밀리초 정수)도 그대로다(`:11-15`).
///
/// ## 권한이 꺼진 것이 이 앱에서 제일 중요한 경고다
///
/// 배터리가 없으면 폰이 꺼지고, 폰이 꺼지면 부모 화면의 연결 끊김 배너가 결국 뜬다 — 늦어도
/// 알기는 안다. 그런데 **권한만 꺼지면 앱은 멀쩡히 켜져 있다.** 파란 위치 표시도 그대로 뜨고,
/// 4시간 유휴 업로드(설계서 §6.4 규칙 2)가 상태 문서를 계속 새로 찍어 부모 화면의 "마지막
/// 신호"까지 살아 있다. 그저 그날 하루가 조용할 뿐이다. 부모는 그것을 "오늘은 별일 없었구나"로
/// 읽는다(`:17-25` 의 같은 문단). **이 감시가 그 침묵에 이유를 붙이는 유일한 입이다**
/// (3단계 판정 기록 8).
///
/// ## 아이폰이 말할 수 없는 것
///
/// 앱이 강제 종료되거나 통째로 죽으면 이 감시도 함께 죽는다 — 말할 프로세스가 없다.
/// 그 자리는 부모 화면의 무응답 배너와 아이 화면의 강제 종료 안내가 나눠 덮는다(§5.3·§15-2).
///
/// ## 한 번만 알린다 — 프로세스가 죽어도
///
/// "이미 알렸다"를 메모리에 두면 앱이 다시 뜰 때마다 잊어버려, 12% 에 앉아 있는 폰이 재시작할
/// 때마다 같은 경고를 새로 올린다. 그래서 `UserDefaults` 에 적는다(코틀린의 SharedPreferences
/// `commit()` 자리, `:50-56`). `synchronize()` 는 **부르지 않는다** — 애플이 deprecated 로
/// 표시했고, `UserDefaults.set` 은 그 자리에서 메모리에 반영되며 디스크 플러시는 프로세스가
/// 죽어도 이어진다(2단계 `PlaceStateStore` 와 같은 판단).
///
/// **표시를 Firestore 쓰기보다 먼저 한다**(`:58-62`). 반대 순서면 오프라인일 때 쓰기가 매달린
/// 채로 검사가 다시 돌아 같은 경고가 여러 번 큐에 쌓이고, 연결이 돌아오는 순간 한꺼번에
/// 올라간다. 대가는 "쓰기가 진짜로 거부되면 그 경고 하나를 잃는다"뿐이다.
@MainActor
final class ConditionWatcher {

    /// 이 아래로 내려가면 알린다. `ConditionWatcher.kt:173`. 안드로이드가 스스로 '배터리 부족'
    /// 이라고 말하는 값과 같아서 아이도 같은 순간에 같은 경고를 본다(`:165-172`).
    static let lowPercent = 15
    /// 여기까지 충전되면 다음 한 번을 다시 알릴 수 있다. `:176`. 문턱을 벌린 것이
    /// `GeofenceEvaluator` 의 이탈 여유 50m 와 같은 히스테리시스다(`:85-93`).
    static let rearmPercent = 20

    /// 코틀린은 `kidcare_conditions` 라는 전용 SharedPreferences 파일에 `battery_reported`·
    /// `permissions_off` 로 적는다(`:66`·`:186-187`). iOS 의 `UserDefaults` 는 파일이 하나뿐이라
    /// 그 파일 이름을 키 앞에 붙여 같은 이름을 만든다 — 다른 기능의 키와 섞이지 않는다.
    private static let batteryKey = "kidcare_conditions.battery_reported"
    private static let permissionsKey = "kidcare_conditions.permissions_off"

    private let defaults: UserDefaults
    private let addEvent: (String, EventDoc) async throws -> Void
    private let logger = Logger(subsystem: "com.kidcare.family", category: "ConditionWatcher")

    init(defaults: UserDefaults = .standard,
         addEvent: @escaping (String, EventDoc) async throws -> Void = { familyId, doc in
             try await EventRepository.add(familyId: familyId, doc: doc)
         }) {
        self.defaults = defaults
        self.addEvent = addEvent
    }

    /// 한 번 훑고, **달라진 것이 있을 때만** `events/` 에 적는다. 아무것도 안 달라졌으면
    /// Firestore 를 한 번도 안 건드린다 — 읽기도 쓰기도 0 이다(`:71-74`).
    ///
    /// `batteryPercent` 와 `permissions` 를 여기서 읽지 않고 받는 이유는 코틀린과 같다(`:76-77`):
    /// `DeviceState` 와 화면이 이미 같은 값을 읽는다. 두 번 적으면 언젠가 한쪽만 고친다.
    func check(familyId: String, childUid: String, batteryPercent: Int,
               permissions: ChildPermissions.Snapshot, now: Int64) async throws {
        try await checkBattery(familyId: familyId, childUid: childUid, percent: batteryPercent, now: now)
        try await checkPermissions(familyId: familyId, childUid: childUid, permissions: permissions, now: now)
    }

    /// 배터리가 [lowPercent] 아래로 **처음** 내려갔을 때 한 번. 충전해서 [rearmPercent] 위로
    /// 올라오면 다시 한 번 알릴 수 있게 풀린다(`:84-107`). 알리는 문턱과 푸는 문턱을 벌려 둔 것이
    /// 핵심이다 — 같은 값으로 두면 14↔15 를 오가는 폰이 경고를 계속 올린다.
    private func checkBattery(familyId: String, childUid: String, percent: Int, now: Int64) async throws {
        // 못 읽으면(-1) 아무 판단도 하지 않는다. 그대로 흘려보내면 "0% 미만"이 되어 폰마다
        // 켜자마자 거짓 경고가 하나 나간다(`:96-98`). 시뮬레이터가 늘 이 상태다.
        guard (1...100).contains(percent) else { return }

        if defaults.bool(forKey: Self.batteryKey) {
            if percent >= Self.rearmPercent { defaults.set(false, forKey: Self.batteryKey) }
            return
        }
        guard percent < Self.lowPercent else { return }

        defaults.set(true, forKey: Self.batteryKey)
        try await add(familyId: familyId, childUid: childUid, type: EventType.lowBattery,
                      detail: String(format: String(localized: "event_detail_battery"), percent), now: now)
    }

    /// 지금 꺼져 있는 것들의 **이름 집합**을 통째로 기억한다. 이렇게 두면 "언제 꺼졌는가"를 따로
    /// 적을 필요 없이, 집합이 늘어난 순간이 곧 전환이다(`:114-117`). 다시 켠 것(집합이 줄어든
    /// 것)은 기억만 갱신하고 알리지 않는다 — 부모가 원하던 상태로 돌아간 것이라 소음이다.
    ///
    /// 여럿이 한꺼번에 꺼져도 문서는 하나다(`:119-121`). 위치를 통째로 끄면 '위치 권한'과
    /// '항상 허용'이 같이 꺼지는데, 그때 줄이 둘 뜨면 부모는 사고가 두 개 난 줄로 읽는다.
    ///
    /// 저장은 **정렬한 배열**로 한다. 코틀린은 `putStringSet` 이라 순서가 없는데 `UserDefaults`
    /// 에는 집합 타입이 없다 — 읽을 때 다시 `Set` 으로 만들므로 판정은 순서와 무관하고,
    /// 적을 때 정렬해 두면 같은 상태가 늘 같은 바이트라 저장소가 헛되이 갱신되지 않는다.
    private func checkPermissions(familyId: String, childUid: String,
                                  permissions: ChildPermissions.Snapshot, now: Int64) async throws {
        // **아직 묻지도 않은 권한은 꺼진 것이 아니다**(통합 검토 I1). CoreLocation 은 델리게이트가
        // 붙는 순간 상태가 `.notDetermined` 인 채로 권한 변경 콜백을 한 번 보낸다. 그것을 그대로
        // 판정하면 아이가 권한 대화상자에 답하기도 전에 부모에게 "애기폰에서 다시 켜주세요"가
        // 가고, 아이가 '허용'을 눌러도 **되돌리는 이벤트는 설계상 영영 안 온다**(집합이 줄어드는
        // 것은 안 알린다). 부모의 첫 5분에 읽지 않은 거짓 경고 하나가 영구히 남는다.
        //
        // 정본에서는 이 일이 일어날 수 없다 — 안드로이드의 감시는 `TrackingService` 안에서만 돌고
        // 그 서비스는 권한이 전부 켜진 뒤에야 뜬다(`ChildHomeActivity.kt:96-101`). 코틀린 주석도
        // 감시의 뜻을 "**켜져 있던** 권한이 꺼졌으면"이라고 못박았다(`ConditionWatcher.kt:110`).
        // iOS 는 감시가 먼저 살아 있으므로 같은 문을 여기에 만든다.
        //
        // **기억도 건드리지 않는다.** 여기서 `[]` 를 적어 두면 나중에 진짜로 꺼진 순간이 여전히
        // 첫 전환이라 결과는 같지만, "아직 아무것도 판정하지 않았다"를 그대로 두는 쪽이 정직하다.
        // 진짜 거부(`.denied`)와 '앱 사용 중만'(`.authorizedWhenInUse`)은 이 문을 지나 그대로 알린다.
        // 배터리 감시(`checkBattery`)는 권한과 무관하므로 이 문 밖에서 계속 돈다.
        guard !ChildPermissions.notYetAsked(permissions) else { return }

        let offNow = ChildPermissions.allMissing(permissions)
        let names = Set(offNow.map(\.rawValue))
        let reported = Set(defaults.stringArray(forKey: Self.permissionsKey) ?? [])
        guard names != reported else { return }

        defaults.set(names.sorted(), forKey: Self.permissionsKey)

        let fresh = offNow.filter { !reported.contains($0.rawValue) }
        guard !fresh.isEmpty else { return }
        let 이름들 = fresh.map(\.이름).joined(separator: ", ")
        try await add(familyId: familyId, childUid: childUid, type: EventType.permissionOff,
                      detail: String(format: String(localized: "event_detail_permission"), 이름들), now: now)
    }

    /// `at` 은 폰 시계다(`PlaceWatcher.onFix` 와 같은 판단, `:145-147`) — 규칙이 서버 시각과
    /// 대조해 과거 7일~미래 1시간 밖이면 거부하지만(`firestore.rules:306-310`. 코틀린 주석은
    /// 24시간이라고 적었는데 규칙이 7일이다. 2단계 판정 기록 12 가 같은 것을 기록했다),
    /// 여기서 "지금"으로 바꿔치기하면 일어난 시각을 지어내는 셈이다.
    ///
    /// 실패는 삼키지 않고 위로 던진다(`:149-150`). 부르는 쪽(`ChildSession`)이 로그로 남긴다 —
    /// 이벤트 하나를 못 쓴 것 때문에 위치 수집이 멈추면 안 된다.
    private func add(familyId: String, childUid: String, type: String, detail: String, now: Int64) async throws {
        logger.notice("조건 사건을 적는다: \(type, privacy: .public)")
        try await addEvent(familyId, EventDoc(id: "", type: type, at: now, childUid: childUid, detail: detail))
    }
}
