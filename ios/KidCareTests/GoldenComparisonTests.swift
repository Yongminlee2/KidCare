import Foundation
import Testing
@testable import KidCare

/// 안드로이드가 `GoldenFileWriterTest` 로 뽑아 둔 입력·기대출력(`ios/KidCareTests/golden/*.json`)을
/// 그대로 먹고, 스위프트 포팅이 같은 답을 내는지 본다.
///
/// 단위 테스트와 목적이 다르다. `ScheduleResolverTests` 같은 포팅 테스트는 "포팅한 사람이
/// 생각한 경우"를 확인한다. 이 파일은 **두 구현이 같은 함수인가**를 프로그램으로 넓게 만든
/// 입력으로 확인한다 — 테스트가 안 보는 입력에서 갈리는 것은 이 방법으로만 잡힌다.
/// 코틀린이 정본이다: 갈리면 스위프트를 고친다.
struct GoldenComparisonTests {

    private final class BundleToken {}

    private func goldenURL(_ name: String) throws -> URL {
        try #require(
            Bundle(for: BundleToken.self).url(forResource: name, withExtension: "json", subdirectory: "golden"),
            "golden/\(name).json 이 테스트 번들에 없다 — project.yml 의 리소스 빌드 페이즈를 확인한다"
        )
    }

    private func readArray(_ name: String) throws -> [[String: Any]] {
        let data = try Data(contentsOf: try goldenURL(name))
        return try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    private func readObject(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: try goldenURL(name))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// golden/ 폴더 자체가 번들에 실려 있는지, 그리고 그 안의 각 파일이 **스윕이라고
    /// 부를 만큼 케이스를 담고 있는지**를 확인한다.
    ///
    /// `size > 0` 만으로는 부족하다 — `[]` 도 2바이트라, 번들 안의 `scheduleResolver.json`
    /// 을 통째로 `[]` 로 바꿔치기해도 이 검사와 나머지 여섯 테스트가 전부 통과해 버린다
    /// (138개짜리 스윕이 조용히 증발해도 CI 는 초록이다 — 리뷰가 실제로 이 방법으로
    /// 재현했다). 그래서 각 파일을 실제로 디코드해서 케이스 수를 세고, 지금 개수보다
    /// 살짝 낮춘 하한과 비교한다 — 하나라도 없어지면 잡되, 생성기가 케이스를 한둘
    /// 더 보태는 정상적인 변화에는 안 흔들리게.
    @Test("golden 파일 다섯 개가 번들에 있고 스윕이라 부를 만큼 케이스를 담고 있다")
    func 골든_리소스가_번들에_있다() throws {
        let scheduleResolver = try readObject("scheduleResolver")
        #expect((scheduleResolver["resolve"] as? [[String: Any]])?.count ?? 0 >= 100, "scheduleResolver.resolve 케이스가 너무 적다")
        #expect((scheduleResolver["overlaps"] as? [[String: Any]])?.count ?? 0 >= 5, "scheduleResolver.overlaps 케이스가 너무 적다")

        let routePathRefiner = try readArray("routePathRefiner")
        #expect(routePathRefiner.count >= 30, "routePathRefiner 케이스가 너무 적다")

        let koreanHolidays = try readArray("koreanHolidays")
        #expect(koreanHolidays.count >= 6, "koreanHolidays 케이스가 너무 적다 (2025~2030년 전부가 있어야 한다)")

        let segmentSummarizer = try readObject("segmentSummarizer")
        #expect((segmentSummarizer["durations"] as? [[String: Any]])?.count ?? 0 >= 40, "segmentSummarizer.durations 케이스가 너무 적다")
        #expect((segmentSummarizer["distances"] as? [[String: Any]])?.count ?? 0 >= 50, "segmentSummarizer.distances 케이스가 너무 적다")
        #expect((segmentSummarizer["timeRanges"] as? [[String: Any]])?.count ?? 0 >= 20, "segmentSummarizer.timeRanges 케이스가 너무 적다")

        let routeWindows = try readArray("routeWindows")
        #expect(routeWindows.count >= 15, "routeWindows 케이스가 너무 적다")
    }

    // MARK: - 공통 파싱

    private func int64(_ any: Any?) -> Int64 { (any as! NSNumber).int64Value }
    private func double(_ any: Any?) -> Double { (any as! NSNumber).doubleValue }
    private func int(_ any: Any?) -> Int { (any as! NSNumber).intValue }
    private func bool(_ any: Any?) -> Bool { (any as! NSNumber).boolValue }
    private func string(_ any: Any?) -> String { any as! String }

    /// "yyyy-MM-dd" → 연·월·일만 담은 "맨몸" DateComponents. `KoreanHolidays`/`ScheduleResolver`
    /// 가 만드는 공휴일 집합의 키와 같은 모양이어야 Set 비교·포함 검사가 맞는다.
    private func parseDate(_ text: String) -> DateComponents {
        let parts = text.split(separator: "-").map { Int($0)! }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }

    // ==================================================================
    // 1. KoreanHolidays — 2025~2030년 전체
    // ==================================================================

    /// 스위프트 `Holiday` case 이름을 코틀린 `Holiday` enum 이름(SCREAMING_SNAKE_CASE)으로
    /// 직접 매핑한다. `String(describing:).uppercased()` 로 자동 변환하면 `.newYear` 가
    /// "NEWYEAR" 가 되어 코틀린의 "NEW_YEAR" 와 어긋난다(다른 case 는 전부 단어가 하나라
    /// 우연히 맞는다) — 매번 새해 첫날마다 거짓 실패가 나므로 표로 못박는다.
    private let holidayKotlinNames: [Holiday: String] = [
        .newYear: "NEW_YEAR", .seollal: "SEOLLAL", .independence: "INDEPENDENCE",
        .buddha: "BUDDHA", .children: "CHILDREN", .memorial: "MEMORIAL",
        .liberation: "LIBERATION", .chuseok: "CHUSEOK", .foundation: "FOUNDATION",
        .hangul: "HANGUL", .christmas: "CHRISTMAS", .substitute: "SUBSTITUTE",
    ]

    @Test("공휴일이 안드로이드와 같다 (2025~2030년 전체, 대체공휴일 포함)")
    func 공휴일_대조() throws {
        for 사례 in try readArray("koreanHolidays") {
            let year = int(사례["year"])
            let expectedHolidays = try #require(사례["holidays"] as? [String: String])

            // 기준일(설날·추석·부처님오신날) 자체가 실제 값과 같은지 먼저 확인한다 — 여기서
            // 갈리면 음력 환산(HolidayCalendar.anchors) 문제고, 기준일은 같은데 아래
            // holidays 가 갈리면 KoreanHolidays.of() 의 대체공휴일 로직 문제다. 두 층을
            // 구분해서 원인을 좁히려고 따로 확인한다.
            let anchors = try #require(HolidayCalendar.anchors(year: year), "\(year)년 기준일 계산 실패")
            #expect(anchors.seollal == parseDate(string(사례["seollal"])), "\(year)년 설날 기준일이 다르다")
            #expect(anchors.chuseok == parseDate(string(사례["chuseok"])), "\(year)년 추석 기준일이 다르다")
            #expect(anchors.buddha == parseDate(string(사례["buddha"])), "\(year)년 부처님오신날 기준일이 다르다")

            let actual = KoreanHolidays.of(year: year, anchors: anchors)
            var actualStrings: [String: String] = [:]
            for (날짜, 공휴일) in actual {
                let key = String(format: "%04d-%02d-%02d", 날짜.year!, 날짜.month!, 날짜.day!)
                actualStrings[key] = holidayKotlinNames[공휴일]
            }
            #expect(actualStrings == expectedHolidays, "\(year)년 공휴일이 다르다")
        }
    }

    // ==================================================================
    // 2. ScheduleResolver — 자정 넘김·겹침·우선순위·공휴일·여러 시간대
    // ==================================================================

    private func parseRule(_ r: [String: Any]) -> ScheduleRule {
        ScheduleRule(
            id: string(r["id"]),
            days: Set((r["days"] as! [Any]).map { int($0) }),
            startMinute: int(r["startMinute"]),
            endMinute: int(r["endMinute"]),
            mode: string(r["mode"]),
            enabled: bool(r["enabled"]),
            priority: int(r["priority"])
        )
    }

    @Test("예약 판정이 안드로이드와 같다 (자정 넘김·겹침·우선순위·공휴일·여러 시간대)")
    func 예약_판정_대조() throws {
        let root = try readObject("scheduleResolver")
        for 사례 in try #require(root["resolve"] as? [[String: Any]]) {
            let rules = (사례["rules"] as! [[String: Any]]).map(parseRule)
            let atMillis = int64(사례["atMillis"])
            let zone = try #require(TimeZone(identifier: string(사례["zone"])))
            let holidays = Set((사례["holidays"] as! [String]).map(parseDate))
            let expectedMode = 사례["mode"] as? String
            let expectedNextBoundary = (사례["nextBoundaryMillis"] as? NSNumber)?.int64Value

            let resolution = ScheduleResolver.resolveAt(rules: rules, atMillis: atMillis, zone: zone, holidays: holidays)
            let context = "atMillis=\(atMillis) zone=\(zone.identifier) rules=\(rules.map(\.id))"
            #expect(resolution.mode == expectedMode, "\(context)")
            #expect(resolution.nextBoundaryMillis == expectedNextBoundary, "\(context)")
        }
    }

    /// `overlapsOf` — 저장 전 겹침 경고. `resolveAt` 과 같은 파일의 공개 함수인데 처음
    /// 리뷰 전에는 대조가 없었다.
    @Test("예약 규칙 겹침 경고가 안드로이드와 같다 (맞닿음·부분·포함·자정 넘김·중복 id·꺼진 규칙)")
    func 예약_규칙_겹침_대조() throws {
        let root = try readObject("scheduleResolver")
        for 사례 in try #require(root["overlaps"] as? [[String: Any]]) {
            let name = string(사례["name"])
            let rules = (사례["rules"] as! [[String: Any]]).map(parseRule)
            let candidate = parseRule(사례["candidate"] as! [String: Any])
            let expectedIds = try #require(사례["overlappingIds"] as? [String]).sorted()

            let actual = ScheduleResolver.overlaps(rules: rules, candidate: candidate).map(\.id).sorted()
            #expect(actual == expectedIds, "\(name)")
        }
    }

    // ==================================================================
    // 3. RoutePathRefiner — 튐 제거·평활·문턱값 경계
    // ==================================================================

    private func parseFix(_ json: [String: Any]) -> Fix {
        Fix(lat: double(json["lat"]), lng: double(json["lng"]), accuracy: double(json["accuracy"]),
            at: int64(json["at"]), speed: double(json["speed"]))
    }

    @Test("경로선 정리가 안드로이드와 같다 (튐 제거·평활·시간/거리/속도 문턱)")
    func 경로선_정리_대조() throws {
        // 위경도는 두 플랫폼의 삼각함수(하버사인) 구현이 ULP 수준에서 다를 수 있어 아주
        // 작은 허용치를 둔다 — 1e-9도는 적도에서 약 0.1mm 로, 로직이 실제로 갈렸을 때
        // 생기는 차이(최소 수 cm~수 m)보다 훨씬 작아 진짜 회귀를 가리지 않는다.
        let epsilon = 1e-9

        for 사례 in try readArray("routePathRefiner") {
            let name = string(사례["name"])
            let points = (사례["points"] as! [[String: Any]]).map(parseFix)
            let expectedLegsJson = try #require(사례["legs"] as? [[[String: Any]]])

            let legs = RoutePathRefiner.refine(points: points)
            #expect(legs.count == expectedLegsJson.count, "\(name): leg 개수가 다르다")
            guard legs.count == expectedLegsJson.count else { continue }

            for (legIndex, leg) in legs.enumerated() {
                let expectedPoints = expectedLegsJson[legIndex].map(parseFix)
                #expect(leg.points.count == expectedPoints.count, "\(name): leg \(legIndex) 점 개수가 다르다")
                guard leg.points.count == expectedPoints.count else { continue }
                for (i, point) in leg.points.enumerated() {
                    let expected = expectedPoints[i]
                    let context = "\(name): leg \(legIndex) point \(i)"
                    #expect(abs(point.lat - expected.lat) < epsilon, "\(context) lat 실제=\(point.lat) 기대=\(expected.lat)")
                    #expect(abs(point.lng - expected.lng) < epsilon, "\(context) lng 실제=\(point.lng) 기대=\(expected.lng)")
                    #expect(point.accuracy == expected.accuracy, "\(context) accuracy")
                    #expect(point.at == expected.at, "\(context) at")
                    #expect(point.speed == expected.speed, "\(context) speed")
                }
            }
        }
    }

    // ==================================================================
    // 4. SegmentSummarizer — 경계값. 코틀린은 한국어 문장을, 스위프트는 구조를 돌려주는
    // 것이 Phase 2 의 의도된 차이라(README 개발일지의 i18n 버그를 이번엔 고치지 않기로
    // 한 결정), 생성기가 코틀린의 **실제 반환 문장**을 파싱해 구조로 바꿔 JSON 에 적어
    // 뒀다. 그래서 여기서 하는 일은 "코틀린이 실제로 돌려준 값 → 구조" 와 스위프트가
    // 직접 돌려주는 구조를 대조하는 것이지, 로직을 다시 구현해 저 혼자와 맞춰보는
    // 헛일이 아니다.
    // ==================================================================

    @Test("구간 요약(기간·거리)이 안드로이드와 같은 구조를 낸다 (59/60초, 999/1000m, 9/10m 경계)")
    func 구간_요약_기간_거리_대조() throws {
        let root = try readObject("segmentSummarizer")

        for 사례 in try #require(root["durations"] as? [[String: Any]]) {
            let millis = int64(사례["millis"])
            let expected: Duration
            switch string(사례["case"]) {
            case "underOneMinute": expected = .underOneMinute
            case "minutes": expected = .minutes(int(사례["minutes"]))
            case "hours": expected = .hours(int(사례["hours"]))
            case "hoursMinutes": expected = .hoursMinutes(int(사례["hours"]), int(사례["minutes"]))
            default:
                Issue.record("모르는 duration case: \(사례["case"] ?? "nil")")
                continue
            }
            let actual = SegmentSummarizer.duration(millis: millis)
            #expect(actual == expected, "millis=\(millis)")
        }

        for 사례 in try #require(root["distances"] as? [[String: Any]]) {
            let meters = double(사례["meters"])
            let actual = SegmentSummarizer.distance(meters: meters)
            switch string(사례["case"]) {
            case "underTenMeters":
                #expect(actual == .underTenMeters, "meters=\(meters)")
            case "meters":
                #expect(actual == .meters(int(사례["roundedMeters"])), "meters=\(meters)")
            case "kilometers":
                // .1 자리까지 반올림된 값 자체를 비교한다 — 코틀린은 문자열 서식(%.1f,
                // HALF_UP)에서, 스위프트는 곱하고 반올림하고 나누는 계산에서 반올림하는데,
                // 둘 다 이진 부동소수 위에서 벌어지는 일이라 아주 미세한 잔차가 남을 수
                // 있다. 두 경로가 정말 다른 소수 첫째 자리로 반올림했다면(예: 1.2 대
                // 1.3) 그 차이는 0.1 이라 1e-9 허용치로는 절대 못 가린다.
                if case let .kilometers(actualKm) = actual {
                    #expect(abs(actualKm - double(사례["kilometers"])) < 1e-9, "meters=\(meters)")
                } else {
                    Issue.record("meters=\(meters): case 가 kilometers 가 아니다 — 실제=\(actual)")
                }
            default:
                Issue.record("모르는 distance case: \(사례["case"] ?? "nil")")
            }
        }
    }

    @Test("구간의 시각 범위가 안드로이드와 같다 (여러 시간대, 자정 넘김 포함)")
    func 구간_시각_범위_대조() throws {
        let root = try readObject("segmentSummarizer")
        for 사례 in try #require(root["timeRanges"] as? [[String: Any]]) {
            let startAt = int64(사례["startAt"])
            let endAt = int64(사례["endAt"])
            let zone = try #require(TimeZone(identifier: string(사례["zone"])))
            let segment = Segment(type: .move, startAt: startAt, endAt: endAt, lat: 0, lng: 0, distanceMeters: 0, pointCount: 1)
            let actual = SegmentSummarizer.timeRange(segment, zone: zone)
            let expected = TimeRange(
                startHour: int(사례["startHour"]), startMinute: int(사례["startMinute"]),
                endHour: int(사례["endHour"]), endMinute: int(사례["endMinute"])
            )
            #expect(actual == expected, "startAt=\(startAt) endAt=\(endAt) zone=\(zone.identifier)")
        }
    }

    // ==================================================================
    // 5. RouteWindows — 창 배분: 하나·둘·여럿, 맞닿음·겹침·멀리 떨어짐, 홀짝 중간점
    // ==================================================================

    /// 코틀린의 포함형 `[first, last]` 쌍을 스위프트의 배제형 `Range<Int64>` 로 바꾼다.
    /// `RouteWindows.swift` 타입 문서의 규칙을 그대로 따른다: `upperBound` 는 "마지막으로
    /// 포함되는 순간 + 1" 이되, `last` 가 `Int64.max` 면(배제형이라 그보다 큰 값을 못
    /// 써서 +1 을 못 한다) `upperBound` 를 `Int64.max` 자체로 못박는다 — 그 결과 그
    /// 경우만 마지막 순간 하나가 "포함"에서 "제외"로 바뀌는 것은 문서에 적힌 대로 의도된
    /// 손실이다. 입력(`moves`)과 출력(`windows`) 모두 같은 규칙으로 바꾼다.
    private func inclusiveToRange(_ first: Int64, _ last: Int64) -> Range<Int64> {
        first..<(last == Int64.max ? Int64.max : last + 1)
    }

    @Test("이동 구간의 경로 창 배분이 안드로이드와 같다 (하나·둘·여럿, 맞닿음·겹침, 홀짝 중간점)")
    func 경로_창_배분_대조() throws {
        for 사례 in try readArray("routeWindows") {
            let name = string(사례["name"])
            let movesJson = try #require(사례["moves"] as? [[Any]])
            let moves = movesJson.map { pair in inclusiveToRange(int64(pair[0]), int64(pair[1])) }
            let expectedJson = try #require(사례["windows"] as? [[Any]])
            let expected = expectedJson.map { pair in inclusiveToRange(int64(pair[0]), int64(pair[1])) }

            let actual = RouteWindows.partition(moves: moves)
            #expect(actual == expected, "\(name)")
        }
    }
}
