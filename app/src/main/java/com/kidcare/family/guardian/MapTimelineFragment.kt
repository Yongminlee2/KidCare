package com.kidcare.family.guardian

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.MarginLayoutParams
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updateLayoutParams
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
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
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.time.ZoneId
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polygon
import org.osmdroid.views.overlay.Polyline

/**
 * 보호자 메인. osmdroid 지도 위에 아이의 위치를 찍고 그 아래에 하루 요약을 보여준다.
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
 * osmdroid 교체(카카오 앱키 미발급 문제 해결) 시점에 카카오 API 호출을 osmdroid로
 * 옮겼다 — 지도가 그리는 내용과 동작 규칙은 그대로다. `.superpowers/map-swap-report.md`
 * 에 API 매핑 근거를 적어뒀다.
 */
class MapTimelineFragment : Fragment() {

    private var _binding: FragmentMapTimelineBinding? = null
    private val binding get() = _binding!!

    // 아이 위치 마커. 처음 생길 때만 카메라를 이동시키기 위해 null 여부로
    // "이미 그린 적 있는가"를 판정한다 — 아래 renderStatus() 참고.
    private var childMarker: Marker? = null

    // 마커 주변에 그리는 오차 원. 마커와 따로 들고 있어야 갱신할 때 이전 원만
    // 골라 지울 수 있다(routeLine 과 같은 규율).
    private var accuracyCircle: Polygon? = null
    private var routeLine: Polyline? = null

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

    // 기기 시간대를 한 번만 읽어 고정한다 — 화면이 떠 있는 동안 시간대가 바뀌는 일은
    // 실질적으로 없고, DayPicker 를 부를 때마다 매번 물어보면 호출부만 늘어난다.
    private val zone: ZoneId = ZoneId.systemDefault()
    private var dayKey: String = DayPicker.todayKey(zone, System.currentTimeMillis())

    // joinedListener 의 onJoined 가 채운다. 날짜를 넘길 때(changeDay)는 이 값을
    // 그대로 재사용하고 다시 조회하지 않는다.
    private var childUid: String? = null
    private lateinit var timelineAdapter: TimelineAdapter
    private var timelineExpanded = false
    private var focusChildOnNextLoad = false

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
        timelineAdapter = TimelineAdapter(zone) { doc -> focusOn(doc.lat, doc.lng) }
        binding.timelineList.layoutManager = LinearLayoutManager(requireContext())
        binding.timelineList.adapter = timelineAdapter
        renderTimeline(emptyList())
        binding.prevDayButton.setOnClickListener { changeDay(-1) }
        binding.nextDayButton.setOnClickListener { changeDay(1) }
        binding.timelineToggleButton.setOnClickListener {
            timelineExpanded = !timelineExpanded
            renderTimelinePanel()
        }
        binding.locateButton.setOnClickListener { locateNow() }
        binding.locateButton.isEnabled = false
        binding.statusBar.text = getString(R.string.map_no_child)
        renderDayHeader()
        renderTimelinePanel()

        subscribe()

        // osmdroid는 mapView.start(...) 같은 비동기 준비 콜백이 없다 — MapView 는
        // 위 FragmentMapTimelineBinding.inflate() 시점에 XML 인플레이트로 이미 완전히
        // 생성되어 있고, 마커/폴리라인을 바로 추가해도 된다.
        binding.mapView.setMultiTouchControls(true)
    }

    /**
     * 자녀 uid 를 계속 지켜본다. `findChildUid` 를 한 번만 부르던 옛 방식은 부모가
     * 지도를 켜 둔 채로 아이가 페어링을 끝내면 화면을 다시 만들기 전까지
     * "연결 안 됨"이 풀리지 않았다(known-issues 3).
     */
    private fun subscribe() {
        val familyId = RoleStore(requireContext()).familyId ?: return
        joinedListener = FamilyRepository.observeChildJoined(
            familyId,
            onJoined = { uid ->
                // 자기 멤버 문서가 바뀔 때마다 이 콜백이 같은 uid 로 다시 불릴 수 있다.
                // uid 가 그대로면 다시 읽을 이유가 없다 — 매번 다시 읽으면 그게 곧
                // 무료 한도를 갉아먹는 읽기다.
                if (uid == childUid) return@observeChildJoined
                childUid = uid
                _binding ?: return@observeChildJoined
                binding.locateButton.isEnabled = true
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
        requestLog.recordRequest()
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

    /** 아이 폰이 대답했다는 사실을 남기고 배너를 즉시 다시 판정하게 한다. */
    private fun recordAnswer() {
        requestLog.recordAnswer()
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
        b.locateButton.isEnabled = !busy && childUid != null
        if (busy) b.statusBar.text = getString(R.string.map_locating)
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
        if (System.currentTimeMillis() - elapsed > requestLog.lastRequestAt) recordAnswer()

        b.statusBar.text = ctx.getString(
            R.string.map_status_format,
            status.battery,
            LastSignalText.relativeText(ctx, signal, elapsed),
        )

        val point = GeoPoint(status.lat, status.lng)
        drawAccuracyCircle(point, status.accuracy)
        val marker = childMarker
        val shouldFocusChild = marker == null || focusChildOnNextLoad
        if (marker == null) {
            val newMarker = Marker(b.mapView)
            newMarker.icon = ContextCompat.getDrawable(requireContext(), R.drawable.marker_child)
            // 카카오 LabelStyle.setAnchorPoint(0.5f, 1.0f)와 같은 값 — 마커 아이콘의
            // 가로 중앙·세로 맨 아래가 실제 좌표를 가리키게 한다(핀 모양 아이콘 전제).
            newMarker.setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
            newMarker.position = point
            b.mapView.overlays.add(newMarker)
            childMarker = newMarker
            // 카메라는 마커가 "처음 생길 때"만 움직인다 — 이후 갱신에서는 부모가 이미
            // 지도를 옮겨봤을 수 있으니 시점을 뺏지 않는다.
        } else {
            marker.position = point
        }
        if (shouldFocusChild) {
            b.mapView.controller.setZoom(CHILD_FOCUS_ZOOM)
            b.mapView.controller.setCenter(point)
            focusChildOnNextLoad = false
        }
        b.mapView.invalidate()
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
     *    가는 테두리를 쓰고 마커보다 **아래**(overlays 인덱스 0)에 넣는다.
     *  - **최소 크기를 강제하지 않는다.** 오차가 작아 지금 배율에서 원이 안 보이면
     *    그게 맞는 결과다. 좋은 fix 를 억지로 큰 원으로 부풀리는 것은 그 자체가
     *    또 다른 거짓말이다.
     *  - accuracy 가 0 이면 아예 안 그린다. 0 은 "오차 없음"이 아니라 **모른다**는
     *    뜻이다(옛 문서·기기가 값을 안 줄 때 0 으로 읽힌다). 모르는 것을 완벽한
     *    것처럼 그리면 안 된다.
     */
    private fun drawAccuracyCircle(center: GeoPoint, accuracyMeters: Float) {
        val b = _binding ?: return

        accuracyCircle?.let { b.mapView.overlays.remove(it) }
        accuracyCircle = null

        if (accuracyMeters <= 0f) {
            b.mapView.invalidate()
            return
        }

        val circle = Polygon(b.mapView)
        circle.setPoints(Polygon.pointsAsCircle(center, accuracyMeters.toDouble()))
        // setFillColor/setStrokeColor 대신 Paint 를 직접 만진다 — 이 파일의
        // Polyline 이 이미 같은 이유(구버전 API deprecated)로 그렇게 하고 있다.
        circle.fillPaint.color = ACCURACY_FILL_COLOR
        circle.outlinePaint.color = ACCURACY_STROKE_COLOR
        circle.outlinePaint.strokeWidth = ACCURACY_STROKE_WIDTH
        // 인덱스 0 = 가장 먼저 그려짐 = 가장 아래. 마커·경로선은 이 위에 남는다.
        // 마커가 나중에 append 되므로 "원이 마커를 덮는" 순서가 나올 수 없다.
        b.mapView.overlays.add(0, circle)
        accuracyCircle = circle
        b.mapView.invalidate()
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
        b.timelineContent.visibility = if (timelineExpanded) View.VISIBLE else View.GONE
        b.timelineToggleButton.rotation = if (timelineExpanded) 180f else 0f
        b.timelineToggleButton.contentDescription = getString(
            if (timelineExpanded) R.string.timeline_collapse else R.string.timeline_expand,
        )
    }

    private fun renderTimeline(
        docs: List<SegmentDoc>,
        points: List<TrailPoint> = emptyList(),
    ) {
        _binding ?: return
        timelineAdapter.submitList(docs)
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
        val b = _binding ?: return
        val point = GeoPoint(lat, lng)
        b.mapView.controller.setZoom(CHILD_FOCUS_ZOOM)
        b.mapView.controller.setCenter(point)
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
        val b = _binding ?: return

        // 위치 마커는 overlays 리스트의 다른 요소라 별개다 — 여기서는 이전 경로선만
        // 지우고 마커는 건드리지 않는다.
        routeLine?.let { b.mapView.overlays.remove(it) }
        routeLine = null

        // 하루 문서에는 필터를 통과한 원시 위치점이 이미 함께 들어 있다. 예전에는 구간
        // 요약의 끝점만 이어 실제 골목과 회전을 많이 잘라냈다. 원시점이 있는 새 기록은
        // 전부 이어 그리고, 옛 문서는 구간 좌표를 이용해 계속 표시한다.
        val positions = if (points.size >= 2) {
            points.sortedBy { it.at }.map { GeoPoint(it.lat, it.lng) }
        } else {
            docs.map { GeoPoint(it.lat, it.lng) }
        }
        if (positions.size < 2) {
            b.mapView.invalidate() // 점 하나로는 선이 안 된다 — 지운 것만 반영하고 끝.
            return
        }

        val polyline = Polyline(b.mapView)
        // setColor/setWidth 는 구버전 API로 deprecated 됐다 — 실제 선을 그리는 Paint 를
        // 직접 건드리는 쪽이 권장 방식이다.
        polyline.outlinePaint.color = ROUTE_COLOR
        polyline.outlinePaint.strokeWidth = ROUTE_LINE_WIDTH
        polyline.setPoints(positions)
        b.mapView.overlays.add(polyline)
        routeLine = polyline
        // 카메라는 여기서 움직이지 않는다 — 부모가 이미 지도를 옮겨봤을 수 있으니
        // 마커가 처음 생길 때(renderStatus())만 이동하고, 경로 갱신으로는 시점을 뺏지 않는다.
        b.mapView.invalidate()
    }

    override fun onResume() {
        super.onResume()
        _binding?.mapView?.onResume()
    }

    override fun onPause() {
        _binding?.mapView?.onPause()
        super.onPause()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean(KEY_TIMELINE_EXPANDED, timelineExpanded)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroyView() {
        joinedListener?.remove()
        joinedListener = null
        loadJob?.cancel()
        loadJob = null
        stopTracking()
        // onDetach()는 osmdroid가 내부적으로 띄운 타일 다운로드 스레드·리시버를
        // 정리한다 — 안 부르면 화면을 나갔다 들어올 때마다 조금씩 샌다.
        _binding?.mapView?.onDetach()
        childMarker = null
        accuracyCircle = null
        routeLine = null
        _binding = null
        super.onDestroyView()
    }

    private companion object {
        /** 관리 탭의 무응답 표시와 같은 값이어야 한다(설계서 §5). */
        private const val COMMAND_TIMEOUT_MILLIS = 60_000L

        /** 명령 발행(서버 확인)을 기다리는 시간. 근거는 [ControlFragment.SEND_TIMEOUT_MILLIS]. */
        private const val SEND_TIMEOUT_MILLIS = 15_000L

        private const val KEY_TIMELINE_EXPANDED = "timeline_expanded"
        private const val CHILD_FOCUS_ZOOM = 18.0

        private const val ROUTE_LINE_WIDTH = 14f
        private const val ROUTE_COLOR = 0xFF287D70.toInt()

        // 경로선과 같은 파랑에 알파만 크게 낮춘 값이다. 색을 따로 만들지 않는 이유:
        // 새 색은 "다른 무언가"라는 신호를 주는데, 이 원은 마커가 가리키는 그 위치의
        // 불확실성일 뿐 별개의 대상이 아니다. 채움 0x22(약 13%)는 아래 지도 타일의
        // 도로·건물 이름이 그대로 읽히는 정도라 영역을 '칠한' 느낌이 안 난다.
        private const val ACCURACY_FILL_COLOR = 0x22287D70
        // 테두리는 채움보다 조금만 진하게. 진하면 지오펜스 경계선처럼 보인다.
        private const val ACCURACY_STROKE_COLOR = 0x55287D70
        // 경로선(14f)의 1/7. 가늘어야 '경계'가 아니라 '번짐'으로 읽힌다.
        private const val ACCURACY_STROKE_WIDTH = 2f
    }
}
