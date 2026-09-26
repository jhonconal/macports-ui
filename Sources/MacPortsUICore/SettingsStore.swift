import Foundation
import Combine

/// App preferences, persisted to `UserDefaults`.
///
/// Kept intentionally small (P0): a custom MacPorts prefix is *not* supported,
/// so there is nothing to store for it. Two knobs are persisted:
///   - `privilegeMode`      – the default elevation strategy for writes
///   - `autoRefreshOutdated` – whether to re-check `port outdated` on launch
///
/// A plain (non-MainActor) `ObservableObject` so it can be owned by
/// `MacPortsService` and read/written by the SwiftUI layer.
public final class SettingsStore: ObservableObject {
    private enum Key {
        static let privilegeMode = "mpui.privilegeMode"
        static let autoRefresh = "mpui.autoRefreshOutdated"
    }

    private let defaults: UserDefaults
    private let privilege: PrivilegeExecutor

    /// Default elevation strategy for write operations.
    @Published public var privilegeMode: PrivilegeMode {
        didSet { defaults.set(privilegeMode.rawValue, forKey: Key.privilegeMode) }
    }
    /// Whether `port outdated` is re-checked when the app launches.
    @Published public var autoRefreshOutdated: Bool {
        didSet { defaults.set(autoRefreshOutdated, forKey: Key.autoRefresh) }
    }

    /// Whether the currently-stored elevation strategy is usable on this host.
    public var isStoredModeAvailable: Bool {
        privilege.isAvailable(privilegeMode)
    }

    public init(defaults: UserDefaults = .standard,
                privilege: PrivilegeExecutor = PrivilegeExecutor()) {
        self.defaults = defaults
        self.privilege = privilege
        // didSet does not fire during init, so there is no spurious write.
        if let raw = defaults.string(forKey: Key.privilegeMode),
           let m = PrivilegeMode(rawValue: raw) {
            self.privilegeMode = m
        } else {
            self.privilegeMode = privilege.isAvailable(.systemDialog) ? .systemDialog : .sudoPassword
        }
        self.autoRefreshOutdated = defaults.object(forKey: Key.autoRefresh) as? Bool ?? true
    }
}
