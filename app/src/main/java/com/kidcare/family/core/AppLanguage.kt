package com.kidcare.family.core

import java.util.Locale

/**
 * 앱이 보여 줄 수 있는 언어와, 지금 어느 것을 쓸지 정하는 규칙.
 *
 * `i18n/languages.json`(공용 저장소의 정본표)과 같은 목록이다. 한쪽만 고치면
 * 어긋나니 언어를 더하거나 뺄 때는 둘 다 고친다.
 *
 * **[resSuffix] 가 [tag] 와 따로 있는 이유:** 리소스 디렉터리 이름과 표준 언어
 * 태그가 다른 언어가 있다. 인도네시아어가 대표적이다 — `res/values-in/` 인데
 * 태그는 `id` 다. 섞으면 조용히 안 잡힌다.
 */
enum class AppLanguage(
    /** 표준 태그(BCP-47). AppCompatDelegate 와 저장에 쓴다. */
    val tag: String,
    /** 목록에 보여 줄 이름. **그 언어 글자로 적고 절대 번역하지 않는다.** */
    val nativeName: String,
    /** `res/values-<이것>/` 디렉터리 이름. 빈 문자열이면 기본 `res/values/`. */
    val resSuffix: String,
) {
    ENGLISH("en", "English", ""),
    KOREAN("ko", "한국어", "ko"),
    JAPANESE("ja", "日本語", "ja"),
    CHINESE_SIMPLIFIED("zh-Hans", "简体中文", "zh"),
    CHINESE_TRADITIONAL("zh-Hant", "繁體中文", "zh-rTW"),
    SPANISH("es", "Español", "es"),
    PORTUGUESE("pt", "Português", "pt"),
    GERMAN("de", "Deutsch", "de"),
    FRENCH("fr", "Français", "fr"),
    ITALIAN("it", "Italiano", "it"),
    RUSSIAN("ru", "Русский", "ru"),
    INDONESIAN("id", "Bahasa Indonesia", "in"),
    VIETNAMESE("vi", "Tiếng Việt", "vi"),
    THAI("th", "ไทย", "th"),
    ;

    companion object {
        val selectable: List<AppLanguage> = entries.toList()

        /**
         * 태그 문자열에서 언어를 찾는다.
         *
         * 중국어를 먼저 갈라내는 것이 핵심이다. 언어 코드(`zh`)만 보면 **번체권이
         * 전부 간체로 떨어진다** — 대만·홍콩 사용자에게는 깨져 보인다.
         */
        fun fromTag(tag: String?): AppLanguage? {
            if (tag.isNullOrBlank()) return null
            val normalized = tag.replace('_', '-').lowercase(Locale.ROOT)
            if (normalized.startsWith("zh")) {
                val traditional = normalized.contains("hant") ||
                    normalized.endsWith("-tw") || normalized.endsWith("-hk") ||
                    normalized.endsWith("-mo")
                return if (traditional) CHINESE_TRADITIONAL else CHINESE_SIMPLIFIED
            }
            val language = normalized.substringBefore('-')
            return entries.firstOrNull {
                it.tag.substringBefore('-').equals(language, ignoreCase = true)
            }
        }
    }
}
