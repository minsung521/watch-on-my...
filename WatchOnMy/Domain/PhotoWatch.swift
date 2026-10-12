import Foundation

/// 사용자가 가져온 사진에서 두 선 사이(케이스+러그)만 잘라낸 시계. 원본 사진은 저장하지 않는다 (06 6-3)
struct PhotoWatch: Codable, Equatable, Sendable {
    var imageFileName: String
    var lugToLugMM: Double
    /// L2L ÷ 두 선 사이 픽셀 거리. 잘라낸 PNG의 픽셀 기준
    var mmPerPixel: Double
    var strapWidthMM: Double
    var strapColor: RGB
}

/// 8비트 알파 마스크. 행 우선, 0번 행이 이미지 맨 위
struct AlphaMask: Equatable, Sendable {
    let width: Int
    let height: Int
    let values: [UInt8]
    static let threshold: UInt8 = 128

    func isForeground(x: Int, y: Int) -> Bool {
        values[y * width + x] >= Self.threshold
    }

    /// 한 행에서 전경이 차지하는 가로 범위
    func rowSpan(y: Int) -> ClosedRange<Int>? {
        guard (0..<height).contains(y) else { return nil }
        var first: Int?
        var last: Int?
        for x in 0..<width where isForeground(x: x, y: y) {
            if first == nil { first = x }
            last = x
        }
        guard let first, let last else { return nil }
        return first...last
    }

    /// 전경이 있는 첫 행과 마지막 행
    var verticalExtent: ClosedRange<Int>? {
        let rows = (0..<height).filter { rowSpan(y: $0) != nil }
        guard let first = rows.first, let last = rows.last else { return nil }
        return first...last
    }
}

enum PhotoMath {
    static func mmPerPixel(lugToLugMM: Double, linePixelDistance: Double) -> Double? {
        guard linePixelDistance > 0, lugToLugMM > 0 else { return nil }
        return lugToLugMM / linePixelDistance
    }

    /// 사진에서 잰 스트랩 폭을 12~24mm로 클램프, 측정 실패면 18mm (06 6-2)
    static func clampedStrapWidth(_ measured: Double?) -> Double {
        guard let measured, measured.isFinite, measured > 0 else { return Constants.fallbackStrapWidthMM }
        return min(max(measured, Constants.strapWidthRangeMM.lowerBound), Constants.strapWidthRangeMM.upperBound)
    }

    struct PrincipalAxis: Equatable {
        /// 주축이 세로축에서 화면 시계방향으로 기운 각도 (−90, 90]
        let angleFromVerticalDegrees: Double
        /// 장축 ÷ 단축
        let axisRatio: Double
    }

    /// 마스크의 2차 중심 모멘트로 주축을 구한다
    static func principalAxis(of mask: AlphaMask) -> PrincipalAxis? {
        var count = 0.0, sumX = 0.0, sumY = 0.0
        for y in 0..<mask.height {
            for x in 0..<mask.width where mask.isForeground(x: x, y: y) {
                count += 1
                sumX += Double(x)
                sumY += Double(y)
            }
        }
        guard count > 8 else { return nil }
        let meanX = sumX / count
        let meanY = sumY / count
        var mu20 = 0.0, mu02 = 0.0, mu11 = 0.0
        for y in 0..<mask.height {
            for x in 0..<mask.width where mask.isForeground(x: x, y: y) {
                let dx = Double(x) - meanX
                let dy = Double(y) - meanY
                mu20 += dx * dx
                mu02 += dy * dy
                mu11 += dx * dy
            }
        }
        // y가 아래로 증가하는 좌표에서 +x → +y 방향(화면 시계방향)으로 잰 장축 각도
        let phi = 0.5 * atan2(2 * mu11, mu20 - mu02) * 180 / Double.pi
        var fromVertical = phi - 90
        while fromVertical <= -90 { fromVertical += 180 }
        while fromVertical > 90 { fromVertical -= 180 }
        let mean = (mu20 + mu02) / 2
        let spread = (((mu20 - mu02) / 2) * ((mu20 - mu02) / 2) + mu11 * mu11).squareRoot()
        let major = mean + spread
        let minor = max(mean - spread, 1e-9)
        return PrincipalAxis(angleFromVerticalDegrees: fromVertical, axisRatio: (major / minor).squareRoot())
    }

    /// 주축이 세로가 되도록 돌릴 각도 (화면 시계방향 +). 거의 원형이면(장단축 비 1.15 미만) 돌리지 않는다
    static func uprightRotationDegrees(for mask: AlphaMask) -> Double {
        guard let axis = principalAxis(of: mask), axis.axisRatio >= Constants.uprightAxisRatioThreshold else { return 0 }
        return -axis.angleFromVerticalDegrees
    }

    /// 각 선에서 바깥쪽 2~3mm 지점 행들의 마스크 폭 중앙값 (mm). 잴 수 없으면 nil
    static func strapWidthMM(mask: AlphaMask, topLineY: Double, bottomLineY: Double, mmPerPixel: Double) -> Double? {
        let widths = sampleRows(mask: mask, topLineY: topLineY, bottomLineY: bottomLineY, mmPerPixel: mmPerPixel)
            .compactMap { mask.rowSpan(y: $0) }
            .map { Double($0.count) * mmPerPixel }
        return median(widths)
    }

    static func sampleRows(mask: AlphaMask, topLineY: Double, bottomLineY: Double, mmPerPixel: Double) -> [Int] {
        guard mmPerPixel > 0 else { return [] }
        return Constants.strapSampleOffsetsMM.flatMap { offset -> [Int] in
            let pixels = offset / mmPerPixel
            return [Int((topLineY - pixels).rounded()), Int((bottomLineY + pixels).rounded())]
        }
        .filter { (0..<mask.height).contains($0) }
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
