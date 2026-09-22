import Foundation

/// 하루치 위치 점을 줄 단위 문자열로 바꾸고 되돌린다. 정본은 안드로이드 `logic/TrailCodec.kt`.
///
/// 형식이 줄 단위 CSV 인 이유는 셋이다. **덧붙이기만 하면 된다**(한 점이 한 줄이라 5초마다
/// 하루치 전체를 다시 쓰지 않는다 — 플래시 마모), **새 의존성이 없다**, **테스트로 고정할 수
/// 있다**.
///
/// **코틀린과 글자가 같을 필요는 없다**(설계서 §4.5). Kotlin `Double.toString`/`Float.toString`
/// 과 Swift 의 문자열 변환은 같은 값에 다른 글자를 낼 수 있는데, 두 플랫폼이 같은 파일을 읽는
/// 일이 없으므로 계약은 "글자가 같다"가 아니라 **"내가 쓴 것을 내가 그대로 읽는다"** 다.
/// 그래서 골든 대조도 문자열이 아니라 `decode` 한 값으로 한다.
enum TrailCodec {

    /// 문서 하나에 담을 점의 최대 개수. `TrailCodec.kt:46`.
    ///
    /// Firestore 문서 한 개의 상한은 1MB 다. 점 하나가 지도 배열 원소로 들어가면 필드 이름까지
    /// 매번 같이 저장돼 대략 90~100바이트를 쓴다 — 2000개면 200KB 안쪽이다. 넘칠 때는 앞부분을
    /// 버리지 않고 [capped] 가 하루 전체에서 경로 모양을 잘 설명하는 점을 고른다.
    static let maxPoints = 2000

    /// 점 하나를 한 줄로. 줄바꿈은 붙이지 않는다 — 파일에 쓰는 쪽이 정한다. `:49-50`.
    static func encodeLine(_ fix: Fix) -> String {
        "\(fix.lat),\(fix.lng),\(fix.accuracy),\(fix.speed),\(fix.at)"
    }

    /// 줄 묶음을 점 목록으로. **깨진 줄은 조용히 버린다.** `:59-60`.
    ///
    /// 파일 끝에 덧붙이는 방식이라 프로세스가 쓰기 도중에 죽으면 마지막 줄이 잘려 있을 수 있다.
    /// 그 한 줄 때문에 그날 기록 전체를 버리면 사고가 훨씬 커진다.
    ///
    /// 코틀린 `lineSequence()` 는 `\r\n`·`\r` 도 줄바꿈으로 보지만 여기서는 `\n` 만 나눈다 —
    /// 우리가 쓰는 파일에는 `\n` 밖에 없고(우리가 쓰는 쪽이다), 골든 생성기도 `\r` 이 섞이지
    /// 않았는지 `check` 로 확인한다.
    static func decode(_ text: String) -> [Fix] {
        text.split(separator: "\n", omittingEmptySubsequences: false).compactMap(decodeLine)
    }

    /// `:62-71`. 코틀린은 `accuracy`/`speed` 를 `toFloatOrNull` 로 읽지만 여기서는 `Double` 이다.
    /// 두 파싱이 갈리는 글자(자바 전용 `1d`·`1f`·`0x1p3` 나 `Float` 로 반올림되는 소수)는 골든
    /// 생성기가 `check` 로 막는다 — 1단계 판정 기록 3 과 같은 규율이다.
    private static func decodeLine(_ line: Substring) -> Fix? {
        let parts = line.split(separator: ",", omittingEmptySubsequences: false)
        if parts.count != 5 { return nil }
        guard let lat = Double(parts[0]),
              let lng = Double(parts[1]),
              let accuracy = Double(parts[2]),
              let speed = Double(parts[3]),
              let at = Int64(parts[4]) else { return nil }
        return Fix(lat: lat, lng: lng, accuracy: accuracy, at: at, speed: speed)
    }

    /// [maxPoints] 를 넘으면 LTTB(Largest Triangle Three Buckets) 방식으로 하루 전체를 대표하는
    /// 점을 고른다. 위·경도를 삼각형 면적으로 비교하므로 직선상의 반복점보다 실제 경로가 꺾이는
    /// 점이 우선해서 남는다. `:78-138`.
    ///
    /// **정수 나눗셈이 섞이면 조용히 갈린다.** `bucketWidth` 의 분모는 `maxPoints - 2` 이고,
    /// `coerceAtMost` 의 대상이 평균 구간에서는 `size`, 탐색 구간에서는 `lastIndex` 로 **서로
    /// 다르다**(`:88-111`). 이 파일에서 가장 틀리기 쉬운 자리라 한 줄씩 대조해 옮겼다.
    static func capped(_ points: [Fix]) -> [Fix] {
        if points.count <= maxPoints { return points }

        var result: [Fix] = []
        result.reserveCapacity(maxPoints)
        let bucketWidth = Double(points.count - 2) / Double(maxPoints - 2)
        let longitudeScale = cos(points[0].lat * .pi / 180.0)
        var selectedIndex = 0
        result.append(points[0])

        for bucket in 0..<(maxPoints - 2) {
            let averageStart = min(Int(floor(Double(bucket + 1) * bucketWidth)) + 1, points.count)
            let averageEnd = min(Int(floor(Double(bucket + 2) * bucketWidth)) + 1, points.count)

            var averageX = 0.0
            var averageY = 0.0
            let averageCount = averageEnd - averageStart
            if averageCount > 0 {
                for index in averageStart..<averageEnd {
                    averageX += points[index].lng * longitudeScale
                    averageY += points[index].lat
                }
                averageX /= Double(averageCount)
                averageY /= Double(averageCount)
            } else {
                averageX = points[points.count - 1].lng * longitudeScale
                averageY = points[points.count - 1].lat
            }

            let rangeStart = min(Int(floor(Double(bucket) * bucketWidth)) + 1, points.count - 1)
            let rangeEnd = min(Int(floor(Double(bucket + 1) * bucketWidth)) + 1, points.count - 1)

            let selected = points[selectedIndex]
            let selectedX = selected.lng * longitudeScale
            let selectedY = selected.lat
            var largestArea = -1.0
            var nextSelectedIndex = rangeStart

            var index = rangeStart
            while index < rangeEnd {
                let candidate = points[index]
                let candidateX = candidate.lng * longitudeScale
                let area = abs(
                    (selectedX - averageX) * (candidate.lat - selectedY)
                        - (selectedX - candidateX) * (averageY - selectedY)
                )
                if area > largestArea {
                    largestArea = area
                    nextSelectedIndex = index
                }
                index += 1
            }

            result.append(points[nextSelectedIndex])
            selectedIndex = nextSelectedIndex
        }

        result.append(points[points.count - 1])
        return result
    }
}
