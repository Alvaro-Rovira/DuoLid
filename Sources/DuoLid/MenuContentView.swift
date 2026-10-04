import SwiftUI

/// Contenido de la ventanita que se abre desde el icono de la barra de menús.
struct MenuContentView: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        let engine = model.engine
        let loginItem = model.loginItem

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("DuoLid").font(.headline)
                Text(engine.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Button {
                    model.toggleEffect()
                } label: {
                    Label(
                        settings.isEnabled ? "Desactivar efecto" : "Activar efecto",
                        systemImage: settings.isEnabled ? "pause.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(settings.isEnabled ? .gray : .accentColor)
                .controlSize(.large)

                if model.toggleHotKey != nil {
                    note("También con \(GlobalHotKey.toggleEffectDescription) desde cualquier app.")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Intensidad")
                    Spacer()
                    Text(settings.intensity, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.intensity, in: 0...1)
            }
            .disabled(!settings.isEnabled)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Iniciar al arrancar sesión")
                    Spacer()
                    Toggle(
                        "Iniciar al arrancar sesión",
                        isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) })
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                }
                .disabled(!loginItem.isSupported)

                if !loginItem.isSupported {
                    note("Disponible al ejecutar DuoLid.app (scripts/build-app.sh).")
                } else if loginItem.requiresApproval {
                    Button("Aprobar en Ajustes del Sistema…") { loginItem.openSystemSettings() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                if let error = loginItem.lastError {
                    note(error).foregroundStyle(.red)
                }
            }

            Divider()

            HStack {
                Button("Panel de ajuste…") { model.showTuningPanel() }
                Spacer()
                Button("Salir") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { loginItem.refresh() }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension EffectEngine {
    var statusText: String {
        guard isEnabled else { return "Efecto desactivado" }
        return switch mode {
        case .sensor:
            sensorAngle.map { "Tapa a \(Int($0))°" } ?? "Leyendo el sensor…"
        case .wakeFallback:
            "Sin sensor de tapa: animación al encender la pantalla"
        }
    }
}
