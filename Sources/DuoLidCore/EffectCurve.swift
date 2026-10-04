/// Convierte el ángulo de la tapa en la intensidad del efecto: 0 = invisible, 1 = máximo.
///
/// El máximo se alcanza en `fullEffectAngle` (≈12°) y no en 0°, porque la pantalla se apaga
/// justo antes de cerrar del todo. Entre ambos ángulos se usa un *smoothstep*, que entra y sale
/// suavemente en los extremos.
public struct EffectCurve: Sendable, Equatable {
    /// Por debajo de este ángulo (grados) el efecto está al máximo.
    public var fullEffectAngle: Double
    /// Por encima de este ángulo (grados) el efecto es invisible.
    public var invisibleAngle: Double

    public init(fullEffectAngle: Double = 12, invisibleAngle: Double = 100) {
        self.fullEffectAngle = fullEffectAngle
        self.invisibleAngle = invisibleAngle
    }

    public func progress(atAngle angle: Double) -> Double {
        let span = invisibleAngle - fullEffectAngle
        guard span > 0 else { return angle <= fullEffectAngle ? 1 : 0 }
        let t = min(max((invisibleAngle - angle) / span, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
