import Foundation
import Observation
import ServiceManagement

/// "Iniciar al arrancar sesión" mediante `SMAppService` (macOS 13+).
/// Solo funciona cuando la app se ejecuta como paquete `.app`, no con `swift run`.
@MainActor
@Observable
final class LoginItem {
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var lastError: String?

    var isSupported: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var requiresApproval: Bool { status == .requiresApproval }

    init() {
        refresh()
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
