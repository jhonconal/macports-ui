import SwiftUI
import MacPortsUICore
import AppKit

// A plain SPM executable has no .app bundle / Info.plist, so the window
// server may not treat it as the active GUI app. This delegate ensures the
// process registers as a regular (foreground) app and self-activates so the
// window is visible and key. (A distributable build would ship an .app.)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct MacPortsUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var service = MacPortsService()

    var body: some Scene {
        WindowGroup("MacPorts") {
            ContentView()
                .environmentObject(service)
                .onAppear {
                    Task { await service.bootstrap() }
                    // TEMPORARY demo hook (removed before release):
                    // MPUI_DEMO=graph     → open the Dependencies tab
                    // MPUI_DEMO=sheet     → open the write-confirmation sheet
                    // MPUI_DEMO=about     → open the About/Info sheet
                    // MPUI_DEMO=doctor   → open the Doctor page
                    // MPUI_DEMO=settings → open the Settings sheet
                    // MPUI_DEMO=nomacports → force the "MacPorts Not Found" alert
                    //   (simulates a host without MacPorts; preview tooling)
                    if let demo = ProcessInfo.processInfo.environment["MPUI_DEMO"] {
                        Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            if demo == "graph" { NotificationCenter.default.post(name: .mpuiDemoGraph, object: nil) }
                            if demo == "sheet" { NotificationCenter.default.post(name: .mpuiDemoSheet, object: nil) }
                            if demo == "about" { NotificationCenter.default.post(name: .mpuiDemoAbout, object: nil) }
                            if demo == "doctor" { NotificationCenter.default.post(name: .mpuiDemoDoctor, object: nil) }
                            if demo == "settings" { NotificationCenter.default.post(name: .mpuiDemoSettings, object: nil) }
                            if demo == "nomacports" { NotificationCenter.default.post(name: .mpuiDemoMissingMacPorts, object: nil) }
                        }
                    }
                }
        }
        .defaultSize(width: 1110, height: 670)
        .defaultPosition(.center)
    }
}

extension Notification.Name {
    static let mpuiDemoGraph = Notification.Name("mpuiDemoGraph")
    static let mpuiDemoSheet = Notification.Name("mpuiDemoSheet")
    static let mpuiDemoAbout = Notification.Name("mpuiDemoAbout")
    static let mpuiDemoDoctor = Notification.Name("mpuiDemoDoctor")
    static let mpuiDemoSettings = Notification.Name("mpuiDemoSettings")
    static let mpuiDemoMissingMacPorts = Notification.Name("mpuiDemoMissingMacPorts")
}
