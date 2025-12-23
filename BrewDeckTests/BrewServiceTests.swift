@testable import BrewDeck
import XCTest

final class BrewServiceTests: XCTestCase {
    func testParseDuOutputStandard() {
        let output = """
        100\t/opt/homebrew/Cellar/pkg1
        200\t/opt/homebrew/Cellar/pkg2
        300\t/opt/homebrew/Cellar
        """
        let sizes = BrewService.parseDuOutput(output)

        XCTAssertEqual(sizes["pkg1"], 100 * 1024)
        XCTAssertEqual(sizes["pkg2"], 200 * 1024)
        XCTAssertNil(sizes["Cellar"])
    }

    func testParseDuOutputWithSpaces() {
        let output = """
        100\t/opt/homebrew/Cellar/package with spaces
        """
        let sizes = BrewService.parseDuOutput(output)

        XCTAssertEqual(sizes["package with spaces"], 100 * 1024)
    }

    func testParseDuOutputSpaceSeparated() {
        let output = """
        100 /opt/homebrew/Cellar/pkg1
        200 /opt/homebrew/Cellar/pkg2
        """
        let sizes = BrewService.parseDuOutput(output)

        XCTAssertEqual(sizes["pkg1"], 100 * 1024)
        XCTAssertEqual(sizes["pkg2"], 200 * 1024)
    }

    func testParseDuOutputComplexPath() {
        let output = """
        123\t/usr/local/Cellar/git
        """
        let sizes = BrewService.parseDuOutput(output)
        XCTAssertEqual(sizes["git"], 123 * 1024)
    }

    func testParseDuOutputWithTrailingSlash() {
        let output = "100\t/opt/homebrew/Cellar/pkg1/"
        let sizes = BrewService.parseDuOutput(output)
        XCTAssertEqual(sizes["pkg1"], 100 * 1024)
    }

    func testParseDuOutputCaskroom() {
        let output = """
        500000\t/opt/homebrew/Caskroom/visual-studio-code
        1000000\t/opt/homebrew/Caskroom
        """
        let sizes = BrewService.parseDuOutput(output)
        XCTAssertEqual(sizes["visual-studio-code"], 500_000 * 1024)
        XCTAssertNil(sizes["Caskroom"])
    }

    func testParseDuOutputEmpty() {
        let sizes = BrewService.parseDuOutput("")
        XCTAssertTrue(sizes.isEmpty)
    }
}
