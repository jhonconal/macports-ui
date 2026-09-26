import SwiftUI
import AppKit
import MacPortsUICore

/// Doctor page: a `port doctor`-style health check of the MacPorts tree.
///
/// Runs the read-only check suite from `MacPortsService`, renders each result
/// with a status icon, and offers a copy-pasteable text report for support.
/// Suggested fixes for the actionable checks are wired to the same
/// confirm-gated write flow the rest of the app uses.
struct DoctorPage: View {
    @EnvironmentObject var service: MacPortsService
    let onRequestWrite: (MacPortsService.PendingWrite) -> Void

    @State private var copied = false

    private var issues: Int { service.lastDoctorChecks.filter { !$0.isHealthy }.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .onAppear { if service.lastDoctorChecks.isEmpty { Task { await service.runDoctorChecks() } } }
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Doctor").font(.system(size: 20, weight: .bold))
                Text("Health check for your MacPorts tree").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if !service.lastDoctorChecks.isEmpty && !service.isDoctorRunning {
                Button {
                    copyReport()
                } label: {
                    Label(copied ? "Copied" : "Copy report", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(copied)
            }
            Button {
                Task { await service.runDoctorChecks() }
            } label: {
                Label("Run again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(service.isDoctorRunning)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: content

    @ViewBuilder
    private var content: some View {
        if service.isDoctorRunning {
            ProgressView("Running health checks…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if service.lastDoctorChecks.isEmpty {
            emptyState
        } else {
            summaryBanner
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(service.lastDoctorChecks) { checkRow($0) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "cross.case.fill").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Run the health check to see the status of your MacPorts installation.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Run checks") { Task { await service.runDoctorChecks() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summaryBanner: some View {
        let healthy = issues == 0
        return HStack(spacing: 8) {
            Image(systemName: healthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(healthy ? .green : .orange)
            Text(healthy ? "All checks passed." : "\(issues) check\(issues == 1 ? "" : "s") need attention.")
                .font(.system(size: 13, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background((healthy ? Color.green : Color.orange).opacity(0.08))
    }

    private func checkRow(_ c: DoctorCheck) -> some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon(c.status)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(c.title).font(.system(size: 13, weight: .semibold))
                    if !c.isHealthy, let s = c.suggestion, let pending = writeAction(for: c) {
                        Button {
                            onRequestWrite(pending)
                        } label: {
                            Label("Run", systemImage: "play.fill").font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(s)
                    }
                }
                Text(c.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                if let s = c.suggestion, !c.isHealthy {
                    Text(s)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.bottom, 10)
        .background(Color.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func statusIcon(_ s: DoctorCheckStatus) -> some View {
        Image(systemName: iconName(s))
            .font(.system(size: 16))
            .foregroundStyle(color(s))
            .frame(width: 20, alignment: .center)
    }

    private func iconName(_ s: DoctorCheckStatus) -> String {
        switch s {
        case .ok: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        }
    }

    private func color(_ s: DoctorCheckStatus) -> Color {
        switch s {
        case .ok: return .green
        case .warn: return .orange
        case .fail: return .red
        }
    }

    /// Maps the actionable checks to their confirm-gated write builders.
    private func writeAction(for c: DoctorCheck) -> MacPortsService.PendingWrite? {
        switch c.id {
        case "tree-age": return service.pendingSelfupdate()
        case "outdated": return service.pendingUpgradeAll()
        case "registry": return service.pendingInstall("sqlite3")
        default: return nil
        }
    }

    private func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            DoctorChecks.reportText(service.lastDoctorChecks,
                                    macportsVersion: service.macportsVersion),
            forType: .string)
        copied = true
        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); copied = false }
    }
}
