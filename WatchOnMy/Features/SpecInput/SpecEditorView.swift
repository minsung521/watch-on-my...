import SwiftUI

/// 스펙 직접 입력 (04 A). L2L·직경만 필수, 나머지는 "세부 설정"에 접어 둔다.
/// 값이 바뀌면 렌더링이 즉시 갱신된다 — 별도 확인 버튼 없음
struct SpecEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Binding var draft: SpecDraft
    @State private var showsDetails = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case lugToLug, diameter
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    numberRow("러그 투 러그", text: $draft.lugToLugText, range: WatchSpec.lugToLugRange, field: .lugToLug, id: "editor.l2l")
                    numberRow("케이스 직경", text: $draft.diameterText, range: WatchSpec.caseDiameterRange, field: .diameter, id: "editor.diameter")
                } header: {
                    Text("필수")
                } footer: {
                    let notices = draft.notices
                    if !notices.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(notices, id: \.self) { notice in
                                Text(notice.message)
                                    .foregroundStyle(notice.isBlocking ? Color.red : Color.orange)
                            }
                        }
                        .accessibilityIdentifier("editor.notices")
                    }
                }

                Section {
                    DisclosureGroup("세부 설정", isExpanded: $showsDetails) {
                        details
                    }
                }
            }
            .navigationTitle("스펙 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                        .accessibilityIdentifier("editor.done")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("입력 완료") { focusedField = nil }
                }
            }
            .onChange(of: focusedField) { _, _ in
                draft.commitClamping()
            }
        }
    }

    @ViewBuilder
    private var details: some View {
        Picker("형상", selection: $draft.caseShape) {
            ForEach(CaseShape.allCases) { shape in
                Text(shape.label).tag(shape)
            }
        }
        .pickerStyle(.segmented)

        Stepper(value: lugWidthBinding, in: WatchSpec.lugWidthRange, step: 2) {
            HStack {
                Text("러그 폭")
                Spacer()
                Text("\(draft.lugWidthMM.mmText)mm\(draft.customLugWidthMM == nil ? " (기본)" : "")")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        if draft.customLugWidthMM != nil {
            Button("러그 폭 기본값으로 (직경 × 0.45)") { draft.customLugWidthMM = nil }
                .font(.footnote)
        }

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("베젤 두께")
                Spacer()
                Text("직경의 \(Int((draft.bezelRatio * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $draft.bezelRatio, in: WatchSpec.bezelRatioRange, step: 0.01)
        }

        Stepper(value: $draft.thicknessMM, in: WatchSpec.thicknessRange, step: 0.5) {
            HStack {
                Text("두께")
                Spacer()
                Text("\(draft.thicknessMM.mmText)mm").monospacedDigit().foregroundStyle(.secondary)
            }
        }

        Picker("크라운 방향", selection: $draft.crownSide) {
            ForEach(CrownSide.allCases) { side in
                Text(side.label).tag(side)
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("다이얼")
            chips(DialPreset.allCases.map { ($0.label, $0.rgb) }, selection: $draft.dialColor)
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("스트랩")
            chips(StrapPreset.allCases.map { ($0.label, $0.rgb) }, selection: $draft.strapColor)
        }

        if let spec = draft.spec, let wrist = appState.state.wrist {
            VStack(alignment: .leading, spacing: 4) {
                Text("측면 (두께)")
                SideProfileView(spec: spec, scale: appState.scale, wristWidthMM: wrist.trueWidthMM, skin: wrist.skinColor)
                    .frame(height: 120)
            }
        }
    }

    private var lugWidthBinding: Binding<Double> {
        Binding(get: { draft.lugWidthMM }, set: { draft.customLugWidthMM = $0 })
    }

    /// 키보드 직접 입력이 1급 경로, 스테퍼는 0.5mm 미세조정
    private func numberRow(_ title: String, text: Binding<String>, range: ClosedRange<Double>, field: Field, id: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer()
            TextField("\(range.lowerBound.mmText)~\(range.upperBound.mmText)", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 70)
                .focused($focusedField, equals: field)
                .accessibilityIdentifier(id)
            Text("mm").foregroundStyle(.secondary)
            Stepper(title, value: Binding(
                get: { SpecDraft.parse(text.wrappedValue).map { min(max($0, range.lowerBound), range.upperBound) } ?? range.lowerBound },
                set: { text.wrappedValue = $0.mmText }
            ), in: range, step: 0.5)
            .labelsHidden()
        }
    }

    private func chips(_ options: [(label: String, rgb: RGB)], selection: Binding<RGB>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(options, id: \.label) { option in
                    Button {
                        selection.wrappedValue = option.rgb
                    } label: {
                        VStack(spacing: 4) {
                            ColorChip(rgb: option.rgb, label: option.label, isSelected: selection.wrappedValue == option.rgb)
                            Text(option.label).font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
