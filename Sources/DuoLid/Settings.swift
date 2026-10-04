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
        static let maxDimming = 1.0
        static let fullEffectAngle = 12.0
        static let invisibleAngle = 100.0
        static let gradientExponent = 1.35
        static let darkenFactor = 2.0
        static let hingeFloor = 0.05
        static let invertGradient = false
    }

    var isEnabled: Bool { didSet { save(isEnabled, "isEnabled") } }
    /// Multiplicador general del efecto (0…1), el que se ajusta desde el menú.
    var intensity: Double { didSet { save(intensity, "intensity") } }
    /// Radio de desenfoque con la tapa cerrada, en puntos.
    var maxBlurRadius: Double { didSet { save(maxBlurRadius, "maxBlurRadius") } }
    /// Multiplicador del negro (1 = la fórmula tal cual, negro opaco con la tapa cerrada).
    var maxDimming: Double { didSet { save(maxDimming, "maxDimming") } }
    var fullEffectAngle: Double { didSet { save(fullEffectAngle, "fullEffectAngle") } }
    var invisibleAngle: Double { didSet { save(invisibleAngle, "invisibleAngle") } }
    /// Exponente del degradado: el efecto crece como altura^exponente desde la bisagra.
    var gradientExponent: Double { didSet { save(gradientExponent, "gradientExponent") } }
    /// Ritmo del oscurecimiento respecto al desenfoque (2 = el doble de rápido).
    var darkenFactor: Double { didSet { save(darkenFactor, "darkenFactor") } }
    /// Altura mínima efectiva en la bisagra, para que esa zona no quede sin efecto.
    var hingeFloor: Double { didSet { save(hingeFloor, "hingeFloor") } }
    /// Da la vuelta al degradado (el efecto nace en el borde superior).
    var invertGradient: Bool { didSet { save(invertGradient, "invertGradient") } }

    /// Se llama tras cualquier cambio, para redibujar el efecto.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let store: UserDefaults

    var curve: EffectCurve {
        EffectCurve(fullEffectAngle: fullEffectAngle, invisibleAngle: invisibleAngle)
    }

    var spatialEffect: SpatialEffect {
        SpatialEffect(
            gradientExponent: gradientExponent,
            darkenFactor: darkenFactor,
            hingeFloor: hingeFloor,
            invertGradient: invertGradient
        )
    }

    init(store: UserDefaults = .standard) {
        self.store = store
        isEnabled = store.object(forKey: "isEnabled") as? Bool ?? true
        intensity = store.object(forKey: "intensity") as? Double ?? Defaults.intensity
        maxBlurRadius = store.object(forKey: "maxBlurRadius") as? Double ?? Defaults.maxBlurRadius
        maxDimming = store.object(forKey: "maxDimming") as? Double ?? Defaults.maxDimming
        fullEffectAngle = store.object(forKey: "fullEffectAngle") as? Double ?? Defaults.fullEffectAngle
        invisibleAngle = store.object(forKey: "invisibleAngle") as? Double ?? Defaults.invisibleAngle
        gradientExponent = store.object(forKey: "gradientExponent") as? Double ?? Defaults.gradientExponent
        darkenFactor = store.object(forKey: "darkenFactor") as? Double ?? Defaults.darkenFactor
        hingeFloor = store.object(forKey: "hingeFloor") as? Double ?? Defaults.hingeFloor
        invertGradient = store.object(forKey: "invertGradient") as? Bool ?? Defaults.invertGradient
    }

    func resetEffectTuning() {
        intensity = Defaults.intensity
        maxBlurRadius = Defaults.maxBlurRadius
        maxDimming = Defaults.maxDimming
        fullEffectAngle = Defaults.fullEffectAngle
        invisibleAngle = Defaults.invisibleAngle
        gradientExponent = Defaults.gradientExponent
        darkenFactor = Defaults.darkenFactor
        hingeFloor = Defaults.hingeFloor
        invertGradient = Defaults.invertGradient
    }

    private func save(_ value: Any, _ key: String) {
        store.set(value, forKey: key)
        onChange?()
    }
}
