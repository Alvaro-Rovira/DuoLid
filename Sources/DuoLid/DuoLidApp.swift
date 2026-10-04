import SwiftUI

@main
struct DuoLidApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: appDelegate.model)
        } label: {
            Image(systemName: appDelegate.model.settings.isEnabled ? "laptopcomputer" : "laptopcomputer.slash")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Equivale a LSUIElement cuando se ejecuta sin empaquetar (`swift run`).
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start(arguments: CommandLine.arguments)
    }
}
