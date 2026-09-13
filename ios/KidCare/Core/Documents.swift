import FirebaseFirestore
import Foundation

/// Firestore 문서와 1:1 로 대응하는 구조체들. 정본은 안드로이드
/// `core/model/Documents.kt` 다 — 필드 이름이 하나라도 어긋나면 안드로이드가
/// 쓴 문서를 못 읽는다.
///
/// **Codable 을 쓰지 않는다.** `firestore.rules` 의 hasOnly() 는 대부분 create 가
/// 아니라 **update** 자리에서 "바뀐 필드 집합"을 검사한다(members·families·commands·events
/// update — 예: members/{uid} update 의 `.hasOnly(['displayName', 'fcmToken',
/// 'appVersion', 'updatedAt'])`). 예외가 하나 있다 — inviteCodes create 의 레거시
/// 2필드 갈래(`familyId`, `expiresAt`)에도 hasOnly() 가 있지만, 이 앱이 쓰는
/// `InviteCodeDoc` create 는 항상 `role`·`createdByUid` 까지 4필드를 채워 그 갈래를
/// 타지 않는다. 이 앱의 create 경로들은 그 검사를 직접 맞을 일이
/// 없지만, Codable 인코더는 그 경계를 몰라서 옵셔널 필드를 하나 더 내보내면(nil 을
/// 생략하지 않고 넣거나, 스키마가 바뀌는 순간) 나중에 update 경로가 말없이
/// hasOnly() 에 걸려 거부될 수 있다. 손으로 맵을 적으면 무엇이 나가는지 눈으로
/// 보이고, `firestoreData` 가 곧 그 계약의 증거다(DocumentsTests 가 필드 집합을
/// 못 박는 이유).
///
/// 시각은 전부 UTC 밀리초다.

enum MemberRole: String {
    case guardian
    case child
}

// MARK: - 읽기 도우미
//
// Firestore 는 정수를 NSNumber 로 돌려주는데, 안드로이드가 Long 으로 쓴 값이
// Int64 로 올 때도 Double 로 올 때도 있다. 한 자리에서 흡수한다.
private func millis(_ any: Any?) -> Int64? {
    if let n = any as? NSNumber { return n.int64Value }
    if let i = any as? Int64 { return i }
    if let i = any as? Int { return Int64(i) }
    return nil
}

private func double(_ any: Any?) -> Double? {
    (any as? NSNumber)?.doubleValue
}

struct FamilyDoc {
    var name: String = ""
    var createdAt: Int64 = 0
    var inviteCode: String = ""
    var inviteExpiresAt: Int64 = 0
    var ownerUid: String = ""
    var schemaVersion: Int = 0
    var primaryChildUid: String = ""

    static let currentSchemaVersion = 2

    init(name: String, createdAt: Int64, ownerUid: String, schemaVersion: Int) {
        self.name = name
        self.createdAt = createdAt
        self.ownerUid = ownerUid
        self.schemaVersion = schemaVersion
    }

    init?(_ data: [String: Any]) {
        name = data["name"] as? String ?? ""
        createdAt = millis(data["createdAt"]) ?? 0
        inviteCode = data["inviteCode"] as? String ?? ""
        inviteExpiresAt = millis(data["inviteExpiresAt"]) ?? 0
        ownerUid = data["ownerUid"] as? String ?? ""
        schemaVersion = Int(millis(data["schemaVersion"]) ?? 0)
        primaryChildUid = data["primaryChildUid"] as? String ?? ""
    }

    var firestoreData: [String: Any] {
        [
            "name": name,
            "createdAt": createdAt,
            "inviteCode": inviteCode,
            "inviteExpiresAt": inviteExpiresAt,
            "ownerUid": ownerUid,
            "schemaVersion": schemaVersion,
            "primaryChildUid": primaryChildUid,
        ]
    }
}

struct MemberDoc {
    var role: MemberRole
    var displayName: String = ""
    var fcmToken: String = ""      // iOS 는 푸시를 안 쓴다(설계서 §1). 늘 빈 값이다.
    var appVersion: String = ""
    var updatedAt: Int64 = 0
    var joinCode: String = ""
    var joinedAt: Int64 = 0

    init(role: MemberRole, displayName: String, updatedAt: Int64, joinCode: String = "", joinedAt: Int64) {
        self.role = role
        self.displayName = displayName
        self.updatedAt = updatedAt
        self.joinCode = joinCode
        self.joinedAt = joinedAt
    }

    init?(_ data: [String: Any]) {
        guard let raw = data["role"] as? String, let role = MemberRole(rawValue: raw) else { return nil }
        self.role = role
        displayName = data["displayName"] as? String ?? ""
        fcmToken = data["fcmToken"] as? String ?? ""
        appVersion = data["appVersion"] as? String ?? ""
        updatedAt = millis(data["updatedAt"]) ?? 0
        joinCode = data["joinCode"] as? String ?? ""
        joinedAt = millis(data["joinedAt"]) ?? 0
    }

    var firestoreData: [String: Any] {
        [
            "role": role.rawValue,
            "displayName": displayName,
            "fcmToken": fcmToken,
            "appVersion": appVersion,
            "updatedAt": updatedAt,
            "joinCode": joinCode,
            "joinedAt": joinedAt,
        ]
    }
}

struct InviteCodeDoc {
    var familyId: String
    var expiresAt: Int64
    var role: MemberRole = .child   // 빈 값은 옛 자녀 코드다
    var createdByUid: String = ""

    init(familyId: String, expiresAt: Int64, role: MemberRole, createdByUid: String) {
        self.familyId = familyId
        self.expiresAt = expiresAt
        self.role = role
        self.createdByUid = createdByUid
    }

    init?(_ data: [String: Any]) {
        guard let familyId = data["familyId"] as? String else { return nil }
        self.familyId = familyId
        expiresAt = millis(data["expiresAt"]) ?? 0
        role = MemberRole(rawValue: data["role"] as? String ?? "child") ?? .child
        createdByUid = data["createdByUid"] as? String ?? ""
    }

    var firestoreData: [String: Any] {
        [
            "familyId": familyId,
            "expiresAt": expiresAt,
            "role": role.rawValue,
            "createdByUid": createdByUid,
        ]
    }
}

/// children/{childUid} — 아이 폰의 현재 상태. 1단계는 지도 마커에 필요한 것만 읽는다.
/// 이 구조체는 **읽기 전용이다** — 보호자 앱은 이 문서를 쓰지 않는다.
struct ChildStatusDoc {
    var lat: Double
    var lng: Double
    var accuracy: Double
    var at: Int64
    var battery: Int
    var charging: Bool
    var ringerMode: String
    var dnd: String
    var network: String
    /// **false(꺼짐)와 nil(모름)은 다른 말이다.** 옛 문서에는 이 칸이 아예 없다.
    var wifiOn: Bool?
    /// **아이 폰 자기 시계**로 적은 마지막 신호 시각. 안드로이드 `Documents.kt`
    /// 의 같은 필드 주석 참고 — 아이 폰 시계가 앞서 있으면 보호자 화면의
    /// "지금 - lastSeenAt" 이 음수가 되어 "마지막 신호 -3분 전" 같은 문구가 뜬다.
    var lastSeenAt: Int64
    /// 같은 순간을 **서버 시계**로 적은 값. `@ServerTimestamp`(안드로이드)가 쓰는
    /// 값이라 아이 폰이 직접 쓰지 않는다 — 그래서 [lastSeenAt] 과 **단위가 다르다**
    /// (여긴 Firestore `Timestamp`, 저긴 UTC 밀리초 `Int64`). 보호자 쪽
    /// `FamilyRepository.serverNow` 도 서버 시각이라 이 필드와 빼면 스큐가 근본에서
    /// 사라진다. 1단계 지도는 아직 이 필드를 안 쓴다 — 3단계 상태 카드가 "마지막
    /// 신호 N분 전"을 계산할 때부터 쓴다. 옛 문서·옛 아이 폰에는 이 칸이 없을 수
    /// 있어 옵셔널이다.
    var lastSeenServerAt: Timestamp?

    init?(_ data: [String: Any]) {
        guard let lat = double(data["lat"]), let lng = double(data["lng"]) else { return nil }
        self.lat = lat
        self.lng = lng
        accuracy = double(data["accuracy"]) ?? 0
        at = millis(data["at"]) ?? 0
        battery = Int(millis(data["battery"]) ?? -1)
        charging = data["charging"] as? Bool ?? false
        ringerMode = data["ringerMode"] as? String ?? "normal"
        dnd = data["dnd"] as? String ?? ""
        network = data["network"] as? String ?? ""
        wifiOn = data["wifiOn"] as? Bool
        lastSeenAt = millis(data["lastSeenAt"]) ?? 0
        lastSeenServerAt = data["lastSeenServerAt"] as? Timestamp
    }
}

/// children/{childUid}/trails/{dayKey} 의 원소. 정본은 안드로이드
/// `core/model/Documents.kt:157-167` 의 `TrailPoint`. 이 구조체는 **읽기 전용이다**
/// — 보호자 앱은 이 문서를 쓰지 않는다(자녀 폰만 쓴다, TrailRepository.swift 참고).
///
/// `battery` 를 안 옮긴 것도 코틀린과 같은 이유다 — 읽는 곳이 없고, 배열 원소마다
/// 필드 이름이 같이 저장되므로 안 쓰는 필드 하나가 하루 문서 크기를 그대로 키운다.
struct TrailPoint {
    let lat: Double
    let lng: Double
    let accuracy: Double
    /// m/s. **반드시 실려야 한다** — `Fix.speed` 주석 참고. 2단계에서 이 값이
    /// 영원히 0 이던 버그(`let speed: Double = 0` 선언부 기본값이 memberwise
    /// 초기화 목록을 통째로 빼버린 것)를 고쳤는데, 여기서 0 으로 뭉개면 그 고침이
    /// 소용없어진다 — `RoutePathRefiner` 가 실제 속도를 영원히 못 받는다.
    let speed: Double
    let at: Int64

    init?(_ data: [String: Any]) {
        guard let lat = double(data["lat"]), let lng = double(data["lng"]) else { return nil }
        self.lat = lat
        self.lng = lng
        accuracy = double(data["accuracy"]) ?? 0
        speed = double(data["speed"]) ?? 0
        at = millis(data["at"]) ?? 0
    }

    /// `RoutePathRefiner.refine(points:)` 가 요구하는 값 모양으로 바꾼다.
    var asFix: Fix { Fix(lat: lat, lng: lng, accuracy: accuracy, at: at, speed: speed) }
}

/// 아이 폰이 마지막으로 신호를 남긴 시각. 정본은 안드로이드 `GuardianMainActivity.kt`
/// 의 `ChildSignal`·`ChildStatusDoc.lastSignal()`·`LastSignalText`.
///
/// 코틀린은 시각(`ChildSignal`, 절대 밀리초 + 출처)과 표기(`LastSignalText`, "12분 전")를
/// 나눠 두고, "아이 폰 시계라 상대 표현을 못 쓰는 경우"(음수 경과)를 위한 셋째 갈래
/// (절대 시각 노출)를 끼워 넣는다. 이 열거형도 그 셋째 갈래를 `.skewed` 로 그대로
/// 갖는다(Fix round 1) — 서버 시각의 음수 경과(왕복 보정 오차 수백 밀리초)만
/// `.minutes(0)`("방금 전")으로 보고, 기기(자녀 폰) 시각의 음수 경과는 절대 시각을
/// 잃지 않고 `.skewed(atMillis:)`로 그대로 넘긴다 — `StatusCard.lastSignal` 주석이
/// 이 갈래를 정한다.
enum LastSignal: Equatable {
    case never
    case minutes(Int)
    case hours(Int)
    case days(Int)
    /// 자녀 폰 시계가 부모 폰보다 앞서 있어 경과 시간을 모를 때 대신 보여줄 절대
    /// 시각(자녀 폰이 적어 보낸 UTC 밀리초, [ChildStatusDoc.lastSeenAt] 값 그대로).
    /// 코틀린 `LastSignalText.relativeText` 의 "기기 시각으로 잰 값이 음수면 상대
    /// 표현을 포기한다" 갈래와 같다 — Fix round 1 리뷰 전에는 이 갈래가 없어
    /// 음수 경과를 전부 `minutes(0)`("방금 전")로 뭉갰는데, 그러면 자녀 폰 시계가
    /// 30분 빠른 옛 기기가 2시간 전에 남긴 신호도 "방금 전"으로 보여 부모가 낡은
    /// 위치를 현재로 믿는 사고로 이어진다.
    case skewed(atMillis: Int64)
}

/// 상태 문서에서 "마지막 신호"를 읽는 자리를 한 곳에 모은다.
///
/// **읽는 쪽은 반드시 이 함수 하나만 지나가야 한다.** 안드로이드
/// `ChildStatusDoc.lastSignal()` 의 주석이 그렇게 못 박았다 — 지도 카드·(나중에
/// 생길) 관리 탭·연결 끊김 배너가 저마다 다른 "마지막 신호"를 말하면 그 자체가
/// 부모를 헷갈리게 한다. `StatusCardView` 는 이 함수만 부른다.
enum StatusCard {

    private static let minuteMillis: Int64 = 60_000
    private static let hourMillis: Int64 = 60 * minuteMillis
    private static let dayMillis: Int64 = 24 * hourMillis

    /// 마지막 신호의 **절대 시각과 그 시계의 출처**. 정본은 안드로이드
    /// `ChildStatusDoc.lastSignal()`(GuardianMainActivity.kt:505-510) — 서버 시각이 있으면
    /// 그것, 없으면 아이 폰 시계로 적은 옛 필드. `nil` 이면 쓸 만한 값이 없다.
    ///
    /// 경과(`lastSignal`)만 열어 두면 무응답 배너의 "물은 뒤에 쓰인 문서인가"
    /// (MapTimelineFragment.kt:757) 판단을 못 한다 — 그 판단은 시각 자체가 필요하다.
    /// 출처를 함께 들고 가는 이유는 아래 음수 경과 처리가 출처에 따라 완전히 갈리기
    /// 때문이다(안드로이드 `ChildSignal(atMillis, fromServerClock)`).
    static func signal(status: ChildStatusDoc) -> (atMillis: Int64, fromServerClock: Bool)? {
        if let serverAt = status.lastSeenServerAt {
            let millis = Int64(serverAt.dateValue().timeIntervalSince1970 * 1000)
            if millis > 0 { return (millis, true) }
        }
        if status.lastSeenAt > 0 { return (status.lastSeenAt, false) }
        return nil
    }

    /// `nowMillis` 는 **반드시 [FamilyRepository.serverNow] 로 잰 값**이어야 한다.
    /// 기기 시계로 빼면 부모 폰이 뒤처진 만큼 "마지막 신호 -3분 전" 같은 문구가
    /// 나온다 — 안드로이드 `ControlFragment` 주석과 같은 함정이다.
    static func lastSignal(status: ChildStatusDoc, nowMillis: Int64) -> LastSignal {
        guard let found = signal(status: status) else { return .never }
        let 경과 = nowMillis - found.atMillis
        // 음수 경과의 뜻은 시계 출처에 따라 다르다 — 코틀린 `LastSignalText.relativeText`
        // (:543-548) 와 같은 갈래. 서버 시각의 음수는 왕복 보정 오차뿐이라 "방금 전"이
        // 정직하고, 아이 폰 시각의 음수는 경과를 모른다는 뜻이라 절대 시각을 넘긴다 —
        // 상대 표현을 쓰면 같은 화면의 다른 줄과 서로를 부정해 부모가 화면을 덜 믿게 된다.
        if 경과 < 0 {
            return found.fromServerClock ? .minutes(0) : .skewed(atMillis: found.atMillis)
        }
        return elapsed(millis: 경과)
    }

    /// 0 이상의 경과를 분·시간·일로 나눈다. 정본은 `LastSignalText.elapsedText`(:551-556).
    /// 음수의 뜻과 처리는 부르는 쪽이 정한다(:550) — 여기서는 0 으로 끌어올리기만 한다.
    /// 무응답 배너(`DisconnectBanner`)도 이 한 곳을 지나간다 — 관리 탭의 마지막 신호와
    /// 배너가 같은 사실을 다른 표기로 말하지 않게(:512-516).
    static func elapsed(millis: Int64) -> LastSignal {
        let millis = max(millis, 0)
        switch millis {
        case ..<minuteMillis: return .minutes(0)
        case ..<hourMillis: return .minutes(Int(millis / minuteMillis))
        case ..<dayMillis: return .hours(Int(millis / hourMillis))
        default: return .days(Int(millis / dayMillis))
        }
    }
}

/// 하루를 머무름·이동으로 요약한 한 토막. 정본은 안드로이드
/// `core/model/Documents.kt:179-189` 의 `SegmentDoc`. 이 구조체도 읽기 전용이다.
struct SegmentDoc {
    /// "STAY" | "MOVE". 코틀린 `SegmentType` 의 `name` 그대로다 — enum 으로
    /// 좁히지 않는 이유는 옛 문서에 다른 값이 있어도(예: 앞으로 새 타입이 추가돼도)
    /// 읽기 자체는 실패하지 않게 두기 위해서다. `RouteOverlay` 가 "MOVE" 문자열만
    /// 비교해서 쓴다.
    let type: String
    let startAt: Int64
    let endAt: Int64
    let lat: Double
    let lng: Double
    let distanceMeters: Double
    let pointCount: Int
    /// 머무른 곳 이름. Task 4 가 채운다. 비어 있으면 화면이 "머무른 곳"으로 표시한다.
    let placeName: String

    init?(_ data: [String: Any]) {
        guard let type = data["type"] as? String else { return nil }
        self.type = type
        startAt = millis(data["startAt"]) ?? 0
        endAt = millis(data["endAt"]) ?? 0
        lat = double(data["lat"]) ?? 0
        lng = double(data["lng"]) ?? 0
        distanceMeters = double(data["distanceMeters"]) ?? 0
        pointCount = Int(millis(data["pointCount"]) ?? 0)
        placeName = data["placeName"] as? String ?? ""
    }
}

/// children/{childUid}/trails/{dayKey} — 하루가 문서 하나다. 정본은 안드로이드
/// `core/model/Documents.kt:148-155` 의 `TrailDoc`. 읽기 전용이다 — 쓰기는
/// 자녀 폰만 한다(`TrailRepository.kt` 주석과 같은 이유).
///
/// 실패하지 않는 이유(다른 Doc 들과 달리 `init?`이 아닌 이유): 코틀린도
/// `toObject(TrailDoc::class.java)`가 데이터 클래스의 기본값으로 없는 필드를
/// 채운다 — 필수 필드가 없다. 빈 맵을 줘도 "빈 하루"가 나오는 것이 맞는 동작이다.
struct TrailDoc {
    let dayKey: String
    let points: [TrailPoint]
    let segments: [SegmentDoc]
    /// 자녀 폰이 이 문서를 마지막으로 올린 시각(자녀 폰 시계).
    let updatedAt: Int64

    init(_ data: [String: Any]) {
        dayKey = data["dayKey"] as? String ?? ""
        points = (data["points"] as? [[String: Any]] ?? []).compactMap(TrailPoint.init)
        segments = (data["segments"] as? [[String: Any]] ?? []).compactMap(SegmentDoc.init)
        updatedAt = millis(data["updatedAt"]) ?? 0
    }
}

/// families/{familyId}/children/{childUid}/commands/{commandId}. 정본은 안드로이드
/// `core/model/Documents.kt:204` 의 `CommandDoc`·`FirestoreCommandTransport.toDoc`.
///
/// **이 구조체는 읽기 전용이다.** 이 앱(보호자)은 이 문서를 만들기만 한다 —
/// `state` 는 항상 `pending` 으로 시작해야 하고(`CommandRepository.send` 참고),
/// 그 뒤 상태를 옮기는 것은 자녀 폰(안드로이드)의 몫이라 이 구조체에 쓰기 표현은
/// 없다(그래서 `firestoreData` 가 없다 — 다른 Doc 들과 다른 점).
///
/// 상태 전이는 pending → delivered → done|failed 한 방향뿐이다(`firestore.rules`
/// 의 `commands` update 규칙). `type`·`payload` 는 자녀가 못 바꾸므로 불변이다.
struct CommandDoc {
    let id: String
    let type: String
    let payload: [String: String]
    /// "pending"|"delivered"|"done"|"failed". `CommandState` 상수와 비교해서 쓴다 —
    /// [SegmentDoc.type] 과 같은 이유로 닫힌 enum 으로 좁히지 않는다: 옛 문서에
    /// 다른 값이 있어도 읽기 자체는 실패하지 않게 둔다.
    let state: String
    let createdAt: Int64
    let deliveredAt: Int64
    let doneAt: Int64
    /// 자녀 폰이 실패 이유로 적는 코드(사람이 읽는 문장이 아니다). `childErrorText`
    /// 가 번역한다 — 정본은 안드로이드 `MapTimelineFragment.childErrorText`(:691).
    let error: String

    init(id: String, _ data: [String: Any]) {
        self.id = id
        type = data["type"] as? String ?? ""
        let rawPayload = data["payload"] as? [String: Any] ?? [:]
        // 지금 이 앱이 보내는 명령([CommandType.locateNow])은 페이로드가 늘 비어
        // 있다 — 값이 생기는 순간은 이후 Task(메시지·알람)의 몫이라, 코틀린처럼
        // 문자열로 뭉개는 정도의 변환이면 충분하다.
        var payload: [String: String] = [:]
        for (key, value) in rawPayload { payload[key] = "\(value)" }
        self.payload = payload
        state = data["state"] as? String ?? ""
        createdAt = millis(data["createdAt"]) ?? 0
        deliveredAt = millis(data["deliveredAt"]) ?? 0
        doneAt = millis(data["doneAt"]) ?? 0
        error = data["error"] as? String ?? ""
    }
}

/// [CommandDoc.type]·[CommandDoc.error] 값들. 정본은 안드로이드 `CommandType`
/// 오브젝트 — 이 앱(보호자)은 지금 이 Task(지금 위치 확인)가 쓰는 값만 옮긴다.
/// 닫힌 enum 이 아니라 문자열 상수 모음인 이유도 안드로이드와 같다: 새 명령이
/// 계속 늘어나는 자리라, 아직 옮기지 않은 값(다른 Task 가 그 기능을 옮길 때
/// 추가한다)까지 이 타입이 미리 알 필요는 없다.
enum CommandType {
    static let locateNow = "locate_now"
    /// [locateNow] 가 위치를 못 잡았을 때 자녀 폰이 [CommandDoc.error] 에 적는 코드.
    static let errorNoFix = "locate_no_fix"
    /// Task 7(실시간 보기). 정본은 안드로이드 `CommandType.START_LIVE_TRACKING`/
    /// `STOP_LIVE_TRACKING`/`PAYLOAD_DURATION_SECONDS`/`PAYLOAD_SESSION_ID`
    /// (`core/model/Documents.kt:238-241`) — 값이 하나라도 다르면 자녀 폰이 이
    /// 명령을 못 알아본다.
    static let startLiveTracking = "start_live_tracking"
    static let stopLiveTracking = "stop_live_tracking"
    static let payloadDurationSeconds = "durationSeconds"
    static let payloadSessionId = "sessionId"

    /// 관리 탭이 보내는 명령(4단계). 정본은 안드로이드 `CommandType`(Documents.kt:215-339) —
    /// 값이 하나라도 다르면 자녀 폰(`child/CommandHandler`)이 이 명령을 못 알아본다.
    static let setRinger = "set_ringer"
    /// 자녀 폰의 실제 벨소리 모드만 읽어 상태 문서에 올린다. 소리는 안 낸다(:217-218).
    static let queryRinger = "query_ringer"
    static let findPhone = "find_phone"
    static let stopFind = "stop_find"
    /// 다른 명령과 달리 `delivered` 가 "전해졌지만 아직 안 읽음"이라는 **최종 상태**일 수
    /// 있다 — `done` 은 아이가 '확인했어요'를 눌렀다는 뜻이다(:247-260).
    static let message = "message"
    static let payloadText = "text"
    static let errorNotificationOff = "message_notification_off"
    /// 하루 안의 분만 보낸다. 오늘인지 내일인지는 자녀 폰이 정한다(:282-299).
    static let setAlarm = "set_alarm"
    static let cancelAlarm = "cancel_alarm"
    static let payloadAtMinuteOfDay = "atMinuteOfDay"
    static let payloadLabel = "label"
    static let errorAlarmExactDenied = "alarm_exact_denied"
}

/// [CommandDoc.state] 값들. 정본은 안드로이드 `CommandState` 오브젝트.
enum CommandState {
    static let pending = "pending"
    static let delivered = "delivered"
    static let done = "done"
    static let failed = "failed"
}

/// `set_ringer` 의 모드 값과 페이로드 키. 정본은 `ControlFragment.kt:1119-1128` — 안드로이드는
/// guardian 이 child 를 import 하지 않아 이 값을 두 곳에 적는다(`child/RingerStateStore.kt:21-27`).
/// 바꿀 일이 생기면 세 곳을 함께 고친다(README "함께 고쳐야 하는 짝").
enum RingerMode {
    static let normal = "normal"
    static let vibrate = "vibrate"
    static let silent = "silent"
    static let payloadKey = "mode"
    /// 자녀 폰이 소리 모드 변경을 거부당했을 때 적는 코드.
    static let errorDenied = "ringer_denied"

    static func isKnown(_ mode: String) -> Bool { mode == normal || mode == vibrate || mode == silent }
}

/// 자녀 폰이 올리는 방해 금지 상태. 정본은 `child/RingerStateStore.kt:9-19`. 방해 금지가
/// 켜지면 안드로이드가 벨소리 모드를 무조건 '무음'으로 보고하므로 둘을 함께 봐야 한다.
enum Dnd {
    /// 꺼짐도 모름도 아니면 켜져 있는 것이다.
    static func isOn(_ value: String?) -> Bool { value == "priority" || value == "alarms" || value == "none" }
}

/// `ChildStatusDoc.network` 값. 정본은 `child/NetworkState.kt:23-27`. 빈 값은 "모른다".
enum NetworkKind {
    static let wifi = "wifi"
    static let cell = "cell"
    static let none = "none"
}

/// children/{childUid}/settings/ringer. 정본은 `Documents.kt:466-482`. 보호자 앱은 이 문서를
/// **통째로 쓰지 않는다** — 필드 하나씩 병합한다(`ScheduleRepository.setRingerLock` 주석).
/// 그래서 `firestoreData` 가 없다.
struct RingerSettingsDoc {
    var lockEnabled = false
    var defaultMode = ""
    var holidayOff = false

    init(_ data: [String: Any]) {
        lockEnabled = data["lockEnabled"] as? Bool ?? false
        defaultMode = data["defaultMode"] as? String ?? ""
        holidayOff = data["holidayOff"] as? Bool ?? false
    }
}
