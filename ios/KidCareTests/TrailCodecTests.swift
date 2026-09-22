import Foundation
import Testing
@testable import KidCare

/// 정본은 안드로이드 `app/src/test/.../TrailCodecTest.kt` 다 — `@Test` 를 하나도 빼지 않고 옮기고,
/// 설계서 §4.5 가 요구한 왕복 테스트 하나를 더했다.
struct TrailCodecTests {

    private func fix(_ at: Int64, lat: Double = 37.5665, lng: Double = 126.9780) -> Fix {
        Fix(lat: lat, lng: lng, accuracy: 12.5, at: at, speed: 1.25)
    }

    @Test("한 점을 줄로 바꿨다가 되돌리면 그대로다")
    func 한_점_왕복() {
        let original = fix(1_754_500_000_000)
        #expect(TrailCodec.decode(TrailCodec.encodeLine(original)) == [original])
    }

    @Test("encodeLine 은 자기 자신이 decode 로 되돌아온다 — 코틀린과 글자가 같을 필요는 없다")
    func 왕복() {
        // Kotlin 의 Double.toString/Float.toString 과 Swift 의 문자열 변환은 같은 값에 다른 글자를
        // 낼 수 있다(설계서 §4.5). 두 플랫폼이 같은 파일을 읽는 일은 없으므로 계약은 "글자가 같다"가
        // 아니라 "내가 쓴 것을 내가 그대로 읽는다"다. 골든 대조도 문자열이 아니라 decode 한 값으로 한다.
        let original = Fix(lat: 37.5665, lng: 126.9780, accuracy: 12.5, at: 1_700_000_000_123, speed: 1.25)
        let back = TrailCodec.decode(TrailCodec.encodeLine(original)).first
        #expect(back?.lat == original.lat)
        #expect(back?.lng == original.lng)
        #expect(back?.accuracy == original.accuracy)
        #expect(back?.speed == original.speed)
        #expect(back?.at == original.at)
    }

    @Test("여러 줄을 순서 그대로 되돌린다")
    func 여러_줄() {
        let points = [fix(100), fix(200, lat: 37.6), fix(300, lng: 127.1)]
        let text = points.map(TrailCodec.encodeLine).joined(separator: "\n")
        #expect(TrailCodec.decode(text) == points)
    }

    @Test("깨진 줄은 버리고 나머지는 살린다")
    func 깨진_줄() {
        // 파일 끝에 덧붙이는 방식이라 프로세스가 쓰기 도중 죽으면 마지막 줄이 잘린다.
        // 그 한 줄 때문에 하루치를 통째로 잃으면 안 된다.
        let good = fix(100)
        let text = TrailCodec.encodeLine(good) + "\n37.5,126.9,10.0"
        #expect(TrailCodec.decode(text) == [good])
    }

    @Test("숫자가 아닌 값이 섞인 줄도 버린다")
    func 숫자_아님() {
        let good = fix(100)
        let text = "abc,def,ghi,jkl,mno\n" + TrailCodec.encodeLine(good)
        #expect(TrailCodec.decode(text) == [good])
    }

    @Test("빈 문자열은 빈 목록이다")
    func 빈_문자열() {
        #expect(TrailCodec.decode("").isEmpty)
    }

    @Test("상한 이하면 목록을 그대로 돌려준다")
    func 상한_이하() {
        // 코틀린은 `assertSame` 으로 "새 리스트를 만들지 않는다"까지 못박는다. 스위프트 배열은
        // 값 타입이라 그 구분이 없으므로 값이 같은지만 본다 — 정상적인 하루는 전부 이 경로를 지난다.
        let points = (1...10).map { fix(Int64($0)) }
        #expect(TrailCodec.capped(points) == points)
    }

    @Test("상한을 넘으면 출발과 도착을 남기고 하루 전체에서 고른다")
    func 상한_초과() {
        let points = (1...(TrailCodec.maxPoints + 500)).map { fix(Int64($0)) }
        let capped = TrailCodec.capped(points)
        #expect(capped.count == TrailCodec.maxPoints)
        #expect(capped.first == points.first)
        #expect(capped.last == points.last)
        #expect(zip(capped, capped.dropFirst()).allSatisfy { $0.at < $1.at })
    }

    @Test("상한을 넘겨도 경로의 큰 회전점은 남긴다")
    func 회전점_보존() {
        let cornerIndex = TrailCodec.maxPoints / 2
        let points = (0...(TrailCodec.maxPoints + 500)).map { index in
            fix(
                Int64(index),
                lat: index == cornerIndex ? 37.9 : 37.5665,
                lng: 126.9780 + Double(index) * 0.000001
            )
        }
        #expect(TrailCodec.capped(points).contains(points[cornerIndex]))
    }

    @Test("상한에 딱 맞으면 아무것도 안 버린다")
    func 상한_정확() {
        let points = (1...TrailCodec.maxPoints).map { fix(Int64($0)) }
        #expect(TrailCodec.capped(points) == points)
    }

    @Test("서버 경로 상한은 이천 점이다")
    func 상한_값() {
        // 이보다 키우는 것은 Firestore 문서 크기 측정 없이 해서는 안 된다.
        #expect(TrailCodec.maxPoints == 2_000)
    }
}
