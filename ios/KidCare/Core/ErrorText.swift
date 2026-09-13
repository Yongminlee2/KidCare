import FirebaseFirestore
import Foundation

/// `Error` 를 화면에 그대로 띄울 수 있는 한 줄 문구로 바꾼다. 정본은 안드로이드
/// `app/src/main/java/com/kidcare/family/core/ErrorText.kt` 의 `errorMessage(Context, Throwable)`.
///
/// **왜 원문을 그대로 안 보여주는가:** "조용히 실패"보다 "보이게, 알아듣게 실패"가
/// 이 앱의 원칙이지만, `error.localizedDescription` 을 그대로 꽂으면 앞부분만
/// 지키고 뒷부분은 못 지킨 셈이다 — "PERMISSION_DENIED: Missing or insufficient
/// permissions." 같은 SDK 원문은 앱을 설치해준 사람이 아니면 그냥 소음이다.
/// 규칙(firestore.rules)과 색인을 콘솔에서 손으로 게시해야 켜지는 구조라
/// (docs/setup.md), 첫 실행에서 가장 흔한 실패가 바로 그 게시 누락이다 — 아래에서
/// 제일 먼저 잡는다.
///
/// 실패 화면 문자열은 기존 문구(`error_generic_format` 등) 뒤에 이 함수의 결과를
/// 끼워 넣는 식으로 쓰인다 — 레이아웃은 그대로 두고 내용만 이 함수가 정한다.
func errorMessage(_ error: Error) -> String {
    let ns = error as NSError

    if ns.domain == FirestoreErrorDomain {
        switch ns.code {
        // FAILED_PRECONDITION 은 복합 색인이 아직 안 만들어졌을 때도 뜬다
        // (docs/setup.md 참고). 규칙 미게시든 색인 미생성이든 부모가 할 수 있는
        // 행동은 같다 — "설치해 준 사람에게 알린다" — 이므로 같은 문구를 쓴다.
        case FirestoreErrorCode.permissionDenied.rawValue,
             FirestoreErrorCode.failedPrecondition.rawValue:
            return String(localized: "error_server_setup")

        // 서버에 닿지 못하는 상황은 아이 쪽 페어링에서 이미 pairing_offline 문구로
        // 안내하고 있다 — 같은 상황이니 문구를 새로 만들지 않고 그대로 재사용한다.
        case FirestoreErrorCode.unavailable.rawValue:
            return String(localized: "pairing_offline")

        case FirestoreErrorCode.unauthenticated.rawValue:
            return String(localized: "error_unauthenticated")

        default:
            break // 아래 공통 처리로 떨어진다.
        }
    }

    // Firestore 예외로 감싸이지 않은 순수 네트워크 실패(URLSession 이 소켓조차 못 여는
    // 경우 등)도 사용자 입장에서는 위 unavailable 과 같은 상황이다.
    if ns.domain == NSURLErrorDomain {
        return String(localized: "pairing_offline")
    }

    // 여기까지 왔다면 원인을 좁히지 못한 경우다. 한국어 안내를 먼저 보여주고,
    // 원문은 지우지 않고 둘째 줄에 남긴다 — 앱을 설치해준 사람이 폰을 들고 직접
    // 디버깅할 때 남은 유일한 단서이기 때문이다.
    return String(format: String(localized: "error_generic_format"), ns.localizedDescription)
}
