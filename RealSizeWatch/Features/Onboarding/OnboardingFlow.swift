import SwiftUI

/// 최초 1회: 기기 스케일 확인 → 화면 설정 안내 → 피부톤 샘플 → 손목 굵기 맞추기 (MIN-44, MIN-45)
struct OnboardingFlow: View {
    @Environment(AppModel.self) private var model

    private enum Step {
        case welcome, display, skin, wrist, done
    }

    @State private var step: Step = .welcome
    @State private var skin = SkinTone(base: SkinPreset.medium.rgb, source: .preset)
    @State private var hasChosenSkin = false
    @State private var matchedWidth = WristProfile.defaultMatchedWidthMM
    @State private var ambient: AmbientReading?

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeStep { step = .display }
            case .display:
                DisplayGuideStep(onBack: { step = .welcome }) { step = .skin }
            case .skin:
                SkinSampleStep(skin: $skin, hasChosen: $hasChosenSkin, onBack: { step = .display }) { step = .wrist }
            case .wrist:
                WristCalibrationView(skin: $skin, matchedWidth: $matchedWidth, cancelTitle: "이전", onCancel: { step = .skin }) { reading in
                    ambient = reading
                    step = .done
                }
            case .done:
                OnboardingDoneStep(matchedWidth: matchedWidth, onBack: { step = .wrist }) {
                    model.completeOnboarding(matchedWidthMM: matchedWidth, skin: skin, ambient: ambient)
                }
            }
        }
        .onAppear {
            matchedWidth = model.state.wrist.matchedWidthMM
            skin = model.state.skin
        }
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

private struct WelcomeStep: View {
    @Environment(AppModel.self) private var model
    var onNext: () -> Void
    @State private var showsCardCalibration = false

    var body: some View {
        let scale = model.scale
        OnboardingPage(step: "1 / 4") {
            Image(systemName: "watch.analog")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
            Text("Real Size Watch")
                .font(.largeTitle.bold())
            Text("아이폰을 손목 위에 올리면, 화면이 가린 팔 부분을 가상 손목으로 채우고 그 위에 시계를 실제 크기(1:1)로 그립니다. 사지도, 가보지도 않고 차보는 경험입니다.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Label(model.device.model?.name ?? "미등록 기기", systemImage: "iphone")
                    .font(.headline)
                Text("1pt = \(String(format: "%.4f", scale.mmPerPoint))mm · \(scale.sourceDescription)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                if model.device.isSimulator {
                    Text("시뮬레이터: 계수는 해당 기기 기준이지만 Mac 화면에서는 실제 크기가 아닙니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if scale.source == .provisional {
                NoticeBanner(
                    symbol: "exclamationmark.triangle.fill",
                    title: "미등록 기기 (\(model.device.identifier))",
                    message: "가장 흔한 460ppi로 가정하고 계속합니다. 신용카드 한 장으로 맞추면 정확해집니다.",
                    actionTitle: "신용카드로 맞추기",
                    action: { showsCardCalibration = true }
                )
                .accessibilityIdentifier("onboarding.provisionalBanner")
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("실내 조명 아래에서", systemImage: "lightbulb")
                Label("1분 정도", systemImage: "clock")
                Label("신용카드 한 장 (정확도 확인용, 선택)", systemImage: "creditcard")
            }
            .font(.subheadline)
        } footer: {
            Button("시작하기", action: onNext)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("onboarding.start")
        }
        .fullScreenCover(isPresented: $showsCardCalibration) {
            CardCalibrationView(mode: .calibrate)
        }
    }
}

private struct DisplayGuideStep: View {
    var onBack: () -> Void
    var onNext: () -> Void

    var body: some View {
        OnboardingPage(step: "2 / 4") {
            Text("화면 설정 확인")
                .font(.title.bold())
            Text("피부색을 맞추려면 화면이 내는 색이 고정되어 있어야 합니다. 아래 두 기능은 앱이 끄거나 상태를 읽을 수 없어 직접 확인해 주세요.")
                .foregroundStyle(.secondary)
            GuideRow(symbol: "sun.max", title: "True Tone 끄기", detail: "설정 › 디스플레이 및 밝기 › True Tone")
            GuideRow(symbol: "moon", title: "Night Shift 끄기", detail: "설정 › 디스플레이 및 밝기 › Night Shift")
            GuideRow(symbol: "lightbulb", title: "실내에서 사용", detail: "밝은 야외에서는 팔이 화면 최대 밝기보다 밝아져 착시가 성립하지 않습니다. 너무 밝으면 앱이 경고합니다.")
            GuideRow(symbol: "sun.min", title: "밝기는 앱이 고정", detail: "손목 화면에서는 자동 밝기 대신 고정 밝기를 쓰고, 나가면 원래대로 돌려놓습니다.")
        } footer: {
            Button("확인했어요", action: onNext)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("onboarding.displayDone")
            Button("이전", action: onBack)
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

private struct OnboardingDoneStep: View {
    @Environment(AppModel.self) private var model
    let matchedWidth: Double
    var onBack: () -> Void
    var onFinish: () -> Void

    var body: some View {
        let measured = matchedWidth * WristProfile.viewingCorrection
        let limits = FitVerdict.limits(wristWidth: measured)
        OnboardingPage(step: nil) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("준비됐어요")
                .font(.largeTitle.bold())
            VStack(spacing: 10) {
                LabeledContent("화면에서 맞춘 폭", value: "\(matchedWidth.mmText)mm")
                LabeledContent("시야각 보정 ×1.083", value: "\(measured.mmText)mm")
                Divider()
                LabeledContent("L2L 여유 상한", value: "\(limits.comfortable.mmText)mm")
                LabeledContent("L2L 경계 상한", value: "\(limits.borderline.mmText)mm")
            }
            .font(.subheadline.monospacedDigit())
            .padding(14)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("시계는 보정 없이 항상 1:1로 그립니다. 손목 폭만 시야각 보정을 거쳐 저장하고, 핏 판정에 씁니다. 경계 구간에서는 판정 대신 '취향의 영역'이라고 알려드려요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } footer: {
            Button("시계 차보기", action: onFinish)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("onboarding.finish")
            Button("손목 다시 맞추기", action: onBack)
        }
    }
}
