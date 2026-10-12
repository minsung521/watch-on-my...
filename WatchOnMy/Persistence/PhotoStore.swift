import CoreGraphics
import Foundation
import ImageIO

/// 잘라낸 사진 시계 PNG를 Application Support에만 둔다. 원본 사진·공유·내보내기·네트워크 없음 (06 6-3)
final class PhotoStore: @unchecked Sendable {
    static let shared = PhotoStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PhotoWatches", isDirectory: true))

    let directory: URL
    private var cache: [String: CGImage] = [:]
    private let lock = NSLock()

    init(directory: URL) {
        self.directory = directory
    }

    func save(pngData: Data) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString).png"
        try pngData.write(to: url(for: name), options: .atomic)
        return name
    }

    func image(named name: String) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[name] { return cached }
        guard let source = CGImageSourceCreateWithURL(url(for: name) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        cache[name] = image
        return image
    }

    func delete(named name: String) {
        lock.lock()
        cache[name] = nil
        lock.unlock()
        try? FileManager.default.removeItem(at: url(for: name))
    }

    func deleteAll() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
        try? FileManager.default.removeItem(at: directory)
    }

    func fileExists(named name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: name).path)
    }

    private func url(for name: String) -> URL {
        directory.appendingPathComponent(name)
    }
}
