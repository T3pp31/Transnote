import Foundation
import os

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.transnote.LocalTranscriber"

    static let general = Logger(subsystem: subsystem, category: "general")
    static let transcription = Logger(subsystem: subsystem, category: "transcription")
    static let export = Logger(subsystem: subsystem, category: "export")
    static let fileAccess = Logger(subsystem: subsystem, category: "fileAccess")

    static func info(_ message: String, logger: Logger = general) {
        logger.info("\(message, privacy: .private)")
    }

    static func error(_ message: String, logger: Logger = general) {
        logger.error("\(message, privacy: .private)")
    }

    static func debug(_ message: String, logger: Logger = general) {
        logger.debug("\(message, privacy: .private)")
    }
}
