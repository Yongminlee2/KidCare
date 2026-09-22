import Foundation
import os

/// 머무름 좌표에 이름을 붙이는 쪽. `TrailUploader` 가 이 모양만 보고 부른다 — 테스트는 가짜를 넣고,
/// 앱은 `PlaceNamer` 를 넣는다. **요구사항이 `async` 인 이유**는 구현이 `actor` 라서다(actor 격리
/// 멤버는 `async` 요구사항만 만족시킬 수 있다).
///
/// 시간 단위가 전부 **밀리초 `Int64`** 인 이유가 둘이다. ① 정본 코틀린이 그 단위다
/// (`TIMEOUT_MILLIS`·`MIN_INTERVAL_MILLIS`·`GEOCODE_BUDGET_MILLIS`). ② 이 모듈에는 이미
/// 보호자 화면이 쓰는 `Duration` 열거형이 있어(`Logic/SegmentSummarizer.swift:13`) 표준
/// `Swift.Duration` 을 쓰려면 모든 자리에 모듈 이름을 붙여야 한다 — 읽기만 나빠진다.
/// `Sendable` 인 이유: `@MainActor` 인 `TrailUploader` 가 들고 있다가 `actor PlaceNamer` 로
/// 건너가야 한다. 구현은 전부 격리된 참조 타입(actor 또는 `@MainActor` 클래스)이라 저절로 만족한다 —
/// `@unchecked Sendable` 을 쓰지 않는다.
protocol PlaceNaming: Sendable {
    /// 네트워크 없이 이미 아는 이름만. 모르면 nil.
    func cachedName(lat: Double, lng: Double) async -> String?
    /// 못 얻으면 nil. `budgetLeftMillis` 안에 요청 슬롯을 못 잡으면 **아예 묻지 않는다**.
    func name(lat: Double, lng: Double, timeout: TimeInterval, budgetLeftMillis: Int64?) async -> String?
}

/// `PlaceNamer` 가 스스로 거절할 때 쓰는 오류.
enum PlaceNamerError: Error, Equatable {
    /// 테스트 프로세스에서 진짜 요청을 하려고 했다. 자세한 근거는 `PlaceNamer.테스트_중`.
    case 테스트에서는_네트워크를_안_탄다
}

/// 좌표를 사람이 읽는 주소로 바꾼다. 정본 `child/PlaceNamer.kt`(전체).
///
/// **OpenStreetMap Nominatim 을 쓴다. `CLGeocoder` 가 아니다**(계획서 판정 기록 8) — 설계서 §4.10 이
/// 엔드포인트·User-Agent·제한시간·최소 간격을 안드로이드와 "같은 값"으로 못 박았고, 이유는 두
/// 플랫폼이 같은 좌표에 **같은 이름**을 붙여야 하기 때문이다. 애플 지도 데이터는 같은 집에 다른
/// 이름을 준다 — 부모 화면의 타임라인이 아이 폰 기종에 따라 달라지면 안 된다.
///
/// Nominatim 은 공개 서버를 무료로 내주는 호의성 서비스라 사용 정책이 있다(초당 최대 1건, 식별
/// 가능한 User-Agent, 결과 캐싱, 다른 서비스로 전환 가능해야 함 — nominatim.org 사용 정책).
/// 슬롯 확보(`name` 안)가 첫째를, ``userAgent`` 가 둘째를, ``PlaceNameCache`` 가 셋째를 만족한다.
/// 넷째를 위해 엔드포인트를 ``endpoint`` 상수 하나로만 몰아뒀다.
///
/// **재시도가 없다.** 안드로이드에도 없다(`PlaceNamer.kt:92-124` 는 한 번 쏘고 실패하면 null 이다).
/// 실패한 결과는 캐시하지 않으므로 다음 업로드가 자연히 다시 묻는다 — 그게 재시도 자리다.
///
/// ## 왜 `actor` 인가 (설계서 §3.6)
/// 코틀린은 companion + `Mutex` 로 "캐시"와 "마지막 요청 시각"을 지켰다(`:158-159`). Swift 에서는
/// 언어 기능으로 대신한다. 다만 actor 는 `await` 지점에서 **재진입**하므로, 잠든 사이에 다른 호출이
/// 들어와 같은 값을 보고 둘 다 짧게 자는 경쟁이 생긴다 — 코틀린이 Mutex 로 막은 그 경쟁이다.
/// 그래서 **자기 전에** 다음 허용 시각을 밀어 슬롯을 먼저 확보한다(계획서 판정 기록 7).
///
/// ## 위치 수집을 절대 막지 않는다
/// 부르는 곳은 `TrailUploader.buildSegments` **하나**뿐이다. `TrackingCoordinator.handle` 도
/// `PlaceWatcher.onFix` 도 이 타입을 모른다(계획서 판정 기록 9). 이벤트의 `placeName` 은 부모가
/// 지은 장소 이름이지 역지오코딩 결과가 아니다.
actor PlaceNamer: PlaceNaming {

    /// 앱이 쓰는 하나. 코틀린이 마지막 요청 시각을 **companion**(프로세스 전체 공유)에 둔 이유
    /// (`:158-159`)를 그대로 옮긴다 — 인스턴스를 여럿 만들면 "초당 1건"이 인스턴스 수만큼 늘어난다.
    /// 캐시도 프로세스 안에서 한 벌만 돌아 디스크와 어긋날 일이 없다.
    static let shared = PlaceNamer()

    // Nominatim 사용 정책이 "다른 서비스로 언제든 전환 가능해야 한다"를 요구한다 — 그래서
    // 엔드포인트를 이 상수 하나로만 몰아둔다(`PlaceNamer.kt:144-146`).
    static let endpoint = "https://nominatim.openstreetmap.org/reverse"

    /// 앱을 식별하는 값만 넣는다 — 이메일 등 개인정보는 제3자(OSM 재단) 서버로 나가는 이 헤더에
    /// 넣지 않는다(`PlaceNamer.kt:148-150`).
    static let userAgent = "KidCare/1.0 (com.kidcare.family)"

    /// `PlaceNamer.kt:152`(`TIMEOUT_MILLIS = 5000`). 연결·읽기 각각의 제한이다. 부르는 쪽이 남은
    /// 예산을 넘겨 준다(`:64-66`).
    static let timeoutSeconds: TimeInterval = 5.0

    /// `PlaceNamer.kt:153`(`MIN_INTERVAL_MILLIS = 1000L`). Nominatim 정책의 "초당 최대 1건".
    static let minIntervalMillis: Int64 = 1_000

    /// 한 번의 업로드에서 새 이름을 묻는 데 쓸 수 있는 시간(`TrailUploader.kt:235`,
    /// `GEOCODE_BUDGET_MILLIS = 3_000L`). 짧게 잡아도 이름이 영영 안 붙는 것은 아니다 — 얻은
    /// 이름은 디스크에 남아 다음부터는 이 예산을 쓰지 않는다.
    static let geocodeBudgetMillis: Int64 = 3_000

    /// 안드로이드 `PREFS_NAME`(`:155`) + `KEY_ENTRIES`(`:156`) 자리. iOS 는 파일이 아니라
    /// `UserDefaults` 라 이름을 하나로 합쳤다 — 값의 형식(`PlaceNameCache.encode`)은 글자까지 같다.
    static let defaultsKey = "kidcare_place_names.entries"

    private let defaults: UserDefaults
    private let fetch: (URL, TimeInterval) async throws -> Data
    private let now: () async -> Int64
    private let sleep: (Int64) async -> Void
    private let logger = Logger(subsystem: "com.kidcare.family", category: "PlaceNamer")

    private var cache: PlaceNameCache
    /// 이 시각(단조 시계, 밀리초) 전에는 새 요청을 쏘지 않는다. **자기 전에** 민다(계획서 판정 기록 7).
    private var nextAllowedAtMillis: Int64 = 0

    /// `now`/`sleep` 은 **단조 시계**다(벽시계가 아니다) — 사용자가 시각을 바꾸거나 NTP 가 뒤로
    /// 돌려도 요청 간격이 무너지면 안 된다. 테스트는 이 둘을 가짜로 바꿔 벽시계를 안 기다린다.
    ///
    /// 저장소를 **`UserDefaults` 가 아니라 suite 이름으로** 받는 이유: `UserDefaults` 는 `Sendable`
    /// 이 아니라 actor 밖에서 만들어 넘기면 Swift 6 가 `sending ... risks causing data races` 로
    /// 거절한다. 이름만 넘기고 **actor 안에서** 연다(`@unchecked Sendable` 을 쓰지 않는다).
    /// `nil` 이면 앱이 쓰는 표준 저장소다 — 안드로이드 `PREFS_NAME` 자리.
    init(suiteName: String? = nil,
         fetch: @escaping (URL, TimeInterval) async throws -> Data = PlaceNamer.urlSessionFetch,
         now: @escaping () async -> Int64 = PlaceNamer.uptimeMillis,
         sleep: @escaping (Int64) async -> Void = { dueMillis in
             let 남은 = dueMillis - PlaceNamer.uptimeMillis()
             if 남은 > 0 { try? await Task.sleep(nanoseconds: UInt64(남은) * 1_000_000) }
         }) {
        defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.fetch = fetch
        self.now = now
        self.sleep = sleep
        cache = PlaceNameCache.decode(defaults.string(forKey: Self.defaultsKey) ?? "")
    }

    /// 네트워크 없이 이미 아는 이름만. 모르면 nil (`PlaceNamer.kt:57-58`).
    func cachedName(lat: Double, lng: Double) -> String? { cache.find(lat: lat, lng: lng) }

    /// 이름을 못 얻으면 nil. 네트워크가 안 되거나 응답이 비어 있으면 **조용히** nil 이다
    /// (`PlaceNamer.kt:60-75`) — 이름 한 건을 못 얻은 것 때문에 하루 문서 업로드가 실패하면 안 된다.
    ///
    /// `budgetLeftMillis` 가 주어지면 그 안에 요청 슬롯을 못 잡는 경우 **아예 묻지 않고** nil 로 돌아온다 —
    /// 1초를 기다린 뒤 예산이 끝나 버리면 기다린 시간이 통째로 낭비되기 때문이다.
    func name(lat: Double, lng: Double,
              timeout: TimeInterval = PlaceNamer.timeoutSeconds,
              budgetLeftMillis: Int64? = nil) async -> String? {
        if let cached = cache.find(lat: lat, lng: lng) { return cached }

        let start = await now()
        let due = max(nextAllowedAtMillis, start)
        if let budgetLeftMillis, due - start >= budgetLeftMillis { return nil }
        // 슬롯을 **먼저** 확보한다. 그다음에 잔다(계획서 판정 기록 7).
        nextAllowedAtMillis = due + Self.minIntervalMillis
        if due > start { await sleep(due) }

        guard let url = URL(string:
            "\(Self.endpoint)?format=jsonv2&lat=\(lat)&lon=\(lng)&accept-language=ko&zoom=18") else {
            return nil
        }
        let data: Data
        do {
            data = try await fetch(url, timeout)
        } catch is CancellationError {
            // 취소는 실패가 아니다. 일반 `catch` 가 삼키지 않도록 **먼저** 갈라 잡고 로그도 안 남긴다
            // (설계서 §16). 이 함수는 `throws` 가 아니라 다시 던질 수 없지만, 부르는 Task 는 이미
            // 취소돼 있어 다음 중단 지점에서 그대로 드러난다.
            return nil
        } catch {
            logger.warning("역지오코딩 요청 실패: \(String(describing: error), privacy: .public)")
            return nil
        }
        guard let name = Self.parse(data) else { return nil }

        // 실패한 결과(nil)는 캐시하지 않는다 — 한 번의 네트워크 오류가 그 자리를 하루 종일 이름
        // 없이 가두면 안 된다(`PlaceNamer.kt:36-38`).
        cache.put(lat: lat, lng: lng, name: name)
        defaults.set(cache.encode(), forKey: Self.defaultsKey)
        return name
    }

    /// 상호·건물명 같은 구체적 장소명이 있으면 그게 사람에게 가장 익숙하니 그대로 쓴다. 없으면 동
    /// 단위 행정 구역명을 쓰고, 도로명이 있으면 덧붙인다. suburb(행정동)를 quarter(법정동)보다 먼저
    /// 보는 근거는 실제 서울 좌표 4곳 확인 결과다(`PlaceNamer.kt:118-139`). 시·도까지 붙이면 화면에서
    /// 잘리므로 그 아래만 남긴다.
    static func parse(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let address = root["address"] as? [String: Any] else { return nil }
        // 코틀린 `optString(key).takeIf(String::isNotEmpty)` 자리 — 없거나 빈 글자면 다음 열쇠로.
        func 값(_ key: String) -> String? {
            guard let text = address[key] as? String, !text.isEmpty else { return nil }
            return text
        }
        if let specific = ["amenity", "shop", "building"].lazy.compactMap(값).first { return specific }
        guard let region = ["suburb", "quarter", "neighbourhood", "city_district"]
            .lazy.compactMap(값).first else { return nil }
        if let road = 값("road"), road != region { return "\(region) \(road)" }
        return region
    }

    /// 지금 이 프로세스가 테스트인가.
    ///
    /// **왜 있나.** `TrailUploader` 의 `namer:` 기본값이 ``shared`` 이고 `PlaceNamer()` 의 `fetch:`
    /// 기본값이 ``urlSessionFetch`` 라, 앞으로 누가 그 인자를 **안 넘긴 채** 테스트를 하나 쓰면
    /// 그 테스트가 OpenStreetMap 공개 서버를 실제로 두드린다. 그것은 그 자체로 Nominatim 사용
    /// 정책 위반이고(호의성 서비스다), CI 가 남의 서버 사정에 따라 빨개지며, 아무도 그 사고를
    /// 알아채지 못한다 — 요청이 **조용히 성공**하기 때문이다. `FirebaseBootstrap.configureForApp`
    /// 이 같은 판단으로 같은 환경변수를 보고 있다(`:31-33`).
    ///
    /// 둘 다 보는 이유: 환경변수는 `xcodebuild test` 가 넣고, `XCTestCase` 는 테스트 번들이
    /// 실제로 적재됐는지를 말한다. 어느 한쪽만 참인 실행 방식이 있어도 막힌다.
    static let 테스트_중: Bool =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || NSClassFromString("XCTestCase") != nil

    /// 단조 시계(밀리초). 벽시계가 아니다 — 사용자가 시각을 바꾸거나 NTP 가 뒤로 돌려도 요청
    /// 간격이 무너지면 안 된다.
    static func uptimeMillis() -> Int64 {
        Int64(bitPattern: DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }

    /// 요청이 이 한 종류뿐이라 HTTP 라이브러리를 하나 더 들이지 않는다(`PlaceNamer.kt:20-23` 과 같은
    /// 판단). 제한시간은 `URLRequest.timeoutInterval` 로 건다 — 코틀린이 소켓 제한시간
    /// (`connectTimeout`/`readTimeout`, `:99-100`)으로 예산을 지킨 것과 같은 자리다.
    static func urlSessionFetch(_ url: URL, _ timeout: TimeInterval) async throws -> Data {
        // **테스트에서는 여기서 끝난다.** 이 앱이 바깥 서버로 나가는 유일한 자리라 문을 여기 건다 —
        // 주입을 잊은 테스트가 하나 생겨도 요청이 못 나간다(``테스트_중`` 주석). 부르는 쪽(`name`)은
        // 이 오류를 다른 실패와 똑같이 nil 로 받으므로 테스트는 "이름을 못 얻었다"로 진행한다.
        if 테스트_중 { throw PlaceNamerError.테스트에서는_네트워크를_안_탄다 }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            // 코틀린도 HTTP 200 이 아니면 null 이다(`:102-105`). 재시도는 없다.
            throw URLError(.badServerResponse)
        }
        return data
    }
}
