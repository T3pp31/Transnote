import Foundation
import os

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.transnote.LocalTranscriber"

    static let general = Logger(subsystem: subsystem, category: "general")
    static let transcription = Logger(subsystem: subsystem, category: "transcription")
    static let export = Logger(subsystem: subsystem, category: "export")
    static let fileAccess = Logger(subsystem: subsystem, category: "fileAccess")

    static func info(_ message: String, logger: Logger = general, privacy: OSLogPrivacy = .private) {
        log(message, privacy: privacy) { logger.info($0) }
    }

    static func error(_ message: String, logger: Logger = general, privacy: OSLogPrivacy = .private) {
        log(message, privacy: privacy) { logger.error($0) }
    }

    static func debug(_ message: String, logger: Logger = general, privacy: OSLogPrivacy = .private) {
        log(message, privacy: privacy) { logger.debug($0) }
    }

    private static func log(
        _ message: String,
        privacy: OSLogPrivacy,
        using log: (OSLogMessage) -> Void
    ) {
        switch privacy {
        case .public:
            log("\(message, privacy: .public)")
        default:
            log("\(message, privacy: .private)")
        }
    }
}
