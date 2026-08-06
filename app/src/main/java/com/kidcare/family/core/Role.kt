package com.kidcare.family.core

import android.content.Context

enum class Role { GUARDIAN, CHILD }

/**
 * 이 기기가 보호자인지 자녀인지, 어느 가족에 속하는지를 기기에 저장한다.
 *
 * 페어링이 끝나면 role 과 familyId 가 함께 채워진다. 둘 중 하나라도 비어 있으면
 * 아직 페어링이 안 끝난 것으로 보고 온보딩으로 되돌린다.
 */
class RoleStore(context: Context) {

    private val prefs = context.getSharedPreferences("kidcare", Context.MODE_PRIVATE)

    var role: Role?
        get() = prefs.getString(KEY_ROLE, null)?.let { runCatching { Role.valueOf(it) }.getOrNull() }
        set(value) = prefs.edit().putString(KEY_ROLE, value?.name).apply()

    var familyId: String?
        get() = prefs.getString(KEY_FAMILY, null)
        set(value) = prefs.edit().putString(KEY_FAMILY, value).apply()

    /** 페어링이 완전히 끝났는가. */
    val isPaired: Boolean get() = role != null && familyId != null

    fun clear() = prefs.edit().clear().apply()

    private companion object {
        const val KEY_ROLE = "role"
        const val KEY_FAMILY = "family_id"
    }
}
