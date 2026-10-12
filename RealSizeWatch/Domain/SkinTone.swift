import Foundation
import SwiftUI

struct RGB: Codable, Equatable, Hashable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hex: UInt32) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }

    /// sRGB 부호화를 풀어 선형 광량으로
    var linear: RGB { RGB(ColorMath.toLinear(r), ColorMath.toLinear(g), ColorMath.toLinear(b)) }
    /// 선형 광량을 sRGB로 (0...1 클램프)
    var encoded: RGB { RGB(ColorMath.toSRGB(r), ColorMath.toSRGB(g), ColorMath.toSRGB(b)) }
    /// 선형 값 기준 상대 휘도
    var relativeLuminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    func scaled(_ factor: Double) -> RGB { RGB(r * factor, g * factor, b * factor) }

    /// sRGB 색을 선형 광량 기준으로 밝히거나 어둡게
    func exposed(_ factor: Double) -> RGB { linear.scaled(factor).encoded }
}

enum ColorMath {
    static func toLinear(_ value: Double) -> Double {
        let c = min(max(value, 0), 1)
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func toSRGB(_ value: Double) -> Double {
        let c = min(max(value, 0), 1)
        return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    /// 흑체 색온도의 sRGB 근사 (Tanner Helland)
    static func blackbody(kelvin: Double) -> RGB {
        let t = min(max(kelvin, 1000), 40000) / 100
        let r: Double
        let g: Double
        let b: Double
        if t <= 66 {
            r = 255
            g = 99.4708025861 * log(t) - 161.1195681661
        } else {
            r = 329.698727446 * pow(t - 60, -0.1332047592)
            g = 288.1221695283 * pow(t - 60, -0.0755148492)
        }
        if t >= 66 {
            b = 255
        } else if t <= 19 {
            b = 0
        } else {
            b = 138.5177312231 * log(t - 10) - 305.0447927307
        }
        func unit(_ v: Double) -> Double { min(max(v, 0), 255) / 255 }
        return RGB(unit(r), unit(g), unit(b))
    }
}

enum SkinPreset: String, CaseIterable, Identifiable, Sendable {
    case fair, light, medium, olive, tan, deep

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fair: "아주 밝은"
        case .light: "밝은"
        case .medium: "중간"
        case .olive: "올리브"
        case .tan: "갈색"
        case .deep: "짙은"
        }
    }

    var rgb: RGB {
        switch self {
        case .fair: RGB(hex: 0xF3CDB3)
        case .light: RGB(hex: 0xE3B08F)
        case .medium: RGB(hex: 0xC99068)
        case .olive: RGB(hex: 0xAD7C53)
        case .tan: RGB(hex: 0x8E5B3C)
        case .deep: RGB(hex: 0x5E3B27)
        }
    }
}

/// 가상 손목은 단색 피부톤 + 곡률 음영으로만 표현한다 (미확정 사항 결정 1)
struct SkinTone: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case camera
        case preset
    }

    var base: RGB
    var source: Source
    /// 수동 미세조정. ±1 = ±1스톱. True Tone 때문에 자동 정합만으로는 부족해 필수다 (MIN-45)
    var lightness: Double = 0
    /// 수동 미세조정. +는 따뜻하게(R↑ B↓)
    var warmth: Double = 0

    func rendered(reference: AmbientReading? = nil, current: AmbientReading? = nil) -> RGB {
        var light = base.linear
        light = RGB(light.r * (1 + 0.15 * warmth), light.g, light.b * (1 - 0.15 * warmth))
        light = light.scaled(pow(2, lightness))
        if let reference, let current {
            light = AmbientCompensation.apply(light, from: reference, to: current)
        }
        return light.encoded
    }
}

/// 전면 카메라로 읽은 주변광. 폰을 팔에 올리면 후면 카메라가 가려지므로 천장광으로 추적한다 (MIN-45)
struct AmbientReading: Codable, Equatable, Sendable {
    var temperatureK: Double
    var ev100: Double

    /// 실내 천장 반사 측광은 대략 EV100 5~8, 그늘진 야외가 11 이상이다.
    /// 이 이상에서는 팔이 화면 최대 휘도보다 밝아 착시가 성립하지 않는다 (미확정 사항 추가 발견).
    static let tooBrightEV100 = 11.0

    var isTooBright: Bool { ev100 >= Self.tooBrightEV100 }

    var summary: String {
        "\(Int(temperatureK.rounded()))K · EV \(String(format: "%.1f", ev100))"
    }
}

/// 캘리브레이션 때의 조명(기준) 대비 지금 조명이 달라진 만큼 피부색을 옮긴다
enum AmbientCompensation {
    static let temperatureDeadbandK = 150.0
    static let evDeadband = 0.25
    static let luminanceFactorRange: ClosedRange<Double> = 0.5...2.0
    static let temperatureRange: ClosedRange<Double> = 2500...10000

    static func apply(_ linear: RGB, from reference: AmbientReading, to current: AmbientReading) -> RGB {
        var result = linear
        if abs(current.temperatureK - reference.temperatureK) >= temperatureDeadbandK {
            let from = ColorMath.blackbody(kelvin: clamp(reference.temperatureK, to: temperatureRange)).linear
            let to = ColorMath.blackbody(kelvin: clamp(current.temperatureK, to: temperatureRange)).linear
            let tinted = RGB(
                linear.r * to.r / max(from.r, 1e-4),
                linear.g * to.g / max(from.g, 1e-4),
                linear.b * to.b / max(from.b, 1e-4)
            )
            // 색도만 옮기고 밝기는 아래 노출 차이로 따로 맞춘다
            result = tinted.scaled(linear.relativeLuminance / max(tinted.relativeLuminance, 1e-6))
        }
        let deltaEV = current.ev100 - reference.ev100
        if abs(deltaEV) >= evDeadband {
            result = result.scaled(clamp(pow(2, deltaEV), to: luminanceFactorRange))
        }
        return result
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
