import Foundation

// MARK: - Domain models
// All public: this library (MacPortsUICore) is consumed by the SwiftUI
// executable target and by unit tests, so its API is exposed.

/// An installed port entry (from `port installed -q`).
public struct InstalledPort: Identifiable, Hashable {
    public let name: String
    public let version: String          // includes revision, e.g. "8.22.0_0"
    public let variants: [String]       // e.g. ["brotli", "http2", ...]; empty if none
    public let state: String            // "active" or "inactive"

    public var id: String { "\(name)@\(version)" }
    public var displayVersion: String { version }
    public var variantString: String {
        variants.isEmpty ? "" : "+" + variants.joined(separator: "+")
    }
    public var isActive: Bool { state == "active" }

    public init(name: String, version: String, variants: [String], state: String) {
        self.name = name; self.version = version
        self.variants = variants; self.state = state
    }
}

/// An outdated port (from `port outdated`).
public struct OutdatedPort: Identifiable, Hashable {
    public let name: String
    public let installedVersion: String
    public let availableVersion: String

    public var id: String { name }

    public init(name: String, installedVersion: String, availableVersion: String) {
        self.name = name; self.installedVersion = installedVersion
        self.availableVersion = availableVersion
    }
}

/// A search hit (from `port search <term>`).
public struct SearchHit: Identifiable, Hashable {
    public let name: String
    public let version: String
    public let categories: [String]
    public var summary: String

    public var id: String { "\(name)@\(version)" }

    public init(name: String, version: String, categories: [String], summary: String) {
        self.name = name; self.version = version
        self.categories = categories; self.summary = summary
    }
}

/// Rich detail for one port (from `port info` / `port deps`).
public struct PortDetail: Hashable {
    public let name: String
    public let version: String
    public let categories: [String]
    public let summary: String
    public let homepage: String?
    public let subports: [String]
    public let variantsEnabled: [String]
    public let variantsAll: [String]
    public let extractDeps: [String]
    public let buildDeps: [String]
    public let libraryDeps: [String]

    public var allDependencies: [String] {
        (extractDeps + buildDeps + libraryDeps).uniqued()
    }

    public init(name: String, version: String, categories: [String], summary: String,
                homepage: String?, subports: [String], variantsEnabled: [String],
                variantsAll: [String], extractDeps: [String], buildDeps: [String],
                libraryDeps: [String]) {
        self.name = name; self.version = version; self.categories = categories
        self.summary = summary; self.homepage = homepage; self.subports = subports
        self.variantsEnabled = variantsEnabled; self.variantsAll = variantsAll
        self.extractDeps = extractDeps; self.buildDeps = buildDeps
        self.libraryDeps = libraryDeps
    }
}

extension Array where Element: Hashable {
    /// De-duplicate preserving first-occurrence order.
    public func uniqued() -> [Element] {
        var seen = Set<Element>()
        var out: [Element] = []
        for e in self where seen.insert(e).inserted {
            out.append(e)
        }
        return out
    }
}

/// A recorded `port` invocation for the transparency log.
public struct CommandLogEntry: Identifiable {
    public let id = UUID()
    public let command: String
    public let startedAt: Date
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public let privileged: Bool

    public var success: Bool { exitCode == 0 }
    public var summary: String { stdout.isEmpty ? stderr : stdout }

    public init(command: String, startedAt: Date, stdout: String, stderr: String,
                exitCode: Int32, privileged: Bool) {
        self.command = command; self.startedAt = startedAt; self.stdout = stdout
        self.stderr = stderr; self.exitCode = exitCode; self.privileged = privileged
    }
}

/// The write action the detail pane offers for a selected port.
public enum DetailAction: String, Sendable {
    case install, upgrade, uninstall
}

/// The outcome of a write operation (install/uninstall/upgrade).
public struct WriteOutcome {
    public let command: String
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public var success: Bool { exitCode == 0 }

    public init(command: String, stdout: String, stderr: String, exitCode: Int32) {
        self.command = command; self.stdout = stdout
        self.stderr = stderr; self.exitCode = exitCode
    }
}
