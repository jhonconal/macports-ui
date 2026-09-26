import SwiftUI
import AppKit
import MacPortsUICore

/// Preferences sheet, triggered from the sidebar's ⚙ button.
///
/// P0 scope (a custom MacPorts prefix is deliberately *not* supported):
///   - MacPorts environment, shown read-only
///   - Default elevation strategy (system dialog vs. sudo password)
///   - "Check outdated on launch" toggle
///   - A read-only `port config` viewer
struct SettingsSheet: View {
    @EnvironmentObject var service: MacPortsService
    @ObservedObject var settings: SettingsStore
    let onDismiss: () -> Void

    @State private var showConfigViewer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                monogram
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings").font(.system(size: 18, weight: .bold))
                    Text("MacPorts preferences").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    environmentSection
                    elevationSection
                    refreshSection
                    configSection
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }

            Divider()
            HStack {
                Spacer()
                Button("Done") { onDismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .frame(width: 440)
        // Persist the live elevation mode into the store whenever it changes.
        .onChange(of: service.privilegeMode) { m in settings.privilegeMode = m }
        .sheet(isPresented: $showConfigViewer) {
            PortConfigViewer()
        }
    }

    // MARK: - sections

    private var environmentSection: some View {
        section("MacPorts") {
            VStack(alignment: .leading, spacing: 6) {
                kvRow("Version", service.macportsVersion ?? "—")
                kvRow("port", service.runner.portPath)
                kvRow("Prefix", MacPortsLocator.defaultPrefix)
                kvRow("registry.db", MacPortsLocator.defaultRegistryDB)
                // NOTE: temporarily suppressed; re-enable when custom-prefix
                // support lands (PortRunner parameterization, P1+).
                // Text("Custom prefix support is planned for a future release.")
                //     .font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var elevationSection: some View {
        section("Privilege elevation") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Default method", selection: $service.privilegeMode) {
                    Text("System authorization dialog").tag(PrivilegeMode.systemDialog)
                    Text("sudo password (in-app)").tag(PrivilegeMode.sudoPassword)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                if !service.privilege.isAvailable(service.privilegeMode) {
                    Label("This method is not available on this host.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private var refreshSection: some View {
        section("Refresh") {
            Toggle("Check for outdated ports when the app launches",
                   isOn: $settings.autoRefreshOutdated)
                .font(.system(size: 12))
        }
    }

    private var configSection: some View {
        section("Configuration") {
            HStack(spacing: 10) {
                Button {
                    Task { await service.loadMacportsConf() }
                    showConfigViewer = true
                } label: {
                    Label("View macports.conf", systemImage: "list.bullet")
                }
                .buttonStyle(.bordered)
                Text(service.macportsConf.isEmpty ? "Read-only view of \(MacPortsLocator.defaultMacportsConf)."
                                                  : "Loaded \(service.macportsConf.count) keys.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - chrome

    private var monogram: some View {
        Text("S")
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
                .frame(width: 90, alignment: .leading)
            Text(v).font(.system(size: 12, weight: .medium)).lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Read-only view of `macports.conf`, with key entries highlighted.
private struct PortConfigViewer: View {
    @EnvironmentObject var service: MacPortsService

    /// Keys worth surfacing at the top.
    private let highlightKeys = ["prefix", "portdbpath", "sources_conf", "rsync_server", "rsync_dir"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("macports.conf").font(.system(size: 15, weight: .bold))
                Spacer()
                Button("Refresh") { Task { await service.loadMacportsConf() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)

            Divider()

            if service.macportsConf.isEmpty {
                VStack(spacing: 8) {
                    ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(service.macportsConf.keys.sorted()), id: \.self) { key in
                            configRow(key, service.macportsConf[key] ?? "")
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(width: 440, height: 360)
    }

    private func configRow(_ key: String, _ value: String) -> some View {
        let highlighted = highlightKeys.contains(key)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(.system(size: 12, weight: highlighted ? .semibold : .regular, design: .monospaced))
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1).truncationMode(.middle)
                .foregroundStyle(highlighted ? .primary : .secondary)
            Spacer()
        }
        .padding(.vertical, 3)
    }
}
