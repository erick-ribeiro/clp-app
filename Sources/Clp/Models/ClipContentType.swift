import Foundation

enum ClipContentType: String, Codable, CaseIterable, Sendable {
  case text
  case rtf
  case image
  case file
  case url
}
