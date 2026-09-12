import Testing

/// 테스트 대상과 러너가 실제로 붙어 있는지만 본다. 안드로이드 `SmokeTest` 와 같은 자리다 —
/// 이게 빨간 날은 코드가 아니라 빌드 설정이 깨진 날이다.
struct SmokeTests {
    @Test("테스트 러너가 돈다")
    func 러너가_돈다() {
        #expect(1 + 1 == 2)
    }
}
