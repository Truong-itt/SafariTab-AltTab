import AppKit
import ServiceManagement

/// App chạy hoàn toàn ẩn: không icon dock, không icon thanh menu, không cửa sổ.
/// Cài xong là chạy, và tự bật khởi động cùng macOS.
///
/// Điều khiển duy nhất là phím tắt ⌃⌥T (bật/tắt). Mọi thứ khác đọc từ
/// UserDefaults, đổi bằng `defaults write com.hihi.SafariMRUTabs …`.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let controller = MRUController()
    private let globalHotkeys = HotkeyManager()
    private var permissionTimer: Timer?
    private var trustMonitor: Timer?
    private var lastTrusted = false

    // MARK: - Vòng đời

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Không còn menu thanh trạng thái nên cũng không còn nút Thoát.
        // "Gỡ cài đặt.command" gọi vào đây để huỷ đăng ký khởi động cùng macOS
        // trước khi xoá app — nếu không sẽ để lại mục rác trong Login Items.
        if CommandLine.arguments.contains("--uninstall") {
            do {
                try SMAppService.mainApp.unregister()
                Log.info("đã huỷ khởi động cùng macOS")
            } catch {
                Log.info("không huỷ được login item: \(error.localizedDescription)")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
            return
        }

        loadPreferences()

        let trusted = AX.isTrusted
        Log.info("khởi động — quyền Accessibility: \(trusted ? "đã cấp" : "CHƯA cấp")")

        if trusted {
            startEngine()
        } else {
            requestPermission()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
        globalHotkeys.unregisterAll()
    }

    private func startEngine() {
        controller.start()

        globalHotkeys.register(.toggleEnabled) { [weak self] in self?.toggleEnabled() }
        globalHotkeys.setEnabled(true)
        Log.info("engine đã chạy, phím bật/tắt ⌃⌥T đã đăng ký")

        enableLoginItemIfNeeded()
        startTrustMonitor()

        // Ghi chẩn đoán vào log ngay lúc khởi động: không còn menu để xem nữa,
        // nên đây là chỗ duy nhất tra cứu khi có sự cố.
        Log.info("chẩn đoán lúc khởi động:\n\(controller.diagnosticsText())")
    }

    // MARK: - Canh quyền Accessibility trong lúc chạy

    /// macOS có thể thu hồi quyền Accessibility bất cứ lúc nào (cập nhật hệ
    /// thống, app bị thay thế, người dùng dọn danh sách…). Trước đây app chỉ
    /// kiểm tra lúc khởi động nên mất quyền là hỏng âm thầm: phím tắt vẫn bắt,
    /// nhưng mọi lệnh đọc tab trả rỗng và người dùng chỉ thấy "chưa có tab nào
    /// để quay lại". Canh liên tục để hỏng thì hỏng cho ra tiếng.
    private func startTrustMonitor() {
        lastTrusted = AX.isTrusted
        trustMonitor?.invalidate()
        trustMonitor = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trusted = AX.isTrusted
            guard trusted != self.lastTrusted else { return }
            self.lastTrusted = trusted
            if trusted {
                Log.info("quyền Accessibility đã có lại — hoạt động bình thường")
                HUD.show("Safari MRU Tabs: đã có lại quyền")
            } else {
                Log.info("MẤT quyền Accessibility — công cụ ngừng hoạt động")
                HUD.show(
                    "Safari MRU Tabs mất quyền Accessibility.\nCấp lại trong System Settings.",
                    duration: 4.0)
            }
        }
    }

    // MARK: - Tuỳ chọn (không có UI — đọc từ UserDefaults)

    private func loadPreferences() {
        let defaults = UserDefaults.standard
        controller.sameWindowOnly = defaults.bool(forKey: "sameWindowOnly")
        if controller.sameWindowOnly {
            Log.info("tuỳ chọn: chỉ chuyển trong cửa sổ hiện tại")
        }
    }

    // MARK: - Quyền Accessibility

    private func requestPermission() {
        AX.requestTrust()
        HUD.show("Safari MRU Tabs cần quyền Accessibility", duration: 3.0)

        // Quyền vừa cấp chỉ chắc chắn có hiệu lực sau khi tiến trình khởi động
        // lại, nên phát hiện được là tự mở lại app.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard AX.isTrusted else { return }
            self.permissionTimer?.invalidate()
            self.permissionTimer = nil
            Log.info("quyền vừa được cấp — tự khởi động lại")
            self.relaunch()
        }
    }

    private func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: - Hành động

    private func toggleEnabled() {
        controller.isEnabled.toggle()
        HUD.show(
            controller.isEnabled
                ? "Safari MRU Tabs: BẬT"
                : "Safari MRU Tabs: TẮT — ⌃⇥ về mặc định")
        Log.info("bật/tắt: \(controller.isEnabled ? "BẬT" : "TẮT")")
    }

    // MARK: - Khởi động cùng macOS

    /// Tự đăng ký, không hỏi: người dùng muốn "cài xong là cứ chạy".
    private func enableLoginItemIfNeeded() {
        guard SMAppService.mainApp.status != .enabled else {
            Log.info("khởi động cùng macOS: đã bật sẵn")
            return
        }
        do {
            try SMAppService.mainApp.register()
            Log.info("khởi động cùng macOS: đã bật")
        } catch {
            Log.info(
                "khởi động cùng macOS: KHÔNG bật được (\(error.localizedDescription)) — "
                + "thường do app chưa nằm trong /Applications")
        }
    }
}
