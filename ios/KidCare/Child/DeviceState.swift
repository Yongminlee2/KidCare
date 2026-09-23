import Foundation
import Network
import os
import UIKit

/// `NWPathMonitor` 가 알려 준 **마지막** 통신 종류를 들고 있는 상자.
///
/// `pathUpdateHandler` 는 `@Sendable` 이라 `@MainActor` 인 [DeviceState] 를 붙잡을 수 없다.
/// 그래서 경로 자체(`NWPath` 는 `Sendable` 이 아니다)가 아니라 **글자 하나**만 잠금에 담아
/// 건네받는다 — `@unchecked Sendable` 을 새로 만들지 않는 방법이기도 하다(Global Constraints).
///
/// **첫 갱신이 오기 전에는 빈 값(모름)이다.** `start(queue:)` 직후의 `currentPath` 는 아직
/// 확정값이 아니라, 그때 읽으면 페어링 직후 처음 뜨는 부모 화면이 "연결 없음"이라고 **거짓말**한다
/// — `ringerMode` 를 굳이 빈 값으로 쓴 이유(`Documents.swift:235-239`)와 같은 기준이다.
/// 모름이어도 **업로드는 그대로 나간다**(안드로이드가 통신 상태를 읽느라 쓰기를 미루지 않는 것과 같다).
final class NetworkPathBox: Sendable {

    private let latest = OSAllocatedUnfairLock<String?>(initialState: nil)

    /// `wifi` · `cell` · `none`, 그리고 **첫 갱신 전에는 빈 값**이다.
    /// 빈 값(모름)과 `none`(붙어 있지 않음)은 다른 말이다.
    var kind: String { latest.withLock { $0 } ?? NetworkKind.unknown }

    func update(_ kind: String) { latest.withLock { $0 = kind } }
}

/// 아이 폰의 지금 상태. **읽기만 한다** — 안드로이드 `child/NetworkState.kt:8-20` 머리 주석과
/// 같은 이유로 끄고 켜는 기능이 없다(아이폰은 읽는 것조차 더 적다).
///
/// 설계서는 이 파일을 3단계에 적어 뒀지만 1단계로 당겼다(1단계 판정 기록 8) — 상태 문서를
/// 쓰면서 배터리만 나중에 채우면 그 사이 올라간 문서가 `battery: -1` 로 남아 부모 화면이
/// "모름"을 띄운다. 권한·저전력 모드 감시(`ConditionWatcher`)는 **안 당긴다**(그건 이벤트를
/// 쓰는 일이라 2·3단계 몫이다).
///
/// `wifiOn`(`NetworkState.kt:43-49`)은 **안 옮긴다.** 아이폰에는 와이파이 스위치를 읽는 API 가
/// 없고, `false`(꺼짐)와 없음(모름)은 다른 말이다(1단계 판정 기록 10).
@MainActor
final class DeviceState {

    struct Snapshot: Equatable {
        /// 0~100. **못 읽으면 -1 이다** — 0 으로 뭉개면 부모 화면이 "다 닳았다"고 거짓말한다
        /// (코틀린 `ChildStatusDoc.battery` 기본값도 -1 이다, `Documents.kt:93`).
        let batteryPercent: Int
        let charging: Bool
        /// `wifi` · `cell` · `none` · 빈 값(모름). 글자는 `NetworkState.kt:23-26` 그대로이고
        /// [NetworkKind] 가 그 값을 들고 있다.
        let network: String
    }

    typealias BatteryReader = @MainActor () -> (level: Float, state: UIDevice.BatteryState)
    typealias NetworkReader = @MainActor () -> String

    private let readBattery: BatteryReader
    private let readNetwork: NetworkReader
    private let monitor: NWPathMonitor?

    /// 경로 감시는 한 번 켜 두고 [NetworkPathBox] 가 받아 둔 마지막 값을 읽는다.
    /// `currentPath` 를 동기로 읽지 **않는다** — `start(queue:)` 가 첫 경로를 큐로 넘기기 전에는
    /// 확정값이 아니라, 그 사이에 나간 첫 상태 문서가 "연결 없음"으로 거짓말한다(그 상자 주석).
    private static let monitorQueue = DispatchQueue(label: "com.kidcare.family.network-path")

    /// **시뮬레이터는 배터리를 안 준다**(`batteryLevel` 이 -1, `batteryState` 가 `.unknown`;
    /// `simctl status_bar override` 는 화면 위 막대만 바꾼다). 그래서 읽기를 주입받는다 —
    /// 기본값이 진짜 `UIDevice` 이고, 시뮬레이터 확인은 `ChildSession.injectedBattery`
    /// (`-childBattery <0~100>`, `#if DEBUG`)가 값을 넣어 준다(3단계 판정 기록 3).
    /// 실기기 실측은 4단계다.
    init(battery: @escaping BatteryReader = DeviceState.systemBattery,
         network: NetworkReader? = nil) {
        readBattery = battery
        if let network {
            readNetwork = network
            monitor = nil
        } else {
            let box = NetworkPathBox()
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in box.update(DeviceState.networkKind(of: path)) }
            monitor.start(queue: Self.monitorQueue)
            self.monitor = monitor
            readNetwork = { box.kind }
        }
    }

    func snapshot() -> Snapshot {
        let battery = readBattery()
        return Snapshot(
            batteryPercent: Self.percent(battery.level),
            charging: Self.isCharging(battery.state),
            network: readNetwork()
        )
    }

    /// 안드로이드 `TrackingService.batteryPercent()`(:823-826)가 `BATTERY_PROPERTY_CAPACITY` 로
    /// 곧장 0~100 정수를 받는 자리다. 아이폰은 0~1 실수라 여기서 백분율로 바꾼다.
    static func percent(_ level: Float) -> Int {
        level < 0 ? -1 : Int((level * 100).rounded())
    }

    /// `TrackingService.isCharging()`(:836-837)의 `BATTERY_STATUS_CHARGING || BATTERY_STATUS_FULL`
    /// 그대로다.
    static func isCharging(_ state: UIDevice.BatteryState) -> Bool {
        state == .charging || state == .full
    }

    static func systemBattery() -> (level: Float, state: UIDevice.BatteryState) {
        // 이 스위치를 안 켜면 레벨이 항상 -1 이다. 여러 번 켜도 문제가 없다.
        UIDevice.current.isBatteryMonitoringEnabled = true
        return (UIDevice.current.batteryLevel, UIDevice.current.batteryState)
    }

    /// 순수 함수라 `nonisolated` 다 — `NWPathMonitor` 의 `@Sendable` 콜백이 이것을 부른다
    /// (`LocationCollector.fix(from:)` 와 같은 모양).
    nonisolated static func networkKind(of path: NWPath) -> String {
        networkKind(
            satisfied: path.status == .satisfied,
            wifi: path.usesInterfaceType(.wifi),
            cellular: path.usesInterfaceType(.cellular)
        )
    }

    /// `NetworkState.current()`(:32-37)의 `when` 을 글자 그대로 옮긴 것이다. 순서까지 같다 —
    /// 와이파이와 셀룰러가 함께 잡히면 와이파이가 이긴다.
    ///
    /// **붙어 있지 않으면 `none` 이다.** 와이파이 스위치가 켜져 있어도 공유기가 인터넷에 못
    /// 나가면 `none` 이라는 것이 코틀린 주석(:17-19)이 굳이 적어 둔 구분이다.
    nonisolated static func networkKind(satisfied: Bool, wifi: Bool, cellular: Bool) -> String {
        guard satisfied else { return NetworkKind.none }
        if wifi { return NetworkKind.wifi }
        if cellular { return NetworkKind.cell }
        return NetworkKind.none
    }
}
