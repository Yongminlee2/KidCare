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
 */
internal enum class ListLoad {

    /**
     * 첫 스냅샷을 아직 못 받았다. **"없어요"도 오류도 아직 사실이 아니다** — 이
     * 상태가 따로 있어야 하는 이유가 그것이다. 여기서 빈 목록 문구를 띄우면 장소를
     * 열 개 정해 둔 부모도 탭을 열 때마다 "아직 정해둔 장소가 없어요"가 한 번씩
     * 번쩍이는 것을 본다.
     */
    LOADING,

    /** 스냅샷을 받았다. 비어 있다면 **정말로** 비어 있는 것이다. */
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
internal fun TextView.renderEmptyState(
    state: ListLoad,
    isEmpty: Boolean,
    @StringRes emptyText: Int,
) {
    visibility = if (isEmpty && state != ListLoad.FAILED) View.VISIBLE else View.GONE
    setText(if (state == ListLoad.LOADED) emptyText else R.string.list_loading)
}
