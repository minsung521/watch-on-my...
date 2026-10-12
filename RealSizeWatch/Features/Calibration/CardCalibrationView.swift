import SwiftUI

/// 신용카드(ID-1) 규격으로 스케일을 확인하거나 보정한다 (MIN-44).
/// 확인: 산출 계수로 그린 카드 테두리가 실물과 1mm 이내로 맞는지 본다.
/// 보정: 미등록 기기에서 테두리를 실물 카드에 맞춰 계수를 역산한다.
struct CardCalibrationView: View {
    enum Mode: String, Identifiable {
        case verify, calibrate
        var id: Self { self }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    @State private var cardHeight: CGFloat?
    @State private var pinchStart: CGFloat?

    init(mode: Mode) {
        _mode = State(initialValue: mode)
    }

    var body: some View {
        let scale = model.scale
        let reference = scale.points(IDCard.heightMM)
        let height = cardHeight ?? reference
        let pointsPerMM = height / IDCard.heightMM
        ZStack {
            Color(white: 0.08).ignoresSafeArea()
            GeometryReader { proxy in
                let width = IDCard.widthMM * pointsPerMM
                let center = CGPoint(x: proxy.size.width / 2 + 12, y: proxy.safeAreaInsets.top + 14 + height / 2)
                RoundedRectangle(cornerRadius: IDCard.cornerRadiusMM * pointsPerMM, style: .circular)
                    .fill(Color.white.opacity(0.07))
                    .overlay {
                        RoundedRectangle(cornerRadius: IDCard.cornerRadiusMM * pointsPerMM, style: .circular)
                            .stroke(Color.white, lineWidth: 1)
                    }
                    .frame(width: width, height: height)
                    .position(center)
                MillimeterRuler(pointsPerMM: pointsPerMM, lengthMM: 85)
                    .frame(width: 30, height: 85 * pointsPerMM)
                    .position(x: center.x - width / 2 - 19, y: center.y - height / 2 + 85 * pointsPerMM / 2)
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .gesture(pinch(reference: height), including: mode == .calibrate ? .all : .none)

            VStack {
                Spacer()
                controls(reference: reference, height: height)
            }
        }
        .statusBarHidden()
        .environment(\.colorScheme, .dark)
    }

    private func controls(reference: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 10) {
            Text(mode == .verify
                 ? "실물 카드를 테두리에 세로로 대보세요. 네 변이 1mm 안으로 맞으면 통과. 눈금은 1mm 간격."
                 : "카드를 세로로 올리고, 두 손가락이나 ± 버튼으로 테두리를 카드 가장자리에 맞추세요.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("1pt = \(String(format: "%.5f", IDCard.heightMM / Double(height)))mm")
                .font(.caption.monospacedDigit())
            if mode == .calibrate {
                HStack(spacing: 10) {
                    Button { cardHeight = height - 0.5 } label: { Image(systemName: "minus").frame(width: 24, height: 24) }
                        .buttonStyle(.bordered)
                        .buttonRepeatBehavior(.enabled)
                    Slider(
                        value: Binding(get: { Double(height) }, set: { cardHeight = CGFloat($0) }),
                        in: Double(reference * 0.85)...Double(reference * 1.15)
                    )
                    Button { cardHeight = height + 0.5 } label: { Image(systemName: "plus").frame(width: 24, height: 24) }
                        .buttonStyle(.bordered)
                        .buttonRepeatBehavior(.enabled)
                }
                HStack(spacing: 10) {
                    Button("취소") { dismiss() }
                        .buttonStyle(.bordered)
                    Button {
                        model.saveCardCalibration(matchedHeightPoints: height)
                        dismiss()
                    } label: {
                        Text("이 크기로 저장").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                HStack(spacing: 10) {
                    Button("카드로 보정") {
                        cardHeight = height
                        mode = .calibrate
                    }
                    .buttonStyle(.bordered)
                    Button {
                        dismiss()
                    } label: {
                        Text("닫기").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func pinch(reference: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? reference
                if pinchStart == nil { pinchStart = start }
                cardHeight = start * value.magnification
            }
            .onEnded { _ in pinchStart = nil }
    }
}

struct MillimeterRuler: View {
    let pointsPerMM: CGFloat
    let lengthMM: Int

    var body: some View {
        Canvas { context, size in
            for mm in 0...lengthMM {
                let y = CGFloat(mm) * pointsPerMM
                let length: CGFloat = mm % 10 == 0 ? 14 : (mm % 5 == 0 ? 10 : 6)
                var tick = Path()
                tick.move(to: CGPoint(x: size.width - length, y: y))
                tick.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(tick, with: .color(.white.opacity(0.85)), lineWidth: 0.5)
                if mm % 10 == 0, mm > 0 {
                    context.draw(
                        Text("\(mm / 10)").font(.system(size: 8).monospacedDigit()).foregroundStyle(.white.opacity(0.7)),
                        at: CGPoint(x: size.width - 21, y: y),
                        anchor: .center
                    )
                }
            }
        }
    }
}
