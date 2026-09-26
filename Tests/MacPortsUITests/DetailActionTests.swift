import Foundation
import Testing
@testable import MacPortsUICore

/// The detail-pane action decision: not installed → Install,
/// installed+outdated → Upgrade, installed up-to-date → Uninstall.
@Suite struct DetailActionTests {

    @MainActor
    private func makeService(installed: [String] = [], outdated: [String] = []) -> MacPortsService {
        let s = MacPortsService()
        s.installedPorts = installed.map {
            InstalledPort(name: $0, version: "1.0_0", variants: [], state: "active")
        }
        s.outdatedPorts = outdated.map {
            OutdatedPort(name: $0, installedVersion: "1.0_0", availableVersion: "2.0_0")
        }
        return s
    }

    @MainActor
    @Test func notInstalledOffersInstall() {
        let s = makeService(installed: ["curl"], outdated: [])
        #expect(s.detailAction(for: "gperf") == .install)
        #expect(s.detailAction(for: "nothing-here") == .install)
    }

    @MainActor
    @Test func installedUpToDateOffersUninstall() {
        let s = makeService(installed: ["curl"], outdated: [])
        #expect(s.detailAction(for: "curl") == .uninstall)
    }

    @MainActor
    @Test func installedOutdatedOffersUpgrade() {
        let s = makeService(installed: ["curl", "openssl"], outdated: ["openssl"])
        #expect(s.detailAction(for: "openssl") == .upgrade)
        #expect(s.detailAction(for: "curl") == .uninstall)
    }

    @MainActor
    @Test func nilSelectionFallsBackToInstall() {
        let s = makeService()
        #expect(s.detailAction(for: nil) == .install)
    }
}
