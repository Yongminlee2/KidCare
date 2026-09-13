import FirebaseFirestore
import Foundation
import Observation

/// 본 화면에서 여는 초대 한 판 — 기준 멤버 읽기 → 번호 발급 → 새 멤버 감시. 정본은 `GuardianPairingActivity`
/// 의 초대 갈래(`EXTRA_INVITE_ROLE`·`EXTRA_RETURN_TO_MAIN`, :64-70). 가족을 새로 만드는 갈래는 1단계
/// `NewFamilySession` 이 옮겼다.
///
/// **이 세션은 화면이 아니라 `ChildSelectorModel` 이 소유한다.** 커버·push 의 내용 뷰는 SwiftUI 가 다시 마운트할
/// 수 있어서, 일을 뷰가 들고 있으면 한 번의 초대에 번호가 두 번 발급된다(`NewFamilySession` 타입 주석의 실측).
///
/// 페어링의 끝은 "번호를 보여줬다"가 아니라 "새 멤버가 실제로 들어왔다"다(:31-34). 들어오면 `onJoined` 를
/// 딱 한 번 부른다.
///
/// ## 정리 뒤에는 아무것도 만지지 않는다
/// `닫힘` 규율은 `AlertViewModel`·`PlaceViewModel` 과 같다. 발급은 취소에 응하지 않는다(`firstToFinish` 주석) —
/// `정리한다()` 가 작업을 취소해도 매달린 발급은 나중에 끝나 돌아온다. 그래서 await 뒤·catch 안·리스너 콜백마다
/// `닫힘` 을 다시 본다. `작업_세대` 는 "지금 작업이 낸 결과인가"를 가른다 — 처음 발급과 새 번호가 겹치지 않게
/// `작업 == nil` 이 막고 있지만, 결과를 적는 자리는 그 가정에 기대지 않는다.
@MainActor
@Observable
final class InviteSession {

    typealias Create = @Sendable (_ familyId: String, _ role: MemberRole, _ previousCode: String?) async throws -> InviteCodeInfo
    typealias Fetch = @Sendable (_ familyId: String) async throws -> [FamilyMember]
    typealias Observe = @Sendable (
        _ familyId: String, _ onChange: @escaping ([FamilyMember]) -> Void, _ onError: @escaping (Error) -> Void
    ) -> ListenerRegistration

    /// `SETUP_TIMEOUT_MILLIS = 20_000L`(:251). 오프라인이면 쓰기가 서버 확인 없이 걸려 무한 스피너가 된다(:112-113).
    nonisolated static let setupTimeoutMillis: Int64 = 20_000

    let role: MemberRole
    private(set) var 코드: String?
    /// 발급 순간의 남은 분. 실시간 카운트다운이 아니다(:196, activity_guardian_pairing.xml:61-63).
    private(set) var 만료_분: Int64?
    private(set) var 진행중 = true
    /// `hint_text` 자리 — 역할별 안내, 또는 실패 문구(:131-132, :163-168).
    private(set) var 안내: String
    /// 버튼 하나가 '새 번호 받기'와 '다시 시도'를 겸한다(:74-79, :166).
    private(set) var 버튼_문구 = String(localized: "pairing_new_code_button")
    private(set) var 버튼_활성 = false

    private let familyId: String
    private let create: Create
    private let fetch: Fetch
    private let observe: Observe
    private let deviceNow: @Sendable () -> Int64
    private let sleep: @Sendable (Int64) async -> Void
    private let onJoined: @MainActor (FamilyMember) -> Void

    /// 발급 전에 이미 있던 멤버. 이 밖의 같은 역할 멤버가 "새로 들어온 사람"이다(:121, :126-127).
    @ObservationIgnored private var 기준_멤버: Set<String> = []
    @ObservationIgnored private var listener: ListenerRegistration?
    @ObservationIgnored private var 작업: Task<Void, Never>?
    @ObservationIgnored private var 작업_세대 = 0
    /// `정리한다()` 뒤로는 발급도 감시도 상태 변경도 새로 만들지 않는다. 되돌려지지 않는다.
    @ObservationIgnored private var 닫힘 = false
    /// 스냅샷이 캐시→서버로 두 번 와도 한 번만 넘어간다(`navigated`, :46-50).
    @ObservationIgnored private var 넘어감 = false

    private struct 준비됨: Sendable {
        let baseline: Set<String>
        let info: InviteCodeInfo
    }

    init(
        familyId: String,
        role: MemberRole,
        create: @escaping Create = FamilyRepository.createInvite,
        fetch: @escaping Fetch = FamilyRepository.fetchMembers,
        observe: @escaping Observe = FamilyRepository.observeMembers,
        deviceNow: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        sleep: @escaping @Sendable (Int64) async -> Void = { millis in
            try? await Task.sleep(nanoseconds: UInt64(millis) * 1_000_000)
        },
        onJoined: @escaping @MainActor (FamilyMember) -> Void
    ) {
        self.familyId = familyId
        self.role = role
        self.create = create
        self.fetch = fetch
        self.observe = observe
        self.deviceNow = deviceNow
        self.sleep = sleep
        self.onJoined = onJoined
        안내 = Self.역할_안내(role)
    }

    /// 제목(:232-236).
    var 제목: String {
        role == .guardian
            ? String(localized: "pairing_guardian_invite_guardian_title")
            : String(localized: "pairing_guardian_title")
    }

    var 만료_문구: String? {
        만료_분.map { String(format: String(localized: "pairing_code_expiry_format"), Int($0)) }
    }

    /// 화면이 보일 때 부른다(`onCreate` → `startPairing`, :103). 이미 번호가 있거나 진행 중이면 아무 일도 하지 않는다 —
    /// 커버가 다시 마운트돼 `.task` 가 또 불려도 번호는 한 번만 발급된다.
    func 시작한다() {
        guard !닫힘, 작업 == nil, 코드 == nil else { return }
        listener?.remove()
        listener = nil
        버튼_활성 = false
        버튼_문구 = String(localized: "pairing_new_code_button")
        진행중 = true
        안내 = Self.역할_안내(role)
        작업_세대 += 1
        let 세대 = 작업_세대
        let familyId = familyId, role = role, create = create, fetch = fetch, sleep = sleep
        작업 = Task { [weak self] in
            do {
                let 결과 = try await firstToFinish(timeoutMillis: Self.setupTimeoutMillis, sleep: sleep) {
                    let baseline = Set(try await fetch(familyId).map(\.uid))
                    let info = try await create(familyId, role, nil)
                    return 준비됨(baseline: baseline, info: info)
                }
                // 매달렸던 발급이 정리 뒤에 돌아와도 사라진 화면의 번호를 채우거나 감시를 붙이지 않는다.
                guard let self, !self.닫힘, self.작업_세대 == 세대 else { return }
                if let 결과 {
                    self.기준_멤버 = 결과.baseline
                    self.번호를_보인다(결과.info)
                    self.듣는다()
                } else {
                    self.실패를_보인다(String(localized: "pairing_offline"))   // withTimeout (:133-146)
                }
            } catch is CancellationError {
                // 정리한다() 가 취소했다 — 실패로 적지 않는다(:148-151).
            } catch {
                guard let self, !self.닫힘, self.작업_세대 == 세대 else { return }
                self.실패를_보인다(String(format: String(localized: "pairing_failed"), errorMessage(error)))
            }
            if let self, self.작업_세대 == 세대 { self.작업 = nil }
        }
    }

    /// 버튼(:77-79). 번호가 아직 없으면 처음부터, 있으면 새 번호.
    func 버튼을_눌렀다() {
        if 코드 == nil { 시작한다() } else { 새_번호를_받는다() }
    }

    /// 화면이 사라진다(`onDestroy`, :241-244).
    func 정리한다() {
        닫힘 = true
        listener?.remove()
        listener = nil
        작업?.cancel()
        작업 = nil
    }

    /// "새 번호 받기": 만료 전이어도 새로 발급해 이전 코드를 죽인다(:170-194). 기준 멤버와 감시는 그대로다.
    private func 새_번호를_받는다() {
        guard !닫힘, 작업 == nil else { return }
        버튼_활성 = false
        진행중 = true
        작업_세대 += 1
        let 세대 = 작업_세대
        let familyId = familyId, role = role, create = create, previous = 코드, sleep = sleep
        작업 = Task { [weak self] in
            do {
                let info = try await firstToFinish(timeoutMillis: Self.setupTimeoutMillis, sleep: sleep) {
                    try await create(familyId, role, previous)
                }
                if let self, !self.닫힘, self.작업_세대 == 세대 {
                    if let info {
                        self.번호를_보인다(info)
                    } else {
                        self.진행중 = false
                        self.안내 = String(localized: "pairing_offline")
                    }
                }
            } catch is CancellationError {
            } catch {
                if let self, !self.닫힘, self.작업_세대 == 세대 {
                    self.진행중 = false
                    self.안내 = String(format: String(localized: "pairing_failed"), errorMessage(error))
                }
            }
            guard let self, self.작업_세대 == 세대 else { return }
            if !self.닫힘 { self.버튼_활성 = true }   // finally (:192-194)
            self.작업 = nil
        }
    }

    /// `showCode`(:197-215). 번호가 떴으면 기다리는 상태라 진행 표시를 끈다 — 아이가 언제 폰을 들지는 모른다.
    private func 번호를_보인다(_ info: InviteCodeInfo) {
        코드 = info.code
        버튼_문구 = String(localized: "pairing_new_code_button")
        만료_분 = max(1, (info.expiresAt - deviceNow() + 59_999) / 60_000)
        안내 = Self.역할_안내(role)
        버튼_활성 = true
        진행중 = false
    }

    /// `showSetupFailure`(:163-168). 같은 화면에서 다시 시도할 수 있게 버튼을 켠다.
    private func 실패를_보인다(_ message: String) {
        진행중 = false
        안내 = message
        버튼_문구 = String(localized: "router_retry")
        버튼_활성 = true
    }

    private func 듣는다() {
        guard !닫힘, listener == nil else { return }
        listener = observe(familyId, { [weak self] members in
            Task { @MainActor in self?.멤버가_바뀌었다(members) }
        }, { [weak self] error in
            Task { @MainActor in self?.감시가_실패했다(error) }
        })
    }

    /// 리스너 콜백은 `remove()` 직전에 이미 대기열에 올라 있을 수 있다 — 그래서 첫 줄에서 닫힘을 본다.
    private func 멤버가_바뀌었다(_ members: [FamilyMember]) {
        guard !닫힘, !넘어감 else { return }
        guard let joined = members.first(where: { $0.role == role.rawValue && !기준_멤버.contains($0.uid) }) else { return }
        넘어감 = true
        listener?.remove()
        listener = nil
        onJoined(joined)
    }

    private func 감시가_실패했다(_ error: Error) {
        guard !닫힘 else { return }
        // 번호는 그대로 둔다 — 아직 유효한 번호를 오류로 덮지 않는다(:131-133 은 hint 자리만 바꾼다).
        안내 = String(format: String(localized: "pairing_failed"), errorMessage(error))
    }

    private static func 역할_안내(_ role: MemberRole) -> String {
        role == .guardian
            ? String(localized: "pairing_guardian_invite_guardian_hint")
            : String(localized: "pairing_guardian_hint")
    }
}
