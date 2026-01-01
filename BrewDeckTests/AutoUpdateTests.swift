import SwiftUI
import XCTest

@testable import BrewDeck

// MARK: - Auto-Update Tests

@MainActor
final class AutoUpdateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Ensure a clean slate before each test
        UserDefaults.standard.removeObject(forKey: "autoUpdateEnabled")
    }

    override func tearDown() {
        // Clean up after each test
        UserDefaults.standard.removeObject(forKey: "autoUpdateEnabled")
        super.tearDown()
    }

    func testAutoUpdateToggle() {
        // Test that auto-update can be enabled and disabled
        let viewModel = BrewViewModel()

        XCTAssertFalse(viewModel.autoUpdateEnabled, "Auto-update should be disabled by default")

        viewModel.setAutoUpdateEnabled(true)
        XCTAssertTrue(viewModel.autoUpdateEnabled, "Auto-update should be enabled after setAutoUpdateEnabled(true)")

        viewModel.setAutoUpdateEnabled(false)
        XCTAssertFalse(viewModel.autoUpdateEnabled, "Auto-update should be disabled after setAutoUpdateEnabled(false)")
    }

    func testAutoUpdateStatusMessageWhenDisabled() {
        let viewModel = BrewViewModel()

        XCTAssertEqual(
            viewModel.autoUpdateStatusMessage,
            "Auto-update is disabled",
            "Status message should indicate auto-update is disabled")
    }

    func testAutoUpdateStatusMessageWhenEnabledNoHistory() {
        let viewModel = BrewViewModel()

        viewModel.setAutoUpdateEnabled(true)

        XCTAssertEqual(
            viewModel.autoUpdateStatusMessage,
            "Auto-update enabled (waiting for next check)",
            "Status message should indicate auto-update is enabled with no history")

        viewModel.setAutoUpdateEnabled(false)
    }

    func testAutoUpdateStatusMessageWithLastUpdateTime() {
        let viewModel = BrewViewModel()

        let testDate = Date().addingTimeInterval(-3600)
        viewModel.lastAutoUpdateTime = testDate
        viewModel.setAutoUpdateEnabled(true)

        let statusMessage = viewModel.autoUpdateStatusMessage

        XCTAssertTrue(
            statusMessage.contains("Last auto-update:"),
            "Status message should contain 'Last auto-update:' when there's a last update time")

        viewModel.setAutoUpdateEnabled(false)
    }

    func testAutoUpdateEnabledPersists() {
        // Test that auto-update setting persists using @AppStorage
        let viewModel1 = BrewViewModel()

        viewModel1.setAutoUpdateEnabled(true)

        let viewModel2 = BrewViewModel()

        XCTAssertTrue(
            viewModel2.autoUpdateEnabled,
            "Auto-update setting should persist across view model instances")

        viewModel2.setAutoUpdateEnabled(false)

        let viewModel3 = BrewViewModel()

        XCTAssertFalse(
            viewModel3.autoUpdateEnabled,
            "Auto-update setting should persist as disabled across view model instances")
    }

    func testAutoUpdateToggleMultipleTimes() {
        let viewModel = BrewViewModel()

        for _ in 0..<5 {
            viewModel.setAutoUpdateEnabled(true)
            XCTAssertTrue(viewModel.autoUpdateEnabled)

            viewModel.setAutoUpdateEnabled(false)
            XCTAssertFalse(viewModel.autoUpdateEnabled)
        }
    }
}
