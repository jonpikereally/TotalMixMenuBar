import AppKit
import ApplicationServices
import CoreAudio

/// Takes over the Mac's volume up/down/mute keys (and mice or keyboards that
/// send the same keys) and points them at a TotalMix output. Keys pass through
/// to macOS untouched whenever MixBar can't act on them: TotalMix isn't
/// connected, the feature is off, or another device is the Mac's sound output.
final class MediaKeys {
    static let shared = MediaKeys()

    enum Key { case up, down, mute }

    /// Return true to swallow the key. Called on the main thread.
    var onKey: (_ key: Key, _ fine: Bool) -> Bool = { _, _ in false }
    var shouldHandle: () -> Bool = { false }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var running = false

    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func promptForAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Starts the event tap. Throws MB-301 without Accessibility, MB-302 if the
    /// tap can't be created.
    func start() throws {
        if running { return }
        guard Self.accessibilityTrusted else { throw AppError(.accessibilityMissing) }
        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<MediaKeys>.fromOpaque(userInfo).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }, userInfo: selfPtr) else {
            throw AppError(.eventTapFailed, "CGEvent.tapCreate returned nil")
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        running = true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        running = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS switches a slow tap off; switch it straight back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let code = (ns.data1 & 0xFFFF_0000) >> 16
        let flags = ns.data1 & 0xFFFF
        let down = (flags & 0xFF00) >> 8 == 0x0A
        let key: Key
        switch code {
        case 0: key = .up       // NX_KEYTYPE_SOUND_UP
        case 1: key = .down     // NX_KEYTYPE_SOUND_DOWN
        case 7: key = .mute     // NX_KEYTYPE_MUTE
        default: return Unmanaged.passUnretained(event)
        }
        guard shouldHandle() else { return Unmanaged.passUnretained(event) }
        // Swallow key-ups too, so macOS doesn't see half a key press.
        guard down else { return nil }
        let isRepeat = flags & 0x1 == 1
        if key == .mute && isRepeat { return nil }
        // ⇧⌥ + volume key = fine steps, like macOS's quarter steps.
        let fine = ns.modifierFlags.contains(.shift) && ns.modifierFlags.contains(.option)
        return onKey(key, fine) ? nil : Unmanaged.passUnretained(event)
    }
}

/// The Mac's current sound output device.
enum SoundOutput {
    /// True when the default output is an RME interface (by maker or name).
    static var isRME: Bool {
        guard let id = defaultDevice() else { return false }
        let maker = string(id, kAudioObjectPropertyManufacturer).lowercased()
        let name = string(id, kAudioObjectPropertyName).lowercased()
        if maker.contains("rme") { return true }
        return ["fireface", "babyface", "madiface", "digiface", "ucx", "ufx", "rme"].contains { name.contains($0) }
    }

    static var name: String {
        defaultDevice().map { string($0, kAudioObjectPropertyName) } ?? "none"
    }

    private static func defaultDevice() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value)
        guard status == noErr, let value else { return "" }
        return value.takeRetainedValue() as String
    }
}
