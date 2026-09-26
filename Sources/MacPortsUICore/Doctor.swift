import Foundation

// MARK: - Doctor (health check)
//
// A health check for the MacPorts tree. MacPorts has no built-in "doctor"
// command, so this suite is assembled here. It is split into three layers so
// the testable logic stays pure:
//
//   DoctorProbes     – gather raw facts (system commands + config-file reads)
//   DoctorFacts      – the raw values, decoupled from status decisions
//   DoctorChecks     – pure `evaluate(facts) -> [DoctorCheck]` status decisions
//
// NOTE: only `port` actions that actually exist in MacPorts 2.x are used
// (`version`, `outdated`, `installed`, `info`, `diskusage`). There is no
// `port stale` or `port config` action; configuration is read from
// `macports.conf` on disk instead.

/// Severity of a single health check.
public enum DoctorCheckStatus: String, Hashable, Sendable {
    case ok, warn, fail
}

/// One health-check result.
public struct DoctorCheck: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let status: DoctorCheckStatus
    public let detail: String          // what was found, human-readable
    public let suggestion: String?     // suggested next step (nil when healthy)

    public init(id: String, title: String, status: DoctorCheckStatus,
                detail: String, suggestion: String? = nil) {
        self.id = id; self.title = title; self.status = status
        self.detail = detail; self.suggestion = suggestion
    }

    public var isHealthy: Bool { status == .ok }
}

/// Raw facts gathered by the probes, *before* any status decision.
/// Keeping these separate lets `DoctorChecks.evaluate` stay pure and
/// unit-testable against hand-crafted values.
public struct DoctorFacts: Sendable {
    public var portAvailable: Bool = false
    public var portVersion: String?
    /// Days since the last MacPorts tree `selfupdate` (nil = unknown).
    public var daysSinceSelfupdate: Double?
    /// Result of `xcode-select -p` (nil = Command Line Tools not installed).
    public var cltPath: String?
    /// Free space under the MacPorts prefix, in GB (nil = unknown).
    public var freeSpaceGB: Double?
    /// Whether `sudo` is currently cached (nil = sudo not runnable).
    public var sudoCached: Bool?
    public var outdatedCount: Int = 0
    /// Whether the registry + sqlite3 CLI are present (dependency graph works).
    public var registryAvailable: Bool = false
    /// `prefix` from `macports.conf` (nil = file not readable).
    public var confPrefix: String?

    public init() {}
}

/// Pure status decisions for the Doctor page.
public enum DoctorChecks {

    /// Evaluates every check and returns them in a stable display order.
    public static func evaluate(_ f: DoctorFacts) -> [DoctorCheck] {
        var out: [DoctorCheck] = []
        out.append(checkMacPorts(f))
        out.append(checkTreeAge(f))
        out.append(checkCLT(f))
        out.append(checkDisk(f))
        out.append(checkSudo(f))
        out.append(checkOutdated(f))
        out.append(checkRegistry(f))
        out.append(checkPrefix(f))
        return out
    }

    // MARK: individual checks

    private static func checkMacPorts(_ f: DoctorFacts) -> DoctorCheck {
        guard f.portAvailable, let v = f.portVersion else {
            return DoctorCheck(id: "macports", title: "MacPorts",
                               status: .fail,
                               detail: f.portAvailable ? "MacPorts is installed but its version could not be read."
                                                       : "MacPorts not found at \(MacPortsLocator.defaultPortPath).",
                               suggestion: "Install MacPorts: https://www.macports.org/install.php")
        }
        return DoctorCheck(id: "macports", title: "MacPorts",
                           status: .ok, detail: "\(v)")
    }

    private static func checkTreeAge(_ f: DoctorFacts) -> DoctorCheck {
        guard let d = f.daysSinceSelfupdate else {
            return DoctorCheck(id: "tree-age", title: "Tree freshness",
                               status: .warn,
                               detail: "Could not locate a MacPorts source tree to measure its age.",
                               suggestion: "sudo port selfupdate")
        }
        let days = Int(d)
        switch d {
        case ..<30:
            return DoctorCheck(id: "tree-age", title: "Tree freshness",
                               status: .ok, detail: "Last selfupdate \(days) day\(d == 1 ? "" : "s") ago.")
        case ..<90:
            return DoctorCheck(id: "tree-age", title: "Tree freshness",
                               status: .warn,
                               detail: "Tree is \(days) days old.",
                               suggestion: "sudo port selfupdate")
        default:
            return DoctorCheck(id: "tree-age", title: "Tree freshness",
                               status: .fail,
                               detail: "Tree is \(days) days old — the port database is very likely stale.",
                               suggestion: "sudo port selfupdate")
        }
    }

    private static func checkCLT(_ f: DoctorFacts) -> DoctorCheck {
        guard let p = f.cltPath else {
            return DoctorCheck(id: "clt", title: "Command Line Tools",
                               status: .warn,
                               detail: "No Xcode / Command Line Tools developer directory is configured.",
                               suggestion: "xcode-select --install")
        }
        return DoctorCheck(id: "clt", title: "Command Line Tools",
                           status: .ok, detail: p)
    }

    private static func checkDisk(_ f: DoctorFacts) -> DoctorCheck {
        guard let gb = f.freeSpaceGB else {
            return DoctorCheck(id: "disk", title: "Disk space",
                               status: .warn,
                               detail: "Free space under /opt/local could not be determined.")
        }
        switch gb {
        case 2.0...:
            return DoctorCheck(id: "disk", title: "Disk space",
                               status: .ok, detail: String(format: "%.1f GB free under /opt/local.", gb))
        case 0.5..<2.0:
            return DoctorCheck(id: "disk", title: "Disk space",
                               status: .warn,
                               detail: String(format: "Only %.1f GB free under /opt/local.", gb),
                               suggestion: "Free up space, then `sudo port clean --all`.")
        default:
            return DoctorCheck(id: "disk", title: "Disk space",
                               status: .fail,
                               detail: String(format: "Only %.1f GB free under /opt/local — builds may fail.", gb),
                               suggestion: "Free up space, then `sudo port clean --all`.")
        }
    }

    private static func checkSudo(_ f: DoctorFacts) -> DoctorCheck {
        guard let cached = f.sudoCached else {
            return DoctorCheck(id: "sudo", title: "Privilege elevation",
                               status: .fail,
                               detail: "`sudo` is not available on this host.",
                               suggestion: "Install or repair /usr/bin/sudo.")
        }
        return DoctorCheck(id: "sudo", title: "Privilege elevation",
                           status: .ok,
                           detail: cached ? "sudo is cached — no password prompt right now."
                                          : "sudo is available; a password will be requested for writes.")
    }

    private static func checkOutdated(_ f: DoctorFacts) -> DoctorCheck {
        guard f.outdatedCount > 0 else {
            return DoctorCheck(id: "outdated", title: "Outdated ports",
                               status: .ok, detail: "No installed ports are outdated.")
        }
        return DoctorCheck(id: "outdated", title: "Outdated ports",
                           status: .warn,
                           detail: "\(f.outdatedCount) installed port\(f.outdatedCount == 1 ? "" : "s") can be upgraded.",
                           suggestion: "sudo port upgrade outdated")
    }

    private static func checkRegistry(_ f: DoctorFacts) -> DoctorCheck {
        guard f.registryAvailable else {
            return DoctorCheck(id: "registry", title: "Registry & dependency graph",
                               status: .warn,
                               detail: "registry.db or the sqlite3 CLI is missing, so the Dependencies view is unavailable.",
                               suggestion: "sudo port install sqlite3")
        }
        return DoctorCheck(id: "registry", title: "Registry & dependency graph",
                           status: .ok,
                           detail: "registry.db and sqlite3 are present; the Dependencies view works.")
    }

    private static func checkPrefix(_ f: DoctorFacts) -> DoctorCheck {
        guard let p = f.confPrefix else {
            return DoctorCheck(id: "prefix", title: "Configuration",
                               status: .warn,
                               detail: "macports.conf could not be read at \(MacPortsLocator.defaultMacportsConf).")
        }
        guard p == MacPortsLocator.defaultPrefix else {
            return DoctorCheck(id: "prefix", title: "Configuration",
                               status: .warn,
                               detail: "config prefix is `\(p)` (this app assumes \(MacPortsLocator.defaultPrefix)).",
                               suggestion: "Verify your MacPorts installation matches this app's expected prefix.")
        }
        return DoctorCheck(id: "prefix", title: "Configuration",
                           status: .ok, detail: "prefix = \(p)")
    }

    /// A plain-text, copy-pasteable health report for pasting into an issue
    /// or forum. Pure over the already-evaluated checks.
    public static func reportText(_ checks: [DoctorCheck],
                                  macportsVersion: String?,
                                  platform: String = ProcessInfo.processInfo.operatingSystemVersionString) -> String {
        let problems = checks.filter { !$0.isHealthy }
        var lines: [String] = []
        lines.append("MacPorts health report")
        if let v = macportsVersion { lines.append("MacPorts: \(v)") }
        lines.append("Platform: \(platform)")
        lines.append("")
        lines.append(problems.isEmpty ? "All checks passed."
                                     : "\(problems.count) check(s) need attention:")
        for c in checks {
            let mark = c.status == .ok ? "[ok]  " : c.status == .warn ? "[warn]" : "[fail]"
            lines.append("\(mark) \(c.title): \(c.detail)")
            if let s = c.suggestion, !c.isHealthy { lines.append("       → \(s)") }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Probes

/// Gathers raw facts for the Doctor page. The pure parse/derive helpers are
/// `public` so they can be unit-tested; the process-launching and file-reading
/// wrappers are thin and best-effort (they return `nil`/`false` on any
/// failure rather than throwing).
public enum DoctorProbes {
    /// Path to `git` used for the tree-freshness probe.
    public static let gitPath = "/usr/bin/git"
    /// `xcode-select` used to detect the CLT/Xcode developer directory.
    public static let xcodeSelectPath = "/usr/bin/xcode-select"
    /// `df` used to read free space under the prefix (note: `/bin/df` on
    /// macOS, not `/usr/bin/df`).
    public static let dfPath = "/bin/df"
    /// Candidate locations for the MacPorts source tree whose last commit
    /// marks the tree age. The standard git layout is tried first; the list
    /// is best-effort and a missing tree simply yields an "unknown" age.
    public static var sourceTreeCandidates: [String] {
        [
            MacPortsLocator.defaultPrefix + "/var/macports/source/Current",
        ]
    }

    /// Candidate locations for the MacPorts source tree in the rsync layout
    /// (MacPorts installed from the official pkg with the rsync site). Such
    /// trees carry no git metadata, and `port selfupdate` refreshes them in
    /// place, so the top-level directory's mtime approximates the last
    /// selfupdate time. The list is best-effort; a missing tree yields an
    /// "unknown" age.
    public static var rsyncTreeCandidates: [String] {
        [
            MacPortsLocator.defaultRsyncTreePath,
        ]
    }

    // MARK: pure, testable helpers

    /// Days since a selfupdate, given the epoch-seconds of the last commit
    /// (git tree) or the tree's mtime (rsync tree).
    public static func daysSinceSelfupdate(now: Date, epoch: TimeInterval) -> Double {
        max(0, now.timeIntervalSince1970 - epoch) / 86_400
    }

    /// Parses the free-space figure (in GB) from `df -k <prefix>` output.
    /// The last non-empty line is the data row; its 3rd integer field is
    /// the "available" 1024-blocks column.
    public static func parseFreeGBFromDf(_ text: String) -> Double? {
        let lines = text.components(separatedBy: .newlines)
        guard let data = lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return nil }
        let ints = data.split(whereSeparator: \.isWhitespace)
            .map { $0.description }
            .filter { $0.allSatisfy(\.isNumber) }
        guard ints.count >= 3, let availKB = Double(ints[2]) else { return nil }
        return availKB / 1024 / 1024
    }

    // MARK: process-launching / file-reading wrappers (best-effort)

    private static let fm = FileManager.default

    /// Days since the last `selfupdate`: the source tree's git log on git
    /// layouts, falling back to the tree directory's mtime on rsync layouts
    /// (where `port selfupdate` refreshes the tree in place). Returns `nil`
    /// when no candidate tree is found.
    public static func daysSinceSelfupdate() -> Double? {
        for dir in sourceTreeCandidates where fm.fileExists(atPath: dir + "/.git")
            || fm.fileExists(atPath: dir) {
            let out = try? ProcessSpawner.run(
                executable: gitPath,
                arguments: ["-C", dir, "log", "-1", "--format=%ct"],
                workDir: URL(fileURLWithPath: "/"))
            if let ts = out?.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
               let epoch = Double(ts) {
                return daysSinceSelfupdate(now: Date(), epoch: epoch)
            }
        }
        for dir in rsyncTreeCandidates where fm.fileExists(atPath: dir) {
            if let mtime = (try? fm.attributesOfItem(atPath: dir))?[.modificationDate] as? Date {
                return daysSinceSelfupdate(now: Date(), epoch: mtime.timeIntervalSince1970)
            }
        }
        return nil
    }

    /// The CLT/Xcode developer directory, or `nil` when none is configured.
    public static func cltPath() -> String? {
        let out = try? ProcessSpawner.run(
            executable: xcodeSelectPath, arguments: ["-p"],
            workDir: URL(fileURLWithPath: "/"))
        guard let o = out, o.exitCode == 0 else { return nil }
        let p = o.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? nil : p
    }

    /// Free space in GB under the MacPorts prefix.
    public static func freeSpaceGB() -> Double? {
        let prefix = MacPortsLocator.defaultPrefix
        guard fm.fileExists(atPath: prefix) else { return nil }
        let out = try? ProcessSpawner.run(
            executable: dfPath, arguments: ["-k", prefix],
            workDir: URL(fileURLWithPath: "/"))
        guard let o = out, o.exitCode == 0 else { return nil }
        return parseFreeGBFromDf(o.stdout)
    }

    /// Whether `sudo` is currently cached. `nil` when sudo is not runnable.
    public static func sudoCached() -> Bool? {
        let sudo = MacPortsLocator.defaultSudoPath
        guard fm.isExecutableFile(atPath: sudo) else { return nil }
        let out = try? ProcessSpawner.run(
            executable: sudo, arguments: ["-n", "true"],
            workDir: URL(fileURLWithPath: "/"))
        guard let o = out else { return nil }
        return o.exitCode == 0
    }

    /// Whether the pieces needed for the Dependencies view are present.
    public static func registryAvailable() -> Bool {
        FileManager.default.fileExists(atPath: MacPortsLocator.defaultRegistryDB) &&
        FileManager.default.isExecutableFile(atPath: MacPortsLocator.defaultSqlite3Path)
    }

    /// The raw text of `macports.conf`, or an empty string when unreadable.
    public static func readMacportsConf() -> String {
        guard let text = try? String(contentsOfFile: MacPortsLocator.defaultMacportsConf,
                                     encoding: .utf8)
        else { return "" }
        return text
    }

    /// The `prefix` key from `macports.conf`, or `nil` when unreadable.
    public static func confPrefix() -> String? {
        let parsed = PortOutputParser.parseMacportsConf(readMacportsConf())
        return parsed["prefix"]
    }
}
