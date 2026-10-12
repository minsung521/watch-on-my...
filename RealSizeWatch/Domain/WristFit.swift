import Foundation

struct WristProfile: Codable, Equatable, Sendable {
    /// 화면 위에서 실제 팔에 맞춘 가상 손목 폭. 렌더링에는 이 값을 그대로 쓴다.
    var matchedWidthMM: Double
    /// 사용자가 직접 입력한 손목 둘레. 있으면 판정 기준 폭을 덮어쓴다 (MIN-48).
    var circumferenceMM: Double?

    /// 손목 실루엣의 최대폭 지점은 팔 윗면보다 손목 두께의 절반(약 21mm) 아래에 있어,
    /// 시야 거리 350mm에서 화면에 맞춘 폭은 실제보다 8.3% 좁다. 보정은 렌더링이 아니라 저장값에 한다 (MIN-45).
    static let viewingCorrection = 1.083
    /// 실제 57mm 손목을 화면에서 맞췄을 때의 값
    static let defaultMatchedWidthMM = 52.6
    static let matchedWidthRange: ClosedRange<Double> = 35...80
    static let circumferenceRange: ClosedRange<Double> = 110...260

    var measuredWidthMM: Double { matchedWidthMM * Self.viewingCorrection }

    var fitWidthMM: Double {
        if let circumferenceMM {
            return WristGeometry.width(fromCircumference: circumferenceMM)
        }
        return measuredWidthMM
    }
}

enum WristGeometry {
    /// 손목 단면을 폭:두께 = 1.35 타원으로 근사한다 (MIN-48)
    static let widthToThickness = 1.35

    /// Ramanujan 타원 둘레 근사
    static func circumference(fromWidth width: Double) -> Double {
        let a = width / 2
        let b = width / (2 * widthToThickness)
        return Double.pi * (3 * (a + b) - ((3 * a + b) * (a + 3 * b)).squareRoot())
    }

    /// 둘레는 폭에 정비례하므로 폭 1mm일 때의 둘레로 나누면 된다
    static func width(fromCircumference circumference: Double) -> Double {
        circumference / Self.circumference(fromWidth: 1)
    }
}

struct FitVerdict: Equatable, Sendable {
    enum Level: Equatable, Sendable {
        case comfortable
        case borderline
        case overhang
    }

    /// 기획서 둘레 테이블은 전 구간에서 L2L 상한 ≈ 실루엣 폭 × 0.78로 수렴한다.
    /// 시야 거리 개인차로 폭 자체에 ±3% 잔차가 있으므로 이분법 대신 경계 밴드를 둔다 (MIN-48).
    static let comfortableRatio = 0.74
    static let overhangRatio = 0.82

    let lugToLug: Double
    let wristWidth: Double
    let level: Level

    init(lugToLug: Double, wristWidth: Double) {
        self.lugToLug = lugToLug
        self.wristWidth = wristWidth
        let limits = Self.limits(wristWidth: wristWidth)
        if lugToLug <= limits.comfortable + 1e-9 {
            level = .comfortable
        } else if lugToLug <= limits.borderline + 1e-9 {
            level = .borderline
        } else {
            level = .overhang
        }
    }

    static func limits(wristWidth: Double) -> (comfortable: Double, borderline: Double) {
        (wristWidth * comfortableRatio, wristWidth * overhangRatio)
    }

    var title: String {
        switch level {
        case .comfortable: "여유 있음"
        case .borderline: "경계 — 취향의 영역"
        case .overhang: "러그가 넘침"
        }
    }

    var message: String {
        let head = "L2L \(lugToLug.mmText)mm — 손목 폭 \(wristWidth.mmText)mm 기준으로"
        switch level {
        case .comfortable: return "\(head) 여유 있게 들어갑니다."
        case .borderline: return "\(head) 경계에 있습니다. 여기부터는 취향의 영역이에요."
        case .overhang: return "\(head) 러그가 넘칩니다."
        }
    }
}

extension Double {
    /// 48 → "48", 52.5 → "52.5", 56.97 → "57"
    var mmText: String {
        let tenths = (self * 10).rounded()
        if tenths.truncatingRemainder(dividingBy: 10) == 0 {
            return String(Int(tenths / 10))
        }
        return String(format: "%.1f", tenths / 10)
    }
}
