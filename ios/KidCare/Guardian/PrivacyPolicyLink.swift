import Foundation

/// 개인정보 처리방침 주소(가이드라인 5.1.1(i) — 앱 안에서도 닿아야 한다). 값은 `project.yml` 의 Info.plist 속성
/// `KidCarePrivacyPolicyURL` 에서 온다. 주인이 게시하기 전에는 비어 있고, 그동안 메뉴에 줄이 뜨지 않는다(7단계 판정 기록 9).
/// 주소를 지어내지 않는다. "준비 중" 줄을 두지 않는 이유: 누를 수 없는 줄은 심사에서 "링크가 동작하지 않는다"로 읽힌다.
enum PrivacyPolicyLink {
    static let infoKey = "KidCarePrivacyPolicyURL"

    static func url(info: [String: Any]? = Bundle.main.infoDictionary) -> URL? {
        guard let text = info?[infoKey] as? String, text.hasPrefix("https://"),
              let url = URL(string: text), let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}
