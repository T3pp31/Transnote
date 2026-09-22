import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    let isBusy: Bool
    let canDownloadSelectedModel: Bool
    let isModelDownloaded: (ModelOption) -> Bool
    let onDownloadSelectedModel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("設定")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sectionSpacing) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.compactSpacing) {
                    Text("文字起こしモデル")
                        .font(.headline)
                    Picker("モデル", selection: $settings.selectedModelID) {
                        ForEach(settings.models) { model in
                            Label(
                                model.displayName,
                                systemImage: isModelDownloaded(model)
                                    ? "checkmark.circle"
                                    : "arrow.down.circle"
                            )
                            .tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 300)
                    .disabled(isBusy)
                    .onChange(of: settings.selectedModelID) { _ in
                        settings.persist()
                    }
                    Text("使用するWhisperモデルを選択します。モデルは別途ダウンロードが必要です。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let selectedModel = settings.selectedModel,
                       !isModelDownloaded(selectedModel) {
                        Button {
                            onDownloadSelectedModel()
                        } label: {
                            Label(
                                NSLocalizedString(
                                    "このモデルをダウンロード",
                                    comment: "Download selected model from settings"
                                ),
                                systemImage: "arrow.down.circle"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canDownloadSelectedModel)
                        .accessibilityHint(
                            NSLocalizedString(
                                "選択中のモデルをダウンロードします",
                                comment: "Download selected model accessibility hint"
                            )
                        )
                    }
                }

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.compactSpacing) {
                    Text("文字起こし言語")
                        .font(.headline)
                    Picker("言語", selection: $settings.selectedLanguageID) {
                        ForEach(settings.languages) { language in
                            Text(language.displayName).tag(language.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 300)
                    .disabled(isBusy)
                    .onChange(of: settings.selectedLanguageID) { _ in
                        settings.persist()
                    }
                    Text("音声の言語を選択します。Autoは自動検出です。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.compactSpacing) {
                Text("ストレージ管理")
                    .font(.headline)
                StorageRow(
                    title: "Imports",
                    directory: AppDirectories.importsDirectory,
                    icon: "tray"
                )
                StorageRow(
                    title: "Models",
                    directory: AppDirectories.modelsDirectory,
                    icon: "internaldrive"
                )
            }

            Spacer()

            HStack {
                Spacer()
                Button("閉じる") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 480, height: 360)
    }
}
private struct StorageRow: View {
    let title: String
    let directory: URL
    let icon: String

    @State private var sizeText: String = "計算中…"

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer()
            Text(sizeText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button("クリア") {
                AppDirectories.clearDirectory(directory)
                sizeText = "0 KB"
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(sizeText == "計算中…")
        }
        .onAppear {
            let bytes = AppDirectories.directorySize(of: directory)
            sizeText = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
    }
}
