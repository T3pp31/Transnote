import Foundation
import os

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.transnote.LocalTranscriber"

    static let general = Logger(subsystem: subsystem, category: "general")
    static let transcription = Logger(subsystem: subsystem, category: "transcription")
    static let export = Logger(subsystem: subsystem, category: "export")
    static let fileAccess = Logger(subsystem: subsystem, category: "fileAccess")

    static func info(_ message: String, logger: Logger = general) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String, logger: Logger = general) {
        logger.error("\(message, privacy: .public)")
    }

    static func debug(_ message: String, logger: Logger = general) {
        logger.debug("\(message, privacy: .public)")
    }
}

enum DebugSessionLogger {
    private static let logPath = "/Users/fukutomiteppei/Documents/GitHub/Transnote/.cursor/debug-22eea9.log"
    private static let sessionId = "22eea9"

    static func log(
        location: String,
        message: String,
        data: [String: String] = [:],
        hypothesisId: String,
        runId: String = "pre-fix"
    ) {
        // #region agent log
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        var payload: [String: Any] = [
            "sessionId": sessionId,
            "timestamp": timestamp,
            "location": location,
            "message": message,
            "hypothesisId": hypothesisId,
            "runId": runId,
        ]
        if !data.isEmpty {
            payload["data"] = data
        }

        guard JSONSerialization.isValidJSONObject(payload),
              let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonLine = String(data: jsonData, encoding: .utf8) else {
            return
        }

        let line = jsonLine + "\n"
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8) ?? Data())
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8))
        }
        // #endregion
    }
}
