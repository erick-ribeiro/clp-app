import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ClipboardPanelView: View {
  @Query(sort: \ClipItem.createdAt, order: .reverse) private var items: [ClipItem]
  @Query(sort: \Board.createdAt) private var boards: [Board]

  @Environment(\.modelContext) private var modelContext
  @EnvironmentObject private var panelState: PanelUIState
  @ObservedObject private var settings = AppSettings.shared

  @State private var selectedBoard: Board?
  @State private var query = ""
  @State private var searchIsFocused = false
  @State private var focusedIndex = 0
  @State private var scrolledItemID: ClipItem.ID?

  @State private var renamingItem: ClipItem?
  @State private var renameText = ""
  @FocusState private var isInlineEditorFocused: Bool
  @FocusState private var resultsHaveKeyboardFocus: Bool

  @State private var boardFrames: [Board.ID: CGRect] = [:]
  @State private var dropTargetBoardID: Board.ID?

  let onSelect: (ClipItem) -> Void
  let onClose: () -> Void

  private static let topCornerRadius: CGFloat = 20

  private var isCompact: Bool {
    settings.isCompactPanelEnabled
  }

  private var scopedItems: [ClipItem] {
    guard let boardID = selectedBoard?.id else { return items }
    return items.filter { $0.board?.id == boardID }
  }

  private var filteredItems: [ClipItem] {
    scopedItems.filter { ClipSearch.matches($0, query: query) }
  }

  var body: some View {
    // O Liquid Glass fica atrás do conteúdo e NÃO participa do hit-test.
    // Dentro de `GlassEffectContainer`, campos de texto e drops deixam de
    // receber clique/teclado de forma confiável no macOS 26.
    ZStack {
      panelShape
        .fill(.clear)
        .glassEffect(.regular, in: panelShape)
        .allowsHitTesting(false)

      VStack(spacing: isCompact ? 6 : 8) {
        topBar

        if filteredItems.isEmpty {
          emptyState
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          results
        }
      }
      .padding(.horizontal, 10)
      .padding(.top, 9)
      .padding(.bottom, 8)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .clipShape(panelShape)
    .frame(minWidth: 700, maxWidth: .infinity, maxHeight: .infinity)
    .coordinateSpace(name: PanelDropCoordinateSpace.name)
    .onPreferenceChange(BoardFramePreferenceKey.self) { frames in
      boardFrames = frames
    }
    .onDrop(
      of: [ClipItemDrag.idType],
      delegate: BoardDropDelegate(
        boards: boards,
        boardFrames: boardFrames,
        dropTargetBoardID: $dropTargetBoardID,
        onDropClip: pinItem
      )
    )
    .focusable(!searchIsFocused && !isInlineEditorFocused)
    .focusEffectDisabled()
    .focused($resultsHaveKeyboardFocus)
    .onAppear {
      resetForPresentation()
    }
    .onChange(of: panelState.presentationID) { _, _ in
      resetForPresentation()
    }
    .onChange(of: panelState.isVisible) { _, isVisible in
      if !isVisible {
        searchIsFocused = false
        resultsHaveKeyboardFocus = false
        dropTargetBoardID = nil
      }
    }
    .onChange(of: searchIsFocused) { _, isFocused in
      if isFocused {
        resultsHaveKeyboardFocus = false
      }
    }
    .onChange(of: query) { _, _ in
      resetResultSelection()
    }
    .onChange(of: selectedBoard?.id) { _, _ in
      resetResultSelection()
    }
    .onChange(of: filteredItems.map(\.id)) { _, _ in
      clampResultSelection()
    }
    .onChange(of: boards.map(\.id)) { _, boardIDs in
      if let selectedBoard, !boardIDs.contains(selectedBoard.id) {
        self.selectedBoard = nil
      }
    }
    .onExitCommand(perform: onClose)
    .onKeyPress(.leftArrow) {
      moveFocus(by: -1)
    }
    .onKeyPress(.upArrow) {
      moveFocus(by: -1)
    }
    .onKeyPress(.rightArrow) {
      moveFocus(by: 1)
    }
    .onKeyPress(.downArrow) {
      moveFocus(by: 1)
    }
    .onKeyPress(.return) {
      selectFocused()
    }
    .onKeyPress { press in
      selectShortcut(from: press)
    }
  }

  private var panelShape: UnevenRoundedRectangle {
    UnevenRoundedRectangle(
      topLeadingRadius: Self.topCornerRadius,
      bottomLeadingRadius: 0,
      bottomTrailingRadius: 0,
      topTrailingRadius: Self.topCornerRadius
    )
  }

  private var topBar: some View {
    HStack(spacing: 12) {
      PanelSearchField(
        text: $query,
        isFocused: $searchIsFocused,
        focusRequestID: panelState.presentationID,
        onMoveToResults: enterResults,
        onSubmit: {
          _ = selectFocused(allowSearchFocus: true)
        },
        onCancel: onClose
      )
      .padding(.leading, 28)
      .padding(.trailing, 12)
      .frame(width: isCompact ? 220 : 260, height: 34)
      .overlay(alignment: .leading) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(
            searchIsFocused ? Color.accentColor : Color.secondary
          )
          .padding(.leading, 12)
          .allowsHitTesting(false)
      }
      .background {
        RoundedRectangle(cornerRadius: 17, style: .continuous)
          .fill(.clear)
          .glassEffect(
            .regular.interactive(),
            in: .rect(cornerRadius: 17)
          )
          .allowsHitTesting(false)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 17, style: .continuous)
          .strokeBorder(
            Color.accentColor.opacity(searchIsFocused ? 0.48 : 0),
            lineWidth: 1
          )
          .allowsHitTesting(false)
      }
      .animation(.easeOut(duration: 0.16), value: searchIsFocused)

      TabBarView(
        boards: boards,
        selectedBoard: $selectedBoard,
        isBoardFieldFocused: $isInlineEditorFocused,
        dropTargetBoardID: dropTargetBoardID,
        onDeleteBoard: deleteBoard,
        onFinishEditing: restoreFocusAfterEditing,
        onClosePanel: onClose
      )
      .frame(maxWidth: .infinity)
    }
    .frame(height: 36)
  }

  private var results: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      LazyHStack(spacing: isCompact ? 8 : 10) {
        ForEach(Array(filteredItems.enumerated()), id: \.element.id) {
          index,
          item in
          ClipCard(
            item: item,
            boards: boards,
            shortcutNumber: index < 9 ? index + 1 : nil,
            isFocused: index == focusedIndex,
            isCompact: isCompact,
            isRenaming: renamingItem?.id == item.id,
            renameText: $renameText,
            isRenameFieldFocused: $isInlineEditorFocused,
            onSelect: {
              onSelect(item)
            },
            onPin: { board in
              pin(item, to: board)
            },
            onUnpin: {
              unpin(item)
            },
            onStartRename: {
              startRenaming(item)
            },
            onCommitRename: {
              commitRename(item)
            },
            onCancelRename: cancelRename,
            onDelete: {
              delete(item)
            },
            onEditFile: {
              editFile(item)
            },
            onEditText: {
              editText(item)
            }
          )
          .id(item.id)
          .onHover { isHovering in
            if isHovering {
              focusedIndex = index
            }
          }
        }
      }
      .scrollTargetLayout()
      .padding(.horizontal, 2)
      .padding(.vertical, 6)
    }
    .scrollPosition(id: $scrolledItemID, anchor: .center)
    .onChange(of: focusedIndex) { _, index in
      guard filteredItems.indices.contains(index) else { return }
      withAnimation(.easeOut(duration: 0.18)) {
        scrolledItemID = filteredItems[index].id
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 7) {
      Image(systemName: query.isEmpty ? "clipboard" : "magnifyingglass")
        .font(.system(size: 24, weight: .light))
        .foregroundStyle(.secondary)

      Text(emptyStateTitle)
        .font(.system(size: 12, weight: .medium))

      if !query.isEmpty {
        Text("Tente outros termos")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(minHeight: isCompact ? 118 : 180)
  }

  private var emptyStateTitle: String {
    if !query.isEmpty {
      return "Nenhum resultado"
    }
    if let selectedBoard {
      return "\(selectedBoard.name) está vazio"
    }
    return "Nenhum item copiado ainda"
  }

  private func resetForPresentation() {
    query = ""
    focusedIndex = 0
    scrolledItemID = nil
    renamingItem = nil
    renameText = ""
    isInlineEditorFocused = false
    resultsHaveKeyboardFocus = false
    dropTargetBoardID = nil
    searchIsFocused = true
  }

  private func resetResultSelection() {
    focusedIndex = 0
    scrolledItemID = filteredItems.first?.id
  }

  private func clampResultSelection() {
    guard !filteredItems.isEmpty else {
      focusedIndex = 0
      scrolledItemID = nil
      return
    }

    focusedIndex = min(focusedIndex, filteredItems.count - 1)
    scrolledItemID = filteredItems[focusedIndex].id
  }

  private func enterResults() {
    guard !filteredItems.isEmpty else { return }
    searchIsFocused = false
    focusedIndex = min(focusedIndex, filteredItems.count - 1)

    DispatchQueue.main.async {
      resultsHaveKeyboardFocus = true
    }
  }

  private func restoreFocusAfterEditing() {
    if filteredItems.isEmpty {
      resultsHaveKeyboardFocus = false
      searchIsFocused = true
    } else {
      enterResults()
    }
  }

  private func moveFocus(by delta: Int) -> KeyPress.Result {
    guard resultsHaveKeyboardFocus,
      !searchIsFocused,
      !isInlineEditorFocused,
      !filteredItems.isEmpty
    else { return .ignored }

    let nextIndex = max(
      0,
      min(filteredItems.count - 1, focusedIndex + delta)
    )
    guard nextIndex != focusedIndex else { return .handled }

    focusedIndex = nextIndex
    return .handled
  }

  private func selectFocused(
    allowSearchFocus: Bool = false
  ) -> KeyPress.Result {
    guard (allowSearchFocus || resultsHaveKeyboardFocus),
      !isInlineEditorFocused,
      !(searchIsFocused && !allowSearchFocus),
      filteredItems.indices.contains(focusedIndex)
    else { return .ignored }

    onSelect(filteredItems[focusedIndex])
    return .handled
  }

  private func selectShortcut(from press: KeyPress) -> KeyPress.Result {
    guard resultsHaveKeyboardFocus,
      !searchIsFocused,
      !isInlineEditorFocused,
      let character = press.characters.first,
      let number = character.wholeNumberValue,
      (1...9).contains(number)
    else { return .ignored }

    let index = number - 1
    guard filteredItems.indices.contains(index) else { return .ignored }
    onSelect(filteredItems[index])
    return .handled
  }

  private func pin(_ item: ClipItem, to board: Board) {
    BoardService.pin(item, to: board, in: modelContext)
  }

  private func pinItem(_ itemID: UUID, _ board: Board) {
    guard let item = items.first(where: { $0.id == itemID }) else { return }
    pin(item, to: board)
  }

  private func unpin(_ item: ClipItem) {
    BoardService.unpin(item, in: modelContext)
  }

  private func deleteBoard(_ board: Board) {
    BoardService.delete(board, in: modelContext)
  }

  private func startRenaming(_ item: ClipItem) {
    renamingItem = item
    renameText = item.title ?? ""
    searchIsFocused = false
    resultsHaveKeyboardFocus = false

    DispatchQueue.main.async {
      isInlineEditorFocused = true
    }
  }

  private func commitRename(_ item: ClipItem) {
    let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
    item.title = title.isEmpty ? nil : title
    modelContext.saveLogged(category: "ClipRename")
    finishItemEditing()
  }

  private func cancelRename() {
    finishItemEditing()
  }

  private func finishItemEditing() {
    renamingItem = nil
    renameText = ""
    isInlineEditorFocused = false

    DispatchQueue.main.async {
      resultsHaveKeyboardFocus = true
    }
  }

  private func delete(_ item: ClipItem) {
    if renamingItem?.id == item.id {
      renamingItem = nil
      renameText = ""
    }
    modelContext.delete(item)
    modelContext.saveLogged(category: "ClipDelete")
  }

  private func editFile(_ item: ClipItem) {
    guard let url = item.resolvedFileURL else { return }
    let didStartAccess = url.startAccessingSecurityScopedResource()
    NSWorkspace.shared.open(url)
    if didStartAccess {
      url.stopAccessingSecurityScopedResource()
    }
  }

  private func editText(_ item: ClipItem) {
    TextEditWindowController.shared.edit(item) { text in
      item.textContent = text
      item.contentHash = ClipboardContentRules.contentHash(
        domain: .text,
        data: Data(text.utf8)
      )
      modelContext.saveLogged(category: "ClipEdit")
    }
  }
}
