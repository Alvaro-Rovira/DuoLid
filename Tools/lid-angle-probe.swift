#!/usr/bin/env swift
//
//  lid-angle-probe.swift
//  Diagnóstico del sensor de ángulo de la tapa (Lid Angle Sensor, "las").
//
//  Uso:  swift Tools/lid-angle-probe.swift [segundos]   (por defecto 30)
//
//  Método (basado en github.com/samhenrigold/LidAngleSensor):
//    HID VendorID 0x05AC, ProductID 0x8104, UsagePage 0x0020 (Sensor), Usage 0x008A (Orientation).
//    Se lee el feature report 1; el ángulo en grados es un UInt16 little-endian en los bytes [1...2].
//

import Foundation
import IOKit
import IOKit.hid

let duration = CommandLine.arguments.dropFirst().first.flatMap(Double.init) ?? 30
let none = IOOptionBits(kIOHIDOptionsTypeNone)

func hex(_ value: Int32) -> String { String(format: "0x%08X", UInt32(bitPattern: value)) }

func intProperty(_ device: IOHIDDevice, _ key: String) -> Int {
    (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? -1
}

func stringProperty(_ device: IOHIDDevice, _ key: String) -> String {
    IOHIDDeviceGetProperty(device, key as CFString) as? String ?? "?"
}

// MARK: - 1. Modelo

var size = 0
sysctlbyname("hw.model", nil, &size, nil, 0)
var modelBytes = [CChar](repeating: 0, count: size)
sysctlbyname("hw.model", &modelBytes, &size, nil, 0)
print("Modelo: \(String(cString: modelBytes))")

// MARK: - 2. Enumerar los dispositivos HID del coprocesador de sensores (PID 0x8104)

let manager = IOHIDManagerCreate(kCFAllocatorDefault, none)
IOHIDManagerSetDeviceMatching(manager, [
    kIOHIDVendorIDKey: 0x05AC,
    kIOHIDProductIDKey: 0x8104,
] as CFDictionary)
let managerOpen = IOHIDManagerOpen(manager, none)
print("IOHIDManagerOpen: \(hex(managerOpen))")

let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
print("Dispositivos 0x05AC:0x8104 encontrados: \(devices.count)")
for device in devices {
    let page = intProperty(device, kIOHIDPrimaryUsagePageKey)
    let usage = intProperty(device, kIOHIDPrimaryUsageKey)
    print(String(format: "  · %-10@ UsagePage 0x%04X  Usage 0x%04X", stringProperty(device, kIOHIDProductKey) as NSString, page, usage))
}

guard let sensor = devices.first(where: {
    intProperty($0, kIOHIDPrimaryUsagePageKey) == 0x0020 && intProperty($0, kIOHIDPrimaryUsageKey) == 0x008A
}) else {
    print("\n✗ No se encontró el sensor de ángulo (UsagePage 0x20 / Usage 0x8A).")
    exit(1)
}
print("\n✓ Sensor encontrado: \"\(stringProperty(sensor, kIOHIDProductKey))\"")

let deviceOpen = IOHIDDeviceOpen(sensor, none)
print("IOHIDDeviceOpen: \(hex(deviceOpen))")
guard deviceOpen == kIOReturnSuccess else {
    print("✗ No se pudo abrir el dispositivo.")
    exit(1)
}

// MARK: - 3. ¿Envía input reports por su cuenta?

nonisolated(unsafe) var inputReportCount = 0
nonisolated(unsafe) var lastInputAngle = -1
let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
IOHIDDeviceRegisterInputReportCallback(sensor, inputBuffer, 64, { _, _, _, _, _, report, length in
    inputReportCount += 1
    if length >= 3 { lastInputAngle = Int(UInt16(report[2]) << 8 | UInt16(report[1])) }
}, nil)
IOHIDDeviceScheduleWithRunLoop(sensor, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

// MARK: - 4. Polling del feature report 1

struct Stats {
    var reads = 0, failures = 0, changes = 0
    var minAngle = Int.max, maxAngle = Int.min
    var totalReadTime: Double = 0, worstReadTime: Double = 0
    var lastAngle: Int?
}
var stats = Stats()
var report = [UInt8](repeating: 0, count: 8)
let start = Date()

print("\nLeyendo durante \(Int(duration)) s — abre y cierra la tapa despacio…\n")
print("  t(s)   ángulo   bytes                      ")

func poll() {
    var length = CFIndex(report.count)
    let t0 = DispatchTime.now().uptimeNanoseconds
    let result = IOHIDDeviceGetReport(sensor, kIOHIDReportTypeFeature, 1, &report, &length)
    let readMs = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
    stats.reads += 1
    stats.totalReadTime += readMs
    stats.worstReadTime = max(stats.worstReadTime, readMs)

    guard result == kIOReturnSuccess, length >= 3 else {
        stats.failures += 1
        if stats.failures <= 3 { print("  GetReport falló: \(hex(result)), longitud \(length)") }
        return
    }

    let angle = Int(UInt16(report[2]) << 8 | UInt16(report[1]))
    stats.minAngle = min(stats.minAngle, angle)
    stats.maxAngle = max(stats.maxAngle, angle)
    guard angle != stats.lastAngle else { return }
    stats.lastAngle = angle
    stats.changes += 1

    let elapsed = Date().timeIntervalSince(start)
    let bytes = report.prefix(length).map { String(format: "%02X", $0) }.joined(separator: " ")
    let bar = String(repeating: "█", count: max(0, min(angle, 180)) / 4)
    print(String(format: "  %5.2f  %4d°    %-26@ %@", elapsed, angle, bytes as NSString, bar as NSString))
}

let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in poll() }
RunLoop.main.add(timer, forMode: .default)
RunLoop.main.run(until: Date().addingTimeInterval(duration))
timer.invalidate()
IOHIDDeviceClose(sensor, none)

// MARK: - 5. Resumen

print("""

Resumen
  Lecturas: \(stats.reads)  (fallos: \(stats.failures))
  Cambios de valor: \(stats.changes)
  Rango observado: \(stats.minAngle == .max ? "—" : "\(stats.minAngle)° … \(stats.maxAngle)°")
  Latencia GetReport: media \(String(format: "%.3f", stats.totalReadTime / Double(max(stats.reads, 1)))) ms, peor \(String(format: "%.3f", stats.worstReadTime)) ms
  Input reports espontáneos: \(inputReportCount)\(lastInputAngle >= 0 ? " (último: \(lastInputAngle)°)" : "")
""")
