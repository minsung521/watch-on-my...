import SwiftUI
import UIKit

/// 손목 캔버스가 보이는 동안 자동 밝기 대신 고정 밝기를 쓰고, 팔에 올려둔 채 화면이 꺼지지 않게 한다 (MIN-45).
@MainActor
final class ScreenControl {
    static let shared = ScreenControl()

    private var holders = 0
    private var savedBrightness: CGFloat?

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.lazy.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    func acquire(brightness: Double) {
        holders += 1
        if savedBrightness == nil {
            savedBrightness = screen?.brightness
        }
        apply(brightness)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func apply(_ brightness: Double) {
        guard holders > 0 else { return }
        screen?.brightness = CGFloat(min(max(brightness, 0), 1))
    }

    func release() {
        guard holders > 0 else { return }
        holders -= 1
        guard holders == 0 else { return }
        if let savedBrightness {
            screen?.brightness = savedBrightness
        }
        savedBrightness = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }
}

private struct CalibratedScreenModifier: ViewModifier {
    let brightness: Double
    @Environment(\.scenePhase) private var scenePhase
    @State private var isHolding = false

    func body(content: Content) -> some View {
        content
            .onAppear { setHolding(true) }
            .onDisappear { setHolding(false) }
            .onChange(of: scenePhase) { _, phase in setHolding(phase == .active) }
            .onChange(of: brightness) { _, value in ScreenControl.shared.apply(value) }
    }

    private func setHolding(_ hold: Bool) {
        guard hold != isHolding else { return }
        isHolding = hold
        if hold {
            ScreenControl.shared.acquire(brightness: brightness)
        } else {
            ScreenControl.shared.release()
        }
    }
}

extension View {
    func calibratedScreen(brightness: Double) -> some View {
        modifier(CalibratedScreenModifier(brightness: brightness))
    }
}
