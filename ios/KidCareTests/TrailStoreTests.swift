import Foundation
import Testing
@testable import KidCare

/// 오늘 경로 파일의 왕복과 "실패를 삼킨다"를 본다. 정본은 안드로이드 `child/TrailStore.kt` 전체다.
/// 임시 디렉터리를 주입받아 실제 Application Support 를 안 건드린다.
struct TrailStoreTests {

    private func 임시_디렉터리() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @Test("점을 붙였다 다시 읽으면 그대로다. 첫 줄은 dayKey 다")
    func 왕복() throws {
        let store = TrailStore(directory: 임시_디렉터리())
        store.reset(dayKey: "2026-09-22")
        let points = [
            Fix(lat: 37.5665, lng: 126.9780, accuracy: 10, at: 1, speed: 0),
            Fix(lat: 37.5666, lng: 126.9781, accuracy: 12.5, at: 6_000, speed: 1.25),
        ]
        points.forEach(store.append)
        let saved = try #require(store.load())
        #expect(saved.dayKey == "2026-09-22")
        #expect(saved.points.map(\.at) == [1, 6_000])
        #expect(saved.points[1].speed == 1.25)
        #expect(saved.points[0].lat == 37.5665)
    }

    @Test("헤더만 있고 점이 없어도 정상이다 — reset 직후의 모양(TrailStore.kt:39-40)")
    func 헤더만() throws {
        let store = TrailStore(directory: 임시_디렉터리())
        store.reset(dayKey: "2026-09-22")
        let saved = try #require(store.load())
        #expect(saved.dayKey == "2026-09-22")
        #expect(saved.points.isEmpty)
    }

    @Test("reset 은 그 날짜로 새로 시작한다 — 어제 점이 오늘 문서로 새지 않는다")
    func 다시_시작() throws {
        let store = TrailStore(directory: 임시_디렉터리())
        store.reset(dayKey: "2026-09-21")
        store.append(Fix(lat: 37.5, lng: 127, accuracy: 10, at: 1))
        store.reset(dayKey: "2026-09-22")
        let saved = try #require(store.load())
        #expect(saved.dayKey == "2026-09-22")
        #expect(saved.points.isEmpty)
    }

    @Test("파일이 아예 없으면 nil 이다 — reset 전의 첫 실행")
    func 파일_없음() {
        #expect(TrailStore(directory: 임시_디렉터리()).load() == nil)
    }

    @Test("마지막 줄이 잘려 있어도 나머지는 살린다 — 쓰다가 죽은 파일(TrailCodec.decode 주석)")
    func 잘린_줄() throws {
        let dir = 임시_디렉터리()
        let store = TrailStore(directory: dir)
        store.reset(dayKey: "2026-09-22")
        store.append(Fix(lat: 37.5665, lng: 126.9780, accuracy: 10, at: 1))
        // 두 번째 점이 쓰이다 말았다.
        let url = dir.appendingPathComponent(TrailStore.fileName)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("37.5666,126.97".utf8))
        try handle.close()

        let saved = try #require(store.load())
        #expect(saved.dayKey == "2026-09-22")
        #expect(saved.points.map(\.at) == [1], "잘린 한 줄 때문에 그날 기록 전체를 버리면 사고가 훨씬 커진다")
    }

    @Test("못 쓰는 경로를 줘도 예외를 던지지 않는다 — 이 파일은 사본이지 원본이 아니다(TrailStore.kt:23-25)")
    func 쓰기_실패를_삼킨다() {
        // /dev/null 은 디렉터리가 아니라 그 아래로는 만들 수도 쓸 수도 없다.
        let store = TrailStore(directory: URL(fileURLWithPath: "/dev/null/kidcare"))
        store.reset(dayKey: "2026-09-22")
        store.append(Fix(lat: 37.5665, lng: 126.9780, accuracy: 10, at: 1))
        #expect(store.load() == nil)
    }

    @Test("reset 없이 append 만 해도 죽지 않는다 — 파일이 없으면 조용히 버린다")
    func reset_없는_append() {
        let store = TrailStore(directory: 임시_디렉터리())
        store.append(Fix(lat: 37.5665, lng: 126.9780, accuracy: 10, at: 1))
        #expect(store.load() == nil)
    }

    @Test("파일은 iCloud 백업에서 빠진다 — 하루치 위치가 밖으로 나갈 이유가 없다(설계서 §6.2)")
    func 백업_제외() throws {
        let dir = 임시_디렉터리()
        let store = TrailStore(directory: dir)
        store.reset(dayKey: "2026-09-22")
        store.append(Fix(lat: 37.5665, lng: 126.9780, accuracy: 10, at: 1))
        let url = dir.appendingPathComponent(TrailStore.fileName)
        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test("파일 이름은 안드로이드와 같다(TrailStore.kt:68)")
    func 파일_이름() {
        #expect(TrailStore.fileName == "trail_today.csv")
    }
}
