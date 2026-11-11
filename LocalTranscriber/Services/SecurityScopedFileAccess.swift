import Foundation

final class SecurityScopedFileAccess: @unchecked Sendable {
  static let shared = SecurityScopedFileAccess()

  private struct ActiveAccess {
    let url: URL
    let didStart: Bool
  }

  private let lock = NSLock()
  private var activeAccesses: [ActiveAccess] = []
  private let startAccessing: (URL) -> Bool
  private let stopAccessing: (URL) -> Void

  init(
    startAccessing: @escaping (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
    stopAccessing: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }
  ) {
    self.startAccessing = startAccessing
    self.stopAccessing = stopAccessing
  }

  func beginAccess(url: URL) throws {
    lock.lock()
    defer { lock.unlock() }

    // スコープ不要の URL でも false になるため、実際のアクセス可否は呼び出し元の I/O に委ねる。
    let didStart = startAccessing(url)

    guard FileManager.default.fileExists(atPath: url.path) else {
      if didStart {
        stopAccessing(url)
      }
      throw AppError.fileNotFound
    }

    activeAccesses.append(ActiveAccess(url: url, didStart: didStart))
  }

  func endAccess(url: URL) {
    lock.lock()
    defer { lock.unlock() }

    if let index = activeAccesses.firstIndex(where: { $0.url == url }) {
      let access = activeAccesses.remove(at: index)
      if access.didStart {
        stopAccessing(access.url)
      }
    }
  }

  func endAllAccess() {
    lock.lock()
    defer { lock.unlock() }

    for access in activeAccesses where access.didStart {
      stopAccessing(access.url)
    }
    activeAccesses.removeAll()
  }

  func createBookmark(for url: URL) throws -> Data {
    try url.bookmarkData(
      options: .withSecurityScope,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
  }

  func resolveBookmark(_ data: Data) throws -> URL {
    var isStale = false
    let url = try URL(
      resolvingBookmarkData: data,
      options: .withSecurityScope,
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )

    if isStale {
      AppLogger.info("Bookmark is stale for \(url.lastPathComponent)", logger: AppLogger.fileAccess)
    }

    return url
  }

  // MARK: - Last export directory

  static let lastExportDirectoryKey = "lastExportDirectoryBookmark"

  /// 最後にエクスポートしたディレクトリの security-scoped bookmark を保存する。
  func saveLastExportDirectoryBookmark(for url: URL) {
    do {
      let data = try createBookmark(for: url)
      UserDefaults.standard.set(data, forKey: Self.lastExportDirectoryKey)
    } catch {
      AppLogger.error(
        "Failed to save last export directory bookmark: \(error)",
        logger: AppLogger.fileAccess
      )
    }
  }

  /// 保存済みの最後のエクスポートディレクトリを解決する。
  /// 呼び出し元は beginAccess(url:) で security-scoped access を開始してから利用する。
  func loadLastExportDirectory() -> URL? {
    guard let data = UserDefaults.standard.data(forKey: Self.lastExportDirectoryKey) else {
      return nil
    }
    do {
      return try resolveBookmark(data)
    } catch {
      AppLogger.error(
        "Failed to resolve last export directory bookmark: \(error)",
        logger: AppLogger.fileAccess
      )
      return nil
    }
  }
}
