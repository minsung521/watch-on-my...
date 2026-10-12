import SwiftUI

/// 캔버스에 그릴 장면. 손목 캔버스는 시스템 외관(다크 모드)을 무시하고 항상 이 값으로 칠한다 (미확정 사항 결정 5).
struct WristScene: Equatable {
    var mmPerPoint: Double
    /// 테스트 도구의 v0.2 비교용. 기본 1 = 엄격 1:1
    var watchFactor: Double = 1
    var wristMatchedMM: Double
    var skin: RGB
    var background: RGB
    var edgeFadeMM: Double
    var watch: WatchSpec?
    var crownSide: CrownSide = .right
}

/// 가로로 지나가는 손목 띠의 세로 단면. 폭은 일정하게 두고(테이퍼는 v2) 위아래 경계만 부드럽게 페이드한다 (미확정 사항 결정 2).
struct BandProfile {
    let centerY: CGFloat
    let halfHeight: CGFloat
    let fade: CGFloat

    var top: CGFloat { centerY - halfHeight - fade / 2 }
    var bottom: CGFloat { centerY + halfHeight + fade / 2 }

    /// 손목 단면을 폭:두께 1.35 타원으로 보고, 위에서 오는 빛에 대한 법선 기울기로 음영을 낸다.
    static func shading(at u: Double) -> Double {
        let k = 1 / WristGeometry.widthToThickness
        let uu = min(abs(u), 0.999)
        let slopeSquared = k * k * uu * uu / (1 - uu * uu)
        let cosine = 1 / (1 + slopeSquared).squareRoot()
        return 0.55 + 0.45 * cosine
    }

    /// 화면에서 맞춘 폭은 페이드의 50% 지점이다
    func alpha(at y: CGFloat) -> Double {
        let distance = abs(y - centerY)
        guard fade > 0 else { return distance <= halfHeight ? 1 : 0 }
        let t = min(max((distance - (halfHeight - fade / 2)) / fade, 0), 1)
        return 1 - Double(t * t * (3 - 2 * t))
    }

    func gradient(for color: RGB, steps: Int = 56) -> Gradient {
        let span = bottom - top
        let stops = (0...steps).map { index -> Gradient.Stop in
            let location = CGFloat(index) / CGFloat(steps)
            let y = top + span * location
            let u = Double((y - centerY) / max(halfHeight, 1))
            let shaded = color.exposed(Self.shading(at: u))
            return Gradient.Stop(color: shaded.color.opacity(alpha(at: y)), location: location)
        }
        return Gradient(stops: stops)
    }

    func shading(for color: RGB) -> GraphicsContext.Shading {
        .linearGradient(gradient(for: color), startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom))
    }
}

enum Palette {
    static let steelLight = RGB(hex: 0xE6E8EB).color
    static let steelDark = RGB(hex: 0x9AA0A8).color
    static let steelEdge = RGB(hex: 0x5F656D).color
    static let polishedLight = RGB(hex: 0xF4F5F7).color
    static let polishedDark = RGB(hex: 0xB5BAC1).color
    static let lightInk = RGB(hex: 0xF4F3EE).color
    static let darkInk = RGB(hex: 0x1C1D20).color
    static let secondsHand = RGB(hex: 0xE0533A).color
}

struct WristRenderer {
    let scene: WristScene

    func draw(in context: inout GraphicsContext, size: CGSize, date: Date) {
        let pointsPerMM = CGFloat(1 / scene.mmPerPoint)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(scene.background.color))

        let band = BandProfile(
            centerY: center.y,
            halfHeight: CGFloat(scene.wristMatchedMM / 2) * pointsPerMM,
            fade: CGFloat(scene.edgeFadeMM) * pointsPerMM
        )
        context.fill(
            Path(CGRect(x: 0, y: band.top, width: size.width, height: band.bottom - band.top)),
            with: band.shading(for: scene.skin)
        )

        guard let watch = scene.watch else { return }
        let k = pointsPerMM * CGFloat(scene.watchFactor)
        let toScreen = CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: center.x, ty: center.y)
        let geometry = WatchGeometry(spec: watch)

        drawStrap(geometry, band: band, k: k, center: center, toScreen: toScreen, in: &context)
        drawCase(geometry, k: k, toScreen: toScreen, in: &context)
        drawDial(geometry, k: k, center: center, toScreen: toScreen, date: date, in: &context)
    }

    private func drawStrap(_ geometry: WatchGeometry, band: BandProfile, k: CGFloat, center: CGPoint, toScreen: CGAffineTransform, in context: inout GraphicsContext) {
        let edgeMM = Double((band.halfHeight + band.fade / 2) / k)
        let strap = geometry.strapPath(toWristEdge: edgeMM).applying(toScreen)
        guard !strap.isEmpty else { return }
        let halfWidth = CGFloat(geometry.spec.lugWidth / 2) * k
        context.drawLayer { layer in
            // 손목과 같은 곡률 음영·끝단 페이드를 공유해 손목을 감싸 넘어가는 것처럼 보이게 한다
            layer.fill(strap, with: band.shading(for: geometry.spec.strapColor.rgb.exposed(0.92)))
            layer.blendMode = .sourceAtop
            layer.fill(strap, with: .linearGradient(
                Gradient(stops: [
                    .init(color: .black.opacity(0.38), location: 0),
                    .init(color: .clear, location: 0.16),
                    .init(color: .white.opacity(0.06), location: 0.5),
                    .init(color: .clear, location: 0.84),
                    .init(color: .black.opacity(0.38), location: 1),
                ]),
                startPoint: CGPoint(x: center.x - halfWidth, y: 0),
                endPoint: CGPoint(x: center.x + halfWidth, y: 0)
            ))
        }
    }

    private func drawCase(_ geometry: WatchGeometry, k: CGFloat, toScreen: CGAffineTransform, in context: inout GraphicsContext) {
        let spec = geometry.spec
        let caseOutline = geometry.casePath().applying(toScreen)
        let lugs = geometry.lugsPath.applying(toScreen)
        let crown = geometry.crownPath(side: scene.crownSide).applying(toScreen)

        var silhouette = caseOutline
        silhouette.addPath(lugs)
        silhouette.addPath(crown)

        // 두께를 2D 한계 안에서 그림자 거리·번짐으로 암시한다
        let shadowOffset = CGFloat(spec.thickness * 0.16) * k
        let shadowBlur = CGFloat(spec.thickness * 0.22) * k
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: shadowBlur))
            layer.translateBy(x: 0, y: shadowOffset)
            layer.fill(silhouette, with: .color(.black.opacity(0.42)))
        }

        let bounds = silhouette.boundingRect
        let steel = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [Palette.steelLight, Palette.steelDark]),
            startPoint: CGPoint(x: bounds.minX, y: bounds.minY),
            endPoint: CGPoint(x: bounds.maxX, y: bounds.maxY)
        )

        context.fill(lugs, with: steel)
        context.stroke(lugs, with: .color(Palette.steelEdge), lineWidth: 0.5)
        context.fill(crown, with: steel)
        context.stroke(crown, with: .color(Palette.steelEdge), lineWidth: 0.5)
        context.stroke(geometry.crownGripPath(side: scene.crownSide).applying(toScreen), with: .color(Palette.steelEdge.opacity(0.6)), lineWidth: 0.35)
        context.fill(caseOutline, with: steel)
        context.stroke(caseOutline, with: .color(Palette.steelEdge), lineWidth: 0.6)

        var bezel = geometry.casePath(inset: geometry.rimWidth).applying(toScreen)
        bezel.addPath(geometry.casePath(inset: geometry.dialInset).applying(toScreen))
        if geometry.hasBezelInsert {
            context.fill(bezel, with: .color(spec.dialColor.insertRGB.color), style: FillStyle(eoFill: true))
            if spec.shape == .round {
                let radius = geometry.caseHalfWidth - geometry.rimWidth - geometry.bezelWidth / 2
                for hour in 0..<12 {
                    let angle = Double(hour) / 12 * 2 * Double.pi
                    let length = geometry.bezelWidth * (hour == 0 ? 0.6 : 0.4)
                    let width = hour == 0 ? 1.2 : 0.45
                    let tick = Path(roundedRect: CGRect(x: -width / 2, y: -length / 2, width: width, height: length), cornerRadius: width / 3)
                        .applying(CGAffineTransform(rotationAngle: angle)
                            .concatenating(CGAffineTransform(translationX: radius * sin(angle), y: -radius * cos(angle))))
                        .applying(toScreen)
                    context.fill(tick, with: .color(Palette.lightInk.opacity(0.85)))
                }
            }
        } else {
            let polished = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [Palette.polishedLight, Palette.polishedDark]),
                startPoint: CGPoint(x: bounds.minX, y: bounds.minY),
                endPoint: CGPoint(x: bounds.maxX, y: bounds.maxY)
            )
            context.fill(bezel, with: polished, style: FillStyle(eoFill: true))
        }
    }

    private func drawDial(_ geometry: WatchGeometry, k: CGFloat, center: CGPoint, toScreen: CGAffineTransform, date: Date, in context: inout GraphicsContext) {
        let spec = geometry.spec
        let dial = geometry.casePath(inset: geometry.dialInset).applying(toScreen)
        let dialRGB = spec.dialColor.rgb
        context.fill(dial, with: .radialGradient(
            Gradient(colors: [dialRGB.exposed(1.12).color, dialRGB.color, dialRGB.exposed(0.82).color]),
            center: center,
            startRadius: 0,
            endRadius: CGFloat(max(geometry.dialHalfWidth, geometry.dialHalfHeight)) * k
        ))
        context.stroke(dial, with: .color(.black.opacity(0.25)), lineWidth: 0.5)

        let isDarkDial = 0.2126 * dialRGB.r + 0.7152 * dialRGB.g + 0.0722 * dialRGB.b < 0.5
        let ink = isDarkDial ? Palette.lightInk : Palette.darkInk
        let radius = min(geometry.dialHalfWidth, geometry.dialHalfHeight)

        for (index, marker) in geometry.markerPositions().enumerated() {
            let length = radius * (index % 3 == 0 ? 0.17 : 0.11)
            let width = radius * (index == 0 ? 0.075 : 0.042)
            let path = Path(roundedRect: CGRect(x: -width / 2, y: -length / 2, width: width, height: length), cornerRadius: width / 3)
                .applying(CGAffineTransform(rotationAngle: marker.angle)
                    .concatenating(CGAffineTransform(translationX: marker.point.x, y: marker.point.y)))
                .applying(toScreen)
            context.fill(path, with: .color(ink))
        }

        let time = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let seconds = Double(time.second ?? 0)
        let minutes = Double(time.minute ?? 0) + seconds / 60
        let hours = Double((time.hour ?? 0) % 12) + minutes / 60

        func hand(turns: Double, length: Double, width: Double, tail: Double) -> Path {
            Path(roundedRect: CGRect(x: -width / 2, y: -length, width: width, height: length + tail), cornerRadius: width / 2)
                .applying(CGAffineTransform(rotationAngle: turns * 2 * Double.pi))
                .applying(toScreen)
        }

        context.fill(hand(turns: hours / 12, length: radius * 0.5, width: radius * 0.075, tail: radius * 0.1), with: .color(ink))
        context.fill(hand(turns: minutes / 60, length: radius * 0.78, width: radius * 0.055, tail: radius * 0.12), with: .color(ink))
        context.fill(hand(turns: seconds / 60, length: radius * 0.88, width: max(radius * 0.018, 0.25), tail: radius * 0.2), with: .color(Palette.secondsHand))
        let cap = radius * 0.05
        context.fill(Path(ellipseIn: CGRect(x: -cap, y: -cap, width: cap * 2, height: cap * 2)).applying(toScreen), with: .color(Palette.secondsHand))
    }
}

struct WristSceneView: View {
    let scene: WristScene

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            Canvas { context, size in
                WristRenderer(scene: scene).draw(in: &context, size: size, date: timeline.date)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(scene.watch.map { "\($0.name), 실제 크기" } ?? "가상 손목")
    }
}
