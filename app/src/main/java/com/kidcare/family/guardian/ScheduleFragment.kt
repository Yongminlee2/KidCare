package com.kidcare.family.guardian

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AlertDialog
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import android.content.res.ColorStateList
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.android.material.button.MaterialButton
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.timepicker.MaterialTimePicker
import com.google.android.material.timepicker.TimeFormat
import com.google.firebase.firestore.ListenerRegistration
import com.kidcare.family.R
import com.kidcare.family.core.CommandRepository
import com.kidcare.family.core.HolidayCalendar
import com.kidcare.family.core.FamilyRepository
import com.kidcare.family.core.RoleStore
import com.kidcare.family.core.ScheduleRepository
import com.kidcare.family.core.errorMessage
import com.kidcare.family.core.model.CommandType
import com.kidcare.family.core.model.ScheduleDoc
import com.kidcare.family.core.toRule
import com.kidcare.family.databinding.FragmentScheduleBinding
import com.kidcare.family.logic.Holiday
import com.kidcare.family.logic.ScheduleResolver
import com.kidcare.family.logic.ScheduleRule
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.time.LocalDate
import java.util.UUID

/**
 * 예약 탭. "평일 밤에는 무음" 같은 시간대 규칙을 만들고 고치고 지운다(설계서 §4.3).
 *
 * ## 규칙이 바뀌면 반드시 아이 폰에 알린다
 *
 * 저장·수정·삭제·켬끔 **네 갈래 모두** 뒤에 [CommandType.SYNC_RULES] 를 보낸다
 * ([notifyChild]). 자녀 폰의 `child/CommandHandler` 가 그 명령을 받아
 * `child/ScheduleApplier.refresh` 를 불러 규칙을 다시 읽고 알람을 다시 건다.
 *
 * 이게 없으면 조용히 고장 난다. 자녀 폰이 다음 경계에 깨어나는 유일한 수단은
 * `ScheduleApplier` 가 걸어 둔 AlarmManager 알람 하나인데,
 *
 * - 규칙이 **하나도 없던** 가족에는 그 알람이 아예 안 걸려 있다
 *   (`ScheduleApplier.scheduleNextBoundary(null)` 이 취소한다). 그래서 **첫 규칙을
 *   만들면** 서비스가 다시 뜨거나 폰을 껐다 켜기 전까지 아무 일도 일어나지 않는다.
 * - 반대로 규칙을 **지웠을 때** 알리지 않으면 더 나쁘다: 이미 걸려 있던 알람이
 *   그대로 울려서, 부모가 지운 규칙 뒤의 모드가 한 번 더 적용된다.
 *
 * 자녀 폰이 `schedules/` 를 직접 구독하게 하면 명령이 필요 없어 보이지만, 상시
 * 유지해야 하는 리스너가 하나 늘어난다. 규칙 변경은 드문 일이라 그때만 명령 한 번을
 * 보내는 쪽이 싸다 — 이 선택은 계획서(4단계 Task 10 Step 2)의 판단이다.
 *
 * 그 명령이 아직 못 나갔으면 **목록 위에 그렇게 적는다**([renderPendingSync]).
 * 안 적으면 전달에 실패한 규칙과 실제로 적용된 규칙이 똑같이 보이고, 부모는 정해뒀다고
 * 믿는데 아이 폰은 옛 규칙대로 돈다. 그 깃발은 [ScheduleSyncStore] 에 남아 뒤로 가기와
 * 앱 재시작을 넘긴다.
 *
 * ## 낙관적으로 그리지 않는다
 *
 * 목록은 **오직 Firestore 스냅샷**([ScheduleRepository.observeSchedules])으로만
 * 그린다. 로컬 상태를 따로 두고 "저장했다 치고" 먼저 그리지 않는다. 편집 판은 쓰기가
 * 끝날 때까지 열린 채로 남고, 실패하면 그 자리에서 [errorMessage] 로 이유를 말하며
 * 부모가 입력한 값을 그대로 지킨다. 규칙이 저장되지도 않았는데 부모가 "정해 뒀다"고
 * 믿는 것이 이 화면에서 가장 나쁜 실패라서다.
 *
 * ## 우선순위
 *
 * [ScheduleDoc.priority] 는 만든 순서대로 자동 부여한다(나중에 만든 것이 큼). 화면에는
 * 절대 노출하지 않는다 — 부모가 "겹치면 나중 것이 이긴다"만 알면 되고, 숫자를 보여주면
 * 그걸 고치고 싶어지는데 v1 에는 고칠 방법이 없다(설계서 §4.3).
 */
class ScheduleFragment : Fragment() {

    private var _binding: FragmentScheduleBinding? = null

    private var scheduleListener: ListenerRegistration? = null
    private var joinedListener: ListenerRegistration? = null

    private var familyId: String? = null
    private var childUid: String? = null

    private lateinit var adapter: ScheduleAdapter

    /** 마지막 스냅샷. 겹침 판정과 새 규칙의 priority 계산이 이 목록을 읽는다. */
    private var rules: List<ScheduleDoc> = emptyList()

    /** 목록을 불러왔는가. 세 상태를 왜 구분하는지는 [ListLoad] 주석에 있다. */
    private var listLoad = ListLoad.LOADING

    /**
     * 지금 화면이 책임지는 쓰기의 세대 번호. 쓰기를 시작할 때마다, 그리고 편집을
     * 취소할 때마다 하나씩 는다.
     *
     * Task 9(ControlFragment)에서 값을 치른 문제와 같은 종류다: 쓰기는 왕복이 있는
     * 코루틴이라, 부모가 저장을 누른 뒤 취소하고 다른 규칙을 열면 먼저 나간 코루틴이
     * 돌아와 **지금 열려 있는 남의 편집 판을 닫아버린다.** 그래서 화면을 만지기 직전에
     * 세대를 확인하고, 최신이 아니면 화면은 건드리지 않는다.
     *
     * 다만 [notifyChild] 는 세대와 무관하게 **항상** 보낸다. 그건 "화면에 무엇을 쓸까"가
     * 아니라 "아이 폰이 새 규칙을 알아야 한다"는 사실이고, 부모가 그 사이 다른 걸
     * 눌렀다고 해서 규칙이 바뀐 사실이 없어지지는 않기 때문이다. 같은 명령이 두 번
     * 가도 자녀 쪽은 규칙을 다시 읽어 알람을 다시 걸 뿐이라 해가 없다.
     */
    private var writeGeneration = 0

    /**
     * 못 보낸 알림 깃발을 담아 두는 곳. 첫 접근은 [onViewCreated] 의 [renderPendingSync]
     * 라 반드시 붙어 있는 동안 초기화되고, 그때 잡아 두는 것은 애플리케이션 컨텍스트라
     * 화면이 사라진 뒤 코루틴에서 읽어도 안전하다.
     */
    private val syncStore by lazy { ScheduleSyncStore(requireContext().applicationContext) }

    /**
     * 규칙을 건드렸는데 아직 [CommandType.SYNC_RULES] 를 확실히 보내지 못했는가.
     *
     * 쓰기 **직전에** 세우고, 명령 발행이 성공한 뒤에만 내린다. 이게 없으면 "삭제는
     * 됐는데 알림은 못 보낸" 상태가 영구히 남고, 그때 자녀 폰에서는 이미 지워진 규칙의
     * 알람이 한 번 더 울린다.
     *
     * 값은 [ScheduleSyncStore](SharedPreferences)에 둔다. 예전에는
     * [onSaveInstanceState] 번들에만 있었는데 그건 회전만 넘기고 **뒤로 가기는 못
     * 넘긴다** — 그 근거는 [ScheduleSyncStore] 문서에 적었다. 값을 바꾸면 곧바로
     * 화면에도 반영한다: 전달 못 한 규칙과 전달된 규칙이 목록에서 똑같이 보이면
     * 부모는 그 차이를 알 방법이 없다.
     */
    private var pendingSync: Boolean
        get() = childUid?.let { syncStore.pendingSync(it) } ?: false
        set(value) {
            childUid?.let { syncStore.setPendingSync(it, value) }
            renderPendingSync()
        }

    // ------------------------------------------------------------ 편집 판 상태
    // 편집 중인 값은 전부 이 필드들이 정답이다. 뷰(토글 버튼)는 이 값을 비추기만 한다
    // — fragment_schedule.xml 의 saveEnabled=false 주석 참고.

    private var editorVisible = false

    /** 고치는 중이면 그 문서 ID, 새로 만드는 중이면 null. */
    private var editorRuleId: String? = null

    /**
     * 새 규칙을 만드는 동안 쓸 문서 ID. 편집을 열 때 한 번 정해 두고 저장할 때 그대로 쓴다.
     *
     * Firestore 가 알아서 만들어 주는 ID 를 쓰지 않는 이유: 그러면 저장이 **두 번**
     * 나갔을 때 규칙이 두 개 생긴다. 두 번 나가는 경로가 실제로 있다 — 저장을 누른
     * 직후 화면을 회전하면 그 코루틴은 뷰와 함께 죽지만 Firestore 쓰기는 살아서
     * 끝나고, 되살아난 화면에서 부모가 아무 일도 안 일어난 줄 알고 저장을 한 번 더
     * 누른다. ID 를 먼저 정해 두면 두 번째 쓰기는 같은 문서에 덮어쓰기라 규칙이
     * 하나로 남는다.
     */
    private var editorNewDocId: String? = null
    private var editorDays = mutableSetOf<Int>()
    private var editorStartMinute = DEFAULT_START_MINUTE
    private var editorEndMinute = DEFAULT_END_MINUTE
    private var editorMode = ScheduleText.MODE_VIBRATE

    /** 고치는 중인 규칙의 켬/끔과 우선순위. 편집으로 바뀌지 않고 그대로 유지된다. */
    private var editorEnabled = true
    private var editorPriority = 0

    /**
     * 이 화면이 **방금 부여한** 우선순위 중 가장 큰 값. [nextPriority] 가 [rules]
     * (마지막 스냅샷)와 함께 본다.
     *
     * 스냅샷만 보면 같은 값을 두 번 줄 수 있다: 규칙 A 를 저장한 직후 그 문서가 담긴
     * 스냅샷이 아직 안 왔는데 규칙 B 를 저장하면, 두 번의 `nextPriority()` 가 같은
     * 최댓값을 읽어 **같은 우선순위**를 매긴다. [ScheduleResolver] 는 그래도 결과를
     * 하나로 정하지만(우선순위가 같으면 늦게 시작한 구간이 이긴다) 그건 부모에게 약속한
     * 규칙("나중에 만든 것이 이긴다")이 아니다 — 부모가 예측할 수 없는 승패가 된다.
     */
    private var lastAssignedPriority = 0

    /** 저장/삭제가 진행 중인가. 진행 중에는 저장 버튼을 잠가 같은 쓰기가 두 번 나가지 않게 한다. */
    private var editorBusy = false

    private var backCallback: OnBackPressedCallback? = null

    /** 지금 떠 있는 확인 대화상자. 화면이 사라질 때 반드시 닫아야 창이 샌다는 경고가 안 뜬다. */
    private var activeDialog: AlertDialog? = null

    /** 못 보낸 알림을 다시 보내는 중인 코루틴. 여러 재시도 경로가 겹쳐 같은 명령을
     *  여러 번 밀어내지 않게 하나로 묶는다([retryPendingSync]). */
    private var syncRetryJob: Job? = null

    /** 공휴일 스위치를 그리는 리스너와 마지막으로 읽은 값. */
    private var settingsListener: ListenerRegistration? = null
    private var holidayOff = false

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        val binding = FragmentScheduleBinding.inflate(inflater, container, false)
        _binding = binding
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        val b = _binding ?: return

        restoreState(savedInstanceState)

        adapter = ScheduleAdapter(
            onEdit = { doc -> openEditor(doc) },
            onToggle = { doc, enabled -> toggleRule(doc, enabled) },
            onDelete = { doc -> confirmDelete(doc) },
        )
        b.scheduleList.layoutManager = LinearLayoutManager(requireContext())
        b.scheduleList.adapter = adapter

        b.addButton.setOnClickListener { openEditor(null) }
        // setOnCheckedChangeListener 가 아니라 setOnClickListener 인 이유는 규칙 줄의
        // 스위치와 같다(ScheduleAdapter 주석) — 값을 대입해 그릴 때 리스너가 불려
        // 쓰기가 나가면 안 된다.
        b.holidaySwitch.setOnClickListener { setHolidayOff(b.holidaySwitch.isChecked) }
        renderHoliday()
        b.editorCancelButton.setOnClickListener { cancelEditor() }
        b.editorSaveButton.setOnClickListener { onSaveClicked() }
        b.syncRetryButton.setOnClickListener { retryPendingSync() }
        b.startTimeButton.setOnClickListener { showTimePicker(TAG_PICK_START) }
        b.endTimeButton.setOnClickListener { showTimePicker(TAG_PICK_END) }

        // 낱개 버튼이라 **누름(click)** 만 듣는다. checked 변경을 들으면 renderEditor 가
        // 값을 대입해 그릴 때도 불려서, 방금 그린 값을 리스너가 다시 상태로 되돌려 쓰는
        // 순환이 생긴다(예전 토글 그룹이 suppressToggleCallbacks 깃발로 막던 문제다).
        // 체크 가능한 MaterialButton 은 눌리는 순간 스스로 상태를 뒤집고 나서 이 리스너를
        // 부르므로 isChecked 는 이미 새 값이다.
        dayButtons(b).forEachIndexed { index, button ->
            button.setOnClickListener {
                val day = index + 1
                if (button.isChecked) editorDays.add(day) else editorDays.remove(day)
                // 요일을 하나라도 고른 순간 경고를 거둔다 — 고쳤는데도 빨간 글씨가 남아
                // 있으면 아직 잘못된 줄 안다.
                if (editorDays.isNotEmpty()) _binding?.editorDaysError?.visibility = View.GONE
            }
        }
        modeButtons(b).forEach { (button, mode) ->
            button.setOnClickListener {
                editorMode = mode
                // 셋 중 하나만 켜져 있어야 한다. 낱개 버튼은 그 규칙을 스스로 모르므로
                // 다시 그려서 맞춘다.
                renderEditor()
            }
        }

        // 편집 중에 뒤로 가기를 누르면 앱이 꺼지는 대신 목록으로 돌아간다. 부모가
        // 방금 고른 요일·시각을 뒤로 가기 한 번에 잃는 것을 막는다.
        val callback = object : OnBackPressedCallback(editorVisible) {
            override fun handleOnBackPressed() = cancelEditor()
        }
        requireActivity().onBackPressedDispatcher.addCallback(viewLifecycleOwner, callback)
        backCallback = callback

        rebindTimePickers()
        renderEditor()
        renderList()
        // 여기서 syncStore 가 처음 만들어진다(위 syncStore 주석). 지난 세션에서 못
        // 보낸 알림이 있으면 화면을 열자마자 그 사실이 보여야 한다.
        renderPendingSync()
        subscribe()
    }

    /**
     * 탭을 옮겨도 이 프래그먼트는 죽지 않는다 — [GuardianMainActivity] 가 replace 가
     * 아니라 show/hide 를 쓰기 때문이다. 그래서 **탭 전환에서는 [onResume] 이 아니라
     * 이 콜백이 불린다.** 못 보낸 알림의 재시도를 여기에도 걸어두지 않으면, 부모가
     * 실제로 가장 자주 하는 동작(예약 탭 다시 누르기)이 재시도 경로에서 통째로 빠진다.
     */
    override fun onHiddenChanged(hidden: Boolean) {
        super.onHiddenChanged(hidden)
        if (!hidden) retryPendingSync()
    }

    /** 앱을 백그라운드에 뒀다가 돌아온 경우. 다른 탭을 보고 있을 때는 건드리지 않는다. */
    override fun onResume() {
        super.onResume()
        if (!isHidden) retryPendingSync()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        // pendingSync 는 여기 담지 않는다 — 뒤로 가기를 못 넘겨서 SharedPreferences 로
        // 옮겼다([ScheduleSyncStore]). 두 곳에 담으면 어느 쪽이 정답인지 흐려진다.
        outState.putInt(KEY_LAST_ASSIGNED_PRIORITY, lastAssignedPriority)
        outState.putBoolean(KEY_EDITOR_VISIBLE, editorVisible)
        outState.putString(KEY_EDITOR_RULE_ID, editorRuleId)
        outState.putString(KEY_EDITOR_NEW_DOC_ID, editorNewDocId)
        outState.putIntArray(KEY_EDITOR_DAYS, editorDays.toIntArray())
        outState.putInt(KEY_EDITOR_START, editorStartMinute)
        outState.putInt(KEY_EDITOR_END, editorEndMinute)
        outState.putString(KEY_EDITOR_MODE, editorMode)
        outState.putBoolean(KEY_EDITOR_ENABLED, editorEnabled)
        outState.putInt(KEY_EDITOR_PRIORITY, editorPriority)
    }

    private fun restoreState(saved: Bundle?) {
        saved ?: return
        lastAssignedPriority = saved.getInt(KEY_LAST_ASSIGNED_PRIORITY, 0)
        editorVisible = saved.getBoolean(KEY_EDITOR_VISIBLE, false)
        editorRuleId = saved.getString(KEY_EDITOR_RULE_ID)
        editorNewDocId = saved.getString(KEY_EDITOR_NEW_DOC_ID)
        editorDays = saved.getIntArray(KEY_EDITOR_DAYS)?.toMutableSet() ?: mutableSetOf()
        editorStartMinute = saved.getInt(KEY_EDITOR_START, DEFAULT_START_MINUTE)
        editorEndMinute = saved.getInt(KEY_EDITOR_END, DEFAULT_END_MINUTE)
        editorMode = saved.getString(KEY_EDITOR_MODE) ?: ScheduleText.MODE_VIBRATE
        editorEnabled = saved.getBoolean(KEY_EDITOR_ENABLED, true)
        editorPriority = saved.getInt(KEY_EDITOR_PRIORITY, 0)
        // 진행 중이던 쓰기의 코루틴은 뷰와 함께 취소됐다. 잠금만 남으면 저장 버튼이
        // 영영 안 눌리므로 여기서 반드시 푼다(쓰기 자체는 Firestore 가 이어서 끝낸다).
        editorBusy = false
    }

    // ---------------------------------------------------------------- 구독

    /**
     * 규칙 목록은 아이가 없어도 읽고 쓸 수 있으므로(가족 단위 컬렉션) 곧바로 구독한다.
     * 아이 uid 는 [CommandType.SYNC_RULES] 를 보낼 때만 필요해서 따로 지켜본다 —
     * 한 번만 조회하지 않는 이유는 MapTimelineFragment·ControlFragment 와 같다
     * (known-issues 3: 화면을 켜 둔 채 페어링이 끝나면 영영 못 알아챈다).
     */
    private fun subscribe() {
        val roleStore = RoleStore(requireContext())
        val fid = roleStore.familyId
        if (fid == null) {
            // 구독을 시작조차 못 한다 = 목록을 못 불러온 것이다([AlertFragment.subscribe] 와 같다).
            listLoad = ListLoad.FAILED
            showState(getString(R.string.schedule_no_family))
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

        scheduleListener = ScheduleRepository.observeSchedules(
            fid,
            selectedUid,
            onChange = { docs, fromCache -> onRulesChanged(docs, fromCache) },
            onError = { e ->
                val ctx = context ?: return@observeSchedules
                _binding ?: return@observeSchedules
                listLoad = ListLoad.FAILED
                showState(getString(R.string.schedule_error_format, errorMessage(ctx, e)))
                renderList()
            },
        )

        settingsListener = ScheduleRepository.observeRingerSettings(
            fid,
            selectedUid,
            onChange = { doc ->
                holidayOff = doc.holidayOff
                renderHoliday()
            },
            // 이 값을 못 읽는 것은 목록을 못 읽는 것과 다르다 — 규칙은 잘 보이는데
            // 스위치 하나만 모르는 상태다. 목록 위 안내 줄을 이 실패로 덮어쓰면
            // 정작 규칙에 대한 안내가 가려지므로 스위치만 잠근다.
            onError = {
                _binding?.holidaySwitch?.isEnabled = false
            },
        )

        joinedListener = FamilyRepository.observeChildJoined(
            fid,
            preferredChildUid = selectedUid,
            onJoined = { uid ->
                if (uid == childUid) return@observeChildJoined
                childUid = uid
                // 지난 세션에서 못 보낸 알림이 있으면 아이 uid 를 알게 된 지금 보낸다.
                // 화면을 열자마자의 재시도([onResume])는 이 시점보다 앞서서 uid 가 없어
                // 그냥 지나갔을 수 있다 — 그래서 이 경로도 함께 남겨둔다.
                retryPendingSync()
            },
            onError = { e ->
                val ctx = context ?: return@observeChildJoined
                _binding ?: return@observeChildJoined
                showState(errorMessage(ctx, e))
            },
        )
    }

    private fun onRulesChanged(docs: List<ScheduleDoc>, fromCache: Boolean) {
        // observeSchedules 는 정렬 없이 준다(문서 ID 순). 부모 눈에는 이른 시각이 위에
        // 오는 것이 자연스러우므로 여기서 정렬한다. priority 는 화면에 안 쓰므로
        // 정렬 기준으로도 쓰지 않는다.
        rules = docs.sortedWith(
            compareBy<ScheduleDoc> { it.startMinute }.thenBy { it.endMinute }.thenBy { it.id }
        )
        // 캐시본으로는 LOADED 로 올리지 않는다 — 이유는 [ListLoad] 주석("오프라인은
        // 네 번째 상태가 아니다"). 부모가 만들어 둔 규칙이 캐시에 있으면 그대로 보이고,
        // 없을 때 "아직 정해둔 규칙이 없어요"라고 단언만 하지 않는다.
        listLoad = if (fromCache) ListLoad.LOADING else ListLoad.LOADED
        renderList()
    }

    // ---------------------------------------------------------------- 편집 판

    /** [doc] 이 null 이면 새 규칙, 아니면 그 규칙을 고친다. */
    private fun openEditor(doc: ScheduleDoc?) {
        editorRuleId = doc?.id
        editorNewDocId = if (doc == null) UUID.randomUUID().toString() else null
        editorDays = doc?.days?.filter { it in 1..7 }?.toMutableSet() ?: DEFAULT_DAYS.toMutableSet()
        editorStartMinute = doc?.startMinute ?: DEFAULT_START_MINUTE
        editorEndMinute = doc?.endMinute ?: DEFAULT_END_MINUTE
        editorMode = doc?.mode ?: ScheduleText.MODE_VIBRATE
        editorEnabled = doc?.enabled ?: true
        editorPriority = doc?.priority ?: 0
        editorBusy = false
        editorVisible = true
        showEditorStatus(null)
        showState(null)
        renderEditor()
    }

    /**
     * 편집을 접는다. 세대를 올리는 이유: 저장을 눌러 왕복이 도는 중에 취소했다면,
     * 그 코루틴이 돌아와 이미 닫힌(또는 다른 규칙으로 다시 열린) 편집 판을 만지면 안 된다.
     *
     * **쓰기가 도는 중에는 취소도 막는다.** 예전에는 [setEditorBusy] 가 저장 버튼만
     * 잠갔고 취소는 그대로 살아 있었는데, 그러면 이런 길이 열린다: 규칙 A 를 저장(느린
     * 쓰기) → 취소 → 새 규칙 B 추가 → 저장. A 의 스냅샷이 아직 안 왔으므로 두
     * [nextPriority] 호출이 같은 최댓값을 읽어 **같은 우선순위**를 매기고, 그러면
     * "나중에 만든 것이 이긴다"는 부모와의 약속이 깨진다. 되돌아가는 길 자체를 잠깐
     * 닫는 쪽이 확실하다 — 기다리는 시간은 쓰기 제한시간(15초)으로 이미 막혀 있고,
     * 그동안 무슨 일이 벌어지는지는 편집 판 안의 "저장 중…"이 말해준다.
     * (뒤로 가기도 이 함수를 지나므로 함께 막힌다.)
     */
    private fun cancelEditor() {
        if (editorBusy) return
        writeGeneration++
        closeEditor()
    }

    private fun closeEditor() {
        editorVisible = false
        editorBusy = false
        editorRuleId = null
        editorNewDocId = null
        showEditorStatus(null)
        renderEditor()
    }

    /**
     * 저장 버튼. 세 관문을 순서대로 지난다.
     *
     * 1. **요일이 비었으면 막는다.** 요일이 없는 규칙은
     *    [ScheduleResolver][com.kidcare.family.logic.ScheduleResolver] 가 어느 날에도
     *    펼치지 않아 한 번도 켜지지 않는데, 목록에는 멀쩡한 줄로 남아 부모는 예약을
     *    해뒀다고 믿는다. "적당한 기본값(예: 매일)으로 대신 저장"도 생각했지만, 매일
     *    무음과 평일 무음은 부모에게 전혀 다른 약속이라 넘겨짚으면 안 된다 — 막고
     *    이유를 말하는 쪽을 골랐다.
     * 2. **시작과 끝이 같으면 물어본다.** 그 입력은 24시간 규칙이 된다(ScheduleResolver
     *    의 intervalStartingOn 주석). 진짜 "하루 종일"을 뜻할 수도 있어서 막지는 않되,
     *    두 칸을 잘못 눌러 하루 종일 무음이 되는 사고는 확인 한 번으로 걸러낸다.
     * 3. **겹치면 알려주되 막지 않는다.** 겹침은 우선순위로 해결되는 정상 상태다
     *    (설계서 §4.3). 어느 규칙과 겹치는지 이름을 대 준다.
     */
    private fun onSaveClicked() {
        val b = _binding ?: return
        if (editorBusy) return

        if (editorDays.isEmpty()) {
            b.editorDaysError.visibility = View.VISIBLE
            return
        }
        b.editorDaysError.visibility = View.GONE

        if (editorStartMinute == editorEndMinute) {
            confirmAllDay { confirmOverlapThenSave() }
            return
        }
        confirmOverlapThenSave()
    }

    private fun confirmAllDay(onConfirmed: () -> Unit) {
        val ctx = context ?: return
        showDialog(
            MaterialAlertDialogBuilder(ctx)
                .setTitle(R.string.schedule_allday_title)
                .setMessage(
                    getString(
                        R.string.schedule_allday_message,
                        ScheduleText.timeText(ctx, editorStartMinute),
                        ScheduleText.modeText(ctx, editorMode),
                    )
                )
                .setPositiveButton(R.string.schedule_allday_confirm) { _, _ -> onConfirmed() }
                .setNegativeButton(R.string.schedule_allday_cancel, null)
        )
    }

    /**
     * 겹치는 규칙이 있으면 이름을 대고 물어본다. 없으면 곧장 저장한다.
     *
     * [ScheduleResolver.overlapsOf] 는 후보를 항상 켜진 것으로 보고(꺼둔 규칙을
     * 고치는 중이어도 나중에 켰을 때의 충돌을 미리 알려준다), 비교 대상 중 꺼진
     * 것은 제외한다 — 그 함수의 주석에 근거가 있다.
     */
    private fun confirmOverlapThenSave() {
        val ctx = context ?: return
        val candidate = ScheduleRule(
            // 새 규칙이면 id 가 빈 문자열이라 기존 어느 문서와도 같지 않다.
            // overlapsOf 는 id 가 같은 규칙을 "자기 자신"으로 보고 건너뛴다.
            id = editorRuleId.orEmpty(),
            days = editorDays.toSet(),
            startMinute = editorStartMinute,
            endMinute = editorEndMinute,
            mode = editorMode,
            enabled = editorEnabled,
            priority = editorPriority,
        )
        val hits = ScheduleResolver.overlapsOf(rules.map { it.toRule() }, candidate)
        if (hits.isEmpty()) {
            saveRule()
            return
        }
        // 판정은 ScheduleRule 로 했지만 문구는 문서에서 만든다 — 한 줄 이름을 만드는
        // 곳이 ScheduleText 하나여야 목록과 대화상자가 같은 말을 한다.
        val firstDoc = rules.firstOrNull { it.id == hits.first().id }
        val firstName = firstDoc?.let { ScheduleText.summary(ctx, it) } ?: return saveRule()
        val message = if (hits.size == 1) {
            getString(R.string.schedule_overlap_message, firstName)
        } else {
            getString(R.string.schedule_overlap_message_more, firstName, hits.size - 1)
        }
        showDialog(
            MaterialAlertDialogBuilder(ctx)
                .setTitle(R.string.schedule_overlap_title)
                .setMessage(message)
                .setPositiveButton(R.string.schedule_overlap_confirm) { _, _ -> saveRule() }
                .setNegativeButton(R.string.schedule_overlap_cancel, null)
        )
    }

    // ---------------------------------------------------------------- 쓰기

    /**
     * 규칙 하나를 저장한다. 새로 만들기와 고치기가 같은 경로다 —
     * [ScheduleRepository.saveSchedule] 은 받은 [ScheduleDoc.id] 문서에 덮어쓰고,
     * 그 ID 는 새 규칙이든 고치는 규칙이든 우리가 항상 정해서 넘긴다
     * ([editorNewDocId] 주석: 저장이 두 번 나가도 규칙이 두 개 생기지 않게 하려는 것).
     *
     * 쓰기가 끝날 때까지 편집 판을 닫지 않는다. 먼저 닫고 목록에만 맡기면, 규칙이
     * 거부됐을 때(권한 문제 등) 방금 만든 줄이 잠깐 보였다가 소리 없이 사라진다 —
     * 부모는 자기가 뭘 잘못 봤다고 생각하지, 규칙이 저장되지 않았다고 생각하지 않는다.
     */
    private fun saveRule() {
        val fid = familyId
        val uid = childUid
        if (fid == null || uid == null) {
            showEditorStatus(getString(R.string.schedule_no_family))
            return
        }
        // 우선순위는 만든 순서다. 새 규칙에는 지금 있는 것들보다 하나 큰 값을
        // 주고(=나중에 만든 것이 이긴다), 고치는 중이면 원래 값을 그대로 둔다 —
        // 시각만 고쳤다고 규칙끼리의 승패가 뒤집히면 부모가 예측할 수 없다.
        val priority = if (editorRuleId == null) nextPriority() else editorPriority
        // 방금 준 값을 기억해 둔다. 이 규칙이 담긴 스냅샷이 돌아오기 전에 다음 규칙을
        // 저장해도 같은 값을 또 주지 않기 위해서다([lastAssignedPriority] 주석).
        if (editorRuleId == null) lastAssignedPriority = priority
        val doc = ScheduleDoc(
            // 새 규칙이면 편집을 열 때 정해 둔 ID 를 쓴다([editorNewDocId] 주석).
            id = editorRuleId ?: editorNewDocId ?: UUID.randomUUID().toString(),
            days = editorDays.sorted(),
            startMinute = editorStartMinute,
            endMinute = editorEndMinute,
            mode = editorMode,
            enabled = editorEnabled,
            priority = priority,
        )

        val generation = ++writeGeneration
        setEditorBusy(true)
        showEditorStatus(getString(R.string.schedule_saving))
        // 쓰기보다 **먼저** 깃발을 세운다(위 pendingSync 주석). 쓰기가 실패했는데 깃발이
        // 남아 다음에 헛 명령을 한 번 보내는 것은 무해하지만, 반대(쓰기는 됐는데 깃발이
        // 없어 영영 안 알리는 것)는 조용한 고장이다.
        pendingSync = true

        viewLifecycleOwner.lifecycleScope.launch {
            try {
                val savedId = withTimeoutOrNull(WRITE_TIMEOUT_MILLIS) {
                    ScheduleRepository.saveSchedule(fid, uid, doc)
                }
                if (generation == writeGeneration && _binding != null) {
                    closeEditor()
                    if (savedId == null) showStateRes(R.string.schedule_save_slow) else showState(null)
                }
                notifyChild(generation)
            } catch (e: CancellationException) {
                // 화면을 떠나며 스코프가 취소된 것이다. 실패로 표시하면 안 된다.
                throw e
            } catch (e: Exception) {
                if (generation != writeGeneration) return@launch
                val ctx = context ?: return@launch
                _binding ?: return@launch
                setEditorBusy(false)
                showEditorStatus(errorMessage(ctx, e))
            }
        }
    }

    /**
     * 켬/끔 스위치. 화면에 보이는 값은 스냅샷이 정한다 — 서버가 이 쓰기를 거부하면
     * Firestore 가 로컬 문서를 되돌리고, 그 스냅샷이 다시 와서 스위치도 저절로
     * 제자리로 간다. 그래서 여기서 직접 되돌리지 않는다. 대신 **왜 되돌아갔는지는
     * 반드시 말한다** — 이유 없이 튕겨 돌아가는 스위치가 부모에게는 고장이다.
     */
    private fun toggleRule(doc: ScheduleDoc, enabled: Boolean) {
        val fid = familyId
        val uid = childUid
        if (fid == null || uid == null) {
            showState(getString(R.string.schedule_no_family))
            return
        }
        val generation = ++writeGeneration
        showState(null)
        pendingSync = true

        viewLifecycleOwner.lifecycleScope.launch {
            try {
                val savedId = withTimeoutOrNull(WRITE_TIMEOUT_MILLIS) {
                    ScheduleRepository.saveSchedule(fid, uid, doc.copy(enabled = enabled))
                }
                if (savedId == null && generation == writeGeneration) {
                    showStateRes(R.string.schedule_save_slow)
                }
                notifyChild(generation)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (generation != writeGeneration) return@launch
                val ctx = context ?: return@launch
                _binding ?: return@launch
                showState(errorMessage(ctx, e))
            }
        }
    }

    /**
     * 공휴일 스위치를 저장하고 아이 폰에 알린다.
     *
     * 규칙 저장과 같은 길을 탄다([pendingSync] → [notifyChild]). 이 값도 결국 자녀 폰의
     * [ScheduleApplier][com.kidcare.family.child.ScheduleApplier] 가 읽어야 효과가 나므로,
     * 알리지 않으면 "부모 화면에서는 켰는데 아이 폰은 공휴일에도 무음"이 된다.
     */
    private fun setHolidayOff(enabled: Boolean) {
        val fid = familyId
        val uid = childUid
        if (fid == null || uid == null) {
            _binding?.holidaySwitch?.isChecked = holidayOff
            showState(getString(R.string.schedule_no_family))
            return
        }
        val generation = ++writeGeneration
        holidayOff = enabled
        renderHoliday()
        showState(null)
        pendingSync = true

        viewLifecycleOwner.lifecycleScope.launch {
            try {
                val done = withTimeoutOrNull(WRITE_TIMEOUT_MILLIS) {
                    ScheduleRepository.setHolidayOff(fid, uid, enabled)
                }
                if (done == null && generation == writeGeneration) {
                    showStateRes(R.string.schedule_save_slow)
                } else if (generation == writeGeneration) {
                    showStateRes(
                        if (enabled) R.string.schedule_holiday_saved
                        else R.string.schedule_holiday_cleared
                    )
                }
                notifyChild(generation)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (generation != writeGeneration) return@launch
                val ctx = context ?: return@launch
                _binding ?: return@launch
                // 서버가 거절했으면 화면도 되돌린다 — 켜진 스위치를 그대로 두면
                // 부모는 공휴일에 쉬는 줄 알고 있는데 실제로는 안 쉰다.
                holidayOff = !enabled
                renderHoliday()
                showState(errorMessage(ctx, e))
            }
        }
    }

    /**
     * 스위치와 그 아래 한 줄. 켜져 있을 때만 다음 쉬는 날을 적는다.
     *
     * 날짜를 적는 것이 이 화면의 유일한 검산이다 — 음력 환산이 틀리면 아무 증상 없이
     * 엉뚱한 날에 쉬는데, 다음 쉬는 날을 눈에 보이게 적어 두면 부모가 달력과 맞춰볼 수
     * 있다.
     */
    private fun renderHoliday() {
        val b = _binding ?: return
        b.holidaySwitch.isChecked = holidayOff
        if (!holidayOff) {
            b.holidayHint.setText(R.string.schedule_holiday_subtitle)
            return
        }
        val next = HolidayCalendar.next(LocalDate.now())
        if (next == null) {
            b.holidayHint.setText(R.string.schedule_holiday_unknown)
            return
        }
        val (date, holiday) = next
        b.holidayHint.text = getString(
            R.string.schedule_holiday_next,
            getString(R.string.schedule_holiday_date, date.monthValue, date.dayOfMonth),
            getString(holidayNameRes(holiday)),
        )
    }

    private fun holidayNameRes(holiday: Holiday): Int = when (holiday) {
        Holiday.NEW_YEAR -> R.string.holiday_new_year
        Holiday.SEOLLAL -> R.string.holiday_seollal
        Holiday.INDEPENDENCE -> R.string.holiday_independence
        Holiday.BUDDHA -> R.string.holiday_buddha
        Holiday.CHILDREN -> R.string.holiday_children
        Holiday.MEMORIAL -> R.string.holiday_memorial
        Holiday.LIBERATION -> R.string.holiday_liberation
        Holiday.CHUSEOK -> R.string.holiday_chuseok
        Holiday.FOUNDATION -> R.string.holiday_foundation
        Holiday.HANGUL -> R.string.holiday_hangul
        Holiday.CHRISTMAS -> R.string.holiday_christmas
        Holiday.SUBSTITUTE -> R.string.holiday_substitute
    }

    private fun confirmDelete(doc: ScheduleDoc) {
        val ctx = context ?: return
        showDialog(
            MaterialAlertDialogBuilder(ctx)
                .setTitle(R.string.schedule_delete_title)
                .setMessage(getString(R.string.schedule_delete_message, ScheduleText.summary(ctx, doc)))
                .setPositiveButton(R.string.schedule_delete_confirm) { _, _ -> deleteRule(doc) }
                .setNegativeButton(R.string.schedule_delete_cancel, null)
        )
    }

    private fun deleteRule(doc: ScheduleDoc) {
        val fid = familyId
        val uid = childUid
        if (fid == null || uid == null) {
            showState(getString(R.string.schedule_no_family))
            return
        }
        val generation = ++writeGeneration
        showState(getString(R.string.schedule_deleting))
        pendingSync = true

        viewLifecycleOwner.lifecycleScope.launch {
            try {
                val done = withTimeoutOrNull(WRITE_TIMEOUT_MILLIS) {
                    ScheduleRepository.deleteSchedule(fid, uid, doc.id)
                }
                if (generation == writeGeneration) {
                    if (done == null) showStateRes(R.string.schedule_save_slow) else showState(null)
                }
                notifyChild(generation)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (generation != writeGeneration) return@launch
                val ctx = context ?: return@launch
                _binding ?: return@launch
                showState(errorMessage(ctx, e))
            }
        }
    }

    /**
     * 아이 폰에 "규칙이 바뀌었다"고 알린다. 저장·수정·삭제·켬끔 네 갈래가 전부 이
     * 함수를 지난다(클래스 주석 참고).
     *
     * [generation] 은 **화면에 글자를 쓸지**만 가른다. 명령 발행 자체는 세대와 상관없이
     * 항상 한다 — 부모가 그 사이 다른 규칙을 만졌다고 해서 앞 규칙이 바뀐 사실이
     * 없어지지 않기 때문이다.
     */
    private suspend fun notifyChild(generation: Int) {
        val fid = familyId ?: return
        val uid = childUid
        if (uid == null) {
            // 보낼 곳이 없다. 아이 폰이 나중에 연결되면 TrackingService 가 뜨면서
            // ScheduleApplier.refresh 를 부르므로(child/TrackingService) 규칙은 그때
            // 저절로 적용된다 — 명령을 기다릴 필요가 없으니 깃발을 내린다.
            pendingSync = false
            if (generation == writeGeneration) showStateRes(R.string.schedule_sync_no_child)
            return
        }
        try {
            val commandId = withTimeoutOrNull(WRITE_TIMEOUT_MILLIS) {
                CommandRepository.send(fid, uid, CommandType.SYNC_RULES)
            }
            if (commandId == null) {
                // 오프라인이면 명령 문서도 로컬 큐에 남아 연결될 때 나간다. 그래도
                // 깃발은 내리지 않는다 — 한 번 더 보내는 비용보다 영영 안 보내는
                // 위험이 훨씬 크고, 중복 SYNC_RULES 는 자녀 쪽에서 무해하다.
                if (generation == writeGeneration) showStateRes(R.string.schedule_sync_slow)
                return
            }
            pendingSync = false
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            val ctx = context ?: return
            if (generation != writeGeneration) return
            _binding ?: return
            showState(ctx.getString(R.string.schedule_sync_failed_format, errorMessage(ctx, e)))
        }
    }

    /**
     * 지난번에 못 보낸 [CommandType.SYNC_RULES] 를 한 번 더 보낸다.
     *
     * 부르는 곳이 넷이다 — 아이 uid 를 알게 된 순간([subscribe] 의 onJoined), 예약 탭을
     * 다시 눌렀을 때([onHiddenChanged]), 앱으로 돌아왔을 때([onResume]), 그리고 부모가
     * 안내 줄의 '다시 알리기'를 눌렀을 때. 여러 경로를 두는 이유는 하나짜리 경로가
     * 실제로 부모가 밟지 않는 길이었기 때문이다: 예전에는 onJoined 하나뿐이었는데
     * [GuardianMainActivity] 가 show/hide 를 쓰므로 탭을 오가도 그 콜백은 다시 불리지
     * 않는다.
     *
     * Firestore 콜백에서도 불리므로 화면이 이미 사라진 뒤일 수 있다. 그때
     * `viewLifecycleOwner` 를 건드리면 그대로 예외라 `_binding` 으로 먼저 막는다 —
     * `_binding` 이 살아 있다는 것은 뷰 생명주기가 아직 유효하다는 뜻이다.
     */
    private fun retryPendingSync() {
        if (!pendingSync) return
        // 아직 아이 uid 를 모른다. 여기서 notifyChild 를 부르면 "아이 폰이 연결되면
        // 저절로 적용돼요"로 깃발을 내려버리는데, 그건 아이가 정말 없을 때 하는 말이지
        // 리스너가 아직 첫 스냅샷을 못 받은 상태에서 할 말이 아니다. onJoined 가 곧
        // 다시 부른다.
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
                // notifyChild 가 이미 자기 실패를 화면에 적는다. 여기까지 오는 것은
                // 그 방어망 밖의 예외뿐이라 화면을 덮어쓰지 않고 조용히 지나간다.
            }
        }
    }

    /**
     * 새 규칙의 우선순위. 지금 있는 것 중 가장 큰 값보다 하나 크다(= 나중에 만든 것이
     * 이긴다). 스냅샷이 아직 안 돌아온 규칙도 [lastAssignedPriority] 로 함께 센다 —
     * 그 필드 주석에 이유가 있다.
     */
    private fun nextPriority(): Int =
        maxOf(rules.maxOfOrNull { it.priority } ?: 0, lastAssignedPriority) + 1

    // ---------------------------------------------------------------- 시각 고르기

    /**
     * [MaterialTimePicker] 는 Material3 아티팩트에 이미 들어 있다(새 의존성 없음).
     *
     * 24시간 표기로 고정하는 이유: 목록도 `22:00 ~ 다음 날 07:00` 처럼 24시간으로
     * 보여주는데 고르는 화면만 오전/오후면 부모가 두 표기를 머릿속에서 맞춰봐야 한다.
     * 밤 시간대 규칙에서 특히 헷갈린다.
     */
    private fun showTimePicker(tag: String) {
        val start = tag == TAG_PICK_START
        val current = if (start) editorStartMinute else editorEndMinute
        val picker = MaterialTimePicker.Builder()
            .setTimeFormat(TimeFormat.CLOCK_24H)
            .setHour(current / 60)
            .setMinute(current % 60)
            .setTitleText(if (start) R.string.schedule_editor_start_title else R.string.schedule_editor_end_title)
            .build()
        bindTimePicker(picker, tag)
        picker.show(childFragmentManager, tag)
    }

    /**
     * 화면이 회전하면 [MaterialTimePicker] 자신은 FragmentManager 가 되살리지만
     * **리스너는 되살아나지 않는다**(새 인스턴스의 리스너 목록은 비어 있다). 그대로
     * 두면 회전 뒤에 확인을 눌러도 시각이 반영되지 않고 창만 닫힌다 — 눌렀는데 아무
     * 일도 안 일어나는, 이 앱이 가장 피하려는 종류의 실패다. 그래서 뷰를 만들 때마다
     * 태그로 찾아 리스너를 다시 붙인다. 태그가 곧 "어느 칸을 고치는 중인가"다.
     */
    private fun rebindTimePickers() {
        listOf(TAG_PICK_START, TAG_PICK_END).forEach { tag ->
            (childFragmentManager.findFragmentByTag(tag) as? MaterialTimePicker)?.let {
                bindTimePicker(it, tag)
            }
        }
    }

    private fun bindTimePicker(picker: MaterialTimePicker, tag: String) {
        picker.addOnPositiveButtonClickListener {
            val minuteOfDay = picker.hour * 60 + picker.minute
            if (tag == TAG_PICK_START) editorStartMinute = minuteOfDay else editorEndMinute = minuteOfDay
            renderEditor()
        }
    }

    // ---------------------------------------------------------------- 그리기

    private fun renderList() {
        val b = _binding ?: return
        adapter.submitList(rules)
        b.scheduleEmpty.renderEmptyState(listLoad, rules.isEmpty(), R.string.schedule_empty)
    }

    /**
     * "아직 애기폰에 전달되지 않았어요" 줄. [pendingSync] 가 바뀔 때마다 저절로 불린다
     * (그 프로퍼티의 setter).
     *
     * 규칙별로 표시하지 않는 이유는 fragment_schedule.xml 의 주석에 적었다 — 깃발이
     * 규칙 묶음 전체를 가리키는 신호 하나에 달려 있어서 나눌 수 있는 값이 아니다.
     */
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
            if (editorRuleId == null) R.string.schedule_editor_title_new
            else R.string.schedule_editor_title_edit
        )

        dayButtons(b).forEachIndexed { index, button ->
            button.isChecked = (index + 1) in editorDays
        }
        modeButtons(b).forEach { (button, mode) -> styleModeButton(button, mode) }

        val ctx = b.root.context
        b.startTimeButton.text = ScheduleText.timeText(ctx, editorStartMinute)
        b.endTimeButton.text = ScheduleText.timeText(ctx, editorEndMinute)

        // 시각 두 칸만 봐서는 "다음 날까지"인지 "하루 종일"인지 알 수 없다. 저장하기
        // 전에 여기서 미리 말해준다(목록 줄의 표기와 같은 문장을 쓴다).
        val crossesOrAllDay = editorEndMinute <= editorStartMinute
        b.rangeHint.visibility = if (crossesOrAllDay) View.VISIBLE else View.GONE
        if (crossesOrAllDay) {
            b.rangeHint.text = ScheduleText.rangeText(ctx, editorStartMinute, editorEndMinute)
        }

        if (editorDays.isNotEmpty()) b.editorDaysError.visibility = View.GONE
        setEditorBusy(editorBusy)
    }

    private fun dayButtons(b: FragmentScheduleBinding): List<MaterialButton> =
        listOf(b.dayMon, b.dayTue, b.dayWed, b.dayThu, b.dayFri, b.daySat, b.daySun)

    private fun modeButtons(b: FragmentScheduleBinding): List<Pair<MaterialButton, String>> = listOf(
        b.scheduleModeNormal to ScheduleText.MODE_NORMAL,
        b.scheduleModeVibrate to ScheduleText.MODE_VIBRATE,
        b.scheduleModeSilent to ScheduleText.MODE_SILENT,
    )

    /**
     * 소리 모드 버튼 하나를 지금 고른 값에 맞춰 칠한다.
     *
     * 고른 것은 그 모드의 색으로 차고, 안 고른 것은 종이색으로 남는다. 색을 XML 의
     * 상태 목록이 아니라 여기서 입히는 이유는 목록 줄의 스티커와 **같은 표**
     * ([ScheduleText.modeLook])를 쓰기 위해서다 — 색을 두 곳에 적으면 하나를 바꿀 때
     * 반드시 하나를 빠뜨린다.
     */
    private fun styleModeButton(button: MaterialButton, mode: String) {
        val ctx = button.context
        val selected = editorMode == mode
        val (iconRes, colorRes, softRes) = ScheduleText.modeLook(mode)
        val strong = ContextCompat.getColor(ctx, colorRes)
        button.isChecked = selected
        button.setIconResource(iconRes)
        button.backgroundTintList = ColorStateList.valueOf(
            ContextCompat.getColor(ctx, if (selected) softRes else R.color.paper_card)
        )
        button.strokeColor = ColorStateList.valueOf(
            if (selected) strong else ContextCompat.getColor(ctx, R.color.line_soft)
        )
        val content = if (selected) strong else ContextCompat.getColor(ctx, R.color.ink_soft)
        button.iconTint = ColorStateList.valueOf(content)
        button.setTextColor(content)
    }

    /** 취소 버튼도 함께 잠근다 — 이유는 [cancelEditor] 주석. */
    private fun setEditorBusy(busy: Boolean) {
        editorBusy = busy
        val b = _binding ?: return
        b.editorSaveButton.isEnabled = !busy
        b.editorCancelButton.isEnabled = !busy
        b.editorProgress.visibility = if (busy) View.VISIBLE else View.GONE
    }

    /** 편집 판 안의 한 줄. null 이면 감춘다. */
    private fun showEditorStatus(message: String?) {
        val b = _binding ?: return
        b.editorStatus.visibility = if (message == null) View.GONE else View.VISIBLE
        b.editorStatus.text = message.orEmpty()
        if (message == null) b.editorProgress.visibility = View.GONE
    }

    /** 목록 판 위의 한 줄. null 이면 감춘다. */
    private fun showState(message: String?) {
        val b = _binding ?: return
        b.scheduleState.visibility = if (message == null) View.GONE else View.VISIBLE
        b.scheduleState.text = message.orEmpty()
    }

    /**
     * 화면이 아직 살아 있을 때만 [showState] 로 문구를 적는다.
     *
     * [showState] 자신도 `_binding` 널 가드를 갖고 있지만, 그것만으로는 모자란다 —
     * 호출부가 인자를 만들 때 부르는 [Fragment.getString] 은 화면이 떨어져 나간
     * 뒤에 부르면 그 자리에서 예외다(가드보다 **먼저** 평가된다). 코루틴 안에서
     * 문구를 적는 곳은 전부 이 함수를 지난다.
     */
    private fun showStateRes(resId: Int) {
        _binding ?: return
        val ctx = context ?: return
        showState(ctx.getString(resId))
    }

    /**
     * 확인 대화상자를 띄운다. 앞에 떠 있던 것은 닫는다 — 두 개가 겹치면 뒤엣것을
     * 닫을 방법이 없고, 화면이 사라질 때 닫지 않으면 창이 샜다는 경고와 함께 죽는다.
     */
    private fun showDialog(builder: MaterialAlertDialogBuilder) {
        activeDialog?.dismiss()
        activeDialog = builder.setOnDismissListener { activeDialog = null }.show()
    }

    override fun onDestroyView() {
        // 리스너 둘, 대화상자 하나, 뒤로가기 콜백 하나를 전부 끊는다. 쓰기 코루틴은
        // viewLifecycleOwner 스코프라 여기서 함께 취소되고(그래도 Firestore 로 이미
        // 넘어간 쓰기 자체는 그대로 끝난다), 모든 그리기 함수는 _binding 이 null 이면
        // 조용히 돌아간다.
        scheduleListener?.remove()
        scheduleListener = null
        joinedListener?.remove()
        joinedListener = null
        settingsListener?.remove()
        settingsListener = null
        syncRetryJob?.cancel()
        syncRetryJob = null
        activeDialog?.dismiss()
        activeDialog = null
        backCallback?.remove()
        backCallback = null
        _binding = null
        super.onDestroyView()
    }

    private companion object {
        /** 새 규칙의 기본값: 평일 21:00~07:00 진동. 가장 흔한 요구("밤에는 조용히")에 가깝다. */
        val DEFAULT_DAYS = setOf(1, 2, 3, 4, 5)
        const val DEFAULT_START_MINUTE = 21 * 60
        const val DEFAULT_END_MINUTE = 7 * 60

        /**
         * Firestore 쓰기는 **서버 확인**을 기다린다. 오프라인이면 그 확인이 영영 오지
         * 않으므로(로컬 큐에는 이미 들어가 있다) 화면을 무한정 붙잡지 않도록 여기서
         * 끊는다. 끊어도 쓰기 자체는 취소되지 않고 연결될 때 나간다.
         */
        const val WRITE_TIMEOUT_MILLIS = 15_000L

        const val TAG_PICK_START = "schedule_pick_start"
        const val TAG_PICK_END = "schedule_pick_end"

        const val KEY_LAST_ASSIGNED_PRIORITY = "last_assigned_priority"
        const val KEY_EDITOR_VISIBLE = "editor_visible"
        const val KEY_EDITOR_RULE_ID = "editor_rule_id"
        const val KEY_EDITOR_NEW_DOC_ID = "editor_new_doc_id"
        const val KEY_EDITOR_DAYS = "editor_days"
        const val KEY_EDITOR_START = "editor_start"
        const val KEY_EDITOR_END = "editor_end"
        const val KEY_EDITOR_MODE = "editor_mode"
        const val KEY_EDITOR_ENABLED = "editor_enabled"
        const val KEY_EDITOR_PRIORITY = "editor_priority"
    }
}
