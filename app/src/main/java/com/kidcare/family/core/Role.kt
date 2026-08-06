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

    // 보호자 쪽에서만 쓴다. 아이가 실제로 members 에 들어온 뒤에야 채워진다
    // (GuardianPairingActivity.goToMain). RouterActivity 가 이 값을 familyId 와
    // 함께 봐야 "코드만 만들고 아무도 안 들어온" 보호자를 GuardianMainActivity 로
    // 잘못 보내지 않는다 — isPaired 는 그 용도로 쓰지 않는다(아래 설명 참고).
    var childUid: String?
        get() = prefs.getString(KEY_CHILD_UID, null)
        set(value) = prefs.edit().putString(KEY_CHILD_UID, value).apply()

    /**
     * 페어링이 완전히 끝났는가.
     *
     * role 과 familyId 만 본다 — 자녀 쪽은 이걸로 충분하다(코드를 넣는 순간
     * familyId 가 생기고 그게 곧 페어링 완료다). 보호자 쪽은 다르다: familyId 는
     * "코드를 만들었다"는 뜻일 뿐 "아이가 들어왔다"는 뜻이 아니므로, 보호자의
     * 실제 완료 여부는 RouterActivity 가 childUid 까지 따로 확인한다. 이 프로퍼티의
     * 의미 자체는 바꾸지 않는다 — 다른 곳에서 이미 이 의미로 쓰고 있기 때문이다.
     */
    val isPaired: Boolean get() = role != null && familyId != null

    fun clear() = prefs.edit().clear().apply()

    private companion object {
        const val KEY_ROLE = "role"
        const val KEY_FAMILY = "family_id"
        const val KEY_CHILD_UID = "child_uid"
    }
}
