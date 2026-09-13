import Foundation
import Testing

/// `Localizable.xcstrings` 는 6단계 전까지 `i18n/ko.json` 에서 손(계획서 공통 절차 A 의
/// 명령)으로 옮긴다. 옮긴 값이 원본과 어긋나지 않았는지, 코드가 부르는 원본 키가
/// 카탈로그에서 빠지지 않았는지를 여기서 기계로 본다 — 빠진 키는 화면에 키 이름
/// 그대로("control_find_hint") 뜨는데 빌드도 다른 테스트도 그걸 못 잡는다.
struct LocalizableCatalogTests {

    /// 1단계에서 화면에 맞춰 손으로 고친 값이 남은 키. `PairingUITests` 가 이 문구로
    /// 버튼을 찾아서 지금 고치면 실기기 자동화가 깨진다. 6단계가 원본에서 생성할 때
    /// 정리한다 — **여기에 새 키를 더하지 않는다.**
    static let 알려진_어긋남: Set<String> = ["guardian_start_join_family", "map_no_child", "role_guardian"]

    /// 안드로이드 서식 → iOS 서식. `%1$s`→`%1$@`, 숫자 서식(`%1$d`·`%1$02d`·`%1$.1f`)은
    /// 그대로, 서식이 아닌 `%` 는 `%%`. 소수 서식은 계획서 공통 절차 A 의 명령이 빠뜨린
    /// 갈래다 — 기존 `%1$.1fkm` 항목이 이미 그대로 옮겨져 있다.
    static func 카탈로그_값(_ source: String) -> String {
        let 서식 = #/%(\d+\$)?(\d+)?(\.\d+)?([sdf])/#
        var result = ""
        var rest = source[...]
        while let i = rest.firstIndex(of: "%") {
            result += rest[..<i]
            let tail = rest[i...]
            if let m = tail.prefixMatch(of: 서식) {
                let position = m.output.1.map(String.init) ?? ""
                let width = m.output.2.map(String.init) ?? ""
                let precision = m.output.3.map(String.init) ?? ""
                let conversion = m.output.4 == "s" ? "@" : String(m.output.4)
                result += "%" + position + width + precision + conversion
                rest = tail[m.range.upperBound...]
            } else if tail.hasPrefix("%%") {
                result += "%%"
                rest = tail.dropFirst(2)
            } else {
                result += "%%"
                rest = tail.dropFirst()
            }
        }
        return result + rest
    }

    private func json(_ relative: String) throws -> [String: Any] {
        let root = try #require(TestRepo.root(), "저장소 루트를 못 찾았다")
        let data = try Data(contentsOf: root.appendingPathComponent(relative))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func 카탈로그() throws -> [String: String] {
        let strings = try #require(try json("ios/KidCare/Localizable.xcstrings")["strings"] as? [String: [String: Any]])
        var out: [String: String] = [:]
        for (key, entry) in strings {
            let ko = (entry["localizations"] as? [String: Any])?["ko"] as? [String: Any]
            out[key] = (ko?["stringUnit"] as? [String: Any])?["value"] as? String
        }
        return out
    }

    @Test("서식 변환 규칙은 기존 카탈로그가 쓴 규칙과 같다")
    func 서식_변환() {
        #expect(Self.카탈로그_값("마지막 신호 %1$s") == "마지막 신호 %1$@")
        #expect(Self.카탈로그_값("%1$02d:%2$02d") == "%1$02d:%2$02d")
        #expect(Self.카탈로그_값("배터리 %1$d%\n%2$s 기준") == "배터리 %1$d%%\n%2$@ 기준")
        #expect(Self.카탈로그_값("%1$s '%2$s'") == "%1$@ '%2$@'")
        #expect(Self.카탈로그_값("%1$.1fkm") == "%1$.1fkm")
    }

    @Test("카탈로그의 모든 한국어 값은 i18n/ko.json 에서 변환 규칙대로 나왔다")
    func 카탈로그는_원본에서_나온다() throws {
        let ko = try json("i18n/ko.json")
        for (key, value) in try 카탈로그() {
            let source = try #require(ko[key] as? String, "\(key) 가 i18n/ko.json 에 없다 — 카탈로그에만 있는 키는 6단계 생성 때 사라진다")
            if Self.알려진_어긋남.contains(key) { continue }
            #expect(value == Self.카탈로그_값(source), "\(key) 값이 원본과 다르다")
        }
    }

    @Test("앱 코드가 부르는 원본 키는 전부 카탈로그에 있다")
    func 코드가_부르는_키는_카탈로그에_있다() throws {
        let root = try #require(TestRepo.root())
        let ko = try json("i18n/ko.json")
        let catalog = try 카탈로그()
        let sources = try #require(FileManager.default.enumerator(at: root.appendingPathComponent("ios/KidCare"), includingPropertiesForKeys: nil))
        var missing: [String] = []
        for case let url as URL in sources where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in text.matches(of: #/"([a-z][a-z0-9_]+)"/#) {
                let key = String(match.output.1)
                if ko[key] != nil && catalog[key] == nil { missing.append("\(url.lastPathComponent): \(key)") }
            }
        }
        #expect(missing.isEmpty, "카탈로그에 없는 키: \(missing.joined(separator: ", "))")
    }

    @Test("공유 원본 i18n/*.json 에는 iOS 서식 %@ 가 없다")
    func 원본에는_iOS_서식이_없다() throws {
        for file in ["i18n/ko.json", "i18n/en.json"] {
            for (key, value) in try json(file) {
                #expect(!(value as? String ?? "").contains("@"), "\(file) 의 \(key) 에 %@ 류 서식이 있다")
            }
        }
    }
}
