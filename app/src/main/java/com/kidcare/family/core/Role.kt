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

    /**
     * 보호자 화면이 현재 보고 있는 자녀. 가족에 자녀가 여러 명이면 상단 선택기에서
     * 이 값만 바꾸고 지도·관리·예약·장소 화면을 같은 자녀로 다시 연다.
     *
     * 예전 1:1 버전은 같은 값을 `child_uid` 에 저장했다. 업그레이드한 보호자 폰이
     * 기존 자녀를 잃지 않도록 새 키가 없을 때 옛 키를 읽고, 처음 쓰는 순간 두 키를
     * 함께 갱신한다.
     */
    var selectedChildUid: String?
        get() = prefs.getString(KEY_SELECTED_CHILD_UID, null)
            ?: prefs.getString(KEY_CHILD_UID, null)
        set(value) {
            prefs.edit()
                .putString(KEY_SELECTED_CHILD_UID, value)
                .putString(KEY_CHILD_UID, value)
                .apply()
        }

    /** 옛 호출부와 저장 데이터 호환용 별칭. 새 코드는 [selectedChildUid]를 쓴다. */
    var childUid: String?
        get() = selectedChildUid
        set(value) { selectedChildUid = value }

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
        const val KEY_SELECTED_CHILD_UID = "selected_child_uid"
    }
}
