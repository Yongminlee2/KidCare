import Foundation

/// 페어링용 6자리 초대 코드.
///
/// 부모 폰 화면에 뜬 코드를 사람이 눈으로 읽어 다른 폰에 옮겨 적는다. 그래서
/// 0/O, 1/I/L 처럼 화면에서 헷갈리는 글자를 알파벳에서 빼고, 사용자가 그런 글자를
/// 입력하면 조용히 교정한다.
///
/// 정본은 안드로이드 `logic/InviteCode.kt` 다. **생성 결과는 안드로이드와 다르다** —
/// 난수기 알고리즘이 달라 같은 시드에서 같은 코드가 나올 수 없다. 두 폰이 맞아야
/// 하는 것은 생성이 아니라 `normalize`·`isValid` 다(한쪽이 만든 코드를 다른 쪽이
/// 같게 읽어야 한다).
enum InviteCode {

    /// 0, 1, O, I, L 을 뺀 31글자.
    static let alphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"

    static let length = 6

    /// 사용자가 잘못 입력하기 쉬운 글자 → 알파벳 안의 대체 글자.
    private static let corrections: [Character: Character] = [
        "0": "Q", "O": "Q",
        "1": "J", "I": "J", "L": "J",
    ]

    static func generate(using generator: inout some RandomNumberGenerator) -> String {
        let letters = Array(alphabet)
        return String((0..<length).map { _ in letters.randomElement(using: &generator)! })
    }

    static func generate() -> String {
        var rng = SystemRandomNumberGenerator()
        return generate(using: &rng)
    }

    /// 대문자화 → 공백·하이픈 제거 → 헷갈리는 글자 교정.
    static func normalize(_ raw: String) -> String {
        String(
            raw.uppercased()
                .filter { !$0.isWhitespace && $0 != "-" }
                .map { corrections[$0] ?? $0 }
        )
    }

    static func isValid(_ raw: String) -> Bool {
        let code = normalize(raw)
        return code.count == length && code.allSatisfy { alphabet.contains($0) }
    }
}

/// 시드를 주면 늘 같은 수열을 내는 난수기. SplitMix64 다.
///
/// 테스트 폴더가 아니라 여기 두는 이유: `generate(using:)` 이 "주어진 난수기를
/// 그대로 쓴다"는 것을 보증하는 유일한 방법이 결정적 난수기로 그 성질을
/// 확인하는 것이라, 이 타입이 곧 그 API 의 의미다.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
