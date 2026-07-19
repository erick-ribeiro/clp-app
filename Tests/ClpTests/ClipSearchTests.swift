import Testing

@testable import Clp

@MainActor
@Suite("Busca de clips")
struct ClipSearchTests {
  @Test("Ignora caixa e acentos")
  func ignoresCaseAndDiacritics() {
    let item = makeItem(
      text: "Reunião de produto",
      title: "Próximos passos"
    )

    #expect(ClipSearch.matches(item, query: "reuniao PRODUTO"))
    #expect(ClipSearch.matches(item, query: "proximos"))
    #expect(!ClipSearch.matches(item, query: "financeiro"))
  }

  @Test("Busca por aplicativo e host da URL")
  func searchesApplicationAndURLHost() {
    let item = ClipItem(
      contentType: .url,
      textContent: "https://developer.apple.com/documentation/swiftui",
      sourceAppBundleID: "com.apple.Safari",
      sourceAppName: "Safari",
      contentHash: "hash"
    )

    #expect(ClipSearch.matches(item, query: "developer apple"))
    #expect(ClipSearch.matches(item, query: "safari"))
    #expect(ClipSearch.matches(item, query: "com.apple"))
  }

  @Test("Consulta vazia mantém o item")
  func emptyQueryMatches() {
    #expect(ClipSearch.matches(makeItem(text: "qualquer"), query: "   "))
  }

  private func makeItem(text: String, title: String? = nil) -> ClipItem {
    ClipItem(
      contentType: .text,
      textContent: text,
      title: title,
      contentHash: "hash"
    )
  }
}
