import SwiftUI

struct MainWindowView: View {
    @StateObject private var viewModel = MainWindowViewModel()
    @StateObject private var updateChecker = UpdateCheckViewModel()
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 16) {
            toolbar
            if viewModel.inlineErrorMessage != nil {
                InlineErrorBanner(
                    title: viewModel.inlineErrorTitle,
                    message: viewModel.inlineErrorMessage ?? "",
                    canRetry: viewModel.canRetryError,
                    onRetry: viewModel.retryLastAction,
                    onDismiss: viewModel.dismissInlineError
                )
            }
            FileDropView(
                supportedExtensions: settings.supportedExtensions,
                selectedFile: viewModel.selectedFile,
                onFileSelected: viewModel.selectFile(url:preferredFileName:)
            )
            TranscriptEditorView(
                text: $viewModel.transcriptText,
                isEditable: viewModel.uiState == .done || viewModel.currentTranscript != nil,
                segments: viewModel.currentTranscript?.segments,
                playingSegmentID: viewModel.playingSegmentID,
                isEditing: $viewModel.isEditingTranscript,
                onSegmentTap: viewModel.playSegment,
                onCopy: viewModel.copyTranscript
            )
            StatusBarView(
                uiState: viewModel.uiState,
                progress: viewModel.progressDisplay,
                inlineErrorTitle: viewModel.inlineErrorTitle,
                canCancel: viewModel.canCancel,
                onCancel: viewModel.cancelTranscription
            )
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 560)
        .onAppear {
            viewModel.refreshModelAvailability()
            updateChecker.checkOnLaunch()
        }
        .alert(
            "アップデートが利用可能です",
            isPresented: Binding(
                get: { updateChecker.updateOffer != nil },
                set: { if !$0 { updateChecker.dismissUpdateOffer() } }
            )
        ) {
            Button("ダウンロード") {
                updateChecker.openDownloadPage()
            }
            Button("後で", role: .cancel) {
                updateChecker.dismissUpdateOffer()
            }
        } message: {
            if let offer = updateChecker.updateOffer {
                Text(
                    "バージョン \(offer.latestVersion) が利用可能です（現在: \(offer.currentVersion)）。"
                        + "ダウンロード後、DMG 内の「インストール.command」を実行してください。"
                        + "旧バージョンは自動的に置き換えられます。"
                )
            }
        }
        .alert(
            viewModel.criticalErrorTitle ?? "エラー",
            isPresented: Binding(
                get: { viewModel.criticalErrorMessage != nil },
                set: { if !$0 { viewModel.dismissCriticalError() } }
            )
        ) {
            Button("OK") {
                viewModel.dismissCriticalError()
            }
        } message: {
            Text(viewModel.criticalErrorMessage ?? "")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("モデル", selection: $settings.selectedModelID) {
                ForEach(settings.models) { model in
                    Label {
                        Text(model.displayName)
                    } icon: {
                        Image(systemName: modelIcon(for: model))
                    }
                    .tag(model.id)
                }
            }
            .frame(width: 240)
            .disabled(viewModel.isBusy)

            if viewModel.canDownloadSelectedModel {
                Button {
                    viewModel.downloadSelectedModel()
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .disabled(viewModel.isBusy)
                .help("選択中のモデルをダウンロード")
            }

            Picker("言語", selection: $settings.selectedLanguageID) {
                ForEach(settings.languages) { language in
                    Text(language.displayName).tag(language.id)
                }
            }
            .frame(width: 140)
            .disabled(viewModel.isBusy)

            Spacer()

            Button("Start") {
                viewModel.startTranscription()
            }
            .disabled(!viewModel.canStartTranscription)
            .keyboardShortcut(.return, modifiers: [.command])

            Menu("Export") {
                ForEach(ExportFormat.allCases) { format in
                    Button(format.displayName) {
                        viewModel.exportTranscript(format: format)
                    }
                }
            }
            .disabled(!viewModel.canExport)
        }
    }

    private func modelIcon(for model: ModelOption) -> String {
        viewModel.isModelDownloaded(model) ? "checkmark.circle" : "arrow.down.circle"
    }
}

private struct InlineErrorBanner: View {
    let title: String?
    let message: String
    let canRetry: Bool
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.body)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                if let title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if canRetry {
                Button("再試行", action: onRetry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("エラーを閉じる")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
