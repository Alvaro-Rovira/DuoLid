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
