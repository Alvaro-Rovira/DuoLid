import AppKit
import SwiftUI

/// Panel para ajustar el efecto con un ángulo simulado. Flota por encima del overlay para que
/// no se desenfoque mientras se usa. Al cerrarlo, el sensor real vuelve a mandar.
@MainActor
final class TuningPanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let engine: EffectEngine

    init(settings: Settings, engine: EffectEngine) {
        self.engine = engine
        // Tamaño fijo: dejar que el panel se ajuste al Form agrupado provoca un bucle de layout.
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 700),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        panel.contentView = NSHostingView(rootView: TuningView(settings: settings, engine: engine))
        super.init()

        panel.title = "Ajuste del efecto"
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.center()
    }

    func show() {
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        // Si macOS no deja activarse a la app (p. ej. lanzada en segundo plano), se muestra igualmente.
        panel.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        engine.setSimulating(false)
    }
}

private struct TuningView: View {
    @Bindable var settings: Settings
    let engine: EffectEngine

    var body: some View {
        Form {
            Section("Ángulo") {
                LabeledContent("Sensor", value: engine.statusText)
                LabeledContent("Efecto") {
                    Text(engine.progress, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                if let angle = engine.lastScreenOffAngle {
                    LabeledContent("Pantalla apagada a", value: "\(Int(angle))°")
                }
                Toggle("Simular ángulo (ignora el sensor)", isOn: Binding(
                    get: { engine.isSimulating }, set: { engine.setSimulating($0) }
                ))
                ValueSlider(
                    title: "Ángulo simulado",
                    value: Binding(get: { engine.simulatedAngle }, set: { engine.simulate(angle: $0) }),
                    range: 0...130, format: degrees
                )
                Button("Reproducir cierre y apertura") { engine.playSimulatedMotion() }
            }

            Section("Efecto") {
                ValueSlider(title: "Intensidad", value: $settings.intensity, range: 0...1, format: percent)
                ValueSlider(title: "Desenfoque máximo", value: $settings.maxBlurRadius, range: 0...80) {
                    "\(Int($0)) pt"
                }
                ValueSlider(title: "Oscurecimiento máximo", value: $settings.maxDimming, range: 0...1, format: percent)
                ValueSlider(title: "Efecto máximo por debajo de", value: $settings.fullEffectAngle, range: 0...45, format: degrees)
                ValueSlider(title: "Invisible por encima de", value: $settings.invisibleAngle, range: 60...140, format: degrees)
                Button("Valores por defecto") { settings.resetEffectTuning() }
            }

            if !settings.isEnabled {
                Text("El efecto está desactivado desde el menú.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func degrees(_ value: Double) -> String { "\(Int(value.rounded()))°" }
    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded())) %" }
}

private struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}
