import AppKit
import SwiftData
import SwiftUI

@MainActor
struct TabBarView: View {
  let boards: [Board]
  @Binding var selectedBoard: Board?
  var isBoardFieldFocused: FocusState<Bool>.Binding
  let dropTargetBoardID: Board.ID?
  let onDeleteBoard: (Board) -> Void
  let onFinishEditing: () -> Void
  let onClosePanel: () -> Void

  @Environment(\.modelContext) private var modelContext
  @Environment(\.openSettings) private var openSettings
  @EnvironmentObject private var panelState: PanelUIState

  @State private var isCreatingBoard = false
  @State private var newBoardName = ""
  @State private var renamingBoard: Board?
  @State private var renameText = ""

  var body: some View {
    HStack(spacing: 8) {
      navigationTray
      settingsButton
    }
    .onAppear {
      SettingsOpener.action = openSettings
    }
    .onChange(of: panelState.presentationID) { _, _ in
      resetTransientState(restoreFocus: false)
    }
  }

  private var navigationTray: some View {
    HStack(spacing: 4) {
      historyPill

      Capsule()
        .fill(Color.primary.opacity(0.12))
        .frame(width: 1, height: 16)
        .padding(.horizontal, 2)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 4) {
          ForEach(boards) { board in
            boardPill(board)
          }

          createBoardControl
        }
        .padding(.vertical, 1)
      }
    }
    .padding(3)
    .background {
      Capsule()
        .fill(.clear)
        .glassEffect(.regular, in: .capsule)
        .allowsHitTesting(false)
    }
  }

  private var settingsButton: some View {
    Button(action: showSettings) {
        Image(systemName: "gearshape")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 32, height: 32)
          .glassEffect(.regular.interactive(), in: .circle)
          .contentShape(.interaction, Circle())
          .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help("Ajustes")
  }

  private var historyPill: some View {
    Button {
      selectedBoard = nil
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "clock")
          .font(.system(size: 11, weight: .semibold))

        Text("Recentes")
          .lineLimit(1)
      }
      .font(
        .system(
          size: 11,
          weight: selectedBoard == nil ? .semibold : .medium
        )
      )
      .foregroundStyle(
        selectedBoard == nil ? Color.accentColor : Color.secondary
      )
      .padding(.horizontal, 10)
      .frame(height: 28)
      .background(
        selectedBoard == nil
          ? Color.accentColor.opacity(0.14)
          : Color.clear,
        in: Capsule()
      )
      .overlay {
        if selectedBoard == nil {
          Capsule()
            .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.75)
        }
      }
      .contentShape(.interaction, Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Histórico recente")
    .help("Histórico recente")
  }

  @ViewBuilder
  private func boardPill(_ board: Board) -> some View {
    if renamingBoard?.id == board.id {
      TextField("Nome do board", text: $renameText)
        .textFieldStyle(.plain)
        .font(.system(size: 11))
        .frame(width: 92)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(Color.primary.opacity(0.08), in: Capsule())
        .overlay {
          Capsule()
            .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.75)
        }
        .focused(isBoardFieldFocused)
        .id("rename-board-\(board.id)")
        .onSubmit {
          commitRename(board)
        }
        .onExitCommand {
          cancelBoardEditing()
        }
    } else {
      Button {
        selectedBoard = board
      } label: {
        HStack(spacing: 6) {
          Circle()
            .fill(Color(hex: board.colorHex))
            .frame(width: 7, height: 7)

          Text(board.name)
            .lineLimit(1)
        }
        .font(
          .system(
            size: 11,
            weight: selectedBoard?.id == board.id ? .semibold : .medium
          )
        )
        .foregroundStyle(
          selectedBoard?.id == board.id ? Color.primary : Color.secondary
        )
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
          selectedBoard?.id == board.id
            ? Color(hex: board.colorHex).opacity(0.16)
            : Color.clear,
          in: Capsule()
        )
        .overlay {
          if selectedBoard?.id == board.id {
            Capsule()
              .strokeBorder(
                Color(hex: board.colorHex).opacity(0.34),
                lineWidth: 0.75
              )
          }
        }
        .contentShape(.interaction, Capsule())
        .contentShape(Capsule())
      }
      .buttonStyle(.plain)
      .contextMenu {
        Button("Renomear") {
          startRenaming(board)
        }
        Button("Excluir", role: .destructive) {
          deleteBoard(board)
        }
      }
      .overlay {
        if dropTargetBoardID == board.id {
          Capsule()
            .strokeBorder(Color(hex: board.colorHex), lineWidth: 2)
        }
      }
      .scaleEffect(dropTargetBoardID == board.id ? 1.08 : 1)
      .animation(
        .spring(response: 0.24, dampingFraction: 0.72),
        value: dropTargetBoardID
      )
      .background {
        GeometryReader { proxy in
          Color.clear
            .allowsHitTesting(false)
            .preference(
              key: BoardFramePreferenceKey.self,
              value: [
                board.id: proxy.frame(in: .named(PanelDropCoordinateSpace.name))
              ]
            )
        }
      }
    }
  }

  @ViewBuilder
  private var createBoardControl: some View {
    if isCreatingBoard {
      TextField("Novo board", text: $newBoardName)
        .textFieldStyle(.plain)
        .font(.system(size: 11))
        .frame(width: 92)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(Color.primary.opacity(0.08), in: Capsule())
        .overlay {
          Capsule()
            .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.75)
        }
        .focused(isBoardFieldFocused)
        .id("new-board")
        .onSubmit(createBoard)
        .onExitCommand {
          cancelBoardEditing()
        }
    } else {
      Button {
        isCreatingBoard = true
        newBoardName = ""
        DispatchQueue.main.async {
          isBoardFieldFocused.wrappedValue = true
        }
      } label: {
        Image(systemName: "plus")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 28, height: 28)
          .background(Color.primary.opacity(0.06), in: Circle())
          .contentShape(.interaction, Circle())
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .help("Novo board")
    }
  }

  private func createBoard() {
    let name = newBoardName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      cancelBoardEditing()
      return
    }

    let board = Board(
      name: name,
      colorHex: BoardColorPalette.nextColor(existingBoards: boards)
    )
    modelContext.insert(board)
    modelContext.saveLogged(category: "BoardCreate")

    selectedBoard = board
    resetTransientState()
  }

  private func startRenaming(_ board: Board) {
    isCreatingBoard = false
    newBoardName = ""
    renamingBoard = board
    renameText = board.name

    DispatchQueue.main.async {
      isBoardFieldFocused.wrappedValue = true
    }
  }

  private func commitRename(_ board: Board) {
    let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !name.isEmpty {
      board.name = name
      modelContext.saveLogged(category: "BoardRename")
    }
    resetTransientState()
  }

  private func deleteBoard(_ board: Board) {
    if selectedBoard?.id == board.id {
      selectedBoard = nil
    }
    if renamingBoard?.id == board.id {
      resetTransientState()
    }
    onDeleteBoard(board)
  }

  private func cancelBoardEditing() {
    resetTransientState()
  }

  private func resetTransientState(restoreFocus: Bool = true) {
    isCreatingBoard = false
    newBoardName = ""
    renamingBoard = nil
    renameText = ""
    isBoardFieldFocused.wrappedValue = false

    if restoreFocus {
      DispatchQueue.main.async {
        onFinishEditing()
      }
    }
  }

  private func showSettings() {
    onClosePanel()
    NSApp.activate(ignoringOtherApps: true)
    openSettings()
  }
}

enum PanelDropCoordinateSpace {
  static let name = "ClpPanelDropCoordinateSpace"
}

struct BoardFramePreferenceKey: PreferenceKey {
  static let defaultValue: [Board.ID: CGRect] = [:]

  static func reduce(
    value: inout [Board.ID: CGRect],
    nextValue: () -> [Board.ID: CGRect]
  ) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}

struct BoardDropDelegate: DropDelegate {
  let boards: [Board]
  let boardFrames: [Board.ID: CGRect]
  @Binding var dropTargetBoardID: Board.ID?
  let onDropClip: (UUID, Board) -> Void

  func dropEntered(info: DropInfo) {
    guard ClipItemDrag.currentDraggedItemID != nil else { return }
    dropTargetBoardID = board(at: info.location)?.id
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    guard ClipItemDrag.currentDraggedItemID != nil else {
      dropTargetBoardID = nil
      return DropProposal(operation: .forbidden)
    }

    dropTargetBoardID = board(at: info.location)?.id
    return DropProposal(
      operation: dropTargetBoardID == nil ? .forbidden : .copy
    )
  }

  func dropExited(info: DropInfo) {
    dropTargetBoardID = nil
  }

  func performDrop(info: DropInfo) -> Bool {
    let target = board(at: info.location)
    let itemID = ClipItemDrag.currentDraggedItemID

    dropTargetBoardID = nil
    ClipItemDrag.currentDraggedItemID = nil

    guard let target, let itemID else { return false }
    onDropClip(itemID, target)
    return true
  }

  private func board(at point: CGPoint) -> Board? {
    boards.first { board in
      boardFrames[board.id]?.contains(point) == true
    }
  }
}
