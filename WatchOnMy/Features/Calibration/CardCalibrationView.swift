import SwiftUI

/// 신용카드(ID-1)로 스케일을 보정하고 검증한다 (01 4~5절).
/// 카드는 세로로 세워 맞춘다(긴 변 85.60mm가 화면 세로축). 크기는 핀치로만, 드래그는 위치 이동, 종횡비 고정.
struct CardCalibrationView: View {
    enum Mode: String, Identifiable {
        case calibrate, verify
        var id: Self { self }
    }

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    @State private var longSidePoints: Double?
    @State private var pinchStart: Double?
    @State private var position: CGSize = .zero
    @State private var dragStart: CGSize?

    init(mode: Mode) {
        _mode = State(initialValue: mode)
    }

    var body: some View {
        let scale = appState.scale
        let estimated = scale.points(fromMM: Constants.cardWidthMM)
        let height = mode == .calibrate ? (longSidePoints ?? estimated) : estimated
        let pointsPerMM = height / Constants.cardWidthMM
        let width = Constants.cardHeightMM * pointsPerMM
        let corner = Constants.cardCornerRadiusMM * pointsPerMM

        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { proxy in
                let center = CGPoint(
                    x: proxy.size.width / 2 + (mode == .calibrate ? position.width : 0),
                    y: max(proxy.size.height * 0.4, CGFloat(height) / 2 + 8) + (mode == .calibrate ? position.height : 0)
                )
                RoundedRectangle(cornerRadius: corner, style: .circular)
                    .fill(Color.white.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: corner, style: .circular).stroke(Color.white, lineWidth: 1)
                    }
                    .frame(width: width, height: height)
                    .position(center)
                if mode == .verify {
                    MillimeterRuler(pointsPerMM: pointsPerMM, lengthMM: 50)
                        .frame(width: 32, height: 50 * pointsPerMM)
                        .position(x: center.x - width / 2 - 22, y: center.y - CGFloat(height) / 2 + 25 * pointsPerMM)
                }
            }
            .contentShape(Rectangle())
            .gesture(moveGesture, including: mode == .calibrate ? .all : .none)
            .simultaneousGesture(pinchGesture(estimated: estimated), including: mode == .calibrate ? .all : .none)

            VStack {
                Spacer()
                controls(height: height)
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
    }

    @ViewBuilder
    private func controls(height: Double) -> some View {
        VStack(spacing: 10) {
            if mode == .calibrate {
                Text("실물 카드를 화면에 세로로 올리고, 카드 테두리와 정확히 맞을 때까지 조절하세요. 두 손가락으로 크기, 한 손가락으로 위치.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button { longSidePoints = height - 1 } label: { Image(systemName: "minus").frame(width: 28, height: 28) }
                        .buttonStyle(.bordered)
                        .buttonRepeatBehavior(.enabled)
                        .accessibilityLabel("1pt 줄이기")
                    Text("1pt = \(String(format: "%.5f", PhysicalScale.cardMMPerPoint(matchedLongSidePoints: height)))mm")
                        .font(.caption.monospacedDigit())
                        .frame(maxWidth: .infinity)
                    Button { longSidePoints = height + 1 } label: { Image(systemName: "plus").frame(width: 28, height: 28) }
                        .buttonStyle(.bordered)
                        .buttonRepeatBehavior(.enabled)
                        .accessibilityLabel("1pt 늘리기")
                }
                HStack(spacing: 10) {
                    Button("취소") { dismiss() }
                        .buttonStyle(.bordered)
                    Button {
                        appState.saveCardCalibration(matchedLongSidePoints: height)
                        position = .zero
                        mode = .verify
                    } label: {
                        Text("이 크기로 저장").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("카드를 올려보세요. 정확히 맞나요?")
                    .font(.headline)
                Text("왼쪽 눈금은 1mm 간격 50mm입니다. 자로 재서 확인할 수도 있습니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("안 맞아요 → 카드로 보정하기") {
                        longSidePoints = height
                        mode = .calibrate
                    }
                    .buttonStyle(.bordered)
                    Button {
                        dismiss()
                    } label: {
                        Text("네, 맞아요").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(14)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var moveGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? position
                if dragStart == nil { dragStart = start }
                position = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func pinchGesture(estimated: Double) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? (longSidePoints ?? estimated)
                if pinchStart == nil { pinchStart = start }
                longSidePoints = start * Double(value.magnification)
            }
            .onEnded { _ in pinchStart = nil }
    }
}

struct MillimeterRuler: View {
    let pointsPerMM: Double
    let lengthMM: Int

    var body: some View {
        Canvas { context, size in
            for mm in 0...lengthMM {
                let y = CGFloat(Double(mm) * pointsPerMM)
                let length: CGFloat = mm % 10 == 0 ? 14 : (mm % 5 == 0 ? 10 : 6)
                var tick = Path()
                tick.move(to: CGPoint(x: size.width - length, y: y))
                tick.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(tick, with: .color(.white.opacity(0.85)), lineWidth: 0.5)
                if mm % 10 == 0, mm > 0 {
                    context.draw(
                        Text("\(mm)").font(.system(size: 8).monospacedDigit()).foregroundStyle(.white.opacity(0.7)),
                        at: CGPoint(x: size.width - 24, y: y),
                        anchor: .center
                    )
                }
            }
        }
    }
}
