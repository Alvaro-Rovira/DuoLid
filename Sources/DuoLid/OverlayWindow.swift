import AppKit
import DuoLidCore
import os
import QuartzCore

/// Gestiona las ventanas del efecto: una por cada pantalla integrada (la que se pliega con la tapa).
@MainActor
final class OverlayController {
    var onScreensChanged: (() -> Void)?
    private var windows: [OverlayWindow] = []
    private var windowScreens: [NSRect] = []
    private var isShown = false
    private var observer: NSObjectProtocol?

    var screen: NSScreen? { windows.first?.screen ?? NSScreen.screens.first(where: \.isBuiltIn) }

    init() {
        rebuildWindows()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rebuildWindows()
                self?.onScreensChanged?()
            }
        }
    }

    func apply(_ appearance: OverlayAppearance) {
        guard appearance.isVisible else { return hide() }
        for window in windows {
            if !isShown { window.orderFrontRegardless() }
            window.apply(appearance)
        }
        isShown = !windows.isEmpty
    }

    func hide() {
        guard isShown else { return }
        windows.forEach { $0.hide() }
        isShown = false
    }

    private func rebuildWindows() {
        let screens = NSScreen.screens.filter(\.isBuiltIn)
        // Este aviso llega también por cambios que no afectan a la pantalla integrada.
        guard screens.map(\.frame) != windowScreens else { return }
        windows.forEach { $0.close() }
        windows = screens.map(OverlayWindow.init(screen:))
        windowScreens = screens.map(\.frame)
        isShown = false
    }
}

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

/// Desenfoque con radio variable de lo que hay detrás de una ventana, mediante la API privada
/// `CGSSetWindowBackgroundBlurRadius` (la misma que usa iTerm2). Se resuelve en tiempo de ejecución
/// para que, si desaparece en alguna versión de macOS, la app siga funcionando con el respaldo.
@MainActor
enum PrivateWindowBlur {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SetBlurRadius = @convention(c) (Int32, Int, Int32) -> Int32

    private static let api: (connection: Int32, setRadius: SetBlurRadius)? = {
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
        guard let connectionSymbol = dlsym(defaultHandle, "CGSMainConnectionID"),
              let setRadiusSymbol = dlsym(defaultHandle, "CGSSetWindowBackgroundBlurRadius")
        else { return nil }
        let connection = unsafeBitCast(connectionSymbol, to: MainConnectionID.self)()
        return (connection, unsafeBitCast(setRadiusSymbol, to: SetBlurRadius.self))
    }()

    private static var hasLoggedFirstCall = false

    static var isAvailable: Bool { api != nil }

    @discardableResult
    static func setRadius(_ radius: Int, for window: NSWindow) -> Bool {
        guard let api, window.windowNumber > 0 else { return false }
        let error = api.setRadius(api.connection, window.windowNumber, Int32(clamping: radius))
        if !hasLoggedFirstCall {
            hasLoggedFirstCall = true
            Logger(subsystem: "DuoLid", category: "overlay")
                .notice("CGSSetWindowBackgroundBlurRadius(\(radius, privacy: .public)) → \(error, privacy: .public)")
        }
        return error == 0
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var isBuiltIn: Bool {
        displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false
    }
}
