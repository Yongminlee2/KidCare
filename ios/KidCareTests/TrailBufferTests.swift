import Foundation
import Testing
@testable import KidCare

/// 오늘 점 메모리 버퍼의 자정 넘김과 재시작 복구. 정본은 안드로이드 `TrailUploader.kt:73-104`.
@MainActor
struct TrailBufferTests {

    private let zone = TimeZone(identifier: "Asia/Seoul")!

    /// 2026-09-22 09:00 KST(= 2026-09-22 00:00 UTC).
    private let 아침: Int64 = 1_790_035_200_000
    /// 2026-09-23 09:00 KST (하루 뒤).
    private var 다음날: Int64 { 아침 + 24 * 60 * 60_000 }

    private func 임시_저장소() -> TrailStore {
        TrailStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    private func fix(_ at: Int64, _ lat: Double = 37.5665) -> Fix {
        Fix(lat: lat, lng: 126.9780, accuracy: 10, at: at, speed: 0)
    }

    @Test("같은 날의 점은 계속 쌓인다")
    func 같은_날() {
        let store = 임시_저장소()
        let buffer = TrailBuffer()
        buffer.append(fix(아침), store: store, zone: zone)
        buffer.append(fix(아침 + 5_000), store: store, zone: zone)
        #expect(buffer.points.map(\.at) == [아침, 아침 + 5_000])
        #expect(buffer.dayKey == "2026-09-22")
        #expect(store.load()?.points.count == 2)
    }

    @Test("날짜가 바뀌면 버퍼와 파일을 비우고 그 날짜로 새로 시작한다")
    func 자정_넘김() {
        let store = 임시_저장소()
        let buffer = TrailBuffer()
        buffer.append(fix(아침), store: store, zone: zone)
        buffer.append(fix(다음날), store: store, zone: zone)
        #expect(buffer.dayKey == "2026-09-23")
        #expect(buffer.points.map(\.at) == [다음날], "어제 점이 오늘 문서로 새면 안 된다")
        let saved = store.load()
        #expect(saved?.dayKey == "2026-09-23")
        #expect(saved?.points.count == 1)
    }

    @Test("restore 는 오늘 파일만 되찾는다 — 어제 파일이면 아무것도 안 한다(TrailUploader.kt:73-83)")
    func 어제_파일() {
        let store = 임시_저장소()
        store.reset(dayKey: "2026-09-21")
        store.append(fix(아침 - 24 * 60 * 60_000))
        let buffer = TrailBuffer()
        #expect(buffer.restore(store: store, zone: zone, nowMillis: 아침) == nil)
        #expect(buffer.points.isEmpty)
        #expect(buffer.dayKey == nil)
    }

    @Test("restore 가 마지막 점을 돌려준다 — 호출자가 필터 기준점으로 이어 쓴다(비스듬한 선 하나를 막는다)")
    func 복구() throws {
        let store = 임시_저장소()
        store.reset(dayKey: "2026-09-22")
        store.append(fix(아침))
        store.append(fix(아침 + 5_000, 37.5666))

        let buffer = TrailBuffer()
        let last = try #require(buffer.restore(store: store, zone: zone, nowMillis: 아침 + 10_000))
        #expect(last.at == 아침 + 5_000)
        #expect(last.lat == 37.5666)
        #expect(buffer.points.count == 2)
        #expect(buffer.dayKey == "2026-09-22")
    }

    @Test("복구한 날의 점을 이어 붙여도 파일을 새로 만들지 않는다 — 되살아난 뒤 오늘 기록이 이어진다")
    func 복구_뒤_이어쓰기() {
        let store = 임시_저장소()
        store.reset(dayKey: "2026-09-22")
        store.append(fix(아침))
        let buffer = TrailBuffer()
        buffer.restore(store: store, zone: zone, nowMillis: 아침 + 10_000)
        buffer.append(fix(아침 + 10_000), store: store, zone: zone)
        #expect(buffer.points.count == 2)
        #expect(store.load()?.points.count == 2)
    }

    @Test("파일이 없으면 복구할 것이 없다")
    func 파일_없음() {
        let buffer = TrailBuffer()
        #expect(buffer.restore(store: 임시_저장소(), zone: zone, nowMillis: 아침) == nil)
        #expect(buffer.dayKey == nil)
    }

    @Test("점이 하나도 없는 오늘 파일을 복구하면 날짜만 되찾고 마지막 점은 없다")
    func 헤더만_복구() {
        let store = 임시_저장소()
        store.reset(dayKey: "2026-09-22")
        let buffer = TrailBuffer()
        #expect(buffer.restore(store: store, zone: zone, nowMillis: 아침) == nil)
        #expect(buffer.dayKey == "2026-09-22")
        #expect(buffer.points.isEmpty)
    }
}
