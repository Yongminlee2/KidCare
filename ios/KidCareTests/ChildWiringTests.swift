import Foundation
import Testing
@testable import KidCare

/// **배선을 소스로 본다.**
///
/// `ChildSession` 은 진짜 `CLLocationManager` 와 Firestore 를 건드리므로 테스트 프로세스에서
/// 통째로 띄울 수 없다(`ChildSessionTests` 머리 주석, 통합 검토 M3 이 그 문을 `start` 까지
/// 내렸다). 그래서 **누가 무엇을 부르는가**는 어떤 단위 테스트에도 안 잡힌다 — 통합 검토 I2 가
/// 정확히 그 구멍이다: 시작하는 두 줄을 각각 지워도 734개가 전부 초록이었다.
///
/// 이 저장소는 이미 같은 방법을 쓴다 — `ReleaseConfigTests` 가 앱 번들을, `LocalizableCatalogTests`
/// 가 소스를 열어 읽는다. 값싸고, 지우면 빨개지고, 무엇을 지키는지가 이름에 적힌다.
///
/// **줄 주석은 걷어내고 본다.** 주석에 적힌 이름이 배선을 대신하면 안 된다 — 주석 처리된
/// 호출은 도는 코드가 아니고, 이 파일들의 주석에는 여기서 찾는 이름이 실제로 나온다.
@MainActor
struct ChildWiringTests {

    private func 소스(_ 상대경로: String) throws -> String {
        let root = try #require(TestRepo.root(), "저장소 루트를 못 찾았다 (i18n/ 와 ios/ 가 함께 있는 폴더가 없다)")
        let text = try String(contentsOf: root.appendingPathComponent(상대경로), encoding: .utf8)
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                guard let 주석 = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<주석.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// `선언 ... { ... }` 한 덩어리. 닫는 중괄호는 들여쓰기(4칸)로 찾는다 — 이 파일들의
    /// 함수는 전부 타입 안의 메서드라 자기 닫는 괄호만 그 자리에 온다.
    private func 함수본문(_ 소스글: String, _ 선언: String) throws -> String {
        let 패턴 = NSRegularExpression.escapedPattern(for: 선언) + "[\\s\\S]*?\\n    \\}"
        let range = try #require(
            소스글.range(of: 패턴, options: .regularExpression),
            "\(선언) 를 못 찾았다 — 이름이 바뀌었으면 이 검사도 함께 옮겨야 한다")
        return String(소스글[range])
    }

    /// **문 1.** 앱이 뜰 때 도는 유일한 자리다. 백그라운드로 되살아난 실행에서는
    /// `WindowGroup` 의 body 가 안 돌 수 있으므로(2단계 통합 검토 I1, 1단계 M6) 화면이 아니라
    /// `init()` 이어야 한다. 이 한 줄이 두 단계 동안 조용히 빠져 있었고, 증상은 "오늘은
    /// 조용하네"라서 아무도 못 찾았다.
    @Test("앱이 뜨면 KidCareApp.init() 이 아이 수집을 시작한다 (통합 검토 I2)")
    func 앱_시작_문() throws {
        let body = try 함수본문(try 소스("ios/KidCare/KidCareApp.swift"), "init()")
        #expect(body.contains("ChildSession.shared.startIfChild()"),
                "이 줄이 없으면 아이 폰이 앱을 다시 열 때까지 아무것도 기록하지 않는다 — 테스트는 전부 통과한 채로")
    }

    /// **문 2.** 아이로 막 페어링을 끝낸 순간. `KidCareApp.init()` 은 앱이 뜰 때 한 번 돌았고
    /// 그때는 역할이 없었으므로, 같은 문을 한 번 더 두드려야 그 실행에서 수집이 시작된다.
    @Test("아이로 막 페어링한 순간에도 같은 문을 두드린다 — RouterView 의 onChildReady (통합 검토 I2)")
    func 페어링_직후_문() throws {
        let src = try 소스("ios/KidCare/RouterView.swift")
        #expect(src.range(of: #"onChildReady:\s*\{[^}]*ChildSession\.shared\.startIfChild\(\)"#,
                          options: .regularExpression) != nil,
                "빈 클로저로 바꿔도 아무 검사가 안 빨개지던 자리다 — 페어링한 그 실행이 통째로 조용해진다")
    }

    @Test("로그인이 실패하면 화면이 그 사실을 말한다 — build 의 실패 갈래가 cannotStart 를 부른다 (통합 검토 I3)")
    func 실패는_화면으로() throws {
        let body = try 함수본문(try 소스("ios/KidCare/Child/ChildSession.swift"), "func build")
        #expect(body.contains("home.cannotStart()"),
                "이 한 줄이 없으면 수집이 하나도 없는 폰이 '공유 중'이라고 말한 채 굳는다")
    }

    @Test("'다시 해보기' 버튼이 실제로 세션을 다시 띄운다 — ChildRootView 의 onRetry (통합 검토 I3)")
    func 다시_해보기_배선() throws {
        let src = try 소스("ios/KidCare/Child/ChildRootView.swift")
        #expect(src.range(of: #"onRetry:\s*\{[^}]*session\.retryStart\(\)"#, options: .regularExpression) != nil,
                "프로세스 안에 세션이 다시 뜰 길이 이 버튼 하나다")
    }

    @Test("stop() 은 만들던 build 를 끊고 OS 지역을 걷는다 (통합 검토 M1·M2)")
    func 멈춤_배선() throws {
        let body = try 함수본문(try 소스("ios/KidCare/Child/ChildSession.swift"), "func stop")
        #expect(body.contains("buildTask?.cancel()"),
                "안 끊으면 로그인을 기다리던 build() 가 멈춘 세션을 다시 채운다 — 파이프라인이 두 벌이 된다")
        #expect(body.contains("placeWatcher?.stopMonitoring()"),
                "안 걷으면 옛 가족의 원 스무 개가 남아 계속 앱을 깨운다")
    }

    @Test("테스트 차단이 start 에 실제로 걸려 있다 (통합 검토 M3)")
    func 차단은_start_에() throws {
        let body = try 함수본문(try 소스("ios/KidCare/Child/ChildSession.swift"), "func start(familyId:")
        #expect(body.contains("mayStart"),
                "start 는 internal 이라 @testable import 로 곧장 닿는다 — 문이 여기 있어야 한다")
    }
}
