import Foundation

/// Reparto del efecto sobre la superficie de la pantalla.
///
/// `g` es la altura normalizada perpendicular a la bisagra: 0 en el borde inferior (la bisagra) y
/// 1 en el superior. `p` es el progreso que da `EffectCurve` (0 = tapa abierta, 1 = tapa en
/// `fullEffectAngle` o más cerrada).
///
/// - Desenfoque: `p · peso(g)`, con `peso(g) = (hingeFloor + (1 − hingeFloor) · g)^gradientExponent`.
/// - Negro: `min(1, darkenFactor · p · peso(g))`. Va más deprisa que el desenfoque y llega a negro
///   primero en el borde lejano a la bisagra. Al final del recorrido (`p ≥ blackoutStart`, ≈33°)
///   toda la pantalla se funde además a negro, para que a `fullEffectAngle` quede negra del todo.
///
/// La imagen no se escala: solo se desenfoca y se funde a negro, con el contenido fijo en su sitio.
public struct SpatialEffect: Sendable, Equatable {
    /// Progreso a partir del cual toda la pantalla se funde a negro.
    public static let blackoutStart = 0.85

    public var gradientExponent: Double
    public var darkenFactor: Double
    /// Altura mínima efectiva, para que la zona de la bisagra no quede del todo sin efecto.
    public var hingeFloor: Double
    /// Da la vuelta al degradado: el efecto nace en el borde superior.
    public var invertGradient: Bool

    public init(
        gradientExponent: Double = 1.35,
        darkenFactor: Double = 2.0,
        hingeFloor: Double = 0.05,
        invertGradient: Bool = false
    ) {
        self.gradientExponent = gradientExponent
        self.darkenFactor = darkenFactor
        self.hingeFloor = hingeFloor
        self.invertGradient = invertGradient
    }

    /// Peso del efecto a la altura `g`: `hingeFloor^exponente` en la bisagra, 1 en el borde opuesto.
    public func weight(atHeight g: Double) -> Double {
        let height = clamp01(g)
        let oriented = invertGradient ? 1 - height : height
        let floor = clamp01(hingeFloor)
        return pow(floor + (1 - floor) * oriented, gradientExponent)
    }

    /// Fracción del radio máximo de desenfoque (0…1).
    public func blurFactor(g: Double, p: Double) -> Double {
        clamp01(p) * weight(atHeight: g)
    }

    /// Opacidad del negro (0…1).
    public func dimAlpha(g: Double, p: Double) -> Double {
        let progress = clamp01(p)
        let spatial = min(1, darkenFactor * progress * weight(atHeight: g))
        return max(spatial, Self.blackout(progress))
    }

    /// Fundido final uniforme: 0 hasta `blackoutStart`, 1 en `p = 1` (smoothstep).
    public static func blackout(_ p: Double) -> Double {
        let t = clamp01((p - blackoutStart) / (1 - blackoutStart))
        return t * t * (3 - 2 * t)
    }

    /// Opacidad del negro en `count` (≥ 2) paradas equiespaciadas, de la bisagra (índice 0) al
    /// borde superior.
    public func dimAlphas(stops count: Int, p: Double) -> [Double] {
        (0..<count).map { dimAlpha(g: Double($0) / Double(count - 1), p: p) }
    }

    /// Valor de la máscara de desenfoque en cada fila de una imagen de `rows` filas. La fila 0 es
    /// el borde **superior** de la pantalla (orden de memoria de un `CGImage`).
    public func maskRows(_ rows: Int) -> [Double] {
        (0..<rows).map { weight(atHeight: 1 - (Double($0) + 0.5) / Double(rows)) }
    }

    /// Lo que determina la máscara: si no cambia, no hace falta regenerarla.
    public struct MaskShape: Sendable, Equatable {
        public var gradientExponent: Double
        public var hingeFloor: Double
        public var invertGradient: Bool
    }

    public var maskShape: MaskShape {
        MaskShape(gradientExponent: gradientExponent, hingeFloor: hingeFloor, invertGradient: invertGradient)
    }
}

private func clamp01(_ value: Double) -> Double {
    min(max(value, 0), 1)
}
