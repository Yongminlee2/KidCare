package com.kidcare.family.guardian

import android.content.Context
import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import com.kidcare.family.R
import com.kidcare.family.core.AuthGateway
import com.kidcare.family.core.FamilyRepository
import com.kidcare.family.core.RoleStore
import com.kidcare.family.core.model.ChildStatusDoc
import com.kidcare.family.databinding.ActivityGuardianMainBinding
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 보호자 메인 컨테이너. 하단 탭이 프래그먼트를 갈아 끼운다.
 *
 * 지금 탭은 셋이다 — 지도(3단계), 관리·예약(4단계). 알림 탭은 events/ 가 생기는
 * 6단계에서 붙인다. 화면이 없는 탭을 미리 넣으면 눌러도 아무것도 없는 빈 탭이 되는데,
 * 그건 부모 눈에 그냥 고장이다.
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

    private val tabs = listOf(
        Tab(R.id.tab_map, TAG_MAP) { MapTimelineFragment() },
        Tab(R.id.tab_control, TAG_CONTROL) { ControlFragment() },
        Tab(R.id.tab_schedule, TAG_SCHEDULE) { ScheduleFragment() },
    )

    /** 지금 보이는 탭. 같은 탭으로 두 번 부르는 호출을 걸러내는 데 쓴다. */
    private var currentTabId: Int = 0

    /**
     * 아이 폰이 마지막으로 남긴 신호. null 이면 **아직 한 번도 받은 적이 없다**는
     * 뜻이고, 그때는 배너를 절대 띄우지 않는다 — 페어링을 아직 안 끝낸 부모에게
     * "연결이 끊겼어요"라고 말하는 것은 거짓말이다. 상태 문서가 한 번도 안 쓰인
     * 경우도 여기서 함께 걸러진다(`observeChildStatus` 는 문서가 없으면 콜백을
     * 부르지 않는다).
     */
    private var lastSignal: ChildSignal? = null

    /**
     * 배너를 주기적으로 다시 판정하는 코루틴.
     *
     * 이게 없으면 기능이 정확히 반대로 동작한다: 판정 재료가 "얼마나 오래됐는가"인데
     * 화면을 다시 그리는 계기가 Firestore 스냅샷뿐이면, **완전히 멎어서 아무 스냅샷도
     * 안 오는 폰**에서는 배너가 영영 안 뜬다. 조용해진 것을 알리는 것이 목적인데 조용해서
     * 못 알리는 셈이다. 그래서 시간이 흐르는 것만으로도 다시 판정한다.
     */
    private var bannerJob: Job? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityGuardianMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

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
        val startTabId = savedInstanceState?.getInt(KEY_SELECTED_TAB) ?: R.id.tab_map
        val startTab = tabs.firstOrNull { it.menuId == startTabId } ?: tabs.first()
        binding.bottomNav.selectedItemId = startTab.menuId
        // 위 대입이 선택 리스너를 부를 수도, (이미 그 항목이 선택돼 있었다면)
        // 재선택 리스너를 불러 그냥 지나갈 수도 있다 — 라이브러리 내부 사정이다.
        // showTab 은 몇 번을 불러도 결과가 같으므로(태그로 찾고 없을 때만 add)
        // 여기서 한 번 더 직접 불러 "첫 화면이 비어 있는" 경우를 원천봉쇄한다.
        showTab(startTab)
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
    }

    // ------------------------------------------------------------ 연결 끊김 배너

    /**
     * 프래그먼트가 자기 `observeChildStatus` 스냅샷을 받을 때마다 여기로 넘겨준다.
     *
     * **리스너를 여기서 새로 붙이지 않는 것이 핵심이다.** 지도 탭과 관리 탭이 이미
     * 각자 같은 문서를 구독하고 있어서, 액티비티가 하나 더 붙이면 같은 문서를 세 번
     * 읽게 된다(무료 한도 이야기는 docs/known-issues.md). 그래서 배너는 **이미 도는
     * 리스너가 밀어주는 값**으로만 산다 — 아이가 다시 신호를 보내면 그 스냅샷이
     * 여기로 들어와 배너가 저절로 사라진다.
     *
     * 지도 탭은 앱을 켜면 항상 만들어지는 첫 탭이고 show/hide 방식이라 탭을 옮겨도
     * 죽지 않는다. 그래서 부모가 관리 탭을 한 번도 안 열어도 이 값은 계속 들어온다.
     */
    fun reportChildStatus(status: ChildStatusDoc) {
        val signal = status.lastSignal() ?: return
        lastSignal = signal
        lifecycleScope.launch { renderBanner() }
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
     * 판정 재료는 [ChildStatusDoc.lastSeenServerAt] **서버 시각뿐이다.** 아이 폰 시계로
     * 적힌 옛 필드로 판정하면 아이 폰 시계가 30분만 뒤처져 있어도 멀쩡히 살아 있는 폰을
     * "끊겼다"고 신고한다 — 이 배너가 저지르면 안 되는 유일한 실수가 그거다(부모가
     * 한 번 헛걸음하면 다음부터 이 문구를 안 믿는다). 옛 버전을 깔고 있는 아이 폰은
     * 그동안 배너 대상이 아니고, 새 버전으로 한 번만 신호를 올리면 그때부터 대상이 된다.
     */
    private suspend fun renderBanner() {
        val signal = lastSignal
        if (signal == null || !signal.fromServerClock) {
            binding.disconnectBanner.visibility = View.GONE
            return
        }
        // 부모 폰 시계도 어긋날 수 있으므로 기준 시각은 서버 보정본을 쓴다
        // (FamilyRepository.serverNow — 프로세스당 한 번만 서버를 다녀온다).
        val now = try {
            FamilyRepository.serverNow(RoleStore(this).familyId, AuthGateway.currentUid())
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            System.currentTimeMillis()
        }
        val elapsed = now - signal.atMillis
        if (elapsed < DISCONNECT_THRESHOLD_MILLIS) {
            binding.disconnectBanner.visibility = View.GONE
            return
        }
        binding.disconnectBanner.visibility = View.VISIBLE
        binding.disconnectBanner.text = getString(
            R.string.guardian_disconnect_banner,
            LastSignalText.elapsedText(this, elapsed),
        )
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putInt(KEY_SELECTED_TAB, binding.bottomNav.selectedItemId)
    }

    private companion object {
        const val TAG_MAP = "tab_map"
        const val TAG_CONTROL = "tab_control"
        const val TAG_SCHEDULE = "tab_schedule"
        const val KEY_SELECTED_TAB = "selected_tab"

        /**
         * 이만큼 신호가 없으면 "끊겼다"고 본다.
         *
         * 30분인 이유: 아이 폰의 위치 보고 주기는 1분(이동 중)~5분(정지 중)이다
         * (child/TrackingService). 그러니 정상 동작 중이라면 30분은 여섯 주기가
         * 통째로 비어야 채워지는 시간이다. 반대로 이 값을 5~10분으로 잡으면
         * **지하철 터널, 절전 낮잠, Doze 창** 하나에도 배너가 뜬다 — 아무 문제 없는
         * 폰을 두고 "아이 폰을 열어보라"고 여러 번 시키면 부모는 이 문구를 곧
         * 무시하게 되고, 그러면 진짜로 강제 종료된 날에도 안 읽는다. 늦게 알리는
         * 쪽이 헛되이 알리는 쪽보다 낫다.
         */
        const val DISCONNECT_THRESHOLD_MILLIS = 30 * 60 * 1000L

        /** 시간이 흐른 것만으로 다시 판정하는 간격([bannerJob] 주석 참고). 30분
         *  기준에 대해 1분 오차면 충분하고, 1분에 한 번 도는 비용은 무시할 만하다. */
        const val BANNER_RECHECK_MILLIS = 60 * 1000L
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
