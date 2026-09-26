import SwiftUI
import MacPortsUICore

/// Transparency log: shows every `port` command the app has run, with exit
/// codes and output. Read-only; most-recent first.
struct LogView: View {
    @EnvironmentObject var service: MacPortsService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Command log").font(.caption).bold().foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { service.log.removeAll() }
                    .disabled(service.log.isEmpty)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(service.log.prefix(200)) { entry in
                            LogRow(entry: entry).id(entry.id)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: service.log.count) { _ in
                    if let first = service.log.first {
                        withAnimation { proxy.scrollTo(first.id, anchor: .top) }
                    }
                }
            }
        }
        .padding(8)
    }
}

private struct LogRow: View {
    let entry: CommandLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(entry.success ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
                Text(entry.command).font(.system(.caption, design: .monospaced))
                if entry.privileged {
                    Text("sudo").font(.caption2).foregroundStyle(.orange)
                }
                Spacer()
                Text("exit \(entry.exitCode)").font(.caption).foregroundStyle(.secondary)
            }
            let output = entry.success ? entry.stdout : (entry.stderr.isEmpty ? entry.stdout : entry.stderr)
            if !output.isEmpty {
                Text(output.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
    }
}
