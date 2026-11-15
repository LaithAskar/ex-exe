import Carbon

/// Global hotkeys via Carbon. Works without Accessibility permission.
enum HotKey {
    static var handlers: [UInt32: () -> Void] = [:]
    static var refs: [EventHotKeyRef?] = []

    static func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            HotKey.handlers[id.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }

    static func register(keyCode: Int, id: UInt32, handler: @escaping () -> Void) {
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let mods = UInt32(cmdKey | optionKey | controlKey)
        let hk = EventHotKeyID(signature: OSType(0x4558_4545), id: id) // 'EXEE'
        let status = RegisterEventHotKey(UInt32(keyCode), mods, hk, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { log("hotkey \(id) registration failed: \(status)") }
        refs.append(ref)
    }
}
