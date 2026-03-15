import XCTest

final class CallNotesUITests: XCTestCase {
    func testRecordTabLoads() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Start Call Notes"].waitForExistence(timeout: 3))
    }
}

