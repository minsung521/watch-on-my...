import SwiftUI

/// 3시 방향에서 본 측면도. 두께(thicknessMM)는 여기서만 쓴다 (00 5절)
struct SideProfileView: View {
    let spec: WatchSpec
    let scale: PhysicalScale
    let wristWidthMM: Double
    let skin: RGB

    var body: some View {
        GeometryReader { proxy in
            let natural = CGFloat(scale.points(fromMM: 1))
            let fitWidth = (proxy.size.width - 16) / CGFloat(spec.lugToLugMM + 8)
            let fitHeight = (proxy.size.height - 28) / CGFloat(spec.thicknessMM + 8)
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
                Text("두께 \(spec.thicknessMM.mmText)mm")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, k: CGFloat) {
        let geometry = CaseGeometry(spec: spec)
        let origin = CGPoint(x: size.width / 2, y: size.height - 10)
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: origin.x + CGFloat(x) * k, y: origin.y + CGFloat(y) * k)
        }

        // 손목 윗면: 폭:두께 1.35 타원의 윗부분
        let a = wristWidthMM / 2
        let b = a / 1.35
        func surfaceY(_ x: Double) -> Double {
            let ratio = min(abs(x) / a, 1)
            return b - b * (1 - ratio * ratio).squareRoot()
        }
        let span = min(a, Double(size.width / 2 / k))
        var wrist = Path()
        wrist.move(to: p(-span, surfaceY(span)))
        stride(from: -span, through: span, by: 0.5).forEach { wrist.addLine(to: p($0, surfaceY($0))) }
        wrist.addLine(to: CGPoint(x: origin.x + CGFloat(span) * k, y: size.height))
        wrist.addLine(to: CGPoint(x: origin.x - CGFloat(span) * k, y: size.height))
        wrist.closeSubpath()
        context.fill(wrist, with: .color(skin.color.opacity(0.55)))

        let t = spec.thicknessMM
        let steel = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [RGB(hex: 0xE6E8EB).color, RGB(hex: 0x9AA0A8).color]),
            startPoint: p(0, -t),
            endPoint: p(0, 0)
        )
        if geometry.hasVisibleLugs {
            for sx in [-1.0, 1.0] {
                var lug = Path()
                let tipX = sx * geometry.lugTipY
                lug.move(to: p(sx * geometry.halfLength * 0.9, -t * 0.55))
                lug.addQuadCurve(
                    to: p(tipX, surfaceY(tipX) - 0.8),
                    control: p(sx * (geometry.halfLength + (geometry.lugTipY - geometry.halfLength) * 0.55), -t * 0.55)
                )
                context.stroke(lug, with: .color(RGB(hex: 0x9AA0A8).color), style: StrokeStyle(lineWidth: 2.2 * k, lineCap: .round))
            }
        }
        let body = Path(
            roundedRect: CGRect(x: origin.x - CGFloat(geometry.halfLength) * k, y: origin.y - CGFloat(t * 0.72) * k,
                                width: CGFloat(geometry.halfLength * 2) * k, height: CGFloat(t * 0.72) * k),
            cornerRadius: 1.2 * k
        )
        context.fill(body, with: steel)
        let crystalHalf = geometry.halfLength * geometry.dialScale
        let crystal = Path(
            roundedRect: CGRect(x: origin.x - CGFloat(crystalHalf) * k, y: origin.y - CGFloat(t) * k,
                                width: CGFloat(crystalHalf * 2) * k, height: CGFloat(t * 0.3) * k),
            cornerRadius: CGFloat(t * 0.12) * k
        )
        context.fill(crystal, with: .color(RGB(hex: 0xB5BAC1).color))
    }
}
