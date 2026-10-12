import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

enum PhotoImportError: LocalizedError {
    case unreadable
    case noForeground
    case failed

    var errorDescription: String? {
        switch self {
        case .unreadable: "사진을 읽지 못했습니다. 다른 사진을 골라주세요."
        case .noForeground, .failed: "배경을 분리하지 못했습니다. 시계가 잘 보이는 정면 사진을 골라주세요"
        }
    }
}

/// 사진 임포트의 이미지 처리. 모두 기기 안에서만 하고 네트워크를 쓰지 않는다 (06 6절)
enum PhotoProcessor {
    struct Cutout {
        let image: CGImage
        let skippedSegmentation: Bool
        let autoRotationDegrees: Double
    }

    struct Result {
        let pngData: Data
        let mmPerPixel: Double
        let strapWidthMM: Double
        let strapColor: RGB
    }

    /// 사진 선택 직후: 방향 보정·축소 → (투명 PNG가 아니면) 누끼 → 자동 세우기 각도
    static func prepare(data: Data) throws -> Cutout {
        guard let image = loadImage(data: data) else { throw PhotoImportError.unreadable }
        let transparent = hasTransparency(image)
        let cutout = transparent ? image : try removeBackground(image)
        let trimmedCutout = trimmed(cutout) ?? cutout
        let mask = alphaMask(of: trimmedCutout, maxDimension: 400)
        guard mask.verticalExtent != nil else { throw PhotoImportError.noForeground }
        return Cutout(
            image: trimmedCutout,
            skippedSegmentation: transparent,
            autoRotationDegrees: PhotoMath.uprightRotationDegrees(for: mask)
        )
    }

    static func loadImage(data: Data, maxPixelSize: Int = 2400) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// 알파 채널이 있고 실제로 투명한 픽셀이 있으면 누끼를 건너뛴다
    static func hasTransparency(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        let mask = alphaMask(of: image, maxDimension: 256)
        let transparent = mask.values.reduce(0) { $0 + ($1 < 250 ? 1 : 0) }
        return Double(transparent) / Double(max(mask.values.count, 1)) > 0.005
    }

    static func removeBackground(_ image: CGImage) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw PhotoImportError.failed
        }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw PhotoImportError.noForeground
        }
        guard let buffer = try? observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: false
        ) else { throw PhotoImportError.failed }
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let output = CIContext().createCGImage(ciImage, from: ciImage.extent) else { throw PhotoImportError.failed }
        return output
    }

    /// 알파만 뽑은 마스크. 0번 행이 이미지 맨 위
    static func alphaMask(of image: CGImage, maxDimension: Int? = nil) -> AlphaMask {
        var width = image.width
        var height = image.height
        if let maxDimension, max(width, height) > maxDimension {
            let ratio = Double(maxDimension) / Double(max(width, height))
            width = max(Int(Double(width) * ratio), 1)
            height = max(Int(Double(height) * ratio), 1)
        }
        var values = [UInt8](repeating: 0, count: width * height)
        values.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
            ) else { return }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return AlphaMask(width: width, height: height, values: values)
    }

    /// 화면 시계방향(+)으로 돌린 뒤 투명 여백을 잘라낸다
    static func rotated(_ image: CGImage, degrees: Double) -> CGImage {
        guard abs(degrees) > 0.01 else { return image }
        let radians = degrees * Double.pi / 180
        let w = Double(image.width)
        let h = Double(image.height)
        let newWidth = Int((abs(w * cos(radians)) + abs(h * sin(radians))).rounded(.up))
        let newHeight = Int((abs(w * sin(radians)) + abs(h * cos(radians))).rounded(.up))
        guard let context = CGContext(
            data: nil, width: newWidth, height: newHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.interpolationQuality = .high
        context.translateBy(x: CGFloat(newWidth) / 2, y: CGFloat(newHeight) / 2)
        // CG 좌표는 y가 위로 증가하므로 화면 시계방향은 음의 각도
        context.rotate(by: CGFloat(-radians))
        context.draw(image, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        guard let output = context.makeImage() else { return image }
        return trimmed(output) ?? output
    }

    /// 전경을 감싸는 최소 사각형으로 자른다
    static func trimmed(_ image: CGImage) -> CGImage? {
        let mask = alphaMask(of: image)
        guard let rows = mask.verticalExtent else { return nil }
        var minX = mask.width
        var maxX = 0
        for y in rows {
            if let span = mask.rowSpan(y: y) {
                minX = min(minX, span.lowerBound)
                maxX = max(maxX, span.upperBound)
            }
        }
        guard minX <= maxX else { return nil }
        return image.cropping(to: CGRect(x: minX, y: rows.lowerBound, width: maxX - minX + 1, height: rows.count))
    }

    /// 두 선으로 스케일 확정: 선 바깥은 잘라내고, 선 바깥 2~3mm에서 스트랩 폭·색을 잰다 (06 6-2)
    static func finish(image: CGImage, topLineY: Double, bottomLineY: Double, lugToLugMM: Double) throws -> Result {
        let top = Int(min(topLineY, bottomLineY).rounded())
        let bottom = Int(max(topLineY, bottomLineY).rounded())
        guard let mmPerPixel = PhotoMath.mmPerPixel(lugToLugMM: lugToLugMM, linePixelDistance: Double(bottom - top)) else {
            throw PhotoImportError.failed
        }
        let mask = alphaMask(of: image)
        let measured = PhotoMath.strapWidthMM(mask: mask, topLineY: Double(top), bottomLineY: Double(bottom), mmPerPixel: mmPerPixel)
        let strapWidth = PhotoMath.clampedStrapWidth(measured)
        let rows = PhotoMath.sampleRows(mask: mask, topLineY: Double(top), bottomLineY: Double(bottom), mmPerPixel: mmPerPixel)
        let strapColor = medianColor(of: image, rows: rows, mask: mask) ?? StrapPreset.blackLeather.rgb

        var minX = mask.width
        var maxX = 0
        for y in max(top, 0)..<min(bottom, mask.height) {
            if let span = mask.rowSpan(y: y) {
                minX = min(minX, span.lowerBound)
                maxX = max(maxX, span.upperBound)
            }
        }
        guard minX <= maxX,
              let cropped = image.cropping(to: CGRect(x: minX, y: top, width: maxX - minX + 1, height: bottom - top)),
              let png = pngData(cropped) else { throw PhotoImportError.failed }
        return Result(pngData: png, mmPerPixel: mmPerPixel, strapWidthMM: strapWidth, strapColor: strapColor)
    }

    /// 표본 행의 불투명 픽셀 채널별 중앙값
    static func medianColor(of image: CGImage, rows: [Int], mask: AlphaMask) -> RGB? {
        guard !rows.isEmpty else { return nil }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var reds: [Double] = [], greens: [Double] = [], blues: [Double] = []
        for y in rows where (0..<height).contains(y) {
            for x in stride(from: 0, to: width, by: 2) {
                let index = (y * width + x) * 4
                let alpha = Double(pixels[index + 3])
                guard alpha >= 200 else { continue }
                reds.append(Double(pixels[index]) / alpha)
                greens.append(Double(pixels[index + 1]) / alpha)
                blues.append(Double(pixels[index + 2]) / alpha)
            }
        }
        guard let r = PhotoMath.median(reds), let g = PhotoMath.median(greens), let b = PhotoMath.median(blues) else { return nil }
        return RGB(r, g, b).clamped
    }

    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
