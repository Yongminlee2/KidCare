import Foundation

/// 역지오코딩으로 얻은 장소 이름을 좌표 **근처**로 찾는 캐시. 정본 `logic/PlaceNameCache.kt`.
///
/// 열쇠를 버리고 **거리**로 찾는 이유는 그 파일 주석(`:3-19`)에 있다 — 이름을 묻는 좌표
/// (`Segment.nameLat`/`nameLng`)는 머무름 점들의 오차 가중 평균이라 점이 하나 늘 때마다 몇 미터씩
/// 움직인다. 반올림한 열쇠는 그때마다 달라져 캐시가 거의 안 맞았다.
///
/// 코틀린은 `ArrayDeque` 를 가진 클래스지만 여기서는 **값 타입**이다. `actor PlaceNamer` 안에
/// 두려면 값 타입이 가장 단순하고, 이 타입이 하는 일은 배열 하나 다루기라 참조 의미가 필요 없다.
struct PlaceNameCache: Equatable, Sendable {

    struct Entry: Equatable, Sendable {
        let lat: Double
        let lng: Double
        let name: String
    }

    /// 같은 곳으로 볼 거리(`:67`). 머무름 반경(`SegmentBuilder.stayRadiusMeters`, 40m)보다 조금 작다.
    static let matchRadiusMeters = 30.0

    /// 아이가 다니는 곳은 많아야 수십 곳이다. 넉넉히 두되 끝없이 늘지는 않게(`:70`).
    static let maxEntries = 300

    /// 코틀린 `String.trim()` 이 자르는 글자 집합이다(`PlaceNameCache.kt:51` 의 `.trim()`).
    ///
    /// **계획서 판정 기록 4 와 다르다.** 그 기록은 코틀린 `trim()` 이 자바 `Character.isWhitespace`
    /// 라고 적었는데, 코틀린 `Char.isWhitespace()` 의 실제 구현은
    /// `Character.isWhitespace(c) || Character.isSpaceChar(c)` 다(kotlin-stdlib
    /// `CharsKt__CharJVMKt.isWhitespace` 바이트코드로 확인). 그래서 두 집합이 갈리는 자리는
    /// 기록이 말한 비분리 공백이 **아니라** 아래 둘이다 — 골든 `placeNameCache.put.sanitize` 가
    /// 두 경우를 실제로 싣고 대조한다.
    ///
    /// 1. **U+0085(NEL)는 빼야 한다.** 두 자바 함수가 모두 false 라 코틀린은 안 자르는데, Swift 의
    ///    `.whitespacesAndNewlines` 는 자른다. 한 글자 차이가 캐시 열쇠가 아니라 **부모 화면에 뜨는
    ///    이름**을 바꾼다.
    /// 2. **U+001C~U+001F 는 넣어야 한다.** 자바 `isWhitespace` 가 true 라 코틀린은 자르는데
    ///    Swift 의 집합에는 없다.
    ///
    /// 비분리 공백 셋(U+00A0·U+2007·U+202F)은 `isSpaceChar` 가 true 라 **양쪽 다 자른다** — 빼면
    /// 오히려 갈린다.
    static let 자바_공백: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.subtract(CharacterSet(charactersIn: "\u{0085}"))
        set.formUnion(CharacterSet(charactersIn: "\u{001C}\u{001D}\u{001E}\u{001F}"))
        return set
    }()

    private let matchRadius: Double
    private let limit: Int
    /// 뒤로 갈수록 최근에 넣은 것. 상한을 넘으면 앞(오래된 것)부터 버린다(`:27-28`).
    private var entries: [Entry] = []

    var size: Int { entries.count }

    init(matchRadiusMeters: Double = PlaceNameCache.matchRadiusMeters,
         maxEntries: Int = PlaceNameCache.maxEntries) {
        matchRadius = matchRadiusMeters
        limit = maxEntries
    }

    /// 반경 안에서 가장 가까운 이름. 없으면 nil (`:32-44`).
    func find(lat: Double, lng: Double) -> String? {
        var best: Entry?
        var bestDistance = Double.greatestFiniteMagnitude
        for entry in entries {
            let distance = Self.distanceMeters(lat, lng, entry.lat, entry.lng)
            if distance <= matchRadius && distance < bestDistance {
                best = entry
                bestDistance = distance
            }
        }
        return best?.name
    }

    /// 이름을 넣는다. 같은 자리(반경 안)에 이미 있던 것은 **바꿔 끼운다**(`:46-56`) — 안 그러면
    /// 집처럼 매일 가는 곳이 흔들린 좌표마다 한 칸씩 늘어 상한을 금방 채운다.
    mutating func put(lat: Double, lng: Double, name: String) {
        let clean = name
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: Self.자바_공백)
        if clean.isEmpty { return }
        entries.removeAll { Self.distanceMeters(lat, lng, $0.lat, $0.lng) <= matchRadius }
        entries.append(Entry(lat: lat, lng: lng, name: clean))
        while entries.count > limit { entries.removeFirst() }
    }

    /// 한 줄에 한 곳: `위도,경도<탭>이름` (`:59`).
    ///
    /// 숫자 글자는 코틀린 `Double.toString` 과 다를 수 있다. **그래서 골든 대조는 이 문자열이 아니라
    /// `decode` 한 뒤의 값으로 한다**(설계서 §4.5 가 `TrailCodec` 에 정한 규율과 같다).
    func encode() -> String {
        entries.map { "\($0.lat),\($0.lng)\t\($0.name)" }.joined(separator: "\n")
    }

    /// 망가진 줄은 조용히 건너뛴다 — 캐시 한 줄 때문에 이름 전체를 잃으면 안 된다(`:72-89`).
    static func decode(_ text: String,
                       matchRadiusMeters: Double = PlaceNameCache.matchRadiusMeters,
                       maxEntries: Int = PlaceNameCache.maxEntries) -> PlaceNameCache {
        var cache = PlaceNameCache(matchRadiusMeters: matchRadiusMeters, maxEntries: maxEntries)
        for line in lines(text) {
            // 코틀린 indexOf('\t') <= 0 — 탭이 없거나 맨 앞이면 버린다.
            guard let tab = line.firstIndex(of: "\t"), tab != line.startIndex else { continue }
            let coordinates = line[line.startIndex..<tab].components(separatedBy: ",")
            guard coordinates.count == 2,
                  let lat = 코틀린_실수(coordinates[0]), let lng = 코틀린_실수(coordinates[1]) else { continue }
            cache.put(lat: lat, lng: lng, name: String(line[line.index(after: tab)...]))
        }
        return cache
    }

    /// 코틀린 `toDoubleOrNull`(`logic/PlaceNameCache.kt:84-85`)은 앞뒤 공백과 자바식 `d`/`f`
    /// 접미사를 받는데 스위프트 `Double.init` 은 거절한다. `encode` 가 만든 줄에는 그런 글자가
    /// 없어 실사용에서는 안 갈리지만, 두 구현이 **같은 함수**라는 약속은 입력이 어디서 오든
    /// 지켜져야 한다(2단계 통합 검토 M2). **정본이 받는 것만 받는다** — 16진 실수나 Infinity
    /// 까지 흉내 내는 것은 정본에 없는 입력을 상상하는 일이다.
    private static func 코틀린_실수(_ text: some StringProtocol) -> Double? {
        var s = text.trimmingCharacters(in: .whitespaces)
        if let last = s.last, "dDfF".contains(last) { s.removeLast() }
        return Double(s)
    }

    /// 코틀린 `lineSequence()` 와 같은 줄 나누기 — `\r\n`·`\n`·`\r` **셋 다** 줄바꿈이다.
    /// `\n` 하나로만 나누면 `\r` 로 끝나는 줄이 통째로 이름 칸에 섞여 들어가 두 플랫폼이 갈린다.
    private static func lines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static func distanceMeters(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        LocationFilter.distanceMeters(
            Fix(lat: lat1, lng: lng1, accuracy: 0, at: 0),
            Fix(lat: lat2, lng: lng2, accuracy: 0, at: 0))
    }
}
