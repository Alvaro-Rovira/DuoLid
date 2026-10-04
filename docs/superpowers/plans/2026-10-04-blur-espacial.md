# Blur espacial anclado a la bisagra — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el efecto de DuoLid sea un desenfoque progresivo en el espacio, que nace en la bisagra y crece hacia el borde superior, más un fundido a negro que acaba en negro opaco a `fullEffectAngle`. Sin escalar el contenido.

**Architecture:** Una función pura nueva en `DuoLidCore` (`SpatialEffect`) calcula, para cada altura `g` y progreso `p`, el factor de desenfoque y el alfa de negro. La ventana del overlay dibuja eso con un `CABackdropLayer` propio con el filtro privado `variableBlur` (radio = `inputRadius × máscara`). La máscara se genera una vez por tamaño de pantalla y forma del degradado. Encima va un `CAGradientLayer` negro de 16 paradas. `AngleSmoother`, `LidAngleSensor` y `EffectCurve` no se tocan.

**Tech Stack:** Swift 6 (SwiftPM, macOS 14+), AppKit + SwiftUI, QuartzCore (APIs privadas `CABackdropLayer` y `CAFilter` resueltas en tiempo de ejecución), Swift Testing.

**Spec:** no hay documento aparte. Es el diseño acordado en el chat el 2026-10-04, reproducido en la sección siguiente.

## Diseño acordado

- `g` = altura normalizada perpendicular a la bisagra: 0 en el borde inferior (bisagra), 1 en el superior. `p` = progreso de `EffectCurve` (0…1).
- `peso(g) = (hingeFloor + (1 − hingeFloor) · g')^gradientExponent`, con `g' = invertGradient ? 1 − g : g`.
- Desenfoque por píxel = `maxBlur · intensidad · p · peso(g)`.
- Negro por píxel = `intensidad · maxDimming · max( min(1, darkenFactor · p · peso(g)), fundido(p) )`, con `fundido(p) = smoothstep(0.85, 1, p)` (opción 1 elegida por el usuario: todo negro a 12°; el fundido empieza hacia los 33°).
- Se elimina el antiguo `pow(p, 1.6)` y la opacidad global del degradado.
- Ajustes nuevos (persistentes, en el panel y en "Valores por defecto"): `gradientExponent` 0.8–2.5 (1.35), `darkenFactor` 1–3 (2.0), `hingeFloor` 0–0.3 (0.05), `invertGradient` (false). `maxDimming` pasa a 1.0 por defecto. Rango de `maxBlurRadius` hasta 72 pt (por defecto 40).
- Respaldos: si `variableBlur`/`CABackdropLayer` no existen → `CGSSetWindowBackgroundBlurRadius` uniforme → `NSVisualEffectView` con alfa. El log dice cuál está activo.
- Rendimiento: la máscara se regenera solo si cambian el tamaño de pantalla, `gradientExponent`, `hingeFloor` o `invertGradient`. Por fotograma solo cambian `inputRadius` y los 16 alfas del degradado. Se mantienen el `CADisplayLink` que se pausa en reposo y la ventana oculta sin efecto.

### Resultado de la prueba previa (paso 0, ya hecho)

Prueba desechable en macOS 27, MacBook Air M4, confirmada a ojo por el usuario en las tres fases:

- `variableBlur` en un `CABackdropLayer` desenfoca las ventanas de otras apps y respeta la máscara.
- **Orientación:** la fila 0 en memoria del `CGImage` de la máscara es el borde **superior** de la pantalla.
- Una máscara de blanco premultiplicado `(v, v, v, v)` funciona.
- El radio se cambia en cada fotograma con `setValue(_, forKeyPath: "filters.variableBlur.inputRadius")`.
- Funcionan las dos variantes: el backdrop interno de `NSVisualEffectView` (no pisa el filtro) y un `CABackdropLayer` propio con `windowServerAware = true`. **Este plan usa el `CABackdropLayer` propio** (cambio respecto al diseño, que decía `NSVisualEffectView`). Así la capa es nuestra: no hay capas de tinte que ocultar y `NSVisualEffectView` no puede reponer sus filtros si cambian la apariencia o la accesibilidad.
- El **plan B** (ScreenCaptureKit + Metal) queda descartado.

## Global Constraints

- macOS 14+, Swift 6 en modo estricto: compilar sin avisos.
- Compilar con `scripts/build-app.sh` y probar con `scripts/test.sh` (usan `--build-system native` con las Command Line Tools).
- No modificar `Sources/DuoLidCore/AngleSmoother.swift`, `Sources/DuoLidCore/LidAngleSensor.swift` ni la lógica de `Sources/DuoLidCore/EffectCurve.swift`.
- Valores por defecto exactos: `gradientExponent = 1.35`, `darkenFactor = 2.0`, `hingeFloor = 0.05`, `invertGradient = false`, `maxDimming = 1.0`, `maxBlurRadius = 40` (rango 0–72), `blackoutStart = 0.85`, 16 paradas en el degradado.
- Sin permisos nuevos (ni Grabación de pantalla ni Accesibilidad).
- Comentarios y textos de interfaz en español, como el resto del proyecto.
- Trabajo en la rama local `blur-espacial`, un commit por tarea, sin `git push` hasta que el usuario lo pida.

## Review Focus

1. **Dirección del negro en pantalla:** el `CAGradientLayer` debe tener la parada 0 en la bisagra (abajo). Si estuviera al revés, el negro nacería abajo. Lo fija el test `stopsGoFromHingeToTop` (orden de datos, Tarea 1) y la comprobación en vivo de la Tarea 4.
2. **Orientación de la máscara:** la fila 0 de la imagen es el borde superior, donde el desenfoque es máximo. Lo fija el test `maskRowsStartAtTheTopEdge` (Tarea 1).
3. **Arrastrar sliders:** cambiar el exponente, el mínimo en la bisagra o la inversión debe regenerar la máscara; cambiar el ritmo del oscurecimiento o el ángulo, no. Lo fija el test `maskShapeIgnoresDarkeningAndProgress` (Tarea 1).
4. **Ajustes extremos** (exponente 0.8, ritmo ×3, bisagra 0.3, invertido): todo debe quedar en 0…1. Lo fija el test `staysWithinZeroAndOne` (Tarea 1).
5. **Desactivar con la pantalla en negro** (botón o ⌃⌥⌘D a 12° simulados): el overlay debe desaparecer al instante, con el desenfoque incluido. Comprobación en vivo en la Tarea 4.

---

### Task 1: `SpatialEffect` en el núcleo, con tests

**Files:**
- Create: `Sources/DuoLidCore/SpatialEffect.swift`
- Create: `Tests/DuoLidCoreTests/SpatialEffectTests.swift`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `public struct SpatialEffect: Sendable, Equatable` con `init(gradientExponent: Double = 1.35, darkenFactor: Double = 2.0, hingeFloor: Double = 0.05, invertGradient: Bool = false)` y propiedades `var` homónimas.
  - `public static let blackoutStart: Double` (0.85) y `public static func blackout(_ p: Double) -> Double`.
  - `public func weight(atHeight g: Double) -> Double`.
  - `public func blurFactor(g: Double, p: Double) -> Double`.
  - `public func dimAlpha(g: Double, p: Double) -> Double`.
  - `public func dimAlphas(stops count: Int, p: Double) -> [Double]` (índice 0 = bisagra; `count ≥ 2`).
  - `public func maskRows(_ rows: Int) -> [Double]` (índice 0 = borde superior).
  - `public struct MaskShape: Sendable, Equatable` y `public var maskShape: MaskShape`.

- [ ] **Step 1: Crear la rama**

```bash
git switch -c blur-espacial
```

- [ ] **Step 2: Escribir los tests que fallan**

`Tests/DuoLidCoreTests/SpatialEffectTests.swift`:

```swift
import Testing
@testable import DuoLidCore

@Suite struct SpatialEffectTests {
    let effect = SpatialEffect()
    let heights = stride(from: 0.0, through: 1.0, by: 0.05).map { $0 }
    let progresses = stride(from: 0.0, through: 1.0, by: 0.05).map { $0 }

    @Test func hingeIsTheMinimum() {
        for p in [0.3, 0.6, 0.8] {
            #expect(effect.blurFactor(g: 0, p: p) < effect.blurFactor(g: 0.5, p: p))
            #expect(effect.dimAlpha(g: 0, p: p) <= effect.dimAlpha(g: 0.5, p: p))
        }
    }

    @Test func growsTowardsTheTopEdge() {
        for p in progresses {
            let blur = heights.map { effect.blurFactor(g: $0, p: p) }
            let dim = heights.map { effect.dimAlpha(g: $0, p: p) }
            #expect(zip(blur, blur.dropFirst()).allSatisfy { $0 <= $1 })
            #expect(zip(dim, dim.dropFirst()).allSatisfy { $0 <= $1 })
        }
    }

    @Test func growsAsTheLidCloses() {
        for g in heights {
            let blur = progresses.map { effect.blurFactor(g: g, p: $0) }
            let dim = progresses.map { effect.dimAlpha(g: g, p: $0) }
            #expect(zip(blur, blur.dropFirst()).allSatisfy { $0 <= $1 })
            #expect(zip(dim, dim.dropFirst()).allSatisfy { $0 <= $1 })
        }
    }

    @Test func staysWithinZeroAndOne() {
        let extreme = SpatialEffect(gradientExponent: 0.8, darkenFactor: 3, hingeFloor: 0.3, invertGradient: true)
        for candidate in [effect, extreme] {
            for g in [-1.0, 0, 0.5, 1, 2] {
                for p in [-1.0, 0, 0.5, 1, 2] {
                    #expect((0...1).contains(candidate.blurFactor(g: g, p: p)))
                    #expect((0...1).contains(candidate.dimAlpha(g: g, p: p)))
                }
            }
        }
    }

    @Test func farEdgeTurnsBlackBeforeTheEnd() {
        #expect(effect.dimAlpha(g: 1, p: 0.5) == 1)
        #expect(effect.blurFactor(g: 1, p: 0.5) < 1)
    }

    @Test func wholeScreenIsBlackAtFullEffect() {
        for g in heights {
            #expect(effect.dimAlpha(g: g, p: 1) == 1)
        }
    }

    @Test func formulaIsUntouchedBeforeTheBlackout() {
        let p = 0.6
        for g in heights {
            #expect(effect.dimAlpha(g: g, p: p) == min(1, 2.0 * p * effect.weight(atHeight: g)))
        }
    }

    @Test func invisibleWhenOpen() {
        for g in heights {
            #expect(effect.blurFactor(g: g, p: 0) == 0)
            #expect(effect.dimAlpha(g: g, p: 0) == 0)
        }
    }

    @Test func hingeFloorKeepsSomeEffectAtTheHinge() {
        #expect(effect.blurFactor(g: 0, p: 1) > 0)
        #expect(SpatialEffect(hingeFloor: 0).blurFactor(g: 0, p: 1) == 0)
    }

    @Test func invertSwapsTheDirection() {
        let inverted = SpatialEffect(invertGradient: true)
        #expect(inverted.blurFactor(g: 0.2, p: 0.7) == effect.blurFactor(g: 0.8, p: 0.7))
    }

    @Test func stopsGoFromHingeToTop() {
        let alphas = effect.dimAlphas(stops: 16, p: 0.5)
        #expect(alphas.count == 16)
        #expect(alphas.first! == effect.dimAlpha(g: 0, p: 0.5))
        #expect(alphas.last! == effect.dimAlpha(g: 1, p: 0.5))
    }

    @Test func maskRowsStartAtTheTopEdge() {
        // La fila 0 de un CGImage es el borde superior (comprobado en la prueba de variableBlur).
        let rows = effect.maskRows(100)
        #expect(rows.count == 100)
        #expect(rows.first! > rows.last!)
        let inverted = SpatialEffect(invertGradient: true).maskRows(100)
        #expect(inverted.first! < inverted.last!)
    }

    @Test func maskShapeIgnoresDarkeningAndProgress() {
        #expect(SpatialEffect(darkenFactor: 3).maskShape == effect.maskShape)
        #expect(SpatialEffect(gradientExponent: 2).maskShape != effect.maskShape)
        #expect(SpatialEffect(hingeFloor: 0.2).maskShape != effect.maskShape)
        #expect(SpatialEffect(invertGradient: true).maskShape != effect.maskShape)
    }
}
```

- [ ] **Step 3: Ejecutar los tests y comprobar que fallan**

Run: `scripts/test.sh`
Expected: error de compilación `cannot find 'SpatialEffect' in scope`.

- [ ] **Step 4: Implementar `SpatialEffect`**

`Sources/DuoLidCore/SpatialEffect.swift`:

```swift
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
```

- [ ] **Step 5: Ejecutar los tests y comprobar que pasan**

Run: `scripts/test.sh`
Expected: `✔ Test run with 20 tests in 3 suites passed` (13 nuevos + 7 existentes).

- [ ] **Step 6: Commit**

```bash
git add Sources/DuoLidCore/SpatialEffect.swift Tests/DuoLidCoreTests/SpatialEffectTests.swift docs/superpowers/plans/2026-10-04-blur-espacial.md
git commit -m "Núcleo: SpatialEffect (blur y negro por altura respecto a la bisagra)"
```

---

### Task 2: Ajustes nuevos y controles en el panel

**Files:**
- Modify: `Sources/DuoLid/Settings.swift`
- Modify: `Sources/DuoLid/TuningPanel.swift`

**Interfaces:**
- Consumes: `SpatialEffect.init(gradientExponent:darkenFactor:hingeFloor:invertGradient:)` (Tarea 1).
- Produces:
  - `Settings.gradientExponent: Double`, `Settings.darkenFactor: Double`, `Settings.hingeFloor: Double`, `Settings.invertGradient: Bool`.
  - `Settings.spatialEffect: SpatialEffect`.
  - `Settings.Defaults.maxDimming == 1.0`.

- [ ] **Step 1: Añadir los valores por defecto**

En `Sources/DuoLid/Settings.swift`, sustituir el `enum Defaults` por:

```swift
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
```

- [ ] **Step 2: Añadir las propiedades persistentes**

En `Settings.swift`, sustituir el comentario y la declaración de `maxDimming`:

```swift
    /// Opacidad del degradado oscuro con la tapa cerrada (0…1).
    var maxDimming: Double { didSet { save(maxDimming, "maxDimming") } }
```

por:

```swift
    /// Multiplicador del negro (1 = la fórmula tal cual, negro opaco con la tapa cerrada).
    var maxDimming: Double { didSet { save(maxDimming, "maxDimming") } }
```

y, justo después de `invisibleAngle`, añadir:

```swift
    /// Exponente del degradado: el efecto crece como altura^exponente desde la bisagra.
    var gradientExponent: Double { didSet { save(gradientExponent, "gradientExponent") } }
    /// Ritmo del oscurecimiento respecto al desenfoque (2 = el doble de rápido).
    var darkenFactor: Double { didSet { save(darkenFactor, "darkenFactor") } }
    /// Altura mínima efectiva en la bisagra, para que esa zona no quede sin efecto.
    var hingeFloor: Double { didSet { save(hingeFloor, "hingeFloor") } }
    /// Da la vuelta al degradado (el efecto nace en el borde superior).
    var invertGradient: Bool { didSet { save(invertGradient, "invertGradient") } }
```

- [ ] **Step 3: Exponer el `SpatialEffect`**

Debajo de `var curve: EffectCurve { … }`, añadir:

```swift
    var spatialEffect: SpatialEffect {
        SpatialEffect(
            gradientExponent: gradientExponent,
            darkenFactor: darkenFactor,
            hingeFloor: hingeFloor,
            invertGradient: invertGradient
        )
    }
```

- [ ] **Step 4: Leerlas en `init` y restablecerlas**

Al final de `init(store:)`, después de leer `invisibleAngle`, añadir:

```swift
        gradientExponent = store.object(forKey: "gradientExponent") as? Double ?? Defaults.gradientExponent
        darkenFactor = store.object(forKey: "darkenFactor") as? Double ?? Defaults.darkenFactor
        hingeFloor = store.object(forKey: "hingeFloor") as? Double ?? Defaults.hingeFloor
        invertGradient = store.object(forKey: "invertGradient") as? Bool ?? Defaults.invertGradient
```

Al final de `resetEffectTuning()`, añadir:

```swift
        gradientExponent = Defaults.gradientExponent
        darkenFactor = Defaults.darkenFactor
        hingeFloor = Defaults.hingeFloor
        invertGradient = Defaults.invertGradient
```

- [ ] **Step 5: Controles en el panel de ajuste**

En `Sources/DuoLid/TuningPanel.swift`, cambiar la altura del panel de `700` a `780` en `NSRect(x: 0, y: 0, width: 380, height: 700)`.

En `TuningView`, sustituir:

```swift
                ValueSlider(title: "Desenfoque máximo", value: $settings.maxBlurRadius, range: 0...80) {
                    "\(Int($0)) pt"
                }
                ValueSlider(title: "Oscurecimiento máximo", value: $settings.maxDimming, range: 0...1, format: percent)
```

por:

```swift
                ValueSlider(title: "Desenfoque máximo", value: $settings.maxBlurRadius, range: 0...72) {
                    "\(Int($0)) pt"
                }
                ValueSlider(title: "Oscurecimiento máximo", value: $settings.maxDimming, range: 0...1, format: percent)
                ValueSlider(title: "Exponente del degradado", value: $settings.gradientExponent, range: 0.8...2.5) {
                    String(format: "%.2f", $0)
                }
                ValueSlider(title: "Ritmo del oscurecimiento", value: $settings.darkenFactor, range: 1...3) {
                    String(format: "×%.1f", $0)
                }
                ValueSlider(title: "Efecto mínimo en la bisagra", value: $settings.hingeFloor, range: 0...0.3, format: percent)
                Toggle("Invertir dirección del gradiente", isOn: $settings.invertGradient)
```

- [ ] **Step 6: Compilar y pasar los tests**

Run: `scripts/build-app.sh && scripts/test.sh`
Expected: `✓ build/DuoLid.app`, sin avisos de Swift; `✔ Test run with 20 tests in 3 suites passed`.

- [ ] **Step 7: Commit**

```bash
git add Sources/DuoLid/Settings.swift Sources/DuoLid/TuningPanel.swift
git commit -m "Ajustes del degradado espacial: exponente, ritmo del negro, mínimo en la bisagra e inversión"
```

---

### Task 3: Dibujar el efecto con blur variable y degradado de 16 paradas

**Files:**
- Create: `Sources/DuoLid/VariableBlur.swift`
- Modify: `Sources/DuoLid/OverlayWindow.swift` (clase `OverlayWindow`, líneas 54–129)
- Modify: `Sources/DuoLid/EffectEngine.swift` (struct `OverlayAppearance`)

**Interfaces:**
- Consumes: `Settings.spatialEffect`, `Settings.maxBlurRadius`, `Settings.maxDimming`, `Settings.intensity` (Tarea 2); `SpatialEffect.dimAlphas(stops:p:)`, `SpatialEffect.dimAlpha(g:p:)`, `SpatialEffect.maskRows(_:)`, `SpatialEffect.maskShape` (Tarea 1).
- Produces:
  - `OverlayAppearance` con `progress`, `blurRadius`, `dimmingScale`, `spatial`, `dimAlphas(stops:)` e `isVisible`.
  - `VariableBlurLayer` (`init?()`, `layer`, `setMask(_:)`, `setRadius(_:)`).
  - `BlurMask.make(size:spatial:) -> CGImage?` y `BlurMask.Key`.
  - `OverlayWindow.BlurBackend`.

- [ ] **Step 1: Nueva `OverlayAppearance`**

En `Sources/DuoLid/EffectEngine.swift`, sustituir el `struct OverlayAppearance` completo por:

```swift
/// Cómo se dibuja el overlay para un progreso dado.
struct OverlayAppearance: Equatable {
    var progress: Double
    /// Radio de desenfoque donde el efecto es máximo (borde lejano a la bisagra), en puntos.
    var blurRadius: Double
    /// Multiplicador del negro: intensidad × oscurecimiento máximo.
    var dimmingScale: Double
    var spatial: SpatialEffect

    @MainActor
    init(progress: Double, settings: Settings) {
        let p = min(max(progress, 0), 1)
        self.progress = p
        blurRadius = settings.maxBlurRadius * settings.intensity * p
        dimmingScale = settings.maxDimming * settings.intensity
        spatial = settings.spatialEffect
    }

    /// Opacidad del negro en `count` paradas, de la bisagra al borde superior.
    func dimAlphas(stops count: Int) -> [Double] {
        spatial.dimAlphas(stops: count, p: progress).map { $0 * dimmingScale }
    }

    var isVisible: Bool {
        let darkest = max(spatial.dimAlpha(g: 0, p: progress), spatial.dimAlpha(g: 1, p: progress))
        return blurRadius >= 0.5 || darkest * dimmingScale >= 0.004
    }
}
```

- [ ] **Step 2: Capa de blur variable y máscara**

`Sources/DuoLid/VariableBlur.swift`:

```swift
import AppKit
import DuoLidCore
import QuartzCore

/// Desenfoque variable de lo que hay detrás de la ventana.
///
/// Es un `CABackdropLayer` propio (la capa que `NSVisualEffectView` usa por dentro) marcado como
/// `windowServerAware`, con el filtro privado `variableBlur`: el radio en cada punto es
/// `inputRadius × máscara`. Ambas clases son privadas y se resuelven en tiempo de ejecución; si
/// faltan, `init` devuelve `nil` y la ventana usa un respaldo. Comprobado en macOS 27 (MacBook Air
/// M4): el servidor de ventanas respeta la máscara y deja cambiar el radio en cada fotograma.
@MainActor
final class VariableBlurLayer {
    let layer: CALayer
    private var radius: Double = 0

    init?() {
        guard Self.isAvailable, let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type else {
            return nil
        }
        layer = backdropClass.init()
        layer.setValue(true, forKey: "windowServerAware")
        layer.setValue("DuoLid", forKey: "groupName")
    }

    /// Cambia la máscara (opaca = radio completo, transparente = sin desenfoque).
    func setMask(_ mask: CGImage) {
        layer.filters = Self.makeFilter(radius: radius, mask: mask).map { [$0] }
    }

    func setRadius(_ newRadius: Double) {
        guard newRadius != radius else { return }
        radius = newRadius
        layer.setValue(newRadius, forKeyPath: "filters.variableBlur.inputRadius")
    }

    private static var isAvailable: Bool {
        guard NSClassFromString("CABackdropLayer") != nil,
              let filterClass = NSClassFromString("CAFilter") as? NSObject.Type,
              let types = filterClass.perform(NSSelectorFromString("filterTypes"))?
                .takeUnretainedValue() as? [String]
        else { return false }
        return types.contains("variableBlur")
    }

    private static func makeFilter(radius: Double, mask: CGImage) -> NSObject? {
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type,
              let filter = filterClass.perform(NSSelectorFromString("filterWithType:"), with: "variableBlur")?
                .takeUnretainedValue() as? NSObject
        else { return nil }
        filter.setValue("variableBlur", forKey: "name")
        filter.setValue(radius, forKey: "inputRadius")
        filter.setValue(mask, forKey: "inputMaskImage")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        return filter
    }
}

/// Imagen de la máscara del desenfoque: cada fila vale `SpatialEffect.weight` a su altura.
/// Se pinta en blanco premultiplicado `(v, v, v, v)`, que el filtro interpreta igual tanto si lee el
/// alfa como la luminancia. La fila 0 es el borde superior (comprobado en la prueba de variableBlur).
enum BlurMask {
    struct Key: Equatable {
        var size: CGSize
        var shape: SpatialEffect.MaskShape
    }

    static func make(size: CGSize, spatial: SpatialEffect) -> CGImage? {
        let width = max(Int(size.width.rounded()), 1)
        let height = max(Int(size.height.rounded()), 1)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let pixels = context.data else { return nil }

        for (row, value) in spatial.maskRows(height).enumerated() {
            memset(pixels + row * context.bytesPerRow, Int32((value * 255).rounded()), width * 4)
        }
        return context.makeImage()
    }
}
```

- [ ] **Step 3: Reescribir `OverlayWindow`**

En `Sources/DuoLid/OverlayWindow.swift`, añadir `import DuoLidCore` debajo de `import AppKit`. Después sustituir la clase `OverlayWindow` completa (desde el comentario `/// Ventana sin bordes…` hasta su `}` de cierre, antes de `/// Desenfoque con radio variable…`) por:

```swift
/// Ventana sin bordes, a pantalla completa, por encima de todo y transparente a los clics.
/// Desenfoca lo que tiene detrás, más cuanto más lejos de la bisagra, y encima pinta un
/// degradado negro que nace en el borde superior y acaba cubriendo toda la pantalla.
@MainActor
final class OverlayWindow: NSWindow {
    /// Cómo se desenfoca lo que hay detrás, de mejor a peor.
    enum BlurBackend: String {
        case variable = "variableBlur (CABackdropLayer)"
        case uniform = "CGSSetWindowBackgroundBlurRadius (uniforme)"
        case visualEffect = "NSVisualEffectView (fundido)"
    }

    private static let dimmingStops = 16
    private static let log = Logger(subsystem: "DuoLid", category: "overlay")

    let blurBackend: BlurBackend
    private let variableBlur: VariableBlurLayer?
    private var fallbackBlurView: NSVisualEffectView?
    private let dimmingLayer = CAGradientLayer()
    private var maskKey: BlurMask.Key?
    private var appliedUniformRadius: Int?

    init(screen: NSScreen) {
        variableBlur = VariableBlurLayer()
        blurBackend = variableBlur != nil ? .variable : (PrivateWindowBlur.isAvailable ? .uniform : .visualEffect)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        animationBehavior = .none

        let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        content.wantsLayer = true
        contentView = content

        if let variableBlur {
            variableBlur.layer.frame = content.bounds
            variableBlur.layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            content.layer?.addSublayer(variableBlur.layer)
        } else if blurBackend == .visualEffect {
            // Respaldo público: desenfoque de radio fijo que se funde con la opacidad.
            let blurView = NSVisualEffectView(frame: content.bounds)
            blurView.autoresizingMask = [.width, .height]
            blurView.material = .fullScreenUI
            blurView.blendingMode = .behindWindow
            blurView.state = .active
            blurView.alphaValue = 0
            content.addSubview(blurView)
            fallbackBlurView = blurView
        }

        // En las capas de AppKit el origen está abajo: (0.5, 0) es el borde de la bisagra, y la
        // parada 0 de `dimAlphas` corresponde a la bisagra.
        dimmingLayer.frame = content.bounds
        dimmingLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        dimmingLayer.startPoint = CGPoint(x: 0.5, y: 0)
        dimmingLayer.endPoint = CGPoint(x: 0.5, y: 1)
        dimmingLayer.locations = (0..<Self.dimmingStops).map {
            NSNumber(value: Double($0) / Double(Self.dimmingStops - 1))
        }
        dimmingLayer.colors = Array(repeating: NSColor.clear.cgColor, count: Self.dimmingStops)
        content.layer?.addSublayer(dimmingLayer)

        Self.log.notice("Desenfoque activo: \(self.blurBackend.rawValue, privacy: .public)")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Que macOS no la recoloque para dejar libre la barra de menús.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    func apply(_ appearance: OverlayAppearance) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        switch blurBackend {
        case .variable:
            updateMaskIfNeeded(appearance.spatial)
            variableBlur?.setRadius(appearance.blurRadius)
        case .uniform:
            let radius = Int(appearance.blurRadius.rounded())
            if radius != appliedUniformRadius, PrivateWindowBlur.setRadius(radius, for: self) {
                appliedUniformRadius = radius
            }
        case .visualEffect:
            fallbackBlurView?.alphaValue = min(appearance.blurRadius / Settings.Defaults.maxBlurRadius, 1)
        }

        dimmingLayer.colors = appearance.dimAlphas(stops: Self.dimmingStops).map {
            NSColor.black.withAlphaComponent($0).cgColor
        }
        CATransaction.commit()
    }

    func hide() {
        orderOut(nil)
        // Al volver a mostrarse se reenvía el radio, por si el servidor de ventanas lo descartó.
        appliedUniformRadius = nil
    }

    /// La máscara solo se regenera si cambian el tamaño o la forma del degradado, nunca por fotograma.
    private func updateMaskIfNeeded(_ spatial: SpatialEffect) {
        guard let variableBlur, let size = contentView?.bounds.size else { return }
        let key = BlurMask.Key(size: size, shape: spatial.maskShape)
        guard key != maskKey, let mask = BlurMask.make(size: size, spatial: spatial) else { return }
        variableBlur.setMask(mask)
        maskKey = key
    }
}
```

- [ ] **Step 4: Compilar y pasar los tests**

Run: `scripts/build-app.sh && scripts/test.sh`
Expected: `✓ build/DuoLid.app`, sin avisos de Swift; `✔ Test run with 20 tests in 3 suites passed`.

- [ ] **Step 5: Comprobar qué desenfoque queda activo**

Run (fuera del sandbox; la pantalla se oscurece unos segundos):

```bash
pkill -x DuoLid; open "$PWD/build/DuoLid.app" --args --simulate-angle 40; sleep 3
/usr/bin/log show --last 10s --predicate 'subsystem == "DuoLid"' --style compact | grep -E "Modo|Desenfoque activo"
pkill -x DuoLid
```

Expected: `Desenfoque activo: variableBlur (CABackdropLayer)`.

- [ ] **Step 6: Commit**

```bash
git add Sources/DuoLid/VariableBlur.swift Sources/DuoLid/OverlayWindow.swift Sources/DuoLid/EffectEngine.swift
git commit -m "Overlay: blur variable anclado a la bisagra y degradado negro de 16 paradas"
```

---

### Task 4: Vistas previas, prueba en vivo y README

**Files:**
- Modify: `README.md`
- Temporal (no va al repo): `$SCRATCHPAD/preview/main.swift`

**Interfaces:**
- Consumes: `EffectCurve.progress(atAngle:)`, `SpatialEffect.maskRows(_:)`, `SpatialEffect.dimAlphas(stops:p:)`.
- Produces: `preview.png` (5 vistas: 100°, 70°, 40°, 20°, 12°) para el usuario; README actualizado.

- [ ] **Step 1: Script de vista previa**

`$SCRATCHPAD/preview/main.swift`, donde `$SCRATCHPAD` es la carpeta temporal de la sesión. Aplica las mismas funciones del núcleo a un escritorio de prueba, usando `CIMaskedVariableBlur` como aproximación del filtro del servidor de ventanas:

```swift
import AppKit
import CoreImage

let curve = EffectCurve()
let spatial = SpatialEffect()
let maxBlur = 40.0          // pt, valor por defecto
let width = 735, height = 478  // mitad de 1470×956 pt: radio en píxeles = radio en pt × 0,5
let angles: [Double] = [100, 70, 40, 20, 12]

func makeBase() -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGradient(colors: [.systemIndigo, .systemTeal])!.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)
    for (index, frame) in [NSRect(x: 30, y: 40, width: 320, height: 380), NSRect(x: 380, y: 70, width: 320, height: 330)].enumerated() {
        NSColor.white.setFill()
        NSBezierPath(roundedRect: frame, xRadius: 10, yRadius: 10).fill()
        let text = (1...22).map { "Línea \($0) de la ventana \(index + 1): texto para ver el desenfoque" }.joined(separator: "\n")
        (text as NSString).draw(in: frame.insetBy(dx: 12, dy: 12),
                                withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.black])
    }
    NSColor.white.withAlphaComponent(0.85).setFill()
    NSRect(x: 0, y: height - 14, width: width, height: 14).fill()
    NSGraphicsContext.current = nil
    return ctx.makeImage()!
}

/// Máscara opaca en gris para Core Image (CIMaskedVariableBlur lee la luminancia): fila 0 = arriba.
func makeMask() -> CIImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    let pixels = ctx.data!
    for (row, value) in spatial.maskRows(height).enumerated() {
        memset(pixels + row * ctx.bytesPerRow, Int32((value * 255).rounded()), width)
    }
    return CIImage(cgImage: ctx.makeImage()!)
}

func render(angle: Double, base: CIImage, mask: CIImage, ci: CIContext) -> CGImage {
    let p = curve.progress(atAngle: angle)
    let blur = CIFilter(name: "CIMaskedVariableBlur", parameters: [
        kCIInputImageKey: base.clampedToExtent(), "inputMask": mask, kCIInputRadiusKey: maxBlur * p * 0.5,
    ])!.outputImage!.cropped(to: base.extent)
    let blurred = ci.createCGImage(blur, from: base.extent)!

    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(blurred, in: CGRect(x: 0, y: 0, width: width, height: height))
    // CGContext tiene el origen abajo: y = 0 es la bisagra, como la parada 0 de dimAlphas.
    let alphas = spatial.dimAlphas(stops: 16, p: p)
    let colors = alphas.map { CGColor(gray: 0, alpha: $0) } as CFArray
    let locations = (0..<16).map { CGFloat($0) / 15 }
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: locations)!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
    return ctx.makeImage()!
}

let base = CIImage(cgImage: makeBase())
let mask = makeMask()
let ci = CIContext()
let gap = 12, labelHeight = 26
let sheet = CGContext(data: nil, width: angles.count * (width + gap) - gap, height: height + labelHeight,
                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
sheet.setFillColor(CGColor(gray: 1, alpha: 1))
sheet.fill(CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height))
NSGraphicsContext.current = NSGraphicsContext(cgContext: sheet, flipped: false)
for (index, angle) in angles.enumerated() {
    let x = index * (width + gap)
    sheet.draw(render(angle: angle, base: base, mask: mask, ci: ci), in: CGRect(x: x, y: 0, width: width, height: height))
    let p = curve.progress(atAngle: angle)
    ("\(Int(angle))°  ·  p = \(String(format: "%.2f", p))" as NSString).draw(
        at: NSPoint(x: x + 8, y: height + 5),
        withAttributes: [.font: NSFont.boldSystemFont(ofSize: 15), .foregroundColor: NSColor.black])
}
NSGraphicsContext.current = nil
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, sheet.makeImage()!, nil)
CGImageDestinationFinalize(destination)
print("✓ \(url.path)")
```

- [ ] **Step 2: Generar y revisar la vista previa**

Run:

```bash
P="$SCRATCHPAD/preview"
swiftc -O Sources/DuoLidCore/EffectCurve.swift Sources/DuoLidCore/SpatialEffect.swift "$P/main.swift" -o "$P/preview"
"$P/preview" "$P/preview.png"
```

Expected: `✓ …/preview.png`. Abrir la imagen (Read) y comprobar:
- 100°: sin efecto.
- 70°: algo de blur y de negro arriba, nada abajo.
- 40°: borde superior negro, blur creciente hacia arriba, bisagra casi nítida.
- 20°: casi todo negro, con un resto visible abajo.
- 12°: negro total.

Enviarla al usuario con `SendUserFile`.

- [ ] **Step 3: Prueba en vivo con el usuario**

Run:

```bash
pkill -x DuoLid; open "$PWD/build/DuoLid.app" --args --simulate-angle 100
```

Pedir al usuario que, en el panel que se abre:
1. Mueva el slider "Ángulo simulado" a 100°, 70°, 40°, 20° y 12°.
2. Pulse "Reproducir cierre y apertura".
3. Pulse ⌃⌥⌘D con el ángulo en 12°: la pantalla negra y el blur deben desaparecer al instante (Review Focus 5). Después, ⌃⌥⌘D otra vez para reactivar el efecto.

Qué debe confirmar:
- el blur crece desde la bisagra hacia arriba;
- el borde superior se oscurece primero;
- a 12° la pantalla es negro opaco;
- no hay velo de color.

Si el degradado parece invertido respecto al vídeo del iPhone Duo, que pruebe "Invertir dirección del gradiente".

- [ ] **Step 4: Actualizar el README**

En `README.md`, sustituir las tres viñetas del principio:

```markdown
- Tapa cerrada (≤ 12°): desenfoque y oscurecimiento al máximo. El máximo se alcanza a ~12° y no a 0°
  porque la pantalla se apaga justo antes de cerrar del todo.
- Tapa abierta (≥ 100°): efecto invisible y ventana oculta (no gasta GPU).
- Entre medias, curva suave. Al abrir, la pantalla primero se ilumina y después se enfoca.
```

por:

```markdown
- El desenfoque es progresivo en el espacio: nace en la bisagra y crece hacia el borde superior.
  El contenido no se escala ni se mueve; solo se emborrona y se funde a negro.
- El negro avanza al doble de ritmo que el desenfoque: el borde superior llega a negro primero, y
  en el último tramo (≈33° → 12°) toda la pantalla se funde a negro opaco.
- Tapa abierta (≥ 100°): efecto invisible y ventana oculta (no gasta GPU). Al abrir, el recorrido es
  el inverso.
```

En la sección "Panel de ajuste", sustituir la frase que empieza por `Permite ajustar el efecto sin mover la tapa:` hasta `el panel vuelve a mandar el sensor real.` por:

```markdown
Permite ajustar el efecto sin mover la tapa: un slider de **ángulo simulado**, un botón que reproduce
un cierre y apertura (con lecturas a 10 Hz como el sensor real), y los parámetros del efecto:
desenfoque máximo (hasta 72 pt), oscurecimiento máximo, exponente del degradado (cómo de deprisa
crece el efecto desde la bisagra), ritmo del oscurecimiento respecto al desenfoque, efecto mínimo en
la bisagra, *Invertir dirección del gradiente*, ángulo de efecto máximo (12°) y ángulo a partir del
cual es invisible (100°). Si sueles trabajar con la pantalla por debajo de 100°, baja este último. Al
cerrar el panel vuelve a mandar el sensor real.
```

Sustituir el bloque de cita que empieza por `> El desenfoque de radio variable usa la API privada` (las cuatro líneas) por:

```markdown
> El desenfoque usa APIs privadas de Core Animation: un `CABackdropLayer` propio (la capa que usa
> `NSVisualEffectView` por dentro) con el filtro `variableBlur`, cuyo radio en cada punto es
> `radio × máscara`. Se cargan en tiempo de ejecución. Si faltan en una versión futura de macOS, la
> app pasa a `CGSSetWindowBackgroundBlurRadius` (desenfoque uniforme) y, si tampoco está, a
> `NSVisualEffectView` (desenfoque fijo que se funde). El log (`log show --predicate 'subsystem ==
> "DuoLid"'`) dice cuál está activo. Por usar APIs privadas, la app no es apta para la Mac App Store.
```

En "Cómo funciona", sustituir el párrafo que empieza por `**Efecto.** \`EffectCurve\` convierte` por:

```markdown
**Efecto.** `EffectCurve` convierte el ángulo en progreso `p` (smoothstep entre 12° y 100°) y
`SpatialEffect` lo reparte por la pantalla según la altura `g` respecto a la bisagra:
desenfoque `= radio · p · peso(g)` y negro `= max(min(1, 2 · p · peso(g)), fundido final)`, con
`peso(g) = (0,05 + 0,95 · g)^1,35`. Una ventana sin bordes por pantalla integrada, en el nivel
`screenSaver`, transparente a los clics y en todos los Escritorios, desenfoca lo que hay detrás
con una máscara generada una vez y pinta encima un degradado negro de 16 paradas. Por fotograma
solo cambian el radio y los 16 alfas. Un `CADisplayLink` solo corre mientras hay algo que animar.
```

En "Estructura", añadir debajo de `  EffectCurve.swift        ángulo → intensidad`:

```
  SpatialEffect.swift      intensidad → blur y negro según la altura respecto a la bisagra
```

y debajo de `  OverlayWindow.swift      ventana del efecto y desenfoque`:

```
  VariableBlur.swift       CABackdropLayer + variableBlur y su máscara
```

- [ ] **Step 5: Compilación final y tests**

Run: `scripts/build-app.sh && scripts/test.sh`
Expected: `✓ build/DuoLid.app`; `✔ Test run with 20 tests in 3 suites passed`.

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "README: blur espacial, ajustes nuevos y APIs privadas usadas"
```
