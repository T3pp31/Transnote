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
            "エラー",
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

    private var inputSection: some View {
        VStack(spacing: 16) {
            toolbar
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
            HStack(spacing: 6) {
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

                if viewModel.canDownloadSelectedModel {
                    Button {
                        viewModel.downloadSelectedModel()
                    } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.isBusy)
                    .help("選択中のモデルをダウンロード")
                    .accessibilityLabel("モデルをダウンロード")
                    .accessibilityHint("選択中の文字起こしモデルをダウンロードします")
                }
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
