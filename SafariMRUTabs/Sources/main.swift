import AppKit

// Không có main.storyboard, không có dock icon — app chỉ sống trên thanh menu.
let appDelegate = AppDelegate()
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
application.delegate = appDelegate
application.run()
