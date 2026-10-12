import Foundation

/// sRGB 0...1
struct RGB: Codable, Hashable, Sendable {
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

    var clamped: RGB {
        RGB(Self.unit(r), Self.unit(g), Self.unit(b))
    }

    /// HSB 밝기 배율과 같다 (sRGB 각 채널에 곱함)
    func scaled(_ factor: Double) -> RGB {
        RGB(r * factor, g * factor, b * factor).clamped
    }

    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    // MARK: HSB

    var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let maxValue = max(r, g, b)
        let minValue = min(r, g, b)
        let delta = maxValue - minValue
        var hue = 0.0
        if delta > 0 {
            if maxValue == r {
                hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxValue == g {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        let saturation = maxValue == 0 ? 0 : delta / maxValue
        return (hue, saturation, maxValue)
    }

    init(hue: Double, saturation: Double, brightness: Double) {
        let h = (hue - floor(hue)) * 6
        let s = Self.unit(saturation)
        let v = Self.unit(brightness)
        let c = v * s
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let (r1, g1, b1): (Double, Double, Double)
        switch h {
        case ..<1: (r1, g1, b1) = (c, x, 0)
        case ..<2: (r1, g1, b1) = (x, c, 0)
        case ..<3: (r1, g1, b1) = (0, c, x)
        case ..<4: (r1, g1, b1) = (0, x, c)
        case ..<5: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        self.init(r1 + m, g1 + m, b1 + m)
    }

    private static func unit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
