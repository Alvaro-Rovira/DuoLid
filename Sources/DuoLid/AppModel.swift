import AppKit

/// Punto de unión de la app: ajustes, motor del efecto, inicio de sesión y panel de ajuste.
@MainActor
final class AppModel {
    let settings = Settings()
    let loginItem = LoginItem()
    let engine: EffectEngine
    private var tuningPanel: TuningPanelController?
    private(set) var toggleHotKey: GlobalHotKey?

    /// Argumentos de ayuda para ajustar y probar el efecto:
    /// - `--tuning` abre el panel de ajuste.
    /// - `--simulate-angle <grados>` arranca simulando ese ángulo (y abre el panel; al cerrarlo
    ///   vuelve a mandar el sensor real).
    /// - `--no-sensor` ignora el sensor para probar el respaldo al encender la pantalla.
    init(arguments: [String] = CommandLine.arguments) {
        engine = EffectEngine(settings: settings, useSensor: !arguments.contains("--no-sensor"))
    }

    func start(arguments: [String]) {
        engine.start()
        let shortcut = GlobalHotKey.toggleEffect
        toggleHotKey = GlobalHotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
            self?.toggleEffect()
        }
        if let index = arguments.firstIndex(of: "--simulate-angle"),
           arguments.indices.contains(index + 1),
           let angle = Double(arguments[index + 1]) {
            engine.simulate(angle: angle)
            showTuningPanel()
        }
        if arguments.contains("--tuning") {
            showTuningPanel()
        }
    }

    func toggleEffect() {
        settings.isEnabled.toggle()
    }

    func showTuningPanel() {
        let panel = tuningPanel ?? TuningPanelController(settings: settings, engine: engine)
        tuningPanel = panel
        panel.show()
    }
}
