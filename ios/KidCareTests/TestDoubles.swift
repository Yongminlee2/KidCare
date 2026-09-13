import FirebaseFirestore
import Foundation
import Testing
import os

/// 여러 스위트가 함께 쓰는 테스트 도구. `MapViewModelTests`·`LiveTrackingTests` 안에
/// 같은 발상의 `Gate` 가 각자 중첩 타입으로 있다 — 이름이 겹쳐 가려지지 않게 모두
/// `Test` 접두사를 붙여 파일 스코프에 둔다(기존 중첩 타입은 건드리지 않는다).

/// 테스트가 열어줄 때까지 매달려 있는 문. 한 번 열리면 계속 열려 있다.
actor TestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// 몇 번 불렸는지 센다. `@Sendable` 클로저 안에서 지역 `var` 를 세면 Swift 6 가 막는다.
actor TestCounter {
    private(set) var value = 0
    @discardableResult
    func next() -> Int {
        value += 1
        return value
    }
}

/// 테스트마다 격리된 `UserDefaults`. 기본 저장소에 쓰면 시뮬레이터의 진짜 앱 상태가
/// 오염된다(3단계 리뷰 M2 가 실제로 찾아낸 흔적).
enum TestDefaults {
    static func isolated(_ name: String) -> UserDefaults {
        UserDefaults(suiteName: "\(name)-\(UUID().uuidString)")!
    }
}

/// `i18n/` 과 `ios/` 를 함께 가진 저장소 루트. `I18nKeyParityTests.repoRoot()` 와 같은
/// 발상 — 시뮬레이터 테스트 프로세스의 작업 디렉터리는 믿을 수 없어 소스 경로에서 찾는다.
enum TestRepo {
    static func root(filePath: String = #filePath) -> URL? {
        var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        while true {
            let fm = FileManager.default
            if fm.fileExists(atPath: dir.appendingPathComponent("i18n").path),
               fm.fileExists(atPath: dir.appendingPathComponent("ios").path) {
                return dir
            }
            let parent = dir.deletingLastPathComponent()
            if parent == dir { return nil }
            dir = parent
        }
    }
}

/// 조건이 참이 될 때까지 메인 액터를 양보하며 기다린다. 뷰모델은 Firestore 콜백을
/// `Task { @MainActor in }` 로 건너오므로, 콜백을 부른 직후 곧바로 상태를 보면
/// 아직 안 바뀌어 있다. 시간이 다 되면 실패를 기록한다.
@MainActor
func eventually(timeoutSeconds: Double = 2, _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    Issue.record("조건이 \(timeoutSeconds)초 안에 참이 되지 않았다")
}

/// 딱 한 번 발화하는 신호 — "이 지점을 실제로 지났다"를 테스트에 알린다. `Task.yield()`
/// 횟수로 순서를 가정하지 않기 위해서다(3단계 리뷰 I2).
actor TestSignal {
    private var fired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if fired { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func fire() {
        guard !fired else { return }
        fired = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// 테스트가 움직이는 시계(UTC 밀리초). `@Sendable` 클로저에서 읽히므로 잠금으로 지킨다 —
/// `OSAllocatedUnfairLock` 이 Sendable 이라 `@unchecked` 가 필요 없다.
final class TestClock: Sendable {
    private let lock: OSAllocatedUnfairLock<Int64>
    init(_ millis: Int64) { lock = OSAllocatedUnfairLock(initialState: millis) }
    var value: Int64 { lock.withLock { $0 } }
    func advance(_ millis: Int64) { lock.withLock { $0 += millis } }
}

/// 진짜 `ListenerRegistration` 흉내. `remove()` 가 불렸는지 본다.
///
/// **`@unchecked Sendable` 은 테스트 타깃에만 있다**(`MapViewModelTests.FakeListenerRegistration`
/// 과 같은 이유) — 프로토콜이 `NSObjectProtocol` 과 동기 `remove()` 를 요구해 actor 로 못
/// 만들고, 잠금으로 직접 지킨다.
final class TestListenerRegistration: NSObject, ListenerRegistration, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)
    var removed: Bool { lock.withLock { $0 } }
    func remove() { lock.withLock { $0 = true } }
}

/// Firestore 콜백 클로저(비 Sendable)를 `@Sendable` 가짜 저장소 밖으로 꺼내 두는 상자.
/// 테스트 전용 — 위와 같은 이유로 잠금으로 지킨다.
final class TestCallbackBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?
    func set(_ value: T) { lock.withLock { stored = value } }
    var value: T? { lock.withLock { stored } }
}
