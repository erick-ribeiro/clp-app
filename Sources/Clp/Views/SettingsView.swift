import SwiftUI

@MainActor
struct SettingsView: View {
  @Environment(\.scenePhase) private var scenePhase
  @ObservedObject private var settings = AppSettings.shared
  @State private var ignoredBundleID = ""
  @State private var accessibilityIsTrusted = AccessibilityPermission.isTrusted

  var body: some View {
    Form {
      Section("Aparência") {
        Toggle(
          "Painel compacto",
          isOn: $settings.isCompactPanelEnabled
        )
        Text("Usa cards de 170 × 135 pontos e reduz a altura do shelf.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Histórico") {
        Picker(
          "Excluir itens não fixados após",
          selection: $settings.retentionPolicy
        ) {
          ForEach(RetentionPolicy.allCases) { policy in
            Text(policy.displayName).tag(policy)
          }
        }
      }

      Section("Privacidade") {
        Toggle(
          "Sincronizar via iCloud",
          isOn: $settings.isCloudSyncEnabled
        )
        .disabled(true)

        Text("A sincronização ainda não está disponível; os dados permanecem neste Mac.")
          .font(.caption)
          .foregroundStyle(.secondary)

        if settings.ignoredBundleIDs.isEmpty {
          Text("Nenhum aplicativo ignorado")
            .foregroundStyle(.secondary)
        } else {
          ForEach(settings.ignoredBundleIDs, id: \.self) { bundleID in
            Text(bundleID)
              .textSelection(.enabled)
          }
          .onDelete { offsets in
            settings.ignoredBundleIDs.remove(atOffsets: offsets)
          }
        }

        HStack {
          TextField(
            "Bundle ID, por exemplo com.1password.1password",
            text: $ignoredBundleID
          )
          .onSubmit(addIgnoredBundleID)

          Button("Adicionar", action: addIgnoredBundleID)
            .disabled(normalizedBundleID.isEmpty)
        }
      }

      Section("Atalho global") {
        LabeledContent("Abrir o Clp") {
          Text("⌘⇧V")
            .foregroundStyle(.secondary)
        }
        Text("A personalização do atalho estará disponível em uma versão futura.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Colagem automática") {
        LabeledContent("Permissão de Acessibilidade") {
          Label(
            accessibilityIsTrusted ? "Concedida" : "Necessária",
            systemImage: accessibilityIsTrusted
              ? "checkmark.circle.fill"
              : "exclamationmark.triangle.fill"
          )
          .foregroundStyle(
            accessibilityIsTrusted ? Color.green : Color.orange
          )
        }

        if !accessibilityIsTrusted {
          HStack {
            Button("Solicitar acesso", action: requestAccessibility)
            Button("Abrir Ajustes do Sistema") {
              AccessibilityPermission.openSystemSettings()
            }
          }
        }

        Text(
          accessibilityIsTrusted
            ? "O Clp pode enviar Cmd+V ao aplicativo de destino."
            : "Sem essa permissão, o item será copiado, mas o Cmd+V automático não será enviado."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .padding(20)
    .frame(width: 500, height: 570)
    .onAppear(perform: refreshAccessibilityStatus)
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        refreshAccessibilityStatus()
      }
    }
  }

  private var normalizedBundleID: String {
    ignoredBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func addIgnoredBundleID() {
    let bundleID = normalizedBundleID
    guard !bundleID.isEmpty,
      !settings.ignoredBundleIDs.contains(where: {
        $0.compare(bundleID, options: .caseInsensitive) == .orderedSame
      })
    else { return }

    settings.ignoredBundleIDs.append(bundleID)
    ignoredBundleID = ""
  }

  private func requestAccessibility() {
    accessibilityIsTrusted = AccessibilityPermission.requestAccess()

    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(500))
      refreshAccessibilityStatus()
    }
  }

  private func refreshAccessibilityStatus() {
    accessibilityIsTrusted = AccessibilityPermission.isTrusted
  }
}
