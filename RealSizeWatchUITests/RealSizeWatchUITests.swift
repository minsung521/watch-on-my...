import XCTest

final class RealSizeWatchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// MIN-49 사용 흐름 ①~⑥ 중 시뮬레이터에서 확인 가능한 부분
    func testFullFlowFromOnboardingToSwitchingWatches() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-state"]
        app.launch()

        // ① 기기 식별 → ② 온보딩
        XCTAssertTrue(app.buttons["onboarding.start"].waitForExistence(timeout: 5))
        app.buttons["onboarding.start"].tap()
        app.buttons["onboarding.displayDone"].tap()
        XCTAssertFalse(app.buttons["skin.next"].isEnabled)
        app.buttons["skin.preset.medium"].tap()
        XCTAssertTrue(app.buttons["skin.next"].isEnabled)
        app.buttons["skin.next"].tap()

        let plus = app.buttons["wrist.plus"]
        XCTAssertTrue(plus.waitForExistence(timeout: 3))
        plus.tap()
        plus.tap()
        XCTAssertEqual(app.staticTexts["wrist.width"].label, "화면 폭 53.6mm")
        app.buttons["wrist.done"].tap()
        app.buttons["onboarding.finish"].tap()

        // ④ 렌더링 + 판정
        let name = app.staticTexts["tryon.watchName"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        let first = name.label
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '손목 폭 58mm'")).firstMatch.exists)

        // ⑥ 버튼과 스와이프로 전환
        app.buttons["tryon.next"].tap()
        XCTAssertNotEqual(name.label, first)
        app.otherElements["tryon.canvas"].swipeRight()
        XCTAssertEqual(name.label, first)

        // ③ 스펙 직접 입력: 필수 값 없이는 저장(렌더링) 불가
        app.buttons["tryon.new"].tap()
        let save = app.buttons["editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        XCTAssertFalse(save.isEnabled)
        let lugToLug = app.textFields["editor.l2l"]
        lugToLug.tap()
        lugToLug.typeText("50")
        XCTAssertFalse(save.isEnabled)
        let diameter = app.textFields["editor.diameter"]
        diameter.tap()
        diameter.typeText("41")
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        XCTAssertEqual(name.label, "라운드 41/50")

        // ② 재실행하면 온보딩을 다시 묻지 않는다
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["tryon.watchName"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["tryon.watchName"].label, "라운드 41/50")
        XCTAssertFalse(app.buttons["onboarding.start"].exists)
    }

    /// 화면 캡처용. TEST_RUNNER_SCREENSHOT_DIR=<경로> 를 주고 실행할 때만 동작한다.
    func testScreenshotTour() throws {
        guard let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else {
            throw XCTSkip("SCREENSHOT_DIR이 없어 건너뜀")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-reset-state"]
        app.launch()
        func shot(_ name: String) {
            sleep(1)
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        }

        shot("01-welcome")
        app.buttons["onboarding.start"].tap()
        shot("02-display")
        app.buttons["onboarding.displayDone"].tap()
        app.buttons["skin.preset.medium"].tap()
        shot("03-skin")
        app.buttons["skin.next"].tap()
        shot("04-wrist")
        app.buttons["wrist.done"].tap()
        shot("05-done")
        app.buttons["onboarding.finish"].tap()
        shot("06-tryon")
        app.otherElements["tryon.canvas"].tap()
        shot("06b-tryon-clean")
        app.otherElements["tryon.canvas"].tap()
        for index in 1...6 {
            app.buttons["tryon.next"].tap()
            shot("07-watch-\(index)")
        }
        app.buttons["tryon.edit"].tap()
        shot("08-editor")
        app.buttons["editor.cancel"].tap()
        app.buttons["tryon.new"].tap()
        shot("08b-editor-new")
        app.buttons["editor.cancel"].tap()
        app.buttons["tryon.settings"].tap()
        shot("09-settings")
        app.buttons["실물 카드로 정확도 확인"].tap()
        shot("10-card")
    }

    func testUnknownDeviceShowsBannerButDoesNotBlock() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-state", "-simulate-unknown-device"]
        app.launch()
        XCTAssertTrue(app.otherElements["onboarding.provisionalBanner"].waitForExistence(timeout: 5)
            || app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH '미등록 기기'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["onboarding.start"].isEnabled)
    }
}
