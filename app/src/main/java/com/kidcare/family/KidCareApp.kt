package com.kidcare.family

import android.app.Application
import androidx.appcompat.app.AppCompatDelegate
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore

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
 */
class KidCareApp : Application() {

    override fun onCreate() {
        super.onCreate()

        // The approved sticker-diary design is intentionally light and warm on every device.
        AppCompatDelegate.setDefaultNightMode(AppCompatDelegate.MODE_NIGHT_NO)

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

    }

    private companion object {
        const val AUTH_EMULATOR_PORT = 9099
        const val FIRESTORE_EMULATOR_PORT = 8080
    }
}
