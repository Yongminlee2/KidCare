import Foundation
import SwiftUI

/// 앱을 열었을 때 어디로 갈지 정한다. 안드로이드 `RouterActivity` 와 같은 자리다.
///
/// 판단 재료는 저장소에 있는 것뿐이다 — 네트워크를 기다리지 않는다. 여기서 서버를
/// 물어보면 통신이 느린 날 첫 화면이 통째로 비어 있게 된다.
///
/// **`showMain` 은 딱 한 번, `init` 에서만 정한다.** 처음엔 `store.familyId` 를 body
/// 안에서 그대로 읽어 분기했는데, `@Observable` 이 그 읽기를 추적하는 바람에
/// `InviteCodeView` 가 `RoleStore.shared.familyId` 를 쓰는 순간(코드를 아직 받기도
/// 전에) `RouterView` 가 다시 그려져 `RoleSelectView`·`InviteCodeView` 를 통째로
/// 걷어내고 `GuardianRootView` 로 바꿔치기했다 — 보호자가 코드를 읽기도 전에 지도로
/// 튕겨나가 아무도 그 코드를 못 봤다(1차 리뷰 CRITICAL). 안드로이드
/// `RouterActivity.destination()` 이 앱을 켤 때 딱 한 번만 도는 것과 같은 이유로,
/// 여기서도 판단은 시작할 때 한 번뿐이어야 한다 — 그 이후로는 온보딩 화면이
/// `onGuardianReady()` 를 불러야만(합류 성공, 또는 코드 화면에서 아이가 들어옴)
/// 넘어간다.
struct RouterView: View {

    @State private var store = RoleStore.shared
    @State private var showMain: Bool

    /// I4(리뷰): `KidCareTests` 는 `KidCare.app` 을 호스트로 띄워서 도는 XcodeGen
    /// 설정이라(`project.yml` 주석), 테스트 프로세스에서도 이 뷰가 실제로 그려진다.
    /// 시뮬레이터에 남은 진짜 `RoleStore` 값(수동 확인이 남긴 것, 또는 `-only-testing`
    /// 이전 실행의 흔적)이 있으면 `showMain` 이 곧장 `GuardianRootView` 로 가고, 그
    /// `.task` 가 `FamilyRepository.fetchChildStatus` → `Firestore.firestore()` 를
    /// 부른다 — 그런데 `FirebaseBootstrap.configureForApp()` 은 테스트 프로세스에서
    /// 일부러 아무 것도 안 한다(그 함수 주석) — `EmulatorHarness.start()` 가 아직
    /// 아무 테스트도 부르지 않았으니 `FirebaseApp` 은 통째로 미구성 상태고, 그
    /// 호출은 `FIRIllegalStateException` 으로 곧장 죽는다. 이 죽음은 테스트 **바디가
    /// 실행되기도 전에** 앱 프로세스 자체를 끝장내서, 실제 앱은 멀쩡한데도 스위트
    /// 전체가 시뮬레이터에 우연히 남아 있던 상태에 따라 죽었다 살았다 한다. 그래서
    /// 테스트 프로세스에서는 데이터를 읽는 화면으로 아예 가지 않는다 — 실제 화면
    /// 검증은 각 뷰모델·리포지토리 테스트가 이미 UI 없이 하고 있다.
    private let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        let store = RoleStore.shared
        // 아이도 본 화면으로 간다 — 이 갈래가 없으면 아이로 페어링한 폰이 앱을 다시 열 때마다
        // 역할 선택 화면으로 돌아간다(수집은 `KidCareApp.init()` 이 이미 시작해 둔 채로).
        _showMain = State(initialValue: (store.role == .guardian || store.role == .child)
                          && store.familyId != nil)
    }

    /// 가족에서 빠진 뒤 첫 화면에 한 번 띄울 결과 글(7단계 판정 기록 8). 빼기 모델은 본 화면과 함께 사라지므로 여기서 받는다.
    @State private var 빠진_결과: String?

    /// 3단계 Task 3 이 `#if DEBUG` `-childSim` 갈래를 지웠다(1단계 판정 기록 9 가 예고한 자리다).
    /// 이제 아이 파이프라인으로 가는 길은 **저장된 역할 하나뿐**이고, 조립은 화면이 아니라
    /// `KidCareApp.init()` → `ChildSession` 이 한다. 시뮬레이터 확인에 남긴 문은
    /// `-childBattery <0~100>`(`ChildSession.injectedBattery`) 하나로, 값 하나를 주입할 뿐
    /// 파이프라인을 따로 만들지 않는다.
    var body: some View {
        Group {
            if isRunningTests {
                Color.clear
            } else if store.role == .child, store.familyId != nil {
                // 아이는 **아이 화면만** 본다 — 보호자 탭이 하나도 안 보인다(설계서 §2-2).
                // 수집 파이프라인은 여기서 만들지 않는다. `KidCareApp.init()` 이 이미 만들었다 —
                // 백그라운드로 되살아난 실행에는 이 body 가 안 돌 수 있기 때문이다(판정 기록 1).
                ChildRootView()
            } else if showMain, let familyId = store.familyId {
                GuardianHomeView(familyId: familyId, onLeft: { outcome in
                    빠진_결과 = outcome.map(LeaveFamilyModel.끝_문구)
                })
                    // 가족이 바뀌면 선택기까지 새로 만든다. 아이가 바뀌면 GuardianHomeView 안에서 탭만 새로 만든다
                    // (통합 검토 M1 의 .id(familyId+childUid) 를 두 겹으로 나눴다 — 6단계 판정 기록 7).
                    .id(familyId)
            } else {
                RoleSelectView(
                    onGuardianReady: { showMain = true },
                    // 아이로 막 페어링을 끝낸 순간이다. 화면은 저장소(`store.role`)가 바뀐 것을
                    // 이 body 가 읽어 저절로 넘어가지만, **수집은 저절로 시작하지 않는다** —
                    // `KidCareApp.init()` 은 앱이 뜰 때 한 번 돌고 그때는 역할이 없었다.
                    // 그래서 같은 문을 한 번 더 두드린다(조립하는 자리는 여전히 하나다).
                    onChildReady: { ChildSession.shared.startIfChild() }
                )
            }
        }
        // 가족에서 빠지면 familyId 가 nil 이 된다. showMain 을 되돌려 두지 않으면, 다시 합류하는 도중 InviteCodeView 가
        // familyId 를 쓰는 순간 코드를 보기도 전에 본 화면으로 튕긴다 — 위 머리 주석의 1차 리뷰 CRITICAL 과 같은 사고다.
        .onChange(of: store.familyId) { _, newValue in
            if newValue == nil { showMain = false }
        }
        .alert(
            Text("leave_family_done_title"),
            isPresented: Binding(get: { 빠진_결과 != nil }, set: { if !$0 { 빠진_결과 = nil } })
        ) {
            Button(role: .cancel) { 빠진_결과 = nil } label: { Text("ios_leave_family_done_ok") }
        } message: {
            Text(verbatim: 빠진_결과 ?? "")
        }
    }
}
