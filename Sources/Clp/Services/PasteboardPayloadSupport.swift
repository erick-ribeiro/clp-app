import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ClpPasteboardTypes {
  static let selfWrite = NSPasteboard.PasteboardType(
    "\(AppMetadata.bundleID).self-write"
  )
}

enum ImagePayloadSupport {
  /// Reads only the image container metadata. It does not decode the bitmap,
  /// which is important for screenshots and other multi-megapixel payloads.
  static func typeIdentifier(for data: Data) -> String? {
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard
      let source = CGImageSourceCreateWithData(data as CFData, options),
      let identifier = CGImageSourceGetType(source)
    else {
      return nil
    }
    return identifier as String
  }

  static func isImageTypeIdentifier(_ identifier: String) -> Bool {
    UTType(identifier)?.conforms(to: .image) == true
  }
}

struct ResolvedSecurityScopedBookmark: Sendable {
  let url: URL
  let isStale: Bool
}

enum SecurityScopedBookmark {
  static func resolve(_ data: Data) throws -> ResolvedSecurityScopedBookmark {
    var isStale = false
    let url = try URL(
      resolvingBookmarkData: data,
      options: [.withSecurityScope],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )
    return ResolvedSecurityScopedBookmark(url: url, isStale: isStale)
  }
}
