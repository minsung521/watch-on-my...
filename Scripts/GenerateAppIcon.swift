import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 프로젝트 루트에서: swift Scripts/GenerateAppIcon.swift
let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func shadedBand(_ rect: CGRect, base: UInt32, edge: UInt32) {
    context.saveGState()
    context.clip(to: rect)
    let gradient = CGGradient(colorsSpace: space, colors: [color(edge), color(base), color(base), color(edge)] as CFArray, locations: [0, 0.3, 0.7, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
    context.restoreGState()
}

context.setFillColor(color(0x101215))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

// 가상 손목 띠 (가로)
shadedBand(CGRect(x: 0, y: 262, width: 1024, height: 500), base: 0xC99068, edge: 0x7A5238)

// 스트랩
shadedBand(CGRect(x: 412, y: 262, width: 200, height: 500), base: 0x3A2618, edge: 0x1E140C)

// 러그
context.setFillColor(color(0xB9BEC5))
for x in [384.0, 612.0] {
    for y in [282.0, 612.0] {
        context.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: 28, height: 130), cornerWidth: 14, cornerHeight: 14, transform: nil))
    }
}
context.fillPath()

// 케이스, 베젤, 다이얼
context.setFillColor(color(0xD9DCE0))
context.fillEllipse(in: CGRect(x: 322, y: 322, width: 380, height: 380))
context.setFillColor(color(0x9AA0A8))
context.fillEllipse(in: CGRect(x: 336, y: 336, width: 352, height: 352))
context.setFillColor(color(0x15171A))
context.fillEllipse(in: CGRect(x: 352, y: 352, width: 320, height: 320))
context.setFillColor(color(0xD9DCE0))
context.fill(CGRect(x: 700, y: 488, width: 26, height: 48))

// 인덱스
context.setFillColor(color(0xF4F3EE))
for hour in 0..<12 {
    let angle = Double(hour) / 12 * 2 * Double.pi
    context.saveGState()
    context.translateBy(x: 512 + 128 * sin(angle), y: 512 + 128 * cos(angle))
    context.rotate(by: -angle)
    let length: CGFloat = hour % 3 == 0 ? 30 : 20
    context.fill(CGRect(x: -5, y: -length / 2, width: 10, height: length))
    context.restoreGState()
}

// 바늘 10:10
func hand(angle: Double, length: CGFloat, width: CGFloat, hex: UInt32) {
    context.saveGState()
    context.translateBy(x: 512, y: 512)
    context.rotate(by: -angle)
    context.setFillColor(color(hex))
    context.addPath(CGPath(roundedRect: CGRect(x: -width / 2, y: -14, width: width, height: length + 14), cornerWidth: width / 2, cornerHeight: width / 2, transform: nil))
    context.fillPath()
    context.restoreGState()
}
hand(angle: -Double.pi / 3, length: 84, width: 16, hex: 0xF4F3EE)
hand(angle: Double.pi / 3, length: 124, width: 11, hex: 0xF4F3EE)
context.setFillColor(color(0xE0533A))
context.fillEllipse(in: CGRect(x: 502, y: 502, width: 20, height: 20))

// 1mm 눈금자
context.setFillColor(color(0xF4F3EE, 0.7))
for index in 0...50 {
    let x = 112 + CGFloat(index) * 16
    let height: CGFloat = index % 10 == 0 ? 56 : (index % 5 == 0 ? 40 : 26)
    context.fill(CGRect(x: x - 2, y: 920 - height, width: 4, height: height))
}

let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("RealSizeWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
assert(CGImageDestinationFinalize(destination))
print("wrote \(url.path)")
