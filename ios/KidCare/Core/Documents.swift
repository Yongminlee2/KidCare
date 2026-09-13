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
