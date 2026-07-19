import Foundation

enum RetentionPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
  case hours24
  case days7
  case days30
  case never

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .hours24:
      "24 horas"
    case .days7:
      "7 dias"
    case .days30:
      "30 dias"
    case .never:
      "Nunca"
    }
  }

  /// Data anterior à qual clips não protegidos podem ser removidos.
  var cutoffDate: Date? {
    let calendar = Calendar.current

    switch self {
    case .hours24:
      return calendar.date(byAdding: .hour, value: -24, to: .now)
    case .days7:
      return calendar.date(byAdding: .day, value: -7, to: .now)
    case .days30:
      return calendar.date(byAdding: .day, value: -30, to: .now)
    case .never:
      return nil
    }
  }
}
