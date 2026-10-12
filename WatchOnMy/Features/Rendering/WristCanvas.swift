import SwiftUI

/// 손목 띠의 화면상 위치. 조작 요소 배치도 이 값으로 띠를 피한다 (06 4-2)
struct BandLayout {
    let canvasHeight: CGFloat
    let matchedWidthPoints: CGFloat
    let offsetPoints: CGFloat
    let fadePoints: CGFloat

    init(canvasHeight: CGFloat, wrist: WristProfile, scale: PhysicalScale) {
        self.canvasHeight = canvasHeight
        matchedWidthPoints = CGFloat(wrist.matchedWidthPoints)
        offsetPoints = CGFloat(wrist.bandOffsetPoints)
        fadePoints = CGFloat(scale.points(fromMM: Constants.bandEdgeFadeMM))
    }

    var centerY: CGFloat { canvasHeight / 2 + offsetPoints }
    var halfHeight: CGFloat { matchedWidthPoints / 2 }
    /// 페이드까지 포함해 띠가 보이는 위·아래 끝
    var visibleTop: CGFloat { centerY - halfHeight - fadePoints / 2 }
    var visibleBottom: CGFloat { centerY + halfHeight + fadePoints / 2 }
}

/// 가상 손목 + 시계 + 스트랩을 하나의 Canvas에 그린다 (02). 시스템 외관과 무관하게 항상 같은 색이다.
struct WristCanvas: View {
    let scale: PhysicalScale
    let wrist: WristProfile
    let watch: WatchSource?
    /// 아이콘 생성 등 시각을 고정할 때
    var fixedDate: Date?

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            Canvas { context, size in
                WristRenderer(
                    scale: scale,
                    wrist: wrist,
                    watch: watch,
                    photoImage: watch?.photoFileName.flatMap { PhotoStore.shared.image(named: $0) },
                    date: fixedDate ?? timeline.date
                )
                .draw(in: &context, size: size)
            }
        }
        .background(Color.black)
        .accessibilityElement()
        .accessibilityLabel(watch == nil ? "가상 손목" : "가상 손목 위 실제 크기 시계")
    }
}

private enum Metal {
    static let light = RGB(hex: 0xE6E8EB)
    static let dark = RGB(hex: 0x9AA0A8)
    static let edge = RGB(hex: 0x5F656D)
    static let lightInk = RGB(hex: 0xF4F3EE)
    static let darkInk = RGB(hex: 0x1C1D20)
}

struct WristRenderer {
    let scale: PhysicalScale
    let wrist: WristProfile
    let watch: WatchSource?
    let photoImage: CGImage?
    let date: Date

    /// 순서: 검정 배경 → 가상 손목 → 그림자 → 스트랩 → 케이스 → 크라운 (02 1절)
    func draw(in context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        let band = BandLayout(canvasHeight: size.height, wrist: wrist, scale: scale)
        drawBand(band, size: size, in: &context)

        guard let watch else { return }
        let k = CGFloat(scale.points(fromMM: 1))
        let center = CGPoint(x: size.width / 2, y: band.centerY)
        let frame = WatchFrame(
            toScreen: CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: center.x, ty: center.y),
            pointsPerMM: k,
            center: center,
            edgeMM: scale.mm(fromPoints: Double(band.halfHeight)),
            band: band,
            canvasWidth: size.width
        )
        switch watch {
        case .parametric(let spec):
            drawParametric(spec, frame: frame, in: &context)
        case .photo(let photo):
            drawPhoto(photo, frame: frame, in: &context)
        }
    }

    // MARK: 가상 손목

    private func drawBand(_ band: BandLayout, size: CGSize, in context: inout GraphicsContext) {
        let rect = CGRect(x: 0, y: band.visibleTop, width: size.width, height: band.visibleBottom - band.visibleTop)
        guard rect.height > 0 else { return }
        let skin = wrist.skinColor
        let steps = 48
        let stops = (0...steps).map { index -> Gradient.Stop in
            let location = CGFloat(index) / CGFloat(steps)
            let y = rect.minY + rect.height * location
            let t = Double((y - (band.centerY - band.halfHeight)) / max(band.matchedWidthPoints, 1))
            let alpha = BandProfile.edgeAlpha(
                distanceFromEdge: Double(band.halfHeight - abs(y - band.centerY)),
                fade: Double(band.fadePoints)
            )
            return Gradient.Stop(color: skin.scaled(BandProfile.brightness(at: t)).color.opacity(alpha), location: location)
        }
        let sideFade = min(CGFloat(scale.points(fromMM: Constants.screenSideFadeMM)) / size.width, 0.45)
        context.drawLayer { layer in
            layer.fill(Path(rect), with: .linearGradient(
                Gradient(stops: stops),
                startPoint: CGPoint(x: 0, y: rect.minY),
                endPoint: CGPoint(x: 0, y: rect.maxY)
            ))
            // 화면 좌·우 끝: 실제 팔과 이어지는 경계의 소프트 페이드
            layer.blendMode = .destinationIn
            layer.fill(Path(rect), with: .linearGradient(
                Gradient(stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: .white, location: sideFade),
                    .init(color: .white, location: 1 - sideFade),
                    .init(color: .white.opacity(0), location: 1),
                ]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: size.width, y: 0)
            ))
        }
    }

    // MARK: 시계 공통

    private struct WatchFrame {
        let toScreen: CGAffineTransform
        let pointsPerMM: CGFloat
        let center: CGPoint
        /// 시계 중심에서 손목 띠 가장자리까지 (mm)
        let edgeMM: Double
        let band: BandLayout
        let canvasWidth: CGFloat
    }

    private func strapPath(widthMM: Double, startY: Double, lugTipY: Double, edgeY: Double) -> Path {
        guard let half = StrapGeometry.halfOutline(widthMM: widthMM, startY: startY, lugTipY: lugTipY, edgeY: edgeY) else { return Path() }
        var bottom = Path()
        bottom.move(to: half[0])
        half.dropFirst().forEach { bottom.addLine(to: $0) }
        half.reversed().dropFirst().forEach { bottom.addLine(to: CGPoint(x: -$0.x, y: $0.y)) }
        bottom.closeSubpath()
        var both = bottom
        both.addPath(bottom, transform: CGAffineTransform(scaleX: 1, y: -1))
        return both
    }

    /// 스트랩: 폭 방향 곡률 음영(양끝 0.72) + 손목 띠 가장자리 직전 페이드. 검정 영역으로 나가지 않는다
    private func drawStrap(_ path: Path, widthMM: Double, color: RGB, frame: WatchFrame, in context: inout GraphicsContext) {
        let screenPath = path.applying(frame.toScreen)
        let halfWidth = CGFloat(widthMM / 2) * frame.pointsPerMM
        let edge = CGFloat(frame.edgeMM) * frame.pointsPerMM
        let fade = CGFloat(Constants.strapEndFadeMM) * frame.pointsPerMM
        let top = frame.center.y - edge
        let span = max(edge * 2, 1)
        let fadeLocation = min(fade / span, 0.49)
        let edgeShade = Constants.strapEdgeShading
        context.drawLayer { layer in
            layer.fill(screenPath, with: .linearGradient(
                Gradient(stops: [
                    .init(color: color.scaled(edgeShade).color, location: 0),
                    .init(color: color.scaled(0.95).color, location: 0.25),
                    .init(color: color.color, location: 0.5),
                    .init(color: color.scaled(0.95).color, location: 0.75),
                    .init(color: color.scaled(edgeShade).color, location: 1),
                ]),
                startPoint: CGPoint(x: frame.center.x - halfWidth, y: 0),
                endPoint: CGPoint(x: frame.center.x + halfWidth, y: 0)
            ))
            layer.blendMode = .destinationIn
            layer.fill(Path(CGRect(x: 0, y: top, width: frame.canvasWidth, height: span)), with: .linearGradient(
                Gradient(stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: .white, location: fadeLocation),
                    .init(color: .white, location: 1 - fadeLocation),
                    .init(color: .white.opacity(0), location: 1),
                ]),
                startPoint: CGPoint(x: 0, y: top),
                endPoint: CGPoint(x: 0, y: top + span)
            ))
        }
    }

    /// 오프셋 0, 블러 2mm, 알파 0.25
    private func drawShadow(of silhouette: Path, frame: WatchFrame, in context: inout GraphicsContext) {
        let blur = CGFloat(Constants.shadowBlurMM) * frame.pointsPerMM
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: blur))
            layer.fill(silhouette, with: .color(.black.opacity(Constants.shadowOpacity)))
        }
    }

    private func metal(_ bounds: CGRect) -> GraphicsContext.Shading {
        .linearGradient(
            Gradient(colors: [Metal.light.color, Metal.dark.color]),
            startPoint: CGPoint(x: bounds.minX, y: bounds.minY),
            endPoint: CGPoint(x: bounds.maxX, y: bounds.maxY)
        )
    }

    // MARK: 파라메트릭 시계

    private func drawParametric(_ spec: WatchSpec, frame: WatchFrame, in context: inout GraphicsContext) {
        let geometry = CaseGeometry(spec: spec)
        let caseOutline = Self.polygon(geometry.outline()).applying(frame.toScreen)
        let lugs = lugsPath(geometry).applying(frame.toScreen)
        let crown = Path(roundedRect: geometry.crownRect(side: spec.crownSide), cornerRadius: 0.4).applying(frame.toScreen)
        let lugTip = geometry.hasVisibleLugs ? geometry.lugTipY : geometry.halfLength
        let strapStart = geometry.halfLength * 0.4
        let strap = strapPath(widthMM: spec.lugWidthMM, startY: strapStart, lugTipY: lugTip, edgeY: frame.edgeMM)

        var silhouette = caseOutline
        silhouette.addPath(lugs)
        silhouette.addPath(crown)
        silhouette.addPath(strapPath(
            widthMM: spec.lugWidthMM,
            startY: strapStart,
            lugTipY: lugTip,
            edgeY: frame.edgeMM - Constants.strapEndFadeMM
        ).applying(frame.toScreen))
        drawShadow(of: silhouette, frame: frame, in: &context)

        drawStrap(strap, widthMM: spec.lugWidthMM, color: spec.strapColor, frame: frame, in: &context)

        let bounds = caseOutline.boundingRect
        context.fill(lugs, with: metal(bounds))
        context.stroke(lugs, with: .color(Metal.edge.color), lineWidth: 0.5)
        context.fill(caseOutline, with: metal(bounds))
        context.stroke(caseOutline, with: .color(Metal.edge.color), lineWidth: 0.6)

        let dial = Self.polygon(geometry.outline(factor: geometry.dialScale)).applying(frame.toScreen)
        let dialRadius = CGFloat(max(geometry.halfWidth, geometry.halfLength) * geometry.dialScale) * frame.pointsPerMM
        context.fill(dial, with: .radialGradient(
            Gradient(colors: [spec.dialColor.scaled(1.04).color, spec.dialColor.scaled(0.96).color]),
            center: frame.center,
            startRadius: 0,
            endRadius: dialRadius
        ))
        context.stroke(dial, with: .color(.black.opacity(0.25)), lineWidth: 0.5)
        drawIndicesAndHands(geometry, ink: spec.dialColor.luminance < 0.5 ? Metal.lightInk : Metal.darkInk, frame: frame, in: &context)

        context.fill(crown, with: metal(bounds))
        context.stroke(crown, with: .color(Metal.edge.color), lineWidth: 0.5)
    }

    private func lugsPath(_ geometry: CaseGeometry) -> Path {
        guard let lug = geometry.lug else { return Path() }
        let r = lug.tipRadius
        var single = Path()
        single.move(to: CGPoint(x: lug.innerX, y: lug.start.y))
        single.addLine(to: CGPoint(x: lug.innerX, y: lug.tipY - r))
        single.addQuadCurve(to: CGPoint(x: lug.innerX + r, y: lug.tipY), control: CGPoint(x: lug.innerX, y: lug.tipY))
        single.addLine(to: CGPoint(x: lug.tipOuterX - r, y: lug.tipY))
        single.addQuadCurve(to: CGPoint(x: lug.tipOuterX, y: lug.tipY - r), control: CGPoint(x: lug.tipOuterX, y: lug.tipY))
        // 바깥쪽 모서리: 케이스 외곽 35° 지점까지 2차 베지어 (02 4-2)
        single.addQuadCurve(to: lug.start, control: CGPoint(x: lug.start.x, y: (lug.start.y + lug.tipY) / 2))
        single.closeSubpath()
        var all = Path()
        for sx in [-1.0, 1.0] {
            for sy in [-1.0, 1.0] {
                all.addPath(single, transform: CGAffineTransform(scaleX: sx, y: sy))
            }
        }
        return all
    }

    /// 12·3·6·9 짧은 막대 4개와 시침·분침만 (02 4-3)
    private func drawIndicesAndHands(_ geometry: CaseGeometry, ink: RGB, frame: WatchFrame, in context: inout GraphicsContext) {
        let dialHalfWidth = geometry.halfWidth * geometry.dialScale
        let dialHalfLength = geometry.halfLength * geometry.dialScale
        let radius = min(dialHalfWidth, dialHalfLength)
        for quarter in 0..<4 {
            let angle = Double(quarter) * Double.pi / 2
            let length = radius * 0.16
            let width = radius * (quarter == 0 ? 0.08 : 0.055)
            let position = CGPoint(x: dialHalfWidth * 0.8 * sin(angle), y: -dialHalfLength * 0.8 * cos(angle))
            let bar = Path(roundedRect: CGRect(x: -width / 2, y: -length / 2, width: width, height: length), cornerRadius: width / 3)
                .applying(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: position.x, y: position.y)))
                .applying(frame.toScreen)
            context.fill(bar, with: .color(ink.color))
        }

        let time = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = Double(time.minute ?? 0)
        let hours = Double((time.hour ?? 0) % 12) + minutes / 60
        func hand(turns: Double, length: Double, width: Double) -> Path {
            Path(roundedRect: CGRect(x: -width / 2, y: -length, width: width, height: length + radius * 0.1), cornerRadius: width / 2)
                .applying(CGAffineTransform(rotationAngle: turns * 2 * Double.pi))
                .applying(frame.toScreen)
        }
        context.fill(hand(turns: hours / 12, length: radius * 0.5, width: radius * 0.08), with: .color(ink.color))
        context.fill(hand(turns: minutes / 60, length: radius * 0.78, width: radius * 0.055), with: .color(ink.color))
        let cap = radius * 0.06
        context.fill(Path(ellipseIn: CGRect(x: -cap, y: -cap, width: cap * 2, height: cap * 2)).applying(frame.toScreen), with: .color(ink.color))
    }

    // MARK: 사진 시계 (06 6-2)

    private func drawPhoto(_ photo: PhotoWatch, frame: WatchFrame, in context: inout GraphicsContext) {
        guard let image = photoImage else { return }
        let widthMM = Double(image.width) * photo.mmPerPixel
        let heightMM = Double(image.height) * photo.mmPerPixel
        let rect = CGRect(x: -widthMM / 2, y: -heightMM / 2, width: widthMM, height: heightMM).applying(frame.toScreen)
        let half = photo.lugToLugMM / 2
        let strap = strapPath(widthMM: photo.strapWidthMM, startY: max(half - 1, 0), lugTipY: half, edgeY: frame.edgeMM)
        let swiftUIImage = Image(decorative: image, scale: 1)

        let shortStrap = strapPath(
            widthMM: photo.strapWidthMM,
            startY: max(half - 1, 0),
            lugTipY: half,
            edgeY: frame.edgeMM - Constants.strapEndFadeMM
        ).applying(frame.toScreen)
        let blur = CGFloat(Constants.shadowBlurMM) * frame.pointsPerMM
        drawShadow(of: shortStrap, frame: frame, in: &context)
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(Constants.shadowOpacity), radius: blur, options: .shadowOnly))
            layer.draw(swiftUIImage, in: rect)
        }

        drawStrap(strap, widthMM: photo.strapWidthMM, color: photo.strapColor, frame: frame, in: &context)
        // 크라운 방향 토글은 적용하지 않는다 (사진 그대로)
        context.draw(swiftUIImage, in: rect)
    }

    static func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }
}
