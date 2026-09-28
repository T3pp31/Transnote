import AVFoundation
import Foundation

struct AudioFileInfo: Sendable, Equatable {
    let url: URL
    let fileName: String
    let fileExtension: String
    let fileSizeBytes: Int64
    let formattedFileSize: String
}

struct AudioFileService {
    let supportedExtensions: [String]

    init(supportedExtensions: [String] = AppConfig.shared.supportedExtensions) {
        self.supportedExtensions = supportedExtensions.map { $0.lowercased() }
    }

    func validate(url: URL, preferredFileName: String? = nil) throws -> AudioFileInfo {
        let pathExt = url.pathExtension.lowercased()
        let ext: String
        if pathExt.isEmpty {
            guard let resolved = SupportedAudioTypes.resolveExtension(for: url, preferredFileName: preferredFileName),
                  supportedExtensions.contains(resolved) else {
                throw AppError.unsupportedFileExtension("unknown")
            }
            ext = resolved
        } else {
            guard supportedExtensions.contains(pathExt) else {
                throw AppError.unsupportedFileExtension(pathExt)
            }
            ext = pathExt
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AppError.fileNotFound
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0

        return AudioFileInfo(
            url: url,
            fileName: url.lastPathComponent,
            fileExtension: ext,
            fileSizeBytes: fileSize,
            formattedFileSize: Self.formatByteCount(fileSize)
        )
    }

    /// AVFoundation で実際にデコード可能かを軽くプローブする。
    /// 拡張子チェックだけでは見逃す破損ファイルを検出するための補助。
    /// - Parameter url: プローブ対象のファイル URL
    /// - Returns: デコード可能なら true
    func probeDecodability(url: URL) -> Bool {
        let asset = AVURLAsset(url: url)
        // 同期的にトラック情報へアクセスして再生可能性を確認する（軽量プローブ）
        guard asset.tracks(withMediaType: .audio).first != nil || asset.isPlayable else {
            return false
        }
        return true
    }

    static func formatByteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
