import Foundation

/// 오늘 걸어온 길을 아이 폰 안에 남긴다. **Firestore 와 아무 상관이 없다.**
/// 정본은 안드로이드 `child/TrailStore.kt` 전체다.
///
/// 왜 필요한가: 위치 점은 한 점씩 올라가지 않고 [TrailBuffer] 의 메모리 버퍼에 쌓였다가 하루
/// 문서 하나로 올라간다(`known-issues.md` 12번). 메모리에만 두면 프로세스가 죽는 순간 그날
/// 아침부터의 기록이 통째로 사라진다.
///
/// 형식은 [TrailCodec] 의 줄 단위 CSV 다. 첫 줄이 dayKey, 그 뒤가 점 한 개당 한 줄이고,
/// **새 점은 파일 끝에 덧붙이기만 한다** — 이동 중 5초마다 하루치 전체를 다시 쓰지 않는다.
///
/// 파일 입출력 실패는 **삼킨다**(`TrailStore.kt:23-25`). 이 파일은 메모리 버퍼의 사본일 뿐
/// 원본이 아니다 — 여기서 던져 위치 수집 자체를 멈추면, 프로세스가 죽었을 때만 쓸모 있는
/// 보험 때문에 평소 동작을 잃는다.
///
/// 안드로이드와 다른 점 셋(1단계 판정 기록 13).
/// 1. 위치가 `.applicationSupportDirectory` 다. `.documentDirectory` 는 파일 앱에 노출될 수
///    있다(설계서 §6.2).
/// 2. **그 폴더는 앱이 만들기 전까지 없다** — 안드로이드 `filesDir` 은 항상 있어서 코틀린에
///    대응 코드가 없다. 그래서 여기서 한 번 만든다.
/// 3. 하루치 위치가 iCloud 로 나갈 이유가 없어 백업에서 뺀다(설계서 §6.2).
///
/// **파일의 시각·속성을 읽는 API 를 쓰지 않는다** — 부르는 순간 `PrivacyInfo.xcprivacy` 에
/// 이유 필요 API 갈래(FileTimestamp)가 하나 늘어난다(1단계 판정 기록 12). 그 갈래에 걸리는
/// 이름들은 `ReleaseConfigTests.이유_필요_API` 목록에 있고, 그 테스트가 소스를 훑어 지킨다 —
/// **이름을 주석에 적기만 해도 걸리므로 여기에도 안 적는다.** 날짜 판정은 파일 시각이 아니라
/// 첫 줄의 dayKey 로 한다(안드로이드와 같다).
final class TrailStore {

    /// [load] 가 돌려주는 것. dayKey 가 오늘이 아니면 남의 날 기록이다(`TrailStore.kt:32`).
    struct Saved: Equatable {
        let dayKey: String
        let points: [Fix]
    }

    /// `TrailStore.kt:68` 과 같은 이름.
    static let fileName = "trail_today.csv"

    private let url: URL?

    init(directory: URL? = nil) {
        let base = directory ?? (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ))
        guard let base else {
            url = nil
            return
        }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent(Self.fileName)
        excludeFromBackup()
    }

    /// 저장된 것이 있으면 돌려준다. 파일이 없거나 읽을 수 없으면 nil(`TrailStore.kt:35-46`).
    func load() -> Saved? {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        guard let newline = text.firstIndex(of: "\n") else {
            // 헤더 한 줄만 있고 점이 하나도 없는 상태(reset 직후)도 정상이다(`:39-40`).
            return Saved(dayKey: text.trimmingCharacters(in: .whitespacesAndNewlines), points: [])
        }
        return Saved(
            dayKey: text[text.startIndex..<newline].trimmingCharacters(in: .whitespacesAndNewlines),
            points: TrailCodec.decode(String(text[text.index(after: newline)...]))
        )
    }

    /// 그 날짜로 새로 시작한다(헤더만 남는다). 자정을 넘겼을 때 부른다(`TrailStore.kt:49-55`).
    func reset(dayKey: String) {
        guard let url else { return }
        do {
            try Data((dayKey + "\n").utf8).write(to: url)
            excludeFromBackup()
        } catch {
            // 삼킨다 — 위 머리 주석.
        }
    }

    /// 점 한 개를 파일 끝에 덧붙인다. [reset] 이 먼저 불려 있어야 한다(`TrailStore.kt:58-64`).
    ///
    /// 덧붙이기는 `FileHandle.seekToEnd` + `write` 다. 한 줄 50바이트라 메인에서도 1ms 아래고,
    /// 버퍼를 만지는 스레드가 하나로 유지된다(`TrailUploader.kt:91-93`).
    func append(_ fix: Fix) {
        guard let url else { return }
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((TrailCodec.encodeLine(fix) + "\n").utf8))
        } catch {
            // 삼킨다 — 위 머리 주석.
        }
    }

    private func excludeFromBackup() {
        guard var url, FileManager.default.fileExists(atPath: url.path) else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
