import SwiftUI

/// 시계 스펙 직접 입력. 값이 바뀌면 뒤의 손목 캔버스에 실제 크기로 즉시 반영된다 (MIN-47).
/// 브랜드/모델 검색이나 DB 없이 임의 스펙만 받는다.
struct SpecEditorView: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: WatchDraft
    var onCancel: () -> Void
    var onSave: (WatchSpec) -> Void
    var onDelete: (() -> Void)?

    @FocusState private var focusedField: Field?

    private enum Field {
        case lugToLug, diameter, name
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let spec = draft.spec {
                        FitBadge(verdict: model.verdict(for: spec), showsMessage: true)
                    } else {
                        Text("L2L과 직경을 입력하면 실제 크기 렌더링과 핏 판정이 시작됩니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    measurementField("러그 투 러그", text: $draft.lugToLugText, placeholder: "예: 48", field: .lugToLug, id: "editor.l2l")
                    measurementField("케이스 직경", text: $draft.diameterText, placeholder: "예: 40", field: .diameter, id: "editor.diameter")
                } header: {
                    Text("필수")
                } footer: {
                    if !draft.issues.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(draft.issues, id: \.self) { issue in
                                Text(issue.message)
                            }
                        }
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("editor.issues")
                    }
                }

                Section("케이스") {
                    Picker("형상", selection: $draft.shape) {
                        ForEach(CaseShape.allCases) { shape in
                            Text(shape.label).tag(shape)
                        }
                    }
                    .pickerStyle(.segmented)
                    sliderRow("러그 폭", value: $draft.lugWidth, in: 10...28, step: 1, display: "\(draft.lugWidth.mmText)mm")
                    sliderRow("베젤 두께", value: $draft.bezelRatio, in: 0...0.3, step: 0.01, display: "반경의 \(Int((draft.bezelRatio * 100).rounded()))%")
                    sliderRow("두께", value: $draft.thickness, in: 5...20, step: 0.5, display: "\(draft.thickness.mmText)mm")
                }

                Section("다이얼") {
                    swatchRow(DialColor.allCases, selection: $draft.dialColor, rgb: \.rgb, label: \.label)
                }

                Section("스트랩") {
                    swatchRow(StrapColor.allCases, selection: $draft.strapColor, rgb: \.rgb, label: \.label)
                }

                if let spec = draft.spec {
                    Section("측면 · 두께") {
                        SideProfileView(
                            spec: spec,
                            mmPerPoint: model.scale.mmPerPoint,
                            wristWidthMM: model.state.wrist.fitWidthMM,
                            skin: model.state.skin.rendered()
                        )
                        .frame(height: 130)
                    }
                }

                Section("이름") {
                    TextField(draft.spec.map { "자동: \($0.name)" } ?? "비워두면 자동으로 지어요", text: $draft.name)
                        .focused($focusedField, equals: .name)
                }

                if let onDelete {
                    Section {
                        Button("이 시계 삭제", role: .destructive, action: onDelete)
                    }
                }
            }
            .navigationTitle(draft.isNew ? "새 시계" : "스펙 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: onCancel)
                        .accessibilityIdentifier("editor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        if let spec = draft.spec { onSave(spec) }
                    }
                    .disabled(draft.spec == nil)
                    .accessibilityIdentifier("editor.save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") { focusedField = nil }
                }
            }
        }
    }

    private func measurementField(_ title: String, text: Binding<String>, placeholder: String, field: Field, id: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
                .focused($focusedField, equals: field)
                .accessibilityIdentifier(id)
            Text("mm").foregroundStyle(.secondary)
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, display: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(display)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func swatchRow<Option: Identifiable & Hashable>(_ options: [Option], selection: Binding<Option>, rgb: KeyPath<Option, RGB>, label: KeyPath<Option, String>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(options) { option in
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        VStack(spacing: 4) {
                            Swatch(rgb: option[keyPath: rgb], label: option[keyPath: label], isSelected: selection.wrappedValue == option)
                            Text(option[keyPath: label]).font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
