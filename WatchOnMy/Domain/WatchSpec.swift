import Foundation

enum CaseShape: String, Codable, CaseIterable, Identifiable, Sendable {
    case round
    case cushion
    /// 기획서의 "텐구"는 토노(tonneau)의 오기
    case tonneau
    case square

    var id: String { rawValue }

    var label: String {
        switch self {
        case .round: "라운드"
        case .cushion: "쿠션"
        case .tonneau: "토노"
        case .square: "사각"
        }
    }

    /// 슈퍼타원 |x/(W/2)|^n + |y/(L/2)|^n = 1 하나로 4가지 형상 (02 4-1)
    var geometry: (exponent: Double, lengthRatio: Double) {
        switch self {
        case .round: (2.0, 1.00)
        case .cushion: (3.2, 1.00)
        case .tonneau: (2.6, 1.18)
        case .square: (6.0, 1.05)
        }
    }
}

enum CrownSide: String, Codable, CaseIterable, Identifiable, Sendable {
    case right, left

    var id: String { rawValue }

    var label: String {
        switch self {
        case .right: "오른쪽"
        case .left: "왼쪽"
        }
    }
}

struct WatchSpec: Codable, Equatable, Sendable {
    var lugToLugMM: Double
    var caseDiameterMM: Double
    var caseShape: CaseShape
    var lugWidthMM: Double
    /// 직경 대비 베젤 폭. 다이얼 경계 = 케이스 외곽 × (1 − 2 × bezelRatio)
    var bezelRatio: Double
    var dialColor: RGB
    /// 측면도 전용. 정면 렌더링에 영향 없음
    var thicknessMM: Double
    var crownSide: CrownSide
    var strapColor: RGB

    static let lugToLugRange: ClosedRange<Double> = 30...60
    static let caseDiameterRange: ClosedRange<Double> = 26...50
    static let lugWidthRange: ClosedRange<Double> = 12...24
    static let bezelRatioRange: ClosedRange<Double> = 0.05...0.25
    static let thicknessRange: ClosedRange<Double> = 5...20
    static let maxLugWidthRatio = 0.7

    static let defaultLugToLugMM = 47.0
    static let defaultCaseDiameterMM = 40.0
    static let defaultBezelRatio = 0.12
    static let defaultThicknessMM = 12.0

    /// 직경 × 0.45를 가장 가까운 짝수로, 12~24 범위
    static func defaultLugWidth(forDiameter diameter: Double) -> Double {
        let even = (diameter * 0.45 / 2).rounded() * 2
        return min(max(even, lugWidthRange.lowerBound), lugWidthRange.upperBound)
    }

    static func standard(lugToLugMM: Double = defaultLugToLugMM, caseDiameterMM: Double = defaultCaseDiameterMM) -> WatchSpec {
        WatchSpec(
            lugToLugMM: lugToLugMM,
            caseDiameterMM: caseDiameterMM,
            caseShape: .round,
            lugWidthMM: defaultLugWidth(forDiameter: caseDiameterMM),
            bezelRatio: defaultBezelRatio,
            dialColor: DialPreset.black.rgb,
            thicknessMM: defaultThicknessMM,
            crownSide: .right,
            strapColor: StrapPreset.blackLeather.rgb
        )
    }

    var caseLengthMM: Double { caseDiameterMM * caseShape.geometry.lengthRatio }

    enum ValidationError: Equatable, Hashable, Sendable {
        case lugToLugShorterThanCase(caseLengthMM: Double)
        case lugWidthTooWide

        var message: String {
            switch self {
            case .lugToLugShorterThanCase(let length):
                "러그 투 러그는 케이스 길이보다 작을 수 없습니다 (케이스 길이 \(length.mmText)mm)"
            case .lugWidthTooWide:
                "러그 폭은 케이스 직경의 70%를 넘을 수 없습니다"
            }
        }
    }

    var validationErrors: [ValidationError] {
        var errors: [ValidationError] = []
        if lugToLugMM < caseLengthMM - 1e-9 {
            errors.append(.lugToLugShorterThanCase(caseLengthMM: caseLengthMM))
        }
        if lugWidthMM > caseDiameterMM * Self.maxLugWidthRatio + 1e-9 {
            errors.append(.lugWidthTooWide)
        }
        return errors
    }

    var autoName: String {
        "\(caseShape.label) \(caseDiameterMM.mmText)/\(lugToLugMM.mmText)"
    }
}

enum DialPreset: String, CaseIterable, Identifiable, Sendable {
    case black, white, blue, green, silver, champagne

    var id: String { rawValue }

    var label: String {
        switch self {
        case .black: "블랙"
        case .white: "화이트"
        case .blue: "블루"
        case .green: "그린"
        case .silver: "실버"
        case .champagne: "샴페인"
        }
    }

    var rgb: RGB {
        switch self {
        case .black: RGB(hex: 0x15171A)
        case .white: RGB(hex: 0xF2F1EC)
        case .blue: RGB(hex: 0x1F3A68)
        case .green: RGB(hex: 0x1F4D3A)
        case .silver: RGB(hex: 0xC9CCD1)
        case .champagne: RGB(hex: 0xD8C3A0)
        }
    }
}

enum StrapPreset: String, CaseIterable, Identifiable, Sendable {
    case blackLeather, brownLeather, navyFabric, silverBracelet

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blackLeather: "블랙 가죽"
        case .brownLeather: "브라운 가죽"
        case .navyFabric: "네이비 패브릭"
        case .silverBracelet: "실버 브레이슬릿"
        }
    }

    var rgb: RGB {
        switch self {
        case .blackLeather: RGB(hex: 0x1B1B1D)
        case .brownLeather: RGB(hex: 0x5B3A24)
        case .navyFabric: RGB(hex: 0x24304A)
        case .silverBracelet: RGB(hex: 0xB9BDC3)
        }
    }
}

/// 직경이 같고 L2L만 다른 대비. 이름에 브랜드·모델명을 쓰지 않는다 (가이드라인 5.2.1)
enum WatchPreset: String, CaseIterable, Identifiable, Sendable {
    case compact, longLug

    var id: UUID {
        switch self {
        case .compact: UUID(uuidString: "00000000-0000-0000-0000-000000004247")!
        case .longLug: UUID(uuidString: "00000000-0000-0000-0000-000000425250")!
        }
    }

    var name: String {
        switch self {
        case .compact: "컴팩트 42/47"
        case .longLug: "롱러그 42/52.5"
        }
    }

    var spec: WatchSpec {
        var spec = WatchSpec.standard(lugToLugMM: self == .compact ? 47 : 52.5, caseDiameterMM: 42)
        spec.lugWidthMM = 20
        return spec
    }

    var savedWatch: SavedWatch {
        SavedWatch(id: id, name: name, source: .parametric(spec))
    }

    static func isPreset(_ id: UUID) -> Bool {
        allCases.contains { $0.id == id }
    }
}

/// 스펙 입력 폼의 상태. 키보드 직접 입력이 1급 경로이므로 숫자는 문자열로 들고 있다 (04 3절)
struct SpecDraft: Equatable, Sendable {
    var lugToLugText: String
    var diameterText: String
    var caseShape: CaseShape
    /// nil이면 직경에 따른 기본 러그 폭을 따른다
    var customLugWidthMM: Double?
    var bezelRatio: Double
    var dialColor: RGB
    var thicknessMM: Double
    var crownSide: CrownSide
    var strapColor: RGB

    init(spec: WatchSpec) {
        lugToLugText = spec.lugToLugMM.mmText
        diameterText = spec.caseDiameterMM.mmText
        caseShape = spec.caseShape
        customLugWidthMM = spec.lugWidthMM == WatchSpec.defaultLugWidth(forDiameter: spec.caseDiameterMM) ? nil : spec.lugWidthMM
        bezelRatio = spec.bezelRatio
        dialColor = spec.dialColor
        thicknessMM = spec.thicknessMM
        crownSide = spec.crownSide
        strapColor = spec.strapColor
    }

    enum Notice: Equatable, Hashable, Sendable {
        case missingLugToLug
        case missingDiameter
        case lugToLugClamped(to: Double)
        case diameterClamped(to: Double)
        case invalid(WatchSpec.ValidationError)

        var isBlocking: Bool {
            switch self {
            case .missingLugToLug, .missingDiameter, .invalid: true
            case .lugToLugClamped, .diameterClamped: false
            }
        }

        var message: String {
            switch self {
            case .missingLugToLug: "러그 투 러그는 필수 값입니다."
            case .missingDiameter: "케이스 직경은 필수 값입니다."
            case .lugToLugClamped(let value): "L2L은 30~60mm 범위라 \(value.mmText)mm로 맞췄습니다."
            case .diameterClamped(let value): "직경은 26~50mm 범위라 \(value.mmText)mm로 맞췄습니다."
            case .invalid(let error): error.message
            }
        }
    }

    var rawLugToLug: Double? { Self.parse(lugToLugText) }
    var rawDiameter: Double? { Self.parse(diameterText) }
    var lugToLugMM: Double? { rawLugToLug.map { Self.clamp($0, to: WatchSpec.lugToLugRange) } }
    var diameterMM: Double? { rawDiameter.map { Self.clamp($0, to: WatchSpec.caseDiameterRange) } }

    var lugWidthMM: Double {
        customLugWidthMM ?? WatchSpec.defaultLugWidth(forDiameter: diameterMM ?? WatchSpec.defaultCaseDiameterMM)
    }

    var notices: [Notice] {
        var notices: [Notice] = []
        if let raw = rawLugToLug, let value = lugToLugMM {
            if raw != value { notices.append(.lugToLugClamped(to: value)) }
        } else {
            notices.append(.missingLugToLug)
        }
        if let raw = rawDiameter, let value = diameterMM {
            if raw != value { notices.append(.diameterClamped(to: value)) }
        } else {
            notices.append(.missingDiameter)
        }
        if let candidate {
            notices.append(contentsOf: candidate.validationErrors.map(Notice.invalid))
        }
        return notices
    }

    /// 필수 값이 비었거나 검증 오류가 있으면 nil — 렌더링으로 진행하지 않는다
    var spec: WatchSpec? {
        guard let candidate, candidate.validationErrors.isEmpty else { return nil }
        return candidate
    }

    /// 범위 밖으로 입력한 숫자를 클램프한 값으로 바꿔 적는다
    mutating func commitClamping() {
        if let value = lugToLugMM { lugToLugText = value.mmText }
        if let value = diameterMM { diameterText = value.mmText }
    }

    private var candidate: WatchSpec? {
        guard let lugToLugMM, let diameterMM else { return nil }
        return WatchSpec(
            lugToLugMM: lugToLugMM,
            caseDiameterMM: diameterMM,
            caseShape: caseShape,
            lugWidthMM: lugWidthMM,
            bezelRatio: bezelRatio,
            dialColor: dialColor,
            thicknessMM: thicknessMM,
            crownSide: crownSide,
            strapColor: strapColor
        )
    }

    static func parse(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

extension Double {
    /// 48 → "48", 52.5 → "52.5"
    var mmText: String {
        let tenths = (self * 10).rounded()
        if tenths.truncatingRemainder(dividingBy: 10) == 0 {
            return String(Int(tenths / 10))
        }
        return String(format: "%.1f", tenths / 10)
    }
}
