package com.kidcare.family.logic

import kotlin.random.Random

/**
 * 페어링용 6자리 초대 코드.
 *
 * 부모 폰 화면에 뜬 코드를 아이가 눈으로 읽어 자기 폰에 옮겨 적는다.
 * 그래서 0/O, 1/I/L 처럼 손글씨·화면에서 헷갈리는 글자를 알파벳에서 빼고,
 * 사용자가 그런 글자를 입력하면 조용히 교정한다.
 *
 * 안드로이드 API 에 의존하지 않는다. JVM 단위 테스트 대상.
 */
object InviteCode {

    /** 0, 1, O, I, L 을 뺀 31글자. */
    const val ALPHABET: String = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"

    const val LENGTH: Int = 6

    /** 사용자가 잘못 입력하기 쉬운 글자 → 알파벳 안의 대체 글자. */
    private val CORRECTIONS: Map<Char, Char> = mapOf(
        '0' to 'Q', 'O' to 'Q',
        '1' to 'J', 'I' to 'J', 'L' to 'J',
    )

    fun generate(random: Random = Random.Default): String =
        buildString(LENGTH) {
            repeat(LENGTH) { append(ALPHABET[random.nextInt(ALPHABET.length)]) }
        }

    /** 대문자화 → 공백·하이픈 제거 → 헷갈리는 글자 교정. */
    fun normalize(raw: String): String =
        raw.uppercase()
            .filterNot { it.isWhitespace() || it == '-' }
            .map { CORRECTIONS[it] ?: it }
            .joinToString("")

    fun isValid(raw: String): Boolean {
        val code = normalize(raw)
        return code.length == LENGTH && code.all { it in ALPHABET }
    }
}
