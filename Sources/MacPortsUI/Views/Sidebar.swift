import SwiftUI
import MacPortsUICore

/// Left navigation column (BrewUI-style). Pages mirror the old tabs.
enum MacPortsPage: Hashable {
    case installed, outdated, discover, dependencies, doctor
}

struct SidebarView: View {
    @EnvironmentObject var service: MacPortsService
    @Binding var page: MacPortsPage
    var onOpenInfo: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    navItem(.installed, "Installed", icon: "shippingbox.fill",
                             badge: "\(service.installedPorts.count)")
                    navItem(.outdated, "Outdated", icon: "arrow.up.circle.fill",
                             badge: service.outdatedPorts.isEmpty ? nil : "\(service.outdatedPorts.count)")
                    navItem(.discover, "Discover", icon: "magnifyingglass", badge: nil)
                    navItem(.dependencies, "Dependencies",
                             icon: "point.3.connected.trianglepath.dotted", badge: nil)
                    navItem(.doctor, "Doctor", icon: "cross.case.fill", badge: nil,
                             hint: "Health check")
                }
                .padding(10)
            }
            Spacer()

            // Bottom utility row: ⚙ = Settings, ℹ = About/Info.
            HStack(spacing: 6) {
                utilButton("gearshape", disabled: false, hint: "Settings", action: onOpenSettings)
                utilButton("info.circle", disabled: false, hint: "About & Info", action: onOpenInfo)
            }
            .padding(8)
        }
        .frame(width: 212)
        .background(.regularMaterial)
    }

    private func navItem(_ p: MacPortsPage, _ title: String, icon: String,
                         badge: String?, disabled: Bool = false,
                         hint: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20, alignment: .center)
            Text(title)
                .fontWeight(page == p ? .semibold : .regular)
            if let hint {
                Text(hint).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if let badge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(Color.gray.opacity(page == p ? 0.35 : 0.18), in: Capsule())
                    .foregroundStyle(page == p ? .primary : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            page == p
            ? RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.16))
            : RoundedRectangle(cornerRadius: 8).fill(Color.clear)
        )
        .contentShape(Rectangle())
        .help(hint ?? title)
        .onTapGesture { if !disabled { page = p } }
        .opacity(disabled ? 0.4 : 1)
    }

    private func utilButton(_ icon: String, disabled: Bool,
                            hint: String, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.bordered)
        .disabled(disabled)
        .help(hint)
    }
}
