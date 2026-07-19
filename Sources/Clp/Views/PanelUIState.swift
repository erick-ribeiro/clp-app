import SwiftUI

/// Estado transitório compartilhado pelas views do painel.
///
/// O `PanelController` mantém a mesma árvore SwiftUI entre apresentações. O
/// contador permite que controles que já estavam focados recebam um novo pedido
/// de foco sempre que o painel reaparece, mesmo quando o valor booleano de foco
/// não mudou entre dois ciclos.
@MainActor
final class PanelUIState: ObservableObject {
  @Published private(set) var isVisible = false
  @Published private(set) var presentationID = 0

  func prepareForPresentation() {
    presentationID &+= 1
    isVisible = true
  }

  func didDismiss() {
    isVisible = false
  }
}
