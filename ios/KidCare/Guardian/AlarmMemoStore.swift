import Foundation

struct AlarmMemo: Equatable {
    let minuteOfDay: Int
    let label: String
    /// 아이 폰이 done 이라고 적었다는 것뿐이다 — 그 뒤 아이가 앱을 강제 종료하면 알람은
    /// 사라지지만 이 값은 모른다. 그 자리는 무응답 배너가 덮는다(AlarmMemoStore.kt:17-23).
    let confirmed: Bool
}

/// "애기폰에 알람을 맞춰 뒀다"는 부모 폰의 기억. 정본은 안드로이드 `guardian/AlarmMemoStore.kt`.
///
/// 부모가 지금 알람이 걸려 있는지 볼 수 없으면 **세 개를 건다.** 알람은 아이 폰 안에만 있고
/// 물어볼 통로가 없어서(서버에 두면 알람 하나에 쓰기 하나가 붙는다 — 무료 한도) 부모 폰이
/// 자기가 보낸 것을 기억한다. `RequestLog` 와 같은 자리, 같은 이유다.
///
/// 키에 `alarm_memo_` 를 붙인다 — 안드로이드는 전용 prefs 파일을 쓰지만 여기서는
/// `RoleStore`·`RequestLog` 와 같은 `UserDefaults` 를 나눠 쓴다(계획서 판정 기록 7).
struct AlarmMemoStore {

    /// 안드로이드 `MAX_MINUTE_OF_DAY = 1439`(:89).
    static let maxMinuteOfDay = 1439
    /// 안드로이드 `EXPIRY_MILLIS = 24 * 60 * 60 * 1000L`(:90).
    static let expiryMillis: Int64 = 24 * 60 * 60 * 1000

    private let defaults: UserDefaults
    private let now: @Sendable () -> Int64

    init(
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.defaults = defaults
        self.now = now
    }

    /// 걸어 둔 알람. 없거나 24시간이 지났으면 nil(:39-49).
    func memo(childUid: String) -> AlarmMemo? {
        guard let minute = defaults.object(forKey: key("minute_of_day", childUid)) as? Int,
              (0...Self.maxMinuteOfDay).contains(minute) else { return nil }
        let sentAt = Int64(defaults.integer(forKey: key("sent_at", childUid)))
        guard now() - sentAt < Self.expiryMillis else { return nil }
        return AlarmMemo(
            minuteOfDay: minute,
            label: defaults.string(forKey: key("label", childUid)) ?? "",
            confirmed: defaults.bool(forKey: key("confirmed", childUid))
        )
    }

    /// 명령이 실제로 발행됐다. 아직 아이 폰의 대답은 못 들었다(:52-59).
    func recordSent(childUid: String, minuteOfDay: Int, label: String) {
        defaults.set(minuteOfDay, forKey: key("minute_of_day", childUid))
        defaults.set(label, forKey: key("label", childUid))
        defaults.set(Int(now()), forKey: key("sent_at", childUid))
        defaults.set(false, forKey: key("confirmed", childUid))
    }

    /// 아이 폰이 done 을 적었다. 기록이 없으면(만료됐거나 취소된 뒤 늦게 온 콜백)
    /// 되살리지 않는다 — 없는 알람을 "맞춰져 있어요"로 만들 자리다(:62-67).
    func recordConfirmed(childUid: String) {
        guard let minute = defaults.object(forKey: key("minute_of_day", childUid)) as? Int,
              (0...Self.maxMinuteOfDay).contains(minute) else { return }
        defaults.set(true, forKey: key("confirmed", childUid))
    }

    /// 알람을 껐거나, 맞추기가 실패했다(:70-77).
    func clear(childUid: String) {
        for base in ["minute_of_day", "label", "sent_at", "confirmed"] {
            defaults.removeObject(forKey: key(base, childUid))
        }
    }

    private func key(_ base: String, _ childUid: String) -> String { "alarm_memo_\(base)_\(childUid)" }
}
