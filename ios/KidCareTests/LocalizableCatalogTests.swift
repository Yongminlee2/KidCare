import Foundation
import Testing

/// `Localizable.xcstrings` 는 `tools/ios-strings.py` 가 `i18n/*.json` 14벌에서 생성한다(6단계).
/// 생성물이 원본과 어긋나지 않았는지, 코드가 부르는 키가 빠지지 않았는지를 기계로 본다 — 빠진 키는
/// 화면에 키 이름 그대로("control_find_hint") 뜨는데 빌드도 다른 테스트도 그걸 못 잡는다.
struct LocalizableCatalogTests {

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

    /// (i18n 파일 이름, 카탈로그 언어 태그). 태그는 안드로이드 `AppLanguage.kt:23-36` 의 tag 와 같다 —
    /// 인도네시아어는 파일도 태그도 `id` 다(`values-in` 은 안드로이드 리소스 폴더 이름일 뿐이다).
    static let 언어_태그: [(file: String, tag: String)] = [
        ("ko", "ko"), ("en", "en"), ("ja", "ja"), ("zh", "zh-Hans"), ("zh_Hant", "zh-Hant"),
        ("es", "es"), ("pt", "pt"), ("de", "de"), ("fr", "fr"), ("it", "it"),
        ("ru", "ru"), ("id", "id"), ("vi", "vi"), ("th", "th"),
    ]

    private func 항목들() throws -> [String: [String: Any]] {
        try #require(try json("ios/KidCare/Localizable.xcstrings")["strings"] as? [String: [String: Any]])
    }

    private func 칸(_ entry: [String: Any], _ tag: String) -> (state: String?, value: String?) {
        let unit = ((entry["localizations"] as? [String: Any])?[tag] as? [String: Any])?["stringUnit"] as? [String: Any]
        return (unit?["state"] as? String, unit?["value"] as? String)
    }

    @Test("원본의 모든 키가 14개 언어 칸을 가진다 — 번역은 translated, 빈 칸은 en 값의 needs_review(판정 기록 3)")
    func 카탈로그는_원본에서_나온다() throws {
        let strings = try 항목들()
        let ko = try json("i18n/ko.json")
        let en = try json("i18n/en.json")
        #expect(Set(strings.keys) == Set(ko.keys), "카탈로그 키가 원본과 다르다 — python3 tools/ios-strings.py")
        for (file, tag) in Self.언어_태그 {
            let source = try json("i18n/\(file).json")
            for key in ko.keys.sorted() {
                let entry = try #require(strings[key], "\(key) 가 카탈로그에 없다")
                let unit = 칸(entry, tag)
                if let value = source[key] as? String {
                    #expect(unit.state == "translated", "\(tag) \(key)")
                    #expect(unit.value == Self.카탈로그_값(value), "\(tag) \(key) 값이 원본과 다르다")
                } else {
                    let fallback = try #require(en[key] as? String)
                    #expect(unit.state == "needs_review", "\(tag) \(key) 빈 칸이 표시되지 않았다")
                    #expect(unit.value == Self.카탈로그_값(fallback), "\(tag) \(key) 빈 칸이 영어로 물러나지 않았다")
                }
            }
        }
    }

    @Test("공유 원본 i18n/*.json 14벌에는 iOS 서식 %@ 가 없다")
    func 원본에는_iOS_서식이_없다() throws {
        for (file, _) in Self.언어_태그 {
            for (key, value) in try json("i18n/\(file).json") {
                #expect(!(value as? String ?? "").contains("%@"), "i18n/\(file).json 의 \(key) 에 %@ 가 있다")
            }
        }
    }
}
