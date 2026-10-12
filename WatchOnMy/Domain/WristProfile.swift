import Foundation

/// 폭이 두 개인 이유: 렌더링은 사용자가 눈으로 맞춘 겉보기 폭(pt), 표시·핏 판정은 시야각 보정을 거친 실측 폭(mm). 합치지 말 것 (00 6절).
struct WristProfile: Codable, Equatable, Sendable {
    /// 사용자가 화면에서 맞춘 띠 높이. 렌더링에 그대로 사용
    var matchedWidthPoints: Double
    /// 띠의 세로 위치 오프셋 (+는 아래)
    var bandOffsetPoints: Double
    /// 시야각 보정 후 실제 폭. 표시 "약 OOmm", v1.1 핏 판정 입력
    var trueWidthMM: Double
    /// v1: 선택한 프리셋
    var skinBaseColor: RGB
    var skinHueOffset: Double
    var skinSaturationScale: Double
    var skinBrightnessScale: Double
    var calibratedAt: Date

    static let hueOffsetRange: ClosedRange<Double> = -0.05...0.05
    static let saturationScaleRange: ClosedRange<Double> = 0.7...1.3
    static let brightnessScaleRange: ClosedRange<Double> = 0.7...1.3

    static func trueWidthMM(matchedWidthPoints: Double, scale: PhysicalScale) -> Double {
        scale.mm(fromPoints: matchedWidthPoints) * Constants.wristDepthCorrection
    }

    /// 손목 맞추기 전 시작값
    static func initial(scale: PhysicalScale, skin: RGB = SkinPreset.p4.rgb) -> WristProfile {
        let points = scale.points(fromMM: Constants.initialMatchedWidthMM)
        return WristProfile(
            matchedWidthPoints: points,
            bandOffsetPoints: 0,
            trueWidthMM: trueWidthMM(matchedWidthPoints: points, scale: scale),
            skinBaseColor: skin,
            skinHueOffset: 0,
            skinSaturationScale: 1,
            skinBrightnessScale: 1,
            calibratedAt: Date()
        )
    }

    var skinColor: RGB {
        SkinColor.adjusted(
            base: skinBaseColor,
            hueOffset: skinHueOffset,
            saturationScale: skinSaturationScale,
            brightnessScale: skinBrightnessScale
        )
    }

    /// "약 57mm" — 계수 검증 전이라 ±3mm 오차가 있으므로 "약"과 정수 반올림이 필수
    var trueWidthText: String {
        "약 \(Int(trueWidthMM.rounded()))mm"
    }

    mutating func recomputeTrueWidth(scale: PhysicalScale) {
        trueWidthMM = Self.trueWidthMM(matchedWidthPoints: matchedWidthPoints, scale: scale)
    }
}

enum SkinColor {
    static func adjusted(base: RGB, hueOffset: Double, saturationScale: Double, brightnessScale: Double) -> RGB {
        let hsb = base.hsb
        let hue = hsb.hue + clamp(hueOffset, to: WristProfile.hueOffsetRange)
        let saturation = hsb.saturation * clamp(saturationScale, to: WristProfile.saturationScaleRange)
        let brightness = hsb.brightness * clamp(brightnessScale, to: WristProfile.brightnessScaleRange)
        return RGB(hue: hue, saturation: saturation, brightness: brightness).clamped
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// 피부톤 프리셋 6종 (03 5-1). sRGB 출발점이며 실기에서 조정 가능
enum SkinPreset: Int, CaseIterable, Identifiable, Sendable {
    case p1 = 1, p2, p3, p4, p5, p6

    var id: Int { rawValue }

    var rgb: RGB {
        switch self {
        case .p1: RGB(hex: 0xF1D3BF)
        case .p2: RGB(hex: 0xE8C1A0)
        case .p3: RGB(hex: 0xD9A982)
        case .p4: RGB(hex: 0xC68E68)
        case .p5: RGB(hex: 0xA9714E)
        case .p6: RGB(hex: 0x7E5236)
        }
    }

    static func matching(_ rgb: RGB) -> SkinPreset? {
        allCases.first { $0.rgb == rgb }
    }
}

/// 손목 띠의 세로 단면: 위치별 곡률 음영과 가장자리 알파
enum BandProfile {
    /// t: 띠 높이 대비 위치(0 = 위쪽 가장자리, 1 = 아래쪽 가장자리)
    static func brightness(at t: Double) -> Double {
        let stops = Constants.bandShading
        let clampedT = min(max(t, 0), 1)
        for index in 1..<stops.count where clampedT <= stops[index].location {
            let lower = stops[index - 1]
            let upper = stops[index]
            let fraction = (clampedT - lower.location) / (upper.location - lower.location)
            return lower.brightness + (upper.brightness - lower.brightness) * fraction
        }
        return stops[stops.count - 1].brightness
    }

    /// distanceFromEdge: 맞춘 가장자리로부터 띠 안쪽(+) 거리. 페이드 구간의 가운데가 맞춘 가장자리다.
    static func edgeAlpha(distanceFromEdge distance: Double, fade: Double) -> Double {
        guard fade > 0 else { return distance >= 0 ? 1 : 0 }
        let t = min(max((distance + fade / 2) / fade, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
