import SwiftUI
import AppKit
import MacPortsUICore

/// Right-hand detail pane (BrewUI style): monogram header, key/value
/// DETAILS block, DEPENDENCIES / DEPENDENTS lists, and an action section
/// with a copyable terminal command + elevated buttons.
struct DetailPane: View {
    @EnvironmentObject var service: MacPortsService
    let onRequestWrite: (MacPortsService.PendingWrite) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let name = service.selectedPortName,
               let d = service.detail, d.name == name {
                body_
            } else if let name = service.selectedPortName {
                loading(name)
            } else {
                placeholder
            }
            Spacer()
        }
        .frame(width: 330)
        // Adaptive: white (textBackgroundColor) in light mode, system dark
        // surface in dark mode — keeps the white-card look in light and
        // removes the hardcoded-white-in-dark bug.
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: service.selectedPortName) { name in
            service.diskUsageBytes = nil
            guard let name else { service.detail = nil; return }
            Task {
                await service.loadDetail(for: name)
                await service.loadDiskUsage(for: name)
            }
        }
    }

    // MARK: - main body

    private var outdated: OutdatedPort? {
        guard let name = service.selectedPortName else { return nil }
        return service.outdatedPorts.first { $0.name == name }
    }

    private var dependents: [String] {
        guard let name = service.selectedPortName,
              let g = service.dependencyGraph else { return [] }
        return Array(g.reverse[name] ?? [])
    }

    @ViewBuilder
    private var body_: some View {
        if let d = service.detail, let name = service.selectedPortName, d.name == name {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(d)
                    detailsSection(d)
                    if !d.allDependencies.isEmpty {
                        section("Dependencies") { depList(d.allDependencies) }
                    }
                    section("Dependents") {
                        if dependents.isEmpty {
                            Text("No dependents.").font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        } else {
                            depList(dependents)
                        }
                    }
                    actionSection(d)
                }
                .padding(16)
            }
        } else {
            Text("No details available for “\(service.selectedPortName ?? "")”.")
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(16)
        }
    }

    private func header(_ d: PortDetail) -> some View {
        HStack(spacing: 10) {
            monogram(d.name)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(d.name).font(.system(size: 15, weight: .bold))
                    if outdated != nil {
                        chip("OUTDATED", warn: true)
                    }
                }
                if !d.summary.isEmpty {
                    Text(d.summary).font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
    }

    private func detailsSection(_ d: PortDetail) -> some View {
        section("Details") {
            VStack(spacing: 7) {
                kvRow("Installed", d.version)
                if let o = outdated {
                    kvRow("Latest", o.availableVersion, valueColor: .orange)
                }
                if let h = d.homepage, !h.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        key("Homepage")
                        Link(h.replacingOccurrences(of: "https://", with: ""),
                             destination: URL(string: h) ?? URL(string: "https://localhost")!)
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                if !d.categories.isEmpty {
                    kvRow("Categories", d.categories.joined(separator: ", "))
                }
                if let bytes = service.diskUsageBytes {
                    kvRow("Disk usage",
                          ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                }
            }
        }
    }

    @ViewBuilder
    private func actionSection(_ d: PortDetail) -> some View {
        switch service.detailAction(for: service.selectedPortName) {
        case .install:
            // Not installed → offer Install (privilege-gated write) instead
            // of the uninstall/upgrade actions shown for installed ports.
            installSection(d)
        case .upgrade:
            upgradeSection(d)
        case .uninstall:
            uninstallSection(d)
        }
    }

    /// Not-installed port: the Install action.
    private func installSection(_ d: PortDetail) -> some View {
        let cmd = service.privilege.displayCommand(["install", d.name], mode: service.privilegeMode)
        return section("Install") {
            commandCard(cmd, subtitle: "Installs this port into \(MacPortsLocator.defaultPrefix)")
            Button {
                onRequestWrite(service.pendingInstall(d.name))
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Install")
                    Text("· \(d.version)")
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .frame(maxWidth: .infinity)
            .disabled(service.writeRunning)
            .controlSize(.regular)
        }
    }

    /// Outdated installed port: Upgrade (prominent) + Uninstall side by side,
    /// matching the pre-change layout.
    private func upgradeSection(_ d: PortDetail) -> some View {
        let cmd = service.privilege.displayCommand(["upgrade", d.name], mode: service.privilegeMode)
        return section("Upgrade") {
            commandCard(cmd, subtitle: "Upgrades this port to the newest version")
            HStack(spacing: 8) {
                Button {
                    onRequestWrite(service.pendingUpgrade(d.name))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("Upgrade")
                        if let o = outdated {
                            Text("· \(o.installedVersion) → \(o.availableVersion)")
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .frame(maxWidth: .infinity)
                .disabled(service.writeRunning)
                Button(role: .destructive) {
                    onRequestWrite(service.pendingUninstall(d.name))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Uninstall")
                    }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .disabled(service.writeRunning)
            }
            .controlSize(.regular)
        }
    }

    /// Installed, up-to-date port: Uninstall only.
    private func uninstallSection(_ d: PortDetail) -> some View {
        let cmd = service.privilege.displayCommand(["uninstall", d.name], mode: service.privilegeMode)
        return section("Uninstall") {
            commandCard(cmd, subtitle: "Uninstalls this port from this Mac")
            HStack(spacing: 8) {
                Button(role: .destructive) {
                    onRequestWrite(service.pendingUninstall(d.name))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Uninstall")
                    }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .disabled(service.writeRunning)
            }
            .controlSize(.regular)
        }
    }

    /// Shared "Terminal command" card (copy + open-in-Terminal) for an
    /// elevated command; reused by the install / upgrade / uninstall actions.
    private func commandCard(_ cmd: String, subtitle: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Label("Terminal command", systemImage: "terminal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cmd, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                Button {
                    TerminalLauncher.open(command: cmd)
                } label: {
                    Label("Open in Terminal", systemImage: "terminal")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Copies the command and opens Terminal — paste (⌘V) to run")
            }
            .padding(10)
            Text(cmd)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 12).padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(subtitle)
                .font(.system(size: 11)).foregroundStyle(.tertiary)
                .padding(.horizontal, 12).padding(.bottom, 10)
        }
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.gray.opacity(0.15)))
    }

    // MARK: - pieces

    private func loading(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            monogram(name)
            ProgressView().controlSize(.small)
            Text(name).font(.system(size: 15, weight: .bold))
        }
        .padding(16)
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "sidebar.right").font(.system(size: 28)).foregroundStyle(.tertiary)
            Text("Select a port to see details")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func monogram(_ name: String) -> some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.blue)
            .frame(width: 44, height: 44)
            .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
    }

    private func key(_ s: String) -> some View {
        Text(s).font(.system(size: 12)).foregroundStyle(.secondary)
            .frame(width: 86, alignment: .leading)
    }

    private func kvRow(_ k: String, _ v: String,
                       valueColor: Color = .primary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            key(k)
            Text(v).font(.system(size: 12, weight: .semibold)).foregroundStyle(valueColor)
                .lineLimit(1).truncationMode(.middle)
        }
    }

    private func depList(_ deps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(deps, id: \.self) { d in
                HStack(spacing: 6) {
                    Circle().fill(Color.gray.opacity(0.35))
                        .frame(width: 5, height: 5)
                    Text(d).font(.system(size: 12))
                }
            }
        }
    }

    private func chip(_ label: String, warn: Bool = false) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold)).tracking(0.4)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4)
                .fill(warn ? Color.orange.opacity(0.15) : Color.gray.opacity(0.12)))
            .foregroundStyle(warn ? Color.orange : .secondary)
    }
}

private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
        content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.bottom, 2)
}
