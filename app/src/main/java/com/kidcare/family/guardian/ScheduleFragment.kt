package com.kidcare.family.guardian

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AlertDialog
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.timepicker.MaterialTimePicker
import com.google.android.material.timepicker.TimeFormat
import com.google.firebase.firestore.ListenerRegistration
import com.kidcare.family.R
import com.kidcare.family.core.CommandRepository
import com.kidcare.family.core.FamilyRepository
import com.kidcare.family.core.RoleStore
import com.kidcare.family.core.ScheduleRepository
import com.kidcare.family.core.errorMessage
import com.kidcare.family.core.model.CommandType
import com.kidcare.family.core.model.ScheduleDoc
import com.kidcare.family.core.toRule
import com.kidcare.family.databinding.FragmentScheduleBinding
import com.kidcare.family.logic.ScheduleResolver
import com.kidcare.family.logic.ScheduleRule
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
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
     * 규칙을 건드렸는데 아직 [CommandType.SYNC_RULES] 를 확실히 보내지 못했는가.
     *
     * 쓰기 **직전에** 세우고, 명령 발행이 성공한 뒤에만 내린다. 화면이 회전하거나
     * 프로세스가 죽어도 [onSaveInstanceState] 로 살아남아, 다음에 이 화면이 열릴 때
     * 한 번 더 보낸다. 이게 없으면 "삭제는 됐는데 알림은 못 보낸" 상태가 영구히 남고,
     * 그때 자녀 폰에서는 이미 지워진 규칙의 알람이 한 번 더 울린다.
     *
     * 앱이 강제 종료되면(저장 상태 자체가 사라지면) 이 그물도 사라진다 — 그때는
     * 자녀 폰이 재부팅·시각변경·서비스 재시작으로 규칙을 다시 읽을 때까지 어긋난다.
     */
    private var pendingSync = false

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

    /** 저장/삭제가 진행 중인가. 진행 중에는 저장 버튼을 잠가 같은 쓰기가 두 번 나가지 않게 한다. */
    private var editorBusy = false

    /** [renderEditor] 가 토글 그룹에 값을 대입하는 동안 리스너가 도로 상태를 고치지 못하게 막는다. */
    private var suppressToggleCallbacks = false

    private var backCallback: OnBackPressedCallback? = null

    /** 지금 떠 있는 확인 대화상자. 화면이 사라질 때 반드시 닫아야 창이 샌다는 경고가 안 뜬다. */
    private var activeDialog: AlertDialog? = null

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
        b.editorCancelButton.setOnClickListener { cancelEditor() }
        b.editorSaveButton.setOnClickListener { onSaveClicked() }
        b.startTimeButton.setOnClickListener { showTimePicker(TAG_PICK_START) }
        b.endTimeButton.setOnClickListener { showTimePicker(TAG_PICK_END) }

        b.dayGroup.addOnButtonCheckedListener { _, checkedId, isChecked ->
            if (suppressToggleCallbacks) return@addOnButtonCheckedListener
            val day = DAY_BUTTON_IDS.indexOf(checkedId) + 1
            if (day <= 0) return@addOnButtonCheckedListener
            if (isChecked) editorDays.add(day) else editorDays.remove(day)
            // 요일을 하나라도 고른 순간 경고를 거둔다 — 고쳤는데도 빨간 글씨가 남아
            // 있으면 아직 잘못된 줄 안다.
            if (editorDays.isNotEmpty()) _binding?.editorDaysError?.visibility = View.GONE
        }
        b.modeGroup.addOnButtonCheckedListener { _, checkedId, isChecked ->
            if (suppressToggleCallbacks || !isChecked) return@addOnButtonCheckedListener
            editorMode = when (checkedId) {
                R.id.schedule_mode_normal -> ScheduleText.MODE_NORMAL
                R.id.schedule_mode_vibrate -> ScheduleText.MODE_VIBRATE
                R.id.schedule_mode_silent -> ScheduleText.MODE_SILENT
                else -> editorMode
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
        subscribe()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putBoolean(KEY_PENDING_SYNC, pendingSync)
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
        pendingSync = saved.getBoolean(KEY_PENDING_SYNC, false)
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
        val fid = RoleStore(requireContext()).familyId
        if (fid == null) {
            showState(getString(R.string.schedule_no_family))
            return
        }
        familyId = fid

        scheduleListener = ScheduleRepository.observeSchedules(
            fid,
            onChange = { docs -> onRulesChanged(docs) },
            onError = { e ->
                val ctx = context ?: return@observeSchedules
                _binding ?: return@observeSchedules
                showState(getString(R.string.schedule_error_format, errorMessage(ctx, e)))
            },
        )

        joinedListener = FamilyRepository.observeChildJoined(
            fid,
            onJoined = { uid ->
                if (uid == childUid) return@observeChildJoined
                childUid = uid
                // 지난 세션에서 못 보낸 알림이 있으면 아이 uid 를 알게 된 지금 보낸다.
                if (pendingSync) resendPendingSync()
            },
            onError = { e ->
                val ctx = context ?: return@observeChildJoined
                _binding ?: return@observeChildJoined
                showState(errorMessage(ctx, e))
            },
        )
    }

    private fun onRulesChanged(docs: List<ScheduleDoc>) {
        // observeSchedules 는 정렬 없이 준다(문서 ID 순). 부모 눈에는 이른 시각이 위에
        // 오는 것이 자연스러우므로 여기서 정렬한다. priority 는 화면에 안 쓰므로
        // 정렬 기준으로도 쓰지 않는다.
        rules = docs.sortedWith(
            compareBy<ScheduleDoc> { it.startMinute }.thenBy { it.endMinute }.thenBy { it.id }
        )
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
     */
    private fun cancelEditor() {
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
        if (fid == null) {
            showEditorStatus(getString(R.string.schedule_no_family))
            return
        }
        val doc = ScheduleDoc(
            // 새 규칙이면 편집을 열 때 정해 둔 ID 를 쓴다([editorNewDocId] 주석).
            id = editorRuleId ?: editorNewDocId ?: UUID.randomUUID().toString(),
            days = editorDays.sorted(),
            startMinute = editorStartMinute,
            endMinute = editorEndMinute,
            mode = editorMode,
            enabled = editorEnabled,
            // 우선순위는 만든 순서다. 새 규칙에는 지금 있는 것들보다 하나 큰 값을
            // 주고(=나중에 만든 것이 이긴다), 고치는 중이면 원래 값을 그대로 둔다 —
            // 시각만 고쳤다고 규칙끼리의 승패가 뒤집히면 부모가 예측할 수 없다.
            priority = if (editorRuleId == null) nextPriority() else editorPriority,
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
                    ScheduleRepository.saveSchedule(fid, doc)
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
        if (fid == null) {
            showState(getString(R.string.schedule_no_family))
            return
        }
        val generation = ++writeGeneration
        showState(null)
        pendingSync = true

        viewLifecycleOwner.lifecycleScope.launch {
            try {
                val savedId = withTimeoutOrNull(WRITE_TIMEOUT_MILLIS) {
                    ScheduleRepository.saveSchedule(fid, doc.copy(enabled = enabled))
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
        if (fid == null) {
            showState(getString(R.string.schedule_no_family))
            return
        }
        val generation = ++writeGeneration
        showState(getString(R.string.schedule_deleting))
        pendingSync = true

        viewLifecycleOwner.lifecycleScope.launch {
            try {
                val done = withTimeoutOrNull(WRITE_TIMEOUT_MILLIS) {
                    ScheduleRepository.deleteSchedule(fid, doc.id)
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
     * 지난번에 못 보낸 [CommandType.SYNC_RULES] 를 화면이 다시 열릴 때 한 번 더 보낸다.
     *
     * Firestore 콜백에서 불리므로 화면이 이미 사라진 뒤일 수 있다. 그때
     * `viewLifecycleOwner` 를 건드리면 그대로 예외라 `_binding` 으로 먼저 막는다 —
     * `_binding` 이 살아 있다는 것은 뷰 생명주기가 아직 유효하다는 뜻이다.
     */
    private fun resendPendingSync() {
        _binding ?: return
        val generation = writeGeneration
        viewLifecycleOwner.lifecycleScope.launch {
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

    /** 새 규칙의 우선순위. 지금 있는 것 중 가장 큰 값보다 하나 크다(= 나중에 만든 것이 이긴다). */
    private fun nextPriority(): Int = (rules.maxOfOrNull { it.priority } ?: 0) + 1

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
        b.scheduleEmpty.visibility = if (rules.isEmpty()) View.VISIBLE else View.GONE
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

        // 토글 그룹에 값을 대입하면 리스너가 불린다 — 그대로 두면 방금 그린 값을
        // 리스너가 다시 상태로 되돌려 쓰는 순환이 생긴다. 그리는 동안만 막는다.
        suppressToggleCallbacks = true
        DAY_BUTTON_IDS.forEachIndexed { index, id ->
            if ((index + 1) in editorDays) b.dayGroup.check(id) else b.dayGroup.uncheck(id)
        }
        b.modeGroup.check(
            when (editorMode) {
                ScheduleText.MODE_NORMAL -> R.id.schedule_mode_normal
                ScheduleText.MODE_SILENT -> R.id.schedule_mode_silent
                else -> R.id.schedule_mode_vibrate
            }
        )
        suppressToggleCallbacks = false

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

    private fun setEditorBusy(busy: Boolean) {
        editorBusy = busy
        val b = _binding ?: return
        b.editorSaveButton.isEnabled = !busy
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
        activeDialog?.dismiss()
        activeDialog = null
        backCallback?.remove()
        backCallback = null
        _binding?.dayGroup?.clearOnButtonCheckedListeners()
        _binding?.modeGroup?.clearOnButtonCheckedListeners()
        _binding = null
        super.onDestroyView()
    }

    private companion object {
        /** 인덱스 + 1 이 요일값(1=월 … 7=일)이다. ScheduleRule.days 와 같은 규칙. */
        val DAY_BUTTON_IDS = intArrayOf(
            R.id.day_mon, R.id.day_tue, R.id.day_wed, R.id.day_thu,
            R.id.day_fri, R.id.day_sat, R.id.day_sun,
        )

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

        const val KEY_PENDING_SYNC = "pending_sync"
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
