#if DEBUG
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// 디버그 빌드 전용. 앱의 렌더러로 아이콘을 뽑아 화면과 아이콘을 일치시킨다 (06 9절). 릴리스 빌드에는 포함되지 않는다.
/// 실행 인자: -export-app-icon <저장할 PNG 경로>
enum IconExporter {
    @MainActor
    static func exportIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-export-app-icon"), arguments.indices.contains(index + 1) else { return }
        let url = URL(fileURLWithPath: arguments[index + 1])
        let renderer = ImageRenderer(content: IconArtwork().frame(width: 1024, height: 1024))
        renderer.scale = 1
        guard let rendered = renderer.cgImage, let opaque = removingAlpha(rendered) else { return }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, opaque, nil)
        CGImageDestinationFinalize(destination)
    }

    /// App Store 아이콘은 알파가 없어야 한다
    private static func removingAlpha(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}

/// 앱 화면 그대로: 검정 배경을 가로지르는 피부색 띠 + 제너릭 라운드 시계 + 스트랩. 인덱스 4개와 시·분침만
struct IconArtwork: View {
    private let scale = PhysicalScale(mmPerPoint: 0.074, source: .cardCalibration)

    private var wrist: WristProfile {
        var wrist = WristProfile.initial(scale: scale, skin: SkinPreset.p4.rgb)
        wrist.matchedWidthPoints = scale.points(fromMM: 56)
        return wrist
    }

    private var spec: WatchSpec {
        var spec = WatchSpec.standard(lugToLugMM: 44, caseDiameterMM: 38)
        spec.lugWidthMM = 20
        spec.bezelRatio = 0.1
        spec.strapColor = StrapPreset.brownLeather.rgb
        return spec
    }

    var body: some View {
        WristCanvas(
            scale: scale,
            wrist: wrist,
            watch: .parametric(spec),
            fixedDate: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 10, minute: 10))
        )
    }
}
#endif
