import CoreGraphics
import Foundation
import Observation

enum BackgroundTone: String, Codable, CaseIterable, Identifiable, Sendable {
    case black, gray, light

    var id: String { rawValue }

    var label: String {
        switch self {
        case .black: "검정"
        case .gray: "회색"
        case .light: "밝은 회색"
        }
    }

    var rgb: RGB {
        switch self {
        case .black: RGB(hex: 0x050506)
        case .gray: RGB(hex: 0x3A3A3C)
        case .light: RGB(hex: 0xC7C7CC)
        }
    }
}

/// 결정사항을 실기에서 비교·검증하기 위한 값. 기본값이 Linear 결정이다.
struct TestTools: Codable, Equatable, Sendable {
    /// 기획서 v0.2 방식(시계를 3% 줄여 그림)과 비교. MIN-45 결정으로 기본은 엄격 1:1
    var legacyWatchCorrection = false
    var simulateUnknownDevice = false
    /// 손목 띠 위아래 경계 소프트 페이드 폭 (미확정 사항 결정 2: 약 10mm)
    var edgeFadeMM = 10.0
    var background = BackgroundTone.black
    var lockedBrightness = 0.5

    static let legacyWatchFactor = 0.97
}

struct CardCalibration: Codable, Equatable, Sendable {
    var mmPerPixel: Double
    var deviceIdentifier: String
}

struct PersistedState: Codable, Equatable, Sendable {
    var onboardingCompleted = false
    var wrist = WristProfile(matchedWidthMM: WristProfile.defaultMatchedWidthMM)
    var skin = SkinTone(base: SkinPreset.medium.rgb, source: .preset)
    var ambientReference: AmbientReading?
    var cardCalibration: CardCalibration?
    var watches: [WatchSpec] = WatchSpec.samples
    var selectedWatchID: UUID?
    var crownSide = CrownSide.right
    var ambientTrackingEnabled = true
    var tools = TestTools()
}

protocol StateStore {
    func load() -> PersistedState?
    func save(_ state: PersistedState)
    func clear()
}

struct UserDefaultsStateStore: StateStore {
    static let key = "RealSizeWatch.state.v1"
    let defaults: UserDefaults

    func load() -> PersistedState? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    func save(_ state: PersistedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}

@MainActor
@Observable
final class AppModel {
    var state: PersistedState {
        didSet {
            guard state != oldValue else { return }
            store.save(state)
        }
    }

    let device: DeviceInfo
    private let store: StateStore
    private let forcesUnknownDevice: Bool

    init(device: DeviceInfo, store: StateStore, forcesUnknownDevice: Bool = false) {
        self.device = device
        self.store = store
        self.forcesUnknownDevice = forcesUnknownDevice
        var loaded = store.load() ?? PersistedState()
        if !loaded.watches.contains(where: { $0.id == loaded.selectedWatchID }) {
            loaded.selectedWatchID = loaded.watches.first?.id
        }
        self.state = loaded
    }

    static func live() -> AppModel {
        let arguments = ProcessInfo.processInfo.arguments
        let store = UserDefaultsStateStore(defaults: .standard)
        if arguments.contains("-reset-state") {
            store.clear()
        }
        return AppModel(
            device: .current(),
            store: store,
            forcesUnknownDevice: arguments.contains("-simulate-unknown-device")
        )
    }

    // MARK: 물리 스케일 (MIN-44)

    var scale: PhysicalScale {
        let card = state.cardCalibration.flatMap { $0.deviceIdentifier == device.identifier ? $0.mmPerPixel : nil }
        return PhysicalScale.resolve(
            device: device,
            cardMMPerPixel: card,
            ignoreTable: forcesUnknownDevice || state.tools.simulateUnknownDevice
        )
    }

    var watchDrawingFactor: Double {
        state.tools.legacyWatchCorrection ? TestTools.legacyWatchFactor : 1
    }

    func saveCardCalibration(matchedHeightPoints: CGFloat) {
        state.cardCalibration = CardCalibration(
            mmPerPixel: PhysicalScale.cardMMPerPixel(matchedHeightPoints: matchedHeightPoints, nativeScale: device.nativeScale),
            deviceIdentifier: device.identifier
        )
    }

    func clearCardCalibration() {
        state.cardCalibration = nil
    }

    // MARK: 시계 목록

    var selectedWatch: WatchSpec? {
        state.watches.first { $0.id == state.selectedWatchID } ?? state.watches.first
    }

    var selectedIndex: Int? {
        guard let selectedWatch else { return nil }
        return state.watches.firstIndex { $0.id == selectedWatch.id }
    }

    func selectWatch(_ id: UUID) {
        state.selectedWatchID = id
    }

    func selectWatch(offset: Int) {
        let count = state.watches.count
        guard count > 0 else { return }
        let next = (((selectedIndex ?? 0) + offset) % count + count) % count
        state.selectedWatchID = state.watches[next].id
    }

    func saveWatch(_ spec: WatchSpec) {
        if let index = state.watches.firstIndex(where: { $0.id == spec.id }) {
            state.watches[index] = spec
        } else {
            state.watches.append(spec)
        }
        state.selectedWatchID = spec.id
    }

    func deleteWatch(_ id: UUID) {
        guard let index = state.watches.firstIndex(where: { $0.id == id }) else { return }
        state.watches.remove(at: index)
        if state.selectedWatchID == id {
            state.selectedWatchID = state.watches.isEmpty ? nil : state.watches[min(index, state.watches.count - 1)].id
        }
    }

    func restoreSamples() {
        let names = Set(state.watches.map(\.name))
        state.watches.append(contentsOf: WatchSpec.samples.filter { !names.contains($0.name) })
        if selectedIndex == nil {
            state.selectedWatchID = state.watches.first?.id
        }
    }

    // MARK: 핏 판정 (MIN-48)

    func verdict(for spec: WatchSpec) -> FitVerdict {
        FitVerdict(lugToLug: spec.lugToLug, wristWidth: state.wrist.fitWidthMM)
    }

    // MARK: 온보딩 (MIN-45)

    func completeOnboarding(matchedWidthMM: Double, skin: SkinTone, ambient: AmbientReading?) {
        var next = state
        next.wrist.matchedWidthMM = matchedWidthMM
        next.skin = skin
        // 피부색은 이번 조명에서 맞췄으므로 이전 기준 조명은 더 이상 유효하지 않다
        next.ambientReference = ambient
        next.onboardingCompleted = true
        state = next
    }

    func applyWristRecalibration(matchedWidthMM: Double, skin: SkinTone, ambient: AmbientReading?) {
        var next = state
        next.wrist.matchedWidthMM = matchedWidthMM
        next.skin = skin
        next.ambientReference = ambient
        state = next
    }

    func restartOnboarding() {
        state.onboardingCompleted = false
    }

    func resetAll() {
        store.clear()
        var fresh = PersistedState()
        fresh.selectedWatchID = fresh.watches.first?.id
        state = fresh
    }
}
