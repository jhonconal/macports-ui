import Foundation

/// Result of a single `port` invocation.
public struct PortResult {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let command: String        // the human-readable command line that ran
    public var success: Bool { exitCode == 0 }

    public init(exitCode: Int32, stdout: String, stderr: String, command: String) {
        self.exitCode = exitCode; self.stdout = stdout
        self.stderr = stderr; self.command = command
    }
}

/// Well-known locations for a default MacPorts install under /opt/local.
public enum MacPortsLocator {
    /// The MacPorts installation prefix (default, non-customizable in P0).
    public static let defaultPrefix = "/opt/local"
    public static let defaultPortPath = "/opt/local/bin/port"
    public static let defaultSudoPath = "/usr/bin/sudo"
    public static let defaultOsascriptPath = "/usr/bin/osascript"
    public static let defaultSqlite3Path = "/opt/local/bin/sqlite3"
    public static let defaultRegistryDB = "/opt/local/var/macports/registry/registry.db"
    /// Ports tree of an rsync-site MacPorts install (the official pkg layout).
    /// `port selfupdate` refreshes this tree in place, so the top-level
    /// directory's mtime is a usable "last selfupdate" signal.
    public static let defaultRsyncTreePath = "/opt/local/var/macports/sources/rsync.macports.org/macports/release/tarballs/ports"
    /// System-wide MacPorts configuration file (`key<TAB>value` lines).
    public static let defaultMacportsConf = "/opt/local/etc/macports/macports.conf"
    /// Ports-source list.
    public static let defaultSourcesConf = "/opt/local/etc/macports/sources.conf"
    /// Run `port` from a neutral directory so it never interprets the CWD
    /// as a port tree (which is what makes `port config` misbehave).
    public static let defaultWorkDir = "/"

    public static var isPortInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: defaultPortPath)
    }
}

/// Runs **read / non-privileged** `port <args>` invocations. Privileged
/// writes are handled by `PrivilegeExecutor`.
public struct PortRunner: Sendable {
    public var portPath: String
    public var workDir: URL

    public init(portPath: String = MacPortsLocator.defaultPortPath,
                workDir: URL = URL(fileURLWithPath: MacPortsLocator.defaultWorkDir)) {
        self.portPath = portPath
        self.workDir = workDir
    }

    /// Human-readable command line, used for the transparency log.
    public func displayCommand(_ args: [String]) -> String {
        "\(portPath) \(args.joined(separator: " "))"
    }

    /// Runs `port <args>` (no elevation). `timeout` (seconds) terminates the
    /// process if exceeded.
    @discardableResult
    public func run(_ args: [String], timeout: TimeInterval? = nil) throws -> PortResult {
        let command = displayCommand(args)
        let out = try ProcessSpawner.run(executable: portPath,
                                         arguments: args,
                                         workDir: workDir,
                                         timeout: timeout)
        return PortResult(exitCode: out.exitCode, stdout: out.stdout,
                          stderr: out.stderr, command: command)
    }
}
