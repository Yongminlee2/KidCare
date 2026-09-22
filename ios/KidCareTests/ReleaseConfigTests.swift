import Foundation
import Testing
@testable import KidCare

/// 출시 빌드가 지켜야 할 성질을 **빌드된 앱 번들을 열어** 본다(7단계 계획서 판정 기록 2·3·4·5·13·15).
/// 설정 파일이 맞아도 빌드가 매니페스트를 빠뜨리거나 권한 문구가 끼어들면, 올린 뒤 메일로 알게 된다.
/// 테스트는 Debug 로 돌지만 여기서 보는 값(매니페스트, Info.plist, lproj)은 구성마다 다르지 않다.
struct ReleaseConfigTests {

    /// 판정 기록 2 의 여섯 개. `docs/app-store/privacy-label.md` 의 "연결된 데이터" 표와 같은 목록이다.
    static let 신고한_수집_항목: Set<String> = [
        "NSPrivacyCollectedDataTypePreciseLocation",
        "NSPrivacyCollectedDataTypeName",
        "NSPrivacyCollectedDataTypeUserID",
        "NSPrivacyCollectedDataTypeEmailsOrTextMessages",
        "NSPrivacyCollectedDataTypeOtherUserContent",
        "NSPrivacyCollectedDataTypeOtherDataTypes",
    ]

    /// 이유가 필요한 API 를 앱 소스에서 찾는 글자들. 애플 목록의 다섯 갈래다.
    /// 주석에 이 단어를 쓰면 걸린다 — 그때는 사람이 보고 판정한다(넓게 걸리는 쪽이 안전하다).
    static let 이유_필요_API: [(category: String, pattern: String)] = [
        ("NSPrivacyAccessedAPICategoryFileTimestamp", #"creationDate|modificationDate|ModificationDate|attributesOfItem|getattrlist|\bf?stat\("#),
        ("NSPrivacyAccessedAPICategorySystemBootTime", #"systemUptime|mach_absolute_time"#),
        ("NSPrivacyAccessedAPICategoryDiskSpace", #"volumeAvailableCapacity|systemFreeSize|systemSize|statfs"#),
        ("NSPrivacyAccessedAPICategoryActiveKeyboards", #"activeInputModes"#),
        ("NSPrivacyAccessedAPICategoryUserDefaults", #"UserDefaults|@AppStorage"#),
    ]

    private func 매니페스트() throws -> [String: Any] {
        let url = try #require(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "PrivacyInfo.xcprivacy 가 앱 번들 최상위에 없다 — project.yml 의 buildPhase: resources 를 본다(판정 기록 16)"
        )
        let data = try Data(contentsOf: url)
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test("추적하지 않는다 — 추적 도메인도 없다(판정 기록 2)")
    func 추적_없음() throws {
        let m = try 매니페스트()
        #expect(m["NSPrivacyTracking"] as? Bool == false)
        #expect((m["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
    }

    @Test("수집 항목은 판정 기록 2 의 여섯 개 — 모두 연결됨, 추적 아님, 앱 기능")
    func 수집_항목() throws {
        let items = try #require(try 매니페스트()["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        #expect(items.count == Self.신고한_수집_항목.count)
        #expect(Set(items.compactMap { $0["NSPrivacyCollectedDataType"] as? String }) == Self.신고한_수집_항목)
        for item in items {
            let name = item["NSPrivacyCollectedDataType"] as? String ?? "?"
            #expect(item["NSPrivacyCollectedDataTypeLinked"] as? Bool == true, "\(name)")
            #expect(item["NSPrivacyCollectedDataTypeTracking"] as? Bool == false, "\(name)")
            #expect(item["NSPrivacyCollectedDataTypePurposes"] as? [String] == ["NSPrivacyCollectedDataTypePurposeAppFunctionality"], "\(name)")
        }
    }

    @Test("앱 코드가 부르는 이유 필요 API 는 모두 신고했고, 안 부르는 것은 신고하지 않았다 — UserDefaults 는 CA92.1")
    func 이유_필요_API() throws {
        let root = try #require(TestRepo.root())
        let app = root.appendingPathComponent("ios/KidCare")
        var source = ""
        let files = try #require(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
        for case let url as URL in files where url.pathExtension == "swift" {
            source += try String(contentsOf: url, encoding: .utf8) + "\n"
        }
        let used = Set(Self.이유_필요_API
            .filter { source.range(of: $0.pattern, options: .regularExpression) != nil }
            .map(\.category))

        let declared = try #require(try 매니페스트()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        #expect(Set(declared.compactMap { $0["NSPrivacyAccessedAPIType"] as? String }) == used,
                "코드에서 찾은 갈래 \(used.sorted()) 와 매니페스트가 다르다")
        let userDefaults = declared.first { $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults" }
        #expect(userDefaults?["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
    }

    @Test("출시 Info.plist — 수출 규정, 1.0 (1), 아이폰 세로 전용, 위치 문구 둘·배경 모드 location 하나(7단계 판정 기록 3·4·5·15, 아이 1단계 판정 기록 12)")
    func 출시_Info() throws {
        let info = try #require(Bundle.main.infoDictionary)
        #expect(info["ITSAppUsesNonExemptEncryption"] as? Bool == false)
        #expect(info["CFBundleShortVersionString"] as? String == "1.0")
        #expect(info["CFBundleVersion"] as? String == "1")
        #expect(info["LSRequiresIPhoneOS"] as? Bool == true)
        #expect(info["UIDeviceFamily"] as? [Int] == [1])
        #expect(info["UISupportedInterfaceOrientations"] as? [String] == ["UIInterfaceOrientationPortrait"])
        // 7단계까지 이 앱은 권한을 하나도 요청하지 않았다("권한 0개"가 자랑이었다 —
        // `2026-09-12-kidcare-ios-design.md` §1). 아이 역할이 그 성질을 **일부러** 깬다:
        // 같은 바이너리가 백그라운드 위치를 요구하게 되므로 심사에서 가이드라인 2.5.4 를
        // 정면으로 만난다(아이 설계서 §15-7). 그래서 단언을 지우지 않고 **뒤집는다** —
        // 셋째 문구나 둘째 배경 모드가 생기면 그 자리에서 빨개진다.
        #expect(
            info.keys.filter { $0.hasSuffix("UsageDescription") }.sorted()
                == ["NSLocationAlwaysAndWhenInUseUsageDescription", "NSLocationWhenInUseUsageDescription"],
            "권한 문구가 위치 둘 말고 더 생겼다 — 늘릴 때는 심사 근거를 먼저 적는다"
        )
        #expect(info["UIBackgroundModes"] as? [String] == ["location"],
                "배경 모드는 location 하나여야 한다 — 가이드라인 2.5.4 는 실제로 쓰는 것만 허용한다")
        #expect(info["KidCarePrivacyPolicyURL"] is String, "Task 2 의 처리방침 줄이 읽는 키")
    }

    @Test("홈 화면 이름은 i18n app_name 그대로 14개 언어(판정 기록 13)")
    func 앱_이름() throws {
        let root = try #require(TestRepo.root())
        for (file, tag) in LocalizableCatalogTests.언어_태그 {
            let data = try Data(contentsOf: root.appendingPathComponent("i18n/\(file).json"))
            let src = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let expected = try #require(src["app_name"] as? String, "\(file).json 에 app_name 이 없다")
            let path = try #require(Bundle.main.path(forResource: tag, ofType: "lproj"), "\(tag).lproj")
            let bundle = try #require(Bundle(path: path))
            #expect(bundle.localizedString(forKey: "CFBundleDisplayName", value: "(없음)", table: "InfoPlist") == expected, "\(tag)")
        }
    }
}
