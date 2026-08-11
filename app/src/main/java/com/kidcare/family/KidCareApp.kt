package com.kidcare.family

import android.app.Application
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import java.io.File
import org.osmdroid.config.Configuration

/**
 * 앱 진입점.
 *
 * ## 오프라인 처리는 이미 켜져 있다 — 다시 만들지 말 것
 *
 * 이 파일에는 Firestore 설정이 한 줄도 없다. **그게 정상이고, 기본값에 기대는 것이
 * 의도다.** 다음 사람이 "오프라인 처리가 없네" 하고 중복 구현하는 것을 막으려고
 * 여기 적어둔다 — `FirebaseFirestoreSettings` 를 세우고 싶어질 때 제일 먼저 오는
 * 자리가 이 함수라서다.
 *
 * 근거(firebase-firestore 26.5.0 의 `FirebaseFirestoreSettings$Builder` 생성자를
 * 역어셈블해 확인): `persistenceEnabled = true`, `cacheSizeBytes = 104857600`(100MB).
 * 안드로이드에서는 **로컬 캐시와 쓰기 큐가 기본으로 켜져 있다.** 그래서 이 앱이
 * 오프라인에서 하는 일은 전부 SDK 가 이미 하고 있다.
 *
 * 다만 읽기와 쓰기가 **정반대로** 움직인다는 것을 알고 써야 한다.
 *
 * - **읽기는 막히지 않는다.** `get()` 은 서버에 못 닿으면 캐시로 답하고 곧바로
 *   돌아온다. 캐시에 그 문서가 없으면 "없는 문서"로 답한다 — 즉 **"서버에 없다"와
 *   "아직 못 받아왔다"가 같은 모양으로 온다.** 둘을 가르는 유일한 값이
 *   `snapshot.metadata.isFromCache` 다([com.kidcare.family.core.TrailRepository.fetch],
 *   [com.kidcare.family.core.FamilyRepository.joinFamily] 가 그래서 그 값을 본다).
 * - **쓰기는 그 자리에 멈춘다.** `set()`/`update()` 가 돌려주는 Task 는 로컬 큐에
 *   들어간 순간이 아니라 **서버가 확인해 준 순간**에만 완료된다(SyncEngine 은
 *   `writeMutations` 에서 TaskCompletionSource 를 보관만 하고,
 *   `handleSuccessfulWrite`/`handleRejectedWrite` 에서야 완료시킨다). 제한시간도
 *   없다. 그래서 `.await()` 를 부른 코루틴은 연결이 돌아올 때까지 **몇 시간이든
 *   매달려 있는다** — 쓰기 자체는 큐에 안전하게 들어가 있는데도 그렇다.
 *
 * 이 비대칭이 화면을 거짓말하게 만든다: 명령을 보낸 화면은 "전달 중…"에서 영영 안
 * 벗어나고, 캐시가 빈 목록은 "아직 없어요"라고 단언한다. 그 자리들을 어떻게
 * 고쳤는지는 `docs/known-issues.md` 19번에 적었다.
 *
 * osmdroid는 카카오맵과 달리 앱키 발급이 필요 없다 — OpenStreetMap 타일은 등록 없이
 * 누구나 받아올 수 있다. 대신 타일을 하나라도 요청하기 전에 사용자 에이전트(User-Agent)를
 * 반드시 지정해야 한다. OSM 공용 타일 서버는 User-Agent로 요청 주체를 구분하는데, 기본값을
 * 그대로 두는 앱이 많아지면 서버가 그 값 자체를 차단할 수 있다 — 그러면 이 앱뿐 아니라
 * osmdroid를 쓰는 다른 앱까지 함께 막히는 정책 위반이 된다. applicationId처럼 앱마다
 * 고유한 값을 넣는 것이 osmdroid 공식 정책이다.
 */
class KidCareApp : Application() {

    override fun onCreate() {
        super.onCreate()

        // 운영 데이터와 완전히 분리한 실기기 통합 테스트 경로. 이 상수는 기본값이
        // false이고 Gradle의 -PfirebaseEmulator=true를 명시한 디버그 APK에서만
        // true가 된다. 127.0.0.1은 각 폰에서 adb reverse로 PC의 같은 에뮬레이터에
        // 연결되므로 보호자·자녀 두 대가 실제 페어링을 검증할 수 있다.
        if (BuildConfig.DEBUG && BuildConfig.USE_FIREBASE_EMULATOR) {
            FirebaseAuth.getInstance().useEmulator("127.0.0.1", AUTH_EMULATOR_PORT)
            FirebaseFirestore.getInstance().useEmulator("127.0.0.1", FIRESTORE_EMULATOR_PORT)
        }

        // FirebaseFirestore.getInstance().firestoreSettings = ... 를 여기에 세우지
        // 않는다. 기본값이 이미 우리가 원하는 값이고(위 클래스 주석의 근거 참고),
        // 기본값과 같은 값을 다시 적어두면 다음 사람이 "이 줄이 켜는 기능"이라고
        // 읽어 지우면 안 되는 줄로 오해한다. 정말 바꿔야 할 때(캐시 크기 조절 등)
        // 만드는 자리는 여기가 맞다.

        val config = Configuration.getInstance()
        config.userAgentValue = BuildConfig.APPLICATION_ID

        // 타일 캐시 위치를 앱 전용 캐시 폴더 아래로 고정한다. 지정하지 않으면 osmdroid가
        // 기기별로 "가장 여유 있는 쓰기 가능 저장소"를 스스로 탐색하는데(jar 역어셈블로
        // 확인 — StorageUtils.getBestWritableStorage), API 29 미만 기기에서는 그 후보에
        // 공용 외장 저장소 루트도 섞여 들어간다. 이 앱은 WRITE_EXTERNAL_STORAGE 권한이
        // 없어 그 경로는 결국 쓰기에 실패해 앱 전용 폴더로 되돌아가지만, 그 판단을 osmdroid
        // 내부 탐색에 맡기지 않고 처음부터 캐시 목적에 맞는 cacheDir 아래로 고정해 버린다
        // — 추가 권한이 전혀 필요 없고, 기기 저장공간이 부족하면 시스템이 알아서 비운다.
        val tileCacheDir = File(cacheDir, "osmdroid")
        config.osmdroidBasePath = tileCacheDir
        config.osmdroidTileCache = File(tileCacheDir, "tiles")
    }

    private companion object {
        const val AUTH_EMULATOR_PORT = 9099
        const val FIRESTORE_EMULATOR_PORT = 8080
    }
}
