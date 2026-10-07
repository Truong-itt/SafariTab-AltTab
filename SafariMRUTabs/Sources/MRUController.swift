import ApplicationServices
import AppKit

/// Một mục trong lịch sử: một tab cụ thể của một cửa sổ Safari cụ thể.
/// Dùng class để so sánh được bằng `===` khi chốt phiên duyệt sâu.
final class TabEntry {
    var window: AXUIElement
    /// nil = cửa sổ chỉ có 1 tab nên không có thanh tab; mục này đại diện cả cửa sổ.
    var tab: AXUIElement?
    var title: String?
    var appleScriptIndex: Int?

    init(window: AXUIElement, tab: AXUIElement?, title: String?, appleScriptIndex: Int?) {
        self.window = window
        self.tab = tab
        self.title = title
        self.appleScriptIndex = appleScriptIndex
    }

    /// Cửa sổ hiện tại của tab — tính lại mỗi lần, phòng khi tab bị kéo sang cửa sổ khác.
    var currentWindow: AXUIElement? {
        if let tab, let owner = AX.element(tab, "AXWindow") { return owner }
        return AX.isValid(window) ? window : nil
    }

    var isAlive: Bool {
        if let tab {
            guard AX.isValid(tab) else { return false }
            guard let owner = AX.element(tab, "AXWindow") else { return false }
            return AX.isValid(owner)
        }
        return AX.isValid(window)
    }

    func matches(_ other: TabEntry) -> Bool {
        if let a = tab, let b = other.tab { return AX.equal(a, b) }
        if tab == nil, other.tab == nil { return AX.equal(window, other.window) }
        return false
    }
}

/// Bộ não: theo dõi tab đang dùng, giữ lịch sử MRU, và chuyển tab.
final class MRUController {

    // MARK: Cấu hình

    var isEnabled = true { didSet { syncHotkeyState(force: true) } }
    var sameWindowOnly = false
    var maxHistory = 50
    var pollInterval: TimeInterval = 0.4
    var cycleTimeout: TimeInterval = 1.2

    /// Gọi khi trạng thái bật/tắt hoặc lịch sử đổi, để cập nhật menu.
    var onStateChange: (() -> Void)?

    // MARK: Trạng thái

    private(set) var history: [TabEntry] = []
    private var tabBarCache: [(window: AXUIElement, bar: AXUIElement?, stamp: Date)] = []

    private var observer: AXObserver?
    private var observerPID: pid_t?
    private var watchedWindows: [AXUIElement] = []

    private var poller: Timer?
    private var frontSync: Timer?
    private var lastWindowScan = Date.distantPast

    private var safariIsFront: Bool?

    private var cycleActive = false
    private var cycleIndex = 0
    private var cycleEntry: TabEntry?
    private var cycleTimer: Timer?

    private let hotkeys = HotkeyManager()

    // MARK: - Vòng đời

    func start() {
        hotkeys.register(.switchPrevious) { [weak self] in self?.switchToPrevious() }
        hotkeys.register(.cycleBack) { [weak self] in self?.cycleBack() }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(
            self, selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        // Lưới an toàn: thông báo didActivate KHÔNG bắn nếu Safari đã sẵn ở phía
        // trước lúc app khởi động. Thiếu bộ đồng bộ này thì phím tắt nằm im mãi.
        frontSync = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.syncHotkeyState()
        }
        syncHotkeyState()
    }

    func stop() {
        endCycle(commit: false)
        hotkeys.unregisterAll()
        poller?.invalidate(); poller = nil
        frontSync?.invalidate(); frontSync = nil
        stopObserver()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        history.removeAll()
        tabBarCache.removeAll()
    }

    @objc private func appActivated(_ note: Notification) {
        syncHotkeyState()
    }

    @objc private func appTerminated(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard app?.bundleIdentifier == SafariTabs.bundleID else { return }
        safariIsFront = false
        stopObserver()
        poller?.invalidate(); poller = nil
        hotkeys.setEnabled(false)
        history.removeAll()
        tabBarCache.removeAll()
        watchedWindows.removeAll()
        onStateChange?()
    }

    // MARK: - Bật/tắt phím tắt theo app đang ở phía trước

    private func syncHotkeyState(force: Bool = false) {
        let front = SafariTabs.isFrontmost
        guard force || front != safariIsFront else { return }
        safariIsFront = front

        Log.info("Safari ở phía trước: \(front) — phím tắt: \(front && isEnabled)")
        if front {
            ensureObserver()
            startPoller()
            hotkeys.setEnabled(isEnabled)
            recordCurrent(force: true)
        } else {
            endCycle(commit: true)
            hotkeys.setEnabled(false)
            poller?.invalidate(); poller = nil
        }
        onStateChange?()
    }

    private func startPoller() {
        guard poller == nil else { return }
        poller = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.recordCurrent()
            if Date().timeIntervalSince(self.lastWindowScan) > 3 {
                self.lastWindowScan = Date()
                self.refreshWindowWatchers()
            }
        }
    }

    // MARK: - Thanh tab (có cache, kể cả kết quả "không có")

    private func tabBar(for window: AXUIElement) -> AXUIElement? {
        let now = Date()
        for (index, cached) in tabBarCache.enumerated().reversed() {
            if !AX.isValid(cached.window) {
                tabBarCache.remove(at: index)
            } else if AX.equal(cached.window, window) {
                if let bar = cached.bar, AX.isValid(bar) { return bar }
                if cached.bar == nil, now.timeIntervalSince(cached.stamp) < 2 { return nil }
                tabBarCache.remove(at: index)
            }
        }
        let bar = SafariTabs.findTabBar(in: window)
        tabBarCache.append((window, bar, now))
        if tabBarCache.count > 12 { tabBarCache.removeFirst() }
        return bar
    }

    // MARK: - Ghi nhận tab đang dùng

    /// Đường nhanh: nếu mục đầu lịch sử vẫn là tab đang được chọn trong đúng cửa
    /// sổ đang focus thì không có gì đổi — thoát sau 2-3 lần đọc thuộc tính.
    /// Không dựa vào tiêu đề, nên vẫn đúng khi hai tab trùng tên.
    func recordCurrent(force: Bool = false) {
        guard isEnabled, !cycleActive else { return }
        guard let window = SafariTabs.focusedWindow() else { return }

        if !force, let current = history.first, AX.equal(current.window, window) {
            if let tab = current.tab {
                if SafariTabs.isSelected(tab) { return }
            } else if AX.title(window) == current.title {
                return
            }
        }

        var tabElement: AXUIElement?
        var position: Int?
        if let bar = tabBar(for: window) {
            let list = SafariTabs.tabs(in: bar)
            if let found = SafariTabs.selectedTab(among: list, window: window) {
                tabElement = found.tab
                position = found.position
            }
        }

        let entry = TabEntry(
            window: window,
            tab: tabElement,
            title: tabElement.flatMap { AX.title($0) } ?? AX.title(window),
            appleScriptIndex: tabElement.map { SafariTabs.appleScriptIndex(of: $0, fallback: position ?? 1) }
        )
        push(entry)
    }

    private func push(_ entry: TabEntry) {
        if let current = history.first, current.matches(entry) {
            current.title = entry.title ?? current.title
            current.appleScriptIndex = entry.appleScriptIndex ?? current.appleScriptIndex
            current.window = entry.window
            return
        }
        history.removeAll { $0.matches(entry) }
        history.insert(entry, at: 0)
        if history.count > maxHistory { history.removeLast(history.count - maxHistory) }
        onStateChange?()
    }

    private func pruneHistory() {
        history.removeAll { !$0.isAlive }
    }

    // MARK: - Chuyển tab

    /// Tìm lại phần tử tab của một mục trong trạng thái hiện tại của Safari.
    private func resolve(_ entry: TabEntry) -> (window: AXUIElement, tab: AXUIElement?, index: Int?)? {
        guard let window = entry.currentWindow, AX.isValid(window) else { return nil }
        let list = tabBar(for: window).map { SafariTabs.tabs(in: $0) } ?? []

        if let stored = entry.tab {
            for (index, tab) in list.enumerated() where AX.equal(tab, stored) {
                return (window, tab, SafariTabs.appleScriptIndex(of: tab, fallback: index + 1))
            }
        }
        if let title = entry.title {                    // dự phòng: khớp theo tiêu đề
            for (index, tab) in list.enumerated() where AX.title(tab) == title {
                return (window, tab, SafariTabs.appleScriptIndex(of: tab, fallback: index + 1))
            }
        }
        if entry.tab == nil, list.isEmpty {
            return (window, nil, nil)                   // cửa sổ 1 tab: chỉ cần đưa lên trước
        }
        return nil                                      // tab đã bị đóng
    }

    @discardableResult
    private func activate(_ entry: TabEntry) -> Bool {
        guard let resolved = resolve(entry) else { return false }

        SafariTabs.runningApp?.activate()
        AX.perform(resolved.window, "AXRaise")
        AX.setBool(resolved.window, "AXMain", true)

        guard let tab = resolved.tab else { return true }

        if AX.perform(tab, "AXPress") {
            entry.window = resolved.window
            entry.tab = tab
            entry.appleScriptIndex = resolved.index
            entry.title = AX.title(tab) ?? entry.title
            return true
        }
        if let index = resolved.index, SafariTabs.selectViaAppleScript(index: index) {
            entry.window = resolved.window
            entry.tab = tab
            entry.appleScriptIndex = index
            return true
        }
        return false
    }

    private func candidateIndices(from start: Int) -> [Int] {
        guard start < history.count else { return [] }
        let focused = sameWindowOnly ? SafariTabs.focusedWindow() : nil
        return (start..<history.count).filter { index in
            guard let focused else { return true }
            return AX.equal(history[index].currentWindow, focused)
        }
    }

    /// Quay lại tab dùng gần nhất. Bấm lần nữa sẽ quay về chỗ vừa rời đi.
    func switchToPrevious() {
        guard isEnabled else { return }
        endCycle(commit: true)
        recordCurrent(force: true)
        pruneHistory()

        for index in candidateIndices(from: 1) {
            let entry = history[index]
            if activate(entry) {
                // Đưa lên đầu NGAY, không đợi bộ theo dõi — nếu đợi thì hai lần
                // bấm liên tiếp sẽ cùng nhảy về một tab thay vì qua lại.
                history.remove(at: index)
                history.insert(entry, at: 0)
                Log.info("⌃⇥ → \(entry.title ?? "—")")
                onStateChange?()
                return
            }
        }
        reportNoCandidate(key: "⌃⇥")
    }

    /// Không tìm được tab để nhảy tới. Phân biệt cho rõ nguyên nhân: mất quyền
    /// Accessibility trông y hệt "lịch sử rỗng" nhưng cách xử lý hoàn toàn khác.
    private func reportNoCandidate(key: String) {
        if !AX.isTrusted {
            Log.info("\(key) thất bại: MẤT quyền Accessibility")
            HUD.show("Mất quyền Accessibility — hãy cấp lại trong System Settings", duration: 3.0)
        } else if SafariTabs.focusedWindow() == nil {
            Log.info("\(key) thất bại: không đọc được cửa sổ Safari nào")
            HUD.show("Không đọc được cửa sổ Safari")
        } else {
            Log.info("\(key) thất bại: lịch sử \(history.count) mục, không mục nào dùng được")
            HUD.show("Chưa có tab nào để quay lại")
        }
    }

    /// Lùi sâu hơn trong lịch sử. Bấm liên tiếp thì lùi tiếp, ngừng bấm thì chốt.
    func cycleBack() {
        guard isEnabled else { return }

        if !cycleActive {
            recordCurrent(force: true)
            pruneHistory()
            cycleActive = true
            cycleIndex = 0
            cycleEntry = nil
        }

        for _ in 0...history.count {
            var list = candidateIndices(from: cycleIndex + 1)
            if list.isEmpty { list = candidateIndices(from: 1) }   // quay vòng về đầu
            guard let target = list.first else {
                reportNoCandidate(key: "⌃⇧⇥")
                endCycle(commit: false)
                return
            }
            let entry = history[target]
            if activate(entry) {
                cycleIndex = target
                cycleEntry = entry
                Log.info("⌃⇧⇥ → [\(target + 1)] \(entry.title ?? "—")")
                cycleTimer?.invalidate()
                cycleTimer = Timer.scheduledTimer(
                    withTimeInterval: cycleTimeout, repeats: false
                ) { [weak self] _ in
                    self?.endCycle(commit: true)
                }
                return
            }
            history.remove(at: target)   // mục chết: bỏ rồi thử tiếp
        }
        endCycle(commit: false)
    }

    private func endCycle(commit: Bool) {
        cycleTimer?.invalidate()
        cycleTimer = nil
        if cycleActive, commit, let entry = cycleEntry,
           let index = history.firstIndex(where: { $0 === entry }) {
            history.remove(at: index)
            history.insert(entry, at: 0)
            onStateChange?()
        }
        cycleActive = false
        cycleIndex = 0
        cycleEntry = nil
    }

    // MARK: - AXObserver: phản ứng tức thì khi đổi tab

    private func stopObserver() {
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observerPID = nil
        watchedWindows.removeAll()
    }

    private func ensureObserver() {
        guard let pid = SafariTabs.runningApp?.processIdentifier else {
            stopObserver()
            return
        }
        if observer != nil, observerPID == pid { return }
        stopObserver()

        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let controller = Unmanaged<MRUController>.fromOpaque(refcon).takeUnretainedValue()
            let name = notification as String
            DispatchQueue.main.async {
                if name == kAXWindowCreatedNotification { controller.refreshWindowWatchers() }
                controller.recordCurrent()
            }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let observer = created else {
            return
        }

        self.observer = observer
        self.observerPID = pid

        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let notifications = [
            kAXFocusedUIElementChangedNotification,
            kAXFocusedWindowChangedNotification,
            kAXMainWindowChangedNotification,
            kAXWindowCreatedNotification,
            kAXApplicationActivatedNotification,
        ]
        for name in notifications {
            AXObserverAddNotification(observer, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(
            CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        refreshWindowWatchers()
    }

    /// Đổi tab làm tiêu đề cửa sổ đổi theo, nên theo dõi AXTitleChanged từng cửa sổ.
    private func refreshWindowWatchers() {
        guard let observer else { return }
        watchedWindows.removeAll { !AX.isValid($0) }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for window in SafariTabs.windows() {
            guard !watchedWindows.contains(where: { AX.equal($0, window) }) else { continue }
            AXObserverAddNotification(
                observer, window, kAXTitleChangedNotification as CFString, refcon)
            watchedWindows.append(window)
        }
    }

    // MARK: - Chẩn đoán

    var hotkeysActive: Bool { hotkeys.isEnabled }
    var safariFrontmost: Bool { safariIsFront ?? false }

    func diagnosticsText() -> String {
        var lines: [String] = []
        lines.append("Quyền Accessibility : \(AX.isTrusted ? "đã cấp" : "CHƯA cấp")")
        lines.append("Công cụ             : \(isEnabled ? "đang bật" : "đang tắt")")
        lines.append("Safari ở phía trước : \(safariFrontmost)")
        lines.append("Phím tắt đang bắt   : \(hotkeysActive)")
        lines.append("AXObserver          : \(observer != nil)")
        lines.append("")

        guard let window = SafariTabs.focusedWindow() else {
            lines.append("Không tìm thấy cửa sổ Safari nào.")
            return lines.joined(separator: "\n")
        }
        lines.append("Cửa sổ: \(AX.title(window) ?? "—")")
        guard let bar = tabBar(for: window) else {
            lines.append("KHÔNG tìm thấy thanh tab (cửa sổ 1 tab, hoặc thanh tab đang ẩn).")
            return lines.joined(separator: "\n")
        }
        let list = SafariTabs.tabs(in: bar)
        lines.append("Thanh tab: \(AX.role(bar) ?? "?") / \(AX.subrole(bar) ?? "?") — \(list.count) tab")
        lines.append("")
        lines.append("Lịch sử MRU (\(history.count) mục):")
        for (index, entry) in history.prefix(10).enumerated() {
            let mark = entry.isAlive ? "•" : "✗"
            lines.append("  \(index + 1). \(mark) \(entry.title ?? "—")")
        }
        return lines.joined(separator: "\n")
    }
}
