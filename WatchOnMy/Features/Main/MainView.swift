import SwiftUI

/// 메인: 손목 띠 위 실제 크기 시계. 조작 요소는 띠 바깥 검정 영역에만 둔다 (05 3절, 06 4절)
struct MainView: View {
    @Environment(AppState.self) private var appState
    @State private var showsChrome = true
    @State private var draft = SpecDraft(spec: .standard())
    @State private var isEditing = false
    @State private var editTarget: SavedWatch?
    @State private var editorDetent = MainView.editorDetent
    @State private var showsRecents = false
    @State private var showsImport = false
    @State private var showsSettings = false
    @State private var showsCard = false

    static let editorFraction: CGFloat = 0.46
    static let editorDetent = PresentationDetent.fraction(editorFraction)

    var body: some View {
        let scale = appState.scale
        GeometryReader { proxy in
            CanvasScaffold(scale: scale, wrist: wrist, watch: displayedWatch) { _ in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isEditing else { return }
                        withAnimation(.easeInOut(duration: 0.2)) { showsChrome.toggle() }
                    }
                    .accessibilityIdentifier("main.canvas")
            } top: { _ in
                topArea(scale: scale)
            } bottom: { _ in
                if showsChrome, !isEditing {
                    bottomBar.transition(.opacity)
                }
            }
            // 스펙 편집 시트가 아래 절반을 덮으면, 실제 크기는 그대로 둔 채 보이는 영역으로 옮긴다
            .offset(y: isEditing && editorDetent == Self.editorDetent ? -(proxy.size.height + proxy.safeAreaInsets.top) * Self.editorFraction / 2 : 0)
            .animation(.spring(duration: 0.35), value: isEditing && editorDetent == Self.editorDetent)
        }
        .background(Color.black.ignoresSafeArea())
        .canvasScreen(isActive: !showsSettings && !showsImport && !showsCard && !(isEditing && editorDetent == .large))
        .sheet(isPresented: $isEditing, onDismiss: commitEdit) {
            SpecEditorView(draft: $draft)
                .presentationDetents([Self.editorDetent, .large], selection: $editorDetent)
                .presentationBackgroundInteraction(.enabled(upThrough: Self.editorDetent))
                .presentationContentInteraction(.scrolls)
        }
        .sheet(isPresented: $showsRecents) {
            RecentsView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .fullScreenCover(isPresented: $showsImport) { PhotoImportView() }
        .fullScreenCover(isPresented: $showsCard) { CardCalibrationView(mode: .calibrate) }
    }

    private var wrist: WristProfile {
        appState.state.wrist ?? WristProfile.initial(scale: appState.scale)
    }

    private var displayedWatch: WatchSource? {
        if isEditing {
            return draft.spec.map(WatchSource.parametric)
        }
        return appState.state.current.source
    }

    // MARK: 검정 영역

    @ViewBuilder
    private func topArea(scale: PhysicalScale) -> some View {
        VStack(spacing: 8) {
            // 미검증 기기 배너는 상시 노출 (01 3-3)
            if !scale.isVerified {
                Button {
                    showsCard = true
                } label: {
                    Label("이 기기는 아직 검증되지 않았습니다 — 카드로 보정하기", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.leading)
                }
                .accessibilityIdentifier("main.provisionalBanner")
            }
            if isEditing, draft.spec == nil {
                Text("L2L과 직경을 입력하면 실제 크기로 그려집니다")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if showsChrome, !isEditing {
                Text(appState.state.current.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("main.watchName")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                chromeButton("스펙 편집", symbol: "slider.horizontal.3", id: "main.edit") { startEditing() }
                chromeButton("사진으로 보기", symbol: "photo", id: "main.photo") { showsImport = true }
                chromeButton("최근", symbol: "clock.arrow.circlepath", id: "main.recents") { showsRecents = true }
                chromeButton("설정", symbol: "gearshape", id: "main.settings") { showsSettings = true }
            }
            Text("화면을 탭하면 버튼이 숨겨집니다")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }

    private func chromeButton(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.body)
                Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(id)
    }

    // MARK: 스펙 편집 (04 A)

    private func startEditing() {
        let current = appState.state.current
        if case .parametric(let spec) = current.source {
            draft = SpecDraft(spec: spec)
        } else {
            draft = SpecDraft(spec: .standard())
        }
        editTarget = current
        editorDetent = Self.editorDetent
        isEditing = true
    }

    /// 시트를 내리면 반영. 별도 확인 버튼은 없다. 바뀐 게 있을 때만 최근 목록에 들어간다
    private func commitEdit() {
        draft.commitClamping()
        guard let spec = draft.spec, let target = editTarget else { return }
        if case .parametric(let original) = target.source, original == spec { return }
        // 프리셋이나 사진을 고쳤다면 새 항목, 직접 입력한 시계를 고쳤다면 같은 항목을 갱신
        let reuse = !WatchPreset.isPreset(target.id) && target.source.photoFileName == nil
        appState.select(SavedWatch(id: reuse ? target.id : UUID(), name: spec.autoName, source: .parametric(spec)))
        editTarget = nil
    }
}
