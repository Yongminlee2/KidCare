import FirebaseFirestore
import Foundation
import Testing
@testable import KidCare

/// 아이 폰이 **쓰는** 문서의 필드 집합이 코틀린과 같은지 본다. 이 앱의 규율
/// ("`firestoreData` 가 곧 계약의 증거", `Documents.swift:18`)을 아이 쪽에도 건다 —
/// 필드가 하나 어긋나면 보호자 화면이 그 값을 통째로 못 읽는다.
struct ChildDocumentsTests {

    @Test("하루 문서의 필드는 코틀린 TrailDoc 과 같다 — 넷뿐이다(Documents.kt:148-155)")
    func 하루문서_필드() {
        let doc = TrailDoc(dayKey: "2026-09-22", points: [], segments: [], updatedAt: 1)
        #expect(Set(doc.firestoreData.keys) == ["dayKey", "points", "segments", "updatedAt"])
        #expect(doc.firestoreData["dayKey"] as? String == "2026-09-22")
        #expect(doc.firestoreData["updatedAt"] as? Int64 == 1)
    }

    @Test("경로점의 필드는 다섯뿐이다 — battery 를 넣지 않는다(Documents.kt:163-167 주석)")
    func 경로점_필드() {
        let point = TrailPoint(Fix(lat: 1, lng: 2, accuracy: 3, at: 5, speed: 4))
        #expect(Set(point.firestoreData.keys) == ["lat", "lng", "accuracy", "speed", "at"])
        #expect(point.firestoreData["speed"] as? Double == 4)
        #expect(point.firestoreData["at"] as? Int64 == 5)
    }

    @Test("구간 요약의 필드는 여덟이다. dayKey 가 없다 — 담고 있는 문서 ID 가 이미 말한다")
    func 구간_필드() {
        let segment = SegmentDoc(
            type: "STAY", startAt: 1, endAt: 2, lat: 37.5, lng: 127,
            distanceMeters: 0, pointCount: 3, placeName: ""
        )
        #expect(Set(segment.firestoreData.keys) == [
            "type", "startAt", "endAt", "lat", "lng", "distanceMeters", "pointCount", "placeName",
        ])
        // nameLat/nameLng 는 이름을 묻는 데만 쓰는 값이라 서버에 안 나간다(TrailUploader.kt:176-178).
        #expect(segment.firestoreData["nameLat"] == nil)
    }

    @Test("구간 타입 글자는 코틀린 SegmentType.name 그대로다 — STAY · MOVE")
    func 구간_타입_글자() {
        let points = [
            Fix(lat: 37.5, lng: 127, accuracy: 10, at: 0),
            Fix(lat: 37.5, lng: 127, accuracy: 10, at: 10 * 60_000),
        ]
        let segments = TrailUploader.buildSegments(points)
        #expect(segments.first?.type == "STAY")
        // 1단계에는 역지오코딩이 없다 — placeName 은 전부 빈 문자열이다(2단계가 채운다).
        #expect(segments.allSatisfy { $0.placeName.isEmpty })
    }

    @Test("상태 문서는 코틀린 필드 + platform 이고, wifiOn 은 안 쓴다(1단계 판정 기록 10)")
    func 상태문서_필드() {
        let write = ChildStatusWrite(
            fix: Fix(lat: 37.5665, lng: 126.9780, accuracy: 12.5, at: 1_790_035_200_000, speed: 1.25),
            battery: 77, charging: false, network: "wifi", lastSeenAt: 1_790_035_200_123
        )
        #expect(Set(write.firestoreData.keys) == [
            "lat", "lng", "accuracy", "at", "battery", "charging",
            "ringerMode", "dnd", "network", "lastSeenAt", "lastSeenServerAt", "platform",
        ])
        // 아이폰은 소리 모드를 읽을 API 가 없다. 필드를 **빼면** 기본값 "normal" 이 살아나
        // 부모 화면이 "벨소리"라고 거짓말한다 — 빈 값이 "모른다"다.
        #expect(write.firestoreData["ringerMode"] as? String == "")
        #expect(write.firestoreData["dnd"] as? String == "")
        #expect(write.firestoreData["platform"] as? String == "ios")
        #expect(RingerMode.isKnown("") == false, "빈 값이 '모름'이 아니게 되면 보호자 화면이 벨소리라고 거짓말한다")
        // 서버 시각은 아이 폰 시계로 채우지 않는다(StatusReporter.kt:61-65).
        #expect(write.firestoreData["lastSeenServerAt"] is FieldValue)
        #expect(write.firestoreData["lastSeenAt"] as? Int64 == 1_790_035_200_123)
        #expect(write.firestoreData["battery"] as? Int == 77)
    }

    @Test("쓴 것을 다시 읽으면 같다 — firestoreData → init 왕복")
    func 왕복() throws {
        let 원본 = TrailDoc(
            dayKey: "2026-09-22",
            points: [TrailPoint(Fix(lat: 37.5665, lng: 126.9780, accuracy: 12.5, at: 1, speed: 1.25))],
            segments: [SegmentDoc(type: "MOVE", startAt: 1, endAt: 2, lat: 37.5, lng: 127,
                                  distanceMeters: 120.5, pointCount: 6, placeName: "")],
            updatedAt: 3
        )
        let 다시 = TrailDoc(원본.firestoreData)
        #expect(다시.dayKey == "2026-09-22")
        #expect(다시.updatedAt == 3)
        #expect(다시.points.count == 1)
        #expect(다시.points[0].speed == 1.25)
        #expect(다시.points[0].accuracy == 12.5)
        #expect(다시.segments.count == 1)
        #expect(다시.segments[0].type == "MOVE")
        #expect(다시.segments[0].distanceMeters == 120.5)
        #expect(다시.segments[0].pointCount == 6)
    }

    @Test("옛 상태 문서에는 platform 이 없다 — 빈 값이면 안드로이드로 본다(설계서 §10.1)")
    func 옛_문서의_platform() throws {
        let 옛것 = try #require(ChildStatusDoc(["lat": 37.5, "lng": 127.0]))
        #expect(옛것.platform == "")
        let 아이폰 = try #require(ChildStatusDoc(["lat": 37.5, "lng": 127.0, "platform": "ios"]))
        #expect(아이폰.platform == "ios")
    }
}
