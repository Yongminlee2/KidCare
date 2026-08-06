package com.kidcare.family.guardian

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.firebase.firestore.ListenerRegistration
import com.kakao.vectormap.KakaoMap
import com.kakao.vectormap.KakaoMapReadyCallback
import com.kakao.vectormap.LatLng
import com.kakao.vectormap.MapLifeCycleCallback
import com.kakao.vectormap.camera.CameraUpdateFactory
import com.kakao.vectormap.label.Label
import com.kakao.vectormap.label.LabelOptions
import com.kakao.vectormap.label.LabelStyle
import com.kakao.vectormap.label.LabelStyles
import com.kakao.vectormap.route.RouteLine
import com.kakao.vectormap.route.RouteLineOptions
import com.kakao.vectormap.route.RouteLineSegment
import com.kakao.vectormap.route.RouteLineStyle
import com.kakao.vectormap.route.RouteLineStyles
import com.kidcare.family.BuildConfig
import com.kidcare.family.R
import com.kidcare.family.core.FamilyRepository
import com.kidcare.family.core.RoleStore
import com.kidcare.family.core.SegmentRepository
import com.kidcare.family.core.model.ChildStatusDoc
import com.kidcare.family.core.model.SegmentDoc
import com.kidcare.family.databinding.FragmentMapTimelineBinding
import com.kidcare.family.logic.DayPicker
import java.text.SimpleDateFormat
import java.time.ZoneId
import java.util.Locale

/**
 * 보호자 메인. 카카오맵 위에 아이의 현재 위치를 찍는다.
 *
 * children/{childUid} 문서(= status. 설계서는 별도 하위 문서로 그렸지만
 * StatusReporter 가 문서 자체를 status 로 쓰기로 했다)를 실시간 구독해
 * 상단 카드 문구와 지도 마커를 함께 갱신한다.
 *
 * 3단계 Task 5 가 지도 아래에 하루 요약 타임라인과 날짜 이동을 붙였다.
 * 3단계 Task 6 이 [drawRoute] 로 지도 위에 하루 경로 폴리라인을 붙였다.
 */
class MapTimelineFragment : Fragment() {

    private var _binding: FragmentMapTimelineBinding? = null
    private val binding get() = _binding!!

    private var kakaoMap: KakaoMap? = null
    private var childLabel: Label? = null
    private var routeLine: RouteLine? = null
    private var statusListener: ListenerRegistration? = null

    // 자녀가 members 에 들어오는 순간을 계속 지켜본다(Task 8 이전엔 findChildUid 를
    // onViewCreated 에서 한 번만 불러 화면을 켜 둔 채로 페어링이 끝나면 다시 만들기
    // 전까지 "연결 안 됨"이 안 풀리는 문제가 있었다). 이 리스너 하나가 statusListener·
    // segmentListener 두 개를 필요할 때마다 다시 걸어 준다.
    private var joinedListener: ListenerRegistration? = null

    // Firestore 스냅샷(특히 캐시 응답)은 onMapReady 보다 먼저 도착할 수 있다.
    // 그 사이에는 지도에 아무것도 그릴 수 없으니 여기 잠깐 담아뒀다가
    // onMapReady 에서 한 번 더 그린다. 반대로 onMapReady 가 먼저 끝나면
    // render() 가 매번 kakaoMap 이 있는지 보고 바로 그리므로 이 값은 안 쓰인다.
    private var pendingStatus: ChildStatusDoc? = null

    private val timeFormat = SimpleDateFormat("HH:mm", Locale.KOREA)

    // 기기 시간대를 한 번만 읽어 고정한다 — 화면이 떠 있는 동안 시간대가 바뀌는 일은
    // 실질적으로 없고, DayPicker 를 부를 때마다 매번 물어보면 호출부만 늘어난다.
    private val zone: ZoneId = ZoneId.systemDefault()
    private var dayKey: String = DayPicker.todayKey(zone, System.currentTimeMillis())
    private var segmentListener: ListenerRegistration? = null

    // joinedListener 의 onJoined 가 채운다. 날짜를 넘길 때(changeDay)는 이 값을
    // 그대로 재사용하고 다시 조회하지 않는다.
    private var childUid: String? = null
    private lateinit var timelineAdapter: TimelineAdapter

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

        // 타임라인은 지도와 무관하다 — 앱키가 없어 지도를 못 띄우는 개발기에서도
        // 날짜 이동 UI 자체는 멀쩡히 그려져야 한다. subscribeSegments 가 childUid 를
        // 못 구해 구독이 아예 안 걸리는 경우(앱키가 없거나, 아직 아이 폰이 첫 보고를
        // 안 올린 첫 실행 구간) renderTimeline 이 한 번도 안 불릴 수 있는데, 그때
        // 화면이 "아무 설명 없이 텅 빈 채로" 남으면 고장으로 읽힌다. 그래서 구독
        // 결과를 기다리지 않고 여기서 빈 목록으로 한 번 먼저 그려 empty 안내부터
        // 보여준다 — 실제 데이터가 오면 renderTimeline 이 다시 불려 덮어쓴다.
        timelineAdapter = TimelineAdapter(zone) { doc -> focusOn(doc.lat, doc.lng) }
        binding.timelineList.layoutManager = LinearLayoutManager(requireContext())
        binding.timelineList.adapter = timelineAdapter
        renderTimeline(emptyList())
        binding.prevDayButton.setOnClickListener { changeDay(-1) }
        binding.nextDayButton.setOnClickListener { changeDay(1) }
        renderDayHeader()

        if (BuildConfig.KAKAO_APP_KEY.isEmpty()) {
            // 앱키가 없다(개발기에 아직 등록 전) — 지도를 아예 시작하지 않는다.
            // 안내만 띄우고, 페어링·위치 수집 등 이 화면과 무관한 기능은 그대로 돈다.
            binding.noKeyNotice.visibility = View.VISIBLE
            return
        }

        binding.mapView.start(
            object : MapLifeCycleCallback() {
                override fun onMapDestroy() = Unit
                override fun onMapError(error: Exception) {
                    _binding?.statusBar?.text = getString(R.string.map_error, error.message ?: "")
                }
            },
            object : KakaoMapReadyCallback() {
                override fun onMapReady(map: KakaoMap) {
                    // 늦게 도착한 콜백일 수 있다 — 화면이 이미 사라졌으면 무시한다.
                    if (_binding == null) return
                    kakaoMap = map
                    pendingStatus?.let { render(it) }
                }
            },
        )

        subscribe()
    }

    /**
     * findChildUid 를 한 번만 부르던 옛 방식은 부모가 지도를 켜 둔 채로 아이가
     * 페어링을 끝내면 화면을 다시 만들기 전까지 "연결 안 됨"이 풀리지 않았다
     * (known-issues 3). observeChildJoined 는 addSnapshotListener 라서(suspend
     * 가 아니다) 코루틴이 필요 없다 — subscribeSegments 와 같은 방식이다.
     */
    private fun subscribe() {
        val store = RoleStore(requireContext())
        val familyId = store.familyId ?: return
        _binding?.statusBar?.text = getString(R.string.map_no_child)
        joinedListener = FamilyRepository.observeChildJoined(
            familyId,
            onJoined = { uid ->
                // 자기 멤버 문서가 바뀔 때마다(예: 다음 단계의 fcmToken/appVersion 갱신)
                // 이 콜백이 같은 uid 로 다시 불릴 수 있다. uid 가 그대로면 리스너를
                // 갈아 끼울 이유가 없다 — 매번 다시 걸면 화면이 불필요하게 다시 그려진다.
                if (uid == childUid) return@observeChildJoined
                childUid = uid
                attachChildListeners(familyId, uid)
            },
            onError = { e -> _binding?.statusBar?.text = getString(R.string.map_error, e.message ?: "") },
        )
    }

    /**
     * childUid 가 (처음이든, 재페어링이든) 확정될 때마다 상태·구간 리스너를 다시 건다.
     * 리스너를 세 개(joinedListener·statusListener·segmentListener) 들고 있게 되므로
     * 옛 statusListener 를 먼저 지운다 — subscribeSegments 가 옛 segmentListener 를
     * 먼저 지우는 것과 같은 규율이다.
     */
    private fun attachChildListeners(familyId: String, uid: String) {
        statusListener?.remove()
        statusListener = FamilyRepository.observeChildStatus(
            familyId,
            uid,
            onChange = { status -> render(status) },
            onError = { e -> _binding?.statusBar?.text = getString(R.string.map_error, e.message ?: "") },
        )
        subscribeSegments()
    }

    /** Firestore 콜백에서도 불릴 수 있어서, onDestroyView 이후엔 아무 뷰도 건드리지 않는다. */
    private fun render(status: ChildStatusDoc) {
        val b = _binding ?: return
        b.statusBar.text = getString(
            R.string.map_status_format,
            status.battery,
            timeFormat.format(status.at),
        )

        val map = kakaoMap
        if (map == null) {
            pendingStatus = status
            return
        }
        pendingStatus = null

        val position = LatLng.from(status.lat, status.lng)
        val label = childLabel
        if (label == null) {
            val styles = LabelStyles.from(
                "child",
                LabelStyle.from(R.drawable.marker_child).setAnchorPoint(0.5f, 1.0f),
            )
            childLabel = map.labelManager?.layer?.addLabel(
                LabelOptions.from("child", position).setStyles(styles)
            )
            map.moveCamera(CameraUpdateFactory.newCenterPosition(position, 16))
        } else {
            label.moveTo(position)
        }
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
        subscribeSegments()
    }

    private fun renderDayHeader() {
        _binding ?: return
        binding.dayHeader.text = DayPicker.headerText(dayKey, zone, System.currentTimeMillis())
        // 아무 반응 없는 버튼은 고장으로 읽힌다 — 오늘에서는 눌러도 못 넘어가므로
        // 아예 비활성으로 보여준다.
        binding.nextDayButton.isEnabled =
            !DayPicker.isFuture(DayPicker.shift(dayKey, 1), zone, System.currentTimeMillis())
    }

    /**
     * 그 날의 구간 목록을 구독한다. 날짜가 바뀔 때마다 다시 불리므로, 옛 리스너를
     * 먼저 지우지 않으면 날짜를 넘길수록 리스너가 쌓여 여러 날의 데이터가 한꺼번에
     * 섞여 보이게 된다.
     */
    private fun subscribeSegments() {
        segmentListener?.remove()
        segmentListener = null
        val familyId = RoleStore(requireContext()).familyId ?: return
        val uid = childUid ?: return
        segmentListener = SegmentRepository.observeSegmentsOfDay(
            familyId = familyId,
            childUid = uid,
            dayKey = dayKey,
            onChange = { docs -> renderTimeline(docs) },
            onError = { e ->
                _binding?.statusBar?.text = getString(R.string.map_error, e.message ?: "")
            },
        )
    }

    private fun renderTimeline(docs: List<SegmentDoc>) {
        _binding ?: return
        timelineAdapter.submitList(docs)
        binding.timelineEmpty.visibility = if (docs.isEmpty()) View.VISIBLE else View.GONE
        drawRoute(docs)
    }

    private fun focusOn(lat: Double, lng: Double) {
        val map = kakaoMap ?: return
        map.moveCamera(CameraUpdateFactory.newCenterPosition(LatLng.from(lat, lng), 16))
    }

    /**
     * 하루 경로를 선으로 그린다.
     *
     * 구간 요약의 좌표만 잇는다 — 원시 점을 전부 내려받으면 하루 수백 개라 느리고,
     * 요약 좌표(머무름 중심 + 이동 끝점)만으로도 "어디서 어디로"는 충분히 보인다.
     * SegmentBuilder 가 이동 구간의 끝을 앞뒤 머무름과 이어붙이도록 만들어 놨기
     * 때문에 이 선은 끊기지 않는다.
     *
     * renderTimeline 은 스냅샷마다, 그리고 날짜를 넘길 때마다 불린다. 매번 새로
     * 선을 그리기 전에 지난 선을 지우지 않으면 날이 바뀔 때마다 선이 겹겹이
     * 쌓여 지도가 낙서가 된다. 앱키가 없어 kakaoMap 이 없는 개발기에서는
     * routeLineManager 에 접근할 이유도 없으므로 맨 앞에서 빠진다.
     */
    private fun drawRoute(docs: List<SegmentDoc>) {
        val map = kakaoMap ?: return
        val layer = map.routeLineManager?.layer ?: return

        // 위치 마커는 labelManager 의 레이어에 있어 별개다 — 여기서 지우는 건
        // routeLineManager 레이어의 선뿐이고 마커는 건드리지 않는다.
        routeLine?.let { layer.remove(it) }
        routeLine = null

        val positions = docs.map { LatLng.from(it.lat, it.lng) }
        if (positions.size < 2) return // 점 하나로는 선이 안 된다.

        val styles = RouteLineStyles.from(RouteLineStyle.from(ROUTE_LINE_WIDTH, ROUTE_COLOR))
        val segment = RouteLineSegment.from(positions, styles)
        routeLine = layer.addRouteLine(RouteLineOptions.from(segment))
        // 카메라는 여기서 움직이지 않는다 — 부모가 이미 지도를 옮겨봤을 수 있으니
        // 마커가 처음 생길 때(render())만 이동하고, 경로 갱신으로는 시점을 뺏지 않는다.
    }

    override fun onResume() {
        super.onResume()
        if (BuildConfig.KAKAO_APP_KEY.isNotEmpty()) _binding?.mapView?.resume()
    }

    override fun onPause() {
        if (BuildConfig.KAKAO_APP_KEY.isNotEmpty()) _binding?.mapView?.pause()
        super.onPause()
    }

    override fun onDestroyView() {
        joinedListener?.remove()
        joinedListener = null
        statusListener?.remove()
        statusListener = null
        segmentListener?.remove()
        segmentListener = null
        kakaoMap = null
        childLabel = null
        routeLine = null
        pendingStatus = null
        _binding = null
        super.onDestroyView()
    }

    private companion object {
        private const val ROUTE_LINE_WIDTH = 14f
        private const val ROUTE_COLOR = 0xFF3D6DF5.toInt()
    }
}
