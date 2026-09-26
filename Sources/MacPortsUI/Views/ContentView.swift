import SwiftUI
import AppKit
import MacPortsUICore

/// Root view. BrewUI-style three-column layout:
///   Sidebar (pages) | Center (list) | Detail pane
/// plus a bottom status bar with an expandable command log.
/// Owns the write-confirmation flow (elevated via system dialog or sudo).
struct ContentView: View {
    @EnvironmentObject var service: MacPortsService

    @State private var page: MacPortsPage = .installed
    @State private var pendingWrite: MacPortsService.PendingWrite?
    @State private var password = ""
    @State private var passwordError: String?
    @State private var writeResult: WriteOutcome?
    @State private var logExpanded = false
    @State private var showAbout = false
    @State private var showSettings = false
    @State private var showMissingMacPorts = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SidebarView(page: $page, onOpenInfo: { showAbout = true },
                            onOpenSettings: { showSettings = true })
                    .frame(maxHeight: .infinity)
                Divider()
                CenterPages(page: page, onRequestWrite: { pendingWrite = $0 })
                    .frame(minWidth: 440)
                Divider()
                DetailPane(onRequestWrite: { pendingWrite = $0 })
            }
            .frame(maxHeight: .infinity)

            StatusBar(logExpanded: $logExpanded)
        }
        .frame(minWidth: 980, idealWidth: 1110, minHeight: 560, idealHeight: 640)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    Task {
                        await service.loadInstalled()
                        await service.loadOutdated()
                    }
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .disabled(service.writeRunning)

                Button {
                    pendingWrite = service.pendingSelfupdate()
                } label: { Label("Selfupdate MacPorts", systemImage: "arrow.triangle.2.circlepath") }
                .disabled(service.writeRunning || !service.isMacPortsAvailable)
            }
        }
        .onAppear {
            // Surface a "MacPorts not installed" popup once, at launch, when
            // the port executable is missing. (Port lists stay empty until
            // MacPorts is installed; the guide link below drives the fix.)
            if !service.isMacPortsAvailable { showMissingMacPorts = true }
        }
        .alert("MacPorts Not Found", isPresented: $showMissingMacPorts) {
            Button("Install MacPorts") {
                if let url = URL(string: "https://www.macports.org/install.php") {
                    NSWorkspace.shared.open(url)
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("OK", role: .cancel) {}
        } message: {
            Text("No MacPorts installation was found at \(MacPortsLocator.defaultPortPath). Port lists will stay empty and install/upgrade actions are unavailable until MacPorts is installed.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .mpuiDemoGraph)) { _ in
            page = .dependencies
        }
        .onReceive(NotificationCenter.default.publisher(for: .mpuiDemoSheet)) { _ in
            pendingWrite = service.pendingSelfupdate()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mpuiDemoAbout)) { _ in
            showAbout = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .mpuiDemoDoctor)) { _ in
            page = .doctor
        }
        .onReceive(NotificationCenter.default.publisher(for: .mpuiDemoSettings)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .mpuiDemoMissingMacPorts)) { _ in
            // Preview hook: force the "MacPorts Not Found" alert even when
            // MacPorts *is* installed (MPUI_DEMO=nomacports).
            showMissingMacPorts = true
        }
        .sheet(item: $pendingWrite) { write in
            WriteConfirmationSheet(
                write: write,
                isRunning: service.writeRunning,
                mode: $service.privilegeMode,
                password: $password,
                error: $passwordError,
                onRun: {
                    Task {
                        let pw = service.privilegeMode == .sudoPassword ? password : nil
                        let outcome = await service.executeWrite(write, password: pw)
                        password = ""
                        if outcome.success {
                            pendingWrite = nil   // close the sheet
                            writeResult = outcome
                        } else {
                            passwordError = "Command exited \(outcome.exitCode)\n\(outcome.stderr)"
                        }
                    }
                },
                onFinished: { pendingWrite = nil }
            )
        }
        .sheet(isPresented: $showAbout) {
            AboutSheet(onDismiss: { showAbout = false })
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(settings: service.settings, onDismiss: { showSettings = false })
        }
        .alert("Write complete",
               isPresented: Binding(
                    get: { writeResult != nil && writeResult?.success == true },
                    set: { _ in writeResult = nil })) {
            Text("The command finished successfully.")
            Button("OK") { writeResult = nil }
        }
    }
}

extension MacPortsService.PendingWrite: Identifiable {
    public var id: String { display }
}
