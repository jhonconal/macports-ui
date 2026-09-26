import SwiftUI
import MacPortsUICore

// MARK: - Center column: header + page content (BrewUI-style)

/// Center column: page title/subtitle + per-page content. The right-hand
/// detail pane is owned by ContentView; pages only manage selection via
/// `service.selectedPortName` and route writes through `onRequestWrite`.
struct CenterPages: View {
    @EnvironmentObject var service: MacPortsService
    let page: MacPortsPage
    let onRequestWrite: (MacPortsService.PendingWrite) -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch page {
            case .installed:    InstalledPage(onRequestWrite: onRequestWrite)
            case .outdated:     OutdatedPage(onRequestWrite: onRequestWrite)
            case .discover:     DiscoverPage(onRequestWrite: onRequestWrite)
            case .dependencies: GraphView()
            case .doctor:       DoctorPage(onRequestWrite: onRequestWrite)
            }
        }
    }
}

// MARK: - Installed

private struct InstalledPage: View {
    @EnvironmentObject var service: MacPortsService
    let onRequestWrite: (MacPortsService.PendingWrite) -> Void

    @State private var query = ""
    @State private var showOnlyOutdated = false

    private var outdatedNames: Set<String> { Set(service.outdatedPorts.map(\.name)) }

    private var filtered: [InstalledPort] {
        var rows = service.installedPorts
        if showOnlyOutdated {
            rows = rows.filter { outdatedNames.contains($0.name) }
        }
        guard !query.isEmpty else { return rows }
        return rows.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.displayVersion.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            pageHeader(title: "Installed",
                       subtitle: "Browse or search your installed ports") {
                TextField("Search installed ports", text: $query)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .frame(width: 220)
                    .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 10) {
                Text("Your ports").font(.system(size: 14, weight: .semibold))
                Text("\(service.installedPorts.count) ports")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)

            // All / Outdated segment
            HStack(spacing: 4) {
                segButton("All", isOn: !showOnlyOutdated) { showOnlyOutdated = false }
                segButton("Outdated", isOn: showOnlyOutdated) { showOnlyOutdated = true }
            }
            .padding(.horizontal, 16).padding(.bottom, 8)

            if service.isLoadingInstalled {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filtered) { p in
                        PortRow(
                            name: p.name,
                            version: p.displayVersion + p.variantString,
                            showOutdatedChip: outdatedNames.contains(p.name),
                            inactive: !p.isActive,
                            selected: service.selectedPortName == p.name
                        ) {
                            select(p.name)
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func select(_ name: String) {
        service.selectedPortName = name
        Task { await service.loadDetail(for: name) }
    }
}

// MARK: - Outdated

private struct OutdatedPage: View {
    @EnvironmentObject var service: MacPortsService
    let onRequestWrite: (MacPortsService.PendingWrite) -> Void

    var body: some View {
        VStack(spacing: 0) {
            pageHeader(title: "Outdated",
                       subtitle: "Installed ports that have a newer upstream version")

            if service.outdatedPorts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40)).foregroundStyle(.green)
                    Text("No installed ports are outdated.")
                        .foregroundStyle(.secondary)
                    Button("Check again") { Task { await service.loadOutdated() } }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(service.outdatedPorts) { p in
                        PortRow(
                            name: p.name,
                            version: p.installedVersion,
                            availableVersion: p.availableVersion,
                            showOutdatedChip: true,
                            selected: service.selectedPortName == p.name
                        ) {
                            service.selectedPortName = p.name
                            Task { await service.loadDetail(for: p.name) }
                        }
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing) {
                            Button("Upgrade", role: .destructive) {
                                onRequestWrite(service.pendingUpgrade(p.name))
                            }
                            .tint(.accentColor)
                        }
                    }
                }
                .listStyle(.plain)

                HStack(spacing: 8) {
                    Button("Upgrade all (\(service.outdatedPorts.count))") {
                        onRequestWrite(service.pendingUpgradeAll())
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(service.writeRunning)
                    Spacer()
                }
                .padding(10)
            }
        }
    }
}

// MARK: - Discover (search)

private struct DiscoverPage: View {
    @EnvironmentObject var service: MacPortsService
    let onRequestWrite: (MacPortsService.PendingWrite) -> Void

    @State private var term = ""
    private var installedNames: Set<String> { Set(service.installedPorts.map(\.name)) }

    var body: some View {
        VStack(spacing: 0) {
            pageHeader(title: "Discover", subtitle: "Search the MacPorts tree") {
                TextField("Search ports…", text: $term)
                    .textFieldStyle(.plain)
                    .onSubmit { run() }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(width: 280)
                    .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .trailing) {
                        Button(action: { run() }) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 10)
                        .disabled(term.isEmpty)
                    }
            }

            if service.isSearching {
                ProgressView("Searching…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if service.searchResults.isEmpty && !term.isEmpty {
                emptyState("No results for “\(term)”.")
            } else if service.searchResults.isEmpty {
                emptyState("Enter a term to search the MacPorts database.")
            } else {
                List {
                    ForEach(service.searchResults) { hit in
                        let installed = installedNames.contains(hit.name)
                        PortRow(
                            name: hit.name,
                            version: hit.version,
                            summary: hit.summary.isEmpty ? nil : hit.summary,
                            notInstalled: !installed,
                            selected: service.selectedPortName == hit.name
                        ) {
                            service.selectedPortName = hit.name
                            if installed {
                                Task { await service.loadDetail(for: hit.name) }
                            }
                        }
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing) {
                            if !installed {
                                Button("Install") {
                                    onRequestWrite(service.pendingInstall(hit.name))
                                }
                                .tint(.accentColor)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func run() {
        let q = term
        Task { await service.search(q) }
    }
}

// MARK: - shared chrome helpers

private func emptyState(_ text: String) -> some View {
    VStack(spacing: 8) {
        Image(systemName: "magnifyingglass").font(.system(size: 32)).foregroundStyle(.tertiary)
        Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

/// Page header: title + subtitle, with an optional trailing view (search).
private func pageHeader<Trailing: View>(
    title: String, subtitle: String,
    @ViewBuilder trailing: () -> Trailing = { EmptyView() }
) -> some View {
    HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 20, weight: .bold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        Spacer()
        trailing()
    }
    .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
}

/// Segmented-control button cell.
private func segButton(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 4)
            .background(
                isOn
                ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor)
                : RoundedRectangle(cornerRadius: 6).fill(Color.clear)
            )
            .foregroundStyle(isOn ? Color.white : .secondary)
    }
    .buttonStyle(.plain)
}
