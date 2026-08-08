package com.kidcare.family.logic

/**
 * 하루치 위치 점을 줄 단위 문자열로 바꾸고 되돌린다.
 *
 * 왜 필요해졌나: 위치 점은 더 이상 한 점마다 Firestore 로 가지 않는다. 아이 폰이
 * 하루치를 자기 안에 쌓아 두고, 부모가 물어볼 때(그리고 하루 한 번 안전 업로드)만
 * 문서 하나로 올린다(docs/known-issues.md 12번). 그러면 프로세스가 죽는 순간 그날
 * 걸어온 길이 통째로 사라지므로 파일에 남겨야 한다.
 *
 * 형식이 줄 단위 CSV 인 이유는 세 가지다.
 *  - **덧붙이기만 하면 된다.** 한 점이 한 줄이라 새 점이 생길 때마다 파일 끝에 한 줄을
 *    붙이면 끝이다. JSON 배열이나 SharedPreferences 였다면 30초마다 하루치 전체를
 *    다시 써야 한다(하루 수백 번의 전체 쓰기 = 쓸데없는 플래시 마모).
 *  - **새 의존성이 없다.** JSON 라이브러리를 들이지 않기로 한 제약을 지킨다.
 *  - **테스트로 고정할 수 있다.** `org.json` 은 안드로이드 프레임워크 클래스라 JVM
 *    단위 테스트에서는 빈 껍데기로 대체돼 이 변환을 테스트로 못 잡는다. 여기는
 *    안드로이드 API 를 하나도 안 쓰므로 그냥 돌아간다.
 *
 * 숫자는 [Double.toString]/[Float.toString] 이 만드는 형식 그대로 쓴다 — 로케일에
 * 좌우되지 않는다. `String.format` 을 쓰면 한국어 로케일에서도 소수점이 `.` 이라
 * 지금은 우연히 맞지만, 로케일이 바뀌면 `,` 가 나와 구분자와 충돌한다.
 */
object TrailCodec {

    /**
     * 문서 하나에 담을 점의 최대 개수.
     *
     * Firestore 문서 한 개의 상한은 1MB 다. 점 하나가 지도 배열 원소로 들어가면
     * 필드 이름까지 매번 같이 저장되므로 대략 90~100바이트를 쓴다 — 2000개면
     * 200KB 안쪽이고, 같은 문서에 함께 담기는 구간 요약(하루 20~30개)까지 더해도
     * 상한의 4분의 1을 안 넘는다.
     *
     * 정상적인 하루는 약 520점이다(이동 30초·정지 5분 주기 + LocationFilter 의
     * 25m/10분 문턱). 즉 2000은 정상치의 네 배가 되는 지점이고, 여기에 닿는 날은
     * 이미 어딘가 고장난 날이다(수집 주기가 폭주했거나, 자정 판정이 어긋나 이틀치가
     * 한 dayKey 에 몰렸거나). 그런 날에도 **문서 쓰기 자체는 성공해야 한다** —
     * 1MB 를 넘기면 그 날의 기록이 통째로 안 올라가고, 부모 화면은 아무 설명 없이
     * 비어 보인다.
     *
     * 넘칠 때 **오래된 쪽을 버린다**([capped]). 균등하게 솎아내는 방법도 있지만
     * 그러면 하루 전체가 반쪽 해상도가 되는데, 넘치는 날은 애초에 비정상이고 부모가
     * 실제로 묻는 것은 "지금 어디 있냐"라서 최근 구간이 온전한 쪽이 낫다. 오래된
     * 앞부분은 그날 이미 여러 번 올라갔던 내용이기도 하다.
     */
    const val MAX_POINTS = 2000

    /** 점 하나를 한 줄로. 줄바꿈은 붙이지 않는다 — 파일에 쓰는 쪽이 정한다. */
    fun encodeLine(fix: Fix): String =
        "${fix.lat},${fix.lng},${fix.accuracy},${fix.speed},${fix.at}"

    /**
     * 줄 묶음을 점 목록으로. **깨진 줄은 조용히 버린다.**
     *
     * 파일 끝에 덧붙이는 방식이라 프로세스가 쓰기 도중에 죽으면 마지막 줄이 잘려
     * 있을 수 있다. 그 한 줄 때문에 그날 기록 전체를 버리면(예외를 던지면) 사고가
     * 훨씬 커진다 — 잘린 줄 하나만 빼고 나머지를 살린다.
     */
    fun decode(text: String): List<Fix> =
        text.lineSequence().mapNotNull(::decodeLine).toList()

    private fun decodeLine(line: String): Fix? {
        val parts = line.split(',')
        if (parts.size != 5) return null
        val lat = parts[0].toDoubleOrNull() ?: return null
        val lng = parts[1].toDoubleOrNull() ?: return null
        val accuracy = parts[2].toFloatOrNull() ?: return null
        val speed = parts[3].toFloatOrNull() ?: return null
        val at = parts[4].toLongOrNull() ?: return null
        return Fix(lat = lat, lng = lng, accuracy = accuracy, at = at, speed = speed)
    }

    /** [MAX_POINTS] 를 넘으면 **가장 오래된 쪽을 버리고** 최근 것만 남긴다. */
    fun capped(points: List<Fix>): List<Fix> =
        if (points.size <= MAX_POINTS) points else points.takeLast(MAX_POINTS)
}
