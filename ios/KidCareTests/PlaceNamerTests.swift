import Foundation
import Testing
@testable import KidCare

/// 정본은 `child/PlaceNamer.kt`. 네트워크·시계·잠자기를 전부 주입해 **실제 요청 없이** 돈다 —
/// 테스트가 OpenStreetMap 공개 서버를 두드리면 그 자체가 사용 정책 위반이다.
/// 이 파일의 어떤 테스트도 `URLSession` 을 타지 않는다.
struct PlaceNamerTests {

    /// 요청을 기록하고 정해진 답을 주는 가짜.
    actor 가짜_서버 {
        private(set) var 요청: [(url: URL, timeout: TimeInterval, at: Int64)] = []
        private var 답: [Data?]
        private let 시계: 가짜_시계
        init(답: [Data?], 시계: 가짜_시계) { self.답 = 답; self.시계 = 시계 }
        func fetch(_ url: URL, _ timeout: TimeInterval) async throws -> Data {
            요청.append((url, timeout, await 시계.지금))
            guard !답.isEmpty, let data = 답.removeFirst() else { throw URLError(.timedOut) }
            return data
        }
        var 횟수: Int { 요청.count }
    }

    /// 자는 대신 시각만 앞으로 민다 — 벽시계를 기다리는 테스트를 만들지 않는다.
    /// `잔_시각` 은 **확보된 슬롯**의 기록이다. 요청이 실제로 나간 시각(`가짜_서버.요청.at`)은
    /// 다른 과제가 먼저 시계를 밀어 버리면 같은 값으로 뭉칠 수 있어, 슬롯 자체를 따로 남긴다.
    actor 가짜_시계 {
        private(set) var 지금: Int64 = 0
        private(set) var 잔_시각: [Int64] = []
        func sleep(until due: Int64) async {
            잔_시각.append(due)
            if due > 지금 { 지금 = due }
        }
    }

    /// 자는 사이에 다른 호출을 **한 번** 끼워 넣는 장치. actor 재진입을 실제로 일으킨다.
    actor 끼어들기 {
        private var namer: PlaceNamer?
        private var 남았나 = true
        func 건다(_ namer: PlaceNamer) { self.namer = namer }
        func 끼어든다() async {
            guard 남았나, let namer else { return }
            남았나 = false
            _ = await namer.name(lat: 39.5, lng: 127.0)
        }
    }

    private func 본문(_ address: [String: String]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["address": address])
    }

    private func 만든다(답: [Data?], suite: String? = nil) -> (PlaceNamer, 가짜_서버, 가짜_시계) {
        let 시계 = 가짜_시계()
        let 서버 = 가짜_서버(답: 답, 시계: 시계)
        let namer = PlaceNamer(
            suiteName: suite ?? "test-\(UUID().uuidString)",
            fetch: { url, timeout in try await 서버.fetch(url, timeout) },
            now: { await 시계.지금 },
            sleep: { due in await 시계.sleep(until: due) })
        return (namer, 서버, 시계)
    }

    @Test("상수는 코틀린 그대로다 (PlaceNamer.kt:146, :150, :152, :153, TrailUploader.kt:235)")
    func 상수() {
        #expect(PlaceNamer.endpoint == "https://nominatim.openstreetmap.org/reverse")
        #expect(PlaceNamer.userAgent == "KidCare/1.0 (com.kidcare.family)")
        #expect(PlaceNamer.timeoutSeconds == 5.0)
        #expect(PlaceNamer.minIntervalMillis == 1_000)
        #expect(PlaceNamer.geocodeBudgetMillis == 3_000)
    }

    @Test("상호·건물명이 있으면 그것을 쓴다 (PlaceNamer.kt:129-131)")
    func 이름_고르기_상호() async {
        let (namer, _, _) = 만든다(답: [본문(["amenity": "행복 어린이집", "suburb": "역삼동", "road": "테헤란로"])])
        #expect(await namer.name(lat: 37.5, lng: 127.0) == "행복 어린이집")
    }

    @Test("상호가 없으면 행정동 + 도로명. 도로명이 없거나 같으면 행정동만 (PlaceNamer.kt:133-138)")
    func 이름_고르기_행정동() async {
        let (a, _, _) = 만든다(답: [본문(["suburb": "역삼동", "road": "테헤란로"])])
        #expect(await a.name(lat: 37.5, lng: 127.0) == "역삼동 테헤란로")
        let (b, _, _) = 만든다(답: [본문(["quarter": "역삼1동"])])
        #expect(await b.name(lat: 37.5, lng: 127.0) == "역삼1동")
        let (c, _, _) = 만든다(답: [본문(["suburb": "역삼동", "road": "역삼동"])])
        #expect(await c.name(lat: 37.5, lng: 127.0) == "역삼동")
    }

    @Test("주소가 없으면 nil 이고, 실패는 캐시하지 않는다 (PlaceNamer.kt:36-38, :127)")
    func 실패는_캐시_안_한다() async {
        let (namer, 서버, _) = 만든다(답: [nil, 본문(["suburb": "역삼동"])])
        #expect(await namer.name(lat: 37.5, lng: 127.0) == nil)
        #expect(await namer.name(lat: 37.5, lng: 127.0) == "역삼동",
                "한 번의 네트워크 오류가 그 자리를 하루 종일 이름 없이 가두면 안 된다")
        #expect(await 서버.횟수 == 2)
    }

    @Test("캐시가 맞으면 네트워크를 안 탄다 — 30m 안이면 같은 곳이다 (PlaceNameCache.kt:67)")
    func 캐시_적중() async {
        let (namer, 서버, _) = 만든다(답: [본문(["amenity": "집"])])
        _ = await namer.name(lat: 37.5, lng: 127.0)
        // 약 11m 북쪽 — 같은 머무름에서 이름 좌표가 흔들리는 폭이다.
        #expect(await namer.name(lat: 37.5001, lng: 127.0) == "집")
        #expect(await 서버.횟수 == 1)
    }

    @Test("네트워크 없이 아는 이름만 준다 (PlaceNamer.kt:57-58)")
    func 캐시만_묻기() async {
        let (namer, 서버, _) = 만든다(답: [본문(["amenity": "집"])])
        #expect(await namer.cachedName(lat: 37.5, lng: 127.0) == nil)
        _ = await namer.name(lat: 37.5, lng: 127.0)
        #expect(await namer.cachedName(lat: 37.5, lng: 127.0) == "집")
        #expect(await 서버.횟수 == 1)
    }

    @Test("요청 간격이 1초 밑으로 안 내려간다 — Nominatim 사용 정책 (PlaceNamer.kt:84-90)")
    func 초당_한_건() async {
        let (namer, 서버, _) = 만든다(답: [본문(["amenity": "가"]), 본문(["amenity": "나"])])
        _ = await namer.name(lat: 37.5, lng: 127.0)
        _ = await namer.name(lat: 38.5, lng: 127.0)
        let 요청 = await 서버.요청
        #expect(요청.count == 2)
        #expect(요청[1].at - 요청[0].at >= 1_000)
    }

    @Test("자는 사이에 들어온 호출은 다음 슬롯을 받는다 — actor 재진입(판정 기록 7)")
    func 자는_사이_재진입() async {
        let 시계 = 가짜_시계()
        let 서버 = 가짜_서버(답: [본문(["amenity": "가"]), 본문(["amenity": "나"]), 본문(["amenity": "다"])],
                          시계: 시계)
        let 끼어들장치 = 끼어들기()
        let namer = PlaceNamer(
            suiteName: "test-\(UUID().uuidString)",
            fetch: { url, timeout in try await 서버.fetch(url, timeout) },
            now: { await 시계.지금 },
            // 자는 **동안** 다른 호출이 들어온다 — 코틀린이 Mutex 로 막은 바로 그 순간이다.
            sleep: { due in
                await 시계.sleep(until: due)
                await 끼어들장치.끼어든다()
            })
        await 끼어들장치.건다(namer)

        _ = await namer.name(lat: 37.5, lng: 127.0)   // 안 자고 바로 쏜다. 슬롯을 1000 으로 민다.
        _ = await namer.name(lat: 38.5, lng: 127.0)   // 1000 까지 자고, 그 사이에 셋째가 끼어든다.

        #expect(await 서버.횟수 == 3)
        #expect(await 시계.잔_시각 == [1_000, 2_000],
                "자기 **전에** 슬롯을 밀지 않으면 끼어든 호출이 같은 1000 을 보고 안 자고 쏜다")
    }

    @Test("남은 예산 안에 슬롯을 못 잡으면 아예 묻지 않는다 — 기다린 시간이 통째로 낭비된다")
    func 예산이_모자라면_안_묻는다() async {
        let (namer, 서버, _) = 만든다(답: [본문(["amenity": "가"]), 본문(["amenity": "나"])])
        _ = await namer.name(lat: 37.5, lng: 127.0)          // 슬롯을 1초 뒤로 민다
        // 다음 슬롯까지 1초를 기다려야 하는데 남은 예산이 0.5초다 → 기다리지 않고 포기한다.
        #expect(await namer.name(lat: 38.5, lng: 127.0, budgetLeftMillis: 500) == nil)
        #expect(await 서버.횟수 == 1)
        // 예산이 넉넉하면 그대로 묻는다.
        #expect(await namer.name(lat: 38.5, lng: 127.0, budgetLeftMillis: 2_000) == "나")
        #expect(await 서버.횟수 == 2)
    }

    @Test("URL 과 헤더가 코틀린과 같다 (PlaceNamer.kt:95-101)")
    func 요청_모양() async throws {
        let (namer, 서버, _) = 만든다(답: [본문(["amenity": "집"])])
        _ = await namer.name(lat: 37.5, lng: 127.0, timeout: 2.0)
        let 요청 = try #require(await 서버.요청.first)
        #expect(요청.url.absoluteString ==
                "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=37.5&lon=127.0&accept-language=ko&zoom=18")
        #expect(요청.timeout == 2.0, "부르는 쪽이 남은 예산을 넘겨 준다(PlaceNamer.kt:64-66)")
    }

    @Test("얻은 이름은 디스크에 남아 다음 프로세스가 즉시 쓴다 (PlaceNamer.kt:52-55, :73)")
    func 디스크_보존() async {
        let suite = "test-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let (namer, _, _) = 만든다(답: [본문(["amenity": "집"])], suite: suite)
        _ = await namer.name(lat: 37.5, lng: 127.0)

        // 프로세스가 다시 뜬 셈 — 같은 저장소를 **이름으로** 다시 여는 새 인스턴스다.
        let (다시, 서버2, _) = 만든다(답: [], suite: suite)
        #expect(await 다시.cachedName(lat: 37.5, lng: 127.0) == "집")
        #expect(await 서버2.횟수 == 0)
    }
}
