import AppKit
import DuoLidCore
import Observation
import os
import QuartzCore

/// Decide cuánto efecto mostrar en cada fotograma.
///
/// - Con sensor: lecturas → `AngleSmoother` (predicción + muelle) → `EffectCurve` → overlay.
/// - Sin sensor: al encenderse la pantalla, animación de desenfocado a nítido en 0,6 s.
///
/// El enlace con la pantalla (`CADisplayLink`) solo corre mientras hay algo que animar, y la
/// ventana del overlay solo está en pantalla mientras el efecto es visible.
@MainActor
@Observable
final class EffectEngine {
    enum Mode { case sensor, wakeFallback }

    static let wakeAnimationDuration: TimeInterval = 0.6

    let mode: Mode
    /// Última lectura del sensor, en grados.
    private(set) var sensorAngle: Double?
    /// Intensidad actual del efecto (0…1) antes de aplicar los ajustes.
    private(set) var progress: Double = 0
    /// Ángulo al que se apagó la pantalla la última vez que se cerró la tapa (para calibrar).
    private(set) var lastScreenOffAngle: Double?
    private(set) var isSimulating = false
    private(set) var simulatedAngle: Double = 110
    var isEnabled: Bool { settings.isEnabled }

    @ObservationIgnored private let settings: Settings
    @ObservationIgnored private let sensor: LidAngleSensor?
    @ObservationIgnored private let overlay = OverlayController()
    @ObservationIgnored private var ticker: FrameTicker!
    @ObservationIgnored private var smoother = AngleSmoother(angle: 120)
    @ObservationIgnored private var hasSample = false
    @ObservationIgnored private var lastFrameTime: CFTimeInterval?
    @ObservationIgnored private var wakeAnimationStart: CFTimeInterval?
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var playback: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let log = Logger(subsystem: "DuoLid", category: "engine")

    init(settings: Settings, useSensor: Bool = true) {
        self.settings = settings
        sensor = useSensor ? LidAngleSensor() : nil
        mode = sensor == nil ? .wakeFallback : .sensor
        ticker = FrameTicker { [weak self] time in self?.frame(at: time) }
        ticker.attach(to: overlay.screen)
        overlay.onScreensChanged = { [weak self] in
            guard let self else { return }
            ticker.attach(to: overlay.screen)
            render()
        }
        settings.onChange = { [weak self] in self?.settingsDidChange() }
        log.notice("Modo: \(self.mode == .sensor ? "sensor" : "respaldo al despertar", privacy: .public)")
    }

    func start() {
        observeScreenSleep()
        applyEnabledState()
    }

    // MARK: - Fuentes de ángulo

    private func receive(_ sample: LidAngleSample) {
        if sensorAngle == nil {
            log.notice("Primera lectura del sensor: \(sample.angle, privacy: .public)°")
        }
        sensorAngle = sample.angle
        guard !isSimulating else { return }
        feed(sample.angle, at: sample.timestamp)
    }

    private func feed(_ angle: Double, at time: CFTimeInterval) {
        if hasSample {
            smoother.add(angle: angle, at: time)
        } else {
            smoother.jump(to: angle, at: time)
            hasSample = true
        }
        startTicking()
    }

    // MARK: - Simulación (panel de ajuste)

    func setSimulating(_ simulating: Bool) {
        guard simulating != isSimulating else { return }
        playback?.cancel()
        isSimulating = simulating
        let angle = simulating ? simulatedAngle : (sensorAngle ?? 180)
        feed(angle, at: CACurrentMediaTime())
    }

    func simulate(angle: Double) {
        playback?.cancel()
        simulatedAngle = angle
        if !isSimulating { isSimulating = true }
        feed(angle, at: CACurrentMediaTime())
    }

    /// Cierra y abre la tapa de mentira, entregando lecturas a 10 Hz y en pasos de 1° como el sensor real.
    func playSimulatedMotion() {
        setSimulating(true)
        playback?.cancel()
        playback = Task { [weak self] in
            let segments: [(from: Double, to: Double, duration: Double)] = [
                (110, 0, 1.2), (0, 0, 0.6), (0, 110, 0.9),
            ]
            for segment in segments {
                let steps = max(Int(segment.duration * 10), 1)
                for step in 1...steps {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled, let self else { return }
                    let t = Double(step) / Double(steps)
                    let eased = t * t * (3 - 2 * t)
                    let angle = (segment.from + (segment.to - segment.from) * eased).rounded()
                    simulatedAngle = angle
                    feed(angle, at: CACurrentMediaTime())
                }
            }
        }
    }

    // MARK: - Fotogramas

    private func startTicking() {
        guard isRunning, !ticker.isRunning else { return }
        lastFrameTime = nil
        ticker.isRunning = true
    }

    private func frame(at time: CFTimeInterval) {
        let dt = min(max(time - (lastFrameTime ?? time), 0), 1.0 / 30)
        lastFrameTime = time

        var newProgress = 0.0
        if hasSample {
            smoother.advance(to: time, by: dt)
            if mode == .sensor || isSimulating {
                newProgress = settings.curve.progress(atAngle: smoother.value)
            }
        }
        if let start = wakeAnimationStart {
            let t = (time - start) / Self.wakeAnimationDuration
            if t >= 1 {
                wakeAnimationStart = nil
            } else {
                let easeOut = 1 - pow(1 - t, 3)
                newProgress = max(newProgress, 1 - easeOut)
            }
        }
        setProgress(newProgress)

        if wakeAnimationStart == nil, smoother.isSettled(at: time) {
            ticker.isRunning = false
        }
    }

    private func setProgress(_ value: Double) {
        // Evita invalidar la interfaz por cambios imperceptibles.
        if abs(value - progress) > 0.001 || (value == 0) != (progress == 0) {
            progress = value
        }
        render()
    }

    private func render() {
        guard isRunning else { return overlay.hide() }
        overlay.apply(OverlayAppearance(progress: progress, settings: settings))
    }

    // MARK: - Ajustes y estado

    private func settingsDidChange() {
        applyEnabledState()
        render()
    }

    private func applyEnabledState() {
        if settings.isEnabled, !isRunning {
            isRunning = true
            sensor?.start { [weak self] sample in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.receive(sample) }
                }
            }
            startTicking()
        } else if !settings.isEnabled, isRunning {
            isRunning = false
            sensor?.stop()
            playback?.cancel()
            wakeAnimationStart = nil
            ticker.isRunning = false
            progress = 0
            hasSample = false
            overlay.hide()
        }
    }

    // MARK: - Reposo de pantalla

    private func observeScreenSleep() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensDidSleep() }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensDidWake() }
        })
    }

    private func screensDidSleep() {
        // Con la tapa casi cerrada, esto mide a qué ángulo apaga macOS la pantalla.
        if let angle = sensorAngle, angle < 45 {
            lastScreenOffAngle = angle
            log.notice("Pantalla apagada con la tapa a \(angle, privacy: .public)°")
        }
        guard mode == .wakeFallback, isRunning else { return }
        // Deja el efecto al máximo para que la pantalla se encienda ya desenfocada.
        wakeAnimationStart = nil
        ticker.isRunning = false
        setProgress(1)
    }

    private func screensDidWake() {
        guard mode == .wakeFallback, isRunning, !isSimulating else { return }
        wakeAnimationStart = CACurrentMediaTime()
        startTicking()
    }
}

/// Cómo se dibuja el overlay para una intensidad dada.
struct OverlayAppearance: Equatable {
    var progress: Double
    /// Radio de desenfoque de lo que hay detrás, en puntos.
    var blurRadius: Double
    /// Opacidad del degradado oscuro (0…1).
    var dimming: Double

    @MainActor
    init(progress: Double, settings: Settings) {
        let p = min(max(progress, 0), 1)
        self.progress = p
        blurRadius = settings.maxBlurRadius * settings.intensity * p
        // El oscurecimiento cae antes que el desenfoque: al abrir, la pantalla primero se
        // ilumina y después se enfoca.
        dimming = settings.maxDimming * settings.intensity * pow(p, 1.6)
    }

    var isVisible: Bool { blurRadius >= 0.5 || dimming >= 0.004 }
}

/// Envoltorio de `CADisplayLink` que se puede pausar cuando no hay nada que animar.
@MainActor
final class FrameTicker: NSObject {
    private var link: CADisplayLink?
    private let onFrame: (CFTimeInterval) -> Void

    init(onFrame: @escaping (CFTimeInterval) -> Void) {
        self.onFrame = onFrame
    }

    var isRunning: Bool {
        get { link.map { !$0.isPaused } ?? false }
        set { link?.isPaused = !newValue }
    }

    func attach(to screen: NSScreen?) {
        let wasRunning = isRunning
        link?.invalidate()
        link = (screen ?? NSScreen.main)?.displayLink(target: self, selector: #selector(tick(_:)))
        link?.add(to: .main, forMode: .common)
        link?.isPaused = !wasRunning
    }

    @objc private func tick(_ link: CADisplayLink) {
        onFrame(link.targetTimestamp)
    }
}
