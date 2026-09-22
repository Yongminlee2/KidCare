import Foundation

/// "이 장소 안에 있었다"는 사실을 프로세스 밖에 남긴다. 정본 `child/PlaceStateStore.kt`.
///
/// ## 왜 메모리에 두면 안 되나 (`:9-20`)
///
/// `GeofenceEvaluator` 는 **직전 상태와 지금이 다를 때만** 알린다. 그 직전 상태를 메모리에만 두면
/// 아침에 학교에 도착한 사실이 사라지고, 오후에 앱이 되살아났을 때 아이는 이미 학교 밖이라
/// `inside=false` 로 심긴다 — **그날의 하교 이탈 알림이 영영 안 나간다.** 침묵이 이 앱에서 제일
/// 나쁜 고장이다. 아이폰에서는 이 위험이 더 크다: 메모리 압박으로 앱이 죽는 일이 흔하고,
/// 지역 감시가 되살려 주는 그 순간이 곧 판정 순간이다(설계서 §7.4).
///
/// ## 저장 형식 (`:22-28`)
///
/// 값이 세 개짜리 줄 목록이라 JSON 파서를 끌어올 것도 없이 줄바꿈·탭으로 나눈다. `placeId` 는
/// Firestore 자동 ID(영숫자)라 두 구분자가 들어갈 수 없다. 그래도 읽는 쪽은 칸 수와 숫자 변환을
/// 확인하고 이상한 줄은 통째로 버린다 — 저장소가 깨졌을 때 예외로 죽는 것보다 그 장소만
/// "처음 보는 장소"로 되돌리는 쪽이 안전하다.
///
/// `UserDefaults` 는 안드로이드 SharedPreferences 자리다(설계서 §7.4). 코틀린이 `apply()` 대신
/// `commit()`(동기)을 쓴 이유(`:34-38`)는 여기서 저절로 지켜진다 — `set` 은 그 자리에서 메모리에
/// 반영되고 디스크 플러시는 프로세스가 죽어도 이어진다. `synchronize()` 는 부르지 않는다
/// (애플이 deprecated 로 표시했고, 막으려는 사고가 여기엔 없다).
@MainActor
final class PlaceStateStore {

    /// 안드로이드는 파일 이름(`kidcare_places`)과 키(`states`)가 따로지만 `UserDefaults` 는
    /// 이름 공간이 하나라 둘을 붙인다.
    static let key = "kidcare_places.states"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var states: [PlaceState] {
        get {
            (defaults.string(forKey: Self.key) ?? "")
                .components(separatedBy: Self.recordSeparator)
                .compactMap(Self.decode)
        }
        set {
            defaults.set(
                newValue.map(Self.encode).joined(separator: Self.recordSeparator),
                forKey: Self.key)
        }
    }

    private static let recordSeparator = "\n"
    private static let fieldSeparator = "\t"

    private static func encode(_ state: PlaceState) -> String {
        [state.placeId, state.inside ? "1" : "0", String(state.lastEventAt)]
            .joined(separator: fieldSeparator)
    }

    private static func decode(_ row: String) -> PlaceState? {
        let parts = row.components(separatedBy: fieldSeparator)
        // 칸 수·숫자 변환을 확인하고 이상한 줄은 통째로 버린다(`:58-63`).
        guard parts.count == 3, !parts[0].isEmpty, let lastEventAt = Int64(parts[2]) else { return nil }
        return PlaceState(placeId: parts[0], inside: parts[1] == "1", lastEventAt: lastEventAt)
    }
}
