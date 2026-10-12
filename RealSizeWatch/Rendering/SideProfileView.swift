import SwiftUI

/// 3시 방향에서 본 측면. 두께를 2D 한계 안에서 근사하고, 손목 곡률 위에 러그가 어떻게 걸치는지 보여준다 (MIN-46).
struct SideProfileView: View {
    let spec: WatchSpec
    let mmPerPoint: Double
    let wristWidthMM: Double
    let skin: RGB

    var body: some View {
        GeometryReader { proxy in
            let natural = CGFloat(1 / mmPerPoint)
            let fitWidth = (proxy.size.width - 16) / CGFloat(spec.lugToLug + 8)
            let fitHeight = (proxy.size.height - 28) / CGFloat(spec.thickness + 8)
            let k = min(natural, fitWidth, fitHeight)
            Canvas { context, size in
                draw(in: &context, size: size, k: k)
            }
            .overlay(alignment: .topLeading) {
                Text(k >= natural - 0.001 ? "실제 크기" : "축소 \(Int((k / natural * 100).rounded()))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .overlay(alignment: .topTrailing) {
                Text("두께 \(spec.thickness.mmText)mm")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, k: CGFloat) {
        let geometry = WatchGeometry(spec: spec)
        let baseY = size.height - 10
        let origin = CGPoint(x: size.width / 2, y: baseY)
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: origin.x + CGFloat(x) * k, y: origin.y + CGFloat(y) * k)
        }

        // 손목 윗면: 폭:두께 1.35 타원의 윗부분
        let a = wristWidthMM / 2
        let b = a / WristGeometry.widthToThickness
        func surfaceY(_ x: Double) -> Double {
            let ratio = min(abs(x) / a, 1)
            return b - b * (1 - ratio * ratio).squareRoot()
        }
        var wrist = Path()
        let span = min(a, Double(size.width / 2 / k))
        wrist.move(to: p(-span, surfaceY(span)))
        stride(from: -span, through: span, by: 0.5).forEach { wrist.addLine(to: p($0, surfaceY($0))) }
        wrist.addLine(to: CGPoint(x: origin.x + CGFloat(span) * k, y: size.height))
        wrist.addLine(to: CGPoint(x: origin.x - CGFloat(span) * k, y: size.height))
        wrist.closeSubpath()
        context.fill(wrist, with: .color(skin.color.opacity(0.55)))

        let t = spec.thickness
        let steel = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [Palette.steelLight, Palette.steelDark]),
            startPoint: p(0, -t),
            endPoint: p(0, 0)
        )

        if geometry.hasVisibleLugs {
            for sx in [-1.0, 1.0] {
                var lug = Path()
                let tipX = sx * geometry.lugTipY
                lug.move(to: p(sx * geometry.caseHalfHeight * 0.9, -t * 0.55))
                lug.addQuadCurve(
                    to: p(tipX, surfaceY(tipX) - 0.8),
                    control: p(sx * (geometry.caseHalfHeight + (geometry.lugTipY - geometry.caseHalfHeight) * 0.55), -t * 0.55)
                )
                context.stroke(lug, with: .color(Palette.steelDark), style: StrokeStyle(lineWidth: 2.2 * k, lineCap: .round))
            }
        }

        let body = Path(
            roundedRect: CGRect(
                x: origin.x - CGFloat(geometry.caseHalfHeight) * k,
                y: origin.y - CGFloat(t * 0.72) * k,
                width: CGFloat(geometry.caseHalfHeight * 2) * k,
                height: CGFloat(t * 0.72) * k
            ),
            cornerRadius: 1.2 * k
        )
        context.fill(body, with: steel)
        context.stroke(body, with: .color(Palette.steelEdge), lineWidth: 0.5)

        let crystalHalf = geometry.caseHalfHeight - geometry.dialInset * 0.6
        let crystal = Path(
            roundedRect: CGRect(
                x: origin.x - CGFloat(crystalHalf) * k,
                y: origin.y - CGFloat(t) * k,
                width: CGFloat(crystalHalf * 2) * k,
                height: CGFloat(t * 0.3) * k
            ),
            cornerRadius: CGFloat(t * 0.12) * k
        )
        context.fill(crystal, with: .color(Palette.polishedDark))
        context.stroke(crystal, with: .color(Palette.steelEdge), lineWidth: 0.5)

        let crownRadius = min(geometry.crownHeight / 2, t * 0.32)
        let crown = Path(ellipseIn: CGRect(
            x: origin.x - CGFloat(crownRadius) * k,
            y: origin.y - CGFloat(t * 0.4 + crownRadius) * k,
            width: CGFloat(crownRadius * 2) * k,
            height: CGFloat(crownRadius * 2) * k
        ))
        context.fill(crown, with: .color(Palette.steelLight))
        context.stroke(crown, with: .color(Palette.steelEdge), lineWidth: 0.5)
    }
}
