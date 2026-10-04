// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DuoLid",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DuoLid", targets: ["DuoLid"]),
    ],
    targets: [
        // Lógica sin interfaz: sensor, curva del efecto y suavizado. Se puede probar con `swift test`.
        .target(name: "DuoLidCore"),
        // App de barra de menús (SwiftUI + AppKit).
        .executableTarget(name: "DuoLid", dependencies: ["DuoLidCore"]),
        .testTarget(name: "DuoLidCoreTests", dependencies: ["DuoLidCore"]),
    ]
)
