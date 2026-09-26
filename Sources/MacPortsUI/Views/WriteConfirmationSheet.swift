import SwiftUI
import MacPortsUICore

/// Confirmation + elevation sheet for a write operation.
///
/// Default strategy is the system authorization dialog (Authorization
/// Services) via `osascript ... with administrator privileges` — the system
/// shows its native password dialog and the command runs as root; the app
/// never captures the password. A fallback "type the password here" mode
/// (sudo -S) is offered for hosts where the dialog is undesirable.
struct WriteConfirmationSheet: View {
    let write: MacPortsService.PendingWrite
    let isRunning: Bool
    @Binding var mode: PrivilegeMode
    @Binding var password: String
    @Binding var error: String?
    let onRun: () -> Void
    let onFinished: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(write.title).font(.title3).bold()
                Text("This will run the privileged command below. MacPorts writes to /opt/local and requires administrator rights.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Text("sudo(root) " + baseCommand)
                .font(.system(.callout, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Elevation strategy picker
            HStack(spacing: 8) {
                Text("Elevation").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $mode) {
                    Text("System dialog").tag(PrivilegeMode.systemDialog)
                    Text("Password (sudo)").tag(PrivilegeMode.sudoPassword)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
            }

            if mode == .sudoPassword {
                SecureField("Administrator password", text: $password)
                    .textFieldStyle(.roundedBorder)
                Text("Your password is sent to `sudo` locally; it is never stored.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Label("A system password dialog will appear when you press Run.",
                      systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let error, !error.isEmpty {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(5)
            }
            if isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Running… (waiting for elevation to complete)").foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onFinished).keyboardShortcut(.cancelAction)
                Button(isRunning ? "Running…" : "Run") {
                    guard !isRunning else { return }
                    if mode == .sudoPassword && password.isEmpty {
                        error = "Enter the administrator password to continue."
                        return
                    }
                    error = nil
                    onRun()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isRunning || (mode == .sudoPassword && password.isEmpty))
            }
        }
        .padding(20)
        .frame(minWidth: 460)
    }

    private var baseCommand: String {
        // The command that will run as root, regardless of the current mode.
        MacPortsLocator.defaultPortPath + " " + write.args.joined(separator: " ")
    }
}
