import Foundation

/// 보호자 화면이 선택할 자녀 한 명. 서버 종류와 무관하게 uid와 표시 이름만 쓴다.
struct SelectableChild {
    let uid: String
    let displayName: String
    let joinedAt: Int64
}

/// N명의 자녀 중 현재 선택을 안정적으로 고른다.
///
/// - 저장해 둔 uid가 아직 가족에 있으면 그대로 유지한다.
/// - 삭제됐거나 첫 실행이면 가입 시각, 이름, uid 순으로 가장 앞선 자녀를 고른다.
/// - 자녀가 없으면 nil이다.
///
/// Firestore나 iOS에 의존하지 않아 자체 서버로 바꿔도 이 규칙은 그대로 쓸 수 있다.
/// 정본은 안드로이드 `logic/ChildSelector.kt` 다.
enum ChildSelector {
    static func select(children: [SelectableChild], preferredUid: String?) -> SelectableChild? {
        if let preferredUid, let kept = children.first(where: { $0.uid == preferredUid }) {
            return kept
        }
        return children.min { a, b in
            let aJoined = a.joinedAt > 0 ? a.joinedAt : Int64.max
            let bJoined = b.joinedAt > 0 ? b.joinedAt : Int64.max
            if aJoined != bJoined { return aJoined < bJoined }
            if a.displayName != b.displayName { return a.displayName < b.displayName }
            return a.uid < b.uid
        }
    }
}
