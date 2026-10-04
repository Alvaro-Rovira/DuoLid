import Carbon.HIToolbox

/// Atajo de teclado global (funciona aunque la app no esté activa) mediante `RegisterEventHotKey`,
/// que a diferencia de los monitores de eventos de AppKit no necesita permiso de Accesibilidad.
@MainActor
final class GlobalHotKey {
    /// ⌃⌥⌘D
    static let toggleEffect = (keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | optionKey | cmdKey))
    static let toggleEffectDescription = "⌃⌥⌘D"

    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Devuelve `nil` si otra app ya usa esa combinación.
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                // Carbon entrega los eventos de atajo en el hilo principal.
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
        let id = EventHotKeyID(signature: OSType(0x4455_4F4C), id: 1)  // 'DUOL'
        guard installed == noErr,
              RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr
        else { return nil }
    }
}
