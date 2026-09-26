import Foundation
import Testing
@testable import MacPortsUICore

/// Pure-logic tests for the Doctor health-check suite and the two new
/// parsers it relies on. These avoid launching processes: `evaluate`, the
/// df/timestamp helpers, and the parsers are all pure.
@Suite struct DoctorTests {

    // MARK: helpers

    /// A fully-healthy fact set to start from.
    private func healthyFacts() -> DoctorFacts {
        var f = DoctorFacts()
        f.portAvailable = true
        f.portVersion = "MacPorts 2.12.6"
        f.daysSinceSelfupdate = 5
        f.cltPath = "/Library/Developer/CommandLineTools"
        f.freeSpaceGB = 10
        f.sudoCached = true
        f.outdatedCount = 0
        f.registryAvailable = true
        f.confPrefix = "/opt/local"
        return f
    }

    // MARK: evaluate

    @Test func allHealthy() {
        let checks = DoctorChecks.evaluate(healthyFacts())
        #expect(checks.count == 8)
        #expect(checks.allSatisfy { $0.isHealthy })
    }

    @Test func treeAgeThresholds() {
        var f = healthyFacts()

        f.daysSinceSelfupdate = 5
        #expect(DoctorChecks.evaluate(f).first { $0.id == "tree-age" }!.status == .ok)

        f.daysSinceSelfupdate = 45
        #expect(DoctorChecks.evaluate(f).first { $0.id == "tree-age" }!.status == .warn)

        f.daysSinceSelfupdate = 200
        #expect(DoctorChecks.evaluate(f).first { $0.id == "tree-age" }!.status == .fail)

        f.daysSinceSelfupdate = nil
        #expect(DoctorChecks.evaluate(f).first { $0.id == "tree-age" }!.status == .warn)
    }

    @Test func cltMissingIsWarn() {
        var f = healthyFacts()
        f.cltPath = nil
        let c = DoctorChecks.evaluate(f).first { $0.id == "clt" }!
        #expect(c.status == .warn)
        #expect(c.suggestion == "xcode-select --install")
    }

    @Test func diskThresholds() {
        var f = healthyFacts()
        f.freeSpaceGB = 3
        #expect(DoctorChecks.evaluate(f).first { $0.id == "disk" }!.status == .ok)
        f.freeSpaceGB = 1
        #expect(DoctorChecks.evaluate(f).first { $0.id == "disk" }!.status == .warn)
        f.freeSpaceGB = 0.3
        #expect(DoctorChecks.evaluate(f).first { $0.id == "disk" }!.status == .fail)
    }

    @Test func sudoUnavailableIsFail() {
        var f = healthyFacts()
        f.sudoCached = nil
        #expect(DoctorChecks.evaluate(f).first { $0.id == "sudo" }!.status == .fail)
    }

    @Test func outdatedWarnsWithCount() {
        var f = healthyFacts()
        f.outdatedCount = 3
        let c = DoctorChecks.evaluate(f).first { $0.id == "outdated" }!
        #expect(c.status == .warn)
        #expect(c.detail.contains("3"))
        #expect(c.suggestion == "sudo port upgrade outdated")
    }

    @Test func registryMissingIsWarn() {
        var f = healthyFacts()
        f.registryAvailable = false
        let c = DoctorChecks.evaluate(f).first { $0.id == "registry" }!
        #expect(c.status == .warn)
        #expect(c.suggestion == "sudo port install sqlite3")
    }

    @Test func prefixMismatchIsWarn() {
        var f = healthyFacts()
        f.confPrefix = "/opt/custom"
        #expect(DoctorChecks.evaluate(f).first { $0.id == "prefix" }!.status == .warn)
    }

    /// Environment-dependent: verifies the rsync-layout tree (no git metadata,
    /// age measured via directory mtime) is found when it exists on this host.
    @Test func rsyncTreeAgeProbeFindsRsyncTree() {
        guard FileManager.default.fileExists(atPath: MacPortsLocator.defaultRsyncTreePath)
        else { return }
        #expect(DoctorProbes.daysSinceSelfupdate() != nil)
    }

    @Test func prefixUnreadableIsWarn() {
        var f = healthyFacts()
        f.confPrefix = nil
        #expect(DoctorChecks.evaluate(f).first { $0.id == "prefix" }!.status == .warn)
    }

    @Test func macPortsUnavailableIsFail() {
        var f = healthyFacts()
        f.portAvailable = false
        f.portVersion = nil
        #expect(DoctorChecks.evaluate(f).first { $0.id == "macports" }!.status == .fail)
    }

    // MARK: report text

    @Test func reportTextListsOnlyProblemSuggestions() {
        var f = healthyFacts()
        f.daysSinceSelfupdate = 120
        f.outdatedCount = 2
        let checks = DoctorChecks.evaluate(f)
        let report = DoctorChecks.reportText(checks, macportsVersion: "MacPorts 2.12.6")
        #expect(report.contains("2 check(s) need attention"))
        #expect(report.contains("sudo port selfupdate"))
        #expect(report.contains("sudo port upgrade outdated"))
        // A healthy check's suggestion must not be printed (there is none to print anyway).
        #expect(!report.contains("xcode-select --install"))
    }

    @Test func reportTextAllHealthy() {
        let checks = DoctorChecks.evaluate(healthyFacts())
        #expect(DoctorChecks.reportText(checks, macportsVersion: "MacPorts 2.12.6")
            .contains("All checks passed."))
    }

    // MARK: probe pure helpers

    @Test func parseFreeGBFromDf() {
        // `df -k /opt/local` sample data row: fs blocks used avail capacity ...
        let text = """
        Filesystem     1024-blocks    Used  Available Capacity
        /dev/disk3s5s1  486727104  91345632  370800560    20%
        """
        let gb = DoctorProbes.parseFreeGBFromDf(text)
        #expect(gb != nil)
        // 370800560 KB ≈ 353.8 GB
        #expect(gb! > 353 && gb! < 355)
    }

    @Test func parseFreeGBFromDfEmpty() {
        #expect(DoctorProbes.parseFreeGBFromDf("") == nil)
    }

    @Test func daysSinceSelfupdateHelper() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        let eightDays = DoctorProbes.daysSinceSelfupdate(now: now, epoch: 1_000_000_000 - 8 * 86_400)
        #expect(abs(eightDays - 8) < 0.001)
        // Negative deltas are clamped to 0.
        #expect(DoctorProbes.daysSinceSelfupdate(now: now, epoch: 1_000_000_000 + 5000) == 0)
    }

    // MARK: new parsers

    @Test func parseMacportsConf() {
        let text = """
        # MacPorts system-wide configuration file.
        prefix              \t/opt/local
        portdbpath          \t/opt/local/var/macports
        applications_dir    \t/Applications/MacPorts
        #binpath            /opt/local/bin:/usr/bin

        """
        let cfg = PortOutputParser.parseMacportsConf(text)
        #expect(cfg["prefix"] == "/opt/local")
        #expect(cfg["portdbpath"] == "/opt/local/var/macports")
        #expect(cfg["applications_dir"] == "/Applications/MacPorts")
        // Commented-out keys are skipped.
        #expect(cfg["binpath"] == nil)
    }

    @Test func parseMacportsConfMultiTokenValue() {
        let text = "sources /opt/local/var/macports/source/Current https://example.com"
        let cfg = PortOutputParser.parseMacportsConf(text)
        #expect(cfg["sources"] == "/opt/local/var/macports/source/Current https://example.com")
    }
}
