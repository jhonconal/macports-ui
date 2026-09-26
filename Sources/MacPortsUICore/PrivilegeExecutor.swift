import Foundation

/// How a privileged `port` write operation is elevated.
public enum PrivilegeMode: String, Sendable, CaseIterable {
    /// Uses Authorization Services via `osascript ... with administrator
    /// privileges`: the system shows its native password dialog and runs the
    /// command as root. No password is ever captured in the UI. Preferred.
    case systemDialog
    /// Classic `sudo -S`: the UI collects the password and feeds it to sudo's
    /// stdin. Fallback when the system dialog is unavailable/undesired.
    case sudoPassword
}

/// Executes **privileged** `port` write operations (install/uninstall/
/// upgrade/selfupdate) using one of two elevation strategies.
public struct PrivilegeExecutor: Sendable {
    public let portPath: String
    public let sudoPath: String
    public let osascriptPath: String
    public let workDir: URL

    public init(portPath: String = MacPortsLocator.defaultPortPath,
                sudoPath: String = MacPortsLocator.defaultSudoPath,
                osascriptPath: String = MacPortsLocator.defaultOsascriptPath,
                workDir: URL = URL(fileURLWithPath: MacPortsLocator.defaultWorkDir)) {
        self.portPath = portPath
        self.sudoPath = sudoPath
        self.osascriptPath = osascriptPath
        self.workDir = workDir
    }

    /// Whether the given strategy is usable on this host.
    public func isAvailable(_ mode: PrivilegeMode) -> Bool {
        let fm = FileManager.default
        switch mode {
        case .systemDialog: return fm.isExecutableFile(atPath: osascriptPath)
        case .sudoPassword: return fm.isExecutableFile(atPath: sudoPath)
        }
    }

    /// Human-readable command line for the transparency log.
    public func displayCommand(_ args: [String], mode: PrivilegeMode) -> String {
        switch mode {
        case .systemDialog:
            return "sudo(root) \(portPath) \(args.joined(separator: " "))  [Authorization dialog]"
        case .sudoPassword:
            return "sudo \(portPath) \(args.joined(separator: " "))"
        }
    }

    @discardableResult
    public func run(_ args: [String], mode: PrivilegeMode,
                    password: String? = nil,
                    timeout: TimeInterval? = nil) throws -> PortResult {
        switch mode {
        case .systemDialog:
            let stmt = ShellEscape.osascriptAdminStatement(path: portPath, args: args)
            let out = try ProcessSpawner.run(executable: osascriptPath,
                                             arguments: ["-e", stmt],
                                             workDir: workDir,
                                             timeout: timeout)
            // osascript propagates the shell's stdout as its own stdout; on a
            // non-zero shell exit or a user-cancelled auth dialog it exits 1
            // and puts an AppleScript error on stderr.
            return PortResult(exitCode: out.exitCode, stdout: out.stdout,
                              stderr: out.stderr, command: displayCommand(args, mode: mode))

        case .sudoPassword:
            let out = try ProcessSpawner.run(executable: sudoPath,
                                             arguments: ["-S", "-p", ""] + [portPath] + args,
                                             stdin: (password ?? "") + "\n",
                                             workDir: workDir,
                                             timeout: timeout)
            return PortResult(exitCode: out.exitCode, stdout: out.stdout,
                              stderr: out.stderr, command: displayCommand(args, mode: mode))
        }
    }
}
