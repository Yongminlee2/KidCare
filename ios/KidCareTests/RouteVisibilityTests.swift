import Foundation
import Testing
@testable import KidCare

/// Task 8 — 구간별 경로 보이기. 정본은 안드로이드 `toggleRoute`(:1089)·
/// `toggleAllRoutes`(:1101)·`renderRouteVisibilityState`(:1111)·`focusOn`(:1039)·
/// `fitWholeRoute`(:1177) 호출 게이팅(:245, :889, :981, :1070). `MapViewModel` 을
/// `dayLoad` 가짜로 채워 Firestore 를 전혀 타지 않는다 — `RouteOverlayTests` 가
/// 이미 증명한 좌표(이동 구간 둘 사이에 머무름)를 그대로 재사용한다.
@MainActor
struct RouteVisibilityTests {

    private let baseLat = 37.5665

    /// 아래 딕셔너리 빌더들은 전부 `nonisolated` 다 — `dayLoad` 로 주입하는
    /// `@Sendable` 클로저 안에서 부르는데, 이 테스트 구조체 자체는 `@MainActor`
    /// 라 격리 없이는(그리고 `[String: Any]` 는 Sendable 이 아니라 미리 만들어
    /// 캡처할 수도 없어서) 클로저 몸통 안에서 매번 새로 지어야 한다.
    private nonisolated func point(at: Int64, east: Double, speed: Double = 1.2) -> [String: Any] {
        ["lat": baseLat, "lng": 126.9780 + east / 88_800.0, "accuracy": 10.0, "speed": speed, "at": at]
    }

    private nonisolated func move(startAt: Int64, endAt: Int64, east: Double) -> [String: Any] {
        ["type": "MOVE", "startAt": startAt, "endAt": endAt,
         "lat": baseLat, "lng": 126.9780 + east / 88_800.0,
         "distanceMeters": 10.0, "pointCount": 2, "placeName": ""]
    }

    private nonisolated func stay(startAt: Int64, endAt: Int64, east: Double, placeName: String = "") -> [String: Any] {
        ["type": "STAY", "startAt": startAt, "endAt": endAt,
         "lat": baseLat, "lng": 126.9780 + east / 88_800.0,
         "distanceMeters": 0.0, "pointCount": 2, "placeName": placeName]
    }

    /// 이동1(1000~2000, startAt=1000) · 머무름(2000~6000) · 이동2(6000~7000,
    /// startAt=6000) — `RouteOverlayTests.이동_구간_둘_사이에_머무름` 이 이미
    /// 증명한 좌표라, 두 이동 구간 모두 실제 선을 낸다는 것을 다시 증명할
    /// 필요가 없다.
    private nonisolated func 하루_기록_A(dayKey: String) -> TrailDoc {
        TrailDoc([
            "dayKey": dayKey,
            "points": [
                point(at: 1_000, east: 0.0), point(at: 2_000, east: 1.5),
                point(at: 3_000, east: 1.5), point(at: 5_000, east: 1.6),
                point(at: 6_000, east: 1.6), point(at: 7_000, east: 3.1),
            ],
            "segments": [
                move(startAt: 1_000, endAt: 2_000, east: 1.5),
                stay(startAt: 2_000, endAt: 6_000, east: 1.55, placeName: "집"),
                move(startAt: 6_000, endAt: 7_000, east: 3.1),
            ],
            "updatedAt": 7_000,
        ])
    }

    /// 완전히 다른 시각대(다른 날)의 이동 하나 — "날짜를 넘기면 숨김이 새 날의
    /// 구간과 안 맞아 사실상 지워진다"를 증명하는 데 쓴다.
    private nonisolated func 하루_기록_B(dayKey: String) -> TrailDoc {
        TrailDoc([
            "dayKey": dayKey,
            "points": [point(at: 50_000, east: 0.0), point(at: 51_000, east: 1.5), point(at: 52_000, east: 3.0)],
            "segments": [move(startAt: 50_000, endAt: 52_000, east: 3.0)],
            "updatedAt": 52_000,
        ])
    }

    /// 하루 종일 머무름만 있는(이동 구간이 없는) 날 — 경로 숨김 버튼이 비활성돼야
    /// 하는 자리를 만든다.
    private nonisolated func 하루_기록_머무름만(dayKey: String) -> TrailDoc {
        TrailDoc([
            "dayKey": dayKey, "points": [] as [[String: Any]], "updatedAt": 0,
            "segments": [stay(startAt: 0, endAt: 1_000, east: 0, placeName: "집")],
        ])
    }

    private func vm(dayLoad: @escaping @Sendable (String, String, String) async throws -> (status: ChildStatusDoc?, trail: TrailDoc?)) -> MapViewModel {
        MapViewModel(familyId: "family", childUid: "child", dayLoad: dayLoad)
    }

    // MARK: - 숨김은 startAt 으로 키를 잡는다

    @Test("이동 행을 탭하면 그 startAt 만 숨기고 나머지는 그대로 둔다")
    func 하나만_숨긴다() async throws {
        let model = vm { _, _, dayKey in (nil, 하루_기록_A(dayKey: dayKey)) }
        await model.하루를_읽는다()

        #expect(model.경로_구간.count == 2)
        let 이동_행 = model.타임라인_행.first { $0.icon == .move && $0.startAt == 1_000 }
        try #require(이동_행 != nil)

        model.타임라인_행을_탭한다(이동_행!)
        #expect(model.hiddenRouteStarts == [1_000])
        #expect(model.표시할_경로_구간.map(\.startAt).sorted() == [6_000])

        // 다시 탭하면 되돌아온다.
        model.타임라인_행을_탭한다(이동_행!)
        #expect(model.hiddenRouteStarts.isEmpty)
        #expect(model.표시할_경로_구간.count == 2)
    }

    @Test("전체 토글: 모두 보이면 전부 숨기고, 하나라도 숨겨져 있으면 전부 다시 보인다")
    func 전체_토글() async throws {
        let model = vm { _, _, dayKey in (nil, 하루_기록_A(dayKey: dayKey)) }
        await model.하루를_읽는다()
        let 전체_startAt: Set<Int64> = [1_000, 6_000]

        #expect(model.경로_전체_보임 == true)
        model.전체_경로를_토글한다()
        #expect(model.hiddenRouteStarts == 전체_startAt) // 모두 보였으니 전부 숨긴다
        #expect(model.경로_전체_보임 == false)

        // 하나만 다시 보여도(=일부만 숨겨져도) "전부 다시 보인다" 쪽으로 갈린다.
        model.타임라인_행을_탭한다(model.타임라인_행.first { $0.startAt == 1_000 && $0.icon == .move }!)
        #expect(model.hiddenRouteStarts == [6_000])

        model.전체_경로를_토글한다()
        #expect(model.hiddenRouteStarts.isEmpty) // 전부 다시 보인다
        #expect(model.경로_전체_보임 == true)
    }

    @Test("경로 숨김 버튼은 구간이 하나도 없으면 비활성이다")
    func 구간_없으면_버튼_비활성() async throws {
        let model = vm { _, _, dayKey in (nil, 하루_기록_머무름만(dayKey: dayKey)) }
        await model.하루를_읽는다()

        #expect(model.경로_구간.isEmpty)
        #expect(model.경로_숨김_버튼_활성화 == false)
        #expect(model.경로_전체_보임 == false) // 구간이 없으면 "전부 보임"도 아니다
    }

    // MARK: - 탭 처리: 머무름/선 없는 구간은 토글이 아니라 포커스

    @Test("머무름 행을 탭하면 토글하지 않고 그 좌표로 포커스를 요청한다")
    func 머무름_행은_포커스() async throws {
        let model = vm { _, _, dayKey in (nil, 하루_기록_A(dayKey: dayKey)) }
        await model.하루를_읽는다()

        let 머무름_행 = try #require(model.타임라인_행.first { $0.icon == .stay })
        #expect(model.포커스_요청 == nil)

        model.타임라인_행을_탭한다(머무름_행)

        #expect(model.hiddenRouteStarts.isEmpty) // 토글되지 않았다
        let 요청 = try #require(model.포커스_요청)
        #expect(요청.lat == 머무름_행.lat)
        #expect(요청.lng == 머무름_행.lng)
        #expect(요청.zoom == MapViewModel.childFocusZoom)
    }

    // MARK: - 경로 요약 문구: 숨김 개수에 따라 갈린다

    @Test("경로 요약 문구는 숨긴 개수에 따라 base/hidden/partial 로 갈린다")
    func 요약_문구_분기() async throws {
        let model = vm { _, _, dayKey in (nil, 하루_기록_A(dayKey: dayKey)) }
        await model.하루를_읽는다()
        let 기본_문구 = model.경로_요약_문구

        let 이동1 = try #require(model.타임라인_행.first { $0.startAt == 1_000 && $0.icon == .move })
        model.타임라인_행을_탭한다(이동1) // 하나만 숨긴다 — partial
        #expect(model.경로_요약_문구 == String(format: String(localized: "timeline_summary_routes_partial"), 기본_문구))

        model.전체_경로를_토글한다() // 이제 전부 숨긴다? 아니다 — 일부만 숨겨진 상태이므로 전체 토글은 "전부 보이기"
        #expect(model.경로_요약_문구 == 기본_문구)

        model.전체_경로를_토글한다() // 이제 전부 숨긴다
        #expect(model.경로_요약_문구 == String(format: String(localized: "timeline_summary_routes_hidden"), 기본_문구))
    }

    // MARK: - 날짜를 넘기면 숨김이 새 날의 구간과 안 맞아 사실상 지워진다

    @Test("날짜를 넘기면 이전 날의 숨김이 새 날의(겹치지 않는) startAt 에 잘못 적용되지 않는다")
    func 날짜를_넘기면_숨김이_지워진다() async throws {
        let 오늘 = DayPicker.todayKey(zone: .current, nowMillis: Int64(Date().timeIntervalSince1970 * 1000))
        let 어제 = DayPicker.shift(dayKey: 오늘, days: -1)

        // 정본 안드로이드 drawRoute 의 `hiddenRouteStarts.retainAll(validKeys)` —
        // 날짜가 다르면 startAt(밀리초)이 우연히 겹칠 일이 사실상 없어, 이
        // 교집합이 "날짜를 넘기면 숨김을 지운다"와 같은 결과를 낸다(브리프
        // "confirm and decide").
        let model = vm { _, _, dayKey in
            dayKey == 어제 ? (nil, 하루_기록_B(dayKey: dayKey)) : (nil, 하루_기록_A(dayKey: dayKey))
        }
        await model.하루를_읽는다() // 오늘 — 하루_기록_A(startAt 1000, 6000)
        let 이동1 = try #require(model.타임라인_행.first { $0.startAt == 1_000 && $0.icon == .move })
        model.타임라인_행을_탭한다(이동1)
        #expect(model.hiddenRouteStarts == [1_000])

        await model.이전_날로() // 어제 — 하루_기록_B(startAt 50000), 겹치는 startAt 이 없다
        #expect(model.hiddenRouteStarts.isEmpty)
        #expect(model.표시할_경로_구간.count == model.경로_구간.count) // 아무것도 숨겨진 게 없다
    }

    // MARK: - fitWholeRoute 요청 게이팅 (카메라를 실제로 옮기는 것은 NaverMapView 의 몫)

    @Test("패널이 접혀 있으면 하루를 읽어도 경로 전체 보기를 요청하지 않는다")
    func 접힌_채로_읽으면_요청하지_않는다() async throws {
        let model = vm { _, _, dayKey in (nil, 하루_기록_A(dayKey: dayKey)) }
        #expect(model.경로_전체_보기_요청 == 0)
        await model.하루를_읽는다()
        #expect(model.경로_전체_보기_요청 == 0) // 기본값이 접힘이다
    }

    @Test("패널을 펼치면 경로 전체 보기를 요청하고, 접으면 요청하지 않는다")
    func 패널_펼침이_요청을_올린다() async throws {
        let model = vm { _, _, dayKey in (nil, 하루_기록_A(dayKey: dayKey)) }
        await model.하루를_읽는다()
        #expect(model.경로_전체_보기_요청 == 0)

        model.타임라인_패널_상태를_갱신한다(펼쳐짐: true, 콘텐츠_높이: 200)
        #expect(model.경로_전체_보기_요청 == 1)

        model.타임라인_패널_상태를_갱신한다(펼쳐짐: false, 콘텐츠_높이: 0)
        #expect(model.경로_전체_보기_요청 == 1) // 접을 때는 안 오른다

        model.타임라인_패널_상태를_갱신한다(펼쳐짐: true, 콘텐츠_높이: 200)
        #expect(model.경로_전체_보기_요청 == 2)
    }

    @Test("펼쳐진 채로 날짜를 넘기면(경로 재로딩) 경로 전체 보기를 다시 요청한다")
    func 펼쳐진_채로_날짜를_넘기면_다시_요청한다() async throws {
        let model = vm { _, _, dayKey in (nil, 하루_기록_A(dayKey: dayKey)) }
        await model.하루를_읽는다()
        model.타임라인_패널_상태를_갱신한다(펼쳐짐: true, 콘텐츠_높이: 200) // 요청 1
        let 이전_요청_수 = model.경로_전체_보기_요청

        await model.이전_날로() // 정본 안드로이드 drawRoute(:1070) 의 "펼쳐진 채로 날짜를 넘기면" 자리
        #expect(model.경로_전체_보기_요청 == 이전_요청_수 + 1)
    }
}
