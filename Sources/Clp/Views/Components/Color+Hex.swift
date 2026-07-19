import SwiftUI

extension Color {
  /// Aceita RGB/RGBA nas formas curta e longa (`#RGB`, `#RGBA`,
  /// `#RRGGBB` e `#RRGGBBAA`). Valores inválidos usam cinza opaco.
  init(hex: String) {
    let value =
      hex
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "#"))

    let expanded: String
    switch value.count {
    case 3, 4:
      expanded = value.map { "\($0)\($0)" }.joined()
    case 6, 8:
      expanded = value
    default:
      self = .gray
      return
    }

    let rgbaString = expanded.count == 6 ? expanded + "FF" : expanded
    guard let rgba = UInt64(rgbaString, radix: 16) else {
      self = .gray
      return
    }

    self.init(
      .sRGB,
      red: Double((rgba >> 24) & 0xFF) / 255,
      green: Double((rgba >> 16) & 0xFF) / 255,
      blue: Double((rgba >> 8) & 0xFF) / 255,
      opacity: Double(rgba & 0xFF) / 255
    )
  }
}
