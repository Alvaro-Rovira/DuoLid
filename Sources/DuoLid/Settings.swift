import DuoLidCore
import Foundation
import Observation

/// Ajustes del usuario, guardados en `UserDefaults`.
@MainActor
@Observable
final class Settings {
    enum Defaults {
        static let intensity = 1.0
        static let maxBlurRadius = 40.0
        static let maxDimming = 0.85
        static let fullEffectAngle = 12.0
        static let invisibleAngle = 100.0
    }

    var isEnabled: Bool { didSet { save(isEnabled, "isEnabled") } }
    /// Multiplicador general del efecto (0…1), el que se ajusta desde el menú.
    var intensity: Double { didSet { save(intensity, "intensity") } }
    /// Radio de desenfoque con la tapa cerrada, en puntos.
    var maxBlurRadius: Double { didSet { save(maxBlurRadius, "maxBlurRadius") } }
    /// Opacidad del degradado oscuro con la tapa cerrada (0…1).
    var maxDimming: Double { didSet { save(maxDimming, "maxDimming") } }
    var fullEffectAngle: Double { didSet { save(fullEffectAngle, "fullEffectAngle") } }
    var invisibleAngle: Double { didSet { save(invisibleAngle, "invisibleAngle") } }

    /// Se llama tras cualquier cambio, para redibujar el efecto.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let store: UserDefaults

    var curve: EffectCurve {
        EffectCurve(fullEffectAngle: fullEffectAngle, invisibleAngle: invisibleAngle)
    }

    init(store: UserDefaults = .standard) {
        self.store = store
        isEnabled = store.object(forKey: "isEnabled") as? Bool ?? true
        intensity = store.object(forKey: "intensity") as? Double ?? Defaults.intensity
        maxBlurRadius = store.object(forKey: "maxBlurRadius") as? Double ?? Defaults.maxBlurRadius
        maxDimming = store.object(forKey: "maxDimming") as? Double ?? Defaults.maxDimming
        fullEffectAngle = store.object(forKey: "fullEffectAngle") as? Double ?? Defaults.fullEffectAngle
        invisibleAngle = store.object(forKey: "invisibleAngle") as? Double ?? Defaults.invisibleAngle
    }

    func resetEffectTuning() {
        intensity = Defaults.intensity
        maxBlurRadius = Defaults.maxBlurRadius
        maxDimming = Defaults.maxDimming
        fullEffectAngle = Defaults.fullEffectAngle
        invisibleAngle = Defaults.invisibleAngle
    }

    private func save(_ value: Any, _ key: String) {
        store.set(value, forKey: key)
        onChange?()
    }
}
