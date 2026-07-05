import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @StateObject private var viewModel = MainWindowViewModel()
    @StateObject private var updateChecker = UpdateCheckViewModel()
    @ObservedObject private var settings = AppSettings.shared
    @State private var showingSettings = false

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
                    String(
                        format: NSLocalizedString(
                            "バージョン %@ が利用可能です（現在: %@）。\nダウンロード後、DMG 内の「インストール.command」を実行してください。\n旧バージョンは自動的に置き換えられます。",
                            comment: "Update available instructions"
                        ),
                        offer.latestVersion,
                        offer.currentVersion
                    )
                )
            }
        }
        .alert(
            viewModel.criticalErrorTitle
                ?? NSLocalizedString("エラー", comment: "Generic error title"),
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
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                isBusy: viewModel.isBusy,
                isModelDownloaded: viewModel.isModelDownloaded
            )
        }
        .overlay(alignment: .top) {
            if let toast = viewModel.toast {
                ToastView(message: toast)
                    .padding(.top, 12)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.toast)
        .focusedSceneValue(\.transcriptionActions, TranscriptionActionsValue(
            canStart: viewModel.canStartTranscription,
            startTranscription: viewModel.startTranscription,
            canCancel: viewModel.canCancel,
            cancelTranscription: viewModel.cancelTranscription,
            openFile: openFilePanel
        ))
    }

    private var inputSection: some View {
        VStack(spacing: DesignTokens.Spacing.sectionSpacing) {
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
        .padding(.horizontal, DesignTokens.Spacing.horizontalPadding)
        .padding(.top, DesignTokens.Spacing.topPadding)
        .padding(.bottom, DesignTokens.Spacing.bottomPadding)
    }

    private var resultSection: some View {
        TranscriptEditorView(
            text: $viewModel.transcriptText,
            isEditable: viewModel.uiState == .done || viewModel.currentTranscript != nil,
            isBusy: viewModel.isBusy,
            segments: viewModel.currentTranscript?.segments,
            playingSegmentID: viewModel.playingSegmentID,
            isEditing: $viewModel.isEditingTranscript,
            onSegmentTap: viewModel.playSegment,
            onCopy: viewModel.copyTranscript
        )
        .frame(maxHeight: .infinity)
        .padding(.horizontal, DesignTokens.Spacing.horizontalPadding)
        .padding(.bottom, DesignTokens.Spacing.bottomPadding)
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
            .padding(.horizontal, DesignTokens.Spacing.horizontalPadding)
            .padding(.vertical, DesignTokens.Spacing.footerVerticalPadding)
            .frame(minHeight: 44)
        }
    }

    private var toolbar: some View {
        VStack(spacing: DesignTokens.Spacing.sectionSpacing) {
            settingsToolbarRow

            Divider()

            actionToolbarRow
        }
    }

    private var settingsToolbarRow: some View {
        HStack(spacing: 12) {
            Button {
                showingSettings = true
            } label: {
                Label("設定", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isBusy)
            .accessibilityLabel("設定")
            .accessibilityHint("モデルや言語の設定を開きます")

            if viewModel.shouldShowModelDownloadButton {
                Button {
                    viewModel.downloadSelectedModel()
                } label: {
                    Label(
                        viewModel.isDownloadingModel
                            ? NSLocalizedString("ダウンロード中…", comment: "Downloading model button")
                            : NSLocalizedString("モデルをダウンロード", comment: "Download model button"),
                        systemImage: viewModel.isDownloadingModel
                            ? "arrow.down.circle.fill"
                            : "arrow.down.circle"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canDownloadSelectedModel)
                .help(
                    viewModel.modelDownloadDisabledReason
                        ?? NSLocalizedString("選択中のモデルをダウンロード", comment: "Download model help")
                )
                .accessibilityLabel(
                    viewModel.isDownloadingModel
                        ? NSLocalizedString("モデルをダウンロード中", comment: "Downloading model accessibility label")
                        : NSLocalizedString("モデルをダウンロード", comment: "Download model button")
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
            .help(
                viewModel.startTranscriptionDisabledReason
                    ?? NSLocalizedString("文字起こしを開始（⌘↩）", comment: "Start transcription shortcut help")
            )
            .accessibilityLabel("文字起こしを開始")
            .accessibilityHint("選択した音声ファイルの文字起こしを開始します")
        }
    }
    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = contentTypesForPicker()
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.selectFile(url: url, preferredFileName: nil)
        }
    }

    private func contentTypesForPicker() -> [UTType] {
        settings.supportedExtensions.compactMap { ext in
            switch ext.lowercased() {
            case "m4a": return .mpeg4Audio
            case "mp3": return .mp3
            case "wav": return .wav
            case "flac": return UTType(filenameExtension: "flac") ?? .audio
            default: return UTType(filenameExtension: ext)
            }
        }
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Corner.banner))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Corner.banner)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
