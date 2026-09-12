import Testing
import Foundation

/// `i18n/*.json` 14개 언어 파일이 같은 문구 키 집합을 공유하는지 본다.
///
/// **지금은 실패하는 것이 맞다.** Phase 1 이 키 7개를, Phase 2 가 다시 늘려 총 18개를
/// `ko.json`/`en.json` 에만 추가했고 나머지 12개 언어에는 아무도 넣지 않았다 — 어느
/// 빌드도 이 키들을 아직 참조하지 않아 아무도 알아채지 못했다. Phase 6 이 이 카탈로그를
/// 실제로 소비하기 시작하면 빠진 언어의 기기에서 문구가 안 나오거나 크래시가 난다.
///
/// 이 테스트는 번역을 지어내지 않는다(안전 관련 문구를 기계 번역으로 흘려보내는 것은
/// 이 작업의 몫이 아니다) — 대신 `withKnownIssue` 로 감싸 **"알려진 문제"로 기록**하면서
/// 스위트 전체는 초록으로 유지한다. 매번 실제로 비교를 돌리기 때문에(스킵이 아니다),
/// Phase 6 이 번역을 다 채워 이 비교가 우연히 통과하는 순간 `withKnownIssue` 자체가
/// "예상한 실패가 안 일어났다"며 실패로 바뀐다 — 그게 이 테스트를 다시 켜서(이 감싸는
/// 코드를 지워서) 정식 검사로 승격할 신호다. `tools/check-i18n-keys.swift` 가 같은
/// 비교를 커맨드라인에서 돌려 Phase 6 착수 시점에 체크리스트로 쓸 수 있게 한다.
struct I18nKeyParityTests {

    /// 이 테스트 파일 자신의 컴파일 시점 경로(`#filePath`)에서 위로 올라가며
    /// `i18n/`과 `ios/`를 함께 가진 저장소 루트를 찾는다. 안드로이드
    /// `GoldenFileWriterTest.repoRoot()` 와 같은 발상이다 — 다만 JVM 의 `user.dir`
    /// 대신 컴파일된 소스 경로를 쓴다(시뮬레이터 테스트 프로세스의 현재 작업 디렉터리는
    /// 신뢰할 수 없어서다).
    private func repoRoot() -> URL? {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while true {
            let i18n = dir.appendingPathComponent("i18n", isDirectory: true)
            let ios = dir.appendingPathComponent("ios", isDirectory: true)
            if FileManager.default.fileExists(atPath: i18n.path), FileManager.default.fileExists(atPath: ios.path) {
                return dir
            }
            let parent = dir.deletingLastPathComponent()
            if parent == dir { return nil }
            dir = parent
        }
    }

    private func keys(of url: URL) throws -> Set<String> {
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TestFailure("\(url.lastPathComponent) 이 JSON 객체({...})가 아니다")
        }
        return Set(object.keys)
    }

    private struct TestFailure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    @Test("14개 언어의 i18n/*.json 이 같은 문구 키 집합을 공유한다 (Phase 6 이 닫을 때까지는 알려진 문제)")
    func 문구_키가_14개_언어_전부에_있다() throws {
        let root = try #require(repoRoot(), "저장소 루트를 못 찾았다 (i18n/ 와 ios/ 가 함께 있는 폴더가 없다)")
        let i18nDir = root.appendingPathComponent("i18n", isDirectory: true)
        let entries = try FileManager.default.contentsOfDirectory(at: i18nDir, includingPropertiesForKeys: nil)
        let jsonFiles = entries.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        try #require(jsonFiles.count >= 14, "i18n/*.json 이 14개보다 적다 — 언어가 통째로 빠졌다")

        var keysByFile: [String: Set<String>] = [:]
        for file in jsonFiles {
            keysByFile[file.lastPathComponent] = try keys(of: file)
        }
        let unionKeys = keysByFile.values.reduce(into: Set<String>()) { $0.formUnion($1) }

        // Phase 6 이 번역을 채워 이 비교가 통과하게 되면 withKnownIssue 가 "예상한
        // 실패가 안 일어났다"며 스스로 실패한다 — 그 실패가 이 파일을 정식 검사로
        // 승격하라는 신호다(Korean: 이 위 문서 참고).
        withKnownIssue("""
        Phase 2 가 새 문구 키 18개를 ko/en 에만 추가했다 — 나머지 12개 언어 번역은 \
        Phase 6 이 한다. 번역을 지어내지 않는다.
        """) {
            for file in jsonFiles {
                let name = file.lastPathComponent
                let missing = unionKeys.subtracting(keysByFile[name] ?? []).sorted()
                #expect(missing.isEmpty, "\(name) 에 \(missing.count)개 키가 없다: \(missing.joined(separator: ", "))")
            }
        }
    }
}
