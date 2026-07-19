import Foundation

enum BoardColorPalette {
  static let hexValues = [
    "#0A84FF", "#FF453A", "#32D74B", "#FF9F0A",
    "#BF5AF2", "#64D2FF", "#FFD60A", "#5E5CE6",
    "#FF375F", "#66D4CF", "#AC8E68", "#30D5C8",
  ]

  /// Escolhe uma cor livre e, quando possível, distante da cor do último
  /// board. A seleção é determinística para facilitar persistência e testes.
  static func nextColor(existingBoards: [Board]) -> String {
    let usedColors = Set(existingBoards.map { $0.colorHex.uppercased() })
    let availableColors = hexValues.filter {
      !usedColors.contains($0.uppercased())
    }

    guard !availableColors.isEmpty else {
      return generatedColor(startingAt: existingBoards.count, excluding: usedColors)
    }

    guard
      let lastColor = existingBoards.max(by: { $0.createdAt < $1.createdAt })?.colorHex
    else {
      return availableColors[0]
    }

    return availableColors.max {
      distance(from: $0, to: lastColor) < distance(from: $1, to: lastColor)
    } ?? availableColors[0]
  }

  private static func generatedColor(
    startingAt index: Int,
    excluding usedColors: Set<String>
  ) -> String {
    let goldenAngle = 137.508
    var candidateIndex = index

    while true {
      let hue = (Double(candidateIndex) * goldenAngle).truncatingRemainder(dividingBy: 360) / 360
      let candidate = hexFromHSB(
        hue: hue,
        saturation: 0.75,
        brightness: 0.95
      )

      if !usedColors.contains(candidate.uppercased()) {
        return candidate
      }

      candidateIndex += 1
    }
  }

  private static func distance(from firstHex: String, to secondHex: String) -> Double {
    let first = rgb(firstHex)
    let second = rgb(secondHex)
    let red = first.red - second.red
    let green = first.green - second.green
    let blue = first.blue - second.blue

    return (red * red + green * green + blue * blue).squareRoot()
  }

  private static func rgb(_ hex: String) -> (red: Double, green: Double, blue: Double) {
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    guard cleaned.count >= 6 else { return (0, 0, 0) }

    let colorValue = String(cleaned.prefix(6))
    guard let rgb = UInt64(colorValue, radix: 16) else { return (0, 0, 0) }

    return (
      Double((rgb >> 16) & 0xFF) / 255,
      Double((rgb >> 8) & 0xFF) / 255,
      Double(rgb & 0xFF) / 255
    )
  }

  private static func hexFromHSB(
    hue: Double,
    saturation: Double,
    brightness: Double
  ) -> String {
    let scaledHue = hue * 6
    let sector = Int(scaledHue.rounded(.down)) % 6
    let fraction = scaledHue - scaledHue.rounded(.down)
    let p = brightness * (1 - saturation)
    let q = brightness * (1 - saturation * fraction)
    let t = brightness * (1 - saturation * (1 - fraction))

    let red: Double
    let green: Double
    let blue: Double

    switch sector {
    case 0:
      (red, green, blue) = (brightness, t, p)
    case 1:
      (red, green, blue) = (q, brightness, p)
    case 2:
      (red, green, blue) = (p, brightness, t)
    case 3:
      (red, green, blue) = (p, q, brightness)
    case 4:
      (red, green, blue) = (t, p, brightness)
    default:
      (red, green, blue) = (brightness, p, q)
    }

    return String(
      format: "#%02X%02X%02X",
      Int((red * 255).rounded()),
      Int((green * 255).rounded()),
      Int((blue * 255).rounded())
    )
  }
}
