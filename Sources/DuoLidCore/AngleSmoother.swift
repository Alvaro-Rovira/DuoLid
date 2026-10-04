import Foundation

/// Convierte las lecturas del sensor (≈10 Hz, en pasos de 1°) en un ángulo continuo que se puede
/// animar a la frecuencia de la pantalla.
///
/// 1. **Predicción.** Entre dos lecturas, el objetivo avanza a la última velocidad medida durante
///    como mucho `predictionHorizon` segundos (lo que tarda en llegar la siguiente lectura). Así un
///    movimiento rápido no se ve a escalones de 10–14°. Si la lectura siguiente no llega, la tapa
///    se ha parado y la predicción se retira poco a poco hasta la última lectura.
/// 2. **Muelle críticamente amortiguado.** Sigue al objetivo sin rebotes y absorbe las correcciones
///    cuando la predicción falla.
public struct AngleSmoother: Sendable {
    /// Tiempo de respuesta del muelle en segundos (equivale al `response` de los springs de SwiftUI).
    public var response: Double
    /// Cuánto se extrapola, como máximo, a partir de la última lectura.
    public var predictionHorizon: Double

    public private(set) var value: Double
    /// Velocidad actual del valor animado, en grados por segundo.
    public private(set) var velocity: Double = 0

    private var lastSample: (angle: Double, time: Double)?
    private var sampleVelocity: Double = 0

    public init(angle: Double, response: Double = 0.15, predictionHorizon: Double = 0.1) {
        self.value = angle
        self.response = response
        self.predictionHorizon = predictionHorizon
    }

    /// Registra una lectura nueva del sensor (`time` en segundos, reloj monótono).
    public mutating func add(angle: Double, at time: Double) {
        if let last = lastSample {
            let dt = time - last.time
            // Tras una pausa larga (o un reposo del Mac) la velocidad anterior ya no significa nada.
            sampleVelocity = dt > 0.01 && dt < 0.5 ? (angle - last.angle) / dt : 0
        }
        lastSample = (angle, time)
    }

    /// Salta a `angle` sin animación.
    public mutating func jump(to angle: Double, at time: Double) {
        value = angle
        velocity = 0
        sampleVelocity = 0
        lastSample = (angle, time)
    }

    /// Ángulo al que se dirige el muelle en el instante `time`.
    public func target(at time: Double) -> Double {
        guard let last = lastSample else { return value }
        let age = max(time - last.time, 0)
        let lead = age <= predictionHorizon ? age : max(2 * predictionHorizon - age, 0)
        return last.angle + sampleVelocity * lead
    }

    /// Avanza la animación `dt` segundos hasta el instante `time`.
    public mutating func advance(to time: Double, by dt: Double) {
        let target = target(at: time)
        // Solución exacta del muelle críticamente amortiguado: estable con cualquier dt.
        let omega = 2 * Double.pi / response
        let offset = value - target
        let decay = exp(-omega * dt)
        let k = (velocity + omega * offset) * dt
        value = target + (offset + k) * decay
        velocity = (velocity - omega * k) * decay
    }

    /// `true` cuando la tapa está quieta y la animación ha llegado a su destino.
    public func isSettled(at time: Double) -> Bool {
        guard let last = lastSample else { return true }
        return time - last.time > 2 * predictionHorizon
            && abs(value - last.angle) < 0.05
            && abs(velocity) < 0.5
    }
}
