import CoreGraphics
import Foundation

/// 실제 PPI가 같은 기기 묶음. 모델이 아니라 이 네 그룹 단위로 관리하고, 신규 모델은 그룹에 편입만 한다 (MIN-44).
enum DisplayGroup: String, Codable, CaseIterable, Sendable {
    case lcd326
    case oled476
    case oled458
    case oled460

    var ppi: Double {
        switch self {
        case .lcd326: 326
        case .oled476: 476
        case .oled458: 458
        case .oled460: 460
        }
    }

    var label: String {
        switch self {
        case .lcd326: "326ppi @2x LCD"
        case .oled476: "476ppi mini"
        case .oled458: "458ppi"
        case .oled460: "460ppi"
        }
    }
}

struct DeviceModel: Equatable, Sendable {
    let name: String
    let group: DisplayGroup
}

enum DeviceCatalog {
    /// Apple 공식 PPI. Xcode 26.6 시뮬레이터 기기 프로필의 mainScreenWidthDPI와 교차 확인했다.
    /// iOS 17 미만 전용 기기(X 이전)는 넣지 않는다.
    static let models: [String: DeviceModel] = [
        "iPhone11,2": DeviceModel(name: "iPhone XS", group: .oled458),
        "iPhone11,4": DeviceModel(name: "iPhone XS Max", group: .oled458),
        "iPhone11,6": DeviceModel(name: "iPhone XS Max", group: .oled458),
        "iPhone11,8": DeviceModel(name: "iPhone XR", group: .lcd326),
        "iPhone12,1": DeviceModel(name: "iPhone 11", group: .lcd326),
        "iPhone12,3": DeviceModel(name: "iPhone 11 Pro", group: .oled458),
        "iPhone12,5": DeviceModel(name: "iPhone 11 Pro Max", group: .oled458),
        "iPhone12,8": DeviceModel(name: "iPhone SE (2세대)", group: .lcd326),
        "iPhone13,1": DeviceModel(name: "iPhone 12 mini", group: .oled476),
        "iPhone13,2": DeviceModel(name: "iPhone 12", group: .oled460),
        "iPhone13,3": DeviceModel(name: "iPhone 12 Pro", group: .oled460),
        "iPhone13,4": DeviceModel(name: "iPhone 12 Pro Max", group: .oled458),
        "iPhone14,2": DeviceModel(name: "iPhone 13 Pro", group: .oled460),
        "iPhone14,3": DeviceModel(name: "iPhone 13 Pro Max", group: .oled458),
        "iPhone14,4": DeviceModel(name: "iPhone 13 mini", group: .oled476),
        "iPhone14,5": DeviceModel(name: "iPhone 13", group: .oled460),
        "iPhone14,6": DeviceModel(name: "iPhone SE (3세대)", group: .lcd326),
        "iPhone14,7": DeviceModel(name: "iPhone 14", group: .oled460),
        "iPhone14,8": DeviceModel(name: "iPhone 14 Plus", group: .oled458),
        "iPhone15,2": DeviceModel(name: "iPhone 14 Pro", group: .oled460),
        "iPhone15,3": DeviceModel(name: "iPhone 14 Pro Max", group: .oled460),
        "iPhone15,4": DeviceModel(name: "iPhone 15", group: .oled460),
        "iPhone15,5": DeviceModel(name: "iPhone 15 Plus", group: .oled460),
        "iPhone16,1": DeviceModel(name: "iPhone 15 Pro", group: .oled460),
        "iPhone16,2": DeviceModel(name: "iPhone 15 Pro Max", group: .oled460),
        "iPhone17,1": DeviceModel(name: "iPhone 16 Pro", group: .oled460),
        "iPhone17,2": DeviceModel(name: "iPhone 16 Pro Max", group: .oled460),
        "iPhone17,3": DeviceModel(name: "iPhone 16", group: .oled460),
        "iPhone17,4": DeviceModel(name: "iPhone 16 Plus", group: .oled460),
        "iPhone17,5": DeviceModel(name: "iPhone 16e", group: .oled460),
        "iPhone18,1": DeviceModel(name: "iPhone 17 Pro", group: .oled460),
        "iPhone18,2": DeviceModel(name: "iPhone 17 Pro Max", group: .oled460),
        "iPhone18,3": DeviceModel(name: "iPhone 17", group: .oled460),
        "iPhone18,4": DeviceModel(name: "iPhone Air", group: .oled460),
        "iPhone18,5": DeviceModel(name: "iPhone 17e", group: .oled460),
    ]

    /// 미등록 기기는 가장 흔한 그룹으로 가정하고 카드 보정을 권한다. 앱을 막지 않는다.
    static let provisionalGroup = DisplayGroup.oled460

    static func model(for identifier: String) -> DeviceModel? {
        models[identifier]
    }
}

/// ISO/IEC 7810 ID-1 카드. 화면 폭이 85.6mm보다 좁으므로 세로로 세워 쓴다.
enum IDCard {
    static let widthMM = 53.98
    static let heightMM = 85.60
    static let cornerRadiusMM = 3.18
}

struct PhysicalScale: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case deviceTable(DisplayGroup)
        case provisional
        case card
    }

    let mmPerPoint: Double
    let source: Source

    var pointsPerMM: Double { 1 / mmPerPoint }

    func points(_ mm: Double) -> CGFloat {
        CGFloat(mm / mmPerPoint)
    }

    func millimeters(_ points: CGFloat) -> Double {
        Double(points) * mmPerPoint
    }

    /// 물리 픽셀/pt는 `scale`이 아니라 `nativeScale`이다.
    /// 12·13 mini는 3x(1125px)로 그린 뒤 물리 1080px로 다운샘플링하므로 nativeScale이 2.88이다.
    static func mmPerPoint(ppi: Double, nativeScale: Double) -> Double {
        25.4 * nativeScale / ppi
    }

    static func resolve(device: DeviceInfo, cardMMPerPixel: Double?, ignoreTable: Bool) -> PhysicalScale {
        if let cardMMPerPixel {
            return PhysicalScale(mmPerPoint: cardMMPerPixel * device.nativeScale, source: .card)
        }
        if !ignoreTable, let model = DeviceCatalog.model(for: device.identifier) {
            return PhysicalScale(
                mmPerPoint: mmPerPoint(ppi: model.group.ppi, nativeScale: device.nativeScale),
                source: .deviceTable(model.group)
            )
        }
        return PhysicalScale(
            mmPerPoint: mmPerPoint(ppi: DeviceCatalog.provisionalGroup.ppi, nativeScale: device.nativeScale),
            source: .provisional
        )
    }

    /// 카드 세로 85.60mm를 화면 위 `matchedHeightPoints`에 맞췄을 때의 물리 픽셀당 mm.
    /// 디스플레이 확대/축소로 nativeScale이 바뀌어도 유지되도록 pt가 아니라 픽셀 단위로 저장한다.
    static func cardMMPerPixel(matchedHeightPoints: CGFloat, nativeScale: Double) -> Double {
        IDCard.heightMM / Double(matchedHeightPoints) / nativeScale
    }

    var sourceDescription: String {
        switch source {
        case .deviceTable(let group): "기기 표 · \(group.label)"
        case .provisional: "미등록 기기 · \(DeviceCatalog.provisionalGroup.label)로 가정"
        case .card: "신용카드 보정값"
        }
    }
}
