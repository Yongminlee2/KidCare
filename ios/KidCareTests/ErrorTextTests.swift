import Testing
@testable import KidCare
import FirebaseFirestore
import Foundation

/// 정본은 안드로이드 `app/src/main/java/com/kidcare/family/core/ErrorText.kt` 의
/// `errorMessage(Context, Throwable)`. 코드별 분기를 그대로 옮긴다.
struct ErrorTextTests {

    private func firestoreError(_ code: Int) -> NSError {
        NSError(domain: FirestoreErrorDomain, code: code)
    }

    @Test("PERMISSION_DENIED 는 서버 설정 안내로 바뀐다")
    func 권한_거부는_서버_설정_안내() {
        #expect(errorMessage(firestoreError(FirestoreErrorCode.permissionDenied.rawValue)) == String(localized: "error_server_setup"))
    }

    @Test("FAILED_PRECONDITION 도 같은 서버 설정 안내를 쓴다 — 색인 미생성과 규칙 미게시를 구분하지 않는다")
    func 조건_실패도_서버_설정_안내() {
        #expect(errorMessage(firestoreError(FirestoreErrorCode.failedPrecondition.rawValue)) == String(localized: "error_server_setup"))
    }

    @Test("UNAVAILABLE 은 오프라인 문구를 재사용한다")
    func 서버_불가는_오프라인_문구() {
        #expect(errorMessage(firestoreError(FirestoreErrorCode.unavailable.rawValue)) == String(localized: "pairing_offline"))
    }

    @Test("UNAUTHENTICATED 는 재로그인 안내다")
    func 인증_풀림은_재로그인_안내() {
        #expect(errorMessage(firestoreError(FirestoreErrorCode.unauthenticated.rawValue)) == String(localized: "error_unauthenticated"))
    }

    @Test("순수 네트워크 실패도 오프라인 문구를 쓴다")
    func 네트워크_실패도_오프라인_문구() {
        let e = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        #expect(errorMessage(e) == String(localized: "pairing_offline"))
    }

    @Test("원인을 못 좁히면 원문을 둘째 줄에 남긴다")
    func 알_수_없는_실패는_원문을_남긴다() {
        let e = NSError(domain: "SomeOtherDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        let expected = String(format: String(localized: "error_generic_format"), "boom")
        #expect(errorMessage(e) == expected)
    }
}
