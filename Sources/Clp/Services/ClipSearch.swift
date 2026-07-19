import Foundation

enum ClipSearch {
  static func matches(_ item: ClipItem, query: String) -> Bool {
    let tokens = normalized(query)
      .split(whereSeparator: \.isWhitespace)
      .map(String.init)

    guard !tokens.isEmpty else { return true }

    let searchableText = normalized(searchFields(for: item).joined(separator: "\n"))
    return tokens.allSatisfy(searchableText.contains)
  }

  static func normalized(_ value: String) -> String {
    value
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
        locale: .current
      )
      .lowercased(with: .current)
  }

  private static func searchFields(for item: ClipItem) -> [String] {
    var fields = [
      item.title,
      item.textContent,
      item.sourceAppName,
      item.sourceAppBundleID,
    ]

    if item.contentType == .url,
      let value = item.textContent,
      let url = URL(string: value)
    {
      fields.append(url.absoluteString)
      fields.append(url.host())
    }

    return fields.compactMap { $0 }
  }
}
