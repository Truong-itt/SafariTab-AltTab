import Carbon.HIToolbox
import Foundation

/// Phím tắt toàn hệ thống bằng Carbon `RegisterEventHotKey`.
///
/// Cách này cướp phím TRƯỚC khi Safari nhìn thấy, nên `Control+Tab` không còn
/// nhảy sang tab bên phải. Đăng ký/huỷ đăng ký theo app đang ở phía trước để
/// các ứng dụng khác không bị ảnh hưởng.
///
/// Lưu ý khi tự kiểm thử: hotkey kiểu Carbon KHÔNG phản ứng với sự kiện phím do
/// phần mềm tạo ra (CGEvent tổng hợp) — phải bấm phím thật.
final class HotkeyManager {

    struct Spec {
        let keyCode: UInt32
        let modifiers: UInt32
        let label: String
    }

    enum Binding: Hashable {
        case switchPrevious     // Control + Tab
        case cycleBack          // Control + Shift + Tab
        case toggleEnabled      // Control + Option + T

        var spec: Spec {
            switch self {
            case .switchPrevious:
                return Spec(keyCode: UInt32(kVK_Tab),
                            modifiers: UInt32(controlKey),
                            label: "⌃⇥")
            case .cycleBack:
                return Spec(keyCode: UInt32(kVK_Tab),
                            modifiers: UInt32(controlKey | shiftKey),
                            label: "⌃⇧⇥")
            case .toggleEnabled:
                return Spec(keyCode: UInt32(kVK_ANSI_T),
                            modifiers: UInt32(controlKey | optionKey),
                            label: "⌃⌥T")
            }
        }
    }

    // Trình xử lý sự kiện dùng chung cho mọi instance, cài đúng một lần.
    private static var handlerInstalled = false
    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static let signature: OSType = 0x534D_5254   // 'SMRT'

    private static let eventHandler: EventHandlerUPP = { _, eventRef, _ in
        guard let eventRef else { return noErr }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID)
        guard status == noErr, let action = HotkeyManager.actions[hotKeyID.id] else { return noErr }
        DispatchQueue.main.async { action() }
        return noErr
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), eventHandler, 1, &eventType, nil, nil)
        handlerInstalled = true
    }

    // MARK: - Instance

    private var ids: [Binding: UInt32] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private(set) var isEnabled = false

    func register(_ binding: Binding, action: @escaping () -> Void) {
        HotkeyManager.installHandlerIfNeeded()
        let id = ids[binding] ?? {
            let new = HotkeyManager.nextID
            HotkeyManager.nextID += 1
            ids[binding] = new
            return new
        }()
        HotkeyManager.actions[id] = action
        if isEnabled { carbonRegister(binding, id: id) }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            for (binding, id) in ids { carbonRegister(binding, id: id) }
        } else {
            for (_, ref) in refs { UnregisterEventHotKey(ref) }
            refs.removeAll()
        }
    }

    func unregisterAll() {
        setEnabled(false)
        for (_, id) in ids { HotkeyManager.actions.removeValue(forKey: id) }
        ids.removeAll()
    }

    var labels: [String] { ids.keys.map { $0.spec.label }.sorted() }

    private func carbonRegister(_ binding: Binding, id: UInt32) {
        guard refs[id] == nil else { return }
        let spec = binding.spec
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: HotkeyManager.signature, id: id)
        let status = RegisterEventHotKey(
            spec.keyCode, spec.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs[id] = ref }
    }
}
