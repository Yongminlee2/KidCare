import FirebaseAuth
import FirebaseFirestore
import Foundation

/// "이 아이폰을 가족에서 빼기"의 서버 쪽(7단계 계획서 판정 기록 8).
///
/// **안드로이드에는 대응물이 없다.** App Store 가이드라인 5.1.1(v)(계정을 만드는 앱은 앱 안에서 삭제도 제공)
/// 때문에 iOS 에만 둔다. 규칙은 고치지 않는다 — 보호자는 자기 멤버 문서를 지울 수 있다
/// (firestore.rules members `allow delete: if memberOf(familyId) && roleIn(familyId) == 'guardian'`).
///
/// 지우지 못하는 것(아이가 쓴 기록, 가족 공용 예약·장소, 가족 문서, 내가 만든 초대 코드와 명령)은 규칙과
/// 필드 구조 때문이다. 목록과 이유는 판정 기록 8 에 있고, 확인 문구와 처리방침에 그대로 적는다.
enum LeaveFamilyRepository {

    enum AuthOutcome: Equatable, Sendable {
        /// 익명 계정까지 서버에서 지웠다.
        case deleted
        /// 서버가 계정 삭제를 받지 않아 로그아웃만 했다. 남은 익명 계정에는 uid 와 만든 시각뿐이다.
        case signedOutOnly
    }

    /// `families/{familyId}/members/{uid}` 를 지운다. **이미 빠진 상태면 성공으로 본다.**
    ///
    /// 앞 시도가 시간 초과로 끝났는데 서버에는 닿았다면, 다시 지우려는 지금은 `memberOf` 가 거짓이라
    /// PERMISSION_DENIED 가 난다. 그것을 "아직 멤버인데 거부됐다"와 가르려고 가족 문서를 서버에서 읽는다.
    /// `families` get 도 `memberOf` 라서, 여기서도 거부되면 정말 빠진 것이다. 읽히면 아직 멤버이므로 원래 오류를
    /// 던진다 — 삼키면 가족에는 남았는데 이 폰은 빠졌다고 믿게 된다. 읽기가 다른 이유(오프라인 등)로 실패하면 그 오류를 던진다.
    ///
    /// 한계: 이 계정이 **처음부터** 그 가족의 멤버가 아니었어도 같은 판정(성공)이 난다. 부르는 곳(`LeaveFamilyModel`)은
    /// 늘 이 폰의 `RoleStore.familyId` 와 로그인 uid 를 넘기므로 그 경우가 생기지 않는다.
    ///
    /// `db` 는 테스트가 연결을 끊은 따로 앱을 넘기려고 받는다. 앱은 늘 기본값이다.
    static func removeMember(familyId: String, uid: String, db: Firestore = Firestore.firestore()) async throws {
        let family = db.collection("families").document(familyId)
        do {
            try await deleteConfirmedByServer(family.collection("members").document(uid), db: db)
        } catch {
            guard isPermissionDenied(error) else { throw error }
            do {
                _ = try await family.getDocument(source: .server)
            } catch let readError {
                if isPermissionDenied(readError) { return }
                throw readError
            }
            throw error
        }
    }

    /// 서버가 받았을 때만 끝나는 삭제. **보통 `delete()` 를 쓰지 않는다.**
    ///
    /// `delete()` 는 오프라인이면 쓰기 대기열에 들어가 연결되는 순간 올라간다. 앱의 디스크 캐시에 남으므로 앱을 껐다 켜도
    /// 올라간다. 그러면 "15초 안에 확인이 없어 아무것도 지우지 않았어요"라고 알린 뒤 몇 시간 뒤에 멤버 문서가 몰래 사라지고,
    /// 이 폰은 가족에 남았다고 믿은 채 권한 오류만 보게 된다. 트랜잭션은 대기열에 남지 않고 서버에 곧장 커밋한다
    /// (FIRFirestore.h: "Unlike transactions, write batches are persisted offline"). 규칙 판정은 같은 members delete 다.
    ///
    /// `maxAttempts = 1`: 기본 5회는 서버에 닿지 못한 오류를 물러났다 다시 시도한다. 그 재시도가 시간 초과를 알린 **뒤에**
    /// 커밋될 수 있으므로 한 번만 시도한다. 한 번의 커밋 요청이 서버에 닿고 응답만 잃은 경우는 남는다 — 그때는 다시 누르면
    /// 위의 "이미 빠짐" 판정이 성공으로 마무리한다.
    private static func deleteConfirmedByServer(_ ref: DocumentReference, db: Firestore) async throws {
        let options = TransactionOptions()
        options.maxAttempts = 1
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.runTransaction(with: options, block: { transaction, _ in
                transaction.deleteDocument(ref)
                return nil
            }, completion: { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// 익명 계정을 지운다. 어떤 이유로든 못 지우면 로그아웃만 하고 그렇다고 돌려준다.
    ///
    /// 던지지 않는 이유: 이 함수는 멤버 문서를 지운 **뒤에만** 불린다. 여기서 실패를 화면에 올리면 "가족에서는 빠졌는데
    /// 실패했다"는 모순된 안내가 된다. 익명 계정은 로그아웃하면 다시 들어갈 길이 없으므로 로그아웃이 곧 이 폰에서의 끝이다.
    /// 대신 결과를 돌려주고, 첫 화면이 "계정은 로그아웃만 했다"고 있는 그대로 알린다(`LeaveFamilyModel.끝_문구`).
    /// 운영 Auth 가 오래된 익명 로그인에 `requiresRecentLogin` 을 내는지는 확인하지 못했다(판정 기록 8) — 두 갈래 모두 여기서 끝난다.
    static func deleteAuthUser() async -> AuthOutcome {
        guard let user = Auth.auth().currentUser else { return .signedOutOnly }
        do {
            try await user.delete()
            return .deleted
        } catch {
            try? Auth.auth().signOut()
            return .signedOutOnly
        }
    }

    static func isPermissionDenied(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == FirestoreErrorDomain && ns.code == FirestoreErrorCode.permissionDenied.rawValue
    }
}
