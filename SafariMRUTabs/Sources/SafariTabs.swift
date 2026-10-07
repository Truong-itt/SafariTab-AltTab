import ApplicationServices
import AppKit

/// Đọc thanh tab của Safari qua Accessibility.
///
/// Safari 26 : thanh tab là con TRỰC TIẾP của AXWindow, subrole
///             `AXOpaqueProviderList`; mỗi tab là AXRadioButton (AXTabButton)
///             với AXValue kiểu boolean và AXIndex 0-based.
/// Safari cũ : thanh tab nằm trong AXTabGroup chứa các AXRadioButton.
/// Cả hai đều được phủ: tìm phần tử đầu tiên có con là AXRadioButton.
enum SafariTabs {

    static let bundleID = "com.apple.Safari"

    /// Không đi vào vùng nội dung web — rất nhiều phần tử, tốn CPU vô ích.
    private static let skipRoles: Set<String> = [
        "AXWebArea", "AXScrollArea", "AXTable", "AXOutline", "AXList",
        "AXTextArea", "AXTextField", "AXImage", "AXStaticText",
        "AXMenuBar", "AXMenu", "AXSheet", "AXBrowser", "AXCell", "AXRow",
        "AXRadioButton",
    ]

    // MARK: - Ứng dụng / cửa sổ

    static var runningApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    static var isFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    static func appElement() -> AXUIElement? {
        guard let pid = runningApp?.processIdentifier else { return nil }
        let element = AXUIElementCreateApplication(pid)
        AX.setTimeout(element)
        return element
    }

    static func focusedWindow() -> AXUIElement? {
        guard let app = appElement() else { return nil }
        let window = AX.element(app, "AXFocusedWindow")
            ?? AX.element(app, "AXMainWindow")
            ?? AX.elements(app, "AXWindows").first
        guard let window, AX.role(window) == "AXWindow" else { return nil }
        return window
    }

    static func windows() -> [AXUIElement] {
        guard let app = appElement() else { return [] }
        return AX.elements(app, "AXWindows")
    }

    // MARK: - Thanh tab

    static func findTabBar(in window: AXUIElement) -> AXUIElement? {
        guard AX.isValid(window) else { return nil }

        // Đường nhanh cho Safari hiện tại
        for child in AX.children(window) where AX.subrole(child) == "AXOpaqueProviderList" {
            return child
        }

        // Đường tổng quát: phần tử đầu tiên có con là AXRadioButton
        var queue: [(element: AXUIElement, depth: Int)] = [(window, 0)]
        var head = 0
        var visited = 0
        while head < queue.count, visited < 400 {
            let node = queue[head]
            head += 1
            visited += 1

            let role = AX.role(node.element) ?? ""
            guard !skipRoles.contains(role) else { continue }

            let kids = AX.children(node.element)
            guard !kids.isEmpty else { continue }

            if node.depth > 0, kids.contains(where: { AX.role($0) == "AXRadioButton" }) {
                return node.element
            }
            if node.depth < 8 {
                for kid in kids { queue.append((kid, node.depth + 1)) }
            }
        }
        return nil
    }

    static func tabs(in tabBar: AXUIElement) -> [AXUIElement] {
        guard AX.isValid(tabBar) else { return [] }
        let declared = AX.elements(tabBar, "AXTabs")
        if !declared.isEmpty { return declared }
        return AX.children(tabBar).filter { AX.role($0) == "AXRadioButton" }
    }

    static func isSelected(_ tab: AXUIElement) -> Bool {
        AX.bool(tab, "AXValue") ?? false
    }

    /// Tab đang hiển thị và vị trí của nó trong danh sách (1-based).
    static func selectedTab(
        among tabs: [AXUIElement], window: AXUIElement
    ) -> (tab: AXUIElement, position: Int)? {
        for (index, tab) in tabs.enumerated() where isSelected(tab) {
            return (tab, index + 1)
        }
        // Dự phòng: khớp tiêu đề cửa sổ với tiêu đề tab
        if let windowTitle = AX.title(window) {
            for (index, tab) in tabs.enumerated() where AX.title(tab) == windowTitle {
                return (tab, index + 1)
            }
        }
        return nil
    }

    /// Chỉ số dùng cho AppleScript (1-based). AXIndex của Safari là 0-based.
    static func appleScriptIndex(of tab: AXUIElement, fallback position: Int) -> Int {
        if let index = AX.int(tab, "AXIndex") { return index + 1 }
        return position
    }

    /// Dự phòng khi AXPress không ăn. Cần quyền Automation cho Safari.
    static func selectViaAppleScript(index: Int) -> Bool {
        let source = """
        tell application "Safari"
            if (count of windows) is 0 then return false
            set w to window 1
            if \(index) > (count of tabs of w) then return false
            set current tab of w to tab \(index) of w
            return true
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        let result = script.executeAndReturnError(&error)
        if error != nil { return false }
        return result.booleanValue
    }
}
