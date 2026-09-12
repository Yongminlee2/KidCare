#!/usr/bin/env swift
//
// make-ios-icon.swift
//
// 안드로이드 적응형 아이콘(배경 mascot_bg + 전경 마스코트, 런처가 마스크로 잘라 합성)을
// iOS 앱 아이콘(마스크 없이 그대로 노출되는 단일 정사각형 PNG) 형태로 미리 "평평하게"
// 합성해 두는 스크립트다. iOS 는 안드로이드처럼 런처가 배경/전경을 따로 합성해 주는
// 구조가 없으므로, 여기서 한 장으로 미리 구워 둬야 한다.
//
// 사용법:
//   swift tools/make-ios-icon.swift <입력 PNG> <출력 PNG>
//
// 의존성을 더하지 않기 위해 ImageMagick 등 외부 도구 대신 CoreGraphics 만 사용한다.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - 인자 파싱

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write("사용법: swift make-ios-icon.swift <입력 PNG> <출력 PNG>\n".data(using: .utf8)!)
    exit(1)
}
let inputPath = arguments[1]
let outputPath = arguments[2]

let canvasSize = 1024
// 마스코트를 캔버스 가로세로의 80% 로 그린다. 안드로이드 적응형 아이콘이 108dp 중
// 가운데 72dp(=108*2/3)만 "안전 영역"으로 보장하는 것과 같은 비율이다. iOS 는
// 시스템이 아이콘 모서리를 둥글게 깎고 홈 화면에서 아이콘끼리 다닥다닥 붙어 보이므로,
// 그림이 가장자리까지 닿으면 깎여 보이거나 옆 아이콘과 붙어 보인다 — 그래서 여백을 둔다.
let inset: CGFloat = 0.8

// MARK: - 원본 PNG 읽기

guard let inputDataProvider = CGDataProvider(filename: inputPath) else {
    FileHandle.standardError.write("입력 파일을 열 수 없습니다: \(inputPath)\n".data(using: .utf8)!)
    exit(1)
}
guard let sourceImage = CGImage(
    pngDataProviderSource: inputDataProvider,
    decode: nil,
    shouldInterpolate: true,
    intent: .defaultIntent
) else {
    FileHandle.standardError.write("PNG 디코딩에 실패했습니다: \(inputPath)\n".data(using: .utf8)!)
    exit(1)
}

// MARK: - 불투명 1024x1024 비트맵 컨텍스트 생성

// App Store 는 알파 채널이 있는 아이콘을 거부한다. CGImageAlphaInfo 를 .noneSkipLast 로
// 주면 컨텍스트 자체가 알파를 저장하지 않으므로(그리는 도중에도, 최종 PNG 에도),
// 원본(RGBA)을 그 위에 그려도 결과 비트맵에는 알파가 아예 존재하지 않는다.
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: canvasSize,
    height: canvasSize,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    FileHandle.standardError.write("비트맵 컨텍스트 생성에 실패했습니다\n".data(using: .utf8)!)
    exit(1)
}

// 안드로이드의 mascot_bg(#CFEDE7, 민트) 로 배경을 채운다 — 같은 앱이므로 아이콘도
// 같은 배경색을 써야 한다.
//
// CGColor(red:green:blue:alpha:) 편의 생성자를 쓰면 안 된다 — 이 생성자는 감마 1.8
// "제네릭" RGB 색공간에서 색을 만드는데, 우리가 그리는 컨텍스트(58행 colorSpace,
// CGColorSpaceCreateDeviceRGB())는 디바이스 RGB다. 그리는 순간 감마 변환이 끼어들어
// 요청한 (0xCF,0xED,0xE7) 대신 더 밝은 (215,240,236)=#D7F0EC 가 픽셀에 그대로 남는다
// (실제로 그렇게 나왔던 회귀다). 컨텍스트와 같은 colorSpace 로 CGColor 를 만들어야
// 성분 값이 그대로(색공간 변환 없이) 픽셀에 찍힌다.
let backgroundColor = CGColor(
    colorSpace: colorSpace,
    components: [0xCF.cgFloatValue, 0xED.cgFloatValue, 0xE7.cgFloatValue, 1.0]
)!
context.setFillColor(backgroundColor)
context.fill(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

// 배경색이 실제로 요청한 성분 그대로 픽셀에 박혔는지, 그린 직후 바로 읽어 확인한다.
// 색공간이 조용히 바뀌는 회귀(위 74행 주석 참고)는 file 로도 sips 로도 안 보이고
// 빌드도 안 걸린다 — 렌더링 직후 픽셀을 직접 읽는 것만이 잡아낸다. 마스코트를 그리기
// 전, 배경만 채운 상태에서 확인해야 마스코트 색이 섞여 들어오지 않는다.
func verifyBackgroundPixel(context: CGContext, x: Int, y: Int, expected: (UInt8, UInt8, UInt8)) {
    guard let data = context.data else {
        FileHandle.standardError.write("컨텍스트 픽셀 버퍼를 못 읽었습니다\n".data(using: .utf8)!)
        exit(1)
    }
    let bytesPerPixel = context.bitsPerPixel / 8
    let offset = (y * context.bytesPerRow) + (x * bytesPerPixel)
    let pointer = data.assumingMemoryBound(to: UInt8.self)
    let actual = (pointer[offset], pointer[offset + 1], pointer[offset + 2])
    guard actual == expected else {
        let message = "배경색이 요청한 값과 다릅니다: 실제=\(actual) 기대=\(expected) "
            + "— CGColor 가 컨텍스트와 다른 색공간에서 만들어졌을 수 있다\n"
        FileHandle.standardError.write(message.data(using: .utf8)!)
        exit(1)
    }
}
verifyBackgroundPixel(context: context, x: 0, y: 0, expected: (0xCF, 0xED, 0xE7))

// 마스코트를 가운데, 80% 크기로 그린다.
let artworkSide = CGFloat(canvasSize) * inset
let origin = (CGFloat(canvasSize) - artworkSide) / 2
context.draw(sourceImage, in: CGRect(x: origin, y: origin, width: artworkSide, height: artworkSide))

guard let flattenedImage = context.makeImage() else {
    FileHandle.standardError.write("합성 이미지 생성에 실패했습니다\n".data(using: .utf8)!)
    exit(1)
}

// MARK: - PNG로 저장

let outputURL = URL(fileURLWithPath: outputPath)
guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    FileHandle.standardError.write("출력 파일을 만들 수 없습니다: \(outputPath)\n".data(using: .utf8)!)
    exit(1)
}
CGImageDestinationAddImage(destination, flattenedImage, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write("PNG 저장에 실패했습니다: \(outputPath)\n".data(using: .utf8)!)
    exit(1)
}

print("아이콘을 만들었습니다: \(outputPath)")

extension Int {
    var cgFloatValue: CGFloat { CGFloat(self) / 255.0 }
}
