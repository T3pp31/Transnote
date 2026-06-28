import SwiftUI

struct MainWindowView: View {
    @StateObject private var viewModel = MainWindowViewModel()
    @StateObject private var updateChecker = UpdateCheckViewModel()
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            inputSection
            resultSection
            footerSection
        }
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

    private var inputSection: some View {
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
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var resultSection: some View {
        TranscriptEditorView(
            text: $viewModel.transcriptText,
            isEditable: viewModel.uiState == .done || viewModel.currentTranscript != nil,
            segments: viewModel.currentTranscript?.segments,
            playingSegmentID: viewModel.playingSegmentID,
            isEditing: $viewModel.isEditingTranscript,
            onSegmentTap: viewModel.playSegment,
            onCopy: viewModel.copyTranscript
        )
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var footerSection: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color.primary.opacity(0.08))

            StatusBarView(
                uiState: viewModel.uiState,
                progress: viewModel.progressDisplay,
                inlineErrorTitle: viewModel.inlineErrorTitle,
                canCancel: viewModel.canCancel,
                onCancel: viewModel.cancelTranscription
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(height: 44)
        }
    }

    private var toolbar: some View {
        VStack(spacing: 16) {
            settingsToolbarRow

            Divider()

            actionToolbarRow
        }
    }

    private var settingsToolbarRow: some View {
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
            .frame(width: 220)
            .disabled(viewModel.isBusy)
            .accessibilityLabel("文字起こしモデル")
            .accessibilityHint("使用するWhisperモデルを選択します")

            Picker("言語", selection: $settings.selectedLanguageID) {
                ForEach(settings.languages) { language in
                    Text(language.displayName).tag(language.id)
                }
            }
            .frame(width: 140)
            .disabled(viewModel.isBusy)
            .accessibilityLabel("文字起こし言語")
            .accessibilityHint("音声の言語を選択します")

            if viewModel.shouldShowModelDownloadButton {
                Button {
                    viewModel.downloadSelectedModel()
                } label: {
                    Label(
                        viewModel.isDownloadingModel ? "ダウンロード中…" : "モデルをダウンロード",
                        systemImage: viewModel.isDownloadingModel
                            ? "arrow.down.circle.fill"
                            : "arrow.down.circle"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canDownloadSelectedModel)
                .help("選択中のモデルをダウンロード")
                .accessibilityLabel(
                    viewModel.isDownloadingModel ? "モデルをダウンロード中" : "モデルをダウンロード"
                )
                .accessibilityHint("選択中の文字起こしモデルをダウンロードします")
            }

            Spacer(minLength: 0)
        }
    }

    private var actionToolbarRow: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            Menu("エクスポート") {
                ForEach(ExportFormat.allCases) { format in
                    Button(format.displayName) {
                        viewModel.exportTranscript(format: format)
                    }
                }
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canExport)
            .accessibilityLabel("文字起こし結果をエクスポート")
            .accessibilityHint("テキスト、SRT、VTT などの形式で書き出します")

            Button("文字起こしを開始") {
                viewModel.startTranscription()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canStartTranscription)
            .keyboardShortcut(.return, modifiers: [.command])
            .accessibilityLabel("文字起こしを開始")
            .accessibilityHint("選択した音声ファイルの文字起こしを開始します")
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
