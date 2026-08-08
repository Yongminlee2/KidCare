package com.kidcare.family.child

import android.content.Context
import android.util.Log
import com.kidcare.family.logic.Fix
import com.kidcare.family.logic.TrailCodec
import java.io.File

/**
 * 오늘 걸어온 길을 아이 폰 안에 남긴다. **Firestore 와 아무 상관이 없다.**
 *
 * 왜 필요한가: 이제 위치 점은 한 점씩 올라가지 않고 [TrailUploader] 의 메모리
 * 버퍼에 쌓였다가 하루 문서 하나로 올라간다(docs/known-issues.md 12번). 메모리에만
 * 두면 프로세스가 죽는 순간(절전 종료, OOM, 재부팅) 그날 아침부터의 기록이 통째로
 * 사라진다 — 옛 구조에서는 이미 Firestore 에 한 점씩 들어가 있어 문제가 아니었다.
 *
 * 형식은 `[TrailCodec]` 의 줄 단위 CSV 다. 첫 줄은 어느 날짜의 기록인지(dayKey),
 * 그 뒤가 점 한 개당 한 줄이다. **새 점은 파일 끝에 덧붙이기만 한다** — 30초마다
 * 하루치 전체를 다시 쓰지 않는다. Room 도, JSON 라이브러리도 안 쓴다(새 의존성
 * 금지). SharedPreferences 를 고르지 않은 이유도 같다: 값 하나를 바꿀 때마다 XML
 * 전체를 다시 쓰므로 25KB 짜리 문자열을 하루 수백 번 통째로 재기록하게 된다.
 *
 * 파일 입출력 실패는 **삼키고 로그만 남긴다.** 이 파일은 메모리 버퍼의 사본일 뿐
 * 원본이 아니다 — 여기서 예외를 던져 위치 수집 자체를 멈추면, 프로세스가 죽었을
 * 때만 쓸모 있는 보험 때문에 평소 동작을 잃는다.
 */
class TrailStore(context: Context) {

    private val file = File(context.filesDir, FILE_NAME)

    /** [load] 가 돌려주는 것. dayKey 가 오늘이 아니면 남의 날 기록이다. */
    data class Saved(val dayKey: String, val points: List<Fix>)

    /** 저장된 것이 있으면 돌려준다. 파일이 없거나 읽을 수 없으면 null. */
    fun load(): Saved? = try {
        if (!file.exists()) null else {
            val text = file.readText()
            val newline = text.indexOf('\n')
            // 헤더 한 줄만 있고 점이 하나도 없는 상태(reset 직후)도 정상이다.
            if (newline < 0) Saved(text.trim(), emptyList())
            else Saved(text.substring(0, newline).trim(), TrailCodec.decode(text.substring(newline + 1)))
        }
    } catch (e: Exception) {
        Log.w(TAG, "오늘 경로 파일을 못 읽었다 — 메모리 버퍼로만 간다", e)
        null
    }

    /** 그 날짜로 새로 시작한다(헤더만 남는다). 자정을 넘겼을 때 부른다. */
    fun reset(dayKey: String) {
        try {
            file.writeText("$dayKey\n")
        } catch (e: Exception) {
            Log.w(TAG, "오늘 경로 파일을 새로 못 만들었다", e)
        }
    }

    /** 점 한 개를 파일 끝에 덧붙인다. [reset] 이 먼저 불려 있어야 한다. */
    fun append(fix: Fix) {
        try {
            file.appendText(TrailCodec.encodeLine(fix) + "\n")
        } catch (e: Exception) {
            Log.w(TAG, "오늘 경로 파일에 점을 못 붙였다", e)
        }
    }

    private companion object {
        const val TAG = "TrailStore"
        const val FILE_NAME = "trail_today.csv"
    }
}
