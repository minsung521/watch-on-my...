import CoreGraphics
import Foundation
import Testing
@testable import WatchOnMy

// MARK: - 01 물리 스케일

struct PhysicalScaleTests {
    private func device(_ identifier: String, nativeScale: Double) -> DeviceInfo {
        DeviceInfo(identifier: identifier, nativeScale: nativeScale, isSimulator: false)
    }

    @Test(arguments: [
        (DisplayGroup.lcd2x, 2.0, 0.15583),
        (.oled476mini, 2.88, 0.15368),
        (.oled3x458, 3.0, 0.16638),
        (.oled3x460, 3.0, 0.16565),
    ])
    func ppiGroupsMatchTable(group: DisplayGroup, nativeScale: Double, expected: Double) {
        let value = PhysicalScale.mmPerPoint(ppi: group.ppi, nativeScale: nativeScale)
        #expect(abs(value - expected) < 0.000005)
    }

    @Test func roundTripConversion() {
        let scale = PhysicalScale(mmPerPoint: 0.16565, source: .deviceTable(identifier: "iPhone18,1"))
        for mm in [0.1, 47.0, 52.5, 85.6] {
            #expect(abs(scale.mm(fromPoints: scale.points(fromMM: mm)) - mm) < 1e-9)
        }
    }

    @Test func miniUsesNativeScale() {
        let scale = PhysicalScale.resolve(device: device("iPhone14,4", nativeScale: 2.88), card: nil)
        #expect(scale.source == .deviceTable(identifier: "iPhone14,4"))
        // 375pt 폭 = 물리 1080px / 476ppi
        #expect(abs(scale.mm(fromPoints: 375) - 1080.0 / 476 * 25.4) < 0.05)
    }

    @Test func cardCalibrationInverse() {
        #expect(abs(PhysicalScale.cardMMPerPoint(matchedLongSidePoints: 517.5) - 0.16541) < 0.00001)
    }

    @Test func cardCalibrationWinsAndSurvivesDisplayZoom() {
        let card = PhysicalScale.card(matchedLongSidePoints: 517.5, device: device("iPhone18,1", nativeScale: 3))
        let standard = PhysicalScale.resolve(device: device("iPhone18,1", nativeScale: 3), card: card)
        #expect(standard.source == .cardCalibration)
        #expect(abs(standard.points(fromMM: Constants.cardWidthMM) - 517.5) < 1e-9)
        let zoomed = PhysicalScale.resolve(device: device("iPhone18,1", nativeScale: 3.3), card: card)
        #expect(abs(zoomed.points(fromMM: Constants.cardWidthMM) * 3.3 - 517.5 * 3) < 1e-6)
        let otherDevice = PhysicalScale.resolve(device: device("iPhone17,1", nativeScale: 3), card: card)
        #expect(otherDevice.source == .deviceTable(identifier: "iPhone17,1"))
    }

    @Test func unknownDeviceFallsBackTo460Unverified() {
        let scale = PhysicalScale.resolve(device: device("iPhone99,9", nativeScale: 3), card: nil)
        #expect(scale.source == .provisional)
        #expect(scale.isVerified == false)
        #expect(scale.mmPerPoint == PhysicalScale.mmPerPoint(ppi: DisplayGroup.oled3x460.ppi, nativeScale: 3))
    }
}

// MARK: - 03 손목·피부톤

struct WristProfileTests {
    @Test func trueWidthAppliesDepthCorrection() {
        let scale = PhysicalScale(mmPerPoint: 0.15368, source: .deviceTable(identifier: "iPhone14,4"))
        let points = 342.0
        #expect(WristProfile.trueWidthMM(matchedWidthPoints: points, scale: scale) == scale.mm(fromPoints: points) * 1.083)
        var wrist = WristProfile.initial(scale: scale)
        wrist.matchedWidthPoints = points
        wrist.recomputeTrueWidth(scale: scale)
        #expect(wrist.trueWidthText == "약 \(Int((scale.mm(fromPoints: points) * 1.083).rounded()))mm")
    }

    @Test(arguments: SkinPreset.allCases)
    func skinAdjustmentsStayInGamut(preset: SkinPreset) {
        for hue in [WristProfile.hueOffsetRange.lowerBound, 0, WristProfile.hueOffsetRange.upperBound] {
            for saturation in [WristProfile.saturationScaleRange.lowerBound, WristProfile.saturationScaleRange.upperBound] {
                for brightness in [WristProfile.brightnessScaleRange.lowerBound, WristProfile.brightnessScaleRange.upperBound] {
                    let color = SkinColor.adjusted(base: preset.rgb, hueOffset: hue, saturationScale: saturation, brightnessScale: brightness)
                    for channel in [color.r, color.g, color.b] {
                        #expect((0...1).contains(channel))
                    }
                }
            }
        }
    }

    @Test func neutralAdjustmentKeepsPreset() {
        let base = SkinPreset.p3.rgb
        let color = SkinColor.adjusted(base: base, hueOffset: 0, saturationScale: 1, brightnessScale: 1)
        #expect(abs(color.r - base.r) < 1e-9 && abs(color.g - base.g) < 1e-9 && abs(color.b - base.b) < 1e-9)
    }

    @Test func bandShadingTable() {
        #expect(BandProfile.brightness(at: 0) == 0.80)
        #expect(abs(BandProfile.brightness(at: 0.2) - 0.94) < 1e-9)
        #expect(BandProfile.brightness(at: 0.5) == 1.00)
        #expect(abs(BandProfile.brightness(at: 0.8) - 0.94) < 1e-9)
        #expect(BandProfile.brightness(at: 1) == 0.80)
    }

    @Test func edgeFadeIsCenteredOnMatchedEdge() {
        #expect(abs(BandProfile.edgeAlpha(distanceFromEdge: 0, fade: 10) - 0.5) < 1e-9)
        #expect(BandProfile.edgeAlpha(distanceFromEdge: 5, fade: 10) == 1)
        #expect(BandProfile.edgeAlpha(distanceFromEdge: -5, fade: 10) == 0)
    }
}

// MARK: - 02·04 시계 스펙과 기하

struct WatchSpecTests {
    @Test func roundOutlineIsCircle() {
        let geometry = CaseGeometry(spec: .standard(lugToLugMM: 47, caseDiameterMM: 42))
        for point in geometry.outline() {
            #expect(abs((point.x * point.x + point.y * point.y).squareRoot() - 21) < 0.01)
        }
    }

    @Test(arguments: [(CaseShape.round, 1.00), (.cushion, 1.00), (.tonneau, 1.18), (.square, 1.05)])
    func caseLengthPerShape(shape: CaseShape, ratio: Double) {
        var spec = WatchSpec.standard(lugToLugMM: 60, caseDiameterMM: 40)
        spec.caseShape = shape
        #expect(abs(spec.caseLengthMM - 40 * ratio) < 1e-9)
    }

    @Test func lugToLugShorterThanCaseIsRejected() {
        var spec = WatchSpec.standard(lugToLugMM: 40, caseDiameterMM: 42)
        spec.caseShape = .round
        #expect(spec.validationErrors == [.lugToLugShorterThanCase(caseLengthMM: 42)])
        var draft = SpecDraft(spec: .standard())
        draft.lugToLugText = "40"
        draft.diameterText = "42"
        #expect(draft.spec == nil)
    }

    @Test(arguments: [26.0, 33.0, 40.0, 42.0, 44.5, 50.0])
    func defaultLugWidthIsEven(diameter: Double) {
        let width = WatchSpec.defaultLugWidth(forDiameter: diameter)
        #expect(width.truncatingRemainder(dividingBy: 2) == 0)
        #expect(WatchSpec.lugWidthRange.contains(width))
    }

    @Test func lugWidthOverSeventyPercentIsRejected() {
        var spec = WatchSpec.standard(lugToLugMM: 34, caseDiameterMM: 26)
        spec.lugWidthMM = 20
        #expect(spec.validationErrors.contains(.lugWidthTooWide))
    }

    @Test func draftRequiresBothValuesAndClampsRange() {
        var draft = SpecDraft(spec: .standard())
        draft.lugToLugText = ""
        #expect(draft.spec == nil)
        #expect(draft.notices.contains(.missingLugToLug))
        draft.lugToLugText = "70"
        #expect(draft.spec?.lugToLugMM == 60)
        #expect(draft.notices.contains(.lugToLugClamped(to: 60)))
        draft.commitClamping()
        #expect(draft.lugToLugText == "60")
    }

    @Test func presetsHaveNeutralNames() {
        #expect(WatchPreset.compact.name == "컴팩트 42/47")
        #expect(WatchPreset.longLug.name == "롱러그 42/52.5")
        #expect(WatchPreset.compact.spec.validationErrors.isEmpty)
        #expect(WatchPreset.longLug.spec.validationErrors.isEmpty)
    }

    @Test func sameDiameterDifferentLugToLugDiffersOnScreen() {
        let scale = PhysicalScale(mmPerPoint: 0.15368, source: .deviceTable(identifier: "iPhone14,4"))
        let compact = CaseGeometry(spec: WatchPreset.compact.spec)
        let longLug = CaseGeometry(spec: WatchPreset.longLug.spec)
        #expect(compact.halfWidth == longLug.halfWidth)
        #expect(scale.points(fromMM: (longLug.lugTipY - compact.lugTipY) * 2) > 30)
    }
}

// MARK: - 06 사진 임포트

struct PhotoMathTests {
    /// 화면 시계방향으로 degrees만큼 기운 직사각형 마스크
    private func rectangleMask(tiltDegrees: Double, halfWidth: Double = 20, halfHeight: Double = 60, size: Int = 200) -> AlphaMask {
        let theta = tiltDegrees * Double.pi / 180
        var values = [UInt8](repeating: 0, count: size * size)
        let center = Double(size) / 2
        for y in 0..<size {
            for x in 0..<size {
                let dx = Double(x) - center
                let dy = Double(y) - center
                let u = dx * cos(theta) + dy * sin(theta)
                let v = -dx * sin(theta) + dy * cos(theta)
                if abs(u) <= halfWidth, abs(v) <= halfHeight { values[y * size + x] = 255 }
            }
        }
        return AlphaMask(width: size, height: size, values: values)
    }

    @Test func tiltedRectangleIsStoodUp() {
        let rotation = PhotoMath.uprightRotationDegrees(for: rectangleMask(tiltDegrees: 30))
        #expect(abs(rotation - -30) < 1)
    }

    @Test func circleIsNotRotated() {
        let size = 200
        var values = [UInt8](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size where (Double(x) - 100) * (Double(x) - 100) + (Double(y) - 100) * (Double(y) - 100) <= 70 * 70 {
                values[y * size + x] = 255
            }
        }
        #expect(PhotoMath.uprightRotationDegrees(for: AlphaMask(width: size, height: size, values: values)) == 0)
    }

    @Test func mmPerPixelFromLines() {
        #expect(PhotoMath.mmPerPixel(lugToLugMM: 47, linePixelDistance: 940) == 0.05)
        #expect(PhotoMath.mmPerPixel(lugToLugMM: 47, linePixelDistance: 0) == nil)
    }

    @Test func strapWidthClamp() {
        #expect(PhotoMath.clampedStrapWidth(9) == 12)
        #expect(PhotoMath.clampedStrapWidth(30) == 24)
        #expect(PhotoMath.clampedStrapWidth(nil) == 18)
        #expect(PhotoMath.clampedStrapWidth(20) == 20)
    }

    @Test func strapWidthMeasuredOutsideLines() {
        // 폭 40px 스트랩이 세로로 지나가는 마스크, 0.5mm/px → 20mm
        let width = 100, height = 300
        var values = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 30..<70 { values[y * width + x] = 255 }
        }
        let mask = AlphaMask(width: width, height: height, values: values)
        let measured = PhotoMath.strapWidthMM(mask: mask, topLineY: 100, bottomLineY: 200, mmPerPixel: 0.5)
        #expect(measured == 20)
    }
}

// MARK: - 최근 목록

struct RecentListTests {
    private func photo(_ name: String) -> SavedWatch {
        SavedWatch(id: UUID(), name: name, source: .photo(PhotoWatch(imageFileName: "\(name).png", lugToLugMM: 47, mmPerPixel: 0.05, strapWidthMM: 20, strapColor: RGB(0, 0, 0))))
    }

    @Test func keepsFiveAndEvictsOldest() {
        var list: [SavedWatch] = []
        var evicted: [SavedWatch] = []
        let watches = (0..<6).map { photo("p\($0)") }
        for watch in watches {
            let result = RecentList.inserting(watch, into: list)
            list = result.list
            evicted += result.evicted
        }
        #expect(list.count == 5)
        #expect(list.first == watches.last)
        #expect(evicted == [watches[0]])
        #expect(RecentList.orphanedPhotoFiles(evicted: evicted, remaining: list, current: list[0]) == ["p0.png"])
    }

    @Test func reselectingMovesToFrontWithoutDuplicates() {
        let a = WatchPreset.compact.savedWatch
        let b = WatchPreset.longLug.savedWatch
        var list = RecentList.inserting(a, into: []).list
        list = RecentList.inserting(b, into: list).list
        list = RecentList.inserting(a, into: list).list
        #expect(list.map(\.id) == [a.id, b.id])
    }
}

// MARK: - 앱 상태

@MainActor
struct AppStateTests {
    private func makeState(defaults: UserDefaults, photos: PhotoStore) -> AppState {
        AppState(
            device: DeviceInfo(identifier: "iPhone14,4", nativeScale: 2.88, isSimulator: false),
            store: UserDefaultsStateStore(defaults: defaults),
            photos: photos
        )
    }

    @Test func onboardingIsNotAskedAgainAfterRelaunch() throws {
        let suite = "WatchOnMyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let photos = PhotoStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let first = makeState(defaults: defaults, photos: photos)
        #expect(first.state.wrist == nil)
        var wrist = WristProfile.initial(scale: first.scale)
        wrist.matchedWidthPoints = 340
        first.saveWrist(wrist)
        let relaunched = makeState(defaults: defaults, photos: photos)
        #expect(relaunched.state.wrist?.matchedWidthPoints == 340)
        #expect(relaunched.state.wrist?.trueWidthMM == first.scale.mm(fromPoints: 340) * 1.083)
    }

    @Test func evictedPhotoFileIsDeleted() throws {
        let suite = "WatchOnMyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let photos = PhotoStore(directory: directory)
        let state = makeState(defaults: defaults, photos: photos)
        let first = try state.addPhotoWatch(pngData: Data([0x89]), lugToLugMM: 47, mmPerPixel: 0.05, strapWidthMM: 20, strapColor: RGB(0, 0, 0))
        guard case .photo(let photo) = first.source else { Issue.record("사진 시계가 아님"); return }
        #expect(photos.fileExists(named: photo.imageFileName))
        for index in 0..<5 {
            var spec = WatchSpec.standard()
            spec.lugToLugMM = 45 + Double(index)
            state.select(SavedWatch(id: UUID(), name: "\(index)", source: .parametric(spec)))
        }
        #expect(!state.state.recents.contains { $0.id == first.id })
        #expect(!photos.fileExists(named: photo.imageFileName))
    }

    @Test func cardCalibrationRecomputesTrueWidth() throws {
        let suite = "WatchOnMyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = makeState(defaults: defaults, photos: PhotoStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        var wrist = WristProfile.initial(scale: state.scale)
        wrist.matchedWidthPoints = 340
        state.saveWrist(wrist)
        state.saveCardCalibration(matchedLongSidePoints: 540)
        #expect(state.scale.source == .cardCalibration)
        #expect(abs((state.state.wrist?.trueWidthMM ?? 0) - 340 * (85.6 / 540) * 1.083) < 1e-9)
    }
}
