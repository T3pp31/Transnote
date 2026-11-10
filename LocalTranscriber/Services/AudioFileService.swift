import AVFoundation
import CryptoKit
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

    /// 音声トラックの有無と AVFoundation の再生可否を軽くプローブする。
    /// 拡張子チェックだけでは見逃す破損ファイルを検出するための補助（全体のデコードは行わない）。
    /// - Parameter url: プローブ対象のファイル URL
    /// - Returns: 音声トラックが存在し、再生可能なら true
    func probeDecodability(url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        return await probeDecodability(
            loadHasAudioTrack: { try await asset.load(.tracks).contains(where: { $0.mediaType == .audio }) },
            loadIsPlayable: { try await asset.load(.isPlayable) }
        )
    }

    // 非対応コーデックなどの環境依存を避け、プロパティ読み込みの結果と失敗を個別に検証できるようにする。
    func probeDecodability(
        loadHasAudioTrack: () async throws -> Bool,
        loadIsPlayable: () async throws -> Bool
    ) async -> Bool {
        do {
            guard try await loadHasAudioTrack() else {
                return false
            }
            return try await loadIsPlayable()
        } catch {
            return false
        }
    }

    static func formatByteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// ファイルの SHA256 フィンガープリントを計算する。
    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        do {
            var hasher = SHA256()
            while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        } catch {
            AppLogger.error(
                "Failed to compute SHA256 for \(url.lastPathComponent): \(error.localizedDescription)",
                logger: AppLogger.fileAccess
            )
            return nil
        }
    }
}
