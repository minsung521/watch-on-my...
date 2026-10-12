import SwiftUI

extension FitVerdict.Level {
    var tint: Color {
        switch self {
        case .comfortable: .green
        case .borderline: .orange
        case .overhang: .red
        }
    }

    var symbol: String {
        switch self {
        case .comfortable: "checkmark.circle.fill"
        case .borderline: "circle.lefthalf.filled"
        case .overhang: "exclamationmark.triangle.fill"
        }
    }
}

struct FitBadge: View {
    let verdict: FitVerdict
    var showsMessage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(verdict.title, systemImage: verdict.level.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(verdict.level.tint)
            if showsMessage {
                Text(verdict.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fit.badge")
    }
}

struct Swatch: View {
    let rgb: RGB
    let label: String
    let isSelected: Bool
    var size: CGFloat = 34

    var body: some View {
        Circle()
            .fill(rgb.color)
            .frame(width: size, height: size)
            .overlay {
                Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.9 : 0.15), lineWidth: isSelected ? 2.5 : 1)
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
    let message: String
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
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.footnote.weight(.semibold))
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct Chip: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(.white)
            .background(Color.accentColor.opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension View {
    /// 손목 캔버스 위에 띄우는 UI 크롬. 시스템 외관은 이 크롬에만 적용된다.
    func chromePanel() -> some View {
        padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
