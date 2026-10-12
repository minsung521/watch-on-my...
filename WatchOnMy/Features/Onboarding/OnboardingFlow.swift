import SwiftUI

/// 최초 1회 온보딩 7단계, 카메라 없음 (06 5-1)
struct OnboardingFlow: View {
    @Environment(AppState.self) private var appState

    private enum Step {
        case principle, display, scale, skinPreset, width, skinTune, done
    }

    @State private var step: Step = .principle
    @State private var wrist: WristProfile?
    @State private var hasChosenSkin = false

    var body: some View {
        ZStack {
            switch step {
            case .principle:
                PrincipleStep { step = .display }
            case .display:
                DisplayGuideStep(onBack: { step = .principle }) {
                    // 등록 기기·카드 보정 완료면 스케일 확인은 자동 통과
                    step = appState.scale.isVerified ? .skinPreset : .scale
                }
            case .scale:
                ScaleCheckStep(onBack: { step = .display }) { step = .skinPreset }
            case .skinPreset:
                SkinPresetView(wrist: wristBinding, hasChosen: $hasChosenSkin, onBack: { step = .display }) {
                    step = .width
                }
            case .width:
                // 건너뛰기 불가: 이 값이 없으면 앱이 성립하지 않는다
                WristWidthView(wrist: wristBinding, onBack: { step = .skinPreset }) { step = .skinTune }
            case .skinTune:
                SkinTuneView(wrist: wristBinding, onBack: { step = .width }, onSkip: {
                    wristBinding.wrappedValue.resetSkinAdjustments()
                    step = .done
                }) {
                    step = .done
                }
            case .done:
                DoneStep(wrist: wristBinding.wrappedValue, onBack: { step = .skinTune }) {
                    appState.saveWrist(wristBinding.wrappedValue)
                }
            }
        }
    }

    private var wristBinding: Binding<WristProfile> {
        Binding(
            get: { wrist ?? WristProfile.initial(scale: appState.scale) },
            set: { wrist = $0 }
        )
    }
}

struct OnboardingPage<Content: View, Footer: View>: View {
    let step: String?
    let content: Content
    let footer: Footer

    init(step: String?, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.step = step
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let step {
                    Text(step)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) { footer }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(.bar)
        }
    }
}

// MARK: 1. 원리 설명

private struct PrincipleStep: View {
    var onNext: () -> Void

    var body: some View {
        OnboardingPage(step: "1 / 7") {
            Text("Watch on My...")
                .font(.largeTitle.bold())
            PrincipleIllustration()
                .frame(height: 230)
                .frame(maxWidth: .infinity)
            Text("폰을 팔 위에 **가로질러, 팔과 직각으로** 올립니다.")
                .font(.title3)
            Text("화면이 가린 팔 부분을 화면 속 가상 손목이 대신하고, 그 위에 시계가 실제 크기(1:1)로 그려집니다. 사지도, 가보지도 않고 차보는 방식입니다.")
                .foregroundStyle(.secondary)
            Label("실내에서 사용하세요. 밝은 야외에서는 화면이 팔보다 어두워 보여 착시가 성립하지 않습니다.", systemImage: "lightbulb")
                .font(.subheadline)
        } footer: {
            Button("시작하기", action: onNext)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("onboarding.start")
        }
    }
}

/// 팔(가로)과 그 위에 직각으로 올린 폰(세로)
private struct PrincipleIllustration: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let armHeight = size.height * 0.36
            let phone = CGSize(width: size.height * 0.48, height: size.height * 0.96)
            ZStack {
                RoundedRectangle(cornerRadius: armHeight / 2)
                    .fill(SkinPreset.p4.rgb.color)
                    .frame(width: size.width * 0.96, height: armHeight)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black)
                    .frame(width: phone.width, height: phone.height)
                    .overlay {
                        ZStack {
                            Rectangle()
                                .fill(SkinPreset.p4.rgb.color)
                                .frame(height: armHeight)
                            Circle()
                                .fill(Color(white: 0.85))
                                .frame(width: armHeight * 0.8)
                                .overlay { Circle().fill(Color(white: 0.1)).padding(armHeight * 0.08) }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(5)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.gray, lineWidth: 2)
                    }
                    .shadow(radius: 6)
                Text("팔")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.6))
                    .position(x: size.width * 0.12, y: size.height / 2)
                Image(systemName: "arrow.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.black.opacity(0.5))
                    .position(x: size.width * 0.88, y: size.height / 2)
            }
            .frame(width: size.width, height: size.height)
        }
        .accessibilityElement()
        .accessibilityLabel("가로로 놓인 팔 위에 폰을 세로로, 팔과 직각으로 올린 그림")
    }
}

// MARK: 2. 화면 설정 안내

private struct DisplayGuideStep: View {
    var onBack: () -> Void
    var onNext: () -> Void

    var body: some View {
        OnboardingPage(step: "2 / 7") {
            Text("화면 설정 확인")
                .font(.title.bold())
            Text("True Tone과 Night Shift는 주변 조명에 맞춰 화면 색을 바꿉니다. 앱이 끄거나 켜져 있는지 확인할 수 없어 직접 꺼주셔야 합니다.")
                .foregroundStyle(.secondary)
            GuideRow(symbol: "sun.max", title: "True Tone 끄기", detail: "설정 › 디스플레이 및 밝기 › True Tone")
            GuideRow(symbol: "moon", title: "Night Shift 끄기", detail: "설정 › 디스플레이 및 밝기 › Night Shift")
            GuideRow(symbol: "sun.min", title: "밝기는 앱이 고정합니다", detail: "손목 화면이 보이는 동안 밝기를 85%로 고정하고, 나가면 원래대로 돌려놓습니다.")
        } footer: {
            Button("끄고 왔어요", action: onNext)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("onboarding.displayDone")
            HStack {
                Button("이전", action: onBack)
                Spacer()
                Button("그냥 진행", action: onNext)
                    .accessibilityIdentifier("onboarding.displaySkip")
            }
        }
    }
}

private struct GuideRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: 3. 스케일 확인 (미등록 기기만)

private struct ScaleCheckStep: View {
    @Environment(AppState.self) private var appState
    var onBack: () -> Void
    var onNext: () -> Void
    @State private var showsCard = false

    var body: some View {
        let scale = appState.scale
        OnboardingPage(step: "3 / 7") {
            Text("화면 크기 확인")
                .font(.title.bold())
            if scale.isVerified {
                NoticeBanner(symbol: "checkmark.seal.fill", title: "카드로 보정했습니다", message: "1pt = \(String(format: "%.5f", scale.mmPerPoint))mm", tint: .green)
            } else {
                NoticeBanner(
                    symbol: "exclamationmark.triangle.fill",
                    title: "이 기기는 아직 검증되지 않았습니다",
                    message: "\(appState.device.identifier) · 가장 흔한 460ppi로 가정하고 계속할 수 있습니다. 신용카드 한 장으로 맞추면 실제 크기가 정확해집니다.",
                    actionTitle: "카드로 보정하기",
                    action: { showsCard = true }
                )
                .accessibilityIdentifier("onboarding.provisionalBanner")
            }
        } footer: {
            Button("계속", action: onNext)
                .buttonStyle(PrimaryButtonStyle())
            Button("이전", action: onBack)
        }
        .fullScreenCover(isPresented: $showsCard) {
            CardCalibrationView(mode: .calibrate)
        }
    }
}

// MARK: 7. 완료

private struct DoneStep: View {
    @Environment(AppState.self) private var appState
    let wrist: WristProfile
    var onBack: () -> Void
    var onFinish: () -> Void

    var body: some View {
        let trueWidth = WristProfile.trueWidthMM(matchedWidthPoints: wrist.matchedWidthPoints, scale: appState.scale)
        OnboardingPage(step: "7 / 7") {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("준비됐어요")
                .font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 6) {
                Text("측정된 손목 폭")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(trueWidth.mmTextInt)
                    .font(.system(size: 44, weight: .bold).monospacedDigit())
                    .accessibilityIdentifier("onboarding.trueWidth")
            }
            Text("화면에서 맞춘 폭에 시야각 보정(×1.083)을 적용한 값입니다. 시야 거리에 따라 ±3mm 정도 차이가 날 수 있어 '약'으로 표시합니다. 시계는 보정 없이 항상 1:1로 그립니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } footer: {
            Button("시계 차보기", action: onFinish)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("onboarding.finish")
            Button("이전", action: onBack)
        }
    }
}
