import SwiftUI

struct WatchListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onCreate: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.state.watches) { watch in
                        Button {
                            model.selectWatch(watch.id)
                            dismiss()
                        } label: {
                            row(for: watch)
                        }
                        .tint(.primary)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { model.state.watches[$0].id }
                        ids.forEach { model.deleteWatch($0) }
                    }
                } footer: {
                    Text("판정 기준 손목 폭 \(model.state.wrist.fitWidthMM.mmText)mm · 왼쪽으로 밀어 삭제")
                }
                Section {
                    Button("예시 시계 복원") { model.restoreSamples() }
                }
            }
            .navigationTitle("시계 목록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onCreate) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("새 시계")
                }
            }
        }
    }

    private func row(for watch: WatchSpec) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(watch.dialColor.rgb.color)
                .frame(width: 26, height: 26)
                .overlay { Circle().strokeBorder(Color.gray.opacity(0.6), lineWidth: 2) }
            VStack(alignment: .leading, spacing: 3) {
                Text(watch.name).font(.body)
                Text("\(watch.shape.label) · \(watch.dimensionSummary)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                let verdict = model.verdict(for: watch)
                Label(verdict.title, systemImage: verdict.level.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(verdict.level.tint)
            }
            Spacer()
            if watch.id == model.selectedWatch?.id {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }
}
