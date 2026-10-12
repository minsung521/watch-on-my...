import SwiftUI

/// 손목 폭 맞추기 — 가장 중요한 화면 (03 6절, 06 5-2).
/// 띠의 위·아래 가장자리를 끌면 중심 대칭으로 폭이 바뀌고, 가운데를 끌면 띠 전체가 위아래로 움직인다. 시계는 나오지 않는다.
struct WristWidthView: View {
    @Environment(AppState.self) private var appState
    @Binding var wrist: WristProfile
    var doneTitle = "다음"
    var onBack: (() -> Void)?
    var onDone: () -> Void

    private enum DragMode {
        case width(start: Double, outwardSign: Double)
        case move(start: Double)
    }

    @State private var dragMode: DragMode?

    var body: some View {
        let scale = appState.scale
        CanvasScaffold(scale: scale, wrist: wrist, watch: nil) { band in
            Color.clear
                .contentShape(Rectangle())
                .gesture(drag(band: band, scale: scale))
                .accessibilityIdentifier("wrist.canvas")
        } top: { _ in
            ViewThatFits(in: .vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("손목 폭 맞추기").font(.headline)
                    Text("폰을 팔과 직각이 되게 올리고, 화면 속 손목의 위아래 끝이 실제 팔과 이어지도록 맞추세요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    distanceNote
                    Text("가장자리를 끌면 폭, 가운데를 끌면 위치가 바뀝니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("손목의 위아래 끝을 실제 팔에 맞추세요").font(.footnote.weight(.semibold))
                    distanceNote
                }
                distanceNote
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } bottom: { _ in
            ViewThatFits(in: .vertical) {
                VStack(spacing: 12) {
                    widthRow
                    offsetRow
                    buttons
                }
                VStack(spacing: 8) {
                    widthRow
                    buttons
                }
                buttons
            }
        }
        .canvasScreen()
    }

    private var distanceNote: some View {
        Label("팔을 눈에서 30~40cm 거리에 두세요", systemImage: "eye")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.yellow)
    }

    private var widthRow: some View {
        let scale = appState.scale
        return HStack(spacing: 12) {
            stepButton("minus", label: "폭 줄이기") { setWidth(wrist.matchedWidthPoints - scale.points(fromMM: Constants.matchedWidthStepMM)) }
            VStack(spacing: 2) {
                Text("손목 폭 \(WristProfile.trueWidthMM(matchedWidthPoints: wrist.matchedWidthPoints, scale: scale).rounded().mmTextInt)")
                    .font(.headline.monospacedDigit())
                    .accessibilityIdentifier("wrist.width")
                Text("화면 \(scale.mm(fromPoints: wrist.matchedWidthPoints).mmText)mm · 0.5mm 단위")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            stepButton("plus", label: "폭 늘리기") { setWidth(wrist.matchedWidthPoints + scale.points(fromMM: Constants.matchedWidthStepMM)) }
        }
    }

    private var offsetRow: some View {
        let step = appState.scale.points(fromMM: 1)
        return HStack(spacing: 12) {
            stepButton("arrow.up", label: "띠 위로") { wrist.bandOffsetPoints -= step }
            Text("띠 위치")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
            stepButton("arrow.down", label: "띠 아래로") { wrist.bandOffsetPoints += step }
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            if let onBack {
                Button("이전", action: onBack)
                    .buttonStyle(.bordered)
            }
            Button {
                onDone()
            } label: {
                Text(doneTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("wrist.done")
        }
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.bordered)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }

    private func setWidth(_ points: Double) {
        let scale = appState.scale
        let range = Constants.matchedWidthRangeMM
        wrist.matchedWidthPoints = min(max(points, scale.points(fromMM: range.lowerBound)), scale.points(fromMM: range.upperBound))
        wrist.recomputeTrueWidth(scale: scale)
    }

    private func drag(band: BandLayout, scale: PhysicalScale) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if dragMode == nil {
                    let distance = value.startLocation.y - band.centerY
                    if abs(distance) > band.halfHeight * 0.45 {
                        dragMode = .width(start: wrist.matchedWidthPoints, outwardSign: distance < 0 ? -1 : 1)
                    } else {
                        dragMode = .move(start: wrist.bandOffsetPoints)
                    }
                }
                switch dragMode {
                case .width(let start, let sign):
                    setWidth(start + 2 * sign * Double(value.translation.height))
                case .move(let start):
                    let limit = Double(band.canvasHeight / 2 - band.halfHeight) - 40
                    wrist.bandOffsetPoints = min(max(start + Double(value.translation.height), -max(limit, 0)), max(limit, 0))
                case nil:
                    break
                }
            }
            .onEnded { _ in dragMode = nil }
    }
}

/// 피부톤 프리셋 6종 중 가장 가까운 것 (03 5-1). 폭을 맞출 때 경계가 보이도록 먼저 고른다
struct SkinPresetView: View {
    @Environment(AppState.self) private var appState
    @Binding var wrist: WristProfile
    @Binding var hasChosen: Bool
    var onBack: (() -> Void)?
    var onNext: () -> Void

    var body: some View {
        CanvasScaffold(scale: appState.scale, wrist: wrist, watch: nil) { _ in
            Color.clear
        } top: { _ in
            VStack(alignment: .leading, spacing: 6) {
                Text("피부톤 고르기").font(.headline)
                Text("폰을 팔에 올리고, 화면 속 손목이 실제 팔과 가장 비슷해 보이는 색을 고르세요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } bottom: { _ in
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(SkinPreset.allCases) { preset in
                        Button {
                            wrist.skinBaseColor = preset.rgb
                            hasChosen = true
                        } label: {
                            ColorChip(rgb: preset.rgb, label: "피부톤 \(preset.rawValue)", isSelected: hasChosen && wrist.skinBaseColor == preset.rgb, size: 40)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("skin.preset.\(preset.rawValue)")
                    }
                }
                HStack(spacing: 10) {
                    if let onBack {
                        Button("이전", action: onBack).buttonStyle(.bordered)
                    }
                    Button {
                        onNext()
                    } label: {
                        Text("다음").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasChosen)
                    .accessibilityIdentifier("skin.next")
                }
            }
        }
        .canvasScreen()
    }
}

/// 같은 자세에서 색조·채도·밝기 미세조정 (03 5-2). 앱이 통제할 수 없는 True Tone 등에 대한 안전장치
struct SkinTuneView: View {
    @Environment(AppState.self) private var appState
    @Binding var wrist: WristProfile
    var doneTitle = "다음"
    var onBack: (() -> Void)?
    var onSkip: (() -> Void)?
    var onDone: () -> Void

    var body: some View {
        CanvasScaffold(scale: appState.scale, wrist: wrist, watch: nil) { _ in
            Color.clear
        } top: { _ in
            VStack(alignment: .leading, spacing: 6) {
                Text("피부톤 미세조정").font(.headline)
                Text("화면 속 손목과 실제 팔의 경계가 보이지 않을 때까지 조절하세요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } bottom: { _ in
            VStack(spacing: 10) {
                slider("색조", value: $wrist.skinHueOffset, range: WristProfile.hueOffsetRange, neutral: 0)
                slider("채도", value: $wrist.skinSaturationScale, range: WristProfile.saturationScaleRange, neutral: 1)
                slider("밝기", value: $wrist.skinBrightnessScale, range: WristProfile.brightnessScaleRange, neutral: 1)
                HStack(spacing: 10) {
                    if let onBack {
                        Button("이전", action: onBack).buttonStyle(.bordered)
                    }
                    if let onSkip {
                        Button("건너뛰기", action: onSkip).buttonStyle(.bordered)
                    }
                    Button {
                        onDone()
                    } label: {
                        Text(doneTitle).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("skinTune.done")
                }
            }
        }
        .canvasScreen()
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, neutral: Double) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .frame(width: 32, alignment: .leading)
            Slider(value: value, in: range)
            Button {
                value.wrappedValue = neutral
            } label: {
                Image(systemName: "arrow.counterclockwise").font(.caption)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(title) 초기화")
        }
    }
}

extension WristProfile {
    mutating func resetSkinAdjustments() {
        skinHueOffset = 0
        skinSaturationScale = 1
        skinBrightnessScale = 1
    }
}

extension Double {
    /// "약 57mm"
    var mmTextInt: String { "약 \(Int(rounded()))mm" }
}

/// 설정 › 손목 다시 맞추기
struct WristRecalibrationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var wrist: WristProfile

    init(wrist: WristProfile) {
        _wrist = State(initialValue: wrist)
    }

    var body: some View {
        WristWidthView(wrist: $wrist, doneTitle: "저장", onBack: { dismiss() }) {
            appState.saveWrist(wrist)
            dismiss()
        }
    }
}

/// 설정 › 피부톤 다시 맞추기: 프리셋 → 미세조정
struct SkinRecalibrationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var wrist: WristProfile
    @State private var tuning = false
    @State private var hasChosen = true

    init(wrist: WristProfile) {
        _wrist = State(initialValue: wrist)
    }

    var body: some View {
        if tuning {
            SkinTuneView(wrist: $wrist, doneTitle: "저장", onBack: { tuning = false }) {
                appState.saveWrist(wrist)
                dismiss()
            }
        } else {
            SkinPresetView(wrist: $wrist, hasChosen: $hasChosen, onBack: { dismiss() }) {
                tuning = true
            }
        }
    }
}
