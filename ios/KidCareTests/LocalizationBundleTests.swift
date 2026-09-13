import Foundation
import Testing
@testable import KidCare

/// 빌드된 앱 번들이 정말 14개 언어를 싣는지, 테스트가 한국어로 도는지를 **결과물을 열어** 본다.
/// 카탈로그 파일이 맞아도 빌드가 언어를 빠뜨리면 그 언어 기기에서만 틀리고, 다른 어떤 테스트도 못 잡는다.
struct LocalizationBundleTests {

    private func json(_ relative: String) throws -> [String: Any] {
        let root = try #require(TestRepo.root())
        let data = try Data(contentsOf: root.appendingPathComponent(relative))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("테스트는 한국어로 돈다 — 한국어 기대값을 적은 테스트 전부의 전제(project.yml 스킴 test language: ko)")
    func 테스트_언어는_한국어() {
        #expect(Bundle.main.preferredLocalizations.first == "ko")
        #expect(String(localized: "tab_alert") == "알림")
    }

    @Test("번들에 14개 언어 lproj 가 모두 있고, 각자 자기 원본 값을 낸다")
    func 열네_언어가_실린다() throws {
        for (file, tag) in LocalizableCatalogTests.언어_태그 {
            let path = try #require(Bundle.main.path(forResource: tag, ofType: "lproj"), "\(tag).lproj 가 번들에 없다")
            let bundle = try #require(Bundle(path: path))
            let expected = try #require(try json("i18n/\(file).json")["tab_alert"] as? String)
            #expect(bundle.localizedString(forKey: "tab_alert", value: "(없음)", table: nil) == expected, "\(tag)")
        }
    }

    @Test("빈 칸은 개발 언어(한국어)가 아니라 영어로 나온다 — 안드로이드 values/ 와 같은 물러남(판정 기록 3)")
    func 빈_칸은_영어로_나온다() throws {
        let gaps = try json("tools/i18n-untranslated.json")
        guard let key = (gaps["de"] as? [String])?.first else { return }   // 모두 번역되면 볼 칸이 없다
        let en = try #require(try json("i18n/en.json")[key] as? String)
        let path = try #require(Bundle.main.path(forResource: "de", ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        #expect(bundle.localizedString(forKey: key, value: "(없음)", table: nil) == LocalizableCatalogTests.카탈로그_값(en))
    }
}
