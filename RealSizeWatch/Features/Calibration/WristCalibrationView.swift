import SwiftUI

/// 폰을 손목 위에 가로질러 올린 채, 화면 속 손목 띠가 화면 양옆 실제 팔과 같은 굵기로 이어지도록 맞춘다.
/// 시계 크기는 조작 대상이 아니다 (MIN-45).
struct WristCalibrationView: View {
    @Environment(AppModel.self) private var model
    @Binding var skin: SkinTone
    @Binding var matchedWidth: Double
    var cancelTitle = "취소"
    var onCancel: (() -> Void)?
    var onDone: (AmbientReading?) -> Void

    @State private var dragStartWidth: Double?
    @State private var pinchStartWidth: Double?
    @State private var showsControls = true
    private let ambient = AmbientLightMonitor.shared

    var body: some View {
        let scale = model.scale
        let tools = model.state.tools
        ZStack {
            tools.background.rgb.color.ignoresSafeArea()
            GeometryReader { proxy in
                WristSceneView(scene: WristScene(
                    mmPerPoint: scale.mmPerPoint,
                    wristMatchedMM: matchedWidth,
                    skin: skin.rendered(),
                    background: tools.background.rgb,
                    edgeFadeMM: tools.edgeFadeMM,
                    watch: nil
                ))
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showsControls.toggle() } }
                .gesture(edgeDrag(centerY: proxy.size.height / 2, scale: scale))
                .simultaneousGesture(pinch)
                .accessibilityIdentifier("wrist.canvas")
            }
            .ignoresSafeArea()

            if showsControls {
                VStack(spacing: 0) {
                    topPanel
                    Spacer(minLength: 0)
                    bottomPanel
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .transition(.opacity)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .calibratedScreen(brightness: tools.lockedBrightness)
        .onAppear { ambient.acquire() }
        .onDisappear { ambient.release() }
    }

    private var topPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("손목 굵기 맞추기")
                .font(.headline)
            Text("시계 보는 자세로 팔을 들고, 폰을 세로로 세워 손목 위에 가로질러 올리세요. 위·아래 가장자리를 끌어 화면 양옆 실제 팔과 같은 굵기로 맞춥니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Chip(symbol: "eye", text: "눈–팔 30~40cm")
                Chip(symbol: "hand.tap", text: "탭: UI 숨김")
                if let reading = ambient.reading {
                    Chip(symbol: "lightbulb", text: reading.summary)
                }
            }
            if ambient.reading?.isTooBright == true {
                Label("너무 밝아요. 그늘이나 실내로 이동하세요.", systemImage: "sun.max.trianglebadge.exclamationmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chromePanel()
    }

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            tuneRow("밝기", value: $skin.lightness, id: "wrist.lightness")
            tuneRow("색온도", value: $skin.warmth, id: "wrist.warmth")
            HStack(spacing: 10) {
                stepButton(symbol: "minus", delta: -0.5)
                    .accessibilityIdentifier("wrist.minus")
                VStack(spacing: 2) {
                    Text("화면 폭 \(matchedWidth.mmText)mm")
                        .font(.headline.monospacedDigit())
                        .accessibilityIdentifier("wrist.width")
                    Text("실제 손목 약 \((matchedWidth * WristProfile.viewingCorrection).mmText)mm (×1.083)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                stepButton(symbol: "plus", delta: 0.5)
                    .accessibilityIdentifier("wrist.plus")
            }
            HStack(spacing: 10) {
                if let onCancel {
                    Button(cancelTitle, action: onCancel)
                        .buttonStyle(.bordered)
                }
                Button {
                    onDone(ambient.reading)
                } label: {
                    Text("이 굵기로 완료").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("wrist.done")
            }
        }
        .chromePanel()
    }

    private func tuneRow(_ title: String, value: Binding<Double>, id: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .frame(width: 40, alignment: .leading)
            Slider(value: value, in: -1...1)
                .accessibilityIdentifier(id)
            Button {
                value.wrappedValue = 0
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(title) 초기화")
        }
    }

    private func stepButton(symbol: String, delta: Double) -> some View {
        Button {
            matchedWidth = Self.clamp(matchedWidth + delta)
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.bordered)
        .buttonRepeatBehavior(.enabled)
    }

    /// 손가락이 잡은 쪽 가장자리를 바깥으로 끌면 굵어진다. 띠는 가운데를 기준으로 대칭이다.
    private func edgeDrag(centerY: CGFloat, scale: PhysicalScale) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let start = dragStartWidth ?? matchedWidth
                if dragStartWidth == nil { dragStartWidth = start }
                let outward = value.startLocation.y < centerY ? -value.translation.height : value.translation.height
                matchedWidth = Self.clamp(start + 2 * scale.millimeters(outward))
            }
            .onEnded { _ in dragStartWidth = nil }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStartWidth ?? matchedWidth
                if pinchStartWidth == nil { pinchStartWidth = start }
                matchedWidth = Self.clamp(start * value.magnification)
            }
            .onEnded { _ in pinchStartWidth = nil }
    }

    static func clamp(_ width: Double) -> Double {
        let range = WristProfile.matchedWidthRange
        return min(max((width * 10).rounded() / 10, range.lowerBound), range.upperBound)
    }
}

/// 설정에서 들어오는 손목 굵기 재조정
struct WristRecalibrationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var skin: SkinTone
    @State private var width: Double

    init(skin: SkinTone, width: Double) {
        _skin = State(initialValue: skin)
        _width = State(initialValue: width)
    }

    var body: some View {
        WristCalibrationView(skin: $skin, matchedWidth: $width, onCancel: { dismiss() }) { reading in
            model.applyWristRecalibration(matchedWidthMM: width, skin: skin, ambient: reading)
            dismiss()
        }
    }
}
