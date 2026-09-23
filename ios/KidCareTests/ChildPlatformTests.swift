import Foundation
import Testing
@testable import KidCare

/// 설계서 §10.1·§10.2. **이 파일이 지키는 것은 "아이폰을 잠근다"가 아니라
/// "모르는 아이를 잠그지 않는다"다** — 그쪽이 틀렸을 때의 대가가 훨씬 크기 때문이다
/// (멀쩡히 되는 안드로이드 아이의 기능이 이유 없이 사라진다).
struct ChildPlatformTests {

    @Test func 아이폰만_아이폰이다() {
        #expect(ChildPlatform.of(platform: "ios") == .iOS)
    }

    /// `Documents.swift:202` 가 없는 필드를 `""` 로 디코드한다. 지금 서버에 있는 모든
    /// 아이 문서가 이 모양이다.
    @Test func 빈_값은_안드로이드다() {
        #expect(ChildPlatform.of(platform: "") == .android)
    }

    /// 모르는 값을 아이폰으로 보면 안 된다 — 나중에 "android" 나 "web" 같은 글자가
    /// 생겨도 잠기는 쪽으로 기울면 안 된다.
    @Test func 모르는_글자도_안드로이드다() {
        #expect(ChildPlatform.of(platform: "android") == .android)
        #expect(ChildPlatform.of(platform: "IOS") == .android)   // 대소문자를 봐준다는 약속이 없다
        #expect(ChildPlatform.of(platform: "web") == .android)
    }

    /// 문서 자체가 없는 것만 `.unknown` 이다.
    @Test func 문서가_없으면_모른다() {
        #expect(ChildPlatform.of(status: nil) == .unknown)
    }

    @Test func 명령을_막는_것은_아이폰뿐이다() {
        #expect(ChildPlatform.iOS.명령을_받을_수_있나 == false)
        #expect(ChildPlatform.android.명령을_받을_수_있나 == true)
        #expect(ChildPlatform.unknown.명령을_받을_수_있나 == true)
    }

    /// **문구는 아이폰일 때만 뜬다.** 모르는 아이에게 "이 아이는 아이폰이에요"라고
    /// 말하는 것은 버튼을 끄는 것보다 더 나쁜 거짓말이다(판정 기록 2).
    @Test func 문구는_아이폰일_때만() {
        #expect(ChildPlatform.iOS.못_한다고_말할까 == true)
        #expect(ChildPlatform.android.못_한다고_말할까 == false)
        #expect(ChildPlatform.unknown.못_한다고_말할까 == false)
    }

    // MARK: - 저장소

    private func 빈_저장소(_ 이름: String = UUID().uuidString) -> ChildPlatformStore {
        ChildPlatformStore(defaults: UserDefaults(suiteName: 이름)!)
    }

    @Test func 기억이_없으면_모른다() {
        #expect(빈_저장소().platform(childUid: "c1") == .unknown)
    }

    @Test func 기억했다_꺼낸다() {
        let s = 빈_저장소()
        s.remember(childUid: "c1", platform: .iOS)
        s.remember(childUid: "c2", platform: .android)
        #expect(s.platform(childUid: "c1") == .iOS)
        #expect(s.platform(childUid: "c2") == .android)
        #expect(s.platform(childUid: "c3") == .unknown)   // 다른 아이의 기억이 새지 않는다
    }

    /// 상태 문서를 못 읽은 것은 **기억을 지우는 일이 아니다.** 네트워크가 잠깐 끊겨
    /// `nil` 이 왔다고 어제 알던 것을 잊으면, 예약 탭이 그 순간 잠금을 놓친다.
    @Test func 모름은_기억을_안_지운다() {
        let s = 빈_저장소()
        s.remember(childUid: "c1", platform: .iOS)
        s.remember(childUid: "c1", platform: .unknown)
        #expect(s.platform(childUid: "c1") == .iOS)
    }

    /// 상태 문서가 `nil` 로 와도 같다 — 읽기 실패가 기억을 지우면 안 된다.
    @Test func 문서가_nil_이면_기억을_안_지운다() {
        let s = 빈_저장소()
        s.remember(childUid: "c1", platform: .iOS)
        s.remember(childUid: "c1", status: nil)
        #expect(s.platform(childUid: "c1") == .iOS)
    }

    /// 아이가 폰을 갈아타면 덮인다.
    @Test func 바뀌면_덮는다() {
        let s = 빈_저장소()
        s.remember(childUid: "c1", platform: .iOS)
        s.remember(childUid: "c1", platform: .android)
        #expect(s.platform(childUid: "c1") == .android)
    }

    /// 상태 문서를 통째로 넘기는 길도 같은 답을 준다 — 화면이 두 길을 섞어 써도 갈리지 않는다.
    @Test func 문서로_기억시킨다() {
        let s = 빈_저장소()
        s.remember(childUid: "c1", status: ChildStatusDoc(["lat": 37.5, "lng": 127.0, "platform": "ios"]))
        #expect(s.platform(childUid: "c1") == .iOS)
    }

    /// `platform` 칸이 없는 문서(= 지금 서버에 있는 모든 문서)는 안드로이드로 기억된다.
    @Test func 칸이_없는_문서는_안드로이드로_기억된다() {
        let s = 빈_저장소()
        s.remember(childUid: "c1", status: ChildStatusDoc(["lat": 37.5, "lng": 127.0]))
        #expect(s.platform(childUid: "c1") == .android)
    }
}
