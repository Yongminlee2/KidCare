package com.kidcare.family.core

import android.app.Activity
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import com.kidcare.family.R

/**
 * 언어 선택 대화상자. 화면 위쪽 지구본 버튼에 물려 쓴다.
 *
 * [AppCompatDelegate.setApplicationLocales] 는 androidx.appcompat 1.6부터
 * **API 33 미만에서도** 앱별 언어를 스스로 저장·적용한다. 고르면 열려 있는
 * 액티비티가 알아서 다시 그려지므로 `recreate()` 를 부를 필요가 없다.
 *
 * 기기 언어를 그대로 따르는 것이 기본이라 목록 맨 위에 '기기 설정 따르기'를 둔다 —
 * 빈 목록을 넣으면 안드로이드가 시스템 로케일로 되돌린다.
 */
object LanguagePicker {

    fun show(activity: Activity) {
        val labels = arrayOf<CharSequence>(activity.getString(R.string.language_follow_system)) +
            AppLanguage.selectable.map { it.nativeName }

        AlertDialog.Builder(activity)
            .setTitle(R.string.language_picker_title)
            .setItems(labels) { _, index ->
                apply(if (index == 0) null else AppLanguage.selectable[index - 1])
            }
            .show()
    }

    /** [language] 가 null 이면 기기 설정을 따른다. */
    fun apply(language: AppLanguage?) {
        AppCompatDelegate.setApplicationLocales(
            if (language == null) {
                LocaleListCompat.getEmptyLocaleList()
            } else {
                LocaleListCompat.forLanguageTags(language.tag)
            },
        )
    }
}
