import SwiftUI

/// ④ 가상 손목 위에 실제 크기 시계 렌더링 → ⑤ 팔에 올려 확인 → ⑥ 좌우로 밀어 다른 시계로 전환 (MIN-49)
struct TryOnView: View {
    @Environment(AppModel.self) private var model
    @State private var showsChrome = true
    /// 시트가 닫히는 동안에도 편집 뷰가 값을 읽으므로 옵셔널 대신 플래그로 표시 여부를 관리한다
    @State private var draft = WatchDraft.blank()
    @State private var isEditing = false
    @State private var editorDetent = TryOnView.editorDetent
    @State private var showsList = false
    @State private var createsAfterList = false
    @State private var showsSettings = false
    @State private var showsCardCalibration = false
    private let ambient = AmbientLightMonitor.shared

    static let editorFraction: CGFloat = 0.46
    static let editorDetent = PresentationDetent.fraction(editorFraction)

    var body: some View {
        let state = model.state
        ZStack {
            state.tools.background.rgb.color.ignoresSafeArea()
            GeometryReader { proxy in
                WristSceneView(scene: scene)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isEditing else { return }
                        withAnimation(.easeInOut(duration: 0.2)) { showsChrome.toggle() }
                    }
                    .gesture(switchGesture)
                    .accessibilityIdentifier("tryon.canvas")
                    // 편집 시트가 아래 절반을 덮으면, 실제 크기는 그대로 둔 채 위쪽 보이는 영역으로 옮긴다
                    .offset(y: isEditorAtHalfHeight ? -proxy.size.height * Self.editorFraction / 2 : 0)
                    .animation(.spring(duration: 0.35), value: isEditorAtHalfHeight)
            }
            .ignoresSafeArea()

            if isEditing, draft.spec == nil {
                VStack {
                    Text("L2L과 직경을 입력하면\n실제 크기로 그려집니다")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 70)
                    Spacer()
                }
            }

            if showsChrome, !isEditing {
                chrome.transition(.opacity)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .calibratedScreen(brightness: state.tools.lockedBrightness)
        .onAppear { if model.state.ambientTrackingEnabled { ambient.acquire() } }
        .onDisappear { if model.state.ambientTrackingEnabled { ambient.release() } }
        .onChange(of: state.ambientTrackingEnabled) { _, enabled in
            if enabled { ambient.acquire() } else { ambient.release() }
        }
        .sheet(isPresented: $isEditing) { editorSheet }
        .sheet(isPresented: $showsList, onDismiss: {
            if createsAfterList {
                createsAfterList = false
                startNewWatch()
            }
        }) {
            WatchListView {
                createsAfterList = true
                showsList = false
            }
        }
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .fullScreenCover(isPresented: $showsCardCalibration) { CardCalibrationView(mode: .calibrate) }
    }

    private var scene: WristScene {
        let state = model.state
        let current = state.ambientTrackingEnabled ? ambient.reading : nil
        let watch = isEditing ? draft.spec : model.selectedWatch
        return WristScene(
            mmPerPoint: model.scale.mmPerPoint,
            watchFactor: model.watchDrawingFactor,
            wristMatchedMM: state.wrist.matchedWidthMM,
            skin: state.skin.rendered(reference: state.ambientReference, current: current),
            background: state.tools.background.rgb,
            edgeFadeMM: state.tools.edgeFadeMM,
            watch: watch,
            crownSide: state.crownSide
        )
    }

    private var isEditorAtHalfHeight: Bool {
        isEditing && editorDetent == Self.editorDetent
    }

    private var switchGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard !isEditing else { return }
                let dx = value.translation.width
                guard abs(dx) > 50, abs(dx) > abs(value.translation.height) * 1.4 else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.selectWatch(offset: dx < 0 ? 1 : -1)
                }
            }
    }

    // MARK: 크롬

    private var chrome: some View {
        VStack(spacing: 8) {
            if model.scale.source == .provisional {
                NoticeBanner(
                    symbol: "exclamationmark.triangle.fill",
                    title: "미등록 기기 · 잠정 스케일",
                    message: "460ppi로 가정해 그리고 있어요. 신용카드로 맞추면 정확해집니다.",
                    actionTitle: "신용카드로 맞추기",
                    action: { showsCardCalibration = true }
                )
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityIdentifier("tryon.provisionalBanner")
            }
            if model.state.ambientTrackingEnabled, ambient.reading?.isTooBright == true {
                NoticeBanner(
                    symbol: "sun.max.trianglebadge.exclamationmark",
                    title: "너무 밝아요",
                    message: "팔이 화면보다 밝아 착시가 성립하지 않습니다. 그늘이나 실내로 이동하세요."
                )
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            header
            Spacer(minLength: 0)
            bottomBar
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var header: some View {
        if let watch = model.selectedWatch {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(watch.name)
                        .font(.headline)
                        .lineLimit(1)
                        .accessibilityIdentifier("tryon.watchName")
                    Spacer(minLength: 8)
                    Text(watch.dimensionSummary)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                FitBadge(verdict: model.verdict(for: watch), showsMessage: true)
            }
            .chromePanel()
        } else {
            Text("시계가 없습니다. 아래에서 새 시계를 추가하세요.")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .chromePanel()
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let index = model.selectedIndex {
                HStack {
                    Button { step(-1) } label: {
                        Image(systemName: "chevron.left").frame(width: 44, height: 36)
                    }
                    .accessibilityLabel("이전 시계")
                    .accessibilityIdentifier("tryon.prev")
                    Spacer()
                    Button { showsList = true } label: {
                        VStack(spacing: 1) {
                            Text("\(index + 1) / \(model.state.watches.count)")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                            Text("시계 목록")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("tryon.list")
                    Spacer()
                    Button { step(1) } label: {
                        Image(systemName: "chevron.right").frame(width: 44, height: 36)
                    }
                    .accessibilityLabel("다음 시계")
                    .accessibilityIdentifier("tryon.next")
                }
            }
            HStack(spacing: 8) {
                chromeButton("스펙 편집", symbol: "slider.horizontal.3", id: "tryon.edit") {
                    guard let watch = model.selectedWatch else { return }
                    editorDetent = Self.editorDetent
                    draft = WatchDraft(spec: watch)
                    isEditing = true
                }
                .disabled(model.selectedWatch == nil)
                chromeButton("새 시계", symbol: "plus", id: "tryon.new") { startNewWatch() }
                chromeButton("설정", symbol: "gearshape", id: "tryon.settings") { showsSettings = true }
            }
            Text("화면을 탭하면 UI가 숨겨져요 · 좌우로 밀어 시계 전환")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .chromePanel()
    }

    private func chromeButton(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.body)
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(id)
    }

    private func step(_ offset: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            model.selectWatch(offset: offset)
        }
    }

    private func startNewWatch() {
        editorDetent = Self.editorDetent
        draft = .blank()
        isEditing = true
    }

    // MARK: 편집 시트

    private var editorSheet: some View {
        SpecEditorView(
            draft: $draft,
            onCancel: { isEditing = false },
            onSave: { spec in
                model.saveWatch(spec)
                isEditing = false
            },
            onDelete: draft.isNew ? nil : {
                model.deleteWatch(draft.id)
                isEditing = false
            }
        )
        .presentationDetents([Self.editorDetent, .large], selection: $editorDetent)
        .presentationBackgroundInteraction(.enabled(upThrough: Self.editorDetent))
        .presentationContentInteraction(.scrolls)
    }
}
