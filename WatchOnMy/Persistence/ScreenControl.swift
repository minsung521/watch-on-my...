import SwiftUI
import UIKit

/// 손목 캔버스가 보이는 동안 밝기를 0.85로 고정하고 화면 잠김을 막는다 (06 8절).
/// 사용자의 원래 밝기는 UserDefaults에 따로 남겨, 앱이 강제 종료돼도 다음 실행에서 덮어쓰지 않고 되돌린다.
@MainActor
final class ScreenControl {
    static let shared = ScreenControl()
    static let savedBrightnessKey = "WatchOnMy.userBrightness"

    private var holders = 0
    private let defaults = UserDefaults.standard

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.lazy.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    func acquire() {
        holders += 1
        guard holders == 1 else { return }
        if defaults.object(forKey: Self.savedBrightnessKey) == nil, let screen {
            defaults.set(Double(screen.brightness), forKey: Self.savedBrightnessKey)
        }
        screen?.brightness = CGFloat(Constants.canvasBrightness)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func release() {
        guard holders > 0 else { return }
        holders -= 1
        guard holders == 0 else { return }
        restoreUserBrightness()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// 직전 실행이 밝기를 고정한 채 끝났다면 원래 값으로 되돌린다
    func restoreUserBrightness() {
        guard holders == 0, let saved = defaults.object(forKey: Self.savedBrightnessKey) as? Double else { return }
        screen?.brightness = CGFloat(saved)
        defaults.removeObject(forKey: Self.savedBrightnessKey)
    }
}

private struct CanvasScreenModifier: ViewModifier {
    let isActive: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var isAppeared = false
    @State private var isHolding = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                isAppeared = true
                update()
            }
            .onDisappear {
                isAppeared = false
                update()
            }
            .onChange(of: scenePhase) { _, _ in update() }
            .onChange(of: isActive) { _, _ in update() }
    }

    private func update() {
        let shouldHold = isAppeared && isActive && scenePhase == .active
        guard shouldHold != isHolding else { return }
        isHolding = shouldHold
        if shouldHold {
            ScreenControl.shared.acquire()
        } else {
            ScreenControl.shared.release()
        }
    }
}

extension View {
    /// 손목 캔버스가 실제로 보이는 동안만 true로 둔다. 전체를 덮는 시트·설정으로 가면 false
    func canvasScreen(isActive: Bool = true) -> some View {
        modifier(CanvasScreenModifier(isActive: isActive))
    }
}
