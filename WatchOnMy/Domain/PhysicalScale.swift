import Foundation

/// 실제 PPI가 같은 기기 묶음. 모델이 아니라 이 4개 그룹 단위로 관리한다 (01 3-2).
enum DisplayGroup: String, Codable, CaseIterable, Sendable {
    case lcd2x
    case oled476mini
    case oled3x458
    case oled3x460

    var ppi: Double {
        switch self {
        case .lcd2x: 326
        case .oled476mini: 476
        case .oled3x458: 458
        case .oled3x460: 460
        }
    }

    var label: String {
        switch self {
        case .lcd2x: "326ppi @2x LCD"
        case .oled476mini: "476ppi mini"
        case .oled3x458: "458ppi"
        case .oled3x460: "460ppi"
        }
    }
}

struct DeviceModel: Equatable, Sendable {
    let name: String
    let group: DisplayGroup
}

/// 기기 identifier → PPI 그룹. Apple 공식 PPI를 Xcode 시뮬레이터 기기 프로필과 교차 확인했다.
enum DeviceScaleTable {
    static let fallbackGroup = DisplayGroup.oled3x460

    static let models: [String: DeviceModel] = [
        "iPhone11,2": DeviceModel(name: "iPhone XS", group: .oled3x458),
        "iPhone11,4": DeviceModel(name: "iPhone XS Max", group: .oled3x458),
        "iPhone11,6": DeviceModel(name: "iPhone XS Max", group: .oled3x458),
        "iPhone11,8": DeviceModel(name: "iPhone XR", group: .lcd2x),
        "iPhone12,1": DeviceModel(name: "iPhone 11", group: .lcd2x),
        "iPhone12,3": DeviceModel(name: "iPhone 11 Pro", group: .oled3x458),
        "iPhone12,5": DeviceModel(name: "iPhone 11 Pro Max", group: .oled3x458),
        "iPhone12,8": DeviceModel(name: "iPhone SE (2세대)", group: .lcd2x),
        "iPhone13,1": DeviceModel(name: "iPhone 12 mini", group: .oled476mini),
        "iPhone13,2": DeviceModel(name: "iPhone 12", group: .oled3x460),
        "iPhone13,3": DeviceModel(name: "iPhone 12 Pro", group: .oled3x460),
        "iPhone13,4": DeviceModel(name: "iPhone 12 Pro Max", group: .oled3x458),
        "iPhone14,2": DeviceModel(name: "iPhone 13 Pro", group: .oled3x460),
        "iPhone14,3": DeviceModel(name: "iPhone 13 Pro Max", group: .oled3x458),
        "iPhone14,4": DeviceModel(name: "iPhone 13 mini", group: .oled476mini),
        "iPhone14,5": DeviceModel(name: "iPhone 13", group: .oled3x460),
        "iPhone14,6": DeviceModel(name: "iPhone SE (3세대)", group: .lcd2x),
        "iPhone14,7": DeviceModel(name: "iPhone 14", group: .oled3x460),
        "iPhone14,8": DeviceModel(name: "iPhone 14 Plus", group: .oled3x458),
        "iPhone15,2": DeviceModel(name: "iPhone 14 Pro", group: .oled3x460),
        "iPhone15,3": DeviceModel(name: "iPhone 14 Pro Max", group: .oled3x460),
        "iPhone15,4": DeviceModel(name: "iPhone 15", group: .oled3x460),
        "iPhone15,5": DeviceModel(name: "iPhone 15 Plus", group: .oled3x460),
        "iPhone16,1": DeviceModel(name: "iPhone 15 Pro", group: .oled3x460),
        "iPhone16,2": DeviceModel(name: "iPhone 15 Pro Max", group: .oled3x460),
        "iPhone17,1": DeviceModel(name: "iPhone 16 Pro", group: .oled3x460),
        "iPhone17,2": DeviceModel(name: "iPhone 16 Pro Max", group: .oled3x460),
        "iPhone17,3": DeviceModel(name: "iPhone 16", group: .oled3x460),
        "iPhone17,4": DeviceModel(name: "iPhone 16 Plus", group: .oled3x460),
        "iPhone17,5": DeviceModel(name: "iPhone 16e", group: .oled3x460),
        "iPhone18,1": DeviceModel(name: "iPhone 17 Pro", group: .oled3x460),
        "iPhone18,2": DeviceModel(name: "iPhone 17 Pro Max", group: .oled3x460),
        "iPhone18,3": DeviceModel(name: "iPhone 17", group: .oled3x460),
        "iPhone18,4": DeviceModel(name: "iPhone Air", group: .oled3x460),
        "iPhone18,5": DeviceModel(name: "iPhone 17e", group: .oled3x460),
    ]

    static func model(for identifier: String) -> DeviceModel? {
        models[identifier]
    }
}

struct DeviceInfo: Equatable, Sendable {
    let identifier: String
    /// 물리 픽셀/pt. mini는 UI를 3x로 그린 뒤 2.88x로 축소 출력하므로 `scale`이 아니라 이 값을 쓴다 (01 3-2 정정).
    let nativeScale: Double
    let isSimulator: Bool

    var model: DeviceModel? { DeviceScaleTable.model(for: identifier) }
}

/// 사용자가 카드에 맞춘 값. 디스플레이 확대로 nativeScale이 바뀌어도 유지되도록 물리 픽셀당 mm로 저장하고 기기에 묶는다.
struct CardCalibration: Codable, Equatable, Sendable {
    var mmPerPixel: Double
    var deviceIdentifier: String
}

/// 앱의 모든 mm ↔ pt 변환은 이 타입 하나를 거친다 (00 4절).
struct PhysicalScale: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case deviceTable(identifier: String)
        /// 미등록 기기: 가장 흔한 그룹을 잠정 적용. 앱을 막지 않고 카드 보정을 권한다 (01 3-3)
        case provisional
        case cardCalibration
    }

    let mmPerPoint: Double
    let source: Source

    func points(fromMM mm: Double) -> Double {
        mm / mmPerPoint
    }

    func mm(fromPoints points: Double) -> Double {
        points * mmPerPoint
    }

    var isVerified: Bool { source != .provisional }

    static func mmPerPoint(ppi: Double, nativeScale: Double) -> Double {
        25.4 * nativeScale / ppi
    }

    static func resolve(device: DeviceInfo, card: CardCalibration?) -> PhysicalScale {
        if let card, card.deviceIdentifier == device.identifier {
            return PhysicalScale(mmPerPoint: card.mmPerPixel * device.nativeScale, source: .cardCalibration)
        }
        if let model = device.model {
            return PhysicalScale(
                mmPerPoint: mmPerPoint(ppi: model.group.ppi, nativeScale: device.nativeScale),
                source: .deviceTable(identifier: device.identifier)
            )
        }
        return PhysicalScale(
            mmPerPoint: mmPerPoint(ppi: DeviceScaleTable.fallbackGroup.ppi, nativeScale: device.nativeScale),
            source: .provisional
        )
    }

    /// 카드 긴 변(85.60mm)을 화면 세로 `matchedLongSidePoints`에 맞췄을 때 (01 4-2)
    static func cardMMPerPoint(matchedLongSidePoints: Double) -> Double {
        Constants.cardWidthMM / matchedLongSidePoints
    }

    static func card(matchedLongSidePoints: Double, device: DeviceInfo) -> CardCalibration {
        CardCalibration(
            mmPerPixel: cardMMPerPoint(matchedLongSidePoints: matchedLongSidePoints) / device.nativeScale,
            deviceIdentifier: device.identifier
        )
    }

    var sourceDescription: String {
        switch source {
        case .deviceTable(let identifier):
            "기기 표 · \(DeviceScaleTable.model(for: identifier)?.group.label ?? identifier)"
        case .provisional:
            "미검증 기기 · \(DeviceScaleTable.fallbackGroup.label)로 가정"
        case .cardCalibration:
            "신용카드 보정값"
        }
    }
}
