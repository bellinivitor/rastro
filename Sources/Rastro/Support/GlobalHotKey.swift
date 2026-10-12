import Carbon.HIToolbox
import Foundation

/// Atalho de teclado global (funciona com qualquer app em primeiro plano).
/// Usa a API Carbon `RegisterEventHotKey`, que não exige permissão de acessibilidade.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    /// `nil` quando o atalho já está em uso por outro app.
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { hotKey.action() }
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
        guard status == noErr else { return nil }

        // Assinatura "DvTl": identifica o atalho deste app.
        let id = EventHotKeyID(signature: OSType(0x4476_546C), id: 1)
        let registered = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registered == noErr else {
            RemoveEventHandler(handlerRef)
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// ⌥⌘N
    static func quickNote(action: @escaping () -> Void) -> GlobalHotKey? {
        GlobalHotKey(keyCode: kVK_ANSI_N, modifiers: cmdKey | optionKey, action: action)
    }
}
