import SwiftUI
import MacPortsUICore

/// Bottom status bar: Ready / Running / Failed + expandable command log.
/// Collapsed it is a thin strip; the chevron reveals the full log panel.
struct StatusBar: View {
    @EnvironmentObject var service: MacPortsService
    @Binding var logExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            if logExpanded {
                LogView()
                    .frame(height: 160)
                    .padding(.horizontal, 10)
            }
            HStack(spacing: 8) {
                stateDot
                statusText
                Spacer()
                if let last = service.lastWriteOutcome, !service.writeRunning {
                    outcomeText(last)
                }
                Button {
                    logExpanded.toggle()
                } label: {
                    Image(systemName: logExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(logExpanded ? "Hide command log" : "Show command log")
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            // Adaptive status strip: near-white in light, dark in dark mode
            // (was hardcoded `Color(white: 0.975)`).
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .top) { Divider() }
        }
    }

    private var stateDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 7, height: 7)
    }

    private var dotColor: Color {
        if service.writeRunning { return .orange }
        if let o = service.lastWriteOutcome, !o.success { return .red }
        return .green
    }

    private var statusText: some View {
        let t: String
        if service.writeRunning {
            t = "Running…"
        } else if let o = service.lastWriteOutcome, !o.success {
            t = "Last write failed (exit \(o.exitCode))"
        } else {
            t = "Ready"
        }
        return Text(t).font(.system(size: 11)).foregroundStyle(.secondary)
    }

    private func outcomeText(_ o: WriteOutcome) -> some View {
        Text("\(o.success ? "✓" : "✗") \(o.command)")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(o.success ? .green : .red)
            .lineLimit(1).truncationMode(.middle)
            .frame(maxWidth: 260, alignment: .trailing)
    }
}
