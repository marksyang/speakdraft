import Foundation
import Carbon.HIToolbox

/// 全域快捷鍵服務（Carbon RegisterEventHotKey，無第三方依賴）
final class HotkeyService {
    static let shared = HotkeyService()

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventRef?] = [:]
    private var handlers: [UInt32: () -> Void] = [:]

    private init() {
        installEventHandler()
    }

    private func installEventHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return noErr }
                let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                service.handlers[hotKeyID.id]?()
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    func register(id: UInt32, combo: KeyCombo, handler: @escaping () -> Void) {
        unregister(id: id)
        guard combo.isSet else { return }

        handlers[id] = handler
        let hotKeyID = EventHotKeyID(signature: OSType(0x53444B59 /* 'SDKY' */), id: id)
        var ref: EventRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        hotKeyRefs[id] = status == noErr ? ref : nil
    }

    func unregister(id: UInt32) {
        if let ref = hotKeyRefs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        handlers[id] = nil
    }
}
