package com.kidcare.family.guardian

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import com.kidcare.family.R
import com.kidcare.family.core.model.ChildStatusDoc
import com.kidcare.family.databinding.ActivityGuardianMainBinding
import com.kidcare.family.logic.DisconnectRule
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 보호자 메인 컨테이너. 하단 탭이 프래그먼트를 갈아 끼운다.
 *
 * 지금 탭은 다섯이다 — 지도(3단계), 관리·예약(4단계), 장소·알림(5단계). 다섯을 접지
 * 않고 그대로 둔 근거(실제 칸 너비)는 guardian_bottom_nav.xml 주석에 적었다.
 *
 * **replace 를 쓰지 않는다.** 프래그먼트를 태그로 찾아 두고 show/hide 로만 오간다.
 * replace 는 탭을 옮길 때마다 지도 프래그먼트를 새로 만들고, 그러면 osmdroid 가
 * 타일을 처음부터 다시 내려받아 탭 이동마다 통신이 생기고 부모가 옮겨둔 지도 위치도
 * 초기화된다.
 *
 * ## 연결 끊김 배너를 여기에 둔 이유
 *
 * 아이가 설정 → 앱 → **강제 종료**를 누르면(권한이 필요 없다) 안드로이드는 앱을
 * "stopped" 상태로 만든다. 그러면 `BOOT_COMPLETED` 가 배달되지 않고 걸어둔
 * `AlarmManager` 알람이 전부 취소된다 — 명령 리스너·되돌리기·예약 알람·위치 추적이
 * 한꺼번에 멎고, 재부팅을 해도 **아이 폰에서 사람이 앱을 한 번 열기 전까지** 그대로다.
 * 기기관리자 권한 없이 사이드로드로 깔린 앱이 이걸 막을 방법은 없다(README, 그리고
 * docs/known-issues.md). 막을 수 없으니 **부모에게 말해주는 것**이 이 배너의 전부다.
 *
 * 배너를 프래그먼트마다 두지 않고 액티비티 레이아웃 한 곳에 둔 이유:
 * 관리 탭을 한 번도 안 여는 부모도 봐야 하고(지도만 보는 부모가 많다), 탭마다 두면
 * 같은 사실을 두 곳에서 판정하게 되어 한쪽만 뜨는 어긋남이 생긴다. 여기 하나면
 * 어느 탭을 보고 있든 같은 문장이 같은 자리에 뜬다.
 *
 * ## 판정 재료를 바꾼 이유 (무료 한도 개편)
 *
 * 옛 판정은 "마지막 상태 신호가 30분 넘게 안 바뀌면"이었다. 그 신호를 만들던
 * 주기적 상태 쓰기가 사라졌으므로(docs/known-issues.md 12번) 그대로 두면 **멀쩡한
 * 폰이 30분마다 무조건 끊긴 것으로 보인다.** 그래서 재료를 "물어봤는데 대답이
 * 없는가"로 바꿨다 — 판정 규칙과 그 근거는 [com.kidcare.family.logic.DisconnectRule],
 * 재료 저장은 [RequestLog] 참고.
 */
class GuardianMainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityGuardianMainBinding

    /**
     * 탭 하나의 명세. [menuId] 는 guardian_bottom_nav.xml 의 항목 ID, [tag] 는
     * FragmentManager 가 프래그먼트를 되찾는 열쇠다.
     *
     * [tag] 를 프래그먼트 클래스 이름으로 삼지 않고 상수로 박아둔 이유: 태그는
     * 회전·프로세스 사망 뒤 복원에서 "같은 화면"을 알아보는 식별자라 클래스 이름을
     * 바꾸면 옛 인스턴스를 못 찾고 하나 더 만들게 된다.
     */
    private data class Tab(val menuId: Int, val tag: String, val create: () -> Fragment)

    /**
     * '장소'를 관리 화면 안의 줄이 아니라 **탭**으로 둔 이유(5단계 Task 3 의 결정).
     *
     * 관리 탭 안에 넣으려면 그 화면 안에 화면 전환을 하나 새로 만들어야 한다(자식
     * 프래그먼트든 별도 액티비티든). 그러면 뒤로 가기 스택이 하나 늘고, 편집 중
     * 화면 회전·프로세스 사망 복원 경로도 그만큼 갈라진다 — 지금 예약 탭이 판 두
     * 개를 겹쳐 쓰는 방식으로 겨우 피해 둔 문제다. 코드는 더 많아지는데 얻는 것은
     * 하단 탭 한 칸뿐이다.
     *
     * 게다가 장소는 관리(지금 바로 아이 폰을 바꾸는 동작들)의 설정이 아니라 이 앱의
     * 독립된 명사다 — 설계서 §3 이 `places/` 를 별도 컬렉션으로 두고 있고, 알림
     * 문구에 그 이름이 그대로 나온다. 관리 화면 아래에 묻으면 부모가 못 찾는다.
     */
    private val tabs = listOf(
        Tab(R.id.tab_map, TAG_MAP) { MapTimelineFragment() },
        Tab(R.id.tab_alert, TAG_ALERT) { AlertFragment() },
        Tab(R.id.tab_control, TAG_CONTROL) { ControlFragment() },
        Tab(R.id.tab_schedule, TAG_SCHEDULE) { ScheduleFragment() },
        Tab(R.id.tab_place, TAG_PLACE) { PlaceFragment() },
    )

    /** 지금 보이는 탭. 같은 탭으로 두 번 부르는 호출을 걸러내는 데 쓴다. */
    private var currentTabId: Int = 0

    /** 배너 판정 재료(마지막 물음·마지막 대답 시각). 화면이 뜬 뒤에만 만진다. */
    private val requestLog by lazy { RequestLog(this) }

    /**
     * 배너를 주기적으로 다시 판정하는 코루틴.
     *
     * 이게 없으면 기능이 정확히 반대로 동작한다: 판정 재료가 "얼마나 오래됐는가"인데
     * 화면을 다시 그리는 계기가 Firestore 스냅샷뿐이면, **완전히 멎어서 아무 스냅샷도
     * 안 오는 폰**에서는 배너가 영영 안 뜬다. 조용해진 것을 알리는 것이 목적인데 조용해서
     * 못 알리는 셈이다. 그래서 시간이 흐르는 것만으로도 다시 판정한다.
     */
    private var bannerJob: Job? = null

    /**
     * 상태바·내비게이션바가 차지하는 높이. 인셋 리스너가 채워 넣는다.
     *
     * 화면마다 이 값을 쓰는 방식이 달라서 액티비티가 한 곳에서 나눠준다. 지도는
     * 상태바 **뒤까지** 그려야 지도다운데(타일이 화면 끝까지 차야 한다), 관리·예약은
     * 첫 줄이 상태바 시계와 겹쳐 읽을 수 없게 된다 — 실기기에서 "지금 바로 바꾸기"가
     * 시계 위에 겹쳐 찍힌 것을 보고 넣은 처리다. 프래그먼트마다 각자 인셋을 먹으면
     * 배너가 떴을 때 여백이 두 번 들어가므로, 누가 먹을지는 여기서 정한다.
     */
    private var topInset: Int = 0

    /** 배너가 레이아웃에서 원래 갖고 있던 위쪽 여백(px). 인셋을 여기에 더한다. */
    private var bannerBaseTopPadding: Int = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityGuardianMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        bannerBaseTopPadding = binding.disconnectBanner.paddingTop

        ViewCompat.setOnApplyWindowInsetsListener(binding.root) { _, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            topInset = bars.top
            // 하단 탭은 늘 내비게이션바를 피한다. 지도와 달리 탭은 가려지면
            // 누를 수가 없어서, 뒤로 깔아둘 이유가 없다.
            binding.bottomNav.updatePadding(bottom = bars.bottom)
            applyTopInset()
            insets
        }

        binding.bottomNav.setOnItemSelectedListener { item ->
            val tab = tabs.firstOrNull { it.menuId == item.itemId }
            if (tab == null) false else { showTab(tab); true }
        }
        // 같은 탭을 다시 눌러도 아무 일도 하지 않는다. 기본 동작은 그대로 두면
        // 선택 리스너가 다시 도는데, 거기서 트랜잭션을 또 커밋할 이유가 없다.
        binding.bottomNav.setOnItemReselectedListener { }

        // 회전·프로세스 사망 뒤에는 FragmentManager 가 프래그먼트를 이미 되살려 놨고
        // BottomNavigationView 도 자기 선택 상태를 스스로 복원한다. 그래도 어느 탭이
        // 선택돼 있었는지는 우리가 직접 기억해 둔다 — 복원 순서(뷰 상태 복원은
        // onCreate 뒤)에 기대지 않고 여기서 곧장 옳은 탭을 띄우기 위해서다.
        // 알림을 눌러 들어온 경우에는 저장된 탭보다 그쪽이 먼저다 — 부모가 방금 본
        // 한 줄을 찾으러 온 것인데 지도가 뜨면 다시 헤매게 된다([AlertService]).
        val startTabId = when {
            intent.getBooleanExtra(EXTRA_OPEN_ALERTS, false) -> R.id.tab_alert
            else -> savedInstanceState?.getInt(KEY_SELECTED_TAB) ?: R.id.tab_map
        }
        val startTab = tabs.firstOrNull { it.menuId == startTabId } ?: tabs.first()
        binding.bottomNav.selectedItemId = startTab.menuId
        // 위 대입이 선택 리스너를 부를 수도, (이미 그 항목이 선택돼 있었다면)
        // 재선택 리스너를 불러 그냥 지나갈 수도 있다 — 라이브러리 내부 사정이다.
        // showTab 은 몇 번을 불러도 결과가 같으므로(태그로 찾고 없을 때만 add)
        // 여기서 한 번 더 직접 불러 "첫 화면이 비어 있는" 경우를 원천봉쇄한다.
        showTab(startTab)
    }

    /**
     * 이미 떠 있는 화면 위로 알림을 눌러 들어온 경우. [AlertService] 의 PendingIntent
     * 가 CLEAR_TOP|SINGLE_TOP 이라 액티비티를 새로 만들지 않고 여기로 들어온다.
     *
     * `setIntent` 를 반드시 부른다 — 안 부르면 이 뒤에 회전이 일어났을 때 [onCreate]
     * 가 옛 인텐트를 다시 읽어 탭이 되돌아간다.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (!intent.getBooleanExtra(EXTRA_OPEN_ALERTS, false)) return
        val tab = tabs.firstOrNull { it.menuId == R.id.tab_alert } ?: return
        binding.bottomNav.selectedItemId = tab.menuId
        // selectedItemId 대입이 이미 선택돼 있던 탭이면 선택 리스너를 안 부른다.
        // showTab 은 여러 번 불려도 결과가 같으므로 여기서 한 번 더 직접 부른다
        // (onCreate 가 같은 이유로 하는 것과 같다).
        showTab(tab)
    }

    /**
     * 이 탭을 보이게 하고 나머지는 숨긴다.
     *
     * 같은 탭으로 여러 번 불려도 안전하다: 태그로 먼저 찾고 없을 때만 새로 만든다.
     * 이 순서가 중요한 이유는 복원 경로다 — 회전하면 FragmentManager 가 지도
     * 프래그먼트를 같은 태그로 이미 되살려 놓는데, 그걸 확인하지 않고 add 하면
     * 지도가 두 개 겹쳐 쌓인다(타일도 두 벌 내려받는다).
     */
    private fun showTab(tab: Tab) {
        if (currentTabId == tab.menuId) return
        val fm = supportFragmentManager
        val tx = fm.beginTransaction()
        tabs.forEach { other ->
            if (other.menuId == tab.menuId) return@forEach
            fm.findFragmentByTag(other.tag)?.let { tx.hide(it) }
        }
        val target = fm.findFragmentByTag(tab.tag)
        if (target == null) {
            tx.add(R.id.fragment_container, tab.create(), tab.tag)
        } else {
            tx.show(target)
        }
        // commit() 이 아니라 commitNow() 다. commit() 은 트랜잭션을 메인 루퍼에
        // 예약만 하므로, 같은 호출 흐름 안에서 showTab 이 한 번 더 불리면 위
        // findFragmentByTag 가 방금 add 한 프래그먼트를 아직 못 찾아 **똑같은
        // 프래그먼트를 하나 더 붙인다** — 지도가 두 겹으로 쌓이고 타일도 두 벌
        // 내려받는다. 바로 위 currentTabId 검사만으로도 지금의 호출 경로는
        // 막히지만, 두 방어선 중 이쪽이 근본이라 함께 둔다.
        tx.commitNow()
        currentTabId = tab.menuId
        applyTopInset()
    }

    /**
     * 상태바 높이를 누가 먹을지 정한다.
     *
     * 순서가 곧 규칙이다. 배너가 떠 있으면 배너가 먹는다 — 배너는 맨 위에 있고,
     * 그게 안 읽히면 배너를 만든 이유가 없어진다. 배너가 없으면 지도 탭만 빼고
     * 프래그먼트 자리가 먹는다. 지도는 상태바 뒤까지 타일을 채워야 하고, 지도에는
     * 가려질 글자가 없다.
     *
     * 둘 중 하나만 먹는다는 것이 요점이다. 양쪽이 다 먹으면 배너가 뜬 순간 상태바
     * 높이만큼 빈 칸이 두 번 생겨 화면이 아래로 밀린다.
     */
    private fun applyTopInset() {
        val bannerShown = binding.disconnectBanner.visibility == View.VISIBLE
        // 배너가 레이아웃에서 이미 갖고 있던 위쪽 여백(12dp)에 상태바 높이를 **더한다**.
        // 그냥 덮어쓰면 배너가 안 떠 있을 때 그 12dp 까지 같이 사라져 글자가 배경에
        // 딱 붙는다.
        binding.disconnectBanner.updatePadding(
            top = bannerBaseTopPadding + if (bannerShown) topInset else 0,
        )
        val mapShown = currentTabId == R.id.tab_map
        binding.fragmentContainer.updatePadding(
            top = if (bannerShown || mapShown) 0 else topInset,
        )
    }

    // ------------------------------------------------------------ 연결 끊김 배너

    /**
     * 프래그먼트가 [RequestLog] 를 갱신한 직후에 부른다(물음을 보냈거나 대답을 받았을 때).
     *
     * **리스너를 여기서 새로 붙이지 않는 것이 핵심이다.** 액티비티가 자기 리스너를
     * 하나 더 붙이면 같은 문서를 한 번 더 읽게 되고, 그건 이 개편이 없애려던 비용이다.
     * 배너는 부모 폰 안의 값([RequestLog])만 보고 판정하므로 서버를 아예 안 건드린다.
     *
     * 1분마다 도는 [bannerJob] 도 어차피 같은 값을 다시 보지만, 대답이 도착한 순간
     * 배너가 최대 1분 늦게 사라지면 부모 눈에는 고장이다 — 그래서 즉시 한 번 더 판정한다.
     */
    fun refreshBanner() {
        renderBanner()
    }

    override fun onStart() {
        super.onStart()
        bannerJob?.cancel()
        bannerJob = lifecycleScope.launch {
            while (true) {
                renderBanner()
                delay(BANNER_RECHECK_MILLIS)
            }
        }
    }

    override fun onStop() {
        // 화면이 안 보이는 동안 1분마다 깨어날 이유가 없다. 다시 보일 때 onStart 가
        // 곧바로 한 번 판정하므로 배너가 늦게 뜨지도 않는다.
        bannerJob?.cancel()
        bannerJob = null
        super.onStop()
    }

    /**
     * 배너를 띄울지 말지 판정하고 문구를 만든다.
     *
     * 재료는 부모 폰 안의 [RequestLog] 뿐이라 서버를 한 번도 안 건드린다. 세 조건
     * (물어본 적 있음 / 그 뒤로 대답 없음 / 문턱 초과)과 그 근거는
     * [com.kidcare.family.logic.DisconnectRule] 에 적어뒀다.
     *
     * 기준 시각으로 [FamilyRepository.serverNow] 대신 기기 시계를 쓴다 — 비교 대상
     * 두 값도 이 폰이 자기 시계로 적은 것이라, 같은 시계끼리 빼는 쪽이 오히려
     * 정확하다([RequestLog] 주석).
     */
    private fun renderBanner() {
        val lastRequestAt = requestLog.lastRequestAt
        val now = System.currentTimeMillis()
        val disconnected = DisconnectRule.isDisconnected(
            lastRequestAt = lastRequestAt,
            lastAnswerAt = requestLog.lastAnswerAt,
            nowMillis = now,
        )
        binding.disconnectBanner.visibility = if (disconnected) View.VISIBLE else View.GONE
        applyTopInset()
        if (!disconnected) return
        binding.disconnectBanner.text = getString(
            R.string.guardian_disconnect_banner,
            LastSignalText.elapsedText(this, now - lastRequestAt),
        )
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putInt(KEY_SELECTED_TAB, binding.bottomNav.selectedItemId)
    }

    companion object {
        /** 알림을 눌러 들어왔다는 표시([AlertService] 가 담는다). */
        const val EXTRA_OPEN_ALERTS = "open_alerts"

        private const val TAG_MAP = "tab_map"
        private const val TAG_ALERT = "tab_alert"
        private const val TAG_CONTROL = "tab_control"
        private const val TAG_SCHEDULE = "tab_schedule"
        private const val TAG_PLACE = "tab_place"
        private const val KEY_SELECTED_TAB = "selected_tab"

        /** 시간이 흐른 것만으로 다시 판정하는 간격([bannerJob] 주석 참고). 30분
         *  기준에 대해 1분 오차면 충분하고, 1분에 한 번 도는 비용은 무시할 만하다.
         *  판정 자체는 서버를 안 건드리므로 이 반복에 통신 비용이 전혀 없다. */
        private const val BANNER_RECHECK_MILLIS = 60 * 1000L
    }
}

/**
 * 아이 폰이 마지막으로 신호를 남긴 시각과 **그 값이 누구 시계인지.**
 *
 * 출처를 함께 들고 다니는 이유: 서버 시계로 적힌 값과 아이 폰 시계로 적힌 값은
 * 신뢰도가 전혀 다른데 둘 다 그냥 Long 이라 섞이면 구분이 안 된다. 연결 끊김 배너는
 * 서버 값일 때만 판정하고, 관리 탭의 "마지막 신호" 한 줄은 아이 폰 값일 때 상대
 * 표현을 포기한다 — 두 판단 다 이 플래그가 있어야 내릴 수 있다.
 */
data class ChildSignal(val atMillis: Long, val fromServerClock: Boolean)

/**
 * 상태 문서에서 "마지막 신호"를 뽑는다. 서버 시각이 있으면 그것, 없으면 아이 폰이
 * 자기 시계로 적은 옛 필드로 물러난다(두 필드가 있는 이유는 [ChildStatusDoc] 주석).
 * null 이면 쓸 만한 값이 아예 없다는 뜻이다.
 *
 * 이 판단을 화면마다 다시 적지 않으려고 한 곳에 모았다 — 지도 탭·관리 탭·배너가
 * 서로 다른 "마지막 신호"를 말하면 그 자체가 부모를 헷갈리게 한다.
 */
fun ChildStatusDoc.lastSignal(): ChildSignal? {
    val serverMillis = lastSeenServerAt?.toDate()?.time
    if (serverMillis != null && serverMillis > 0L) return ChildSignal(serverMillis, true)
    if (lastSeenAt > 0L) return ChildSignal(lastSeenAt, false)
    return null
}

/**
 * "12분 전" / "8월 7일 14:32" 같은 시각 표기를 한 곳에서 만든다.
 *
 * 관리 탭의 마지막 신호 한 줄과 연결 끊김 배너가 같은 사실을 가리키므로 표기가
 * 달라지면 안 된다. Locale 은 MapTimelineFragment 의 시각 표기와 맞춘다.
 */
object LastSignalText {

    private const val MINUTE_MILLIS = 60_000L
    private const val HOUR_MILLIS = 60 * MINUTE_MILLIS
    private const val DAY_MILLIS = 24 * HOUR_MILLIS

    private val clockFormat = SimpleDateFormat("M월 d일 HH:mm", Locale.KOREA)

    /**
     * "12분 전" / "8월 7일 14:32 (애기폰 시계 기준…)" 중 정직한 쪽을 고른다.
     *
     * 경과가 음수인 경우가 둘인데 뜻이 전혀 다르다.
     *
     * - **서버 시각으로 잰 값**이 음수라면 그 크기는
     *   [com.kidcare.family.core.FamilyRepository.serverNow] 의 왕복 보정 오차(수백
     *   밀리초)뿐이다. 실제로 방금 신호가 온 것이므로 "방금 전"이 정직하다.
     * - **아이 폰 시계로 잰 값**(옛 버전 자녀 폰)이 음수면 아이 폰 시계가 부모 폰보다
     *   앞서 있다는 뜻이고, 그 순간 우리는 그 신호가 얼마나 오래됐는지 **모른다.**
     *   이때 상대 표현을 쓰면 안 된다: 같은 화면의 다른 줄("응답하지 않아요",
     *   "12분 전 확인한 위치")과 서로를 부정해서 부모는 아무것도 알 수 없고 화면을
     *   덜 믿게 된다. 그래서 경과 대신 아이 폰이 적어 보낸 절대 시각을 그대로
     *   보여주고, 그 값이 정확하지 않다는 것도 함께 말한다.
     *
     * 관리 탭과 지도 탭이 같은 사실을 말하므로 이 판단은 여기 한 곳에만 있어야 한다.
     */
    fun relativeText(ctx: Context, signal: ChildSignal, elapsedMillis: Long): String =
        if (elapsedMillis < 0L && !signal.fromServerClock) {
            ctx.getString(R.string.control_last_seen_skewed_value, clockText(signal.atMillis))
        } else {
            elapsedText(ctx, elapsedMillis.coerceAtLeast(0L))
        }

    /** [elapsedMillis] 는 0 이상이어야 한다 — 음수의 뜻과 처리는 호출부가 정한다. */
    fun elapsedText(ctx: Context, elapsedMillis: Long): String = when {
        elapsedMillis < MINUTE_MILLIS -> ctx.getString(R.string.control_last_seen_now)
        elapsedMillis < HOUR_MILLIS -> ctx.getString(R.string.control_last_seen_minutes, elapsedMillis / MINUTE_MILLIS)
        elapsedMillis < DAY_MILLIS -> ctx.getString(R.string.control_last_seen_hours, elapsedMillis / HOUR_MILLIS)
        else -> ctx.getString(R.string.control_last_seen_days, elapsedMillis / DAY_MILLIS)
    }

    /** 상대 표현을 쓸 수 없을 때의 절대 시각. */
    fun clockText(atMillis: Long): String = clockFormat.format(Date(atMillis))
}
