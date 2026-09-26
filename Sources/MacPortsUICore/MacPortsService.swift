import Foundation
import Combine

/// Drives the UI. Shells out to MacPorts for reads, uses a
/// `PrivilegeExecutor` for writes, parses output, and exposes publishable
/// state. Read operations run without elevation; write operations are gated
/// behind an explicit confirm step and an elevation strategy (system auth
/// dialog, or sudo password).
@MainActor
public final class MacPortsService: ObservableObject {
    public let runner: PortRunner
    public let privilege: PrivilegeExecutor
    /// Persisted preferences (elevation default, launch refresh behavior).
    public let settings: SettingsStore

    // Read state
    @Published public var installedPorts: [InstalledPort] = []
    @Published public var outdatedPorts: [OutdatedPort] = []
    @Published public var searchResults: [SearchHit] = []
    @Published public var detail: PortDetail?
    @Published public var diskUsageBytes: Int64?
    @Published public var selectedPortName: String?
    @Published public var macportsVersion: String?
    @Published public var isMacPortsAvailable: Bool = MacPortsLocator.isPortInstalled
    @Published public var isLoadingInstalled = false
    @Published public var isSearching = false
    @Published public var isDetailLoading = false

    // Dependency graph state
    @Published public var dependencyGraph: DependencyGraph?
    @Published public var isGraphLoading = false
    @Published public var graphFocus: String?
    @Published public var graphScope: GraphScope = .dependencies

    // Write-flow state
    @Published public var writeRunning = false
    @Published public var lastWriteOutcome: WriteOutcome?
    /// The elevation strategy used for writes. Defaults to the system
    /// authorization dialog; falls back to sudo if the dialog is unavailable.
    @Published public var privilegeMode: PrivilegeMode

    // Doctor state
    @Published public var lastDoctorChecks: [DoctorCheck] = []
    @Published public var isDoctorRunning = false

    // `macports.conf` (read-only, for the Settings viewer)
    @Published public var macportsConf: [String: String] = [:]

    // Transparency log (most recent first)
    @Published public var log: [CommandLogEntry] = []

    /// A staged write operation awaiting confirmation.
    public struct PendingWrite {
        public let title: String
        public let args: [String]
        public let display: String

        public init(title: String, args: [String], display: String) {
            self.title = title; self.args = args; self.display = display
        }
    }

    public init(runner: PortRunner = PortRunner(),
                privilege: PrivilegeExecutor = PrivilegeExecutor(),
                settings: SettingsStore = SettingsStore()) {
        self.runner = runner
        self.privilege = privilege
        self.settings = settings
        // The elevation default comes from the persisted preference; fall back
        // to auto-detection when no preference has been stored yet.
        self.privilegeMode = settings.privilegeMode
    }

    // MARK: - bootstrap

    public func bootstrap() async {
        if isMacPortsAvailable {
            await loadVersion()
            await loadInstalled()
            // The "check outdated on launch" preference is honored here: when
            // the user has turned it off we skip the (network-free but still
            // non-trivial) `port outdated` sweep.
            if settings.autoRefreshOutdated { await loadOutdated() }
            await loadGraph()
        }
    }

    // MARK: - reads

    public func loadVersion() async {
        guard let r = await runAndLog(["version"]) else { return }
        macportsVersion = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    public func loadInstalled() async -> [InstalledPort] {
        isLoadingInstalled = true
        defer { isLoadingInstalled = false }
        guard let r = await runAndLog(["installed", "-q"]) else {
            installedPorts = []; return []
        }
        installedPorts = PortOutputParser.parseInstalled(r.stdout)
        return installedPorts
    }

    @discardableResult
    public func loadOutdated() async -> [OutdatedPort] {
        guard let r = await runAndLog(["outdated"]) else {
            outdatedPorts = []; return []
        }
        outdatedPorts = PortOutputParser.parseOutdated(r.stdout)
        return outdatedPorts
    }

    @discardableResult
    public func search(_ term: String) async -> [SearchHit] {
        let q = term.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { searchResults = []; return [] }
        isSearching = true
        defer { isSearching = false }
        guard let r = await runAndLog(["search", q]) else {
            searchResults = []; return []
        }
        searchResults = PortOutputParser.parseSearch(r.stdout)
        return searchResults
    }

    @discardableResult
    public func loadDetail(for name: String) async -> PortDetail? {
        isDetailLoading = true
        defer { isDetailLoading = false }
        guard let r = await runAndLog(["info", name]) else { detail = nil; return nil }
        detail = PortOutputParser.parseInfo(r.stdout)
        return detail
    }

    @discardableResult
    public func loadDiskUsage(for name: String) async -> Int64? {
        guard let r = await runAndLog(["diskusage", name]) else {
            diskUsageBytes = nil; return nil
        }
        diskUsageBytes = PortOutputParser.parseDiskUsageBytes(r.stdout + " " + r.stderr)
        return diskUsageBytes
    }

    @discardableResult
    public func loadGraph() async -> DependencyGraph? {
        guard GraphProvider.isAvailable else { dependencyGraph = nil; return nil }
        isGraphLoading = true
        defer { isGraphLoading = false }
        do {
            let g = try await Task.detached {
                try GraphProvider.loadInstalledGraph()
            }.value
            dependencyGraph = g
            // Seed the graph focus to the currently selected port if any.
            if graphFocus == nil { graphFocus = selectedPortName ?? "curl" }
            return g
        } catch {
            log.insert(CommandLogEntry(command: "sqlite3 registry.db (graph)",
                                       startedAt: Date(), stdout: "", stderr: "\(error)",
                                       exitCode: -1, privileged: false), at: 0)
            dependencyGraph = nil
            return nil
        }
    }

    // MARK: - write builders (no execution)

    public func pendingInstall(_ name: String) -> PendingWrite {
        PendingWrite(title: "Install \(name)", args: ["install", name],
                     display: privilege.displayCommand(["install", name], mode: privilegeMode))
    }
    public func pendingUninstall(_ name: String) -> PendingWrite {
        PendingWrite(title: "Uninstall \(name)", args: ["uninstall", name],
                     display: privilege.displayCommand(["uninstall", name], mode: privilegeMode))
    }
    public func pendingUpgrade(_ name: String) -> PendingWrite {
        PendingWrite(title: "Upgrade \(name)", args: ["upgrade", name],
                     display: privilege.displayCommand(["upgrade", name], mode: privilegeMode))
    }
    public func pendingUpgradeAll() -> PendingWrite {
        PendingWrite(title: "Upgrade all outdated ports", args: ["upgrade", "--all"],
                     display: privilege.displayCommand(["upgrade", "--all"], mode: privilegeMode))
    }
    public func pendingSelfupdate() -> PendingWrite {
        PendingWrite(title: "Selfupdate MacPorts", args: ["selfupdate"],
                     display: privilege.displayCommand(["selfupdate"], mode: privilegeMode))
    }

    // MARK: - detail-pane action decision

    /// Which write action the detail pane should offer for `name`, based on
    /// the current installed/outdated state:
    ///   - not installed          → `.install`
    ///   - installed + outdated   → `.upgrade`
    ///   - installed, up to date → `.uninstall`
    /// `nil` falls back to `.install` (defensive: the pane only renders
    /// actions for a selected port).
    public func detailAction(for name: String?) -> DetailAction {
        guard let name,
              installedPorts.contains(where: { $0.name == name })
        else { return .install }
        return outdatedPorts.contains(where: { $0.name == name }) ? .upgrade : .uninstall
    }

    // MARK: - Doctor (read-only health check)

    /// Runs the full health-check suite. The `port` reads go through the
    /// transparency log; the system probes are best-effort. Result is stored
    /// in `lastDoctorChecks` and returned.
    @discardableResult
    public func runDoctorChecks() async -> [DoctorCheck] {
        isDoctorRunning = true
        defer { isDoctorRunning = false }
        let facts = await doctorFacts()
        let checks = DoctorChecks.evaluate(facts)
        lastDoctorChecks = checks
        return checks
    }

    private func doctorFacts() async -> DoctorFacts {
        var f = DoctorFacts()
        f.portAvailable = MacPortsLocator.isPortInstalled
        f.outdatedCount = outdatedPorts.count
        if f.portAvailable {
            if let r = await runAndLog(["version"]) {
                f.portVersion = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let r = await runAndLog(["outdated"]) {
                f.outdatedCount = PortOutputParser.parseOutdated(r.stdout).count
            }
        }
        f.daysSinceSelfupdate = await Task.detached { DoctorProbes.daysSinceSelfupdate() }.value
        f.cltPath = await Task.detached { DoctorProbes.cltPath() }.value
        f.freeSpaceGB = await Task.detached { DoctorProbes.freeSpaceGB() }.value
        f.sudoCached = await Task.detached { DoctorProbes.sudoCached() }.value
        f.registryAvailable = DoctorProbes.registryAvailable()
        f.confPrefix = DoctorProbes.confPrefix()
        return f
    }

    // MARK: - Settings: read-only `macports.conf`

    /// Loads `macports.conf` into `macportsConf` (plain file read, no
    /// elevation, no shell). Returns the parsed `[key: value]` map, or `nil`
    /// when the file is unreadable.
    @discardableResult
    public func loadMacportsConf() async -> [String: String]? {
        let text = await Task.detached { DoctorProbes.readMacportsConf() }.value
        guard !text.isEmpty else { macportsConf = [:]; return nil }
        macportsConf = PortOutputParser.parseMacportsConf(text)
        return macportsConf
    }

    // MARK: - write execution (elevated, confirm-gated)

    @discardableResult
    public func executeWrite(_ p: PendingWrite, password: String? = nil) async -> WriteOutcome {
        writeRunning = true
        defer { writeRunning = false }
        let outcome: WriteOutcome
        do {
            let mode = privilegeMode
            let r = try await Task.detached { [privilege, mode] in
                try privilege.run(p.args, mode: mode, password: password,
                                   timeout: 15 * 60)
            }.value
            outcome = WriteOutcome(command: r.command, stdout: r.stdout,
                                   stderr: r.stderr, exitCode: r.exitCode)
            log.insert(CommandLogEntry(command: r.command, startedAt: Date(),
                                       stdout: r.stdout, stderr: r.stderr,
                                       exitCode: r.exitCode, privileged: true), at: 0)
        } catch {
            outcome = WriteOutcome(command: privilege.displayCommand(p.args, mode: privilegeMode),
                                   stdout: "", stderr: "\(error)", exitCode: -1)
        }
        lastWriteOutcome = outcome
        // A user-cancelled auth dialog surfaces as failure with a
        // cancellation marker; still refresh views on success.
        if outcome.success {
            await loadInstalled()
            await loadOutdated()
        }
        return outcome
    }

    // MARK: - helpers

    @discardableResult
    private func runAndLog(_ args: [String], timeout: TimeInterval? = nil) async -> PortResult? {
        let result: Result<PortResult, Error> = await Task.detached { [runner] in
            do { return .success(try runner.run(args, timeout: timeout)) }
            catch { return .failure(error) }
        }.value
        switch result {
        case .success(let r):
            log.insert(CommandLogEntry(command: r.command, startedAt: Date(),
                                       stdout: r.stdout, stderr: r.stderr,
                                       exitCode: r.exitCode, privileged: false), at: 0)
            return r
        case .failure(let e):
            log.insert(CommandLogEntry(command: runner.displayCommand(args),
                                       startedAt: Date(), stdout: "", stderr: "\(e)",
                                       exitCode: -1, privileged: false), at: 0)
            return nil
        }
    }
}
