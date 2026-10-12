import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var cardMode: CardCalibrationView.Mode?
    @State private var showsWristRecalibration = false
    @State private var showsSkinRecalibration = false
    @State private var confirmsReset = false

    var body: some View {
        NavigationStack {
            Form {
                wristSection
                scaleSection

                Section {
                    Label("실내에서 사용하세요. 밝은 야외에서는 착시가 성립하지 않습니다.", systemImage: "lightbulb")
                    Label("True Tone과 Night Shift는 꺼두세요. 설정 › 디스플레이 및 밝기", systemImage: "sun.max")
                    Label("사진 시계는 정면 사진이어야 정확합니다. 비스듬한 사진은 실제보다 작게 그려집니다.", systemImage: "photo")
                } header: {
                    Text("사용 안내")
                }
                .font(.footnote)

                Section {
                    LabeledContent("버전", value: Self.versionText)
                    Button("온보딩 다시 하기") {
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(400))
                            appState.restartOnboarding()
                        }
                    }
                    Button("모든 데이터 초기화", role: .destructive) { confirmsReset = true }
                } header: {
                    Text("앱")
                } footer: {
                    Text("모든 데이터는 이 기기 안에만 있습니다. 서버로 보내지 않습니다.")
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .confirmationDialog("손목·스케일 보정과 최근 시계를 모두 지울까요?", isPresented: $confirmsReset, titleVisibility: .visible) {
                Button("초기화", role: .destructive) {
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        appState.resetAll()
                    }
                }
            }
        }
        .fullScreenCover(item: $cardMode) { mode in
            CardCalibrationView(mode: mode)
        }
        .fullScreenCover(isPresented: $showsWristRecalibration) {
            if let wrist = appState.state.wrist {
                WristRecalibrationView(wrist: wrist)
            }
        }
        .fullScreenCover(isPresented: $showsSkinRecalibration) {
            if let wrist = appState.state.wrist {
                SkinRecalibrationView(wrist: wrist)
            }
        }
    }

    private var wristSection: some View {
        Section {
            if let wrist = appState.state.wrist {
                LabeledContent("측정된 손목 폭", value: wrist.trueWidthText)
                    .accessibilityIdentifier("settings.trueWidth")
            }
            Button("손목 다시 맞추기") { showsWristRecalibration = true }
            Button("피부톤 다시 맞추기") { showsSkinRecalibration = true }
        } header: {
            Text("손목")
        } footer: {
            Text("화면에서 맞춘 폭에 시야각 보정(×1.083)을 적용한 값입니다. ±3mm 정도 차이가 날 수 있습니다.")
        }
    }

    private var scaleSection: some View {
        let scale = appState.scale
        let device = appState.device
        return Section {
            LabeledContent("기기", value: device.model?.name ?? "미등록")
            LabeledContent("식별자", value: device.identifier)
            LabeledContent("출처", value: scale.sourceDescription)
            LabeledContent("1pt", value: String(format: "%.5f mm", scale.mmPerPoint))
            Button("카드로 정확도 확인") { cardMode = .verify }
            Button("스케일 다시 보정") { cardMode = .calibrate }
            if appState.state.cardCalibration != nil {
                Button("카드 보정 지우기 (기기 표로 복귀)", role: .destructive) { appState.clearCardCalibration() }
            }
        } header: {
            Text("화면 스케일")
        } footer: {
            Text(device.isSimulator
                 ? "시뮬레이터입니다. 계수는 해당 기기 기준이지만 Mac 화면에서는 실제 크기가 아닙니다."
                 : "mm/pt = 25.4 × nativeScale ÷ PPI. 카드 보정값이 있으면 기기 표보다 우선합니다.")
        }
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }
}
