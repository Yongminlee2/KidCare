package com.kidcare.family.guardian

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import androidx.fragment.app.Fragment
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.firebase.firestore.ListenerRegistration
import com.kidcare.family.R
import com.kidcare.family.core.FamilyRepository
import com.kidcare.family.core.RoleStore
import com.kidcare.family.core.SegmentRepository
import com.kidcare.family.core.errorMessage
import com.kidcare.family.core.model.ChildStatusDoc
import com.kidcare.family.core.model.SegmentDoc
import com.kidcare.family.databinding.FragmentMapTimelineBinding
import com.kidcare.family.logic.DayPicker
import java.text.SimpleDateFormat
import java.time.ZoneId
import java.util.Locale
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polyline

/**
 * 보호자 메인. osmdroid 지도 위에 아이의 현재 위치를 찍는다.
 *
 * children/{childUid} 문서(= status. 설계서는 별도 하위 문서로 그렸지만
 * StatusReporter 가 문서 자체를 status 로 쓰기로 했다)를 실시간 구독해
 * 상단 카드 문구와 지도 마커를 함께 갱신한다.
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
    // "이미 그린 적 있는가"를 판정한다 — 아래 render() 참고.
    private var childMarker: Marker? = null
    private var routeLine: Polyline? = null
    private var statusListener: ListenerRegistration? = null

    // 자녀가 members 에 들어오는 순간을 계속 지켜본다(Task 8 이전엔 findChildUid 를
    // onViewCreated 에서 한 번만 불러 화면을 켜 둔 채로 페어링이 끝나면 다시 만들기
    // 전까지 "연결 안 됨"이 안 풀리는 문제가 있었다). 이 리스너 하나가 statusListener·
    // segmentListener 두 개를 필요할 때마다 다시 걸어 준다.
    private var joinedListener: ListenerRegistration? = null

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

        // 타임라인은 지도와 무관하다. subscribeSegments 가 childUid 를 못 구해 구독이
        // 아예 안 걸리는 경우(아직 아이 폰이 첫 보고를 안 올린 첫 실행 구간) renderTimeline
        // 이 한 번도 안 불릴 수 있는데, 그때 화면이 "아무 설명 없이 텅 빈 채로" 남으면
        // 고장으로 읽힌다. 그래서 구독 결과를 기다리지 않고 여기서 빈 목록으로 한 번 먼저
        // 그려 empty 안내부터 보여준다 — 실제 데이터가 오면 renderTimeline 이 다시 불려
        // 덮어쓴다.
        timelineAdapter = TimelineAdapter(zone) { doc -> focusOn(doc.lat, doc.lng) }
        binding.timelineList.layoutManager = LinearLayoutManager(requireContext())
        binding.timelineList.adapter = timelineAdapter
        renderTimeline(emptyList())
        binding.prevDayButton.setOnClickListener { changeDay(-1) }
        binding.nextDayButton.setOnClickListener { changeDay(1) }
        renderDayHeader()

        // subscribe() 는 지도 초기화보다 먼저 부른다. 카카오 시절엔 앱키가 없는 기기에서
        // subscribe() 호출부 자체가 앱키 가드 뒤에 있어 건너뛰어지는 사고가 있었다(관련
        // 기록: docs/known-issues.md). osmdroid로 바뀌며 앱키 가드 자체가 없어져 같은
        // 사고는 구조적으로 재발할 수 없지만, "데이터 구독은 지도 설정과 무관하며 항상
        // 먼저 돈다"는 순서는 그대로 지킨다.
        subscribe()

        // osmdroid는 mapView.start(...) 같은 비동기 준비 콜백이 없다 — MapView 는
        // 위 FragmentMapTimelineBinding.inflate() 시점에 XML 인플레이트로 이미 완전히
        // 생성되어 있고, 마커/폴리라인을 바로 추가해도 된다. 그래서 카카오 시절의
        // pendingStatus(맵 준비 전에 도착한 Firestore 스냅샷을 잠깐 담아뒀다가 onMapReady
        // 에서 다시 그리던 값)는 필요 없어져 지웠다 — render()/drawRoute() 는 이제
        // _binding 널 체크만으로 충분하다.
        binding.mapView.setMultiTouchControls(true)
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
            onError = { e -> _binding?.statusBar?.text = getString(R.string.map_error, errorMessage(requireContext(), e)) },
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
            onChange = { status ->
                render(status)
                // 연결 끊김 배너는 액티비티 레이아웃에 있고 리스너를 따로 붙이지 않는다.
                // 지도 탭은 앱을 켜면 항상 만들어지고 show/hide 라 탭을 옮겨도 살아
                // 있으므로, 관리 탭을 한 번도 안 여는 부모에게도 이 경로로 값이 계속
                // 들어간다([GuardianMainActivity.reportChildStatus] 주석).
                (activity as? GuardianMainActivity)?.reportChildStatus(status)
            },
            onError = { e -> _binding?.statusBar?.text = getString(R.string.map_error, errorMessage(requireContext(), e)) },
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

        val point = GeoPoint(status.lat, status.lng)
        val marker = childMarker
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
            b.mapView.controller.setZoom(16.0)
            b.mapView.controller.setCenter(point)
        } else {
            marker.position = point
            b.mapView.invalidate()
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
        // Fix 6: 새 리스너를 걸기 전에 화면을 먼저 빈 상태로 되돌린다. 안 그러면
        // 새 리스너가 에러로 죽었을 때(색인 없음 등) renderTimeline 이 한 번도 안
        // 불려서, 어제 목록과 어제 경로선이 오늘 헤더 아래 그대로 남는다 — 부모가
        // 아이 위치를 잘못 읽는 상태다. 여기서 지우면 drawRoute(emptyList()) 도
        // 같이 불려 경로선까지 함께 지워진다.
        renderTimeline(emptyList())
        val familyId = RoleStore(requireContext()).familyId ?: return
        val uid = childUid ?: return
        segmentListener = SegmentRepository.observeSegmentsOfDay(
            familyId = familyId,
            childUid = uid,
            dayKey = dayKey,
            onChange = { docs -> renderTimeline(docs) },
            onError = { e ->
                // Fix 7: map_error 를 그대로 쓰면 타임라인(색인 누락 등) 실패가
                // "지도를 불러오지 못했어요"로 보인다 — 실제로는 지도가 멀쩡한데도.
                // 다음 status 스냅샷이 10분 안에 이 문구를 덮어쓰긴 하지만, 그 전에
                // 뜨는 짧은 순간에도 원인이 맞는 문구여야 한다.
                _binding?.statusBar?.text = getString(R.string.timeline_error, errorMessage(requireContext(), e))
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
        val b = _binding ?: return
        val point = GeoPoint(lat, lng)
        b.mapView.controller.setZoom(16.0)
        b.mapView.controller.setCenter(point)
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
     * 쌓여 지도가 낙서가 된다.
     */
    private fun drawRoute(docs: List<SegmentDoc>) {
        val b = _binding ?: return

        // 위치 마커는 overlays 리스트의 다른 요소라 별개다 — 여기서는 이전 경로선만
        // 지우고 마커는 건드리지 않는다.
        routeLine?.let { b.mapView.overlays.remove(it) }
        routeLine = null

        val positions = docs.map { GeoPoint(it.lat, it.lng) }
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
        // 마커가 처음 생길 때(render())만 이동하고, 경로 갱신으로는 시점을 뺏지 않는다.
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

    override fun onDestroyView() {
        joinedListener?.remove()
        joinedListener = null
        statusListener?.remove()
        statusListener = null
        segmentListener?.remove()
        segmentListener = null
        // onDetach()는 osmdroid가 내부적으로 띄운 타일 다운로드 스레드·리시버를
        // 정리한다 — 안 부르면 화면을 나갔다 들어올 때마다 조금씩 샌다.
        _binding?.mapView?.onDetach()
        childMarker = null
        routeLine = null
        _binding = null
        super.onDestroyView()
    }

    private companion object {
        private const val ROUTE_LINE_WIDTH = 14f
        private const val ROUTE_COLOR = 0xFF3D6DF5.toInt()
    }
}
