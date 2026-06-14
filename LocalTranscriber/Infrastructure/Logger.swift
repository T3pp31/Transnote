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
    private static let ingestURL = URL(string: "http://127.0.0.1:7393/ingest/8a2f614f-b14b-498d-b2f4-8f129340b240")!
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
              let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }

        var request = URLRequest(url: ingestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sessionId, forHTTPHeaderField: "X-Debug-Session-Id")
        request.httpBody = jsonData
        URLSession.shared.dataTask(with: request).resume()

        let containerLogURL = AppDirectories.applicationSupport.appendingPathComponent("debug-\(sessionId).log")
        try? FileManager.default.createDirectory(
            at: AppDirectories.applicationSupport,
            withIntermediateDirectories: true
        )
        if let line = String(data: jsonData, encoding: .utf8) {
            let lineData = (line + "\n").data(using: .utf8) ?? Data()
            if let handle = try? FileHandle(forWritingTo: containerLogURL) {
                handle.seekToEndOfFile()
                handle.write(lineData)
                try? handle.close()
            } else {
                try? lineData.write(to: containerLogURL)
            }
        }
        // #endregion
    }
}
