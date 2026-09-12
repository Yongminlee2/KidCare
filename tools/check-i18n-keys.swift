#!/usr/bin/env swift
//
// check-i18n-keys.swift
//
// `i18n/*.json` 14개 파일이 같은 문구 키 집합을 공유하는지 확인한다.
//
// 왜 필요한가: Phase 1 이 새 키 7개를, Phase 2 가 다시 늘려 총 18개를 `ko.json`·
// `en.json` 에만 추가했다 — 나머지 12개 언어에는 아무도 넣지 않았고, 안드로이드도
// iOS 도 그 키들을 아직 참조하지 않아 어느 빌드도 이를 알아채지 못했다. 이대로
// Phase 6 이 이 카탈로그에서 문구를 뽑아 쓰기 시작하면, 빠진 언어의 기기에서만
// 문구가 안 나오거나(최선) 크래시가 난다(최악).
//
// 이 스크립트는 번역을 짓지 않는다 — 그건 이 파일이 할 일이 아니다(안전 관련 문구를
// 기계 번역으로 12개 언어에 흘려보내는 것은 맡겨진 일이 아니다). 그저 **빠진 키를
// 언어별로 나열해서**, Phase 6 착수 시점에 "뭐가 문제인지 찾는" 일이 아니라 "이
// 목록을 채우는" 일이 되게 한다.
//
// 사용법:
//   swift tools/check-i18n-keys.swift [i18n 디렉터리 경로, 기본값 "i18n"]
//
// 종료 코드: 키 집합이 일치하면 0, 하나라도 어긋나면 1.

import Foundation

let arguments = CommandLine.arguments
let i18nDirPath = arguments.count > 1 ? arguments[1] : "i18n"
let i18nDir = URL(fileURLWithPath: i18nDirPath)

let fileManager = FileManager.default
guard let entries = try? fileManager.contentsOfDirectory(at: i18nDir, includingPropertiesForKeys: nil) else {
    FileHandle.standardError.write("i18n 디렉터리를 못 찾았다: \(i18nDir.path)\n".data(using: .utf8)!)
    exit(1)
}
let jsonFiles = entries
    .filter { $0.pathExtension == "json" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

guard !jsonFiles.isEmpty else {
    FileHandle.standardError.write("i18n/*.json 파일이 하나도 없다: \(i18nDir.path)\n".data(using: .utf8)!)
    exit(1)
}

func keys(of url: URL) throws -> Set<String> {
    let data = try Data(contentsOf: url)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw NSError(
            domain: "check-i18n-keys", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "\(url.lastPathComponent) 이 JSON 객체({...})가 아니다"]
        )
    }
    return Set(object.keys)
}

var keysByFile: [String: Set<String>] = [:]
for file in jsonFiles {
    do {
        keysByFile[file.lastPathComponent] = try keys(of: file)
    } catch {
        FileHandle.standardError.write("\(file.lastPathComponent) 을 읽는 데 실패했다: \(error.localizedDescription)\n".data(using: .utf8)!)
        exit(1)
    }
}

// 합집합을 "이상적인 전체 키 집합"으로 삼는다 — 어느 한 언어가 기준이 아니라, 지금까지
// 어느 파일에든 등장한 키는 전부 있어야 한다고 본다.
let unionKeys = keysByFile.values.reduce(into: Set<String>()) { $0.formUnion($1) }

var hasMismatch = false
for file in jsonFiles {
    let name = file.lastPathComponent
    let missing = unionKeys.subtracting(keysByFile[name] ?? []).sorted()
    if !missing.isEmpty {
        hasMismatch = true
        print("\(name): \(missing.count)개 키 없음")
        for key in missing {
            print("  - \(key)")
        }
    }
}

if hasMismatch {
    print("")
    print("14개 i18n/*.json 파일이 같은 키 집합을 공유하지 않는다.")
    print("번역을 지어내지 말 것 — 실제 번역이 준비되는 대로(Phase 6) 위에 나열된 키를 채운다.")
    exit(1)
} else {
    print("모든 i18n/*.json 파일이 같은 \(unionKeys.count)개 키를 공유한다.")
}
