import Foundation
import IOKit.hid
import QuartzCore

public struct LidAngleSample: Sendable, Equatable {
    /// Ángulo de la tapa en grados (0 = cerrada).
    public let angle: Double
    /// Instante de la lectura, en el reloj de `CACurrentMediaTime()`.
    public let timestamp: TimeInterval
}

/// Lector del sensor de ángulo de la tapa ("las") de los MacBook con Apple Silicon.
///
/// HID 0x05AC:0x8104, UsagePage 0x0020 (Sensor), Usage 0x008A (Orientation). El ángulo se lee del
/// feature report 1 como un `UInt16` little-endian en los bytes 1–2. Método tomado de
/// https://github.com/samhenrigold/LidAngleSensor.
///
/// El sensor no envía datos por su cuenta (solo un latido de 1 Hz) y se actualiza a ≈10 Hz, así que
/// se consulta a 60 Hz mientras la tapa se mueve, para captar cada lectura nueva cuanto antes, y a
/// 10 Hz cuando lleva un segundo quieta. Cada consulta cuesta ≈0,16 ms de CPU.
public final class LidAngleSensor: @unchecked Sendable {
    public static let activeInterval: TimeInterval = 1.0 / 60
    public static let idleInterval: TimeInterval = 1.0 / 10
    public static let idleAfter: TimeInterval = 1.0

    private static let noOptions = IOOptionBits(kIOHIDOptionsTypeNone)

    // Todo el estado mutable vive en `queue`.
    private let queue = DispatchQueue(label: "DuoLid.LidAngleSensor", qos: .userInteractive)
    private var device: IOHIDDevice?
    private var isDeviceOpen = false
    private var timer: DispatchSourceTimer?
    private var isActiveRate = true
    private var handler: (@Sendable (LidAngleSample) -> Void)?
    private var lastAngle: Double?
    private var lastChange: TimeInterval = 0
    private var failures = 0
    private var report = [UInt8](repeating: 0, count: 8)

    /// Devuelve `nil` si este Mac no expone el sensor.
    public init?() {
        guard let device = Self.findDevice() else { return nil }
        self.device = device
    }

    deinit {
        timer?.cancel()
        if isDeviceOpen, let device { IOHIDDeviceClose(device, Self.noOptions) }
    }

    /// Empieza a leer. `handler` se llama en una cola interna cada vez que cambia el ángulo
    /// (la primera lectura siempre se entrega).
    public func start(handler: @escaping @Sendable (LidAngleSample) -> Void) {
        queue.async { [self] in
            guard timer == nil else { return }
            self.handler = handler
            lastAngle = nil
            openDevice()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.setEventHandler { [weak self] in self?.poll() }
            self.timer = timer
            setRate(active: true)
            timer.resume()
        }
    }

    public func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
            handler = nil
            closeDevice()
        }
    }

    // MARK: - Polling

    private func poll() {
        guard let device, isDeviceOpen else { return recordFailure() }

        var length = CFIndex(report.count)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
        let now = CACurrentMediaTime()
        guard result == kIOReturnSuccess, length >= 3 else { return recordFailure() }
        failures = 0

        let angle = Double(UInt16(report[2]) << 8 | UInt16(report[1]))
        if angle != lastAngle {
            lastAngle = angle
            lastChange = now
            if !isActiveRate { setRate(active: true) }
            handler?(LidAngleSample(angle: angle, timestamp: now))
        } else if isActiveRate, now - lastChange > Self.idleAfter {
            setRate(active: false)
        }
    }

    private func setRate(active: Bool) {
        isActiveRate = active
        let interval = active ? Self.activeInterval : Self.idleInterval
        timer?.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(active ? 2 : 20))
    }

    /// Si el dispositivo deja de responder (por ejemplo tras un reposo), se vuelve a buscar.
    private func recordFailure() {
        failures += 1
        guard failures % 30 == 0 else { return }
        closeDevice()
        device = Self.findDevice()
        openDevice()
    }

    private func openDevice() {
        guard let device, !isDeviceOpen else { return }
        isDeviceOpen = IOHIDDeviceOpen(device, Self.noOptions) == kIOReturnSuccess
    }

    private func closeDevice() {
        if isDeviceOpen, let device { IOHIDDeviceClose(device, Self.noOptions) }
        isDeviceOpen = false
    }

    // MARK: - Descubrimiento

    /// Busca el sensor y comprueba que responde a una lectura.
    static func findDevice() -> IOHIDDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, noOptions)
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: 0x05AC,
            kIOHIDProductIDKey: 0x8104,
            kIOHIDPrimaryUsagePageKey: 0x0020,
            kIOHIDPrimaryUsageKey: 0x008A,
        ] as CFDictionary)

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return nil }
        return devices.first { device in
            guard IOHIDDeviceOpen(device, noOptions) == kIOReturnSuccess else { return false }
            defer { IOHIDDeviceClose(device, noOptions) }
            var report = [UInt8](repeating: 0, count: 8)
            var length = CFIndex(report.count)
            return IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length) == kIOReturnSuccess
                && length >= 3
        }
    }
}
