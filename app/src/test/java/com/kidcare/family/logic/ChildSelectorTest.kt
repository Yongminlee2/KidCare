package com.kidcare.family.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ChildSelectorTest {

    @Test fun `저장한 자녀가 있으면 목록 순서와 무관하게 유지한다`() {
        val children = listOf(
            SelectableChild("second", "둘째", 20L),
            SelectableChild("first", "첫째", 10L),
        )

        assertEquals("second", ChildSelector.select(children, "second")?.uid)
    }

    @Test fun `저장한 자녀가 사라졌으면 가장 먼저 가입한 자녀를 고른다`() {
        val children = listOf(
            SelectableChild("second", "둘째", 20L),
            SelectableChild("first", "첫째", 10L),
        )

        assertEquals("first", ChildSelector.select(children, "removed")?.uid)
    }

    @Test fun `옛 문서처럼 가입 시각이 없으면 이름과 uid로 결과가 고정된다`() {
        val children = listOf(
            SelectableChild("b", "아이", 0L),
            SelectableChild("a", "아이", 0L),
        )

        assertEquals("a", ChildSelector.select(children, null)?.uid)
    }

    @Test fun `자녀가 없으면 선택도 없다`() {
        assertNull(ChildSelector.select(emptyList(), "anything"))
    }
}
