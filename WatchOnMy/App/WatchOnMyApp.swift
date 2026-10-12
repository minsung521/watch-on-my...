import SwiftUI

@main
struct WatchOnMyApp: App {
    @State private var appState: AppState

    init() {
        _appState = State(initialValue: AppState.live())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
    }
}

/// 손목 프로필이 없으면 온보딩, 있으면 메인. 재실행 시 완료된 단계를 다시 묻지 않는다 (05 2절)
struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            if appState.state.wrist != nil {
                MainView()
                    .transition(.opacity)
            } else {
                OnboardingFlow()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.state.wrist != nil)
        .task {
            // 직전 실행이 밝기를 고정한 채 강제 종료됐다면 사용자의 밝기로 되돌린다
            ScreenControl.shared.restoreUserBrightness()
            #if DEBUG
            IconExporter.exportIfRequested()
            #endif
        }
    }
}
