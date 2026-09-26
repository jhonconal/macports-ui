import SwiftUI
import MacPortsUICore

/// Shared rich list row for port lists: colored monogram + name + chips
/// (OUTDATED / inactive / not installed) + optional summary + version line.
struct PortRow: View {
    let name: String
    let version: String                 // installed (or current) version
    var availableVersion: String? = nil // non-nil ⇒ show "→ available"
    var summary: String? = nil
    var showOutdatedChip: Bool = false
    var inactive: Bool = false
    var notInstalled: Bool = false
    var selected: Bool = false
    var onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            monogram
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name).font(.system(size: 13, weight: .semibold))
                    chip("PORT")
                    if showOutdatedChip { chip("OUTDATED", warn: true) }
                    if inactive { chip("INACTIVE", warn: true) }
                    if notInstalled { chip("NOT INSTALLED") }
                }
                if let summary, !summary.isEmpty {
                    Text(summary).font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    statusDot
                    Text(versionLine).font(.system(size: 11))
                        .foregroundStyle(showOutdatedChip ? .orange : .secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(selected ? Color.accentColor.opacity(0.08) : Color.clear)
        .overlay(alignment: .leading) {
            if selected {
                Rectangle().fill(Color.accentColor).frame(width: 3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var statusDot: some View {
        Circle()
            .fill(showOutdatedChip ? Color.orange : .green)
            .frame(width: 7, height: 7)
    }

    private var versionLine: String {
        if let a = availableVersion {
            return "\(version)  →  \(a) available"
        }
        return version
    }

    /// Deterministic pastel background + blue/green initial (stable per port).
    private var monogram: some View {
        let initial = String(name.prefix(1)).uppercased()
        let hues: [Color] = [.blue, .green, .indigo, .teal, .purple, .orange]
        let idx = abs(name.hashValue) % hues.count
        return Text(initial)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(hues[idx])
            .frame(width: 34, height: 34)
            .background(hues[idx].opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
    }

    private func chip(_ label: String, warn: Bool = false) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.4)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(warn ? Color.orange.opacity(0.15) : Color.gray.opacity(0.12))
            )
            .foregroundStyle(warn ? Color.orange : .secondary)
    }
}
