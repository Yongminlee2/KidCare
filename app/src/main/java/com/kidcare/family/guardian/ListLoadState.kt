package com.kidcare.family.guardian

import android.view.View
import android.widget.TextView
import androidx.annotation.StringRes
import com.kidcare.family.R

/**
 * 목록 화면 셋(알림·장소·예약)이 공유하는 "빈 목록" 판정.
 *
 * ## 왜 한곳에 모았나
 *
 * 셋 다 `list.isEmpty()` **하나만** 보고 빈 목록 문구를 띄우고 있었다. 그러면 못
 * 불러온 화면과 정말 비어 있는 화면이 **같은 말을 한다.** 규칙을 아직 게시하지 않았을
 * 때(`docs/setup.md` "5단계 규칙 재게시")가 그 상황인데, 그때 화면에는 목록 위에
 * 오류 한 줄과 한가운데에 "아직 온 알림이 없어요"가 **같은 크기로 동시에** 떴다.
 * 부모는 가운데 큰 글씨를 읽고 "조용한 하루"로 이해하는데 진실은 "아무것도 못
 * 읽었다"다 — 이 앱이 제일 두려워하는 실패가 정확히 그 모양이다.
 *
 * 세 화면에 각각 고치면 다음 목록 화면이 또 같은 모양으로 태어난다. 판정을 여기
 * 한 줄로 모아두면 새 화면은 이 함수를 부르거나 안 부르거나 둘 중 하나다.
 *
 * ## 오프라인은 **네 번째 상태가 아니다**
 *
 * 6단계에서 확인하고 내린 결론이라 여기 적어둔다(중복 구현 방지). 오프라인에서 오는
 * 스냅샷은 캐시본이다(`metadata.isFromCache == true`). 새 상태를 하나 더 만들지 않고
 * [LOADING] 으로 접는데, 이유가 둘이다.
 *
 * 1. **뜻이 정확히 같다.** [LOADING] 은 "서버의 답을 아직 못 받았다"이고, 캐시본이
 *    바로 그 상태다. 캐시에 든 것은 그대로 목록에 그려지므로 부모가 보는 내용은
 *    줄지 않고, 다만 **"없어요"라고 단언하지 않는다.**
 * 2. **따로 두면 온라인에서 거짓말이 하나 생긴다.** 리스너를 걸면 온라인에서도
 *    캐시본이 한 번 먼저 오고 서버본이 곧 따라온다. "인터넷이 안 돼요" 같은 문구를
 *    이 상태에 걸어 두면 통신이 멀쩡한 폰에서 탭을 열 때마다 그 문구가 번쩍인다 —
 *    [LOADING] 이 애초에 막으려던 그 번쩍임이 문구만 바뀌어 돌아온다.
 *
 * 대가는 하나다: 오프라인이 길어지면 빈 화면이 "불러오는 중이에요…"에서 안 벗어난다.
 * 그건 거짓말이 아니다 — Firestore 는 정말로 계속 다시 시도하는 중이고, 연결되는
 * 순간 저절로 채워진다.
 */
internal enum class ListLoad {

    /**
     * 첫 스냅샷을 아직 못 받았다. **"없어요"도 오류도 아직 사실이 아니다** — 이
     * 상태가 따로 있어야 하는 이유가 그것이다. 여기서 빈 목록 문구를 띄우면 장소를
     * 열 개 정해 둔 부모도 탭을 열 때마다 "아직 정해둔 장소가 없어요"가 한 번씩
     * 번쩍이는 것을 본다.
     *
     * **캐시본만 받은 상태(오프라인)도 여기다** — 위 클래스 주석 참고.
     */
    LOADING,

    /**
     * **서버가 확인해 준** 스냅샷을 받았다. 비어 있다면 **정말로** 비어 있는 것이다.
     * 캐시본으로는 이 상태에 오면 안 된다(위 클래스 주석).
     */
    LOADED,

    /**
     * 못 불러왔다. 이유는 목록 위 한 줄이 이미 말하고 있으므로 빈 목록 자리는
     * 통째로 비운다.
     */
    FAILED,
}

/**
 * 빈 목록 자리의 문구를 상태에 맞춰 그린다. [emptyText] 는 **[ListLoad.LOADED] 일
 * 때만** 쓴다.
 *
 * 실패했을 때 이 자리에 오류를 대신 적지 않는 것은 일부러다. 오류 문구는 목록 위
 * 한 줄에 이미 있고, 여기에 또 적으면 같은 말이 두 번 나오거나 — 더 나쁘게 —
 * 두 문장이 서로 다른 말을 하게 된다.
 */
/**
 * 그림이 함께 있는 빈 화면. 보임/숨김은 묶음(이 뷰)이 맡고 글은 [label] 이 맡는다.
 *
 * 글만 있는 자리는 아래 [TextView] 판을 그대로 쓴다(지도 탭의 타임라인). 두 판을
 * 나눈 이유는 한쪽에 그림이 생겼다고 다른 쪽까지 묶음으로 바꿀 이유가 없어서다.
 */
internal fun View.renderEmptyState(
    label: TextView,
    state: ListLoad,
    isEmpty: Boolean,
    @StringRes emptyText: Int,
) {
    visibility = if (isEmpty && state != ListLoad.FAILED) View.VISIBLE else View.GONE
    label.setText(if (state == ListLoad.LOADED) emptyText else R.string.list_loading)
}

internal fun TextView.renderEmptyState(
    state: ListLoad,
    isEmpty: Boolean,
    @StringRes emptyText: Int,
) {
    visibility = if (isEmpty && state != ListLoad.FAILED) View.VISIBLE else View.GONE
    setText(if (state == ListLoad.LOADED) emptyText else R.string.list_loading)
}
