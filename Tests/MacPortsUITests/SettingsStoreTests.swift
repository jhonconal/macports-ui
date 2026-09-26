import Foundation
import Testing
@testable import MacPortsUICore

/// `SettingsStore` persistence tests. Uses an isolated `UserDefaults` suite
/// so the host's real preferences are never touched.
@Suite struct SettingsStoreTests {

    private func makeDefaults() -> UserDefaults {
        let name = "mpui.test.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func defaultsWhenNothingStored() {
        let d = makeDefaults()
        let s = SettingsStore(defaults: d)
        // No stored autoRefresh → default true.
        #expect(s.autoRefreshOutdated == true)
        // privilegeMode is always a valid case.
        #expect(PrivilegeMode.allCases.contains(s.privilegeMode))
    }

    @Test func persistsAutoRefresh() {
        let d = makeDefaults()
        let s = SettingsStore(defaults: d)
        s.autoRefreshOutdated = false
        #expect(d.bool(forKey: "mpui.autoRefreshOutdated") == false)

        // A fresh store reads the persisted value back.
        let s2 = SettingsStore(defaults: d)
        #expect(s2.autoRefreshOutdated == false)
    }

    @Test func persistsPrivilegeMode() {
        let d = makeDefaults()
        let s = SettingsStore(defaults: d)
        s.privilegeMode = .sudoPassword
        #expect(d.string(forKey: "mpui.privilegeMode") == "sudoPassword")

        let s2 = SettingsStore(defaults: d)
        #expect(s2.privilegeMode == .sudoPassword)
    }

    @Test func loadsStoredPrivilegeMode() {
        let d = makeDefaults()
        d.set("systemDialog", forKey: "mpui.privilegeMode")
        let s = SettingsStore(defaults: d)
        #expect(s.privilegeMode == .systemDialog)
    }
}
