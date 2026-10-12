import SwiftUI

@main
struct RealSizeWatchApp: App {
    @State private var model: AppModel

    init() {
        _model = State(initialValue: AppModel.live())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

/// ② 온보딩은 한 번 완료하면 재실행 시 다시 요구하지 않는다 (MIN-49)
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if model.state.onboardingCompleted {
                TryOnView()
                    .transition(.opacity)
            } else {
                OnboardingFlow()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.state.onboardingCompleted)
    }
}
