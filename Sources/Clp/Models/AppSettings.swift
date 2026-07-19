import Combine
import Foundation

/// Preferências leves e não relacionais, persistidas fora do SwiftData.
@MainActor
final class AppSettings: ObservableObject {
  static let shared = AppSettings()

  private enum Keys {
    static let retentionPolicy = "clp.retentionPolicy"
    static let ignoredBundleIDs = "clp.ignoredBundleIDs"
    static let isCloudSyncEnabled = "clp.isCloudSyncEnabled"
    static let isCompactPanelEnabled = "clp.isCompactPanelEnabled"
  }

  private let defaults: UserDefaults

  @Published var retentionPolicy: RetentionPolicy {
    didSet {
      defaults.set(retentionPolicy.rawValue, forKey: Keys.retentionPolicy)
    }
  }

  @Published var ignoredBundleIDs: [String] {
    didSet {
      defaults.set(ignoredBundleIDs, forKey: Keys.ignoredBundleIDs)
    }
  }

  /// Reservado para uma versão futura. O ModelContainer atual é local.
  @Published var isCloudSyncEnabled: Bool {
    didSet {
      defaults.set(isCloudSyncEnabled, forKey: Keys.isCloudSyncEnabled)
    }
  }

  @Published var isCompactPanelEnabled: Bool {
    didSet {
      defaults.set(isCompactPanelEnabled, forKey: Keys.isCompactPanelEnabled)
    }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    if let rawValue = defaults.string(forKey: Keys.retentionPolicy),
      let policy = RetentionPolicy(rawValue: rawValue)
    {
      retentionPolicy = policy
    } else {
      retentionPolicy = .days7
    }

    ignoredBundleIDs = defaults.stringArray(forKey: Keys.ignoredBundleIDs) ?? []
    isCloudSyncEnabled = defaults.bool(forKey: Keys.isCloudSyncEnabled)
    isCompactPanelEnabled = defaults.bool(forKey: Keys.isCompactPanelEnabled)
  }
}
