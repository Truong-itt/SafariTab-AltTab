import OSLog

/// Ghi log ra hệ thống. Xem bằng:
///   log show --last 5m --predicate 'subsystem == "com.hihi.SafariMRUTabs"' --info
///   log stream --predicate 'subsystem == "com.hihi.SafariMRUTabs"' --info
enum Log {
    private static let logger = Logger(subsystem: "com.hihi.SafariMRUTabs", category: "core")

    static func info(_ message: String) {
        // mức notice mới được ghi xuống đĩa; info chỉ nằm trong bộ nhớ
        logger.notice("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
