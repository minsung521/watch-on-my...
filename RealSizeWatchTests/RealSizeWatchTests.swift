import XCTest
@testable import RealSizeWatch

final class PhysicalScaleTests: XCTestCase {
    private func device(_ identifier: String, nativeScale: Double) -> DeviceInfo {
        DeviceInfo(identifier: identifier, nativeScale: nativeScale, isSimulator: false)
    }

    func testLinearPPIGroupsMatchResearchTable() {
        XCTAssertEqual(PhysicalScale.mmPerPoint(ppi: 460, nativeScale: 3), 0.16565, accuracy: 0.00001)
        XCTAssertEqual(PhysicalScale.mmPerPoint(ppi: 458, nativeScale: 3), 0.16638, accuracy: 0.00001)
        XCTAssertEqual(PhysicalScale.mmPerPoint(ppi: 326, nativeScale: 2), 0.15583, accuracy: 0.00001)
    }

    func testMiniUsesNativeScaleNotRenderScale() {
        // 13 mini: 375pt × 3 = 1125px로 그린 뒤 물리 1080px로 다운샘플링 → nativeScale 2.88
        let scale = PhysicalScale.resolve(device: device("iPhone14,4", nativeScale: 2.88), cardMMPerPixel: nil, ignoreTable: false)
        XCTAssertEqual(scale.source, .deviceTable(.oled476))
        let physicalWidthMM = 1080 / 476 * 25.4
        XCTAssertEqual(375 * scale.mmPerPoint, physicalWidthMM, accuracy: 0.05)
        // 고정 scale 3으로 계산하면 화면 폭이 2.4mm 넘게 커진다
        XCTAssertGreaterThan(375 * PhysicalScale.mmPerPoint(ppi: 476, nativeScale: 3) - physicalWidthMM, 2.4)
    }

    func testLogicalWidthMatchesPhysicalPanelForCurrentModels() {
        // (식별자, 논리 폭 pt, 물리 폭 px, PPI) — 시뮬레이터 기기 프로필 값
        let cases: [(String, Double, Double, Double)] = [
            ("iPhone18,1", 402, 1206, 460),
            ("iPhone17,2", 440, 1320, 460),
            ("iPhone14,3", 428, 1284, 458),
            ("iPhone14,6", 375, 750, 326),
        ]
        for (identifier, points, pixels, ppi) in cases {
            let nativeScale = pixels / points
            let scale = PhysicalScale.resolve(device: device(identifier, nativeScale: nativeScale), cardMMPerPixel: nil, ignoreTable: false)
            XCTAssertEqual(points * scale.mmPerPoint, pixels / ppi * 25.4, accuracy: 0.05, identifier)
        }
    }

    func testUnknownDeviceAssumes460WithoutBlocking() {
        let scale = PhysicalScale.resolve(device: device("iPhone99,9", nativeScale: 3), cardMMPerPixel: nil, ignoreTable: false)
        XCTAssertEqual(scale.source, .provisional)
        XCTAssertEqual(scale.mmPerPoint, PhysicalScale.mmPerPoint(ppi: 460, nativeScale: 3), accuracy: 1e-12)
    }

    func testCardCalibrationOverridesTableAndSurvivesDisplayZoom() {
        let matchedHeight: CGFloat = 530
        let perPixel = PhysicalScale.cardMMPerPixel(matchedHeightPoints: matchedHeight, nativeScale: 3)
        let standard = PhysicalScale.resolve(device: device("iPhone18,1", nativeScale: 3), cardMMPerPixel: perPixel, ignoreTable: false)
        XCTAssertEqual(standard.source, .card)
        XCTAssertEqual(Double(standard.points(IDCard.heightMM)), Double(matchedHeight), accuracy: 1e-9)

        // 디스플레이 확대로 nativeScale이 바뀌어도 물리 크기는 같아야 한다
        let zoomed = PhysicalScale.resolve(device: device("iPhone18,1", nativeScale: 3.3), cardMMPerPixel: perPixel, ignoreTable: false)
        XCTAssertEqual(Double(zoomed.points(IDCard.heightMM)) * 3.3, Double(matchedHeight) * 3, accuracy: 1e-6)
    }
}

final class WristFitTests: XCTestCase {
    func testViewingCorrectionAppliesToStoredWidth() {
        let wrist = WristProfile(matchedWidthMM: 52.6)
        XCTAssertEqual(wrist.measuredWidthMM, 56.97, accuracy: 0.01)
        XCTAssertEqual(wrist.fitWidthMM, wrist.measuredWidthMM)
    }

    func testCircumferenceConversionMatchesPlanTable() {
        // MIN-48 표: 둘레 → 실루엣 폭(타원 근사, 폭:두께 1.35)
        let expectations: [(Double, Double)] = [(152, 55.4), (165, 60.0), (178, 64.7), (191, 69.3)]
        for (circumference, width) in expectations {
            XCTAssertEqual(WristGeometry.width(fromCircumference: circumference), width, accuracy: 0.3)
        }
    }

    func testPlanTableConvergesToRatioWithinBand() {
        let table: [(circumference: Double, maxLugToLug: Double)] = [(152, 44), (165, 47), (178, 49.5), (191, 52)]
        for row in table {
            let ratio = row.maxLugToLug / WristGeometry.width(fromCircumference: row.circumference)
            XCTAssertEqual(ratio, 0.78, accuracy: 0.035)
            XCTAssertGreaterThan(ratio, FitVerdict.comfortableRatio)
            XCTAssertLessThanOrEqual(ratio, FitVerdict.overhangRatio)
        }
    }

    func testVerdictBands() {
        XCTAssertEqual(FitVerdict(lugToLug: 42, wristWidth: 57).level, .comfortable)
        XCTAssertEqual(FitVerdict(lugToLug: 42.18, wristWidth: 57).level, .comfortable)
        XCTAssertEqual(FitVerdict(lugToLug: 44, wristWidth: 57).level, .borderline)
        XCTAssertEqual(FitVerdict(lugToLug: 46.74, wristWidth: 57).level, .borderline)
        XCTAssertEqual(FitVerdict(lugToLug: 47, wristWidth: 57).level, .overhang)
    }

    func testVerdictMessageMatchesIssueExample() {
        XCTAssertEqual(FitVerdict(lugToLug: 51, wristWidth: 57).message, "L2L 51mm — 손목 폭 57mm 기준으로 러그가 넘칩니다.")
    }

    func testCircumferenceOverridesMeasurement() {
        var wrist = WristProfile(matchedWidthMM: 52.6)
        wrist.circumferenceMM = 165
        XCTAssertEqual(wrist.fitWidthMM, 60.0, accuracy: 0.3)
    }
}

final class WatchSpecTests: XCTestCase {
    func testBlankDraftCannotRender() {
        let draft = WatchDraft.blank()
        XCTAssertNil(draft.spec)
        XCTAssertTrue(draft.issues.contains(.missingLugToLug))
        XCTAssertTrue(draft.issues.contains(.missingDiameter))
    }

    func testRequiredValuesUnlockRenderingAndAutoName() {
        var draft = WatchDraft.blank()
        draft.lugToLugText = "52,5"
        XCTAssertNil(draft.spec)
        draft.diameterText = "42"
        XCTAssertEqual(draft.spec?.lugToLug, 52.5)
        XCTAssertEqual(draft.spec?.name, "라운드 42/52.5")
    }

    func testLugToLugShorterThanCaseIsRejected() {
        var draft = WatchDraft.blank()
        draft.lugToLugText = "38"
        draft.diameterText = "40"
        XCTAssertEqual(draft.issues, [.lugToLugShorterThanCase])
    }

    func testSameDiameterDifferentLugToLugDiffersOnScreen() {
        let short = WatchGeometry(spec: WatchSpec(name: "a", lugToLug: 47, diameter: 42))
        let long = WatchGeometry(spec: WatchSpec(name: "b", lugToLug: 52.5, diameter: 42))
        XCTAssertEqual(short.caseHalfWidth, long.caseHalfWidth)
        let scale = PhysicalScale(mmPerPoint: PhysicalScale.mmPerPoint(ppi: 476, nativeScale: 2.88), source: .deviceTable(.oled476))
        let difference = scale.points(long.halfLength * 2) - scale.points(short.halfLength * 2)
        XCTAssertEqual(Double(difference), 5.5 / scale.mmPerPoint, accuracy: 0.01)
        XCTAssertGreaterThan(difference, 30)
    }

    func testIntegratedTonneauHasNoSeparateLugs() {
        let tonneau = WatchGeometry(spec: WatchSpec(name: "t", lugToLug: 48, diameter: 40, shape: .tonneau))
        XCTAssertFalse(tonneau.hasVisibleLugs)
        XCTAssertEqual(tonneau.caseHalfHeight, 24)
    }
}

final class SkinToneTests: XCTestCase {
    private let tone = SkinTone(base: SkinPreset.medium.rgb, source: .camera)

    func testUnchangedLightingKeepsColor() {
        let reference = AmbientReading(temperatureK: 4000, ev100: 6)
        XCTAssertEqual(tone.rendered(reference: reference, current: reference), tone.rendered())
    }

    func testWarmerLightShiftsTowardRed() {
        let base = tone.rendered()
        let warmer = tone.rendered(reference: AmbientReading(temperatureK: 5500, ev100: 6), current: AmbientReading(temperatureK: 3000, ev100: 6))
        XCTAssertGreaterThan(warmer.r / warmer.b, base.r / base.b)
    }

    func testBrightnessCompensationIsClamped() {
        let reference = AmbientReading(temperatureK: 4000, ev100: 6)
        let twice = tone.rendered(reference: reference, current: AmbientReading(temperatureK: 4000, ev100: 7)).linear
        let clamped = tone.rendered(reference: reference, current: AmbientReading(temperatureK: 4000, ev100: 9)).linear
        let base = tone.rendered().linear
        XCTAssertEqual(twice.g / base.g, 2, accuracy: 0.02)
        XCTAssertEqual(clamped.g / base.g, 2, accuracy: 0.02)
    }

    func testOutdoorThresholdAndExposureFormula() {
        XCTAssertEqual(CameraTuning.ev100(aperture: 2, seconds: 1 / 60, iso: 100), log2(240), accuracy: 1e-9)
        XCTAssertFalse(AmbientReading(temperatureK: 4000, ev100: 7).isTooBright)
        XCTAssertTrue(AmbientReading(temperatureK: 6000, ev100: 12).isTooBright)
    }
}

@MainActor
final class AppModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "RealSizeWatchTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeModel(identifier: String = "iPhone14,4", forcesUnknown: Bool = false) -> AppModel {
        AppModel(
            device: DeviceInfo(identifier: identifier, nativeScale: 2.88, isSimulator: false),
            store: UserDefaultsStateStore(defaults: defaults),
            forcesUnknownDevice: forcesUnknown
        )
    }

    func testOnboardingIsNotAskedAgainAfterRelaunch() {
        let first = makeModel()
        XCTAssertFalse(first.state.onboardingCompleted)
        let reading = AmbientReading(temperatureK: 4100, ev100: 6.2)
        first.completeOnboarding(matchedWidthMM: 54, skin: SkinTone(base: SkinPreset.olive.rgb, source: .camera), ambient: reading)

        let relaunched = makeModel()
        XCTAssertTrue(relaunched.state.onboardingCompleted)
        XCTAssertEqual(relaunched.state.wrist.matchedWidthMM, 54)
        XCTAssertEqual(relaunched.state.skin.base, SkinPreset.olive.rgb)
        XCTAssertEqual(relaunched.state.ambientReference, reading)
    }

    func testWatchSwitchingWrapsAround() {
        let model = makeModel()
        let ids = model.state.watches.map(\.id)
        XCTAssertEqual(model.selectedWatch?.id, ids.first)
        model.selectWatch(offset: -1)
        XCTAssertEqual(model.selectedWatch?.id, ids.last)
        model.selectWatch(offset: 1)
        XCTAssertEqual(model.selectedWatch?.id, ids.first)
    }

    func testSavingNewWatchSelectsIt() {
        let model = makeModel()
        var draft = WatchDraft.blank()
        draft.lugToLugText = "50"
        draft.diameterText = "41"
        let spec = try! XCTUnwrap(draft.spec)
        model.saveWatch(spec)
        XCTAssertEqual(model.selectedWatch, spec)
        XCTAssertEqual(makeModel().selectedWatch, spec)
    }

    func testDeletingSelectedWatchSelectsNeighbour() {
        let model = makeModel()
        let second = model.state.watches[1]
        model.selectWatch(second.id)
        model.deleteWatch(second.id)
        XCTAssertEqual(model.selectedWatch?.id, model.state.watches[1].id)
    }

    func testCardCalibrationIsTiedToDevice() {
        let model = makeModel()
        model.saveCardCalibration(matchedHeightPoints: 560)
        XCTAssertEqual(model.scale.source, .card)
        let otherDevice = makeModel(identifier: "iPhone18,1")
        XCTAssertEqual(otherDevice.scale.source, .deviceTable(.oled460))
    }

    func testUnknownDeviceToolFallsBackToProvisional() {
        let model = makeModel()
        XCTAssertEqual(model.scale.source, .deviceTable(.oled476))
        model.state.tools.simulateUnknownDevice = true
        XCTAssertEqual(model.scale.source, .provisional)
        XCTAssertEqual(makeModel(forcesUnknown: true).scale.source, .provisional)
    }

    func testRecalibrationDropsStaleAmbientReference() {
        let model = makeModel()
        model.completeOnboarding(matchedWidthMM: 52, skin: model.state.skin, ambient: AmbientReading(temperatureK: 4000, ev100: 6))
        model.applyWristRecalibration(matchedWidthMM: 55, skin: model.state.skin, ambient: nil)
        XCTAssertNil(model.state.ambientReference)
        XCTAssertEqual(model.state.wrist.matchedWidthMM, 55)
    }
}
