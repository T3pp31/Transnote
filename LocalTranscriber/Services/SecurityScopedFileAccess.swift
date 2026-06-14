import Foundation

final class SecurityScopedFileAccess: @unchecked Sendable {
  static let shared = SecurityScopedFileAccess()

  private let lock = NSLock()
  private var activeURLs: [URL] = []

  func beginAccess(url: URL) throws {
    lock.lock()
    defer { lock.unlock() }

    guard FileManager.default.fileExists(atPath: url.path) else {
      throw AppError.fileNotFound
    }

    guard url.startAccessingSecurityScopedResource() else {
      throw AppError.fileAccessDenied
    }

    activeURLs.append(url)
  }

  func endAccess(url: URL) {
    lock.lock()
    defer { lock.unlock() }

    if let index = activeURLs.firstIndex(where: { $0 == url }) {
      url.stopAccessingSecurityScopedResource()
      activeURLs.remove(at: index)
    }
  }

  func endAllAccess() {
    lock.lock()
    defer { lock.unlock() }

    for url in activeURLs {
      url.stopAccessingSecurityScopedResource()
    }
    activeURLs.removeAll()
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
      AppLogger.info("Bookmark is stale for \(url.path)", logger: AppLogger.fileAccess)
    }

    return url
  }
}
