import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var circumferenceText = ""
    @State private var cardMode: CardCalibrationView.Mode?
    @State private var showsWristCalibration = false
    @State private var confirmsReset = false
    private let ambient = AmbientLightMonitor.shared

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                scaleSection
                wristSection

                Section {
                    Picker("크라운 방향", selection: $model.state.crownSide) {
                        ForEach(CrownSide.allCases) { side in
                            Text(side.label).tag(side)
                        }
                    }
                } header: {
                    Text("착용")
                } footer: {
                    Text("좌우 손 구분은 크라운 위치에만 영향을 줍니다. 손목 위 세로 위치는 폰을 움직여 맞춥니다.")
                }

                Section {
                    Toggle("조명 변화 자동 추적", isOn: $model.state.ambientTrackingEnabled)
                    LabeledContent("기준 조명", value: model.state.ambientReference?.summary ?? "없음")
                    LabeledContent("현재 조명", value: ambient.reading?.summary ?? "—")
                } header: {
                    Text("피부톤과 조명")
                } footer: {
                    Text("전면 카메라로 천장광의 색온도와 노출을 읽어, 캘리브레이션 때와 달라진 만큼 피부색을 자동 보정합니다. EV 11 이상(밝은 야외)에서는 경고합니다. True Tone·Night Shift는 앱이 끄거나 읽을 수 없으니 직접 꺼주세요.")
                }

                Section {
                    Toggle("v0.2 방식 비교: 시계 3% 축소", isOn: $model.state.tools.legacyWatchCorrection)
                    Toggle("미등록 기기처럼 동작", isOn: $model.state.tools.simulateUnknownDevice)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("손목 경계 페이드")
                            Spacer()
                            Text("\(model.state.tools.edgeFadeMM.mmText)mm").monospacedDigit().foregroundStyle(.secondary)
                        }
                        Slider(value: $model.state.tools.edgeFadeMM, in: 0...16, step: 1)
                    }
                    Picker("배경", selection: $model.state.tools.background) {
                        ForEach(BackgroundTone.allCases) { tone in
                            Text(tone.label).tag(tone)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("고정 화면 밝기")
                            Spacer()
                            Text("\(Int((model.state.tools.lockedBrightness * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)
                        }
                        Slider(value: $model.state.tools.lockedBrightness, in: 0.2...1, step: 0.05)
                    }
                } header: {
                    Text("테스트 도구")
                } footer: {
                    Text("기본값이 Linear 결정사항입니다(시계 엄격 1:1, 페이드 10mm). 실기 비교·검증용으로만 바꾸세요.")
                }

                Section {
                    Button("온보딩 다시 하기") {
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(400))
                            model.restartOnboarding()
                        }
                    }
                    Button("모든 데이터 초기화", role: .destructive) { confirmsReset = true }
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .confirmationDialog("모든 시계와 캘리브레이션을 지울까요?", isPresented: $confirmsReset, titleVisibility: .visible) {
                Button("초기화", role: .destructive) {
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        model.resetAll()
                    }
                }
            }
        }
        .fullScreenCover(item: $cardMode) { mode in
            CardCalibrationView(mode: mode)
        }
        .fullScreenCover(isPresented: $showsWristCalibration) {
            WristRecalibrationView(skin: model.state.skin, width: model.state.wrist.matchedWidthMM)
        }
        .onAppear {
            circumferenceText = model.state.wrist.circumferenceMM?.mmText ?? ""
        }
        .onChange(of: circumferenceText) { _, text in
            if let value = WatchDraft.parse(text), WristProfile.circumferenceRange.contains(value) {
                model.state.wrist.circumferenceMM = value
            } else if text.trimmingCharacters(in: .whitespaces).isEmpty {
                model.state.wrist.circumferenceMM = nil
            }
        }
    }

    private var scaleSection: some View {
        let scale = model.scale
        let device = model.device
        return Section {
            LabeledContent("기기", value: device.model?.name ?? "미등록")
            LabeledContent("식별자", value: device.identifier)
            LabeledContent("출처", value: scale.sourceDescription)
            LabeledContent("nativeScale", value: String(format: "%.3f", device.nativeScale))
            LabeledContent("1pt", value: String(format: "%.5f mm", scale.mmPerPoint))
            Button("실물 카드로 정확도 확인") { cardMode = .verify }
            Button("신용카드로 스케일 보정") { cardMode = .calibrate }
            if model.state.cardCalibration != nil {
                Button("카드 보정 지우기 (기기 표로 복귀)", role: .destructive) { model.clearCardCalibration() }
            }
        } header: {
            Text("물리 스케일")
        } footer: {
            Text(device.isSimulator
                 ? "시뮬레이터입니다. 계수는 해당 기기 기준으로 계산하지만 Mac 화면에서는 실제 크기가 아닙니다."
                 : "mm/pt = 25.4 × nativeScale ÷ PPI. 카드 보정값이 있으면 기기 표보다 우선합니다.")
        }
    }

    private var wristSection: some View {
        let wrist = model.state.wrist
        let limits = FitVerdict.limits(wristWidth: wrist.fitWidthMM)
        return Section {
            LabeledContent("화면에서 맞춘 폭", value: "\(wrist.matchedWidthMM.mmText)mm")
            LabeledContent("시야각 보정 ×1.083", value: "\(wrist.measuredWidthMM.mmText)mm")
            HStack {
                Text("손목 둘레")
                Spacer()
                TextField("선택 입력", text: $circumferenceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 100)
                Text("mm").foregroundStyle(.secondary)
            }
            if let circumference = wrist.circumferenceMM {
                LabeledContent("둘레 → 폭 (타원 근사)", value: "\(circumference.mmText) → \(WristGeometry.width(fromCircumference: circumference).mmText)mm")
            }
            LabeledContent("판정 기준 폭", value: "\(wrist.fitWidthMM.mmText)mm")
            LabeledContent("L2L 여유 / 경계 상한", value: "\(limits.comfortable.mmText) / \(limits.borderline.mmText)mm")
            Button("손목 굵기·피부톤 다시 맞추기") { showsWristCalibration = true }
        } header: {
            Text("손목")
        } footer: {
            Text("둘레를 입력하면 측정값 대신 둘레로 환산한 폭(폭:두께 1.35 타원)으로 판정합니다. 화면 속 가상 손목 굵기는 바뀌지 않습니다.")
        }
    }
}
