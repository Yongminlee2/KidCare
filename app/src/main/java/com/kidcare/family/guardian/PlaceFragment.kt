package com.kidcare.family.guardian

import android.annotation.SuppressLint
import android.os.Bundle
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AlertDialog
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.firebase.firestore.ListenerRegistration
import com.kidcare.family.R
import com.kidcare.family.core.CommandRepository
import com.kidcare.family.core.FamilyRepository
import com.kidcare.family.core.PlaceRepository
import com.kidcare.family.core.RoleStore
import com.kidcare.family.core.errorMessage
import com.kidcare.family.core.model.CommandType
import com.kidcare.family.core.model.PlaceDoc
import com.kidcare.family.databinding.FragmentPlaceBinding
import com.naver.maps.geometry.LatLng
import com.naver.maps.map.CameraUpdate
import com.naver.maps.map.NaverMap
import com.naver.maps.map.OnMapReadyCallback
import com.naver.maps.map.overlay.CircleOverlay
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.util.UUID
import kotlin.math.roundToInt

/**
 * 장소 탭. "학교에 도착하면 알려줘" 같은 장소를 만들고 고치고 지운다(설계서 §4.6).
 *
 * ## 좌표는 숫자로 넣게 하지 않는다
 *
 * 위도·경도를 입력칸으로 받으면 부모는 이 화면을 못 쓴다. 대신 지도를 띄우고 **화면
 * 한가운데를 좌표로 삼는다.** 가운데에는 고정된 십자가 있고(`ic_map_crosshair`), 그
 * 둘레에 지금 고른 반경만큼의 원이 함께 그려져서, 부모는 "어디를" 과 "얼마나 넓게"를
 * 같은 그림에서 동시에 본다. 확인 버튼을 따로 두지 않은 것은 그 버튼이 아무 일도 하지
 * 않기 때문이다 — 지도 가운데가 곧 좌표이므로 저장이 그대로 그 값을 쓴다.
 *
 * 지도의 시작 위치는 **아이의 마지막 확인 위치**다. 부모가 정하려는 장소는 거의 항상
 * 아이가 다니는 곳 근처다. 그 위치를 아직 한 번도 못 받았으면 한반도 전체가 보이는
 * 배율로 열고 그 사실을 화면에 적는다([renderEditorMapNotice]) — 서울 시청 같은 그럴듯한
 * 좌표를 기본값으로 찍어두면 부모가 그 자리를 "확인된 어딘가"로 읽는다.
 *
 * ## 장소가 바뀌면 반드시 아이 폰에 알린다
 *
 * 저장·수정·삭제·알림 스위치 변경이 전부 [writeThenNotify] 한 갈래를 지나고, 그 함수가
 * 쓰기 뒤에 [CommandType.SYNC_RULES] 를 보낸다. 쓰기 경로를 하나로 좁혀 둔 것이 요점이다 —
 * 나중에 경로를 하나 더 만들어도 이 함수를 안 지나면 컴파일러가 아니라 사람이 알아채야
 * 하는데, 그 사람이 놓친 사고가 4단계 Task 10 에서 한 번 있었다.
 *
 * 알림 스위치는 편집 판 안에만 있으므로 "스위치를 껐다"는 곧 "장소를 고쳤다"이고 저장을
 * 지난다. 그래서 실제 쓰기 갈래는 저장(만들기·고치기 공용)과 삭제 **둘뿐**이며 둘 다
 * [writeThenNotify] 안에 있다.
 *
 * 못 보낸 명령은 [PlaceSyncStore] 에 깃발로 남아 화면을 다시 열 때 재시도된다. 여기서
 * 특히 위험한 것은 **삭제**다 — 아이 폰이 모르면 이미 지운 장소의 지오펜스가 그대로
 * 남아 계속 울리고, 부모 화면에는 그 장소가 없으니 원인을 찾을 방법이 없다.
 *
 * ## 개수 상한
 *
 * 20개다(설계서 §4.6). 21번째를 만들려 하면 **추가 버튼이 잠기고 그 위에 이유가 뜬다**
 * ([renderList]) — 반응 없는 버튼만 두면 부모는 앱이 고장 난 줄 안다.
 */
class PlaceFragment : Fragment(), OnMapReadyCallback {

    private var _binding: FragmentPlaceBinding? = null

    private var placeListener: ListenerRegistration? = null
    private var joinedListener: ListenerRegistration? = null

    private var familyId: String? = null
    private var childUid: String? = null

    private lateinit var adapter: PlaceAdapter

    /** 마지막 스냅샷. 개수 상한 판정이 이 목록을 읽는다. */
    private var places: List<PlaceDoc> = emptyList()

    /** 목록을 불러왔는가. 세 상태를 왜 구분하는지는 [ListLoad] 주석에 있다. */
    private var listLoad = ListLoad.LOADING

    /**
     * 아이의 마지막 확인 위치. 새 장소를 만들 때 지도의 시작점이다.
     * 한 번만 읽는다(아래 [subscribe] 의 onJoined) — 정확한 현재 위치가 아니라
     * "그 동네"만 필요해서 다시 읽을 이유가 없다.
     */
    private var childHome: LatLng? = null

    /** 지금 화면이 책임지는 쓰기의 세대 번호. 규율은 [ScheduleFragment.writeGeneration] 과 같다. */
    private var writeGeneration = 0

    private val syncStore by lazy { PlaceSyncStore(requireContext().applicationContext) }

    /** 장소를 건드렸는데 아직 [CommandType.SYNC_RULES] 를 보내지 못했는가([PlaceSyncStore]). */
    private var pendingSync: Boolean
        get() = childUid?.let { syncStore.pendingSync(it) } ?: false
        set(value) {
            childUid?.let { syncStore.setPendingSync(it, value) }
            renderPendingSync()
        }

    // ------------------------------------------------------------ 편집 판 상태
    // 편집 중인 값의 정답은 전부 이 필드들이다. 뷰는 비추기만 한다
    // (fragment_place.xml 의 saveEnabled=false 주석 참고).

    private var editorVisible = false

    /** 고치는 중이면 그 문서 ID, 새로 만드는 중이면 null. */
    private var editorPlaceId: String? = null

    /** 새 장소를 만드는 동안 쓸 문서 ID. 저장이 두 번 나가도 장소가 두 개 생기지 않게
     *  편집을 열 때 미리 정해 둔다([ScheduleFragment.editorNewDocId] 와 같은 이유). */
    private var editorNewDocId: String? = null
    private var editorName = ""
    private var editorLat = 0.0
    private var editorLng = 0.0
    private var editorRadius = DEFAULT_RADIUS_METERS
    private var editorNotifyEnter = true
    private var editorNotifyExit = true

    /**
     * 지금 편집 중인 좌표가 **뜻이 있는 값인가.**
     *
     * 좌표가 (0,0) 인지로 판단하면 안 된다. 지도를 프로그램으로 옮기면(아이 위치로
     * 옮기거나, 아이 위치를 몰라 한반도 전체로 여는 것) 지도 SDK가 카메라 이벤트를
     * 되쏘아 [onMapMoved] 가 그 자리를 좌표로 적어버리기 때문이다 — 그 순간 "아직
     * 안 정했다"와 "한반도 한가운데를 골랐다"가 구분되지 않는다. 그 이벤트가 동기로
     * 오는지 다음 그리기에서 오는지도 SDK 내부 사정이라, 순서에 기대면 기기마다
     * 다르게 동작한다.
     *
     * 그래서 뜻이 생기는 순간만 세 가지로 못박는다: 있는 장소를 고칠 때, 아이의 마지막
     * 확인 위치로 지도를 열 때, 그리고 **부모가 지도에 손을 댈 때**. 마지막 것은 터치
     * 리스너라 사람이 만졌을 때만 불린다.
     */
    private var coordinateChosen = false

    private var editorBusy = false

    /** [renderEditor] 가 뷰에 값을 대입하는 동안 리스너가 도로 상태를 고치지 못하게 막는다. */
    private var suppressWidgetCallbacks = false

    /**
     * 지도를 **프로그램으로** 옮기는 동안 [onMapMoved] 가 좌표를 되받아쓰지 못하게 막는다.
     *
     * 없으면 이렇게 망가진다: 편집을 열며 좌표를 아이 위치로 정해두고 지도를 옮기는데,
     * 카메라 이동이 이벤트를 되쏜다 → [onMapMoved] 가 **아직 안 옮겨진**
     * 지도의 중심(0,0)을 좌표로 적어버린다 → 바로 뒤따르는 setCenter 가 그 0,0 으로
     * 지도를 옮긴다. 부모가 장소를 처음 추가할 때 지도가 대서양 한가운데(파란 사각형)로
     * 열리던 것이 이것이었다. 지도가 명령을 무시한 게 아니라 우리가 0,0 으로 가라고
     * 시킨 것이다 — 실기기 로그에 lat=0.0 이 찍혀서야 드러났다.
     */
    private var suppressMapCallbacks = false

    private var backCallback: OnBackPressedCallback? = null
    private var activeDialog: AlertDialog? = null
    private var syncRetryJob: Job? = null

    /** 반경 원. 지도 위에서 하나만 유지하고 점만 갈아 끼운다. */
    private var naverMap: NaverMap? = null
    private var radiusCircle: CircleOverlay? = null

    /** 지도 이동을 좌표로 옮기는 리스너. [onDestroyView] 에서 반드시 뗀다. */
    private var mapListener: NaverMap.OnCameraIdleListener? = null

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        val binding = FragmentPlaceBinding.inflate(inflater, container, false)
        _binding = binding
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        val b = _binding ?: return

        restoreState(savedInstanceState)

        adapter = PlaceAdapter(
            onEdit = { doc -> openEditor(doc) },
            onDelete = { doc -> confirmDelete(doc) },
        )
        b.placeList.layoutManager = LinearLayoutManager(requireContext())
        b.placeList.adapter = adapter

        b.addButton.setOnClickListener { openEditor(null) }
        b.editorCancelButton.setOnClickListener { cancelEditor() }
        b.editorSaveButton.setOnClickListener { onSaveClicked() }
        b.syncRetryButton.setOnClickListener { retryPendingSync() }

        b.radiusSlider.addOnChangeListener { _, value, _ ->
            if (suppressWidgetCallbacks) return@addOnChangeListener
            editorRadius = value.toDouble()
            renderRadius()
            drawRadiusCircle()
        }
        b.notifyEnterSwitch.setOnClickListener {
            editorNotifyEnter = b.notifyEnterSwitch.isChecked
            renderNotifyHint()
        }
        b.notifyExitSwitch.setOnClickListener {
            editorNotifyExit = b.notifyExitSwitch.isChecked
            renderNotifyHint()
        }

        setUpMap(b, savedInstanceState)

        val callback = object : OnBackPressedCallback(editorVisible) {
            override fun handleOnBackPressed() = cancelEditor()
        }
        requireActivity().onBackPressedDispatcher.addCallback(viewLifecycleOwner, callback)
        backCallback = callback

        renderEditor()
        // 화면을 회전하면 MapView 가 통째로 새로 만들어진다 — 필드에 살아남은 좌표를
        // 지도에 다시 심어주지 않으면, 편집 판은 열려 있는데 지도만 엉뚱한 자리를
        // 비추고 그 뒤 첫 스크롤이 **그 엉뚱한 자리를 좌표로 덮어쓴다.**
        if (editorVisible) centerEditorMap()
        renderList()
        renderPendingSync()
        subscribe()
    }

    /**
     * 지도를 준비한다.
     *
     * 터치 가로채기를 막는 한 줄이 없으면 이 화면은 쓸 수 없다: 편집 판이 ScrollView 라
     * 세로 드래그를 스크롤이 먼저 먹어버려 **지도를 위아래로 못 옮긴다.** 좌표를 정하는
     * 것이 이 화면의 전부인데 그 동작이 반만 되는 셈이다.
     */
    @SuppressLint("ClickableViewAccessibility")
    private fun setUpMap(b: FragmentPlaceBinding, savedInstanceState: Bundle?) {
        b.placeMap.onCreate(savedInstanceState)
        b.placeMap.setOnTouchListener { v, event ->
            v.parent?.requestDisallowInterceptTouchEvent(true)
            // 사람이 지도를 만졌다 = 이 자리를 골랐다. 스크롤 이벤트가 아니라 터치로
            // 판단하는 이유는 [coordinateChosen] 주석에 있다.
            if (event.actionMasked == MotionEvent.ACTION_DOWN && !coordinateChosen) {
                coordinateChosen = true
                renderEditorMapNotice()
            }
            // false 를 돌려줘야 네이버 지도 자신의 터치 처리(이동·확대)가 그대로 이어진다.
            false
        }
        b.placeMap.getMapAsync(this)
    }

    override fun onMapReady(map: NaverMap) {
        if (_binding == null || !isAdded) return
        naverMap = map
        map.uiSettings.apply {
            isZoomControlEnabled = false
            isLocationButtonEnabled = false
            isScaleBarEnabled = false
            setLogoMargin(dp(8), 0, 0, dp(8))
        }
        val listener = NaverMap.OnCameraIdleListener { onMapMoved() }
        map.addOnCameraIdleListener(listener)
        mapListener = listener
        if (editorVisible) centerEditorMap()
    }

    /** 지도가 움직였다 = 좌표가 바뀌었다. 화면 가운데가 곧 이 장소의 가운데다. */
    private fun onMapMoved() {
        if (suppressMapCallbacks) return
        _binding ?: return
        val center = naverMap?.cameraPosition?.target ?: return
        if (!isValidCoordinate(center.latitude, center.longitude)) return
        editorLat = center.latitude
        editorLng = center.longitude
        drawRadiusCircle()
    }

    override fun onStart() {
        super.onStart()
        _binding?.placeMap?.onStart()
    }

    override fun onResume() {
        super.onResume()
        _binding?.placeMap?.onResume()
        if (!isHidden) retryPendingSync()
    }

    override fun onPause() {
        _binding?.placeMap?.onPause()
        super.onPause()
    }

    override fun onStop() {
        _binding?.placeMap?.onStop()
        super.onStop()
    }

    override fun onLowMemory() {
        _binding?.placeMap?.onLowMemory()
        super.onLowMemory()
    }

    /**
     * 탭을 옮겨도 이 프래그먼트는 죽지 않는다([GuardianMainActivity] 가 show/hide 를
     * 쓴다). 그래서 탭 전환에서는 [onResume] 이 아니라 이 콜백이 불린다 — 못 보낸
     * 명령의 재시도를 여기에도 걸어야 부모가 실제로 밟는 길이 덮인다
     * ([ScheduleFragment.onHiddenChanged] 와 같은 이유).
     */
    override fun onHiddenChanged(hidden: Boolean) {
        super.onHiddenChanged(hidden)
        if (!hidden) retryPendingSync()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        _binding?.placeMap?.onSaveInstanceState(outState)
        outState.putBoolean(KEY_EDITOR_VISIBLE, editorVisible)
        outState.putString(KEY_EDITOR_PLACE_ID, editorPlaceId)
        outState.putString(KEY_EDITOR_NEW_DOC_ID, editorNewDocId)
        outState.putString(KEY_EDITOR_NAME, currentNameInput())
        outState.putDouble(KEY_EDITOR_LAT, editorLat)
        outState.putDouble(KEY_EDITOR_LNG, editorLng)
        outState.putDouble(KEY_EDITOR_RADIUS, editorRadius)
        outState.putBoolean(KEY_EDITOR_NOTIFY_ENTER, editorNotifyEnter)
        outState.putBoolean(KEY_EDITOR_NOTIFY_EXIT, editorNotifyExit)
        outState.putBoolean(KEY_COORDINATE_CHOSEN, coordinateChosen)
    }

    private fun restoreState(saved: Bundle?) {
        saved ?: return
        editorVisible = saved.getBoolean(KEY_EDITOR_VISIBLE, false)
        editorPlaceId = saved.getString(KEY_EDITOR_PLACE_ID)
        editorNewDocId = saved.getString(KEY_EDITOR_NEW_DOC_ID)
        editorName = saved.getString(KEY_EDITOR_NAME).orEmpty()
        editorLat = saved.getDouble(KEY_EDITOR_LAT, 0.0)
        editorLng = saved.getDouble(KEY_EDITOR_LNG, 0.0)
        editorRadius = snapRadius(saved.getDouble(KEY_EDITOR_RADIUS, DEFAULT_RADIUS_METERS))
        editorNotifyEnter = saved.getBoolean(KEY_EDITOR_NOTIFY_ENTER, true)
        editorNotifyExit = saved.getBoolean(KEY_EDITOR_NOTIFY_EXIT, true)
        coordinateChosen = saved.getBoolean(KEY_COORDINATE_CHOSEN, false) &&
            isValidCoordinate(editorLat, editorLng)
        // 진행 중이던 쓰기의 코루틴은 뷰와 함께 취소됐다. 잠금만 남으면 저장 버튼이
        // 영영 안 눌린다(쓰기 자체는 Firestore 가 이어서 끝낸다).
        editorBusy = false
    }

    // ---------------------------------------------------------------- 구독

    private fun subscribe() {
        val roleStore = RoleStore(requireContext())
        val fid = roleStore.familyId
        if (fid == null) {
            // 구독을 시작조차 못 한다 = 목록을 못 불러온 것이다([AlertFragment.subscribe] 와 같다).
            listLoad = ListLoad.FAILED
            showState(getString(R.string.place_no_family))
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
        childUid = selectedUid
        // 리스너의 첫 스냅샷은 같은 uid라 아래 중복 방지 조건에서 반환된다.
        // 선택된 아이의 최근 위치는 여기서 한 번 읽어 편집 지도의 시작점으로 쓴다.
        loadChildHome(fid, selectedUid)

        placeListener = PlaceRepository.observePlaces(
            fid,
            selectedUid,
            onChange = { docs, fromCache -> onPlacesChanged(docs, fromCache) },
            onError = { e ->
                val ctx = context ?: return@observePlaces
                _binding ?: return@observePlaces
                listLoad = ListLoad.FAILED
                showState(getString(R.string.place_error_format, errorMessage(ctx, e)))
                renderList()
            },
        )

        joinedListener = FamilyRepository.observeChildJoined(
            fid,
            preferredChildUid = selectedUid,
            onJoined = { uid ->
                if (uid == childUid) return@observeChildJoined
                childUid = uid
                loadChildHome(fid, uid)
                retryPendingSync()
            },
            onError = { e ->
                val ctx = context ?: return@observeChildJoined
                _binding ?: return@observeChildJoined
                showState(errorMessage(ctx, e))
            },
        )
    }

    /**
     * 아이의 마지막 확인 위치를 **한 번** 읽는다. 새 장소를 만들 때 지도가 열리는 자리다.
     *
     * 실패해도 화면에 아무 말도 하지 않는다 — 이건 편의를 위한 읽기지 이 화면의 기능이
     * 아니고, 못 읽었을 때 부모가 할 일은 "지도를 손으로 옮기기" 하나뿐인데 그 안내는
     * 편집을 열 때 [renderEditorMapNotice] 가 이미 한다.
     */
    private fun loadChildHome(fid: String, uid: String) {
        _binding ?: return
        viewLifecycleOwner.lifecycleScope.launch {
            try {
                val status = FamilyRepository.fetchChildStatus(fid, uid) ?: return@launch
                if (!isValidCoordinate(status.lat, status.lng) ||
                    (status.lat == 0.0 && status.lng == 0.0)
                ) return@launch
                _binding ?: return@launch
                val home = LatLng(status.lat, status.lng)
                childHome = home
                // 이미 새 장소 편집을 열어 둔 채 기다리고 있었다면 그때 지도를 옮겨준다.
                // 부모가 그 사이 손으로 옮겨봤다면 coordinateChosen 이 이미 true 라
                // 건드리지 않는다 — 정해둔 자리를 뒤늦게 뺏으면 안 된다.
                if (editorVisible && !coordinateChosen) {
                    editorLat = home.latitude
                    editorLng = home.longitude
                    coordinateChosen = true
                    centerEditorMap()
                }
                renderEditorMapNotice()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // 로그도 화면도 남기지 않는다(위 문서 주석).
            }
        }
    }

    private fun onPlacesChanged(docs: List<PlaceDoc>, fromCache: Boolean) {
        // observePlaces 는 정렬 없이 준다(문서 ID 순). 부모 눈에는 이름순이 자연스럽고,
        // 자녀 폰이 지오펜스 20개를 자를 때 쓰는 기준도 이름순이라 두 화면이 같은 순서를
        // 본다(PlaceWatcher.registerGeofences).
        places = docs.sortedWith(compareBy({ it.name }, { it.id }))
        // 캐시본으로는 LOADED 로 올리지 않는다 — 이유는 [ListLoad] 주석("오프라인은
        // 네 번째 상태가 아니다").
        listLoad = if (fromCache) ListLoad.LOADING else ListLoad.LOADED
        renderList()
    }

    // ---------------------------------------------------------------- 편집 판

    /** [doc] 이 null 이면 새 장소, 아니면 그 장소를 고친다. */
    private fun openEditor(doc: PlaceDoc?) {
        // 상한에 걸리면 추가 버튼이 이미 잠겨 있지만, 잠기기 직전에 눌린 경우를 위해
        // 여기서도 막는다. 상한 안내는 목록 위에 이미 떠 있다.
        if (doc == null && places.size >= MAX_PLACES) return

        editorPlaceId = doc?.id
        editorNewDocId = if (doc == null) UUID.randomUUID().toString() else null
        editorName = doc?.name.orEmpty()
        // 새 장소는 아이의 마지막 확인 위치에서 시작한다 — 부모가 정하려는 곳은 거의
        // 항상 그 근처다. 그 위치를 아직 모르면 좌표는 "아직 안 정해짐"으로 두고
        // centerEditorMap 이 지도를 넓게 연다.
        val home = childHome
        editorLat = doc?.lat ?: home?.latitude ?: 0.0
        editorLng = doc?.lng ?: home?.longitude ?: 0.0
        coordinateChosen = (doc != null || home != null) &&
            isValidCoordinate(editorLat, editorLng)
        editorRadius = snapRadius(doc?.radiusMeters?.takeIf { it > 0.0 } ?: DEFAULT_RADIUS_METERS)
        editorNotifyEnter = doc?.notifyEnter ?: true
        editorNotifyExit = doc?.notifyExit ?: true
        editorBusy = false
        editorVisible = true
        showEditorStatus(null)
        showState(null)
        renderEditor()
        centerEditorMap()
    }

    private fun cancelEditor() {
        if (editorBusy) return
        // 쓰기가 도는 중에 취소하고 다른 장소를 열면, 먼저 나간 코루틴이 돌아와 남의
        // 편집 판을 닫는다([ScheduleFragment.cancelEditor] 와 같은 규율).
        writeGeneration++
        closeEditor()
    }

    private fun closeEditor() {
        editorVisible = false
        editorBusy = false
        editorPlaceId = null
        editorNewDocId = null
        showEditorStatus(null)
        renderEditor()
    }

    /**
     * 지도를 편집 중인 좌표로 옮긴다. 좌표가 아직 없으면(새 장소) 아이의 마지막 확인
     * 위치로, 그것도 없으면 한반도 전체가 보이는 배율로 연다.
     */
    private fun centerEditorMap() {
        val b = _binding ?: return
        // 편집 판은 직전까지 GONE이라 크기가 0일 수 있다. 뷰가 실제 레이아웃된 다음
        // 네이버 지도 객체가 준비됐을 때 카메라를 적용한다.
        postForCurrentView(b.placeMap) { applyEditorCamera() }
    }

    /** 지도에 크기가 생긴 뒤에만 부른다([centerEditorMap]). */
    private fun applyEditorCamera() {
        // 그리기 직전은 화면이 사라진 뒤에도 올 수 있다.
        val laid = _binding ?: return
        val map = naverMap ?: return
        suppressMapCallbacks = true
        val chosenCenter = editorCenterOrNull()
        if (coordinateChosen && chosenCenter == null) coordinateChosen = false
        val update = if (coordinateChosen && chosenCenter != null) {
            CameraUpdate.scrollAndZoomTo(chosenCenter, PLACE_ZOOM)
        } else {
            // 아이 위치를 모른다. 그럴듯한 좌표를 기본값으로 찍어두지 않고 넓게 연다 —
            // 좌표는 부모가 지도에 손을 대는 순간에야 생긴다([coordinateChosen]).
            CameraUpdate.scrollAndZoomTo(LatLng(COUNTRY_LAT, COUNTRY_LNG), COUNTRY_ZOOM)
        }
        map.moveCamera(update)
        // 되쏘는 이벤트는 이 프레임 안에 오기도 하고 다음 그리기에 오기도 한다
        // (SDK 내부 사정). 다음 메시지까지 미뤄 두 경우를 모두 덮는다.
        postForCurrentView(laid.placeMap) { suppressMapCallbacks = false }
        drawRadiusCircle()
        renderEditorMapNotice()
    }

    /**
     * 반경을 슬라이더 눈금(50m)에 맞춘다.
     *
     * [com.google.android.material.slider.Slider] 는 눈금에 안 맞는 값을 대입하면
     * **그 자리에서 예외로 죽는다.** 이 화면으로 만든 문서는 항상 눈금 위에 있지만,
     * 콘솔에서 손으로 고친 문서 하나가 부모 폰의 장소 탭을 통째로 못 열게 만들면 안 된다.
     */
    private fun snapRadius(meters: Double): Double {
        val steps = ((meters - MIN_RADIUS_METERS) / RADIUS_STEP_METERS).roundToInt()
        return (MIN_RADIUS_METERS + steps * RADIUS_STEP_METERS)
            .coerceIn(MIN_RADIUS_METERS, MAX_RADIUS_METERS)
    }

    /**
     * 지금 고른 반경만큼의 원을 지도 가운데에 그린다.
     *
     * 원이 없으면 슬라이더의 "300m"가 화면에서 아무 뜻이 없다 — 부모는 300m 가 자기
     * 아파트 단지보다 큰지 작은지 모른다. 네이버 [CircleOverlay]에 실제 미터 반경을 준다.
     *
     * 다만 색은 그쪽보다 진하다. 저 원은 "이만큼 불확실하다"는 번짐이라 안 보일수록
     * 좋지만, 이 원은 부모가 **지금 정하고 있는 값 자체**라 또렷해야 한다.
     */
    private fun drawRadiusCircle() {
        _binding ?: return
        val map = naverMap ?: return
        val center = editorCenterOrNull()
        if (!editorVisible || !coordinateChosen || center == null) {
            radiusCircle?.map = null
            radiusCircle = null
            return
        }
        val circle = radiusCircle ?: CircleOverlay(center, editorRadius).also {
            it.color = RADIUS_FILL_COLOR
            it.outlineColor = RADIUS_STROKE_COLOR
            it.outlineWidth = dp(RADIUS_STROKE_WIDTH_DP)
            // 기본 생성자의 중심은 NaN이다. 중심과 반경을 넣은 뒤에만 지도에 붙여야
            // 네이버 SDK가 "center is invalid"로 앱을 종료시키지 않는다.
            it.map = map
            radiusCircle = it
        }
        circle.center = center
        circle.radius = editorRadius
    }

    private fun editorCenterOrNull(): LatLng? =
        if (isValidCoordinate(editorLat, editorLng)) LatLng(editorLat, editorLng) else null

    private fun isValidCoordinate(lat: Double, lng: Double): Boolean =
        lat.isFinite() && lng.isFinite() && lat in -90.0..90.0 && lng in -180.0..180.0

    /**
     * 저장 버튼. 관문은 하나다 — **이름이 비면 막는다.**
     *
     * 이름이 알림 문구에 그대로 들어가기 때문이다("○○에 도착했어요"). 비면 부모 폰에
     * "에 도착했어요"가 뜬다.
     *
     * 좌표는 딱 한 경우에만 막는다 — 아이 위치를 몰라 지도를 한반도 전체로 열었는데
     * 부모가 지도를 한 번도 안 만진 경우([coordinateChosen]). 그대로 저장하면 한반도
     * 한가운데에 반경 200m 짜리 장소가 생기는데, 목록에는 멀쩡한 줄로 남아 부모는
     * 장소를 정해뒀다고 믿는다. 안내 문구는 이미 지도 위에 떠 있지만 저장 버튼 옆에도
     * 적는다 — 눌렀는데 아무 일도 안 일어나는 것이 이 앱에서 가장 나쁜 실패다.
     */
    private fun onSaveClicked() {
        val b = _binding ?: return
        if (editorBusy) return

        editorName = currentNameInput()
        if (editorName.isEmpty()) {
            b.editorNameError.visibility = View.VISIBLE
            return
        }
        b.editorNameError.visibility = View.GONE

        if (!coordinateChosen) {
            showEditorStatus(getString(R.string.place_editor_no_child_location))
            return
        }
        savePlace()
    }

    // ---------------------------------------------------------------- 쓰기

    /**
     * 장소를 쓰는 **유일한 두 갈래**가 지나는 자리. 쓰기 뒤에 반드시
     * [CommandType.SYNC_RULES] 를 보낸다(클래스 주석).
     *
     * [onWritten] 은 쓰기가 끝난 뒤 화면을 정리하는 일이고, 세대가 밀렸으면 부르지
     * 않는다. 반면 명령 발행([notifyChild])은 세대와 무관하게 **항상** 한다 — 부모가
     * 그 사이 다른 것을 만졌다고 해서 장소가 바뀐 사실이 없어지지는 않는다.
     */
    private fun writeThenNotify(
        busyMessage: String?,
        write: suspend () -> Unit,
        onWritten: (slow: Boolean) -> Unit,
        onFailed: (String) -> Unit,
    ) {
        val generation = ++writeGeneration
        if (busyMessage != null) showEditorStatus(busyMessage)
        // 쓰기보다 **먼저** 깃발을 세운다. 쓰기가 실패했는데 깃발이 남아 헛 명령을 한 번
        // 보내는 것은 무해하지만, 반대(쓰기는 됐는데 깃발이 없어 영영 안 알리는 것)는
        // 조용한 고장이다([ScheduleFragment.saveRule] 과 같은 순서).
        pendingSync = true

        viewLifecycleOwner.lifecycleScope.launch {
            try {
                val done = withTimeoutOrNull(WRITE_TIMEOUT_MILLIS) { write() }
                if (generation == writeGeneration && _binding != null) onWritten(done == null)
                notifyChild(generation)
            } catch (e: CancellationException) {
                // 화면을 떠나며 스코프가 취소된 것이다. 실패로 표시하면 안 된다.
                throw e
            } catch (e: Exception) {
                if (generation != writeGeneration) return@launch
                val ctx = context ?: return@launch
                _binding ?: return@launch
                onFailed(errorMessage(ctx, e))
            }
        }
    }

    /**
     * 장소 하나를 저장한다. 만들기와 고치기가 같은 경로다 — [PlaceRepository.savePlace]
     * 는 받은 ID 문서에 덮어쓰고, 그 ID 는 어느 쪽이든 우리가 미리 정해서 넘긴다.
     *
     * 쓰기가 끝날 때까지 편집 판을 닫지 않는다. 먼저 닫으면 거부됐을 때 방금 만든 줄이
     * 잠깐 보였다가 소리 없이 사라지고, 부모는 자기가 뭘 잘못 봤다고 생각한다.
     */
    private fun savePlace() {
        val fid = familyId
        val uid = childUid
        if (fid == null || uid == null) {
            showEditorStatus(getString(R.string.place_no_family))
            return
        }
        val doc = PlaceDoc(
            id = editorPlaceId ?: editorNewDocId ?: UUID.randomUUID().toString(),
            name = editorName,
            lat = editorLat,
            lng = editorLng,
            radiusMeters = editorRadius,
            notifyEnter = editorNotifyEnter,
            notifyExit = editorNotifyExit,
        )
        setEditorBusy(true)
        writeThenNotify(
            busyMessage = getString(R.string.place_saving),
            write = { PlaceRepository.savePlace(fid, uid, doc) },
            onWritten = { slow ->
                closeEditor()
                if (slow) showStateRes(R.string.place_save_slow) else showState(null)
            },
            onFailed = { message ->
                setEditorBusy(false)
                showEditorStatus(message)
            },
        )
    }

    private fun confirmDelete(doc: PlaceDoc) {
        val ctx = context ?: return
        showDialog(
            MaterialAlertDialogBuilder(ctx)
                .setTitle(R.string.place_delete_title)
                .setMessage(getString(R.string.place_delete_message, PlaceText.summary(ctx, doc)))
                .setPositiveButton(R.string.place_delete_confirm) { _, _ -> deletePlace(doc) }
                .setNegativeButton(R.string.place_delete_cancel, null)
        )
    }

    private fun deletePlace(doc: PlaceDoc) {
        val fid = familyId
        val uid = childUid
        if (fid == null || uid == null) {
            showState(getString(R.string.place_no_family))
            return
        }
        showState(getString(R.string.place_deleting))
        writeThenNotify(
            busyMessage = null,
            write = { PlaceRepository.deletePlace(fid, uid, doc.id) },
            onWritten = { slow -> if (slow) showStateRes(R.string.place_save_slow) else showState(null) },
            onFailed = { message -> showState(message) },
        )
    }

    /**
     * 아이 폰에 "장소가 바뀌었다"고 알린다. 자녀 폰의 `child/CommandHandler` 가 이
     * 명령으로 장소를 다시 읽고 지오펜스를 다시 건다.
     *
     * 예약 규칙과 **같은** 명령을 쓴다. 자녀 쪽이 그 하나로 예약과 장소를 둘 다 다시
     * 읽으므로 종류를 나눌 이유가 없고, 나누면 부모 쪽에 "어느 쪽을 보낼까" 하는 갈래가
     * 하나 늘어난다 — 그 갈래를 잘못 고르면 조용히 옛 상태로 돈다.
     */
    private suspend fun notifyChild(generation: Int) {
        val fid = familyId ?: return
        val uid = childUid
        if (uid == null) {
            // 보낼 곳이 없다. 아이 폰이 나중에 연결되면 TrackingService 가 뜨면서
            // 장소를 읽고 지오펜스를 거므로(child/TrackingService.refreshPlaces) 명령을
            // 기다릴 필요가 없다 — 깃발을 내린다.
            pendingSync = false
            if (generation == writeGeneration) showStateRes(R.string.place_sync_no_child)
            return
        }
        try {
            val commandId = withTimeoutOrNull(WRITE_TIMEOUT_MILLIS) {
                CommandRepository.send(fid, uid, CommandType.SYNC_RULES)
            }
            if (commandId == null) {
                // 오프라인이면 명령 문서도 로컬 큐에 남아 연결될 때 나간다. 그래도 깃발은
                // 내리지 않는다 — 한 번 더 보내는 비용보다 영영 안 보내는 위험이 크고,
                // 중복 SYNC_RULES 는 자녀 쪽에서 무해하다.
                if (generation == writeGeneration) showStateRes(R.string.place_sync_slow)
                return
            }
            pendingSync = false
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            val ctx = context ?: return
            if (generation != writeGeneration) return
            _binding ?: return
            showState(ctx.getString(R.string.place_sync_failed_format, errorMessage(ctx, e)))
        }
    }

    /**
     * 지난번에 못 보낸 [CommandType.SYNC_RULES] 를 한 번 더 보낸다. 부르는 곳이 넷인
     * 이유는 [ScheduleFragment.retryPendingSync] 와 같다 — 하나짜리 경로는 부모가 실제로
     * 밟지 않는 길이었다.
     */
    private fun retryPendingSync() {
        if (!pendingSync) return
        // 아직 아이 uid 를 모른다. 여기서 notifyChild 를 부르면 "연결되면 저절로
        // 적용돼요"로 깃발을 내려버리는데, 그건 아이가 정말 없을 때 할 말이지 리스너가
        // 첫 스냅샷을 아직 못 받은 상태에서 할 말이 아니다.
        if (childUid == null) return
        if (syncRetryJob?.isActive == true) return
        _binding ?: return
        val generation = writeGeneration
        syncRetryJob = viewLifecycleOwner.lifecycleScope.launch {
            try {
                notifyChild(generation)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // notifyChild 가 이미 자기 실패를 화면에 적는다.
            }
        }
    }

    // ---------------------------------------------------------------- 그리기

    private fun renderList() {
        val b = _binding ?: return
        adapter.submitList(places)
        b.placeEmpty.renderEmptyState(
            b.placeEmptyText, listLoad, places.isEmpty(), R.string.place_empty,
        )

        val full = places.size >= MAX_PLACES
        b.addButton.isEnabled = !full
        b.placeLimitNotice.visibility = if (full) View.VISIBLE else View.GONE
        if (full) {
            b.placeLimitNotice.text = getString(R.string.place_limit_notice, MAX_PLACES)
        }
    }

    private fun renderPendingSync() {
        val b = _binding ?: return
        b.syncPendingBar.visibility = if (pendingSync) View.VISIBLE else View.GONE
    }

    private fun renderEditor() {
        val b = _binding ?: return
        b.listPane.visibility = if (editorVisible) View.GONE else View.VISIBLE
        b.editorPane.visibility = if (editorVisible) View.VISIBLE else View.GONE
        backCallback?.isEnabled = editorVisible

        b.editorTitle.setText(
            if (editorPlaceId == null) R.string.place_editor_title_new
            else R.string.place_editor_title_edit
        )

        // 같은 값을 다시 넣으면 커서가 앞으로 튄다. 다를 때만 쓴다.
        if (currentNameInput() != editorName) b.nameInput.setText(editorName)
        b.editorNameError.visibility = View.GONE

        // 값을 대입하면 리스너가 불려 방금 그린 값을 상태로 되돌려 쓰는 순환이 생긴다.
        // 그리는 동안만 막는다(ScheduleFragment.renderEditor 와 같은 처리).
        suppressWidgetCallbacks = true
        b.radiusSlider.value = editorRadius.toFloat()
            .coerceIn(MIN_RADIUS_METERS.toFloat(), MAX_RADIUS_METERS.toFloat())
        b.notifyEnterSwitch.isChecked = editorNotifyEnter
        b.notifyExitSwitch.isChecked = editorNotifyExit
        suppressWidgetCallbacks = false

        renderRadius()
        renderNotifyHint()
        renderEditorMapNotice()
        setEditorBusy(editorBusy)
    }

    private fun renderRadius() {
        val b = _binding ?: return
        b.radiusValue.text = getString(R.string.place_editor_radius_value, editorRadius.toInt())
    }

    private fun renderNotifyHint() {
        val b = _binding ?: return
        b.notifyNoneHint.visibility =
            if (!editorNotifyEnter && !editorNotifyExit) View.VISIBLE else View.GONE
    }

    /** 아이 위치를 몰라 지도를 넓게 열었다는 안내. 부모가 지도를 만지면 사라진다. */
    private fun renderEditorMapNotice() {
        val b = _binding ?: return
        b.editorMapNotice.visibility = if (coordinateChosen) View.GONE else View.VISIBLE
    }

    private fun currentNameInput(): String = _binding?.nameInput?.text?.toString()?.trim() ?: editorName

    private fun setEditorBusy(busy: Boolean) {
        editorBusy = busy
        val b = _binding ?: return
        b.editorSaveButton.isEnabled = !busy
        // 취소도 함께 잠근다 — 쓰기가 도는 중에 되돌아가는 길을 열어두면 밀린 코루틴이
        // 남의 편집 판을 닫는다([ScheduleFragment.cancelEditor]).
        b.editorCancelButton.isEnabled = !busy
        b.editorProgress.visibility = if (busy) View.VISIBLE else View.GONE
    }

    private fun showEditorStatus(message: String?) {
        val b = _binding ?: return
        b.editorStatus.visibility = if (message == null) View.GONE else View.VISIBLE
        b.editorStatus.text = message.orEmpty()
        if (message == null) b.editorProgress.visibility = View.GONE
    }

    private fun showState(message: String?) {
        val b = _binding ?: return
        b.placeState.visibility = if (message == null) View.GONE else View.VISIBLE
        b.placeState.text = message.orEmpty()
    }

    /**
     * 화면이 아직 살아 있을 때만 문구를 적는다. [Fragment.getString] 은 화면이 떨어져
     * 나간 뒤에 부르면 그 자리에서 예외라 가드보다 **먼저** 평가되는 인자 계산이 위험하다
     * ([ScheduleFragment.showStateRes] 와 같은 이유).
     */
    private fun showStateRes(resId: Int) {
        _binding ?: return
        val ctx = context ?: return
        showState(ctx.getString(resId))
    }

    private fun showDialog(builder: MaterialAlertDialogBuilder) {
        activeDialog?.dismiss()
        activeDialog = builder.setOnDismissListener { activeDialog = null }.show()
    }

    override fun onDestroyView() {
        placeListener?.remove()
        placeListener = null
        joinedListener?.remove()
        joinedListener = null
        syncRetryJob?.cancel()
        syncRetryJob = null
        activeDialog?.dismiss()
        activeDialog = null
        backCallback?.remove()
        backCallback = null
        _binding?.radiusSlider?.clearOnChangeListeners()
        mapListener?.let { naverMap?.removeOnCameraIdleListener(it) }
        mapListener = null
        radiusCircle?.map = null
        radiusCircle = null
        naverMap = null
        _binding?.placeMap?.onDestroy()
        _binding = null
        super.onDestroyView()
    }

    private companion object {
        /**
         * 설계서 §4.6 의 장소 개수 상한. `child/PlaceWatcher.MAX_GEOFENCES` 와 **같은
         * 값이어야 한다** — guardian 은 child 를 import 하지 않는 것이 모듈 경계(설계서 §3)라
         * 여기 다시 적는다. 바꿀 일이 생기면 두 곳을 함께 고쳐야 한다.
         */
        const val MAX_PLACES = 20

        /** 슬라이더 범위·눈금. fragment_place.xml 의 valueFrom/valueTo/stepSize 와
         *  같아야 한다 — 어긋나면 Slider 가 값을 대입하는 순간 예외로 죽는다. */
        const val MIN_RADIUS_METERS = 100.0
        const val MAX_RADIUS_METERS = 1000.0
        const val RADIUS_STEP_METERS = 50.0

        /** 새 장소의 기본 반경. 학교·학원 한 채와 그 앞마당이 대략 이 정도다. */
        const val DEFAULT_RADIUS_METERS = 200.0

        /** 장소를 고를 때의 배율. 건물 하나와 그 둘레가 함께 보인다. */
        const val PLACE_ZOOM = 16.0

        /** 아이 위치를 모를 때. 한반도 전체가 들어오는 배율과 그 가운데다. */
        const val COUNTRY_ZOOM = 6.0
        const val COUNTRY_LAT = 36.5
        const val COUNTRY_LNG = 127.8

        /** 오프라인 쓰기를 화면이 무한정 붙잡지 않게 끊는 시간([ScheduleFragment] 와 같다). */
        const val WRITE_TIMEOUT_MILLIS = 15_000L

        // 지도 위의 반경 원. 하늘색 계열이라 앱의 다른 파란 요소(경로선)와 한 가족이지만,
        // 정확도 원(0x22/0x55)보다 진하다 — 저건 '번짐'이고 이건 부모가 지금 정하는 값이다.
        const val RADIUS_FILL_COLOR = 0x333D6DF5
        const val RADIUS_STROKE_COLOR = 0xBB3D6DF5.toInt()
        const val RADIUS_STROKE_WIDTH_DP = 4

        const val KEY_EDITOR_VISIBLE = "editor_visible"
        const val KEY_EDITOR_PLACE_ID = "editor_place_id"
        const val KEY_EDITOR_NEW_DOC_ID = "editor_new_doc_id"
        const val KEY_EDITOR_NAME = "editor_name"
        const val KEY_EDITOR_LAT = "editor_lat"
        const val KEY_EDITOR_LNG = "editor_lng"
        const val KEY_EDITOR_RADIUS = "editor_radius"
        const val KEY_EDITOR_NOTIFY_ENTER = "editor_notify_enter"
        const val KEY_EDITOR_NOTIFY_EXIT = "editor_notify_exit"
        const val KEY_COORDINATE_CHOSEN = "coordinate_chosen"
    }

    private fun dp(value: Int): Int {
        val density = _binding?.root?.resources?.displayMetrics?.density
            ?: context?.resources?.displayMetrics?.density
            ?: 1f
        return (value * density).toInt()
    }

    /** 지도 준비·카메라 작업이 이전 Fragment View에 뒤늦게 실행되는 것을 막는다. */
    private fun postForCurrentView(view: View, action: () -> Unit) {
        val expectedBinding = _binding ?: return
        view.post {
            if (_binding === expectedBinding && isAdded) action()
        }
    }
}
