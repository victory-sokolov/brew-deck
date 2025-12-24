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

    // MARK: - BrewService+Extensions Tests

    func testSearchPackagesWithShortQuery() async throws {
        // Test that queries shorter than 2 characters return empty array
        let service = BrewService.shared
        let result = try await service.searchPackages(query: "a")
        XCTAssertTrue(result.isEmpty)
    }

    func testSearchPackagesWithEmptyQuery() async throws {
        let service = BrewService.shared
        let result = try await service.searchPackages(query: "")
        XCTAssertTrue(result.isEmpty)
    }

    func testPackageFormattedSize() {
        // Test the formattedSize computed property
        let packageWithSize = Package(
            name: "test",
            fullName: "test",
            description: "test package",
            homepage: "https://example.com",
            type: .formula,
            installedVersion: "1.0.0",
            latestVersion: "1.0.0",
            isOutdated: false,
            sizeOnDisk: 1024 * 1024, // 1 MB
            lastUsedTime: nil,
            installDate: nil,
            dependencies: nil,
            installationPath: nil
        )

        XCTAssertNotNil(packageWithSize.formattedSize)
        XCTAssertTrue(packageWithSize.formattedSize!.contains("1 MB") || packageWithSize.formattedSize!.contains("1MB"))

        let packageWithoutSize = Package(
            name: "test2",
            fullName: "test2",
            description: "test package",
            homepage: "https://example.com",
            type: .formula,
            installedVersion: "1.0.0",
            latestVersion: "1.0.0",
            isOutdated: false,
            sizeOnDisk: nil,
            lastUsedTime: nil,
            installDate: nil,
            dependencies: nil,
            installationPath: nil
        )

        XCTAssertNil(packageWithoutSize.formattedSize)
    }

    func testPackageIsInstalled() {
        let installedPackage = Package(
            name: "installed",
            fullName: "installed",
            description: "installed package",
            homepage: "https://example.com",
            type: .formula,
            installedVersion: "1.0.0",
            latestVersion: "1.0.0",
            isOutdated: false,
            sizeOnDisk: nil,
            lastUsedTime: nil,
            installDate: nil,
            dependencies: nil,
            installationPath: nil
        )

        let notInstalledPackage = Package(
            name: "not-installed",
            fullName: "not-installed",
            description: "not installed package",
            homepage: "https://example.com",
            type: .formula,
            installedVersion: nil,
            latestVersion: "1.0.0",
            isOutdated: false,
            sizeOnDisk: nil,
            lastUsedTime: nil,
            installDate: nil,
            dependencies: nil,
            installationPath: nil
        )

        XCTAssertTrue(installedPackage.isInstalled)
        XCTAssertFalse(notInstalledPackage.isInstalled)
    }

    func testPackageInitFromFormula() {
        let formula = Formula(
            name: "git",
            fullName: "git",
            desc: "Distributed version control system",
            homepage: "https://git-scm.com",
            versions: FormulaVersions(stable: "2.39.0"),
            outdated: false,
            installed: [
                FormulaInstalled(
                    version: "2.39.0",
                    runtimeDependencies: [FormulaDependency(fullName: "curl")],
                    installedOnRequest: true,
                    installedAsDependency: false,
                    installedSize: 1024 * 1024
                )
            ]
        )

        let package = Package(from: formula)

        XCTAssertEqual(package.name, "git")
        XCTAssertEqual(package.fullName, "git")
        XCTAssertEqual(package.description, "Distributed version control system")
        XCTAssertEqual(package.homepage, "https://git-scm.com")
        XCTAssertEqual(package.type, .formula)
        XCTAssertEqual(package.installedVersion, "2.39.0")
        XCTAssertEqual(package.latestVersion, "2.39.0")
        XCTAssertFalse(package.isOutdated)
        XCTAssertEqual(package.sizeOnDisk, 1024 * 1024)
        XCTAssertEqual(package.dependencies, ["curl"])
        XCTAssertTrue(package.isInstalled)
    }

    func testPackageInitFromCask() {
        let cask = Cask(
            token: "visual-studio-code",
            name: ["Visual Studio Code"],
            desc: "Code editing. Redefined.",
            homepage: "https://code.visualstudio.com",
            version: "1.80.0",
            installed: "1.79.0",
            outdated: true
        )

        let package = Package(from: cask)

        XCTAssertEqual(package.name, "visual-studio-code")
        XCTAssertEqual(package.fullName, "Visual Studio Code")
        XCTAssertEqual(package.description, "Code editing. Redefined.")
        XCTAssertEqual(package.homepage, "https://code.visualstudio.com")
        XCTAssertEqual(package.type, .cask)
        XCTAssertEqual(package.installedVersion, "1.79.0")
        XCTAssertEqual(package.latestVersion, "1.80.0")
        XCTAssertTrue(package.isOutdated)
        XCTAssertNil(package.sizeOnDisk)
        XCTAssertNil(package.dependencies)
        XCTAssertTrue(package.isInstalled)
    }

    func testOutdatedPackageInfo() {
        let info = OutdatedPackageInfo(
            name: "git",
            type: .formula,
            installedVersion: "2.38.0",
            latestVersion: "2.39.0"
        )

        XCTAssertEqual(info.name, "git")
        XCTAssertEqual(info.type, .formula)
        XCTAssertEqual(info.installedVersion, "2.38.0")
        XCTAssertEqual(info.latestVersion, "2.39.0")
    }

    func testPackageTypeCodable() {
        // Test that PackageType can be encoded/decoded
        let types: [PackageType] = [.formula, .cask]

        for type in types {
            let data = try? JSONEncoder().encode(type)
            XCTAssertNotNil(data)

            let decoded = try? JSONDecoder().decode(PackageType.self, from: data!)
            XCTAssertEqual(decoded, type)
        }
    }

    func testPackageCodable() {
        let package = Package(
            name: "git",
            fullName: "git",
            description: "Version control",
            homepage: "https://git-scm.com",
            type: .formula,
            installedVersion: "2.39.0",
            latestVersion: "2.39.0",
            isOutdated: false,
            sizeOnDisk: 1024 * 1024,
            lastUsedTime: Date(),
            installDate: Date(),
            dependencies: ["curl"],
            installationPath: "/usr/local/Cellar/git"
        )

        let data = try? JSONEncoder().encode(package)
        XCTAssertNotNil(data)

        let decoded = try? JSONDecoder().decode(Package.self, from: data!)
        XCTAssertEqual(decoded?.name, package.name)
        XCTAssertEqual(decoded?.type, package.type)
        XCTAssertEqual(decoded?.installedVersion, package.installedVersion)
    }
}
