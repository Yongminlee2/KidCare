package com.kidcare.family.guardian

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.firebase.firestore.ListenerRegistration
import com.kidcare.family.R
import com.kidcare.family.core.EventRepository
import com.kidcare.family.core.RoleStore
import com.kidcare.family.core.errorMessage
import com.kidcare.family.core.model.EventDoc
import com.kidcare.family.databinding.FragmentAlertBinding
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * 알림 탭. `events/` 를 최신순으로 보여주고, 화면을 열면 읽음으로 바꾼다.
 *
 * 맨 위에 [AlertService] 스위치가 있다. 그 서비스가 왜 있고 켜면 무엇이 생기는지는
 * 그 클래스 주석에 있고, **부모에게 하는 설명은 `alert_service_hint` 한 줄**이다 —
 * 켜기 전에 대가(알림줄에 표시 하나, 배터리)를 먼저 말한다.
 *
 * ## 살구빛과 읽음 표시가 부딪히는 문제
 *
 * "안 읽은 것은 살구빛"과 "화면을 열면 읽음으로 바꾼다"를 곧이곧대로 붙이면 색이
 * 부모 눈에 닿기 전에 사라진다. 그래서 화면이 보이는 순간의 안 읽은 ID 를 따로
 * 붙들어 두고([highlight]) 그것으로 색을 칠한다. 탭을 떠나면 비운다 — 다음에 열 때는
 * 그 사이에 새로 온 것만 살구빛이어야 한다.
 *
 * ## 읽음 표시는 `read` 하나만 쓴다
 *
 * 규칙이 `hasOnly(['read'])` 라 다른 필드를 함께 쓰면 통째로 거부된다. 그 계약은
 * [EventRepository.markRead] 안에 갇혀 있고 이 화면은 ID 목록만 넘긴다.
 */
class AlertFragment : Fragment() {

    private var _binding: FragmentAlertBinding? = null

    private var listener: ListenerRegistration? = null
    private var familyId: String? = null

    private lateinit var adapter: AlertAdapter

    /** 마지막 스냅샷. 최신순으로 온다. */
    private var events: List<EventDoc> = emptyList()

    /** 목록을 불러왔는가. 세 상태를 왜 구분하는지는 [ListLoad] 주석에 있다. */
    private var listLoad = ListLoad.LOADING

    /** 이번에 화면을 열었을 때 안 읽은 상태였던 ID 들(클래스 주석). */
    private val highlight = mutableSetOf<String>()

    /** 읽음 표시 쓰기. 겹쳐 나가지 않게 하나로 묶는다. */
    private var markJob: Job? = null

    /** 지금 부모 눈앞에 있는가. 탭 전환과 앱 전환 둘 다 여기로 모인다. */
    private var visible = false

    /**
     * 안드로이드 13+ 의 알림 권한. **스위치를 켜기 직전에만** 물어본다.
     *
     * 이 권한이 없으면 서비스는 멀쩡히 도는데 알림이 시스템에서 조용히 버려진다 —
     * 부모 폰에는 상시 표시만 남고 정작 알림은 안 오는, 가장 나쁜 조합이다. 그래서
     * 거절당하면 스위치를 켜지 않고 왜 못 켜는지 적는다.
     */
    private val requestNotificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) {
                enableService()
            } else {
                renderSwitch()
                showState(getString(R.string.alert_notification_denied))
            }
        }

    /** [renderSwitch] 가 스위치에 값을 대입하는 동안 리스너가 도로 서비스를 껐다 켜지 못하게 막는다. */
    private var suppressSwitchCallback = false

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        val binding = FragmentAlertBinding.inflate(inflater, container, false)
        _binding = binding
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        val b = _binding ?: return

        adapter = AlertAdapter()
        b.alertList.layoutManager = LinearLayoutManager(requireContext())
        b.alertList.adapter = adapter

        b.serviceSwitch.setOnCheckedChangeListener { _, checked ->
            if (suppressSwitchCallback) return@setOnCheckedChangeListener
            showState(null)
            if (checked) askThenEnable() else disableService()
        }

        renderSwitch()
        renderList()
        subscribe()
    }

    private fun subscribe() {
        val roleStore = RoleStore(requireContext())
        val fid = roleStore.familyId
        if (fid == null) {
            // 구독을 시작조차 못 한다 = 목록을 못 불러온 것이다. 여기서 LOADING 으로
            // 두면 "불러오는 중이에요"가 영원히 떠 있는다.
            listLoad = ListLoad.FAILED
            showState(getString(R.string.alert_no_family))
            renderList()
            return
        }
        familyId = fid
        val selectedUid = roleStore.selectedChildUid
        if (selectedUid == null) {
            listLoad = ListLoad.LOADED
            showState(getString(R.string.map_no_child))
            renderList()
            return
        }
        listener = EventRepository.observeEvents(
            fid,
            childUid = selectedUid,
            onChange = { docs, fromCache -> onEventsChanged(docs, fromCache) },
            onError = { e ->
                val ctx = context ?: return@observeEvents
                _binding ?: return@observeEvents
                listLoad = ListLoad.FAILED
                showState(getString(R.string.alert_error_format, errorMessage(ctx, e)))
                renderList()
            },
        )
    }

    private fun onEventsChanged(docs: List<EventDoc>, fromCache: Boolean) {
        _binding ?: return
        events = docs
        // 캐시본으로는 LOADED 로 올리지 않는다. 오프라인에서 빈 목록에 "아직 온 알림이
        // 없어요"를 띄우면 부모는 그걸 "조용한 하루"로 읽는데, 진실은 "서버에 못
        // 물어봤다"다 — 이 앱이 제일 두려워하는 실패가 정확히 그 모양이다([ListLoad]).
        listLoad = if (fromCache) ListLoad.LOADING else ListLoad.LOADED
        // 화면이 보이는 동안 새로 온 것도 그 자리에서 읽음이 된다 — 부모가 보고 있는데
        // 안 읽음으로 남겨두면 알림줄에도 한 번 더 뜬다.
        if (visible) consumeUnread()
        renderList()
    }

    // ------------------------------------------------------------ 보임/숨김

    /**
     * 탭을 옮겨도 이 프래그먼트는 죽지 않는다([GuardianMainActivity] 가 show/hide 를
     * 쓴다). 그래서 탭 전환에서는 [onResume] 이 아니라 이 콜백이 불린다 —
     * [ScheduleFragment.onHiddenChanged] 와 같은 이유로 양쪽에 다 걸어둔다.
     */
    override fun onHiddenChanged(hidden: Boolean) {
        super.onHiddenChanged(hidden)
        setVisible(!hidden)
    }

    override fun onResume() {
        super.onResume()
        if (!isHidden) setVisible(true)
    }

    override fun onPause() {
        // 앱이 백그라운드로 내려간다. 이 순간부터는 부모가 목록을 보고 있지 않으므로
        // 서비스가 다시 알림을 띄워야 한다.
        setVisible(false)
        super.onPause()
    }

    private fun setVisible(nowVisible: Boolean) {
        if (visible == nowVisible) return
        visible = nowVisible
        AlertService.setListVisible(nowVisible)
        if (nowVisible) {
            // 눈으로 보고 있는 줄을 알림줄에서도 조르고 있을 이유가 없다. 스냅샷을
            // 기다리지 않고 지금 거둔다 — 왕복을 기다리면 그동안 알림이 그대로 남는다.
            context?.let { AlertService.cancelAlert(it.applicationContext) }
            consumeUnread()
        } else {
            highlight.clear()
        }
        renderList()
    }

    /**
     * 지금 안 읽은 것들을 강조 목록에 넣고 서버에 읽음으로 적는다.
     *
     * 쓰기가 실패해도(오프라인 등) 화면에는 아무 말도 하지 않는다. 부모가 방금 한 일이
     * 아니라 화면이 저 혼자 한 일이고, 대가는 "다음에 이 탭을 열면 한 번 더 시도한다"
     * 뿐이다 — 여기서 빨간 줄을 띄우면 부모는 자기가 뭘 잘못했는지 찾게 된다.
     */
    private fun consumeUnread() {
        val fid = familyId ?: return
        val ids = events.filter { !it.read }.map { it.id }
        if (ids.isEmpty()) return
        highlight += ids
        if (markJob?.isActive == true) return
        _binding ?: return
        markJob = viewLifecycleOwner.lifecycleScope.launch {
            try {
                EventRepository.markRead(fid, ids)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // 조용히 넘어가는 대신 흔적은 남긴다(adb logcat -s AlertFragment:W).
                Log.w(TAG, "읽음 표시 실패 — 다음에 다시 시도한다", e)
            }
        }
    }

    // ------------------------------------------------------------ 스위치

    private fun askThenEnable() {
        val ctx = context ?: return
        val needsPermission = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                ctx, Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED
        if (needsPermission) {
            requestNotificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
            return
        }
        enableService()
    }

    private fun enableService() {
        // 애플리케이션 컨텍스트를 넘긴다 — 서비스는 이 화면보다 오래 산다.
        val ctx = context?.applicationContext ?: return
        AlertService.setEnabled(ctx, true)
        renderSwitch()
    }

    private fun disableService() {
        val ctx = context?.applicationContext ?: return
        AlertService.setEnabled(ctx, false)
        renderSwitch()
    }

    // ------------------------------------------------------------ 그리기

    private fun renderSwitch() {
        val b = _binding ?: return
        val ctx = context ?: return
        // 화면의 정답은 프래그먼트 필드가 아니라 저장된 값이다(스위치를 켠 뒤 권한
        // 거절로 되돌아오는 길이 있어서, 뷰의 체크 상태를 믿으면 어긋난다).
        suppressSwitchCallback = true
        b.serviceSwitch.isChecked = AlertService.isEnabled(ctx)
        suppressSwitchCallback = false
    }

    private fun renderList() {
        val b = _binding ?: return
        adapter.setUnread(highlight.toSet())
        adapter.submitList(events)
        b.alertEmpty.renderEmptyState(
            b.alertEmptyText, listLoad, events.isEmpty(), R.string.alert_empty,
        )
    }

    /** 목록 위의 한 줄. null 이면 감춘다. */
    private fun showState(message: String?) {
        val b = _binding ?: return
        b.alertState.visibility = if (message == null) View.GONE else View.VISIBLE
        b.alertState.text = message.orEmpty()
    }

    override fun onDestroyView() {
        // 화면이 사라지는데 "보고 있다"가 남으면 서비스가 영영 알림을 안 띄운다.
        AlertService.setListVisible(false)
        visible = false
        listener?.remove()
        listener = null
        markJob?.cancel()
        markJob = null
        _binding?.serviceSwitch?.setOnCheckedChangeListener(null)
        _binding = null
        super.onDestroyView()
    }

    private companion object {
        const val TAG = "AlertFragment"
    }
}
