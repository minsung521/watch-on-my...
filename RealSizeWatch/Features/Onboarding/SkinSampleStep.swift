import SwiftUI

struct SkinSampleStep: View {
    @Binding var skin: SkinTone
    @Binding var hasChosen: Bool
    var onBack: () -> Void
    var onNext: () -> Void

    @State private var sampler = SkinSampler()

    var body: some View {
        OnboardingPage(step: "3 / 4") {
            Text("피부톤 정하기")
                .font(.title.bold())
            Text("폰을 팔에 올리기 전에, 시계가 닿을 손목 윗면을 후면 카메라로 5~10cm 거리에서 비춰 색을 샘플링합니다. 화이트밸런스는 D65로 고정해 조명색이 지워지지 않게 합니다.")
                .foregroundStyle(.secondary)
            cameraSection
            presetSection
            HStack(spacing: 12) {
                Circle()
                    .fill(skin.base.color)
                    .frame(width: 28, height: 28)
                    .overlay { Circle().strokeBorder(.quaternary) }
                Text(hasChosen ? "선택됨 · \(skin.source == .camera ? "카메라 샘플" : "프리셋")" : "아직 고르지 않았어요")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("다음 단계에서 폰을 팔에 올린 채 밝기와 색온도를 직접 미세조정합니다. True Tone 때문에 자동 정합만으로는 정확할 수 없어 수동 조정이 필수입니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } footer: {
            Button("다음: 손목 맞추기") {
                sampler.stop()
                onNext()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!hasChosen)
            .accessibilityIdentifier("skin.next")
            Button("이전", action: onBack)
        }
        .onAppear { sampler.start() }
        .onDisappear { sampler.stop() }
    }

    @ViewBuilder
    private var cameraSection: some View {
        switch sampler.status {
        case .running, .starting, .idle:
            VStack(spacing: 12) {
                ZStack {
                    if let session = sampler.session, sampler.status == .running {
                        CameraPreview(session: session)
                    } else {
                        Color.black
                        ProgressView().tint(.white)
                    }
                    Circle()
                        .strokeBorder(.white, lineWidth: 2)
                        .frame(width: 92, height: 92)
                        .shadow(radius: 2)
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                HStack(spacing: 12) {
                    Circle()
                        .fill((sampler.liveColor ?? RGB(0.5, 0.5, 0.5)).color)
                        .frame(width: 40, height: 40)
                        .overlay { Circle().strokeBorder(.quaternary) }
                    Text("원 안의 평균색")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("이 색으로") {
                        guard let color = sampler.liveColor else { return }
                        skin = SkinTone(base: color, source: .camera)
                        hasChosen = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(sampler.liveColor == nil)
                }
            }
        case .unavailable:
            NoticeBanner(
                symbol: "camera",
                title: "카메라를 쓸 수 없어요",
                message: "시뮬레이터처럼 후면 카메라가 없는 환경입니다. 아래 프리셋에서 고르세요.",
                tint: .gray
            )
        case .denied:
            NoticeBanner(
                symbol: "camera",
                title: "카메라 권한이 없어요",
                message: "설정에서 카메라를 허용하거나, 아래 프리셋에서 고르세요.",
                actionTitle: "설정 열기",
                action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            )
        case .failed:
            NoticeBanner(symbol: "camera", title: "카메라를 시작하지 못했어요", message: "아래 프리셋에서 고르세요.")
        }
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sampler.status == .unavailable ? "프리셋" : "또는 프리셋")
                .font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 14) {
                ForEach(SkinPreset.allCases) { preset in
                    Button {
                        skin = SkinTone(base: preset.rgb, source: .preset)
                        hasChosen = true
                    } label: {
                        VStack(spacing: 6) {
                            Swatch(rgb: preset.rgb, label: preset.label, isSelected: hasChosen && skin.base == preset.rgb, size: 44)
                            Text(preset.label).font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("skin.preset.\(preset.rawValue)")
                }
            }
        }
    }
}
