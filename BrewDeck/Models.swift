import Foundation

enum PackageType: String, Codable, CaseIterable {
    case formula
    case cask
}

struct Package: Identifiable, Codable, Hashable {
    var id: String { self.name }
    let name: String
    let fullName: String?
    let description: String?
    let homepage: String?
    let type: PackageType
    let installedVersion: String?
    let latestVersion: String
    let isOutdated: Bool
    var sizeOnDisk: Int64? // Only for formulae usually
    let lastUsedTime: Date?
    let installDate: Date?

    // Additional metadata
    let dependencies: [String]?
    let installationPath: String?

    var isInstalled: Bool {
        self.installedVersion != nil
    }

    var formattedSize: String? {
        guard let size = sizeOnDisk else { return nil }

        // Handle zero size (which is valid for symlinks) and very small sizes
        if size == 0 {
            return "0 bytes"
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

// MARK: - JSON Decoding Structures

struct BrewInfoResponse: Decodable {
    let formulae: [Formula]
    let casks: [Cask]
}

struct Formula: Decodable {
    let name: String
    let fullName: String?
    let desc: String?
    let homepage: String?
    let versions: FormulaVersions?
    let outdated: Bool?
    let installed: [FormulaInstalled]?

    enum CodingKeys: String, CodingKey {
        case name, homepage, desc, versions, outdated, installed
        case fullName = "full_name"
    }
}

struct FormulaVersions: Decodable {
    let stable: String?
}

struct FormulaInstalled: Decodable {
    let version: String
    let runtimeDependencies: [FormulaDependency]?
    let installedOnRequest: Bool?
    let installedAsDependency: Bool?
    let installedSize: Int64?

    enum CodingKeys: String, CodingKey {
        case version, installedOnRequest, installedAsDependency
        case runtimeDependencies = "runtime_dependencies"
        case installedSize = "installed_size"
    }
}

struct FormulaDependency: Decodable {
    let fullName: String

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
    }
}

struct Cask: Decodable {
    let token: String
    let name: [String]?
    let desc: String?
    let homepage: String?
    let version: String
    let installed: String?
    let outdated: Bool?

    enum CodingKeys: String, CodingKey {
        case token, name, desc, homepage, version, installed, outdated
    }
}

struct OutdatedResponse: Decodable {
    let formulae: [OutdatedFormula]
    let casks: [OutdatedCask]
}

struct OutdatedFormula: Decodable {
    let name: String
    let installedVersions: [String]
    let currentVersion: String

    enum CodingKeys: String, CodingKey {
        case name
        case installedVersions = "installed_versions"
        case currentVersion = "current_version"
    }
}

struct OutdatedCask: Decodable {
    let name: String
    let installedVersions: [String]
    let currentVersion: String

    enum CodingKeys: String, CodingKey {
        case name
        case installedVersions = "installed_versions"
        case currentVersion = "current_version"
    }
}

struct OutdatedPackageInfo: Codable {
    let name: String
    let type: PackageType
    let installedVersion: String
    let latestVersion: String
}

extension Package {
    init(from formula: Formula) {
        self.name = formula.name
        self.fullName = formula.fullName
        self.description = formula.desc
        self.homepage = formula.homepage
        self.type = .formula
        self.installedVersion = formula.installed?.first?.version
        self.latestVersion = formula.versions?.stable ?? ""
        self.isOutdated = formula.outdated ?? false
        self.sizeOnDisk = formula.installed?.first?.installedSize
        self.lastUsedTime = nil
        self.installDate = nil
        self.dependencies = formula.installed?.first?.runtimeDependencies?.map(\.fullName)
        self.installationPath = nil
    }

    init(from cask: Cask) {
        self.name = cask.token
        self.fullName = cask.name?.first
        self.description = cask.desc
        self.homepage = cask.homepage
        self.type = .cask
        self.installedVersion = cask.installed
        self.latestVersion = cask.version
        self.isOutdated = cask.outdated ?? false
        self.sizeOnDisk = nil
        self.lastUsedTime = nil
        self.installDate = nil
        self.dependencies = nil
        self.installationPath = nil
    }
}
