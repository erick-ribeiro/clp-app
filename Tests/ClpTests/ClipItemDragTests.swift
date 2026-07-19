import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Clp

@MainActor
@Suite("Drag de clips")
struct ClipItemDragTests {
  @Test("Provider de texto expõe payload real e identificador interno")
  func textProviderTypes() {
    let item = ClipItem(
      contentType: .text,
      textContent: "Arraste este texto",
      contentHash: "text"
    )

    let provider = ClipItemDrag.itemProvider(for: item)

    #expect(
      provider.hasItemConformingToTypeIdentifier(
        ClipItemDrag.idTypeIdentifier
      )
    )
    #expect(
      provider.hasItemConformingToTypeIdentifier(UTType.text.identifier)
    )
    #expect(ClipItemDrag.currentDraggedItemID == item.id)
    ClipItemDrag.currentDraggedItemID = nil
  }

  @Test("Provider de URL expõe URL nativa")
  func urlProviderTypes() {
    let item = ClipItem(
      contentType: .url,
      textContent: "https://apple.com",
      contentHash: "url"
    )

    let provider = ClipItemDrag.itemProvider(for: item)

    #expect(
      provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
    )
    ClipItemDrag.currentDraggedItemID = nil
  }
}
