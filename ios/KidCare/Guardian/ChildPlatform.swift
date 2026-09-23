import Foundation

/// 아이 폰이 어떤 폰인가. 설계서 §10.2 가 "화면마다 `platform == "ios"` 를 직접 비교하지
/// 않는다 — 비교가 흩어지면 한 군데를 빠뜨린다"라고 정한 그 한 곳이다.
///
/// **`"ios"` 라는 글자는 이 저장소에 두 군데뿐이다**: 아이가 쓰는 `Documents.swift:252` 와
/// 보호자가 읽는 여기. 화면은 이 enum 만 본다.
enum ChildPlatform: Sendable {
    /// 상태 문서가 있고 `platform` 이 `"ios"` 가 **아닌** 모든 경우. 빈 값이 여기다.
    case android
    case iOS
    /// 상태 문서를 아직 못 읽었거나 아예 없다. **아이 폰이 한 번도 위치를 안 올린 가족이다.**
    case unknown

    /// 아이 상태 문서의 `platform` 한 글자로 판단한다.
    ///
    /// **빈 값·모르는 값이 전부 `.android` 인 것이 이 함수의 핵심이다**(설계서 §10.1).
    /// 지금 서버에 있는 모든 아이 문서에 이 필드가 없고, 모르는 아이의 기능을 조용히
    /// 없애면 안 된다. 반대 방향(아이폰인데 아직 안 잠김)은 아이 폰이 페어링 뒤 첫
    /// 좌표에서 업로드를 한 번 강제해 닫는다.
    static func of(platform: String) -> ChildPlatform {
        platform == "ios" ? .iOS : .android
    }

    /// 문서가 없으면 `.unknown`. 있으면 [of(platform:)].
    static func of(status: ChildStatusDoc?) -> ChildPlatform {
        guard let status else { return .unknown }
        return of(platform: status.platform)
    }

    /// 아이 폰이 `commands/` 를 구독하나. **`.iOS` 만 false** 다(설계서 §1·§10.2).
    /// 소리 모드·소리 상태 조회·핸드폰 찾기·메시지·알람·`locate_now`·실시간 보기·
    /// `sync_rules` 가 전부 이 한 줄에 달려 있다.
    var 명령을_받을_수_있나: Bool { self != .iOS }

    /// "아이폰이라 못 해요"를 화면에 적을까. **`.unknown` 에서는 안 적는다** — 모르는
    /// 아이에게 아이폰이라고 말하는 것은 버튼을 끄는 것보다 더 나쁜 거짓말이다.
    var 못_한다고_말할까: Bool { self == .iOS }
}
