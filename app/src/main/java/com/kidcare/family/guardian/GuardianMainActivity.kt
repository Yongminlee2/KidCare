package com.kidcare.family.guardian

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.fragment.app.Fragment
import com.kidcare.family.R
import com.kidcare.family.databinding.ActivityGuardianMainBinding

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

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putInt(KEY_SELECTED_TAB, binding.bottomNav.selectedItemId)
    }

    private companion object {
        const val TAG_MAP = "tab_map"
        const val TAG_CONTROL = "tab_control"
        const val TAG_SCHEDULE = "tab_schedule"
        const val KEY_SELECTED_TAB = "selected_tab"
    }
}
