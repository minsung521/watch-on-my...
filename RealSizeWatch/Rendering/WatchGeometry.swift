import Foundation
import SwiftUI

/// 스펙에서 실루엣을 만든다. 모든 좌표는 시계 중심 원점의 mm 단위, y는 아래(6시)가 +이다.
/// 12–6 축(L2L)은 화면 세로, 크라운은 화면 좌우로 놓인다. 아이폰을 손목 위에 가로질러 올리는 자세 기준이다.
struct WatchGeometry {
    let spec: WatchSpec

    var caseHalfWidth: Double { spec.diameter / 2 }

    var caseHalfHeight: Double {
        switch spec.shape {
        case .tonneau: min(spec.lugToLug / 2, spec.diameter / 2 * 1.2)
        default: spec.diameter / 2
        }
    }

    var lugTipY: Double { spec.lugToLug / 2 }
    var hasVisibleLugs: Bool { lugTipY > caseHalfHeight + 0.4 }
    var lugThickness: Double { min(3.4, max(1.8, spec.diameter * 0.065)) }
    var rimWidth: Double { 0.7 }
    var bezelWidth: Double { max(0.6, spec.bezelRatio * min(caseHalfWidth, caseHalfHeight)) }
    var dialInset: Double { rimWidth + bezelWidth }
    var dialHalfWidth: Double { max(caseHalfWidth - dialInset, 1) }
    var dialHalfHeight: Double { max(caseHalfHeight - dialInset, 1) }
    var crownProtrusion: Double { max(1.6, spec.diameter * 0.05) }
    var crownHeight: Double { max(3.6, spec.diameter * 0.13) }
    var hasBezelInsert: Bool { spec.bezelRatio >= 0.12 }
    /// 12–6 방향으로 시계가 차지하는 반길이
    var halfLength: Double { max(lugTipY, caseHalfHeight) }

    func casePath(inset: Double = 0) -> Path {
        let hw = max(caseHalfWidth - inset, 0.5)
        let hh = max(caseHalfHeight - inset, 0.5)
        switch spec.shape {
        case .round:
            return Path(ellipseIn: CGRect(x: -hw, y: -hh, width: hw * 2, height: hh * 2))
        case .square:
            return Path(
                roundedRect: CGRect(x: -hw, y: -hh, width: hw * 2, height: hh * 2),
                cornerRadius: min(hw, hh) * 0.28,
                style: .continuous
            )
        case .cushion:
            return Self.superellipse(halfWidth: hw, halfHeight: hh, exponent: 4, pinch: 0)
        case .tonneau:
            return Self.superellipse(halfWidth: hw, halfHeight: hh, exponent: 4.5, pinch: 0.2)
        }
    }

    var lugsPath: Path {
        guard hasVisibleLugs else { return Path() }
        let inner = spec.lugWidth / 2 + 0.3
        let root = caseHalfHeight * 0.5
        let lug = Path(
            roundedRect: CGRect(x: inner, y: root, width: lugThickness, height: lugTipY - root),
            cornerRadius: lugThickness / 2,
            style: .continuous
        )
        var lugs = Path()
        for sx in [-1.0, 1.0] {
            for sy in [-1.0, 1.0] {
                lugs.addPath(lug, transform: CGAffineTransform(scaleX: sx, y: sy))
            }
        }
        return lugs
    }

    func crownPath(side: CrownSide) -> Path {
        let inner = caseHalfWidth - 0.5
        let rect = CGRect(x: inner, y: -crownHeight / 2, width: crownProtrusion + 0.5, height: crownHeight)
        let path = Path(roundedRect: rect, cornerRadius: 0.6, style: .continuous)
        return side == .right ? path : path.applying(CGAffineTransform(scaleX: -1, y: 1))
    }

    func crownGripPath(side: CrownSide) -> Path {
        var path = Path()
        let start = caseHalfWidth + 0.2
        let end = caseHalfWidth + crownProtrusion - 0.2
        var y = -crownHeight / 2 + 0.5
        while y < crownHeight / 2 - 0.3 {
            path.move(to: CGPoint(x: start, y: y))
            path.addLine(to: CGPoint(x: end, y: y))
            y += 0.55
        }
        return side == .right ? path : path.applying(CGAffineTransform(scaleX: -1, y: 1))
    }

    /// 러그에서 손목 실루엣 가장자리까지 뻗으며 좁아지는 띠 두 개 (미확정 사항 결정 4)
    func strapPath(toWristEdge edge: Double) -> Path {
        let start = caseHalfHeight * 0.6
        guard edge > start else { return Path() }
        let startHalf = spec.lugWidth / 2
        let endHalf = spec.lugWidth * 0.86 / 2
        var path = Path()
        for sy in [-1.0, 1.0] {
            path.move(to: CGPoint(x: -startHalf, y: sy * start))
            path.addLine(to: CGPoint(x: startHalf, y: sy * start))
            path.addLine(to: CGPoint(x: endHalf, y: sy * edge))
            path.addLine(to: CGPoint(x: -endHalf, y: sy * edge))
            path.closeSubpath()
        }
        return path
    }

    /// 다이얼 인덱스 위치. 사각·쿠션도 내접 타원 위에 둔다.
    func markerPositions(radiusFactor: Double = 0.82) -> [(angle: Double, point: CGPoint)] {
        (0..<12).map { hour in
            let angle = Double(hour) / 12 * 2 * Double.pi
            let point = CGPoint(
                x: dialHalfWidth * radiusFactor * sin(angle),
                y: -dialHalfHeight * radiusFactor * cos(angle)
            )
            return (angle, point)
        }
    }

    private static func superellipse(halfWidth: Double, halfHeight: Double, exponent n: Double, pinch: Double) -> Path {
        var path = Path()
        let steps = 160
        for i in 0..<steps {
            let t = Double(i) / Double(steps) * 2 * Double.pi
            let c = cos(t)
            let s = sin(t)
            let ux = copysign(pow(abs(c), 2 / n), c)
            let uy = copysign(pow(abs(s), 2 / n), s)
            let point = CGPoint(x: ux * halfWidth * (1 - pinch * uy * uy), y: uy * halfHeight)
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}
