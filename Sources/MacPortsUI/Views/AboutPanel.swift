import SwiftUI
import AppKit
import MacPortsUICore

/// About / Info sheet: app + MacPorts info, environment self-check,
/// documentation links, and an "open in Terminal" shortcut.
///
/// Triggered from the sidebar's ℹ button (see SidebarView / ContentView).
struct AboutSheet: View {
    @EnvironmentObject var service: MacPortsService
    let onDismiss: () -> Void

    private let fm = FileManager.default

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                monogram
                VStack(alignment: .leading, spacing: 2) {
                    Text("MacPorts").font(.system(size: 18, weight: .bold))
                    Text("version \(AppInfo.version) · native SwiftUI reference implementation")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    macportsSection
                    environmentSection
                    linksSection
                    terminalSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            Divider()
            HStack {
                Spacer()
                Button("Close") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 420)
    }

    // MARK: - MacPorts facts

    private var macportsSection: some View {
        section("MacPorts") {
            kvRow("Version", service.macportsVersion ?? "—")
            kvRow("port", service.runner.portPath)
            kvRow("Prefix", "/opt/local")
            kvRow("Installed ports", "\(service.installedPorts.count)")
            kvRow("Outdated ports", "\(service.outdatedPorts.count)")
        }
    }

    // MARK: - environment self-check

    private var environmentSection: some View {
        section("Environment") {
            VStack(spacing: 6) {
                checkRow("port executable", fm.isExecutableFile(atPath: service.runner.portPath))
                checkRow("sudo (password elevation)", fm.isExecutableFile(atPath: service.privilege.sudoPath))
                checkRow("osascript (system dialog)", fm.isExecutableFile(atPath: service.privilege.osascriptPath))
                checkRow("sqlite3 CLI", fm.isExecutableFile(atPath: MacPortsLocator.defaultSqlite3Path))
                checkRow("registry.db", fm.fileExists(atPath: MacPortsLocator.defaultRegistryDB))
                checkRow("Dependency graph", GraphProvider.isAvailable)
            }
        }
    }

    private func checkRow(_ label: String, _ ok: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
                .font(.system(size: 13))
            Text(label).font(.system(size: 12))
            if !ok {
                Text("missing").font(.system(size: 11)).foregroundStyle(.red)
            }
            Spacer()
        }
    }

    // MARK: - links

    private var linksSection: some View {
        section("Links") {
            VStack(alignment: .leading, spacing: 6) {
                link("MacPorts", "https://www.macports.org")
                link("MacPorts Wiki", "https://trac.macports.org/wiki/WikiStart")
                link("MacPorts (GitHub)", "https://github.com/macports/macports")
            }
        }
    }

    private func link(_ label: String, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 6) {
                Text(label)
                Text(url)
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - open in terminal

    private var terminalSection: some View {
        section("Terminal") {
            VStack(alignment: .leading, spacing: 8) {
                if let cmd = lastWriteCommand {
                    Text(cmd)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 6))
                    Button {
                        TerminalLauncher.open(command: cmd)
                    } label: {
                        Label("Open Terminal (command copied — paste ⌘V to run)",
                              systemImage: "terminal")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text("No write command yet. Run an install/upgrade, then you can open it here.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Most recent privileged command from the transparency log.
    private var lastWriteCommand: String? {
        service.lastWriteOutcome?.command
            ?? service.log.first(where: \.privileged)?.command
    }

    // MARK: - shared bits

    private var monogram: some View {
        Text("M")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 11))
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold)).tracking(0.6)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func kvRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(k).font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(v).font(.system(size: 12, weight: .medium)).lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// App version, hardcoded until the bundle's CFBundleShortVersionString is
/// wired through (SPM executable has no Info.plist in debug builds).
enum AppInfo {
    static let version = "0.1.0"
}

/// Copies a command to the clipboard and opens Terminal so the user can
/// paste-and-run it. Intentionally not auto-executed: running a privileged
/// command is a user action (matches the "write-before-confirm" principle).
enum TerminalLauncher {
    @MainActor
    static func open(command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Terminal"]
        try? p.run()
    }
}
