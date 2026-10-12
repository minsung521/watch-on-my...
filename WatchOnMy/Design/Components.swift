import SwiftUI

extension RGB {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
}

/// 색상 칩 (다이얼·스트랩·피부톤 선택)
struct ColorChip: View {
    let rgb: RGB
    let label: String
    let isSelected: Bool
    var size: CGFloat = 34

    var body: some View {
        Circle()
            .fill(rgb.color)
            .frame(width: size, height: size)
            .overlay {
                Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.9 : 0.2), lineWidth: isSelected ? 2.5 : 1)
            }
            .padding(2)
            .contentShape(Circle())
            .accessibilityLabel(label)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct NoticeBanner: View {
    let symbol: String
    let title: String
    var message: String?
    var tint: Color = .orange
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.body.weight(.semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.footnote.weight(.semibold))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(.white)
            .background(
                Color.accentColor.opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }
}

/// 손목 캔버스 전체 화면. 조작 요소는 띠 바깥 검정 영역(위·아래)에만 두고, 띠가 오프셋으로 움직이면 영역도 따라간다 (06 4-2).
/// 검정 영역 위의 크롬은 가독성을 위해 어두운 외관으로 고정한다. 캔버스는 원래 외관과 무관하다.
struct CanvasScaffold<Gestures: View, Top: View, Bottom: View>: View {
    let scale: PhysicalScale
    let wrist: WristProfile
    let watch: WatchSource?
    var showsControls = true
    let gestures: (BandLayout) -> Gestures
    let top: (CGFloat) -> Top
    let bottom: (CGFloat) -> Bottom

    init(
        scale: PhysicalScale,
        wrist: WristProfile,
        watch: WatchSource?,
        showsControls: Bool = true,
        @ViewBuilder gestures: @escaping (BandLayout) -> Gestures,
        @ViewBuilder top: @escaping (CGFloat) -> Top,
        @ViewBuilder bottom: @escaping (CGFloat) -> Bottom
    ) {
        self.scale = scale
        self.wrist = wrist
        self.watch = watch
        self.showsControls = showsControls
        self.gestures = gestures
        self.top = top
        self.bottom = bottom
    }

    var body: some View {
        GeometryReader { outer in
            let insets = outer.safeAreaInsets
            let fullHeight = outer.size.height + insets.top + insets.bottom
            let band = BandLayout(canvasHeight: fullHeight, wrist: wrist, scale: scale)
            let margin: CGFloat = 6
            let topSpace = max(band.visibleTop - insets.top - margin, 0)
            let bottomSpace = max(fullHeight - band.visibleBottom - insets.bottom - margin, 0)
            ZStack(alignment: .top) {
                WristCanvas(scale: scale, wrist: wrist, watch: watch)
                gestures(band)
                if showsControls {
                    VStack(spacing: 0) {
                        top(topSpace)
                            .frame(maxWidth: .infinity, maxHeight: topSpace, alignment: .top)
                            .padding(.top, insets.top)
                        Spacer(minLength: 0)
                        bottom(bottomSpace)
                            .frame(maxWidth: .infinity, maxHeight: bottomSpace, alignment: .bottom)
                            .padding(.bottom, insets.bottom)
                    }
                    .padding(.horizontal, 16)
                    .transition(.opacity)
                }
            }
            .frame(width: outer.size.width, height: fullHeight)
            .ignoresSafeArea()
        }
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}
