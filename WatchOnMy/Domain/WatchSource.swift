import Foundation

enum WatchSource: Codable, Equatable, Sendable {
    case parametric(WatchSpec)
    case photo(PhotoWatch)

    var lugToLugMM: Double {
        switch self {
        case .parametric(let spec): spec.lugToLugMM
        case .photo(let photo): photo.lugToLugMM
        }
    }

    var photoFileName: String? {
        if case .photo(let photo) = self { return photo.imageFileName }
        return nil
    }
}

/// 최근 목록·현재 시계에 쓰는 이름 붙은 시계
struct SavedWatch: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var source: WatchSource
}

/// 최근 본 시계 (파라메트릭·사진 함께, 최대 5개). 동시 비교가 아니라 전환 편의용 (04 5절)
enum RecentList {
    /// 맨 앞에 넣고(같은 id는 끌어올림) 한도를 넘는 것은 밀어낸다
    static func inserting(_ watch: SavedWatch, into list: [SavedWatch], limit: Int = Constants.recentLimit) -> (list: [SavedWatch], evicted: [SavedWatch]) {
        var next = list.filter { $0.id != watch.id }
        next.insert(watch, at: 0)
        let evicted = Array(next.dropFirst(limit))
        return (Array(next.prefix(limit)), evicted)
    }

    /// 밀려난 시계 중 더 이상 어디에서도 쓰지 않는 사진 파일
    static func orphanedPhotoFiles(evicted: [SavedWatch], remaining: [SavedWatch], current: SavedWatch) -> [String] {
        let inUse = Set((remaining + [current]).compactMap(\.source.photoFileName))
        return evicted.compactMap(\.source.photoFileName).filter { !inUse.contains($0) }
    }
}
