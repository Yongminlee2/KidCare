package com.kidcare.family.core

import android.content.Context
import com.google.firebase.firestore.FirebaseFirestoreException
import com.kidcare.family.R
import java.io.IOException

/**
 * Throwable 을 부모(또는 아이)가 읽고 바로 행동할 수 있는 한국어 문장으로 바꾼다.
 *
 * 이 앱은 "조용히 실패"보다 "보이게, 그리고 알아듣게 실패"를 원칙으로 삼는다.
 * 그런데 실패 문구에 e.message 를 그대로 꽂아 넣으면 앞부분만 지키고 뒷부분은
 * 못 지킨 셈이다 — 화면엔 뭔가 뜨지만 "PERMISSION_DENIED: Missing or
 * insufficient permissions." 같은 SDK 원문은 개발자가 아닌 사람에게는 그냥
 * 소음이다. 특히 이 앱은 규칙(firestore.rules)과 색인을 사람이 콘솔에서 직접
 * 게시/생성해야 켜지는 구조라(docs/setup.md), 첫 실행에서 가장 흔한 실패가
 * 바로 그 게시 누락이다 — 아래에서 제일 먼저 잡는다.
 *
 * 실패 화면 문자열은 대부분 "%1$s" 자리표시자를 쓴 기존 문구(pairing_failed,
 * connect_failed, map_error, timeline_error) 뒤에 이 함수의 결과를 끼워 넣는
 * 식으로 쓰인다 — 레이아웃(줄바꿈 위치)은 그대로 두고 내용만 이 함수가 정한다.
 */
fun errorMessage(context: Context, e: Throwable): String {
    if (e is FirebaseFirestoreException) {
        when (e.code) {
            // FAILED_PRECONDITION 은 복합 색인이 아직 안 만들어졌을 때도 뜬다
            // (docs/setup.md 참고). 규칙 미게시든 색인 미생성이든 부모가 할 수
            // 있는 행동은 같다 — "설치해 준 사람에게 알린다" — 이므로 같은
            // 문구를 쓴다.
            FirebaseFirestoreException.Code.PERMISSION_DENIED,
            FirebaseFirestoreException.Code.FAILED_PRECONDITION ->
                return context.getString(R.string.error_server_setup)

            // 서버에 닿지 못하는 상황은 아이 쪽 페어링에서 이미 pairing_offline
            // 문구로 안내하고 있다 — 같은 상황이니 문구를 새로 만들지 않고
            // 그대로 재사용한다.
            FirebaseFirestoreException.Code.UNAVAILABLE ->
                return context.getString(R.string.pairing_offline)

            FirebaseFirestoreException.Code.UNAUTHENTICATED ->
                return context.getString(R.string.error_unauthenticated)

            else -> Unit // 아래 공통 처리로 떨어진다.
        }
    }

    // Firestore 예외로 감싸이지 않은 순수 네트워크 실패(소켓이 아예 안 열리는
    // 경우 등)도 사용자 입장에서는 위 UNAVAILABLE 과 같은 상황이다.
    // UnknownHostException·SocketTimeoutException 은 모두 IOException 의
    // 하위 타입이라 이 한 줄로 다 잡힌다.
    if (e is IOException) {
        return context.getString(R.string.pairing_offline)
    }

    // 여기까지 왔다면 원인을 좁히지 못한 경우다. 한국어 안내를 먼저 보여주고,
    // 원문은 지우지 않고 둘째 줄에 남긴다 — 앱을 설치해준 사람이 폰을 들고
    // 직접 디버깅할 때 남은 유일한 단서이기 때문이다.
    return context.getString(R.string.error_generic_format, e.message ?: e.toString())
}
