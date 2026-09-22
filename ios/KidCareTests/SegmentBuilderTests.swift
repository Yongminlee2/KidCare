import Foundation
import Testing
@testable import KidCare

/// 정본은 안드로이드 `app/src/test/.../SegmentBuilderTest.kt` 다 — `@Test` 를 하나도 빼지 않고 옮겼다.
struct SegmentBuilderTests {

    private let baseLat = 37.5665
    private let baseLng = 126.9780
    private let t0: Int64 = 1_700_000_000_000

    /// 기준점에서 북쪽으로 `meters` 만큼, `minutes` 분 뒤의 점. 위도 1도 ≈ 111,320m.
    private func p(_ meters: Double, _ minutes: Int64, accuracy: Double = 10) -> Fix {
        Fix(
            lat: baseLat + meters / 111_320.0,
            lng: baseLng,
            accuracy: accuracy,
            at: t0 + minutes * 60_000
        )
    }

    @Test("점이 없으면 구간도 없다")
    func 점_없음() {
        #expect(SegmentBuilder.build(points: []).isEmpty)
    }

    @Test("점이 하나면 구간을 만들지 않는다")
    func 점_하나() {
        // 구간은 시작과 끝이 있어야 의미가 있다. 점 하나로는 머무름인지 이동인지 알 수 없다.
        #expect(SegmentBuilder.build(points: [p(0, 0)]).isEmpty)
    }

    @Test("하루 종일 같은 자리에 있으면 머무름 하나로 묶인다")
    func 하루_종일_머무름() {
        let points = (0...20).map { p(Double($0) * 2, Int64($0) * 10) }   // 10분 간격, 2m 씩만 흔들림
        let segments = SegmentBuilder.build(points: points)
        #expect(segments.count == 1)
        #expect(segments[0].type == .stay)
        #expect(segments[0].startAt == t0)
        #expect(segments[0].endAt == t0 + 200 * 60_000)
        #expect(segments[0].pointCount == 21)
    }

    @Test("5분을 못 채운 정지는 머무름이 아니다")
    func 짧은_정지() {
        // 0분과 3분에 같은 자리, 그 뒤 멀리 이동 → 정지 3분은 머무름이 아니라 이동에 흡수된다.
        let points = [p(0, 0), p(5, 3), p(2000, 10), p(4000, 20)]
        let segments = SegmentBuilder.build(points: points)
        #expect(!segments.contains { $0.type == .stay }, "머무름이 하나도 없어야 한다: \(segments)")
    }

    @Test("정확히 5분 머무르면 머무름으로 인정한다")
    func 최소_머무름_경계() {
        // 경계값. minStayMillis 는 '이상' 이어야 한다.
        let points = [p(0, 0), p(5, 5), p(3000, 20), p(6000, 30)]
        let segments = SegmentBuilder.build(points: points)
        #expect(segments.first?.type == .stay)
        #expect((segments.first?.endAt ?? 0) - (segments.first?.startAt ?? 0) == 5 * 60_000)
    }

    @Test("GPS 가 한 번 튀어도 머무름이 깨지지 않는다")
    func 한_번_튐() {
        // 반경을 벗어난 점이 연속 2개여야 머무름이 끝난다. 1개는 튄 것으로 본다.
        let points = [
            p(0, 0), p(10, 10),
            p(500, 20),           // 튐 (연속 1개)
            p(15, 30), p(20, 40),
        ]
        let segments = SegmentBuilder.build(points: points)
        #expect(segments.count == 1)
        #expect(segments[0].type == .stay)
        #expect(segments[0].endAt == t0 + 40 * 60_000)
    }

    @Test("반경을 벗어난 점이 연속 두 개면 머무름이 끝난다")
    func 연속_이탈() {
        let points = [
            p(0, 0), p(10, 10), p(20, 20),
            p(3000, 30), p(6000, 40),        // 연속 2개 → 머무름 종료
            p(9000, 50), p(12000, 60),
        ]
        let segments = SegmentBuilder.build(points: points)
        #expect(segments[0].type == .stay)
        #expect(segments[0].endAt == t0 + 20 * 60_000)
        #expect(segments[1].type == .move)
    }

    @Test("머무름 이동 머무름 순서로 나온다")
    func 구간_순서() {
        var points: [Fix] = (0...4).map { p(Double($0) * 5, Int64($0) * 10) }   // 학교: 0~40분
        points.append(p(1500, 50)); points.append(p(3000, 60))                  // 이동: 50~60분
        points.append(contentsOf: (0...5).map { p(3000 + Double($0) * 5, 70 + Int64($0) * 10) })  // 학원
        let segments = SegmentBuilder.build(points: points)
        #expect(segments.map(\.type) == [.stay, .move, .stay])
    }

    @Test("이동 구간은 앞뒤 머무름과 시각이 이어진다")
    func 구간_시각_연결() {
        // 지도에 선을 그릴 때 구간 사이가 끊기면 안 된다.
        var points: [Fix] = (0...4).map { p(Double($0) * 5, Int64($0) * 10) }
        points.append(p(1500, 50)); points.append(p(3000, 60))
        points.append(contentsOf: (0...5).map { p(3000 + Double($0) * 5, 70 + Int64($0) * 10) })
        let segments = SegmentBuilder.build(points: points)
        for i in 0..<(segments.count - 1) {
            #expect(segments[i].endAt == segments[i + 1].startAt,
                    "구간 \(i) 의 끝과 \(i + 1) 의 시작이 어긋난다: \(segments)")
        }
    }

    @Test("이동 거리는 점 사이 거리의 합이다")
    func 이동_거리() {
        let points = [
            p(0, 0), p(5, 5),          // 머무름
            p(1000, 20), p(2000, 30),  // 이동
            p(3000, 40), p(3005, 50),  // 머무름
        ]
        let move = SegmentBuilder.build(points: points).first { $0.type == .move }
        let distance = move?.distanceMeters ?? -1
        #expect((2800.0...3200.0).contains(distance),
                "이동 거리가 \(distance)m 로 예상 범위(2800~3200)를 벗어났다")
    }

    @Test("머무름의 좌표는 그 구간 점들의 평균이다")
    func 머무름_평균_좌표() {
        let points = [p(0, 0), p(30, 5), p(3000, 30), p(6000, 40)]
        let stay = SegmentBuilder.build(points: points).first { $0.type == .stay }
        // 0m 와 30m 의 평균 = 15m 지점 (두 점 다 머무름 반경 40m 안이다)
        let expectedLat = baseLat + 15.0 / 111_320.0
        #expect(abs((stay?.lat ?? 0) - expectedLat) < 1e-6)
    }

    @Test("시각이 뒤섞여 들어와도 정렬해서 처리한다")
    func 정렬() {
        // Firestore 쿼리 결과 순서를 믿지 않는다.
        let ordered = (0...10).map { p(Double($0) * 2, Int64($0) * 10) }
        #expect(SegmentBuilder.build(points: ordered) == SegmentBuilder.build(points: ordered.shuffled()))
    }

    @Test("정확도가 나쁜 점은 계산에서 뺀다")
    func 나쁜_정확도_제외() {
        let points = [
            p(0, 0), p(5, 10),
            p(5000, 15, accuracy: 500),   // 오차 500m — 무시돼야 한다
            p(10, 20), p(15, 30),
        ]
        let segments = SegmentBuilder.build(points: points)
        #expect(segments.count == 1)
        #expect(segments[0].type == .stay)
        #expect(segments[0].pointCount == 4)
    }

    @Test("완화 문턱으로 올라온 거친 점은 계산에서 빼지 않는다")
    func 완화_문턱_점_유지() {
        // 오차 50~100m 는 LocationFilter 가 "오래 아무것도 못 올렸을 때" 일부러 올린 점이다.
        // 여기서 빼 버리면 신호가 나쁜 날에 지도 마커만 움직이고 타임라인은 텅 빈다.
        let points = [p(0, 0), p(5, 10, accuracy: 90), p(10, 20), p(15, 30)]
        let segments = SegmentBuilder.build(points: points)
        #expect(segments.count == 1)
        #expect(segments[0].pointCount == 4)
    }

    @Test("이름 좌표는 정확한 점 쪽으로 끌린다")
    func 이름_좌표_가중평균() {
        // 도착 순간 한 번 크게 튄 fix(오차 90m)가 이름을 정하면 옆 건물이 나온다.
        // 나쁜 점도 머무름 반경(40m) 안이어야 같은 구간에 들어간다.
        let points = [
            p(30, 0, accuracy: 90),   // 도착 순간의 나쁜 점
            p(0, 10), p(0, 20), p(0, 30),
        ]
        let stay = try? #require(SegmentBuilder.build(points: points).first { $0.type == .stay })
        let badLat = baseLat + 30.0 / 111_320.0
        let goodLat = baseLat

        let nameOffset = abs((stay?.nameLat ?? 0) - goodLat)
        let meanOffset = abs((stay?.lat ?? 0) - goodLat)
        #expect(nameOffset < meanOffset,
                "이름 좌표가 단순 평균보다 좋은 점에 가까워야 한다: name=\(stay?.nameLat ?? 0) mean=\(stay?.lat ?? 0)")
        #expect(abs((stay?.nameLat ?? 0) - badLat) > abs((stay?.nameLat ?? 0) - goodLat),
                "이름 좌표가 나쁜 점 쪽으로 끌려갔다: \(stay?.nameLat ?? 0)")
    }

    @Test("오차가 모두 같으면 이름 좌표는 단순 평균과 같다")
    func 균일_가중치() {
        // 가중치가 균일하면 가중 평균은 산술 평균이다 — 가중이 공짜로 좌표를 흔들지 않는다는 확인이다.
        let points = [p(0, 0), p(30, 5), p(3000, 30), p(6000, 40)]
        let stay = SegmentBuilder.build(points: points).first { $0.type == .stay }
        #expect(abs((stay?.lat ?? 0) - (stay?.nameLat ?? 1)) < 1e-9)
        #expect(abs((stay?.lng ?? 0) - (stay?.nameLng ?? 1)) < 1e-9)
    }

    @Test("오차 0 인 옛 점이 이름 좌표를 독점하지 않는다")
    func 오차_0_점() {
        // 옛 points 문서는 accuracy 가 0 으로 읽힌다. 0 은 완벽하다는 뜻이 아니라 모른다는 뜻이라,
        // 1/0² 로 무한대 가중치를 주면 안 된다.
        let points = [
            p(30, 0, accuracy: 0),
            p(0, 10), p(0, 20), p(0, 30),
        ]
        let stay = SegmentBuilder.build(points: points).first { $0.type == .stay }
        let loneLat = baseLat + 30.0 / 111_320.0

        #expect(stay?.nameLat.isFinite == true, "이름 좌표가 유한해야 한다: \(stay?.nameLat ?? .nan)")
        #expect((stay?.nameLat ?? .infinity) < loneLat,
                "오차 0 짜리 점 하나가 이름 좌표를 통째로 가져갔다: \(stay?.nameLat ?? 0)")
        #expect((stay?.nameLat ?? 0) > baseLat,
                "나머지 점들이 이름 좌표를 통째로 가져갔다: \(stay?.nameLat ?? 0)")
    }

    @Test("이동 구간의 이름 좌표는 도착 지점 그대로다")
    func 이동_이름_좌표() {
        let points = [p(0, 0), p(5, 5), p(3000, 30), p(6000, 40)]
        let move = SegmentBuilder.build(points: points).first { $0.type == .move }
        #expect(abs((move?.lat ?? 0) - (move?.nameLat ?? 1)) < 1e-12)
        #expect(abs((move?.lng ?? 0) - (move?.nameLng ?? 1)) < 1e-12)
    }
}
