import Carbon.HIToolbox

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    var onPress: () -> Void = {}

    /// Registers Shift+Cmd+M globally (no permissions required). Returns what
    /// failed, or nil on success.
    func register() -> String? {
        if hotKeyRef != nil { return nil }
        if handlerRef == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                          eventKind: UInt32(kEventHotKeyPressed))
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
                guard let userData else { return noErr }
                Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue().onPress()
                return noErr
            }, 1, &eventType, selfPtr, &handlerRef)
            if status != noErr { return "InstallEventHandler returned \(status)" }
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D584252) /* 'MXBR' */, id: 1)
        let keyStatus = RegisterEventHotKey(UInt32(kVK_ANSI_M),
                            UInt32(cmdKey | shiftKey),
                            hotKeyID,
                            GetApplicationEventTarget(),
                            0,
                            &hotKeyRef)
        if keyStatus != noErr { return "RegisterEventHotKey returned \(keyStatus)" }
        return nil
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}
