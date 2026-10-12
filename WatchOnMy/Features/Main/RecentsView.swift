import SwiftUI

/// 프리셋 2종 + 최근 본 시계 5개. 전환 편의일 뿐 동시 비교 화면이 아니다 (04 5절)
struct RecentsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("프리셋") {
                    ForEach(WatchPreset.allCases) { preset in
                        row(preset.savedWatch)
                    }
                }
                Section {
                    ForEach(appState.state.recents) { watch in
                        row(watch)
                    }
                } header: {
                    Text("최근 본 시계")
                } footer: {
                    Text("최근 \(Constants.recentLimit)개까지 기기 안에만 저장합니다. 목록에서 밀려난 사진 시계 이미지는 함께 지워집니다.")
                }
            }
            .navigationTitle("시계 전환")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private func row(_ watch: SavedWatch) -> some View {
        Button {
            appState.select(watch)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                thumbnail(watch.source)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(watch.name).foregroundStyle(.primary)
                    Text(detail(watch.source))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if watch.id == appState.state.current.id {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
        }
        .tint(.primary)
    }

    @ViewBuilder
    private func thumbnail(_ source: WatchSource) -> some View {
        switch source {
        case .parametric(let spec):
            Circle()
                .fill(spec.dialColor.color)
                .overlay { Circle().strokeBorder(Color.gray.opacity(0.7), lineWidth: 3) }
        case .photo(let photo):
            if let image = appState.photos.image(named: photo.imageFileName) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
    }

    private func detail(_ source: WatchSource) -> String {
        switch source {
        case .parametric(let spec):
            "\(spec.caseShape.label) · Ø\(spec.caseDiameterMM.mmText) · L2L \(spec.lugToLugMM.mmText)mm"
        case .photo(let photo):
            "사진 · L2L \(photo.lugToLugMM.mmText)mm"
        }
    }
}
