import CoreGraphics
import Foundation
import Observation

struct PersistedState: Codable, Equatable {
    /// nil이면 온보딩이 필요하다
    var wrist: WristProfile?
    var cardCalibration: CardCalibration?
    var current: SavedWatch = WatchPreset.compact.savedWatch
    var recents: [SavedWatch] = [WatchPreset.compact.savedWatch]
}

protocol StateStore {
    func load() -> PersistedState?
    func save(_ state: PersistedState)
    func clear()
}

struct UserDefaultsStateStore: StateStore {
    static let key = "WatchOnMy.state.v1"
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

/// 앱 상태 하나. 루트 뷰가 손목 프로필 유무로 온보딩/메인을 분기한다 (05 2절)
@MainActor
@Observable
final class AppState {
    var state: PersistedState {
        didSet {
            guard state != oldValue else { return }
            store.save(state)
        }
    }

    let device: DeviceInfo
    let photos: PhotoStore
    private let store: StateStore

    init(device: DeviceInfo, store: StateStore, photos: PhotoStore) {
        self.device = device
        self.store = store
        self.photos = photos
        self.state = store.load() ?? PersistedState()
    }

    static func live() -> AppState {
        let arguments = ProcessInfo.processInfo.arguments
        let store = UserDefaultsStateStore(defaults: .standard)
        var device = DeviceInfo.current()
        #if DEBUG
        if arguments.contains("-reset-state") {
            store.clear()
            PhotoStore.shared.deleteAll()
        }
        // 미등록 기기 흐름 확인용: -device-identifier iPhone99,9
        if let index = arguments.firstIndex(of: "-device-identifier"), arguments.indices.contains(index + 1) {
            device = DeviceInfo(identifier: arguments[index + 1], nativeScale: device.nativeScale, isSimulator: device.isSimulator)
        }
        #endif
        let appState = AppState(device: device, store: store, photos: .shared)
        #if DEBUG
        // 화면 확인용: 온보딩을 건너뛰고 기본 손목으로 메인을 띄운다
        if arguments.contains("-debug-sample-wrist"), appState.state.wrist == nil {
            appState.saveWrist(WristProfile.initial(scale: appState.scale))
        }
        #endif
        return appState
    }

    // MARK: 스케일 (01)

    var scale: PhysicalScale {
        PhysicalScale.resolve(device: device, card: state.cardCalibration)
    }

    func saveCardCalibration(matchedLongSidePoints: Double) {
        var next = state
        next.cardCalibration = PhysicalScale.card(matchedLongSidePoints: matchedLongSidePoints, device: device)
        let newScale = PhysicalScale.resolve(device: device, card: next.cardCalibration)
        next.wrist?.recomputeTrueWidth(scale: newScale)
        state = next
    }

    func clearCardCalibration() {
        var next = state
        next.cardCalibration = nil
        next.wrist?.recomputeTrueWidth(scale: PhysicalScale.resolve(device: device, card: nil))
        state = next
    }

    // MARK: 손목 (03)

    func saveWrist(_ wrist: WristProfile) {
        var profile = wrist
        profile.recomputeTrueWidth(scale: scale)
        profile.calibratedAt = Date()
        state.wrist = profile
    }

    func restartOnboarding() {
        state.wrist = nil
    }

    // MARK: 시계 (04, 06)

    func select(_ watch: SavedWatch) {
        var next = state
        let result = RecentList.inserting(watch, into: next.recents)
        next.current = watch
        next.recents = result.list
        let orphans = RecentList.orphanedPhotoFiles(evicted: result.evicted, remaining: result.list, current: watch)
        state = next
        orphans.forEach { photos.delete(named: $0) }
    }

    @discardableResult
    func addPhotoWatch(pngData: Data, lugToLugMM: Double, mmPerPixel: Double, strapWidthMM: Double, strapColor: RGB) throws -> SavedWatch {
        let fileName = try photos.save(pngData: pngData)
        let photo = PhotoWatch(
            imageFileName: fileName,
            lugToLugMM: lugToLugMM,
            mmPerPixel: mmPerPixel,
            strapWidthMM: strapWidthMM,
            strapColor: strapColor
        )
        let saved = SavedWatch(id: UUID(), name: "사진 시계 · L2L \(lugToLugMM.mmText)", source: .photo(photo))
        select(saved)
        return saved
    }

    func resetAll() {
        store.clear()
        photos.deleteAll()
        state = PersistedState()
    }
}
