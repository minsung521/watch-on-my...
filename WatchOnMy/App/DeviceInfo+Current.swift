import Foundation
import UIKit

extension DeviceInfo {
    @MainActor
    static func current() -> DeviceInfo {
        #if targetEnvironment(simulator)
        let identifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Simulator"
        let isSimulator = true
        #else
        var sysinfo = utsname()
        uname(&sysinfo)
        let identifier = withUnsafeBytes(of: &sysinfo.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        let isSimulator = false
        #endif
        return DeviceInfo(identifier: identifier, nativeScale: Double(UIScreen.main.nativeScale), isSimulator: isSimulator)
    }
}
