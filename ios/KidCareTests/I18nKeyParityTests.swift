import Foundation
import Testing

/// `i18n/*.json` 14벌의 키 계약(6단계 계획서 판정 기록 3).
///
/// 5단계까지는 Swift Testing 의 알려진 문제(known issue) 감싸기로 "12개 언어에 21키가 없다"를 알려진 문제로만 기록했다. 번역은 지어낼 수
/// 없으므로(안전 문구를 기계 번역으로 흘려보내지 않는다) 그 문제를 "채워서" 닫는 길은 없다. 대신 빈 칸을
/// `tools/i18n-untranslated.json` 에 적어 두고 **정확히** 같은지 본다 — 빈 칸이 새로 생겨도, 누가 번역을
/// 채웠는데 목록을 안 줄여도 빨개진다. 빈 칸이 기기에서 어떻게 보이는지는 `LocalizationBundleTests` 가 본다.
struct I18nKeyParityTests {

    /// 빈 칸이 물러날 곳이라 빠지면 안 되는 두 언어. en 은 안드로이드 `values/` 의 언어다(strings.xml:2).
    static let 전부_있어야_하는_언어: Set<String> = ["ko", "en"]
    static let 언어: Set<String> = ["ko", "en", "ja", "zh", "zh_Hant", "es", "pt", "de", "fr", "it", "ru", "id", "vi", "th"]

    private func json(_ relative: String) throws -> [String: Any] {
        let root = try #require(TestRepo.root(), "저장소 루트를 못 찾았다 (i18n/ 와 ios/ 가 함께 있는 폴더가 없다)")
        let data = try Data(contentsOf: root.appendingPathComponent(relative))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any], "\(relative) 이 JSON 객체가 아니다")
    }

    private func keys(_ lang: String) throws -> Set<String> {
        Set(try json("i18n/\(lang).json").keys)
    }

    @Test("i18n/ 에는 정확히 14개 언어 파일이 있다 — 하나가 통째로 빠지면 그 언어 칸 전체가 조용히 영어가 된다")
    func 언어_파일은_열넷() throws {
        let root = try #require(TestRepo.root())
        let names = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("i18n").path)
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
        #expect(Set(names) == Self.언어)
    }

    @Test("ko 와 en 은 모든 키를 가진다")
    func 한국어와_영어는_빈_칸이_없다() throws {
        var union = Set<String>()
        for lang in Self.언어 { union.formUnion(try keys(lang)) }
        for lang in Self.전부_있어야_하는_언어.sorted() {
            let missing = union.subtracting(try keys(lang)).sorted()
            #expect(missing.isEmpty, "\(lang).json 에 없는 키: \(missing.joined(separator: ", "))")
        }
    }

    @Test("나머지 12개 언어의 빈 칸은 tools/i18n-untranslated.json 과 정확히 같고, 원본에 없는 키는 없다")
    func 빈_칸은_기록과_같다() throws {
        let ko = try keys("ko")
        let recorded = try json("tools/i18n-untranslated.json")
        let others = Self.언어.subtracting(Self.전부_있어야_하는_언어)
        #expect(Set(recorded.keys) == others, "기록의 언어 목록이 12개 언어와 다르다")
        for lang in others.sorted() {
            let have = try keys(lang)
            #expect(have.subtracting(ko).isEmpty, "\(lang).json 에만 있는 키: \(have.subtracting(ko).sorted())")
            let actual = ko.subtracting(have)
            let expected = Set(try #require(recorded[lang] as? [String], "\(lang) 기록이 배열이 아니다"))
            #expect(
                actual == expected,
                "\(lang): 새 빈 칸 \(actual.subtracting(expected).sorted()) / 채웠는데 기록에 남은 칸 \(expected.subtracting(actual).sorted()) — 의도한 변화면 python3 tools/ios-strings.py --write-gaps"
            )
        }
    }
}
