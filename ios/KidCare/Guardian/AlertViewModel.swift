import FirebaseFirestore
import Foundation
import Observation
import os

/// 알림 탭의 두뇌. 정본은 `AlertFragment.kt`.
///
/// ## 살구빛과 읽음 표시가 부딪히는 문제 (:34-39, 설계서 §4)
/// "안 읽은 것은 살구빛"과 "보이면 읽음으로 바꾼다"를 곧이곧대로 붙이면 색이 부모 눈에 닿기 전에 사라진다.
/// 그래서 보이는 순간의 안 읽은 ID 를 `강조` 에 따로 붙들고 그것으로 칠한다. 탭을 떠나면 비운다.
///
/// ## 읽음 표시는 `read` 하나 (:41-44)
/// 이 뷰모델은 ID 목록만 넘긴다. 필드 계약은 `EventRepository.markRead` 안에 있다.
///
/// ## 정리 뒤에는 아무것도 만지지 않는다
/// `닫힘` 규율은 `PlaceViewModel`·`ScheduleViewModel` 과 같다(5단계 통합 검토 I1·M2). 리스너 콜백은 `remove()`
/// 직전에 이미 대기열에 올라 있을 수 있고, 탭 뷰가 사라진 뒤에도 scenePhase 변화가 보임을 알려 올 수 있다.
@MainActor
@Observable
final class AlertViewModel {

    typealias Observe = @Sendable (
        _ familyId: String, _ childUid: String?,
        _ onChange: @escaping ([EventDoc], Bool) -> Void, _ onError: @escaping (Error) -> Void
    ) -> ListenerRegistration
    typealias MarkRead = @Sendable (_ familyId: String, _ ids: [String]) async throws -> Void

    /// 마지막 스냅샷. 최신순이다(:55-56).
    private(set) var events: [EventDoc] = []
    /// 세 상태를 왜 나누는지는 `ListLoad` 주석(:58-59).
    private(set) var listLoad: ListLoad = .loading
    /// 목록 위 한 줄. nil 이면 감춘다(:279-284).
    private(set) var 상태_줄: String?
    /// 이번에 보이기 시작했을 때 안 읽은 상태였던 ID 들(:61-62).
    private(set) var 강조: Set<String> = []
    /// 읽음 쓰기가 도는 중인가(`markJob?.isActive`, :64-65, :216).
    private(set) var 읽음_쓰는_중 = false

    let familyId: String
    let childUid: String?

    private let observe: Observe
    private let markRead: MarkRead
    @ObservationIgnored private var listener: ListenerRegistration?
    @ObservationIgnored private var 시작함 = false
    /// `정리한다()` 뒤로는 구독도 쓰기도 상태 변경도 새로 만들지 않는다(4단계 통합 검토 M1).
    @ObservationIgnored private var 닫힘 = false
    /// 지금 부모 눈앞에 있는가. 탭 전환과 앱 전환이 여기로 모인다(:67-68).
    @ObservationIgnored private var 보이는가 = false
    @ObservationIgnored private var 읽음_쓰기: Task<Void, Never>?

    private static let logger = Logger(subsystem: "com.kidcare.family", category: "AlertViewModel")

    init(
        familyId: String,
        childUid: String?,
        observe: @escaping Observe = EventRepository.observeEvents,
        markRead: @escaping MarkRead = EventRepository.markRead
    ) {
        self.familyId = familyId
        self.childUid = childUid
        self.observe = observe
        self.markRead = markRead
    }

    /// 빈 목록 자리의 문구. nil 이면 감춘다(`renderEmptyState`, :274-276).
    var 빈_목록_문구: String? {
        listLoad.emptyText(isEmpty: events.isEmpty, loaded: String(localized: "alert_empty"))
    }

    /// 탭을 처음 보일 때 구독한다(`onViewCreated` → `subscribe`, :116-150). 두 번째부터는 무시한다.
    /// 가족이 없는 갈래(:121-129)는 iOS 에 없다 — `GuardianRootView` 는 familyId 가 있어야 만들어진다.
    func 시작한다() {
        guard !시작함, !닫힘 else { return }
        시작함 = true
        guard let childUid else {
            // :131-137 — 구독을 시작조차 못 하지만 "불러오는 중"에 가두지 않는다.
            listLoad = .loaded
            상태_줄 = String(localized: "map_no_child")
            return
        }
        listener = observe(familyId, childUid, { [weak self] docs, fromCache in
            Task { @MainActor in self?.스냅샷을_받았다(docs, fromCache: fromCache) }
        }, { [weak self] error in
            Task { @MainActor in self?.구독이_실패했다(error) }
        })
    }

    /// 보임이 바뀌었다(`setVisible`, :189-202). 같은 값이면 아무 일도 하지 않는다.
    func 보임이_바뀌었다(_ 보인다: Bool) {
        guard !닫힘, 보이는가 != 보인다 else { return }
        보이는가 = 보인다
        if 보인다 {
            안_읽은_것을_거둔다()
        } else {
            // 다음에 열 때는 그 사이에 새로 온 것만 살구빛이어야 한다(:38-39).
            강조.removeAll()
        }
    }

    /// 화면이 사라진다(`onDestroyView`, :286-297).
    func 정리한다() {
        닫힘 = true
        보이는가 = false
        listener?.remove()
        listener = nil
        읽음_쓰기?.cancel()
        읽음_쓰기 = nil
        읽음_쓰는_중 = false
        강조.removeAll()
    }

    private func 스냅샷을_받았다(_ docs: [EventDoc], fromCache: Bool) {
        guard !닫힘 else { return }
        events = docs
        // 캐시본으로는 loaded 로 올리지 않는다 — 오프라인의 빈 목록은 "조용한 하루"가 아니다(:155-158).
        listLoad = ListLoad.after(fromCache: fromCache)
        // 보는 동안 새로 온 것도 그 자리에서 읽음이 된다(:159-161).
        if 보이는가 { 안_읽은_것을_거둔다() }
    }

    private func 구독이_실패했다(_ error: Error) {
        guard !닫힘 else { return }
        listLoad = .failed
        상태_줄 = String(format: String(localized: "alert_error_format"), errorMessage(error))
    }

    /// 지금 안 읽은 것들을 강조에 넣고 서버에 읽음으로 적는다(:204-228).
    ///
    /// 쓰기가 실패해도 화면에는 아무 말도 하지 않는다. 부모가 한 일이 아니라 화면이 혼자 한 일이고, 대가는
    /// "다음에 열면 한 번 더 시도"뿐이다. 흔적은 로그에 남긴다.
    private func 안_읽은_것을_거둔다() {
        let ids = events.filter { !$0.read }.map(\.id)
        guard !ids.isEmpty else { return }
        강조.formUnion(ids)
        guard 읽음_쓰기 == nil else { return }   // 겹쳐 나가지 않게 하나로 묶는다(:64-65, :216)
        let familyId = familyId
        let markRead = markRead
        읽음_쓰는_중 = true
        읽음_쓰기 = Task { [weak self] in
            do {
                try await markRead(familyId, ids)
            } catch is CancellationError {
                // 정리한다() 가 취소했다.
            } catch {
                Self.logger.warning("읽음 표시 실패 — 다음에 다시 시도한다: \(String(describing: error), privacy: .public)")
            }
            // await 사이에 정리됐으면 아무것도 만지지 않는다. 정리한다() 가 이미 두 값을 내렸으므로 지금은
            // 이 guard 를 빼도 보이는 차이가 없다 — 정리 쪽이 바뀌어도 늦은 완료가 상태를 되살리지 않게 둔다.
            guard let self, !self.닫힘 else { return }
            self.읽음_쓰기 = nil
            self.읽음_쓰는_중 = false
        }
    }
}
