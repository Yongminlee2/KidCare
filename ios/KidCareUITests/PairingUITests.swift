import XCTest

/// 실기기에서 사람 대신 화면을 눌러보는 자동화.
///
/// 단위 테스트(`KidCareTests`)와 목적이 다르다. 저 쪽은 계산이 맞는지를 보고,
/// 이 쪽은 **실제 아이폰에서 운영 Firebase 를 상대로 페어링이 되는지**를 본다.
/// 그래서 기본 테스트 스킴에 넣지 않는다 — 시뮬레이터에서 돌 이유가 없고,
/// 운영 데이터를 건드리므로 사람이 의도해서 돌려야 한다.
final class PairingUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// 앱이 뜨고 역할 선택 화면이 보이는지. 자동화가 실기기에 닿는지를 먼저 확인한다.
    func test_역할선택_화면이_보인다() throws {
        let app = XCUIApplication()
        app.launch()

        let 보호자 = app.buttons["보호자"]
        XCTAssertTrue(보호자.waitForExistence(timeout: 20), "역할 선택 화면이 안 떴다")

        붙인다(app, 이름: "01-역할선택")
    }

    /// 보호자 → 가족에 합류하기 → 코드 입력 → 합류.
    ///
    /// 코드는 안드로이드 폰에서 발급한 **보호자용** 6자리를 환경변수로 받는다.
    /// 없으면 건너뛴다 — 코드는 10분이면 죽어서 소스에 박아둘 수가 없다.
    func test_보호자_코드로_가족에_합류한다() throws {
        guard let 코드 = ProcessInfo.processInfo.environment["KIDCARE_INVITE_CODE"],
              코드.count == 6 else {
            throw XCTSkip("KIDCARE_INVITE_CODE 환경변수가 없다. 안드로이드 폰에서 보호자 초대 코드를 발급해 넣을 것.")
        }

        let app = XCUIApplication()
        app.launch()

        let 보호자 = app.buttons["보호자"]
        XCTAssertTrue(보호자.waitForExistence(timeout: 20), "역할 선택 화면이 안 떴다")
        보호자.tap()
        붙인다(app, 이름: "02-보호자-갈래선택")

        let 합류 = app.buttons["가족에 합류하기"]
        XCTAssertTrue(합류.waitForExistence(timeout: 10), "합류 갈래가 안 보인다")
        합류.tap()

        let 입력칸 = app.textFields.firstMatch
        XCTAssertTrue(입력칸.waitForExistence(timeout: 10), "코드 입력칸이 없다")
        입력칸.tap()
        입력칸.typeText(코드)
        붙인다(app, 이름: "03-코드입력")

        let 합류버튼 = app.buttons["연결하기"]
        XCTAssertTrue(합류버튼.waitForExistence(timeout: 5), "합류 버튼이 없다")
        합류버튼.tap()

        // 합류가 끝나면 지도 화면으로 넘어간다. 네트워크 왕복이 있으니 넉넉히 기다린다.
        let 지도가_떴나 = app.otherElements.containing(NSPredicate(format: "identifier CONTAINS[c] 'map'")).firstMatch
        _ = 지도가_떴나.waitForExistence(timeout: 30)
        sleep(5)   // 지도 타일이 실제로 그려질 시간
        붙인다(app, 이름: "04-합류결과")
    }

    /// 스크린샷을 테스트 결과에 남긴다. 실기기는 내가 화면을 직접 볼 수 없어서
    /// 이 첨부가 유일한 눈이다.
    private func 붙인다(_ app: XCUIApplication, 이름: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = 이름
        shot.lifetime = .keepAlways
        add(shot)
    }
}
