import Foundation

enum CaseShape: String, Codable, CaseIterable, Identifiable, Sendable {
    case round
    case cushion
    /// 기획서의 "텐구"는 토노(tonneau)의 오기 (작업지시서 변경 7건)
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
}

enum DialColor: String, Codable, CaseIterable, Identifiable, Sendable {
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

    /// 베젤 인서트 색 (베젤 비율이 큰 다이버형에서만 쓴다)
    var insertRGB: RGB {
        switch self {
        case .blue: RGB(hex: 0x16284A)
        case .green: RGB(hex: 0x163628)
        case .champagne: RGB(hex: 0x3A3126)
        default: RGB(hex: 0x111214)
        }
    }
}

/// 스트랩은 단색 3~4종으로 제한한다 (미확정 사항 결정 4)
enum StrapColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case black, brown, navy, tan

    var id: String { rawValue }

    var label: String {
        switch self {
        case .black: "블랙"
        case .brown: "브라운"
        case .navy: "네이비"
        case .tan: "탄"
        }
    }

    var rgb: RGB {
        switch self {
        case .black: RGB(hex: 0x1B1B1D)
        case .brown: RGB(hex: 0x5B3A24)
        case .navy: RGB(hex: 0x1D2840)
        case .tan: RGB(hex: 0xA9794B)
        }
    }
}

/// 좌우 손 구분은 크라운 위치에만 영향을 준다. 토글 하나, 기본 오른쪽 (미확정 사항 결정 3)
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

struct WatchSpec: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    /// 1순위 지표 (mm)
    var lugToLug: Double
    /// 보조 지표 (mm). 토노는 가로 폭
    var diameter: Double
    var shape: CaseShape = .round
    var lugWidth: Double = 20
    /// 케이스 반경 대비 베젤 두께
    var bezelRatio: Double = 0.08
    var dialColor: DialColor = .black
    var thickness: Double = 11
    var strapColor: StrapColor = .black

    var dimensionSummary: String {
        "Ø\(diameter.mmText) · L2L \(lugToLug.mmText) · 러그 \(lugWidth.mmText)mm"
    }
}

extension WatchSpec {
    /// 브랜드 없는 제너릭 예시. 42/47과 42/52.5는 MIN-46 완료 기준의 비교 쌍이다.
    static var samples: [WatchSpec] {
        [
            WatchSpec(name: "기준 실루엣 40/48", lugToLug: 48, diameter: 40, lugWidth: 20, bezelRatio: 0.1, dialColor: .black, thickness: 11, strapColor: .black),
            WatchSpec(name: "드레스 36", lugToLug: 43, diameter: 36, lugWidth: 18, bezelRatio: 0.03, dialColor: .white, thickness: 8.5, strapColor: .brown),
            WatchSpec(name: "다이버 42 숏러그", lugToLug: 47, diameter: 42, lugWidth: 20, bezelRatio: 0.2, dialColor: .black, thickness: 13, strapColor: .black),
            WatchSpec(name: "파일럿 42 롱러그", lugToLug: 52.5, diameter: 42, lugWidth: 22, bezelRatio: 0.04, dialColor: .black, thickness: 12, strapColor: .brown),
            WatchSpec(name: "쿠션 44", lugToLug: 50, diameter: 44, shape: .cushion, lugWidth: 22, bezelRatio: 0.12, dialColor: .blue, thickness: 14, strapColor: .navy),
            WatchSpec(name: "사각 34", lugToLug: 42, diameter: 34, shape: .square, lugWidth: 20, bezelRatio: 0.06, dialColor: .silver, thickness: 9, strapColor: .black),
            WatchSpec(name: "토노 40", lugToLug: 48, diameter: 40, shape: .tonneau, lugWidth: 20, bezelRatio: 0.05, dialColor: .champagne, thickness: 11, strapColor: .tan),
        ]
    }
}

/// 입력 폼의 편집 상태. 필수 값(L2L, 직경)이 비어 있거나 잘못되면 `spec`이 nil이라 렌더링으로 넘어가지 않는다 (MIN-47).
struct WatchDraft: Equatable {
    enum Issue: Equatable, Hashable {
        case missingLugToLug
        case missingDiameter
        case lugToLugOutOfRange
        case diameterOutOfRange
        case lugToLugShorterThanCase
        case lugWidthTooWide

        var message: String {
            switch self {
            case .missingLugToLug: "러그 투 러그(L2L)는 필수 값입니다."
            case .missingDiameter: "케이스 직경은 필수 값입니다."
            case .lugToLugOutOfRange: "L2L은 25~70mm 사이로 입력하세요."
            case .diameterOutOfRange: "직경은 20~60mm 사이로 입력하세요."
            case .lugToLugShorterThanCase: "L2L은 케이스 직경보다 짧을 수 없습니다."
            case .lugWidthTooWide: "러그 폭이 케이스에 비해 너무 넓습니다."
            }
        }
    }

    static let lugToLugRange: ClosedRange<Double> = 25...70
    static let diameterRange: ClosedRange<Double> = 20...60

    var id: UUID
    var isNew: Bool
    var name: String
    var lugToLugText: String
    var diameterText: String
    var shape: CaseShape
    var lugWidth: Double
    var bezelRatio: Double
    var dialColor: DialColor
    var thickness: Double
    var strapColor: StrapColor

    init(spec: WatchSpec) {
        id = spec.id
        isNew = false
        name = spec.name
        lugToLugText = spec.lugToLug.mmText
        diameterText = spec.diameter.mmText
        shape = spec.shape
        lugWidth = spec.lugWidth
        bezelRatio = spec.bezelRatio
        dialColor = spec.dialColor
        thickness = spec.thickness
        strapColor = spec.strapColor
    }

    static func blank() -> WatchDraft {
        var draft = WatchDraft(spec: WatchSpec(name: "", lugToLug: 0, diameter: 0))
        draft.id = UUID()
        draft.isNew = true
        draft.lugToLugText = ""
        draft.diameterText = ""
        return draft
    }

    var lugToLug: Double? { Self.parse(lugToLugText) }
    var diameter: Double? { Self.parse(diameterText) }

    var issues: [Issue] {
        var issues: [Issue] = []
        let l2l = lugToLug
        let d = diameter
        if l2l == nil {
            issues.append(.missingLugToLug)
        } else if let l2l, !Self.lugToLugRange.contains(l2l) {
            issues.append(.lugToLugOutOfRange)
        }
        if d == nil {
            issues.append(.missingDiameter)
        } else if let d, !Self.diameterRange.contains(d) {
            issues.append(.diameterOutOfRange)
        }
        if let l2l, let d, Self.lugToLugRange.contains(l2l), Self.diameterRange.contains(d) {
            if l2l < d { issues.append(.lugToLugShorterThanCase) }
            if lugWidth > d * 0.8 { issues.append(.lugWidthTooWide) }
        }
        return issues
    }

    var spec: WatchSpec? {
        guard issues.isEmpty, let l2l = lugToLug, let d = diameter else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return WatchSpec(
            id: id,
            name: trimmed.isEmpty ? "\(shape.label) \(d.mmText)/\(l2l.mmText)" : trimmed,
            lugToLug: l2l,
            diameter: d,
            shape: shape,
            lugWidth: lugWidth,
            bezelRatio: bezelRatio,
            dialColor: dialColor,
            thickness: thickness,
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
}
