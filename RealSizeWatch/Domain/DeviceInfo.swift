import Foundation
import UIKit

struct DeviceInfo: Equatable, Sendable {
    let identifier: String
    let nativeScale: Double
    let isSimulator: Bool

    var model: DeviceModel? { DeviceCatalog.model(for: identifier) }

    @MainActor
    static func current() -> DeviceInfo {
        #if targetEnvironment(simulator)
        let identifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Simulator"
        let isSimulator = true
        #else
        var info = utsname()
        uname(&info)
        let identifier = withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        let isSimulator = false
        #endif
        return DeviceInfo(identifier: identifier, nativeScale: Double(UIScreen.main.nativeScale), isSimulator: isSimulator)
    }
}
