import AppKit
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
/// Desenfoca lo que tiene detrás y pinta un degradado oscuro que nace en la bisagra.
@MainActor
final class OverlayWindow: NSWindow {
    private let dimmingLayer = CAGradientLayer()
    private var fallbackBlurView: NSVisualEffectView?
    private var appliedBlurRadius: Int?

    init(screen: NSScreen) {
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

        if !PrivateWindowBlur.isAvailable {
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

        // En las capas de AppKit el origen está abajo: (0.5, 0) es el borde de la bisagra.
        dimmingLayer.frame = content.bounds
        dimmingLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        dimmingLayer.startPoint = CGPoint(x: 0.5, y: 0)
        dimmingLayer.endPoint = CGPoint(x: 0.5, y: 1)
        dimmingLayer.opacity = 0
        content.layer?.addSublayer(dimmingLayer)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Que macOS no la recoloque para dejar libre la barra de menús.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    func apply(_ appearance: OverlayAppearance) {
        let radius = Int(appearance.blurRadius.rounded())
        if radius != appliedBlurRadius, PrivateWindowBlur.setRadius(radius, for: self) {
            appliedBlurRadius = radius
        }
        fallbackBlurView?.alphaValue = min(appearance.blurRadius / Settings.Defaults.maxBlurRadius, 1)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dimmingLayer.opacity = Float(appearance.dimming)
        // Al cerrar, la sombra sube desde la bisagra hasta cubrir la pantalla entera.
        let topAlpha = 0.25 + 0.75 * appearance.progress
        dimmingLayer.colors = [
            NSColor.black.cgColor,
            NSColor.black.withAlphaComponent(topAlpha).cgColor,
        ]
        CATransaction.commit()
    }

    func hide() {
        orderOut(nil)
        // Al volver a mostrarse se reenvía el radio, por si el servidor de ventanas lo descartó.
        appliedBlurRadius = nil
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
