import Foundation
import Network
import Testing
import UIKit
@testable import KidCare

/// 배터리·충전·통신 종류의 **매핑만** 본다. 진짜 `UIDevice`·`NWPathMonitor` 를 안 쓴다 —
/// 시뮬레이터는 배터리를 안 주고(레벨 -1), 통신 상태는 테스트가 정할 수 없다(1단계 판정 기록 8).
@MainActor
struct DeviceStateTests {

    @Test("배터리 레벨 0.77 은 77% 다")
    func 배터리_변환() {
        let state = DeviceState(battery: { (0.77, .unplugged) }, network: { NetworkKind.none })
        #expect(state.snapshot().batteryPercent == 77)
    }

    @Test("못 읽으면(-1) -1 을 그대로 올린다 — 0% 로 뭉개면 부모가 놀란다(Documents.kt:93 의 기본값도 -1)")
    func 배터리_모름() {
        let state = DeviceState(battery: { (-1, .unknown) }, network: { NetworkKind.none })
        #expect(state.snapshot().batteryPercent == -1)
    }

    @Test("0.0 은 0% 다 — 다 닳은 것과 못 읽은 것은 다른 말이다")
    func 배터리_바닥() {
        let state = DeviceState(battery: { (0, .unplugged) }, network: { NetworkKind.none })
        #expect(state.snapshot().batteryPercent == 0)
        #expect(DeviceState(battery: { (1, .full) }, network: { NetworkKind.none }).snapshot().batteryPercent == 100)
    }

    @Test("charging 과 full 은 충전 중이다(TrackingService.kt:836-837)")
    func 충전() {
        for state: UIDevice.BatteryState in [.charging, .full] {
            #expect(DeviceState(battery: { (0.5, state) }, network: { NetworkKind.none }).snapshot().charging, "\(state)")
        }
        for state: UIDevice.BatteryState in [.unplugged, .unknown] {
            #expect(DeviceState(battery: { (0.5, state) }, network: { NetworkKind.none }).snapshot().charging == false, "\(state)")
        }
    }

    @Test("통신 종류 값은 NetworkState.kt:23-26 과 같은 글자다: wifi · cell · none")
    func 통신_글자() {
        #expect(NetworkKind.wifi == "wifi")
        #expect(NetworkKind.cell == "cell")
        #expect(NetworkKind.none == "none")
        let state = DeviceState(battery: { (0.5, .unplugged) }, network: { NetworkKind.wifi })
        #expect(state.snapshot().network == "wifi")
    }

    @Test("연결이 없으면 none 이다 — 와이파이 스위치가 켜져 있어도 인터넷에 못 나가면 none 이다(NetworkState.kt:32-37)")
    func 통신_없음() {
        #expect(DeviceState.networkKind(satisfied: false, wifi: true, cellular: false) == NetworkKind.none)
        #expect(DeviceState.networkKind(satisfied: true, wifi: true, cellular: false) == NetworkKind.wifi)
        #expect(DeviceState.networkKind(satisfied: true, wifi: false, cellular: true) == NetworkKind.cell)
        // 둘 다면 와이파이가 먼저다 — 코틀린 when 의 순서 그대로다.
        #expect(DeviceState.networkKind(satisfied: true, wifi: true, cellular: true) == NetworkKind.wifi)
        // 유선·기타 인터페이스는 코틀린의 `else -> NONE` 자리다.
        #expect(DeviceState.networkKind(satisfied: true, wifi: false, cellular: false) == NetworkKind.none)
    }

    @Test("경로 감시의 첫 갱신 전에는 빈 값(모름)이다 — '연결 없음'이라고 거짓말하지 않는다")
    func 경로_첫_갱신_전() {
        let 상자 = NetworkPathBox()
        #expect(상자.kind == NetworkKind.unknown)
        #expect(상자.kind.isEmpty, "빈 값이어야 부모 화면이 '모름'으로 접는다")
        #expect(상자.kind != NetworkKind.none, "붙어 있지 않다(none)와 아직 모른다는 다른 말이다")

        상자.update(NetworkKind.wifi)
        #expect(상자.kind == "wifi")
        상자.update(NetworkKind.none)
        #expect(상자.kind == "none", "갱신이 오면 그때부터 진짜 값이다")
    }

    @Test("모르는 통신 상태로도 업로드는 그대로 나간다 — 읽느라 쓰기를 미루지 않는다(NetworkState.kt 는 동기로 읽는다)")
    func 모름도_그대로_올린다() {
        let state = DeviceState(battery: { (0.5, .unplugged) }, network: { NetworkKind.unknown })
        #expect(state.snapshot().network == "")
        #expect(state.snapshot().batteryPercent == 50, "통신을 몰라도 나머지는 정상으로 실린다")
    }
}
