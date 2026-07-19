import Foundation
import SwiftData

@MainActor
final class PersistenceStore {
  static let shared = PersistenceStore()

  let container: ModelContainer
  let storeURL: URL

  private init(fileManager: FileManager = .default) {
    let schema = Schema([
      ClipItem.self,
      Board.self,
    ])

    do {
      let applicationSupport = try fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      let storeDirectory = applicationSupport.appending(
        path: AppMetadata.bundleID,
        directoryHint: .isDirectory
      )

      try fileManager.createDirectory(
        at: storeDirectory,
        withIntermediateDirectories: true
      )

      storeURL = storeDirectory.appending(
        path: "Clp.store",
        directoryHint: .notDirectory
      )

      let configuration = ModelConfiguration(
        AppMetadata.displayName,
        schema: schema,
        url: storeURL,
        allowsSave: true,
        cloudKitDatabase: .none
      )

      container = try ModelContainer(
        for: schema,
        configurations: [configuration]
      )
    } catch {
      fatalError(
        "Não foi possível inicializar o armazenamento local do Clp: \(error)"
      )
    }
  }

  var mainContext: ModelContext {
    container.mainContext
  }
}
