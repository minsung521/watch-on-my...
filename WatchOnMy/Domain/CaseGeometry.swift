import CoreGraphics
import Foundation

/// 파라메트릭 시계의 기하 (02 4절). 좌표는 시계 중심 원점의 mm, x는 오른쪽(크라운·직경 방향), y는 아래(L2L 방향)가 +.
struct CaseGeometry: Equatable {
    let spec: WatchSpec

    var exponent: Double { spec.caseShape.geometry.exponent }
    var halfWidth: Double { spec.caseDiameterMM / 2 }
    var halfLength: Double { spec.caseLengthMM / 2 }
    var lugTipY: Double { spec.lugToLugMM / 2 }
    var hasVisibleLugs: Bool { lugTipY > halfLength + 0.3 }
    /// 다이얼 경계 = 케이스 외곽을 이 비율로 축소
    var dialScale: Double { max(1 - 2 * spec.bezelRatio, 0.1) }

    /// 케이스 외곽 (factor로 축소하면 다이얼 경계)
    func outline(factor: Double = 1, steps: Int = 240) -> [CGPoint] {
        (0..<steps).map { index in
            let t = Double(index) / Double(steps) * 2 * Double.pi
            let c = cos(t)
            let s = sin(t)
            return CGPoint(
                x: halfWidth * factor * copysign(pow(abs(c), 2 / exponent), c),
                y: halfLength * factor * copysign(pow(abs(s), 2 / exponent), s)
            )
        }
    }

    /// 세로축에서 angle만큼 기운 방향으로 중심에서 외곽까지의 거리
    func radius(fromVerticalDegrees angle: Double) -> Double {
        let radians = angle * Double.pi / 180
        let x = sin(radians) / halfWidth
        let y = cos(radians) / halfLength
        return 1 / pow(pow(abs(x), exponent) + pow(abs(y), exponent), 1 / exponent)
    }

    /// 오른쪽 아래 러그 하나. 나머지 셋은 좌우·상하 대칭
    var lug: LugGeometry? {
        guard hasVisibleLugs else { return nil }
        let innerX = spec.lugWidthMM / 2
        let angle = Constants.lugOuterStartAngleDegrees * Double.pi / 180
        let r = radius(fromVerticalDegrees: Constants.lugOuterStartAngleDegrees)
        let startX = max(r * sin(angle), innerX + Constants.minimumLugThicknessMM)
        let start = CGPoint(x: startX, y: r * cos(angle))
        let tipOuterX = innerX + (startX - innerX) * Constants.lugTipTaper
        let tipRadius = min(Constants.lugTipRadiusMM, (tipOuterX - innerX) / 2)
        return LugGeometry(innerX: innerX, start: start, tipY: lugTipY, tipOuterX: tipOuterX, tipRadius: tipRadius)
    }

    /// 3시 방향(가로축) 케이스 옆면, y = 0
    func crownRect(side: CrownSide) -> CGRect {
        let inset = 0.4
        let x = side == .right ? halfWidth - inset : -halfWidth - Constants.crownWidthMM
        return CGRect(x: x, y: -Constants.crownHeightMM / 2, width: Constants.crownWidthMM + inset, height: Constants.crownHeightMM)
    }
}

struct LugGeometry: Equatable {
    let innerX: Double
    let start: CGPoint
    let tipY: Double
    let tipOuterX: Double
    let tipRadius: Double
}

/// 스트랩은 케이스 아래(러그 사이)에서 시작해 러그 끝부터 손목 띠 가장자리까지 좁아진다 (02 5절)
enum StrapGeometry {
    /// 아래쪽 스트랩의 오른쪽 절반 윤곽 (x ≥ 0). 위쪽·왼쪽은 대칭
    static func halfOutline(widthMM: Double, startY: Double, lugTipY: Double, edgeY: Double) -> [CGPoint]? {
        guard edgeY > startY else { return nil }
        let half = widthMM / 2
        let tipY = min(max(lugTipY, startY), edgeY)
        let endHalf = half * (edgeY > lugTipY ? Constants.strapEndTaper : 1)
        return [
            CGPoint(x: 0, y: startY),
            CGPoint(x: half, y: startY),
            CGPoint(x: half, y: tipY),
            CGPoint(x: endHalf, y: edgeY),
            CGPoint(x: 0, y: edgeY),
        ]
    }
}
