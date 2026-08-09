package com.kidcare.family.guardian

import android.content.Context
import android.os.Bundle
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.core.view.children
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import com.google.android.material.chip.Chip
import com.google.android.material.timepicker.MaterialTimePicker
import com.google.android.material.timepicker.TimeFormat
import com.google.firebase.firestore.ListenerRegistration
import com.kidcare.family.R
import com.kidcare.family.core.AuthGateway
import com.kidcare.family.core.CommandRepository
import com.kidcare.family.core.FamilyRepository
import com.kidcare.family.core.RoleStore
import com.kidcare.family.core.ScheduleRepository
import com.kidcare.family.core.errorMessage
import com.kidcare.family.core.model.CommandDoc
import com.kidcare.family.core.model.CommandState
import com.kidcare.family.core.model.CommandType
import com.kidcare.family.core.model.RingerSettingsDoc
import com.kidcare.family.databinding.FragmentControlBinding
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * 관리 탭. 부모가 버튼을 누르면 아이 폰이 바뀐다.
 *
 * 이 화면의 원칙은 "정직한 표시"다. 명령을 보낸 뒤에는 [CommandRepository.observeOne]
 * 로 그 명령 문서 하나를 따라가며 `전달 중…` → `완료`를 보여주고, 60초 안에 아이 폰이
 * 아무 대답도 하지 않으면 "애기폰이 응답하지 않아요"와 마지막 신호 시각을 함께 띄운다
 * (설계서 §5). 눌렀는데 아무 반응이 없는 화면이 부모에게는 가장 나쁘다.
 *
 * "완료"가 뜻하는 것은 **아이 폰이 done 이라고 적었다**는 것 하나뿐이다. 아이가 실제로
 * 실행하지 않고 상태만 앞으로 밀어도 규칙으로는 막을 수 없다(firestore.rules 의
 * commands update 주석, docs/known-issues.md). 그 이상을 뜻하는 문구를 쓰지 않는
 * 이유다.
 *
 * 모드 값("normal"/"vibrate"/"silent")과 페이로드 키("mode")는 자녀 폰의
 * `child/CommandHandler`·`child/RingerMode` 와 맞춰야 하는 약속인데, guardian 은
 * child 를 import 하지 않으므로(설계서 §3 모듈 경계) 값을 아래 companion 에 다시
 * 적는다. 바꿀 일이 생기면 반드시 두 곳을 함께 고쳐야 한다.
 *
 * 메시지와 알람의 페이로드 키만 예외적으로 [CommandType] 의 상수를 직접 쓴다
 * ([CommandType.PAYLOAD_TEXT]·[CommandType.PAYLOAD_AT_MINUTE_OF_DAY]·
 * [CommandType.PAYLOAD_LABEL]) — 그 오브젝트는 guardian·child 가 이미 함께 import 하는
 * 자리라 굳이 두 벌로 만들 이유가 없다(그 상수 주석에 근거를 적었다).
 *
 * 알람 시각은 **부모 폰에서 절대 시각으로 바꾸지 않는다.** 보내는 것은 하루 안의 분
 * 하나이고, 오늘인지 내일인지는 아이 폰이 정한다([CommandType.SET_ALARM]). 이 화면이
 * 그 대신 들고 있는 것은 "내가 무엇을 보냈나"라는 기억뿐이다([AlarmMemoStore]).
 */
class ControlFragment : Fragment() {

    private var _binding: FragmentControlBinding? = null

    private var joinedListener: ListenerRegistration? = null
    private var settingsListener: ListenerRegistration? = null
    private var commandListener: ListenerRegistration? = null

    /** 마지막 신호 시각 한 번 읽기. 옛 statusListener 를 대신한다. */
    private var statusJob: Job? = null

    /** 연결 끊김 배너의 판정 재료를 적는 곳([RequestLog], DisconnectRule 주석 참고). */
    private val requestLog by lazy { RequestLog(requireContext().applicationContext) }

    private var familyId: String? = null
    private var childUid: String? = null

    /**
     * 아이 폰이 마지막으로 남긴 신호. null 이면 아직 한 번도 없다.
     *
     * 시각뿐 아니라 **누구 시계로 적힌 값인지**도 함께 들고 있다([ChildSignal]) —
     * 서버 시각이면 뺄셈의 양쪽이 같은 시계라 "12분 전"을 그대로 믿을 수 있고,
     * 아이 폰 시계면 그럴 수 없다([lastSeenPhrase]).
     */
    private var lastSignal: ChildSignal? = null

    private var timeoutJob: Job? = null
    private var findResetJob: Job? = null
    private var lockSaveJob: Job? = null

    /** 60초가 지나 "응답 없음"을 이미 띄웠는가. 늦게 오는 pending/delivered 스냅샷이
     *  실패 문구를 다시 "전달 중…"으로 되돌리지 못하게 막는다. */
    private var timedOut = false

    /**
     * 지금 화면이 따라가고 있는 명령의 세대 번호. [send] 를 부를 때마다 하나씩 는다.
     *
     * 발행은 코루틴이라 "버튼을 눌렀다"와 "명령 문서 id 를 받았다" 사이에 네트워크
     * 왕복이 한 번 있다. 버튼은 일부러 잠그지 않으므로([send] 주석) 부모가 진동을
     * 눌렀다가 곧바로 무음으로 고치면 그 왕복 안에서 두 번째 발행이 시작되고, 두
     * 코루틴이 **모두** [track] 에 도착한다. 세대 번호가 없으면 뒤에 도착한 쪽이
     * `commandListener` 와 `timeoutJob` 을 그냥 덮어써서 이렇게 된다.
     *
     * - 먼저 붙은 리스너는 `remove()` 없이 참조를 잃는다 — 화면을 떠나도 안 떨어지는
     *   Firestore 리스너가 하나 영구히 남는다.
     * - 밀려난 첫 명령이 나중에 done/failed 가 되면 그 고아 리스너가 깨어나 **두 번째**
     *   명령의 60초 타이머를 끄고, 부모가 보고 있지도 않은 명령의 "완료"를 적는다.
     * - 그래서 두 번째 명령이 진짜로 먹통이 돼도 "애기폰이 응답하지 않아요"가 영영
     *   안 뜬다 — 타이머가 이미 남의 손에 꺼졌기 때문이다.
     *
     * 그래서 발행 **전에** 세대를 붙잡아 두고, 왕복이 끝난 뒤·리스너 콜백 안·타임아웃
     * 안에서 그 값이 아직 최신인지 확인한다. 최신이 아니면 화면도 타이머도 건드리지
     * 않는다.
     */
    private var commandGeneration = 0

    /**
     * 지금 따라가고 있는 명령의 종류. [send] 가 매번 다시 정하고, null 이면 따라가는
     * 명령이 없다.
     *
     * 종류를 들고 있어야 하는 이유가 둘이다. 하나는 아래 [trackingMessage] 이고, 다른
     * 하나는 알람 기억([alarmMemo])이다 — `done` 하나를 두고 "알람이 맞춰졌다"와 "알람이
     * 꺼졌다"와 "그 밖의 완료"가 서로 다른 일을 해야 한다.
     */
    private var trackingType: String? = null

    /**
     * 지금 따라가고 있는 명령이 **메시지**인가.
     *
     * 메시지만 상태 줄의 뜻이 다르기 때문에 필요하다. 다른 명령에서 `delivered` 는
     * 잠깐 지나가는 중간역이지만, 메시지에서는 **아이가 아직 안 읽었다**는 최종
     * 상태일 수 있다 — 아이가 '확인했어요'를 눌러야 done 이 되니까(설계서 §3,
     * [CommandType.MESSAGE]). 그래서 같은 `delivered` 를 두고
     *
     * - 다른 명령: "전달 중…", 60초 뒤 "애기폰이 응답하지 않아요"
     * - 메시지: "애기폰에 도착했어요 · 아직 안 읽음", 타임아웃 없음
     *
     * 으로 갈라 적는다. 이 둘을 한 문장으로 뭉개면 부모는 잘 전해진 메시지를 보고
     * 아이 폰이 죽었다고 읽는다.
     *
     * 별도 필드가 아니라 [trackingType] 에서 파생시키는 이유: 같은 사실을 필드 둘이
     * 따로 들고 있으면 [send] 가 한쪽만 갱신하는 순간이 생기고, 그 순간의 화면은
     * 어느 쪽 해석도 아니게 된다.
     */
    private val trackingMessage: Boolean get() = trackingType == CommandType.MESSAGE

    /**
     * 부모가 고른 알람 시각(하루 안의 분). 기본값 7:00 은 이 통로가 실제로 쓰이는 자리
     * ("아침에 깨워줘")에 가장 가깝다.
     *
     * **이 값을 그대로 명령에 담고, 절대 시각으로 바꾸지 않는다** — 오늘인지 내일인지는
     * 아이 폰이 정한다([CommandType.SET_ALARM] 주석).
     */
    private var alarmMinute = DEFAULT_ALARM_MINUTE

    /** "애기폰에 알람을 맞춰 뒀다"는 부모 폰의 기억. 이유는 [AlarmMemoStore] 클래스 주석. */
    private val alarmMemo by lazy { AlarmMemoStore(requireContext().applicationContext) }

    /**
     * 부모가 방금 잠금 스위치로 만든 값. 아직 서버 스냅샷으로 되돌아오지 않았다.
     *
     * 이게 없으면 화면을 연 직후의 첫 읽기(또는 그 사이 지나가던 옛 스냅샷)가 부모가
     * 그 사이에 만진 스위치를 옛 값으로 덮어써 버린다 — 켰는데 저절로 꺼지는 스위치다.
     */
    private var pendingLockValue: Boolean? = null

    /**
     * 이 화면에서 폰찾기를 시작시킨 시각(부모 폰 시계). 0 이면 "우리가 울린 적 없다".
     * 자세한 판단 기준은 [renderFindButton] 주석 참고.
     */
    private var findStartedAt: Long = 0L

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        val binding = FragmentControlBinding.inflate(inflater, container, false)
        _binding = binding
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        val b = _binding ?: return

        // 화면이 회전해도 "지금 울리는 중"이라는 판단은 남아야 한다. 안 그러면
        // 회전 한 번에 버튼이 '핸드폰 찾기'로 되돌아가고, 그걸 누르면 이미 울리는
        // 폰에 시작 명령을 한 번 더 보내게 된다.
        findStartedAt = savedInstanceState?.getLong(KEY_FIND_STARTED_AT) ?: 0L
        alarmMinute = savedInstanceState?.getInt(KEY_ALARM_MINUTE) ?: DEFAULT_ALARM_MINUTE

        b.modeNormalButton.setOnClickListener { sendRinger(MODE_NORMAL) }
        b.modeVibrateButton.setOnClickListener { sendRinger(MODE_VIBRATE) }
        b.modeSilentButton.setOnClickListener { sendRinger(MODE_SILENT) }

        b.findButton.setOnClickListener {
            if (believedRinging()) sendStopFind() else sendFindPhone()
        }
        b.findStopButton.setOnClickListener { sendStopFind() }

        // 칩은 입력칸을 채우기만 한다(레이아웃 주석 참고). 칩마다 id 를 두고 리스너를
        // 네 번 다는 대신 자식들을 훑는다 — 문장을 하나 더 넣을 때 XML 만 고치면 된다.
        b.messageChips.children.filterIsInstance<Chip>().forEach { chip ->
            chip.setOnClickListener {
                b.messageInput.setText(chip.text)
                // 커서를 끝으로. 칩을 누른 뒤 바로 고쳐 쓰는 경우가 많다.
                b.messageInput.setSelection(chip.text.length)
            }
        }
        b.messageSendButton.setOnClickListener { sendMessage() }

        b.alarmTimeButton.setOnClickListener { showAlarmTimePicker() }
        b.alarmSetButton.setOnClickListener { sendSetAlarm() }
        b.alarmCancelButton.setOnClickListener { sendCancelAlarm() }
        // 회전하면 MaterialTimePicker 자신은 FragmentManager 가 되살리지만 리스너는
        // 되살아나지 않는다 — 그대로 두면 확인을 눌러도 시각이 안 바뀌고 창만 닫힌다.
        // ScheduleFragment.rebindTimePickers 가 같은 이유로 있다.
        (childFragmentManager.findFragmentByTag(TAG_PICK_ALARM) as? MaterialTimePicker)
            ?.let { bindAlarmTimePicker(it) }

        // CompoundButton 의 클릭 리스너는 사람이 누를 때만 불린다 — 아래 renderLock()
        // 이 하는 프로그램적 isChecked 대입으로는 불리지 않는다. 그래서 "서버에서 온
        // 값"과 "부모가 누른 값"이 섞이지 않는다(setOnCheckedChangeListener 로는
        // 이 둘을 구분할 수 없어 플래그를 세워 껐다 켜야 한다).
        b.lockSwitch.setOnClickListener { saveLock(b.lockSwitch.isChecked) }

        setChildDependentButtonsEnabled(false)
        renderFindButton()
        renderAlarm()
        renderCommand(CommandUi.Idle)
        subscribe()

        if (believedRinging()) {
            // 회전 전에 걸어둔 타이머는 사라졌다. 남은 시간만큼 다시 건다.
            scheduleFindReset(FIND_AUTO_STOP_MILLIS - (System.currentTimeMillis() - findStartedAt))
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putLong(KEY_FIND_STARTED_AT, findStartedAt)
        outState.putInt(KEY_ALARM_MINUTE, alarmMinute)
    }

    // ---------------------------------------------------------------- 구독

    /**
     * 가족 단위 설정(잠금 스위치)은 아이가 없어도 읽고 쓸 수 있으므로 곧바로 구독하고,
     * 아이에게 보내는 명령은 childUid 가 필요하므로 아이가 들어오는 것을 지켜본다.
     *
     * [FamilyRepository.findChildUid] 로 한 번만 조회하지 않는 이유는
     * MapTimelineFragment 와 같다(known-issues 3): 부모가 이 화면을 켜 둔 채로 아이가
     * 페어링을 끝내면, 한 번 조회 방식에서는 화면을 다시 만들기 전까지 버튼이 계속
     * 꺼져 있다.
     */
    private fun subscribe() {
        val roleStore = RoleStore(requireContext())
        val fid = roleStore.familyId ?: return
        familyId = fid
        val selectedUid = roleStore.selectedChildUid
        if (selectedUid == null) {
            setChildDependentButtonsEnabled(false)
            showChildState(getString(R.string.map_no_child))
            return
        }
        childUid = selectedUid

        settingsListener = ScheduleRepository.observeRingerSettings(
            fid,
            selectedUid,
            onChange = { doc -> renderLock(doc.lockEnabled) },
            onError = { e -> showChildState(errorMessageOrNull(e)) },
        )

        joinedListener = FamilyRepository.observeChildJoined(
            fid,
            preferredChildUid = selectedUid,
            onJoined = { uid ->
                if (uid == childUid) return@observeChildJoined
                childUid = uid
                setChildDependentButtonsEnabled(true)
                showChildState(null)
                loadStatus(fid, uid)
            },
            onError = { e -> showChildState(errorMessageOrNull(e)) },
        )
    }

    /**
     * 마지막 신호 시각만 쓴다 — 60초 무응답 문구에 붙일 값이다(설계서 §5).
     *
     * 옛 코드는 이 문서를 화면이 떠 있는 내내 구독했다. 자녀 폰이 위치를 올릴 때마다
     * 이 문서를 덮어쓰던 시절에는 그게 "실시간"이었지만, 이제 이 문서는 부모가
     * 물어볼 때와 하루 한 번만 바뀐다(docs/known-issues.md 12번) — 구독을 유지해도
     * 얻는 것 없이 읽기만 는다. 화면을 열 때 한 번 읽고 끝낸다.
     */
    private fun loadStatus(fid: String, uid: String) {
        statusJob?.cancel()
        statusJob = viewLifecycleOwner.lifecycleScope.launch {
            try {
                lastSignal = FamilyRepository.fetchChildStatus(fid, uid)?.lastSignal()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // 이 값은 60초 무응답 문구에 붙는 보조 정보다. 못 읽어도 화면 전체를
                // 오류로 덮지 않는다 — lastSeenPhrase 가 "아직 한 번도 신호가
                // 없었어요"로 정직하게 물러난다.
                Log.w(TAG, "마지막 신호 시각을 못 읽었다", e)
            }
        }
    }

    // ---------------------------------------------------------------- 명령 보내기

    private fun sendRinger(mode: String) {
        // 페이로드 키 "mode" 는 child/CommandHandler 가 읽는 키다. 여기서 오타가 나면
        // 아이 폰은 빈 모드를 받아 실패로 처리한다.
        send(CommandType.SET_RINGER, mapOf(PAYLOAD_MODE to mode))
    }

    private fun sendFindPhone() {
        send(CommandType.FIND_PHONE) {
            // 명령이 실제로 만들어진 뒤에만 버튼을 '소리 끄기'로 바꾼다. 누르자마자
            // 바꿔놓으면 발행 자체가 실패했을 때 울리지도 않는 폰을 끄라고 하게 된다.
            findStartedAt = System.currentTimeMillis()
            renderFindButton()
            scheduleFindReset(FIND_AUTO_STOP_MILLIS)
        }
    }

    private fun sendStopFind() {
        send(CommandType.STOP_FIND) {
            findStartedAt = 0L
            findResetJob?.cancel()
            findResetJob = null
            renderFindButton()
        }
    }

    /**
     * 부모가 쓴 한마디를 보낸다.
     *
     * 길이 상한(100자)은 입력칸이 이미 막고 있다(`android:maxLength`, 레이아웃 주석).
     * 여기서 다시 자르지 않는 이유가 그것이다 — 보내는 순간에 조용히 잘라내면 부모는
     * 자기가 쓴 문장의 뒷부분이 사라진 줄 모른다.
     *
     * 입력칸을 비우는 것은 발행이 실제로 성공한 뒤([send] 의 `onSent`)다. 누르자마자
     * 비우면 오프라인에서 발행이 실패했을 때 방금 쓴 문장이 어디에도 안 남는다.
     */
    private fun sendMessage() {
        val b = _binding ?: return
        val text = b.messageInput.text?.toString()?.trim().orEmpty()
        if (text.isEmpty()) {
            renderCommand(CommandUi.Failed(getString(R.string.control_message_empty)))
            return
        }
        send(CommandType.MESSAGE, mapOf(CommandType.PAYLOAD_TEXT to text)) {
            _binding?.messageInput?.setText("")
        }
    }

    // ---------------------------------------------------------------- 알람 맞추기

    /**
     * 24시간 표기로 고정하는 이유는 [ScheduleFragment.showTimePicker] 와 같다 — 화면의
     * 다른 시각 표시(`07:00`)와 고르는 창의 표기가 어긋나면 부모가 둘을 머릿속에서
     * 맞춰봐야 하고, 새벽·밤 시각에서 특히 헷갈린다.
     */
    private fun showAlarmTimePicker() {
        val picker = MaterialTimePicker.Builder()
            .setTimeFormat(TimeFormat.CLOCK_24H)
            .setHour(alarmMinute / 60)
            .setMinute(alarmMinute % 60)
            .setTitleText(R.string.control_alarm_picker_title)
            .build()
        bindAlarmTimePicker(picker)
        picker.show(childFragmentManager, TAG_PICK_ALARM)
    }

    private fun bindAlarmTimePicker(picker: MaterialTimePicker) {
        picker.addOnPositiveButtonClickListener {
            alarmMinute = picker.hour * 60 + picker.minute
            renderAlarm()
        }
    }

    /**
     * 알람을 맞춘다. **보내는 것은 하루 안의 분과 이름뿐이다** — 절대 시각을 여기서
     * 계산하면 두 폰의 시간대·시계 차이가 그대로 어긋남이 된다([CommandType.SET_ALARM]).
     *
     * 기억을 `onSent`(발행 성공)에서 적고 `done` 에서 굳히는 이유: 여기서 미리 적으면
     * 오프라인으로 발행이 실패했을 때 걸리지도 않은 알람이 화면에 남고, 반대로 done 에서만
     * 적으면 부모가 대답을 기다리는 동안(최대 60초, 그 사이에 탭을 옮기면 영영) 화면이
     * "아무 알람도 없음"이라고 말한다. 두 단계로 두면 화면이 어느 순간에도 거짓말을 안 한다.
     */
    private fun sendSetAlarm() {
        val b = _binding ?: return
        val uid = childUid ?: return
        val label = b.alarmLabelInput.text?.toString()?.trim().orEmpty()
        val minute = alarmMinute
        send(
            CommandType.SET_ALARM,
            mapOf(
                CommandType.PAYLOAD_AT_MINUTE_OF_DAY to minute.toString(),
                CommandType.PAYLOAD_LABEL to label,
            ),
        ) {
            alarmMemo.recordSent(uid, minute, label)
            renderAlarm()
        }
    }

    /**
     * 맞춰둔 알람을 끈다. 부모 폰의 기억은 **발행이 성공한 순간** 지운다 — 아이 폰이
     * 대답하기 전에 지우는 셈이지만, 여기서 남겨두면 '알람 끄기'를 누른 부모 화면에
     * "알람이 맞춰져 있어요"가 그대로 남아 부모가 한 번 더 누르게 된다. 명령 자체가
     * 실패하면 아래 [onCommandChanged] 가 실패 문구를 띄운다.
     */
    private fun sendCancelAlarm() {
        val uid = childUid ?: return
        send(CommandType.CANCEL_ALARM) {
            alarmMemo.clear(uid)
            renderAlarm()
        }
    }

    /**
     * 명령을 발행하고 그 문서 하나를 따라가기 시작한다.
     *
     * 앞선 명령의 추적은 여기서 끊는다 — 부모가 진동을 누른 직후 무음을 누르는 것은
     * 자연스러운 행동이고, 그때 화면이 말해야 하는 것은 방금 누른 명령의 상태다.
     * 버튼을 잠그지 않는 이유이기도 하다: 응답이 60초까지 걸릴 수 있는데 그동안
     * 버튼이 죽어 있으면 화면이 고장 난 것처럼 보인다.
     *
     * 다만 여기서 끊는 것만으로는 모자란다. 발행은 왕복 한 번이 걸리는 코루틴이라
     * 두 번째 누름이 첫 번째 왕복 **안에서** 시작될 수 있고, 그러면 두 코루틴이
     * 나란히 [track] 까지 간다. 그래서 [commandGeneration] 으로 "지금 화면의 주인"을
     * 하나로 못박는다 — 자세한 이유는 그 필드 주석에 적었다.
     */
    private fun send(
        type: String,
        payload: Map<String, String> = emptyMap(),
        onSent: () -> Unit = {},
    ) {
        val fid = familyId
        val uid = childUid
        if (fid == null || uid == null) {
            renderCommand(CommandUi.Failed(getString(R.string.map_no_child)))
            return
        }
        stopTracking()
        timedOut = false
        // 상태 줄이 무슨 뜻으로 읽혀야 하는지가 명령 종류에 달렸다([trackingMessage]).
        // 세대 번호와 같은 자리에서 정해 둬야 늦게 오는 앞 명령의 콜백이 새 명령의
        // 해석을 물려받지 않는다.
        trackingType = type
        // 발행 결과를 기다리는 동안 부모가 다른 버튼을 누를 수 있다. 지금 이 순간의
        // 세대를 붙잡아 두고, 왕복이 끝난 뒤 그 값이 아직 최신인지로 판단한다
        // ([commandGeneration] 주석 참고).
        val generation = ++commandGeneration
        // 명령 종류와 상관없이 "물어봤다"로 친다. 아이 폰이 강제 종료돼 있으면 소리
        // 모드 변경이든 폰찾기든 똑같이 대답이 없고, 연결 끊김 배너가 알리려는 것이
        // 바로 그 상태다(DisconnectRule).
        requestLog.recordRequest(uid)
        renderCommand(CommandUi.Sending)

        viewLifecycleOwner.lifecycleScope.launch {
            try {
                // 제한시간이 필요한 이유: Firestore 쓰기 Task 는 **서버가 확인해 준
                // 순간에만** 완료되고 제한시간이 없다([com.kidcare.family.KidCareApp]
                // 주석). 오프라인이면 명령 문서는 로컬 큐에 잘 들어가지만 이 await 는
                // 영영 안 돌아오고, 그러면 아래 track() 도 60초 타이머도 시작되지 않아
                // **화면이 '전달 중…'과 도는 스피너에 영원히 갇힌다.** 부모는 지금
                // 애기폰으로 가는 중이라고 읽는다.
                //
                // 끊어도 쓰기는 취소되지 않는다 — 연결되면 그대로 나간다
                // (ScheduleFragment.WRITE_TIMEOUT_MILLIS 와 같은 장치·같은 값).
                val commandId = withTimeoutOrNull(SEND_TIMEOUT_MILLIS) {
                    CommandRepository.send(fid, uid, type, payload)
                }
                _binding ?: return@launch
                if (commandId == null) {
                    // **여기서 onSent() 를 부르면 안 된다.** 그 콜백들은 전부 "명령이
                    // 실제로 나갔다"를 전제로 화면을 고친다 — 울리지도 않는 폰에
                    // '소리 끄기' 버튼을 띄우고(sendFindPhone), 걸리지도 않은 알람을
                    // "맞춰져 있어요"로 적는다(sendSetAlarm). 큐에 들어간 것은 나간
                    // 것이 아니다.
                    if (generation != commandGeneration) return@launch
                    renderCommand(CommandUi.Queued)
                    return@launch
                }
                // onSent 는 세대와 상관없이 부른다. 이건 "화면 한 줄에 무엇을 적을까"가
                // 아니라 "명령이 실제로 발행됐다"는 사실이고(폰찾기 버튼의 상태가 여기에
                // 달려 있다), 부모가 그 사이에 다른 버튼을 눌렀다고 해서 아이 폰이
                // 울리기 시작한 사실이 없어지지는 않는다.
                onSent()
                // 기다리는 동안 더 새로운 명령이 나갔다면 화면은 그 명령의 것이다.
                // 여기서 track() 을 부르면 남의 리스너와 타이머를 덮어쓴다 — 리스너를
                // 아예 만들지 않으므로 remove() 를 빠뜨릴 길도 함께 없어진다.
                if (generation != commandGeneration) return@launch
                track(fid, uid, commandId, generation)
            } catch (e: CancellationException) {
                // 화면을 떠나며 스코프가 취소된 것이다. 실패로 표시하면 안 된다.
                throw e
            } catch (e: Exception) {
                // 이미 밀려난 명령의 실패다. 부모가 지금 보고 있는 명령의 "전달 중…"을
                // 실패 문구로 덮어쓰면, 정작 진행 중인 명령이 실패한 것처럼 보인다.
                if (generation != commandGeneration) return@launch
                val ctx = context ?: return@launch
                renderCommand(CommandUi.Failed(errorMessage(ctx, e)))
            }
        }
    }

    /**
     * 명령 문서 하나를 따라가기 시작한다.
     *
     * [generation] 은 [send] 가 발행 **전에** 붙잡아 둔 값이다. 리스너 콜백도 타임아웃도
     * 그 값이 아직 최신일 때만 화면과 타이머를 만진다 — `ListenerRegistration.remove()`
     * 는 "앞으로 오지 마라"는 뜻이지 이미 큐에 올라간 콜백까지 되돌리지는 않으므로,
     * 리스너를 뗐다는 사실만 믿지 않고 콜백 안에서 한 번 더 확인한다.
     */
    private fun track(fid: String, uid: String, commandId: String, generation: Int) {
        // 대입하기 전에 반드시 앞의 것을 뗀다. 지금 호출 경로에서는 send 앞머리가 이미
        // 떼어 놓았지만, 이 한 줄이 있어야 "commandListener 를 remove() 없이 덮어쓰는
        // 경로는 없다"가 이 함수만 읽어도 성립한다.
        stopTracking()
        commandListener = CommandRepository.observeOne(
            fid, uid, commandId,
            onChange = { doc ->
                if (generation == commandGeneration) onCommandChanged(doc)
            },
            onError = { e ->
                if (generation != commandGeneration) return@observeOne
                val message = errorMessageOrNull(e)
                if (message != null) {
                    timeoutJob?.cancel()
                    timeoutJob = null
                    renderCommand(CommandUi.Failed(message))
                }
            },
        )
        timeoutJob = viewLifecycleOwner.lifecycleScope.launch {
            delay(COMMAND_TIMEOUT_MILLIS)
            if (generation != commandGeneration) return@launch
            onTimedOut(generation)
        }
    }

    private fun onCommandChanged(doc: CommandDoc) {
        _binding ?: return
        when (doc.state) {
            CommandState.DONE -> {
                timeoutJob?.cancel()
                timeoutJob = null
                recordAnswer()
                // 알람 맞추기의 done 은 "아이 폰이 알람을 걸었다"는 뜻이다. 여기서
                // 기억을 굳혀야 부모가 탭을 옮겼다 돌아와도 걸어둔 알람이 보인다
                // (AlarmMemoStore 클래스 주석 — 이 기록이 뜻하는 것과 뜻하지 않는 것).
                if (trackingType == CommandType.SET_ALARM) {
                    childUid?.let { alarmMemo.recordConfirmed(it) }
                    renderAlarm()
                }
                // 메시지의 done 은 "아이가 확인했어요를 눌렀다"는 뜻이다. '완료'라고
                // 적으면 부모는 그걸 "보내기가 끝났다"로 읽는다 — 전혀 다른 말이다.
                renderCommand(if (trackingMessage) CommandUi.MessageRead else CommandUi.Done)
            }
            CommandState.FAILED -> {
                timeoutJob?.cancel()
                timeoutJob = null
                // 알람이 안 걸렸는데 화면에 "맞춰져 있어요"가 남으면 그게 이 기능에서
                // 제일 나쁜 거짓말이다. 실패는 곧 기억을 지우는 것이다.
                if (trackingType == CommandType.SET_ALARM) {
                    childUid?.let { alarmMemo.clear(it) }
                    renderAlarm()
                }
                // 실패도 대답이다 — 아이 폰이 살아 있으니 error 를 적을 수 있었다.
                // 연결 끊김 배너가 알리려는 것은 "죽어서 아무 말이 없다"이지
                // "할 수 없다고 답했다"가 아니다.
                recordAnswer()
                renderCommand(CommandUi.Failed(childErrorText(doc.error)))
            }
            // 아직 진행 중이다. 이미 "응답 없음"을 띄운 뒤라면 되돌리지 않는다 —
            // 실패 문구 아래에서 스피너가 다시 도는 화면을 만들지 않기 위해서다.
            CommandState.PENDING, CommandState.DELIVERED -> {
                if (trackingMessage && doc.state == CommandState.DELIVERED) {
                    // 메시지는 여기가 종착역일 수 있다 — 아이가 안 누르면 영영 done 이
                    // 안 된다. 그래서 60초 타이머를 **여기서 끈다.** 안 끄면 잘 전해진
                    // 메시지 위에 "애기폰이 응답하지 않아요"가 덮이는데, 그건 사실이
                    // 아니다: 아이 폰은 delivered 를 적을 만큼 멀쩡히 살아 있었다.
                    timeoutJob?.cancel()
                    timeoutJob = null
                    // delivered 를 적었다는 것 자체가 아이 폰의 대답이다. 이걸 안 남기면
                    // 아이가 메시지를 안 읽는 동안 연결 끊김 배너가 "대답이 없다"고
                    // 잘못 뜬다(RequestLog·DisconnectRule).
                    recordAnswer()
                    renderCommand(CommandUi.MessageUnread)
                } else if (!timedOut) {
                    renderCommand(CommandUi.Sending)
                }
            }
            else -> Unit
        }
    }

    /**
     * 60초가 지나도 아이 폰이 대답하지 않았다. 여기서 하는 말은 "명령이 실패했다"가
     * 아니라 "대답이 없다"이다 — 명령 문서는 그대로 남아 있고 아이 폰이 나중에
     * 살아나면 그때 실행된다. 그래서 리스너는 떼지 않는다: 늦게라도 done 이 오면
     * 위 [onCommandChanged] 가 "완료"로 고쳐 준다.
     */
    private suspend fun onTimedOut(generation: Int) {
        _binding ?: return
        timedOut = true
        // 마지막 신호 문구는 서버 시각을 물어보느라 잠깐 걸릴 수 있다. 그동안 스피너가
        // 계속 도는 일이 없도록 실패 표시를 먼저 확정하고, 문구는 뒤에 채워 넣는다.
        renderCommand(CommandUi.Failed(getString(R.string.control_command_timeout)))

        val seen = elapsedSinceLastSeen()
        // 위 한 줄에서 화면을 떠났거나 부모가 새 명령을 눌렀을 수 있다. 여기서부터는
        // 붙잡아 둔 Context 로만 문자열을 만든다 — Fragment.getString 은 화면이 떨어져
        // 나간 뒤에 부르면 그대로 예외다.
        //
        // 세대도 여기서 다시 본다. 코루틴 취소만 믿을 수 없기 때문이다:
        // FamilyRepository.serverNow 는 오프셋이 이미 캐시돼 있으면 정지점 없이 곧장
        // 돌아오므로, 그 사이 timeoutJob 이 취소됐어도 이 줄까지 그대로 흘러온다.
        _binding ?: return
        if (generation != commandGeneration) return
        val ctx = context ?: return
        renderCommand(
            CommandUi.Failed(
                ctx.getString(R.string.control_command_timeout_format, lastSeenPhrase(ctx, seen))
            )
        )
    }

    /** 마지막 신호와, 그로부터 흐른 시간. 신호가 한 번도 없었으면 이 값 자체가 null 이다. */
    private data class SeenElapsed(val signal: ChildSignal, val elapsedMillis: Long)

    /**
     * 마지막 신호로부터 흐른 시간. null 이면 아이 폰이 한 번도 신호를 준 적이 없다.
     * **음수로 돌아올 수 있다** — 그 뜻과 처리는 [lastSeenPhrase] 참고.
     *
     * 기준 시각을 [FamilyRepository.serverNow] 로 얻는 이유: 부모 폰 시계가 뒤처져
     * 있으면 [System.currentTimeMillis] 로 뺀 값이 음수가 돼 "마지막 신호 -3분 전"이
     * 찍힌다.
     *
     * 아이 폰이 새 버전이면 [ChildSignal.fromServerClock] 이 true 이고, 그때는 뺄셈의
     * 양쪽이 모두 **서버 시각**이라 아이 폰 시계가 어긋나 있어도 이 값이 정확하다
     * (docs/known-issues.md 7번을 그렇게 닫았다). 옛 버전이면 아이 폰이 자기 시계로
     * 적은 값이라 여전히 음수가 나올 수 있고, 그 예외 경로는 아래에서 다룬다.
     */
    private suspend fun elapsedSinceLastSeen(): SeenElapsed? {
        val signal = lastSignal ?: return null
        val now = FamilyRepository.serverNow(familyId, AuthGateway.currentUid())
        return SeenElapsed(signal, now - signal.atMillis)
    }

    /**
     * "마지막 신호 12분 전". 계산은 위에서 끝났고 여기서는 문장만 고른다.
     *
     * 경과가 음수일 때(아이 폰 시계가 앞선 옛 버전)의 처리는 지도 탭과 같아야 하므로
     * [LastSignalText.relativeText] 한 곳에 모아 뒀다 — 근거도 거기 적혀 있다.
     */
    private fun lastSeenPhrase(ctx: Context, seen: SeenElapsed?): String {
        if (seen == null) return ctx.getString(R.string.control_last_seen_never)
        return ctx.getString(
            R.string.control_last_seen_format,
            LastSignalText.relativeText(ctx, seen.signal, seen.elapsedMillis),
        )
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
        ERROR_RINGER_DENIED -> getString(R.string.control_error_ringer_denied)
        // 메시지가 아이 폰 화면에 아예 못 뜬 경우. 부모가 할 수 있는 일(아이 폰에서
        // 알림 켜기)이 분명하므로 그것까지 문장에 담는다.
        CommandType.ERROR_NOTIFICATION_OFF ->
            getString(R.string.control_error_message_notification_off)
        // 아이 폰에서 정확한 알람을 못 건다. 이것도 부모가 할 수 있는 일(아이 폰에서
        // '알람 및 리마인더' 켜기)이 분명하므로 그것까지 문장에 담는다.
        CommandType.ERROR_ALARM_EXACT_DENIED ->
            getString(R.string.control_error_alarm_exact_denied)
        else -> getString(R.string.control_error_child_failed)
    }

    private fun stopTracking() {
        commandListener?.remove()
        commandListener = null
        timeoutJob?.cancel()
        timeoutJob = null
    }

    // ---------------------------------------------------------------- 잠금 스위치

    /**
     * 서버에서 온 값을 화면에 반영한다.
     *
     * 부모가 방금 만진 값([pendingLockValue])이 아직 되돌아오지 않았다면 그대로 둔다 —
     * 화면을 연 직후 첫 읽기가 늦게 도착해 방금 켠 스위치를 도로 끄는 일을 막는다.
     * 우리가 쓴 값이 스냅샷으로 돌아오면(Firestore 는 로컬 쓰기를 즉시 한 번
     * 되돌려준다) 그때 대기 상태를 푼다.
     */
    private fun renderLock(enabled: Boolean) {
        val b = _binding ?: return
        val pending = pendingLockValue
        if (pending != null && pending != enabled) return
        pendingLockValue = null
        b.lockSwitch.isChecked = enabled
    }

    /**
     * settings/ringer 쓰기는 규칙상 보호자만 할 수 있다(firestore.rules 의 settings
     * 블록). 이 기기는 보호자로 페어링될 때 members/{uid}.role 을 'guardian' 으로
     * 만들었으므로(FamilyRepository.createFamily) 통과하는 것이 정상이지만, 규칙이
     * 아직 게시되지 않았거나 역할 문서가 어긋난 기기에서는 PERMISSION_DENIED 가 난다.
     * 그때 스위치만 조용히 제자리로 튕기면 부모는 스위치가 고장 났다고 생각한다 —
     * 되돌리되 이유를 반드시 함께 말한다.
     */
    private fun saveLock(enabled: Boolean) {
        val fid = familyId
        val uid = childUid
        val b = _binding ?: return
        if (fid == null || uid == null) {
            b.lockSwitch.isChecked = !enabled
            renderCommand(CommandUi.Failed(getString(R.string.map_no_child)))
            return
        }
        pendingLockValue = enabled
        lockSaveJob?.cancel()
        lockSaveJob = viewLifecycleOwner.lifecycleScope.launch {
            try {
                // 스위치는 이미 부모가 민 자리에 가 있고, Firestore 가 로컬 쓰기를 즉시
                // 되돌려주므로 renderLock 도 그 값을 굳힌다 — 즉 오프라인에서도 화면은
                // "저장됐다"처럼 보인다. 서버 확인이 제한시간 안에 안 오면 그 사실을
                // 한 줄로 말한다. 스위치를 되돌리지는 않는다: 쓰기는 큐에 살아 있고
                // 연결되면 그대로 저장되므로, 되돌리면 그게 더 큰 거짓말이 된다.
                val saved = withTimeoutOrNull(SEND_TIMEOUT_MILLIS) {
                    ScheduleRepository.saveRingerSettings(fid, uid, RingerSettingsDoc(lockEnabled = enabled))
                }
                if (saved == null) {
                    _binding ?: return@launch
                    renderCommand(CommandUi.Queued)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val view = _binding ?: return@launch
                val ctx = context ?: return@launch
                pendingLockValue = null
                view.lockSwitch.isChecked = !enabled
                renderCommand(CommandUi.Failed(errorMessage(ctx, e)))
            }
        }
    }

    // ---------------------------------------------------------------- 그리기

    /**
     * 폰찾기 버튼이 무엇을 보여주는가.
     *
     * 아이 폰이 지금 울리고 있는지는 **알 방법이 없다.** status 문서에 그 값이 없고,
     * 자녀 폰이 5분 뒤 스스로 멈추기도 한다(child/FindPhoneController, 설계서 §4.5).
     * 그래서 이렇게 나눈다.
     *
     * - 앱을 새로 열었을 때: 우리가 울린 기억이 없으므로 큰 버튼은 '핸드폰 찾기'다.
     *   대신 아래 작은 버튼('이미 울리고 있다면 소리 끄기')이 항상 살아 있어서, 지난
     *   세션에 울려놓고 못 끈 폰도 여기서 끌 수 있다. 중지 명령은 울리지 않을 때 와도
     *   아이 폰에서 아무 일 없이 지나간다(FindPhoneController.stop 은 널 안전하다).
     * - 우리가 방금 울렸을 때: 큰 버튼이 '소리 끄기'가 된다. 작은 버튼은 같은 일을
     *   하게 되므로 숨긴다.
     * - 울린 지 5분이 지났을 때: 아이 폰은 이미 스스로 멈췄다. 큰 버튼을 '핸드폰 찾기'로
     *   되돌린다 — 아무것도 안 울리는데 '소리 끄기'가 떠 있으면 그게 더 헷갈린다.
     */
    private fun renderFindButton() {
        val b = _binding ?: return
        val ringing = believedRinging()
        b.findButton.setText(if (ringing) R.string.control_find_stop else R.string.control_find_phone)
        b.findStopButton.visibility = if (ringing) View.GONE else View.VISIBLE
    }

    private fun believedRinging(): Boolean =
        findStartedAt != 0L && System.currentTimeMillis() - findStartedAt < FIND_AUTO_STOP_MILLIS

    /**
     * 알람 구역 두 줄: 고른 시각이 적힌 버튼과, 지금 걸려 있는 알람 한 줄.
     *
     * 걸린 알람이 없으면 그 줄을 통째로 감춘다 — 빈 줄로 자리를 잡고 있으면 "없음"이
     * 하나의 상태처럼 읽히는데, 이 화면에서 알람은 있거나 없거나 둘 중 하나다.
     *
     * 문구를 '완료' 여부로 가르는 이유는 [AlarmMemoStore] 클래스 주석에 있다. 요약하면
     * 여기서 말할 수 있는 것은 "애기폰이 걸었다고 답했다"까지이고, 그 뒤에 아이가 앱을
     * 강제 종료하면 알람은 사라지지만 이 줄은 그 사실을 모른다. 그 자리를 덮는 것은
     * 지도·관리 화면 위의 연결 끊김 배너다.
     */
    private fun renderAlarm() {
        val b = _binding ?: return
        val ctx = context ?: return
        b.alarmTimeButton.text = ctx.getString(
            R.string.control_alarm_time_format, ScheduleText.timeText(ctx, alarmMinute),
        )

        val memo = childUid?.let { alarmMemo.memo(it) }
        b.alarmState.visibility = if (memo == null) View.GONE else View.VISIBLE
        if (memo == null) return
        val time = ScheduleText.timeText(ctx, memo.minuteOfDay)
        val what =
            if (memo.label.isEmpty()) time
            else ctx.getString(R.string.control_alarm_state_labeled, time, memo.label)
        b.alarmState.text = ctx.getString(
            if (memo.confirmed) R.string.control_alarm_state_confirmed
            else R.string.control_alarm_state_pending,
            what,
        )
    }

    private fun scheduleFindReset(afterMillis: Long) {
        findResetJob?.cancel()
        findResetJob = viewLifecycleOwner.lifecycleScope.launch {
            delay(afterMillis.coerceAtLeast(0L))
            findStartedAt = 0L
            renderFindButton()
        }
    }

    /** 명령 상태 한 줄. 스피너와 문구를 이 한 곳에서만 만진다 — 실패 문구 아래에서
     *  스피너가 계속 도는 화면(3단계 실기기 검증에서 잡힌 결함)을 구조적으로 막는다. */
    private sealed interface CommandUi {
        object Idle : CommandUi
        object Sending : CommandUi
        object Done : CommandUi

        /**
         * 메시지가 아이 폰에 닿았지만 아직 확인 버튼이 안 눌렸다.
         *
         * 스피너를 돌리지 않는 것이 [Sending] 과의 차이다 — 여기서 기다리는 것은
         * 네트워크가 아니라 **사람**이고, 도는 스피너는 "지금 뭔가 진행 중"이라는
         * 거짓말이 된다.
         */
        object MessageUnread : CommandUi

        /** 아이가 '확인했어요'를 눌렀다. */
        object MessageRead : CommandUi

        /**
         * 명령이 이 폰의 큐에만 들어갔다. 아직 서버에도, 애기폰에도 안 갔다.
         *
         * [Failed] 로 뭉개지 않는 이유: 실패가 아니다. 연결이 돌아오면 그대로 나가고
         * 애기폰이 그때 실행한다 — **그래서 오히려 말해줘야 한다.** 터널에서 누른
         * 무음이 한 시간 뒤 아이가 학원에 앉아 있을 때 걸릴 수 있다.
         *
         * [Sending] 과 달리 스피너를 안 돌린다. 여기서 기다리는 것은 왕복이 아니라
         * **통신 복구**라, 도는 스피너는 "곧 끝난다"는 거짓 신호가 된다
         * ([MessageUnread] 와 같은 판단).
         */
        object Queued : CommandUi

        data class Failed(val message: String) : CommandUi
    }

    private fun renderCommand(state: CommandUi) {
        val b = _binding ?: return
        val spinning = state is CommandUi.Sending
        b.commandProgress.visibility = if (spinning) View.VISIBLE else View.GONE
        b.commandStatus.visibility = if (state is CommandUi.Idle) View.GONE else View.VISIBLE
        b.commandStatus.text = when (state) {
            CommandUi.Idle -> ""
            CommandUi.Sending -> getString(R.string.control_command_sending)
            CommandUi.Done -> getString(R.string.control_command_done)
            CommandUi.MessageUnread -> getString(R.string.control_message_unread)
            CommandUi.MessageRead -> getString(R.string.control_message_read)
            CommandUi.Queued -> getString(R.string.control_command_queued)
            is CommandUi.Failed -> state.message
        }
    }

    /** [message] 가 null 이면 안내를 감춘다. */
    private fun showChildState(message: String?) {
        val b = _binding ?: return
        b.childState.visibility = if (message == null) View.GONE else View.VISIBLE
        b.childState.text = message.orEmpty()
    }

    /** Firestore 콜백은 화면이 사라진 뒤에도 한 번 더 올 수 있다. 그때는 null 을 준다. */
    private fun errorMessageOrNull(e: Exception): String? {
        _binding ?: return null
        val ctx = context ?: return null
        return errorMessage(ctx, e)
    }

    /** 아이 폰이 없으면 보낼 곳이 없다. 잠금 스위치는 가족 설정이라 그대로 둔다. */
    private fun setChildDependentButtonsEnabled(enabled: Boolean) {
        val b = _binding ?: return
        b.modeNormalButton.isEnabled = enabled
        b.modeVibrateButton.isEnabled = enabled
        b.modeSilentButton.isEnabled = enabled
        b.findButton.isEnabled = enabled
        b.findStopButton.isEnabled = enabled
        // 칩과 입력칸은 그대로 둔다. 아이 폰이 아직 안 붙었어도 부모가 문장을 미리
        // 써 두는 것은 막을 이유가 없다 — 보낼 수 없는 것은 '보내기' 하나뿐이다.
        b.messageSendButton.isEnabled = enabled
        // 시각 고르기와 이름 적기는 그대로 둔다(메시지 입력칸과 같은 판단) — 아이 폰이
        // 아직 안 붙었어도 부모가 미리 정해 두는 것을 막을 이유가 없다. 보낼 수 없는
        // 것은 맞추기·끄기 둘뿐이다.
        b.alarmSetButton.isEnabled = enabled
        b.alarmCancelButton.isEnabled = enabled
        if (!enabled) showChildState(getString(R.string.map_no_child))
    }

    override fun onDestroyView() {
        // 리스너 넷과 코루틴 셋을 전부 끊는다. viewLifecycleOwner 스코프가 알아서
        // 취소해 주지만, 타임아웃이 뷰가 사라진 뒤에 깨어나 binding 을 만지면 그대로
        // 크래시라 여기서 명시적으로도 끊는다(그리고 모든 그리기 함수는 _binding 이
        // null 이면 조용히 돌아간다).
        joinedListener?.remove()
        joinedListener = null
        statusJob?.cancel()
        statusJob = null
        settingsListener?.remove()
        settingsListener = null
        commandListener?.remove()
        commandListener = null
        timeoutJob?.cancel()
        timeoutJob = null
        findResetJob?.cancel()
        findResetJob = null
        lockSaveJob?.cancel()
        lockSaveJob = null
        _binding = null
        super.onDestroyView()
    }

    private companion object {
        /** child/RingerMode 와 같은 값이어야 한다(위 클래스 주석 참고). */
        const val MODE_NORMAL = "normal"
        const val MODE_VIBRATE = "vibrate"
        const val MODE_SILENT = "silent"

        /** child/CommandHandler 가 SET_RINGER 에서 읽는 페이로드 키. */
        const val PAYLOAD_MODE = "mode"

        /** child/CommandHandler 가 소리 모드 변경이 거부됐을 때 적는 코드. */
        const val ERROR_RINGER_DENIED = "ringer_denied"

        const val TAG = "ControlFragment"

        const val COMMAND_TIMEOUT_MILLIS = 60_000L

        /**
         * 명령 **발행**(서버 확인)을 기다리는 시간. 위 60초와 다른 것이다 — 저건
         * "애기폰이 대답하기까지", 이건 "이 쓰기가 서버에 닿기까지"다.
         *
         * 값은 [ScheduleFragment] 의 쓰기 제한시간과 같다. 같은 사실("오프라인이면
         * 서버 확인이 영영 안 온다")을 막는 같은 장치라 다른 숫자를 쓸 이유가 없다.
         */
        const val SEND_TIMEOUT_MILLIS = 15_000L

        /** child/FindPhoneController 의 5분 자동 정지와 같은 값(설계서 §4.5). */
        const val FIND_AUTO_STOP_MILLIS = 5 * 60 * 1000L

        const val KEY_FIND_STARTED_AT = "find_started_at"

        /** 아침 7시. 이 통로가 실제로 쓰이는 자리("아침에 깨워줘")에 가장 가깝다. */
        const val DEFAULT_ALARM_MINUTE = 7 * 60

        const val KEY_ALARM_MINUTE = "alarm_minute"
        const val TAG_PICK_ALARM = "pick_alarm_time"
    }
}
