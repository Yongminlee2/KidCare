package com.kidcare.family.guardian

import android.annotation.SuppressLint
import android.content.res.ColorStateList
import android.graphics.PointF
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.MarginLayoutParams
import android.view.ViewConfiguration
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import androidx.core.content.ContextCompat
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.firebase.firestore.ListenerRegistration
import com.kidcare.family.R
import com.kidcare.family.core.AuthGateway
import com.kidcare.family.core.CommandRepository
import com.kidcare.family.core.FamilyRepository
import com.kidcare.family.core.RoleStore
import com.kidcare.family.core.TrailRepository
import com.kidcare.family.core.errorMessage
import com.kidcare.family.core.model.ChildStatusDoc
import com.kidcare.family.core.model.CommandState
import com.kidcare.family.core.model.CommandType
import com.kidcare.family.core.model.SegmentDoc
import com.kidcare.family.core.model.TrailPoint
import com.kidcare.family.databinding.FragmentMapTimelineBinding
import com.kidcare.family.logic.DayPicker
import com.kidcare.family.logic.Fix
import com.kidcare.family.logic.RoutePathRefiner
import com.kidcare.family.logic.RouteWindows
import com.kidcare.family.logic.SegmentSummarizer
import com.kidcare.family.logic.SegmentType
import com.naver.maps.geometry.LatLng
import com.naver.maps.geometry.LatLngBounds
import com.naver.maps.map.CameraAnimation
import com.naver.maps.map.CameraUpdate
import com.naver.maps.map.NaverMap
import com.naver.maps.map.OnMapReadyCallback
import com.naver.maps.map.overlay.CircleOverlay
import com.naver.maps.map.overlay.Marker
import com.naver.maps.map.overlay.OverlayImage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.time.ZoneId
import java.util.UUID
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * 보호자 메인. 네이버 지도 위에 아이의 위치를 찍고 그 아래에 하루 요약을 보여준다.
 *
 * ## "지금 위치"가 아니라 "마지막으로 확인한 위치"다
 *
 * 무료 한도 개편(docs/known-issues.md 12번) 전에는 아이 폰이 1~5분마다 상태 문서를
 * 덮어썼고 이 화면은 그걸 실시간 구독했다. 지금 아이 폰은 **부모가 물어볼 때와 하루
 * 한 번**만 올린다. 그래서 이 화면은 두 가지를 반드시 지킨다.
 *
 * 1. **묵은 위치를 지금 위치인 척 보여주지 않는다.** 상단 카드가 항상 "언제 확인한
 *    것인지"를 함께 말한다([renderStatus]).
 * 2. **물어보는 방법이 화면에 보인다.** '지금 위치 확인' 버튼이 `locate_now` 명령을
 *    보내고, 아이 폰이 대답하면 그때 다시 읽어 그린다([locateNow]).
 *
 * 상시 구독은 셋 다 없앴다(상태·구간·경로). 대신 화면을 열 때·날짜를 넘길 때·
 * 대답이 왔을 때 [FamilyRepository.fetchChildStatus] 와 [TrailRepository.fetch] 로
 * 한 번씩만 읽는다 — 읽기가 언제 몇 번 일어나는지가 코드에 그대로 보인다.
 *
 * 명령을 기다리는 동안에만 명령 문서 하나에 짧게 리스너를 붙인다. 세대 번호로
 * 밀린 명령의 콜백을 막는 규율은 [ControlFragment.commandGeneration] 과 같다 —
 * 그 이유는 저쪽 주석에 자세히 적혀 있다.
 *
 * 3단계 Task 5 가 지도 아래에 하루 요약 타임라인과 날짜 이동을 붙였다.
 * 3단계 Task 6 이 [drawRoute] 로 지도 위에 하루 경로 폴리라인을 붙였다.
 * 지도 엔진은 네이버 Mobile Dynamic Map SDK를 사용한다. 아이 위치 수집과 서버 기록은
 * 지도 SDK와 무관하며, 이 화면이 열릴 때만 네이버 지도를 사용한다.
 */
class MapTimelineFragment : Fragment(), OnMapReadyCallback {

    private var _binding: FragmentMapTimelineBinding? = null
    private val binding get() = _binding!!

    // 아이 위치 마커. 처음 생길 때만 카메라를 이동시키기 위해 null 여부로
    // "이미 그린 적 있는가"를 판정한다 — 아래 renderStatus() 참고.
    private var naverMap: NaverMap? = null
    private var childMarker: Marker? = null

    // 마커 주변에 그리는 오차 원. 마커와 따로 들고 있어야 갱신할 때 이전 원만
    // 골라 지울 수 있다(routeLine 과 같은 규율).
    private var accuracyCircle: CircleOverlay? = null
    private var routeOverlay: GradientRouteOverlay? = null
    private var routeSections: List<RouteSection> = emptyList()
    private val hiddenRouteStarts = mutableSetOf<Long>()
    private var lastRouteLegs: List<List<LatLng>> = emptyList()
    private var lastRoutePositions: List<LatLng> = emptyList()
    private var lastMapStatus: ChildStatusDoc? = null

    // 자녀가 members 에 들어오는 순간을 계속 지켜본다(known-issues 3): 부모가 이 화면을
    // 켜 둔 채로 아이가 페어링을 끝내면, 한 번 조회 방식에서는 화면을 다시 만들기
    // 전까지 "연결 안 됨"이 안 풀린다. 이건 상태·경로 구독과 성격이 다르다 — members
    // 는 페어링 때 한 번 바뀌고 그 뒤로 조용해서 읽기가 늘지 않는다.
    private var joinedListener: ListenerRegistration? = null

    /** 화면을 열 때·날짜를 넘길 때·대답이 왔을 때 도는 한 번 읽기. */
    private var loadJob: Job? = null

    /**
     * 아래 타임라인을 불러왔는가. 목록 화면 셋과 같은 판정을 쓴다([ListLoad]).
     *
     * 예전에는 `docs.isEmpty()` 하나로 "이 날은 기록이 없어요"를 띄웠다. 그래서 못
     * 읽은 날과 정말 안 걸어 다닌 날이 **같은 말을 했다** — 오프라인에서 어제로
     * 넘기면(캐시에 없는 날) 아이가 하루 종일 걸어 다닌 날에 대고 "기록이 없어요"라고
     * 말한다. 목록 화면 셋이 이미 고친 결함인데 이 화면만 남아 있었다.
     */
    private var timelineLoad = ListLoad.LOADING

    /** 명령을 보낸 뒤 대답이 올 때까지만 붙어 있는 리스너와 그 60초 타이머. */
    private var commandListener: ListenerRegistration? = null
    private var timeoutJob: Job? = null
    private var commandGeneration = 0

    /** 실시간 보기 명령과 상태 문서 구독은 기존 '지금 위치 확인' 명령과 독립적으로 관리한다. */
    private var liveCommandListener: ListenerRegistration? = null
    private var liveStatusListener: ListenerRegistration? = null
    private var liveCommandTimeoutJob: Job? = null
    private var liveSessionTimeoutJob: Job? = null
    private var liveCommandGeneration = 0
    private var liveTrackingActive = false
    private var liveTrackingBusy = false
    private var liveBaselineAt = Long.MIN_VALUE
    private var liveSessionId: String? = null

    // 기기 시간대를 한 번만 읽어 고정한다 — 화면이 떠 있는 동안 시간대가 바뀌는 일은
    // 실질적으로 없고, DayPicker 를 부를 때마다 매번 물어보면 호출부만 늘어난다.
    private val zone: ZoneId = ZoneId.systemDefault()
    private var dayKey: String = DayPicker.todayKey(zone, System.currentTimeMillis())

    // joinedListener 의 onJoined 가 채운다. 날짜를 넘길 때(changeDay)는 이 값을
    // 그대로 재사용하고 다시 조회하지 않는다.
    private var childUid: String? = null
    private lateinit var timelineAdapter: TimelineAdapter
    private var timelineExpanded = false
    /** 접었다 다시 펼쳐도 사용자가 드래그해 정한 높이를 되살리기 위한 콘텐츠 높이. */
    private var lastExpandedTimelineHeight = 0
    private var focusChildOnNextLoad = false
    private var routeSummaryBaseText: CharSequence = ""

    /** 연결 끊김 배너의 판정 재료를 적는 곳([RequestLog], DisconnectRule 주석 참고). */
    private val requestLog by lazy { RequestLog(requireContext().applicationContext) }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        _binding = FragmentMapTimelineBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        timelineExpanded = savedInstanceState?.getBoolean(KEY_TIMELINE_EXPANDED) ?: false
        lastExpandedTimelineHeight = savedInstanceState
            ?.getInt(KEY_TIMELINE_CONTENT_HEIGHT)
            ?.takeIf { it > 0 }
            ?: dp(DEFAULT_TIMELINE_CONTENT_HEIGHT_DP)

        // 지도만 상태바 뒤까지 그리고, 그 위에 뜬 상태 카드는 상태바 아래로 내린다.
        // 레이아웃에 적힌 12dp 여백에 상태바 높이를 **더한다** — 덮어쓰면 상태바가
        // 없는 화면에서 카드가 위에 딱 붙는다.
        val cardBaseTopMargin = (binding.statusCard.layoutParams as MarginLayoutParams).topMargin
        ViewCompat.setOnApplyWindowInsetsListener(binding.statusCard) { v, insets ->
            val top = insets.getInsets(WindowInsetsCompat.Type.systemBars()).top
            v.updateLayoutParams<MarginLayoutParams> { topMargin = cardBaseTopMargin + top }
            insets
        }

        // 타임라인은 지도와 무관하다. 아직 childUid 를 못 구한 첫 실행 구간에서 화면이
        // "아무 설명 없이 텅 빈 채로" 남으면 고장으로 읽히므로, 읽기 결과를 기다리지
        // 않고 여기서 빈 목록으로 한 번 먼저 그려 empty 안내부터 보여준다.
        timelineAdapter = TimelineAdapter(zone) { doc ->
            if (doc.type == SegmentType.MOVE.name) toggleRoute(doc)
            else focusOn(doc.lat, doc.lng)
        }
        binding.timelineList.layoutManager = LinearLayoutManager(
            requireContext(), LinearLayoutManager.HORIZONTAL, false,
        )
        binding.timelineList.adapter = timelineAdapter
        renderTimeline(emptyList())
        binding.prevDayButton.setOnClickListener { changeDay(-1) }
        binding.nextDayButton.setOnClickListener { changeDay(1) }
        binding.timelineToggleButton.setOnClickListener {
            timelineExpanded = !timelineExpanded
            renderTimelinePanel()
        }
        bindTimelineDragHandle()
        binding.routeVisibilityButton.setOnClickListener { toggleAllRoutes() }
        binding.mapChildSelector.setOnClickListener {
            (activity as? GuardianMainActivity)?.showChildMenuFrom(it)
        }
        binding.statusDetails.setOnClickListener { showBatteryInfo() }
        binding.locateButton.setOnClickListener { locateNow() }
        binding.liveTrackingButton.setOnClickListener {
            if (liveTrackingActive || liveTrackingBusy) stopLiveTracking()
            else startLiveTracking()
        }
        setLocateButtonEnabled(false)
        renderLiveTrackingState()
        binding.statusBar.text = getString(R.string.map_no_child)
        renderDayHeader()
        renderTimelinePanel()
        refreshSelectedChildHeader()

        binding.mapView.onCreate(savedInstanceState)
        binding.mapView.getMapAsync(this)
        subscribe()
    }

    override fun onMapReady(map: NaverMap) {
        val b = _binding ?: return
        if (!isAdded) return
        naverMap = map
        map.uiSettings.apply {
            isZoomControlEnabled = false
            isLocationButtonEnabled = false
            isScaleBarEnabled = false
            logoGravity = Gravity.START or Gravity.BOTTOM
        }
        postForCurrentView(b.timelinePanel) { updateMapControls() }
        renderMapStatus()
        renderRouteOverlay()
        if (timelineExpanded) postForCurrentView(b.mapView) { fitWholeRoute() }
    }

    fun refreshSelectedChildHeader() {
        val b = _binding ?: return
        b.childName.text = (activity as? GuardianMainActivity)?.selectedChildLabelText()
            ?: getString(R.string.child_default_name)
    }

    private fun showBatteryInfo() {
        MaterialAlertDialogBuilder(requireContext())
            .setTitle(R.string.map_battery_info_title)
            .setMessage(R.string.map_battery_info_message)
            .setPositiveButton(R.string.map_battery_info_confirm, null)
            .show()
    }

    /**
     * 자녀 uid 를 계속 지켜본다. `findChildUid` 를 한 번만 부르던 옛 방식은 부모가
     * 지도를 켜 둔 채로 아이가 페어링을 끝내면 화면을 다시 만들기 전까지
     * "연결 안 됨"이 풀리지 않았다(known-issues 3).
     */
    private fun subscribe() {
        val roleStore = RoleStore(requireContext())
        val familyId = roleStore.familyId ?: return
        joinedListener = FamilyRepository.observeChildJoined(
            familyId,
            preferredChildUid = roleStore.selectedChildUid,
            onJoined = { uid ->
                // 자기 멤버 문서가 바뀔 때마다 이 콜백이 같은 uid 로 다시 불릴 수 있다.
                // uid 가 그대로면 다시 읽을 이유가 없다 — 매번 다시 읽으면 그게 곧
                // 무료 한도를 갉아먹는 읽기다.
                if (uid == childUid) return@observeChildJoined
                stopLiveTracking(targetUid = childUid)
                clearMapForChildSwitch()
                childUid = uid
                _binding ?: return@observeChildJoined
                // 화면 생성 때는 childUid가 아직 없어 실시간 토글이 비활성이다. 자녀를
                // 비동기로 찾은 뒤 현재 위치 버튼만 켜면 토글은 계속 흐린 채 눌리지 않는다.
                // 두 컨트롤의 활성 상태를 같은 함수에서 다시 계산한다.
                renderLiveTrackingState()
                load(familyId, uid)
            },
            onError = { e ->
                // Firestore 콜백은 화면이 사라진 뒤에도 한 번 더 올 수 있다. requireContext()
                // 도 getString() 도 그때 부르면 그대로 예외라 둘 다 먼저 확인한다.
                _binding ?: return@observeChildJoined
                val ctx = context ?: return@observeChildJoined
                showError(ctx.getString(R.string.map_error, errorMessage(ctx, e)))
            },
        )
    }

    // ------------------------------------------------------------------ 한 번 읽기

    /**
     * 마지막으로 확인된 상태와 그 날의 경로를 **각각 한 번씩** 읽어 그린다.
     * 읽기 2회가 전부다.
     */
    private fun load(familyId: String, uid: String) {
        // Firestore 콜백에서도 불린다 — 화면이 사라진 뒤에 viewLifecycleOwner 를
        // 만지면 그 자리에서 IllegalStateException 이다.
        _binding ?: return
        loadJob?.cancel()
        timelineLoad = ListLoad.LOADING
        loadJob = viewLifecycleOwner.lifecycleScope.launch {
            try {
                val status = FamilyRepository.fetchChildStatus(familyId, uid)
                val trail = TrailRepository.fetch(familyId, uid, dayKey)
                _binding ?: return@launch
                // 타임라인을 먼저 그린다. renderStatus 는 서버 시각 보정을 기다리는
                // suspend 함수라(FamilyRepository.serverNow) 통신이 느리면 그 자리에서
                // 몇 초를 쉰다 — 뒤에 두면 이미 손에 든 하루 기록이 그 시간만큼 화면에
                // 안 나오고, 그동안 화면은 옛 날짜의 목록을 그대로 보여준다.
                timelineLoad = ListLoad.LOADED
                renderTimeline(
                    trail?.segments ?: emptyList(),
                    trail?.points ?: emptyList(),
                )
                renderStatus(status)
            } catch (e: CancellationException) {
                // 화면을 떠났거나 다음 읽기가 이 읽기를 밀어낸 것이다. 실패가 아니다.
                throw e
            } catch (e: Exception) {
                val ctx = context ?: return@launch
                // 못 읽었으면 빈 자리에 "이 날은 기록이 없어요"를 띄우지 않는다 —
                // 이유는 위 [timelineLoad] 주석. 목록 자체는 건드리지 않는다(직전에
                // 성공한 날의 목록이 남아 있을 수 있고, 날짜를 넘긴 경우라면 changeDay
                // 가 이미 비워 뒀다).
                timelineLoad = ListLoad.FAILED
                renderTimelineEmpty(timelineAdapter.itemCount == 0)
                showError(getString(R.string.timeline_error, errorMessage(ctx, e)))
            }
        }
    }

    private fun reload() {
        val ctx = context ?: return
        val familyId = RoleStore(ctx).familyId ?: return
        val uid = childUid ?: return
        load(familyId, uid)
    }

    // ------------------------------------------------------------------ 지금 위치 확인

    /**
     * '지금 위치 확인'. 아이 폰에 `locate_now` 명령을 보내고, 대답이 올 때까지만
     * 그 명령 문서 하나에 리스너를 붙인다.
     *
     * 리스너를 `done`/`failed` 에서 곧바로 뗀다. 이 리스너는 "지금 이 물음의 답"만
     * 기다리는 것이고, 답이 온 뒤에도 남겨두면 상시 구독을 없앤 의미가 사라진다
     * (관리 탭은 늦게 오는 done 을 기다리느라 일부러 안 떼는데, 여기는 답이 온
     * 즉시 [reload] 로 문서를 다시 읽으므로 남겨둘 이유가 없다).
     *
     * 60초 무응답 표시는 관리 탭과 같은 규칙이다(설계서 §5). 그때 리스너와 타이머를
     * 정리하되 [RequestLog] 에는 대답을 적지 않는다 — 그래야 30분 뒤 연결 끊김
     * 배너가 이 무응답을 근거로 뜰 수 있다.
     */
    private fun locateNow() {
        val familyId = RoleStore(requireContext()).familyId
        val uid = childUid
        if (familyId == null || uid == null) {
            showError(getString(R.string.map_no_child))
            return
        }
        stopTracking()
        // 발행 결과를 기다리는 동안 부모가 버튼을 또 누를 수 있다. 지금 이 순간의
        // 세대를 붙잡아 두고, 왕복이 끝난 뒤 그 값이 아직 최신인지로 판단한다
        // ([ControlFragment.commandGeneration] 주석에 이 규율의 근거가 있다).
        val generation = ++commandGeneration
        requestLog.recordRequest(uid)
        renderLocating(true)

        viewLifecycleOwner.lifecycleScope.launch {
            try {
                // 제한시간의 이유는 [ControlFragment.SEND_TIMEOUT_MILLIS] 와 같다:
                // 오프라인이면 이 await 가 영영 안 돌아와 track() 도 60초 타이머도
                // 시작되지 않고, 화면은 "위치를 확인하는 중이에요…"와 도는 스피너에
                // 영원히 갇힌다. 끊어도 명령 문서는 큐에 남아 연결되면 그대로 나간다.
                val commandId = withTimeoutOrNull(SEND_TIMEOUT_MILLIS) {
                    CommandRepository.send(familyId, uid, CommandType.LOCATE_NOW)
                }
                _binding ?: return@launch
                if (generation != commandGeneration) return@launch
                if (commandId == null) {
                    renderLocating(false)
                    showError(getString(R.string.control_command_queued))
                    return@launch
                }
                track(familyId, uid, commandId, generation)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (generation != commandGeneration) return@launch
                val ctx = context ?: return@launch
                renderLocating(false)
                showError(errorMessage(ctx, e))
            }
        }
    }

    private fun track(familyId: String, uid: String, commandId: String, generation: Int) {
        stopTracking()
        commandListener = CommandRepository.observeOne(
            familyId, uid, commandId,
            onChange = { doc ->
                if (generation != commandGeneration) return@observeOne
                // remove() 는 "앞으로 오지 마라"는 뜻이지 이미 큐에 올라간 콜백까지
                // 되돌리지는 않는다. 화면이 사라진 뒤라면 여기서 멈춘다.
                _binding ?: return@observeOne
                when (doc.state) {
                    CommandState.DONE -> {
                        stopTracking()
                        recordAnswer()
                        renderLocating(false)
                        focusChildOnNextLoad = true
                        reload()
                    }
                    CommandState.FAILED -> {
                        stopTracking()
                        // 실패도 대답이다 — 아이 폰이 살아 있으니 error 를 적을 수 있었다.
                        recordAnswer()
                        renderLocating(false)
                        showError(childErrorText(doc.error))
                    }
                    else -> Unit
                }
            },
            onError = { e ->
                if (generation != commandGeneration) return@observeOne
                _binding ?: return@observeOne
                val ctx = context ?: return@observeOne
                stopTracking()
                renderLocating(false)
                showError(errorMessage(ctx, e))
            },
        )
        timeoutJob = viewLifecycleOwner.lifecycleScope.launch {
            delay(COMMAND_TIMEOUT_MILLIS)
            if (generation != commandGeneration) return@launch
            _binding ?: return@launch
            stopTracking()
            renderLocating(false)
            showError(getString(R.string.control_command_timeout))
        }
    }

    private fun stopTracking() {
        commandListener?.remove()
        commandListener = null
        timeoutJob?.cancel()
        timeoutJob = null
    }

    private fun startLiveTracking() {
        val familyId = RoleStore(requireContext()).familyId ?: run {
            showError(getString(R.string.map_no_child))
            return
        }
        val uid = childUid ?: run {
            showError(getString(R.string.map_no_child))
            return
        }

        stopLiveCommandTracking()
        val generation = ++liveCommandGeneration
        val sessionId = UUID.randomUUID().toString()
        liveSessionId = sessionId
        liveTrackingBusy = true
        liveBaselineAt = lastMapStatus?.at ?: Long.MIN_VALUE
        renderLiveTrackingState()
        binding.statusBar.text = getString(R.string.map_live_connecting)

        viewLifecycleOwner.lifecycleScope.launch {
            try {
                val commandId = withTimeoutOrNull(SEND_TIMEOUT_MILLIS) {
                    CommandRepository.send(
                        familyId,
                        uid,
                        CommandType.START_LIVE_TRACKING,
                        mapOf(
                            CommandType.PAYLOAD_DURATION_SECONDS to
                                LIVE_SESSION_DURATION_SECONDS.toString(),
                            CommandType.PAYLOAD_SESSION_ID to sessionId,
                        ),
                    )
                }
                if (_binding == null || generation != liveCommandGeneration) return@launch
                if (commandId == null) {
                    failLiveStart(getString(R.string.control_command_queued))
                    return@launch
                }
                trackLiveStart(familyId, uid, commandId, generation)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (generation != liveCommandGeneration) return@launch
                val ctx = context ?: return@launch
                failLiveStart(errorMessage(ctx, e))
            }
        }
    }

    private fun trackLiveStart(
        familyId: String,
        uid: String,
        commandId: String,
        generation: Int,
    ) {
        stopLiveCommandTracking()
        liveCommandListener = CommandRepository.observeOne(
            familyId,
            uid,
            commandId,
            onChange = { doc ->
                if (_binding == null || generation != liveCommandGeneration) return@observeOne
                when (doc.state) {
                    CommandState.DONE -> beginLiveStatusSubscription(familyId, uid, generation)
                    CommandState.FAILED -> failLiveStart(childErrorText(doc.error))
                    else -> Unit
                }
            },
            onError = { error ->
                if (_binding == null || generation != liveCommandGeneration) return@observeOne
                val ctx = context ?: return@observeOne
                failLiveStart(errorMessage(ctx, error))
            },
        )
        liveCommandTimeoutJob = viewLifecycleOwner.lifecycleScope.launch {
            delay(COMMAND_TIMEOUT_MILLIS)
            if (generation != liveCommandGeneration || _binding == null) return@launch
            failLiveStart(getString(R.string.control_command_timeout))
        }
    }

    private fun beginLiveStatusSubscription(familyId: String, uid: String, generation: Int) {
        stopLiveCommandTracking()
        liveTrackingBusy = false
        liveTrackingActive = true
        renderLiveTrackingState()
        binding.statusBar.text = getString(R.string.map_live_waiting)

        liveStatusListener?.remove()
        liveStatusListener = FamilyRepository.observeChildStatus(
            familyId,
            uid,
            onChange = { status ->
                if (_binding == null || generation != liveCommandGeneration ||
                    !liveTrackingActive
                ) return@observeChildStatus
                // 구독 직후 되돌아오는 과거 문서는 실시간 위치처럼 표시하지 않는다.
                if (status == null || status.at <= liveBaselineAt) {
                    binding.statusBar.text = getString(R.string.map_live_waiting)
                    return@observeChildStatus
                }
                lastMapStatus = status
                binding.statusBar.text = getString(
                    R.string.map_live_active_status,
                    status.accuracy.coerceAtLeast(0f).roundToInt(),
                    status.battery,
                )
                renderMapStatus()
            },
            onError = { error ->
                if (_binding == null || generation != liveCommandGeneration) return@observeChildStatus
                val ctx = context ?: return@observeChildStatus
                showError(errorMessage(ctx, error))
            },
        )

        liveSessionTimeoutJob?.cancel()
        liveSessionTimeoutJob = viewLifecycleOwner.lifecycleScope.launch {
            delay(LIVE_SESSION_DURATION_SECONDS * 1_000L)
            if (generation != liveCommandGeneration || !liveTrackingActive) return@launch
            stopLiveTracking()
            showError(getString(R.string.map_live_timeout))
        }
    }

    private fun failLiveStart(message: String) {
        stopLiveTracking()
        showError(message)
    }

    /**
     * 화면의 실시간 구독을 즉시 끄고 아이 폰에도 종료 명령을 보낸다.
     * 아이 폰은 종료 명령을 못 받더라도 자체 10분 제한으로 원래 수집 주기로 돌아간다.
     */
    private fun stopLiveTracking(
        sendCommand: Boolean = true,
        targetUid: String? = childUid,
    ) {
        val wasRunning = liveTrackingActive || liveTrackingBusy
        val sessionId = liveSessionId
        liveSessionId = null
        ++liveCommandGeneration
        liveTrackingActive = false
        liveTrackingBusy = false
        stopLiveCommandTracking()
        liveStatusListener?.remove()
        liveStatusListener = null
        liveSessionTimeoutJob?.cancel()
        liveSessionTimeoutJob = null
        renderLiveTrackingState()

        if (wasRunning && _binding != null) {
            binding.statusBar.text = getString(R.string.map_live_stopped)
        }

        if (!sendCommand || !wasRunning || targetUid == null) return
        val familyId = context?.let { RoleStore(it).familyId } ?: return
        lifecycleScope.launch {
            try {
                withTimeoutOrNull(SEND_TIMEOUT_MILLIS) {
                    CommandRepository.send(
                        familyId,
                        targetUid,
                        CommandType.STOP_LIVE_TRACKING,
                        sessionId?.let { mapOf(CommandType.PAYLOAD_SESSION_ID to it) }
                            ?: emptyMap(),
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "실시간 종료 명령 전송 실패", e)
            }
        }
    }

    private fun stopLiveCommandTracking() {
        liveCommandListener?.remove()
        liveCommandListener = null
        liveCommandTimeoutJob?.cancel()
        liveCommandTimeoutJob = null
    }

    private fun renderLiveTrackingState() {
        val b = _binding ?: return
        val label = when {
            liveTrackingBusy -> R.string.map_live_button_connecting
            liveTrackingActive -> R.string.map_live_stop
            else -> R.string.map_live_start
        }
        val description = when {
            liveTrackingBusy -> R.string.map_live_cancel_description
            liveTrackingActive -> R.string.map_live_stop_description
            else -> R.string.map_live_start_description
        }
        val background = when {
            liveTrackingBusy -> R.color.apricot
            liveTrackingActive -> R.color.grass
            else -> R.color.paper_card
        }
        val foreground = when {
            liveTrackingBusy || liveTrackingActive -> R.color.on_accent
            else -> R.color.ink_soft
        }
        val stroke = if (liveTrackingActive || liveTrackingBusy) background else R.color.line
        b.liveTrackingButton.setText(label)
        b.liveTrackingButton.contentDescription = getString(description)
        b.liveTrackingButton.isEnabled = childUid != null
        b.liveTrackingButton.alpha = if (b.liveTrackingButton.isEnabled) 1f else 0.55f
        b.liveTrackingButton.backgroundTintList = ColorStateList.valueOf(
            ContextCompat.getColor(requireContext(), background),
        )
        b.liveTrackingButton.setTextColor(ContextCompat.getColor(requireContext(), foreground))
        b.liveTrackingButton.iconTint = ColorStateList.valueOf(
            ContextCompat.getColor(requireContext(), foreground),
        )
        b.liveTrackingButton.strokeColor = ColorStateList.valueOf(
            ContextCompat.getColor(requireContext(), stroke),
        )
        setLocateButtonEnabled(childUid != null && !liveTrackingActive && !liveTrackingBusy)
    }

    /** 아이 폰이 대답했다는 사실을 남기고 배너를 즉시 다시 판정하게 한다. */
    private fun recordAnswer() {
        childUid?.let { requestLog.recordAnswer(it) }
        (activity as? GuardianMainActivity)?.refreshBanner()
    }

    /**
     * 자녀 폰이 `error` 필드에 남긴 값은 사람이 읽는 문장이 아니라 코드다
     * (child/CommandHandler 가 적는다). 그대로 보여주지 않고 한국어로 바꾼다.
     */
    private fun childErrorText(raw: String): String = when (raw) {
        CommandType.ERROR_NO_FIX -> getString(R.string.map_locate_no_fix)
        else -> getString(R.string.control_error_child_failed)
    }

    // ------------------------------------------------------------------ 그리기

    private fun renderLocating(busy: Boolean) {
        val b = _binding ?: return
        b.locateProgress.visibility = if (busy) View.VISIBLE else View.GONE
        // 물어보는 중에 또 물어보면 명령 문서만 하나 더 만들어져 쓰기 예산을 깎는다.
        setLocateButtonEnabled(
            !busy && childUid != null && !liveTrackingActive && !liveTrackingBusy,
        )
        if (busy) b.statusBar.text = getString(R.string.map_locating)
    }

    /** MaterialCardView로 바꾼 현재위치 버튼의 비활성 상태도 눈에 보이게 맞춘다. */
    private fun setLocateButtonEnabled(enabled: Boolean) {
        val button = _binding?.locateButton ?: return
        button.isEnabled = enabled
        button.alpha = if (enabled) 1f else 0.48f
    }

    private fun showError(message: String) {
        _binding?.statusBar?.text = message
    }

    /**
     * 상단 카드와 지도 마커. **언제 확인한 위치인지를 반드시 함께 말한다.**
     *
     * 이 화면이 저지르면 안 되는 유일한 실수가 "묵은 위치를 지금 위치처럼 보여주는
     * 것"이다. 예전에는 아이 폰이 1~5분마다 올려서 화면의 점이 사실상 현재였지만,
     * 지금은 부모가 마지막으로 물어본 그 순간의 점이다 — 아침에 확인한 위치가 저녁에
     * 그대로 떠 있을 수 있다.
     *
     * 경과 계산의 기준 시각은 [FamilyRepository.serverNow] 다. 부모 폰 시계가
     * 뒤처져 있으면 [System.currentTimeMillis] 로 뺀 값이 음수가 돼 "-3분 전"이
     * 찍힌다. 음수가 나올 수 있는 나머지 경우의 처리는
     * [LastSignalText.relativeText] 가 맡는다.
     */
    private suspend fun renderStatus(status: ChildStatusDoc?) {
        val b = _binding ?: return
        val signal = status?.lastSignal()
        if (status == null || signal == null) {
            b.statusBar.text = getString(R.string.map_status_never)
            lastMapStatus = null
            renderMapStatus()
            return
        }
        val now = FamilyRepository.serverNow(
            RoleStore(requireContext()).familyId, AuthGateway.currentUid(),
        )
        // 여기서부터는 붙잡아 둔 Context 로만 문자열을 만든다 — 위 한 줄에서 화면을
        // 떠났을 수 있고, Fragment.getString 은 화면이 떨어져 나간 뒤에 부르면 그대로
        // 예외다. serverNow 는 오프셋이 캐시돼 있으면 정지점 없이 곧장 돌아오므로
        // 코루틴 취소만 믿을 수 없다(ControlFragment.onTimedOut 과 같은 함정).
        _binding ?: return
        val ctx = context ?: return
        val elapsed = now - signal.atMillis

        // 부모가 마지막으로 물어본 **뒤에** 쓰인 상태 문서라면 그 자체가 "애기폰이
        // 살아 있다"는 대답이다(늦게 살아난 폰의 안전 업로드일 수도 있다). 이걸 안
        // 보면, 서버에 이미 새 기록이 올라와 있는데도 연결 끊김 배너가 옛 물음을
        // 근거로 계속 뜬다. 서버 시각과 기기 시각을 직접 비교하지 않고 경과 시간을
        // 기기 시각으로 되돌려 비교한다 — 두 시계의 어긋남이 안 섞이게.
        if (System.currentTimeMillis() - elapsed > requestLog.lastRequestAt(childUid)) recordAnswer()

        b.statusBar.text = ctx.getString(
            R.string.map_status_format,
            status.battery,
            LastSignalText.relativeText(ctx, signal, elapsed),
        )

        lastMapStatus = status
        renderMapStatus()
    }

    /** 네이버 지도가 비동기로 준비되므로 상태를 보관했다가 준비 직후에도 다시 그린다. */
    private fun renderMapStatus() {
        val map = naverMap ?: return
        val status = lastMapStatus
        if (status == null || !status.lat.isFinite() || !status.lng.isFinite()) {
            childMarker?.map = null
            childMarker = null
            accuracyCircle?.map = null
            accuracyCircle = null
            return
        }

        val point = LatLng(status.lat, status.lng)
        drawAccuracyCircle(point, status.accuracy)
        val marker = childMarker
        val shouldFocusChild = marker == null || focusChildOnNextLoad || liveTrackingActive
        if (marker == null) {
            val ctx = context ?: return
            val newMarker = Marker()
            newMarker.icon = OverlayImage.fromBitmap(ChildMarkerFactory.create(ctx))
            // 마커 아이콘의
            // 가로 중앙·세로 맨 아래가 실제 좌표를 가리키게 한다(핀 모양 아이콘 전제).
            newMarker.anchor = PointF(0.5f, 1.0f)
            newMarker.position = point
            newMarker.map = map
            childMarker = newMarker
            // 카메라는 마커가 "처음 생길 때"만 움직인다 — 이후 갱신에서는 부모가 이미
            // 지도를 옮겨봤을 수 있으니 시점을 뺏지 않는다.
        } else {
            marker.position = point
        }
        if (shouldFocusChild) {
            val update = if (liveTrackingActive) {
                CameraUpdate.scrollTo(point).animate(CameraAnimation.Linear, 500)
            } else {
                CameraUpdate.scrollAndZoomTo(point, CHILD_FOCUS_ZOOM)
            }
            map.moveCamera(update)
            focusChildOnNextLoad = false
        }
    }

    /**
     * 현재 위치 마커 둘레에 오차 원을 그린다.
     *
     * 지도에 점 하나만 찍으면 그 점이 얼마나 믿을 만한지가 화면에서 완전히 사라진다 —
     * 오차 12m 짜리 fix 와 90m 짜리 fix 가 **똑같이 확신에 찬 핀 하나**로 보인다.
     * `ChildStatusDoc` 은 이미 accuracy 를 싣고 올라오므로 저장 형식도, 보안 규칙도
     * 건드릴 필요가 없다 — 있는 값을 안 보여주고 있었을 뿐이다.
     *
     * 그리는 규칙:
     *  - **불확실성으로 읽혀야지 지오펜스나 강조로 읽히면 안 된다.** 옅은 채움에
     *    가는 테두리를 쓰고 마커보다 낮은 Z 인덱스에 넣는다.
     *  - **최소 크기를 강제하지 않는다.** 오차가 작아 지금 배율에서 원이 안 보이면
     *    그게 맞는 결과다. 좋은 fix 를 억지로 큰 원으로 부풀리는 것은 그 자체가
     *    또 다른 거짓말이다.
     *  - accuracy 가 0 이면 아예 안 그린다. 0 은 "오차 없음"이 아니라 **모른다**는
     *    뜻이다(옛 문서·기기가 값을 안 줄 때 0 으로 읽힌다). 모르는 것을 완벽한
     *    것처럼 그리면 안 된다.
     */
    private fun drawAccuracyCircle(center: LatLng, accuracyMeters: Float) {
        val map = naverMap ?: return

        accuracyCircle?.map = null
        accuracyCircle = null

        if (accuracyMeters <= 0f) return

        val circle = CircleOverlay(center, accuracyMeters.toDouble()).apply {
            color = ACCURACY_FILL_COLOR
            outlineColor = ACCURACY_STROKE_COLOR
            outlineWidth = dp(ACCURACY_STROKE_WIDTH_DP)
            globalZIndex = ACCURACY_Z_INDEX
            this.map = map
        }
        accuracyCircle = circle
    }

    /** "이전 날"/"다음 날" 버튼. 미래로는 못 가게 막는다 — 볼 데이터가 없는 날이다. */
    private fun changeDay(days: Long) {
        val candidate = DayPicker.shift(dayKey, days)
        // 미래 날짜는 볼 것이 없다. 버튼을 눌러도 아무 일이 없으면 고장으로 보이므로
        // 다음 날 버튼 자체를 오늘에서 비활성으로 두고(renderDayHeader), 여기서는
        // 혹시 모를 경합(비활성화되기 직전 눌림 등)에 대비한 방어만 한다.
        if (DayPicker.isFuture(candidate, zone, System.currentTimeMillis())) return
        dayKey = candidate
        renderDayHeader()
        // Fix 6(옛 코드의 이유 그대로): 새로 읽기 전에 화면을 먼저 빈 상태로 되돌린다.
        // 안 그러면 읽기가 실패했을 때 어제 목록과 어제 경로선이 오늘 헤더 아래 그대로
        // 남는다 — 부모가 아이 위치를 잘못 읽는 상태다.
        //
        // 비우기 **전에** 상태를 되돌린다. 안 그러면 지난 날의 LOADED 가 남아 있어
        // 새 날짜를 아직 읽지도 않았는데 "이 날은 기록이 없어요"가 한 번 번쩍인다.
        timelineLoad = ListLoad.LOADING
        renderTimeline(emptyList())
        reload()
    }

    private fun renderDayHeader() {
        _binding ?: return
        binding.dayHeader.text = DayPicker.headerText(dayKey, zone, System.currentTimeMillis())
        // 아무 반응 없는 버튼은 고장으로 읽힌다 — 오늘에서는 눌러도 못 넘어가므로
        // 아예 비활성으로 보여준다.
        binding.nextDayButton.isEnabled =
            !DayPicker.isFuture(DayPicker.shift(dayKey, 1), zone, System.currentTimeMillis())
    }

    private fun renderTimelinePanel() {
        val b = _binding ?: return
        val contentHeight = if (timelineExpanded) {
            lastExpandedTimelineHeight.coerceAtMost(maxTimelineContentHeight(collapsedPanelHeight()))
        } else {
            0
        }
        setTimelineContentHeight(contentHeight)
        renderTimelineToggleState()
        // 고정 dp 대신 실제 패널 높이를 쓴다. 글꼴 크기나 기기 비율이 달라도 현재 위치
        // 버튼과 네이버 로고가 패널 위 같은 간격에 놓인다.
        postForCurrentView(b.timelinePanel) {
            updateMapControls()
            if (timelineExpanded) fitWholeRoute()
        }
    }

    private fun renderTimelineToggleState() {
        val b = _binding ?: return
        b.timelineToggleButton.setText(
            if (timelineExpanded) R.string.timeline_collapse else R.string.timeline_view_records,
        )
        b.timelineToggleButton.contentDescription = getString(
            if (timelineExpanded) R.string.timeline_collapse else R.string.timeline_expand,
        )
    }

    /**
     * 보라색 손잡이를 실제 높이 조절 손잡이로 만든다. 패널 전체 높이를 억지로 고정하지
     * 않고 가운데 콘텐츠 높이만 바꾸므로, 위 요약 줄과 아래 날짜 줄은 항상 온전히 남는다.
     */
    @SuppressLint("ClickableViewAccessibility") // performClick을 ACTION_UP에서 직접 호출한다.
    private fun bindTimelineDragHandle() {
        val b = _binding ?: return
        val handle = b.timelineDragHandle
        val touchSlop = ViewConfiguration.get(requireContext()).scaledTouchSlop
        var startRawY = 0f
        var startContentHeight = 0
        var currentContentHeight = 0
        var basePanelHeight = 0
        var dragging = false

        // 짧게 누르면 기존 접기/펼치기와 같은 동작을 해 접근성 클릭도 의미가 있게 한다.
        handle.setOnClickListener {
            timelineExpanded = !timelineExpanded
            renderTimelinePanel()
        }
        handle.setOnTouchListener { view, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startRawY = event.rawY
                    startContentHeight = if (b.timelineContent.isVisible) {
                        b.timelineContent.height
                    } else {
                        0
                    }
                    currentContentHeight = startContentHeight
                    basePanelHeight = (b.timelinePanel.height - startContentHeight)
                        .coerceAtLeast(dp(COLLAPSED_PANEL_HEIGHT_DP))
                    dragging = false
                    view.parent?.requestDisallowInterceptTouchEvent(true)
                    true
                }

                MotionEvent.ACTION_MOVE -> {
                    val deltaY = event.rawY - startRawY
                    if (!dragging && abs(deltaY) > touchSlop) dragging = true
                    if (dragging) {
                        currentContentHeight = (startContentHeight - deltaY.roundToInt())
                            .coerceIn(0, maxTimelineContentHeight(basePanelHeight))
                        setTimelineContentHeight(currentContentHeight)
                        // 레이아웃 측정 한 프레임을 기다리지 않아 손잡이와 버튼이 함께 움직인다.
                        updateMapControls(basePanelHeight + currentContentHeight)
                    }
                    true
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    view.parent?.requestDisallowInterceptTouchEvent(false)
                    if (dragging) {
                        settleTimelineDrag(currentContentHeight, basePanelHeight)
                    } else if (event.actionMasked == MotionEvent.ACTION_UP) {
                        view.performClick()
                    }
                    true
                }

                else -> false
            }
        }
    }

    private fun settleTimelineDrag(contentHeight: Int, basePanelHeight: Int) {
        val maxHeight = maxTimelineContentHeight(basePanelHeight)
        val settledHeight = if (contentHeight < dp(DRAG_COLLAPSE_THRESHOLD_DP)) {
            0
        } else {
            contentHeight.coerceIn(dp(MIN_EXPANDED_CONTENT_HEIGHT_DP), maxHeight)
        }
        timelineExpanded = settledHeight > 0
        if (timelineExpanded) lastExpandedTimelineHeight = settledHeight
        setTimelineContentHeight(settledHeight)
        renderTimelineToggleState()
        postForCurrentView(binding.timelinePanel) {
            updateMapControls()
            if (timelineExpanded) fitWholeRoute()
        }
    }

    private fun setTimelineContentHeight(height: Int) {
        val content = _binding?.timelineContent ?: return
        val safeHeight = height.coerceAtLeast(0)
        content.updateLayoutParams<ViewGroup.LayoutParams> { this.height = safeHeight }
        content.isVisible = safeHeight > 0
    }

    private fun collapsedPanelHeight(): Int {
        val b = _binding ?: return dp(COLLAPSED_PANEL_HEIGHT_DP)
        val contentHeight = if (b.timelineContent.isVisible) {
            b.timelineContent.height
        } else {
            0
        }
        return (b.timelinePanel.height - contentHeight)
            .coerceAtLeast(dp(COLLAPSED_PANEL_HEIGHT_DP))
    }

    private fun maxTimelineContentHeight(basePanelHeight: Int): Int {
        val rootHeight = _binding?.root?.height ?: 0
        if (rootHeight <= 0) return dp(MAX_TIMELINE_CONTENT_HEIGHT_DP)
        val maxPanelHeight = (rootHeight * MAX_TIMELINE_PANEL_RATIO).roundToInt()
        return (maxPanelHeight - basePanelHeight)
            .coerceAtLeast(dp(MIN_EXPANDED_CONTENT_HEIGHT_DP))
    }

    private fun renderTimeline(
        docs: List<SegmentDoc>,
        points: List<TrailPoint> = emptyList(),
    ) {
        _binding ?: return
        timelineAdapter.submitList(docs)
        val distance = SegmentSummarizer.distanceText(docs.sumOf { it.distanceMeters })
        routeSummaryBaseText = if (docs.isEmpty()) {
            getString(R.string.timeline_summary_empty)
        } else if (dayKey == DayPicker.todayKey(zone, System.currentTimeMillis())) {
            getString(R.string.timeline_summary_today, distance)
        } else {
            getString(R.string.timeline_summary_day, distance)
        }
        binding.routeSummary.text = routeSummaryBaseText
        renderTimelineEmpty(docs.isEmpty())
        drawRoute(points, docs)
    }

    /**
     * [docs] 를 인자로 받는 이유: `submitList` 는 비동기(diff)라 바로 다음 줄의
     * `itemCount` 는 아직 옛 값이다. 목록을 새로 그리는 자리에서는 방금 넘긴 목록으로
     * 판단하고, 실패 경로처럼 목록을 안 건드리는 자리에서만 `itemCount` 를 본다.
     */
    private fun renderTimelineEmpty(isEmpty: Boolean) {
        _binding?.timelineEmpty?.renderEmptyState(timelineLoad, isEmpty, R.string.timeline_empty)
    }

    private fun focusOn(lat: Double, lng: Double) {
        val map = naverMap ?: return
        map.moveCamera(CameraUpdate.scrollAndZoomTo(LatLng(lat, lng), CHILD_FOCUS_ZOOM))
    }

    /**
     * 하루 경로를 선으로 그린다.
     *
     * 새 하루 문서에서는 `TrailDoc.points`의 원시 위치점을 시간순으로 잇는다. 구간
     * 끝점만 이으면 골목과 회전 구간이 잘려 보호자가 실제 이동선을 확인하기 어렵기
     * 때문이다. 원시점이 없던 옛 문서는 구간 좌표로 대신 그려 호환성을 유지한다.
     *
     * renderTimeline 은 읽기마다, 그리고 날짜를 넘길 때마다 불린다. 매번 새로 선을
     * 그리기 전에 지난 선을 지우지 않으면 날이 바뀔 때마다 선이 겹겹이 쌓여 지도가
     * 낙서가 된다.
     */
    private fun drawRoute(points: List<TrailPoint>, docs: List<SegmentDoc>) {
        _binding ?: return

        // 위치 마커는 별개 오버레이다 — 여기서는 이전 경로선만
        // 지우고 마커는 건드리지 않는다.
        routeOverlay?.remove()
        routeOverlay = null

        routeSections = buildRouteSections(points, docs)
        val validKeys = routeSections.mapTo(mutableSetOf()) { it.startAt }
        hiddenRouteStarts.retainAll(validKeys)
        timelineAdapter.setHiddenMoveStarts(hiddenRouteStarts.toSet())
        renderRouteVisibilityState()

        renderRouteOverlay()
        if (timelineExpanded) postForCurrentView(binding.mapView) { fitWholeRoute() }
        // 카메라는 여기서 움직이지 않는다 — 부모가 이미 지도를 옮겨봤을 수 있으니
        // 마커가 처음 생길 때(renderStatus())만 이동하고, 경로 갱신으로는 시점을 뺏지 않는다.
    }

    private fun renderRouteOverlay() {
        routeOverlay?.remove()
        routeOverlay = null
        lastRouteLegs = routeSections
            .filterNot { it.startAt in hiddenRouteStarts }
            .flatMap { it.legs }
        lastRoutePositions = lastRouteLegs.flatten()
        val map = naverMap ?: return
        if (lastRouteLegs.sumOf { it.lastIndex.coerceAtLeast(0) } < 1) return
        val ctx = context ?: return
        routeOverlay = GradientRouteOverlay(ctx, lastRouteLegs).also { it.attach(map) }
    }

    /** 이동 카드 하나를 누르면 그 구간 선만 지도에서 켜거나 끈다. */
    private fun toggleRoute(doc: SegmentDoc) {
        if (routeSections.none { it.startAt == doc.startAt }) {
            focusOn(doc.lat, doc.lng)
            return
        }
        if (!hiddenRouteStarts.add(doc.startAt)) hiddenRouteStarts.remove(doc.startAt)
        timelineAdapter.setHiddenMoveStarts(hiddenRouteStarts.toSet())
        renderRouteVisibilityState()
        renderRouteOverlay()
    }

    /** 모두 보이는 중이면 전부 숨기고, 하나라도 숨겨져 있으면 전부 다시 보인다. */
    private fun toggleAllRoutes() {
        val keys = routeSections.mapTo(mutableSetOf()) { it.startAt }
        if (keys.isEmpty()) return
        if (keys.all { it !in hiddenRouteStarts }) hiddenRouteStarts.addAll(keys)
        else hiddenRouteStarts.removeAll(keys)
        timelineAdapter.setHiddenMoveStarts(hiddenRouteStarts.toSet())
        renderRouteVisibilityState()
        renderRouteOverlay()
    }

    private fun renderRouteVisibilityState() {
        val b = _binding ?: return
        val keys = routeSections.map { it.startAt }
        val allVisible = keys.isNotEmpty() && keys.all { it !in hiddenRouteStarts }
        b.routeVisibilityButton.isEnabled = keys.isNotEmpty()
        b.routeVisibilityButton.alpha = if (keys.isNotEmpty()) 1f else 0.38f
        b.routeVisibilityButton.setIconResource(
            if (allVisible) R.drawable.ic_visibility else R.drawable.ic_visibility_off,
        )
        b.routeVisibilityButton.contentDescription = getString(
            if (allVisible) R.string.timeline_hide_all_routes
            else R.string.timeline_show_all_routes,
        )
        val hiddenCount = keys.count { it in hiddenRouteStarts }
        b.routeSummary.text = when {
            hiddenCount == 0 -> routeSummaryBaseText
            hiddenCount == keys.size -> getString(
                R.string.timeline_summary_routes_hidden, routeSummaryBaseText,
            )
            else -> getString(R.string.timeline_summary_routes_partial, routeSummaryBaseText)
        }
    }

    /**
     * 원시 GPS 점을 MOVE 시간 범위별로 나눠 카드 하나와 지도 선 하나를 연결한다.
     *
     * 창은 구간의 startAt..endAt 그대로가 아니라 [RouteWindows.partition] 으로
     * **하루 전체를 빈틈없이 나눈 것**을 쓴다. 예전에는 창 밖(머무름 기준점, 구간
     * 계산과 업로드의 미세한 어긋남, 마지막 이동 뒤의 최신 점)에 떨어진 점이 어느
     * 선에도 안 들어가 조용히 사라졌다 — 아이 폰에는 다 쌓여 있는데 부모 지도만
     * 중간이 삭제된 것처럼 보였던 원인. 흔들림 정리는 창이 아니라
     * [RoutePathRefiner] 가 맡는다.
     */
    private fun buildRouteSections(
        points: List<TrailPoint>,
        docs: List<SegmentDoc>,
    ): List<RouteSection> {
        val sortedPoints = points.sortedBy { it.at }
        val moveDocs = docs.filter { it.type == SegmentType.MOVE.name }.sortedBy { it.startAt }
        val windows = RouteWindows.partition(moveDocs.map { it.startAt..it.endAt })
        return moveDocs.mapIndexedNotNull { moveIndex, doc ->
            val window = windows[moveIndex]
            val windowPoints = sortedPoints.filter { it.at in window }
            val refined = if (windowPoints.size >= 2) {
                RoutePathRefiner.refine(
                    windowPoints.map { Fix(it.lat, it.lng, it.accuracy, it.at, it.speed) },
                ).map { leg -> leg.points.map { LatLng(it.lat, it.lng) } }
                    .filter { it.size >= 2 }
            } else {
                emptyList()
            }

            // points가 없던 옛 기록도 양옆 구간 좌표로 근사해 계속 볼 수 있게 한다.
            val legs = refined.ifEmpty {
                val index = docs.indexOf(doc)
                val fallback = listOfNotNull(
                    docs.getOrNull(index - 1), doc, docs.getOrNull(index + 1),
                ).filter { it.lat.isFinite() && it.lng.isFinite() }
                    .distinctBy { it.lat to it.lng }
                    .map { LatLng(it.lat, it.lng) }
                if (fallback.size >= 2) listOf(fallback) else emptyList()
            }
            if (legs.isEmpty()) null else RouteSection(doc.startAt, legs)
        }
    }

    private fun fitWholeRoute() {
        _binding ?: return
        val map = naverMap ?: return
        if (lastRoutePositions.size < 2) return
        val bounds = LatLngBounds.Builder().apply {
            lastRoutePositions.forEach(::include)
        }.build()
        val horizontal = dp(48)
        val top = dp(112)
        val bottom = timelinePanelHeight() + dp(24)
        map.moveCamera(
            CameraUpdate.fitBounds(bounds, horizontal, top, horizontal, bottom)
                .animate(CameraAnimation.Easing, 350),
        )
    }

    /** 아래 패널에 가려지지 않도록 네이버 법적 고지 로고를 항상 지도 안에 남긴다. */
    private fun updateNaverLogoMargin(panelHeight: Int = timelinePanelHeight()) {
        val map = naverMap ?: return
        map.uiSettings.setLogoMargin(
            dp(14),
            0,
            0,
            panelHeight + dp(8),
        )
    }

    /** 지도 위 부유 컨트롤을 하단 패널의 실제 높이에 맞춘다. */
    private fun updateMapControls(panelHeight: Int = timelinePanelHeight()) {
        val b = _binding ?: return
        b.locateButton.updateLayoutParams<android.widget.FrameLayout.LayoutParams> {
            bottomMargin = panelHeight + dp(12)
        }
        b.liveTrackingButton.updateLayoutParams<android.widget.FrameLayout.LayoutParams> {
            bottomMargin = panelHeight + dp(12)
        }
        updateNaverLogoMargin(panelHeight)
    }

    private fun timelinePanelHeight(): Int {
        val height = _binding?.timelinePanel?.height ?: 0
        return if (height > 0) height else {
            dp(COLLAPSED_PANEL_HEIGHT_DP) + if (timelineExpanded) {
                lastExpandedTimelineHeight.takeIf { it > 0 }
                    ?: dp(DEFAULT_TIMELINE_CONTENT_HEIGHT_DP)
            } else {
                0
            }
        }
    }

    private fun clearMapForChildSwitch() {
        lastMapStatus = null
        routeSections = emptyList()
        hiddenRouteStarts.clear()
        lastRouteLegs = emptyList()
        lastRoutePositions = emptyList()
        childMarker?.map = null
        childMarker = null
        accuracyCircle?.map = null
        accuracyCircle = null
        routeOverlay?.remove()
        routeOverlay = null
    }

    /**
     * 지도 SDK와 View.post 콜백은 Fragment가 화면에서 떨어지는 순간에도 마지막 한 번
     * 도착할 수 있다. Fragment.resources는 그 구간에 예외를 던지므로, 살아 있는 View의
     * 리소스를 우선 쓰고 이미 정리됐다면 안전한 기본 배율로 계산한다.
     */
    private fun dp(value: Int): Int {
        val density = _binding?.root?.resources?.displayMetrics?.density
            ?: context?.resources?.displayMetrics?.density
            ?: 1f
        return (value * density).toInt()
    }

    /** 현재 화면에서 예약한 작업만 실행해, 이전 Fragment View의 지연 작업을 버린다. */
    private fun postForCurrentView(view: View, action: () -> Unit) {
        val expectedBinding = _binding ?: return
        view.post {
            if (_binding === expectedBinding && isAdded) action()
        }
    }

    private data class RouteSection(
        val startAt: Long,
        val legs: List<List<LatLng>>,
    )

    override fun onStart() {
        super.onStart()
        _binding?.mapView?.onStart()
    }

    override fun onResume() {
        super.onResume()
        _binding?.mapView?.onResume()
    }

    override fun onPause() {
        _binding?.mapView?.onPause()
        super.onPause()
    }

    override fun onStop() {
        _binding?.mapView?.onStop()
        super.onStop()
    }

    override fun onLowMemory() {
        _binding?.mapView?.onLowMemory()
        super.onLowMemory()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean(KEY_TIMELINE_EXPANDED, timelineExpanded)
        outState.putInt(KEY_TIMELINE_CONTENT_HEIGHT, lastExpandedTimelineHeight)
        _binding?.mapView?.onSaveInstanceState(outState)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroyView() {
        joinedListener?.remove()
        joinedListener = null
        loadJob?.cancel()
        loadJob = null
        stopTracking()
        stopLiveTracking()
        clearMapForChildSwitch()
        naverMap = null
        _binding?.mapView?.onDestroy()
        _binding = null
        super.onDestroyView()
    }

    private companion object {
        private const val TAG = "MapTimelineFragment"
        /** 관리 탭의 무응답 표시와 같은 값이어야 한다(설계서 §5). */
        private const val COMMAND_TIMEOUT_MILLIS = 60_000L

        /** 명령 발행(서버 확인)을 기다리는 시간. 근거는 [ControlFragment.SEND_TIMEOUT_MILLIS]. */
        private const val SEND_TIMEOUT_MILLIS = 15_000L
        private const val LIVE_SESSION_DURATION_SECONDS = 10 * 60L

        private const val KEY_TIMELINE_EXPANDED = "timeline_expanded"
        private const val KEY_TIMELINE_CONTENT_HEIGHT = "timeline_content_height"
        private const val DEFAULT_TIMELINE_CONTENT_HEIGHT_DP = 174
        private const val MAX_TIMELINE_CONTENT_HEIGHT_DP = 340
        private const val MIN_EXPANDED_CONTENT_HEIGHT_DP = 96
        private const val DRAG_COLLAPSE_THRESHOLD_DP = 56
        private const val COLLAPSED_PANEL_HEIGHT_DP = 136
        private const val MAX_TIMELINE_PANEL_RATIO = 0.72f
        private const val CHILD_FOCUS_ZOOM = 18.0

        // 경로선과 같은 파랑에 알파만 크게 낮춘 값이다. 색을 따로 만들지 않는 이유:
        // 새 색은 "다른 무언가"라는 신호를 주는데, 이 원은 마커가 가리키는 그 위치의
        // 불확실성일 뿐 별개의 대상이 아니다. 채움 0x22(약 13%)는 아래 지도 타일의
        // 도로·건물 이름이 그대로 읽히는 정도라 영역을 '칠한' 느낌이 안 난다.
        private const val ACCURACY_FILL_COLOR = 0x269B7DE2
        // 테두리는 채움보다 조금만 진하게. 진하면 지오펜스 경계선처럼 보인다.
        private const val ACCURACY_STROKE_COLOR = 0x669B7DE2
        // 경로선(14f)의 1/7. 가늘어야 '경계'가 아니라 '번짐'으로 읽힌다.
        private const val ACCURACY_STROKE_WIDTH_DP = 2
        private const val ACCURACY_Z_INDEX = -190_000
    }
}
