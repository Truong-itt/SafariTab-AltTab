import ApplicationServices
import Foundation

/// Lớp bọc mỏng quanh Accessibility API, không bao giờ ném lỗi ra ngoài.
enum AX {

    // MARK: - Đọc thuộc tính

    static func raw(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        raw(element, name) as? String
    }

    static func bool(_ element: AXUIElement, _ name: String) -> Bool? {
        guard let value = raw(element, name) else { return nil }
        if CFGetTypeID(value) == CFBooleanGetTypeID() { return (value as! CFBoolean) == kCFBooleanTrue }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }

    static func int(_ element: AXUIElement, _ name: String) -> Int? {
        (raw(element, name) as? NSNumber)?.intValue
    }

    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = raw(element, name) else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        guard let value = raw(element, name) as? [AnyObject] else { return [] }
        return value.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }

    // MARK: - Tiện ích

    static func children(_ element: AXUIElement) -> [AXUIElement] { elements(element, "AXChildren") }
    static func role(_ element: AXUIElement) -> String? { string(element, "AXRole") }
    static func subrole(_ element: AXUIElement) -> String? { string(element, "AXSubrole") }
    static func title(_ element: AXUIElement) -> String? { string(element, "AXTitle") }

    /// Phần tử còn sống hay đã bị huỷ (tab/cửa sổ đã đóng).
    static func isValid(_ element: AXUIElement) -> Bool { role(element) != nil }

    /// So sánh hai tham chiếu có trỏ tới cùng một đối tượng UI hay không.
    static func equal(_ a: AXUIElement?, _ b: AXUIElement?) -> Bool {
        guard let a, let b else { return false }
        return CFEqual(a, b)
    }

    @discardableResult
    static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    @discardableResult
    static func setBool(_ element: AXUIElement, _ name: String, _ value: Bool) -> Bool {
        AXUIElementSetAttributeValue(
            element, name as CFString, (value ? kCFBooleanTrue : kCFBooleanFalse)!
        ) == .success
    }

    /// Chặn treo khi Safari bận: mọi lời gọi tối đa 0.5 giây.
    static func setTimeout(_ element: AXUIElement, seconds: Float = 0.5) {
        AXUIElementSetMessagingTimeout(element, seconds)
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
