import SwiftUI

struct MainWindowView: View {
    @StateObject private var viewModel = MainWindowViewModel()
    @StateObject private var updateChecker = UpdateCheckViewModel()
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 16) {
            toolbar
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
            "Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
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
            .accessibilityLabel("文字起こしモデル")
            .accessibilityHint("使用するWhisperモデルを選択します")

            if viewModel.canDownloadSelectedModel {
                Button {
                    viewModel.downloadSelectedModel()
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .disabled(viewModel.isBusy)
                .help("選択中のモデルをダウンロード")
                .accessibilityLabel("モデルをダウンロード")
                .accessibilityHint("選択中の文字起こしモデルをダウンロードします")
            }

            Picker("言語", selection: $settings.selectedLanguageID) {
                ForEach(settings.languages) { language in
                    Text(language.displayName).tag(language.id)
                }
            }
            .frame(width: 140)
            .disabled(viewModel.isBusy)
            .accessibilityLabel("文字起こし言語")
            .accessibilityHint("音声の言語を選択します")

            Spacer()

            Button("Start") {
                viewModel.startTranscription()
            }
            .disabled(!viewModel.canStartTranscription)
            .keyboardShortcut(.return, modifiers: [.command])
            .accessibilityLabel("文字起こしを開始")
            .accessibilityHint("選択した音声ファイルの文字起こしを開始します")

            Menu("Export") {
                ForEach(ExportFormat.allCases) { format in
                    Button(format.displayName) {
                        viewModel.exportTranscript(format: format)
                    }
                }
            }
            .disabled(!viewModel.canExport)
            .accessibilityLabel("文字起こし結果をエクスポート")
            .accessibilityHint("テキスト、SRT、VTT などの形式で書き出します")
        }
    }

    private func modelIcon(for model: ModelOption) -> String {
        viewModel.isModelDownloaded(model) ? "checkmark.circle" : "arrow.down.circle"
    }
}
